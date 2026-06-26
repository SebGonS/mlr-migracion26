-- ═══════════════════════════════════════════════════════════════
-- PATCH: Mark pre-cuadre lavado_maquinas as COMPLETADO
--        and post retroactive paired consumption movements.
--
-- Problem: Lavados were physically executed but not registered in the
-- system before the last cuadre ran.  The cuadre absorbed the insumo
-- deficit via AJUSTE_NEG.  We need to:
--   1. Mark the lavados COMPLETADO (state + timestamps).
--   2. Post consumption traceability: for each insumo, a paired
--      AJUSTE_POS ingress (offsets the cuadre's AJUSTE_NEG) and a
--      PROD_CONSUMO/LAVADO_MAQUINA egress tied to the lavado.
--
-- Net stock / valuation effect: ZERO.
--   • AJUSTE_POS ingress  +qty @ MAP → item_saldo +qty, item_valoracion +qty*MAP
--   • PROD_CONSUMO egress −qty @ MAP → item_saldo −qty, item_valoracion −qty*MAP
--   Both movements share the same doc_movimiento_id and are backdated to
--   1 second before the cuadre's fecha_cierre.
--
-- Run inside a transaction.  Review SELECT output, then COMMIT or ROLLBACK.
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ─── STEP 0: install helper functions ───────────────────────────

-- mes.completar_lavado_retroactivo(lavado_id, cuadre_id)
-- Marks one lavado COMPLETADO and posts paired inventory movements.
CREATE OR REPLACE FUNCTION mes.completar_lavado_retroactivo(
    p_lavado_id BIGINT,
    p_cuadre_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta'
AS $$
DECLARE
    v_usr_id       INT   := get_user_id();
    v_lavado       mes.lavado_maquina%ROWTYPE;
    v_cuadre       inventario.cuadre%ROWTYPE;
    v_insumos      JSONB;
    v_egr_tipo_id  SMALLINT;
    v_ing_tipo_id  SMALLINT;
    v_motivo_id    SMALLINT;
    v_doc_mov_id   BIGINT;
    v_ubicacion_id INT;
    v_fyh_ts       TIMESTAMPTZ;
    v_rec          RECORD;
    v_lote_id      INT;
BEGIN
    IF NOT jwt_has_permission('produccion.administrar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.administrar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_lavado FROM mes.lavado_maquina WHERE id = p_lavado_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'lavado_maquina id=% no encontrado.', p_lavado_id;
    END IF;
    IF v_lavado.estado NOT IN ('PENDIENTE', 'EN_PROCESO') THEN
        RAISE EXCEPTION 'lavado_maquina id=% estado=%: solo PENDIENTE/EN_PROCESO aceptado.',
            p_lavado_id, v_lavado.estado;
    END IF;

    SELECT * INTO v_cuadre FROM inventario.cuadre WHERE id = p_cuadre_id;
    IF NOT FOUND OR v_cuadre.estado <> 'ejecutado' THEN
        RAISE EXCEPTION 'cuadre id=% no encontrado o no está en estado ejecutado.', p_cuadre_id;
    END IF;

    IF v_lavado.fyh_cre >= v_cuadre.fecha_cierre THEN
        RAISE EXCEPTION 'lavado_maquina id=% fue creado después del cierre del cuadre id=% — no aplica.',
            p_lavado_id, p_cuadre_id;
    END IF;

    -- Estimate timestamp from ordinal position in the day's schedule.
    -- Strategy: find the completed partida_paso runs scheduled on the same
    -- machine/date, bracket the lavado by secuencia, then interpolate:
    --   • both neighbours known  → midpoint between prev.fyh_fin and next.fyh_inicio
    --   • only prev known        → prev.fyh_fin + 30 min
    --   • only next known        → next.fyh_inicio - 30 min
    --   • no neighbours at all   → noon on the scheduled date
    --   • no programacion row    → day before cuadre snapshot at noon (last resort)
    -- NOTE: caller must disable trg_bi_item_movimientos_corte_cuadre first —
    -- the cutoff trigger blocks fecha_hora < MAX(fecha_cuadre).
    WITH lav_prog AS (
        -- Most recent schedule entry (lavado may have been rescheduled across dates)
        SELECT p.maquina_id, p.fecha, p.secuencia
        FROM mes.programacion p
        WHERE p.actividad_tipo = 'LAVADO_MAQUINA'
          AND p.actividad_id   = p_lavado_id
        ORDER BY p.fecha DESC
        LIMIT 1
    ),
    paso_runs AS (
        -- completed ejecucion timestamps for partida_pasos on the same machine/date
        SELECT
            pr.secuencia,
            MAX(ppe.fyh_fin)    AS fyh_fin,
            MIN(ppe.fyh_inicio) AS fyh_inicio
        FROM mes.programacion pr
        JOIN mes.partida_paso_ejecucion ppe
               ON ppe.partida_paso_id = pr.actividad_id
        WHERE pr.actividad_tipo = 'partida_paso'
          AND pr.maquina_id     = (SELECT maquina_id FROM lav_prog)
          AND pr.fecha          = (SELECT fecha       FROM lav_prog)
          AND ppe.fyh_fin IS NOT NULL
        GROUP BY pr.secuencia
    ),
    bracket AS (
        SELECT
            (SELECT MAX(fyh_fin)    FROM paso_runs r, lav_prog lp WHERE r.secuencia < lp.secuencia) AS prev_end,
            (SELECT MIN(fyh_inicio) FROM paso_runs r, lav_prog lp WHERE r.secuencia > lp.secuencia) AS next_start,
            (SELECT fecha FROM lav_prog) AS sched_date
    )
    SELECT COALESCE(
        CASE
            -- Normal bracket: prev finished before next started → midpoint
            WHEN prev_end IS NOT NULL AND next_start IS NOT NULL
                 AND prev_end < next_start
                THEN prev_end + (next_start - prev_end) / 2
            -- Inverted bracket: secuencia order doesn't match wall-clock order
            -- (step rescheduled after execution). Anchor just before next_start.
            WHEN prev_end IS NOT NULL AND next_start IS NOT NULL
                 AND prev_end >= next_start
                THEN next_start - INTERVAL '30 minutes'
            WHEN prev_end IS NOT NULL
                THEN prev_end   + INTERVAL '30 minutes'
            WHEN next_start IS NOT NULL
                THEN next_start - INTERVAL '30 minutes'
            ELSE (sched_date + TIME '12:00:00')::TIMESTAMPTZ
        END
    )
    INTO v_fyh_ts
    FROM bracket;

    IF v_fyh_ts IS NULL THEN
        -- No programacion row at all — fall back to day before cuadre snapshot
        v_fyh_ts := (v_cuadre.fecha_cuadre::DATE - 1 + TIME '12:00:00')::TIMESTAMPTZ;
    END IF;

    -- Aggregate recipe insumos (identical logic to finalizar_lavado_maquina)
    SELECT jsonb_agg(jsonb_build_object('item_id', item_id, 'cantidad', cantidad))
    INTO v_insumos
    FROM (
        SELECT lmpi.item_id, SUM(lmpi.cantidad) AS cantidad
        FROM receta.lavado_maquina_paso lmp
        JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id = lmp.id
        WHERE lmp.receta_id = v_lavado.receta_id
        GROUP BY lmpi.item_id
    ) agg;

    IF v_insumos IS NOT NULL THEN
        SELECT id INTO v_egr_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';
        SELECT id INTO v_ing_tipo_id  FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS';
        SELECT id INTO v_motivo_id
            FROM inventario.item_movimiento_motivo
            WHERE item_movimiento_tipo_id = v_egr_tipo_id AND codigo = 'LAVADO_MAQUINA';

        -- Default insumo storage location
        SELECT u.id INTO v_ubicacion_id
        FROM inventario.ubicacion u
        JOIN inventario.almacen a ON a.id = u.almacen_id
        WHERE a.codigo = 'ALM_INS'
        LIMIT 1;

        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

        FOR v_rec IN
            SELECT
                (i->>'item_id')::INT        AS item_id,
                (i->>'cantidad')::NUMERIC   AS cantidad,
                COALESCE(iv.precio_promedio, 0) AS precio
            FROM jsonb_array_elements(v_insumos) i
            LEFT JOIN inventario.item_valoracion iv
                   ON iv.item_id = (i->>'item_id')::INT
        LOOP
            -- Phantom lote: enters and exits in the same operation.
            -- Linked to the cuadre so its origin is traceable.
            INSERT INTO inventario.lote (
                item_id, documento_tipo, documento_id, cantidad, fyh_cre
            ) VALUES (
                v_rec.item_id, 'cuadre', p_cuadre_id::INT, v_rec.cantidad, v_fyh_ts
            )
            RETURNING id INTO v_lote_id;

            -- AJUSTE_POS: credits back what the cuadre's AJUSTE_NEG absorbed
            -- for this lavado's consumption.  Net stock effect = 0 after the
            -- PROD_CONSUMO below.
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                destino_ubicacion_id,
                cantidad, precio_unitario,
                documento_tipo, documento_id,
                observacion, fecha_hora, fyh_cre
            ) VALUES (
                v_doc_mov_id,
                v_rec.item_id, v_lote_id, v_ing_tipo_id,
                v_ubicacion_id,
                v_rec.cantidad, v_rec.precio,
                'cuadre', p_cuadre_id::INT,
                'Corrección retroactiva lavado_maquina id=' || p_lavado_id
                    || ': devuelve lo absorbido por cuadre id=' || p_cuadre_id,
                v_fyh_ts, v_fyh_ts
            );

            -- PROD_CONSUMO: the actual consumption tied to this lavado for traceability.
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                origen_ubicacion_id,
                cantidad, precio_unitario,
                documento_tipo, documento_id, motivo_id,
                observacion, fecha_hora, fyh_cre
            ) VALUES (
                v_doc_mov_id,
                v_rec.item_id, v_lote_id, v_egr_tipo_id,
                v_ubicacion_id,
                v_rec.cantidad, v_rec.precio,
                'lavado_maquina', p_lavado_id::INT, v_motivo_id,
                'Corrección retroactiva: consumo real, cuadre id=' || p_cuadre_id
                    || ' había absorbido el déficit.',
                v_fyh_ts, v_fyh_ts
            );
        END LOOP;
    END IF;

    -- Mark COMPLETADO
    UPDATE mes.lavado_maquina SET
        estado      = 'COMPLETADO',
        fyh_inicio  = COALESCE(fyh_inicio, fyh_cre),
        fyh_fin     = v_fyh_ts,
        fyh_mod     = now()
    WHERE id = p_lavado_id;

    -- Update machine maintenance stamp (same as finalizar_lavado_maquina)
    UPDATE mes.maquina SET
        ultimo_mantenimiento = v_fyh_ts,
        fyh_mod              = now()
    WHERE id = v_lavado.maquina_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mes.completar_lavado_retroactivo(BIGINT, BIGINT) TO authenticated;


-- mes.completar_lavados_pre_cuadre(cuadre_id)
-- Batch wrapper: processes every PENDIENTE/EN_PROCESO lavado that predates
-- the given cuadre's fecha_cierre.  Returns one row per lavado with result.
CREATE OR REPLACE FUNCTION mes.completar_lavados_pre_cuadre(p_cuadre_id BIGINT)
RETURNS TABLE (lavado_id BIGINT, receta_id INT, maquina_id INT, resultado TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta'
AS $$
DECLARE
    v_cuadre inventario.cuadre%ROWTYPE;
    v_lm     mes.lavado_maquina%ROWTYPE;
BEGIN
    SELECT * INTO v_cuadre FROM inventario.cuadre WHERE id = p_cuadre_id;
    IF NOT FOUND OR v_cuadre.estado <> 'ejecutado' THEN
        RAISE EXCEPTION 'cuadre id=% no encontrado o no está ejecutado.', p_cuadre_id;
    END IF;

    FOR v_lm IN
        SELECT lm.*
        FROM mes.lavado_maquina lm
        WHERE lm.estado IN ('PENDIENTE', 'EN_PROCESO')
          AND lm.fyh_cre < v_cuadre.fecha_cierre
        ORDER BY lm.fyh_cre
    LOOP
        BEGIN
            PERFORM mes.completar_lavado_retroactivo(v_lm.id, p_cuadre_id);
            lavado_id  := v_lm.id;
            receta_id  := v_lm.receta_id;
            maquina_id := v_lm.maquina_id;
            resultado  := 'OK';
            RETURN NEXT;
        EXCEPTION WHEN OTHERS THEN
            lavado_id  := v_lm.id;
            receta_id  := v_lm.receta_id;
            maquina_id := v_lm.maquina_id;
            resultado  := SQLERRM;
            RETURN NEXT;
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION mes.completar_lavados_pre_cuadre(BIGINT) TO authenticated;


-- ─── STEP 1: Preview what will be processed ─────────────────────
SELECT
    lm.id,
    lm.estado,
    m.nombre        AS maquina,
    lm.fyh_cre,
    lm.fyh_inicio,
    (
        SELECT jsonb_agg(jsonb_build_object(
            'item_id', agg.item_id,
            'item', agg.nombre,
            'cantidad', agg.cantidad
        ))
        FROM (
            SELECT lmpi.item_id, it.nombre, SUM(lmpi.cantidad) AS cantidad
            FROM receta.lavado_maquina_paso lmp
            JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id = lmp.id
            JOIN item it ON it.id = lmpi.item_id
            WHERE lmp.receta_id = lm.receta_id
            GROUP BY lmpi.item_id, it.nombre
        ) agg
    ) AS insumos_receta
FROM mes.lavado_maquina lm
JOIN mes.maquina m ON m.id = lm.maquina_id
WHERE lm.estado IN ('PENDIENTE', 'EN_PROCESO')
  AND lm.fyh_cre < (
      SELECT fecha_cierre FROM inventario.cuadre
      WHERE estado = 'ejecutado'
      ORDER BY fecha_cierre DESC LIMIT 1
  )
ORDER BY lm.fyh_cre;


-- ─── STEP 2: Bypass cutoff trigger, execute, restore trigger ────
-- The corte-cuadre trigger blocks fecha_hora < MAX(fecha_cuadre).
-- We want pre-snapshot position (fecha_cuadre - 1s), so we must
-- temporarily disable it.  ALTER TABLE is transactional in PG:
-- ROLLBACK restores the trigger automatically.
ALTER TABLE inventario.item_movimientos
    DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

SELECT *
FROM mes.completar_lavados_pre_cuadre(
    (SELECT id FROM inventario.cuadre
     WHERE estado = 'ejecutado'
     ORDER BY fecha_cierre DESC LIMIT 1)
);

-- Re-enable immediately — never leave this disabled at COMMIT.
ALTER TABLE inventario.item_movimientos
    ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;


-- Review the result set above.  Every row should say 'OK'.
--   COMMIT;   ← if all OK (trigger is re-enabled before this point)
--   ROLLBACK; ← to undo everything (trigger stays enabled either way)



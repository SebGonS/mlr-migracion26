-- ═══════════════════════════════════════════════════════════════════════════════
-- BACKFILL: Create TENIDO paso + execution + production output for a partida
--           that already has rolls assigned but is missing the full MES lifecycle.
--
-- WHEN TO USE:
--   partida EXISTS  ✓
--   partida_componente rows (lote_id) exist  ✓
--   mes.partida_paso rows   MISSING  ✓
--   inventario.lote PROD_ING output rows  MISSING  ✓
--
-- WORKFLOW:
--   1. Edit the parameters block (same values in both sections below).
--   2. Run the DRY-RUN block — verify partida, rolls, weights, payload look right.
--   3. Run the EXECUTE block — commits everything.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────────
-- STEP 1 — DRY RUN  (read-only, safe to run any time)
-- ───────────────────────────────────────────────────────────────────────────────
\echo '=== DRY RUN — partida snapshot ==='

WITH params AS (
    SELECT
        5179                                    AS partida_id,
        4                                       AS maquina_id,
        TIMESTAMPTZ '2026-05-21 15:40:00-05'   AS fyh_inicio,
        TIMESTAMPTZ '2026-05-21 19:30:00-05'   AS fyh_fin,
        321.6::NUMERIC                          AS peso_rollos,
        46.5::NUMERIC                           AS peso_rib
)
SELECT
    -- ── Partida ──────────────────────────────────────────────────────────────
    p.id                                        AS partida_id,
    p.estado_produccion,
    p.fyh_cre::date                             AS fecha_creacion,

    -- ── Rolls assigned ───────────────────────────────────────────────────────
    COUNT(pc.lote_id)                           AS rollos_asignados,
    SUM(l.cantidad)                             AS kg_total_asignado,

    -- ── Precondition flags (all must be OK to proceed) ───────────────────────
    CASE WHEN EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id = p.id)
         THEN '⚠ YA EXISTE — abortará' ELSE 'OK — ningún paso' END  AS paso_guard,

    CASE WHEN EXISTS (
             SELECT 1 FROM inventario.lote lout
             JOIN mes.partida_paso_ejecucion pe ON pe.id = lout.documento_id
                                               AND lout.documento_tipo = 'partida_paso_ejecucion'
             JOIN mes.partida_paso pp2 ON pp2.id = pe.partida_paso_id
             WHERE pp2.partida_id = p.id)
         THEN '⚠ YA EXISTE — abortará' ELSE 'OK — sin output lotes' END  AS output_guard,

    -- ── Reference data ───────────────────────────────────────────────────────
    (SELECT id   FROM mes.operacion WHERE codigo = 'TENIDO')        AS tenido_op_id,
    (SELECT ub.id FROM inventario.ubicacion ub
     JOIN inventario.almacen alm ON alm.id = ub.almacen_id
     WHERE alm.codigo = 'ALM_PT' LIMIT 1)                           AS alm_pt_ubicacion_id,
    (SELECT m.nombre FROM mes.maquina m WHERE m.id = params.maquina_id) AS maquina,

    -- ── Backfill timestamps ──────────────────────────────────────────────────
    params.fyh_inicio,
    params.fyh_fin,
    params.fyh_fin - params.fyh_inicio          AS duracion,

    -- ── Weight summary ───────────────────────────────────────────────────────
    params.peso_rollos,
    params.peso_rib,
    params.peso_rollos + params.peso_rib        AS peso_total_salida

FROM params
JOIN mes.partida p ON p.id = params.partida_id
LEFT JOIN mes.partida_componente pc ON pc.partida_id = p.id AND pc.lote_id IS NOT NULL
LEFT JOIN inventario.lote l ON l.id = pc.lote_id
GROUP BY p.id, p.estado_produccion, p.fyh_cre,
         params.maquina_id, params.fyh_inicio, params.fyh_fin,
         params.peso_rollos, params.peso_rib;

\echo '=== DRY RUN — rolls to be consumed (input) ==='

WITH params AS (SELECT 5179 AS partida_id)
SELECT
    l.id                                        AS lote_id,
    l.codigo                                    AS lote_codigo,
    l.cantidad                                  AS kg,
    ird.flg_rib,
    t.nombre                                    AS propietario,
    l.fyh_cre::date                             AS fecha_ingreso,
    CASE WHEN EXISTS (SELECT 1 FROM inventario.pesaje ps WHERE ps.lote_id = l.id)
         THEN 'pesado' ELSE '⚠ SIN PESAJE' END AS pesaje_estado
FROM params
JOIN mes.partida_componente pc ON pc.partida_id = params.partida_id AND pc.lote_id IS NOT NULL
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
LEFT JOIN tercero t ON t.id = l.propietario_id
ORDER BY ird.flg_rib, l.id;

\echo '=== DRY RUN — registrar_produccion payload preview ==='

WITH params AS (
    SELECT
        5179    AS partida_id,
        321.6   AS peso_rollos,
        46.5    AS peso_rib
),
ubicacion AS (
    SELECT ub.id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_PT'
    LIMIT 1
)
SELECT jsonb_pretty(
    jsonb_build_object(
        'ubicacion_id', u.id,
        'peso_rollos',  params.peso_rollos,
        'peso_rib',     params.peso_rib,
        'output', (
            SELECT jsonb_agg(jsonb_build_object('input_lote_id', pc.lote_id))
            FROM mes.partida_componente pc
            WHERE pc.partida_id = params.partida_id AND pc.lote_id IS NOT NULL
        )
    )
) AS payload_preview
FROM params, ubicacion u;


-- ───────────────────────────────────────────────────────────────────────────────
-- STEP 2 — EXECUTE  (writes to DB — review dry-run output first)
-- ───────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    -- ── CONFIGURE THESE ─────────────────────────────────────────────────────
    v_partida_id    BIGINT      := 5179;
    v_maquina_id    INT         := 4;
    v_fyh_inicio    TIMESTAMPTZ := TIMESTAMPTZ '2026-05-21 15:40:00-05';
    v_fyh_fin       TIMESTAMPTZ := TIMESTAMPTZ '2026-05-21 19:30:00-05';
    v_peso_rollos   NUMERIC     := 321.6;   -- NULL = skip, weight stays per-lote
    v_peso_rib      NUMERIC     := 46.5;    -- NULL = skip
    v_usr_admin     INT         := 1;       -- stamped on usr_cre/usr_mod
    -- ────────────────────────────────────────────────────────────────────────

    v_paso_id       BIGINT;
    v_ejecucion_id  BIGINT;
    v_ubicacion_id  INT;
    v_op_tenido_id  SMALLINT;
    v_roll_count    INT;
    v_output_json   JSONB;
    v_payload       JSONB;
    v_result        TEXT;
BEGIN
    -- ── 1. Guards ─────────────────────────────────────────────────────────

    IF NOT EXISTS (SELECT 1 FROM mes.partida WHERE id = v_partida_id) THEN
        RAISE EXCEPTION 'Partida #% no existe.', v_partida_id;
    END IF;

    SELECT COUNT(*) INTO v_roll_count
    FROM mes.partida_componente
    WHERE partida_id = v_partida_id AND lote_id IS NOT NULL;

    IF v_roll_count = 0 THEN
        RAISE EXCEPTION 'Partida #% no tiene rollos asignados en partida_componente.', v_partida_id;
    END IF;

    IF EXISTS (SELECT 1 FROM mes.partida_paso WHERE partida_id = v_partida_id) THEN
        RAISE EXCEPTION 'Partida #% ya tiene paso(s). Abortando para evitar duplicados.', v_partida_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM inventario.lote l
        JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
                                          AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        WHERE pp.partida_id = v_partida_id
    ) THEN
        RAISE EXCEPTION 'Partida #% ya tiene lotes de salida producidos. Abortando.', v_partida_id;
    END IF;

    -- ── 2. Resolve reference data ─────────────────────────────────────────

    SELECT id INTO v_op_tenido_id FROM mes.operacion WHERE codigo = 'TENIDO';
    IF NOT FOUND THEN RAISE EXCEPTION 'Operación TENIDO no encontrada.'; END IF;

    SELECT ub.id INTO v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_PT' LIMIT 1;

    IF v_ubicacion_id IS NULL THEN RAISE EXCEPTION 'Ubicación ALM_PT no encontrada.'; END IF;

    -- ── 3. partida_paso (TENIDO, seq 1) ──────────────────────────────────
    INSERT INTO mes.partida_paso (
        partida_id, secuencia, operacion_id, maquina_planificada_id, usr_cre, fyh_cre
    )
    VALUES (v_partida_id, 1, v_op_tenido_id, v_maquina_id, v_usr_admin, v_fyh_inicio)
    RETURNING id INTO v_paso_id;

    RAISE NOTICE 'partida_paso creado: id=%', v_paso_id;

    -- ── 4. partida_paso_ejecucion (EN_PROCESO) ────────────────────────────
    --    registrar_produccion looks up the run by estado='EN_PROCESO'.
    --    fyh_fin is left NULL here; it gets the backfill value in step 7.
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, cantidad, usr_cre, fyh_cre
    )
    VALUES (v_paso_id, 'EN_PROCESO', v_maquina_id, v_fyh_inicio, v_roll_count, v_usr_admin, v_fyh_inicio)
    RETURNING id INTO v_ejecucion_id;

    RAISE NOTICE 'partida_paso_ejecucion creado: id=% (EN_PROCESO)', v_ejecucion_id;

    -- ── 5. Build payload ──────────────────────────────────────────────────
    SELECT jsonb_agg(jsonb_build_object('input_lote_id', pc.lote_id))
    INTO v_output_json
    FROM mes.partida_componente pc
    WHERE pc.partida_id = v_partida_id AND pc.lote_id IS NOT NULL;

    v_payload := jsonb_build_object('ubicacion_id', v_ubicacion_id, 'output', v_output_json);

    IF v_peso_rollos IS NOT NULL THEN
        v_payload := v_payload || jsonb_build_object('peso_rollos', v_peso_rollos);
    END IF;
    IF v_peso_rib IS NOT NULL THEN
        v_payload := v_payload || jsonb_build_object('peso_rib', v_peso_rib);
    END IF;

    -- ── 6. Register production output ────────────────────────────────────
    --    PROD_CONSUMO egress on input rolls + PROD_ING ingress on output lotes
    --    + partida_detalle.cantidad_producida updated.
    v_result := mes.registrar_produccion(v_ejecucion_id, v_payload);
    RAISE NOTICE 'registrar_produccion: %', v_result;

    -- ── 7. Close the execution ────────────────────────────────────────────
    UPDATE mes.partida_paso_ejecucion
    SET estado  = 'COMPLETADO',
        fyh_fin = v_fyh_fin,
        usr_mod = v_usr_admin,
        fyh_mod = NOW()
    WHERE id = v_ejecucion_id;

    RAISE NOTICE 'Ejecución % → COMPLETADO (fyh_fin=%)', v_ejecucion_id, v_fyh_fin;

    -- ── 8. Partida → TECO ─────────────────────────────────────────────────
    PERFORM mes.actualizar_estado_partida(v_partida_id);

    RAISE NOTICE '──────────────────────────────────────────────────────────';
    RAISE NOTICE 'RESUMEN partida #%:', v_partida_id;
    RAISE NOTICE '  partida_paso id        : %', v_paso_id;
    RAISE NOTICE '  partida_paso_ejecucion : %', v_ejecucion_id;
    RAISE NOTICE '  rollos procesados      : %', v_roll_count;
    RAISE NOTICE '  estado_produccion      : %',
        (SELECT estado_produccion FROM mes.partida WHERE id = v_partida_id);
    RAISE NOTICE '──────────────────────────────────────────────────────────';
END;
$$;

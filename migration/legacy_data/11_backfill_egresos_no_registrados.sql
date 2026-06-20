-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY BACKFILL: egresos de insumos NO registrados (TENIDO + LAVADO_MAQUINA)
--
-- Posts the chemical PROD_CONSUMO egress that operators never registered during
-- the first weeks live, BACKDATED to the run timestamp, and re-syncs the frozen
-- snapshot of any open cuadre so the reconciliation still balances.
--
-- READ FIRST: migration/diagnostics/debug_egresos_no_registrados.sql
--   Run that diagnostic and eyeball the numbers BEFORE running this.
--
-- WHAT THIS DOES
--   1. Builds, into a TEMP table, one egress line per (run, insumo):
--        TENIDO  → generar_receta formula WITH factor_stock, ÷1000 → KG.
--                  (Does NOT read cantidad_reservada — it is mixed-unit post kg-fix.)
--        LAVADO  → SUM(lavado_maquina_paso_insumo.cantidad)  [already kg, no scaling]
--   2. "Brute-force backdating": temporarily disables ONLY the two corte-de-cuadre
--      triggers (trg_*_item_movimientos_corte_cuadre) so movements dated before the
--      cutoff are accepted. The stock (trg_ai_im_sync_cantidad_actual) and MAP
--      (trg_ai_item_movimientos_map) triggers stay ON, so item_saldo / valoracion
--      update normally. (Do NOT use session_replication_role=replica — that would
--      silence the stock+MAP triggers too and leave balances untouched.)
--   3. Posts PROD_CONSUMO movements: non-fungible insumos FIFO-resolved via
--      mes.calcular_fifo (chronological order → sequential depletion), fungible
--      insumos lotless with the same ubicacion fallback registrar_consumo_paso uses.
--      Every movement is stamped observacion='BACKFILL_EGRESO_NO_REGISTRADO'.
--      fecha_hora = run end (COALESCE fyh_fin, fyh_inicio).
--   4. Subtracts every backfilled egress dated BEFORE an open cuadre's fecha_cuadre
--      from that cuadre_detalle.cantidad_sistema (and recomputes stock_valorado),
--      logging each application in inventario.cuadre_backfill_ajuste so re-runs are
--      idempotent.
--
-- ASSUMPTIONS / CAVEATS
--   • Amounts are KG (recipe grams ÷1000), consistent with generar_receta and the
--     NUMERIC(15,7) ledger after patch 28. Run patch 28 BEFORE this script.
--   • Egress amount still includes factor_stock. NOTE: live registrar_consumo_paso
--     posts the display value WITHOUT factor_stock, so for diluted insumos (factor≠1,
--     e.g. item 13) this backfill diverges from live consumption. Deferred per
--     decision to set factor_stock aside; revisit if diluted insumos are in window.
--   • calcular_fifo resolves lots against CURRENT stock. Because these consumptions
--     were never posted, current stock is inflated, so lots usually resolve cleanly;
--     where an item is now short the FIFO falls short — SECTION 3 flags it.
--   • Only OPEN cuadres (borrador/preparado) get their snapshot adjusted. An already
--     'ejecutado' cuadre is left alone (its adjustments were already posted); the
--     backdated egress simply lowers current stock.
--   • Requires ownership of inventario.item_movimientos (ALTER TABLE ... TRIGGER).
--   • SCOPE IS THE DATE WINDOW ONLY. Runs migrated by legacy script
--     08_migrar_ejecuciones_batch.sql also lack chemical egress; this backfill will
--     post egresses for ANY COMPLETADO tenido run in the window. Set win_ini/win_fin
--     to the live go-live period so those backdated legacy runs fall OUTSIDE it.
--     Confirm with SECTION 0 / the diagnostic that the listed runs are real live runs.
--
-- WORKFLOW: run SECTION 0 → SECTION 1 → SECTION 2 → SECTION 3, in order.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- WINDOW — keep identical to the diagnostic. Edit both literals only.
--   win_ini inclusive >=   |   win_fin exclusive <
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0a. Lines that CANNOT be computed (NULL amount) — fix machine relacion_bano first.
WITH params AS (SELECT '2026-01-01'::timestamptz AS win_ini, '2026-04-01'::timestamptz AS win_fin),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO'),
pasos AS (
    SELECT pe.id AS ejecucion_id, pp.id AS paso_id, pp.partida_id, pp.receta_id,
           COALESCE(pe.maquina_id, pp.maquina_planificada_id) AS maquina_id,
           pp.relacion_bano_objetivo
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    CROSS JOIN params pr
    WHERE pe.estado='COMPLETADO' AND pp.receta_id IS NOT NULL
      AND p.estado_produccion <> 'CANCELADA'
      AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
      AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      JOIN egr_tipo et ON et.id=im.item_movimiento_tipo_id
                      JOIN item_insumo_detalle iid ON iid.item_id=im.item_id
                      WHERE im.documento_tipo='partida_paso_ejecucion' AND im.documento_id=pe.id)
)
SELECT s.ejecucion_id, s.partida_id, s.maquina_id,
       COALESCE(s.relacion_bano_objetivo, m.relacion_bano) AS rb,
       '⚠ g/L insumos no calculables: falta relacion_bano' AS problema
FROM pasos s
LEFT JOIN mes.maquina m ON m.id = s.maquina_id
WHERE COALESCE(s.relacion_bano_objetivo, m.relacion_bano) IS NULL
  AND EXISTS (  -- only matters if the recipe has any g/L insumo
      SELECT 1 FROM receta.tenido_paso rtp
      JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id=rtp.id
      JOIN item_insumo_detalle iid ON iid.item_id=rtpi.item_id
      WHERE rtp.receta_id=s.receta_id AND iid.medida='g/L');

-- 0b. Open cuadre snapshots that SECTION 2 will touch
SELECT id AS cuadre_id, estado, almacen_id, fecha_cuadre
FROM inventario.cuadre
WHERE estado IN ('borrador','preparado')
ORDER BY fecha_cuadre DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — POST BACKDATED EGRESS  (run as ONE transaction)
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;

-- 1a. Materialize every egress line to post.
CREATE TEMP TABLE _egresos_backfill (
    documento_tipo TEXT        NOT NULL,
    documento_id   BIGINT      NOT NULL,
    item_id        INT         NOT NULL,
    cantidad       NUMERIC(15,7),   -- kg, 7 dp (= recipe grams ÷ 1000; see patch 28)
    fyh_evento     TIMESTAMPTZ NOT NULL
) ON COMMIT DROP;

-- TENIDO lines
WITH params AS (SELECT '2026-01-01'::timestamptz AS win_ini, '2026-04-01'::timestamptz AS win_fin),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO'),
pasos AS (
    SELECT pe.id AS ejecucion_id, pp.id AS paso_id, pp.partida_id, pp.receta_id,
           COALESCE(pe.maquina_id, pp.maquina_planificada_id) AS maquina_id,
           pp.relacion_bano_objetivo,
           COALESCE(pe.fyh_fin, pe.fyh_inicio) AS fyh_evento
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    CROSS JOIN params pr
    WHERE pe.estado='COMPLETADO' AND pp.receta_id IS NOT NULL
      AND p.estado_produccion <> 'CANCELADA'
      AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
      AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      JOIN egr_tipo et ON et.id=im.item_movimiento_tipo_id
                      JOIN item_insumo_detalle iid ON iid.item_id=im.item_id
                      WHERE im.documento_tipo='partida_paso_ejecucion' AND im.documento_id=pe.id)
),
ctx AS (
    SELECT s.*, pz.peso,
           GREATEST(pz.peso, m.capacidad_min_kg)
               * COALESCE(s.relacion_bano_objetivo, m.relacion_bano) AS volumen
    FROM pasos s
    LEFT JOIN mes.maquina m ON m.id = s.maquina_id
    LEFT JOIN (
        SELECT s2.ejecucion_id, SUM(l.cantidad) AS peso
        FROM pasos s2
        JOIN mes.partida_componente pc ON pc.partida_id=s2.partida_id AND pc.lote_id IS NOT NULL
        JOIN inventario.lote l         ON l.id = pc.lote_id
        GROUP BY s2.ejecucion_id) pz ON pz.ejecucion_id = s.ejecucion_id
)
INSERT INTO _egresos_backfill (documento_tipo, documento_id, item_id, cantidad, fyh_evento)
SELECT 'partida_paso_ejecucion', c.ejecucion_id, rtpi.item_id,
       -- Recompute in KG straight from the recipe formula. We deliberately do NOT
       -- read mes.partida_componente.cantidad_reservada: that column is mixed-unit
       -- (grams for rows written before the kg fix, kg after), so trusting it would
       -- silently post stale grams. ÷1000 converts g/L×L and %×kg×10 (grams) → kg,
       -- matching generar_receta and the NUMERIC(15,7) ledger (patch 28).
       -- factor_stock kept as-is (diluted-insumo concern, deferred — see ASSUMPTIONS).
       ROUND(CASE iid.medida
                 WHEN 'g/L' THEN SUM(rtpi.cantidad) * c.volumen * iid.factor_stock / 1000
                 WHEN '%'   THEN SUM(rtpi.cantidad) * c.peso * 10 * iid.factor_stock / 1000
             END, 7),
       c.fyh_evento
FROM ctx c
JOIN receta.tenido_paso        rtp  ON rtp.receta_id = c.receta_id
JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id  = rtp.id
JOIN item_insumo_detalle       iid  ON iid.item_id   = rtpi.item_id
GROUP BY c.ejecucion_id, rtpi.item_id, iid.medida, iid.factor_stock,
         c.volumen, c.peso, c.fyh_evento;

-- LAVADO_MAQUINA lines (fixed quantities)
WITH params AS (SELECT '2026-01-01'::timestamptz AS win_ini, '2026-04-01'::timestamptz AS win_fin)
INSERT INTO _egresos_backfill (documento_tipo, documento_id, item_id, cantidad, fyh_evento)
SELECT 'lavado_maquina', lm.id, lmpi.item_id,
       SUM(lmpi.cantidad),
       COALESCE(lm.fyh_inicio, lm.fyh_fin)
FROM mes.lavado_maquina lm
CROSS JOIN params pr
JOIN receta.lavado_maquina_paso        lmp  ON lmp.receta_id = lm.receta_id
JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id  = lmp.id
WHERE lm.estado='COMPLETADO'
  AND COALESCE(lm.fyh_inicio, lm.fyh_fin) >= pr.win_ini
  AND COALESCE(lm.fyh_inicio, lm.fyh_fin) <  pr.win_fin
  AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  WHERE im.documento_tipo='lavado_maquina' AND im.documento_id=lm.id)
GROUP BY lm.id, lmpi.item_id, COALESCE(lm.fyh_inicio, lm.fyh_fin);

-- 1b. Drop uncomputable / non-positive lines (flagged in SECTION 0a).
DELETE FROM _egresos_backfill WHERE cantidad IS NULL OR cantidad <= 0;

-- 1c. Brute-force backdating: lift the corte-de-cuadre guard (keep stock + MAP triggers ON).
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

-- 1d. Post the movements, chronologically so FIFO depletes in run order.
DO $$
DECLARE
    r              RECORD;
    v_egr_tipo     SMALLINT;
    v_motivo       SMALLINT;
    v_doc          BIGINT;
    v_consumos_std JSONB;
    v_fifo         JSONB;
BEGIN
    SELECT id INTO v_egr_tipo FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO';

    FOR r IN
        SELECT documento_tipo, documento_id, fyh_evento
        FROM _egresos_backfill
        GROUP BY documento_tipo, documento_id, fyh_evento
        ORDER BY fyh_evento, documento_tipo, documento_id
    LOOP
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc;

        IF r.documento_tipo = 'lavado_maquina' THEN
            SELECT id INTO v_motivo FROM inventario.item_movimiento_motivo
            WHERE item_movimiento_tipo_id = v_egr_tipo AND codigo='LAVADO_MAQUINA';
        ELSE
            v_motivo := NULL;
        END IF;

        -- Non-fungible → FIFO lot resolution against (live) current stock
        SELECT jsonb_agg(jsonb_build_object('item_id', e.item_id, 'cantidad', e.cantidad))
        INTO v_consumos_std
        FROM _egresos_backfill e
        JOIN item it ON it.id = e.item_id
        WHERE e.documento_tipo = r.documento_tipo AND e.documento_id = r.documento_id
          AND it.flg_fungible = false;

        IF v_consumos_std IS NOT NULL THEN
            v_fifo := mes.calcular_fifo(v_consumos_std);
            IF v_fifo IS NOT NULL THEN
                INSERT INTO inventario.item_movimientos(
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, cantidad, precio_unitario, fecha_hora,
                    documento_tipo, documento_id, motivo_id, observacion)
                SELECT v_doc, (c->>'item_id')::INT, (c->>'lote_id')::INT, v_egr_tipo,
                       (c->>'ubicacion_id')::INT, (c->>'cantidad')::NUMERIC,
                       (SELECT precio_promedio FROM inventario.item_valoracion WHERE item_id=(c->>'item_id')::INT),
                       r.fyh_evento, r.documento_tipo, r.documento_id, v_motivo,
                       'BACKFILL_EGRESO_NO_REGISTRADO'
                FROM jsonb_array_elements(v_fifo) c;
            END IF;
        END IF;

        -- Fungible → lotless egress, same ubicacion fallback as registrar_consumo_paso
        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario, fecha_hora,
            documento_tipo, documento_id, motivo_id, observacion)
        SELECT v_doc, e.item_id, NULL, v_egr_tipo,
               COALESCE(
                   (SELECT ubicacion_id FROM inventario.item_saldo
                     WHERE item_id=e.item_id ORDER BY cantidad_actual DESC LIMIT 1),
                   (SELECT im2.origen_ubicacion_id FROM inventario.item_movimientos im2
                     WHERE im2.item_id=e.item_id AND im2.origen_ubicacion_id IS NOT NULL
                     ORDER BY im2.id DESC LIMIT 1),
                   (SELECT ity.ubicacion_default_id FROM item it2
                     JOIN item_tipo ity ON ity.id=it2.item_tipo_id WHERE it2.id=e.item_id)),
               e.cantidad,
               (SELECT precio_promedio FROM inventario.item_valoracion WHERE item_id=e.item_id),
               r.fyh_evento, r.documento_tipo, r.documento_id, v_motivo,
               'BACKFILL_EGRESO_NO_REGISTRADO'
        FROM _egresos_backfill e
        JOIN item it ON it.id = e.item_id
        WHERE e.documento_tipo = r.documento_tipo AND e.documento_id = r.documento_id
          AND it.flg_fungible = true;
    END LOOP;

    RAISE NOTICE 'Backfill egresos: % documentos procesados.',
        (SELECT COUNT(DISTINCT (documento_tipo, documento_id)) FROM _egresos_backfill);
END $$;

-- 1e. Restore the corte-de-cuadre guard.
ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;
ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — RE-SYNC OPEN CUADRE SNAPSHOTS  (idempotent)
-- Every backfilled egress dated before an open cuadre's fecha_cuadre lowers the
-- frozen cantidad_sistema for that item. Applications are logged so re-runs are safe.
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS inventario.cuadre_backfill_ajuste (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cuadre_id          BIGINT NOT NULL REFERENCES inventario.cuadre(id),
    item_movimiento_id BIGINT NOT NULL REFERENCES inventario.item_movimientos(id),
    item_id            INT    NOT NULL,
    cantidad           NUMERIC(14,4) NOT NULL,
    fyh_cre            TIMESTAMPTZ DEFAULT now(),
    UNIQUE (cuadre_id, item_movimiento_id)
);

DO $$
DECLARE
    v_cuadre RECORD;
    v_n      INT;
BEGIN
    FOR v_cuadre IN
        SELECT id, fecha_cuadre FROM inventario.cuadre
        WHERE estado IN ('borrador','preparado')
    LOOP
        WITH nuevos AS (
            SELECT im.id AS mov_id, im.item_id, im.cantidad
            FROM inventario.item_movimientos im
            WHERE im.observacion = 'BACKFILL_EGRESO_NO_REGISTRADO'
              AND im.fecha_hora  < v_cuadre.fecha_cuadre
              AND EXISTS (SELECT 1 FROM inventario.cuadre_detalle cd
                          WHERE cd.cuadre_id = v_cuadre.id AND cd.item_id = im.item_id)
              AND NOT EXISTS (SELECT 1 FROM inventario.cuadre_backfill_ajuste a
                              WHERE a.cuadre_id = v_cuadre.id AND a.item_movimiento_id = im.id)
        ),
        logged AS (
            INSERT INTO inventario.cuadre_backfill_ajuste (cuadre_id, item_movimiento_id, item_id, cantidad)
            SELECT v_cuadre.id, mov_id, item_id, cantidad FROM nuevos
            RETURNING item_id, cantidad
        ),
        agg AS (SELECT item_id, SUM(cantidad) AS delta FROM logged GROUP BY item_id)
        UPDATE inventario.cuadre_detalle cd
        SET cantidad_sistema       = cd.cantidad_sistema - agg.delta,
            stock_valorado_sistema = ROUND((cd.cantidad_sistema - agg.delta)
                                           * COALESCE(cd.precio_promedio_sistema, 0), 4),
            fyh_mod                = now()
        FROM agg
        WHERE cd.cuadre_id = v_cuadre.id AND cd.item_id = agg.item_id;

        GET DIAGNOSTICS v_n = ROW_COUNT;
        RAISE NOTICE 'Cuadre #% (cutoff %): % items de snapshot ajustados.',
            v_cuadre.id, v_cuadre.fecha_cuadre, v_n;
    END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — VERIFY
-- ═══════════════════════════════════════════════════════════════════════════════

-- 3a. Zero-egress runs remaining in the window (should be 0, minus uncomputable 0a rows)
WITH params AS (SELECT '2026-01-01'::timestamptz AS win_ini, '2026-04-01'::timestamptz AS win_fin),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO')
SELECT
    COUNT(*) FILTER (WHERE tipo='tenido') AS tenido_sin_egreso_restantes,
    COUNT(*) FILTER (WHERE tipo='lavado') AS lavado_sin_egreso_restantes
FROM (
    SELECT 'tenido' AS tipo
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id=pe.partida_paso_id
    JOIN mes.partida p ON p.id=pp.partida_id
    CROSS JOIN params pr
    WHERE pe.estado='COMPLETADO' AND pp.receta_id IS NOT NULL AND p.estado_produccion<>'CANCELADA'
      AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
      AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      JOIN egr_tipo et ON et.id=im.item_movimiento_tipo_id
                      JOIN item_insumo_detalle iid ON iid.item_id=im.item_id
                      WHERE im.documento_tipo='partida_paso_ejecucion' AND im.documento_id=pe.id)
    UNION ALL
    SELECT 'lavado'
    FROM mes.lavado_maquina lm
    CROSS JOIN params pr
    WHERE lm.estado='COMPLETADO'
      AND COALESCE(lm.fyh_inicio,lm.fyh_fin) >= pr.win_ini
      AND COALESCE(lm.fyh_inicio,lm.fyh_fin) <  pr.win_fin
      AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      WHERE im.documento_tipo='lavado_maquina' AND im.documento_id=lm.id)
) q;

-- 3b. What was posted
SELECT documento_tipo,
       COUNT(*)                       AS movimientos,
       COUNT(DISTINCT documento_id)   AS documentos,
       ROUND(SUM(cantidad),4)         AS cantidad_total,
       ROUND(SUM(monto),2)            AS valor_total
FROM inventario.item_movimientos
WHERE observacion = 'BACKFILL_EGRESO_NO_REGISTRADO'
GROUP BY documento_tipo;

-- 3c. Cuadre snapshot adjustments applied
SELECT a.cuadre_id, COUNT(*) AS movimientos_aplicados,
       COUNT(DISTINCT a.item_id) AS items, ROUND(SUM(a.cantidad),4) AS cantidad_restada
FROM inventario.cuadre_backfill_ajuste a
GROUP BY a.cuadre_id ORDER BY a.cuadre_id;

-- 3d. Insumos driven negative by the backfill (informational — expected if stock
--     had already been understated). Reads item_saldo directly, since vw_stock_items
--     hides non-positive balances. Investigate large negatives.
SELECT i.id AS item_id, i.codigo, i.nombre, ROUND(SUM(si.cantidad_actual),4) AS stock_actual
FROM inventario.item_saldo si
JOIN item i ON i.id = si.item_id
WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
              WHERE im.item_id = i.id AND im.observacion='BACKFILL_EGRESO_NO_REGISTRADO')
GROUP BY i.id, i.codigo, i.nombre
HAVING SUM(si.cantidad_actual) < 0
ORDER BY SUM(si.cantidad_actual);


-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL (undo this backfill)
--   1. Restore touched cuadre snapshots:
--        UPDATE inventario.cuadre_detalle cd
--        SET cantidad_sistema = cd.cantidad_sistema + s.delta,
--            stock_valorado_sistema = ROUND((cd.cantidad_sistema + s.delta)
--                                          * COALESCE(cd.precio_promedio_sistema,0),4)
--        FROM (SELECT cuadre_id, item_id, SUM(cantidad) delta
--              FROM inventario.cuadre_backfill_ajuste GROUP BY cuadre_id,item_id) s
--        WHERE cd.cuadre_id=s.cuadre_id AND cd.item_id=s.item_id;
--        DELETE FROM inventario.cuadre_backfill_ajuste;
--   2. Remove the movements (stock+MAP triggers reverse the balances automatically):
--        DELETE FROM inventario.item_movimientos
--        WHERE observacion='BACKFILL_EGRESO_NO_REGISTRADO';
--      (If the corte trigger blocks the delete, it only guards INSERT/UPDATE — DELETE
--       is unaffected. Run step 1 before step 2.)
-- ═══════════════════════════════════════════════════════════════════════════════

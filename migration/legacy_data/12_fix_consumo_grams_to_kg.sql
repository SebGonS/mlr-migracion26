-- ═══════════════════════════════════════════════════════════════════════════════
-- DATA FIX: chemical consumption posted in GRAMS → KG  (live go-live data)
--
-- CONTEXT
--   Before the generar_receta unit fix, the frontend sent the recipe field
--   "cantidad_requerida_kg" (actually grams) verbatim to finalizar_paso →
--   registrar_consumo_paso, which stored it as-is. Stock items are kg, so every
--   chemical PROD_CONSUMO that operators registered live is 1000× too large, and
--   that error already cascaded into item_saldo / lote_saldo / item_valoracion.
--
--   This script corrects the already-posted rows. The complementary script
--   11_backfill_egresos_no_registrados.sql handles runs whose chemicals were NEVER
--   posted (it now writes kg). 08_migrar_ejecuciones_batch.sql is unaffected
--   (roll weights, always kg). LAVADO consumption is unaffected (always kg).
--
-- SCOPE (what gets divided by 1000)
--   item_movimientos where:
--     • item_movimiento_tipo = PROD_CONSUMO
--     • documento_tipo = 'partida_paso_ejecucion'        (tenido step consumption)
--     • item ∈ item_insumo_detalle with medida IN ('g/L','%')  (recipe chemicals;
--       this EXCLUDES roll PROD_CONSUMO, which is kg, and any kg-medida insumo)
--   Normal consumption AND matizado both match (both came through the grams path).
--   Rows already in the fix log are skipped (idempotent).
--
-- ASSUMPTIONS
--   • Every matching row came through the grams-scaled recipe path. If any operator
--     ever typed a real kg amount for a g/L/% insumo, that row would be wrongly
--     divided — SECTION 0 lists the rows so you can eyeball before running.
--   • factor_stock is NOT touched here (deferred). The /1000 is a pure unit fix.
--   • Run AFTER patch 28 (columns widened to 15,7) and the generar_receta deploy.
--
-- HOW BALANCES ARE REBUILT (not delta-patched)
--   item_saldo / lote_saldo sync is purely additive (no clamp), so they are rebuilt
--   exactly by re-aggregating signed movements for affected items/lotes.
--   item_valoracion (MAP) clamps with GREATEST(0,…) and resets valorado at qty=0,
--   so it is rebuilt by a chronological REPLAY of fn_trg_actualizar_map per item.
--
--   DECISION — replay order: (fecha_hora, id) = economic chronological order. The
--   live triggers accumulated in insert (id) order, which differs only for backdated
--   rows. Chronological is the correct moving-average basis; switch the ORDER BY in
--   SECTION 2c to (id) if you'd rather reproduce the original insert-order figures.
--
-- WORKFLOW: SECTION 0 (read-only) → 1 → 2 → 3, in order. Whole thing is reversible
--   (see REVERSAL at the bottom).
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0a. Summary: how many rows / how much grams will be corrected
SELECT
    im.documento_tipo,
    COUNT(*)                          AS movimientos,
    COUNT(DISTINCT im.item_id)        AS insumos,
    ROUND(SUM(im.cantidad), 4)        AS total_actual_grams,
    ROUND(SUM(im.cantidad) / 1000, 7) AS total_corregido_kg
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
GROUP BY im.documento_tipo;

-- 0b. Per-row detail (eyeball for any suspiciously small / already-kg values)
SELECT im.id AS mov_id, im.fecha_hora, im.item_id, it.nombre AS insumo, iid.medida,
       im.lote_id, im.origen_ubicacion_id,
       im.cantidad AS cantidad_grams, ROUND(im.cantidad / 1000, 7) AS cantidad_kg,
       im.observacion
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item it             ON it.id  = im.item_id
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
ORDER BY im.fecha_hora, im.id;

-- 0c. Affected items' current valoración (compare against SECTION 3 after the fix)
SELECT iv.item_id, it.nombre, iv.precio_promedio, iv.stock_qty, iv.stock_valorado
FROM inventario.item_valoracion iv
JOIN item it ON it.id = iv.item_id
WHERE iv.item_id IN (
    SELECT DISTINCT im.item_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo = 'PROD_CONSUMO'
    JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
)
ORDER BY iv.item_id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — CORRECT THE MOVEMENTS  (÷1000, logged)
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS inventario.consumo_kg_fix_log (
    item_movimiento_id BIGINT PRIMARY KEY REFERENCES inventario.item_movimientos(id),
    item_id            INT           NOT NULL,
    old_cantidad       NUMERIC(15,7) NOT NULL,
    new_cantidad       NUMERIC(15,7) NOT NULL,
    fyh_cre            TIMESTAMPTZ DEFAULT now()
);

-- These rows are dated in the go-live window, possibly before a cuadre cutoff; the
-- corte guard only blocks UPDATE, so lift it for this transaction. The stock + MAP
-- triggers are AFTER INSERT only and do NOT fire on UPDATE, so balances are rebuilt
-- explicitly in SECTION 2 (do not rely on cascade here).
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

WITH afectados AS (
    SELECT im.id, im.item_id, im.cantidad AS old_cantidad
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo = 'PROD_CONSUMO'
    JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
),
upd AS (
    UPDATE inventario.item_movimientos im
    SET cantidad = ROUND(a.old_cantidad / 1000, 7)   -- monto (generated) recomputes automatically
    FROM afectados a
    WHERE im.id = a.id
    RETURNING im.id, im.item_id, a.old_cantidad, im.cantidad AS new_cantidad
)
INSERT INTO inventario.consumo_kg_fix_log (item_movimiento_id, item_id, old_cantidad, new_cantidad)
SELECT id, item_id, old_cantidad, new_cantidad FROM upd;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — REBUILD BALANCES for affected items  (same transaction)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. item_saldo: re-aggregate signed movements per (item, ubicacion).
--     Matches fn_trg_sync_cantidad_actual (credit destino, debit origen, no clamp).
--     DELETE then INSERT as separate statements (a combined data-modifying CTE
--     would not see its own DELETE and could hit a unique violation).
DELETE FROM inventario.item_saldo
WHERE item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log);

INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
SELECT item_id, ubicacion_id, SUM(qty)
FROM (
    SELECT im.item_id, im.destino_ubicacion_id AS ubicacion_id,  im.cantidad AS qty
    FROM inventario.item_movimientos im
    WHERE im.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
      AND im.destino_ubicacion_id IS NOT NULL
    UNION ALL
    SELECT im.item_id, im.origen_ubicacion_id, -im.cantidad
    FROM inventario.item_movimientos im
    WHERE im.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
      AND im.origen_ubicacion_id IS NOT NULL
) s
GROUP BY item_id, ubicacion_id;

-- 2b. lote_saldo: same rebuild, for lotes touched by any corrected movement.
DELETE FROM inventario.lote_saldo
WHERE lote_id IN (
    SELECT DISTINCT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im.id
    WHERE im.lote_id IS NOT NULL
);

INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT lote_id, ubicacion_id, SUM(qty)
FROM (
    SELECT im.lote_id, im.destino_ubicacion_id AS ubicacion_id,  im.cantidad AS qty
    FROM inventario.item_movimientos im
    WHERE im.destino_ubicacion_id IS NOT NULL
      AND im.lote_id IN (
          SELECT DISTINCT im2.lote_id FROM inventario.item_movimientos im2
          JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im2.id
          WHERE im2.lote_id IS NOT NULL)
    UNION ALL
    SELECT im.lote_id, im.origen_ubicacion_id, -im.cantidad
    FROM inventario.item_movimientos im
    WHERE im.origen_ubicacion_id IS NOT NULL
      AND im.lote_id IN (
          SELECT DISTINCT im2.lote_id FROM inventario.item_movimientos im2
          JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im2.id
          WHERE im2.lote_id IS NOT NULL)
) s
GROUP BY lote_id, ubicacion_id;

-- 2c. item_valoracion: chronological replay of the MAP algorithm per affected item
--     (exact mirror of inventario.fn_trg_actualizar_map).
DO $$
DECLARE
    r_item   RECORD;
    r_mov    RECORD;
    v_valz   boolean;
    v_recalc boolean;
    v_map    numeric(12,4);
    v_qty    numeric(15,7);
    v_val    numeric(16,4);
BEGIN
    FOR r_item IN SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log LOOP
        v_map := 0; v_qty := 0; v_val := 0;

        FOR r_mov IN
            SELECT im.cantidad, im.precio_unitario, im.destino_ubicacion_id,
                   imt.flg_valorizable, imt.flg_recalcula_costo
            FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE im.item_id = r_item.item_id
            ORDER BY im.fecha_hora, im.id          -- ⇦ replay order (see header DECISION)
        LOOP
            IF r_mov.precio_unitario IS NULL THEN CONTINUE; END IF;
            IF NOT r_mov.flg_valorizable        THEN CONTINUE; END IF;

            IF r_mov.destino_ubicacion_id IS NOT NULL THEN
                IF r_mov.flg_recalcula_costo THEN
                    v_val := v_val + (r_mov.cantidad * r_mov.precio_unitario);
                    v_qty := v_qty + r_mov.cantidad;
                    v_map := CASE WHEN v_qty > 0 THEN ROUND(v_val / v_qty, 4) ELSE 0 END;
                ELSE
                    v_val := v_val + (r_mov.cantidad * v_map);
                    v_qty := v_qty + r_mov.cantidad;
                END IF;
            ELSE
                v_val := GREATEST(0, v_val - (r_mov.cantidad * v_map));
                v_qty := GREATEST(0, v_qty - r_mov.cantidad);
                IF v_qty = 0 THEN v_val := 0; END IF;
            END IF;
        END LOOP;

        INSERT INTO inventario.item_valoracion (item_id, precio_promedio, stock_qty, stock_valorado, fyh_mod)
        VALUES (r_item.item_id, v_map, v_qty, v_val, now())
        ON CONFLICT (item_id) DO UPDATE
            SET precio_promedio = EXCLUDED.precio_promedio,
                stock_qty       = EXCLUDED.stock_qty,
                stock_valorado  = EXCLUDED.stock_valorado,
                fyh_mod         = EXCLUDED.fyh_mod;
    END LOOP;

    RAISE NOTICE 'Valoración recomputada para % insumos.',
        (SELECT COUNT(DISTINCT item_id) FROM inventario.consumo_kg_fix_log);
END $$;

COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — VERIFY  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 3a. What was corrected
SELECT COUNT(*) AS movimientos_corregidos,
       COUNT(DISTINCT item_id) AS insumos,
       ROUND(SUM(old_cantidad), 4) AS total_old_grams,
       ROUND(SUM(new_cantidad), 7) AS total_new_kg
FROM inventario.consumo_kg_fix_log;

-- 3b. item_saldo vs independent re-aggregation (should be 0 rows out of sync)
WITH itms AS (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log),
expected AS (
    SELECT item_id, ubicacion_id, SUM(qty) AS cantidad
    FROM (
        SELECT im.item_id, im.destino_ubicacion_id AS ubicacion_id,  im.cantidad AS qty
        FROM inventario.item_movimientos im JOIN itms USING (item_id)
        WHERE im.destino_ubicacion_id IS NOT NULL
        UNION ALL
        SELECT im.item_id, im.origen_ubicacion_id, -im.cantidad
        FROM inventario.item_movimientos im JOIN itms USING (item_id)
        WHERE im.origen_ubicacion_id IS NOT NULL
    ) s GROUP BY item_id, ubicacion_id
)
SELECT e.item_id, e.ubicacion_id, e.cantidad AS esperado, s.cantidad_actual AS real
FROM expected e
LEFT JOIN inventario.item_saldo s
       ON s.item_id = e.item_id AND s.ubicacion_id IS NOT DISTINCT FROM e.ubicacion_id
WHERE ROUND(e.cantidad, 7) <> ROUND(COALESCE(s.cantidad_actual, 0), 7);

-- 3c. Affected items' valoración after the fix (compare to SECTION 0c)
SELECT iv.item_id, it.nombre, iv.precio_promedio, iv.stock_qty, iv.stock_valorado
FROM inventario.item_valoracion iv
JOIN item it ON it.id = iv.item_id
WHERE iv.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
ORDER BY iv.item_id;

-- 3d. Insumos still negative after the fix (investigate — may be genuine shortfalls)
SELECT i.id AS item_id, i.codigo, i.nombre, ROUND(SUM(si.cantidad_actual), 7) AS stock_actual
FROM inventario.item_saldo si
JOIN item i ON i.id = si.item_id
WHERE i.id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
GROUP BY i.id, i.codigo, i.nombre
HAVING SUM(si.cantidad_actual) < 0
ORDER BY SUM(si.cantidad_actual);


-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL (undo this fix)
--   BEGIN;
--   ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;
--   UPDATE inventario.item_movimientos im
--   SET cantidad = f.old_cantidad
--   FROM inventario.consumo_kg_fix_log f
--   WHERE im.id = f.item_movimiento_id;
--   ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;
--   -- then re-run SECTION 2 (2a/2b/2c) to rebuild balances from the restored quantities,
--   -- and finally:  TRUNCATE inventario.consumo_kg_fix_log;  (or DELETE the reverted ids)
--   COMMIT;
--
-- NOTE on open cuadres: if a cuadre (borrador/preparado) was frozen during the
-- go-live window, its cantidad_sistema snapshot captured the inflated stock. This
-- script does NOT touch cuadre snapshots. If SECTION 0b shows rows dated before an
-- open cuadre's fecha_cuadre, re-sync that snapshot the same way 11 SECTION 2 does
-- (add the corrected delta back to cuadre_detalle.cantidad_sistema). Check first:
--   SELECT id, estado, fecha_cuadre FROM inventario.cuadre WHERE estado IN ('borrador','preparado');
-- ═══════════════════════════════════════════════════════════════════════════════

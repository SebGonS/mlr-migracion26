-- Bulk repair for the systemic version of the partida-6223 bug: 3521 dyed
-- output lotes (168 partidas, 2026-06-10 to 2026-07-06) got their PROD_ING
-- movement posted with destino_ubicacion_id NULL, so fn_trg_sync_cantidad_actual
-- never credited lote_saldo/item_saldo — real rolls, zero recorded stock,
-- invisible to vw_stock_lotes and everything built on it.
-- See migration/diagnostics/audit_prod_ing_missing_destino.sql (scope) and
-- audit_prod_ing_missing_destino_downstream.sql (confirmed: all 3521 are
-- "clean" — no later movement assumed stock existed, so a blanket credit is
-- safe; no double-accounting risk).
--
-- Undyed (flg_tenido=false, 33 rows) and non-PROD_ING types (COMPRA_ING, 6 rows)
-- are OUT OF SCOPE for this script — reviewed separately per user decision.
--
-- IMPORTANT (v2): the first version of this script re-derived the "affected"
-- set in steps 2/3 by matching destino_ubicacion_id = ALM_CRU AFTER step 1
-- had already run — but ALM_CRU is also the normal correct destination for
-- every OTHER dyed PROD_ING lote system-wide, so it re-credited ~29,671
-- already-correct lotes on top of their existing balance (33192 vs the
-- expected 3521). That version was rolled back, never committed. This version
-- freezes the affected lote_id set into a temp table BEFORE any UPDATE runs,
-- and every later step joins against that frozen set only.
--
-- Run inside a transaction; check the guard + verify queries before COMMIT.

BEGIN;

-- 0. Guard: ALM_CRU must resolve to exactly one ubicacion, or this whole
--    approach is wrong and needs a real per-lote location instead of a constant.
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM inventario.ubicacion u
    JOIN inventario.almacen a ON a.id = u.almacen_id
    WHERE a.codigo = 'ALM_CRU';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ALM_CRU resolves to % ubicacion(es), expected exactly 1 — abort, patch needs per-lote location instead.', v_count;
    END IF;
END $$;

-- 1. Freeze the affected set NOW, before touching anything. This is the same
--    predicate as the audit (origen NULL AND destino NULL) — nothing else
--    can ever match this after step 2 runs, because this table is a snapshot.
CREATE TEMP TABLE _affected_prod_ing AS
SELECT im.id AS movimiento_id, im.lote_id, l.item_id, l.cantidad
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
JOIN inventario.lote_rollo_detalle lrd   ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
JOIN inventario.lote l                   ON l.id = im.lote_id
WHERE imt.codigo = 'PROD_ING'
  AND im.origen_ubicacion_id IS NULL
  AND im.destino_ubicacion_id IS NULL
  AND l.fyh_elm IS NULL;

-- Sanity check: must equal 3521 (the audited count) before proceeding.
SELECT COUNT(*) AS frozen_affected_count FROM _affected_prod_ing;

-- 2. Backfill destino_ubicacion_id — scoped to the frozen movement_id set only.
UPDATE inventario.item_movimientos im
SET destino_ubicacion_id = (
    SELECT u.id FROM inventario.ubicacion u
    JOIN inventario.almacen a ON a.id = u.almacen_id
    WHERE a.codigo = 'ALM_CRU'
)
WHERE im.id IN (SELECT movimiento_id FROM _affected_prod_ing);

-- 3. Create the missing lote_saldo rows — one per frozen lote, no aggregation
--    needed (lote_id is unique per roll, no ON CONFLICT collision here).
INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT
    a.lote_id,
    (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen al ON al.id = u.almacen_id WHERE al.codigo = 'ALM_CRU'),
    a.cantidad
FROM _affected_prod_ing a
ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
    SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;

-- 4. Mirror into item_saldo — grouped by item_id since many frozen lotes share
--    an item (ON CONFLICT can't touch the same row twice in one statement).
INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
SELECT
    a.item_id,
    (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen al ON al.id = u.almacen_id WHERE al.codigo = 'ALM_CRU'),
    SUM(a.cantidad)
FROM _affected_prod_ing a
GROUP BY a.item_id
ON CONFLICT (item_id, ubicacion_id) DO UPDATE
    SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;

-- 5. Verify — all scoped to the frozen set, so counts must equal frozen_affected_count.
SELECT COUNT(*) AS movimientos_backfilled
FROM inventario.item_movimientos im
JOIN _affected_prod_ing a ON a.movimiento_id = im.id
WHERE im.destino_ubicacion_id = (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen al ON al.id = u.almacen_id WHERE al.codigo = 'ALM_CRU');

SELECT COUNT(*) AS lotes_con_saldo_nuevo
FROM inventario.lote_saldo ls
JOIN _affected_prod_ing a ON a.lote_id = ls.lote_id
WHERE ls.ubicacion_id = (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen al ON al.id = u.almacen_id WHERE al.codigo = 'ALM_CRU');

-- 6. Re-run the original audit predicate globally — should be 0 (no more
--    affected dyed PROD_ING anywhere, not just within our frozen set).
SELECT COUNT(*) AS remaining_affected_global
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
JOIN inventario.lote_rollo_detalle lrd   ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
WHERE imt.codigo = 'PROD_ING'
  AND im.origen_ubicacion_id IS NULL
  AND im.destino_ubicacion_id IS NULL;

-- 7. Spot-check: pick a handful of lotes that were NOT in the affected set but
--    do sit in ALM_CRU, to confirm their balance is untouched (still whatever
--    it was before this script ran — should match their original lote.cantidad
--    minus anything legitimately consumed since, not doubled).
SELECT ls.lote_id, l.cantidad AS lote_cantidad_original, ls.cantidad_actual
FROM inventario.lote_saldo ls
JOIN inventario.lote l ON l.id = ls.lote_id
WHERE ls.ubicacion_id = (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen al ON al.id = u.almacen_id WHERE al.codigo = 'ALM_CRU')
  AND ls.lote_id NOT IN (SELECT lote_id FROM _affected_prod_ing)
ORDER BY ls.lote_id DESC
LIMIT 10;

-- If frozen_affected_count = 3521, movimientos_backfilled = 3521,
-- lotes_con_saldo_nuevo = 3521, remaining_affected_global = 0, and the
-- spot-check in step 7 shows sane (non-doubled) values: COMMIT;
-- Otherwise: ROLLBACK;

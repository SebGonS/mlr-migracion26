-- Repair: partida 6223 (ejecucion 30538) — 21 output rolls (lote 137639-137659)
-- never got a destino_ubicacion_id on their PROD_ING movement (movimiento_id
-- 259058-259078, all fyh_cre 2026-07-06 18:55:26). Root cause: mes.registrar_produccion
-- reads v_ubicacion_id from p_datos->>'ubicacion_id' with no NOT NULL guard
-- (funciones/mes.sql:1606); the caller passed it null/missing for this call.
-- Because inventario.fn_trg_sync_cantidad_actual only credits lote_saldo when
-- destino_ubicacion_id IS NOT NULL, these rolls have real lote rows + a posted
-- movement but zero stock anywhere — invisible to vw_stock_lotes and therefore
-- to doc.vw_despacho_pendiente. See migration/diagnostics/debug_partida_6223_saldo_gap.sql.
--
-- Fix: backfill destino_ubicacion_id = ALM_PT's ubicacion, then insert the
-- lote_saldo/item_saldo rows the trigger would have created had the value
-- been present at insert time. Run inside a transaction; review the SELECT
-- checks before committing.

BEGIN;

-- 0. Resolve ALM_PT's ubicacion_id (one row expected — "the only location in
--    almacen ALM_PT" per user confirmation).
SELECT u.id AS ubicacion_id, u.codigo, a.codigo AS almacen_codigo
FROM inventario.ubicacion u
JOIN inventario.almacen a ON a.id = u.almacen_id
WHERE a.codigo = 'ALM_PT';

-- 1. Backfill the movement rows (they were posted with NULL destino, which is
--    wrong — this is a correction of the original row, not a new reversal,
--    since no stock was ever actually credited/consumed for these).
UPDATE inventario.item_movimientos im
SET destino_ubicacion_id = (
    SELECT u.id FROM inventario.ubicacion u
    JOIN inventario.almacen a ON a.id = u.almacen_id
    WHERE a.codigo = 'ALM_PT'
)
WHERE im.id BETWEEN 259058 AND 259078
  AND im.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING')
  AND im.destino_ubicacion_id IS NULL;

-- 2. Create the lote_saldo rows the trigger should have created (mirrors
--    fn_trg_sync_cantidad_actual's ingress branch, migration/12_triggers_audit.sql:291).
INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT l.id,
       (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen a ON a.id = u.almacen_id WHERE a.codigo = 'ALM_PT'),
       l.cantidad
FROM inventario.lote l
WHERE l.id BETWEEN 137639 AND 137659
ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
    SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;

-- 3. Mirror into item_saldo (same trigger branch credits item_saldo alongside lote_saldo).
--    Grouped by item_id first — several of these rolls share the same item_id,
--    and ON CONFLICT DO UPDATE can't touch the same row twice in one statement.
INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
SELECT l.item_id,
       (SELECT u.id FROM inventario.ubicacion u JOIN inventario.almacen a ON a.id = u.almacen_id WHERE a.codigo = 'ALM_PT'),
       SUM(l.cantidad)
FROM inventario.lote l
WHERE l.id BETWEEN 137639 AND 137659
GROUP BY l.item_id
ON CONFLICT (item_id, ubicacion_id) DO UPDATE
    SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;

-- 4. Verify: partida 6223 should now appear in the dispatch-pending view.
SELECT * FROM doc.vw_despacho_pendiente WHERE partida_id = 6223;

SELECT lote_id, cantidad_actual FROM inventario.lote_saldo
WHERE lote_id BETWEEN 137639 AND 137659;

-- If query 4 looks right: COMMIT;
-- If anything looks wrong:  ROLLBACK;

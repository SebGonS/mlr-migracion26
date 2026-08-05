-- Follow-up to debug_despacho_pendiente_visibility.sql for partida 6223.
-- All 21 output rolls (lote 137639-137659) show cantidad_disponible = NULL in
-- vw_stock_lotes, meaning no row at all in that view — not just zero stock.
-- vw_stock_lotes (migration/08_views.sql:43) requires:
--   1. l.fyh_elm IS NULL         (lote not soft-deleted)
--   2. a row in inventario.lote_saldo for the lote
--   3. SUM(ls.cantidad_actual) > 0
-- This checks each directly against inventario.lote and inventario.lote_saldo.

SELECT
    l.id            AS lote_id,
    l.fyh_elm,
    (l.fyh_elm IS NULL)                    AS ok_not_deleted,
    l.cantidad      AS lote_cantidad,
    ls.cantidad_actual,
    ls.ubicacion_id,
    (ls.lote_id IS NOT NULL)               AS has_saldo_row
FROM inventario.lote l
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
WHERE l.id BETWEEN 137639 AND 137659
ORDER BY l.id;

-- If has_saldo_row is false for these: no lote_saldo record was ever created
-- (the movement that should've inserted/upserted it never ran, or ran against
-- a different lote_id). Check item_movimientos for these lotes to see what
-- movement(s), if any, exist:
SELECT
    im.lote_id, im.id AS movimiento_id, imt.codigo AS tipo,
    im.origen_ubicacion_id, im.destino_ubicacion_id,
    im.cantidad, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id BETWEEN 137639 AND 137659
ORDER BY im.lote_id, im.fyh_cre;


SELECT * FROM inventario.almacen
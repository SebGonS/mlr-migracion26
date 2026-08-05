-- Diagnostic: is item_id=255 (the hilo item ingested via entrega 9874) actually
-- mapped to unidad 'kg', or does it show as 'UN' somewhere in the frontend's data path?
--
-- Hypothesis: CrearPartidaDrawer.tsx computes
--   cantidad: lote.unidad.toUpperCase() === 'UN' ? 1 : (lote.peso ?? lote.cantidad_disponible)
-- and the live error showed cantidad_requerida=1 for every roll of item 255 —
-- meaning lote.unidad resolved to 'UN' for this item in whatever view/query
-- the drawer reads roll data from, even though item.unidad_id should be 'kg'
-- for ROLLO items per project convention.

-- 1. item master — canonical unit
SELECT i.id, i.codigo, i.nombre, i.unidad_id, u.codigo AS unidad_codigo
FROM item i
JOIN unidad u ON u.id = i.unidad_id
WHERE i.id = 255;

-- 2. item_rollo_detalle — confirm it's flagged as a roll item
SELECT ird.item_id, ird.articulo_id, ird.flg_rib
FROM item_rollo_detalle ird
WHERE ird.item_id = 255;

-- 3. Whatever view the drawer actually queries for roll selection —
--    check vw_lotes_rollos_stock (per migration/08_views.sql) for this lote/item,
--    specifically the 'unidad' column it exposes
SELECT lote_id, item_id, item_codigo, unidad, cantidad_disponible, peso
FROM inventario.vw_lotes_rollos_stock
WHERE item_id = 255
LIMIT 5;

-- ============================================================================
-- Check: could the ingress for compra 992 have posted movements referencing
-- the compra directly (documento_tipo='compra') instead of via the entrega?
-- Some legacy/import paths may have used documento_tipo='compra' rather than
-- 'entrega' as the anchor.
-- ============================================================================

-- Any movements at all referencing compra 992 directly?
SELECT im.id, im.item_id, imt.codigo, im.cantidad, im.fecha_hora,
       im.documento_tipo, im.documento_id, im.documento_linea_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'compra' AND im.documento_id = 992;

-- Broader: any movements at all for items 210/212 (JAKOFIX/JAKAZOL) around
-- the compra date (2026-06-25), regardless of documento_tipo, to catch any
-- other anchor pattern (e.g. lote created directly against 'compra')
SELECT im.id, im.item_id, imt.codigo, im.cantidad, im.fecha_hora,
       im.documento_tipo, im.documento_id, im.documento_linea_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id IN (210, 212)
  AND im.fecha_hora BETWEEN '2026-06-20' AND '2026-07-01'
ORDER BY im.fecha_hora;

-- Same check on lote: any lote for these items/dates not anchored to entrega 856?
SELECT l.id, l.item_id, l.cantidad, l.documento_tipo, l.documento_id, l.fyh_cre
FROM inventario.lote l
WHERE l.item_id IN (210, 212)
  AND l.fyh_cre BETWEEN '2026-06-20' AND '2026-07-01'
ORDER BY l.fyh_cre;

-- Does inventario.item_movimientos even allow documento_tipo='compra' as a
-- value anywhere else in the system (to know if this pattern exists at all)?
SELECT DISTINCT documento_tipo, count(*)
FROM inventario.item_movimientos
WHERE documento_tipo ILIKE '%compra%'
GROUP BY documento_tipo;

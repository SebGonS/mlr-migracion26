-- ============================================================================
-- Follow-up investigation: compra 1004 (type A mismatch) + 992, 1000 (type B)
-- ============================================================================

-- ── COMPRA 1004 (type A: cantidad_recibida stale) ────────────────────────────
SELECT c.id AS compra_id, c.tercero_id, c.fyh_cre, c.fyh_elm
FROM doc.compra c WHERE c.id = 1004;

SELECT cd.id, cd.item_id, i.nombre, cd.cantidad AS ordenada, cd.cantidad_recibida, cd.precio_unitario
FROM doc.compra_detalle cd JOIN item i ON i.id = cd.item_id
WHERE cd.compra_id = 1004 ORDER BY cd.id;

SELECT ce.entrega_id, e.serie, e.correlativo, e.fecha_recepcion, e.fyh_elm
FROM doc.compra_entrega ce JOIN doc.entrega e ON e.id = ce.entrega_id
WHERE ce.compra_id = 1004;

SELECT im.id AS mov_id, im.item_id, im.lote_id, imt.codigo AS mov_tipo,
       im.cantidad, im.fecha_hora, im.documento_id, im.documento_linea_id, im.observacion
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'entrega'
  AND im.documento_id IN (SELECT entrega_id FROM doc.compra_entrega WHERE compra_id = 1004)
ORDER BY im.item_id, im.id;

-- ── COMPRA 992 / entrega 856 (type B) ─────────────────────────────────────────
SELECT l.id, l.item_id, l.cantidad, l.documento_tipo, l.documento_id
FROM inventario.lote l WHERE l.documento_tipo='entrega' AND l.documento_id = 856;

SELECT im.id, im.item_id, imt.codigo, im.cantidad, im.documento_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo='entrega' AND im.documento_id = 856;

SELECT ub.id AS ubicacion_id, ub.codigo, alm.codigo AS almacen_codigo
FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id
WHERE alm.codigo = 'ALM_INS';

-- ── COMPRA 1000 / entrega 942 (type B) ────────────────────────────────────────
SELECT l.id, l.item_id, l.cantidad, l.documento_tipo, l.documento_id
FROM inventario.lote l WHERE l.documento_tipo='entrega' AND l.documento_id = 942;

SELECT im.id, im.item_id, imt.codigo, im.cantidad, im.documento_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo='entrega' AND im.documento_id = 942;

SELECT cd.id, cd.item_id, i.nombre, cd.cantidad AS ordenada, cd.cantidad_recibida
FROM doc.compra_detalle cd JOIN item i ON i.id = cd.item_id
WHERE cd.compra_id = 1000;

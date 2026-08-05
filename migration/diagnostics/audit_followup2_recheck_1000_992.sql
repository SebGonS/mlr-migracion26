-- ============================================================================
-- Recheck: compra 1000 shows cantidad_recibida=1000 (matches ordenada) but
-- earlier audit + lote/movement query both came back EMPTY for entrega 942.
-- Need to find out where the 1000kg is actually tracked, if not via entrega 942.
-- ============================================================================

-- Is entrega 942 even linked to compra 1000? (compra_entrega link)
SELECT * FROM doc.compra_entrega WHERE compra_id = 1000;

-- All entregas linked to compra 1000 (maybe more than one, and 942 isn't the
-- one carrying the goods)
SELECT ce.entrega_id, e.serie, e.correlativo, e.fecha_recepcion, e.fyh_elm, et.codigo
FROM doc.compra_entrega ce
JOIN doc.entrega e ON e.id = ce.entrega_id
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE ce.compra_id = 1000;

-- entrega 942 itself — does it even exist / what type is it?
SELECT e.id, e.serie, e.correlativo, e.fecha_recepcion, e.fyh_elm, et.codigo AS tipo
FROM doc.entrega e JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE e.id = 942;

-- entrega_detalle for 942 again, full row
SELECT * FROM doc.entrega_detalle WHERE entrega_id = 942;

-- Item 6 TRITON: any movements anywhere (not just entrega 942) around that date
SELECT im.id, im.item_id, imt.codigo, im.cantidad, im.fecha_hora,
       im.documento_tipo, im.documento_id, im.documento_linea_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 6
  AND im.fecha_hora BETWEEN '2026-06-20' AND '2026-07-01'
ORDER BY im.fecha_hora;

-- ============================================================================
-- COMPRA 992 / entrega 856 — same recheck (was flagged empty, confirm real)
-- ============================================================================
SELECT ce.entrega_id, e.serie, e.correlativo, e.fecha_recepcion, e.fyh_elm, et.codigo
FROM doc.compra_entrega ce
JOIN doc.entrega e ON e.id = ce.entrega_id
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE ce.compra_id = 992;

SELECT cd.id, cd.item_id, i.nombre, cd.cantidad AS ordenada, cd.cantidad_recibida
FROM doc.compra_detalle cd JOIN item i ON i.id = cd.item_id
WHERE cd.compra_id = 992;

SELECT * FROM doc.entrega_detalle WHERE entrega_id = 856;

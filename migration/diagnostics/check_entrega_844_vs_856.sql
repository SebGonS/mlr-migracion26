-- ============================================================================
-- Is entrega 844's COMPRA_ING for item 210 (25kg) actually the SAME physical
-- receipt as entrega 856's line for item 210 (25kg), just posted under a
-- different/earlier guía? Or a coincidentally-equal but separate purchase?
-- ============================================================================

-- What is entrega 844? Which compra (if any) is it linked to?
SELECT e.id, e.serie, e.correlativo, e.fecha_recepcion, e.fyh_elm, et.codigo AS tipo,
       e.tercero_id
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE e.id = 844;

SELECT ce.compra_id, ce.entrega_id
FROM doc.compra_entrega ce WHERE ce.entrega_id = 844;

-- entrega 844's detail lines
SELECT ed.id, ed.entrega_id, ed.item_id, ed.cantidad, ed.linea, ed.compra_detalle_id
FROM doc.entrega_detalle ed WHERE ed.entrega_id = 844;

-- entrega 856's tercero (supplier) — compare to 844's tercero. Same supplier
-- suggests possible duplicate; different supplier means genuinely separate POs.
SELECT e.id, e.tercero_id, t.razon_social
FROM doc.entrega e
LEFT JOIN tercero t ON t.id = e.tercero_id
WHERE e.id IN (844, 856);

-- compra 992's tercero for comparison
SELECT c.id, c.tercero_id, t.razon_social
FROM doc.compra c LEFT JOIN tercero t ON t.id = c.tercero_id
WHERE c.id = 992;

-- Was compra 992 perhaps linked to entrega 844 too (multiple entregas per
-- compra, like the 1000/942+960 case)?
SELECT ce.compra_id, ce.entrega_id
FROM doc.compra_entrega ce WHERE ce.compra_id = 992;

-- The cuadre 33 event — what was it, and did it touch these items right
-- before the 844 COMPRA_ING posted (same day, ~5 hours earlier)?
SELECT * FROM inventario.cuadre WHERE id = 33;

-- Same "Todos los rollos deben estar pesados antes de generar la receta"
-- error, now on partida 6380. Characterize before assuming it's the same
-- root cause as 6353 (unrecorded client return leaving rolls at zero stock).
-- READ ONLY. Run on a fresh connection.

-- 1) Components + soft-delete + pesaje status (same shape as the 6353 check).
SELECT
    pc.lote_id,
    l.fyh_elm            AS lote_soft_deleted_at,
    l.cantidad            AS lote_cantidad,
    l.estado_calidad,
    l.documento_tipo      AS lote_origen_doc_tipo,
    l.documento_id        AS lote_origen_doc_id,
    p.id                  AS pesaje_id,
    p.tipo                AS pesaje_tipo,
    p.peso_real
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.pesaje p ON p.lote_id = pc.lote_id
WHERE pc.partida_id = 6380
ORDER BY l.fyh_elm NULLS FIRST, pc.lote_id;

-- 2) Which of those actually trip the guard (mirrors generar_receta's own check).
SELECT pc.lote_id, l.fyh_elm AS lote_soft_deleted_at
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6380
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);

-- 3) Raw lote_saldo (bypasses the >0 view filter) for the offending lots --
--    is this the same "zero stock, never returned" signature as 6353?
SELECT ls.lote_id, ls.ubicacion_id, ls.cantidad_actual
FROM mes.partida_componente pc
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = pc.lote_id
WHERE pc.partida_id = 6380
ORDER BY pc.lote_id, ls.ubicacion_id;

-- 4) Full movement ledger per lot -- look for a PROD_ING -> SERV_EGR pair
--    with no subsequent return-in movement (the 6353 pattern), vs. rolls
--    that simply never got weighed at all (no SERV_EGR, still on-site).
SELECT pc.lote_id, im.id AS mov_id, imt.codigo AS mov_tipo,
       im.origen_ubicacion_id, im.destino_ubicacion_id,
       im.cantidad, im.documento_tipo, im.documento_id, im.fyh_cre
FROM mes.partida_componente pc
JOIN inventario.item_movimientos im ON im.lote_id = pc.lote_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE pc.partida_id = 6380
ORDER BY pc.lote_id, im.fyh_cre, im.id;

-- 5) If it IS the same pattern, get the dispatch entrega + client for the
--    devolucion call (mirrors the 6353 lookup).
SELECT DISTINCT im.documento_id AS entrega_id, e.tercero_id, t.nombre AS cliente,
       et.codigo AS tipo_codigo
FROM mes.partida_componente pc
JOIN inventario.item_movimientos im ON im.lote_id = pc.lote_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'SERV_EGR'
JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
LEFT JOIN tercero t ON t.id = e.tercero_id
WHERE pc.partida_id = 6380;

-- Diagnostic: why does entrega_id=9874 (ingreso interno) show no stock for partida creation?
-- Run each block and share the output.

-- 1. Entrega header — confirm it exists and check serie/correlativo/tipo
SELECT e.id, e.entrega_tipo_id, et.codigo AS tipo_codigo, e.tercero_id,
       e.serie, e.correlativo, e.fecha_emision, e.usr_cre
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE e.id = 9874;

-- 2. Entrega detalle lines — confirm lote_id populated, ubicacion_id set
SELECT ed.id, ed.entrega_id, ed.linea, ed.lote_id, ed.item_id, ed.cantidad, ed.ubicacion_id, ed.n_rollos
FROM doc.entrega_detalle ed
WHERE ed.entrega_id = 9874
ORDER BY ed.linea;

-- 3. Lotes created for this entrega
SELECT l.id, l.item_id, l.documento_tipo, l.documento_id, l.cantidad,
       l.propietario_id, l.fyh_cre, l.fyh_elm
FROM inventario.lote l
WHERE l.documento_tipo = 'entrega' AND l.documento_id = 9874
ORDER BY l.id;

-- 4. lote_rollo_detalle rows — confirm entrega_id linkage
SELECT lrd.lote_id, lrd.entrega_id, lrd.ancho, lrd.malla, lrd.rendimiento,
       lrd.color_x_cliente_id, lrd.flg_tenido, lrd.flg_antipilling
FROM inventario.lote_rollo_detalle lrd
WHERE lrd.entrega_id = 9874;

-- 5. item_movimientos for this entrega — confirm SERV_ING rows with destino_ubicacion_id set
SELECT im.id, im.doc_movimiento_id, im.item_id, im.lote_id, imt.codigo AS mov_tipo,
       im.origen_ubicacion_id, im.destino_ubicacion_id, im.cantidad,
       im.documento_tipo, im.documento_id, im.fecha_hora
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'entrega' AND im.documento_id = 9874
ORDER BY im.id;

-- 6. lote_saldo for those lotes — this is what vw_stock_lotes reads
SELECT ls.lote_id, ls.ubicacion_id, ls.cantidad_actual
FROM inventario.lote_saldo ls
JOIN inventario.lote l ON l.id = ls.lote_id
WHERE l.documento_tipo = 'entrega' AND l.documento_id = 9874
ORDER BY ls.lote_id;

-- 7. vw_stock_lotes directly — what crear_partida actually checks against
SELECT vsl.lote_id, vsl.item_id, vsl.cantidad_disponible
FROM inventario.vw_stock_lotes vsl
JOIN inventario.lote l ON l.id = vsl.lote_id
WHERE l.documento_tipo = 'entrega' AND l.documento_id = 9874
ORDER BY vsl.lote_id;

-- 8. Sanity: does trg_ai_im_sync_cantidad_actual exist and is it enabled?
SELECT tgname, tgenabled, tgrelid::regclass
FROM pg_trigger
WHERE tgname = 'trg_ai_im_sync_cantidad_actual';

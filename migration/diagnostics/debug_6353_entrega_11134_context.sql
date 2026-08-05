-- Params needed to call doc.registrar_devolucion_cliente for the 14 rolls
-- on partida 6353 that the client returned after service (entrega 11134
-- dispatch), so the return was never recorded and they're invisible to
-- every pesaje-writing function (no lote_saldo row).
--
-- READ ONLY. Run on a fresh connection.

-- 1) entrega 11134 header — tercero_id (client) required to match on the
--    devolucion guard, plus tipo/serie for reference.
SELECT e.id, e.entrega_tipo_id, et.codigo AS tipo_codigo, e.tercero_id,
       t.nombre AS cliente, e.serie, e.correlativo, e.fecha_emision
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
LEFT JOIN tercero t  ON t.id = e.tercero_id
WHERE e.id = 11134;

-- 2) Confirm DEVOLUCION_CLIENTE_SERVICIO entrega_tipo id (should be 8).
SELECT id, codigo, item_movimiento_tipo_id
FROM doc.entrega_tipo
WHERE codigo LIKE 'DEVOLUCION%';

-- 3) Where did these rolls physically leave from (ubicacion 8) -- confirm
--    what that location is, so we know a sane destino_ubicacion_id for
--    the return receipt.
SELECT id, codigo, nombre, almacen_id
FROM inventario.ubicacion
WHERE id = 8;

-- 4) Exact item/lote list + total weight for the devolucion items[] payload.
SELECT pc.lote_id, l.item_id, l.cantidad
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6353
ORDER BY pc.lote_id;

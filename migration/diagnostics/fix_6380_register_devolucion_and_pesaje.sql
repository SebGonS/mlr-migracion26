-- partida 6380: same pattern as 6353 -- 5 output rolls of paso 8414
-- dispatched via entrega 11122, never recorded as returned. Self-contained:
-- derives tercero_id and the roll list instead of hardcoding them.

-- 0) Sanity check before running the write: confirm entrega 11122 is a
--    real dispatch (has a tercero) and see the roll list this will use.
SELECT e.id, e.tercero_id, t.nombre AS cliente, et.codigo
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
LEFT JOIN tercero t ON t.id = e.tercero_id
WHERE e.id = 11122;

SELECT l.id AS lote_id, l.item_id, l.cantidad, lrd.entrega_id AS origen_lote_entrega_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = 6380;
-- origen_lote_entrega_id is the param you'll need for registrar_pesaje_grupo
-- below (the RAW material's original entrega, not the finished-goods
-- dispatch 11122 -- same distinction as 6353's 8396 vs 11134).

-- 1) Register the return (adjust fecha_recepcion / ubicacion_id=8 if the
--    actual return date/location differs).
SELECT doc.registrar_devolucion_cliente(
    jsonb_build_object(
        'entrega_tipo_id', 8,
        'tercero_id', (SELECT tercero_id FROM doc.entrega WHERE id = 11122),
        'fecha_recepcion', null,
        'items', (
            SELECT jsonb_agg(jsonb_build_object(
                'item_id', l.item_id,
                'cantidad', l.cantidad,
                'lote_id', l.id,
                'ubicacion_id', 8
            ))
            FROM mes.partida_componente pc
            JOIN inventario.lote l ON l.id = pc.lote_id
            WHERE pc.partida_id = 6380
        )
    )
);

-- 2) Verify stock is back.
SELECT sa.*
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN mes.partida_componente pc ON pc.lote_id = sa.lote_id
WHERE pc.partida_id = 6380;
-- Expect 5 rows.

-- 3) Weigh them with the real measured total -- fill in item_id/flg_rib/
--    origen_lote_entrega_id from query 0's second result, and the real kg:
-- SELECT inventario.registrar_pesaje_grupo(6380, <origen_lote_entrega_id>, <item_id>, <flg_rib>, <real_total_kg>);

-- 4) Confirm the guard clears.
SELECT pc.lote_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6380
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows.

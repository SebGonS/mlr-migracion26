-- partida 6465: same pattern as 6353/6380 -- 10 output rolls (167200-167209)
-- of partida_paso_ejecucion 8592 dispatched via entrega 10985, never recorded
-- as returned. Self-contained: derives tercero_id and the roll list instead
-- of hardcoding them.

-- 0) Sanity check before running the write: confirm entrega 10985 is a
--    real dispatch (has a tercero) and see the roll list this will use.
SELECT e.id, e.tercero_id, t.nombre AS cliente, et.codigo
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
LEFT JOIN tercero t ON t.id = e.tercero_id
WHERE e.id = 10985;

SELECT l.id AS lote_id, l.item_id, l.cantidad, lrd.entrega_id AS origen_lote_entrega_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = 6465;
-- origen_lote_entrega_id is the param you'll need for registrar_pesaje_grupo
-- below (the RAW material's original entrega, not the finished-goods
-- dispatch 10985 -- same distinction as 6353's 8396 vs 11134).

-- 1) Register the return (adjust fecha_recepcion / ubicacion_id=8 if the
--    actual return date/location differs).
SELECT doc.registrar_devolucion_cliente(
    jsonb_build_object(
        'entrega_tipo_id', 8,
        'tercero_id', (SELECT tercero_id FROM doc.entrega WHERE id = 10985),
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
            WHERE pc.partida_id = 6465
        )
    )
);

-- 2) Verify stock is back.
SELECT sa.*
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN mes.partida_componente pc ON pc.lote_id = sa.lote_id
WHERE pc.partida_id = 6465;
-- Expect 10 rows.

-- 3) Weigh them using the current lote.cantidad total (regular rolls, no rib
--    split needed -- flg_rib=false). origen_lote_entrega_id and item_id are
--    derived rather than hardcoded; errors out if the group isn't uniform.
SELECT inventario.registrar_pesaje_grupo(
    6465,
    (SELECT DISTINCT lrd.entrega_id
     FROM mes.partida_componente pc
     JOIN inventario.lote l ON l.id = pc.lote_id
     LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
     WHERE pc.partida_id = 6465),
    (SELECT DISTINCT l.item_id
     FROM mes.partida_componente pc
     JOIN inventario.lote l ON l.id = pc.lote_id
     WHERE pc.partida_id = 6465),
    false,
    (SELECT SUM(l.cantidad)
     FROM mes.partida_componente pc
     JOIN inventario.lote l ON l.id = pc.lote_id
     WHERE pc.partida_id = 6465)
);

-- 4) Confirm the guard clears.
SELECT pc.lote_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6465
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows.


SELECT * FROM calidad.inspeccion i ORDER BY id dESC
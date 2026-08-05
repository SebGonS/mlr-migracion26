-- partida 6353: the 14 output rolls of paso 8772 were dispatched to
-- client 227 (Yuseft) via entrega 11134 (DESPACHO_CLIENTE) on 2026-05-09,
-- then physically returned by the client for this tenido step -- but the
-- return was never recorded, so the rolls have zero stock/no lote_saldo
-- row and are invisible to every pesaje-writing function.
--
-- Fix: 1) record the return receipt (doc.registrar_devolucion_cliente,
-- DEVOLUCION_CLIENTE_SERVICIO), 2) re-run the weighing call (params were
-- already correct), 3) confirm generar_receta's guard clears.

-- 1) Register the return. Adjust fecha_recepcion to the ACTUAL date the
--    client returned them if known (currently defaults to now()).
--    ubicacion_id=8 (UBI-01) mirrors where they were dispatched from --
--    change if returns land somewhere else physically.
SELECT doc.registrar_devolucion_cliente('{
    "entrega_tipo_id": 8,
    "tercero_id": 227,
    "fecha_recepcion": null,
    "items": [
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169325, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169326, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169327, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169328, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169329, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169330, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169331, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169332, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169333, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169334, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169335, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169336, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169337, "ubicacion_id": 8},
        {"item_id": 272, "cantidad": 22.4850, "lote_id": 169338, "ubicacion_id": 8}
    ]
}'::jsonb);

-- 2) Verify they now show up in stock.
SELECT sa.*
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN mes.partida_componente pc ON pc.lote_id = sa.lote_id
WHERE pc.partida_id = 6353;
-- Expect 14 rows now (was empty before).

-- 3) Now re-run your original (already-correct) weighing call with the
--    REAL measured total weight for the group:
SELECT inventario.registrar_pesaje_grupo(6353, 8396, 272, false, 314.8);

-- 4) Confirm the pesaje guard clears.
SELECT pc.lote_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6353
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows -- generar_receta should now work.



SELECT * FROM inventario.cuadre




SELECT doc.fn_refresh_compra_detalle_qtys(1019);
SELECT id, item_id, cantidad, cantidad_recibida FROM doc.compra_detalle WHERE compra_id = 1019;


SELECT ed.id, ed.entrega_id, ed.item_id, ed.compra_detalle_id
FROM doc.entrega_detalle ed
JOIN doc.compra_entrega ce ON ce.entrega_id = ed.entrega_id
WHERE ce.compra_id = 1019;


UPDATE doc.entrega_detalle ed
SET compra_detalle_id = cd.id
FROM doc.compra_detalle cd
WHERE ed.id IN (216510, 216511)
  AND cd.compra_id = 1019
  AND cd.item_id = ed.item_id;


SELECT id, entrega_id, item_id, compra_detalle_id FROM doc.entrega_detalle WHERE id IN (216510, 216511);

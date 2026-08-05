-- Diagnostic: item 255's unidad is correctly 'kg', and vw_lotes_rollos_stock
-- reports unidad='kg' for OTHER lotes of item 255 (91516-91520, all 21.7275 kg).
-- But lote_id=139028 (from entrega 9874, ingested with no peso_total → 0.1kg
-- sentinel) is the one that produced cantidad_requerida=1 in the partida error.
--
-- Check: does vw_lotes_rollos_stock even return a row for lote 139028? If the
-- view's WHERE/JOIN excludes freshly-ingested unweighed rolls (e.g. filters on
-- an entrega_id condition, an estado_calidad default, or something INGRESO_INTERNO
-- doesn't populate the same way as client entregas), the frontend might fall back
-- to a different/older data source or a stale cached "1" for missing rows.

SELECT lote_id, item_id, item_codigo, unidad, cantidad_disponible, peso, estado_calidad
FROM inventario.vw_lotes_rollos_stock
WHERE lote_id = 139028;

-- Compare: raw lote + lrd + saldo for the same roll (should all show 0.1kg)
SELECT l.id AS lote_id, l.cantidad AS lote_cantidad, l.estado_calidad,
       lrd.entrega_id, lrd.flg_tenido,
       ls.cantidad_actual
FROM inventario.lote l
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
WHERE l.id = 139028;

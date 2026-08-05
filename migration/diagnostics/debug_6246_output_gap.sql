-- Why does 6246 have completed pasos but zero output lotes / zero PROD_ING?
-- READ ONLY.

-- 1) EVERY movement under 6246's ejecuciones, itemized (not just aggregated).
--    Shows exactly what was posted: chemical consumo vs roll consumo vs PROD_ING.
SELECT ppe.id AS ejecucion_id, pp.secuencia, o.codigo AS operacion,
       imt.codigo AS mov_tipo, im.lote_id, im.item_id,
       i.nombre AS item, im.cantidad, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id AND im.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN item i ON i.id = im.item_id
WHERE pp.partida_id = 6246
ORDER BY pp.secuencia, ppe.id, imt.codigo;

-- 2) Any output lote anywhere whose genealogy (origen_lote_id) points at a 6246
--    input roll — catches outputs minted under a different partida/ejecucion.
SELECT l.id AS out_lote_id, l.documento_tipo, l.documento_id,
       l.estado_calidad, l.fyh_elm, lrd.origen_lote_id, lrd.entrega_id
FROM inventario.lote_rollo_detalle lrd
JOIN inventario.lote l ON l.id = lrd.lote_id
WHERE lrd.origen_lote_id BETWEEN 136293 AND 136314
ORDER BY lrd.origen_lote_id;

-- 3) Are the 22 input rolls actually consumed? Look for ANY PROD_CONSUMO on them
--    (roll-level, lote_id set), across the whole ledger, any partida.
SELECT im.lote_id, imt.codigo AS mov_tipo, im.documento_tipo, im.documento_id,
       im.cantidad, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id BETWEEN 136293 AND 136314
ORDER BY im.lote_id, im.fyh_cre;

-- 4) What did the finalize/consumo calls for 6246's pasos actually submit?
--    Pull the logs_api params for this partida's paso ids.
SELECT id, function_name, user_id, called_at,
       jsonb_pretty(params) AS params
FROM logs_api
WHERE function_name IN ('finalizar_paso','registrar_produccion','registrar_consumo_paso','iniciar_paso')
  AND (
        (params->>'p_paso_id')::bigint IN (25497,25498,25499,25500,25501)
     OR (params->>'paso_id')::bigint   IN (25497,25498,25499,25500,25501)
     OR (params->>'ejecucion_id')::bigint IN (10456,10473,30650,30711,30714,30781)
     OR (params->>'p_ejecucion_id')::bigint IN (10456,10473,30650,30711,30714,30781)
  )
ORDER BY called_at;

-- 5) How the reproceso inspection roll (136293) relates: is its REPROCESO
--    inspection tied to ejecucion 30714, which is a SECADO paso (25500)?
--    That means QC was done on an INPUT roll mid-production, not on an output.
SELECT ppe.id AS ejecucion_id, pp.secuencia, o.codigo AS operacion, pp.estado
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE ppe.id = 30714;

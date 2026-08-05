-- ============================================================================
-- Follow-up: 6467 is NOT reversed yet (estado_produccion=PLANIFICADA,
-- fyh_elm NULL) — no anular_reproceso/mover_lotes_reproceso call exists for
-- it. Correction from user: the second partida is 6495, not 6497. READ ONLY.
-- ============================================================================

-- 1) Header for 6495 (correcting the earlier typo of 6497).
SELECT id, EXTRACT(YEAR FROM fyh_cre)::text || '-' || LPAD(numero::text,4,'0') AS codigo,
       partida_origen_id, estado_produccion, estado_comercial, fyh_cre, fyh_elm
FROM mes.partida
WHERE id = 6495;

-- 1b) The crear_reproceso call that created 6495 (if it's a rework at all).
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name = 'crear_reproceso'
  AND called_at BETWEEN (SELECT fyh_cre - interval '5 minutes' FROM mes.partida WHERE id = 6495)
                     AND (SELECT fyh_cre + interval '5 minutes' FROM mes.partida WHERE id = 6495)
ORDER BY called_at;

-- 1c) Any anular_reproceso/mover_lotes_reproceso call already made for 6495.
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name IN ('anular_reproceso','mover_lotes_reproceso')
  AND (params->>'reproceso_id')::bigint = 6495
ORDER BY called_at;

-- 2) 6467's rolls right now — should still be sitting on 6467 itself since it
--    was never reversed.
SELECT pc.partida_id, pc.lote_id, pc.cantidad_reservada, l.estado_calidad, l.cantidad AS peso_kg
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.lote_id IN (172411,172412,172413,172414,172415,172416,172417,172418,172419,172420,
                     173291,173292,173293,173294,173295,173296,173297,173298,173299,173300)
ORDER BY pc.partida_id, pc.lote_id;

-- 3) Has 6467 had any production/movements on these rolls that would make a
--    manual cancel+repoint unsafe?
SELECT im.id, im.lote_id, imt.codigo AS mov_tipo, im.cantidad,
       im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (172411,172412,172413,172414,172415,172416,172417,172418,172419,172420,
                     173291,173292,173293,173294,173295,173296,173297,173298,173299,173300)
ORDER BY im.fyh_cre;

-- 4) 6467's own paso/execution state.
SELECT pp.id, pp.secuencia, pp.operacion_id, pp.estado,
       ppe.id AS ejecucion_id, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6467
ORDER BY pp.secuencia, ppe.id;

-- 5) Any inspeccion (REPROCESO/BAJA verdict) tied to root 6347's pasos for
--    these lotes, to know what estado_calidad to restore them to.
SELECT ci.lote_id, ci.resultado, ci.partida_paso_ejecucion_id, ci.fyh_cre
FROM calidad.inspeccion ci
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE pp.partida_id = 6347
  AND ci.lote_id IN (172411,172412,172413,172414,172415,172416,172417,172418,172419,172420,
                     173291,173292,173293,173294,173295,173296,173297,173298,173299,173300)
ORDER BY ci.lote_id, ci.fyh_cre;

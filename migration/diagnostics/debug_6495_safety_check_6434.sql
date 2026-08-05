-- ============================================================================
-- 6495 was created from 6434 (logs_api id 41596: crear_reproceso
-- partida_id=6434, 12 lotes: 172863-172874). 6495.partida_origen_id=6400,
-- but 6434 != 6400, so 6434 is itself a rework of root 6400 (same bug shape
-- as 6470/6430). 6495 has NOT been reversed yet (PLANIFICADA, fyh_elm NULL)
-- — so we avoid mes.anular_reproceso entirely and do the correct move by
-- hand, straight to 6434.
--
-- READ ONLY. Need: current componente location (Case A vs B), whether these
-- lotes have existing rows on 6434 already, movements/production since
-- 6495 was created, 6434's paso state, and the quality verdict to restore.
-- ============================================================================

-- 1) Where do these lotes sit right now (should be 6495, since not reversed).
SELECT pc.partida_id, pc.lote_id, pc.cantidad_reservada, l.estado_calidad,
       l.cantidad AS peso_kg, l.documento_tipo, l.documento_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874)
ORDER BY pc.partida_id, pc.lote_id;

-- 2) Any existing componente rows on 6434 for these lotes already? (expect 0)
SELECT * FROM mes.partida_componente
WHERE partida_id = 6434
  AND lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874);

-- 3) Movements on these lotes since 6495 was created (2026-07-23 21:05:51).
SELECT im.id, im.lote_id, imt.codigo AS mov_tipo, im.cantidad,
       im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874)
  AND im.fyh_cre > '2026-07-23 21:05:51.502065+00'
ORDER BY im.fyh_cre;

-- 4) 6495's own paso/execution state (confirm nothing started).
SELECT pp.id, pp.secuencia, pp.operacion_id, pp.estado,
       ppe.id AS ejecucion_id, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6495
ORDER BY pp.secuencia, ppe.id;

-- 5) 6434's own paso/execution state (target of the move — confirm it's
--    still open to receive these rolls back).
SELECT pp.id, pp.secuencia, pp.operacion_id, pp.estado,
       ppe.id AS ejecucion_id, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6434
ORDER BY pp.secuencia, ppe.id;

-- 6) Quality verdict to restore: last NON-rework verdict on 6434's own pasos
--    (the true immediate owner) for these lotes, excluding REPROCESO/BAJA.
SELECT ci.lote_id, ci.resultado, ci.partida_paso_ejecucion_id, ci.fyh_cre
FROM calidad.inspeccion ci
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE pp.partida_id = 6434
  AND ci.lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874)
ORDER BY ci.lote_id, ci.fyh_cre;

-- 7) The REPROCESO/BAJA verdict that pulled these lotes into 6495 (the
--    erroneous rework verdict to hard-delete on 6434's pasos, mirroring
--    mover_lotes_reproceso step 3 — but targeted at 6434, not root 6400).
SELECT ci.id, ci.lote_id, ci.resultado, ci.partida_paso_ejecucion_id, ci.fyh_cre
FROM calidad.inspeccion ci
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE pp.partida_id = 6434
  AND ci.lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874)
  AND ci.resultado IN ('REPROCESO','BAJA')
ORDER BY ci.lote_id, ci.fyh_cre;

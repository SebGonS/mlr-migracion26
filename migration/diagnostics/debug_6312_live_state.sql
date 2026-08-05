-- Decide Scenario 1 (6312 untouched -> revert + generate all 22) vs
-- Scenario 2 (6312 already processed its roll -> recover/reassign).
-- READ ONLY. Run on a FRESH connection.

-- 1) 6312 header + pasos: any ejecucion started?
SELECT pp.id AS paso_id, pp.secuencia, o.codigo AS operacion, pp.estado AS paso_estado,
       ppe.id AS ejecucion_id, ppe.estado AS ejec_estado, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6312
ORDER BY pp.secuencia, ppe.id;

-- 2) ANY inventory movement tied to 6312's pasos? (consumo / prod_ing / anything)
SELECT imt.codigo AS mov_tipo, COUNT(*) n, COUNT(DISTINCT im.lote_id) n_lotes,
       SUM(im.cantidad) kg
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.documento_id IN (
      SELECT ppe.id FROM mes.partida_paso pp
      JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
      WHERE pp.partida_id = 6312)
GROUP BY imt.codigo;

-- 3) Any OUTPUT lote minted under 6312 (would mean rework already produced)?
SELECT l.id AS lote_id, l.documento_id AS ejecucion_id, l.cantidad, l.estado_calidad, l.fyh_elm
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE l.documento_tipo = 'partida_paso_ejecucion' AND pp.partida_id = 6312;

-- 4) Current components on 6312 (which roll(s) sit there now).
SELECT pc.lote_id, l.estado_calidad, l.documento_tipo, l.documento_id
FROM mes.partida_componente pc JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312 ORDER BY pc.lote_id;

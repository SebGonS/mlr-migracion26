-- READ ONLY · What ARE the children of 4320's 12 rolls, really? Link by origen_lote_id
-- (not a guessed id range). And what is 4320's rework child partida + its ejecs?

-- §1 · The children found via origen_lote_id → their lote row + FULL movement ledger
SELECT c.lote_id AS child_lote_id, c.origen_lote_id AS raw_parent,
       c.flg_tenido, l.documento_tipo AS child_doc_tipo, l.documento_id AS child_doc_id,
       l.cantidad, l.fyh_cre AS child_created, l.propietario_id,
       im.id AS mov_id, imt.codigo AS mov, imt.factor, im.documento_tipo AS mov_doc_tipo,
       im.documento_id AS mov_doc_id, im.fecha_hora
FROM inventario.lote_rollo_detalle c
JOIN inventario.lote l ON l.id = c.lote_id
LEFT JOIN inventario.item_movimientos im ON im.lote_id = c.lote_id
LEFT JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE c.origen_lote_id BETWEEN 84802 AND 84813
ORDER BY c.lote_id, im.fecha_hora, im.id;

-- §2 · If the child lote sits on a partida_paso_ejecucion, which partida is that?
--      (is it 4320 itself, or 4320's rework child partida?)
SELECT DISTINCT l.documento_id AS ejec_id, pp.partida_id AS child_lands_on_partida,
       p.partida_origen_id, p.estado_produccion, o.codigo AS operacion,
       COUNT(*) AS child_lotes
FROM inventario.lote_rollo_detalle c
JOIN inventario.lote l ON l.id = c.lote_id AND l.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE c.origen_lote_id BETWEEN 84802 AND 84813
GROUP BY 1,2,3,4,5;

-- §3 · 4320's rework child partida — id, when, estado
SELECT id AS rework_child_partida, partida_origen_id, estado_produccion, fyh_cre
FROM mes.partida WHERE partida_origen_id = 4320;

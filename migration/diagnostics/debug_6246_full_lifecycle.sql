-- ============================================================================
-- FULL lifecycle debug of partida 6246 (root) and 6312 (rework child).
-- Expected end state per user:
--   6246: 22 target, 22 input assigned+consumed, 22 OUTPUT rolls produced
--   1 output in rework (6312, QC=REPROCESO); other 21 outputs pending dispatch.
--
-- Question to answer: are the 22 rolls on 6312 INPUT rolls (entrega) or OUTPUT
-- rolls (partida_paso_ejecucion)? Did 6246 actually produce outputs at all?
-- READ ONLY.
-- ============================================================================

-- 1) Both headers -------------------------------------------------------------
SELECT p.id,
       EXTRACT(YEAR FROM p.fyh_cre)::text||'-'||LPAD(p.numero::text,4,'0') AS codigo,
       p.partida_origen_id, p.estado_produccion, p.estado_comercial,
       p.fyh_inicio, p.fyh_fin
FROM mes.partida p WHERE p.id IN (6246,6312) ORDER BY p.id;

-- 2) partida_detalle for both (target vs produced) ---------------------------
SELECT pd.partida_id, pd.item_id, i.nombre,
       pd.cantidad AS target_rolls, pd.cantidad_producida
FROM mes.partida_detalle pd JOIN item i ON i.id = pd.item_id
WHERE pd.partida_id IN (6246,6312) ORDER BY pd.partida_id, pd.item_id;

-- 3) 6246 pasos + ejecuciones: did production actually run? -------------------
SELECT pp.partida_id, pp.id AS paso_id, pp.secuencia, pp.operacion_id,
       o.codigo AS operacion, pp.estado AS paso_estado,
       ppe.id AS ejecucion_id, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6246
ORDER BY pp.secuencia, ppe.id;

-- 4) ALL lotes tied to 6246 — split by role.
--    INPUT rolls  = documento_tipo='entrega' (came in on a guia)
--    OUTPUT rolls = documento_tipo='partida_paso_ejecucion' whose ejecucion
--                   belongs to a 6246 paso.
SELECT 'INPUT (entrega)' AS rol, l.id AS lote_id,
       EXTRACT(YEAR FROM l.fyh_cre)::int%100||'-'||LPAD(l.secuencia::text,5,'0') AS lote_codigo,
       l.item_id, l.cantidad AS peso_kg, l.estado_calidad,
       l.documento_tipo, l.documento_id, l.fyh_elm
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6246 AND l.documento_tipo = 'entrega'
UNION ALL
SELECT 'OUTPUT (produccion)', l.id,
       EXTRACT(YEAR FROM l.fyh_cre)::int%100||'-'||LPAD(l.secuencia::text,5,'0'),
       l.item_id, l.cantidad, l.estado_calidad,
       l.documento_tipo, l.documento_id, l.fyh_elm
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE l.documento_tipo = 'partida_paso_ejecucion' AND pp.partida_id = 6246
ORDER BY 1, 2;

-- 5) Same for 6312 (the rework child) ----------------------------------------
SELECT 'INPUT (entrega)' AS rol, l.id AS lote_id,
       l.estado_calidad, l.documento_tipo, l.documento_id, l.fyh_elm
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312 AND l.documento_tipo = 'entrega'
UNION ALL
SELECT 'OUTPUT (produccion)', l.id, l.estado_calidad,
       l.documento_tipo, l.documento_id, l.fyh_elm
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE l.documento_tipo = 'partida_paso_ejecucion' AND pp.partida_id = 6312
ORDER BY 1,2;

-- 6) Movement ledger for 6246's pasos: PROD_CONSUMO (inputs eaten) and
--    PROD_ING (outputs produced). Confirms "22 consumed, 22 output".
SELECT imt.codigo AS mov_tipo, COUNT(*) AS n_movs,
       COUNT(DISTINCT im.lote_id) AS n_lotes, SUM(im.cantidad) AS kg_total
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.documento_id IN (
      SELECT ppe.id FROM mes.partida_paso pp
      JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
      WHERE pp.partida_id = 6246)
GROUP BY imt.codigo ORDER BY imt.codigo;

-- 7) All inspecciones for the rolls in play (136293..136314) — full history,
--    what verdict, on which ejecucion, and which partida that ejecucion is under.
SELECT ci.lote_id, ci.resultado, ci.partida_paso_ejecucion_id,
       pp.partida_id AS inspeccion_en_partida, ci.observacion, ci.fyh_cre
FROM calidad.inspeccion ci
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
LEFT JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE ci.lote_id BETWEEN 136293 AND 136314
ORDER BY ci.lote_id, ci.fyh_cre;

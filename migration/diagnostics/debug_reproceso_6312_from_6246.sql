-- ============================================================================
-- Diagnostic: reproceso 6312 branched 22 rolls from partida 6246, but only ONE
-- roll was supposed to go. Goal: understand exactly what crear_reproceso did so
-- a safe correction can move the 21 mistaken rolls back to 6246.
--
-- READ ONLY. Nothing here mutates. Run each block, paste the output back.
-- ============================================================================

-- 0) Headers: confirm the family link and current states -----------------------
SELECT p.id,
       EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text,4,'0') AS codigo,
       p.partida_origen_id,
       p.estado_produccion,
       p.estado_comercial,
       p.fyh_cre
FROM mes.partida p
WHERE p.id IN (6246, 6312)
ORDER BY p.id;

-- 1) 6312's partida_detalle (should read cantidad=22 today; we want 1) ---------
SELECT pd.id, pd.partida_id, pd.item_id, i.nombre AS item,
       pd.cantidad AS roll_count_intent, pd.cantidad_producida, pd.unidad_id
FROM mes.partida_detalle pd
JOIN item i ON i.id = pd.item_id
WHERE pd.partida_id = 6312
ORDER BY pd.item_id;

-- 2) All rolls currently attached to 6312 as components (Case A: moved input rolls)
--    This is the primary set to reclassify. estado_calidad was reset to PENDIENTE.
SELECT pc.id AS componente_id,
       pc.lote_id,
       EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text,5,'0') AS lote_codigo,
       l.item_id, l.cantidad AS peso_kg,
       l.estado_calidad,
       l.documento_tipo,      -- 'partida_paso_ejecucion' => this is an OUTPUT re-dye lote (Case B)
       l.documento_id,
       pc.cantidad_reservada,
       pc.fyh_cre AS componente_fyh_cre
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312
ORDER BY pc.lote_id;

-- 3) Count + split by case so we know the correction shape --------------------
SELECT
    COUNT(*)                                                               AS total_rolls_on_6312,
    COUNT(*) FILTER (WHERE l.documento_tipo = 'partida_paso_ejecucion')    AS case_b_output_redye,
    COUNT(*) FILTER (WHERE l.documento_tipo <> 'partida_paso_ejecucion'
                        OR l.documento_tipo IS NULL)                       AS case_a_input_rolls
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312;

-- 4) SAFETY GATE: has 6312 already started producing on these rolls? -----------
--    Any paso started / any movement under 6312's pasos means moving rolls back
--    is NOT a clean data edit — surface it before touching anything.
SELECT pp.id AS partida_paso_id, pp.secuencia, pp.operacion_id, pp.estado AS paso_estado,
       ppe.id AS ejecucion_id, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6312
ORDER BY pp.secuencia, ppe.id;

-- 5) SAFETY GATE: any inventory movements tied to 6312's pasos/ejecuciones? ----
SELECT im.id, im.lote_id, imt.codigo AS mov_tipo, im.cantidad,
       im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.documento_id IN (
      SELECT ppe.id
      FROM mes.partida_paso pp
      JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
      WHERE pp.partida_id = 6312
  )
ORDER BY im.fyh_cre;

-- 6) The historical QC verdict for these rolls (what to restore estado_calidad to)
--    crear_reproceso wiped lote.estado_calidad to PENDIENTE, but calidad.inspeccion
--    preserves the original REPROCESO verdict per lote.
SELECT ins.lote_id,
       ins.resultado,
       ins.partida_paso_ejecucion_id,
       ins.observacion,
       ins.fyh_cre
FROM calidad.inspeccion ins
WHERE ins.lote_id IN (
      SELECT pc.lote_id FROM mes.partida_componente pc WHERE pc.partida_id = 6312
  )
ORDER BY ins.lote_id, ins.fyh_cre;

-- 7a) discover logs_api columns first (its timestamp col is NOT fyh_cre) -------
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'logs_api'
ORDER BY ordinal_position;

-- 7b) logs_api entry for the mistaken crear_reproceso call — shows the exact lote
--    list that was passed, and lets us confirm which single roll was intended.
--    Ordered by id (monotonic) to avoid depending on the timestamp column name.
SELECT id, function_name, user_id, params
FROM logs_api
WHERE function_name = 'crear_reproceso'
  AND (params->>'partida_id')::bigint = 6246
ORDER BY id DESC
LIMIT 5;





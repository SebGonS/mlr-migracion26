-- Prep facts for the 6246 output-generation + 6312 reassign script. READ ONLY.

-- A) 6312 state + does its schedule (mes.programacion) survive the soft-delete?
SELECT id, estado_produccion, fyh_elm, fyh_programacion, partida_origen_id
FROM mes.partida WHERE id = 6312;

SELECT prog.id AS programacion_id, prog.actividad_id, prog.maquina_id,
       prog.fecha, prog.secuencia, prog.nota
FROM mes.programacion prog
WHERE prog.actividad_tipo = 'partida_paso'
  AND prog.actividad_id IN (SELECT id FROM mes.partida_paso WHERE partida_id = 6312);

-- B) 6312's pasos (needed to know which paso the schedule points to, and to
--    reattach the reassigned roll's future rework).
SELECT id AS paso_id, secuencia, operacion_id, estado FROM mes.partida_paso
WHERE partida_id = 6312 ORDER BY secuencia;

-- C) The 22 input rolls now on 6246 — the exact input_lote_id list + weight,
--    and confirm all are components of 6246.
SELECT pc.lote_id, l.cantidad AS peso_kg, l.item_id, l.estado_calidad
FROM mes.partida_componente pc JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6246 AND pc.lote_id BETWEEN 136293 AND 136314
ORDER BY pc.lote_id;

-- D) COMPACTADO ejecucion 30781: current estado (must become EN_PROCESO via
--    anular_produccion; confirm it is the paso's ejecucion and COMPLETADO).
SELECT ppe.id AS ejecucion_id, ppe.estado, pp.id AS paso_id, pp.secuencia,
       o.codigo AS operacion, pp.partida_id
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE ppe.id = 30781;

-- E) A valid ubicacion_id to place output rolls (where the inputs currently sit).
SELECT DISTINCT sa.ubicacion_id
FROM inventario.vw_stock_lotes_ubicacion sa
WHERE sa.lote_id BETWEEN 136293 AND 136314;

-- What is partida_paso 8271 / ejecucion 1860 actually? Which partida, step, operacion.
SELECT
    p.id AS partida_id, p.partida_origen_id, p.estado_produccion AS partida_estado,
    pp.id AS partida_paso_id, pp.secuencia, pp.estado AS paso_estado,
    o.id AS operacion_id, o.codigo AS operacion_codigo, o.nombre AS operacion_nombre,
    ppe.id AS ejecucion_id, ppe.estado AS ejecucion_estado,
    ppe.maquina_id, m.nombre AS maquina_nombre,
    ppe.fyh_inicio, ppe.fyh_fin, ppe.cantidad_rollos, ppe.peso_kg
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.partida p       ON p.id = pp.partida_id
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN mes.maquina m   ON m.id = ppe.maquina_id
WHERE ppe.id = 1860;

-- All pasos of partida 5947, for full context.
SELECT pp.id AS partida_paso_id, pp.secuencia, pp.estado, o.codigo, o.nombre
FROM mes.partida_paso pp
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE pp.partida_id = 5947
ORDER BY pp.secuencia;

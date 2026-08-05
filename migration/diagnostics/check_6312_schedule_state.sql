-- What is 6312's state after the revert soft-deleted it, and is its schedule
-- (mes.programacion) entry still intact? READ ONLY.

-- 1) 6312 header
SELECT id, estado_produccion, fyh_elm, usr_elm,
       fyh_programacion, fyh_inicio, partida_origen_id
FROM mes.partida WHERE id = 6312;

-- 2) 6312's pasos (still there? still hold receta/maquina plan?)
SELECT id AS paso_id, secuencia, operacion_id, estado, receta_id
FROM mes.partida_paso WHERE partida_id = 6312 ORDER BY secuencia;

-- 3) Schedule entries: any mes.programacion pointing at 6312's pasos?
SELECT prog.id AS programacion_id, prog.actividad_tipo, prog.actividad_id,
       prog.maquina_id, prog.fyh_inicio_plan, prog.fyh_fin_plan, prog.estado,
       prog.fyh_elm
FROM mes.programacion prog
WHERE prog.actividad_tipo = 'partida_paso'
  AND prog.actividad_id IN (SELECT id FROM mes.partida_paso WHERE partida_id = 6312);

-- 4) 6312's partida_detalle (revert deleted it — confirm gone)
SELECT * FROM mes.partida_detalle WHERE partida_id = 6312;

-- 5) Where do the 22 rolls live now (sanity)
SELECT pc.partida_id, COUNT(*) FROM mes.partida_componente pc
WHERE pc.lote_id BETWEEN 136293 AND 136314 GROUP BY pc.partida_id;

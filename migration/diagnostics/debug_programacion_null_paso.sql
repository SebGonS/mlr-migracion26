-- ═══════════════════════════════════════════════════════════════
-- BUG: mes.get_programacion_diaria devuelve paso_id NULL para un
-- slot con actividad_tipo='partida_paso' (maquina_id=19, secuencia=5,
-- fecha=2026-07-10). El frontend deriva actividad_id = paso_id al
-- guardar -> null -> viola NOT NULL en mes.programacion.
--
-- Hipótesis: fila huérfana en mes.programacion cuyo actividad_id ya
-- no existe en mes.partida_paso (LEFT JOIN produce pp.id NULL, pero
-- prog.actividad_tipo sigue siendo 'partida_paso').
-- ═══════════════════════════════════════════════════════════════

-- 1) La fila cruda de programacion (sin joins) — ¿qué actividad_id tiene?
SELECT *
FROM mes.programacion
WHERE maquina_id = 19
  AND fecha = '2026-07-10'
  AND secuencia = 5;

-- 2) ¿Existe ese actividad_id en mes.partida_paso?
SELECT prog.id AS programacion_id, prog.actividad_id, pp.id AS partida_paso_id, pp.partida_id, pp.estado
FROM mes.programacion prog
LEFT JOIN mes.partida_paso pp ON pp.id = prog.actividad_id
WHERE prog.maquina_id = 19
  AND prog.fecha = '2026-07-10'
  AND prog.secuencia = 5;

-- 3) Barrido general: ¿hay OTRAS filas huérfanas en mes.programacion
-- (actividad_tipo='partida_paso' apuntando a un partida_paso que ya
-- no existe)? Esto nos dice si es un caso aislado o sistémico.
SELECT prog.*
FROM mes.programacion prog
LEFT JOIN mes.partida_paso pp ON pp.id = prog.actividad_id
WHERE prog.actividad_tipo = 'partida_paso'
  AND pp.id IS NULL;

-- 4) Si el partida_paso fue eliminado, ¿hay rastro en logs_api de qué
-- lo borró y cuándo? (buscar deletes/anulaciones recientes en mes)
SELECT id, function_name, user_id, params, called_at
FROM logs_api
WHERE function_name ILIKE '%partida%' OR function_name ILIKE '%paso%'
ORDER BY called_at DESC
LIMIT 30;


-- ═══════════════════════════════════════════════════════════════
-- ROOT CAUSE (confirmado): mes.actualizar_pasos_partida (funciones/core.sql)
-- borra filas de mes.partida_paso al remover un paso desde el frontend,
-- pero nunca borraba la fila correspondiente en mes.programacion si ese
-- paso estaba agendado en el tablero. Arreglado en el código fuente
-- (cascade delete agregado antes del DELETE de partida_paso).
--
-- 5) Cleanup de huérfanos YA existentes (los creados antes del fix).
-- Descomentar y correr solo después de confirmar con la query 3 arriba
-- que estas son las únicas filas afectadas.
-- ═══════════════════════════════════════════════════════════════
-- DELETE FROM mes.programacion prog
-- WHERE prog.actividad_tipo = 'partida_paso'
--   AND NOT EXISTS (
--       SELECT 1 FROM mes.partida_paso pp WHERE pp.id = prog.actividad_id
--   );


DELETE FROM mes.programacion prog
WHERE prog.actividad_tipo = 'partida_paso'
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_paso pp WHERE pp.id = prog.actividad_id
  );

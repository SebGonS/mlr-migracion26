-- investigate_release_stale_reserva_6135.sql
-- partida_componente_id 124266 (item_id 7, partida 6135, paso 21895) has sat
-- PROGRAMADA/PENDIENTE since 2026-06-15, holding 150 kg reserved indefinitely and
-- blocking other pasos' stock checks for that item. Confirm it's actually
-- abandoned before releasing it — do NOT run the DELETE below without checking
-- section 1 first.

-- 1) Full context on the stalled paso ------------------------------------------
SELECT p.id AS partida_id, p.estado_produccion, p.fyh_cre AS partida_creada,
       pp.id AS paso_id, pp.estado AS paso_estado, pp.operacion_id, pp.receta_id,
       pp.fyh_cre AS paso_creado,
       (SELECT MAX(fecha) FROM mes.programacion
        WHERE actividad_tipo = 'partida_paso' AND actividad_id = pp.id) AS ultima_fecha_programada,
       (SELECT COUNT(*) FROM mes.partida_paso_ejecucion WHERE partida_paso_id = pp.id) AS ejecuciones,
       (SELECT MAX(fyh_inicio) FROM mes.partida_paso_ejecucion WHERE partida_paso_id = pp.id) AS ultima_ejecucion_inicio
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.id = 21895
WHERE p.id = 6135;

-- 2) All partida_componente rows for this partida (rolls + this chemical) ------
SELECT id, item_id, lote_id, partida_paso_id, cantidad_reservada, fyh_cre
FROM mes.partida_componente
WHERE partida_id = 6135
ORDER BY fyh_cre DESC;

-- 3) Any other pasos on this same partida — is production still moving? -------
SELECT pp.id, pp.estado, pp.operacion_id, o.nombre AS operacion, pp.fyh_cre
FROM mes.partida_paso pp
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE pp.partida_id = 6135
ORDER BY pp.secuencia;

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIRMED (2026-07-17): partida 6135 created 2026-06-15, all 5 pasos still
-- PENDIENTE, never scheduled, zero executions in 32 days — genuinely stalled.
-- generar_receta ran once on creation day and left 13 chemical reservations
-- (item_id 6,171,26,217,15,21,2,133,7,13,92,3,104) all equally stale, each
-- capable of blocking a different item's stock check the same way item 7 did.
--
-- Release ALL chemical reservations for this paso (NOT the roll rows above —
-- those are a different reservation type, leave them). This does NOT touch
-- physical stock (nothing was ever consumed) — it only clears the bookkeeping
-- hold, freeing all 13 items back to full availability for other pasos.
DELETE FROM mes.partida_componente
WHERE partida_paso_id = 21895 AND item_id IS NOT NULL;
-- ═══════════════════════════════════════════════════════════════════════════

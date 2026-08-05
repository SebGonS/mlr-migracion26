-- ============================================================================
-- Same bug as 6470 (see debug_6470_reproceso_origin*.sql /
-- fix_6470_repoint_componentes_to_6430.sql): mes.mover_lotes_reproceso always
-- sends reversed rolls back to the flat family ROOT (partida_origen_id),
-- never to the immediate sibling partida they actually came from.
--
-- Need the same treatment for 6467 and 6497. READ ONLY.
-- ============================================================================

-- 0) Headers: current state + declared root for both.
SELECT id,
       EXTRACT(YEAR FROM fyh_cre)::text || '-' || LPAD(numero::text,4,'0') AS codigo,
       partida_origen_id, estado_produccion, estado_comercial, fyh_cre, fyh_elm
FROM mes.partida
WHERE id IN (6467, 6497)
ORDER BY id;

-- 1) The crear_reproceso call that created EACH of them — params->>'partida_id'
--    is the true immediate source (sibling rework or root).
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name = 'crear_reproceso'
  AND called_at BETWEEN (SELECT fyh_cre - interval '5 minutes' FROM mes.partida WHERE id = 6467)
                     AND (SELECT fyh_cre + interval '5 minutes' FROM mes.partida WHERE id = 6467)
ORDER BY called_at;

SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name = 'crear_reproceso'
  AND called_at BETWEEN (SELECT fyh_cre - interval '5 minutes' FROM mes.partida WHERE id = 6497)
                     AND (SELECT fyh_cre + interval '5 minutes' FROM mes.partida WHERE id = 6497)
ORDER BY called_at;

-- 2) The anular_reproceso / mover_lotes_reproceso reversal call for each.
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name IN ('anular_reproceso','mover_lotes_reproceso')
  AND (params->>'reproceso_id')::bigint IN (6467, 6497)
ORDER BY called_at;

-- 3) Current componente rows for whichever partida each family's root is,
--    filtered to fyh_mod matching each reversal's timestamp (from step 2) so
--    we can isolate exactly which lotes just got moved. Run after seeing (0)
--    and (2) to fill in the real root id(s) if different from 6168.
SELECT pc.partida_id, pc.lote_id, pc.cantidad_reservada,
       pc.fyh_mod, l.estado_calidad, l.cantidad AS peso_kg
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id IN (
    SELECT DISTINCT COALESCE(partida_origen_id, id)
    FROM mes.partida WHERE id IN (6467, 6497)
)
ORDER BY pc.fyh_mod DESC NULLS LAST, pc.partida_id, pc.lote_id;

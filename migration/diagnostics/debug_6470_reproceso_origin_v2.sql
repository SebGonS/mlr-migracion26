-- ============================================================================
-- Follow-up to debug_6470_reproceso_origin.sql. Confirmed family:
--   root 6168 -> siblings 6283, 6430, and 6470 (now CANCELADA, fyh_elm set
--   2026-07-24 15:09:02, i.e. fully unwound / zero rolls remaining).
--
-- The first pass's logs_api search came back empty because it looked for a
-- quoted "6470" (JSON strings), but numeric params in JSONB are unquoted.
-- Widening the match here. READ ONLY.
-- ============================================================================

-- 1) ANY logs_api row mentioning 6470 anywhere in params, any function.
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE params::text LIKE '%6470%'
ORDER BY called_at;

-- 2) crear_reproceso calls around 6470's creation time (2026-07-23 15:05:27),
--    to see the exact lote list and the source partida_id passed in.
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name = 'crear_reproceso'
  AND called_at BETWEEN '2026-07-23 14:55:00+00' AND '2026-07-23 15:15:00+00'
ORDER BY called_at;

-- 3) anular_reproceso / mover_lotes_reproceso calls around the reversal time
--    (fyh_elm = 2026-07-24 15:09:02.39939+00).
SELECT id, function_name, user_id, called_at, params
FROM logs_api
WHERE function_name IN ('anular_reproceso','mover_lotes_reproceso')
  AND called_at BETWEEN '2026-07-24 14:55:00+00' AND '2026-07-24 15:20:00+00'
ORDER BY called_at;

-- 4) Sibling partidas' current componente rolls (6168 root, 6283, 6430) —
--    the reversed rolls should show up on 6168 (root) per the bug, mixed in
--    with rolls that always belonged there. peso_kg + fyh_cre on the
--    componente row helps spot which ones were just moved back (fyh_mod
--    around 2026-07-24 15:09).
SELECT pc.partida_id, pc.lote_id, pc.cantidad_reservada,
       pc.fyh_cre AS componente_fyh_cre, pc.fyh_mod AS componente_fyh_mod,
       l.estado_calidad, l.cantidad AS peso_kg
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id IN (6168, 6283, 6430)
ORDER BY pc.fyh_mod DESC NULLS LAST, pc.partida_id, pc.lote_id;

-- Run on a FRESH connection. If unsure, run a bare ROLLBACK; first.
-- Ground-truth check of the committed state after the 6312 correction.

-- 1) Exactly which lotes sit on 6312 right now?  Expect ONE row (136293).
SELECT pc.id AS componente_id, pc.lote_id, l.estado_calidad, pc.fyh_cre, pc.fyh_mod
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312
ORDER BY pc.lote_id;

-- 2) Counts side by side.
SELECT '6312' AS partida, COUNT(*) AS componentes FROM mes.partida_componente WHERE partida_id = 6312
UNION ALL
SELECT '6246', COUNT(*) FROM mes.partida_componente WHERE partida_id = 6246;

-- 3) Am I inside an uncommitted transaction right now?
--    'idle' = no open tx (good).  'idle in transaction' = you have one open.
SELECT pid, state, xact_start, query_start
FROM pg_stat_activity
WHERE pid = pg_backend_pid();

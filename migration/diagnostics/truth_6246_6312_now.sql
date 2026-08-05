-- Plain committed truth. No BEGIN/DO/tx. Run each line, read the numbers.
-- Confirm you are NOT in an open transaction first:
SELECT state FROM pg_stat_activity WHERE pid = pg_backend_pid();  -- want 'active'/'idle', NOT 'idle in transaction'

-- Where does each incident roll live right now, and what QC state?
SELECT pc.partida_id AS lives_on_partida, COUNT(*) AS n
FROM mes.partida_componente pc
WHERE pc.lote_id BETWEEN 136293 AND 136314
GROUP BY pc.partida_id
ORDER BY pc.partida_id;

-- 6312 status
SELECT id, estado_produccion, fyh_elm FROM mes.partida WHERE id = 6312;

-- QC verdicts still on the 22 rolls
SELECT COUNT(*) AS inspecciones_en_inputs
FROM calidad.inspeccion WHERE lote_id BETWEEN 136293 AND 136314;

-- estado_calidad spread
SELECT estado_calidad, COUNT(*) FROM inventario.lote
WHERE id BETWEEN 136293 AND 136314 GROUP BY estado_calidad;

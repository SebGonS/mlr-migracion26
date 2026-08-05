-- Confirm 6290 has a rework child that now holds the reassigned rolls
SELECT id, partida_origen_id, estado_produccion, estado_comercial, fyh_cre
FROM mes.partida
WHERE partida_origen_id = 6290
ORDER BY fyh_cre;

-- Componentes on the rework child(ren)
SELECT pc.partida_id, pc.lote_id, pc.cantidad_reservada
FROM mes.partida_componente pc
WHERE pc.partida_id IN (SELECT id FROM mes.partida WHERE partida_origen_id = 6290);

-- Family-level rollup view, for comparison
SELECT * FROM mes.vw_partida_familia WHERE partida_id = 6290;

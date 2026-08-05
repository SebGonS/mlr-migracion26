-- The correction (rolled back) showed 6312 still had 2 components, not 1.
-- 22 rolls were listed in the diagnostic but the move returned exactly 21, so
-- 6312 held 23 components: 22 from the incident + 1 extra. Identify the extra.
SELECT pc.id AS componente_id,
       pc.lote_id,
       EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text,5,'0') AS lote_codigo,
       l.item_id, l.cantidad AS peso_kg, l.estado_calidad,
       l.documento_tipo, l.documento_id,
       pc.cantidad_reservada, pc.fyh_cre AS componente_fyh_cre,
       (pc.lote_id BETWEEN 136293 AND 136314) AS is_incident_roll
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312
ORDER BY pc.lote_id;

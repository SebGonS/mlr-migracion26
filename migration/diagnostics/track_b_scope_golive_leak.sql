-- READ ONLY · Does any of the 528 in-scope partidas carry POST-go-live activity that
-- the legacy partida.fyh_cre gate misses (like 4320 did)? Such a partida is LIVE and
-- must NOT be backfilled. Checks: post-go-live compactado ejec, post-go-live ejec of
-- any kind, non-terminal estado_produccion, or an existing post-go-live child lote.

WITH tb_roll AS (
    SELECT im.lote_id, im.documento_id AS partida_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
      AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=im.lote_id),0)=0
),
demand AS (SELECT partida_id, COUNT(DISTINCT lote_id) AS raw_shipped FROM tb_roll GROUP BY partida_id),
supply AS (
    SELECT pp.partida_id, SUM(ppe.cantidad_rollos) AS supply_rollos
    FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id GROUP BY pp.partida_id
),
childed_partida AS (
    SELECT DISTINCT tr.partida_id FROM tb_roll tr
    WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id = tr.lote_id)
),
in_scope AS (
    SELECT d.partida_id FROM demand d
    JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
    JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
    WHERE d.partida_id NOT IN (SELECT partida_id FROM childed_partida)
)
SELECT
    -- (1) in-scope partidas whose estado is still active (not TECO/CERRADA/CANCELADA)
    COUNT(*) FILTER (WHERE p.estado_produccion NOT IN ('TECO','CERRADA','CANCELADA'))       AS active_estado,
    -- (2) in-scope partidas with a POST-go-live compactado ejec (would write onto live step)
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
        WHERE pp.partida_id=s.partida_id AND ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz)) AS post_golive_compactado_ejec,
    -- (3) in-scope partidas with ANY post-go-live ejec
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
        WHERE pp.partida_id=s.partida_id AND ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz)) AS post_golive_any_ejec,
    -- (4) in-scope partidas that have a rework CHILD partida (like 4320→6075)
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM mes.partida ch WHERE ch.partida_origen_id = s.partida_id))            AS has_rework_child,
    COUNT(*)                                                                                 AS total_in_scope
FROM in_scope s
JOIN mes.partida p ON p.id = s.partida_id;
-- ALL of (1)(2)(3)(4) should be 0 for a clean legacy-only backfill. Any >0 = leak to inspect.

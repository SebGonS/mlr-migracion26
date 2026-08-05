-- READ ONLY · Compare candidate legacy-activity GATES on the in-scope set, to pick a
-- robust one that doesn't rely on estado_produccion. For each in-scope partida gather
-- timestamp-based activity signals, then show which gate excludes which partidas.
-- go-live = '2026-05-25 15:27:52+00'::timestamptz.

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
in_scope AS (   -- pre-activity-gate scope (528 partidas)
    SELECT d.partida_id, d.raw_shipped FROM demand d
    JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
    JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
    WHERE d.partida_id NOT IN (SELECT partida_id FROM childed_partida)
),
sig AS (
    SELECT s.partida_id, s.raw_shipped,
        p.estado_produccion,
        -- G_ejec: any ejec started post-go-live (STRONG: real live production)
        EXISTS (SELECT 1 FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                WHERE pp.partida_id=s.partida_id AND ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz) AS g_post_golive_ejec,
        -- also by ejec.fyh_cre (created post-go-live even if fyh_inicio null/legacy)
        EXISTS (SELECT 1 FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                WHERE pp.partida_id=s.partida_id AND ppe.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) AS g_post_golive_ejec_cre,
        -- G_lote: any lote on this partida's ejecs created post-go-live
        EXISTS (SELECT 1 FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                JOIN inventario.lote l ON l.documento_tipo='partida_paso_ejecucion' AND l.documento_id=ppe.id
                WHERE pp.partida_id=s.partida_id AND l.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) AS g_post_golive_lote,
        -- G_rework: has a rework child partida created post-go-live
        EXISTS (SELECT 1 FROM mes.partida ch WHERE ch.partida_origen_id=s.partida_id
                AND ch.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) AS g_post_golive_rework_child,
        -- G_estado: the weak status gate (for comparison)
        (p.estado_produccion NOT IN ('TECO','CERRADA','CANCELADA')) AS g_active_estado
    FROM in_scope s JOIN mes.partida p ON p.id=s.partida_id
)
-- §1 · how many partidas each gate would exclude (and combined timestamp-only gate)
SELECT
    COUNT(*)                                                     AS total_in_scope_528,
    COUNT(*) FILTER (WHERE g_post_golive_ejec)                   AS excl_by_ejec_inicio,
    COUNT(*) FILTER (WHERE g_post_golive_ejec_cre)               AS excl_by_ejec_cre,
    COUNT(*) FILTER (WHERE g_post_golive_lote)                   AS excl_by_lote_cre,
    COUNT(*) FILTER (WHERE g_post_golive_rework_child)           AS excl_by_rework_child,
    COUNT(*) FILTER (WHERE g_active_estado)                      AS excl_by_estado_only,
    -- proposed TIMESTAMP-ONLY gate = any post-go-live ejec(inicio|cre) OR lote OR rework child
    COUNT(*) FILTER (WHERE g_post_golive_ejec OR g_post_golive_ejec_cre
                        OR g_post_golive_lote OR g_post_golive_rework_child)  AS excl_by_timestamp_gate,
    -- partidas estado flags as active but timestamp gate says clean (estado false-positive)
    COUNT(*) FILTER (WHERE g_active_estado AND NOT (g_post_golive_ejec OR g_post_golive_ejec_cre
                        OR g_post_golive_lote OR g_post_golive_rework_child)) AS estado_flags_but_no_activity
FROM sig;

-- §2 · dump every partida any gate flags, to eyeball the disagreement (esp. 4595)
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
    SELECT d.partida_id, d.raw_shipped FROM demand d
    JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
    JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
    WHERE d.partida_id NOT IN (SELECT partida_id FROM childed_partida)
)
SELECT s.partida_id, s.raw_shipped, p.estado_produccion,
    (p.estado_produccion NOT IN ('TECO','CERRADA','CANCELADA')) AS active_estado,
    EXISTS (SELECT 1 FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
            WHERE pp.partida_id=s.partida_id AND ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz) AS post_golive_ejec_inicio,
    EXISTS (SELECT 1 FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
            WHERE pp.partida_id=s.partida_id AND ppe.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) AS post_golive_ejec_cre,
    EXISTS (SELECT 1 FROM mes.partida ch WHERE ch.partida_origen_id=s.partida_id
            AND ch.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) AS post_golive_rework_child,
    (SELECT MAX(ppe.fyh_cre) FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
     WHERE pp.partida_id=s.partida_id) AS latest_ejec_fyh_cre
FROM in_scope s JOIN mes.partida p ON p.id=s.partida_id
WHERE (p.estado_produccion NOT IN ('TECO','CERRADA','CANCELADA'))
   OR EXISTS (SELECT 1 FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
              WHERE pp.partida_id=s.partida_id AND (ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz
                                                 OR ppe.fyh_cre    > '2026-05-25 15:27:52+00'::timestamptz))
   OR EXISTS (SELECT 1 FROM mes.partida ch WHERE ch.partida_origen_id=s.partida_id
              AND ch.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz)
ORDER BY s.partida_id;

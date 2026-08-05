-- READ ONLY · Identify the live/post-go-live in-scope partidas to exclude, and the
-- new clean counts after adding an ACTIVITY-level legacy gate (not just partida.fyh_cre).
-- Rule: exclude a partida if it has ANY post-go-live ejec OR a non-terminal estado.
-- (rework-child existence alone does NOT exclude — only live activity does.)
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
),
flagged AS (   -- in-scope partidas with LIVE activity
    SELECT s.partida_id, s.raw_shipped,
        p.estado_produccion,
        (p.estado_produccion NOT IN ('TECO','CERRADA','CANCELADA'))          AS active_estado,
        EXISTS (SELECT 1 FROM mes.partida_paso pp
                JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                WHERE pp.partida_id=s.partida_id
                  AND ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz) AS post_golive_ejec
    FROM in_scope s JOIN mes.partida p ON p.id=s.partida_id
)
-- §1 · the live partidas to exclude (should be a small handful incl. the 2)
SELECT partida_id, raw_shipped, estado_produccion, active_estado, post_golive_ejec
FROM flagged
WHERE active_estado OR post_golive_ejec
ORDER BY partida_id;

-- §2 · new clean counts after excluding live partidas
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
),
clean AS (
    SELECT s.partida_id, s.raw_shipped
    FROM in_scope s JOIN mes.partida p ON p.id=s.partida_id
    WHERE p.estado_produccion IN ('TECO','CERRADA','CANCELADA')
      AND NOT EXISTS (SELECT 1 FROM mes.partida_paso pp
                      JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                      WHERE pp.partida_id=s.partida_id
                        AND ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz)
)
SELECT COUNT(*) AS clean_partidas, SUM(raw_shipped) AS clean_rolls FROM clean;


SELECT * FROM item WHERE nombre ILIKE '%perox%'
SELECT * FROM doc.compra WHERE id IN (
    SELECT compra_id FROm doc.compra_detalle WHERE item_id IN (
        SELECT id FROM item WHERE nombre ILIKE '%peroxfin%'
    )
) ORDER BY fyh_cre DESC;
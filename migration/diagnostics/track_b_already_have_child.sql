-- ============================================================================
-- DIAGNOSTIC · The 12 in-scope raw rolls that ALREADY have a dyed child — READ ONLY
-- ============================================================================
-- §0 of backfill_track_b_production.sql flagged 12 in-scope rolls where a dyed lote
-- already names them as origen_lote_id. Building would create a SECOND child →
-- double-produce. Characterize + decide to EXCLUDE them (and how many partidas).
-- Nothing writes.
-- ============================================================================

WITH tb_roll AS (
    SELECT im.id AS egr_mov_id, im.lote_id, im.documento_id AS partida_id, im.cantidad, im.fecha_hora
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
in_scope AS (
    SELECT d.partida_id FROM demand d
    JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
    JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
flagged AS (
    SELECT tr.*
    FROM tb_roll tr JOIN in_scope s ON s.partida_id=tr.partida_id
    WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id = tr.lote_id)
)

-- §1 · per-roll dump of the 12: the raw roll, its child, the child's doc + dispatch
SELECT
    f.lote_id                                        AS raw_lote_id,
    f.partida_id,
    f.cantidad                                       AS raw_peso,
    f.fecha_hora                                     AS raw_egr_date,
    child.id                                         AS child_lote_id,
    child.documento_tipo                             AS child_doc_tipo,
    child.documento_id                               AS child_doc_id,
    clrd.flg_tenido                                  AS child_flg_tenido,
    (SELECT string_agg(DISTINCT imt.codigo,'+' ORDER BY imt.codigo)
     FROM inventario.item_movimientos im
     JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
     WHERE im.lote_id=f.lote_id)                     AS raw_movements,
    (SELECT string_agg(DISTINCT imt.codigo,'+' ORDER BY imt.codigo)
     FROM inventario.item_movimientos im
     JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
     WHERE im.lote_id=child.id)                      AS child_movements
FROM flagged f
JOIN inventario.lote_rollo_detalle clrd ON clrd.origen_lote_id = f.lote_id
JOIN inventario.lote child ON child.id = clrd.lote_id
ORDER BY f.partida_id, f.lote_id;

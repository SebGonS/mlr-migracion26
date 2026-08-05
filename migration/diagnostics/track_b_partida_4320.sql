-- READ ONLY · How many in-scope rolls does partida 4320 contribute + is 4320 the
-- ONLY partida with any already-childed roll? Determines the new scope counts.
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
in_scope AS (
    SELECT d.partida_id, d.raw_shipped FROM demand d
    JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
    JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
partidas_with_childed AS (
    SELECT DISTINCT tr.partida_id
    FROM tb_roll tr JOIN in_scope s ON s.partida_id=tr.partida_id
    WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id = tr.lote_id)
)
SELECT
    (SELECT COUNT(*) FROM partidas_with_childed)                          AS partidas_with_any_childed_roll,
    (SELECT string_agg(partida_id::text, ',') FROM partidas_with_childed) AS which_partidas,
    (SELECT raw_shipped FROM in_scope WHERE partida_id = 4320)            AS partida_4320_scope_rolls,
    (SELECT COUNT(*) FROM in_scope)                                       AS total_scope_partidas,
    (SELECT SUM(raw_shipped) FROM in_scope)                              AS total_scope_rolls,
    (SELECT COUNT(*) FROM in_scope WHERE partida_id NOT IN (SELECT partida_id FROM partidas_with_childed)) AS partidas_after_exclude,
    (SELECT SUM(raw_shipped) FROM in_scope WHERE partida_id NOT IN (SELECT partida_id FROM partidas_with_childed)) AS rolls_after_exclude;

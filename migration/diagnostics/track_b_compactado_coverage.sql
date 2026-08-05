-- ============================================================================
-- DIAGNOSTIC · Track B compactado-ejecucion coverage (supply vs demand) — READ ONLY
-- ============================================================================
-- Build plan: for each Track-B partida, post synthetic PROD_CONSUMO of the raw
-- rolls that shipped + PROD_ING dyed output on the COMPACTADO partida_paso_ejecucion,
-- then re-home the raw SERV_EGR to a dyed outbound entrega. Compactado is the final
-- closure step where the app posts PROD_CONSUMO (mes.transferir_rollo_partida cmt +
-- registrar_produccion at funciones/mes.sql:1674-1767).
--
-- BEFORE writing the build we must know, per Track-B partida:
--   • does it HAVE a compactado paso + ≥1 ejecucion?  (gaps need a synthetic paso/ejec)
--   • one compactado ejec or several (rib/regular are naturally separate)?
--   • do the ejec cantidad_rollos snapshots COVER the raw-rolls-shipped (demand)?
--     → the supply/demand conflict: don't overflow a single ejec.
--
-- "Track-B partida" := has ≥1 SERV_EGR on documento_tipo='PARTIDA' over a raw
-- (flg_tenido=false) roll; partida id = im.documento_id. Nothing writes.
-- ============================================================================


-- ── §1 · Do all Track-B partidas have a compactado paso? ──────────────────────
WITH tb AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_shipped
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
comp AS (
    SELECT pp.partida_id, COUNT(DISTINCT pp.id) AS n_comp_pasos
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    GROUP BY pp.partida_id
),
comp_ejec AS (
    SELECT pp.partida_id, COUNT(DISTINCT ppe.id) AS n_comp_ejecs
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
    GROUP BY pp.partida_id
)
SELECT
    (c.n_comp_pasos IS NOT NULL)   AS has_compactado_paso,
    (ce.n_comp_ejecs IS NOT NULL)  AS has_compactado_ejec,
    COUNT(*)                       AS partidas,
    SUM(tb.raw_shipped)            AS raw_rolls
FROM tb
LEFT JOIN comp c       ON c.partida_id = tb.partida_id
LEFT JOIN comp_ejec ce ON ce.partida_id = tb.partida_id
GROUP BY 1, 2
ORDER BY partidas DESC;


-- ── §2 · How many compactado ejecs per Track-B partida (1 vs many)? ───────────
WITH tb AS (
    SELECT DISTINCT im.documento_id AS partida_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
),
comp_ejec AS (
    SELECT pp.partida_id, COUNT(DISTINCT ppe.id) AS n_comp_ejecs
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
    JOIN tb ON tb.partida_id = pp.partida_id
    GROUP BY pp.partida_id
)
SELECT n_comp_ejecs, COUNT(*) AS partidas
FROM comp_ejec
GROUP BY 1 ORDER BY 1;


-- ── §3 · Supply vs demand: compactado ejec cantidad_rollos vs raw shipped ─────
-- demand = raw rolls shipped (to consume+produce). supply = SUM of compactado
-- ejec cantidad_rollos (the snapshot capacity). Compare per partida.
WITH tb AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_shipped
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
comp_supply AS (
    SELECT pp.partida_id,
           SUM(ppe.cantidad_rollos)                         AS supply_rollos,
           COUNT(*) FILTER (WHERE ppe.cantidad_rollos IS NULL) AS n_null_snapshot,
           COUNT(*)                                         AS n_ejecs
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
    GROUP BY pp.partida_id
)
SELECT
    CASE
        WHEN cs.partida_id IS NULL              THEN 'no_compactado_ejec'
        WHEN cs.supply_rollos IS NULL           THEN 'supply_all_null_snapshot'
        WHEN cs.supply_rollos = tb.raw_shipped  THEN 'supply = demand'
        WHEN cs.supply_rollos > tb.raw_shipped  THEN 'supply > demand (room)'
        ELSE                                         'supply < demand (OVERFLOW risk)'
    END                                 AS coverage,
    COUNT(*)                            AS partidas,
    SUM(tb.raw_shipped)                 AS demand_rolls,
    SUM(COALESCE(cs.supply_rollos,0))   AS supply_rolls
FROM tb
LEFT JOIN comp_supply cs ON cs.partida_id = tb.partida_id
GROUP BY 1
ORDER BY partidas DESC;


-- ── §4 · Are the raw shipped rolls still assigned (partida_componente) so we ──
--         can consume them? And are they in stock (they egressed — likely 0)?
-- registrar_produccion consumes rolls via partida_componente membership. Check if
-- the Track-B raw rolls are still linked to their partida there. (If not, the build
-- consumes by ledger identity instead — this tells us which path.)
WITH tb_rolls AS (
    SELECT DISTINCT im.lote_id, im.documento_id AS partida_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
)
SELECT
    EXISTS (SELECT 1 FROM mes.partida_componente pc
            WHERE pc.lote_id = tb.lote_id AND pc.partida_id = tb.partida_id)  AS in_partida_componente,
    COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=tb.lote_id),0) > 0 AS in_stock,
    COUNT(*) AS rolls
FROM tb_rolls tb
GROUP BY 1, 2
ORDER BY rolls DESC;


-- ── §5 · Compactado ejec estado + fyh — are they finalized or open? ───────────
-- If ejecs are already COMPLETADO the build back-posts onto closed steps (fine for
-- migration); shows the estado distribution so we know what we're writing onto.
WITH tb AS (
    SELECT DISTINCT im.documento_id AS partida_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
)
SELECT ppe.estado, COUNT(*) AS compactado_ejecs,
       COUNT(*) FILTER (WHERE ppe.cantidad_rollos IS NULL) AS null_snapshot,
       MIN(ppe.fyh_inicio) AS earliest, MAX(ppe.fyh_inicio) AS latest
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
JOIN tb ON tb.partida_id = pp.partida_id
GROUP BY ppe.estado
ORDER BY compactado_ejecs DESC;

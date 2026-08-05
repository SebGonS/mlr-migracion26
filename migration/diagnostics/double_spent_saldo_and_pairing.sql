-- ============================================================================
-- DIAGNOSTIC · Saldo state + AJUSTE_POS pairing safety for the 193 — READ ONLY
-- ============================================================================
-- Two sub-groups found:
--   G1 (151): SERV_ING > SERV_EGR > AJUSTE_POS > PROD_CONSUMO   (net 0)
--   G2 ( 42): SERV_ING > SERV_EGR > PROD_CONSUMO                (net -1*cantidad)
-- Plan: delete the phantom SERV_EGR (both groups) + its paired AJUSTE_POS (G1 only).
-- Before writing the patch we must confirm:
--   §C1  current lote_saldo per group (0? negative?) — sets the post-delete target
--   §C2  each G1 roll has EXACTLY ONE AJUSTE_POS matching the phantom (lote+cantidad),
--        so we delete the right reversal and never touch a legit adjustment
--   §C3  the phantom SERV_EGR is uniquely identifiable per roll (exactly one, on
--        PARTIDA, matching cantidad) — no ambiguity when deleting
-- Nothing writes.
-- ============================================================================

WITH ds AS (
    SELECT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
    HAVING bool_or(imt.codigo='PROD_CONSUMO') AND bool_or(imt.codigo='SERV_EGR')
),
raw_ds AS (
    SELECT ds.lote_id FROM ds
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = ds.lote_id AND lrd.flg_tenido = false
),
grp AS (   -- classify each roll into G1/G2 by presence of AJUSTE_POS
    SELECT raw_ds.lote_id,
           bool_or(imt.codigo='AJUSTE_POS') AS has_ajuste
    FROM raw_ds
    JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY raw_ds.lote_id
)

-- ── §C1 · Current lote_saldo per group ────────────────────────────────────────
SELECT
    CASE WHEN g.has_ajuste THEN 'G1 (has AJUSTE_POS, net0)' ELSE 'G2 (no AJUSTE, net-1)' END AS grp,
    COALESCE(ls.cantidad_actual, 0)  AS saldo,
    a.codigo                         AS almacen,
    COUNT(*)                         AS rolls
FROM grp g
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = g.lote_id
LEFT JOIN inventario.ubicacion u   ON u.id = ls.ubicacion_id
LEFT JOIN inventario.almacen  a    ON a.id = u.almacen_id
GROUP BY 1, 2, 3
ORDER BY grp, saldo;


-- ── §C2 · Per-roll movement-type COUNTS — uniqueness of phantom & reversal ────
-- For each of the 193, how many SERV_EGR / AJUSTE_POS / SERV_ING / PROD_CONSUMO?
-- We NEED exactly one phantom SERV_EGR per roll (on PARTIDA) and, for G1, exactly
-- one AJUSTE_POS to pair with it. Any roll with >1 of either is a special case we
-- must handle explicitly, not blanket-delete.
WITH ds AS (
    SELECT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
    HAVING bool_or(imt.codigo='PROD_CONSUMO') AND bool_or(imt.codigo='SERV_EGR')
),
raw_ds AS (
    SELECT ds.lote_id FROM ds
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = ds.lote_id AND lrd.flg_tenido = false
),
cnt AS (
    SELECT raw_ds.lote_id,
        COUNT(*) FILTER (WHERE imt.codigo='SERV_ING')                                  AS n_serv_ing,
        COUNT(*) FILTER (WHERE imt.codigo='SERV_EGR')                                  AS n_serv_egr,
        COUNT(*) FILTER (WHERE imt.codigo='SERV_EGR' AND im.documento_tipo='PARTIDA')  AS n_serv_egr_partida,
        COUNT(*) FILTER (WHERE imt.codigo='AJUSTE_POS')                                AS n_ajuste_pos,
        COUNT(*) FILTER (WHERE imt.codigo='PROD_CONSUMO')                              AS n_prod_consumo
    FROM raw_ds
    JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY raw_ds.lote_id
)
SELECT n_serv_ing, n_serv_egr, n_serv_egr_partida, n_ajuste_pos, n_prod_consumo,
       COUNT(*) AS rolls
FROM cnt
GROUP BY 1,2,3,4,5
ORDER BY rolls DESC;
-- expect two rows: (1,1,1,1,1)=151 and (1,1,1,0,1)=42. Anything else = a special case.


-- ── §C3 · For G1, does the AJUSTE_POS cantidad match the phantom SERV_EGR? ─────
-- The reversal we delete must equal the phantom in magnitude (same roll, same qty).
-- Confirms AJUSTE_POS.cantidad = SERV_EGR.cantidad for every G1 roll.
WITH ds AS (
    SELECT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
    HAVING bool_or(imt.codigo='PROD_CONSUMO') AND bool_or(imt.codigo='SERV_EGR')
),
raw_ds AS (
    SELECT ds.lote_id FROM ds
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = ds.lote_id AND lrd.flg_tenido = false
),
egr AS (
    SELECT im.lote_id, im.cantidad
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
),
aj AS (
    SELECT im.lote_id, im.cantidad
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='AJUSTE_POS'
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
)
SELECT
    (egr.cantidad = aj.cantidad) AS qty_matches,
    COUNT(*) AS rolls
FROM egr JOIN aj ON aj.lote_id = egr.lote_id
GROUP BY 1;
-- expect: qty_matches=true → 151. Any false = investigate before deleting that AJUSTE.


-- ============================================================================
-- DIAGNOSTIC · Track B "over" bucket — why raw_dispatched > legacy_rollos — READ ONLY
-- ============================================================================
-- Re-baseline found 306 partidas where DISTINCT raw rolls with SERV_EGR on
-- documento_tipo='PARTIDA' EXCEEDS legacy produccion_tenido.rollos by 1–8 (mostly
-- +1/+2/+3). Before any production backfill we must explain the surplus — it's the
-- same ledger-noise family as the 193 double-spend and must not be baked in.
--
-- Hypotheses to test:
--   H1  a roll has MULTIPLE SERV_EGR on PARTIDA (duplicate egress) → inflates count
--   H2  extra raw egresses belong to a DIFFERENT partida than legacy attributes
--       (rework pooling: legacy keys original, egress keyed on child or vice versa)
--   H3  the surplus rolls also have PROD_CONSUMO (more double-spend that escaped the
--       193 filter — e.g. flg_tenido mislabel, or consumo on non-pp_ejec doc)
--   H4  genuine: more rolls really shipped than legacy recorded (legacy undercount)
--
-- Nothing writes. go-live cutoff '2026-05-25 15:27:52+00'::timestamptz.
-- ============================================================================

-- reusable: the "over" partidas + their surplus size -----------------------------
-- (inlined per section since each SELECT is standalone)


-- ── §1 · H1: multiple SERV_EGR (PARTIDA) per roll? ────────────────────────────
-- Per roll in the Track-B set, how many SERV_EGR-on-PARTIDA movements? >1 = dup.
SELECT n_egr_per_roll, COUNT(*) AS rolls
FROM (
    SELECT im.lote_id, COUNT(*) AS n_egr_per_roll
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.lote_id
) x
GROUP BY 1 ORDER BY 1;
-- if all n_egr_per_roll=1 → H1 rejected (no per-roll duplication).


-- ── §2 · H3: do any "over"-partida raw egress rolls ALSO have PROD_CONSUMO? ────
-- (should be 0 now — we cleared the 193 — but the over-count may hide more.)
WITH rawship AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_dispatched
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
legacy AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, SUM(pt.rollos) AS legacy_rollos
    FROM mes.partida mp JOIN public.produccion_tenido pt ON pt.partida_id=mp.id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
),
over_partidas AS (
    SELECT rs.partida_id
    FROM rawship rs
    LEFT JOIN mes.partida mp ON mp.id=rs.partida_id
    LEFT JOIN legacy lg ON lg.pool_id=COALESCE(mp.partida_origen_id, rs.partida_id)
    WHERE lg.legacy_rollos IS NOT NULL AND rs.raw_dispatched > lg.legacy_rollos
),
over_rolls AS (
    SELECT DISTINCT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    JOIN over_partidas op ON op.partida_id = im.documento_id
    WHERE im.documento_tipo='PARTIDA'
)
SELECT
    COUNT(*) AS over_bucket_raw_rolls,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM inventario.item_movimientos im2
        JOIN inventario.item_movimiento_tipo imt2 ON imt2.id=im2.item_movimiento_tipo_id AND imt2.codigo='PROD_CONSUMO'
        WHERE im2.lote_id = orr.lote_id))                                AS also_has_prod_consumo,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id = orr.lote_id AND c.flg_tenido=true))     AS has_dyed_child
FROM over_rolls orr;


-- ── §3 · H2: rework pooling — is legacy keyed on original but egress on child? ─
-- For "over" partidas, split raw egress by whether the egress partida is itself a
-- rework (partida_origen_id NOT NULL) and whether legacy rollos exist at the child
-- vs the pool. Shows if the surplus is a pooling artifact.
WITH rawship AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_dispatched
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
legacy_pool AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, SUM(pt.rollos) AS legacy_rollos
    FROM mes.partida mp JOIN public.produccion_tenido pt ON pt.partida_id=mp.id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
),
legacy_direct AS (   -- legacy rollos keyed on the exact partida (not pooled)
    SELECT pt.partida_id, SUM(pt.rollos) AS legacy_rollos_direct
    FROM public.produccion_tenido pt GROUP BY pt.partida_id
)
SELECT
    (mp.partida_origen_id IS NOT NULL)                                   AS egress_partida_is_rework,
    (COALESCE(pr_direct.legacy_rollos_direct,0) = 0)                     AS no_direct_legacy,
    COUNT(*)                                                             AS partidas,
    SUM(rs.raw_dispatched)                                               AS raw_rolls,
    SUM(rs.raw_dispatched - lg.legacy_rollos)                            AS total_surplus
FROM rawship rs
LEFT JOIN mes.partida mp ON mp.id=rs.partida_id
LEFT JOIN legacy_pool lg ON lg.pool_id=COALESCE(mp.partida_origen_id, rs.partida_id)
LEFT JOIN legacy_direct pr_direct ON pr_direct.partida_id = rs.partida_id
WHERE lg.legacy_rollos IS NOT NULL AND rs.raw_dispatched > lg.legacy_rollos
GROUP BY 1, 2
ORDER BY partidas DESC;


-- ── §4 · Pooling double-count check: is the SAME roll egressed under BOTH an ──
--         original AND its rework partida? (would inflate the pool's raw count)
-- Count rolls whose SERV_EGR documento_id maps to a rework, AND that also appear
-- egressed under the original — i.e. one physical roll counted twice in the pool.
WITH egr AS (
    SELECT DISTINCT im.lote_id, im.documento_id AS egr_partida_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
)
SELECT
    COUNT(*)                                                     AS raw_egress_rows,
    COUNT(DISTINCT lote_id)                                      AS distinct_rolls,
    COUNT(*) - COUNT(DISTINCT lote_id)                           AS rolls_egressed_under_multiple_partidas
FROM egr;
-- if distinct_rolls < raw_egress_rows, some rolls egress under >1 partida id → pool double-count.


-- ── §5 · Sample 12 "over" partidas: legacy vs raw vs dyed, with rework flag ────
WITH rawship AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_dispatched
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
prod AS (
    SELECT pp.partida_id, COUNT(*) AS dyed_produced
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    GROUP BY pp.partida_id
),
legacy AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, SUM(pt.rollos) AS legacy_rollos
    FROM mes.partida mp JOIN public.produccion_tenido pt ON pt.partida_id=mp.id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
)
SELECT rs.partida_id,
       mp.partida_origen_id,
       (mp.partida_origen_id IS NOT NULL) AS is_rework,
       rs.raw_dispatched,
       COALESCE(pr.dyed_produced,0)       AS dyed_produced,
       lg.legacy_rollos,
       (rs.raw_dispatched + COALESCE(pr.dyed_produced,0) - lg.legacy_rollos) AS surplus,
       mp.fyh_cre
FROM rawship rs
LEFT JOIN prod pr ON pr.partida_id=rs.partida_id
LEFT JOIN mes.partida mp ON mp.id=rs.partida_id
LEFT JOIN legacy lg ON lg.pool_id=COALESCE(mp.partida_origen_id, rs.partida_id)
WHERE lg.legacy_rollos IS NOT NULL
  AND (rs.raw_dispatched + COALESCE(pr.dyed_produced,0)) > lg.legacy_rollos
ORDER BY surplus DESC, rs.partida_id
LIMIT 12;




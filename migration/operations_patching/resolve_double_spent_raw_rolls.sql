-- ============================================================================
-- RESOLVE · 193 double-spent raw rolls (phantom raw SERV_EGR) — Track B knot
-- ============================================================================
-- WHAT: 193 RAW rolls (lote_rollo_detalle.flg_tenido=false) each carry BOTH a real
--   PROD_CONSUMO (consumed into dyeing; every one has a dyed child + dyed output
--   already re-homed to an outbound entrega in Track A) AND a PHANTOM raw SERV_EGR
--   on documento_tipo='PARTIDA'. A roll cannot be dyed-into AND shipped raw. The
--   SERV_EGR is a migration artifact: it shares the SERV_ING's exact microsecond
--   fecha_hora (auto-generated, not a real dispatch), and predates the (import-
--   stamped) PROD_CONSUMO only because consumption was stamped at import time.
--
-- EVIDENCE (all verified this session, see migration/diagnostics/):
--   • characterize_double_spent_rolls.sql : 193 all flg_tenido=false; SERV_EGR on
--     PARTIDA + PROD_CONSUMO on partida_paso_ejecucion; ALL have a dyed child;
--     ALL out of stock (saldo 0). In 9 partidas.
--   • double_spent_movement_ledger.sql : two chains —
--       G1 (151): SERV_ING > SERV_EGR > AJUSTE_POS > PROD_CONSUMO   net = 0
--       G2 ( 42): SERV_ING > SERV_EGR > PROD_CONSUMO                net = -1*cantidad
--     The G1 AJUSTE_POS is a PRIOR partial repair that already compensated the
--     phantom egress so the roll could be consumed.
--   • double_spent_saldo_and_pairing.sql : per roll exactly 1 of each mov type
--     (G1: incl. 1 AJUSTE_POS; G2: 0); AJUSTE_POS.cantidad = SERV_EGR.cantidad for
--     all 151; current lote_saldo = 0 for BOTH groups (ALM_CRU).
--
-- FIX (pure DELETE of migration artifacts — nothing to "rewire" to; the egress
--   never happened):
--   G1 (151): delete the phantom SERV_EGR *and* its paired AJUSTE_POS (a net-zero
--             noise pair) → clean chain SERV_ING > PROD_CONSUMO.
--   G2 ( 42): delete the phantom SERV_EGR only → net returns to 0.
--   Both groups end as SERV_ING(+1) > PROD_CONSUMO(-1) = net 0, which EQUALS the
--   current lote_saldo (0). The saldo trigger fn_trg_sync_cantidad_actual is
--   AFTER INSERT ONLY, so DELETE does not disturb lote_saldo — and no correction is
--   needed because target (0) already equals current (0). We assert this in §2.
--
-- RESULT: these 193 leave the 12,265 Track-B raw set (they were never raw-shipped);
--   ledger now tells the true story received→consumed→dyed. Expected to also heal
--   part of the ejecucion under-count.
--
-- SCOPE: legacy only. Every target partida.fyh_cre <= go-live (asserted in §0/§2).
-- WRITES: DELETE inventario.item_movimientos ONLY (193 SERV_EGR + 151 AJUSTE_POS).
--
-- ⚠ DRY-RUN §0, run §1 in a txn, read §2, then COMMIT.
-- ============================================================================


-- ── §0 · DRY RUN — exactly what will be deleted, and the safety invariants ─────
WITH ds AS (
    SELECT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
    HAVING bool_or(imt.codigo='PROD_CONSUMO') AND bool_or(imt.codigo='SERV_EGR')
),
raw_ds AS (   -- the 193: raw double-spent rolls
    SELECT ds.lote_id FROM ds
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = ds.lote_id AND lrd.flg_tenido = false
),
phantom_egr AS (   -- the phantom SERV_EGR on PARTIDA (both groups)
    SELECT im.id AS mov_id, im.lote_id, im.cantidad
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
    WHERE im.documento_tipo = 'PARTIDA'
),
paired_ajuste AS (   -- G1's AJUSTE_POS reversal (qty matches, same roll)
    SELECT im.id AS mov_id, im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='AJUSTE_POS'
    JOIN phantom_egr pe ON pe.lote_id = im.lote_id AND pe.cantidad = im.cantidad
)
SELECT
    (SELECT COUNT(*) FROM raw_ds)                                            AS rolls_total_expect_193,
    (SELECT COUNT(*) FROM phantom_egr)                                       AS serv_egr_to_delete_expect_193,
    (SELECT COUNT(*) FROM paired_ajuste)                                     AS ajuste_pos_to_delete_expect_151,
    -- every roll's PROD_CONSUMO stays + every roll has a dyed child (safety)
    (SELECT COUNT(*) FROM raw_ds r WHERE NOT EXISTS (
        SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id = r.lote_id AND c.flg_tenido = true))         AS rolls_without_dyed_child_expect_0,
    -- all target partidas legacy (via the SERV_EGR's documento_id → mes.partida)
    (SELECT COUNT(DISTINCT pe.lote_id) FROM phantom_egr pe
        JOIN inventario.item_movimientos e ON e.id = pe.mov_id
        JOIN mes.partida p ON p.id = e.documento_id
        WHERE p.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz)             AS rolls_post_golive_expect_0;


-- ── §1 · Execute ──────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL statement_timeout = 0;

-- Materialize the exact movement ids to delete (both groups) into a temp set,
-- so the two DELETEs target identical, pre-identified rows.
CREATE TEMP TABLE _ds_del ON COMMIT DROP AS
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
phantom_egr AS (
    SELECT im.id AS mov_id, im.lote_id, im.cantidad, 'SERV_EGR'::text AS kind
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
    WHERE im.documento_tipo = 'PARTIDA'
),
paired_ajuste AS (
    SELECT im.id AS mov_id, im.lote_id, im.cantidad, 'AJUSTE_POS'::text AS kind
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='AJUSTE_POS'
    JOIN phantom_egr pe ON pe.lote_id = im.lote_id AND pe.cantidad = im.cantidad
)
SELECT mov_id, lote_id, kind FROM phantom_egr
UNION ALL
SELECT mov_id, lote_id, kind FROM paired_ajuste;

-- guard: must be exactly 193 SERV_EGR + 151 AJUSTE_POS = 344 rows
DO $$
DECLARE n_egr int; n_aj int;
BEGIN
    SELECT COUNT(*) INTO n_egr FROM _ds_del WHERE kind='SERV_EGR';
    SELECT COUNT(*) INTO n_aj  FROM _ds_del WHERE kind='AJUSTE_POS';
    IF n_egr <> 193 OR n_aj <> 151 THEN
        RAISE EXCEPTION 'Unexpected delete set: SERV_EGR=% (want 193), AJUSTE_POS=% (want 151)', n_egr, n_aj;
    END IF;
END $$;

DELETE FROM inventario.item_movimientos im
USING _ds_del d
WHERE im.id = d.mov_id;


-- ── §2 · Verify ───────────────────────────────────────────────────────────────
-- (a) the double-spent knot is gone: no raw roll has BOTH PROD_CONSUMO and SERV_EGR
SELECT COUNT(*) AS double_spent_remaining_expect_0
FROM (
    SELECT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = false
    GROUP BY im.lote_id
    HAVING bool_or(imt.codigo='PROD_CONSUMO') AND bool_or(imt.codigo='SERV_EGR')
) x;

-- (b) every one of the 193 now nets to exactly 0 across its movements (no under/over)
--     and still HAS its PROD_CONSUMO (we deleted only egress + adjustment).
WITH targets AS (
    SELECT DISTINCT lote_id FROM _ds_del
)
SELECT
    COUNT(*)                                                        AS rolls_expect_193,
    COUNT(*) FILTER (WHERE net_qty = 0)                             AS net_zero_expect_193,
    COUNT(*) FILTER (WHERE has_consumo)                             AS still_have_consumo_expect_193,
    COUNT(*) FILTER (WHERE has_serv_egr)                            AS still_have_serv_egr_expect_0
FROM (
    SELECT t.lote_id,
           SUM(imt.factor * im.cantidad)                       AS net_qty,
           bool_or(imt.codigo='PROD_CONSUMO')                  AS has_consumo,
           bool_or(imt.codigo='SERV_EGR')                      AS has_serv_egr
    FROM targets t
    JOIN inventario.item_movimientos im ON im.lote_id = t.lote_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY t.lote_id
) n;

-- (c) lote_saldo unchanged and still 0 for all 193 (target == current, no drift)
WITH targets AS (SELECT DISTINCT lote_id FROM _ds_del)
SELECT COALESCE(ls.cantidad_actual,0) AS saldo, COUNT(*) AS rolls
FROM targets t
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = t.lote_id
GROUP BY 1 ORDER BY 1;   -- expect: single row saldo=0, rolls=193

-- (d) Track-B raw dispatch set should now be ~12,072 (12,265 - 193)
SELECT COUNT(DISTINCT im.lote_id) AS track_b_raw_serv_egr_now
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
JOIN inventario.lote l ON l.id=im.lote_id AND l.documento_tipo IS NOT NULL
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
WHERE im.documento_tipo='PARTIDA';   -- expect ~12,072

-- COMMIT;    -- ← after §2: (a)=0, (b) all 193/193/193/0, (c) single saldo=0 row, (d)~12,072
-- ROLLBACK;  -- ← if anything is off

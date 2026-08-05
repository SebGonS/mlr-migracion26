-- ============================================================================
-- DIAGNOSTIC · Track B re-baseline after the 193 double-spent fix — READ ONLY
-- ============================================================================
-- Context: resolve_double_spent_raw_rolls.sql deleted 193 phantom raw SERV_EGR
-- (+151 paired AJUSTE_POS). Track B raw dispatch set is now 12,072 rolls. This
-- re-runs the Track B census to see how the clean/mismatch split and ejecucion
-- drift shifted — the phantom removal should have healed a chunk (the 193 were
-- rolls that had really been consumed, mis-counted as raw-shipped).
--
-- DEFINITIONS (kept identical to roll_lifecycle_status.sql so numbers compare):
--   raw_dispatched (per partida) = DISTINCT raw rolls with SERV_EGR on doc=PARTIDA
--   dyed_produced  (per partida) = flg_tenido=true lotes on partida_paso_ejecucion
--   legacy_rollos  (per pool)    = SUM(public.produccion_tenido.rollos), pooled on
--                                  COALESCE(partida_origen_id, id) (original+reworks)
--   clean  := dyed_produced + raw_dispatched = legacy_rollos
-- go-live cutoff: '2026-05-25 15:27:52+00'::timestamptz. Nothing writes.
-- ============================================================================


-- NOTE: the Track-B set is defined by the MOVEMENT's documento_tipo='PARTIDA'
-- (im.documento_id = partida id). The lote ORIGIN documento_tipo is already
-- normalized to 'entrega' by N2 — do NOT filter the lote on 'PARTIDA'.


-- ── §1 · Track B headcount + partida span (confirm 12,072 / how many partidas) ─
SELECT
    COUNT(DISTINCT im.lote_id)        AS raw_serv_egr_rolls_expect_12072,
    COUNT(DISTINCT im.documento_id)   AS partidas
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
WHERE im.documento_tipo='PARTIDA';


-- ── §2 · Per-partida reconciliation: clean vs mismatch (was 300/333) ──────────
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
    FROM mes.partida mp
    JOIN public.produccion_tenido pt ON pt.partida_id = mp.id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
),
recon AS (
    SELECT rs.partida_id,
           rs.raw_dispatched,
           COALESCE(pr.dyed_produced,0) AS dyed_produced,
           lg.legacy_rollos,
           (COALESCE(pr.dyed_produced,0) + rs.raw_dispatched) AS total_accounted
    FROM rawship rs
    LEFT JOIN prod pr   ON pr.partida_id = rs.partida_id
    LEFT JOIN mes.partida mp ON mp.id = rs.partida_id
    LEFT JOIN legacy lg ON lg.pool_id = COALESCE(mp.partida_origen_id, rs.partida_id)
)
SELECT
    CASE
        WHEN legacy_rollos IS NULL                         THEN 'no_legacy_rollos'
        WHEN total_accounted = legacy_rollos               THEN 'clean (dyed+raw=legacy)'
        WHEN total_accounted < legacy_rollos               THEN 'short (accounted < legacy)'
        ELSE                                                    'over  (accounted > legacy)'
    END                                   AS bucket,
    COUNT(*)                              AS partidas,
    SUM(raw_dispatched)                   AS raw_rolls,
    SUM(dyed_produced)                    AS dyed_rolls
FROM recon
GROUP BY 1
ORDER BY partidas DESC;


-- ── §3 · Mismatch magnitude distribution (how far off, signed) ────────────────
-- total_accounted - legacy_rollos, bucketed, to see if mismatches are small/large.
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
    FROM mes.partida mp
    JOIN public.produccion_tenido pt ON pt.partida_id = mp.id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
)
SELECT
    (COALESCE(pr.dyed_produced,0) + rs.raw_dispatched - lg.legacy_rollos) AS accounted_minus_legacy,
    COUNT(*) AS partidas
FROM rawship rs
LEFT JOIN prod pr ON pr.partida_id = rs.partida_id
LEFT JOIN mes.partida mp ON mp.id = rs.partida_id
LEFT JOIN legacy lg ON lg.pool_id = COALESCE(mp.partida_origen_id, rs.partida_id)
WHERE lg.legacy_rollos IS NOT NULL
GROUP BY 1
ORDER BY partidas DESC, accounted_minus_legacy;


-- ── §4 · Ejecucion-snapshot drift, re-measured (was 79 over / 230 under / 402 NULL)
-- out_lotes = dyed output lotes on the ejec; compare to ppe.cantidad_rollos snapshot.
WITH ejec_out AS (
    SELECT l.documento_id AS ejec_id, COUNT(*) AS out_lotes, SUM(l.cantidad) AS out_peso
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    WHERE l.documento_tipo='partida_paso_ejecucion'
    GROUP BY l.documento_id
)
SELECT
    COUNT(*)                                                          AS ejecs_with_output,
    COUNT(*) FILTER (WHERE ppe.cantidad_rollos IS NULL)              AS snapshot_NULL,
    COUNT(*) FILTER (WHERE eo.out_lotes = ppe.cantidad_rollos)       AS count_matches,
    COUNT(*) FILTER (WHERE eo.out_lotes > ppe.cantidad_rollos)       AS count_OVERFLOW,
    COUNT(*) FILTER (WHERE eo.out_lotes < ppe.cantidad_rollos)       AS count_under,
    round(SUM(abs(eo.out_peso - ppe.peso_kg))
          FILTER (WHERE ppe.peso_kg IS NOT NULL)::numeric, 2)        AS total_peso_drift
FROM ejec_out eo
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = eo.ejec_id;


-- ── §5 · Ledger consistency per ejec (PROD_CONSUMO vs PROD_ING count) ─────────
-- After the fix, consumed_in should = produced_out more often (we removed spurious
-- egresses, not consumo — but confirm no ejec got orphaned).
WITH per_ejec AS (
    SELECT im.documento_id AS ejec_id,
        COUNT(*) FILTER (WHERE imt.codigo='PROD_CONSUMO') AS consumed_in,
        COUNT(*) FILTER (WHERE imt.codigo='PROD_ING')     AS produced_out
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
    WHERE im.documento_tipo='partida_paso_ejecucion'
      AND imt.codigo IN ('PROD_CONSUMO','PROD_ING')
    GROUP BY im.documento_id
)
SELECT COUNT(*) AS ejecs,
       COUNT(*) FILTER (WHERE consumed_in = produced_out)  AS counts_match,
       COUNT(*) FILTER (WHERE consumed_in <> produced_out) AS counts_differ,
       COUNT(*) FILTER (WHERE produced_out = 0)            AS no_output,
       COUNT(*) FILTER (WHERE consumed_in = 0)             AS no_input
FROM per_ejec;

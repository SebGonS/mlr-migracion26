-- ============================================================================
-- DIAGNOSTIC · Characterize the 193 DOUBLE-SPENT raw rolls — READ ONLY
-- ============================================================================
-- A "double-spent" roll is a RAW lote (lote_rollo_detalle.flg_tenido=false) that
-- carries BOTH:
--     • a PROD_CONSUMO movement  (consumed into production; doc=partida_paso_ejecucion)
--     • a raw  SERV_EGR movement (shipped raw as a shortcut; doc=PARTIDA)
-- Physically impossible: a roll cannot be dyed-into AND shipped raw. One of the two
-- ledger events is spurious and must be resolved BEFORE the Track-B production backfill.
--
-- This script ONLY reads. It classifies each of the 193 so we can pick a per-case
-- rule. Nothing here writes. go-live cutoff: '2026-05-25 15:27:52+00'::timestamptz
--
-- Every section is a standalone SELECT. Run top→bottom, paste results back.
-- ============================================================================


-- Shared definition of the double-spent set (repeated inline per section since
-- each SELECT is standalone). A raw lote with >=1 PROD_CONSUMO and >=1 SERV_EGR.


-- ── §1 · Headcount — confirm the 193 and split raw-only vs any-dyed SERV_EGR ───
-- Sanity: does the count reproduce? And is the SERV_EGR really on a RAW roll
-- (flg_tenido=false) — yes by construction, but we also report the SERV_EGR's
-- documento_tipo distribution (should be PARTIDA for the shortcut dispatch).
WITH ds AS (
    SELECT im.lote_id,
           bool_or(imt.codigo = 'PROD_CONSUMO') AS has_consumo,
           bool_or(imt.codigo = 'SERV_EGR')     AS has_serv_egr
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
    HAVING bool_or(imt.codigo='PROD_CONSUMO') AND bool_or(imt.codigo='SERV_EGR')
)
SELECT
    lrd.flg_tenido,
    COUNT(*) AS rolls
FROM ds
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = ds.lote_id
GROUP BY 1
ORDER BY 1;
-- expect: flg_tenido=false → 193 (the Track-B knot). Any flg_tenido=true rows would
-- be a DIFFERENT anomaly (a dyed roll consumed+dispatched — not this task).


-- ── §2 · The SERV_EGR & PROD_CONSUMO document context per roll ────────────────
-- For the 193 raw double-spent, what doc does each of the two movements sit on?
-- SERV_EGR should be on PARTIDA (shortcut raw dispatch); PROD_CONSUMO on a
-- partida_paso_ejecucion. We cross-tab the doc-type pairs.
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
    SELECT im.lote_id, string_agg(DISTINCT im.documento_tipo, ',') AS egr_doctypes,
           COUNT(*) AS n_egr
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
    GROUP BY im.lote_id
),
con AS (
    SELECT im.lote_id, string_agg(DISTINCT im.documento_tipo, ',') AS con_doctypes,
           COUNT(*) AS n_con
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo='PROD_CONSUMO'
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
    GROUP BY im.lote_id
)
SELECT egr.egr_doctypes, con.con_doctypes,
       COUNT(*)                       AS rolls,
       SUM(egr.n_egr)                 AS total_serv_egr_movs,
       SUM(con.n_con)                 AS total_prod_consumo_movs
FROM raw_ds
JOIN egr ON egr.lote_id = raw_ds.lote_id
JOIN con ON con.lote_id = raw_ds.lote_id
GROUP BY 1, 2
ORDER BY rolls DESC;


-- ── §3 · Chronology — which came FIRST, consumo or dispatch? ──────────────────
-- If PROD_CONSUMO precedes SERV_EGR, the roll was consumed then (impossibly) also
-- shipped → the SERV_EGR is the spurious shortcut. If SERV_EGR precedes, it was
-- shipped raw then (impossibly) consumed → the PROD_CONSUMO is spurious. This is
-- the primary signal for the per-case rule.
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
times AS (
    SELECT raw_ds.lote_id,
           MIN(im.fecha_hora) FILTER (WHERE imt.codigo='PROD_CONSUMO') AS t_consumo,
           MIN(im.fecha_hora) FILTER (WHERE imt.codigo='SERV_EGR')     AS t_egr
    FROM raw_ds
    JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY raw_ds.lote_id
)
SELECT
    CASE
        WHEN t_consumo < t_egr THEN 'consumo_first (SERV_EGR likely spurious)'
        WHEN t_egr < t_consumo THEN 'dispatch_first (PROD_CONSUMO likely spurious)'
        WHEN t_consumo = t_egr THEN 'same_timestamp (ambiguous)'
        ELSE 'missing_one_side (unexpected)'
    END AS ordering,
    COUNT(*) AS rolls
FROM times
GROUP BY 1
ORDER BY rolls DESC;


-- ── §4 · Current stock position of each double-spent roll ─────────────────────
-- Location = destino of the LAST movement. If a roll's last movement is the egress
-- it is OUT of stock (shipped won); if last is a PROD_ING/consumo-context it may be
-- sitting in-plant. Tells us which event "really happened" physically.
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
last_mov AS (
    SELECT DISTINCT ON (im.lote_id)
           im.lote_id, imt.codigo AS last_code, im.destino_ubicacion_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN raw_ds ON raw_ds.lote_id = im.lote_id
    ORDER BY im.lote_id, im.fecha_hora DESC, im.id DESC
),
saldo AS (
    SELECT lote_id, SUM(cantidad_actual) AS stock
    FROM inventario.lote_saldo
    GROUP BY lote_id
)
SELECT
    lm.last_code                                            AS last_movement,
    COALESCE(a.codigo, '(out / no ubicacion)')              AS last_destino_almacen,
    COUNT(*)                                                AS rolls,
    SUM(COALESCE(s.stock,0))                                AS sum_stock_actual,
    COUNT(*) FILTER (WHERE COALESCE(s.stock,0) > 0)         AS rolls_with_stock
FROM raw_ds
LEFT JOIN last_mov lm            ON lm.lote_id = raw_ds.lote_id
LEFT JOIN inventario.ubicacion u ON u.id = lm.destino_ubicacion_id
LEFT JOIN inventario.almacen   a ON a.id = u.almacen_id
LEFT JOIN saldo s                ON s.lote_id = raw_ds.lote_id
GROUP BY 1, 2
ORDER BY rolls DESC;


-- ── §5 · Does the roll have a DYED CHILD? (did production really produce output?)
-- If a raw double-spent roll is named as origen_lote_id of a dyed child lote, then
-- production genuinely produced a dyed output from it → consumo is real, the raw
-- SERV_EGR is the spurious shortcut. If NO dyed child exists, production likely
-- didn't really run → the SERV_EGR (raw ship) is the true event.
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
)
SELECT
    EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
            WHERE c.origen_lote_id = raw_ds.lote_id AND c.flg_tenido = true) AS has_dyed_child,
    COUNT(*) AS rolls
FROM raw_ds
GROUP BY 1
ORDER BY 1;


-- ── §6 · Which partida bucket — 300-clean vs 333-mismatch? ────────────────────
-- Per partida, is dyed_produced + raw_dispatched == legacy_rollos (clean) or not?
-- We map each double-spent roll to its partida (via the PROD_CONSUMO ejec→paso→partida)
-- and report how the 193 distribute across clean vs mismatch partidas.
-- legacy_rollos = public.produccion_tenido rollos pooled on original partida.
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
-- partida each double-spent roll was consumed into
roll_partida AS (
    SELECT DISTINCT raw_ds.lote_id, pp.partida_id
    FROM raw_ds
    JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id AND im.documento_tipo='partida_paso_ejecucion'
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo='PROD_CONSUMO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
),
-- per-partida dyed produced (ledger)
prod AS (
    SELECT pp.partida_id, COUNT(*) AS dyed_produced
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    GROUP BY pp.partida_id
),
-- per-partida raw dispatched (SERV_EGR on PARTIDA, raw rolls)
rawship AS (
    SELECT l.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_dispatched
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote l ON l.id = im.lote_id AND l.documento_tipo='PARTIDA'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY l.documento_id
),
-- legacy rollos pooled on original partida (original + reworks)
legacy AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id,
           SUM(pt.rollos) AS legacy_rollos
    FROM mes.partida mp
    JOIN public.produccion_tenido pt ON pt.partida_id = mp.id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
),
partida_bucket AS (
    SELECT rp.partida_id,
           COALESCE(pr.dyed_produced,0)  AS dyed_produced,
           COALESCE(rs.raw_dispatched,0) AS raw_dispatched,
           lg.legacy_rollos,
           (COALESCE(pr.dyed_produced,0) + COALESCE(rs.raw_dispatched,0) = lg.legacy_rollos) AS is_clean
    FROM (SELECT DISTINCT partida_id FROM roll_partida) rp
    LEFT JOIN prod pr    ON pr.partida_id = rp.partida_id
    LEFT JOIN rawship rs ON rs.partida_id = rp.partida_id
    LEFT JOIN legacy lg  ON lg.pool_id = COALESCE(
                              (SELECT partida_origen_id FROM mes.partida WHERE id = rp.partida_id),
                              rp.partida_id)
)
SELECT
    CASE WHEN pb.is_clean THEN 'clean (dyed+raw=legacy)'
         WHEN pb.legacy_rollos IS NULL THEN 'no_legacy_rollos'
         ELSE 'mismatch' END AS partida_bucket,
    COUNT(DISTINCT rp.lote_id) AS double_spent_rolls,
    COUNT(DISTINCT rp.partida_id) AS partidas
FROM roll_partida rp
JOIN partida_bucket pb ON pb.partida_id = rp.partida_id
GROUP BY 1
ORDER BY double_spent_rolls DESC;


-- ── §7 · Full per-roll dump (the 193, one row each) — for eyeballing edge cases ─
-- Everything above, joined per roll, so we can inspect the ambiguous/same-timestamp
-- cases individually and confirm the chosen rule handles them.
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
agg AS (
    SELECT raw_ds.lote_id,
           MIN(im.fecha_hora) FILTER (WHERE imt.codigo='PROD_CONSUMO') AS t_consumo,
           MIN(im.fecha_hora) FILTER (WHERE imt.codigo='SERV_EGR')     AS t_egr,
           MIN(im.documento_id) FILTER (WHERE imt.codigo='PROD_CONSUMO') AS consumo_ejec_id,
           MIN(im.documento_id) FILTER (WHERE imt.codigo='SERV_EGR')     AS egr_partida_id
    FROM raw_ds
    JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY raw_ds.lote_id
)
SELECT
    a.lote_id,
    l.cantidad                                              AS peso_kg,
    l.documento_tipo                                        AS lote_origin_doctype,
    a.t_consumo, a.t_egr,
    a.consumo_ejec_id, a.egr_partida_id,
    pp.partida_id                                           AS consumed_into_partida,
    EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
            WHERE c.origen_lote_id = a.lote_id AND c.flg_tenido=true) AS has_dyed_child,
    COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=a.lote_id),0) AS stock_actual
FROM agg a
JOIN inventario.lote l ON l.id = a.lote_id
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.id = a.consumo_ejec_id
LEFT JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
ORDER BY a.lote_id;

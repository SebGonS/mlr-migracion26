-- ============================================================================
-- DIAGNOSTIC · Was the precio_unit meaning switch TEMPORAL? — READ ONLY
-- ============================================================================
-- Context (from the client): legacy was never an invoice system — precio_unit is ONE
-- overloaded field whose MEANING changed over time, constrained by a limited schema:
--   • early  → the DYEING RATE ($/kg)          (sub-10 values)
--   • later  → the ROLL PRICE                  (>=10 values) — operator asked for it
-- So sub-10 and >=10 are DIFFERENT QUANTITIES, not one quantity in two units. The "10"
-- cutoff is likely an artifact of WHEN the meaning flipped, not a real boundary
-- (client: cutoff "historical, PIT unclear").
--
-- If the switch is temporal, MLR rows should separate cleanly by DATE. Nothing writes.
-- ============================================================================

-- ── §1 · MLR rows by year × basis — does the switch show as an era boundary? ──
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
)
SELECT
    EXTRACT(YEAR FROM dsp.fecha_despacho)::int      AS year,
    COUNT(*) FILTER (WHERE dsp.precio_unit <  10)   AS rows_sub10_dyeing_rate,
    COUNT(*) FILTER (WHERE dsp.precio_unit >= 10)   AS rows_ge10_roll_price,
    round(AVG(dsp.precio_unit) FILTER (WHERE dsp.precio_unit <  10)::numeric,2) AS avg_sub10,
    round(AVG(dsp.precio_unit) FILTER (WHERE dsp.precio_unit >= 10)::numeric,2) AS avg_ge10,
    MIN(dsp.fecha_despacho) AS first_desp, MAX(dsp.fecha_despacho) AS last_desp
FROM public.despacho dsp
JOIN public.partida lp ON lp.id = dsp.partida_id
JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
WHERE COALESCE(dsp.flg_elm,false)=false
GROUP BY 1 ORDER BY 1;
-- Clean era boundary (sub10 only early, ge10 only later) ⇒ temporal switch confirmed;
-- classify by DATE, not by the 10 threshold. Overlap ⇒ not purely temporal.


-- ── §2 · Same probe for REGULAR customers (control) ──────────────────────────
-- Regular customers never got the roll-price treatment (zero rows >=10, verified).
-- Their dyeing rate over time is the baseline — confirms the field stayed stable for them.
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
)
SELECT
    EXTRACT(YEAR FROM dsp.fecha_despacho)::int    AS year,
    COUNT(*)                                      AS rows,
    round(AVG(dsp.precio_unit)::numeric,2)        AS avg_precio_kg,
    round(MIN(dsp.precio_unit)::numeric,2)        AS min_precio,
    round(MAX(dsp.precio_unit)::numeric,2)        AS max_precio
FROM public.despacho dsp
JOIN public.partida lp ON lp.id = dsp.partida_id
JOIN cli ON cli.id = lp.cliente_id AND NOT cli.is_mlr
WHERE COALESCE(dsp.flg_elm,false)=false
GROUP BY 1 ORDER BY 1;


-- ── §3 · If temporal: the exact boundary (last sub-10 vs first >=10 per MLR) ──
WITH cli AS (
    SELECT c.id, c.cliente, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
)
SELECT
    cli.cliente,
    MAX(dsp.fecha_despacho) FILTER (WHERE dsp.precio_unit <  10) AS last_dyeing_rate_row,
    MIN(dsp.fecha_despacho) FILTER (WHERE dsp.precio_unit >= 10) AS first_roll_price_row,
    COUNT(*) FILTER (WHERE dsp.precio_unit <  10)                AS n_sub10,
    COUNT(*) FILTER (WHERE dsp.precio_unit >= 10)                AS n_ge10
FROM public.despacho dsp
JOIN public.partida lp ON lp.id = dsp.partida_id
JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
WHERE COALESCE(dsp.flg_elm,false)=false
GROUP BY cli.cliente
ORDER BY n_ge10 DESC;
-- If last_dyeing_rate_row < first_roll_price_row per customer ⇒ clean temporal switch.

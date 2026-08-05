-- ============================================================================
-- DIAGNOSTIC · Is the ">=10 ⇒ per-roll" cutoff right? — READ ONLY
-- ============================================================================
-- Converting MLR precio_unit>=10 by kg/roll yields ~$1.10/kg — HALF the per-kg
-- populations (~1.95–2.05). Economically odd (MLR customers BUY fabric → should be
-- higher, not lower). Either (a) real related-party discount, or (b) those values are
-- legitimate per-KG sale prices and must NOT be converted. Client flagged the cutoff
-- as unverified. Two internal-consistency tests. Nothing writes.
-- ============================================================================

-- ── §1 · Is the MLR precio_unit>=10 group ITSELF bimodal? ─────────────────────
-- If it splits into a low cluster (~10–30, plausible per-KG sale) and a high cluster
-- (~40–135, plausible per-ROLL), then the cutoff of 10 is too low and the group mixes
-- two bases. A single tight cluster ⇒ one basis.
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.nombre ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
)
SELECT
    width_bucket(dsp.precio_unit, 10, 140, 13) AS bucket,
    round(MIN(dsp.precio_unit)::numeric,2)     AS from_precio,
    round(MAX(dsp.precio_unit)::numeric,2)     AS to_precio,
    COUNT(*)                                   AS rows
FROM public.despacho dsp
JOIN public.partida lp ON lp.id = dsp.partida_id
JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
WHERE COALESCE(dsp.flg_elm,false)=false AND dsp.precio_unit >= 10
GROUP BY 1 ORDER BY 1;


-- ── §2 · Same-customer consistency (the decisive test) ───────────────────────
-- For MLR customers that appear in BOTH buckets: their per-kg rate (<10 rows) is the
-- ground truth for what they pay. If the SAME customer's >=10 rows, once converted,
-- land near that rate → conversion is right (per-roll confirmed). If converted lands
-- way below it (e.g. 1.10 vs 2.05) → the >=10 rows are NOT per-roll (reading (b)).
WITH cli AS (
    SELECT c.id, c.nombre, (c.procedencia='MLR' OR c.nombre ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
pt AS (
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
d AS (
    SELECT cli.id AS cliente_id, cli.nombre, dsp.precio_unit,
           (dsp.precio_unit >= 10) AS is_high,
           dsp.precio_unit * pt.pt_rollos / NULLIF(pt.pt_kilos,0) AS converted_kg
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
    LEFT JOIN pt ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
)
SELECT
    nombre,
    COUNT(*) FILTER (WHERE NOT is_high)                                              AS rows_per_kg,
    round(AVG(precio_unit)  FILTER (WHERE NOT is_high)::numeric,2)                   AS their_per_kg_rate,
    COUNT(*) FILTER (WHERE is_high)                                                  AS rows_high,
    round(AVG(precio_unit)  FILTER (WHERE is_high)::numeric,2)                       AS their_raw_high,
    round(AVG(converted_kg) FILTER (WHERE is_high)::numeric,2)                       AS their_converted_kg
FROM d
GROUP BY nombre
HAVING COUNT(*) FILTER (WHERE NOT is_high) > 0 AND COUNT(*) FILTER (WHERE is_high) > 0
ORDER BY rows_high DESC;
-- Read: does their_converted_kg ≈ their_per_kg_rate? (→ per-roll confirmed)
--       or is their_raw_high the sane one? (→ >=10 are per-kg, do NOT convert)

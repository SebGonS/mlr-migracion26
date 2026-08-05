-- ============================================================================
-- DIAGNOSTIC · Do sub-10 and >=10 rows share a PARTIDA? — READ ONLY
-- ============================================================================
-- Client fact: ALL MLR-filtered clients were sold DYED ROLLS, no exceptions.
-- So sub-10 MLR rows are NOT "dyeing service" customers — they are sales where only
-- the dye charge got registered (incomplete record), OR the two row types are additive
-- components of one job. Decisive test:
--   • partida has BOTH sub-10 and >=10   ⇒ ADDITIVE (roll price + dye charge per job)
--   • partida has EITHER, never both     ⇒ ALTERNATIVE recording (only one got stored)
-- Then: is >=10 per-ROLL or per-KG? Economics decide (a dyed-roll SALE must exceed the
-- ~$2.03/kg dyeing cost). Nothing writes.
-- ============================================================================

-- ── §1 · MLR partidas: only sub-10 / only >=10 / BOTH ────────────────────────
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
per_partida AS (
    SELECT dsp.partida_id,
           COUNT(*) FILTER (WHERE dsp.precio_unit <  10) AS n_sub10,
           COUNT(*) FILTER (WHERE dsp.precio_unit >= 10) AS n_ge10
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
    WHERE COALESCE(dsp.flg_elm,false)=false
    GROUP BY dsp.partida_id
)
SELECT
    CASE WHEN n_sub10 > 0 AND n_ge10 > 0 THEN 'BOTH (additive?)'
         WHEN n_ge10  > 0                THEN 'only >=10 (roll/sale price)'
         ELSE                                 'only sub-10 (dye charge only)'
    END                     AS partida_bucket,
    COUNT(*)                AS partidas,
    SUM(n_sub10)            AS rows_sub10,
    SUM(n_ge10)             AS rows_ge10
FROM per_partida
GROUP BY 1 ORDER BY partidas DESC;
-- BOTH ≈ 0  ⇒ alternative recording (your theory) — sub-10 MLR rows are incomplete sales.


-- ── §2 · If BOTH exists, eyeball the pairs (are they additive?) ──────────────
WITH cli AS (
    SELECT c.id, c.cliente, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
pt AS (
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
per_partida AS (
    SELECT dsp.partida_id, cli.cliente,
           COUNT(*) FILTER (WHERE dsp.precio_unit <  10) AS n_sub10,
           COUNT(*) FILTER (WHERE dsp.precio_unit >= 10) AS n_ge10,
           round(AVG(dsp.precio_unit) FILTER (WHERE dsp.precio_unit <  10)::numeric,2) AS avg_sub10,
           round(AVG(dsp.precio_unit) FILTER (WHERE dsp.precio_unit >= 10)::numeric,2) AS avg_ge10
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
    WHERE COALESCE(dsp.flg_elm,false)=false
    GROUP BY dsp.partida_id, cli.cliente
    HAVING COUNT(*) FILTER (WHERE dsp.precio_unit < 10) > 0
       AND COUNT(*) FILTER (WHERE dsp.precio_unit >= 10) > 0
)
SELECT pp.partida_id, pp.cliente, pp.n_sub10, pp.avg_sub10, pp.n_ge10, pp.avg_ge10,
       pt.pt_kilos, pt.pt_rollos,
       round((pt.pt_kilos/NULLIF(pt.pt_rollos,0))::numeric,2) AS kg_per_roll
FROM per_partida pp LEFT JOIN pt ON pt.partida_id = pp.partida_id
ORDER BY pp.partida_id
LIMIT 30;


-- ── §3 · Economics: is >=10 per-ROLL or per-KG? ──────────────────────────────
-- For >=10 rows compute the implied line total BOTH ways and the resulting $/kg.
-- A dyed-roll SALE must exceed the ~2.03/kg dyeing cost to be coherent.
--   per-roll reading: total = precio_unit * rollos_total  → $/kg = total / kg_dispatched
--   per-kg  reading: total = precio_unit * kg_dispatched  → $/kg = precio_unit
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
pt AS (
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
r AS (
    SELECT dsp.precio_unit, dsp.rollos_total,
           pt.pt_kilos / NULLIF(pt.pt_rollos,0)              AS kg_per_roll,
           dsp.rollos_total * (pt.pt_kilos/NULLIF(pt.pt_rollos,0)) AS kg_dispatched
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN cli ON cli.id = lp.cliente_id AND cli.is_mlr
    LEFT JOIN pt ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false AND dsp.precio_unit >= 10
)
SELECT
    COUNT(*)                                                         AS rows,
    round(AVG(precio_unit)::numeric,2)                               AS avg_precio_unit,
    round(AVG(kg_per_roll)::numeric,2)                               AS avg_kg_per_roll,
    -- reading A: per-ROLL → effective $/kg (suspect if < dyeing ~2.03)
    round(AVG(precio_unit / NULLIF(kg_per_roll,0))::numeric,2)       AS A_per_roll_implies_usd_kg,
    round(AVG(precio_unit * rollos_total)::numeric,2)                AS A_avg_line_total,
    -- reading B: per-KG → $/kg is precio_unit itself
    round(AVG(precio_unit)::numeric,2)                               AS B_per_kg_usd_kg,
    round(AVG(precio_unit * kg_dispatched)::numeric,2)               AS B_avg_line_total
FROM r;
-- Read: which line total looks like a real dyed-fabric sale? A (~$490/dispatch,
-- $1.10/kg — below dyeing cost) or B (~$11k/dispatch, $24.67/kg — fabric+dyeing)?

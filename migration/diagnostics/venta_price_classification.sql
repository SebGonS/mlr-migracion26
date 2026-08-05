-- ============================================================================
-- DIAGNOSTIC · Verify the despacho price/ownership classification — READ ONLY
-- ============================================================================
-- Rule (legacy, treat as correct):
--   MLR customer := cliente.procedencia='MLR' OR cliente.nombre ~* '(MLR|Oswaldo)'
--   regular customer            → precio_unit is per-KG  → precio_kg = precio_unit
--   MLR customer & precio_unit < 10  → per-KG            → precio_kg = precio_unit
--   MLR customer & precio_unit >= 10 → per-ROLL          → precio_kg = precio_unit / (kg per roll)
--       kg per roll = pt_kilos / pt_rollos  (produccion_tenido, tenido rows, per partida)
--       ⇒ precio_kg = precio_unit * pt_rollos / pt_kilos
-- Confirms: (1) high precio_unit concentrates in MLR (rule premise holds),
--           (2) converted per-kg values look sane (~2–6), (3) coverage + blind spots.
-- Legacy joins: public.despacho → public.partida.cliente_id → public.cliente. No writes.
-- ============================================================================

--     SELECT * FROM articulo_tipo WHERE id=45
--     SELECT * FROM doc.articulo_tipo_familia
--     SELECT DISTINCT nombre,f.familia_id FROM doc.articulo_tipo_familia f
--     LEFT JOIN articulo_tipo t ON t.id=f.familia_id
--     WHERE t.id=45


-- INSERT INTO doc.articulo_tipo_familia (articulo_tipo_id, familia_id, fyh_cre)
-- SELECT 45, 16, now()

WITH cli AS (   -- MLR flag per legacy customer
    SELECT c.id,
           (c.procedencia = 'MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
pt AS (         -- kg + rolls per partida (tenido), for kg/roll
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
d AS (
    SELECT dsp.id, dsp.partida_id, dsp.rollos_total, dsp.precio_unit, dsp.nfactura,
           COALESCE(cli.is_mlr,false) AS is_mlr,
           pt.pt_kilos, pt.pt_rollos,
           CASE
             WHEN NOT COALESCE(cli.is_mlr,false)      THEN 'per_kg_regular'
             WHEN dsp.precio_unit < 10                THEN 'per_kg_mlr_low'
             ELSE                                          'per_roll_mlr_high'
           END AS basis,
           CASE
             WHEN COALESCE(cli.is_mlr,false) AND dsp.precio_unit >= 10
               THEN dsp.precio_unit * pt.pt_rollos / NULLIF(pt.pt_kilos,0)   -- convert
             ELSE dsp.precio_unit                                            -- already per-kg
           END AS precio_kg_norm
    FROM public.despacho dsp
    LEFT JOIN public.partida lp ON lp.id = dsp.partida_id
    LEFT JOIN cli             ON cli.id = lp.cliente_id
    LEFT JOIN pt              ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false) = false
)
-- ── §1 · concentration: does precio_unit>=10 live in MLR customers? ────────────
SELECT
    is_mlr,
    (precio_unit >= 10) AS precio_ge_10,
    COUNT(*)            AS despacho_rows,
    SUM(rollos_total)   AS rolls
FROM d
GROUP BY 1,2 ORDER BY 1,2;

-- ── §2 · normalized precio_kg distribution per basis (sanity: ~2–6 USD/kg) ─────
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
pt AS (
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
d AS (
    SELECT dsp.id, dsp.partida_id, dsp.rollos_total, dsp.precio_unit, dsp.nfactura,
           COALESCE(cli.is_mlr,false) AS is_mlr, pt.pt_kilos, pt.pt_rollos,
           CASE WHEN NOT COALESCE(cli.is_mlr,false) THEN 'per_kg_regular'
                WHEN dsp.precio_unit < 10 THEN 'per_kg_mlr_low'
                ELSE 'per_roll_mlr_high' END AS basis,
           CASE WHEN COALESCE(cli.is_mlr,false) AND dsp.precio_unit >= 10
                THEN dsp.precio_unit * pt.pt_rollos / NULLIF(pt.pt_kilos,0)
                ELSE dsp.precio_unit END AS precio_kg_norm
    FROM public.despacho dsp
    LEFT JOIN public.partida lp ON lp.id = dsp.partida_id
    LEFT JOIN cli ON cli.id = lp.cliente_id
    LEFT JOIN pt ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false) = false
)
SELECT
    basis,
    COUNT(*)                                                   AS rows,
    round(MIN(precio_kg_norm)::numeric,2)                      AS min_kg,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY precio_kg_norm)::numeric,2) AS median_kg,
    round(AVG(precio_kg_norm)::numeric,2)                      AS avg_kg,
    round(MAX(precio_kg_norm)::numeric,2)                      AS max_kg,
    COUNT(*) FILTER (WHERE precio_kg_norm IS NULL)             AS null_cannot_convert,
    COUNT(*) FILTER (WHERE precio_kg_norm > 12)                AS still_looks_high
FROM d
GROUP BY basis ORDER BY basis;

-- ── §3 · blind spots ──────────────────────────────────────────────────────────
-- (a) regular customers with precio_unit>=10 → treated as per-kg = suspiciously high
-- (b) per-roll rows missing kg (can't convert)
WITH cli AS (
    SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr
    FROM public.cliente c
),
pt AS (
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
d AS (
    SELECT dsp.id, dsp.partida_id, dsp.rollos_total, dsp.precio_unit, dsp.nfactura,
           COALESCE(cli.is_mlr,false) AS is_mlr, pt.pt_kilos, pt.pt_rollos,
           CASE WHEN NOT COALESCE(cli.is_mlr,false) THEN 'per_kg_regular'
                WHEN dsp.precio_unit < 10 THEN 'per_kg_mlr_low'
                ELSE 'per_roll_mlr_high' END AS basis,
           CASE WHEN COALESCE(cli.is_mlr,false) AND dsp.precio_unit >= 10
                THEN dsp.precio_unit * pt.pt_rollos / NULLIF(pt.pt_kilos,0)
                ELSE dsp.precio_unit END AS precio_kg_norm
    FROM public.despacho dsp
    LEFT JOIN public.partida lp ON lp.id = dsp.partida_id
    LEFT JOIN cli ON cli.id = lp.cliente_id
    LEFT JOIN pt ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false) = false
)
SELECT
    COUNT(*) FILTER (WHERE basis='per_kg_regular' AND precio_unit >= 10)                 AS regular_high_precio_SUSPECT,
    COUNT(*) FILTER (WHERE basis='per_roll_mlr_high' AND (pt_kilos IS NULL OR pt_kilos=0)) AS per_roll_missing_kg,
    COUNT(*) FILTER (WHERE precio_unit = 0)                                              AS zero_precio,
    COUNT(DISTINCT partida_id) FILTER (WHERE is_mlr)                                     AS mlr_partidas,
    COUNT(DISTINCT partida_id)                                                           AS total_partidas
FROM d;

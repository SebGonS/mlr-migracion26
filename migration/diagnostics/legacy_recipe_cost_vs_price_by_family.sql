-- ============================================================================
-- LEGACY DIAGNOSTIC — Recipe cost vs billed price, grouped by article-type "family"
-- Run against the LEGACY (public) schema.
--
-- Purpose: test whether the client's price "convergence" is justified.
--   The client priced several articulo_tipo the SAME (one negotiated rate per
--   family). But each articulo_tipo has its own recipe → its own chemical cost.
--   This script computes the ACTUAL recipe cost of every member type and lines
--   it up against the single family price, so you can see how much margin
--   varies under one price. Big spread = the convergence is hiding real cost
--   differences (fragile / possibly losing money on the costlier types).
--
-- Cost formula: faithful copy of legacy generate_complete_recipe:
--     g/L → cantidad * 5  / 1000 * precio_prom_kg_usd
--     %   → cantidad * 10 / 1000 * precio_prom_kg_usd
--   (legacy medida_enum only has 'g/L' and '%'; no factor_stock existed.)
--
-- Family normalization: faithful copy of the legacy price-lookup CASE,
--   including the client-specific rule (cliente_id IN (1,11,22) → bucket 20).
--
-- Price match: legacy strict equality on color_x_cliente_id + tenido_id + fibra
--   + tipo_articulo_id(=family bucket) + adicional(antipilling), activo = 1.
--
-- Caveat: insumos with NULL precio_prom_kg_usd are counted as 0 here (so cost
--   is understated for those recipes) and flagged via insumos_sin_precio.
-- ============================================================================

WITH
-- 1) Chemical cost per approved recipe (one row per receta2)
recipe_cost AS (
    SELECT
        r.id                       AS receta_id,
        r.color_x_cliente_id,
        r.tipo_articulo_id,
        r.fibra,
        r.tenido_id,
        r.flg_antipilling,
        SUM(
            CASE i.medida
                WHEN 'g/L' THEN (5.0  * ri.cantidad) / 1000.0
                WHEN '%'   THEN (10.0 * ri.cantidad) / 1000.0
                ELSE 0
            END * COALESCE(i.precio_prom_kg_usd, 0)
        )                                                   AS costo_kg,
        COUNT(*) FILTER (WHERE i.precio_prom_kg_usd IS NULL) AS insumos_sin_precio
    FROM public.receta2 r
    JOIN public.receta_x_insumo ri ON ri.receta_id = r.id
    JOIN public.insumo          i  ON i.id         = ri.insumo_id
    WHERE r.flg_produccion = true          -- approved/production recipes only
    GROUP BY r.id, r.color_x_cliente_id, r.tipo_articulo_id,
             r.fibra, r.tenido_id, r.flg_antipilling
),

-- 2) Attach client + the legacy pricing FAMILY (bucket)
recipe_fam AS (
    SELECT
        rc.*,
        cxc.cliente_id,
        CASE
            WHEN cxc.cliente_id IN (1,11,22)
                 AND rc.tipo_articulo_id IN (4,8,9,10,11,12,14,15,17,18,20) THEN 20
            WHEN rc.tipo_articulo_id IN (4,9,18)    THEN 18
            WHEN rc.tipo_articulo_id IN (8,12)      THEN 12
            WHEN rc.tipo_articulo_id IN (10,14,17)  THEN 14
            WHEN rc.tipo_articulo_id IN (16,22,23)  THEN 16
            ELSE rc.tipo_articulo_id
        END AS familia
    FROM recipe_cost rc
    JOIN public.color_x_cliente cxc ON cxc.id = rc.color_x_cliente_id
),

-- 3) Collapse to one cost per (pricing cell, article type)
cell_tipo AS (
    SELECT
        color_x_cliente_id, tenido_id, fibra, flg_antipilling, familia,
        tipo_articulo_id,
        AVG(costo_kg)          AS costo_kg,
        SUM(insumos_sin_precio) AS insumos_sin_precio
    FROM recipe_fam
    GROUP BY color_x_cliente_id, tenido_id, fibra, flg_antipilling, familia, tipo_articulo_id
),

-- 4) Attach the single billed price for the family
priced AS (
    SELECT
        ct.*,
        cp.precio_tenido
    FROM cell_tipo ct
    LEFT JOIN public.catalogo_precios cp
           ON cp.color_x_cliente_id = ct.color_x_cliente_id
          AND cp.tenido_id          = ct.tenido_id
          AND cp.fibra              = ct.fibra
          AND cp.tipo_articulo_id   = ct.familia
          AND cp.activo             = 1
          AND (COALESCE(cp.adicional_id, 0) > 0) = ct.flg_antipilling
)

-- ============================================================================
-- OUTPUT B (main) — Family spread: where >1 article type shares ONE price
-- High spread_pct_de_precio / wide margin range = convergence not justified.
-- ============================================================================
SELECT
    cli.cliente,
    co.color,
    te.tenido,
    p.fibra,
    p.flg_antipilling                                          AS antipilling,
    ta.nombre                                           AS familia,
    COUNT(*)                                                   AS tipos_en_familia,
    array_agg(p.tipo_articulo_id ORDER BY p.tipo_articulo_id)  AS tipos,
    ROUND(MIN(p.costo_kg), 4)                                  AS costo_min,
    ROUND(MAX(p.costo_kg), 4)                                  AS costo_max,
    ROUND(MAX(p.costo_kg) - MIN(p.costo_kg), 4)                AS costo_spread,
    MAX(p.precio_tenido)                                       AS precio_familia,
    ROUND((MAX(p.costo_kg) - MIN(p.costo_kg))
          / NULLIF(MAX(p.precio_tenido), 0) * 100, 1)          AS spread_pct_de_precio,
    -- best-case margin (cheapest member) vs worst-case margin (costliest member)
    ROUND((MAX(p.precio_tenido) - MIN(p.costo_kg))
          / NULLIF(MAX(p.precio_tenido), 0) * 100, 1)          AS margen_mejor_pct,
    ROUND((MAX(p.precio_tenido) - MAX(p.costo_kg))
          / NULLIF(MAX(p.precio_tenido), 0) * 100, 1)          AS margen_peor_pct,
    SUM(p.insumos_sin_precio)                                  AS insumos_sin_precio
FROM priced p
JOIN public.color_x_cliente cxc ON cxc.id = p.color_x_cliente_id
JOIN public.cliente         cli ON cli.id = cxc.cliente_id
JOIN public.color           co  ON co.id  = cxc.color_id
LEFT JOIN public.tenido     te  ON te.id  = p.tenido_id
LEFT JOIN public.articulo_tipo ta ON ta.id = p.familia
GROUP BY cli.cliente, co.color, te.tenido, p.fibra,
         p.flg_antipilling, ta.nombre, p.familia
HAVING COUNT(*) > 1                          -- only real families (price shared across types)
ORDER BY spread_pct_de_precio DESC NULLS LAST;


-- ============================================================================
-- OUTPUT A (drill-down) — one row per article type, its own cost vs family price.
-- Uncomment to inspect a specific family from Output B.
-- ============================================================================
-- SELECT
--     cli.cliente, co.color, te.tenido, p.fibra, p.flg_antipilling AS antipilling,
--     ta_fam.tipo_articulo AS familia,
--     ta_tipo.tipo_articulo AS articulo_tipo,
--     p.tipo_articulo_id,
--     ROUND(p.costo_kg, 4)   AS costo_kg,
--     p.precio_tenido        AS precio_familia,
--     ROUND((p.precio_tenido - p.costo_kg) / NULLIF(p.precio_tenido,0) * 100, 1) AS margen_pct,
--     p.insumos_sin_precio
-- FROM priced p
-- JOIN public.color_x_cliente cxc ON cxc.id = p.color_x_cliente_id
-- JOIN public.cliente cli ON cli.id = cxc.cliente_id
-- JOIN public.color   co  ON co.id  = cxc.color_id
-- LEFT JOIN public.tenido te ON te.id = p.tenido_id
-- LEFT JOIN public.articulo_tipo ta_fam  ON ta_fam.id  = p.familia
-- LEFT JOIN public.articulo_tipo ta_tipo ON ta_tipo.id = p.tipo_articulo_id
-- WHERE p.familia = 18      -- <-- set the family bucket you want to inspect
-- ORDER BY cli.cliente, co.color, te.tenido, p.tipo_articulo_id;
SELECT * FROM articulo_tipo;
SELECT * FROm articulo
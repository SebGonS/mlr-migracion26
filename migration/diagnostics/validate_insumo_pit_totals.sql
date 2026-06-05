-- ─────────────────────────────────────────────────────────────────────────────
-- PIT (Point-In-Time) running total comparison — insumo ledger vs legacy
--
-- Computes daily cumulative balance from both sides up to the migration
-- cutoff, then finds the FIRST date per item where they diverge.
-- That date is where a movement has a wrong fecha_hora.
--
-- Legacy sources:
--   Ingress  → public.inventario (fyh_cre::date)
--   Egress   → public.salida_inventario_detalle_x_stock (sdxs.fecha::date)
--
-- New ledger:
--   item_movimientos filtered to migrated rows (fyh_cre < cutoff)
--   movement types: COMPRA_ING, AJUSTE_POS, MUESTRA_ING (factor=+1)
--                   PROD_CONSUMO, AJUSTE_NEG, MUESTRA_EGR (factor=-1)
--
-- Usage:
--   Query 1 — first_divergence: one row per item, shows which day the
--             running totals first split. If empty, migration is clean.
--   Query 2 — full_timeline: drill into a specific item to see every day.
--             Set v_item_id to the item.id you want to inspect.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Shared parameters ────────────────────────────────────────────────────────
-- Adjust cutoff to the actual go-live date (movements fyh_cre >= cutoff are
-- live-system rows and excluded from both sides of the comparison).
-- ─────────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════════
-- Query 1 — first divergence date per item
-- ══════════════════════════════════════════════════════════════════════════════

WITH cutoff AS (
    SELECT '2025-09-25 15:00:00+00'::TIMESTAMPTZ AS ts
),

-- ── Legacy side ───────────────────────────────────────────────────────────────
legacy_ingress AS (
    SELECT
        COALESCE(ixp.insumo_id, inv.insumo_id)      AS item_id,
        inv.fyh_cre::date                            AS fecha,
        SUM(inv.cantidad)                            AS qty
    FROM public.inventario inv
    LEFT JOIN public.insumo_x_proveedor ixp ON ixp.id = inv.insumo_x_proveedor_id
    CROSS JOIN cutoff
    WHERE inv.cantidad > 0
      AND COALESCE(ixp.insumo_id, inv.insumo_id) IS NOT NULL
      AND inv.fyh_cre < cutoff.ts
    GROUP BY 1, 2
),
legacy_egress AS (
    SELECT
        l.item_id,
        sdxs.fecha::date                             AS fecha,
        -SUM(sdxs.cantidad::numeric(12,4))           AS qty
    FROM public.salida_inventario si
    JOIN public.salida_inventario_detalle sid
        ON sid.salida_inventario_id = si.id
    JOIN public.salida_inventario_detalle_x_stock sdxs
        ON sdxs.salida_inventario_detalle_id = sid.id
    JOIN inventario.lote l ON l.id = sdxs.inventario_id
    CROSS JOIN cutoff
    WHERE si.estado = 'aprobado'
      AND sdxs.fecha < cutoff.ts
    GROUP BY 1, 2
),
legacy_daily AS (
    SELECT item_id, fecha, SUM(qty) AS qty
    FROM (SELECT * FROM legacy_ingress UNION ALL SELECT * FROM legacy_egress) x
    GROUP BY 1, 2
),
legacy_running AS (
    SELECT
        item_id,
        fecha,
        ROUND(SUM(SUM(qty)) OVER (PARTITION BY item_id ORDER BY fecha), 4) AS running_total
    FROM legacy_daily
    GROUP BY item_id, fecha
),

-- ── New ledger side ───────────────────────────────────────────────────────────
new_daily AS (
    SELECT
        im.item_id,
        im.fecha_hora::date                          AS fecha,
        SUM(im.cantidad * imt.factor)                AS qty
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    CROSS JOIN cutoff
    WHERE imt.codigo IN (
        'COMPRA_ING', 'AJUSTE_POS', 'MUESTRA_ING',
        'PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR'
    )
      AND im.fyh_cre < cutoff.ts
    GROUP BY 1, 2
),
new_running AS (
    SELECT
        item_id,
        fecha,
        ROUND(SUM(SUM(qty)) OVER (PARTITION BY item_id ORDER BY fecha), 4) AS running_total
    FROM new_daily
    GROUP BY item_id, fecha
),

-- ── Day-by-day comparison ─────────────────────────────────────────────────────
comparison AS (
    SELECT
        COALESCE(l.item_id, n.item_id)                  AS item_id,
        COALESCE(l.fecha,   n.fecha)                    AS fecha,
        COALESCE(l.running_total, 0)                    AS legacy_running,
        COALESCE(n.running_total, 0)                    AS new_running,
        ABS(COALESCE(l.running_total, 0)
          - COALESCE(n.running_total, 0))               AS diff
    FROM legacy_running l
    FULL JOIN new_running n
        ON n.item_id = l.item_id AND n.fecha = l.fecha
)

-- First day the running totals diverge per item (insumos only — rolls excluded)
SELECT DISTINCT ON (c.item_id)
    i.codigo                        AS item,
    c.fecha                         AS first_divergence_date,
    c.legacy_running                AS legacy_total_at_split,
    c.new_running                   AS ledger_total_at_split,
    c.diff                          AS gap_at_split
FROM comparison c
JOIN item i ON i.id = c.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo != 'ROLLO'
WHERE c.diff > 0.01
ORDER BY c.item_id, c.fecha
;


-- ══════════════════════════════════════════════════════════════════════════════
-- Query 2 — full daily timeline for one item (drill-down)
-- Set v_item_id to the item.id you want to inspect.
-- ══════════════════════════════════════════════════════════════════════════════

WITH v AS (SELECT 24 AS v_item_id),   -- ← EDIT THIS
cutoff AS (
    SELECT '2025-09-25 15:00:00+00'::TIMESTAMPTZ AS ts
),

legacy_ingress AS (
    SELECT
        COALESCE(ixp.insumo_id, inv.insumo_id)      AS item_id,
        inv.fyh_cre::date                            AS fecha,
        SUM(inv.cantidad)                            AS qty
    FROM public.inventario inv
    LEFT JOIN public.insumo_x_proveedor ixp ON ixp.id = inv.insumo_x_proveedor_id
    CROSS JOIN cutoff, v
    WHERE inv.cantidad > 0
      AND COALESCE(ixp.insumo_id, inv.insumo_id) = v.v_item_id
      AND inv.fyh_cre < cutoff.ts
    GROUP BY 1, 2
),
legacy_egress AS (
    SELECT
        l.item_id,
        sdxs.fecha::date                             AS fecha,
        -SUM(sdxs.cantidad::numeric(12,4))           AS qty
    FROM public.salida_inventario si
    JOIN public.salida_inventario_detalle sid
        ON sid.salida_inventario_id = si.id
    JOIN public.salida_inventario_detalle_x_stock sdxs
        ON sdxs.salida_inventario_detalle_id = sid.id
    JOIN inventario.lote l ON l.id = sdxs.inventario_id
    CROSS JOIN cutoff, v
    WHERE si.estado = 'aprobado'
      AND sdxs.fecha < cutoff.ts
      AND l.item_id = v.v_item_id
    GROUP BY 1, 2
),
legacy_daily AS (
    SELECT item_id, fecha, SUM(qty) AS qty
    FROM (SELECT * FROM legacy_ingress UNION ALL SELECT * FROM legacy_egress) x
    GROUP BY 1, 2
),
legacy_running AS (
    SELECT
        fecha,
        SUM(qty)                                                            AS day_qty,
        ROUND(SUM(SUM(qty)) OVER (ORDER BY fecha), 4)                      AS running_total
    FROM legacy_daily
    GROUP BY fecha
),

new_daily AS (
    SELECT
        im.fecha_hora::date                          AS fecha,
        SUM(im.cantidad * imt.factor)                AS qty
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    CROSS JOIN cutoff, v
    WHERE imt.codigo IN (
        'COMPRA_ING', 'AJUSTE_POS', 'MUESTRA_ING',
        'PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR'
    )
      AND im.fyh_cre < cutoff.ts
      AND im.item_id = v.v_item_id
    GROUP BY 1
),
new_running AS (
    SELECT
        fecha,
        SUM(qty)                                                            AS day_qty,
        ROUND(SUM(SUM(qty)) OVER (ORDER BY fecha), 4)                      AS running_total
    FROM new_daily
    GROUP BY fecha
)

SELECT
    COALESCE(l.fecha, n.fecha)              AS fecha,
    ROUND(COALESCE(l.day_qty,      0), 4)  AS legacy_day,
    ROUND(COALESCE(n.day_qty,      0), 4)  AS ledger_day,
    ROUND(COALESCE(l.running_total,0), 4)  AS legacy_running,
    ROUND(COALESCE(n.running_total,0), 4)  AS ledger_running,
    ROUND(ABS(COALESCE(l.running_total,0)
            - COALESCE(n.running_total,0)), 4) AS diff,
    CASE WHEN ABS(COALESCE(l.running_total,0)
               - COALESCE(n.running_total,0)) > 0.01
         THEN '⚠ SPLIT' ELSE '' END        AS status
FROM legacy_running l
FULL JOIN new_running n USING (fecha)
ORDER BY fecha
;

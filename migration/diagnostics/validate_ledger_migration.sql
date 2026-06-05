-- ─────────────────────────────────────────────────────────────────────────────
-- LEDGER MIGRATION VALIDATION
--
-- Purpose: verify that migrated item_movimientos rows have correct timestamps
-- and quantities vs the legacy source tables.
--
-- Run the sections in order:
--   A  Identify migration timestamp clusters (fyh_cre buckets, not real timestamps)
--   B  Detect movements still stuck at a migration-run timestamp
--   C  Ingress quantity check  (new ledger vs public.inventario)
--   D  Egress quantity check   (new ledger vs salida_inventario_detalle_x_stock)
--   E  Net stock check         (A-B balance vs item_saldo)
--   F  Per-item timeline       (drill-down for a single item)
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION A  — Migration timestamp clusters
-- Shows all distinct fyh_cre values that represent bulk migration runs (≥ 50 rows
-- sharing the same second-truncated timestamp).
-- Use this to discover all migration-run timestamps to feed into Section B.
-- ═══════════════════════════════════════════════════════════════════════════════

SELECT
    date_trunc('second', im.fyh_cre)                                    AS migration_ts,
    COUNT(*)                                                             AS total_rows,
    COUNT(DISTINCT im.item_id)                                          AS items_affected,
    array_agg(DISTINCT imt.codigo ORDER BY imt.codigo)                  AS movement_types,
    MIN(im.fecha_hora)                                                   AS earliest_fecha_hora,
    MAX(im.fecha_hora)                                                   AS latest_fecha_hora,
    -- flag: if fecha_hora values also cluster at the same timestamp it means
    -- historical dates were not recovered (the "now()" bug)
    COUNT(*) FILTER (WHERE date_trunc('second', im.fecha_hora)
                         = date_trunc('second', im.fyh_cre))            AS rows_with_fecha_eq_fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
GROUP BY 1
HAVING COUNT(*) >= 50
ORDER BY total_rows DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION B  — Movements still stuck at a migration-run timestamp
--
-- For egress movement types (PROD_CONSUMO, AJUSTE_NEG, MUESTRA_EGR):
--   fecha_hora should be the real legacy transaction date (sdxs.fecha),
--   NOT the migration run timestamp.
--
-- For ingress movement types (COMPRA_ING, AJUSTE_POS, MUESTRA_ING):
--   fecha_hora should be inventario.fyh_cre (already a real date in legacy).
--
-- The known patched migration timestamp is '2025-09-11 22:53:28.212517+00'.
-- Add any others you find in Section A to the IN list below.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH migration_timestamps AS (
    -- Extend this list with any other timestamps found in Section A
    SELECT unnest(ARRAY[
        '2025-09-11 22:53:28.212517+00'::TIMESTAMPTZ
        -- add more here if Section A shows other clusters
    ]) AS ts
)
SELECT
    imt.codigo                          AS mov_type,
    im.item_id,
    i.codigo                            AS item,
    im.fecha_hora,
    im.fyh_cre,
    COUNT(*)                            AS n_rows,
    SUM(im.cantidad)                    AS total_qty
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
JOIN item i ON i.id = im.item_id
WHERE date_trunc('second', im.fecha_hora) IN (SELECT ts FROM migration_timestamps)
GROUP BY 1, 2, 3, 4, 5
ORDER BY imt.codigo, im.item_id, im.fecha_hora;

-- Quick summary: how many rows per type still sit at a migration timestamp
WITH migration_timestamps AS (
    SELECT unnest(ARRAY[
        '2025-09-11 22:53:28.212517+00'::TIMESTAMPTZ
    ]) AS ts
)
SELECT
    imt.codigo                                  AS mov_type,
    COUNT(*)                                    AS stuck_rows,
    COUNT(DISTINCT im.item_id)                  AS affected_items
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE date_trunc('second', im.fecha_hora) IN (SELECT ts FROM migration_timestamps)
GROUP BY 1
ORDER BY stuck_rows DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION C  — Ingress quantity check  (insumo items only)
--
-- Expected: SUM ingress movements = SUM public.inventario.cantidad per item.
-- Discrepancies > 0.01 kg are flagged.
-- Roll lotes (documento_tipo='PARTIDA') are excluded — their ingress is SERV_ING
-- which has no equivalent in public.inventario.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH legacy_ingress AS (
    SELECT
        COALESCE(ixp.insumo_id, inv.insumo_id)          AS item_id,
        SUM(inv.cantidad)                                AS ingress_qty
    FROM public.inventario inv
    LEFT JOIN public.insumo_x_proveedor ixp ON ixp.id = inv.insumo_x_proveedor_id
    WHERE inv.cantidad > 0
      AND COALESCE(ixp.insumo_id, inv.insumo_id) IS NOT NULL
    GROUP BY 1
),
new_ingress AS (
    SELECT
        im.item_id,
        SUM(im.cantidad)                                AS ingress_qty
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE imt.codigo IN ('COMPRA_ING', 'AJUSTE_POS', 'MUESTRA_ING')
    GROUP BY 1
)
SELECT
    i.codigo                                            AS item,
    ROUND(COALESCE(li.ingress_qty, 0), 4)              AS legacy_ingress,
    ROUND(COALESCE(ni.ingress_qty, 0), 4)              AS new_ingress,
    ROUND(COALESCE(li.ingress_qty, 0)
        - COALESCE(ni.ingress_qty, 0), 4)              AS diff,
    CASE
        WHEN li.ingress_qty IS NULL THEN 'NEW ONLY – no legacy source'
        WHEN ni.ingress_qty IS NULL THEN 'MISSING – in legacy but not migrated'
        WHEN ABS(li.ingress_qty - ni.ingress_qty) > 0.01 THEN 'MISMATCH'
        ELSE 'OK'
    END                                                AS status
FROM legacy_ingress li
FULL JOIN new_ingress ni ON ni.item_id = li.item_id
JOIN item i ON i.id = COALESCE(li.item_id, ni.item_id)
WHERE ABS(COALESCE(li.ingress_qty, 0) - COALESCE(ni.ingress_qty, 0)) > 0.01
   OR li.item_id IS NULL
   OR ni.item_id IS NULL
ORDER BY ABS(COALESCE(li.ingress_qty, 0) - COALESCE(ni.ingress_qty, 0)) DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION D  — Egress quantity check  (insumo items only)
--
-- Expected: SUM egress movements = SUM sdxs.cantidad per item (approved salidas).
-- ═══════════════════════════════════════════════════════════════════════════════

WITH legacy_egress AS (
    SELECT
        l.item_id,
        SUM(sdxs.cantidad::numeric(12,4))               AS egress_qty
    FROM public.salida_inventario si
    JOIN public.salida_inventario_detalle sid
        ON sid.salida_inventario_id = si.id
    JOIN public.salida_inventario_detalle_x_stock sdxs
        ON sdxs.salida_inventario_detalle_id = sid.id
    JOIN inventario.lote l ON l.id = sdxs.inventario_id
    WHERE si.estado = 'aprobado'
      AND sdxs.cantidad > 0
    GROUP BY 1
),
new_egress AS (
    SELECT
        im.item_id,
        SUM(im.cantidad)                                AS egress_qty
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
    GROUP BY 1
)
SELECT
    i.codigo                                            AS item,
    ROUND(COALESCE(le.egress_qty, 0), 4)               AS legacy_egress,
    ROUND(COALESCE(ne.egress_qty, 0), 4)               AS new_egress,
    ROUND(COALESCE(le.egress_qty, 0)
        - COALESCE(ne.egress_qty, 0), 4)               AS diff,
    CASE
        WHEN le.egress_qty IS NULL THEN 'NEW ONLY – no legacy source'
        WHEN ne.egress_qty IS NULL THEN 'MISSING – in legacy but not migrated'
        WHEN ABS(le.egress_qty - ne.egress_qty) > 0.01 THEN 'MISMATCH'
        ELSE 'OK'
    END                                                AS status
FROM legacy_egress le
FULL JOIN new_egress ne ON ne.item_id = le.item_id
JOIN item i ON i.id = COALESCE(le.item_id, ne.item_id)
WHERE ABS(COALESCE(le.egress_qty, 0) - COALESCE(ne.egress_qty, 0)) > 0.01
   OR le.item_id IS NULL
   OR ne.item_id IS NULL
ORDER BY ABS(COALESCE(le.egress_qty, 0) - COALESCE(ne.egress_qty, 0)) DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION E  — Net stock check
--
-- Verifies: SUM(ingress) - SUM(egress) from item_movimientos
--   matches inventario.item_saldo.cantidad_actual per item.
-- Large discrepancies usually mean a duplicate or missing migration movement.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH ledger_balance AS (
    SELECT
        im.item_id,
        SUM(im.cantidad * imt.factor)                   AS ledger_balance
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE imt.codigo IN (
        'COMPRA_ING', 'AJUSTE_POS', 'MUESTRA_ING',
        'PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR'
    )
    GROUP BY 1
)
SELECT
    i.codigo                                            AS item,
    ROUND(lb.ledger_balance, 4)                        AS ledger_balance,
    ROUND(isa2.cantidad_actual, 4)                     AS saldo_actual,
    ROUND(lb.ledger_balance - isa2.cantidad_actual, 4) AS diff
FROM ledger_balance lb
JOIN inventario.item_saldo isa2 ON isa2.item_id = lb.item_id
JOIN item i ON i.id = lb.item_id
WHERE ABS(lb.ledger_balance - isa2.cantidad_actual) > 0.01
ORDER BY ABS(lb.ledger_balance - isa2.cantidad_actual) DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION F  — Per-item ledger drill-down
--
-- Shows the full movement timeline for one item.
-- Change v_item_id to investigate a specific item.
-- Rows flagged as SUSPECT_TIMESTAMP have fecha_hora matching a known migration
-- run timestamp — those may need correction if the type is an egress movement.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH v AS (
    SELECT 24 AS v_item_id   -- ← EDIT THIS  (use item.id)
),
migration_timestamps AS (
    SELECT unnest(ARRAY[
        '2025-09-11 22:53:28.212517+00'::TIMESTAMPTZ
    ]) AS ts
)
SELECT
    im.id                                               AS mov_id,
    im.fecha_hora,
    im.fyh_cre,
    imt.codigo                                         AS tipo,
    im.cantidad * imt.factor                           AS neta,
    SUM(im.cantidad * imt.factor)
        OVER (ORDER BY im.fecha_hora, im.id)           AS saldo,
    im.lote_id,
    im.doc_movimiento_id,
    im.documento_tipo,
    im.documento_id,
    -- Flag: fecha_hora is stuck at a known migration-run timestamp
    CASE WHEN date_trunc('second', im.fecha_hora) IN (SELECT ts FROM migration_timestamps)
         THEN '⚠ SUSPECT'
         ELSE ''
    END                                                AS timestamp_flag,
    -- Flag: fecha_hora = fyh_cre (suspect for egress movements where date should differ)
    CASE WHEN im.fecha_hora = im.fyh_cre
          AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
         THEN '⚠ EGR_TS_EQ_CRE'
         ELSE ''
    END                                                AS egress_flag
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id, v
WHERE im.item_id = v.v_item_id
ORDER BY im.fecha_hora, im.id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION G  — Timestamp distribution per item (for suspect items)
--
-- For a given item, shows all distinct fecha_hora values used on egress movements
-- alongside their legacy sdxs.fecha counterparts.
-- If fecha_hora != sdxs.fecha on any row, the timestamp fix may be incomplete.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH v AS (
    SELECT 24 AS v_item_id   -- ← EDIT THIS
)
SELECT
    im.id                                               AS mov_id,
    imt.codigo                                         AS tipo,
    im.cantidad                                        AS qty,
    im.fecha_hora                                      AS fecha_hora_current,
    sdxs.fecha                                         AS fecha_hora_expected,
    sdxs.fecha = im.fecha_hora                         AS ts_ok,
    si.id                                              AS salida_id,
    si.fyh_solicitud_tz                                AS salida_solicitud_ts
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
-- Recover legacy source row via lote_id + cantidad fingerprint
JOIN public.salida_inventario_detalle_x_stock sdxs
    ON sdxs.inventario_id = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN public.salida_inventario_detalle sid
    ON sid.id = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si
    ON si.id = sid.salida_inventario_id
    AND si.estado = 'aprobado', v
WHERE im.item_id = v.v_item_id
ORDER BY im.fecha_hora, im.id;
 
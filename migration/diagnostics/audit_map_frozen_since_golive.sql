-- ═══════════════════════════════════════════════════════════════════════════════
-- Audit: is inventario.item_valoracion (MAP) frozen since go-live?
-- ───────────────────────────────────────────────────────────────────────────────
-- THEORY (from code reading, needs data confirmation):
--   doc.registrar_entrega_compra is the only path that posts purchase movements,
--   and it never sets item_movimientos.precio_unitario. The MAP trigger
--   (inventario.fn_trg_actualizar_map, live version in patches/28) returns on
--   line 1 when precio_unitario IS NULL. So no COMPRA_ING has ever updated
--   item_valoracion — contradicting 11_data_migration.sql:1655 ("Going forward
--   the trigger handles new COMPRA_ING movements").
--
--   Meanwhile PROD_CONSUMO (mes.sql:945) DOES stamp precio_unitario = current MAP,
--   so the valuation ledger is debited on egress and never credited on ingress.
--
-- READ-ONLY. No writes. Safe to run on production.
--   psql "$CONN" -f migration/diagnostics/audit_map_frozen_since_golive.sql
-- ═══════════════════════════════════════════════════════════════════════════════

\echo ''
\echo '=== A. SMOKING GUN: COMPRA_ING movements that carry a price ==================='
\echo '    Theory predicts: con_precio = 0. Any non-zero kills the theory.'
SELECT
    COUNT(*)                                             AS compra_ing_total,
    COUNT(im.precio_unitario)                            AS con_precio,
    COUNT(*) - COUNT(im.precio_unitario)                 AS sin_precio,
    MIN(im.fecha_hora)::date                             AS primera,
    MAX(im.fecha_hora)::date                             AS ultima
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE imt.codigo = 'COMPRA_ING';

\echo ''
\echo '=== B. Has item_valoracion been touched since the go-live seed? ==============='
\echo '    Theory predicts: nearly every row still sits at its 2026-05-25 seed.'
SELECT
    CASE
        WHEN fyh_mod <= '2026-05-25 15:27:52+00'::timestamptz THEN 'seed (nunca actualizado)'
        ELSE 'modificado post go-live'
    END                          AS estado,
    COUNT(*)                     AS items,
    MIN(fyh_mod)                 AS mas_antiguo,
    MAX(fyh_mod)                 AS mas_reciente
FROM inventario.item_valoracion
GROUP BY 1
ORDER BY 2 DESC;

\echo ''
\echo '=== C. MAGNITUDE: frozen MAP vs latest actual purchase price =================='
\echo '    How wrong is costing today? Top 25 by absolute drift.'
WITH ultimo_precio AS (
    SELECT DISTINCT ON (cd.item_id)
           cd.item_id,
           cd.precio_unitario  AS precio_ultima_compra,
           c.fyh_cre           AS fecha_ultima_compra
    FROM doc.compra_detalle cd
    JOIN doc.compra c ON c.id = cd.compra_id
    WHERE c.fyh_elm IS NULL
      AND cd.precio_unitario > 0
    ORDER BY cd.item_id, c.fyh_cre DESC
)
SELECT
    i.codigo,
    LEFT(i.nombre, 34)                                        AS item,
    iv.precio_promedio                                        AS map_congelado,
    up.precio_ultima_compra                                   AS precio_real,
    ROUND(up.precio_ultima_compra - iv.precio_promedio, 4)    AS drift_abs,
    CASE WHEN iv.precio_promedio > 0
         THEN ROUND(100.0 * (up.precio_ultima_compra - iv.precio_promedio)
                    / iv.precio_promedio, 1)
    END                                                       AS drift_pct,
    up.fecha_ultima_compra::date                              AS ult_compra
FROM inventario.item_valoracion iv
JOIN item i           ON i.id = iv.item_id
JOIN ultimo_precio up ON up.item_id = iv.item_id
WHERE up.precio_ultima_compra IS DISTINCT FROM iv.precio_promedio
ORDER BY ABS(up.precio_ultima_compra - iv.precio_promedio) DESC
LIMIT 25;

\echo ''
\echo '=== D. DRAIN: item_valoracion.stock_qty vs real physical stock ================'
\echo '    Consumption debits stock_qty; purchases never credit it. Expect qty to'
\echo '    trail item_saldo, and stock_valorado to clamp toward 0 while stock exists.'
WITH fisico AS (
    SELECT item_id, SUM(cantidad_actual) AS qty_real
    FROM inventario.item_saldo
    GROUP BY item_id
)
SELECT
    i.codigo,
    LEFT(i.nombre, 34)                          AS item,
    ROUND(f.qty_real, 3)                        AS stock_fisico,
    ROUND(iv.stock_qty, 3)                      AS valoracion_qty,
    ROUND(f.qty_real - iv.stock_qty, 3)         AS faltante,
    iv.precio_promedio                          AS map,
    iv.stock_valorado,
    CASE WHEN iv.stock_valorado = 0 AND f.qty_real > 0
         THEN 'VALOR EN CERO CON STOCK FISICO' END AS alerta
FROM inventario.item_valoracion iv
JOIN item i   ON i.id = iv.item_id
JOIN fisico f ON f.item_id = iv.item_id
WHERE ABS(f.qty_real - iv.stock_qty) > 0.001
ORDER BY (f.qty_real - iv.stock_qty) DESC
LIMIT 25;

\echo ''
\echo '=== E. Rollup: how widespread? ================================================'
WITH fisico AS (
    SELECT item_id, SUM(cantidad_actual) AS qty_real
    FROM inventario.item_saldo GROUP BY item_id
)
SELECT
    COUNT(*)                                                          AS items_valorizados,
    COUNT(*) FILTER (WHERE ABS(f.qty_real - iv.stock_qty) > 0.001)    AS con_drift_qty,
    COUNT(*) FILTER (WHERE iv.stock_valorado = 0 AND f.qty_real > 0)  AS valor_cero_con_stock,
    ROUND(SUM(iv.stock_valorado), 2)                                  AS valor_total_reportado
FROM inventario.item_valoracion iv
JOIN fisico f ON f.item_id = iv.item_id;

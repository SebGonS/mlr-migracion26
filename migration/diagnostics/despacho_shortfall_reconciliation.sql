-- ============================================================================
-- DIAGNOSTIC · Legacy despacho vs already-dispatched vs in-stock (per pool) — READ ONLY
-- ============================================================================
-- Confirms stock is "rightish" and sizes the remaining dispatch. Per POOL
-- (original + reworks, COALESCE(partida_origen_id,id)):
--   despacho_total     = SUM(public.despacho.rollos_total) WHERE NOT flg_elm  (ground truth)
--   dispatched_dyed    = dyed rolls with SERV_EGR|VENTA_EGR on documento_tipo='entrega'
--   instock_dyed       = dyed rolls with lote_saldo.cantidad_actual > 0
-- Outcome per pool:
--   shortfall = despacho_total - dispatched_dyed
--     > 0 & instock covers it   → dispatch the shortfall from stock (the real work)
--     <= 0                       → fully dispatched; any in-stock = genuine leftover
--     > 0 & instock short        → STOCK PROBLEM (can't cover what legacy shipped)
-- despacho keys on the legacy ORIGINAL partida; reworks pool up via partida_origen_id.
-- go-live '2026-05-25 15:27:52+00'. Nothing writes.
-- ============================================================================

WITH desp AS (
    SELECT partida_id AS pool_id, SUM(rollos_total) AS despacho_total
    FROM public.despacho
    WHERE COALESCE(flg_elm,false) = false
    GROUP BY partida_id
),
dyed AS (
    SELECT l.id AS lote_id,
           COALESCE(mp.partida_origen_id, mp.id) AS pool_id,
           EXISTS (SELECT 1 FROM inventario.item_movimientos im
                   JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
                   WHERE im.lote_id=l.id AND im.documento_tipo='entrega') AS dispatched,
           COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=l.id),0) > 0 AS in_stock
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id AND mp.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
per_pool AS (
    SELECT COALESCE(d.pool_id, y.pool_id) AS pool_id,
           COALESCE(d.despacho_total,0)                              AS despacho_total,
           COUNT(y.lote_id)                                          AS dyed_total,
           COUNT(y.lote_id) FILTER (WHERE y.dispatched)              AS dispatched_dyed,
           COUNT(y.lote_id) FILTER (WHERE y.in_stock)                AS instock_dyed
    FROM desp d
    FULL JOIN dyed y ON y.pool_id = d.pool_id
    GROUP BY COALESCE(d.pool_id, y.pool_id), d.despacho_total
)
-- ── §1 · Outcome buckets ──────────────────────────────────────────────────────
SELECT
    CASE
        WHEN despacho_total = 0                                  THEN 'no_despacho_record'
        WHEN despacho_total - dispatched_dyed <= 0              THEN 'fully_dispatched'
        WHEN despacho_total - dispatched_dyed <= instock_dyed   THEN 'shortfall_covered_by_stock'
        ELSE                                                         'shortfall_EXCEEDS_stock'
    END AS outcome,
    COUNT(*)                                              AS pools,
    SUM(despacho_total)                                   AS sum_despacho_total,
    SUM(dispatched_dyed)                                  AS sum_dispatched,
    SUM(instock_dyed)                                     AS sum_instock,
    SUM(GREATEST(despacho_total - dispatched_dyed,0))     AS sum_shortfall
FROM per_pool
GROUP BY 1 ORDER BY pools DESC;


-- ── §2 · The dispatch-shortfall pools in detail (the actual work list) ─────────
WITH desp AS (
    SELECT partida_id AS pool_id, SUM(rollos_total) AS despacho_total
    FROM public.despacho WHERE COALESCE(flg_elm,false)=false GROUP BY partida_id
),
dyed AS (
    SELECT l.id AS lote_id, COALESCE(mp.partida_origen_id, mp.id) AS pool_id,
           EXISTS (SELECT 1 FROM inventario.item_movimientos im
                   JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
                   WHERE im.lote_id=l.id AND im.documento_tipo='entrega') AS dispatched,
           COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=l.id),0) > 0 AS in_stock
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id AND mp.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
per_pool AS (
    SELECT COALESCE(d.pool_id,y.pool_id) AS pool_id,
           COALESCE(d.despacho_total,0) AS despacho_total,
           COUNT(y.lote_id) FILTER (WHERE y.dispatched) AS dispatched_dyed,
           COUNT(y.lote_id) FILTER (WHERE y.in_stock)   AS instock_dyed
    FROM desp d FULL JOIN dyed y ON y.pool_id=d.pool_id
    GROUP BY COALESCE(d.pool_id,y.pool_id), d.despacho_total
)
SELECT pool_id, despacho_total, dispatched_dyed, instock_dyed,
       (despacho_total - dispatched_dyed) AS shortfall
FROM per_pool
WHERE despacho_total - dispatched_dyed > 0
ORDER BY shortfall DESC
LIMIT 40;

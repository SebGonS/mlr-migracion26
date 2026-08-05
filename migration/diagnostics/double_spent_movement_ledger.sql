-- ============================================================================
-- DIAGNOSTIC · Full movement ledger for a few double-spent rolls — READ ONLY
-- ============================================================================
-- We've established: all 193 are raw rolls with a real PROD_CONSUMO (dyed child
-- exists) + a SPURIOUS raw SERV_EGR on PARTIDA. Before choosing the reversal
-- mechanism we must see the EXACT movement sequence + running saldo per roll, so
-- the compensating movement lands the net stock correctly (currently 0).
--
-- Nothing writes.
-- ============================================================================

-- ── §A · Every movement of a representative sample (2 rolls from each partida) ─
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
sample AS (  -- 2 lowest lote_ids per consumed-into partida
    SELECT lote_id FROM (
        SELECT raw_ds.lote_id,
               row_number() OVER (PARTITION BY pp.partida_id ORDER BY raw_ds.lote_id) AS rn
        FROM raw_ds
        JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id AND im.documento_tipo='partida_paso_ejecucion'
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='PROD_CONSUMO'
        JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id
        JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    ) z WHERE rn <= 2
)
SELECT
    im.lote_id, im.id AS mov_id, imt.codigo AS mov, imt.factor,
    im.cantidad, im.origen_ubicacion_id, im.destino_ubicacion_id,
    im.documento_tipo, im.documento_id, im.fecha_hora
FROM sample
JOIN inventario.item_movimientos im ON im.lote_id = sample.lote_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
ORDER BY im.lote_id, im.fecha_hora, im.id;


-- ── §B · Net factor*cantidad per roll (should the ledger net to 0 stock?) ─────
-- Sum of factor*cantidad across ALL movements per double-spent roll. If a roll
-- egressed TWICE (phantom SERV_EGR -1 AND real PROD_CONSUMO -1) but only ingressed
-- once (SERV_ING +1), the net is -1*cantidad → NEGATIVE phantom. lote_saldo shows 0
-- (trigger is AFTER-INSERT; the double egress drove it below the single ingress).
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
net AS (
    SELECT raw_ds.lote_id,
           l.cantidad AS lote_cantidad,
           COUNT(*) FILTER (WHERE imt.factor > 0)                       AS n_ingress,
           COUNT(*) FILTER (WHERE imt.factor < 0)                       AS n_egress,
           SUM(imt.factor * im.cantidad)                                AS net_qty,
           string_agg(imt.codigo, '>' ORDER BY im.fecha_hora, im.id)   AS mov_chain
    FROM raw_ds
    JOIN inventario.lote l ON l.id = raw_ds.lote_id
    JOIN inventario.item_movimientos im ON im.lote_id = raw_ds.lote_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY raw_ds.lote_id, l.cantidad
)
SELECT mov_chain, n_ingress, n_egress,
       COUNT(*) AS rolls,
       COUNT(*) FILTER (WHERE net_qty = 0)                  AS net_zero,
       COUNT(*) FILTER (WHERE net_qty < 0)                  AS net_negative,
       COUNT(*) FILTER (WHERE net_qty > 0)                  AS net_positive
FROM net
GROUP BY mov_chain, n_ingress, n_egress
ORDER BY rolls DESC;


-- ── §C · Current lote_saldo rows for the double-spent set ─────────────────────
-- Confirm what the trigger actually left. If the double egress underflowed, saldo
-- may be 0 (clamped) or negative — determines whether reversing the phantom egress
-- needs a compensating +qty and whether that would wrongly restore stock.
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
    COALESCE(ls.cantidad_actual, 0) AS saldo,
    a.codigo                        AS almacen,
    COUNT(*)                        AS saldo_rows
FROM raw_ds
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = raw_ds.lote_id
LEFT JOIN inventario.ubicacion u   ON u.id = ls.ubicacion_id
LEFT JOIN inventario.almacen  a    ON a.id = u.almacen_id
GROUP BY 1, 2
ORDER BY saldo_rows DESC;

-- ═══════════════════════════════════════════════════════════════
-- 42_factura_total_linea_rounding_fix
--
-- Bug: total_linea was rounded independently from
-- cantidad * precio_unitario * (1 + igv_porcentaje/100), while
-- subtotal_linea and igv_linea are each rounded independently from
-- the ex-IGV base. For certain fractional cent values (e.g.
-- cantidad=25, precio_unitario=6.55 -> 163.75 * 1.18 = 193.225) the
-- three independently-rounded quantities don't reconcile:
--   subtotal_linea (163.75) + igv_linea (29.48) = 193.23
--   total_linea (independently rounded from 193.225)            = 193.22 or 193.23
-- depending on rounding-mode boundary luck. Summed across several
-- lines on one invoice, header-level subtotal + igv can end up 1c+
-- off from header total, tripping chk_factura_montos
-- (ABS(total - (subtotal+igv)) < 0.01) and rolling back the whole
-- registrar_factura_cliente / registrar_factura_proveedor call.
--
-- Confirmed live incident: compra #1057 / factura_proveedor attempt
-- (2026-08-04) — frontend-side instance fixed in
-- FacturaProveedorDrawer.tsx. This migration closes the equivalent
-- gap on the backend so doc.registrar_factura_cliente (which sums
-- factura_detalle.total_linea directly, never taking a caller-
-- supplied total) can't hit the same failure, and hardens
-- factura_proveedor_detalle for consistency even though nothing
-- currently sums its total_linea server-side.
--
-- Fix: total_linea is redefined as the sum of the same two rounded
-- expressions subtotal_linea/igv_linea already use, so it can never
-- disagree with them. Postgres forbids a generated column from
-- referencing another generated column ("cannot use generated
-- column ... in column generation expression"), so the expressions
-- are inlined rather than referencing subtotal_linea/igv_linea by
-- name — it's still round(net) + round(tax), never an independent
-- third rounding. GENERATED column expressions can't be altered in
-- place; drop + re-add.
--
-- DROP COLUMN IF EXISTS: an earlier attempt at this migration on
-- 2026-08-04 partially applied — factura_detalle's DROP committed
-- before its (then-invalid) ADD errored out, leaving that column
-- missing while factura_proveedor_detalle was never reached. IF
-- EXISTS makes this script safe to run once from a clean schema or
-- to finish applying from that exact partial state either way.
--
-- factura_proveedor_detalle.total_linea has a dependent view,
-- doc.vw_compras_item_mes (migration/08_views.sql), which reads
-- fpd.total_linea directly — CASCADE drops it along with the
-- column, so it's recreated verbatim below (same definition as
-- 08_views.sql; keep both in sync if that view ever changes).
-- factura_detalle.total_linea has no dependents.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE doc.factura_detalle DROP COLUMN IF EXISTS total_linea;
ALTER TABLE doc.factura_detalle ADD COLUMN total_linea NUMERIC(12,2)
    GENERATED ALWAYS AS (
        ROUND(cantidad * precio_unitario, 2)
        + ROUND(cantidad * precio_unitario * igv_porcentaje / 100, 2)
    ) STORED;

ALTER TABLE doc.factura_proveedor_detalle DROP COLUMN IF EXISTS total_linea CASCADE;
ALTER TABLE doc.factura_proveedor_detalle ADD COLUMN total_linea NUMERIC(12,2)
    GENERATED ALWAYS AS (
        ROUND(cantidad * precio_unitario, 2)
        + ROUND(cantidad * precio_unitario * igv_porcentaje / 100, 2)
    ) STORED;

-- Recreate doc.vw_compras_item_mes, dropped by the CASCADE above.
CREATE OR REPLACE VIEW doc.vw_compras_item_mes AS
WITH facturas_con_detalle AS (
    SELECT DISTINCT factura_proveedor_id FROM doc.factura_proveedor_detalle
),
lineas AS (
    SELECT
        fp.id                                                   AS factura_proveedor_id,
        fp.tercero_id,
        fp.fecha_emision,
        fpd.item_id,
        fpd.cantidad,
        fpd.subtotal_linea                                      AS monto_exigv,
        fpd.total_linea                                         AS monto_conigv,
        'factura'::text                                         AS fuente
    FROM doc.factura_proveedor_detalle fpd
    JOIN doc.factura_proveedor fp ON fp.id = fpd.factura_proveedor_id
    WHERE fp.estado_pago <> 'anulado'

    UNION ALL

    SELECT
        fp.id                                                   AS factura_proveedor_id,
        fp.tercero_id,
        fp.fecha_emision,
        cd.item_id,
        cd.cantidad,
        cd.cantidad * cd.precio_unitario                        AS monto_exigv,
        cd.cantidad * cd.precio_unitario * 1.18                AS monto_conigv,
        'compra'::text                                          AS fuente
    FROM doc.compra_factura_proveedor cfp
    JOIN doc.factura_proveedor fp ON fp.id = cfp.factura_proveedor_id
    JOIN doc.compra_detalle cd    ON cd.compra_id = cfp.compra_id
    WHERE fp.estado_pago <> 'anulado'
      AND NOT EXISTS (
          SELECT 1 FROM facturas_con_detalle fcd
          WHERE fcd.factura_proveedor_id = fp.id
      )
)
SELECT
    l.tercero_id,
    t.nombre                                          AS proveedor_nombre,
    l.item_id,
    i.codigo                                          AS item_codigo,
    i.nombre                                          AS item_nombre,
    un.codigo                                         AS unidad_codigo,
    EXTRACT(YEAR  FROM l.fecha_emision)::INT          AS ano,
    EXTRACT(MONTH FROM l.fecha_emision)::INT          AS mes,
    TO_CHAR(l.fecha_emision, 'YYYY-MM')               AS ano_mes,
    SUM(l.cantidad)                                   AS cantidad_total,
    SUM(l.monto_exigv)                                AS monto_exigv,
    SUM(l.monto_conigv)                               AS monto_conigv,
    CASE
        WHEN bool_and(l.fuente = 'factura') THEN 'factura'
        WHEN bool_and(l.fuente = 'compra')  THEN 'compra'
        ELSE                                     'mixto'
    END                                             AS fuente
FROM lineas l
JOIN tercero t ON t.id  = l.tercero_id
JOIN item i    ON i.id  = l.item_id
JOIN unidad un ON un.id = i.unidad_id
GROUP BY l.tercero_id, t.nombre,
         l.item_id, i.codigo, i.nombre, un.codigo,
         EXTRACT(YEAR  FROM l.fecha_emision),
         EXTRACT(MONTH FROM l.fecha_emision),
         TO_CHAR(l.fecha_emision, 'YYYY-MM');

GRANT SELECT ON doc.vw_compras_item_mes TO authenticated;

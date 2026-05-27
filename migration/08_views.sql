-- ═══════════════════════════════════════════════════════════════
-- Step 8: Views
-- Must come after all tables they reference.
-- ═══════════════════════════════════════════════════════════════
-- DROP VIEW IF EXISTS vw_colores CASCADE;
-- ── vw_colores ────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_colores AS
SELECT
    a.id          AS color_x_cliente_id,
    b.id          AS color_id,
    b.color,
    a.cliente_id::integer,                    -- legacy FK kept for backward compat
    t.nombre      AS tono,
    t.nombre      AS cliente,        -- alias kept for backward compat
    a.hex         AS color_x_cliente_hex,
    b.hex         AS color_hex,
        a.tercero_id
FROM color_x_cliente a
JOIN color b    ON a.color_id   = b.id
LEFT JOIN tercero t ON a.tercero_id = t.id;

-- ── vw_items ──────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_items AS
SELECT
    i.id        AS item_id,
    i.codigo    AS item_codigo,
    i.nombre    AS item_nombre,
    i.item_tipo_id,
    i.unidad_id,
    it.codigo   AS item_tipo_codigo,
    u.codigo    AS unidad_codigo
FROM item i
JOIN item_tipo it ON i.item_tipo_id = it.id
JOIN unidad u ON i.unidad_id = u.id;

-- ── inventario.vw_item_movimiento_categoria ───────────────────
-- Already created in 05 before the table — kept here for view-only reference.

-- ── inventario.vw_stock_lotes ─────────────────────────────────
-- Per-lot stock, location-agnostic — sums lote_saldo across locations (≈ SAP MCHB view).
-- Used by FIFO (calcular_fifo), lot-level gate checks, and roll stock views.
DROP VIEW IF EXISTS inventario.vw_stock_actual CASCADE;
CREATE OR REPLACE VIEW inventario.vw_stock_lotes AS
SELECT
    l.id                    AS lote_id,
    l.item_id,
    SUM(ls.cantidad_actual) AS cantidad_disponible,
    l.fyh_cre               AS fecha_hora_ingreso
FROM inventario.lote l
JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
WHERE l.fyh_elm IS NULL
GROUP BY l.id, l.item_id, l.fyh_cre
HAVING SUM(ls.cantidad_actual) > 0;

-- ── inventario.vw_stock_lotes_ubicacion ───────────────────────
-- Per-(lot, location) stock — exposes ubicacion_id for picking and location display.
CREATE OR REPLACE VIEW inventario.vw_stock_lotes_ubicacion AS
SELECT
    l.id               AS lote_id,
    l.item_id,
    ls.ubicacion_id,
    ls.cantidad_actual AS cantidad_disponible,
    l.fyh_cre          AS fecha_hora_ingreso
FROM inventario.lote l
JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
WHERE l.fyh_elm IS NULL
  AND ls.cantidad_actual > 0;

GRANT SELECT ON inventario.vw_stock_lotes           TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_lotes_ubicacion TO anon, authenticated;


-- ── inventario.vw_lotes_rollos_stock ─────────────────────────
-- Shows all rolls currently in stock (dyed and undyed).
-- Batch attributes come from partida for both dyed and undyed rolls —
-- this shows "expected" specs for undyed rolls (useful for operators).
-- For dyed rolls the same values are also on lote_rollo_detalle.
-- lote_rollo_detalle is joined for: guia_remision_id, flg_tenido.
-- DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock;
CREATE OR REPLACE VIEW inventario.vw_lotes_rollos_stock AS
SELECT
    sa.lote_id,
    sa.item_id,
    i.codigo                        AS item_codigo,
    i.nombre                        AS item_nombre,
    sa.ubicacion_id,
    u.nombre                        AS ubicacion,
    a.nombre                        AS almacen,
    sa.cantidad_disponible,
    un.codigo                       AS unidad,
    l.estado_calidad::text,
    l.cantidad                      AS peso,
    ird.articulo_id,
    art.nombre                      AS articulo_nombre,
    art.articulo_tipo_id,
    ird.flg_rib,
    art.fibra,
    -- All batch attributes from lrd — NULL for undyed rolls (not yet set)
    lrd.flg_tenido,
    lrd.flg_antipilling,
    lrd.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.cliente_id,
    vc.color_hex,
    vc.color_x_cliente_hex,
    lrd.tenido_id,
    tn.tenido,
    lrd.ancho,
    lrd.malla,
    lrd.rendimiento,
    l.propietario_id,
    t.nombre                        AS propietario,
    -- Ingress guia — billing anchor
    lrd.guia_remision_id,
    gr.serie                        AS guia_serie,
    gr.correlativo                  AS guia_correlativo
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN inventario.lote l                  ON l.id = sa.lote_id
JOIN item i                             ON i.id = sa.item_id
JOIN item_tipo it                       ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN item_rollo_detalle ird             ON ird.item_id = i.id
JOIN articulo art                       ON art.id = ird.articulo_id
JOIN unidad un                          ON un.id = i.unidad_id
LEFT JOIN inventario.ubicacion u         ON u.id = sa.ubicacion_id
LEFT JOIN inventario.almacen a           ON a.id = u.almacen_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id
LEFT JOIN doc.guia_remision gr          ON gr.id = lrd.guia_remision_id
LEFT JOIN tercero t                     ON t.id = l.propietario_id
LEFT JOIN vw_colores vc                 ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN tenido tn                     ON tn.id = lrd.tenido_id;

-- ── inventario.vw_lotes_rollos_disponibles ────────────────────
-- Available rolls only: physical stock minus rolls reserved by active partidas.
-- Equivalent to SAP MD04 vs MMBE:
--   vw_lotes_rollos_stock    = MMBE (physical)
--   vw_lotes_rollos_disponibles = MD04 (available to assign)
-- CANCELADA partidas restore stock via PROD_CONSUMO_REV but do not delete
-- partida_componente rows — the estado filter handles that case.
-- Use this view for order assignment / picking screens.
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_disponibles;
CREATE OR REPLACE VIEW inventario.vw_lotes_rollos_disponibles AS
SELECT s.*
FROM inventario.vw_lotes_rollos_stock s
WHERE NOT EXISTS (
    SELECT 1 FROM mes.partida_componente pc
    JOIN mes.partida p ON p.id = pc.partida_id
    WHERE pc.lote_id = s.lote_id
      AND p.estado_produccion NOT IN ('CERRADA', 'CANCELADA')
      AND p.fyh_elm IS NULL
);

-- ── mes.vw_partidas (detailed: paso/material/produccion stats) ───────────
-- Replaces the old "ordenes de produccion" view: after the schema redesign
-- mes.partida IS the commercial order. Paso execution state is derived from
-- partida_paso_ejecucion (no estado column on partida_paso anymore).
DROP VIEW IF EXISTS mes.vw_partidas;
CREATE OR REPLACE VIEW mes.vw_partidas AS
SELECT
    p.id,
    p.numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                            AS codigo,
    p.estado_produccion                                                    AS estado,
    p.estado_comercial,
    p.estado_facturacion,
    p.partida_origen_id,
    p.fyh_cre,
    p.fyh_programacion,
    p.fyh_inicio,
    p.fyh_fin,
    p.fecha_acordada,
    p.tercero_id,
    c.nombre                                                               AS cliente,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    p.tenido_id,
    t.tenido,
    p.articulo_tipo_id,
    at.nombre                                                              AS articulo_tipo,
    p.fibra,
    p.flg_antipilling,
    p.malla,
    p.rendimiento,
    p.ancho,
    p.prioridad_id,
    pr.prioridad,
    COALESCE(pasos_stats.total_pasos, 0)                                   AS total_pasos,
    COALESCE(pasos_stats.pasos_completados, 0)                             AS pasos_completados,
    COALESCE(pasos_stats.pasos_en_proceso, 0)                              AS pasos_en_proceso,
    COALESCE(pasos_stats.pasos_pendientes, 0)                              AS pasos_pendientes,
    CASE
        WHEN COALESCE(pasos_stats.total_pasos, 0) > 0
        THEN ROUND(
            (COALESCE(pasos_stats.pasos_completados, 0)::NUMERIC
             / pasos_stats.total_pasos::NUMERIC) * 100, 0)
        ELSE 0
    END                                                                    AS progreso_porcentaje,
    COALESCE(materiales_stats.total_materiales, 0)                        AS total_materiales,
    COALESCE(materiales_stats.cantidad_total_kg, 0)                       AS cantidad_total_kg,
    COALESCE(produccion_stats.rollos_producidos, 0)                       AS rollos_producidos,
    COALESCE(produccion_stats.kg_producidos, 0)                           AS kg_producidos,
    CASE
        WHEN p.fyh_inicio IS NOT NULL AND p.fyh_fin IS NOT NULL
            THEN EXTRACT(EPOCH FROM (p.fyh_fin - p.fyh_inicio)) / 3600
        WHEN p.fyh_inicio IS NOT NULL
            THEN EXTRACT(EPOCH FROM (NOW() - p.fyh_inicio)) / 3600
        ELSE NULL
    END                                                                    AS duracion_horas,
    p.usr_cre,
    prof.nombre || ' ' || prof.apellido                                    AS creado_por,
    p.usr_mod,
    p.fyh_mod,
    p.fyh_elm
FROM mes.partida p
LEFT JOIN tercero c        ON c.id  = p.tercero_id
LEFT JOIN vw_colores vc    ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido t         ON t.id  = p.tenido_id
LEFT JOIN articulo_tipo at ON at.id = p.articulo_tipo_id
LEFT JOIN prioridad pr     ON pr.id = p.prioridad_id
LEFT JOIN usuario prof     ON prof.id = p.usr_cre
LEFT JOIN LATERAL (
    -- Paso completion is derived: a paso is COMPLETADO when it has a COMPLETADO ejecucion.
    -- PENDIENTE = no ejecucion rows at all. EN_PROCESO = ejecucion with EN_PROCESO estado.
    SELECT
        COUNT(*)                                                           AS total_pasos,
        COUNT(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
        ))                                                                 AS pasos_completados,
        COUNT(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
        ))                                                                 AS pasos_en_proceso,
        COUNT(*) FILTER (WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id
        ))                                                                 AS pasos_pendientes
    FROM mes.partida_paso pp
    WHERE pp.partida_id = p.id
) pasos_stats ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_materiales, SUM(l.cantidad) AS cantidad_total_kg
    FROM mes.partida_componente opi
    LEFT JOIN inventario.lote l ON l.id = opi.lote_id
    WHERE opi.partida_id = p.id
) materiales_stats ON true
LEFT JOIN LATERAL (
    SELECT
        COUNT(*)           AS rollos_producidos,
        SUM(l.cantidad)    AS kg_producidos
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
    JOIN mes.partida_paso pp           ON pp.id = pe.partida_paso_id
    WHERE l.documento_tipo = 'partida_paso_ejecucion'
      AND pp.partida_id = p.id
      AND l.fyh_elm IS NULL
) produccion_stats ON true;

GRANT SELECT ON mes.vw_partidas TO anon, authenticated;

-- ── doc.vw_compras ────────────────────────────────────────────
-- List view for purchase orders.
-- estado_ingreso: derived from compra_detalle (ordered) vs quantities
--   received via linked guias (guia_remision_detalle).  Comparison is at
--   the (compra, item) level — same granularity the linkage allows.
--   'sin_lineas'  → compra header only, no detail lines
--   'pendiente'   → no guias linked yet
--   'parcial'     → some items partially received
--   'completo'    → all ordered quantities covered by received quantities
DROP VIEW IF EXISTS doc.vw_compras;
CREATE OR REPLACE VIEW doc.vw_compras AS
SELECT
    c.id,
    c.tercero_id,
    p.nombre AS proveedor_nombre,
    c.fecha,
    -- Aggregated factura info (N facturas per compra)
    facturas.total_facturas,
    facturas.facturas_ids,
    facturas.facturas_numeros,
    facturas.monto_facturas_total,
    facturas.estado_pago_consolidado,
    COALESCE(det.total_items, 0)               AS total_items,
    COALESCE(det.monto_total, 0)               AS monto_total,
    COALESCE(guias.total_guias, 0)             AS total_guias,
    COALESCE(letras.total_letras, 0)           AS total_letras,
    COALESCE(letras.monto_letras_pendiente, 0) AS monto_letras_pendiente,
    -- Receipt progress derived from linked guias
    CASE
        WHEN det.total_items = 0                   THEN 'sin_lineas'
        WHEN COALESCE(guias.total_guias, 0) = 0    THEN 'pendiente'
        WHEN recepcion.qty_pendiente <= 0           THEN 'completo'
        ELSE                                             'parcial'
    END                                        AS estado_ingreso,
    c.observacion,
    c.fyh_elm,
    c.usr_cre,
    c.fyh_cre
FROM doc.compra c
JOIN tercero p ON p.id = c.tercero_id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*)                                                       AS total_facturas,
        jsonb_agg(fp.id ORDER BY fp.fyh_cre)                          AS facturas_ids,
        string_agg(fp.serie || '-' || fp.numero, ', ' ORDER BY fp.fyh_cre) AS facturas_numeros,
        SUM(fp.total)                                                  AS monto_facturas_total,
        CASE
            WHEN COUNT(*) = 0                           THEN 'sin_factura'
            WHEN bool_and(fp.estado_pago = 'total')     THEN 'total'
            WHEN bool_or(fp.estado_pago != 'pendiente') THEN 'parcial'
            ELSE                                             'pendiente'
        END                                                            AS estado_pago_consolidado
    FROM doc.compra_factura_proveedor cfp
    JOIN doc.factura_proveedor fp ON fp.id = cfp.factura_proveedor_id
    WHERE cfp.compra_id = c.id
) facturas ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_items, SUM(cd.cantidad * cd.precio_unitario) AS monto_total
    FROM doc.compra_detalle cd WHERE cd.compra_id = c.id
) det ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_guias
    FROM doc.compra_guia_remision cgr WHERE cgr.compra_id = c.id
) guias ON true
LEFT JOIN LATERAL (
    SELECT COUNT(DISTINCT lf.letra_id)                                         AS total_letras,
           SUM(lf.monto_aplicado) FILTER (WHERE l.estado = 'emitida')          AS monto_letras_pendiente
    FROM doc.compra_factura_proveedor cfp
    JOIN doc.letra_factura lf ON lf.factura_proveedor_id = cfp.factura_proveedor_id
    JOIN doc.letra l ON l.id = lf.letra_id
    WHERE cfp.compra_id = c.id
) letras ON true
LEFT JOIN LATERAL (
    -- Sum ordered qty vs received qty across all items in this compra.
    -- Received = guia_remision_detalle rows for linked guias, matched by item_id.
    SELECT SUM(cd.cantidad) - COALESCE(SUM(rec.cantidad_recibida), 0) AS qty_pendiente
    FROM doc.compra_detalle cd
    LEFT JOIN LATERAL (
        SELECT SUM(grd.cantidad) AS cantidad_recibida
        FROM doc.compra_guia_remision cgr
        JOIN doc.guia_remision_detalle grd
            ON grd.guia_remision_id = cgr.guia_remision_id
           AND grd.item_id = cd.item_id
        WHERE cgr.compra_id = c.id
    ) rec ON true
    WHERE cd.compra_id = c.id
) recepcion ON true;

GRANT SELECT ON doc.vw_compras TO authenticated;

-- ── doc.vw_facturas_proveedor ──────────────────────────────────
-- Hydrated list view for supplier invoices.
-- Adds proveedor name, line count, letter coverage, and open balance.
CREATE OR REPLACE VIEW doc.vw_facturas_proveedor AS
SELECT
    fp.id,
    fp.tercero_id,
    t.nombre                                             AS proveedor_nombre,
    fp.serie,
    fp.numero,
    fp.serie || '-' || fp.numero::text                   AS numero_completo,
    fp.fecha_emision,
    fp.fecha_vencimiento,
    fp.tipo_pago,
    fp.moneda,
    fp.tipo_cambio,
    fp.subtotal,
    fp.igv,
    fp.total,
    fp.estado_pago,
    fp.observacion,
    COALESCE(lineas.total_lineas, 0)                     AS total_lineas,
    COALESCE(letras.total_letras, 0)                     AS total_letras,
    COALESCE(letras.monto_aplicado_total, 0)             AS monto_aplicado_total,
    fp.total - COALESCE(letras.monto_aplicado_total, 0)  AS saldo_pendiente,
    CASE
        WHEN fp.estado_pago IN ('total', 'anulado') THEN NULL
        ELSE GREATEST(0, CURRENT_DATE - fp.fecha_vencimiento)
    END                                                  AS dias_vencido,
    COALESCE(compras.total_compras, 0)                   AS total_compras,
    fp.fyh_cre,
    fp.usr_cre
FROM doc.factura_proveedor fp
JOIN tercero t ON t.id = fp.tercero_id
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_lineas
    FROM doc.factura_proveedor_detalle fpd
    WHERE fpd.factura_proveedor_id = fp.id
) lineas ON true
LEFT JOIN LATERAL (
    SELECT
        COUNT(DISTINCT lf.letra_id)                                      AS total_letras,
        SUM(lf.monto_aplicado) FILTER (WHERE l.estado != 'anulada')      AS monto_aplicado_total
    FROM doc.letra_factura lf
    JOIN doc.letra l ON l.id = lf.letra_id
    WHERE lf.factura_proveedor_id = fp.id
) letras ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_compras
    FROM doc.compra_factura_proveedor cfp
    WHERE cfp.factura_proveedor_id = fp.id
) compras ON true;

GRANT SELECT ON doc.vw_facturas_proveedor TO authenticated;

-- ── doc.vw_compras_item_mes ────────────────────────────────────
-- Purchases aggregated by (supplier, item, month).
-- All amounts in USD. Excludes anuladas.
-- Designed for time-series and supplier purchase analysis; the frontend
-- pivots months into columns.
--
-- Source priority (same pattern as vw_precio_promedio_insumos):
--   1. factura_proveedor_detalle — authoritative when invoice lines are entered.
--   2. compra_detalle via compra_factura_proveedor — fallback for facturas that
--      have no detail lines (legacy migration: headers only, no line breakdown).
--      IGV hardcoded at 18% — all insumo purchases (domestic + imports) carry IGV.
--      `fuente` column lets callers distinguish the two sources.
--
-- Once all facturas have detail lines entered, the fallback branch becomes
-- unreachable and can be dropped.
CREATE OR REPLACE VIEW doc.vw_compras_item_mes AS
WITH facturas_con_detalle AS (
    -- Which facturas already have line-level detail entered
    SELECT DISTINCT factura_proveedor_id FROM doc.factura_proveedor_detalle
),
lineas AS (
    -- Branch 1: authoritative invoice lines
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

    -- Branch 2: fallback — compra lines for facturas with no detail yet.
    -- IGV rate = fp.igv / fp.subtotal (handles 0% and 18% correctly).
    -- If one factura links to multiple compras the lines from all are included;
    -- this is acceptable given the fallback is transitional.
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
    -- 'factura' once all lines are entered; 'compra' while on fallback;
    -- 'mixto' if a period somehow has both (shouldn't happen in practice)
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

-- ── doc.vw_letras ──────────────────────────────────────────────
-- Hydrated list view for payment letters.
-- Adds proveedor name, invoice count, applied amount, and free balance.
CREATE OR REPLACE VIEW doc.vw_letras AS
SELECT
    l.id,
    l.tercero_id,
    t.nombre                                             AS proveedor_nombre,
    l.numero,
    l.monto,
    l.fecha_giro,
    l.fecha_vencimiento,
    l.fecha_pago,
    l.banco,
    l.estado,
    l.observacion,
    COALESCE(facturas.total_facturas, 0)                 AS total_facturas,
    COALESCE(facturas.monto_aplicado_total, 0)           AS monto_aplicado_total,
    l.monto - COALESCE(facturas.monto_aplicado_total, 0) AS monto_libre,
    CASE
        WHEN l.estado IN ('pagada', 'anulada') THEN NULL
        ELSE GREATEST(0, CURRENT_DATE - l.fecha_vencimiento)
    END                                                  AS dias_vencido,
    l.fyh_cre,
    l.usr_cre
FROM doc.letra l
JOIN tercero t ON t.id = l.tercero_id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*)              AS total_facturas,
        SUM(lf.monto_aplicado) AS monto_aplicado_total
    FROM doc.letra_factura lf
    WHERE lf.letra_id = l.id
) facturas ON true;

GRANT SELECT ON doc.vw_letras TO authenticated;

-- ── doc.vw_cuentas_por_pagar ───────────────────────────────────
-- Combined AP view: one row per (factura, letra) clearing pair.
--
-- Spine: letra_factura junction, LEFT-joined from both sides so that:
--   • Facturas with no letra yet  → 1 row, all letra_* columns NULL
--   • Facturas with N letras      → N rows, one per letra
--   • Letras covering M facturas  → M rows, one per factura
--
-- factura_saldo = factura total minus ALL applied letras for that factura
-- (computed via lateral, not from this row's monto_aplicado alone —
--  otherwise multi-letra facturas would show the wrong balance).
--
-- Common filter patterns:
--   AP aging          : estado_pago NOT IN ('total','anulado') ORDER BY factura_dias_vencido DESC
--   Payment schedule  : letra_estado = 'emitida'              ORDER BY letra_fecha_vencimiento
--   Unassigned        : letra_id IS NULL AND estado_pago NOT IN ('total','anulado')
--   Overdue letters   : letra_estado = 'vencida'
--   By supplier       : tercero_id = X
CREATE OR REPLACE VIEW doc.vw_cuentas_por_pagar AS
SELECT
    -- ── Factura side ──────────────────────────────────────────
    fp.id                                                   AS factura_id,
    fp.tercero_id,
    t.nombre                                                AS proveedor_nombre,
    fp.serie || '-' || fp.numero::text                      AS factura_numero,
    fp.fecha_emision,
    fp.fecha_vencimiento                                    AS factura_fecha_vencimiento,
    fp.moneda,
    fp.tipo_cambio,
    fp.subtotal,
    fp.igv,
    fp.total                                                AS factura_total,
    fp.tipo_pago,
    fp.estado_pago,
    CASE
        WHEN fp.estado_pago IN ('total', 'anulado') THEN NULL
        ELSE GREATEST(0, CURRENT_DATE - fp.fecha_vencimiento)
    END                                                     AS factura_dias_vencido,
    -- Open balance: total minus sum of all non-anulada letras on this factura
    fp.total - COALESCE(saldo.monto_aplicado_total, 0)      AS factura_saldo,

    -- ── Letra side (NULL when no letra assigned yet) ──────────
    l.id                                                    AS letra_id,
    l.numero                                                AS letra_numero,
    lf.monto_aplicado,
    l.monto                                                 AS letra_monto,
    l.fecha_giro,
    l.fecha_vencimiento                                     AS letra_fecha_vencimiento,
    l.fecha_pago,
    l.banco,
    l.estado                                                AS letra_estado,
    CASE
        WHEN l.id IS NULL                      THEN NULL
        WHEN l.estado IN ('pagada', 'anulada') THEN NULL
        ELSE GREATEST(0, CURRENT_DATE - l.fecha_vencimiento)
    END                                                     AS letra_dias_vencido

FROM doc.factura_proveedor fp
JOIN tercero t ON t.id = fp.tercero_id
-- Open balance across ALL letras on this factura (not just the current row's)
LEFT JOIN LATERAL (
    SELECT SUM(lf2.monto_aplicado) FILTER (WHERE l2.estado <> 'anulada') AS monto_aplicado_total
    FROM doc.letra_factura lf2
    JOIN doc.letra l2 ON l2.id = lf2.letra_id
    WHERE lf2.factura_proveedor_id = fp.id
) saldo ON true
-- Clearing pairs
LEFT JOIN doc.letra_factura lf ON lf.factura_proveedor_id = fp.id
LEFT JOIN doc.letra l          ON l.id = lf.letra_id;

GRANT SELECT ON doc.vw_cuentas_por_pagar TO authenticated;

-- ── doc.vw_compras_recepcion ───────────────────────────────────
-- Receipt tracking: per (compra, item) shows ordered qty vs qty
-- received via linked guias, and the remaining open qty.
--
-- "Received" = sum of guia_remision_detalle.cantidad for all guias
-- linked to this compra (via compra_guia_remision) that carry this
-- item_id.  There is intentionally no FK from a guia line to a
-- compra line — linkage is at the compra↔guia level — so this is
-- the finest granularity possible without schema changes.
--
-- Rows exist for every compra_detalle line including those with
-- zero receipt (qty_pendiente = cantidad_ordenada).  Use WHERE
-- qty_pendiente > 0 to filter open lines.
CREATE OR REPLACE VIEW doc.vw_compras_recepcion AS
SELECT
    c.id                                                              AS compra_id,
    c.tercero_id,
    t.nombre                                                          AS proveedor_nombre,
    c.fecha,
    cd.id                                                             AS compra_detalle_id,
    cd.item_id,
    i.codigo                                                          AS item_codigo,
    i.nombre                                                          AS item_nombre,
    un.codigo                                                         AS unidad_codigo,
    cd.cantidad                                                       AS cantidad_ordenada,
    COALESCE(rec.cantidad_recibida, 0)                                AS cantidad_recibida,
    cd.cantidad - COALESCE(rec.cantidad_recibida, 0)                  AS cantidad_pendiente,
    cd.precio_unitario,
    cd.cantidad * cd.precio_unitario                                  AS valor_linea,
    -- Per-line receipt status
    CASE
        WHEN COALESCE(rec.cantidad_recibida, 0) = 0               THEN 'pendiente'
        WHEN COALESCE(rec.cantidad_recibida, 0) >= cd.cantidad    THEN 'completo'
        ELSE                                                            'parcial'
    END                                                               AS estado_linea,
    c.fyh_elm
FROM doc.compra c
JOIN tercero t          ON t.id  = c.tercero_id
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i             ON i.id  = cd.item_id
JOIN unidad un          ON un.id = i.unidad_id
LEFT JOIN LATERAL (
    SELECT SUM(grd.cantidad) AS cantidad_recibida
    FROM doc.compra_guia_remision cgr
    JOIN doc.guia_remision_detalle grd
        ON grd.guia_remision_id = cgr.guia_remision_id
       AND grd.item_id = cd.item_id
    WHERE cgr.compra_id = c.id
) rec ON true;

GRANT SELECT ON doc.vw_compras_recepcion TO authenticated;

-- ── inventario.vw_item_proveedor_guia ─────────────────────────
CREATE OR REPLACE VIEW inventario.vw_item_proveedor_guia AS
SELECT DISTINCT
    i.id AS item_id,
    i.codigo AS item_codigo,
    i.nombre AS item_nombre,
    gr.tercero_id AS proveedor_id,
    t.nombre AS proveedor_nombre
FROM doc.guia_remision gr
JOIN doc.guia_remision_tipo grt ON grt.id = gr.guia_remision_tipo_id
JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
JOIN item i ON i.id = grd.item_id
JOIN tercero t ON t.id = gr.tercero_id
WHERE grt.flg_emitida = false AND t.flg_proveedor = true;

GRANT SELECT ON inventario.vw_item_proveedor_guia TO anon, authenticated;


-- ── inventario.vw_lotes_rollos_despachados ────────────────────
CREATE OR REPLACE VIEW inventario.vw_lotes_rollos_despachados AS
WITH mov AS (
    SELECT
        im.lote_id,
        SUM(im.cantidad * (
            CASE WHEN im.destino_ubicacion_id IS NOT NULL THEN  1 ELSE 0 END +
            CASE WHEN im.origen_ubicacion_id  IS NOT NULL THEN -1 ELSE 0 END
        ))                                                              AS saldo,
        BOOL_OR(im.origen_ubicacion_id IS NOT NULL
                AND imt.categoria NOT IN ('PRODUCCION', 'TRANSFERENCIA')) AS has_egreso
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
)
SELECT
    l.id AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.item_id,
    i.codigo AS item_codigo,
    i.nombre AS item_nombre,
    un.codigo AS unidad,
    l.estado_calidad::text,
    l.cantidad AS peso,
    ird.articulo_id,
    art.nombre                          AS articulo_nombre,
    art.articulo_tipo_id,
    lrd.flg_tenido,
    ird.flg_rib,
    art.fibra,
    -- Batch attributes from lrd (authoritative for dyed rolls — set by registrar_produccion)
    lrd.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.cliente_id,
    vc.color_hex,
    vc.color_x_cliente_hex,
    lrd.tenido_id,
    lrd.ancho,
    lrd.malla,
    lrd.rendimiento,
    lrd.flg_antipilling,
    c.id                                AS propietario_id,
    c.nombre                            AS propietario,
    p.id AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    lrd.guia_remision_id
FROM inventario.lote l
JOIN mov m                              ON m.lote_id = l.id AND m.saldo <= 0 AND m.has_egreso
JOIN item i                             ON i.id = l.item_id
JOIN item_tipo it                       ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN item_rollo_detalle ird             ON ird.item_id = i.id
JOIN articulo art                       ON art.id = ird.articulo_id
JOIN unidad un                          ON un.id = i.unidad_id
JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id AND lrd.flg_tenido = true
LEFT JOIN tercero c                     ON c.id = l.propietario_id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_paso pp          ON pp.id = pe.partida_paso_id
LEFT JOIN mes.partida p                ON p.id = pp.partida_id
LEFT JOIN vw_colores vc                 ON vc.color_x_cliente_id = lrd.color_x_cliente_id;

DROP VIEW IF EXISTS mes.vw_partida_resumen_tenido;
-- ── mes.partida_resumen_tenido ────────────────────────────────
CREATE OR REPLACE VIEW mes.vw_partida_resumen_tenido AS
SELECT
    pd.partida_id,
    a.id            AS articulo_id,
    a.nombre        AS articulo_nombre,
    a.articulo_tipo_id,           -- added
    at.nombre       AS articulo_tipo_nombre,  -- added
    a.fibra,
    SUM(pd.cantidad)                                                     AS total_rollos,
    SUM(pd.cantidad)                                                     AS cantidad_total,
    SUM(CASE WHEN ird.flg_rib = false THEN pd.cantidad ELSE 0 END)      AS cantidad_regular,
    SUM(CASE WHEN ird.flg_rib = true  THEN pd.cantidad ELSE 0 END)      AS cantidad_rib
FROM mes.partida_detalle pd
JOIN item_rollo_detalle ird  ON ird.item_id  = pd.item_id
JOIN articulo a              ON a.id         = ird.articulo_id
JOIN articulo_tipo at        ON at.id        = a.articulo_tipo_id   -- added
GROUP BY pd.partida_id, a.id, a.nombre, a.articulo_tipo_id, at.nombre, a.fibra
ORDER BY 1, 2;


-- ── mes.vw_maquinas ───────────────────────────────────────────
CREATE OR REPLACE VIEW mes.vw_maquinas AS
SELECT
    m.id,
    m.codigo,
    m.nombre,
    m.maquina_tipo_id,
    mt.codigo AS maquina_tipo_codigo,
    mt.nombre AS maquina_tipo_nombre,
    m.relacion_bano
FROM mes.maquina m
LEFT JOIN mes.maquina_tipo mt ON mt.id = m.maquina_tipo_id;

-- ── mes.vw_partida_produccion_rollos ──────────────────────────
CREATE OR REPLACE VIEW mes.vw_partida_produccion_rollos AS
SELECT
    p.id AS partida_id,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    COUNT(*) AS cantidad_rollos
FROM inventario.lote l
JOIN vw_items vi ON vi.item_id = l.item_id AND vi.item_tipo_codigo = 'ROLLO'
JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
WHERE l.documento_tipo = 'partida_paso_ejecucion'
GROUP BY p.id, l.item_id, vi.item_codigo, vi.item_nombre;

-- ── inventario.vw_stock_items ─────────────────────────────────
-- Item-level stock totals, location-agnostic — reads item_saldo (≈ SAP MARD).
-- O(1) per item: no aggregation over lot history. Used by availability gates.
DROP VIEW IF EXISTS inventario.vw_stock_general CASCADE;
CREATE OR REPLACE VIEW inventario.vw_stock_items AS
SELECT
    vi.item_id, vi.item_codigo, vi.item_nombre,
    vi.item_tipo_id, vi.item_tipo_codigo,
    SUM(si.cantidad_actual) AS cantidad_total,
    vi.unidad_id, vi.unidad_codigo
FROM inventario.item_saldo si
JOIN vw_items vi ON vi.item_id = si.item_id
WHERE si.cantidad_actual > 0
GROUP BY vi.item_id, vi.item_codigo, vi.item_nombre,
         vi.item_tipo_id, vi.item_tipo_codigo, vi.unidad_id, vi.unidad_codigo;

-- ── inventario.vw_stock_items_ubicacion ───────────────────────
-- Item stock by location — exposes ubicacion_id for location-scoped checks.
CREATE OR REPLACE VIEW inventario.vw_stock_items_ubicacion AS
SELECT
    vi.item_id, vi.item_codigo, vi.item_nombre,
    vi.item_tipo_id, vi.item_tipo_codigo,
    si.ubicacion_id,
    si.cantidad_actual AS cantidad_total,
    vi.unidad_id, vi.unidad_codigo
FROM inventario.item_saldo si
JOIN vw_items vi ON vi.item_id = si.item_id
WHERE si.cantidad_actual > 0;

-- ── inventario.vw_stock_items_valorado ───────────────────────
-- Item stock + MAP valuation (≈ SAP MB52). Financial view only — not for
-- availability gates (use vw_stock_items for that).
-- LEFT JOIN so items with no valuation row still appear (cost columns NULL).
CREATE OR REPLACE VIEW inventario.vw_stock_items_valorado AS
SELECT
    vi.item_id, vi.item_codigo, vi.item_nombre,
    vi.item_tipo_id, vi.item_tipo_codigo,
    SUM(si.cantidad_actual)   AS cantidad_total,
    vi.unidad_id, vi.unidad_codigo,
    iv.precio_promedio,
    iv.stock_valorado
FROM inventario.item_saldo si
JOIN  vw_items vi                    ON vi.item_id = si.item_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = si.item_id
WHERE si.cantidad_actual > 0
GROUP BY vi.item_id, vi.item_codigo, vi.item_nombre,
         vi.item_tipo_id, vi.item_tipo_codigo,
         vi.unidad_id, vi.unidad_codigo,
         iv.precio_promedio, iv.stock_valorado;

-- ── inventario.vw_stock_rollos ────────────────────────────────
-- Kept as combined base view in case any function needs a single roll stock source.
-- For frontend use prefer vw_stock_rollos_crudos / vw_stock_rollos_tenidos below.
/*
CREATE OR REPLACE VIEW inventario.vw_stock_rollos AS
SELECT
    sa.item_id,
    i.codigo AS item_codigo,
    i.nombre AS item_nombre,
    u.codigo AS unidad_codigo,
    ird.articulo_id,
    art.nombre AS articulo_nombre,
    art.articulo_tipo_id,
    ird.flg_rib,
    art.fibra,
    lrd.flg_tenido,
    lrd.flg_antipilling,
    lrd.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.cliente_id,
    vc.color_hex,
    vc.color_x_cliente_hex,
    lrd.tenido_id,
    tn.tenido,
    lrd.ancho,
    lrd.malla,
    lrd.rendimiento,
    l.propietario_id,
    c.nombre AS propietario,
    COUNT(sa.lote_id)           AS cantidad_rollos,
    SUM(sa.cantidad_disponible) AS cantidad_total
FROM inventario.vw_stock_actual sa
JOIN inventario.lote l          ON l.id = sa.lote_id
JOIN item i                     ON i.id = sa.item_id
JOIN item_tipo it               ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN unidad u                   ON u.id = i.unidad_id
JOIN item_rollo_detalle ird     ON ird.item_id = i.id
JOIN articulo art               ON art.id = ird.articulo_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id
LEFT JOIN vw_colores vc         ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN tenido tn             ON tn.id = lrd.tenido_id
LEFT JOIN tercero c             ON c.id = l.propietario_id
GROUP BY
    sa.item_id, i.codigo, i.nombre, u.codigo,
    ird.articulo_id, art.nombre, art.articulo_tipo_id, ird.flg_rib, art.fibra,
    lrd.flg_tenido, lrd.flg_antipilling,
    lrd.color_x_cliente_id, vc.color_id, vc.color, vc.tono, vc.cliente_id,
    vc.color_hex, vc.color_x_cliente_hex,
    lrd.tenido_id, tn.tenido, lrd.ancho, lrd.malla, lrd.rendimiento,
    l.propietario_id, c.nombre
ORDER BY art.nombre, i.nombre;
*/

-- ── inventario.vw_stock_rollos_crudos ─────────────────────────
-- Undyed rolls in stock. One row per (item × propietario).
CREATE OR REPLACE VIEW inventario.vw_stock_rollos_crudos AS
SELECT
    sa.item_id,
    i.codigo                    AS item_codigo,
    i.nombre                    AS item_nombre,
    u.codigo                    AS unidad_codigo,
    ird.articulo_id,
    art.nombre                  AS articulo_nombre,
    art.articulo_tipo_id,
    ird.flg_rib,
    art.fibra,
    l.propietario_id,
    c.nombre                    AS propietario,
    COUNT(sa.lote_id)           AS cantidad_rollos,
    SUM(sa.cantidad_disponible) AS cantidad_total
FROM inventario.vw_stock_lotes sa
JOIN inventario.lote l              ON l.id = sa.lote_id
JOIN item i                         ON i.id = sa.item_id
JOIN item_tipo it                   ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN unidad u                       ON u.id = i.unidad_id
JOIN item_rollo_detalle ird         ON ird.item_id = i.id
JOIN articulo art                   ON art.id = ird.articulo_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id
LEFT JOIN tercero c                 ON c.id = l.propietario_id
WHERE lrd.flg_tenido IS NOT TRUE
GROUP BY
    sa.item_id, i.codigo, i.nombre, u.codigo,
    ird.articulo_id, art.nombre, art.articulo_tipo_id, ird.flg_rib, art.fibra,
    l.propietario_id, c.nombre
ORDER BY art.nombre, i.nombre;

-- ── inventario.vw_stock_rollos_tenidos ────────────────────────
-- Dyed (finished) rolls in stock. Grouped by full spec identity —
-- color, tenido, ancho, malla, rendimiento, antipilling, quality state.
-- Two rows with the same color but different malla are distinct stock units.
CREATE OR REPLACE VIEW inventario.vw_stock_rollos_tenidos AS
SELECT
    sa.item_id,
    i.codigo                    AS item_codigo,
    i.nombre                    AS item_nombre,
    u.codigo                    AS unidad_codigo,
    ird.articulo_id,
    art.nombre                  AS articulo_nombre,
    art.articulo_tipo_id,
    ird.flg_rib,
    art.fibra,
    lrd.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    vc.color_x_cliente_hex,
    vc.tercero_id,
    lrd.tenido_id,
    tn.tenido,
    lrd.flg_antipilling,
    lrd.ancho,
    lrd.malla,
    lrd.rendimiento,
    l.estado_calidad,
    l.propietario_id,
    c.nombre                    AS propietario,
    COUNT(sa.lote_id)           AS cantidad_rollos,
    SUM(sa.cantidad_disponible) AS cantidad_total
FROM inventario.vw_stock_lotes sa
JOIN inventario.lote l              ON l.id = sa.lote_id
JOIN item i                         ON i.id = sa.item_id
JOIN item_tipo it                   ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN unidad u                       ON u.id = i.unidad_id
JOIN item_rollo_detalle ird         ON ird.item_id = i.id
JOIN articulo art                   ON art.id = ird.articulo_id
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id AND lrd.flg_tenido = true
LEFT JOIN vw_colores vc             ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN tenido tn                 ON tn.id = lrd.tenido_id
LEFT JOIN tercero c                 ON c.id = l.propietario_id
GROUP BY
    sa.item_id, i.codigo, i.nombre, u.codigo,
    ird.articulo_id, art.nombre, art.articulo_tipo_id, ird.flg_rib, art.fibra,
    lrd.color_x_cliente_id, vc.color_id, vc.color, vc.tono, vc.color_hex,
    vc.color_x_cliente_hex, vc.tercero_id,
    lrd.tenido_id, tn.tenido, lrd.flg_antipilling,
    lrd.ancho, lrd.malla, lrd.rendimiento,
    l.estado_calidad, l.propietario_id, c.nombre
ORDER BY art.nombre, vc.color, i.nombre;

-- ── inventario.vw_stock_insumos ───────────────────────────────
-- Insumo stock totals with tipo/colorante attributes, location-agnostic.
-- Aggregates item_saldo across locations (item_saldo key is item_id + ubicacion_id).
CREATE OR REPLACE VIEW inventario.vw_stock_insumos AS
SELECT
    si.item_id,
    i.codigo                    AS item_codigo,
    i.nombre                    AS item_nombre,
    SUM(si.cantidad_actual)     AS cantidad_total,
    un.codigo                   AS unidad_codigo,
    iid.insumo_tipo_id,
    intp.codigo                 AS insumo_tipo_codigo,
    intp.nombre                 AS insumo_tipo_nombre,
    iid.colorante_tipo_id,
    ct.codigo                   AS colorante_tipo_codigo,
    ct.nombre                   AS colorante_tipo_nombre
FROM inventario.item_saldo si
JOIN item i        ON i.id = si.item_id
JOIN item_tipo it  ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
JOIN unidad un     ON un.id = i.unidad_id
LEFT JOIN item_insumo_detalle iid  ON iid.item_id = si.item_id
LEFT JOIN insumo_tipo intp         ON intp.id = iid.insumo_tipo_id
LEFT JOIN colorante_tipo ct        ON ct.id = iid.colorante_tipo_id
WHERE si.cantidad_actual > 0
GROUP BY si.item_id, i.codigo, i.nombre, un.codigo,
         iid.insumo_tipo_id, intp.codigo, intp.nombre,
         iid.colorante_tipo_id, ct.codigo, ct.nombre;

-- ── inventario.vw_precio_promedio_insumos ────────────────────
-- Weighted average cost per insumo item.
-- Primary source: factura_proveedor_detalle (what was actually invoiced).
-- Fallback: compra_detalle (estimated purchase price, used when no
-- invoice detail lines exist yet for that item).
-- Used for recipe cost reference and margin display — not balance sheet
-- inventory valuation.
CREATE OR REPLACE VIEW inventario.vw_precio_promedio_insumos AS
WITH fpd AS (
    -- Authoritative: invoiced prices
    SELECT
        fpd.item_id,
        SUM(fpd.cantidad * fpd.precio_unitario) AS valor_total,
        SUM(fpd.cantidad)                        AS cantidad_total
    FROM doc.factura_proveedor_detalle fpd
    GROUP BY fpd.item_id
),
cd AS (
    -- Fallback: purchase order prices
    SELECT
        cd.item_id,
        SUM(cd.cantidad * cd.precio_unitario) AS valor_total,
        SUM(cd.cantidad)                       AS cantidad_total
    FROM doc.compra_detalle cd
    -- Only use compra rows for items with no invoice detail yet
    WHERE NOT EXISTS (
        SELECT 1 FROM doc.factura_proveedor_detalle fpd
        WHERE fpd.item_id = cd.item_id
    )
    GROUP BY cd.item_id
),
combinado AS (
    SELECT item_id, valor_total, cantidad_total FROM fpd
    UNION ALL
    SELECT item_id, valor_total, cantidad_total FROM cd
)
SELECT
    c.item_id,
    vi.item_codigo,
    vi.item_nombre,
    vi.unidad_codigo,
    ROUND(SUM(c.valor_total) / NULLIF(SUM(c.cantidad_total), 0), 4) AS precio_promedio_usd,
    SUM(c.cantidad_total)                                            AS cantidad_comprada
FROM combinado c
JOIN vw_items vi ON vi.item_id = c.item_id
GROUP BY c.item_id, vi.item_codigo, vi.item_nombre, vi.unidad_codigo;

GRANT SELECT ON inventario.vw_precio_promedio_insumos TO authenticated;

-- ── inventario.vw_lotes_disponibles ──────────────────────────
CREATE OR REPLACE VIEW inventario.vw_lotes_disponibles AS
SELECT
    vi.item_id,
    vi.item_codigo,
    vi.item_nombre,
    vi.item_tipo_id,
    vi.item_tipo_codigo,
    sa.lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    sa.ubicacion_id,
    sa.cantidad_disponible,
    vi.unidad_id,
    vi.unidad_codigo
FROM inventario.vw_stock_lotes_ubicacion sa
LEFT JOIN vw_items vi ON vi.item_id = sa.item_id
LEFT JOIN inventario.lote l ON l.id = sa.lote_id;

-- ── calidad.vw_lotes_pendientes_inspeccion ────────────────────
-- Shows all ROLLO lotes pending QC:
--   Output rolls: created by a partida_paso_ejecucion (always eligible)
--   Input rolls:  assigned via partida_componente to an EN_PRODUCCION partida
-- Step/machine context comes from the ejecucion path (NULL for input rolls).
-- Partida context is resolved from whichever path applies.
-- DROP VIEW IF EXISTS calidad.vw_lotes_pendientes_inspeccion;
CREATE OR REPLACE VIEW calidad.vw_lotes_pendientes_inspeccion AS
SELECT
    l.id AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    l.documento_tipo,
    l.documento_id,
    COALESCE(pe.id,     active_ppe.ejecucion_id)        AS partida_paso_ejecucion_id,
    COALESCE(pp.id,     active_ppe.paso_id)             AS partida_paso_id,
    m.id                                                AS maquina_id,
    m.codigo                                            AS maquina_codigo,
    o.id                                                AS operacion_id,
    o.codigo                                            AS operacion_codigo,
    p.id                                                AS partida_id,
    p.partida_origen_id,
    EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text, 4, '0') AS partida_codigo,
    p.ancho,
    p.rendimiento,
    p.malla,
    p.flg_antipilling,
    p.prioridad_id,
    pr.prioridad,
    l.propietario_id,
    c.nombre AS cliente_nombre,
    l.fyh_cre AS fecha_creacion_lote
FROM inventario.lote l
JOIN vw_items vi ON vi.item_id = l.item_id AND vi.item_tipo_codigo = 'ROLLO'
LEFT JOIN mes.partida_paso_ejecucion pe
    ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
-- For input rolls: resolve the currently active paso ejecucion in the assigned partida
LEFT JOIN LATERAL (
    SELECT ppe.id           AS ejecucion_id,
           ppe.maquina_id   AS active_maquina_id,
           pp2.id           AS paso_id,
           pp2.operacion_id AS active_operacion_id
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp2 ON pp2.id = ppe.partida_paso_id
    WHERE pp2.partida_id = pc.partida_id
      AND ppe.estado = 'EN_PROCESO'
      AND pe.id IS NULL
    LIMIT 1
) active_ppe ON true
LEFT JOIN mes.operacion o ON o.id = COALESCE(pp.operacion_id, active_ppe.active_operacion_id)
LEFT JOIN mes.maquina m   ON m.id = COALESCE(pe.maquina_id,   active_ppe.active_maquina_id)
LEFT JOIN mes.partida p ON p.id = COALESCE(pp.partida_id, pc.partida_id)
LEFT JOIN tercero c    ON c.id  = l.propietario_id
LEFT JOIN prioridad pr ON pr.id = p.prioridad_id
WHERE (
    -- Output roll: ejecucion exists, no inspection recorded for it yet
    (pe.id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM calidad.inspeccion ci
        WHERE ci.lote_id = l.id AND ci.partida_paso_ejecucion_id = pe.id
    ))
    OR
    -- Input roll: currently active in a paso, no inspection recorded for that paso yet
    (active_ppe.ejecucion_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM calidad.inspeccion ci
        WHERE ci.lote_id = l.id AND ci.partida_paso_ejecucion_id = active_ppe.ejecucion_id
    ))
);

-- ── calidad.vw_inspecciones ───────────────────────────────────
CREATE OR REPLACE VIEW calidad.vw_inspecciones AS
SELECT
    i.id AS inspeccion_id,
    i.lote_id,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    i.partida_paso_ejecucion_id,
    i.resultado,
    i.observacion,
    i.empleado_id,
    e.nombre AS empleado_nombre,
    i.fyh_inspeccion
FROM calidad.inspeccion i
LEFT JOIN inventario.lote l ON l.id = i.lote_id
LEFT JOIN vw_items vi ON vi.item_id = l.item_id
LEFT JOIN mes.empleado e ON e.id = i.empleado_id;

-- ── calidad.vw_partidas_pendientes_calidad ────────────────────
-- Partida-level QC summary — aggregates over vw_lotes_pendientes_inspeccion.
-- lotes_en_produccion:   input rolls currently inside an EN_PROCESO paso
--                        (more output lotes may appear for QC when the step completes)
-- lotes_asignados_total: total input rolls reserved for this partida
-- tiene_rework_activo:   at least one non-closed rework partida linked to this one
-- partida_origen_id:     non-NULL means this row is itself a rework
DROP VIEW IF EXISTS calidad.vw_partidas_pendientes_calidad;
CREATE OR REPLACE VIEW calidad.vw_partidas_pendientes_calidad AS
WITH base AS (
    SELECT
        partida_id,
        partida_codigo,
        partida_origen_id,
        cliente_nombre,
        prioridad_id,
        operacion_codigo,
        lote_id,
        fecha_creacion_lote
    FROM calidad.vw_lotes_pendientes_inspeccion
    WHERE partida_id IS NOT NULL
),
agg AS (
    SELECT
        partida_id,
        partida_codigo,
        partida_origen_id,
        cliente_nombre,
        prioridad_id,
        COUNT(*)                                                             AS lotes_pendientes_qc,
        array_agg(DISTINCT operacion_codigo ORDER BY operacion_codigo)
            FILTER (WHERE operacion_codigo IS NOT NULL)                     AS operaciones_pendientes,
        MIN(fecha_creacion_lote)                                            AS lote_pendiente_mas_antiguo
    FROM base
    GROUP BY partida_id, partida_codigo, partida_origen_id, cliente_nombre, prioridad_id
)
SELECT
    a.partida_id,
    a.partida_codigo,
    a.partida_origen_id,
    a.cliente_nombre,
    a.prioridad_id,
    a.lotes_pendientes_qc,
    a.operaciones_pendientes,
    a.lote_pendiente_mas_antiguo,
    (
        SELECT COUNT(DISTINCT pc.lote_id)
        FROM mes.partida_componente pc
        WHERE pc.partida_id = a.partida_id
          AND pc.lote_id IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM mes.partida_paso pp
              JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
              WHERE pp.partida_id = a.partida_id
                AND ppe.estado = 'EN_PROCESO'
          )
    )                                                                        AS lotes_en_produccion,
    (
        SELECT COUNT(*)
        FROM mes.partida_componente
        WHERE partida_id = a.partida_id AND lote_id IS NOT NULL
    )                                                                        AS lotes_asignados_total,
    EXISTS (
        SELECT 1 FROM mes.partida rw
        WHERE rw.partida_origen_id = a.partida_id
          AND rw.estado_produccion NOT IN ('CANCELADA', 'TECO', 'CERRADA')
    )                                                                        AS tiene_rework_activo
FROM agg a
ORDER BY a.lote_pendiente_mas_antiguo;

-- ── mes.vw_empleados_activos ───────────────────────────────────
CREATE OR REPLACE VIEW mes.vw_empleados_activos AS
SELECT
    e.id,
    e.nombre,
    e.apellido,
    e.nombre || ' ' || e.apellido AS nombre_completo,
    e.rol_id,
    er.nombre AS rol_nombre,
    e.turno_id
FROM mes.empleado e
JOIN mes.empleado_rol er ON er.id = e.rol_id
WHERE e.activo = true;

-- ── mes.vw_pasos ──────────────────────────────────────────────
-- Execution columns (estado, fyh_inicio/fin, maquina, empleado) come from the
-- latest partida_paso_ejecucion row — they were removed from partida_paso in step 04.
-- maquina_planificada_id replaces the dropped maquina_asignada_id on partida_paso.
CREATE OR REPLACE VIEW mes.vw_pasos AS
SELECT
    pp.id                                                                  AS paso_id,
    pp.secuencia,
    pp.partida_id,
    p.numero                                                               AS partida_numero,
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || LPAD(p.numero::TEXT, 4, '0')  AS partida_codigo,
    p.tercero_id,
    c.nombre                                                               AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.color_hex,
    pp.operacion_id,
    o.codigo                                                               AS operacion_codigo,
    o.nombre                                                               AS operacion_nombre,
    o.requiere_receta,
    o.requiere_maquina,
    pp.maquina_planificada_id,
    pp.receta_id,
    -- Planning targets
    pp.ph_objetivo,
    pp.temperatura_objetivo,
    pp.relacion_bano_objetivo,
    pp.tiempo_estandar,
    -- Active machine: actual (from ejecucion) falls back to planned
    m.id                                                                   AS maquina_id,
    m.codigo                                                               AS maquina_codigo,
    m.nombre                                                               AS maquina_nombre,
    -- Execution data from latest ejecucion run
    pe.id                                                                  AS ejecucion_id,
    pe.empleado_id,
    pe.fyh_inicio,
    pe.fyh_fin,
    pe.ph_real,
    pe.temperatura_real,
    pe.relacion_bano_real,
    pe.cantidad,
    pe.notas,
    -- Scheduling context
    prog.id                                                                AS programacion_id,
    prog.fecha                                                             AS fecha_programada,
    prog.secuencia                                                         AS secuencia_programada,
    -- Derived execution state: PENDIENTE when no ejecucion rows exist
    CASE
        WHEN pe.id IS NOT NULL AND pe.estado = 'COMPLETADO' THEN 'COMPLETADO'
        WHEN pe.id IS NOT NULL AND pe.estado = 'EN_PROCESO' THEN 'EN_PROCESO'
        WHEN pe.id IS NOT NULL AND pe.estado = 'OMITIDO'    THEN 'OMITIDO'
        ELSE 'PENDIENTE'
    END                                                                    AS estado
FROM mes.partida_paso pp
JOIN mes.partida p      ON p.id  = pp.partida_id
JOIN mes.operacion o    ON o.id  = pp.operacion_id
LEFT JOIN tercero c     ON c.id  = p.tercero_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN LATERAL (
    SELECT id, estado, maquina_id, empleado_id,
           fyh_inicio, fyh_fin, ph_real, temperatura_real,
           relacion_bano_real, cantidad, notas
    FROM mes.partida_paso_ejecucion
    WHERE partida_paso_id = pp.id
    ORDER BY fyh_inicio DESC NULLS LAST
    LIMIT 1
) pe ON true
LEFT JOIN mes.maquina m ON m.id = COALESCE(pe.maquina_id, pp.maquina_planificada_id)
LEFT JOIN mes.programacion prog ON prog.actividad_tipo = 'partida_paso'
                                AND prog.actividad_id  = pp.id;

-- ── inventario.vw_items_movimientos ───────────────────────────
CREATE OR REPLACE VIEW inventario.vw_items_movimientos AS
SELECT
    im.id                                                             AS movimiento_id,
    im.fecha_hora,
    im.item_id,
    vi.item_codigo,
    vi.item_nombre,
    im.lote_id,
    CASE WHEN l.id IS NOT NULL
        THEN EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0')
    END                                                               AS lote_codigo,
    im.item_movimiento_tipo_id,
    imt.codigo                                                        AS tipo_codigo,
    imt.nombre                                                        AS tipo_nombre,
    imt.categoria,
    im.cantidad,
    im.cantidad * (
        CASE WHEN im.destino_ubicacion_id IS NOT NULL THEN  1 ELSE 0 END +
        CASE WHEN im.origen_ubicacion_id  IS NOT NULL THEN -1 ELSE 0 END
    )                                                                 AS cantidad_neta,
    im.origen_ubicacion_id,
    uo.nombre                                                         AS origen_nombre,
    im.destino_ubicacion_id,
    ud.nombre                                                         AS destino_nombre,
    im.documento_tipo,
    im.documento_id,
    im.observacion
FROM inventario.item_movimientos im
LEFT JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
LEFT JOIN vw_items vi ON vi.item_id = im.item_id
LEFT JOIN inventario.lote l ON l.id = im.lote_id
LEFT JOIN inventario.ubicacion uo ON uo.id = im.origen_ubicacion_id
LEFT JOIN inventario.ubicacion ud ON ud.id = im.destino_ubicacion_id;

-- ── public.vw_dashboard_kpis ──────────────────────────────────
-- Single-row view for stat cards. Frontend calls .from('vw_dashboard_kpis').single().
-- Month-over-month creation counts let the frontend compute the diff %.
CREATE OR REPLACE VIEW public.vw_dashboard_kpis AS
WITH
  ini_mes AS (SELECT date_trunc('month', now()) AS d),
  ini_ant AS (SELECT date_trunc('month', now()) - interval '1 month' AS d),

  partidas_kpi AS (
    SELECT
      COUNT(*) FILTER (WHERE estado_produccion NOT IN ('CERRADA','CANCELADA'))          AS activas,
      COUNT(*) FILTER (WHERE fyh_cre >= (SELECT d FROM ini_mes))                        AS creadas_mes_actual,
      COUNT(*) FILTER (WHERE fyh_cre >= (SELECT d FROM ini_ant)
                         AND fyh_cre <  (SELECT d FROM ini_mes))                        AS creadas_mes_anterior
    FROM mes.partida
  ),

  ordenes_kpi AS (
    SELECT
      COUNT(*) FILTER (WHERE estado_produccion NOT IN ('CERRADA','CANCELADA')) AS activas,
      COUNT(*) FILTER (WHERE fyh_cre >= (SELECT d FROM ini_mes))               AS creadas_mes_actual,
      COUNT(*) FILTER (WHERE fyh_cre >= (SELECT d FROM ini_ant)
                         AND fyh_cre <  (SELECT d FROM ini_mes))               AS creadas_mes_anterior
    FROM mes.partida
  ),

  pasos_kpi AS (
    SELECT
      COUNT(*) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id
      ))                                                                        AS pendientes,
      COUNT(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
      ))                                                                        AS en_partida
    FROM mes.partida_paso pp
    JOIN mes.partida p ON p.id = pp.partida_id
    WHERE p.estado_produccion NOT IN ('CERRADA','CANCELADA')
  ),

  rollos_kpi AS (
    SELECT
      COUNT(DISTINCT sa.lote_id)                                       AS rollos_en_planta,
      SUM(sa.cantidad_disponible)                                      AS kg_en_planta,
      COUNT(DISTINCT sa.lote_id) FILTER (
          WHERE l.fyh_cre >= (SELECT d FROM ini_mes))                  AS recibidos_mes_actual,
      COUNT(DISTINCT sa.lote_id) FILTER (
          WHERE l.fyh_cre >= (SELECT d FROM ini_ant)
            AND l.fyh_cre <  (SELECT d FROM ini_mes))                  AS recibidos_mes_anterior
    FROM inventario.vw_stock_lotes sa
    JOIN inventario.lote l ON l.id = sa.lote_id
    JOIN item i             ON i.id  = sa.item_id
    JOIN item_tipo it       ON it.id = i.item_tipo_id
    WHERE it.codigo = 'ROLLO'
  )

SELECT
  p.activas                  AS partidas_activas,
  p.creadas_mes_actual       AS partidas_creadas_mes_actual,
  p.creadas_mes_anterior     AS partidas_creadas_mes_anterior,
  o.activas                  AS ordenes_activas,
  o.creadas_mes_actual       AS ordenes_creadas_mes_actual,
  o.creadas_mes_anterior     AS ordenes_creadas_mes_anterior,
  ps.pendientes              AS pasos_pendientes,
  ps.en_partida              AS pasos_en_partida,
  r.rollos_en_planta,
  r.kg_en_planta,
  r.recibidos_mes_actual     AS rollos_recibidos_mes_actual,
  r.recibidos_mes_anterior   AS rollos_recibidos_mes_anterior
FROM partidas_kpi p, ordenes_kpi o, pasos_kpi ps, rollos_kpi r;

-- ── public.vw_dashboard_actividad_reciente ────────────────────
-- Recent business events feed (last 20, up to 30-day window).
-- Sources: partidas created, ordenes finalized, pasos completed.
CREATE OR REPLACE VIEW public.vw_dashboard_actividad_reciente AS
SELECT tipo, descripcion, fyh, referencia_id, referencia_codigo
FROM (
  SELECT
    'PARTIDA_CREADA'   AS tipo,
    'Partida creada' || COALESCE(' — ' || te.nombre, '') AS descripcion,
    p.fyh_cre          AS fyh,
    p.id               AS referencia_id,
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || LPAD(p.numero::TEXT, 4, '0') AS referencia_codigo
  FROM mes.partida p
  LEFT JOIN tercero te ON te.id = p.tercero_id
  WHERE p.fyh_cre >= now() - interval '30 days'

  UNION ALL

  SELECT
    'PARTIDA_CERRADA',
    'Partida #' || p.numero::TEXT || ' cerrada',
    p.fyh_fin,
    p.id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0')
  FROM mes.partida p
  WHERE p.fyh_fin >= now() - interval '30 days'
    AND p.fyh_fin <= now()
    AND p.estado_produccion = 'CERRADA'

  UNION ALL

  SELECT
    'PASO_COMPLETADO',
    'Paso completado: ' || o.nombre,
    pe.fyh_fin,
    pp.id,
    pp.id::TEXT
  FROM mes.partida_paso pp
  JOIN mes.operacion o ON o.id = pp.operacion_id
  JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
  WHERE pe.fyh_fin >= now() - interval '7 days'
    AND pe.estado = 'COMPLETADO'
) feed
ORDER BY fyh DESC
LIMIT 20;

-- ── public.vw_dashboard_tareas ────────────────────────────────
-- Actionable task counts for the "Tareas Pendientes" card.
-- Zero-count rows are filtered out — empty on a clean day.
CREATE OR REPLACE VIEW public.vw_dashboard_tareas AS
SELECT tipo, descripcion, count, urgencia
FROM (
  SELECT
    'SIN_RUTA'    AS tipo,
    'Partidas confirmadas sin ruta de producción' AS descripcion,
    COUNT(*)::INT AS count,
    'alta'        AS urgencia
  FROM mes.partida p
  WHERE p.estado_produccion = 'CREADA'
    AND NOT EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id = p.id)

  UNION ALL

  SELECT
    'PASO_VENCIDO',
    'Pasos con más de 24h en ejecución',
    COUNT(*)::INT,
    'alta'
  FROM mes.partida_paso pp
  JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
  WHERE pe.estado = 'EN_PROCESO'
    AND pe.fyh_inicio < now() - interval '24 hours'

  UNION ALL

  SELECT
    'FECHA_PROXIMA',
    'Partidas con entrega en ≤ 3 días',
    COUNT(*)::INT,
    'alta'
  FROM mes.partida
  WHERE estado_produccion IN ('CREADA','PLANIFICADA','PROGRAMADA','EN_PRODUCCION','TECO')
    AND fecha_acordada BETWEEN CURRENT_DATE AND CURRENT_DATE + 3

  UNION ALL

  SELECT
    'SIN_MAQUINA',
    'Pasos en ejecución sin máquina asignada',
    COUNT(*)::INT,
    'media'
  FROM mes.partida_paso pp
  JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
  WHERE pe.estado = 'EN_PROCESO' AND pe.maquina_id IS NULL
) t
WHERE count > 0
ORDER BY CASE urgencia WHEN 'alta' THEN 1 ELSE 2 END;

-- ── inventario.vw_guias_rollos_pendientes ─────────────────────
-- Guias with at least one in-stock roll not yet assigned to a partida.
-- Drops off automatically once all rolls are assigned or leave stock.
-- Mirrors the condition used by alertas.check_rollos_sin_programar.
CREATE OR REPLACE VIEW inventario.vw_guias_rollos_pendientes AS
SELECT
    gr.id                                       AS guia_remision_id,
    gr.serie || '-' || gr.correlativo           AS guia_numero,
    gr.fecha_emision,
    gr.tercero_id,
    t.nombre                                    AS tercero_nombre,
    (CURRENT_DATE - gr.fecha_emision::DATE)     AS dias_espera,
    COUNT(l.id)                                 AS total_rollos,
    COUNT(l.id) FILTER (WHERE pc.lote_id IS NULL)      AS rollos_pendientes,
    COUNT(l.id) FILTER (WHERE pc.lote_id IS NOT NULL)  AS rollos_asignados,
    SUM(sl.cantidad_disponible) FILTER (WHERE pc.lote_id IS NULL)     AS peso_pendiente_kg,
    SUM(sl.cantidad_disponible) FILTER (WHERE pc.lote_id IS NOT NULL) AS peso_asignado_kg,
    SUM(sl.cantidad_disponible)                 AS peso_total_kg
FROM doc.guia_remision gr
JOIN doc.guia_remision_tipo grt         ON grt.id = gr.guia_remision_tipo_id
                                        AND grt.codigo = 'CLIENTE_ENVIO_PROCESO'
JOIN tercero t                          ON t.id = gr.tercero_id
JOIN inventario.lote_rollo_detalle lrd  ON lrd.guia_remision_id = gr.id
JOIN inventario.lote l                  ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
JOIN inventario.vw_stock_lotes sl       ON sl.lote_id = l.id
LEFT JOIN mes.partida_componente pc     ON pc.lote_id = l.id
GROUP BY gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id, t.nombre
HAVING COUNT(l.id) FILTER (WHERE pc.lote_id IS NULL) > 0;

GRANT SELECT ON inventario.vw_guias_rollos_pendientes TO authenticated;

-- ── inventario.vw_rollos_por_guia ────────────────────────────
-- Roll counts and weights aggregated per ingress guia.
-- Used for intake review and guia → partida assignment UI.
-- Only covers rolls with a guia (MLR-confectioned rolls excluded).
CREATE OR REPLACE VIEW inventario.vw_rollos_por_guia AS
SELECT
    gr.id                               AS guia_remision_id,
    gr.serie,
    gr.correlativo,
    gr.serie || '-' || gr.correlativo   AS guia_numero,
    gr.fecha_emision,
    gr.tercero_id,
    t.nombre                            AS tercero_nombre,
    grt.codigo                          AS guia_tipo,
    COUNT(lrd.lote_id)                  AS total_rollos,
    COUNT(lrd.lote_id) FILTER (WHERE lrd.flg_tenido = false) AS rollos_crudos,
    COUNT(lrd.lote_id) FILTER (WHERE lrd.flg_tenido = true)  AS rollos_tenidos,
    SUM(l.cantidad)                     AS peso_total_kg,
    -- Stock status
    COUNT(sa.lote_id)                   AS rollos_en_stock,
    SUM(sa.cantidad_disponible)         AS peso_en_stock_kg
FROM doc.guia_remision gr
JOIN doc.guia_remision_tipo grt         ON grt.id = gr.guia_remision_tipo_id
JOIN tercero t                          ON t.id = gr.tercero_id
JOIN inventario.lote_rollo_detalle lrd  ON lrd.guia_remision_id = gr.id
JOIN inventario.lote l                  ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
LEFT JOIN inventario.vw_stock_lotes sa ON sa.lote_id = l.id
GROUP BY gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id,
         t.nombre, grt.codigo;

-- ── inventario.vw_pesaje_pendiente ─────────────────────────────
-- One row per (partida, guia_remision, item) for partidas that have
-- a TENIDO paso scheduled AND at least one assigned roll with no
-- pesaje record.
-- Business rule: if any roll in the partida is unweighed the whole
-- batch must be reweighed (prorated flow), so the filter is at
-- partida level — ALL rolls for that partida are shown, not just
-- the unweighed ones.
-- Drives the print-friendly weighing form: the frontend groups by
-- partida → guia → item to build the grid.
--
-- Partida header columns repeat on every row (denormalised for ease
-- of use — the frontend can read them from the first row per group).
-- fecha_programada: earliest scheduling board date for the TENIDO paso.
-- rollos: total assigned rolls for this (partida, guia, item) cell.
-- flg_rib: true = rib item, false = regular. Lets the frontend style
--   rows differently without parsing item names.
DROP VIEW IF EXISTS mes.vw_pesaje_pendiente;
CREATE OR REPLACE VIEW mes.vw_pesaje_pendiente AS
SELECT
    -- ── Partida header (repeats per row) ──────────────────────
    p.id                                                                      AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                              AS partida_codigo,
    p.tercero_id,
    ter.nombre                                                                AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.color_hex,
    p.tenido_id,
    t.tenido,
    p.articulo_tipo_id,
    at.nombre                                                                 AS articulo_tipo,
    p.fibra,
    p.malla,
    p.rendimiento,
    p.ancho,
    p.fecha_acordada,
    -- Earliest scheduling board date for the TENIDO paso
    (
        SELECT MIN(pr.fecha)
        FROM mes.partida_paso  pp2
        JOIN mes.operacion     op2 ON op2.id = pp2.operacion_id
                                   AND op2.codigo = 'TENIDO'
        JOIN mes.programacion  pr  ON pr.actividad_tipo = 'partida_paso'
                                   AND pr.actividad_id  = pp2.id
        WHERE pp2.partida_id = p.id
    )                                                                         AS fecha_programada,

    -- ── Guia ──────────────────────────────────────────────────
    gr.id                                                                     AS guia_remision_id,
    gr.serie || '-' || gr.correlativo                                         AS guia_numero,

    -- ── Item ──────────────────────────────────────────────────
    l.item_id,
    i.codigo                                                                  AS item_codigo,
    i.nombre                                                                  AS item_nombre,
    ird.flg_rib,

    -- ── Roll count for this (partida, guia, item) cell ────────
    COUNT(*)::INT                                                             AS rollos

FROM mes.partida p
LEFT JOIN tercero       ter ON ter.id = p.tercero_id
LEFT JOIN vw_colores    vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido        t   ON t.id  = p.tenido_id
LEFT JOIN articulo_tipo at  ON at.id = p.articulo_tipo_id

-- Walk from partida down to the actual rolls
JOIN mes.partida_componente            pc  ON pc.partida_id = p.id
                                          AND pc.lote_id IS NOT NULL
JOIN inventario.lote                   l   ON l.id  = pc.lote_id
                                          AND l.fyh_elm IS NULL
JOIN item                              i   ON i.id  = l.item_id
JOIN item_rollo_detalle                ird ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
LEFT JOIN doc.guia_remision             gr  ON gr.id = lrd.guia_remision_id

WHERE p.fyh_elm IS NULL

  -- Condition 1: has at least one TENIDO paso on the scheduling board
  AND EXISTS (
      SELECT 1
      FROM mes.partida_paso  pp
      JOIN mes.operacion     op ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
      JOIN mes.programacion  pr ON pr.actividad_tipo = 'partida_paso'
                               AND pr.actividad_id   = pp.id
      WHERE pp.partida_id = p.id
  )

  -- Condition 2: at least one assigned roll has no pesaje record yet
  -- (triggers full-batch reweigh — all rolls shown, not just unweighed ones)
  AND EXISTS (
      SELECT 1
      FROM mes.partida_componente pc2
      LEFT JOIN inventario.pesaje ps ON ps.lote_id = pc2.lote_id
      WHERE pc2.partida_id = p.id
        AND pc2.lote_id IS NOT NULL
        AND ps.lote_id IS NULL
  )

GROUP BY
    p.id, p.numero, p.fyh_cre,
    p.tercero_id, ter.nombre,
    p.color_x_cliente_id, vc.color, vc.color_hex,
    p.tenido_id, t.tenido,
    p.articulo_tipo_id, at.nombre,
    p.fibra, p.malla, p.rendimiento, p.ancho, p.fecha_acordada,
    gr.id, gr.serie, gr.correlativo,
    l.item_id, i.codigo, i.nombre, ird.flg_rib;

-- ── Grants ────────────────────────────────────────────────────
GRANT SELECT ON mes.vw_pesaje_pendiente             TO authenticated;
GRANT SELECT ON inventario.vw_rollos_por_guia              TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_stock            TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_disponibles      TO anon, authenticated;
-- GRANT SELECT ON inventario.vw_stock_rollos              TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_rollos_crudos          TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_rollos_tenidos         TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_items                  TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_items_ubicacion        TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_items_valorado         TO authenticated;
GRANT SELECT ON inventario.vw_stock_insumos                TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_disponibles            TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_despachados     TO anon, authenticated;
GRANT SELECT ON inventario.vw_items_movimientos            TO anon, authenticated;
GRANT SELECT ON mes.vw_maquinas                   TO authenticated;
GRANT SELECT ON mes.vw_empleados_activos          TO authenticated;
GRANT SELECT ON mes.vw_pasos                      TO anon, authenticated;
GRANT SELECT ON mes.vw_partida_produccion_rollos  TO anon, authenticated;
GRANT SELECT ON calidad.vw_lotes_pendientes_inspeccion    TO authenticated;
GRANT SELECT ON calidad.vw_inspecciones                   TO authenticated;
GRANT SELECT ON calidad.vw_partidas_pendientes_calidad    TO authenticated;
GRANT SELECT ON mes.vw_partida_resumen_tenido              TO authenticated;
GRANT SELECT ON public.vw_dashboard_kpis                   TO authenticated;
GRANT SELECT ON public.vw_dashboard_actividad_reciente     TO authenticated;
GRANT SELECT ON public.vw_dashboard_tareas                 TO authenticated;

GRANT SELECT ON ALL TABLES IN SCHEMA doc        TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA mes        TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA inventario TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA calidad    TO authenticated;
GRANT USAGE ON SCHEMA mes        TO authenticated;
GRANT USAGE ON SCHEMA doc        TO authenticated;
GRANT USAGE ON SCHEMA inventario TO authenticated;
GRANT USAGE ON SCHEMA calidad    TO authenticated;
GRANT INSERT ON calidad.inspeccion      TO authenticated;
GRANT INSERT ON calidad.inspeccion_foto TO authenticated;
GRANT INSERT, UPDATE ON mes.operacion   TO authenticated;


/*
-- ═══════════════════════════════════════════════════════════════
-- REVERSAL — undoes step 8 in full. Run then comment back out.
-- Views that depend on other views here are covered by CASCADE.
-- Non-view grants (INSERT/UPDATE on tables, schema USAGE) must
-- be revoked explicitly — dropping the views doesn't touch them.
-- ═══════════════════════════════════════════════════════════════

-- public views
DROP VIEW IF EXISTS public.vw_dashboard_tareas             CASCADE;
DROP VIEW IF EXISTS public.vw_dashboard_actividad_reciente CASCADE;
DROP VIEW IF EXISTS public.vw_dashboard_kpis               CASCADE;

-- calidad views
DROP VIEW IF EXISTS calidad.vw_partidas_pendientes_calidad CASCADE;
DROP VIEW IF EXISTS calidad.vw_inspecciones                CASCADE;
DROP VIEW IF EXISTS calidad.vw_lotes_pendientes_inspeccion CASCADE;

-- mes views
DROP VIEW IF EXISTS mes.vw_pasos                           CASCADE;
DROP VIEW IF EXISTS mes.vw_empleados_activos               CASCADE;
DROP VIEW IF EXISTS mes.vw_maquinas                        CASCADE;
DROP VIEW IF EXISTS mes.vw_partida_resumen_tenido          CASCADE;
DROP VIEW IF EXISTS mes.vw_partida_produccion_rollos       CASCADE;
DROP VIEW IF EXISTS mes.vw_partidas                        CASCADE;

-- inventario views (dependent on vw_stock_lotes — drop before it)
DROP VIEW IF EXISTS inventario.vw_pesaje_pendiente         CASCADE;
DROP VIEW IF EXISTS inventario.vw_guias_rollos_pendientes  CASCADE;
DROP VIEW IF EXISTS inventario.vw_rollos_por_guia          CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_despachados CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_disponibles CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock       CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_rollos_tenidos     CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_rollos_crudos      CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_items_valorado     CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_items_ubicacion    CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_items              CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_insumos            CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_disponibles        CASCADE;
DROP VIEW IF EXISTS inventario.vw_precio_promedio_insumos  CASCADE;
DROP VIEW IF EXISTS inventario.vw_item_proveedor_guia      CASCADE;
DROP VIEW IF EXISTS inventario.vw_items_movimientos        CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_lotes_ubicacion    CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_lotes              CASCADE;

-- doc views
DROP VIEW IF EXISTS doc.vw_letras                          CASCADE;
DROP VIEW IF EXISTS doc.vw_cuentas_por_pagar               CASCADE;
DROP VIEW IF EXISTS doc.vw_compras_item_mes                CASCADE;
DROP VIEW IF EXISTS doc.vw_facturas_proveedor              CASCADE;
DROP VIEW IF EXISTS doc.vw_compras_recepcion               CASCADE;
DROP VIEW IF EXISTS doc.vw_compras                         CASCADE;

-- public base views (other views may depend — drop last)
DROP VIEW IF EXISTS vw_items                               CASCADE;
DROP VIEW IF EXISTS vw_colores                             CASCADE;

-- Non-view grants on tables (not removed by DROP VIEW)
REVOKE INSERT ON calidad.inspeccion      FROM authenticated;
REVOKE INSERT ON calidad.inspeccion_foto FROM authenticated;
REVOKE UPDATE ON mes.operacion           FROM authenticated;

-- Schema USAGE grants added in this file
-- (doc USAGE was also granted in step 7 — leave that revoke to step 7's reversal)
REVOKE USAGE ON SCHEMA mes        FROM authenticated;
REVOKE USAGE ON SCHEMA inventario FROM authenticated;
REVOKE USAGE ON SCHEMA calidad    FROM authenticated;
*/

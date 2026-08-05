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
-- lrd.entrega_id is the unified origin for all roll types:
--   client-supplied rolls → guia-type entrega
--   MLR-confectioned rolls → INGRESO_INTERNO entrega (post patch-35)
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock CASCADE;
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
    lrd.entrega_id,
    gr.serie                        AS entrega_serie,
    gr.correlativo                  AS entrega_correlativo
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN inventario.lote l                      ON l.id = sa.lote_id
JOIN item i                                 ON i.id = sa.item_id
JOIN item_tipo it                           ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN item_rollo_detalle ird                 ON ird.item_id = i.id
JOIN articulo art                           ON art.id = ird.articulo_id
JOIN unidad un                              ON un.id = i.unidad_id
LEFT JOIN inventario.ubicacion u            ON u.id = sa.ubicacion_id
LEFT JOIN inventario.almacen a              ON a.id = u.almacen_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id
LEFT JOIN doc.entrega gr                    ON gr.id = lrd.entrega_id
LEFT JOIN tercero t                         ON t.id = l.propietario_id
LEFT JOIN vw_colores vc                     ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN tenido tn                         ON tn.id = lrd.tenido_id;

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
DROP VIEW IF EXISTS mes.vw_partidas CASCADE;
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
    p.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    p.tenido_id,
    t.tenido,
    p.grupo_articulo_id,
    ga.nombre                                                              AS grupo_articulo,
    p.fibra,
    p.flg_antipilling,
    p.flg_doble_bolsa,
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
    p.fyh_elm,
    p.observacion
FROM mes.partida p
LEFT JOIN tercero c        ON c.id  = p.tercero_id
LEFT JOIN vw_colores vc    ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido t         ON t.id  = p.tenido_id
LEFT JOIN grupo_articulo ga ON ga.id = p.grupo_articulo_id
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

-- ── mes.vw_partida_familia_output ──────────────────────────────
-- SINGLE SOURCE OF TRUTH for family-level fulfillment. One row per
-- *terminal deliverable* output roll across a rework family (root partida
-- + its reprocesos). Read by mes.vw_partida_familia, mes.get_partida_familia
-- and mes.cerrar_partida so "produced vs intended" is defined in ONE place.
--
-- "Terminal deliverable" = an output lote (created by a partida_paso_ejecucion)
-- that is:
--   • alive          — fyh_elm IS NULL (not scrapped / dado de baja), AND
--   • not re-consumed — net PROD_CONSUMO <= 0.
-- The second filter is what DEDUPES reworked rolls: when a child re-dyes a
-- roll it consumes the parent's output lote (PROD_CONSUMO) and emits a fresh
-- one. The consumed parent lote drops out here; only the child's new output
-- survives. A roll merely *dispatched* (VENTA_EGR/SERV_EGR) keeps counting —
-- delivery is fulfillment, rework is not. PROD_CONSUMO_REV (annulled
-- consumption) restores the lote automatically via the net sum.
--
-- root_id flattens the rework topology: every member resolves to the original
-- via COALESCE(partida_origen_id, id) — same rule as mes.crear_reproceso.
CREATE OR REPLACE VIEW mes.vw_partida_familia_output AS
SELECT
    COALESCE(p.partida_origen_id, p.id)   AS root_id,
    p.id                                  AS partida_id,
    (p.partida_origen_id IS NOT NULL)     AS es_reproceso,
    l.id                                  AS lote_id,
    l.item_id,
    l.estado_calidad,
    l.cantidad
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
                                  AND l.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p       ON p.id = pp.partida_id
WHERE l.fyh_elm IS NULL
  AND (
        SELECT COALESCE(SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO'     THEN 1
                                 WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN -1
                                 ELSE 0 END), 0)
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = l.id
      ) <= 0;

GRANT SELECT ON mes.vw_partida_familia_output TO anon, authenticated;

-- ── mes.vw_partida_familia ─────────────────────────────────────
-- COMMERCIAL rollup: one row per rework family, keyed on the ROOT partida.
-- Folds every reproceso child into the original so a board/list shows
-- fulfillment-vs-intent without drilling into each rework. Children are
-- excluded from the result (partida_origen_id IS NULL filter) — they appear
-- only as part of their parent's aggregated numbers.
--
--   demanda_rollos          intended output. Intent lives ONLY on the root's
--                           partida_detalle; a child's detalle is a rework count
--                           of the SAME rolls and is never added.
--   producido_bueno         terminal APROBADO rolls across the family
--   producido_pendiente     terminal rolls still awaiting QC (PENDIENTE)
--   producido_reproceso     terminal rolls flagged REPROCESO, not yet reworked
--   producido_terminal      all terminal rolls (any QC state)
--   faltante                GREATEST(0, demanda - producido_bueno)
--   porcentaje_cumplimiento producido_bueno / demanda * 100
--   flg_cumplida            producido_bueno >= demanda (and demanda > 0)
--   num_reprocesos          count of rework children
--   tiene_rework_activo     a child still open (not TECO/CERRADA/CANCELADA)
DROP VIEW IF EXISTS mes.vw_partida_familia CASCADE;
CREATE OR REPLACE VIEW mes.vw_partida_familia AS
WITH demanda AS (
    SELECT pd.partida_id AS root_id, SUM(pd.cantidad) AS demanda_rollos
    FROM mes.partida_detalle pd
    GROUP BY pd.partida_id
),
salida AS (
    SELECT
        root_id,
        COUNT(*) FILTER (WHERE estado_calidad = 'APROBADO')  AS producido_bueno,
        COUNT(*) FILTER (WHERE estado_calidad = 'PENDIENTE') AS producido_pendiente,
        COUNT(*) FILTER (WHERE estado_calidad = 'REPROCESO') AS producido_reproceso,
        COUNT(*)                                             AS producido_terminal
    FROM mes.vw_partida_familia_output
    GROUP BY root_id
)
SELECT
    r.id                                          AS partida_id,
    EXTRACT(YEAR FROM r.fyh_cre)::TEXT
        || '-' || LPAD(r.numero::TEXT, 4, '0')    AS codigo,
    r.tercero_id,
    c.nombre                                      AS cliente,
    r.grupo_articulo_id,
    ga.nombre                                     AS grupo_articulo,
    r.color_x_cliente_id,
    vc.color,
    vc.color_hex,
    r.estado_produccion,
    r.estado_comercial,
    r.estado_facturacion,
    r.prioridad_id,
    pr.prioridad,
    r.fecha_acordada,
    r.fyh_cre,
    COALESCE(d.demanda_rollos, 0)                 AS demanda_rollos,
    COALESCE(s.producido_bueno, 0)                AS producido_bueno,
    COALESCE(s.producido_pendiente, 0)            AS producido_pendiente,
    COALESCE(s.producido_reproceso, 0)            AS producido_reproceso,
    COALESCE(s.producido_terminal, 0)             AS producido_terminal,
    GREATEST(0, COALESCE(d.demanda_rollos, 0) - COALESCE(s.producido_bueno, 0))
                                                  AS faltante,
    ROUND(COALESCE(s.producido_bueno, 0)::numeric
          / NULLIF(COALESCE(d.demanda_rollos, 0), 0) * 100, 0)
                                                  AS porcentaje_cumplimiento,
    (COALESCE(s.producido_bueno, 0) >= COALESCE(d.demanda_rollos, 0)
       AND COALESCE(d.demanda_rollos, 0) > 0)     AS flg_cumplida,
    (SELECT COUNT(*) FROM mes.partida rw WHERE rw.partida_origen_id = r.id)
                                                  AS num_reprocesos,
    EXISTS (
        SELECT 1 FROM mes.partida rw
        WHERE rw.partida_origen_id = r.id
          AND rw.estado_produccion NOT IN ('TECO', 'CERRADA', 'CANCELADA')
    )                                             AS tiene_rework_activo
FROM mes.partida r
LEFT JOIN demanda d        ON d.root_id = r.id
LEFT JOIN salida  s        ON s.root_id = r.id
LEFT JOIN tercero c        ON c.id  = r.tercero_id
LEFT JOIN grupo_articulo ga ON ga.id = r.grupo_articulo_id
LEFT JOIN vw_colores vc    ON vc.color_x_cliente_id = r.color_x_cliente_id
LEFT JOIN prioridad pr     ON pr.id = r.prioridad_id
WHERE r.partida_origen_id IS NULL      -- roots only; children fold into the parent
  AND r.fyh_elm IS NULL;

GRANT SELECT ON mes.vw_partida_familia TO anon, authenticated;

-- ── doc.vw_compras ────────────────────────────────────────────
-- List view for purchase orders.
-- estado_ingreso: derived from compra_detalle.cantidad_recibida
--   (synced by ingresar_compra and vincular_entregas_compra via
--   fn_refresh_compra_detalle_qtys — covers both PO-first and orderless flows).
--   'sin_lineas'  → compra header only, no detail lines
--   'pendiente'   → nothing received yet
--   'parcial'     → some items partially received
--   'completo'    → all ordered quantities received
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
    COALESCE(entregas.total_entregas, 0)             AS total_entregas,
    COALESCE(letras.total_letras, 0)           AS total_letras,
    COALESCE(letras.monto_letras_pendiente, 0) AS monto_letras_pendiente,
    -- Receipt progress derived from linked entregas
    CASE
        WHEN det.total_items = 0                              THEN 'sin_lineas'
        WHEN COALESCE(recepcion.qty_recibida, 0) = 0          THEN 'pendiente'
        WHEN COALESCE(recepcion.qty_pendiente, 0) <= 0        THEN 'completo'
        ELSE                                                       'parcial'
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
    SELECT COUNT(*) AS total_entregas
    FROM doc.compra_entrega cgr WHERE cgr.compra_id = c.id
) entregas ON true
LEFT JOIN LATERAL (
    SELECT COUNT(DISTINCT lf.letra_id)                                         AS total_letras,
           SUM(lf.monto_aplicado) FILTER (WHERE l.estado = 'emitida')          AS monto_letras_pendiente
    FROM doc.compra_factura_proveedor cfp
    JOIN doc.letra_factura lf ON lf.factura_proveedor_id = cfp.factura_proveedor_id
    JOIN doc.letra l ON l.id = lf.letra_id
    WHERE cfp.compra_id = c.id
) letras ON true
LEFT JOIN LATERAL (
    SELECT
        SUM(cd.cantidad - cd.cantidad_recibida) AS qty_pendiente,
        SUM(cd.cantidad_recibida)               AS qty_recibida
    FROM doc.compra_detalle cd
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
-- Source priority (factura-over-compra fallback):
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
DROP VIEW IF EXISTS doc.vw_compras_recepcion;
-- Receipt tracking: per (compra, item) shows ordered qty vs qty
-- received via linked entregas, and the remaining open qty.
--
-- "Received" = sum of entrega_detalle.cantidad for all entregas
-- linked to this compra (via compra_entrega) that carry this
-- item_id.  There is intentionally no FK from a entrega line to a
-- compra line — linkage is at the compra↔entrega level — so this is
-- the finest granularity possible without schema changes.
--
-- Rows exist for every compra_detalle line including those with
-- zero receipt (qty_pendiente = cantidad_ordenada).  Use WHERE
-- qty_pendiente > 0 to filter open lines.
-- cantidad_recibida reads from the denormalized compra_detalle.cantidad_recibida,
-- which fn_refresh_compra_detalle_qtys keeps correct across all ingress paths
-- (documento_tipo='compra' direct movements AND documento_tipo='entrega' via compra_entrega).
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
    cd.cantidad_recibida                                              AS cantidad_recibida,
    cd.cantidad - cd.cantidad_recibida                                AS cantidad_pendiente,
    cd.precio_unitario,
    cd.cantidad * cd.precio_unitario                                  AS valor_linea,
    -- Per-line receipt status
    CASE
        WHEN cd.cantidad_recibida = 0               THEN 'pendiente'
        WHEN cd.cantidad_recibida >= cd.cantidad    THEN 'completo'
        ELSE                                             'parcial'
    END                                                               AS estado_linea,
    c.fyh_elm
FROM doc.compra c
JOIN tercero t             ON t.id  = c.tercero_id
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i                ON i.id  = cd.item_id
JOIN unidad un             ON un.id = i.unidad_id;

GRANT SELECT ON doc.vw_compras_recepcion TO authenticated;

-- ── inventario.vw_item_proveedor_entrega ─────────────────────────
CREATE OR REPLACE VIEW inventario.vw_item_proveedor_entrega AS
SELECT DISTINCT
    i.id AS item_id,
    i.codigo AS item_codigo,
    i.nombre AS item_nombre,
    gr.tercero_id AS proveedor_id,
    t.nombre AS proveedor_nombre
FROM doc.entrega gr
JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
JOIN doc.entrega_detalle grd ON grd.entrega_id = gr.id
JOIN item i ON i.id = grd.item_id
JOIN tercero t ON t.id = gr.tercero_id
WHERE grt.flg_emitida = false AND t.flg_proveedor = true;

GRANT SELECT ON inventario.vw_item_proveedor_entrega TO anon, authenticated;


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
    lrd.entrega_id,
    e.serie                             AS entrega_serie,
    e.correlativo                       AS entrega_correlativo
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
LEFT JOIN vw_colores vc                 ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN doc.entrega e                 ON e.id = lrd.entrega_id;


-- ── inventario.vw_venta_rollos_devolvibles ───────────────────────
-- Locates rolls a client can return under a given venta (client-QC dyed
-- return, concept #2 in DEVOLUCION_REPROCESO_FLOW_SPEC.md), so the frontend
-- can launch registrar_devolucion_cliente from a venta screen.
--
-- NOTE: does NOT reuse lrd.entrega_id (that carries the INGRESS anchor
-- forward through production — see mes.sql registrar_produccion — so its
-- venta_id is always NULL). The dispatch entrega/venta is instead derived
-- from the roll's own egress movement, same pattern as
-- doc.registrar_devolucion_cliente's entrega_origen_id derivation.
--
-- Eligibility: still out with the client (net saldo <= 0 since its last
-- dispatch). No separate "already returned" check is needed — a return
-- posts an ingress movement that brings saldo back >= 0, which drops the
-- roll out of this view on its own; the ledger is the single source of truth.
CREATE OR REPLACE VIEW inventario.vw_venta_rollos_devolvibles AS
WITH ultimo_despacho AS (
    SELECT DISTINCT ON (im.lote_id)
        im.lote_id,
        im.documento_id AS entrega_id,
        e.venta_id,
        et.codigo        AS entrega_tipo_codigo
    FROM inventario.item_movimientos im
    JOIN doc.entrega e      ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
    WHERE im.origen_ubicacion_id IS NOT NULL
      AND et.codigo IN ('VENTA_EGRESO', 'DESPACHO_CLIENTE')
      AND e.venta_id IS NOT NULL
    ORDER BY im.lote_id, im.id DESC
),
saldo AS (
    SELECT lote_id, SUM(cantidad * (
        CASE WHEN destino_ubicacion_id IS NOT NULL THEN  1 ELSE 0 END +
        CASE WHEN origen_ubicacion_id  IS NOT NULL THEN -1 ELSE 0 END
    )) AS saldo
    FROM inventario.item_movimientos
    GROUP BY lote_id
)
SELECT
    ud.venta_id,
    l.id                                 AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.item_id,
    i.codigo                             AS item_codigo,
    i.nombre                             AS item_nombre,
    art.nombre                           AS articulo_nombre,
    vc.color,
    l.cantidad                           AS peso,
    ud.entrega_id,
    ud.entrega_tipo_codigo,
    l.propietario_id,
    p.id                                 AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo
FROM ultimo_despacho ud
JOIN inventario.lote l                  ON l.id = ud.lote_id
JOIN saldo s                            ON s.lote_id = l.id AND s.saldo <= 0
JOIN item i                             ON i.id = l.item_id
JOIN item_rollo_detalle ird             ON ird.item_id = i.id
JOIN articulo art                       ON art.id = ird.articulo_id
JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id AND lrd.flg_tenido = true
LEFT JOIN vw_colores vc                 ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_paso pp           ON pp.id = pe.partida_paso_id
LEFT JOIN mes.partida p                 ON p.id = pp.partida_id;

GRANT SELECT ON inventario.vw_venta_rollos_devolvibles TO authenticated;


-- ── inventario.vw_venta_entregas_devolvibles ─────────────────────
-- Guía grain of the above: the frontend's default selection unit is "return
-- this whole guía" (defaults to all its rolls), with vw_venta_rollos_devolvibles
-- used underneath for a free pick of particular rolls when the return is
-- partial. Same aggregate-via-GROUP-BY pattern as guia_remision_detalle
-- (see [[document-model-philosophy]]) — no separate source of truth, just a
-- rollup of the roll-grain view above.
CREATE OR REPLACE VIEW inventario.vw_venta_entregas_devolvibles AS
SELECT
    r.venta_id,
    r.entrega_id,
    r.entrega_tipo_codigo,
    e.serie          AS entrega_serie,
    e.correlativo    AS entrega_correlativo,
    e.fecha_emision,
    COUNT(*)         AS n_rollos,
    SUM(r.peso)      AS peso_total
FROM inventario.vw_venta_rollos_devolvibles r
JOIN doc.entrega e ON e.id = r.entrega_id
GROUP BY r.venta_id, r.entrega_id, r.entrega_tipo_codigo, e.serie, e.correlativo, e.fecha_emision;

GRANT SELECT ON inventario.vw_venta_entregas_devolvibles TO authenticated;

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


-- ── mes.vw_maquinas ───────────────────────────────────────────}
drop view if exists mes.vw_maquinas;
CREATE OR REPLACE VIEW mes.vw_maquinas AS
SELECT
    m.id,
    m.codigo,
    m.nombre,
    m.maquina_tipo_id,
    mt.codigo AS maquina_tipo_codigo,
    mt.nombre AS maquina_tipo_nombre,
    mt.operacion_id,
    m.capacidad_min_kg,
    o.codigo   AS operacion_codigo,
    m.relacion_bano
FROM mes.maquina m
LEFT JOIN mes.maquina_tipo mt ON mt.id = m.maquina_tipo_id
LEFT JOIN mes.operacion o     ON o.id  = mt.operacion_id;

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
CREATE OR REPLACE VIEW inventario.vw_stock_items AS
SELECT
    vi.item_id, vi.item_codigo, vi.item_nombre,
    vi.item_tipo_id, vi.item_tipo_codigo,
    SUM(si.cantidad_actual) AS cantidad_total,
    vi.unidad_id, vi.unidad_codigo
FROM inventario.item_saldo si
JOIN vw_items vi ON vi.item_id = si.item_id
WHERE si.cantidad_actual != 0
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
WHERE si.cantidad_actual != 0;

-- ── inventario.vw_stock_items_valorado ───────────────────────
-- Item stock + MAP valuation (≈ SAP MB52). Financial view only — not for
-- availability gates (use vw_stock_items for that).
-- LEFT JOIN so items with no valuation row still appear (cost columns NULL).
CREATE OR REPLACE VIEW inventario.vw_stock_items_valorado AS
SELECT
    vi.item_id, vi.item_codigo, vi.item_nombre,
    vi.item_tipo_id, vi.item_tipo_codigo,
    SUM(si.cantidad_actual)                                  AS cantidad_total,
    vi.unidad_id, vi.unidad_codigo,
    iv.precio_promedio,
    -- stock_valorado from item_valoracion is a MAP accounting figure that can
    -- diverge from physical stock due to floor-at-zero behavior on negative
    -- stock events. Always compute from net quantity × MAP price for display.
    ROUND((SUM(si.cantidad_actual) * COALESCE(iv.precio_promedio, 0))::numeric, 4)::NUMERIC(16,4)
                                                             AS stock_valorado
FROM inventario.item_saldo si
JOIN  vw_items vi                       ON vi.item_id = si.item_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = si.item_id
WHERE si.cantidad_actual != 0
GROUP BY vi.item_id, vi.item_codigo, vi.item_nombre,
         vi.item_tipo_id, vi.item_tipo_codigo,
         vi.unidad_id, vi.unidad_codigo,
         iv.precio_promedio, iv.stock_valorado;

-- ── inventario.vw_stock_x_proveedor ──────────────────────────
-- Current stock grouped by (item, supplier), valued at item MAP price.
-- Supplier resolved via lote origin document:
--   Path A: lote.documento_tipo='compra'  → doc.compra directly
--   Path B: lote.documento_tipo='entrega' → doc.compra_entrega → doc.compra
-- Items with no purchase origin (e.g. production output lotes) appear with
-- proveedor_id / proveedor_nombre NULL.
-- precio_promedio is item-level MAP — same across all supplier rows for the
-- same item. stock_valorado = per-supplier quantity × item MAP.
-- SELECT * FROM inventario.vw_stock_x_proveedor WHERE proveedor_id IS nOT NULL;
CREATE OR REPLACE VIEW inventario.vw_stock_x_proveedor AS
WITH lote_proveedor AS (
    -- Path A: direct compra receipt
    SELECT l.id AS lote_id, c.tercero_id AS proveedor_id
    FROM inventario.lote l
    JOIN doc.compra c ON c.id = l.documento_id
    WHERE l.documento_tipo = 'compra'
    UNION
    -- Path B: orderless entrega receipt (DISTINCT prevents fanout when one
    -- entrega maps to multiple compras from the same supplier)
    SELECT DISTINCT l.id, c.tercero_id
    FROM inventario.lote l
    JOIN doc.compra_entrega ce ON ce.entrega_id = l.documento_id
    JOIN doc.compra c          ON c.id = ce.compra_id
    WHERE l.documento_tipo = 'entrega'
)
SELECT
    vi.item_id,
    vi.item_codigo,
    vi.item_nombre,
    vi.item_tipo_id,
    vi.item_tipo_codigo,
    vi.unidad_id,
    vi.unidad_codigo,
    t.id                                                         AS proveedor_id,
    t.nombre                                                     AS proveedor_nombre,
    SUM(ls.cantidad_actual)                                      AS cantidad_total,
    iv.precio_promedio,
    ROUND((SUM(ls.cantidad_actual) * COALESCE(iv.precio_promedio, 0))::numeric, 4)::NUMERIC(16,4)
                                                                 AS stock_valorado
FROM inventario.lote_saldo ls
JOIN inventario.lote l          ON l.id = ls.lote_id AND l.fyh_elm IS NULL
JOIN vw_items vi                ON vi.item_id = l.item_id
LEFT JOIN lote_proveedor lp     ON lp.lote_id = l.id
LEFT JOIN tercero t             ON t.id = lp.proveedor_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = l.item_id
WHERE ls.cantidad_actual > 0
GROUP BY vi.item_id, vi.item_codigo, vi.item_nombre,
         vi.item_tipo_id, vi.item_tipo_codigo,
         vi.unidad_id, vi.unidad_codigo,
         t.id, t.nombre, iv.precio_promedio;

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
-- Insumo stock + MAP valuation + tipo/colorante attributes, location-agnostic.
-- Flat single-pass projection of the insumo subtype (class-table inheritance:
-- item + item_insumo_detalle): each table is joined exactly once, aggregated once.
-- Values at item_valoracion.precio_promedio — the same MAP carrying-value source
-- as vw_stock_items_valorado (inventory carrying value, not invoice-derived
-- replacement/recipe cost).
-- Net-stock filter <> 0 (aggregates item_saldo across locations incl. the NULL
-- fungible bucket) so debt positions net correctly instead of being dropped.
-- Financial view: granted to authenticated only (exposes cost).
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
    ct.nombre                   AS colorante_tipo_nombre,
    iv.precio_promedio,
    ROUND((SUM(si.cantidad_actual) * COALESCE(iv.precio_promedio, 0))::numeric, 4)::NUMERIC(16,4)
                                AS stock_valorado
FROM inventario.item_saldo si
JOIN item i        ON i.id = si.item_id
JOIN item_tipo it  ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
JOIN unidad un     ON un.id = i.unidad_id
LEFT JOIN item_insumo_detalle iid       ON iid.item_id = si.item_id
LEFT JOIN insumo_tipo intp              ON intp.id = iid.insumo_tipo_id
LEFT JOIN colorante_tipo ct             ON ct.id = iid.colorante_tipo_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = si.item_id
WHERE si.cantidad_actual != 0
GROUP BY si.item_id, i.codigo, i.nombre, un.codigo,
         iid.insumo_tipo_id, intp.codigo, intp.nombre,
         iid.colorante_tipo_id, ct.codigo, ct.nombre,
         iv.precio_promedio
HAVING SUM(si.cantidad_actual) != 0;

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

-- ── calidad.vw_qc_pendiente_output ─────────────────────────────
-- Path A only — QC on a production-output roll (a lote materialized by
-- registrar_produccion, documento_tipo='partida_paso_ejecucion') against the
-- ejecucion that created it. In the current production model output is
-- materialized at the producing/closure step; mid-route steps only route the
-- roll (per-step output tracking is WIP, not modeled now), and mid-process QC of
-- a roll still being worked is the INPUT side (vw_qc_pendiente_input).
--
-- Pending = estado_calidad='PENDIENTE'. This IS the authoritative signal in the
-- current schema: every QC write path (crear_inspeccion, bulk_aprobar_lotes,
-- bulk_rechazar_lotes — funciones/calidad.sql) flips estado_calidad in the SAME
-- transaction as the inspeccion INSERT, so PENDIENTE ⟺ "no inspeccion recorded".
-- The NOT EXISTS(inspeccion for creating ejec) is kept as a cheap belt-and-
-- suspenders (runs only over the already-tiny PENDIENTE-output set), but
-- estado_calidad is the indexable driver — see idx_lote_pendiente_qc_output
-- (migration/patches/62). documento_id already IS the creating ejecucion, so
-- unlike Path B/C no LATERAL "active step" resolution is needed.
--
-- NOTE — legacy divergence, intentionally NOT preserved: some backfilled lotes
-- carry estado_calidad='APROBADO' with no inspeccion row (old bulk data loads
-- that set the column directly). The pre-split view keyed on inspeccion-existence
-- and so listed those ~2k already-approved rolls as "pending"; keying on
-- estado_calidad here correctly drops them. That is a deliberate behavior change
-- scoped to legacy data artifacts, per "design for the current schema, forget
-- legacy" — no current function can produce that state.
--
-- pc guard: a lote that is also an assigned component is a rework input — Path
-- B/C territory. Excluding it keeps the two views disjoint so the compatibility
-- UNION doesn't double-count it.
--
-- Gates dispatch downstream (vw_despacho_pendiente requires estado_calidad
-- ='APROBADO'), a separate concern from whether QC has been recorded here.
CREATE OR REPLACE VIEW calidad.vw_qc_pendiente_output AS
SELECT
    l.id AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    l.documento_tipo,
    l.documento_id,
    pe.id                                               AS partida_paso_ejecucion_id,
    pp.id                                                AS partida_paso_id,
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
    p.color_x_cliente_id,
    vc.color_id,
    vc.color AS color_nombre,
    vc.color_hex,
    vc.color_x_cliente_hex,
    l.propietario_id,
    c.nombre AS cliente_nombre,
    l.fyh_cre AS fecha_creacion_lote,
    pe.fyh_fin                                          AS fecha_produccion,
    true                                                 AS es_output
FROM inventario.lote l
JOIN vw_items vi ON vi.item_id = l.item_id AND vi.item_tipo_codigo = 'ROLLO'
JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN mes.maquina m   ON m.id = pe.maquina_id
LEFT JOIN tercero c    ON c.id  = p.tercero_id
LEFT JOIN prioridad pr ON pr.id = p.prioridad_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
WHERE l.estado_calidad = 'PENDIENTE'
  -- pc guard: a lote that is ALSO an assigned component is a rework input — that's
  -- Path B/C (vw_qc_pendiente_input) territory. Excluding it here keeps the two
  -- views disjoint so the compatibility UNION doesn't double-count it.
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc WHERE pc.lote_id = l.id
  )
  -- Defensive (redundant with estado_calidad in the current schema, cheap here).
  AND NOT EXISTS (
      SELECT 1 FROM calidad.inspeccion ci
      WHERE ci.lote_id = l.id AND ci.partida_paso_ejecucion_id = pe.id
  )
  -- Closed/cancelled partidas have no pending QC work. Legacy 'Despachado' partidas
  -- are migrated as CERRADA (11_data_migration).
  AND COALESCE(p.estado_produccion, 'CREADA') NOT IN ('CERRADA', 'CANCELADA');

-- ── calidad.vw_qc_pendiente_input ──────────────────────────────
-- Paths B+C only — mid-process inspection of a roll still assigned as a live
-- component of an in-progress partida (raw fabric intake, or a rework input
-- re-entering via crear_reproceso Case B). Does NOT gate dispatch; it's a
-- production-time checkpoint, distinct in consequence from vw_qc_pendiente_output.
--
--   Path B — original input roll (documento_tipo != 'partida_paso_ejecucion'):
--     Raw fabric roll assigned to a partida via partida_componente.
--     Inspectable per paso, as long as not yet consumed (lote_saldo > 0).
--
--   Path C — rework input roll (documento_tipo = 'partida_paso_ejecucion'):
--     Output lote from a previous partida now assigned as input to a rework child.
--     The old inspection (against the OLD ejecucion) is irrelevant here — active_ppe
--     resolves the CURRENT rework paso instead.
--
-- Driven from non-terminal partidas first (~900 rows today) via a MATERIALIZED CTE,
-- not from the full lote table — bounds the LATERAL "active step" resolution to
-- that partida's own partida_componente rows instead of fanning it out over every
-- roll ever created. MATERIALIZED is required, not stylistic: without it Postgres
-- inlines the CTE and, on the measured cardinalities, mis-estimates its way into
-- leading with a Seq Scan on inventario.lote instead (measured 3.1s vs 0.9s with
-- the fence — see performance diagnosis, 2026-07-31). Re-check this fence after
-- any major shift in partida/lote row counts; the plan choice depends on it.
-- EN_PROCESO takes priority; falls back to most recently started COMPLETADO paso so
-- rolls remain inspectable in the window between step completion and next step start.
-- A JOIN (not LEFT JOIN) LATERAL naturally drops rolls with no active step at all.
CREATE OR REPLACE VIEW calidad.vw_qc_pendiente_input AS
WITH partidas_activas AS MATERIALIZED (
    SELECT id FROM mes.partida
    WHERE COALESCE(estado_produccion, 'CREADA') NOT IN ('CERRADA', 'CANCELADA')
)
SELECT
    l.id AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    l.documento_tipo,
    l.documento_id,
    active_ppe.ejecucion_id                             AS partida_paso_ejecucion_id,
    active_ppe.paso_id                                  AS partida_paso_id,
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
    p.color_x_cliente_id,
    vc.color_id,
    vc.color AS color_nombre,
    vc.color_hex,
    vc.color_x_cliente_hex,
    l.propietario_id,
    c.nombre AS cliente_nombre,
    l.fyh_cre AS fecha_creacion_lote,
    active_ppe.active_fyh_fin                           AS fecha_produccion,
    false                                                AS es_output
FROM partidas_activas pa
JOIN mes.partida p ON p.id = pa.id
JOIN mes.partida_componente pc ON pc.partida_id = pa.id AND pc.lote_id IS NOT NULL
JOIN inventario.lote l ON l.id = pc.lote_id
JOIN vw_items vi ON vi.item_id = l.item_id AND vi.item_tipo_codigo = 'ROLLO'
JOIN LATERAL (
    SELECT ppe.id           AS ejecucion_id,
           ppe.maquina_id   AS active_maquina_id,
           pp2.id           AS paso_id,
           pp2.operacion_id AS active_operacion_id,
           ppe.fyh_fin      AS active_fyh_fin
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp2 ON pp2.id = ppe.partida_paso_id
    WHERE pp2.partida_id = pc.partida_id
      AND ppe.estado IN ('EN_PROCESO', 'COMPLETADO')
    ORDER BY
        CASE WHEN ppe.estado = 'EN_PROCESO' THEN 0 ELSE 1 END,
        pp2.secuencia DESC,
        ppe.fyh_inicio DESC
    LIMIT 1
) active_ppe ON true
LEFT JOIN mes.operacion o ON o.id = active_ppe.active_operacion_id
LEFT JOIN mes.maquina m   ON m.id = active_ppe.active_maquina_id
LEFT JOIN tercero c    ON c.id  = p.tercero_id
LEFT JOIN prioridad pr ON pr.id = p.prioridad_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
WHERE
  -- "Already inspected" is checked against the whole PASO (any of its ejecucion
  -- runs), not just active_ppe's single most-recent run: a paso can have multiple
  -- ejecucion rows (normal run + lagging continuation, e.g. a batch split across
  -- machine capacity), and active_ppe always surfaces the newest one for context
  -- (maquina/operacion). Scoping the EXISTS to that one run alone would resurface
  -- rolls already inspected under an earlier run of the same paso as false pending.
  NOT EXISTS (
      SELECT 1
      FROM calidad.inspeccion ci
      JOIN mes.partida_paso_ejecucion ppe_chk ON ppe_chk.id = ci.partida_paso_ejecucion_id
      WHERE ci.lote_id = l.id
        AND ppe_chk.partida_paso_id = active_ppe.paso_id
  )
  AND EXISTS (
      SELECT 1 FROM inventario.lote_saldo ls
      WHERE ls.lote_id = l.id AND ls.cantidad_actual > 0
  );

-- ── calidad.vw_lotes_pendientes_inspeccion ────────────────────
-- Compatibility union — same column contract as before the split. Existing
-- consumers (get_lotes_pendientes_partida, bulk_aprobar_lotes, bulk_rechazar_lotes,
-- vw_partidas_pendientes_calidad, vw_auditoria_pendiente) keep working unchanged.
-- Cheap: each UNION ALL branch keeps its own WHERE/join shape, so Postgres plans
-- and pushes predicates into each branch independently instead of merging them
-- into one CASE-expression-laden join tree (which was the actual cost driver in
-- the pre-split view — see performance diagnosis, 2026-07-30).
-- New call sites that only need one path (e.g. a dispatch-gate screen, or an
-- in-process QC screen) should query vw_qc_pendiente_output / _input directly
-- and skip this union entirely.
CREATE OR REPLACE VIEW calidad.vw_lotes_pendientes_inspeccion AS
SELECT * FROM calidad.vw_qc_pendiente_output
UNION ALL
SELECT * FROM calidad.vw_qc_pendiente_input;

-- ── calidad.vw_inspecciones ───────────────────────────────────
DROP VIEW IF EXISTS calidad.vw_inspecciones;
CREATE OR REPLACE VIEW calidad.vw_inspecciones AS
SELECT
    i.id                                                                    AS inspeccion_id,
    i.lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0')
                                                                            AS lote_codigo,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    i.partida_paso_ejecucion_id,
    p.id                                                                    AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text, 4, '0')
                                                                            AS partida_codigo,
    p.partida_origen_id,
    t.nombre                                                                AS cliente_nombre,
    vc.color_id,
    vc.color                                                                AS color_nombre,
    vc.color_hex,
    vc.color_x_cliente_hex,
    op.codigo                                                               AS operacion_codigo,
    i.resultado,
    i.observacion,
    i.empleado_id,
    e.nombre                                                                AS empleado_nombre,
    i.fyh_inspeccion
FROM calidad.inspeccion i
LEFT JOIN inventario.lote            l   ON l.id  = i.lote_id
LEFT JOIN vw_items                   vi  ON vi.item_id = l.item_id
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.id = i.partida_paso_ejecucion_id
LEFT JOIN mes.partida_paso           pp  ON pp.id  = ppe.partida_paso_id
LEFT JOIN mes.partida                p   ON p.id   = pp.partida_id
LEFT JOIN tercero                    t   ON t.id   = p.tercero_id
LEFT JOIN vw_colores                 vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN mes.operacion              op  ON op.id  = pp.operacion_id
LEFT JOIN mes.empleado               e   ON e.id   = i.empleado_id;

-- ── calidad.vw_partidas_pendientes_calidad ────────────────────
-- Partida-level QC summary — aggregates over vw_lotes_pendientes_inspeccion.
-- lotes_en_produccion:   input rolls currently inside an EN_PROCESO paso
--                        (more output lotes may appear for QC when the step completes)
-- lotes_asignados_total: total input rolls reserved for this partida
-- tiene_rework_activo:   at least one non-closed rework partida linked to this one
-- partida_origen_id:     non-NULL means this row is itself a rework
-- lotes_output_pendientes_qc / peso_output_pendiente_kg:
--   subset scoped to es_output=true (finished output rolls, always produced at the
--   partida's closure step per PROD_CONSUMO semantics — see vw_lotes_pendientes_inspeccion).
--   Lets a "final QC only" consumer filter/sort without a separate view.
DROP VIEW IF EXISTS calidad.vw_partidas_pendientes_calidad;
CREATE OR REPLACE VIEW calidad.vw_partidas_pendientes_calidad AS
WITH base AS (
    SELECT
        v.partida_id,
        v.partida_codigo,
        v.partida_origen_id,
        v.cliente_nombre,
        v.prioridad_id,
        v.color_id,
        v.color_nombre,
        v.color_hex,
        v.color_x_cliente_hex,
        v.operacion_codigo,
        v.lote_id,
        v.fecha_creacion_lote,
        v.es_output,
        l.cantidad AS peso_kg
    FROM calidad.vw_lotes_pendientes_inspeccion v
    JOIN inventario.lote l ON l.id = v.lote_id
    WHERE v.partida_id IS NOT NULL
),
agg AS (
    SELECT
        partida_id,
        partida_codigo,
        partida_origen_id,
        cliente_nombre,
        prioridad_id,
        color_id,
        color_nombre,
        color_hex,
        color_x_cliente_hex,
        COUNT(*)                                                             AS lotes_pendientes_qc,
        array_agg(DISTINCT operacion_codigo ORDER BY operacion_codigo)
            FILTER (WHERE operacion_codigo IS NOT NULL)                     AS operaciones_pendientes,
        MIN(fecha_creacion_lote)                                            AS lote_pendiente_mas_antiguo,
        COUNT(*)         FILTER (WHERE es_output)                           AS lotes_output_pendientes_qc,
        COALESCE(SUM(peso_kg) FILTER (WHERE es_output), 0)                  AS peso_output_pendiente_kg
    FROM base
    GROUP BY partida_id, partida_codigo, partida_origen_id, cliente_nombre, prioridad_id,
             color_id, color_nombre, color_hex, color_x_cliente_hex
)
SELECT
    a.partida_id,
    a.partida_codigo,
    a.partida_origen_id,
    a.cliente_nombre,
    a.prioridad_id,
    a.color_id,
    a.color_nombre,
    a.color_hex,
    a.color_x_cliente_hex,
    a.lotes_pendientes_qc,
    a.operaciones_pendientes,
    a.lote_pendiente_mas_antiguo,
    a.lotes_output_pendientes_qc,
    a.peso_output_pendiente_kg,
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

-- ── calidad.vw_auditoria_pendiente ────────────────────────────
-- Audit print sheet: one row per (partida, entrega, item) with
-- count of QC-pending rolls. Sourced from vw_lotes_pendientes_inspeccion
-- so SUM(rollos) == lotes_pendientes_qc in vw_partidas_pendientes_calidad
-- by construction.
-- DROP VIEW IF EXISTS calidad.vw_auditoria_pendiente;
CREATE OR REPLACE VIEW calidad.vw_auditoria_pendiente AS
SELECT
    p.id                                                                       AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text, 4, '0') AS partida_codigo,
    ter.nombre                                                                 AS cliente,
    vc.color,
    vc.color_hex,
    t.tenido,
    ga.nombre                                                                  AS grupo_articulo,
    p.fibra,
    p.malla,
    p.ancho,
    p.rendimiento,
    p.observacion,
    gr.id                                                                      AS entrega_id,
    gr.serie                                                                   AS entrega_serie,
    gr.correlativo                                                             AS entrega_correlativo,
    i.id                                                                       AS item_id,
    i.codigo                                                                   AS item_codigo,
    i.nombre                                                                   AS item_nombre,
    ird.flg_rib,
    COUNT(*)::INT                                                              AS rollos
FROM calidad.vw_lotes_pendientes_inspeccion vl
JOIN inventario.lote          l   ON l.id   = vl.lote_id
JOIN mes.partida              p   ON p.id   = vl.partida_id
LEFT JOIN tercero             ter ON ter.id  = p.tercero_id
LEFT JOIN vw_colores          vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido              t   ON t.id    = p.tenido_id
LEFT JOIN grupo_articulo      ga  ON ga.id   = p.grupo_articulo_id
JOIN item                     i   ON i.id    = l.item_id
LEFT JOIN item_rollo_detalle  ird ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id  = l.id
LEFT JOIN doc.entrega   gr  ON gr.id   = lrd.entrega_id
GROUP BY
    p.id, p.numero, p.fyh_cre,
    p.tercero_id, ter.nombre,
    p.color_x_cliente_id, vc.color, vc.color_hex,
    p.tenido_id, t.tenido,
    p.grupo_articulo_id, ga.nombre,
    p.fibra, p.malla, p.rendimiento, p.ancho, p.observacion,
    gr.id, gr.serie, gr.correlativo,
    i.id, i.codigo, i.nombre,
    ird.flg_rib;

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
-- Machine resolution: actual (latest ejecucion) → scheduled (programacion). The routing
-- step (partida_paso) carries no machine; maquina_programada_id surfaces the board's choice.
DROP VIEW IF EXISTS mes.vw_pasos;
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
    pp.receta_id,
    -- Planning targets
    pp.ph_objetivo,
    pp.temperatura_objetivo,
    prog.relacion_bano                                                     AS relacion_bano_objetivo,
    pp.tiempo_estandar,
    -- Active machine: actual (from ejecucion) falls back to the scheduled machine
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
    pe.cantidad_rollos,
    pe.peso_kg,
    pe.notas,
    pe.ancho_entrada,
    pe.ancho_salida,
    pe.velocidad,
    pe.entrada,
    pe.salida,
    pe.rendimiento,
    pe.pases,
    pe.malla_alimentacion,
    -- TERMOFIJADO extension
    pt.ancho_marco,
    pt.vel_maquina,
    pt.vel_alimentacion,
    pt.densidad_entrada,
    pt.densidad_salida,
    pt.lm,
    pt.galga,
    -- Scheduling context
    prog.id                                                                AS programacion_id,
    prog.maquina_id                                                        AS maquina_programada_id,
    prog.fecha                                                             AS fecha_programada,
    prog.secuencia                                                         AS secuencia_programada,
    -- Derived execution state: PENDIENTE when no ejecucion rows exist
    CASE
        WHEN pe.id IS NOT NULL AND pe.estado = 'COMPLETADO' THEN 'COMPLETADO'
        WHEN pe.id IS NOT NULL AND pe.estado = 'EN_PROCESO' THEN 'EN_PROCESO'
        WHEN pe.id IS NOT NULL AND pe.estado = 'OMITIDO'    THEN 'OMITIDO'
        ELSE 'PENDIENTE'
    END                                                                    AS estado,
    -- Active-pipeline signal for the non-scheduled stations (preparado, perchado, …):
    -- estado_produccion goes PROGRAMADA once the partida is on the board (its teñido/
    -- termofijado got scheduled) and EN_PRODUCCION once it starts, so a station filters
    -- its queue to estado IN ('PROGRAMADA','EN_PRODUCCION'). Free column — it's just the
    -- partida estado from the existing JOIN, no subquery, no cost to other consumers.
    p.estado_produccion                                                    AS partida_estado_produccion
FROM mes.partida_paso pp
JOIN mes.partida p      ON p.id  = pp.partida_id
JOIN mes.operacion o    ON o.id  = pp.operacion_id
LEFT JOIN tercero c     ON c.id  = p.tercero_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN LATERAL (
    SELECT id, estado, maquina_id, empleado_id,
           fyh_inicio, fyh_fin, ph_real, temperatura_real,
           relacion_bano_real, cantidad_rollos,peso_kg, notas,
           ancho_entrada, ancho_salida, velocidad,
           entrada, salida, rendimiento, pases, malla_alimentacion
    FROM mes.partida_paso_ejecucion
    WHERE partida_paso_id = pp.id
    ORDER BY fyh_inicio DESC NULLS LAST
    LIMIT 1
) pe ON true
LEFT JOIN LATERAL (
    SELECT id, maquina_id, fecha, secuencia, relacion_bano
    FROM mes.programacion
    WHERE actividad_tipo = 'partida_paso' AND actividad_id = pp.id
    ORDER BY fyh_cre DESC
    LIMIT 1
) prog ON true
LEFT JOIN mes.maquina m ON m.id = COALESCE(pe.maquina_id, prog.maquina_id)
LEFT JOIN mes.partida_paso_ejecucion_termofijado pt ON pt.ejecucion_id = pe.id;

-- ── mes.vw_cola_estacion ──────────────────────────────────────
-- FCFS work queue for the NON-scheduled finishing stations (preparado, secado,
-- perchado, compactado, …). Standalone (NOT built on vw_pasos) and pre-filtered to
-- active partidas + actionable pasos, so it's lean and only ever scans current WIP.
--
-- Scope is the partida lifecycle, NOT mes.programacion. The board is rebuilt each
-- day by carrying forward only UNFINISHED work, so a partida drops off it the moment
-- its teñido completes — which is exactly when its post-teñido steps become ready.
-- estado_produccion is carryover-safe: PROGRAMADA = scheduled/pre-teñido,
-- EN_PRODUCCION = running through the entire finishing tail (until TECO/CERRADA).
--
-- Driver is backed by idx_partida_activa (partial index on the two active states).
-- The frontend adds operacion_id + listo and orders by fyh_listo (FCFS):
--   vw_cola_estacion?operacion_id=eq.<op>&estado=eq.PENDIENTE&listo=is.true&order=fyh_listo.asc.nullslast
DROP VIEW IF EXISTS mes.vw_cola_estacion;
CREATE OR REPLACE VIEW mes.vw_cola_estacion AS
SELECT
    pp.id                                                                AS paso_id,
    pp.secuencia,
    pp.partida_id,
    pp.operacion_id,
    o.codigo                                                             AS operacion_codigo,
    o.nombre                                                             AS operacion_nombre,
    o.requiere_receta,
    o.requiere_maquina,
    pp.estado,
    p.estado_produccion                                                  AS partida_estado_produccion,
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || LPAD(p.numero::TEXT, 4, '0')   AS partida_codigo,
    p.tercero_id,
    c.nombre                                                             AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.color_hex,
    p.partida_origen_id,
    -- latest execution run (ejecucion_id for anular, plus start time / machine)
    pe.id                                                                AS ejecucion_id,
    pe.fyh_inicio,
    pe.maquina_id,
    -- readiness: every earlier paso in the partida is settled (mirrors iniciar_paso)
    NOT EXISTS (
        SELECT 1 FROM mes.partida_paso prev
        WHERE prev.partida_id = pp.partida_id
          AND prev.secuencia  < pp.secuencia
          AND prev.estado NOT IN ('COMPLETADO','OMITIDO')
    )                                                                    AS listo,
    -- FCFS arrival: latest predecessor completion time (when this paso became workable)
    (SELECT MAX(pe2.fyh_fin)
     FROM mes.partida_paso prev
     JOIN mes.partida_paso_ejecucion pe2 ON pe2.partida_paso_id = prev.id
     WHERE prev.partida_id = pp.partida_id
       AND prev.secuencia  < pp.secuencia
       AND prev.estado IN ('COMPLETADO','OMITIDO'))                      AS fyh_listo
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.partida_id = p.id
JOIN mes.operacion o     ON o.id = pp.operacion_id
LEFT JOIN tercero c      ON c.id = p.tercero_id
LEFT JOIN vw_colores vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN LATERAL (
    SELECT id, fyh_inicio, maquina_id
    FROM mes.partida_paso_ejecucion
    WHERE partida_paso_id = pp.id
    ORDER BY fyh_inicio DESC NULLS LAST
    LIMIT 1
) pe ON true
WHERE p.estado_produccion IN ('PROGRAMADA','EN_PRODUCCION')
  AND pp.estado            IN ('PENDIENTE','EN_PROCESO');

GRANT SELECT ON mes.vw_cola_estacion TO authenticated;

-- ── mes.vw_wip ────────────────────────────────────────────────
-- Real-time work-in-process BOARD: one row per active partida, answering
-- "where is this order on the floor right now, on which machine, and how long
-- has it sat in that state?". Complements the other two floor views —
-- vw_pasos is step-centric (full history), vw_cola_estacion is a per-station
-- FCFS queue; this one is partida-centric and pre-filtered to live WIP, so it's
-- the natural driver for a plant-floor big screen / manager dashboard.
--
-- Current-step pick per partida (first match wins):
--   1. the EN_PROCESO paso            → something is physically running,
--   2. lowest-secuencia PENDIENTE paso whose predecessors are all settled
--                                     → ready and waiting at its station,
--   3. lowest-secuencia PENDIENTE paso → blocked behind unfinished work.
-- situacion encodes which case won. horas_en_estado is the dwell time — long
-- EN_COLA = a starved station, long EN_PROCESO vs tiempo_estandar = running over.
-- Driver filter (PROGRAMADA/EN_PRODUCCION) is backed by idx_partida_activa.
CREATE OR REPLACE VIEW mes.vw_wip AS
SELECT
    p.id                                                                   AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text, 4, '0') AS partida_codigo,
    p.estado_produccion,
    p.prioridad_id,
    pr.prioridad,
    p.tercero_id,
    c.nombre                                                               AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.color_hex,
    p.fecha_acordada,
    (p.fecha_acordada IS NOT NULL AND p.fecha_acordada < CURRENT_DATE)      AS flg_atraso,
    -- progress across the whole route
    tot.total_pasos,
    tot.pasos_hechos,
    CASE WHEN tot.total_pasos > 0
        THEN ROUND(tot.pasos_hechos::numeric / tot.total_pasos * 100, 0)
        ELSE 0 END                                                         AS progreso_porcentaje,
    -- current step
    cur.paso_id                                                            AS paso_actual_id,
    cur.secuencia                                                          AS secuencia_actual,
    cur.operacion_id,
    o.codigo                                                               AS operacion_codigo,
    o.nombre                                                               AS operacion_nombre,
    cur.ejecucion_id,
    cur.maquina_id,
    m.codigo                                                               AS maquina_codigo,
    m.nombre                                                               AS maquina_nombre,
    -- live situation + dwell
    CASE
        WHEN cur.paso_id IS NULL             THEN 'SIN_PASO'
        WHEN cur.estado_paso = 'EN_PROCESO'  THEN 'EN_PROCESO'
        WHEN cur.listo                       THEN 'EN_COLA'
        ELSE 'BLOQUEADA'
    END                                                                    AS situacion,
    cur.desde,
    ROUND((EXTRACT(EPOCH FROM (now() - cur.desde)) / 3600)::numeric, 1)     AS horas_en_estado,
    cur.tiempo_estandar
FROM mes.partida p
LEFT JOIN tercero c     ON c.id  = p.tercero_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN prioridad pr  ON pr.id = p.prioridad_id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*)                                                        AS total_pasos,
        COUNT(*) FILTER (WHERE pp.estado IN ('COMPLETADO','OMITIDO'))   AS pasos_hechos
    FROM mes.partida_paso pp
    WHERE pp.partida_id = p.id
) tot ON true
LEFT JOIN LATERAL (
    SELECT
        pp.id                                                          AS paso_id,
        pp.secuencia,
        pp.operacion_id,
        pp.estado                                                      AS estado_paso,
        pp.tiempo_estandar,
        pe.id                                                          AS ejecucion_id,
        pe.maquina_id,
        NOT EXISTS (
            SELECT 1 FROM mes.partida_paso prev
            WHERE prev.partida_id = pp.partida_id
              AND prev.secuencia  < pp.secuencia
              AND prev.estado NOT IN ('COMPLETADO','OMITIDO')
        )                                                              AS listo,
        -- when the current state began: run start if running; else the moment
        -- predecessors cleared (dropped into the queue); else the partida's
        -- schedule/creation time for the very first step.
        CASE
            WHEN pp.estado = 'EN_PROCESO' THEN pe.fyh_inicio
            ELSE COALESCE(
                (SELECT MAX(pe2.fyh_fin)
                   FROM mes.partida_paso prev
                   JOIN mes.partida_paso_ejecucion pe2 ON pe2.partida_paso_id = prev.id
                  WHERE prev.partida_id = pp.partida_id
                    AND prev.secuencia  < pp.secuencia
                    AND prev.estado IN ('COMPLETADO','OMITIDO')),
                p.fyh_programacion, p.fyh_cre)
        END                                                            AS desde
    FROM mes.partida_paso pp
    LEFT JOIN LATERAL (
        SELECT id, maquina_id, fyh_inicio
        FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = pp.id
        ORDER BY fyh_inicio DESC NULLS LAST
        LIMIT 1
    ) pe ON true
    WHERE pp.partida_id = p.id
      AND pp.estado IN ('PENDIENTE','EN_PROCESO')
    ORDER BY CASE WHEN pp.estado = 'EN_PROCESO' THEN 0 ELSE 1 END, pp.secuencia
    LIMIT 1
) cur ON true
LEFT JOIN mes.operacion o ON o.id = cur.operacion_id
LEFT JOIN mes.maquina m   ON m.id = cur.maquina_id
WHERE p.estado_produccion IN ('PROGRAMADA','EN_PRODUCCION');

GRANT SELECT ON mes.vw_wip TO authenticated;

-- ── mes.vw_maquina_cola ───────────────────────────────────────
-- Machine-centric board: one row per SCHEDULED activity (mes.programacion),
-- so the frontend groups by maquina_id and renders each machine's current run
-- plus everything queued behind it (order by fecha, orden_cola). Companion to
-- vw_wip (partida-centric) — together they are the two axes of the floor board.
--
-- Polymorphic like get_actividades_sin_programar: a programacion row is either a
-- 'partida_paso' (dyeing/finishing step) or a 'LAVADO_MAQUINA' (standalone wash);
-- the two legs are UNION-ed to a common shape (wash lines carry NULL partida info).
--
-- Scope is the live board: today's rows plus any still-open activity carried over
-- from earlier days. Idle machines have zero rows here by design — the board
-- frontend LEFT JOINs mes.vw_maquinas to surface machines with nothing scheduled.
-- flg_actual marks the line currently running on the machine; horas_en_estado is
-- its dwell so an over-running batch is obvious at a glance.
CREATE OR REPLACE VIEW mes.vw_maquina_cola AS
WITH cola AS (
    -- leg A · planned production step
    SELECT
        prog.maquina_id,
        prog.fecha,
        prog.secuencia                                                     AS orden_cola,
        prog.id                                                            AS programacion_id,
        prog.nota,
        prog.actividad_tipo,
        prog.actividad_id,
        pp.partida_id,
        EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text, 4, '0') AS partida_codigo,
        p.tercero_id,
        c.nombre                                                           AS cliente,
        p.color_x_cliente_id,
        vc.color,
        vc.color_hex,
        o.codigo                                                           AS operacion_codigo,
        o.nombre                                                           AS operacion_nombre,
        pp.secuencia                                                       AS paso_secuencia,
        pp.estado::text                                                    AS estado_actividad,
        (pp.estado = 'EN_PROCESO')                                         AS flg_actual,
        CASE WHEN pp.estado = 'EN_PROCESO' THEN pe.fyh_inicio END          AS desde
    FROM mes.programacion prog
    JOIN mes.partida_paso pp ON pp.id = prog.actividad_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    JOIN mes.operacion o     ON o.id  = pp.operacion_id
    LEFT JOIN tercero c      ON c.id  = p.tercero_id
    LEFT JOIN vw_colores vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN LATERAL (
        SELECT fyh_inicio
        FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = pp.id
        ORDER BY fyh_inicio DESC NULLS LAST
        LIMIT 1
    ) pe ON true
    WHERE prog.actividad_tipo = 'partida_paso'
      AND (prog.fecha >= CURRENT_DATE OR pp.estado IN ('PENDIENTE','EN_PROCESO'))

    UNION ALL

    -- leg B · standalone machine wash
    SELECT
        prog.maquina_id,
        prog.fecha,
        prog.secuencia,
        prog.id,
        prog.nota,
        prog.actividad_tipo,
        prog.actividad_id,
        NULL::bigint,
        NULL::text,
        NULL::int,
        NULL::text,
        NULL::int,
        NULL::text,
        NULL::text,
        'LAVADO_MAQUINA',
        'Lavado de máquina',
        NULL::smallint,
        lm.estado::text,
        (lm.estado = 'EN_PROCESO'),
        CASE WHEN lm.estado = 'EN_PROCESO' THEN lm.fyh_inicio END
    FROM mes.programacion prog
    JOIN mes.lavado_maquina lm ON lm.id = prog.actividad_id
    WHERE prog.actividad_tipo = 'LAVADO_MAQUINA'
      AND (prog.fecha >= CURRENT_DATE OR lm.estado IN ('PENDIENTE','EN_PROCESO'))
)
SELECT
    m.id                                                                   AS maquina_id,
    m.codigo                                                               AS maquina_codigo,
    m.nombre                                                               AS maquina_nombre,
    m.estado_actual                                                        AS maquina_estado,
    mt.operacion_id                                                        AS maquina_operacion_id,
    cola.fecha,
    cola.orden_cola,
    cola.programacion_id,
    cola.nota,
    cola.actividad_tipo,
    cola.actividad_id,
    cola.partida_id,
    cola.partida_codigo,
    cola.tercero_id,
    cola.cliente,
    cola.color_x_cliente_id,
    cola.color,
    cola.color_hex,
    cola.operacion_codigo,
    cola.operacion_nombre,
    cola.paso_secuencia,
    cola.estado_actividad,
    cola.flg_actual,
    cola.desde,
    ROUND((EXTRACT(EPOCH FROM (now() - cola.desde)) / 3600)::numeric, 1)    AS horas_en_estado
FROM cola
JOIN mes.maquina m        ON m.id  = cola.maquina_id
LEFT JOIN mes.maquina_tipo mt ON mt.id = m.maquina_tipo_id;

GRANT SELECT ON mes.vw_maquina_cola TO authenticated;

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
DROP VIEW IF EXISTS public.vw_dashboard_kpis;
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
  ps.en_partida              AS pasos_en_proceso,
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

-- ── inventario.vw_entregas_rollos_pendientes ─────────────────────
-- entregas with at least one in-stock roll not yet assigned to a partida.
-- Drops off automatically once all rolls are assigned or leave stock.
-- Mirrors the condition used by alertas.check_rollos_sin_programar.
CREATE OR REPLACE VIEW inventario.vw_entregas_rollos_pendientes AS
SELECT
    gr.id                                       AS entrega_id,
    gr.serie || '-' || gr.correlativo           AS entrega_numero,
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
FROM doc.entrega gr
JOIN doc.entrega_tipo grt         ON grt.id = gr.entrega_tipo_id
                                        AND grt.codigo = 'CLIENTE_ENVIO_PROCESO'
JOIN tercero t                          ON t.id = gr.tercero_id
JOIN inventario.lote_rollo_detalle lrd  ON lrd.entrega_id = gr.id
JOIN inventario.lote l                  ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
JOIN inventario.vw_stock_lotes sl       ON sl.lote_id = l.id
LEFT JOIN mes.partida_componente pc     ON pc.lote_id = l.id
GROUP BY gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id, t.nombre
HAVING COUNT(l.id) FILTER (WHERE pc.lote_id IS NULL) > 0;

GRANT SELECT ON inventario.vw_entregas_rollos_pendientes TO authenticated;

-- ── inventario.vw_rollos_por_entrega ────────────────────────────
-- Roll counts and weights aggregated per ingress entrega.
-- Used for intake review and entrega → partida assignment UI.
-- Only covers rolls with a entrega (MLR-confectioned rolls excluded).
CREATE OR REPLACE VIEW inventario.vw_rollos_por_entrega AS
SELECT
    gr.id                               AS entrega_id,
    gr.serie,
    gr.correlativo,
    gr.serie || '-' || gr.correlativo   AS entrega_numero,
    gr.fecha_emision,
    gr.tercero_id,
    t.nombre                            AS tercero_nombre,
    grt.codigo                          AS entrega_tipo,
    COUNT(lrd.lote_id)                  AS total_rollos,
    COUNT(lrd.lote_id) FILTER (WHERE lrd.flg_tenido = false) AS rollos_crudos,
    COUNT(lrd.lote_id) FILTER (WHERE lrd.flg_tenido = true)  AS rollos_tenidos,
    SUM(l.cantidad)                     AS peso_total_kg,
    -- Stock status
    COUNT(sa.lote_id)                   AS rollos_en_stock,
    SUM(sa.cantidad_disponible)         AS peso_en_stock_kg
FROM doc.entrega gr
JOIN doc.entrega_tipo grt         ON grt.id = gr.entrega_tipo_id
JOIN tercero t                          ON t.id = gr.tercero_id
JOIN inventario.lote_rollo_detalle lrd  ON lrd.entrega_id = gr.id
JOIN inventario.lote l                  ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
LEFT JOIN inventario.vw_stock_lotes sa ON sa.lote_id = l.id
GROUP BY gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id,
         t.nombre, grt.codigo;

-- ── inventario.vw_pesaje_pendiente ─────────────────────────────
-- One row per (partida, entrega, item) for partidas that have
-- a TENIDO paso scheduled AND at least one assigned roll with no
-- pesaje record.
-- Business rule: if any roll in the partida is unweighed the whole
-- batch must be reweighed (prorated flow), so the filter is at
-- partida level — ALL rolls for that partida are shown, not just
-- the unweighed ones.
-- Drives the print-friendly weighing form: the frontend groups by
-- partida → entrega → item to build the grid.
--
-- Partida header columns repeat on every row (denormalised for ease
-- of use — the frontend can read them from the first row per group).
-- fecha_programada: earliest scheduling board date for the TENIDO paso.
-- rollos: total assigned rolls for this (partida, entrega, item) cell.
-- flg_rib: true = rib item, false = regular. Lets the frontend style
--   rows differently without parsing item names.
DROP VIEW IF EXISTS mes.vw_pesaje_pendiente;
CREATE OR REPLACE VIEW mes.vw_pesaje_pendiente AS
SELECT
    -- ── Partida header (repeats per row) ──────────────────────
    p.id                                                                      AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                              AS partida_codigo,
    p.partida_origen_id,
    p.tercero_id,
    ter.nombre                                                                AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.color_hex,
    p.tenido_id,
    t.tenido,
    p.grupo_articulo_id,
    ga.nombre                                                                 AS grupo_articulo,
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

    -- ── entrega ──────────────────────────────────────────────────
    gr.id                                                                     AS entrega_id,
    gr.serie || '-' || gr.correlativo                                         AS entrega_numero,

    -- ── Item ──────────────────────────────────────────────────
    l.item_id,
    i.codigo                                                                  AS item_codigo,
    i.nombre                                                                  AS item_nombre,
    ird.flg_rib,

    -- ── Roll count for this (partida, entrega, item) cell ────────
    COUNT(*)::INT                                                             AS rollos

FROM mes.partida p
LEFT JOIN tercero       ter ON ter.id = p.tercero_id
LEFT JOIN vw_colores    vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido        t   ON t.id  = p.tenido_id
LEFT JOIN grupo_articulo ga ON ga.id = p.grupo_articulo_id

-- Walk from partida down to the actual rolls
JOIN mes.partida_componente            pc  ON pc.partida_id = p.id
                                          AND pc.lote_id IS NOT NULL
JOIN inventario.lote                   l   ON l.id  = pc.lote_id
                                          AND l.fyh_elm IS NULL
JOIN item                              i   ON i.id  = l.item_id
JOIN item_rollo_detalle                ird ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
LEFT JOIN doc.entrega             gr  ON gr.id = lrd.entrega_id

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
    p.grupo_articulo_id, ga.nombre,
    p.fibra, p.malla, p.rendimiento, p.ancho, p.fecha_acordada,
    gr.id, gr.serie, gr.correlativo,
    l.item_id, i.codigo, i.nombre, ird.flg_rib;

-- ── Grants ────────────────────────────────────────────────────
GRANT SELECT ON mes.vw_pesaje_pendiente             TO authenticated;
GRANT SELECT ON inventario.vw_rollos_por_entrega              TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_stock            TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_disponibles      TO anon, authenticated;
-- GRANT SELECT ON inventario.vw_stock_rollos              TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_rollos_crudos          TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_rollos_tenidos         TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_items                  TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_items_ubicacion        TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_items_valorado         TO authenticated;
GRANT SELECT ON inventario.vw_stock_x_proveedor            TO authenticated;
GRANT SELECT ON inventario.vw_stock_insumos                TO authenticated;
GRANT SELECT ON inventario.vw_lotes_disponibles            TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_despachados     TO anon, authenticated;
GRANT SELECT ON inventario.vw_items_movimientos            TO anon, authenticated;
GRANT SELECT ON mes.vw_maquinas                   TO authenticated;
GRANT SELECT ON mes.vw_empleados_activos          TO authenticated;
GRANT SELECT ON mes.vw_pasos                      TO anon, authenticated;
GRANT SELECT ON mes.vw_partida_produccion_rollos  TO anon, authenticated;
GRANT SELECT ON calidad.vw_lotes_pendientes_inspeccion    TO authenticated;
GRANT SELECT ON calidad.vw_qc_pendiente_output             TO authenticated;
GRANT SELECT ON calidad.vw_qc_pendiente_input              TO authenticated;
GRANT SELECT ON calidad.vw_inspecciones                   TO authenticated;
GRANT SELECT ON calidad.vw_partidas_pendientes_calidad    TO authenticated;
GRANT SELECT ON calidad.vw_auditoria_pendiente            TO authenticated;
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
GRANT SELECT,INSERT, UPDATE ON mes.operacion   TO authenticated;
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
DROP VIEW IF EXISTS calidad.vw_auditoria_pendiente         CASCADE;
DROP VIEW IF EXISTS calidad.vw_partidas_pendientes_calidad CASCADE;
DROP VIEW IF EXISTS calidad.vw_inspecciones                CASCADE;
DROP VIEW IF EXISTS calidad.vw_lotes_pendientes_inspeccion CASCADE;
DROP VIEW IF EXISTS calidad.vw_qc_pendiente_input          CASCADE;
DROP VIEW IF EXISTS calidad.vw_qc_pendiente_output          CASCADE;

-- mes views
DROP VIEW IF EXISTS mes.vw_cola_estacion                   CASCADE;
DROP VIEW IF EXISTS mes.vw_pasos                           CASCADE;
DROP VIEW IF EXISTS mes.vw_empleados_activos               CASCADE;
DROP VIEW IF EXISTS mes.vw_maquinas                        CASCADE;
DROP VIEW IF EXISTS mes.vw_partida_resumen_tenido          CASCADE;
DROP VIEW IF EXISTS mes.vw_partida_produccion_rollos       CASCADE;
DROP VIEW IF EXISTS mes.vw_partidas                        CASCADE;

-- inventario views (dependent on vw_stock_lotes — drop before it)
DROP VIEW IF EXISTS inventario.vw_pesaje_pendiente         CASCADE;
DROP VIEW IF EXISTS inventario.vw_entregas_rollos_pendientes  CASCADE;
DROP VIEW IF EXISTS inventario.vw_rollos_por_entrega          CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_despachados CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_disponibles CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock       CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_rollos_tenidos     CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_rollos_crudos      CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_items_valorado     CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_x_proveedor        CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_items_ubicacion    CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_items              CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_insumos            CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_disponibles        CASCADE;
DROP VIEW IF EXISTS inventario.vw_item_proveedor_entrega      CASCADE;
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




-- doc.vw_ordenes_servicio — retired in patch-35 (collapsed into entrega INGRESO_INTERNO)
DROP VIEW IF EXISTS doc.vw_ordenes_servicio;

-- ── doc.vw_pendientes_proceso ─────────────────────────────────
-- Reporte "Pendientes de Proceso": por cada (entrega × artículo), cuántos
-- rollos siguen en planta esperando proceso.
-- Acotado a rollos EN STOCK; excluye productos terminados esperando despacho
-- (origen_lote_id IS NULL OR asignado a partida activa).
DROP VIEW IF EXISTS doc.vw_rollos_estado;
CREATE OR REPLACE VIEW doc.vw_pendientes_proceso AS
WITH rollos AS (
    SELECT
        lrd.entrega_id,
        gr.serie || '-' || COALESCE(gr.correlativo, gr.id::text) AS documento,
        gr.fecha_emision::date                                    AS fecha_emision,
        gr.tercero_id,
        tg.nombre                                                 AS cliente,
        ird.articulo_id,
        art.nombre                                                AS articulo,
        art.articulo_tipo_id,
        at.nombre                                                 AS articulo_tipo,
        art.fibra,
        l.cantidad                                                AS peso_kg,
        lrd.flg_tenido,
        lrd.origen_lote_id,
        EXISTS (
            SELECT 1
            FROM mes.partida_componente pc
            JOIN mes.partida p ON p.id = pc.partida_id
            WHERE pc.lote_id = l.id
              AND pc.item_id IS NULL
              AND p.estado_produccion NOT IN ('TECO', 'CERRADA', 'CANCELADA')
              AND p.fyh_elm IS NULL
        )                                                         AS asignado
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id
    JOIN inventario.vw_stock_lotes sl       ON sl.lote_id = l.id
    LEFT JOIN item_rollo_detalle ird        ON ird.item_id = l.item_id
    LEFT JOIN articulo art                  ON art.id = ird.articulo_id
    LEFT JOIN articulo_tipo at              ON at.id = art.articulo_tipo_id
    LEFT JOIN doc.entrega gr                ON gr.id = lrd.entrega_id
    LEFT JOIN tercero tg                    ON tg.id = gr.tercero_id
    WHERE l.fyh_elm IS NULL
      AND gr.fyh_elm IS NULL
      AND lrd.entrega_id IS NOT NULL
)
SELECT
    entrega_id,
    documento,
    fecha_emision,
    tercero_id,
    cliente,
    articulo_id,
    articulo,
    articulo_tipo_id,
    articulo_tipo,
    fibra,
    COUNT(*)                                 AS rollos_en_stock,
    COUNT(*) FILTER (WHERE NOT asignado)     AS rollos_sin_asignar,
    COUNT(*) FILTER (WHERE asignado)         AS rollos_asignados_pendientes,
    COUNT(*) FILTER (WHERE NOT flg_tenido)   AS rollos_sin_tenir,
    ROUND(SUM(peso_kg)::numeric, 2)          AS kg_en_stock
FROM rollos
WHERE origen_lote_id IS NULL
   OR asignado
GROUP BY
    entrega_id, documento, fecha_emision, tercero_id, cliente,
    articulo_id, articulo, articulo_tipo_id, articulo_tipo, fibra;

GRANT SELECT ON doc.vw_pendientes_proceso TO authenticated;

-- ── inventario.vw_cuadre ──────────────────────────────────────
-- Originally in 05_new_tables_foundation.sql but omitted almacen_id in live DB.
-- Redefined here so reruns pick up the correct column set.
-- DROP required because almacen_id is mid-list; CREATE OR REPLACE only allows appending.
DROP VIEW IF EXISTS inventario.vw_cuadre CASCADE;
CREATE OR REPLACE VIEW inventario.vw_cuadre AS
SELECT
    c.id           AS cuadre_id,
    c.fecha_cuadre,
    c.fecha_cierre,
    c.estado,
    c.almacen_id,
    (SELECT MAX(c2.fecha_cierre)
     FROM inventario.cuadre c2
     WHERE c2.estado = 'ejecutado'
       AND c2.id < c.id
       AND (c2.almacen_id = c.almacen_id
            OR (c2.almacen_id IS NULL AND c.almacen_id IS NULL))) AS ult_cuadre_ejecutado_fecha
FROM inventario.cuadre c;

GRANT SELECT ON inventario.vw_cuadre TO authenticated;

-- ── doc.vw_catalogo_precios_historico ─────────────────────────
-- Every catalog price row ever written (active + superseded), with
-- display names joined in. catalogo_precios is already historic by
-- design — upsert_catalogo_precio (funciones/facturacion.sql) never
-- overwrites a row in place, it closes the old one (fyh_elm) and
-- inserts a new one — so this just surfaces that lineage.
--
-- RLS on the underlying table (comercial_ver policy, migration/10)
-- applies here same as any other view, so frontend can query/filter
-- this directly (.eq() on any dimension, or none for the full list)
-- without a round trip per combination.
--
-- grupo_articulo_id/tenido_id here are the raw stored values (TENIDO
-- rows already normalized to their pricing family by upsert_catalogo_precio
-- — see doc.fn_familia_precio). Filtering for one specific combo's
-- lineage must normalize the same way first.
DROP VIEW IF EXISTS doc.vw_catalogo_precios_historico CASCADE;
CREATE OR REPLACE VIEW doc.vw_catalogo_precios_historico AS
SELECT
    cp.id,
    cp.operacion_id,
    op.nombre               AS operacion,
    cp.color_x_cliente_id,
    c.color,
    cp.tercero_id,
    t.nombre                AS cliente,
    cp.grupo_articulo_id,
    ga.nombre                AS grupo_articulo,
    cp.tenido_id,
    ten.tenido,
    cp.fibra,
    cp.precio_kg,
    cp.costo_kg,
    cp.usr_cre,
    cp.fyh_cre,
    cp.usr_elm,
    cp.fyh_elm,
    (cp.fyh_elm IS NULL)     AS activo
FROM doc.catalogo_precios cp
JOIN mes.operacion op             ON op.id = cp.operacion_id
LEFT JOIN color_x_cliente cxc     ON cxc.id = cp.color_x_cliente_id
LEFT JOIN public.color c          ON c.id   = cxc.color_id
LEFT JOIN tercero t                ON t.id   = COALESCE(cp.tercero_id, cxc.tercero_id)
LEFT JOIN public.grupo_articulo ga ON ga.id  = cp.grupo_articulo_id
LEFT JOIN tenido ten                ON ten.id = cp.tenido_id
ORDER BY cp.fyh_cre DESC;

GRANT SELECT ON doc.vw_catalogo_precios_historico TO authenticated;

-- ── doc.vw_familia_precio ───────────────────────────────────────
-- Read model for doc.articulo_tipo_familia (the grupo_articulo → pricing
-- family mapping table; renamed to grupo_articulo_familia in migration 34,
-- not yet applied — GRUPO_ARTICULO_HANDOFF.md decision 12). Written via
-- doc.upsert_familia_precio (funciones/facturacion.sql), read by
-- doc.fn_familia_precio for TENIDO pricing only.
--
-- flg_default: tercero_id IS NULL → applies to every client unless a
-- per-client row overrides it. Both can exist for the same grupo — the
-- override wins (fn_familia_precio ORDER BY tercero_id NULLS LAST).
--
-- flg_bucket_remapped surfaces the documented one-hop landmine in
-- fn_familia_precio: familia_grupo_id is itself resolved through this same
-- table with no recursion, so a bucket that is ALSO a mapped subject (e.g.
-- default 4,9→18 while a client override sends 4,9→20) only resolves
-- correctly today because of ORDER BY luck between the two rows. TRUE here
-- means the bucket in this row has its own mapping row(s) and needs eyeballing
-- before relying on it — do not add a second hop to fix this, see the
-- doc.familia_precio backlog item in GRUPO_ARTICULO_HANDOFF.md instead.
--
-- Legacy articulo_tipo_id/familia_id are intentionally NOT projected — they
-- are being phased out and new rows (via upsert_familia_precio) never
-- populate them.
DROP VIEW IF EXISTS doc.vw_familia_precio CASCADE;
CREATE OR REPLACE VIEW doc.vw_familia_precio AS
SELECT
    f.grupo_articulo_id,
    g.nombre                AS grupo_articulo,
    f.tercero_id,
    t.nombre                 AS cliente,
    (f.tercero_id IS NULL)   AS flg_default,
    f.familia_grupo_id,
    gf.nombre                AS familia_grupo,
    EXISTS (
        SELECT 1 FROM doc.articulo_tipo_familia f2
        WHERE f2.grupo_articulo_id = f.familia_grupo_id
    )                         AS flg_bucket_remapped,
    f.usr_cre,
    f.fyh_cre,
    f.usr_mod,
    f.fyh_mod
FROM doc.articulo_tipo_familia f
JOIN public.grupo_articulo g  ON g.id  = f.grupo_articulo_id
JOIN public.grupo_articulo gf ON gf.id = f.familia_grupo_id
LEFT JOIN tercero t            ON t.id  = f.tercero_id
ORDER BY g.nombre, flg_default DESC;

GRANT SELECT ON doc.vw_familia_precio TO authenticated;


-- ── mes.vw_partida_comercial ────────────────────────────────────────────────
-- DERIVED dispatch-fulfillment + billing projection, at FAMILIA (root) level.
-- This is the authoritative truth mes.partida.estado_comercial only CACHES
-- (see doc.recompute_estado_comercial, funciones/despacho.sql) — if they ever
-- disagree, THIS view is right. Reuses mes.vw_partida_familia_output for the
-- terminal-lote dedup rule so the numbers can't drift from cerrar_partida /
-- get_partida_familia. See VENTA_MODULE_HANDOFF.md decisions #9, #12.
--
-- dispatched_ahora = terminal APROBADO lotes with a live SERV_EGR/VENTA_EGR
--   (no later SERV_DEV_ING/DEV_CLI_ING undoing it) — mirrors recompute's fold.
-- pendiente        = GREATEST(0, total_terminal - dispatched_ahora)
-- Billing columns roll up doc.venta_detalle for this root partida (venta lines
-- bill against INTENT, i.e. always the root — decision #6), excluding ANULADA
-- ventas. A partida can have venta lines with no dispatch yet is NOT possible
-- (venta is born at dispatch — decision on venta lifecycle) so these two halves
-- are always consistent by construction.
-- ─────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS mes.vw_partida_comercial;
CREATE VIEW mes.vw_partida_comercial AS
WITH terminal AS (
    SELECT root_id, lote_id
    FROM mes.vw_partida_familia_output
    WHERE estado_calidad = 'APROBADO'
),
fulfillment AS (
    SELECT
        t.root_id,
        COUNT(*) AS total_terminal,
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = t.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
            )
            AND NOT EXISTS (
                SELECT 1 FROM inventario.item_movimientos im2
                JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                WHERE im2.lote_id = t.lote_id AND imt2.codigo IN ('SERV_DEV_ING','DEV_CLI_ING')
            )
        ) AS dispatched_ahora
    FROM terminal t
    GROUP BY t.root_id
)
SELECT
    p.id                                                                     AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo,
    p.tercero_id,
    c.nombre                                                                 AS cliente,
    p.estado_comercial                                                       AS estado_comercial_cache,
    COALESCE(f.total_terminal, 0)                                            AS total_terminal,
    COALESCE(f.dispatched_ahora, 0)                                          AS dispatched_ahora,
    GREATEST(0, COALESCE(f.total_terminal, 0) - COALESCE(f.dispatched_ahora, 0)) AS pendiente,
    v.venta_ids,
    v.referencia_refs,
    v.total_kg_facturado,
    v.total_importe
FROM mes.partida p
JOIN tercero c ON c.id = p.tercero_id
LEFT JOIN fulfillment f ON f.root_id = p.id
LEFT JOIN LATERAL (
    SELECT
        jsonb_agg(DISTINCT vd.venta_id)                                            AS venta_ids,
        jsonb_agg(DISTINCT (ve.referencia_serie || '-' || ve.referencia_correlativo))
            FILTER (WHERE ve.referencia_serie IS NOT NULL)                         AS referencia_refs,
        SUM(vd.cantidad_kg)                                                        AS total_kg_facturado,
        SUM(vd.cantidad_kg * COALESCE(
            (SELECT SUM(c.precio_kg) FROM doc.venta_detalle_cargo c WHERE c.venta_detalle_id = vd.id), 0
        ))                                                                         AS total_importe
    FROM doc.venta_detalle vd
    JOIN doc.venta ve ON ve.id = vd.venta_id AND ve.flg_elm = false
    WHERE vd.partida_id = p.id
) v ON true
WHERE p.partida_origen_id IS NULL   -- root only, matches mes.vw_partida_familia convention
  AND p.fyh_elm IS NULL;

GRANT SELECT ON mes.vw_partida_comercial TO authenticated;


-- ── doc.vw_venta ────────────────────────────────────────────────────────────
-- Read surface for the sales spine: ITEM line (venta_detalle, one per
-- articulo×tenido×color) + its CHARGE sub-lines aggregated (venta_detalle_cargo,
-- one per operación — see migration/patches/56_venta_detalle_item_grain.sql /
-- VENTA_PER_ITEM_BILLING_SPEC.md). importe = cantidad_kg × Σcargo.precio_kg.
-- Composed description fills in when venta_detalle.descripcion is blank
-- (doc.fn_descripcion_linea — a manual override, if present, always wins).
-- ─────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS doc.vw_venta;
CREATE VIEW doc.vw_venta AS
SELECT
    v.id                AS venta_id,
    v.tercero_id,
    t.nombre            AS cliente,
    v.fecha,
    v.referencia_serie,
    v.referencia_correlativo,
    vd.id               AS detalle_id,
    vd.linea,
    vd.tipo,
    vd.item_id,
    it.nombre           AS item_nombre,
    vd.articulo_id,
    art.nombre          AS articulo,
    vd.partida_id,
    pcod.codigo         AS partida_codigo,
    vd.color_x_cliente_id,
    vc.color,
    vd.tenido_id,
    ten.tenido,
    vd.grupo_articulo_id,
    ga.nombre           AS grupo_articulo,
    vd.cantidad_kg,
    vd.cantidad_rollos,
    cg.precio_kg_total,
    ROUND(vd.cantidad_kg * COALESCE(cg.precio_kg_total, 0), 2) AS importe,
    cg.cargos,
    COALESCE(
        vd.descripcion,
        doc.fn_descripcion_linea(
            vd.tipo, vd.item_id, vd.articulo_id, vd.color_x_cliente_id, vd.tenido_id
        )
    )                   AS descripcion
FROM doc.venta v
JOIN tercero t ON t.id = v.tercero_id
LEFT JOIN doc.venta_detalle vd ON vd.venta_id = v.id
LEFT JOIN LATERAL (
    SELECT SUM(c.precio_kg) AS precio_kg_total,
           jsonb_agg(jsonb_build_object(
               'operacion_id', c.operacion_id,
               'operacion',    (SELECT nombre FROM mes.operacion WHERE id = c.operacion_id),
               'precio_kg',    c.precio_kg) ORDER BY c.operacion_id NULLS FIRST) AS cargos
    FROM doc.venta_detalle_cargo c WHERE c.venta_detalle_id = vd.id
) cg ON true
LEFT JOIN public.articulo art      ON art.id = vd.articulo_id
LEFT JOIN item it                  ON it.id = vd.item_id
LEFT JOIN vw_colores vc            ON vc.color_x_cliente_id = vd.color_x_cliente_id
LEFT JOIN tenido ten                ON ten.id = vd.tenido_id
LEFT JOIN grupo_articulo ga        ON ga.id = vd.grupo_articulo_id
LEFT JOIN LATERAL (
    SELECT EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo
    FROM mes.partida p WHERE p.id = vd.partida_id
) pcod ON true
WHERE v.flg_elm = false;

GRANT SELECT ON doc.vw_venta TO authenticated;


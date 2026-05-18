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

-- ── inventario.vw_stock_actual ────────────────────────────────
-- Two branches unioned, both fully maintained — no aggregation at query time.
--   Lot-tracked (rollos): reads lote.cantidad_actual  (≈ SAP MCHB)
--   Lot-less (insumos):   reads saldo_item.cantidad_actual (≈ SAP MARD)
CREATE OR REPLACE VIEW inventario.vw_stock_actual AS
SELECT
    l.id                AS lote_id,
    l.item_id,
    NULL::INT           AS ubicacion_id,
    l.cantidad_actual   AS cantidad_disponible,
    l.fyh_cre           AS fecha_hora_ingreso
FROM inventario.lote l
WHERE l.cantidad_actual > 0
  AND l.fyh_elm IS NULL
UNION ALL
SELECT
    NULL::INT           AS lote_id,
    si.item_id,
    NULL::INT           AS ubicacion_id,
    si.cantidad_actual  AS cantidad_disponible,
    NULL::TIMESTAMPTZ   AS fecha_hora_ingreso
FROM inventario.saldo_item si
WHERE si.cantidad_actual > 0;

GRANT SELECT ON inventario.vw_stock_actual TO anon, authenticated;


-- ── inventario.vw_lotes_rollos_stock ─────────────────────────
-- Shows all rolls currently in stock (dyed and undyed).
-- Batch attributes come from partida for both dyed and undyed rolls —
-- this shows "expected" specs for undyed rolls (useful for operators).
-- For dyed rolls the same values are also on lote_rollo_detalle.
-- lote_rollo_detalle is joined for: guia_remision_id, flg_tenido.
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock;
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
FROM inventario.vw_stock_actual sa
JOIN inventario.lote l                  ON l.id = sa.lote_id
JOIN item i                             ON i.id = sa.item_id
JOIN item_tipo it                       ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN item_rollo_detalle ird             ON ird.item_id = i.id
JOIN articulo art                       ON art.id = ird.articulo_id
JOIN unidad un                          ON un.id = i.unidad_id
JOIN inventario.ubicacion u             ON u.id = sa.ubicacion_id
JOIN inventario.almacen a               ON a.id = u.almacen_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id
LEFT JOIN doc.guia_remision gr          ON gr.id = lrd.guia_remision_id
LEFT JOIN tercero t                     ON t.id = l.propietario_id
LEFT JOIN vw_colores vc                 ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN tenido tn                     ON tn.id = lrd.tenido_id
ORDER BY art.nombre, u.nombre, i.nombre;

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
    p.partida_origen_id,
    p.fyh_cre,
    p.fyh_inicio,
    p.fyh_fin,
    p.tercero_id,
    c.nombre                                                               AS cliente,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    p.tenido_id,
    t.tenido,
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
    prof.nombre || ' ' || prof.apellido                                    AS creado_por
FROM mes.partida p
LEFT JOIN tercero c     ON c.id  = p.tercero_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido t      ON t.id  = p.tenido_id
LEFT JOIN usuario prof  ON prof.id = p.usr_cre
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
    c.observacion,
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
) letras ON true;

GRANT SELECT ON doc.vw_compras TO authenticated;

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
        SUM(im.cantidad * imt.factor)                                   AS saldo,
        BOOL_OR(imt.factor = -1 AND imt.categoria != 'PRODUCCION')     AS has_egreso
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


-- ── mes.partida_resumen_tenido ────────────────────────────────
CREATE OR REPLACE VIEW mes.vw_partida_resumen_tenido AS
SELECT
    pd.partida_id,
    a.id            AS articulo_id,
    a.nombre        AS articulo_nombre,
    a.articulo_tipo_id,           -- added
    at.nombre       AS articulo_tipo_nombre,  -- added
    a.fibra,
    COUNT(pd.item_id)                                                    AS total_rollos,
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

-- ── inventario.vw_stock_general ───────────────────────────────
CREATE OR REPLACE VIEW inventario.vw_stock_general AS
SELECT
    vi.item_id,
    vi.item_codigo,
    vi.item_nombre,
    vi.item_tipo_id,
    vi.item_tipo_codigo,
    SUM(sa.cantidad_disponible) AS cantidad_total,
    vi.unidad_id,
    vi.unidad_codigo
FROM inventario.vw_stock_actual sa
LEFT JOIN vw_items vi ON vi.item_id = sa.item_id
GROUP BY vi.item_id, vi.item_codigo, vi.item_nombre, vi.item_tipo_id, vi.item_tipo_codigo, vi.unidad_id, vi.unidad_codigo;

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
FROM inventario.vw_stock_actual sa
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
FROM inventario.vw_stock_actual sa
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
-- Reads from maintained saldo_item — no aggregation at query time.
CREATE OR REPLACE VIEW inventario.vw_stock_insumos AS
SELECT
    si.item_id,
    i.codigo            AS item_codigo,
    i.nombre            AS item_nombre,
    si.cantidad_actual  AS cantidad_total,
    un.codigo           AS unidad_codigo,
    iid.insumo_tipo_id,
    intp.codigo         AS insumo_tipo_codigo,
    intp.nombre         AS insumo_tipo_nombre,
    iid.colorante_tipo_id,
    ct.codigo           AS colorante_tipo_codigo,
    ct.nombre           AS colorante_tipo_nombre
FROM inventario.saldo_item si
JOIN item i        ON i.id = si.item_id
JOIN item_tipo it  ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
JOIN unidad un     ON un.id = i.unidad_id
LEFT JOIN item_insumo_detalle iid  ON iid.item_id = si.item_id
LEFT JOIN insumo_tipo intp         ON intp.id = iid.insumo_tipo_id
LEFT JOIN colorante_tipo ct        ON ct.id = iid.colorante_tipo_id
WHERE si.cantidad_actual > 0;

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
FROM inventario.vw_stock_actual sa
LEFT JOIN vw_items vi ON vi.item_id = sa.item_id
LEFT JOIN inventario.lote l ON l.id = sa.lote_id;

-- ── calidad.vw_lotes_pendientes_inspeccion ────────────────────
-- Shows all ROLLO lotes pending QC:
--   Output rolls: created by a partida_paso_ejecucion (always eligible)
--   Input rolls:  assigned via partida_componente to an EN_PRODUCCION partida
-- Step/machine context comes from the ejecucion path (NULL for input rolls).
-- Partida context is resolved from whichever path applies.
DROP VIEW IF EXISTS calidad.vw_lotes_pendientes_inspeccion;
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
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || p.numero    AS partida_codigo,
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
    pp.id AS paso_id,
    pp.secuencia,
    pp.partida_id,
    p.numero AS partida_numero,
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    pp.operacion_id,
    o.codigo AS operacion_codigo,
    o.nombre AS operacion_nombre,
    o.requiere_receta,
    o.requiere_maquina,
    pp.maquina_planificada_id,
    pp.receta_id,
    m.codigo AS maquina_codigo,
    m.nombre AS maquina_nombre,
    -- Derived execution state: PENDIENTE when no ejecucion rows exist
    CASE
        WHEN pe.id IS NOT NULL AND pe.estado = 'COMPLETADO' THEN 'COMPLETADO'
        WHEN pe.id IS NOT NULL AND pe.estado = 'EN_PROCESO' THEN 'EN_PROCESO'
        WHEN pe.id IS NOT NULL AND pe.estado = 'OMITIDO'    THEN 'OMITIDO'
        ELSE 'PENDIENTE'
    END AS estado
FROM mes.partida_paso pp
JOIN mes.partida p ON p.id = pp.partida_id
JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN LATERAL (
    SELECT id, estado, maquina_id
    FROM mes.partida_paso_ejecucion
    WHERE partida_paso_id = pp.id
    ORDER BY fyh_inicio DESC NULLS LAST
    LIMIT 1
) pe ON true
LEFT JOIN mes.maquina m ON m.id = COALESCE(pe.maquina_id, pp.maquina_planificada_id);

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
    imt.factor,
    im.cantidad,
    im.cantidad * imt.factor                                          AS cantidad_neta,
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
    FROM inventario.vw_stock_actual sa
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
LEFT JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id
GROUP BY gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id,
         t.nombre, grt.codigo;

-- ── Grants ────────────────────────────────────────────────────
GRANT SELECT ON inventario.vw_rollos_por_guia         TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_stock      TO anon, authenticated;
-- GRANT SELECT ON inventario.vw_stock_rollos        TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_rollos_crudos   TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_rollos_tenidos  TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_general       TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_insumos       TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_disponibles   TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_despachados TO anon, authenticated;
GRANT SELECT ON inventario.vw_items_movimientos   TO anon, authenticated;
GRANT SELECT ON mes.vw_maquinas                   TO authenticated;
GRANT SELECT ON mes.vw_empleados_activos          TO authenticated;
GRANT SELECT ON mes.vw_pasos                      TO anon, authenticated;
GRANT SELECT ON mes.vw_partida_produccion_rollos  TO anon, authenticated;
GRANT SELECT ON calidad.vw_lotes_pendientes_inspeccion TO authenticated;
GRANT SELECT ON calidad.vw_inspecciones           TO authenticated;
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
GRANT UPDATE ON mes.operacion           TO authenticated;

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
DROP VIEW IF EXISTS calidad.vw_inspecciones                CASCADE;
DROP VIEW IF EXISTS calidad.vw_lotes_pendientes_inspeccion CASCADE;

-- mes views
DROP VIEW IF EXISTS mes.vw_pasos                           CASCADE;
DROP VIEW IF EXISTS mes.vw_empleados_activos               CASCADE;
DROP VIEW IF EXISTS mes.vw_maquinas                        CASCADE;
DROP VIEW IF EXISTS mes.vw_partida_resumen_tenido          CASCADE;
DROP VIEW IF EXISTS mes.vw_partida_produccion_rollos       CASCADE;
DROP VIEW IF EXISTS mes.vw_partidas                        CASCADE;

-- inventario views (dependent on vw_stock_actual — drop before it)
DROP VIEW IF EXISTS inventario.vw_rollos_por_guia          CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_despachados CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock       CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_rollos_tenidos     CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_rollos_crudos      CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_general            CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_insumos            CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_disponibles        CASCADE;
DROP VIEW IF EXISTS inventario.vw_precio_promedio_insumos  CASCADE;
DROP VIEW IF EXISTS inventario.vw_item_proveedor_guia      CASCADE;
DROP VIEW IF EXISTS inventario.vw_items_movimientos        CASCADE;
DROP VIEW IF EXISTS inventario.vw_stock_actual             CASCADE;

-- doc views
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

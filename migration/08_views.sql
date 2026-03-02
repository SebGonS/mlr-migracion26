-- ═══════════════════════════════════════════════════════════════
-- Step 8: Views
-- Must come after all tables they reference.
-- ═══════════════════════════════════════════════════════════════

-- ── vw_colores ────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_colores AS
SELECT
    a.id AS color_x_cliente_id,
    b.id AS color_id,
    b.color,
    c.id AS cliente_id,
    c.cliente AS tono,
    c.cliente AS cliente,
    a.hex AS color_x_cliente_hex,
    b.hex AS color_hex
FROM color_x_cliente a
JOIN color b ON a.color_id = b.id
JOIN cliente c ON a.cliente_id = c.id;

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
CREATE OR REPLACE VIEW inventario.vw_stock_actual AS
SELECT
    im.lote_id,
    im.item_id,
    COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id) AS ubicacion_id,
    SUM(im.cantidad * imt.factor) AS cantidad_disponible,
    MIN(im.fecha_hora) AS fecha_hora_ingreso
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON im.item_movimiento_tipo_id = imt.id
GROUP BY im.lote_id, im.item_id, COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id)
HAVING SUM(im.cantidad * imt.factor) > 0;

GRANT SELECT ON inventario.vw_stock_actual TO anon, authenticated;

-- ── inventario.vw_lotes_rollos_stock ─────────────────────────
CREATE OR REPLACE VIEW inventario.vw_lotes_rollos_stock AS
SELECT
    sa.lote_id,
    sa.item_id,
    i.codigo AS item_codigo,
    i.nombre AS item_nombre,
    sa.ubicacion_id,
    u.nombre AS ubicacion,
    a.nombre AS almacen,
    sa.cantidad_disponible,
    un.codigo AS unidad,
    l.estado_calidad::text,
    (l.detalles->>'ancho')::numeric AS ancho,
    l.cantidad AS peso,
    ird.articulo_id,
    art.nombre AS articulo,  -- FIX: was art.articulo (old column name)
    ird.flg_tenido,
    ird.flg_rib,
    art.fibra,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.cliente_id,
    vc.color_hex,
    vc.color_x_cliente_hex,
    c.id AS propietario_id,
    c.cliente AS propietario
FROM inventario.vw_stock_actual sa
JOIN inventario.lote l ON l.id = sa.lote_id
JOIN item i ON i.id = sa.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id
JOIN item_rollo_detalle ird ON ird.item_id = i.id
JOIN articulo art ON art.id = ird.articulo_id
JOIN unidad un ON un.id = i.unidad_id
JOIN inventario.ubicacion u ON u.id = sa.ubicacion_id
JOIN inventario.almacen a ON a.id = u.almacen_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = (l.detalles->>'color_x_cliente_id')::smallint
LEFT JOIN cliente c ON c.id = l.propietario_id
WHERE it.codigo = 'ROLLO'
ORDER BY a.nombre, u.nombre, i.nombre;

-- ── doc.vw_partidas_lista_comercial ───────────────────────────
DROP VIEW IF EXISTS doc.vw_partidas_lista_comercial;
CREATE OR REPLACE VIEW doc.vw_partidas_lista_comercial AS
SELECT
    p.id,
    p.numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo,
    p.estado,
    p.cliente_id,
    c.cliente,
    p.prioridad_id,
    pri.prioridad,
    p.tenido_id,
    t.tenido,
    p.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    vc.color_x_cliente_hex,
    p.malla,
    p.rendimiento,
    p.ancho,
    p.flg_antipilling,
    p.fyh_cre AS fecha_creacion,
    p.fyh_programacion AS fecha_programacion,
    p.fyh_inicio AS fecha_inicio,
    p.fyh_fin AS fecha_finalizacion,
    EXTRACT(EPOCH FROM (NOW() - p.fyh_cre)) / 86400 AS dias_desde_creacion,
    COALESCE(pd_agg.total_items, 0) AS total_items,
    COALESCE(pd_agg.cantidad_total, '0') AS cantidad_total,
    COALESCE(pd_agg.cantidad_principales, '0') AS cantidad_principales,
    COALESCE(pd_agg.cantidad_rib, '0') AS cantidad_rib,
    CASE
        WHEN EXISTS (SELECT 1 FROM mes.orden_produccion op WHERE op.partida_id = p.id)
        THEN true ELSE false
    END AS tiene_ordenes_produccion,
    p.usr_cre,
    p.fyh_cre
FROM doc.partida p
LEFT JOIN cliente c ON c.id = p.cliente_id
LEFT JOIN prioridad pri ON pri.id = p.prioridad_id
LEFT JOIN tenido t ON t.id = p.tenido_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS total_items,
        SUM(pd.cantidad) AS cantidad_total,
        SUM(CASE WHEN ird.flg_rib = FALSE THEN pd.cantidad ELSE 0 END) AS cantidad_principales,
        SUM(CASE WHEN ird.flg_rib = TRUE  THEN pd.cantidad ELSE 0 END) AS cantidad_rib
    FROM doc.partida_detalle pd
    LEFT JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    WHERE pd.partida_id = p.id
) pd_agg ON true;

GRANT SELECT ON doc.vw_partidas_lista_comercial TO authenticated;

-- ── mes.vw_ordenes_produccion ─────────────────────────────────
DROP VIEW IF EXISTS mes.vw_ordenes_produccion;
CREATE OR REPLACE VIEW mes.vw_ordenes_produccion AS
SELECT
    op.id,
    op.tipo,
    op.estado,
    op.orden_origen_id,
    op.fyh_cre,
    op.fyh_inicio,
    op.fyh_fin,
    op.partida_id,
    p.numero AS partida_numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    p.estado AS partida_estado,
    c.id AS cliente_id,
    c.cliente,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    t.id AS tenido_id,
    t.tenido,
    COALESCE(pasos_stats.total_pasos, 0)        AS total_pasos,
    COALESCE(pasos_stats.pasos_completados, 0)  AS pasos_completados,
    COALESCE(pasos_stats.pasos_en_proceso, 0)   AS pasos_en_proceso,
    COALESCE(pasos_stats.pasos_pendientes, 0)   AS pasos_pendientes,
    CASE
        WHEN COALESCE(pasos_stats.total_pasos, 0) > 0
        THEN ROUND((COALESCE(pasos_stats.pasos_completados, 0)::NUMERIC / pasos_stats.total_pasos::NUMERIC) * 100, 0)
        ELSE 0
    END AS progreso_porcentaje,
    COALESCE(materiales_stats.total_materiales, 0)  AS total_materiales,
    COALESCE(materiales_stats.cantidad_total_kg, 0) AS cantidad_total_kg,
    COALESCE(produccion_stats.lotes_generados, 0)   AS lotes_generados,
    CASE
        WHEN op.fyh_inicio IS NOT NULL AND op.fyh_fin IS NOT NULL
            THEN EXTRACT(EPOCH FROM (op.fyh_fin - op.fyh_inicio)) / 3600
        WHEN op.fyh_inicio IS NOT NULL
            THEN EXTRACT(EPOCH FROM (NOW() - op.fyh_inicio)) / 3600
        ELSE NULL
    END AS duracion_horas,
    op.usr_cre,
    prof.first_name || ' ' || prof.last_name AS creado_por
FROM mes.orden_produccion op
JOIN doc.partida p ON p.id = op.partida_id
LEFT JOIN cliente c ON c.id = p.cliente_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido t ON t.id = p.tenido_id
LEFT JOIN profiles prof ON prof.id_usuario = op.usr_cre
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS total_pasos,
        COUNT(*) FILTER (WHERE estado = 'COMPLETADO') AS pasos_completados,
        COUNT(*) FILTER (WHERE estado = 'EN_PROCESO')  AS pasos_en_proceso,
        COUNT(*) FILTER (WHERE estado = 'PENDIENTE')   AS pasos_pendientes
    FROM mes.orden_produccion_paso opp WHERE opp.orden_produccion_id = op.id
) pasos_stats ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_materiales, SUM(l.cantidad) AS cantidad_total_kg
    FROM mes.orden_produccion_item opi
    LEFT JOIN inventario.lote l ON l.id = opi.lote_id
    WHERE opi.orden_produccion_id = op.id
) materiales_stats ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS lotes_generados
    FROM inventario.lote l
    WHERE l.documento_tipo = 'orden_produccion' AND l.documento_id = op.id
) produccion_stats ON true;

GRANT SELECT ON mes.vw_ordenes_produccion TO anon, authenticated;

-- ── doc.vw_compras ────────────────────────────────────────────
DROP VIEW IF EXISTS doc.vw_compras;
CREATE OR REPLACE VIEW doc.vw_compras AS
SELECT
    c.id,
    c.proveedor_id,
    p.proveedor AS proveedor_nombre,
    c.fecha,
    c.factura_proveedor_id,
    fp.serie                  AS factura_serie,
    fp.numero                 AS factura_numero,
    fp.total                  AS factura_total,
    fp.moneda                 AS factura_moneda,
    fp.estado_pago,
    fp.fecha_vencimiento,
    COALESCE(det.total_items, 0)               AS total_items,
    COALESCE(det.monto_total, 0)               AS monto_total,
    COALESCE(guias.total_guias, 0)             AS total_guias,
    COALESCE(letras.total_letras, 0)           AS total_letras,
    COALESCE(letras.monto_letras_pendiente, 0) AS monto_letras_pendiente,
    c.observacion,
    c.usr_cre,
    c.fyh_cre
FROM doc.compra c
JOIN proveedor p ON p.id = c.proveedor_id
LEFT JOIN doc.factura_proveedor fp ON fp.id = c.factura_proveedor_id
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_items, SUM(cd.cantidad * cd.precio_unitario) AS monto_total
    FROM doc.compra_detalle cd WHERE cd.compra_id = c.id
) det ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_guias
    FROM doc.compra_guia_remision cgr WHERE cgr.compra_id = c.id
) guias ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_letras,
           SUM(l.monto) FILTER (WHERE l.estado = 'pendiente') AS monto_letras_pendiente
    FROM doc.letra l WHERE l.factura_proveedor_id = c.factura_proveedor_id
) letras ON true;

GRANT SELECT ON doc.vw_compras TO authenticated;

-- ── inventario.vw_item_proveedor_guia ─────────────────────────
CREATE OR REPLACE VIEW inventario.vw_item_proveedor_guia AS
SELECT DISTINCT
    i.id AS item_id,
    i.codigo AS item_codigo,
    i.nombre AS item_nombre,
    gr.emisor_proveedor_id AS proveedor_id,
    p.proveedor AS proveedor_nombre
FROM doc.guia_remision gr
JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
JOIN item i ON i.id = grd.item_id
JOIN proveedor p ON p.id = gr.emisor_proveedor_id
WHERE gr.emisor_proveedor_id IS NOT NULL;

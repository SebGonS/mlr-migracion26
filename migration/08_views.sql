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
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock;
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
    c.nombre AS propietario
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
LEFT JOIN tercero c ON c.id = l.propietario_id
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
    p.tercero_id,
    c.nombre AS cliente,
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
    p.fecha_acordada,
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
LEFT JOIN tercero c ON c.id = p.tercero_id
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
    c.id AS tercero_id,
    c.nombre AS cliente,
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
    prof.nombre || ' ' || prof.apellido AS creado_por
FROM mes.orden_produccion op
JOIN doc.partida p ON p.id = op.partida_id
LEFT JOIN tercero c ON c.id = p.tercero_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido t ON t.id = p.tenido_id
LEFT JOIN usuario prof ON prof.id = op.usr_cre
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
CREATE OR REPLACE VIEW doc.vw_compras AS
SELECT
    c.id,
    c.tercero_id,
    p.nombre AS proveedor_nombre,
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
JOIN tercero p ON p.id = c.tercero_id
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
           SUM(l.monto) FILTER (WHERE l.estado = 'emitida') AS monto_letras_pendiente
    FROM doc.letra l WHERE l.factura_proveedor_id = c.factura_proveedor_id
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
SELECT
    l.id AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.item_id,
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
    art.nombre AS articulo,  -- FIX: art.articulo → art.nombre
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
FROM inventario.lote l
LEFT JOIN inventario.vw_stock_actual sa ON l.id = sa.lote_id
JOIN item i ON i.id = l.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id
JOIN item_rollo_detalle ird ON ird.item_id = i.id
JOIN articulo art ON art.id = ird.articulo_id
JOIN unidad un ON un.id = i.unidad_id
LEFT JOIN inventario.ubicacion u ON u.id = sa.ubicacion_id
LEFT JOIN inventario.almacen a ON a.id = u.almacen_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = (l.detalles->>'color_x_cliente_id')::smallint
LEFT JOIN cliente c ON c.id = l.propietario_id
WHERE it.codigo = 'ROLLO' AND sa.cantidad_disponible IS NULL
AND EXISTS (
    SELECT 1 FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.lote_id = l.id
      AND imt.codigo IN ('SERV_EGR')
)
ORDER BY a.nombre, u.nombre, i.nombre;

-- ── doc.partida_resumen_tenido ────────────────────────────────
CREATE OR REPLACE VIEW doc.partida_resumen_tenido AS
SELECT
    pd.partida_id,
    a.id AS articulo_id,
    a.nombre AS articulo_nombre,
    a.fibra,
    COUNT(pd.item_id) AS total_rollos,
    SUM(pd.cantidad) AS cantidad_total,
    SUM(CASE WHEN ird.flg_rib = false THEN pd.cantidad ELSE 0 END) AS cantidad_regular,
    SUM(CASE WHEN ird.flg_rib = true  THEN pd.cantidad ELSE 0 END) AS cantidad_rib
FROM doc.partida_detalle pd
JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
JOIN articulo a ON ird.articulo_id = a.id
GROUP BY 1, 2, 3, 4
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
JOIN mes.orden_produccion_paso opp ON opp.id = l.documento_id
JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
JOIN doc.partida p ON op.partida_id = p.id
WHERE l.documento_tipo = 'ORDEN_PRODUCCION_PASO'
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
CREATE OR REPLACE VIEW inventario.vw_stock_rollos AS
WITH rollos AS (
    SELECT
        sa.item_id,
        i.codigo AS item_codigo,
        i.nombre AS item_nombre,
        op.partida_id,
        COUNT(sa.lote_id) AS cantidad_rollos,
        SUM(sa.cantidad_disponible) AS cantidad_total,
        u.codigo AS unidad_codigo,
        l.propietario_id,
        l.estado_calidad
    FROM inventario.vw_stock_actual sa
    JOIN inventario.lote l ON l.id = sa.lote_id
    LEFT JOIN mes.orden_produccion_paso opp
        ON documento_tipo = 'ORDEN_PRODUCCION_PASO' AND opp.id = l.documento_id
    LEFT JOIN mes.orden_produccion op ON opp.orden_produccion_id = op.id
    JOIN item i ON i.id = sa.item_id
    JOIN item_tipo it ON it.id = i.item_tipo_id
    JOIN unidad u ON i.unidad_id = u.id
    WHERE it.codigo = 'ROLLO'
    GROUP BY sa.item_id, i.codigo, i.nombre, op.partida_id, u.codigo, l.propietario_id, l.estado_calidad
)
SELECT
    r.item_id,
    r.item_codigo,
    r.item_nombre,
    r.partida_id,
    r.cantidad_rollos,
    r.cantidad_total,
    r.unidad_codigo,
    r.estado_calidad,
    ird.articulo_id,
    art.nombre AS articulo,  -- FIX: art.articulo → art.nombre
    ird.flg_tenido,
    ird.flg_rib,
    art.fibra,
    p.tenido_id,
    t.tenido,
    p.ancho,
    p.malla,
    p.rendimiento,
    p.flg_antipilling,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.cliente_id,
    vc.color_hex,
    vc.color_x_cliente_hex,
    c.id AS propietario_id,
    c.cliente AS propietario
FROM rollos r
JOIN item_rollo_detalle ird ON ird.item_id = r.item_id
JOIN articulo art ON art.id = ird.articulo_id
LEFT JOIN doc.partida p ON p.id = r.partida_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN cliente c ON c.id = r.propietario_id
LEFT JOIN tenido t ON t.id = p.tenido_id
ORDER BY art.nombre, r.item_nombre;  -- FIX: art.articulo → art.nombre

-- ── inventario.vw_stock_insumos ───────────────────────────────
CREATE OR REPLACE VIEW inventario.vw_stock_insumos AS
WITH insumos AS (
    SELECT
        sa.item_id,
        vi.item_codigo,
        vi.item_nombre,
        SUM(sa.cantidad_disponible) AS cantidad_total,
        vi.unidad_codigo
    FROM inventario.vw_stock_actual sa
    JOIN vw_items vi ON vi.item_id = sa.item_id
    WHERE vi.item_tipo_codigo = 'INSUMO'
    GROUP BY sa.item_id, vi.item_codigo, vi.item_nombre, vi.unidad_codigo
)
SELECT
    i.item_id,
    i.item_codigo,
    i.item_nombre,
    i.cantidad_total,
    i.unidad_codigo,
    iid.insumo_tipo_id,
    it.codigo AS insumo_tipo_codigo,
    it.nombre AS insumo_tipo_nombre,
    iid.colorante_tipo_id,
    ct.codigo AS colorante_tipo_codigo,
    ct.nombre AS colorante_tipo_nombre
FROM insumos i
LEFT JOIN item_insumo_detalle iid ON iid.item_id = i.item_id
LEFT JOIN insumo_tipo it ON it.id = iid.insumo_tipo_id
LEFT JOIN colorante_tipo ct ON ct.id = iid.colorante_tipo_id;

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
DROP VIEW IF EXISTS calidad.vw_lotes_pendientes_inspeccion;
CREATE OR REPLACE VIEW calidad.vw_lotes_pendientes_inspeccion AS
SELECT
    l.id AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre) || '-' || l.secuencia AS lote_codigo,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    l.documento_tipo,
    l.documento_id,
    opp.id AS orden_produccion_paso_id,
    m.id AS maquina_id,
    m.codigo AS maquina_codigo,
    o.id AS operacion_id,
    o.codigo AS operacion_codigo,
    p.id AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || p.numero AS partida_codigo,
    p.ancho,
    p.rendimiento,
    p.malla,
    p.flg_antipilling,
    p.prioridad_id,
    pr.prioridad,
    l.propietario_id,
    c.cliente AS cliente_nombre,
    l.fyh_cre AS fecha_creacion_lote
FROM inventario.lote l
LEFT JOIN vw_items vi ON vi.item_id = l.item_id
LEFT JOIN mes.orden_produccion_paso opp
    ON opp.id = l.documento_id AND l.documento_tipo = 'ORDEN_PRODUCCION_PASO'
LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
LEFT JOIN mes.maquina m ON m.id = opp.maquina_asignada_id
LEFT JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
LEFT JOIN doc.partida p ON p.id = op.partida_id
LEFT JOIN cliente c ON l.propietario_id = c.id
LEFT JOIN prioridad pr ON pr.id = p.prioridad_id
WHERE l.estado_calidad = 'PENDIENTE'
  AND vi.item_tipo_codigo = 'ROLLO'
  AND l.documento_tipo = 'ORDEN_PRODUCCION_PASO';

-- ── calidad.vw_inspecciones ───────────────────────────────────
CREATE OR REPLACE VIEW calidad.vw_inspecciones AS
SELECT
    i.id AS inspeccion_id,
    i.lote_id,
    l.item_id,
    vi.item_codigo,
    vi.item_nombre,
    i.orden_produccion_paso_id,
    i.resultado,
    i.observacion,
    i.empleado_id,
    e.nombre AS empleado_nombre,
    i.fyh_inspeccion
FROM calidad.inspeccion i
LEFT JOIN inventario.lote l ON l.id = i.lote_id
LEFT JOIN vw_items vi ON vi.item_id = l.item_id
LEFT JOIN mes.empleado e ON e.id = i.empleado_id;

-- ── mes.vw_pasos ──────────────────────────────────────────────
CREATE OR REPLACE VIEW mes.vw_pasos AS
SELECT
    opp.id AS paso_id,
    opp.secuencia,
    opp.orden_produccion_id,
    op.partida_id,
    p.numero AS partida_numero,
    EXTRACT(YEAR FROM p.fyh_cre) || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    opp.operacion_id,
    o.codigo AS operacion_codigo,
    o.nombre AS operacion_nombre,
    o.requiere_receta,
    o.requiere_maquina,
    opp.maquina_asignada_id,
    opp.receta_id,
    m.codigo AS maquina_codigo,
    m.nombre AS maquina_nombre,
    opp.estado,
    opp.fyh_inicio,
    opp.fyh_fin,
    opp.flg_genera_produccion
FROM mes.orden_produccion_paso opp
JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
JOIN doc.partida p ON p.id = op.partida_id
JOIN mes.operacion o ON o.id = opp.operacion_id
LEFT JOIN mes.maquina m ON m.id = opp.maquina_asignada_id;

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

-- ── Grants ────────────────────────────────────────────────────
GRANT SELECT ON inventario.vw_stock_rollos        TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_general       TO anon, authenticated;
GRANT SELECT ON inventario.vw_stock_insumos       TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_disponibles   TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_despachados TO anon, authenticated;
GRANT SELECT ON inventario.vw_items_movimientos   TO anon, authenticated;
GRANT SELECT ON mes.vw_maquinas                   TO authenticated;
GRANT SELECT ON mes.vw_pasos                      TO anon, authenticated;
GRANT SELECT ON mes.vw_partida_produccion_rollos  TO anon, authenticated;
GRANT SELECT ON calidad.vw_lotes_pendientes_inspeccion TO authenticated;
GRANT SELECT ON calidad.vw_inspecciones           TO authenticated;
GRANT SELECT ON doc.partida_resumen_tenido        TO authenticated;

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

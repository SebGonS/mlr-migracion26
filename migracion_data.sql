-- MLR Database Migration Script
-- Migrates data from existing tables to new PostgreSQL schema
-- Execute after tablas.sql and funciones.sql are loaded

BEGIN;


-- ============================================================================
-- 1. MASTER DATA MIGRATION - Public Schema
-- ===========================================================================
-- CREAR ROLLOS CRUDOS
SELECT  UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C') codigo,
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'UN'
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1');

WITH base AS (
   SELECT  UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C') codigo,
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'UN'
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1')
),
ins_item AS (
    INSERT INTO item (
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre
    )
    SELECT
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW()
    FROM base b
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fibra,
    flg_tenido,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    false,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

-----MIGRAR ROLLOS RIB CRUDOS

WITH base AS (
   SELECT  UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C') codigo,
'Rollo Rib' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'UN'
WHERE rib>0
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1')
),
ins_item AS (
    INSERT INTO item (
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre
    )
    SELECT
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW()
    FROM base b
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fibra,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);





-- ============================================================================
-- 2. INVENTORY MIGRATION - Inventario Schema
-- ============================================================================

-- Migrate warehouses (almacen)
INSERT INTO inventario.almacen (codigo, descripcion, ubicacion, usr_cre, fyh_cre)
SELECT 
    alm.codigo,
    alm.descripcion,
    COALESCE(alm.ubicacion, 'No especificada'),
    'migration_admin',
    NOW()
FROM source_almacen alm
WHERE alm.codigo IS NOT NULL
ON CONFLICT (codigo_canon) DO NOTHING;

-- Migrate warehouse locations (ubicacion)
INSERT INTO inventario.ubicacion (id_almacen, codigo, descripcion, capacidad, usr_cre, fyh_cre)
SELECT 
    a.id,
    ub.codigo,
    COALESCE(ub.descripcion, 'Sin descripción'),
    COALESCE(ub.capacidad, 0),
    'migration_admin',
    NOW()
FROM source_ubicacion ub
LEFT JOIN inventario.almacen a ON LOWER(UNACCENT(ub.almacen_codigo)) = a.codigo_canon
WHERE ub.codigo IS NOT NULL
ON CONFLICT (codigo_canon) DO NOTHING;

-- Migrate item movement types (item_movimiento_tipo)
INSERT INTO inventario.item_movimiento_tipo (codigo, descripcion, tipo_movimiento, usr_cre, fyh_cre)
SELECT DISTINCT 
    LOWER(imt.codigo),
    imt.descripcion,
    COALESCE(imt.tipo, 'ENTRADA'),
    'migration_admin',
    NOW()
FROM source_item_movimiento_tipo imt
WHERE imt.codigo IS NOT NULL
ON CONFLICT (codigo_canon) DO NOTHING;

-- ============================================================================
-- 3. DOCUMENT MIGRATION - Doc Schema
-- ============================================================================

-- Migrate production orders (partida)
INSERT INTO doc.partida (codigo, descripcion, id_cliente, fecha_orden, estado, usr_cre, fyh_cre)
SELECT 
    p.codigo,
    COALESCE(p.descripcion, ''),
    COALESCE(c.id, 1), -- Default cliente if not found
    COALESCE(p.fecha_orden, NOW()),
    COALESCE(p.estado, 'creado'),
    'migration_admin',
    NOW()
FROM source_partida p
LEFT JOIN source_cliente c ON p.id_cliente = c.id
WHERE p.codigo IS NOT NULL
ON CONFLICT (codigo_canon) DO NOTHING;

-- Migrate production order details (partida_detalle)
INSERT INTO doc.partida_detalle (id_partida, id_item, cantidad, observaciones, usr_cre, fyh_cre)
SELECT 
    par.id,
    i.id,
    COALESCE(pd.cantidad, 0),
    COALESCE(pd.observaciones, ''),
    'migration_admin',
    NOW()
FROM source_partida_detalle pd
LEFT JOIN doc.partida par ON LOWER(UNACCENT(pd.codigo_partida)) = par.codigo_canon
LEFT JOIN public.item i ON LOWER(UNACCENT(pd.codigo_item)) = i.codigo_canon
WHERE pd.codigo_partida IS NOT NULL AND pd.codigo_item IS NOT NULL
ON CONFLICT (id_partida, id_item) DO NOTHING;

-- Migrate shipment guides (guia_remision)
INSERT INTO doc.guia_remision (codigo, id_partida, tipo_movimiento, fecha_movimiento, estado, usr_cre, fyh_cre)
SELECT 
    gr.codigo,
    COALESCE(par.id, 1), -- Default if not found
    COALESCE(gr.tipo_movimiento, 'compra_ingreso'),
    COALESCE(gr.fecha_movimiento, NOW()),
    COALESCE(gr.estado, 'pendiente'),
    'migration_admin',
    NOW()
FROM source_guia_remision gr
LEFT JOIN doc.partida par ON LOWER(UNACCENT(gr.codigo_partida)) = par.codigo_canon
WHERE gr.codigo IS NOT NULL
ON CONFLICT (codigo_canon) DO NOTHING;

-- Migrate shipment guide details (guia_remision_detalle)
INSERT INTO doc.guia_remision_detalle (id_guia_remision, id_item, id_ubicacion, lote, cantidad, usr_cre, fyh_cre)
SELECT 
    gr.id,
    i.id,
    COALESCE(u.id, 1), -- Default location if not found
    COALESCE(grd.lote, 'SIN_LOTE'),
    COALESCE(grd.cantidad, 0),
    'migration_admin',
    NOW()
FROM source_guia_remision_detalle grd
LEFT JOIN doc.guia_remision gr ON LOWER(UNACCENT(grd.codigo_guia)) = gr.codigo_canon
LEFT JOIN public.item i ON LOWER(UNACCENT(grd.codigo_item)) = i.codigo_canon
LEFT JOIN inventario.ubicacion u ON LOWER(UNACCENT(grd.ubicacion)) = u.codigo_canon
WHERE grd.codigo_guia IS NOT NULL AND grd.codigo_item IS NOT NULL
ON CONFLICT (id_guia_remision, id_item) DO NOTHING;

-- ============================================================================
-- 4. MANUFACTURING EXECUTION MIGRATION - MES Schema
-- ============================================================================

-- Migrate production templates (if applicable to your MES)
-- INSERT INTO mes.plantilla_produccion ...

-- ============================================================================
-- 5. VERIFICATION & CLEANUP
-- ============================================================================

-- Verify migration counts
SELECT 'Items migrated' as entity, COUNT(*) as total FROM public.item
UNION ALL
SELECT 'Production orders', COUNT(*) FROM doc.partida
UNION ALL
SELECT 'Warehouses', COUNT(*) FROM inventario.almacen
UNION ALL
SELECT 'Shipment guides', COUNT(*) FROM doc.guia_remision;

-- Check for NULL foreign keys (potential issues)
SELECT 'Partida with NULL cliente' as issue, COUNT(*) as count 
FROM doc.partida WHERE id_cliente IS NULL
UNION ALL
SELECT 'Partida_detalle with NULL item', COUNT(*) FROM doc.partida_detalle WHERE id_item IS NULL
UNION ALL
SELECT 'Guia_remision_detalle with NULL ubicacion', COUNT(*) FROM doc.guia_remision_detalle WHERE id_ubicacion IS NULL;

COMMIT;
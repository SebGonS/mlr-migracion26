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
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
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
UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
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
    flg_rib,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

--------------------INSERTAR ITEM ROLLO teñido
WITH base AS (
   SELECT  UPPER('R-' || a.articulo||'-'|| COALESCE(fibra, '1')||'-T') codigo,
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'UN'
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-T'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido',
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
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);
---- RIB TEÑIDO

WITH base AS (
   SELECT  UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-T') codigo,
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido' nombre,
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
UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-T'),
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido',
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
    flg_rib,
    flg_tenido,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    true,
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

-- ============================================================================
-- MIGRAR INSUMOS
-- ============================================================================
SELECT 'I-' ||
CASE tipo WHEN 'directo' THEN 'COL' WHEN 'reactivo' THEN 'COL' WHEN 'disperso' THEN 'COL' WHEN 'auxiliar' THEN 'AUX' WHEN 'quimico' THEN 'QUIM' END || '-' ||
CASE tipo WHEN 'directo' THEN 'DIR-' WHEN 'reactivo' THEN 'RX-' WHEN 'disperso' THEN 'DIS-' ELSE '' END ||
UPPER(trim(both '-' from regexp_replace(regexp_replace(i.insumo COLLATE "C", '\s+', ' ', 'g'), '[^A-Z0-9]+', '-', 'g'))) codigo,
i.insumo nombre,
u.id unidad_id,
i.medida,
it.id item_tipo_id,
it2.id insumo_tipo_id,
ct.id colorante_tipo_id,
insumo_id
FROM insumo i
LEFT JOIN item_tipo it ON it.codigo = 'INSUMO'
LEFT JOIN unidad u ON u.codigo = 'kg'
LEFT JOIN insumo_tipo it2 ON it2.nombre = CASE tipo WHEN 'directo' THEN 'colorante' WHEN 'reactivo' THEN 'colorante' WHEN 'disperso' THEN 'colorante' ELSE i.tipo::text END ---case when diperso,reactivo or directo then colorante
LEFT JOIN colorante_tipo ct ON ct.nombre=i.tipo::text;

with base AS(
    SELECT 'I-' ||
CASE tipo WHEN 'directo' THEN 'COL' WHEN 'reactivo' THEN 'COL' WHEN 'disperso' THEN 'COL' WHEN 'auxiliar' THEN 'AUX' WHEN 'quimico' THEN 'QUIM' END || '-' ||
CASE tipo WHEN 'directo' THEN 'DIR-' WHEN 'reactivo' THEN 'RX-' WHEN 'disperso' THEN 'DIS-' ELSE '' END ||
UPPER(trim(both '-' from regexp_replace(regexp_replace(i.insumo COLLATE "C", '\s+', ' ', 'g'), '[^A-Z0-9]+', '-', 'g'))) codigo,
i.insumo nombre,
u.id unidad_id,
i.medida,
it.id item_tipo_id,
it2.id insumo_tipo_id,
ct.id colorante_tipo_id,
i.id
FROM insumo i
LEFT JOIN item_tipo it ON it.codigo = 'INSUMO'
LEFT JOIN unidad u ON u.codigo = 'kg'
LEFT JOIN insumo_tipo it2 ON it2.nombre = CASE tipo WHEN 'directo' THEN 'colorante' WHEN 'reactivo' THEN 'colorante' WHEN 'disperso' THEN 'colorante' ELSE i.tipo::text END ---case when diperso,reactivo or directo then colorante
LEFT JOIN colorante_tipo ct ON ct.nombre=i.tipo::text
),
ins as(
    INSERT INTO item (
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre,
        legacy_id
    )
    SELECT
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW(),
        id
    FROM base b
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_insumo_detalle(
    item_id,
    medida,
    insumo_tipo_id,
    colorante_tipo_id,
    fyh_cre
)
SELECT
    i.id,
    b.medida,
    b.insumo_tipo_id,
    b.colorante_tipo_id,
    NOW()
FROM ins i
JOIN base b USING (codigo);


-- ============================================================================
-- CREAR ALMACENES
-- ============================================================================

INSERT INTO inventario.almacen(codigo,nombre,fyh_cre)
VALUES ('ALM-INS', 'Almacén de Insumos', NOW()),
       ('ALM-CRU', 'Almacén de Crudo', NOW());

INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,fyh_cre)
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM-INS'
UNION ALL
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM-CRU';

-- ============================================================================
-- MIGRAR PARTIDAS
-- ============================================================================
--Mapear Estados existentes
-- SELECT '''' || estado || '''' AS estado FROM estado
UPDATE partida
SET fyh_cre_tz=fyh_cre + INTERVAL '5 hours'
WHERE fyh_cre_tz='2025-09-11 22:53:28.212517+00';
UPDATE estado
SET estado_produccion = CASE estado
    WHEN 'Para Programar' THEN 'CREADA'::orden_produccion_estado_enum
    WHEN 'Programado' THEN 'PROGRAMADA'::orden_produccion_estado_enum
    WHEN 'En Proceso Teñido' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Teñido' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Lavado Hidro' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Secado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Para Despachar' THEN 'TECO'::orden_produccion_estado_enum
    WHEN 'Despachado' THEN 'CERRADA'::orden_produccion_estado_enum
    WHEN 'Devolución' THEN 'CERRADA'::orden_produccion_estado_enum
    WHEN 'Observado' THEN 'TECO'::orden_produccion_estado_enum
    WHEN 'Reprocesado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'En Proceso Reproceso' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Planchado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Replanchado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Termofijado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Perchado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
END,
estado_comercial = CASE estado
 WHEN 'Para Programar' THEN 'CREADA'::partida_estado_enum
    WHEN 'Programado' THEN 'CONFIRMADA'::partida_estado_enum
    WHEN 'En Proceso Teñido' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Teñido' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Lavado Hidro' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Secado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Para Despachar' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Despachado' THEN 'ENTREGADA'::partida_estado_enum
    WHEN 'Devolución' THEN 'DEVUELTA_PARCIAL'::partida_estado_enum
    WHEN 'Observado' THEN 'ENTREGADA'::partida_estado_enum
    WHEN 'Reprocesado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'En Proceso Reproceso' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Planchado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Replanchado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Termofijado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Perchado' THEN 'EN_PRODUCCION'::partida_estado_enum END

-- SELECT * FROM partida LIMIT 100
-- SELECT * FROM partida_estado_historial

SELECT ROW_NUMBER() OVER (PARTITION BY peh.partida_id ORDER BY peh.id desc) rw,peh.*,e.estado FROM partida_estado_historial peh
LEFT JOIN estado e ON e.id=peh.estado_id
ORDER BY partida_id

WITH ult_estado as(SELECT ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY id desc) rw,* FROM partida_estado_historial)
,base as(SELECT 
pp.id,
pp.codigo,pp.prioridad_id,pp.cliente_id,
pp.tenido_id,pp.previo_id,
pp.articulo_id, pp.malla,pp.rendimiento,
pp.rib
e.estado,
e.estado_comercial,
e.estado_produccion,
pp.fecha_registro,
pp.fecha_entrega,
pp.usr_cre,
pp.fyh_cre_tz
FROM public.partida pp
LEFT JOIN ult_estado ue ON pp.id = ue.partida_id AND rw=1
LEFT JOIN estado e ON ue.estado_id = e.id)
,ins_partida as(
   INSERT INTO doc.partida (
    id,
    numero,
    prioridad_id,
    cliente_id,
    tenido_id,
    previo_id,
    articulo_id,
    fibra,
    malla,
    rendimiento,
    estado,
    fyh_programacion,
    fyh_inicio,
    fyh_fin,
    usr_cre,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    p.id,          -- same id as old partida
    p.codigo,
    p.prioridad_id,
    p.cliente_id,
    p.tenido_id,
    p.previo_id,
    p.articulo_id,
    p.fibra,
    p.malla,
    p.rendimiento,
    p.estado_comercial,
    p.fecha_registro,
    p.fecha_registro,
    p.fecha_entrega,
    p.usr_cre,
    p.fyh_cre_tz
FROM base p
RETURNING id
),
ins_partida_detalle AS (
    INSERT INTO doc.partida_detalle (
        id_partida,
        id_item,
        cantidad,
        usr_cre,
        fyh_cre
    )
    SELECT
        ins_partida.id,
        i.id,
        COALESCE(pd.cantidad, 0),
        COALESCE(pd.observaciones, ''),
        'migration_admin',
        NOW()
    FROM base p
    LEFT JOIN item_rollo_detalle ird ON ird.articulo_id=p.articulo_id AND flg_tenido=false AND (!flg_rib OR (flg_rib AND p.rib>0))
    WHERE pd.codigo_partida IS NOT NULL AND pd.codigo_item IS NOT NULL
    ON CONFLICT (id_partida, id_item) DO NOTHING
)

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
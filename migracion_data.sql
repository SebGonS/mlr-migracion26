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
UPDATE estado
SET estado_produccion = CASE estado
    WHEN 'Para Programar' THEN 'CREADA'
    WHEN 'Programado' THEN 'PROGRAMADO'
    WHEN 'En Proceso Teñido' THEN 'EN_PROCESO'
    WHEN 'Teñido' THEN 'EN_PROCESO'
    WHEN 'Lavado Hidro' THEN 'EN_PROCESO'
    WHEN 'Secado' THEN 'EN_PROCESO'
    WHEN 'Para Despachar' THEN 'TECO'
    WHEN 'Despachado' THEN 'CERRADA'
    WHEN 'Devolución' THEN 'DEVOLUCION'
    WHEN 'Observado' THEN 'OBSERVADO'
    WHEN 'Reprocesado' THEN 'REPROCESADO'
    WHEN 'En Proceso Reproceso' THEN 'EN_PROCESO_REPROCESO'
    WHEN 'Planchado' THEN 'PLANCHADO'
    WHEN 'Replanchado' THEN 'REPLANCHADO'
    WHEN 'Termofijado' THEN 'TERMOFIJADO'
    WHEN 'Perchado' THEN ''
END,
estado_comercial = CASE estado
    WHEN '' THEN ''
END
'Secado'
'Para Despachar'
'Despachado'
'Devolución'
'Observado'
'Reprocesado'
'En Proceso Reproceso'
'Planchado'
'Replanchado'
'Termofijado'
'Perchado'
SELECT * FROM partida LIMIT 100
SELECT * FROM partida_estado_historial

SELECT ROW_NUMBER() OVER (PARTITION BY peh.partida_id ORDER BY peh.id desc) rw,peh.*,e.estado FROM partida_estado_historial peh
LEFT JOIN estado e ON e.id=peh.estado_id
ORDER BY partida_id

WITH estado as(SELECT ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY id desc) rw,* FROM partida_estado_historial)


SELECT codigo,prioridad_id,cliente_id,tenido_id,previo_id,articulo_id, malla,rendimiento FROM public.partida pp

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
-- =============================================================================
-- Step 21: IAM sync — brings live DB in line with the migration plan.
-- Safe to run on the existing DB; all statements are idempotent.
-- Run AFTER migration/10_auth.sql and migration/11_permissions_patch.sql.
-- =============================================================================


-- =============================================================================
-- SECTION 1: Missing permissions
-- Live DB was set up before the configuracion.operacional split was designed.
-- =============================================================================

INSERT INTO iam.permiso (code, descripcion)
VALUES ('configuracion.operacional', 'Gestionar máquinas, tipos de máquina, operaciones, roles de empleado y almacenes')
ON CONFLICT (code) DO NOTHING;


-- =============================================================================
-- SECTION 2: Missing role
-- =============================================================================

INSERT INTO iam.rol (code, nombre, descripcion)
SELECT v.code, v.nombre, v.descripcion
FROM (VALUES
    ('tecnico_planta', 'Técnico de Planta', 'Gestión de stock y edición de recetas y rutas de producción')
) AS v(code, nombre, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM iam.rol r WHERE r.code = v.code);


-- =============================================================================
-- SECTION 3: Missing rol_permiso assignments
-- Covers gaps between live DB state and the full plan in 10_auth.sql +
-- 11_permissions_patch.sql. All ON CONFLICT DO NOTHING — safe to re-run.
-- =============================================================================

INSERT INTO iam.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM (VALUES
    -- admin: add configuracion.operacional
    ('admin',                  'configuracion.operacional'),
    -- jefe_planta: add configuracion.operacional, catalogos.editar
    ('jefe_planta',            'configuracion.operacional'),
    ('jefe_planta',            'catalogos.editar'),
    -- supervisor_produccion: add produccion.administrar
    -- (supervisors close orders on the floor)
    ('supervisor_produccion',  'produccion.administrar'),
    -- compras: add produccion.ver (visibility into consumption reports)
    ('compras',                'produccion.ver'),
    -- tecnico_planta: full role
    ('tecnico_planta',         'inventario.ver'),
    ('tecnico_planta',         'inventario.crear'),
    ('tecnico_planta',         'inventario.editar'),
    ('tecnico_planta',         'catalogos.editar'),
    ('tecnico_planta',         'produccion.ver'),
    ('tecnico_planta',         'produccion.editar'),
    ('tecnico_planta',         'produccion.configurar'),
    ('tecnico_planta',         'comercial.ver')
) AS mapping(rol_code, permiso_code)
JOIN iam.rol     r ON r.code = mapping.rol_code
JOIN iam.permiso p ON p.code = mapping.permiso_code
ON CONFLICT (rol_id, permiso_id) DO NOTHING;


-- =============================================================================
-- SECTION 4: inventario.cuadre / cuadre_detalle — RLS
-- These tables were created with GRANT SELECT only (no RLS).
-- Align them with all other inventory tables: gate on inventario.ver.
-- Writes go through SECURITY DEFINER functions (no write policies needed).
-- =============================================================================

ALTER TABLE inventario.cuadre         ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.cuadre_detalle ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "inventario_ver" ON inventario.cuadre;
DROP POLICY IF EXISTS "inventario_ver" ON inventario.cuadre_detalle;

CREATE POLICY "inventario_ver" ON inventario.cuadre
    FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON inventario.cuadre_detalle
    FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));


-- =============================================================================
-- SECTION 5: RLS policy corrections (from 11_permissions_patch.sql)
-- Re-apply in case 11_permissions_patch.sql was not previously run.
-- =============================================================================

-- calidad.tipo_defecto: write guard → calidad.editar (not catalogos.editar)
DROP POLICY IF EXISTS "catalogos_insert" ON calidad.tipo_defecto;
DROP POLICY IF EXISTS "catalogos_update" ON calidad.tipo_defecto;
CREATE POLICY "catalogos_insert" ON calidad.tipo_defecto
    FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('calidad.editar'));
CREATE POLICY "catalogos_update" ON calidad.tipo_defecto
    FOR UPDATE TO authenticated USING     (jwt_has_permission('calidad.editar'));

-- mes.maquina write: → configuracion.operacional
DROP POLICY IF EXISTS "produccion_configurar_insert" ON mes.maquina;
DROP POLICY IF EXISTS "produccion_configurar_update" ON mes.maquina;
DROP POLICY IF EXISTS "operacional_insert"           ON mes.maquina;
DROP POLICY IF EXISTS "operacional_update"           ON mes.maquina;
CREATE POLICY "operacional_insert" ON mes.maquina
    FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "operacional_update" ON mes.maquina
    FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

-- mes.operacion / receta.operacion / mes.maquina_tipo / mes.empleado_rol: → configuracion.operacional
DROP POLICY IF EXISTS "catalogos_insert" ON mes.operacion;
DROP POLICY IF EXISTS "catalogos_update" ON mes.operacion;
CREATE POLICY "catalogos_insert" ON mes.operacion
    FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.operacion
    FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

DROP POLICY IF EXISTS "catalogos_insert" ON receta.operacion;
DROP POLICY IF EXISTS "catalogos_update" ON receta.operacion;
CREATE POLICY "catalogos_insert" ON receta.operacion
    FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON receta.operacion
    FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

DROP POLICY IF EXISTS "catalogos_insert" ON mes.maquina_tipo;
DROP POLICY IF EXISTS "catalogos_update" ON mes.maquina_tipo;
CREATE POLICY "catalogos_insert" ON mes.maquina_tipo
    FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.maquina_tipo
    FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

DROP POLICY IF EXISTS "catalogos_insert" ON mes.empleado_rol;
DROP POLICY IF EXISTS "catalogos_update" ON mes.empleado_rol;
CREATE POLICY "catalogos_insert" ON mes.empleado_rol
    FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.empleado_rol
    FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

-- mes.partida / mes.partida_detalle: produccion.ver as second SELECT policy
DROP POLICY IF EXISTS "produccion_ver" ON mes.partida;
DROP POLICY IF EXISTS "produccion_ver" ON mes.partida_detalle;
CREATE POLICY "produccion_ver" ON mes.partida
    FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.partida_detalle
    FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));

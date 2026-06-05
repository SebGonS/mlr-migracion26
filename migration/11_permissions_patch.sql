-- =============================================================================
-- Step 11: Permission layer patch
-- Run this on the already-deployed database (migration/10_auth.sql already ran).
-- All statements are idempotent.
-- =============================================================================


-- =============================================================================
-- SECTION 1: New permission — configuracion.operacional
-- =============================================================================

INSERT INTO iam.permiso (code, descripcion)
VALUES ('configuracion.operacional', 'Gestionar máquinas, tipos de máquina, operaciones, roles de empleado y almacenes')
ON CONFLICT (code) DO NOTHING;

-- Grant to admin
INSERT INTO iam.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM iam.rol r, iam.permiso p
WHERE r.code = 'admin' AND p.code = 'configuracion.operacional'
ON CONFLICT (rol_id, permiso_id) DO NOTHING;


-- =============================================================================
-- SECTION 2: RLS policy changes
-- All blocks use DROP POLICY IF EXISTS + CREATE POLICY for idempotency.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 2a. calidad.tipo_defecto: write guard catalogos.editar → calidad.editar
-- Quality owns its own defect type catalog; purchasing/inventory should not.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "catalogos_insert" ON calidad.tipo_defecto;
DROP POLICY IF EXISTS "catalogos_update" ON calidad.tipo_defecto;
CREATE POLICY "catalogos_insert" ON calidad.tipo_defecto FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('calidad.editar'));
CREATE POLICY "catalogos_update" ON calidad.tipo_defecto FOR UPDATE TO authenticated USING     (jwt_has_permission('calidad.editar'));


-- -----------------------------------------------------------------------------
-- 2b. Operational catalogs: configuracion.admin → configuracion.operacional
-- Plant managers need to add machine types, operation types, etc. without IAM access.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "catalogos_insert" ON mes.operacion;
DROP POLICY IF EXISTS "catalogos_update" ON mes.operacion;
CREATE POLICY "catalogos_insert" ON mes.operacion FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.operacion FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

DROP POLICY IF EXISTS "catalogos_insert" ON receta.operacion;
DROP POLICY IF EXISTS "catalogos_update" ON receta.operacion;
CREATE POLICY "catalogos_insert" ON receta.operacion FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON receta.operacion FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

DROP POLICY IF EXISTS "catalogos_insert" ON mes.maquina_tipo;
DROP POLICY IF EXISTS "catalogos_update" ON mes.maquina_tipo;
CREATE POLICY "catalogos_insert" ON mes.maquina_tipo FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.maquina_tipo FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

DROP POLICY IF EXISTS "catalogos_insert" ON mes.empleado_rol;
DROP POLICY IF EXISTS "catalogos_update" ON mes.empleado_rol;
CREATE POLICY "catalogos_insert" ON mes.empleado_rol FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.empleado_rol FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));


-- -----------------------------------------------------------------------------
-- 2c. mes.maquina write: produccion.configurar → configuracion.operacional
-- Machine instances are physical infrastructure, not recipe knowledge.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "produccion_configurar_insert" ON mes.maquina;
DROP POLICY IF EXISTS "produccion_configurar_update" ON mes.maquina;
DROP POLICY IF EXISTS "operacional_insert"           ON mes.maquina;
DROP POLICY IF EXISTS "operacional_update"           ON mes.maquina;
CREATE POLICY "operacional_insert" ON mes.maquina FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "operacional_update" ON mes.maquina FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));


-- -----------------------------------------------------------------------------
-- 2d. mes.partida / mes.partida_detalle: add produccion.ver as second SELECT policy
-- partida is a bridge entity — production roles need the header without comercial.ver.
-- PERMISSIVE policies combine with OR; comercial.ver policy is unchanged.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "produccion_ver" ON mes.partida;
DROP POLICY IF EXISTS "produccion_ver" ON mes.partida_detalle;
CREATE POLICY "produccion_ver" ON mes.partida         FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.partida_detalle FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));


-- -----------------------------------------------------------------------------
-- 2e. inventario.lote_rollo_detalle: close the open-to-all anomaly
-- All current roles have inventario.ver so there is no functional change,
-- but this closes a future gap and aligns with all other inventory tables.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "ver_lote_rollo" ON inventario.lote_rollo_detalle;
CREATE POLICY "ver_lote_rollo" ON inventario.lote_rollo_detalle FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));


-- -----------------------------------------------------------------------------
-- 2f. receta.* business tables: enable RLS + produccion.ver SELECT gate
-- Recipes were previously unprotected at the table level (exposed only via
-- SECURITY DEFINER functions/views). Direct SELECT is now gated.
-- receta.operacion is intentionally excluded — it is a catalog table (Tier 1,
-- open to all authenticated).
-- -----------------------------------------------------------------------------
ALTER TABLE receta.tenido                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE receta.tenido_paso                ENABLE ROW LEVEL SECURITY;
ALTER TABLE receta.tenido_paso_insumo         ENABLE ROW LEVEL SECURITY;
ALTER TABLE receta.lavado_maquina             ENABLE ROW LEVEL SECURITY;
ALTER TABLE receta.lavado_maquina_paso        ENABLE ROW LEVEL SECURITY;
ALTER TABLE receta.lavado_maquina_paso_insumo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "produccion_ver" ON receta.tenido;
DROP POLICY IF EXISTS "produccion_ver" ON receta.tenido_paso;
DROP POLICY IF EXISTS "produccion_ver" ON receta.tenido_paso_insumo;
DROP POLICY IF EXISTS "produccion_ver" ON receta.lavado_maquina;
DROP POLICY IF EXISTS "produccion_ver" ON receta.lavado_maquina_paso;
DROP POLICY IF EXISTS "produccion_ver" ON receta.lavado_maquina_paso_insumo;

CREATE POLICY "produccion_ver" ON receta.tenido                     FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON receta.tenido_paso                FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON receta.tenido_paso_insumo         FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON receta.lavado_maquina             FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON receta.lavado_maquina_paso        FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON receta.lavado_maquina_paso_insumo FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));


-- =============================================================================
-- SECTION 3: Function guard updates
-- inventario.crear_almacen / modificar_almacen / eliminar_almacen now check
-- configuracion.operacional instead of configuracion.admin.
-- Deploy updated funciones/core.sql to apply this change.
-- =============================================================================

-- No SQL here — these are PL/pgSQL function bodies in funciones/core.sql.
-- Run the updated core.sql file (or the three function bodies individually)
-- against the live DB after applying this patch.


-- =============================================================================
-- SECTION 4: Role layer changes
-- All inserts use ON CONFLICT DO NOTHING — safe to re-run.
-- =============================================================================

-- New role
INSERT INTO iam.rol (code, nombre, descripcion)
SELECT v.code, v.nombre, v.descripcion
FROM (VALUES
    ('tecnico_planta', 'Técnico de Planta', 'Gestión de stock y edición de recetas y rutas de producción')
) AS v(code, nombre, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM iam.rol r WHERE r.code = v.code);

-- Role-permission assignments: fixes to existing roles + new tecnico_planta
INSERT INTO iam.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM (VALUES
    -- jefe_planta: add missing configuracion.operacional and catalogos.editar
    ('jefe_planta', 'configuracion.operacional'),
    ('jefe_planta', 'catalogos.editar'),
    -- supervisor_produccion: add missing produccion.administrar
    -- (supervisors close orders; justified by job function)
    ('supervisor_produccion', 'produccion.administrar'),
    -- compras: add produccion.ver for consumption report visibility
    ('compras', 'produccion.ver'),
    -- tecnico_planta: full role
    ('tecnico_planta', 'inventario.ver'),
    ('tecnico_planta', 'inventario.crear'),
    ('tecnico_planta', 'inventario.editar'),
    ('tecnico_planta', 'catalogos.editar'),
    ('tecnico_planta', 'produccion.ver'),
    ('tecnico_planta', 'produccion.editar'),
    ('tecnico_planta', 'produccion.configurar'),
    ('tecnico_planta', 'comercial.ver')
) AS mapping(rol_code, permiso_code)
JOIN iam.rol     r ON r.code = mapping.rol_code
JOIN iam.permiso p ON p.code = mapping.permiso_code
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

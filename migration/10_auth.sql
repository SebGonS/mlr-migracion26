-- =============================================================================
-- Step 10: Authorization — JWT hook and RLS policies
-- get_user_id() is defined in step 3 (migration/03_base_functions.sql).
-- Re-running is safe (CREATE OR REPLACE / IF NOT EXISTS).
-- =============================================================================


-- =============================================================================
-- SECTION 1: Custom Access Token Hook
-- Fires on every login and token refresh.
-- Injects user_permissions, user_roles, and id_usuario into the JWT.
--
-- After deploying: Supabase Dashboard → Authentication → Hooks
--   → Custom Access Token → schema: public, function: custom_access_token_hook
-- =============================================================================
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, iam
AS $$
DECLARE
  claims        jsonb;
  v_numeric_id  integer;
  v_permissions text[];
  v_role_codes  text[];
BEGIN
  -- Bridge auth UUID → numeric id
  SELECT id INTO v_numeric_id
  FROM public.usuario
  WHERE auth_id = (event->>'user_id')::uuid;

  -- No usuario row = no permissions, id_usuario JWT claim stays NULL.
  IF v_numeric_id IS NULL THEN
    claims := event->'claims';
    claims := jsonb_set(claims, '{user_permissions}', '[]'::jsonb);
    claims := jsonb_set(claims, '{user_roles}',       '[]'::jsonb);
    claims := jsonb_set(claims, '{id_usuario}',       'null'::jsonb);
    RETURN jsonb_set(event, '{claims}', claims);
  END IF;

  -- Collect all permission codes across all roles
  SELECT ARRAY_AGG(DISTINCT p.code) INTO v_permissions
  FROM iam.user_rol ur
  JOIN iam.rol_permiso rp ON rp.rol_id = ur.rol_id
  JOIN iam.permiso p ON p.id = rp.permiso_id
  WHERE ur.user_id = v_numeric_id;

  -- Collect role codes
  SELECT ARRAY_AGG(DISTINCT r.code) INTO v_role_codes
  FROM iam.user_rol ur
  JOIN iam.rol r ON r.id = ur.rol_id
  WHERE ur.user_id = v_numeric_id;

  claims := event->'claims';
  claims := jsonb_set(claims, '{user_permissions}', COALESCE(to_jsonb(v_permissions), '[]'::jsonb));
  claims := jsonb_set(claims, '{user_roles}',       COALESCE(to_jsonb(v_role_codes),  '[]'::jsonb));
  claims := jsonb_set(claims, '{id_usuario}',       to_jsonb(v_numeric_id));

  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM PUBLIC, authenticated, anon;


-- =============================================================================
-- SECTION 2: RLS Helper
-- STABLE = result cached per query, not per row. Safe and efficient for RLS.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.jwt_has_permission(permission_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt()->'user_permissions') ? permission_code;
$$;

GRANT EXECUTE ON FUNCTION public.jwt_has_permission TO authenticated;


-- =============================================================================
-- SECTION 3: RLS Policies
-- Only SELECT policies. Writes go through SECURITY DEFINER functions (Section 4).
-- Grouped by domain. Add new tables following the established pattern.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TIER 1: Catalog — open to all authenticated users (used in dropdowns)
-- -----------------------------------------------------------------------------

ALTER TABLE public.unidad            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unidad_conversion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_tipo         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insumo_tipo       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colorante_tipo    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.articulo_tipo     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.articulo          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.color             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cliente           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proveedor         ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.guia_remision_tipo   ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.operacion            ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.maquina_tipo         ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.empleado_rol         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calidad.tipo_defecto     ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.item_movimiento_tipo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_read" ON public.unidad            FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.unidad_conversion FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.item_tipo         FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.insumo_tipo       FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.colorante_tipo    FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.articulo_tipo     FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.articulo          FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.color             FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.cliente           FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON public.proveedor         FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON doc.guia_remision_tipo   FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON mes.operacion            FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON mes.maquina_tipo         FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON mes.empleado_rol         FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON calidad.tipo_defecto     FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read" ON inventario.item_movimiento_tipo FOR SELECT TO authenticated USING (true);


-- -----------------------------------------------------------------------------
-- TIER 2: Business tables — gated by domain permission
-- -----------------------------------------------------------------------------

-- ── Inventario ───────────────────────────────────────────────────────────────
ALTER TABLE public.item                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_insumo_detalle       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_rollo_detalle             ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.almacen                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.ubicacion                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.lote                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.item_movimientos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.pesaje                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario.lote_rollo_detalle         ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventario_ver" ON public.item                        FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON public.item_insumo_detalle         FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON public.item_rollo_detalle          FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON inventario.almacen                 FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON inventario.ubicacion               FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON inventario.lote                    FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON inventario.item_movimientos        FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "inventario_ver" ON inventario.pesaje                  FOR SELECT TO authenticated USING (jwt_has_permission('inventario.ver'));
CREATE POLICY "ver_lote_rollo"  ON inventario.lote_rollo_detalle     FOR SELECT TO authenticated USING (true);

-- ── Comercial ─────────────────────────────────────────────────────────────────
ALTER TABLE doc.partida                ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.partida_detalle        ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.guia_remision          ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.guia_remision_detalle  ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.catalogo_precios              ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.compra                        ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.compra_detalle                ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.compra_guia_remision          ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.factura_proveedor             ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.factura_proveedor_detalle     ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.letra                         ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.letra_factura                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.factura                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.factura_detalle               ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.partida_guia_remision         ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.compra_factura_proveedor      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comercial_ver" ON doc.partida                    FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.partida_detalle            FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.guia_remision              FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.guia_remision_detalle      FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.catalogo_precios           FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.compra                     FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.compra_detalle             FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.compra_guia_remision       FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.factura_proveedor          FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.factura_proveedor_detalle  FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.letra                      FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.letra_factura              FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.factura                    FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.factura_detalle            FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.partida_guia_remision      FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.compra_factura_proveedor   FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));

-- ── Producción ────────────────────────────────────────────────────────────────
ALTER TABLE mes.maquina                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.empleado                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.ruta_plantilla               ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.ruta_plantilla_detalle       ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.orden_produccion             ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.orden_produccion_paso        ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.orden_produccion_item        ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.orden_produccion_paso_item   ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.programacion                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE mes.lavado_maquina               ENABLE ROW LEVEL SECURITY;

CREATE POLICY "produccion_ver" ON mes.maquina                    FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.empleado                   FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.ruta_plantilla             FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.ruta_plantilla_detalle     FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.orden_produccion           FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.orden_produccion_paso      FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.orden_produccion_item      FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.orden_produccion_paso_item FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.programacion               FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));
CREATE POLICY "produccion_ver" ON mes.lavado_maquina             FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));

-- ── Calidad ───────────────────────────────────────────────────────────────────
ALTER TABLE calidad.inspeccion         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calidad.inspeccion_defecto ENABLE ROW LEVEL SECURITY;
ALTER TABLE calidad.inspeccion_foto    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "calidad_ver" ON calidad.inspeccion         FOR SELECT TO authenticated USING (jwt_has_permission('calidad.ver'));
CREATE POLICY "calidad_ver" ON calidad.inspeccion_defecto FOR SELECT TO authenticated USING (jwt_has_permission('calidad.ver'));
CREATE POLICY "calidad_ver" ON calidad.inspeccion_foto    FOR SELECT TO authenticated USING (jwt_has_permission('calidad.ver'));


-- -----------------------------------------------------------------------------
-- TIER 3: Usuario & IAM
-- -----------------------------------------------------------------------------

ALTER TABLE public.usuario  ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_row"        ON public.usuario FOR SELECT TO authenticated USING (auth.uid() = auth_id);
CREATE POLICY "admin_read_all" ON public.usuario FOR SELECT TO authenticated USING (jwt_has_permission('configuracion.ver'));

ALTER TABLE iam.rol ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read" ON iam.rol FOR SELECT TO authenticated USING (true);

ALTER TABLE iam.permiso     ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.user_rol    ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.rol_permiso ENABLE ROW LEVEL SECURITY;

CREATE POLICY "configuracion_ver" ON iam.permiso     FOR SELECT TO authenticated USING (jwt_has_permission('configuracion.ver'));
CREATE POLICY "configuracion_ver" ON iam.user_rol    FOR SELECT TO authenticated USING (jwt_has_permission('configuracion.ver'));
CREATE POLICY "configuracion_ver" ON iam.rol_permiso FOR SELECT TO authenticated USING (jwt_has_permission('configuracion.ver'));


-- =============================================================================
-- SECTION 4: Permission guard pattern for SECURITY DEFINER write functions
-- Paste the guard block at the top of each function's BEGIN body.
-- =============================================================================

-- Guard snippet (copy into each function):
--
--   IF NOT jwt_has_permission('domain.action') THEN
--     RAISE EXCEPTION 'Sin permiso: se requiere domain.action'
--       USING ERRCODE = 'insufficient_privilege';
--   END IF;

-- Permission code reference:
-- ┌─────────────────────────────────────────────┬────────────────────────────┐
-- │ Function                                    │ Permission                 │
-- ├─────────────────────────────────────────────┼────────────────────────────┤
-- │ COMERCIAL                                                                │
-- │  crear/editar partida                        │ comercial.crear/editar     │
-- │  registrar/anular guia_remision              │ comercial.crear/editar     │
-- │  crear_compra, vincular_*                    │ comercial.crear            │
-- │  registrar_factura_proveedor                 │ comercial.crear            │
-- │  registrar_letra, vincular_factura_compra    │ comercial.editar           │
-- │  pagar_letra                                 │ comercial.editar           │
-- ├─────────────────────────────────────────────┼────────────────────────────┤
-- │ INVENTARIO                                                               │
-- │  crear/editar item                           │ inventario.crear/editar    │
-- │  ajuste inventario                           │ inventario.editar          │
-- │  actualizar_pesos_*                          │ inventario.editar          │
-- ├─────────────────────────────────────────────┼────────────────────────────┤
-- │ PRODUCCIÓN                                                               │
-- │  crear_orden_produccion                      │ produccion.crear           │
-- │  actualizar_pasos_orden                      │ produccion.editar          │
-- │  iniciar_paso, finalizar_paso                │ produccion.ejecutar        │
-- │  registrar_consumo_paso                      │ produccion.ejecutar        │
-- │  registrar_items_procesados                  │ produccion.ejecutar        │
-- │  guardar_programacion                        │ produccion.programar       │
-- │  iniciar_lavado, finalizar_lavado            │ produccion.ejecutar        │
-- ├─────────────────────────────────────────────┼────────────────────────────┤
-- │ CALIDAD                                                                  │
-- │  crear/editar inspeccion                     │ calidad.crear/editar       │
-- ├─────────────────────────────────────────────┼────────────────────────────┤
-- │ CONFIGURACIÓN                                                            │
-- │  gestión de usuarios/roles                   │ configuracion.admin        │
-- │  crear maquina, operacion, ruta_plantilla    │ configuracion.admin        │
-- └─────────────────────────────────────────────┴────────────────────────────┘

-- =============================================================================
-- SECTION N: Auth user creation hook
-- Fires on INSERT into auth.users (new signup / admin-created user).
-- Maps auth.users → public.usuario using current column names.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_trg_bi_usuario_from_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  INSERT INTO public.usuario (auth_id, nombre, apellido)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'first_name',
    NEW.raw_user_meta_data ->> 'last_name'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_bi_auth_users_usuario ON auth.users;
CREATE TRIGGER trg_bi_auth_users_usuario
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_bi_usuario_from_auth();

  
-- ============================================================================
-- IAM: permisos and rol_permiso seed
-- Idempotent — ON CONFLICT DO NOTHING on both tables.
-- Covers every permission code referenced in RLS policies and function guards.
-- ============================================================================

INSERT INTO iam.permiso (code, descripcion) VALUES
    ('comercial.ver',        'Ver partidas, guías, compras y documentos comerciales'),
    ('comercial.crear',      'Crear partidas, guías de remisión y compras'),
    ('comercial.editar',     'Editar documentos comerciales, registrar facturas y letras'),
    ('inventario.ver',       'Ver stock, lotes, movimientos e ítems'),
    ('inventario.crear',     'Crear ítems e ingresar stock'),
    ('inventario.editar',    'Ajustar stock, actualizar pesos y valoraciones'),
    ('produccion.ver',       'Ver órdenes, pasos, programación y lavados'),
    ('produccion.crear',     'Crear órdenes de producción'),
    ('produccion.editar',    'Editar pasos y estructura de órdenes'),
    ('produccion.ejecutar',  'Iniciar y finalizar pasos y lavados, registrar consumos'),
    ('produccion.programar', 'Guardar y modificar la programación de máquinas'),
    ('calidad.ver',          'Ver inspecciones y resultados de calidad'),
    ('calidad.crear',        'Registrar inspecciones de calidad'),
    ('calidad.editar',       'Editar inspecciones existentes'),
    ('configuracion.ver',    'Ver usuarios, roles y configuración del sistema'),
    ('configuracion.admin',  'Gestionar usuarios, roles, máquinas, operaciones y plantillas')
ON CONFLICT (code) DO NOTHING;

-- rol_permiso: resolved by code so IDs don't need to be hardcoded
INSERT INTO iam.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM (VALUES
    -- ── admin: todo ──────────────────────────────────────────
    ('admin', 'comercial.ver'),
    ('admin', 'comercial.crear'),
    ('admin', 'comercial.editar'),
    ('admin', 'inventario.ver'),
    ('admin', 'inventario.crear'),
    ('admin', 'inventario.editar'),
    ('admin', 'produccion.ver'),
    ('admin', 'produccion.crear'),
    ('admin', 'produccion.editar'),
    ('admin', 'produccion.ejecutar'),
    ('admin', 'produccion.programar'),
    ('admin', 'calidad.ver'),
    ('admin', 'calidad.crear'),
    ('admin', 'calidad.editar'),
    ('admin', 'configuracion.ver'),
    ('admin', 'configuracion.admin'),
    -- ── jefe_planta: full operations, no user/config mgmt ────
    ('jefe_planta', 'comercial.ver'),
    ('jefe_planta', 'inventario.ver'),
    ('jefe_planta', 'inventario.crear'),
    ('jefe_planta', 'inventario.editar'),
    ('jefe_planta', 'produccion.ver'),
    ('jefe_planta', 'produccion.crear'),
    ('jefe_planta', 'produccion.editar'),
    ('jefe_planta', 'produccion.ejecutar'),
    ('jefe_planta', 'produccion.programar'),
    ('jefe_planta', 'calidad.ver'),
    ('jefe_planta', 'calidad.crear'),
    ('jefe_planta', 'calidad.editar'),
    ('jefe_planta', 'configuracion.ver'),
    -- ── supervisor_produccion: plan + execute, read-only elsewhere
    ('supervisor_produccion', 'comercial.ver'),
    ('supervisor_produccion', 'inventario.ver'),
    ('supervisor_produccion', 'produccion.ver'),
    ('supervisor_produccion', 'produccion.crear'),
    ('supervisor_produccion', 'produccion.editar'),
    ('supervisor_produccion', 'produccion.ejecutar'),
    ('supervisor_produccion', 'produccion.programar'),
    ('supervisor_produccion', 'calidad.ver'),
    -- ── operador_produccion: execute only ────────────────────
    ('operador_produccion', 'produccion.ver'),
    ('operador_produccion', 'produccion.ejecutar'),
    ('operador_produccion', 'inventario.ver'),
    ('operador_produccion', 'calidad.ver'),
    -- ── calidad ──────────────────────────────────────────────
    ('calidad', 'calidad.ver'),
    ('calidad', 'calidad.crear'),
    ('calidad', 'calidad.editar'),
    ('calidad', 'produccion.ver'),
    ('calidad', 'inventario.ver'),
    -- ── inventario ───────────────────────────────────────────
    ('inventario', 'inventario.ver'),
    ('inventario', 'inventario.crear'),
    ('inventario', 'inventario.editar'),
    ('inventario', 'produccion.ver'),
    ('inventario', 'comercial.ver'),
    -- ── compras ──────────────────────────────────────────────
    ('compras', 'comercial.ver'),
    ('compras', 'comercial.crear'),
    ('compras', 'comercial.editar'),
    ('compras', 'inventario.ver'),
    ('compras', 'inventario.crear'),
    -- ── sistema: automated processes, broad read + execute ───
    ('sistema', 'produccion.ver'),
    ('sistema', 'produccion.ejecutar'),
    ('sistema', 'inventario.ver'),
    ('sistema', 'inventario.editar'),
    ('sistema', 'calidad.ver')
) AS mapping(rol_code, permiso_code)
JOIN iam.rol     r ON r.code = mapping.rol_code
JOIN iam.permiso p ON p.code = mapping.permiso_code
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

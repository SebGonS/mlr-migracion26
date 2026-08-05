-- mes.empleado had SELECT (produccion_ver) but no INSERT/UPDATE policy or grant,
-- unlike its sibling catalog mes.maquina. Bring it in line so it can be populated
-- and maintained through the app (configuracion.operacional), not just service_role.

DROP POLICY IF EXISTS "catalogos_insert" ON mes.empleado;
DROP POLICY IF EXISTS "catalogos_update" ON mes.empleado;

CREATE POLICY "catalogos_insert" ON mes.empleado FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "catalogos_update" ON mes.empleado FOR UPDATE TO authenticated USING     (jwt_has_permission('configuracion.operacional'));

GRANT INSERT, UPDATE ON mes.empleado TO authenticated;
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.empleado FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.empleado FROM anon, authenticated;

-- perfil_id links an employee to a public.usuario login — an IAM action, not plant
-- config. configuracion.operacional (held by jefe_planta) must not be able to set or
-- change it; that belongs to configuracion.admin (see SCHEMA_MANUAL.md separation
-- rationale). No RPC to assign it yet (feature on standby) — for now perfil_id can
-- only be set directly as service_role, until a configuracion.admin-gated RPC exists.
REVOKE INSERT (perfil_id) ON mes.empleado FROM anon, authenticated;
REVOKE UPDATE (perfil_id) ON mes.empleado FROM anon, authenticated;

-- Run once as a superuser / admin.
-- Grants claude_ro read-only access to the `calidad` schema — missed in the
-- original _create_readonly_role.sql (which covered doc/mes/inventario/receta/public).
-- SELECT-only; no write grants.

GRANT USAGE ON SCHEMA calidad TO claude_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA calidad TO claude_ro;

-- Keep future calidad tables covered automatically (still SELECT-only):
ALTER DEFAULT PRIVILEGES IN SCHEMA calidad GRANT SELECT ON TABLES TO claude_ro;

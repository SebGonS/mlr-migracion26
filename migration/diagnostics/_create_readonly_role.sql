-- Run once as a superuser / existing admin role.
-- Creates a login role with SELECT-only access across the schemas this
-- migration work touches. No INSERT/UPDATE/DELETE/DDL grants anywhere.

CREATE ROLE claude_ro LOGIN PASSWORD '<choose-a-password>';

GRANT USAGE ON SCHEMA doc, mes, inventario, receta, public TO claude_ro;

GRANT SELECT ON ALL TABLES IN SCHEMA doc       TO claude_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA mes       TO claude_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA inventario TO claude_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA receta    TO claude_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public    TO claude_ro;

-- Keep future tables covered automatically (optional but convenient —
-- still SELECT-only, so safe):
ALTER DEFAULT PRIVILEGES IN SCHEMA doc        GRANT SELECT ON TABLES TO claude_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA mes        GRANT SELECT ON TABLES TO claude_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventario GRANT SELECT ON TABLES TO claude_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA receta     GRANT SELECT ON TABLES TO claude_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public     GRANT SELECT ON TABLES TO claude_ro;

-- Explicitly no BYPASSRLS, no NOSUPERUSER needed (default), no CREATEDB/CREATEROLE.
-- If RLS policies restrict rows for "authenticated"/anon roles, claude_ro reading
-- as a plain role with table GRANTs still sees all rows unless RLS is FORCEd —
-- confirm that's the intent (it is, for migration diagnostics).

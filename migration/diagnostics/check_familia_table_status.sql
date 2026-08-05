-- ============================================================================
-- Real live status of the familia-pricing table: articulo_tipo_familia vs
-- grupo_articulo_familia — has migration 34 (rename + index swap + drop
-- legacy columns) actually run? GRUPO_ARTICULO_HANDOFF.md still lists 34 as
-- "deferred, not started" as of 2026-07-20 — this checks whether reality
-- has since moved past the doc.
-- ============================================================================
SELECT * FROM doc.articulo_tipo_familia LIMIT 5;
-- 1. Which name exists?
SELECT to_regclass('doc.articulo_tipo_familia')  AS legacy_name_exists,
       to_regclass('doc.grupo_articulo_familia')  AS new_name_exists;

-- 2. Columns on whichever one exists (run against the name that hit above)
SELECT table_schema, table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'doc'
  AND table_name IN ('articulo_tipo_familia', 'grupo_articulo_familia')
ORDER BY table_name, ordinal_position;

-- 3. Indexes — are the unique indexes still keyed on the legacy columns
--    (articulo_tipo_id/familia_id) or swapped onto grupo_articulo_id/
--    familia_grupo_id? This is the detail that determines whether a new
--    mixed grupo (no origen_articulo_tipo_id) is actually protected by a
--    uniqueness constraint.
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'doc'
  AND tablename IN ('articulo_tipo_familia', 'grupo_articulo_familia')
ORDER BY indexname;

-- 4. Grants for the app role — confirms whether direct writes from the
--    frontend are even possible, or whether a function is still required.
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'doc'
  AND table_name IN ('articulo_tipo_familia', 'grupo_articulo_familia')
  AND grantee IN ('authenticated', 'service_role', 'anon')
ORDER BY grantee, privilege_type;

-- 5. Does articulo_tipo itself still exist (34 also retires it)?
SELECT to_regclass('public.articulo_tipo') AS articulo_tipo_exists;

-- 6. Any CRUD function already defined for this table (in case one landed
--    without updating the handoff doc)?
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'doc'
  AND (p.prosrc ILIKE '%articulo_tipo_familia%' OR p.prosrc ILIKE '%grupo_articulo_familia%')
ORDER BY p.proname;

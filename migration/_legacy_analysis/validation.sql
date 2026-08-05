-- =====================================================================
-- Post-load validation — run AFTER loading baseline.sql into the new project.
-- Confirms the active-object set landed intact and nothing unexpected
-- leaked in from the legacy cluster.
-- =====================================================================

-- 1. Object counts per schema — compare against CLASSIFICATION.md expectations
--    (tables: 94, views: 101, functions: 229, types: 21, sequences: 60 kept)
SELECT 'tables' AS kind, table_schema, count(*)
FROM information_schema.tables
WHERE table_schema IN ('public','doc','mes','inventario','receta','calidad','iam','notification','alertas','audit')
  AND table_type = 'BASE TABLE'
GROUP BY table_schema
UNION ALL
SELECT 'views', table_schema, count(*)
FROM information_schema.views
WHERE table_schema IN ('public','doc','mes','inventario','receta','calidad','iam','notification','alertas','audit')
GROUP BY table_schema
UNION ALL
SELECT 'functions', n.nspname, count(*)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public','doc','mes','inventario','receta','calidad','iam','notification','alertas','audit')
GROUP BY n.nspname
ORDER BY 1, 2;

-- 2. None of the legacy/junk tables should exist at all in the new project
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'tmp','tmp2','tmp_parche','tmp_receta','tmp_receta_casos','temp_id_partida','temp_id_receta',
    'temp_insumos_corregidos','prod_tmp','parada_tmp','sertks1','sertks2','mersan','insumo_corregido',
    'json_debug_log','receta_id','v_receta_id','id_receta_x_partida',
    'compra','despacho','partida','receta2','receta_x_paso','receta_x_insumo','catalogo_precios',
    'cliente','proveedor','insumo','maquina','paso','produccion','produccion_tenido','programa_tenido',
    'programacion','lavado_maquina','entrada_inventario','salida_inventario','cuadre_inventario'
  );
-- expect: 0 rows. Any row here means a legacy table leaked into the baseline.

-- 3. Every FK in the new schema must resolve to a table that actually exists
--    (this is normally guaranteed by baseline.sql loading successfully — FK creation
--     fails at DDL time if the target table is missing — but re-check post-load in
--     case of a later manual edit)
SELECT conname, conrelid::regclass AS table_from, confrelid::regclass AS table_to
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace::regnamespace::text IN ('public','doc','mes','inventario','receta','calidad','iam','notification','alertas','audit');
-- eyeball: table_to should only be Tier-A public tables, domain tables, or auth.users (platform).

-- 4. Confirm the two intentionally-dropped vestigial FKs are indeed absent
SELECT conname FROM pg_constraint
WHERE conname IN ('tercero_cliente_id_fkey','tercero_cliente_id2_fkey','tercero_proveedor_id_fkey','color_x_cliente_fk_cliente_fkey');
-- expect: 0 rows (dropped by design; tercero.cliente_id/cliente_id2/proveedor_id and
-- color_x_cliente.cliente_id columns still exist as plain nullable integers — verify below)

SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE (table_schema, table_name, column_name) IN (
  ('public','tercero','cliente_id'), ('public','tercero','cliente_id2'), ('public','tercero','proveedor_id'),
  ('public','color_x_cliente','cliente_id')
);
-- expect: all 4 rows present (columns retained, just not FK-enforced)

-- 5. Collation sanity check — public.case_insensitive must exist (used by public.tipo_receta)
SELECT collname FROM pg_collation WHERE collname = 'case_insensitive' AND collnamespace = 'public'::regnamespace;
-- expect: 1 row

-- 6. RLS is actually enabled where the original schema expected it
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname IN ('doc','mes','inventario','receta','calidad','iam','notification','alertas','audit')
  AND rowsecurity = false;
-- expect: 0 rows, unless a specific table was intentionally left without RLS (check against dump)

-- 7. Extensions loaded
SELECT extname FROM pg_extension
WHERE extname IN ('pg_cron','pgsodium','pg_graphql','pg_stat_statements','pgcrypto','pgjwt','supabase_vault','unaccent','uuid-ossp');
-- expect: all 9 (some are auto-installed by Supabase provisioning regardless of baseline.sql)

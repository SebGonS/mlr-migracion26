-- ============================================================================
-- 29 · Rename doc.guia_remision* → doc.entrega*  (live-DB catalog rename)
-- ============================================================================
-- WHY: `guia_remision` named the generic delivery/movement document after one
-- specific legal artifact (the PE "guía de remisión"). The table is really the
-- delivery entity (SAP LIKP/LIPS, Odoo stock.picking) that posts to the ledger
-- (item_movimientos ≈ MKPF/MSEG). Legal serie/correlativo are nominal references
-- on it, not its identity. Generalized name: `entrega` (delivery), direction-aware.
--
-- SCOPE: pure catalog rename of the doc.guia_remision* family. No data change.
--   - Views auto-track table/column renames (stored by OID/attnum) → keep working.
--   - plpgsql FUNCTION bodies are stored as text, resolved at runtime → they do
--     NOT auto-update. After this script REDEPLOY funciones/*.sql, then DROP the
--     stale old-named functions (§6).
--
-- ⚠️ OUT OF SCOPE — DO NOT TOUCH (legacy `public.*` schema, a DIFFERENT concept):
--     public.partida.guia            (varchar free-text legacy field)
--     public.compra.guia_remision    (text legacy reference)
--     public.devolucion.guia_remision(text legacy reference)
--     + every public.vw_* that reads them.
--   These are unrelated to doc.entrega. Renaming them breaks legacy compatibility.
--
-- IDEMPOTENT: safe to re-run. Section 1-2 use IF EXISTS; 3-5 are dynamic loops
-- driven by the live catalog, so they no-op once names are already migrated.
--
-- VERIFY: run the discovery query (§8). After this script + redeploy, remaining
--   rows should be ONLY the legacy public.* items above (a different concept).
--   The source find/replace was broad (guia→entrega), so view aliases
--   (guia_serie/correlativo/numero → entrega_*) and view objects (vw_*_guia →
--   vw_*_entrega) are ALREADY converted in source; §6 makes the live redeploy land.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────
-- FUNCTIONAL RENAMES (required)
-- ────────────────────────────────────────────────────────────────────────
BEGIN;

-- 1 · Tables ----------------------------------------------------------------
ALTER TABLE IF EXISTS doc.guia_remision_tipo    RENAME TO entrega_tipo;
ALTER TABLE IF EXISTS doc.guia_remision         RENAME TO entrega;
ALTER TABLE IF EXISTS doc.guia_remision_detalle RENAME TO entrega_detalle;
ALTER TABLE IF EXISTS doc.compra_guia_remision  RENAME TO compra_entrega;

-- 2 · Columns (reference the NEW table names) --------------------------------
ALTER TABLE IF EXISTS doc.entrega                   RENAME COLUMN guia_remision_tipo_id TO entrega_tipo_id;
ALTER TABLE IF EXISTS doc.entrega_detalle           RENAME COLUMN guia_remision_id      TO entrega_id;
ALTER TABLE IF EXISTS doc.compra_entrega            RENAME COLUMN guia_remision_id      TO entrega_id;
ALTER TABLE IF EXISTS doc.factura_detalle           RENAME COLUMN guia_remision_id      TO entrega_id;
ALTER TABLE IF EXISTS inventario.lote_rollo_detalle RENAME COLUMN guia_remision_id      TO entrega_id;

-- 3 · Bare-"guia" objects (don't contain the full "guia_remision" stem) ------
ALTER INDEX IF EXISTS inventario.idx_lrd_guia      RENAME TO idx_lrd_entrega;
ALTER INDEX IF EXISTS doc.idx_factura_detalle_guia RENAME TO idx_factura_detalle_entrega;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_guia_doc_fields') THEN
        ALTER TABLE doc.entrega RENAME CONSTRAINT chk_guia_doc_fields TO chk_entrega_doc_fields;
    END IF;
END$$;

-- 4 · Triggers (dynamic — audit + codigo_canon; catches truncated names) ------
-- Renaming prevents DOUBLE audit triggers when migration 12 is re-run.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT t.tgname, t.tgrelid::regclass AS tbl
        FROM pg_trigger t
        JOIN pg_class c     ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE NOT t.tgisinternal
          AND n.nspname = 'doc'
          AND t.tgname LIKE '%guia_remision%'
    LOOP
        EXECUTE format('ALTER TRIGGER %I ON %s RENAME TO %I',
                       r.tgname, r.tbl, replace(r.tgname, 'guia_remision', 'entrega'));
    END LOOP;
END$$;

COMMIT;

-- ────────────────────────────────────────────────────────────────────────
-- 5 · COSMETIC RENAMES (optional — spotless catalog; nothing references these
--     by name in code). Dynamic so it handles 63-char-truncated auto names.
-- ────────────────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE r RECORD;
BEGIN
    -- identity sequences
    FOR r IN
        SELECT n.nspname AS sch, c.relname AS nm
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'S' AND c.relname LIKE '%guia_remision%'
    LOOP
        EXECUTE format('ALTER SEQUENCE %I.%I RENAME TO %I',
                       r.sch, r.nm, replace(r.nm, 'guia_remision', 'entrega'));
    END LOOP;

    -- auto-named constraints (pkey / fkey / unique / check)
    FOR r IN
        SELECT con.conname AS nm, con.conrelid::regclass AS tbl
        FROM pg_constraint con
        WHERE con.conname LIKE '%guia_remision%'
    LOOP
        EXECUTE format('ALTER TABLE %s RENAME CONSTRAINT %I TO %I',
                       r.tbl, r.nm, replace(r.nm, 'guia_remision', 'entrega'));
    END LOOP;

    -- constraint-backing indexes keep their own name; rename separately
    FOR r IN
        SELECT schemaname AS sch, indexname AS nm
        FROM pg_indexes
        WHERE indexname LIKE '%guia_remision%'
    LOOP
        EXECUTE format('ALTER INDEX %I.%I RENAME TO %I',
                       r.sch, r.nm, replace(r.nm, 'guia_remision', 'entrega'));
    END LOOP;
END$$;
COMMIT;

-- ────────────────────────────────────────────────────────────────────────
-- 6 · VIEW TEARDOWN (run IMMEDIATELY BEFORE redeploying 08_views.sql)
-- ────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE VIEW cannot rename a column or a view object. Buckets 2+3
-- (output aliases guia_serie/correlativo/numero/tipo → entrega_*, and the view
-- objects vw_*_guia → vw_*_entrega) are already converted in SOURCE, but LIVE
-- still has the old views. Drop them (CASCADE) so the 08_views redeploy recreates
-- them clean. 08_views is the single source of all views → recreation is total.
-- IF EXISTS = safe whether or not 08_views' own DROP block already removed some.
-- SCOPE: doc/inventario/mes/calidad only. public.* views read the LEGACY
-- partida.guia / compra.guia_remision columns (not renamed) → leave them.
BEGIN;
-- object-renamed orphans (08_views drops the NEW names, never these old ones)
DROP VIEW IF EXISTS inventario.vw_guias_rollos_pendientes  CASCADE;
DROP VIEW IF EXISTS inventario.vw_rollos_por_guia          CASCADE;
DROP VIEW IF EXISTS inventario.vw_item_proveedor_guia      CASCADE;
-- column-renamed (guia_* aliases / guia_remision_id → entrega_*); CREATE OR
-- REPLACE would error on these, so drop first.
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock       CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_disponibles CASCADE;
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_despachados CASCADE;
DROP VIEW IF EXISTS calidad.vw_auditoria_pendiente         CASCADE;
DROP VIEW IF EXISTS doc.vw_aprobados_sin_despacho          CASCADE;
DROP VIEW IF EXISTS doc.vw_compras                         CASCADE;
DROP VIEW IF EXISTS doc.vw_compras_recepcion               CASCADE;
DROP VIEW IF EXISTS doc.vw_pendientes_facturacion          CASCADE;
DROP VIEW IF EXISTS doc.vw_pendientes_proceso              CASCADE;
DROP VIEW IF EXISTS mes.vw_pesaje_pendiente                CASCADE;
COMMIT;
-- → now redeploy migration/08_views.sql (recreates all of the above, new names).

-- ============================================================================
-- 7 · POST-STEPS (run AFTER redeploying funciones/*.sql with the new names)
-- ----------------------------------------------------------------------------
-- Re-running source CREATE OR REPLACE creates new-named functions ALONGSIDE the
-- old ones — drop the stale old names (discovery query flags them as detail='NAME').
--
--   DROP FUNCTION IF EXISTS doc.crear_guia(jsonb);                         -- → crear_entrega
--   DROP FUNCTION IF EXISTS doc.get_guia_remision(bigint);                 -- → get_entrega
--   DROP FUNCTION IF EXISTS doc.anular_guia_remision(bigint);              -- → anular_entrega
--   DROP FUNCTION IF EXISTS doc.vincular_guias_compra(bigint, jsonb);      -- vestige / → vincular_entregas_compra
--   DROP FUNCTION IF EXISTS doc.desvincular_guias_compra(bigint, jsonb);   -- vestige / → desvincular_entregas_compra
--   DROP FUNCTION IF EXISTS inventario.registrar_pesaje_guia(bigint, numeric, numeric);   -- if renamed in source
--   DROP FUNCTION IF EXISTS inventario.registrar_pesaje_guia_individual(bigint, jsonb);   -- if renamed in source
--
-- NOTE: routine rows with detail='body' just need REDEPLOY (no drop).
-- ============================================================================

-- ============================================================================
-- 8 · DISCOVERY / VERIFICATION QUERY — any remaining "guia" in the catalog
-- ============================================================================
-- WITH hits AS (
--   SELECT 'relation' AS kind, n.nspname AS schema, c.relname AS object, c.relkind::text AS detail
--   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
--   WHERE c.relkind IN ('r','v','m','S','p') AND c.relname ILIKE '%guia%'
--     AND n.nspname NOT IN ('pg_catalog','information_schema')
--   UNION ALL
--   SELECT 'column', n.nspname, c.relname||'.'||a.attname, format_type(a.atttypid,a.atttypmod)
--   FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
--   WHERE a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','p','v','m')
--     AND a.attname ILIKE '%guia%' AND n.nspname NOT IN ('pg_catalog','information_schema')
--   UNION ALL
--   SELECT 'routine', n.nspname, p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
--          CASE WHEN p.proname ILIKE '%guia%' THEN 'NAME' ELSE 'body' END
--   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--   WHERE (p.proname ILIKE '%guia%' OR p.prosrc ILIKE '%guia%')
--     AND n.nspname NOT IN ('pg_catalog','information_schema')
--   UNION ALL
--   SELECT 'view_body', schemaname, viewname, 'definition'
--   FROM pg_views WHERE definition ILIKE '%guia%' AND schemaname NOT IN ('pg_catalog','information_schema')
--   UNION ALL
--   SELECT 'constraint', n.nspname, con.conrelid::regclass||' :: '||con.conname, con.contype::text
--   FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE con.conname ILIKE '%guia%'
--   UNION ALL
--   SELECT 'index', schemaname, indexname, tablename
--   FROM pg_indexes WHERE indexname ILIKE '%guia%' AND schemaname NOT IN ('pg_catalog','information_schema')
--   UNION ALL
--   SELECT 'trigger', n.nspname, t.tgrelid::regclass||' :: '||t.tgname, NULL
--   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
--   WHERE NOT t.tgisinternal AND t.tgname ILIKE '%guia%'
-- )
-- SELECT * FROM hits ORDER BY kind, schema, object;

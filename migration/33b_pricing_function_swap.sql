-- ═══════════════════════════════════════════════════════════════
-- Step 33b: swap the pricing functions onto grupo_articulo
--
-- DEPENDS ON: 33 (applied — grupo columns exist and are backfilled).
--
-- WHY THIS IS A SEPARATE FILE AND NOT "just re-apply funciones/" ────────────
-- The conversion changes SIGNATURES, not just bodies:
--     fn_get_precio      p_articulo_tipo_id SMALLINT → p_grupo_articulo_id INT
--     fn_familia_precio  p_articulo_tipo_id SMALLINT → p_grupo_articulo_id INT
--     fn_precio_info     idem
--     upsert_catalogo_precio idem
-- CREATE OR REPLACE cannot change a signature — it creates a SECOND OVERLOAD.
-- Patch 46 already paid for this lesson (see its Step 3b): it first created the
-- new arity alongside the old one, and every call became ambiguous
-- ("function ... is not unique") because both overloads matched. SMALLINT→INT is
-- the same trap by a different route: an INT literal is assignable to both, so
-- leaving the old function in place makes the call ambiguous rather than
-- silently wrong — loud, but a hard outage.
--
-- The only safe order, from 46:
--     drop every dependent explicitly → drop the old functions
--     → recreate the functions → rebuild dependents fresh
-- EXPLICIT drops, never CASCADE, so a forgotten dependent fails loudly HERE
-- instead of being silently deleted and noticed in a month.
--
-- ⚠ APPLY ORDER:
--     1. Run the PRE-FLIGHT query below and reconcile the drop list. Do not
--        skip it — the list is a snapshot, and it is the whole safety net.
--     2. Run this file (drops + index re-key).
--     3. Re-apply funciones/facturacion.sql, then funciones/despacho.sql, then
--        migration/08_views.sql (recreates doc.vw_venta — dropped in §1, see the
--        fn_descripcion_linea note), then funciones/receta.sql, funciones/mes.sql.
--   Between 2 and 3 the pricing path DOES NOT EXIST. This is deliberate — a
--   missing function errors, a wrong-keyed one silently mis-prices. Run 2 and 3
--   in ONE session, ideally one transaction.
--
-- AUTHORITY (verified live 2026-07-19 via pg_proc):
--   · fn_get_precio is the 6-arg post-patch-46 shape with no flg_antipilling.
--   · funciones/facturacion.sql matches that shape, so the file — not patch 46 —
--     is the source to convert from. No risk of reverting 46's antipilling work.
--   · No pre-existing overloads: exactly one row per proname. The signatures
--     below are therefore complete.
--   · registrar_despacho lives in funciones/despacho.sql (it already carries the
--     venta module — 14 venta_detalle refs). VENTA_MODULE_CONSOLIDATED.sql at
--     repo root is a STAGING DRAFT, not live. Do not convert that copy.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. DDL MISSED BY 33: doc.factura_detalle ──────────────────────────────
-- ⚠ 33 re-keyed catalogo_precios, articulo_tipo_familia and venta_detalle but
-- NOT factura_detalle, which carries the same snapshot billing dimensions
-- (migration/07:893). Found while converting the billing views.
--
-- This is the highest-consequence gap in the whole migration. It is not just a
-- display column: vw_pendientes_facturacion and vw_aprobados_sin_despacho use
--     AND fd.articulo_tipo_id = l.articulo_tipo_id
-- as the ANTI-JOIN that excludes already-invoiced lines. Re-key the left side
-- (the partida) without the right side (the invoice) and the comparison stops
-- matching, so every previously-billed line reappears as pending → DOUBLE
-- BILLING, silently, on real client invoices.
--
-- Same snapshot semantics as venta_detalle: historical rows are backfilled so
-- old invoices still resolve a substrate, and the column is deliberately NOT
-- NULL-constrained (ad-hoc invoice lines legitimately carry no article dim).
ALTER TABLE doc.factura_detalle
    ADD COLUMN IF NOT EXISTS grupo_articulo_id INT REFERENCES grupo_articulo(id);

UPDATE doc.factura_detalle fd
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = fd.articulo_tipo_id
  AND fd.grupo_articulo_id IS NULL;

-- Abort if any concrete articulo_tipo_id failed to resolve. NULLs are expected
-- (ad-hoc lines) and excluded, exactly as in 33's §4.
DO $$
DECLARE v_fd INT;
BEGIN
    SELECT COUNT(*) INTO v_fd FROM doc.factura_detalle
    WHERE articulo_tipo_id IS NOT NULL AND grupo_articulo_id IS NULL;

    IF v_fd > 0 THEN
        RAISE EXCEPTION
            'Migración 33b abortada: % línea(s) de factura sin grupo_articulo_id resuelto.', v_fd;
    END IF;
END $$;

-- ── 0b. PRE-FLIGHT — reconcile the drop list before running anything ──────
-- ⚠ A TEXT-MATCH PRE-FLIGHT IS NOT ENOUGH — this cost a round trip. The first
-- version of this query regex-matched view definitions for 'fn_get_precio' and
-- MISSED doc.vw_precios_pendientes, which never names the function: it just
-- selects FROM doc.vw_precios_estado, which does. View-on-view chains are
-- invisible to text matching, and Postgres WILL refuse the DROP on them.
--
-- Use pg_depend — that is what DROP itself consults. Run BOTH:
--
-- (a) Transitive view dependents. Drop deepest-first:
--   WITH RECURSIVE deps AS (
--       SELECT c.oid, 1 AS nivel
--       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
--       WHERE n.nspname='doc' AND c.relname IN
--           ('vw_precios_estado','vw_pendientes_facturacion','vw_aprobados_sin_despacho')
--       UNION
--       SELECT r.ev_class, d.nivel + 1
--       FROM deps d
--       JOIN pg_depend dep ON dep.refobjid = d.oid
--       JOIN pg_rewrite r  ON r.oid = dep.objid
--       WHERE r.ev_class <> d.oid
--   )
--   SELECT n.nspname||'.'||c.relname AS objeto, MAX(d.nivel) AS profundidad
--   FROM deps d JOIN pg_class c ON c.oid = d.oid
--   JOIN pg_namespace n ON n.oid = c.relnamespace
--   GROUP BY 1 ORDER BY profundidad DESC;
--
-- (b) Function callers — text match, because pg_depend does NOT track plpgsql
--     body references:
--   SELECT n.nspname||'.'||p.proname||'('||
--          pg_get_function_identity_arguments(p.oid)||')' AS objeto
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE p.prosrc ~ '(fn_get_precio|fn_familia_precio)'
--     AND p.proname NOT IN ('fn_get_precio','fn_familia_precio');
--
-- Why (b) still matters even though DROP won't complain about them: plpgsql is
-- LATE-BINDING, so those functions break at RUNTIME, not at drop time. They must
-- be re-applied in step 3 regardless. Silence here is not safety.

-- ── 1. Drop dependents, deepest first ─────────────────────────────────────
-- Views bind their references at definition time, so all views go before the
-- functions; within views, dependents before their sources.
--
-- ⚠ A SECOND, INDEPENDENT reason every view below must be dropped, not just
-- CREATE OR REPLACE'd: Postgres does not allow CREATE OR REPLACE VIEW to rename
-- an existing output column — it only allows appending new columns at the end.
-- Every view converted in this pass renames articulo_tipo_id/articulo_tipo →
-- grupo_articulo_id/grupo_articulo IN PLACE (not additively), so re-applying the
-- owning funciones/*.sql or migration/08_views.sql file fails outright with
-- "cannot change name of view column" unless the view is dropped first. This is
-- true independent of whatever function-dependency reason got each view onto
-- this list — vw_tenido (receta.sql) has NO function-signature reason to be
-- here, it needs dropping for the rename alone.
--
-- vw_precios_pendientes is a thin filter over vw_precios_estado
-- (funciones/facturacion.sql:587) and must be dropped FIRST or the next line
-- fails. Surfaced by pre-flight (a); grep did not find it.
DROP VIEW     IF EXISTS doc.vw_precios_pendientes;
DROP VIEW     IF EXISTS doc.vw_precios_estado;
DROP VIEW     IF EXISTS doc.vw_pendientes_facturacion;
DROP VIEW     IF EXISTS doc.vw_aprobados_sin_despacho;
-- get_tenido_versiones (funciones/receta.sql) selects FROM receta.vw_tenido —
-- late-binding (plpgsql/sql function bodies are not pg_depend edges), so this
-- DROP will not fail on it, but get_tenido_versiones breaks at RUNTIME until
-- receta.sql is re-applied in step 3 regardless.
DROP VIEW     IF EXISTS receta.vw_tenido;
DROP FUNCTION IF EXISTS doc.get_precios_partida(BIGINT[]);
DROP FUNCTION IF EXISTS doc.registrar_despacho(JSONB);

-- Signatures confirmed live via pg_get_function_identity_arguments — these are
-- exact. A typo makes DROP ... IF EXISTS a silent no-op, leaving the old
-- function to collide with the new one at step 3.
DROP FUNCTION IF EXISTS doc.fn_precio_info(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, BOOLEAN);
DROP FUNCTION IF EXISTS doc.upsert_catalogo_precio(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, NUMERIC);
DROP FUNCTION IF EXISTS doc.fn_get_precio(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT);
DROP FUNCTION IF EXISTS doc.fn_familia_precio(SMALLINT, INT);

-- ⚠ CORRECTED TWICE — fn_descripcion_linea needs an explicit drop AND a
-- dependent view drop first, same reason as the four functions above but with
-- a sharper edge. It is a DISPLAY helper (builds the invoice line text), not
-- part of price resolution, but its p_articulo_tipo_id SMALLINT → 4th-arg INT
-- change is still a signature change.
--
-- doc.vw_venta (migration/08_views.sql) is its ONLY caller, and it passes
-- vd.articulo_tipo_id — a SMALLINT column on the LIVE (pre-33b) venta_detalle.
-- That means the live view is bound via pg_depend to the OLD SMALLINT overload
-- specifically, not just textually referencing the function name. DROP FUNCTION
-- on that signature FAILS ("cannot drop ... other objects depend on it") unless
-- vw_venta is dropped first. Neither pre-flight query (a) or (b) above would
-- have caught this — (a) only seeds from the three pricing views, (b) only
-- matches fn_get_precio/fn_familia_precio callers. Found by re-reading the
-- caller directly while converting despacho.sql.
DROP VIEW     IF EXISTS doc.vw_venta;
DROP FUNCTION IF EXISTS doc.fn_descripcion_linea(venta_linea_tipo_enum, SMALLINT, INT, SMALLINT, INT, INT, BOOLEAN);

-- ── 2. Re-key the active-row unique index ─────────────────────────────────
-- ⚠ NOT IN THE ORIGINAL 33 PLAN — a real gap. uq_catalogo_precios_activo was
-- rebuilt by patch 46 keyed on COALESCE(articulo_tipo_id::int, -1). Once pricing
-- resolves on grupo, "one active row per combination" would still be enforced on
-- the ABANDONED column: two active rows differing only by grupo get wrongly
-- rejected, and a genuine duplicate gets wrongly allowed. Same class of step as
-- migration 31 on the recipe side.
--
-- ⚠ Schema-qualify DROP INDEX — unqualified it silently no-ops ("does not exist,
-- skipping") if doc is not on the session search_path, leaving the OLD index in
-- place while the new one is created. That is a known scar in this project;
-- see the gotchas in GRUPO_ARTICULO_HANDOFF.md.
DROP INDEX IF EXISTS doc.uq_catalogo_precios_activo;

-- CREATE INDEX cannot be schema-qualified — it inherits the table's schema.
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalogo_precios_activo
    ON doc.catalogo_precios (
        operacion_id,
        COALESCE(color_x_cliente_id, -1),
        COALESCE(tercero_id,         -1),
        COALESCE(grupo_articulo_id,  -1),
        COALESCE(tenido_id,          -1),
        COALESCE(fibra::int,         -1)
    )
    WHERE fyh_elm IS NULL;

-- If the CREATE above fails with a uniqueness violation, the grupo re-key has
-- COLLAPSED two previously-distinct active rows onto one key — i.e. two
-- articulo_tipos mapped to the same grupo. Migration 28 seeds 1:1 so this should
-- not happen; if it does, STOP and inspect rather than soft-closing a row:
--   SELECT operacion_id, color_x_cliente_id, tercero_id, grupo_articulo_id,
--          tenido_id, fibra, COUNT(*), array_agg(id)
--   FROM doc.catalogo_precios WHERE fyh_elm IS NULL
--   GROUP BY 1,2,3,4,5,6 HAVING COUNT(*) > 1;

-- ── 3. NEXT: re-apply the funciones/ files ────────────────────────────────
-- Nothing else happens in this file. The recreated bodies live in funciones/ so
-- they stay re-appliable; only the destructive sequencing belongs here.
--
-- The GRANTs are signature-pinned and are reissued by facturacion.sql:
--   GRANT EXECUTE ON FUNCTION doc.fn_familia_precio(INT, INT) TO authenticated;
-- A stale GRANT on the OLD signature does not error — it just silently fails to
-- apply to the new function, and the frontend gets permission denied.

-- ── VERIFY (after step 3) ─────────────────────────────────────────────────
-- All four pricing functions took the new key, and no overload survived
-- (expect exactly one row each, all menciona_grupo = true):
--   SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
--          p.prosrc LIKE '%grupo_articulo%' AS menciona_grupo
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname='doc' AND p.proname IN
--     ('fn_get_precio','fn_familia_precio','fn_precio_info','upsert_catalogo_precio')
--   ORDER BY 1;
--
-- THE CHECK THAT MATTERS — a known pure partida must resolve the SAME precio_kg
-- as before this swap. A wrong key here does not error; it quietly resolves a
-- wildcard row. Capture the number BEFORE running step 2.


SELECT n.nspname || '.' || c.relname AS objeto, 'view' AS tipo
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('v','m')
  AND pg_get_viewdef(c.oid) ~ '(fn_get_precio|fn_familia_precio)'
UNION ALL
SELECT n.nspname || '.' || p.proname || '(' ||
       pg_get_function_identity_arguments(p.oid) || ')', 'function'
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosrc ~ '(fn_get_precio|fn_familia_precio)'
  AND p.proname NOT IN ('fn_get_precio','fn_familia_precio')
ORDER BY 2, 1;

-- ============================================================================
-- PATCH 49 — doc.articulo_tipo_familia: legacy columns become optional
-- ----------------------------------------------------------------------------
-- articulo_tipo_id/familia_id are being phased out (migration 34 drops them
-- and renames the table to grupo_articulo_familia — see
-- GRUPO_ARTICULO_HANDOFF.md decision 12, still deferred as of 2026-07-20).
-- They are currently NOT NULL, which blocks writing ANY row for a grupo that
-- has no origen_articulo_tipo_id — every grupo_articulo created after the
-- migration/28 seed. Not a permissions gap: a hard schema wall.
--
-- doc.upsert_familia_precio (funciones/facturacion.sql) is the new write
-- path and deliberately never populates these two columns going forward —
-- they're being retired, no point deriving them just to throw away in 34.
-- Existing rows keep their legacy values untouched.
--
-- ⚠ uq_articulo_tipo_familia_default/_cliente stay partial unique indexes on
-- articulo_tipo_id (index swap onto grupo_articulo_id is also part of 34).
-- Postgres unique indexes never treat NULL as equal to NULL, so once rows
-- start landing with articulo_tipo_id NULL, these indexes stop catching
-- duplicates for them entirely. upsert_familia_precio does its own manual
-- dedup on (grupo_articulo_id, tercero_id) for exactly this reason — do not
-- rely on these indexes for new rows.
-- ============================================================================
ALTER TABLE doc.articulo_tipo_familia
    ALTER COLUMN articulo_tipo_id DROP NOT NULL,
    ALTER COLUMN familia_id       DROP NOT NULL;

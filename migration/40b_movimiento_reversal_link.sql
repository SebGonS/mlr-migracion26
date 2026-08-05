-- ═══════════════════════════════════════════════════════════════
-- Step 40b: item_movimientos reversal linkage
-- ---------------------------------------------------------------------
-- Problem: every reversal in the ledger (PROD_CONSUMO_REV, PROD_ING_REV,
-- PROD_SCRAP_REV, AJUSTE_POS/NEG counter-postings, DEV_*_REV, SERV_*_REV)
-- was only ever tied to the row it cancels by shared context — same
-- documento_tipo/documento_id/motivo_id — never a direct pointer. That's
-- workable for signed-SUM aggregates (reporte.vw_matizado nets correctly
-- without it), but it means "which exact movement did this reversal
-- cancel?" can only be answered by inference/ordering, not a JOIN. That
-- same gap is the root cause behind the known reproceso-reversal bug
-- (mover_lotes_reproceso reverses to the flat root instead of the true
-- immediate source — see REPROCESO_GENEALOGY_TODO.md).
--
-- Fix: a self-referencing FK at the LINE level (mirrors SAP's own
-- material-document reversal pattern: MSEG carries SMBLN + SMBLP,
-- reversed-document + reversed-document's item — a per-line pointer,
-- not just a header-level "this doc reverses that doc" link). NULL on
-- original postings; set on reversal rows to the specific original
-- row's id.
--
-- Cost: both directions are indexed seeks, not scans —
--   reversal → original: PK lookup on item_movimientos.id (already indexed).
--   original → its reversal: needs its own index (FKs don't get one for
--   free on the child column) — added below.
--
-- Populated by: funciones/reversiones.sql (anular_cuadre_ejecutado,
-- calidad.revertir_baja_lote), funciones/mes.sql (corregir_matizado,
-- anular_produccion), funciones/devoluciones.sql (anular_devolucion_*).
-- Left NULL where a reversal nets multiple original rows into one FK
-- target ambiguously (see anular_produccion step 6 comment) rather than
-- picking one arbitrarily.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE inventario.item_movimientos
    ADD COLUMN IF NOT EXISTS reversion_movimiento_id BIGINT
        REFERENCES inventario.item_movimientos(id);

COMMENT ON COLUMN inventario.item_movimientos.reversion_movimiento_id IS
    'NULL on original postings. On a reversal row, points at the specific original movement it cancels (line-level, not header-level — mirrors SAP MSEG SMBLN+SMBLP). Left NULL when a single reversal nets multiple original rows.';

-- original → its reversal(s). Sparse (most rows are NULL / not indexed by
-- default), cheap, and makes "was this movement ever reversed?" a seek.
--
-- NOTE: on a live DB prefer CREATE INDEX CONCURRENTLY (cannot run inside a
-- transaction block; run it separately from the ALTER TABLE above):
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_im_reversion_movimiento
--     ON inventario.item_movimientos (reversion_movimiento_id);
CREATE INDEX IF NOT EXISTS idx_im_reversion_movimiento
    ON inventario.item_movimientos (reversion_movimiento_id);

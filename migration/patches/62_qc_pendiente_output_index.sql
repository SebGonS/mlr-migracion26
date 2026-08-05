-- 62_qc_pendiente_output_index.sql
--
-- Supporting index for calidad.vw_qc_pendiente_output (migration/08_views.sql),
-- whose driving filter is estado_calidad='PENDIENTE' on production-output lotes.
--
-- The predicate MUST scope on BOTH estado_calidad AND documento_tipo, not
-- estado_calidad alone. estado_calidad defaults to 'PENDIENTE' at lote creation,
-- and ingress lotes (documento_tipo='entrega') are input material outside this
-- Path-A output QC — they just sit at PENDIENTE. Measured live (2026-08-01):
-- ~108k entrega/PENDIENTE vs only ~1,042 partida_paso_ejecucion/PENDIENTE.
-- Indexing estado_calidad alone would cover ~half the table (real bloat + write
-- cost on every ingress) for zero benefit; scoping to documento_tipo keeps the
-- index 1:1 with the view's actual driver set (~1k rows) and cheap to maintain
-- (only production-output writes touch it).
--
-- documento_tipo is constant within the partial index (per the predicate), so it
-- need not be a key column — documento_id is the key, for the view's join to
-- mes.partida_paso_ejecucion (pe.id = l.documento_id).
--
-- ⚠ REPLACES an earlier, over-broad version of this index. A prior draft of this
-- patch shipped as (documento_tipo, documento_id) WHERE estado_calidad='PENDIENTE'
-- — that predicate covers ~110k rows (every ingress lote sits at PENDIENTE), so it
-- is maintained on every entrega insert for no benefit. If that index is already
-- live, CREATE INDEX IF NOT EXISTS will NOT replace it (name match = skip), so the
-- DROP below is required to actually swap in the lean predicate.
--
-- Run CONCURRENTLY on a live DB (cannot run inside a transaction block) —
-- see migration/41_reporting_access.sql for the same pattern.
--   DROP INDEX CONCURRENTLY IF EXISTS inventario.idx_lote_pendiente_qc_output;
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_lote_pendiente_qc_output
--     ON inventario.lote (documento_id)
--     WHERE estado_calidad = 'PENDIENTE' AND documento_tipo = 'partida_paso_ejecucion';

DROP INDEX IF EXISTS inventario.idx_lote_pendiente_qc_output;
CREATE INDEX IF NOT EXISTS idx_lote_pendiente_qc_output
    ON inventario.lote (documento_id)
    WHERE estado_calidad = 'PENDIENTE' AND documento_tipo = 'partida_paso_ejecucion';

/*
-- ═══════════════════════════════════════════════════════════════
-- REVERSAL
-- ═══════════════════════════════════════════════════════════════
DROP INDEX IF EXISTS inventario.idx_lote_pendiente_qc_output;
*/

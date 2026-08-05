-- ============================================================================
-- FIX: partida 6464 (rework child of root 5090, PROGRAMADA) has 4 stale
-- partida_componente rows (lotes 122749-122752) that were already legitimately
-- claimed and consumed by sibling reproceso 5947 (root 5090 too) at its
-- TENIDO step (ejecucion 1860, COMPLETADO, no output lote -- pass-through
-- step). These rolls physically no longer exist as free stock and were never
-- actually available to 6464 -- the componente rows are a duplicate/erroneous
-- reservation. Remove them from 6464.
--
-- 5947 is NOT touched -- its consumption is real and its pipeline (TENIDO ->
-- LAVADO_HIDRO -> SECADO done, VOLTEADO/PERCHADO/VOLTEADO/COMPACTADO pending)
-- stays as-is.
-- ============================================================================

-- 1) Remove the stale rows.
DELETE FROM mes.partida_componente
WHERE partida_id = 6464
  AND lote_id IN (122749,122750,122751,122752);

-- 2) Recount 6464's partida_detalle from remaining components (will drop to 0
--    if these were its only componentes -- expected, see note below).
SELECT mes._recount_reproceso_detalle(6464);

-- 3) Refresh 6464's estado_produccion.
SELECT mes.actualizar_estado_partida(6464);

-- ── Verify ───────────────────────────────────────────────────────────────
SELECT * FROM mes.partida_componente WHERE partida_id = 6464;
-- Expect 0 rows -- 6464 now has NO input reserved. It needs the correct
-- source rolls assigned before it can do anything (separate task -- we
-- haven't determined what 6464 SHOULD rework yet).

SELECT id, estado_produccion FROM mes.partida WHERE id = 6464;

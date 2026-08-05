-- ============================================================================
-- RESTORE: the 4 rolls (122749-122752) were correctly reserved to 6464 all
-- along -- 5947 is a FIRST rework attempt (Tenido/Lavado/Secado genuinely
-- completed on them, real history, not reversed), but it failed again before
-- reaching Compactado/output, so the rolls are now on a SECOND rework pass:
-- 6464. Move the componente ownership back to 6464. 5947's paso history
-- stays untouched -- it's real, it just isn't where these rolls currently
-- belong.
-- ============================================================================

UPDATE mes.partida_componente
SET partida_id = 6464
WHERE partida_id = 5947
  AND lote_id IN (122749,122750,122751,122752);

-- Recompute roll-count intent + estado on both affected partidas.
SELECT mes._recount_reproceso_detalle(6464);
SELECT mes.actualizar_estado_partida(6464);
SELECT mes.actualizar_estado_partida(5947);

-- ── Verify ───────────────────────────────────────────────────────────────
SELECT lote_id, partida_id, cantidad_reservada
FROM mes.partida_componente
WHERE lote_id IN (122749,122750,122751,122752);
-- Expect: 4 rows, all partida_id = 6464.

-- Confirm generar_receta's pesaje guard clears for 6464 (these are input
-- rolls already weighed upstream at root 5090 -- pesaje should already exist
-- on the lote regardless of which partida currently owns the componente row).
SELECT pc.lote_id
FROM mes.partida_componente pc
WHERE pc.partida_id = 6464
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows -- if not, that's the actual reason the recipe print failed.

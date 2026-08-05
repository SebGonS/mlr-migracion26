-- ============================================================================
-- FIX: partida 6470 was a reproceso created FROM 6430 (logs_api id 41531:
-- crear_reproceso partida_id=6430, 20 lotes), not from the family root 6168.
-- When 6470 was reversed via mes.anular_reproceso -> mover_lotes_reproceso
-- (logs_api id 41676), the rolls were sent back to v_child.partida_origen_id,
-- which crear_reproceso always sets to the flat family ROOT (6168) rather
-- than the immediate sibling partida they actually came from. Confirmed via
-- debug_6470_reproceso_origin*.sql: all 20 partida_componente rows currently
-- sit on 6168 with fyh_mod = 2026-07-24 15:09:02.39939 (the reversal time).
--
-- Safety checks (debug_6470_safety_check_6430.sql) confirmed:
--   - No existing componente rows on 6430 for these lotes (no collision).
--   - No movements against these lotes since the wrong repoint.
--   - 6430's next paso (id 36735, secuencia 40) is still PENDIENTE — nothing
--     has consumed these rolls since, so a plain reservation repoint is safe.
--
-- estado_calidad was explicitly set to 'REPROCESO' by the anular_reproceso
-- call itself (p_estado_calidad param) — that was an intentional operator
-- choice, not part of the bug, and is left untouched here.
--
-- Root's (6168) partida_detalle intent is never touched by this kind of
-- move (matches mover_lotes_reproceso's own convention of leaving root
-- detalle alone) since 6168 never actually "owned" these rolls at the
-- roll-count-intent level for this rework.
-- ============================================================================

UPDATE mes.partida_componente
SET partida_id = 6430, fyh_mod = NOW()
WHERE partida_id = 6168
  AND lote_id IN (132920,132921,132922,132923,132924,132925,132926,132927,132928,132929,
                  132930,132931,132932,132933,132934,132935,132936,132937,132938,133016);

-- ── Verify ───────────────────────────────────────────────────────────────
SELECT partida_id, lote_id, cantidad_reservada, fyh_mod
FROM mes.partida_componente
WHERE lote_id IN (132920,132921,132922,132923,132924,132925,132926,132927,132928,132929,
                  132930,132931,132932,132933,132934,132935,132936,132937,132938,133016)
ORDER BY lote_id;
-- Expect: 20 rows, all partida_id = 6430.

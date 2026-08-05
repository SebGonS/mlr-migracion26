-- ============================================================================
-- FIX: partida 6495 is a reproceso created FROM 6434 (logs_api id 41596:
-- crear_reproceso partida_id=6434, 12 lotes: 172863-172874), but 6495's
-- partida_origen_id was set to 6400 (the flat family root), because 6434 is
-- itself a rework child of root 6400 (confirmed: 6434 != 6400). This is the
-- same bug shape as 6470 (see fix_6470_repoint_componentes_to_6430.sql):
-- mes.mover_lotes_reproceso would send these rolls back to the flat root
-- (6400) instead of their true immediate source (6434).
--
-- 6495 has NOT been reversed yet (still PLANIFICADA, fyh_elm NULL) — so
-- instead of calling the buggy mes.anular_reproceso/mover_lotes_reproceso
-- and then correcting it, we do the equivalent steps by hand directly
-- against 6434, skipping the bug entirely.
--
-- Verified via debug_6495_safety_check_6434.sql:
--   - Case A input rolls (documento_tipo='entrega', real roll ingress —
--     not a Case B post-final-paso re-dye output).
--   - No existing componente rows on 6434 for these lotes (no collision).
--   - No movements on these lotes since 6495 was created.
--   - 6434's own pasos: 4 COMPLETADO (10-40) + 1 PENDIENTE (50) — still open,
--     safe to receive the reservation back.
--   - 6495's own pasos: all PENDIENTE, nothing started under 6495.
--   - The ONLY calidad.inspeccion row for these lotes on 6434's pasos is the
--     REPROCESO verdict itself (ids 10356-10367, partida_paso_ejecucion_id
--     31785) that pulled them into 6495 — no earlier non-rework verdict
--     exists, so estado_calidad is restored to PENDIENTE (confirmed with
--     user; matches mover_lotes_reproceso's own fallback default).
-- ============================================================================

BEGIN;

-- 1) Move the componente rows back to the TRUE source, 6434 (not root 6400).
UPDATE mes.partida_componente
SET partida_id = 6434, fyh_mod = NOW()
WHERE partida_id = 6495
  AND lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874);

-- 2) Restore estado_calidad to PENDIENTE (no prior non-rework verdict exists).
UPDATE inventario.lote
SET estado_calidad = 'PENDIENTE', fyh_mod = NOW()
WHERE id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874);

-- 3) Hard-delete the erroneous REPROCESO verdict rows on 6434's pasos for
--    these lotes (the verdict that wrongly pulled them into 6495).
DELETE FROM calidad.inspeccion
WHERE id IN (10356,10357,10358,10359,10360,10361,10362,10363,10364,10365,10366,10367);

-- 4) Soft-delete 6495 (full undo — it now has zero rolls).
UPDATE mes.partida
SET estado_produccion = 'CANCELADA', fyh_elm = NOW()
WHERE id = 6495;

-- ── Verify ───────────────────────────────────────────────────────────────
SELECT partida_id, lote_id, cantidad_reservada, fyh_mod
FROM mes.partida_componente
WHERE lote_id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874)
ORDER BY lote_id;
-- Expect: 12 rows, all partida_id = 6434.

SELECT id, estado_calidad FROM inventario.lote
WHERE id IN (172863,172864,172865,172866,172867,172868,172869,172870,172871,172872,172873,172874);
-- Expect: 12 rows, all estado_calidad = 'PENDIENTE'.

SELECT id, estado_produccion, fyh_elm FROM mes.partida WHERE id = 6495;
-- Expect: estado_produccion = 'CANCELADA', fyh_elm set.

-- If everything above looks right: COMMIT;
-- If anything is off:              ROLLBACK;

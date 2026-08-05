-- ============================================================================
-- FIX: move the 16 rolls flagged REPROCESO ("Fuera de tono", inspeccion ids
-- 10328-10343, partida_paso_ejecucion_id=31422) from root partida 6349 into
-- the existing rework child 6469 (partida_origen_id=6349, currently PROGRAMADA).
--
-- These are raw input rolls (Case A of mes.crear_reproceso: already in
-- partida_componente, not PROD_ING output -- confirmed empty in the prior
-- diagnostic), so the move mirrors crear_reproceso's Case A treatment:
--   1) repoint partida_componente rows to the child
--   2) reset estado_calidad to PENDIENTE (rolls re-enter the rework cycle;
--      the REPROCESO verdict stays recorded in calidad.inspeccion)
--   3) recount the child's partida_detalle (roll-count intent) from components
--   4) refresh the child's estado_produccion
-- ============================================================================

-- 1) Move componente rows root -> child.
UPDATE mes.partida_componente
SET partida_id = 6469, fyh_mod = NOW()
WHERE partida_id = 6349
  AND lote_id IN (171149,171150,171151,171152,171153,171154,171155,171156,
                  171157,171158,171159,171160,171161,171162,171163,171164);

-- 2) Reset quality state so rolls enter the rework cycle as pending inspection.
UPDATE inventario.lote
SET estado_calidad = 'PENDIENTE'
WHERE id IN (171149,171150,171151,171152,171153,171154,171155,171156,
             171157,171158,171159,171160,171161,171162,171163,171164);

-- 3) Recompute partida_detalle roll-count intent on the child.
SELECT mes._recount_reproceso_detalle(6469);

-- 4) Refresh estado_produccion on the child now that it has components.
SELECT mes.actualizar_estado_partida(6469);

-- ── Verify ───────────────────────────────────────────────────────────────
SELECT pc.lote_id, pc.partida_id
FROM mes.partida_componente pc
WHERE pc.lote_id IN (171149,171150,171151,171152,171153,171154,171155,171156,
                      171157,171158,171159,171160,171161,171162,171163,171164)
ORDER BY pc.lote_id;
-- Expect all 16 rows with partida_id = 6469.

SELECT id, estado_produccion FROM mes.partida WHERE id IN (6349, 6469);

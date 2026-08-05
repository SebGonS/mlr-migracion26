-- ============================================================================
-- FIX: reverse the PROD_CONSUMO on ejecucion 1860 (5947's Tenido step) for
-- the 4 rolls now reassigned to 6464. This rework attempt (5947) is being
-- abandoned/superseded by a second attempt (6464) -- the consumption itself
-- must be reversed so the rolls can be weighed under 6464 (registrar_pesaje_
-- grupo refuses to weigh a roll that already has a PROD_CONSUMO movement).
--
-- Note: this resets ejecucion 1860 + partida_paso 8271 back to EN_PROCESO.
-- It does NOT touch 5947's paso 2 (Lavado Hidro) / paso 3 (Secado), which
-- stay COMPLETADO -- 5947 will look inconsistent (steps 2-3 done, step 1
-- reopened), which is expected/acceptable for an abandoned rework attempt.
-- Pre-flight guards (no output lotes, no downstream movements, no QC
-- inspection on 1860's output) were already confirmed empty/clear.
-- ============================================================================

SELECT mes.anular_produccion(1860);

-- ── Verify ───────────────────────────────────────────────────────────────
-- The 4 rolls should no longer show a PROD_CONSUMO (net-positive) movement.
SELECT im.lote_id, imt.codigo, im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (122749,122750,122751,122752)
ORDER BY im.lote_id, im.fyh_cre;

SELECT id, estado FROM mes.partida_paso_ejecucion WHERE id = 1860;
SELECT id, secuencia, estado FROM mes.partida_paso WHERE partida_id = 5947 ORDER BY secuencia;

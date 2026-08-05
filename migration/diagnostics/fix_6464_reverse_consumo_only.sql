-- ============================================================================
-- FIX: reverse ONLY the PROD_CONSUMO on ejecucion 1860 for the 4 rolls
-- (122749-122752), WITHOUT touching 5947's paso/ejecucion state (stays
-- COMPLETADO -- the step history is real and untouched). This is a targeted
-- version of what mes.anular_produccion's step 6 does (PROD_CONSUMO_REV),
-- skipping its step 8 (reset ejecucion/paso to EN_PROCESO) since we only
-- want to unblock registrar_pesaje_grupo's "already has production
-- movements" guard, not reopen the step.
--
-- No output-lote reversal needed: confirmed earlier that ejecucion 1860
-- produced zero output lotes.
-- ============================================================================

INSERT INTO inventario.item_movimientos(
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    destino_ubicacion_id, cantidad, documento_tipo, documento_id
)
SELECT
    nextval('inventario.mov_doc_seq'),
    im.item_id,
    im.lote_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV'),
    im.origen_ubicacion_id,   -- restore to where it was consumed from
    im.cantidad,
    'partida_paso_ejecucion',
    1860
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.documento_id = 1860
  AND im.lote_id IN (122749,122750,122751,122752);

-- ── Verify ───────────────────────────────────────────────────────────────
-- Net consumption should now be 0 for each roll.
SELECT im.lote_id,
       SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN -im.cantidad ELSE im.cantidad END) AS net_consumido
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = 1860
  AND im.lote_id IN (122749,122750,122751,122752)
  AND imt.codigo IN ('PROD_CONSUMO','PROD_CONSUMO_REV')
GROUP BY im.lote_id;
-- Expect 0 for all 4.

-- Confirm 5947's paso/ejecucion states are untouched (still COMPLETADO).
SELECT id, estado FROM mes.partida_paso_ejecucion WHERE id = 1860;
SELECT id, secuencia, estado FROM mes.partida_paso WHERE partida_id = 5947 ORDER BY secuencia;

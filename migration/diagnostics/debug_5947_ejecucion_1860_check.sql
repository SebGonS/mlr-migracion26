-- ============================================================================
-- DIAGNOSTIC: pre-flight check before running mes.anular_produccion(1860) to
-- undo 5947's phantom paso-1 execution (per user: 5947 never actually ran;
-- only root partida 5090 has real production). Confirms the anular_produccion
-- guards will pass. Read-only.
-- ============================================================================

-- ── 1. Any output lotes produced BY ejecucion 1860 itself? ──────────────────
SELECT l.id AS lote_id, l.item_id, l.fyh_elm,
       ROUND(l.cantidad::NUMERIC,2) AS kg_lote
FROM inventario.lote l
WHERE l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = 1860;

-- ── 2. Any downstream movements on those output lotes (guard #1)? ───────────
SELECT im.lote_id, imt.codigo, im.documento_tipo, im.documento_id
FROM inventario.lote l
JOIN inventario.item_movimientos im ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = 1860
  AND l.fyh_elm IS NULL
  AND imt.codigo NOT IN ('PROD_ING','PROD_ING_REV');

-- ── 3. Any QC inspection on those output lotes (guard #2)? ──────────────────
SELECT ci.id, ci.lote_id, ci.resultado
FROM inventario.lote l
JOIN calidad.inspeccion ci ON ci.lote_id = l.id
WHERE l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = 1860
  AND l.fyh_elm IS NULL;

-- ── 4. Confirm the 4 rolls' PROD_CONSUMO on 1860 is still net-positive ──────
--     (i.e. not already partially reversed elsewhere).
SELECT im.lote_id,
       SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN -im.cantidad ELSE im.cantidad END) AS net_consumido
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = 1860
  AND im.lote_id IN (122749,122750,122751,122752)
  AND imt.codigo IN ('PROD_CONSUMO','PROD_CONSUMO_REV')
GROUP BY im.lote_id;

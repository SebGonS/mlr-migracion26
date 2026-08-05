-- ============================================================================
-- DIAGNOSTIC: full movement ledger + lote_saldo + header for the 4 zero-stock,
-- no-pesaje componente rolls of partida 6464. Read-only.
-- ============================================================================

-- ── 1. Full movement ledger for these lotes (chronological, per lote) ────────
SELECT
    im.lote_id,
    imt.codigo          AS movimiento,
    im.documento_tipo,
    im.documento_id,
    im.cantidad,
    im.origen_ubicacion_id,
    im.destino_ubicacion_id,
    im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (122749,122750,122751,122752)
ORDER BY im.lote_id, im.fyh_cre;

-- ── 2. Raw lote_saldo rows ────────────────────────────────────────────────
SELECT ls.lote_id, ls.ubicacion_id, ls.cantidad_actual
FROM inventario.lote_saldo ls
WHERE ls.lote_id IN (122749,122750,122751,122752)
ORDER BY ls.lote_id, ls.ubicacion_id;

-- ── 3. Lote header ─────────────────────────────────────────────────────────
SELECT l.id AS lote_id, l.item_id, l.documento_tipo, l.documento_id,
       l.propietario_id, ROUND(l.cantidad::NUMERIC,2) AS kg_lote, l.estado_calidad
FROM inventario.lote l
WHERE l.id IN (122749,122750,122751,122752)
ORDER BY l.id;

-- ── 4. What consumed them (PROD_CONSUMO documento context) ────────────────
SELECT im.lote_id, im.documento_tipo, im.documento_id, pp.partida_id AS consumo_partida_id,
       pp.id AS partida_paso_id, ppe.id AS ejecucion_id, ppe.estado
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
LEFT JOIN mes.partida_paso_ejecucion ppe ON im.documento_tipo = 'partida_paso_ejecucion' AND ppe.id = im.documento_id
LEFT JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE im.lote_id IN (122749,122750,122751,122752)
ORDER BY im.lote_id;

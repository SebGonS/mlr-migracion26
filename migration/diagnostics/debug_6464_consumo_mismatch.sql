-- ============================================================================
-- DIAGNOSTIC: partida 6464's 4 componente rolls (122749-122752) show PROD_ING
-- (produced by ejecucion 8786) then PROD_CONSUMO into ejecucion 1860, which
-- belongs to partida 5947 -- a seemingly unrelated partida. Investigate
-- whether 5947/6464 are actually related (root/rework) or this is a
-- mismatched consumption record. Read-only.
-- ============================================================================

-- ── 1. Both partida headers -- family relationship? ─────────────────────────
SELECT id, partida_origen_id, estado_produccion, tercero_id, fyh_cre, fecha_acordada
FROM mes.partida
WHERE id IN (5947, 6464)
ORDER BY id;

-- ── 2. ejecucion 8786 (producer) -- which partida/paso does IT belong to? ───
SELECT ppe.id AS ejecucion_id, ppe.estado, ppe.fyh_inicio, ppe.fyh_fin,
       pp.id AS partida_paso_id, pp.partida_id, pp.secuencia
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE ppe.id IN (8786, 1860);

-- ── 3. All other rolls consumed by ejecucion 1860 -- is this consumption a ──
--     normal-sized batch, or does it look like these 4 got lumped in wrongly?
SELECT im.lote_id, im.cantidad, l.item_id, l.documento_tipo AS lote_origin_doctype,
       l.documento_id AS lote_origin_docid
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
JOIN inventario.lote l ON l.id = im.lote_id
WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = 1860
ORDER BY im.lote_id;

-- ── 4. All componentes currently reserved to 6464 (full picture, not just ───
--      the 4 zero-stock ones) -- how many total, and do the others check out?
SELECT pc.lote_id, l.item_id, l.documento_tipo, l.documento_id,
       ROUND(l.cantidad::NUMERIC,2) AS kg_lote,
       ROUND(sa.cantidad_disponible::NUMERIC,2) AS kg_disponible
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.vw_stock_lotes sa ON sa.lote_id = l.id
WHERE pc.partida_id = 6464
ORDER BY pc.lote_id;

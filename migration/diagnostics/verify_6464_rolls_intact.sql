-- ============================================================================
-- VERIFY: after deleting 6464's stale partida_componente rows for lotes
-- 122749-122752, confirm the physical lotes and their real (5947) reservation
-- are untouched. Read-only.
-- ============================================================================

-- 1) The lotes themselves still exist, unmodified, not soft-deleted.
SELECT id, item_id, cantidad, fyh_elm
FROM inventario.lote
WHERE id IN (122749,122750,122751,122752);
-- Expect: 4 rows, fyh_elm IS NULL, cantidad = 22.65 each. (fyh_elm NOT NULL
-- would mean soft-deleted -- should not be the case here.)

-- 2) Their full movement ledger is untouched (still PROD_ING + PROD_CONSUMO).
SELECT im.lote_id, imt.codigo, im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (122749,122750,122751,122752)
ORDER BY im.lote_id, im.fyh_cre;

-- 3) They are still correctly reserved to 5947 (the only removal was 6464's
--    duplicate row).
SELECT lote_id, partida_id
FROM mes.partida_componente
WHERE lote_id IN (122749,122750,122751,122752);
-- Expect: 4 rows, all partida_id = 5947.

-- 4) 5947's production state is untouched (still 3 completed steps).
SELECT pp.secuencia, pp.estado, o.codigo, ppe.id AS ejecucion_id, ppe.estado AS ejecucion_estado
FROM mes.partida_paso pp
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 5947
ORDER BY pp.secuencia;

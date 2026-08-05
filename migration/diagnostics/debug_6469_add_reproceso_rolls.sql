-- ============================================================================
-- DIAGNOSTIC: partida 6469 header + current location of the 16 REPROCESO
-- rolls (171149-171164, from calidad.inspeccion partida_paso_ejecucion_id=31422)
-- before moving them in. Read-only.
-- ============================================================================

-- ── 1. partida 6469 header ────────────────────────────────────────────────
SELECT id, partida_origen_id, estado_produccion, tercero_id, grupo_articulo_id,
       color_x_cliente_id, fecha_acordada
FROM mes.partida
WHERE id = 6469;

-- ── 2. Where do these 16 lotes currently live? (partida_componente owner) ───
SELECT pc.lote_id, pc.partida_id AS current_partida_id, p.partida_origen_id,
       p.estado_produccion
FROM mes.partida_componente pc
JOIN mes.partida p ON p.id = pc.partida_id
WHERE pc.lote_id IN (171149,171150,171151,171152,171153,171154,171155,171156,
                      171157,171158,171159,171160,171161,171162,171163,171164)
ORDER BY pc.lote_id;

-- ── 3. Which partida/paso produced them (PROD_ING origin) + current stock ───
SELECT l.id AS lote_id, pp.partida_id AS produced_by_partida, l.item_id,
       ROUND(sa.cantidad_disponible::NUMERIC,2) AS kg_disponible
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
LEFT JOIN inventario.vw_stock_lotes sa ON sa.lote_id = l.id
WHERE l.id IN (171149,171150,171151,171152,171153,171154,171155,171156,
               171157,171158,171159,171160,171161,171162,171163,171164)
ORDER BY l.id;

-- ============================================================================
-- DIAGNOSTIC: partida 6465 componentes (reserved raw rolls) — do they exist in
-- stock, do they have an egress movement, and do they have a pesaje record?
-- Grouped to keep output small. Read-only.
-- ============================================================================

WITH rolls AS (
    SELECT
        pc.lote_id,
        ROUND(sa.cantidad_disponible::NUMERIC, 2)   AS kg_disponible,
        EXISTS (SELECT 1 FROM inventario.pesaje px WHERE px.lote_id = pc.lote_id) AS tiene_pesaje,
        (SELECT imt.codigo
         FROM inventario.item_movimientos im
         JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
         WHERE im.lote_id = pc.lote_id
         ORDER BY im.fyh_cre DESC LIMIT 1)          AS ultimo_movimiento
    FROM mes.partida_componente pc
    LEFT JOIN inventario.vw_stock_lotes sa ON sa.lote_id = pc.lote_id
    WHERE pc.partida_id = 6465
      AND pc.lote_id IS NOT NULL
)
SELECT
    (kg_disponible IS NULL OR kg_disponible = 0)   AS sin_stock,
    tiene_pesaje,
    ultimo_movimiento,
    COUNT(*)                                       AS rollos,
    STRING_AGG(lote_id::text, ',' ORDER BY lote_id) AS lote_ids
FROM rolls
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 3;

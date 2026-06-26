-- ============================================================================
-- 34 · entrega_detalle.compra_detalle_id  (LIPS → EKPO link)
-- ============================================================================
-- Adds the missing line-to-line reference from a delivery line back to the
-- PO line it fulfills. Analogous to SAP LIPS carrying the EKPO reference,
-- and mirrors the documento_linea_id already on item_movimientos (MSEG→LIPS).
--
--   item_movimientos.documento_linea_id → entrega_detalle.id      (MSEG→LIPS)
--   entrega_detalle.compra_detalle_id   → compra_detalle.id       (LIPS→EKPO) ← this patch
--
-- NULL = not assigned to a PO line (orderless receipt, or non-compra entrega).
-- Set by ingresar_compra when it creates the entrega_detalle line, or by
-- vincular_entregas_compra during admin reconciliation (future).
-- ============================================================================

ALTER TABLE doc.entrega_detalle
    ADD COLUMN IF NOT EXISTS compra_detalle_id BIGINT
        REFERENCES doc.compra_detalle(id);


UPDATE doc.compra_detalle cd
SET cantidad_recibida = COALESCE((
    SELECT SUM(im.cantidad)
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE imt.codigo = 'COMPRA_ING'
      AND im.item_id = cd.item_id
      AND im.documento_tipo = 'compra'
      AND im.documento_id = 989
), 0)
WHERE cd.compra_id = 989;


SELECT doc.get_compra(989)
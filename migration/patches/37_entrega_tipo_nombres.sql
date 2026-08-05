-- ═══════════════════════════════════════════════════════════════════════════════
-- 37 · entrega_tipo nombre clarification
-- ───────────────────────────────────────────────────────────────────────────────
-- "Devolución a cliente" vs "Devolución de cliente" was ambiguous in the UI —
-- same word, opposite direction. Rewrite to make direction explicit in the label.
-- No schema changes; nombre only.
-- ═══════════════════════════════════════════════════════════════════════════════

UPDATE doc.entrega_tipo SET nombre = 'Devolución – Envío de crudo a cliente'
WHERE codigo = 'DEVOLUCION_CLIENTE_CRUDO';

UPDATE doc.entrega_tipo SET nombre = 'Devolución – Envío de insumos a proveedor'
WHERE codigo = 'DEVOLUCION_PROVEEDOR';

UPDATE doc.entrega_tipo SET nombre = 'Devolución – Recepción de producto vendido'
WHERE codigo = 'DEVOLUCION_CLIENTE_VENTA';

UPDATE doc.entrega_tipo SET nombre = 'Devolución – Recepción de material de servicio'
WHERE codigo = 'DEVOLUCION_CLIENTE_SERVICIO';

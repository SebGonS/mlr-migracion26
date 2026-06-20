-- ═══════════════════════════════════════════════════════════════
-- Orden de servicio: order / receipt split (compra-style).
--   • orden_servicio_detalle.cantidad_recibida — received counter
--     (mirrors compra_detalle.cantidad_recibida)
--   • SERV_ING_REV movement type — append-only reversal of SERV_ING
--
-- Prerequisite: 23b (lote_rollo_detalle.factura_hilo) — the receipt
-- function references it.
-- After running, redeploy funciones/core.sql (ingresar_orden_servicio,
-- crear_orden_servicio, revertir_recepcion_orden_servicio, get_orden_servicio).
-- ═══════════════════════════════════════════════════════════════

-- ── received counter on the OS line ──────────────────────────────
ALTER TABLE doc.orden_servicio_detalle
    ADD COLUMN cantidad_recibida INT NOT NULL DEFAULT 0;

-- Backfill: rolls already ingressed on creation count as received.
-- Received = live SERV_ING lotes whose movement is stamped with this line.
UPDATE doc.orden_servicio_detalle osd
SET cantidad_recibida = sub.n
FROM (
    SELECT im.documento_linea_id AS detalle_id, COUNT(DISTINCT im.lote_id) AS n
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo t ON t.id = im.item_movimiento_tipo_id
    JOIN inventario.lote l ON l.id = im.lote_id AND l.fyh_elm IS NULL
    WHERE im.documento_tipo = 'orden_servicio'
      AND t.codigo = 'SERV_ING'
      AND im.documento_linea_id IS NOT NULL
    GROUP BY im.documento_linea_id
) sub
WHERE osd.id = sub.detalle_id;

-- ── reversal movement type ───────────────────────────────────────
INSERT INTO inventario.item_movimiento_tipo
(codigo, nombre, categoria, factor, flg_afecta_stock, flg_valorizable, flg_recalcula_costo, req_partner, req_origen, req_destino, descripcion)
VALUES
('SERV_ING_REV', 'Servicio – Anulación Recepción Material', 'PROCESO_EXTERNO', -1, true, false, false, true, true, false,
 'Anulación de recepción de material (reversal de SERV_ING)')
ON CONFLICT (codigo) DO NOTHING;

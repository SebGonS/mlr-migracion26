-- ═══════════════════════════════════════════════════════════════
-- Migration 23: Movement type for admin reversal of scrap
-- Adds PROD_SCRAP_REV, the only new movement type required by
-- funciones/reversiones.sql. All other reversal functions reuse
-- existing PESAJE_POS/NEG and AJUSTE_POS/NEG types.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO inventario.item_movimiento_tipo
(codigo, nombre, categoria, factor, flg_afecta_stock, flg_valorizable, flg_recalcula_costo, req_partner, req_origen, req_destino, descripcion)
VALUES
('PROD_SCRAP_REV', 'Producción – Anulación Baja Calidad', 'PRODUCCION', 1, true, false, false, false, false, true,
 'Anulación de baja de rollo por calidad (reversal de PROD_SCRAP). Solo vía calidad.revertir_baja_lote.');

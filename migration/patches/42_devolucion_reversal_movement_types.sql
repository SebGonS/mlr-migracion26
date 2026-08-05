-- ============================================================================
-- Patch 42: reversal movement types for the devolution RPCs (funciones/devoluciones.sql)
-- ============================================================================
-- registrar_devolucion_cliente / _crudo_cliente / _proveedor post DEV_CLI_ING,
-- SERV_DEV_ING, DEV_CLI_EGR, DEV_PROV_EGR as real, valorizable business events.
-- Those codes cannot double as their own anulación reversal (that would post a
-- second indistinguishable business event instead of a stock-only correction),
-- so this adds a dedicated _REV counterpart for each, following the same
-- pattern already used for SERV_ING_REV / PROD_ING_REV / PROD_CONSUMO_REV:
-- non-valorizable, stock-only, opposite factor, swapped req_origen/req_destino.
--
-- Consumed by doc.anular_devolucion_cliente / _crudo_cliente / _proveedor
-- (funciones/devoluciones.sql).
-- ============================================================================

INSERT INTO inventario.item_movimiento_tipo
(codigo, nombre, categoria, factor, flg_afecta_stock, flg_valorizable, flg_recalcula_costo, req_partner, req_origen, req_destino, descripcion)
VALUES
('DEV_CLI_ING_REV',   'Devolución Cliente – Anulación',            'DEVOLUCION',      -1, true, false, false, true, true,  false, 'Anulación de devolución de cliente (reversal de DEV_CLI_ING)'),
('DEV_CLI_EGR_REV',   'Devolución Cliente – Anulación',            'DEVOLUCION',       1, true, false, false, true, false, true,  'Anulación de devolución de crudo a cliente (reversal de DEV_CLI_EGR)'),
('DEV_PROV_EGR_REV',  'Devolución Proveedor – Anulación',          'DEVOLUCION',       1, true, false, false, true, false, true,  'Anulación de devolución a proveedor (reversal de DEV_PROV_EGR)'),
('SERV_DEV_ING_REV',  'Servicio – Anulación Devolución Material',  'PROCESO_EXTERNO', -1, true, false, false, true, true,  false, 'Anulación de devolución de material de servicio (reversal de SERV_DEV_ING)');

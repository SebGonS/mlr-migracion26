-- ═══════════════════════════════════════════════════════════════
-- Migration 23: documento_linea_id on item_movimientos
-- Adds line-item reference to the ledger (≈ SAP MSEG.EBELP).
-- Nullable — existing rows and docs without line granularity stay NULL.
-- Populated by crear_orden_servicio; extend to crear_guia when billing needs it.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE inventario.item_movimientos
    ADD COLUMN documento_linea_id BIGINT;

-- SELECT distinct guia FROM partida 
-- JOIN cliente ON cliente.id = partida.cliente_id
-- WHERE cliente ILIKE '%MLR%' OR cliente ILIKE '%oswaldo%'

COMMENT ON COLUMN inventario.item_movimientos.documento_linea_id
    IS 'Line item within the source document. Polymorphic: points to orden_servicio_detalle.id, guia_remision_detalle.id, etc. NULL for docs without line-level tracking.';

-- ================================================================
-- Patch 12 — Denormalized receipt/invoice qty on compra_detalle
-- ================================================================
-- Adds cantidad_recibida and cantidad_facturada to doc.compra_detalle.
-- Source of truth remains the ledger (entrega_detalle and
-- factura_proveedor_detalle). These columns are maintained by the
-- compras.sql functions after every link/unlink operation.
-- ================================================================

ALTER TABLE doc.compra_detalle
    ADD COLUMN IF NOT EXISTS cantidad_recibida NUMERIC(12,4) NOT NULL DEFAULT 0;

-- Backfill: received quantities from linked entregas
UPDATE doc.compra_detalle cd
SET cantidad_recibida = COALESCE((
    SELECT SUM(grd.cantidad)
    FROM doc.compra_entrega cgr
    JOIN doc.entrega_detalle grd
        ON grd.entrega_id = cgr.entrega_id
       AND grd.item_id = cd.item_id
    WHERE cgr.compra_id = cd.compra_id
), 0);


ALTER TABLE doc.entrega
    ALTER COLUMN serie       DROP NOT NULL,
    ALTER COLUMN correlativo DROP NOT NULL,
    ADD CONSTRAINT chk_entrega_doc_fields
        CHECK ((serie IS NULL) = (correlativo IS NULL));

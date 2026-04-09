-- ═══════════════════════════════════════════════════════════════
-- Step 16: doc.factura_proveedor_detalle — Supplier invoice lines
-- Depends on: doc.factura_proveedor, item (steps 7, 5)
-- ═══════════════════════════════════════════════════════════════

-- ── doc.factura_proveedor_detalle ─────────────────────────────
-- Per-line detail of a supplier invoice.
-- Authoritative source for item purchase price — use this for
-- recipe cost calculations, not compra_detalle.precio_unitario.
--
-- compra_detalle.precio_unitario remains the estimated/agreed price
-- at the time of purchase registration (which may precede the invoice).
-- This table records what the supplier actually charged.
--
-- A factura_proveedor without detalle rows is still valid for invoices
-- entered as a lump sum — detalle is optional but preferred.
CREATE TABLE IF NOT EXISTS doc.factura_proveedor_detalle (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    factura_proveedor_id BIGINT       NOT NULL REFERENCES doc.factura_proveedor(id),
    item_id              INT          NOT NULL REFERENCES item(id),
    cantidad             NUMERIC(12,4) NOT NULL CHECK (cantidad > 0),
    precio_unitario      NUMERIC(12,4) NOT NULL CHECK (precio_unitario >= 0),
    igv_porcentaje       NUMERIC(5,2)  NOT NULL DEFAULT 18
                             CHECK (igv_porcentaje IN (0, 18)),
    subtotal_linea       NUMERIC(12,2) GENERATED ALWAYS AS
                             (ROUND(cantidad * precio_unitario, 2)) STORED,
    igv_linea            NUMERIC(12,2) GENERATED ALWAYS AS
                             (ROUND(cantidad * precio_unitario * igv_porcentaje / 100, 2)) STORED,
    total_linea          NUMERIC(12,2) GENERATED ALWAYS AS
                             (ROUND(cantidad * precio_unitario * (1 + igv_porcentaje / 100), 2)) STORED,
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW()
);

-- ── RLS & Grants ──────────────────────────────────────────────
ALTER TABLE doc.factura_proveedor_detalle ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comercial_ver" ON doc.factura_proveedor_detalle
    FOR SELECT TO authenticated
    USING (jwt_has_permission('comercial.ver'));

GRANT SELECT ON doc.factura_proveedor_detalle TO authenticated;

-- ── Audit trigger ─────────────────────────────────────────────
CREATE TRIGGER trg_bi_factura_proveedor_detalle_audit
    BEFORE INSERT ON doc.factura_proveedor_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-- ── REVOKEs ───────────────────────────────────────────────────
REVOKE INSERT (usr_cre, fyh_cre) ON doc.factura_proveedor_detalle FROM anon, authenticated;

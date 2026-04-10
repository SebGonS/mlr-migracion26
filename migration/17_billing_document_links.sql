-- ═══════════════════════════════════════════════════════════════
-- Step 17: Billing document links
-- Depends on: migration/07 (partida, guia_remision, factura_detalle),
--             migration/15 (catalogo_precios)
--
-- Completes the SAP-style document graph mirroring the purchase side:
--
--   PURCHASE SIDE (existing):
--     compra ──────────────────────── hub
--       ├── compra_guia_remision ───→ guia_remision (logistics)
--       └── compra_detalle ─────────→ factura_proveedor (financial)
--
--   SALES/SERVICE SIDE (this migration):
--     partida ─────────────────────── hub (service order)
--       ├── partida_guia_remision ──→ guia_remision CLIENTE_ENVIO_PROCESO (ingress)
--       └── factura ────────────────→ financial document
--             ├── factura_guia_remision → guia_remision DESPACHO_CLIENTE (dispatch)
--             └── factura_detalle ─── pure financial charge lines
--
-- Coverage tracking:
--   Unbilled dispatch guias = DESPACHO_CLIENTE guias NOT IN factura_guia_remision.
--   No estado_facturacion flag anywhere — coverage is always derived by query.
--
-- factura_detalle granularity:
--   One row per (operacion × articulo_tipo × color × tenido × antipilling),
--   aggregated across all dispatch guias covered by the invoice.
--   Billing dimensions are denormalized at invoice time so the financial
--   document is self-contained and does not depend on partida state.
-- ═══════════════════════════════════════════════════════════════


-- ── 1. doc.partida_guia_remision ─────────────────────────────
-- N:N junction: service order ↔ ingress guias.
-- Mirrors doc.compra_guia_remision.
-- Authoritative document-layer link — the derivable path
-- (guia_detalle → lote → OP → partida) exists for genealogy
-- but is expensive; this is the query-time anchor.
CREATE TABLE IF NOT EXISTS doc.partida_guia_remision (
    partida_id        BIGINT NOT NULL REFERENCES doc.partida(id),
    guia_remision_id  BIGINT NOT NULL REFERENCES doc.guia_remision(id),
    PRIMARY KEY (partida_id, guia_remision_id),
    usr_cre INT,
    fyh_cre TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE doc.partida_guia_remision ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comercial_ver" ON doc.partida_guia_remision
    FOR SELECT TO authenticated
    USING (jwt_has_permission('comercial.ver'));

GRANT SELECT ON doc.partida_guia_remision TO authenticated;

CREATE TRIGGER trg_bi_partida_guia_remision_audit
    BEFORE INSERT ON doc.partida_guia_remision
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

REVOKE INSERT (usr_cre, fyh_cre) ON doc.partida_guia_remision FROM anon, authenticated;


-- ── 2. doc.factura_guia_remision ──────────────────────────────
-- N:N junction: invoice ↔ dispatch guias (DESPACHO_CLIENTE).
-- One invoice can cover multiple dispatch guias; one dispatch
-- guia appears on at most one invoice (enforced by UNIQUE below).
--
-- This is the billing coverage anchor:
--   unbilled dispatch guias = guias of type DESPACHO_CLIENTE
--   where id NOT IN (SELECT guia_remision_id FROM factura_guia_remision)
CREATE TABLE IF NOT EXISTS doc.factura_guia_remision (
    factura_id        BIGINT NOT NULL REFERENCES doc.factura(id),
    guia_remision_id  BIGINT NOT NULL REFERENCES doc.guia_remision(id),
    PRIMARY KEY (factura_id, guia_remision_id),
    -- A dispatch guia can only be billed once
    CONSTRAINT uq_guia_billed_once UNIQUE (guia_remision_id),
    usr_cre INT,
    fyh_cre TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE doc.factura_guia_remision ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comercial_ver" ON doc.factura_guia_remision
    FOR SELECT TO authenticated
    USING (jwt_has_permission('comercial.ver'));

GRANT SELECT ON doc.factura_guia_remision TO authenticated;

CREATE TRIGGER trg_bi_factura_guia_remision_audit
    BEFORE INSERT ON doc.factura_guia_remision
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

REVOKE INSERT (usr_cre, fyh_cre) ON doc.factura_guia_remision FROM anon, authenticated;


-- ── 3. doc.factura_detalle — billing dimension columns ────────
-- Pure financial charge lines. No guia FK here — the logistics
-- link lives in factura_guia_remision above.
--
-- operacion_id: which service is being charged (TENIDO, PLANCHADO...).
--   NULL for ad-hoc lines.
--
-- es_antipilling: true for the antipilling surcharge line.
--   Distinguishes it from the base TENIDO line on the same invoice
--   when both share the same operacion_id.
--
-- Billing dimensions — denormalized from partida at invoice creation
-- time so the financial document is self-contained:
--   articulo_tipo_id  — what material was processed
--   color_x_cliente_id — client's specific color
--   tenido_id         — dye recipe applied (NULL for non-dyeing ops)
--
-- partida_id (existing column): retained for traceability/genealogy.
--   Nullable: ad-hoc lines and multi-partida aggregations leave it NULL.
ALTER TABLE doc.factura_detalle
    ADD COLUMN IF NOT EXISTS operacion_id       SMALLINT REFERENCES mes.operacion(id),
    ADD COLUMN IF NOT EXISTS es_antipilling     BOOLEAN  NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS articulo_tipo_id   SMALLINT REFERENCES articulo_tipo(id),
    ADD COLUMN IF NOT EXISTS color_x_cliente_id INT      REFERENCES color_x_cliente(id),
    ADD COLUMN IF NOT EXISTS tenido_id          INT      REFERENCES tenido(id);

-- Index to support description auto-generation and grouping queries
-- on the invoice review screen.
CREATE INDEX IF NOT EXISTS idx_factura_detalle_dims
    ON doc.factura_detalle (operacion_id, articulo_tipo_id, color_x_cliente_id)
    WHERE operacion_id IS NOT NULL;

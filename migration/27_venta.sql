-- ═══════════════════════════════════════════════════════════════════════════
-- migration/27_venta.sql
-- ═══════════════════════════════════════════════════════════════════════════
-- doc.venta — the COMMERCIAL SPINE (sales hub) that MLR was missing.
--
-- The outbound mirror of doc.compra. The deal layer, not the invoice layer:
--
--     inbound   compra  ──▶ factura_proveedor   (invoice)
--     outbound  venta   ──▶ factura             (invoice)   ← factura stays dormant
--
-- Analogous to SAP VBAK (sales order) / Odoo sale.order — NOT to doc.factura,
-- which is the billing document (VBRK / account.move). The hub ties together:
--
--     doc.venta ── the sale (spine)
--         ├── doc.entrega    (guia / delivery)     via entrega.venta_id
--         ├── sales factura  (MLR's own invoice)   via factura_serie/numero  [REFERENCE only, 1:1]
--         └── mes.partida    (the job/intent)      via venta_detalle.partida_id + lote genealogy
--
-- MLR does NOT emit its own facturas (the external .NET system + SUNAT own that).
-- The invoice is REFERENCED, never reproduced: no IGV, no SUNAT push, no AR here.
-- doc.factura + migration/26 (cobranza) stay DORMANT; if in-house emission is ever
-- turned on, a doc.factura is GENERATED FROM this hub — the hub is upstream.
--
-- Lifecycle: born at DISPATCH (first moment which-lotes / what-price / factura become
-- known). MLR delivers a sale all at once → one guía, one factura. The factura ref is
-- NULL while ABIERTA and filled when the factura is emitted (→ FACTURADA).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$ BEGIN
    CREATE TYPE venta_estado_enum AS ENUM ('ABIERTA', 'FACTURADA', 'ANULADA');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Line nature — a REFLECTION of the ledger's ownership split, never an independent
-- decision. lote.propietario_id is the single source of truth; registrar_despacho
-- derives both the movement type and this from it, so they cannot disagree:
--   SERVICIO → client-owned rolls (propietario_id <> 1) → SERV_EGR  (PROCESO_EXTERNO, non-valorized, no COGS)
--   VENTA    → MLR-owned rolls    (propietario_id  = 1) → VENTA_EGR (VENTA, valorized, COGS)
DO $$ BEGIN
    CREATE TYPE venta_linea_tipo_enum AS ENUM ('SERVICIO', 'VENTA');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── doc.venta ───────────────────────────────────────────────────────────────
-- Header / hub. One per commercial sale (≈ one external factura's worth of work).
-- Client + external invoice REFERENCE + status. No internal correlativo (as with
-- doc.compra); amounts live on the detalle.
CREATE TABLE doc.venta (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tercero_id          INT  NOT NULL REFERENCES tercero(id),
    fecha               DATE NOT NULL DEFAULT CURRENT_DATE,   -- commercial/opening date (first dispatch)

    -- The sales factura REFERENCE — MLR's own invoice, emitted in the external system
    -- (SUNAT lives there), referenced here, never reproduced. 1:1 with the venta: a
    -- sale ships all at once → one guía, one factura. NULL while ABIERTA; filled at
    -- emission (→ FACTURADA).
    factura_serie       TEXT,
    factura_numero      INT,
    factura_fecha_venc  DATE,

    estado              venta_estado_enum NOT NULL DEFAULT 'ABIERTA',
    observacion         TEXT,

    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    flg_elm BOOLEAN NOT NULL DEFAULT false,
    usr_elm INT, fyh_elm TIMESTAMPTZ,

    -- Both present together or neither (mirrors chk_entrega_doc_fields).
    CONSTRAINT chk_venta_factura_fields CHECK ((factura_serie IS NULL) = (factura_numero IS NULL))
);

-- MLR's own correlative → a given factura maps to exactly one venta.
CREATE UNIQUE INDEX uq_venta_factura
    ON doc.venta (factura_serie, factura_numero) WHERE factura_serie IS NOT NULL;

CREATE INDEX idx_venta_tercero ON doc.venta (tercero_id);
CREATE INDEX idx_venta_abierta ON doc.venta (estado) WHERE estado = 'ABIERTA';

CREATE TRIGGER trg_biud_venta_audit
    BEFORE INSERT OR UPDATE OR DELETE ON doc.venta
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_venta_cre
    BEFORE INSERT ON doc.venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_venta_mod
    BEFORE UPDATE ON doc.venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();


-- ── doc.venta_detalle ───────────────────────────────────────────────────────
-- Charge lines: one per billable operation on the sale (TENIDO, TERMOFIJADO,
-- PERCHADO, ANTIPILLING surcharge…). The dispatch user's "sum of prices".
--
-- SNAPSHOT BOUNDARY — a billing line is a FROZEN record of a transaction, so it
-- freezes everything that defines the charge and determined its price:
--   • precio_kg / cantidad_kg          — the charge itself (price is user-adjusted, catalog drifts).
--   • color_x_cliente / tenido / articulo_tipo / flg_antipilling — the billing dims that
--     keyed the price, snapshot from the partida's intent at dispatch (mirrors doc.factura_detalle).
-- This keeps the line coherent and self-contained even if the partida is later edited —
-- billing never leans on live master data, and the partida stays free to change.
-- Only NON-pricing spec (ancho, rendimiento) and fibra (intrinsic to the article) stay
-- derived — composed into the description at display time, never stored here.
CREATE TABLE doc.venta_detalle (
    id              BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venta_id        BIGINT   NOT NULL REFERENCES doc.venta(id),
    linea           SMALLINT NOT NULL DEFAULT 1,

    -- Ownership: tipo mirrors lote.propietario_id (SERVICIO = client's material,
    -- VENTA = MLR's) — the same fact that picks SERV_EGR vs VENTA_EGR.
    tipo            venta_linea_tipo_enum NOT NULL DEFAULT 'SERVICIO',
    operacion_id    SMALLINT REFERENCES mes.operacion(id),   -- what is billed (→ catalogo_precios); antipilling surcharge = its own operacion
    item_id         INT      REFERENCES item(id),            -- sale lines: the product (NULL on service lines)

    -- Billing dims — SNAPSHOT from the partida's intent at dispatch (see boundary note).
    color_x_cliente_id  INT      REFERENCES color_x_cliente(id),
    tenido_id           INT      REFERENCES tenido(id),
    articulo_tipo_id    SMALLINT REFERENCES articulo_tipo(id),
    flg_antipilling     BOOLEAN  NOT NULL DEFAULT false,        -- pricing dim (catalogo key); the surcharge itself is its own operacion line

    -- The INTENT partida this line bills — the PARENT of any rework chain
    -- (partida_origen_id IS NULL). Billing is against what the client ordered;
    -- reworks are NOT billed separately (MLR absorbs them), and any divergence
    -- (e.g. a batch re-dyed to black) is handled by the manually-set price, not by
    -- pointing at the child. Terminal/fulfillment output is a dispatch-tracking
    -- concern, not this column.
    -- Nullable for ad-hoc lines (mirrors doc.factura_detalle.partida_id).
    partida_id      BIGINT   REFERENCES mes.partida(id),

    descripcion     TEXT,    -- optional human label; derived/generated when blank

    -- Snapshot charge (USD — MLR bills exclusively in USD, as with catalogo_precios).
    cantidad_kg     NUMERIC(12,4) NOT NULL CHECK (cantidad_kg > 0),   -- frozen basis
    precio_kg       NUMERIC(12,4) NOT NULL CHECK (precio_kg >= 0),    -- frozen rate
    importe         NUMERIC(12,2) GENERATED ALWAYS AS (ROUND(cantidad_kg * precio_kg, 2)) STORED,

    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (venta_id, linea)
);

CREATE INDEX idx_venta_detalle_venta   ON doc.venta_detalle (venta_id);
CREATE INDEX idx_venta_detalle_partida ON doc.venta_detalle (partida_id);

CREATE TRIGGER trg_biud_venta_detalle_audit
    BEFORE INSERT OR UPDATE OR DELETE ON doc.venta_detalle
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();


-- ── doc.entrega.venta_id ────────────────────────────────────────────────────
-- The structural link. MLR delivers a sale all at once (one guía, one factura),
-- so this is effectively 1:1 in practice — but modeled as a plain FK on entrega
-- (not an M:N junction like doc.compra_entrega) since a dispatch entrega belongs
-- to exactly one sale by construction; a receipt entrega, by contrast, can be
-- shared across compras. This, plus the factura ref on the header, ties guía and
-- factura together through the spine. Nullable: an entrega may exist before
-- attachment, and non-commercial entregas never get one.
ALTER TABLE doc.entrega
    ADD COLUMN venta_id BIGINT REFERENCES doc.venta(id);

CREATE INDEX idx_entrega_venta ON doc.entrega (venta_id);


-- ── Grants & RLS (mirrors the commercial module in migration/26) ─────────────
ALTER TABLE doc.venta         ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.venta_detalle ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON doc.venta         TO authenticated;
GRANT SELECT, INSERT, UPDATE ON doc.venta_detalle TO authenticated;

-- Reads gated by the commercial permission; writes go through the dispatch
-- function (SECURITY DEFINER), consistent with the rest of the doc flows.
DROP POLICY IF EXISTS "comercial_ver" ON doc.venta;
DROP POLICY IF EXISTS "comercial_ver" ON doc.venta_detalle;
CREATE POLICY "comercial_ver" ON doc.venta
    FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.venta_detalle
    FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));

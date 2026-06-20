-- ═══════════════════════════════════════════════════════════════
-- Migration 26: Tesorería + Cobranza (Layer A — AR & cash)
-- ───────────────────────────────────────────────────────────────
-- Closes the two sub-ledger gaps that the operational system cannot
-- live without, independent of any future general-ledger decision:
--
--   1. AR / collections — customer payments against doc.factura.
--      Today doc.factura has no estado_pago and no payment document,
--      so "who owes us money" is unanswerable. This mirrors the AP
--      design (doc.letra / doc.letra_factura) on the customer side.
--
--   2. Treasury — where the money actually lands. cuenta_financiera
--      (caja/bancos) + an append-only movimiento ledger. Every cobro,
--      supplier payment, and paid letra posts a row here.
--
-- AP symmetry: a supplier invoice could only be settled via a letra.
-- Cash/transfer payments to suppliers had no representation, so this
-- migration also adds doc.pago_proveedor (the cash counterpart of a
-- letra). pagar_letra is extended (in funciones/compras.sql) to post a
-- treasury EGRESO when a paying account is supplied.
--
-- Scope deliberately EXCLUDES: general ledger / chart of accounts /
-- journal entries, SUNAT electronic books, letras por cobrar (customer
-- letras — add later if customers start accepting them). See
-- REVERSIONES_FRONTEND_SPEC.md sibling docs for layering rationale.
--
-- Run once against the live DB. Idempotent where practical.
-- ═══════════════════════════════════════════════════════════════

-- ── Enums ──────────────────────────────────────────────────────
DO $$ BEGIN
    CREATE TYPE tesoreria_cuenta_tipo_enum AS ENUM ('CAJA', 'BANCO');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE tesoreria_mov_tipo_enum AS ENUM ('INGRESO', 'EGRESO');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE medio_pago_enum AS ENUM (
        'EFECTIVO', 'TRANSFERENCIA', 'DEPOSITO', 'CHEQUE', 'LETRA', 'OTRO'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Lifecycle of a cobro / pago document (the cash settlement doc).
-- reuses the same two states for both AR and AP cash payments.
DO $$ BEGIN
    CREATE TYPE liquidacion_estado_enum AS ENUM ('registrado', 'anulado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── doc.factura.estado_pago ────────────────────────────────────
-- Mirrors factura_proveedor.estado_pago. Maintained by
-- doc.recalcular_estado_pago_factura() — never written by clients.
-- Amount-based (sum of applied cobros), unlike the AP side which is
-- letra-state-based; the customer side has no instrument lifecycle.
ALTER TABLE doc.factura
    ADD COLUMN IF NOT EXISTS estado_pago estado_pago_enum NOT NULL DEFAULT 'pendiente';

-- ═══════════════════════════════════════════════════════════════
-- TREASURY SCHEMA
-- ═══════════════════════════════════════════════════════════════
CREATE SCHEMA IF NOT EXISTS tesoreria;
GRANT USAGE ON SCHEMA tesoreria TO authenticated;

-- ── tesoreria.cuenta_financiera ────────────────────────────────
-- Caja and bank accounts. The account's own currency is authoritative
-- (a soles caja, a USD bank account, etc.) — set moneda explicitly per
-- account; there is no default because MLR runs both PEN and USD.
CREATE TABLE tesoreria.cuenta_financiera (
    id            INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo        TEXT NOT NULL UNIQUE,
    codigo_canon  TEXT NOT NULL UNIQUE,
    nombre        TEXT NOT NULL,
    tipo          tesoreria_cuenta_tipo_enum NOT NULL,
    moneda        CHAR(3) NOT NULL,
    banco         TEXT,                 -- NULL for CAJA
    numero_cuenta TEXT,                 -- bank account number; NULL for CAJA
    cci           TEXT,                 -- interbank code (CCI)
    flg_activo    BOOLEAN NOT NULL DEFAULT true,
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    usr_elm INT, fyh_elm TIMESTAMPTZ,
    CONSTRAINT chk_cuenta_banco CHECK (
        tipo = 'CAJA' OR banco IS NOT NULL
    )
);

-- ── tesoreria.movimiento ───────────────────────────────────────
-- Append-only cash/bank ledger. One row per inflow/outflow.
-- Polymorphic source via (documento_tipo, documento_id):
--   'cobro' | 'pago_proveedor' | 'letra' | 'manual'
-- Never UPDATE/DELETE — reversals post a counter-movement.
CREATE TABLE tesoreria.movimiento (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cuenta_financiera_id INT NOT NULL REFERENCES tesoreria.cuenta_financiera(id),
    tipo                 tesoreria_mov_tipo_enum NOT NULL,
    fecha                DATE NOT NULL DEFAULT CURRENT_DATE,
    monto                NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    moneda               CHAR(3) NOT NULL,
    tipo_cambio          NUMERIC(10,4),
    medio_pago           medio_pago_enum,
    referencia           TEXT,            -- operation / voucher number
    documento_tipo       TEXT,
    documento_id         BIGINT,
    glosa                TEXT,
    flg_conciliado       BOOLEAN NOT NULL DEFAULT false,
    fyh_conciliacion     TIMESTAMPTZ,
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ
);

CREATE INDEX idx_tes_mov_cuenta ON tesoreria.movimiento (cuenta_financiera_id);
CREATE INDEX idx_tes_mov_doc    ON tesoreria.movimiento (documento_tipo, documento_id);
CREATE INDEX idx_tes_mov_fecha  ON tesoreria.movimiento (fecha);

-- ═══════════════════════════════════════════════════════════════
-- AR — COBRANZA (customer collections)
-- ═══════════════════════════════════════════════════════════════

-- ── doc.cobro ──────────────────────────────────────────────────
-- Customer payment receipt. Mirrors doc.letra on the AR side, but a
-- cobro is actual money (it posts to tesoreria), not a credit promise.
-- tercero_id: the client who paid. cuenta_financiera_id: where it landed
--   (nullable only for medio_pago that doesn't touch an account yet).
CREATE TABLE doc.cobro (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tercero_id           INT NOT NULL REFERENCES tercero(id),
    fecha                DATE NOT NULL DEFAULT CURRENT_DATE,
    medio_pago           medio_pago_enum NOT NULL DEFAULT 'TRANSFERENCIA',
    cuenta_financiera_id INT REFERENCES tesoreria.cuenta_financiera(id),
    monto                NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    moneda               CHAR(3) NOT NULL DEFAULT 'USD',
    tipo_cambio          NUMERIC(10,4),
    referencia           TEXT,
    observacion          TEXT,
    estado               liquidacion_estado_enum NOT NULL DEFAULT 'registrado',
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    usr_elm INT, fyh_elm TIMESTAMPTZ
);

-- ── doc.cobro_factura ──────────────────────────────────────────
-- Clearing: applies a portion of a cobro to a customer factura.
-- One cobro → N facturas; one factura → N cobros (M:M with amount).
-- Invariant (enforced by registrar_cobro): SUM(monto_aplicado) per
-- cobro ≤ cobro.monto.
CREATE TABLE doc.cobro_factura (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cobro_id       BIGINT NOT NULL REFERENCES doc.cobro(id),
    factura_id     BIGINT NOT NULL REFERENCES doc.factura(id),
    monto_aplicado NUMERIC(12,2) NOT NULL CHECK (monto_aplicado > 0),
    UNIQUE (cobro_id, factura_id),
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_cobro_factura_factura ON doc.cobro_factura (factura_id);

-- ═══════════════════════════════════════════════════════════════
-- AP SYMMETRY — supplier cash payments (the letra counterpart)
-- ═══════════════════════════════════════════════════════════════

-- ── doc.pago_proveedor ─────────────────────────────────────────
-- Cash/transfer payment to a supplier. The non-letra way to settle a
-- factura_proveedor. Structurally identical to doc.cobro (opposite
-- direction). Posts a tesoreria EGRESO.
CREATE TABLE doc.pago_proveedor (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tercero_id           INT NOT NULL REFERENCES tercero(id),
    fecha                DATE NOT NULL DEFAULT CURRENT_DATE,
    medio_pago           medio_pago_enum NOT NULL DEFAULT 'TRANSFERENCIA',
    cuenta_financiera_id INT REFERENCES tesoreria.cuenta_financiera(id),
    monto                NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    moneda               CHAR(3) NOT NULL DEFAULT 'USD',
    tipo_cambio          NUMERIC(10,4),
    referencia           TEXT,
    observacion          TEXT,
    estado               liquidacion_estado_enum NOT NULL DEFAULT 'registrado',
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    usr_elm INT, fyh_elm TIMESTAMPTZ
);

CREATE TABLE doc.pago_proveedor_factura (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pago_id              BIGINT NOT NULL REFERENCES doc.pago_proveedor(id),
    factura_proveedor_id BIGINT NOT NULL REFERENCES doc.factura_proveedor(id),
    monto_aplicado       NUMERIC(12,2) NOT NULL CHECK (monto_aplicado > 0),
    UNIQUE (pago_id, factura_proveedor_id),
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_pago_prov_factura ON doc.pago_proveedor_factura (factura_proveedor_id);

-- NOTE: factura_proveedor.estado_pago becomes amount-aware once cash
-- payments exist. doc.recalcular_estado_pago_factura_proveedor()
-- (funciones/compras.sql) reconciles BOTH letras and pagos. The legacy
-- letra-only cascade in pagar_letra is replaced by that helper.

-- ═══════════════════════════════════════════════════════════════
-- TRIGGERS — audit + cre/mod/elm + codigo_canon
-- ═══════════════════════════════════════════════════════════════

-- cuenta_financiera (catalog-like: has codigo/codigo_canon)
CREATE TRIGGER trg_bi_cuenta_fin_canon  BEFORE INSERT ON tesoreria.cuenta_financiera
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
CREATE TRIGGER trg_bi_cuenta_fin_cre    BEFORE INSERT ON tesoreria.cuenta_financiera
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_cuenta_fin_mod    BEFORE UPDATE ON tesoreria.cuenta_financiera
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_cuenta_fin_elm    BEFORE UPDATE ON tesoreria.cuenta_financiera
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

-- movimiento (append-only ledger; audit + cre)
CREATE TRIGGER trg_biud_tes_mov_audit   BEFORE INSERT OR UPDATE OR DELETE ON tesoreria.movimiento
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_tes_mov_cre       BEFORE INSERT ON tesoreria.movimiento
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-- cobro
CREATE TRIGGER trg_biud_cobro_audit     BEFORE INSERT OR UPDATE OR DELETE ON doc.cobro
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_cobro_cre         BEFORE INSERT ON doc.cobro
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_cobro_mod         BEFORE UPDATE ON doc.cobro
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_cobro_elm         BEFORE UPDATE ON doc.cobro
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

CREATE TRIGGER trg_bi_cobro_factura_cre BEFORE INSERT ON doc.cobro_factura
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-- pago_proveedor
CREATE TRIGGER trg_biud_pago_prov_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.pago_proveedor
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_pago_prov_cre     BEFORE INSERT ON doc.pago_proveedor
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_pago_prov_mod     BEFORE UPDATE ON doc.pago_proveedor
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_pago_prov_elm     BEFORE UPDATE ON doc.pago_proveedor
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

CREATE TRIGGER trg_bi_pago_prov_fac_cre BEFORE INSERT ON doc.pago_proveedor_factura
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-- ═══════════════════════════════════════════════════════════════
-- RLS — SELECT gated by comercial.ver (writes go through functions)
-- ═══════════════════════════════════════════════════════════════
ALTER TABLE tesoreria.cuenta_financiera ENABLE ROW LEVEL SECURITY;
ALTER TABLE tesoreria.movimiento        ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.cobro                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.cobro_factura           ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.pago_proveedor          ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.pago_proveedor_factura  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "comercial_ver" ON tesoreria.cuenta_financiera;
DROP POLICY IF EXISTS "comercial_ver" ON tesoreria.movimiento;
DROP POLICY IF EXISTS "comercial_ver" ON doc.cobro;
DROP POLICY IF EXISTS "comercial_ver" ON doc.cobro_factura;
DROP POLICY IF EXISTS "comercial_ver" ON doc.pago_proveedor;
DROP POLICY IF EXISTS "comercial_ver" ON doc.pago_proveedor_factura;

-- cuenta_financiera is also a dropdown source (which account to pay from),
-- so any authenticated user with comercial.ver can read it.
CREATE POLICY "comercial_ver" ON tesoreria.cuenta_financiera FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON tesoreria.movimiento        FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.cobro                   FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.cobro_factura           FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.pago_proveedor          FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.pago_proveedor_factura  FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));

-- Account management (create/edit bank accounts) = plant infrastructure.
CREATE POLICY "config_oper_insert" ON tesoreria.cuenta_financiera FOR INSERT TO authenticated WITH CHECK (jwt_has_permission('configuracion.operacional'));
CREATE POLICY "config_oper_update" ON tesoreria.cuenta_financiera FOR UPDATE TO authenticated USING (jwt_has_permission('configuracion.operacional'));

-- ── Grants ─────────────────────────────────────────────────────
GRANT SELECT ON tesoreria.cuenta_financiera TO authenticated;
GRANT SELECT ON tesoreria.movimiento        TO authenticated;
GRANT SELECT ON doc.cobro                   TO authenticated;
GRANT SELECT ON doc.cobro_factura           TO authenticated;
GRANT SELECT ON doc.pago_proveedor          TO authenticated;
GRANT SELECT ON doc.pago_proveedor_factura  TO authenticated;
-- cuenta_financiera direct INSERT/UPDATE allowed (RLS-gated) for catalog UX.
GRANT INSERT, UPDATE ON tesoreria.cuenta_financiera TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VIEWS
-- ═══════════════════════════════════════════════════════════════

-- ── tesoreria.vw_saldos_cuentas ────────────────────────────────
-- Current balance per financial account (INGRESO − EGRESO).
CREATE OR REPLACE VIEW tesoreria.vw_saldos_cuentas AS
SELECT
    cf.id,
    cf.codigo,
    cf.nombre,
    cf.tipo,
    cf.moneda,
    cf.banco,
    cf.numero_cuenta,
    cf.flg_activo,
    COALESCE(SUM(m.monto) FILTER (WHERE m.tipo = 'INGRESO'), 0)
      - COALESCE(SUM(m.monto) FILTER (WHERE m.tipo = 'EGRESO'), 0) AS saldo
FROM tesoreria.cuenta_financiera cf
LEFT JOIN tesoreria.movimiento m ON m.cuenta_financiera_id = cf.id
WHERE cf.fyh_elm IS NULL
GROUP BY cf.id, cf.codigo, cf.nombre, cf.tipo, cf.moneda,
         cf.banco, cf.numero_cuenta, cf.flg_activo;

GRANT SELECT ON tesoreria.vw_saldos_cuentas TO authenticated;

-- ── tesoreria.vw_movimientos ───────────────────────────────────
-- Hydrated cash ledger: account name + signed amount for reporting.
CREATE OR REPLACE VIEW tesoreria.vw_movimientos AS
SELECT
    m.id,
    m.cuenta_financiera_id,
    cf.codigo                                         AS cuenta_codigo,
    cf.nombre                                         AS cuenta_nombre,
    m.tipo,
    m.fecha,
    m.monto,
    CASE WHEN m.tipo = 'INGRESO' THEN m.monto ELSE -m.monto END AS monto_signed,
    m.moneda,
    m.tipo_cambio,
    m.medio_pago,
    m.referencia,
    m.documento_tipo,
    m.documento_id,
    m.glosa,
    m.flg_conciliado,
    m.fyh_conciliacion,
    m.fyh_cre,
    m.usr_cre
FROM tesoreria.movimiento m
JOIN tesoreria.cuenta_financiera cf ON cf.id = m.cuenta_financiera_id;

GRANT SELECT ON tesoreria.vw_movimientos TO authenticated;

-- ── doc.vw_cobros ──────────────────────────────────────────────
-- Hydrated list view for customer receipts. Mirrors doc.vw_letras.
CREATE OR REPLACE VIEW doc.vw_cobros AS
SELECT
    c.id,
    c.tercero_id,
    t.nombre                                              AS cliente_nombre,
    c.fecha,
    c.medio_pago,
    c.cuenta_financiera_id,
    cf.nombre                                             AS cuenta_nombre,
    c.monto,
    c.moneda,
    c.tipo_cambio,
    c.referencia,
    c.observacion,
    c.estado,
    COALESCE(ap.total_facturas, 0)                        AS total_facturas,
    COALESCE(ap.monto_aplicado_total, 0)                  AS monto_aplicado_total,
    c.monto - COALESCE(ap.monto_aplicado_total, 0)        AS monto_libre,
    c.fyh_cre,
    c.usr_cre
FROM doc.cobro c
JOIN tercero t                       ON t.id = c.tercero_id
LEFT JOIN tesoreria.cuenta_financiera cf ON cf.id = c.cuenta_financiera_id
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_facturas, SUM(cofa.monto_aplicado) AS monto_aplicado_total
    FROM doc.cobro_factura cofa
    WHERE cofa.cobro_id = c.id
) ap ON true
WHERE c.fyh_elm IS NULL;

GRANT SELECT ON doc.vw_cobros TO authenticated;

-- ── doc.vw_cuentas_por_cobrar ──────────────────────────────────
-- Combined AR view: one row per (factura, cobro) clearing pair.
-- Mirror of doc.vw_cuentas_por_pagar.
--
--   • Facturas with no cobro yet → 1 row, all cobro_* columns NULL
--   • Facturas with N cobros     → N rows, one per cobro
--
-- factura_saldo = total minus ALL non-anulado cobros on that factura
-- (computed via lateral, not from this row's monto_aplicado alone).
--
-- Common filters:
--   AR aging       : estado_pago NOT IN ('total','anulado') ORDER BY factura_dias_vencido DESC
--   Unapplied      : cobro_id IS NULL AND estado_pago NOT IN ('total','anulado')
--   By client      : tercero_id = X
-- Only issued invoices are receivables — borrador facturas are excluded.
CREATE OR REPLACE VIEW doc.vw_cuentas_por_cobrar AS
SELECT
    -- ── Factura side ──────────────────────────────────────────
    f.id                                                    AS factura_id,
    f.tercero_id,
    t.nombre                                                AS cliente_nombre,
    f.serie || '-' || f.numero::text                        AS factura_numero,
    f.tipo_comprobante,
    f.fecha_emision,
    f.fecha_vencimiento                                     AS factura_fecha_vencimiento,
    f.moneda,
    f.tipo_cambio,
    f.subtotal,
    f.igv,
    f.total                                                 AS factura_total,
    f.estado,
    f.estado_pago,
    CASE
        WHEN f.estado_pago IN ('total', 'anulado') THEN NULL
        ELSE GREATEST(0, CURRENT_DATE - f.fecha_vencimiento)
    END                                                     AS factura_dias_vencido,
    f.total - COALESCE(saldo.monto_aplicado_total, 0)       AS factura_saldo,

    -- ── Cobro side (NULL when no cobro applied yet) ───────────
    c.id                                                    AS cobro_id,
    c.fecha                                                 AS cobro_fecha,
    c.medio_pago                                            AS cobro_medio_pago,
    cofa.monto_aplicado,
    c.monto                                                 AS cobro_monto,
    c.referencia                                            AS cobro_referencia,
    c.estado                                                AS cobro_estado
FROM doc.factura f
JOIN tercero t ON t.id = f.tercero_id
LEFT JOIN LATERAL (
    SELECT SUM(cf2.monto_aplicado) FILTER (WHERE c2.estado <> 'anulado') AS monto_aplicado_total
    FROM doc.cobro_factura cf2
    JOIN doc.cobro c2 ON c2.id = cf2.cobro_id
    WHERE cf2.factura_id = f.id
) saldo ON true
LEFT JOIN doc.cobro_factura cofa ON cofa.factura_id = f.id
LEFT JOIN doc.cobro c            ON c.id = cofa.cobro_id
WHERE f.fyh_elm IS NULL
  AND f.estado <> 'borrador';

GRANT SELECT ON doc.vw_cuentas_por_cobrar TO authenticated;

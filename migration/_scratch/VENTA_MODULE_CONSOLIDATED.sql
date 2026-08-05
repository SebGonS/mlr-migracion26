-- ═══════════════════════════════════════════════════════════════════════════
-- ⛔ DO NOT RUN — REFERENCE ONLY. NOT CANONICAL. (moved to _scratch 2026-07-19)
-- ═══════════════════════════════════════════════════════════════════════════
-- This file re-declares objects whose SOURCE OF TRUTH is elsewhere:
--   · doc.registrar_despacho(jsonb)  → funciones/despacho.sql:375  (LIVE)
--   · doc.fn_descripcion_linea(...)  → funciones/despacho.sql
--   · doc.venta / doc.venta_detalle  → migration/27_venta.sql
--
-- Applying it would CREATE OR REPLACE the live registrar_despacho with the copy
-- below. As of migration 33b the live version resolves prices on
-- grupo_articulo_id; the copy here still uses articulo_tipo_id. That swap does
-- NOT error — it silently reverts dispatch pricing to the retired key, which is
-- the exact failure mode migrations 28-34 exist to eliminate.
--
-- Read it for context. Make changes in funciones/despacho.sql.
-- ═══════════════════════════════════════════════════════════════════════════
-- VENTA_MODULE_CONSOLIDATED.sql
-- ═══════════════════════════════════════════════════════════════════════════
-- CONSOLIDATED REFERENCE for the entire venta (sales hub) module — every table,
-- function, and view this module touches, in one file, so a future session (or
-- a fresh model) can load full context without grepping across despacho.sql,
-- devoluciones.sql, 08_views.sql, and facturacion.sql.
--
-- THIS FILE IS A READ REFERENCE, NOT AN INDEPENDENT DEPLOY SCRIPT.
--   • Canonical, authoritative source of each object is still its home file
--     (listed per section below) — edit there, then re-sync this copy.
--   • SECTION 1 (tables) is NOT idempotent (matches migration/27_venta.sql —
--     no IF NOT EXISTS) — do NOT re-run it if already applied. Included here
--     for context only.
--   • SECTIONS 2–3 (functions, views) ARE safe to re-run — every statement is
--     CREATE OR REPLACE. Re-running them re-syncs a DB to this file's content.
--
-- Companion doc: VENTA_MODULE_HANDOFF.md — the prose decision record (why, not
-- what). Read that first if you're unsure whether something here is settled or
-- still open.
--
-- Contents:
--   1. Tables      — doc.venta, doc.venta_detalle, doc.entrega.venta_id      (migration/27_venta.sql)
--   2. Functions   — recompute_estado_comercial, registrar_despacho,
--                     facturar_venta, anular_venta, fn_descripcion_linea      (funciones/despacho.sql)
--                   — venta_id stamping + recompute call sites               (funciones/devoluciones.sql — PATCH NOTES, not full bodies)
--   3. Views       — mes.vw_partida_comercial, doc.vw_venta                  (migration/08_views.sql)
--   4. OPEN ISSUE  — funciones/facturacion.sql has a live, parallel MLR-emits-
--                     its-own-factura pipeline that conflicts with this module.
--                     NOT resolved. See bottom of this file.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1 — TABLES  (source: migration/27_venta.sql — NOT idempotent, reference only)
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
-- Header / hub. The outbound mirror of doc.compra. One per commercial sale.
CREATE TABLE doc.venta (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tercero_id          INT  NOT NULL REFERENCES tercero(id),
    fecha               DATE NOT NULL DEFAULT CURRENT_DATE,

    -- MLR's own factura REFERENCE — emitted in the external system, referenced
    -- here, never reproduced. 1:1 with the venta (MLR ships all at once).
    factura_serie       TEXT,
    factura_numero      INT,
    factura_fecha_venc  DATE,

    estado              venta_estado_enum NOT NULL DEFAULT 'ABIERTA',
    observacion         TEXT,

    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    flg_elm BOOLEAN NOT NULL DEFAULT false,
    usr_elm INT, fyh_elm TIMESTAMPTZ,

    CONSTRAINT chk_venta_factura_fields CHECK ((factura_serie IS NULL) = (factura_numero IS NULL))
);

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
-- Charge lines. SNAPSHOT boundary: freeze the charge (cantidad_kg/precio_kg)
-- AND the pricing-key dims that determined it (color/tenido/articulo_tipo/
-- flg_antipilling) — same reason the price freezes: a billing line is a
-- frozen record of a transaction, decoupled from partida mutability. Only
-- non-pricing spec (ancho/rendimiento) and fibra stay derived, composed at
-- display time (fn_descripcion_linea).
CREATE TABLE doc.venta_detalle (
    id              BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venta_id        BIGINT   NOT NULL REFERENCES doc.venta(id),
    linea           SMALLINT NOT NULL DEFAULT 1,

    tipo            venta_linea_tipo_enum NOT NULL DEFAULT 'SERVICIO',
    operacion_id    SMALLINT REFERENCES mes.operacion(id),
    item_id         INT      REFERENCES item(id),

    color_x_cliente_id  INT      REFERENCES color_x_cliente(id),
    tenido_id           INT      REFERENCES tenido(id),
    articulo_tipo_id    SMALLINT REFERENCES articulo_tipo(id),
    flg_antipilling     BOOLEAN  NOT NULL DEFAULT false,

    -- INTENT partida (parent/root). Billing is against what was ordered;
    -- reworks are not billed separately.
    partida_id      BIGINT   REFERENCES mes.partida(id),

    descripcion     TEXT,    -- NULL = compose via fn_descripcion_linea; non-NULL = manual override

    cantidad_kg     NUMERIC(12,4) NOT NULL CHECK (cantidad_kg > 0),
    precio_kg       NUMERIC(12,4) NOT NULL CHECK (precio_kg >= 0),
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
-- The structural link. Direct FK (not M:N like compra_entrega): a dispatch or
-- return entrega belongs to exactly one sale by construction.
ALTER TABLE doc.entrega
    ADD COLUMN venta_id BIGINT REFERENCES doc.venta(id);

CREATE INDEX idx_entrega_venta ON doc.entrega (venta_id);

ALTER TABLE doc.venta         ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc.venta_detalle ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON doc.venta         TO authenticated;
GRANT SELECT, INSERT, UPDATE ON doc.venta_detalle TO authenticated;
CREATE POLICY "comercial_ver" ON doc.venta
    FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));
CREATE POLICY "comercial_ver" ON doc.venta_detalle
    FOR SELECT TO authenticated USING (jwt_has_permission('comercial.ver'));


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2 — FUNCTIONS  (source: funciones/despacho.sql, safe to re-run)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── doc.recompute_estado_comercial ────────────────────────────────────────
-- Refreshes mes.partida.estado_comercial — a CACHE of derived fulfillment
-- truth, never authoritative itself (mes.vw_partida_comercial IS the truth).
-- Inline recompute at the end of every fulfillment-affecting function, NOT a
-- trigger (caller already knows the partida; a trigger would re-derive it per
-- roll via genealogy). Follows the compra_detalle.cantidad_recibida precedent.
--
-- CALL SITES (closed set — update here + HANDOFF doc if this list grows):
--   registrar_despacho, registrar_devolucion_cliente,
--   registrar_devolucion_crudo_cliente, anular_entrega,
--   anular_devolucion_cliente, anular_devolucion_crudo_cliente.
--
-- Denominator: terminal APROBADO output for the family, via
-- mes.vw_partida_familia_output (same dedup rule as cerrar_partida /
-- get_partida_familia). Numerator: of those, currently-dispatched lotes (a
-- SERV_EGR/VENTA_EGR with no later SERV_DEV_ING/DEV_CLI_ING undoing it).
--
-- DEVUELTA_* mapping is a FIRST-PASS HEURISTIC — not validated against real
-- return history yet.
CREATE OR REPLACE FUNCTION doc.recompute_estado_comercial(p_partida_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario', 'doc'
AS $$
DECLARE
    v_root_id      BIGINT;
    v_total        INT;
    v_dispatched   INT;
    v_ever_dispatched INT;
    v_estado       partida_estado_comercial_enum;
BEGIN
    SELECT COALESCE(partida_origen_id, id) INTO v_root_id
    FROM mes.partida WHERE id = p_partida_id AND fyh_elm IS NULL;

    IF v_root_id IS NULL THEN
        RETURN;
    END IF;

    WITH terminal AS (
        SELECT lote_id FROM mes.vw_partida_familia_output
        WHERE root_id = v_root_id AND estado_calidad = 'APROBADO'
    )
    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = terminal.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
            )
            AND NOT EXISTS (
                SELECT 1 FROM inventario.item_movimientos im2
                JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                WHERE im2.lote_id = terminal.lote_id AND imt2.codigo IN ('SERV_DEV_ING','DEV_CLI_ING')
            )
        ),
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = terminal.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
            )
        )
    INTO v_total, v_dispatched, v_ever_dispatched
    FROM terminal;

    v_estado := CASE
        WHEN v_total = 0                                   THEN 'PENDIENTE'
        WHEN v_dispatched = 0 AND v_ever_dispatched = v_total THEN 'DEVUELTA_TOTAL'
        WHEN v_dispatched < v_ever_dispatched               THEN 'DEVUELTA_PARCIAL'
        WHEN v_dispatched >= v_total                        THEN 'ENTREGADA'
        WHEN v_dispatched > 0                                THEN 'ENTREGA_PARCIAL'
        ELSE 'PENDIENTE'
    END;

    UPDATE mes.partida
    SET estado_comercial = v_estado
    WHERE id = v_root_id AND estado_comercial IS DISTINCT FROM v_estado;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.recompute_estado_comercial(BIGINT) TO authenticated;


-- ── doc.registrar_despacho ──────────────────────────────────────────────────
-- ONE-SHOT dispatch. items[] (physical rolls) drives entrega/movements via the
-- EXISTING doc.crear_entrega (reused, not reimplemented); cargos[] (the
-- operations the dispatch user sums/charges) drives venta_detalle, with dims/
-- price fetched automatically. See funciones/despacho.sql for the full p_datos
-- shape documented inline.
--
-- p_datos = {
--   "tercero_id": 7,                          -- optional; derived from cargos' partidas if omitted
--   "items": [ { "item_id":.., "lote_id":.., "ubicacion_id":.., "cantidad":..,
--                "propietario_id":.., "partida_id":.. } ],
--   "guias": { "VENTA_EGRESO": {...}, "DESPACHO_CLIENTE": {...} },  -- optional, headless if omitted
--   "cargos": [ { "partida_id":.., "operacion_id":.., "cantidad_kg":..,
--                 "precio_kg":.. (optional), "item_id":.. (VENTA lines only) } ]
-- }
-- Returns: { "venta_id":.., "entrega_ids":[..], "cargo_ids":[..] }
--
-- NOT YET VALIDATED against real data:
--   • ownership-mix guard raises rather than resolves (confirm this can't happen)
--   • see recompute_estado_comercial's DEVUELTA_* caveat above
CREATE OR REPLACE FUNCTION doc.registrar_despacho(p_datos jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'mes', 'inventario'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_tercero_id    int  := (p_datos->>'tercero_id')::int;
    v_venta_id      bigint;
    v_entrega_ids   bigint[] := '{}';
    v_cargo_ids     bigint[] := '{}';
    v_entrega_id    bigint;
    v_tipo_codigo   text;
    v_tipo_id       smallint;
    v_guia          jsonb;
    v_items_grupo   jsonb;
    v_root_id       BIGINT;
    v_cargo         jsonb;
    v_cargo_id      bigint;
    v_partida       RECORD;
    v_precio_kg     NUMERIC(12,4);
    v_tipo_venta    venta_linea_tipo_enum;
    v_linea         SMALLINT;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF jsonb_array_length(COALESCE(p_datos->'items', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'registrar_despacho: se requiere al menos un item.';
    END IF;

    IF v_tercero_id IS NULL THEN
        SELECT DISTINCT p.tercero_id INTO v_tercero_id
        FROM mes.partida p
        WHERE p.id = ANY(
            SELECT DISTINCT (c->>'partida_id')::bigint
            FROM jsonb_array_elements(COALESCE(p_datos->'cargos', '[]'::jsonb)) c
        );
    END IF;
    IF v_tercero_id IS NULL THEN
        RAISE EXCEPTION 'registrar_despacho: no se pudo determinar tercero_id (proporcione tercero_id o cargos con partida_id).';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_despacho', v_usr_id, p_datos);

    -- ── 1. Physical side: one entrega per ownership group, via crear_entrega ──
    -- Loops over exactly 2 fixed groups (ownership is structurally binary) but
    -- the BODY is 6 real steps — looping avoids duplicating that sequence, not
    -- just a value. crear_entrega is reused as-is (not reimplemented, not
    -- wrapped) — it's ~140 lines of already-live validated logic called
    -- directly by the existing two-step frontend flow. As of 2026-07-14
    -- crear_entrega RETURNS bigint (changed from text — see funciones/core.sql
    -- and HANDOFF item 6b), so this is a clean SELECT..INTO, no currval needed.
    FOR v_tipo_codigo IN SELECT unnest(ARRAY['VENTA_EGRESO','DESPACHO_CLIENTE'])
    LOOP
        SELECT jsonb_agg(item) INTO v_items_grupo
        FROM jsonb_array_elements(p_datos->'items') item
        WHERE (v_tipo_codigo = 'VENTA_EGRESO'    AND (item->>'propietario_id')::int = 1)
           OR (v_tipo_codigo = 'DESPACHO_CLIENTE' AND (item->>'propietario_id')::int IS DISTINCT FROM 1);

        CONTINUE WHEN v_items_grupo IS NULL;

        SELECT id INTO v_tipo_id FROM doc.entrega_tipo WHERE codigo = v_tipo_codigo;
        v_guia := (p_datos->'guias')->v_tipo_codigo;

        SELECT doc.crear_entrega(jsonb_build_object(
            'entrega_tipo_id', v_tipo_id,
            'tercero_id',      v_tercero_id,
            'serie',           v_guia->>'serie',
            'correlativo',     v_guia->>'correlativo',
            'fecha_emision',   COALESCE(v_guia->>'fecha_emision', now()::text),
            'items',           v_items_grupo
        )) INTO v_entrega_id;

        v_entrega_ids := array_append(v_entrega_ids, v_entrega_id);
    END LOOP;

    IF array_length(v_entrega_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'registrar_despacho: ningún item resolvió a un grupo de despacho válido.';
    END IF;

    -- ── 2. Commercial side: open/reuse the ABIERTA venta for this tercero ──
    SELECT id INTO v_venta_id
    FROM doc.venta
    WHERE tercero_id = v_tercero_id AND estado = 'ABIERTA'
    ORDER BY fyh_cre DESC
    LIMIT 1
    FOR UPDATE;

    IF v_venta_id IS NULL THEN
        INSERT INTO doc.venta (tercero_id, usr_cre)
        VALUES (v_tercero_id, v_usr_id)
        RETURNING id INTO v_venta_id;
    END IF;

    UPDATE doc.entrega SET venta_id = v_venta_id WHERE id = ANY(v_entrega_ids);

    -- ── 3. Charge lines — snapshot dims from each cargo's INTENT partida ──
    v_linea := 0;
    FOR v_cargo IN SELECT * FROM jsonb_array_elements(COALESCE(p_datos->'cargos', '[]'::jsonb))
    LOOP
        v_linea := v_linea + 1;

        SELECT COALESCE(partida_origen_id, id) INTO v_root_id
        FROM mes.partida WHERE id = (v_cargo->>'partida_id')::bigint;

        IF v_root_id IS NULL THEN
            RAISE EXCEPTION 'registrar_despacho: partida % (cargo) no existe.', v_cargo->>'partida_id';
        END IF;

        SELECT p.tercero_id, p.color_x_cliente_id, p.tenido_id, p.articulo_tipo_id,
               p.fibra, p.flg_antipilling, p.precio_kg
        INTO v_partida
        FROM mes.partida p WHERE p.id = v_root_id;

        SELECT CASE
                 WHEN bool_and((item->>'propietario_id')::int = 1)          THEN 'VENTA'
                 WHEN bool_and((item->>'propietario_id')::int IS DISTINCT FROM 1) THEN 'SERVICIO'
                 ELSE NULL
               END
        INTO v_tipo_venta
        FROM jsonb_array_elements(p_datos->'items') item
        WHERE (
            SELECT COALESCE(partida_origen_id, id) FROM mes.partida
            WHERE id = (item->>'partida_id')::bigint
        ) = v_root_id;

        IF v_tipo_venta IS NULL THEN
            RAISE EXCEPTION 'registrar_despacho: partida % mezcla rollos propios y de cliente en este despacho — no se puede facturar como una sola línea.',
                v_root_id;
        END IF;

        v_precio_kg := COALESCE(
            (v_cargo->>'precio_kg')::numeric,
            v_partida.precio_kg,
            doc.fn_get_precio(
                (v_cargo->>'operacion_id')::smallint,
                v_partida.color_x_cliente_id,
                v_partida.tercero_id,
                v_partida.articulo_tipo_id,
                v_partida.tenido_id,
                v_partida.fibra,
                v_partida.flg_antipilling
            )
        );

        IF v_precio_kg IS NULL THEN
            RAISE EXCEPTION 'registrar_despacho: no se encontró precio para partida % / operación % — indique precio_kg manualmente.',
                v_root_id, v_cargo->>'operacion_id';
        END IF;

        INSERT INTO doc.venta_detalle (
            venta_id, linea, tipo, operacion_id, item_id,
            color_x_cliente_id, tenido_id, articulo_tipo_id, flg_antipilling,
            partida_id, descripcion, cantidad_kg, precio_kg, usr_cre
        ) VALUES (
            v_venta_id, v_linea, v_tipo_venta::venta_linea_tipo_enum,
            (v_cargo->>'operacion_id')::smallint,
            NULLIF(v_cargo->>'item_id','')::int,
            v_partida.color_x_cliente_id, v_partida.tenido_id, v_partida.articulo_tipo_id, v_partida.flg_antipilling,
            v_root_id, v_cargo->>'descripcion',
            (v_cargo->>'cantidad_kg')::numeric, v_precio_kg, v_usr_id
        )
        RETURNING id INTO v_cargo_id;

        v_cargo_ids := array_append(v_cargo_ids, v_cargo_id);
    END LOOP;

    -- ── 4. Refresh the fulfillment cache for every distinct partida touched ──
    PERFORM doc.recompute_estado_comercial(DISTINCT_ROOT.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM jsonb_array_elements(p_datos->'items') item
        JOIN mes.partida p ON p.id = (item->>'partida_id')::bigint
    ) DISTINCT_ROOT;

    RETURN jsonb_build_object(
        'venta_id',    v_venta_id,
        'entrega_ids', to_jsonb(v_entrega_ids),
        'cargo_ids',   to_jsonb(v_cargo_ids)
    );
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_despacho - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.registrar_despacho(jsonb) TO authenticated;


-- ── doc.facturar_venta ──────────────────────────────────────────────────────
-- Stamps the EXTERNAL factura reference on an ABIERTA venta and closes it.
-- Does NOT touch doc.factura / SUNAT / IGV — reference, not emission.
CREATE OR REPLACE FUNCTION doc.facturar_venta(
    p_venta_id     BIGINT,
    p_serie        TEXT,
    p_numero       INT,
    p_fecha_venc   DATE DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id  int := get_user_id();
    v_estado  venta_estado_enum;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado INTO v_estado FROM doc.venta WHERE id = p_venta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venta #% no encontrada.', p_venta_id;
    END IF;
    IF v_estado <> 'ABIERTA' THEN
        RAISE EXCEPTION 'Venta #% no está ABIERTA (estado actual: %) — no se puede facturar.', p_venta_id, v_estado;
    END IF;

    UPDATE doc.venta
    SET factura_serie = p_serie, factura_numero = p_numero, factura_fecha_venc = p_fecha_venc,
        estado = 'FACTURADA', usr_mod = v_usr_id
    WHERE id = p_venta_id;

    RETURN format('Venta #%s facturada con %s-%s.', p_venta_id, p_serie, p_numero);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in facturar_venta - User: %, venta: %, Error: %', v_usr_id, p_venta_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.facturar_venta(BIGINT, TEXT, INT, DATE) TO authenticated;


-- ── doc.anular_venta ────────────────────────────────────────────────────────
-- Voids the commercial record. Does NOT reverse entregas/movements — that is
-- doc.anular_entrega's job, run separately. FIRST PASS: no cascade guard
-- against still-active linked entregas.
CREATE OR REPLACE FUNCTION doc.anular_venta(p_venta_id BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id  int := get_user_id();
    v_estado  venta_estado_enum;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado INTO v_estado FROM doc.venta WHERE id = p_venta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venta #% no encontrada.', p_venta_id;
    END IF;
    IF v_estado = 'ANULADA' THEN
        RAISE EXCEPTION 'Venta #% ya está anulada.', p_venta_id;
    END IF;

    UPDATE doc.venta SET estado = 'ANULADA', usr_mod = v_usr_id WHERE id = p_venta_id;

    RETURN format('Venta #%s anulada.', p_venta_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_venta - User: %, venta: %, Error: %', v_usr_id, p_venta_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.anular_venta(BIGINT) TO authenticated;


-- ── doc.fn_descripcion_linea ─────────────────────────────────────────────────
-- Composes the venta_detalle line label from structured columns — never
-- free-typed. Enriches generic items with partida order context (color, tenido).
CREATE OR REPLACE FUNCTION doc.fn_descripcion_linea(
    p_tipo               venta_linea_tipo_enum,
    p_operacion_id       SMALLINT,
    p_item_id            INT,
    p_articulo_tipo_id   SMALLINT,
    p_color_x_cliente_id INT,
    p_tenido_id          INT,
    p_flg_antipilling    BOOLEAN
)
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path TO 'public', 'mes', 'doc'
AS $$
    SELECT CASE
        WHEN p_tipo = 'VENTA' THEN
            COALESCE((SELECT nombre FROM item WHERE id = p_item_id), 'Producto')
        ELSE
            TRIM(BOTH ' · ' FROM
                COALESCE((SELECT nombre FROM mes.operacion WHERE id = p_operacion_id), '')
                || ' — '
                || COALESCE((SELECT nombre FROM articulo_tipo WHERE id = p_articulo_tipo_id), '')
                || COALESCE(' · ' || (SELECT color FROM vw_colores WHERE color_x_cliente_id = p_color_x_cliente_id), '')
                || COALESCE(' · ' || (SELECT tenido FROM tenido WHERE id = p_tenido_id), '')
                || CASE WHEN p_flg_antipilling THEN ' · Antipilling' ELSE '' END
            )
    END;
$$;

GRANT EXECUTE ON FUNCTION doc.fn_descripcion_linea(
    venta_linea_tipo_enum, SMALLINT, INT, SMALLINT, INT, INT, BOOLEAN
) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2b — DEVOLUCIONES PATCH NOTES (source: funciones/devoluciones.sql)
-- ═══════════════════════════════════════════════════════════════════════════
-- These are EDITS inside pre-existing, much larger functions — reproducing the
-- full bodies here would duplicate ~600 lines unrelated to venta. Instead: the
-- exact snippet added to each, and where. Apply/verify against the live file.

-- Added to doc.registrar_devolucion_cliente (funciones/devoluciones.sql, before
-- its final RETURN), right after the entrega_detalle + item_movimientos insert:
--
--   UPDATE doc.entrega
--   SET venta_id = (
--       SELECT e2.venta_id
--       FROM inventario.item_movimientos im
--       JOIN doc.entrega e2 ON e2.id = im.documento_id AND im.documento_tipo = 'entrega'
--       WHERE im.lote_id = ANY(
--           SELECT (item->>'lote_id')::int FROM jsonb_array_elements(p_datos->'items') item
--       )
--       AND im.origen_ubicacion_id IS NOT NULL  -- outbound direction: the original dispatch
--       AND e2.venta_id IS NOT NULL
--       LIMIT 1
--   )
--   WHERE id = v_entrega_id;
--
--   PERFORM doc.recompute_estado_comercial(root.root_id)
--   FROM (
--       SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
--       FROM doc.entrega_detalle ed
--       JOIN inventario.lote l ON l.id = ed.lote_id
--       JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
--       JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
--       JOIN mes.partida p ON p.id = pp.partida_id
--       WHERE ed.entrega_id = v_entrega_id
--   ) root;

-- SAME pattern added to doc.registrar_devolucion_crudo_cliente (identical shape).

-- Added to doc.anular_devolucion_cliente AND doc.anular_devolucion_crudo_cliente
-- (funciones/devoluciones.sql, right after `UPDATE doc.entrega SET usr_elm=.., fyh_elm=NOW() WHERE id=p_entrega_id`):
--
--   PERFORM doc.recompute_estado_comercial(root.root_id)
--   FROM (
--       SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
--       FROM doc.entrega_detalle ed
--       JOIN inventario.lote l ON l.id = ed.lote_id
--       JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
--       JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
--       JOIN mes.partida p ON p.id = pp.partida_id
--       WHERE ed.entrega_id = p_entrega_id
--   ) root;

-- Added to doc.anular_entrega (funciones/despacho.sql, right after
-- `UPDATE doc.entrega SET usr_elm=.., fyh_elm=NOW() WHERE id=p_entrega_id`,
-- BEFORE its final RETURN) — the SAME recompute snippet as above (keyed on
-- p_entrega_id). For inbound entregas the join finds no rows — harmless no-op.


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3 — VIEWS  (source: migration/08_views.sql, safe to re-run)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── mes.vw_partida_comercial ────────────────────────────────────────────────
-- DERIVED dispatch-fulfillment + billing projection, at FAMILIA (root) level.
-- Authoritative truth mes.partida.estado_comercial only CACHES — if they ever
-- disagree, THIS view is right.
CREATE OR REPLACE VIEW mes.vw_partida_comercial AS
WITH terminal AS (
    SELECT root_id, lote_id
    FROM mes.vw_partida_familia_output
    WHERE estado_calidad = 'APROBADO'
),
fulfillment AS (
    SELECT
        t.root_id,
        COUNT(*) AS total_terminal,
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = t.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
            )
            AND NOT EXISTS (
                SELECT 1 FROM inventario.item_movimientos im2
                JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                WHERE im2.lote_id = t.lote_id AND imt2.codigo IN ('SERV_DEV_ING','DEV_CLI_ING')
            )
        ) AS dispatched_ahora
    FROM terminal t
    GROUP BY t.root_id
)
SELECT
    p.id                                                                     AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo,
    p.tercero_id,
    c.nombre                                                                 AS cliente,
    p.estado_comercial                                                       AS estado_comercial_cache,
    COALESCE(f.total_terminal, 0)                                            AS total_terminal,
    COALESCE(f.dispatched_ahora, 0)                                          AS dispatched_ahora,
    GREATEST(0, COALESCE(f.total_terminal, 0) - COALESCE(f.dispatched_ahora, 0)) AS pendiente,
    v.venta_ids,
    v.factura_refs,
    v.total_kg_facturado,
    v.total_importe
FROM mes.partida p
JOIN tercero c ON c.id = p.tercero_id
LEFT JOIN fulfillment f ON f.root_id = p.id
LEFT JOIN LATERAL (
    SELECT
        jsonb_agg(DISTINCT vd.venta_id)                                            AS venta_ids,
        jsonb_agg(DISTINCT (ve.factura_serie || '-' || ve.factura_numero::text))
            FILTER (WHERE ve.factura_serie IS NOT NULL)                            AS factura_refs,
        SUM(vd.cantidad_kg)                                                        AS total_kg_facturado,
        SUM(vd.importe)                                                            AS total_importe
    FROM doc.venta_detalle vd
    JOIN doc.venta ve ON ve.id = vd.venta_id AND ve.estado <> 'ANULADA'
    WHERE vd.partida_id = p.id
) v ON true
WHERE p.partida_origen_id IS NULL
  AND p.fyh_elm IS NULL;

GRANT SELECT ON mes.vw_partida_comercial TO authenticated;


-- ── doc.vw_venta ────────────────────────────────────────────────────────────
-- Read surface for the sales spine: header + charge lines, composed description.
CREATE OR REPLACE VIEW doc.vw_venta AS
SELECT
    v.id                AS venta_id,
    v.tercero_id,
    t.nombre            AS cliente,
    v.fecha,
    v.factura_serie,
    v.factura_numero,
    v.factura_fecha_venc,
    v.estado,
    vd.id               AS detalle_id,
    vd.linea,
    vd.tipo,
    vd.operacion_id,
    op.nombre           AS operacion_nombre,
    vd.item_id,
    it.nombre           AS item_nombre,
    vd.partida_id,
    pcod.codigo         AS partida_codigo,
    vd.color_x_cliente_id,
    vc.color,
    vd.tenido_id,
    ten.tenido,
    vd.articulo_tipo_id,
    aty.nombre          AS articulo_tipo,
    vd.flg_antipilling,
    COALESCE(
        vd.descripcion,
        doc.fn_descripcion_linea(
            vd.tipo, vd.operacion_id, vd.item_id, vd.articulo_tipo_id,
            vd.color_x_cliente_id, vd.tenido_id, vd.flg_antipilling
        )
    )                   AS descripcion,
    vd.cantidad_kg,
    vd.precio_kg,
    vd.importe
FROM doc.venta v
JOIN tercero t ON t.id = v.tercero_id
LEFT JOIN doc.venta_detalle vd     ON vd.venta_id = v.id
LEFT JOIN mes.operacion op         ON op.id = vd.operacion_id
LEFT JOIN item it                  ON it.id = vd.item_id
LEFT JOIN vw_colores vc            ON vc.color_x_cliente_id = vd.color_x_cliente_id
LEFT JOIN tenido ten                ON ten.id = vd.tenido_id
LEFT JOIN public.articulo_tipo aty ON aty.id = vd.articulo_tipo_id
LEFT JOIN LATERAL (
    SELECT EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo
    FROM mes.partida p WHERE p.id = vd.partida_id
) pcod ON true;

GRANT SELECT ON doc.vw_venta TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4 — RESOLVED: estado_facturacion / doc.factura pipeline KEPT (2026-07-13)
-- ═══════════════════════════════════════════════════════════════════════════
-- funciones/facturacion.sql has a COMPLETE, wired MLR-emits-its-own-factura
-- pipeline (doc.registrar_factura_cliente, doc.vw_pendientes_facturacion,
-- doc.anular_factura_cliente, mes.partida.estado_facturacion) — confirmed DEAD
-- CODE, not called by the frontend. Likely the "basic outline on the financial
-- aspect" built before the venta direction was settled.
--
-- DECISION: do NOT retire estado_facturacion, do NOT touch doc.factura. Keep
-- this dormant pipeline parked, unmodified, as insurance in case the client
-- later demands payment-status tracking. Deliberate, not negligence — don't
-- "clean up" or wire it to venta without being asked again.
--
-- RESOLVED (2026-07-14): doc.crear_entrega now RETURNS bigint (the created
-- entrega_id), matching its sibling doc.registrar_entrega_compra, instead of
-- the previous `text` message. registrar_despacho now uses a clean
-- SELECT doc.crear_entrega(...) INTO v_entrega_id — the currval() workaround
-- is gone. This is a BREAKING CHANGE for BOTH of crear_entrega's direct
-- callers (receipt/CLIENTE_ENVIO_PROCESO and dispatch/VENTA_EGRESO+
-- DESPACHO_CLIENTE) — the frontend must be updated to read the returned id
-- instead of the old display message for both flows. The function's own
-- inline comment (funciones/core.sql) carries the same note. The receipt/
-- dispatch flow SPLIT considered earlier (separate dedicated functions) was
-- explicitly NOT done — this was the smaller, sufficient fix for the actual
-- problem (a good RPC returns the id).



SELECT * FROM calidad.vw_partidas_pendientes_calidad
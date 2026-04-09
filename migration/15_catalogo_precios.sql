-- ═══════════════════════════════════════════════════════════════
-- Step 15: doc.catalogo_precios — Service price catalog
-- Depends on: doc schema, mes.operacion, color_x_cliente,
--             articulo_tipo, tenido (steps 5, 7)
-- Replaces: public.catalogo_precios (legacy)
-- ═══════════════════════════════════════════════════════════════

-- ── doc.catalogo_precios ──────────────────────────────────────
-- Per-kg rate for each billable service combination.
-- All prices are in USD — MLR bills exclusively in USD.
--
-- Lookup key: operacion × color/client × article type × dyeing × fiber.
-- NULL in any dimension = wildcard (matches any value of that dimension).
-- Most-specific active match wins — see doc.fn_get_precio().
--
-- Historicity: rows are immutable once created. To change a price,
-- set fyh_fin on the current row (via doc.upsert_catalogo_precio)
-- and insert a new row. This preserves pricing history for invoice
-- reconstruction without a separate history table.
--
-- Antipilling: stored as a second price on the TENIDO row rather than
-- a separate catalog row. The billing query emits a second line when
-- partida.flg_antipilling = true AND precio_antipilling IS NOT NULL.
-- Only TENIDO rows carry a precio_antipilling value.
CREATE TABLE IF NOT EXISTS doc.catalogo_precios (
    id                  BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Lookup dimensions (NULL = wildcard)
    operacion_id        SMALLINT NOT NULL REFERENCES mes.operacion(id),
    color_x_cliente_id  INT      REFERENCES color_x_cliente(id),  -- NULL = any client/color
    articulo_tipo_id    SMALLINT REFERENCES articulo_tipo(id),     -- NULL = any article type
    tenido_id           INT      REFERENCES tenido(id),            -- NULL = any / N/A for non-dyeing ops
    fibra               SMALLINT,                                  -- NULL = any; matches articulo.fibra

    -- Prices (USD/kg)
    precio_kg           NUMERIC(10,4) NOT NULL CHECK (precio_kg >= 0),
    precio_antipilling  NUMERIC(10,4)           CHECK (precio_antipilling >= 0),
                        -- Only set on TENIDO rows; NULL on PLANCHADO, PERCHADO, etc.

    -- Audit (fyh_elm = inactive: either superseded by a new price or deleted for error)
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_elm INT, fyh_elm TIMESTAMPTZ
);

-- One active row per key combination at any time.
-- COALESCE(-1): NULL dimensions use -1 as a sentinel so they
-- participate correctly in the unique index.
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalogo_precios_activo
    ON doc.catalogo_precios (
        operacion_id,
        COALESCE(color_x_cliente_id,    -1),
        COALESCE(articulo_tipo_id::int, -1),
        COALESCE(tenido_id,             -1),
        COALESCE(fibra::int,            -1)
    )
    WHERE fyh_elm IS NULL;

-- ── RLS & Grants ─────────────────────────────────────────────
ALTER TABLE doc.catalogo_precios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comercial_ver" ON doc.catalogo_precios
    FOR SELECT TO authenticated
    USING (jwt_has_permission('comercial.ver'));

-- ── Audit triggers ────────────────────────────────────────────
CREATE TRIGGER trg_bi_catalogo_precios_audit
    BEFORE INSERT ON doc.catalogo_precios
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-- No mod trigger: rows are immutable. fyh_fin is set by upsert_catalogo_precio.

-- ── REVOKEs ──────────────────────────────────────────────────
REVOKE INSERT (usr_cre, fyh_cre, usr_elm, fyh_elm) ON doc.catalogo_precios FROM anon, authenticated;

-- ── Data migration from legacy public.catalogo_precios ───────
-- Runs only if the old table still exists (idempotent — skips on conflict).
--
-- Mapping:
--   tipo_articulo_id  → articulo_tipo_id  (table renamed in step 4)
--   adicional_id = 1  → precio_antipilling copied from a hardcoded default,
--                        since the legacy table stored the flag but the actual
--                        antipilling price was hardcoded in get_partidas_despacho
--                        (0.10 general, 0.15 for Urban/cliente_id IN (1,11,22)).
--                        Active antipilling rows are migrated with precio_antipilling = NULL
--                        and must be manually set after reviewing client rates.
--   activo = 0        → fyh_fin = fyh_fin from legacy (already a timestamp)
--   activo = 1        → fyh_fin = NULL (currently active)
--   operacion_id      → always TENIDO (legacy catalog was dyeing-only)
--
-- IMPORTANT: after running, manually populate PLANCHADO/PERCHADO rates
-- and set precio_antipilling on active TENIDO rows per client agreement.
DO $$
DECLARE
    v_tenido_op_id SMALLINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'catalogo_precios'
    ) THEN
        RETURN;
    END IF;

    SELECT id INTO v_tenido_op_id FROM mes.operacion WHERE codigo = 'TENIDO';

    INSERT INTO doc.catalogo_precios (
        operacion_id,
        color_x_cliente_id,
        articulo_tipo_id,
        tenido_id,
        fibra,
        precio_kg,
        precio_antipilling,
        fyh_elm,
        fyh_cre
    )
    SELECT
        v_tenido_op_id,
        cp.color_x_cliente_id,
        cp.tipo_articulo_id::smallint,
        cp.tenido_id,
        cp.fibra::smallint,
        cp.precio_tenido,
        NULL,   -- antipilling prices were hardcoded, not in catalog; set manually
        CASE WHEN cp.activo = 0 THEN cp.fyh_fin ELSE NULL END,  -- fyh_elm
        cp.fyh_cre
    FROM public.catalogo_precios cp
    WHERE cp.adicional_id IS NULL OR cp.adicional_id = 0
    -- Skip the legacy adicional=1 rows: they were shadow rows never used in billing.
    -- Antipilling pricing goes on the base TENIDO row as precio_antipilling instead.
    ON CONFLICT DO NOTHING;
END $$;

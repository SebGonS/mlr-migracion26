-- ═══════════════════════════════════════════════════════════════════════════════
-- 46 · doc.catalogo_precios: remove flg_antipilling as a pricing dimension
-- ───────────────────────────────────────────────────────────────────────────────
-- SUPERSEDES patch 45. 45 was a same-day stopgap (widen the unique index to stop
-- the "duplicate key" error). This patch is the real fix, decided after tracing
-- the legacy intent: flg_antipilling on catalogo_precios was never a price
-- dimension — it existed only so upsert_catalogo_precio could bind a price row
-- to a specific receta.tenido variant (base vs antipilling) to snapshot that
-- variant's costo_kg. precio_kg itself is, by design, the SAME number for both
-- variants (one cotización covers both; antipilling is billed separately via
-- the ANTIPILLING ghost operación, already modeled correctly and untouched here).
--
-- costo_kg on catalogo_precios is non-authoritative context — it drifts the
-- moment the recipe changes and nothing reconciles it. doc.fn_precio_info
-- already recomputes cost live from receta.tenido for margin preview, so the
-- stored snapshot was never load-bearing. Kept as an informational column,
-- decoupled from any variant match — the recipe lookup now takes whichever
-- approved recipe matches the other dimensions (base preferred, tie-broken by
-- most recently approved), same "just context" meaning.
--
-- Net change: one price row per (operacion, client/color, articulo_tipo,
-- tenido, fibra) — no more duplicate false/true rows to keep in sync by hand,
-- and the unique-index collision this was created to guard against becomes
-- structurally impossible instead of just loosened.
--
-- FRONTEND IMPACT (not handled by this patch — hand off to frontend agent):
--   - UpsertCatalogoPrecioDrawer.tsx: drop p_flg_antipilling from the
--     upsert_catalogo_precio RPC call; the "Con antipilling / Sin antipilling"
--     badge/toggle for PRICE entry goes away (fn_precio_info call is unchanged
--     and can still preview both recipe variants' cost/margin if wanted).
--   - vw_precios_pendientes / PrecioPendiente type: flg_antipilling column
--     removed from the row shape; one pending row per combo instead of two.
--   - consulta-precios/page.tsx: vw_catalogo_precios_historico query and
--     grouping on 'flg_antipilling' (lines ~192, 196, 328, 338) needs rework —
--     column no longer exists.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Step 1: guard — abort if any base/antipilling pair disagrees on precio_kg ──
-- If this fires, someone negotiated a genuinely different antipilling rate and
-- the collapse below would silently destroy that. Resolve manually, then re-run.
--
-- Steps 1 and 2 are wrapped in a column-existence check so this whole patch is
-- safely re-runnable: if an earlier attempt already got as far as dropping
-- flg_antipilling before failing later on, re-running from the top must not
-- error out here on a column that's already gone. PL/pgSQL only parses a
-- statement against the catalog when it's actually reached, so a query
-- referencing flg_antipilling inside a skipped IF branch is never touched.
DO $$
DECLARE
    v_tenido_op_id SMALLINT;
    v_mismatch     RECORD;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'doc' AND table_name = 'catalogo_precios' AND column_name = 'flg_antipilling'
    ) THEN
        SELECT id INTO v_tenido_op_id FROM mes.operacion WHERE codigo = 'TENIDO';

        FOR v_mismatch IN
            SELECT
                f.color_x_cliente_id, f.tercero_id, f.articulo_tipo_id, f.tenido_id, f.fibra,
                f.precio_kg AS precio_false, t.precio_kg AS precio_true
            FROM doc.catalogo_precios f
            JOIN doc.catalogo_precios t
              ON t.operacion_id = f.operacion_id
             AND COALESCE(t.color_x_cliente_id,    -1) = COALESCE(f.color_x_cliente_id,    -1)
             AND COALESCE(t.tercero_id,            -1) = COALESCE(f.tercero_id,            -1)
             AND COALESCE(t.articulo_tipo_id::int, -1) = COALESCE(f.articulo_tipo_id::int, -1)
             AND COALESCE(t.tenido_id,             -1) = COALESCE(f.tenido_id,             -1)
             AND COALESCE(t.fibra::int,            -1) = COALESCE(f.fibra::int,            -1)
             AND t.fyh_elm IS NULL
             AND t.flg_antipilling = true
            WHERE f.operacion_id = v_tenido_op_id
              AND f.flg_antipilling = false
              AND f.fyh_elm IS NULL
              AND t.precio_kg IS DISTINCT FROM f.precio_kg
        LOOP
            RAISE EXCEPTION
                'catalogo_precios: base/antipilling precio_kg mismatch for color_x_cliente_id=%, tercero_id=%, articulo_tipo_id=%, tenido_id=%, fibra=% (sin_antipilling=%, con_antipilling=%) — resolve manually before running patch 46',
                v_mismatch.color_x_cliente_id, v_mismatch.tercero_id, v_mismatch.articulo_tipo_id,
                v_mismatch.tenido_id, v_mismatch.fibra, v_mismatch.precio_false, v_mismatch.precio_true;
        END LOOP;
    ELSE
        RAISE NOTICE 'catalogo_precios.flg_antipilling already dropped — skipping guard (already ran on a prior attempt).';
    END IF;
END $$;

-- ── Step 2: collapse — close the redundant antipilling-variant row wherever a
-- base-variant row is already active for the same dimensions (price verified
-- equal above). Lone antipilling-only rows (no base counterpart) are left
-- untouched — they simply become the combo's sole price after the column drop.
DO $$
DECLARE
    v_tenido_op_id SMALLINT;
    v_closed       INT;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'doc' AND table_name = 'catalogo_precios' AND column_name = 'flg_antipilling'
    ) THEN
        SELECT id INTO v_tenido_op_id FROM mes.operacion WHERE codigo = 'TENIDO';

        WITH closed AS (
            UPDATE doc.catalogo_precios t
            SET fyh_elm = NOW()
            FROM doc.catalogo_precios f
            WHERE t.operacion_id = v_tenido_op_id
              AND t.flg_antipilling = true
              AND t.fyh_elm IS NULL
              AND f.operacion_id = v_tenido_op_id
              AND f.flg_antipilling = false
              AND f.fyh_elm IS NULL
              AND COALESCE(t.color_x_cliente_id,    -1) = COALESCE(f.color_x_cliente_id,    -1)
              AND COALESCE(t.tercero_id,            -1) = COALESCE(f.tercero_id,            -1)
              AND COALESCE(t.articulo_tipo_id::int, -1) = COALESCE(f.articulo_tipo_id::int, -1)
              AND COALESCE(t.tenido_id,             -1) = COALESCE(f.tenido_id,             -1)
              AND COALESCE(t.fibra::int,            -1) = COALESCE(f.fibra::int,            -1)
            RETURNING t.id
        )
        SELECT count(*) INTO v_closed FROM closed;

        RAISE NOTICE 'catalogo_precios: closed % redundant antipilling-variant rows', v_closed;
    ELSE
        RAISE NOTICE 'catalogo_precios.flg_antipilling already dropped — skipping collapse (already ran on a prior attempt).';
    END IF;
END $$;

-- ── Step 3: drop objects that reference the column being dropped ──
-- (CREATE OR REPLACE VIEW cannot remove columns from its output list, so these
-- two need a real drop + recreate further down.)
DROP VIEW IF EXISTS doc.vw_catalogo_precios_historico;
DROP VIEW IF EXISTS doc.vw_precios_pendientes;
DROP INDEX IF EXISTS doc.uq_catalogo_precios_activo;

-- ── Step 3b: drop everything that calls fn_get_precio, BEFORE touching it ──
-- The old fn_get_precio has `p_flg_antipilling BOOLEAN DEFAULT NULL` — a
-- default — so it's callable with only 6 args. Creating the new 6-arg
-- fn_get_precio alongside the old 7-arg one (as a first attempt at this patch
-- did) makes every 6-arg call ambiguous ("is not unique"), because both
-- overloads match. The only safe order is: drop every dependent explicitly,
-- then drop the old fn_get_precio, THEN create the new one and rebuild
-- dependents fresh. Explicit drops (not CASCADE) so a forgotten dependent
-- fails loudly here instead of being silently deleted.
DROP VIEW     IF EXISTS doc.vw_pendientes_facturacion;
DROP VIEW     IF EXISTS doc.vw_aprobados_sin_despacho;
DROP FUNCTION IF EXISTS doc.get_precios_partida(BIGINT[]);
DROP FUNCTION IF EXISTS doc.fn_precio_info(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, BOOLEAN);
DROP FUNCTION IF EXISTS doc.registrar_despacho(JSONB);
-- fn_precios_partida: dead duplicate of get_precios_partida left over from an
-- old rename (confirmed byte-identical in restore_full.log, LANGUAGE sql,
-- still calling the old 7-arg fn_get_precio). consulta-precios/page.tsx was
-- calling this orphaned name; repointed to get_precios_partida separately.
DROP FUNCTION IF EXISTS doc.fn_precios_partida(BIGINT[]);
DROP FUNCTION IF EXISTS doc.fn_get_precio(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, BOOLEAN);

-- ── Step 4: drop the column (IF EXISTS — re-runnable if a prior attempt got this far) ──
ALTER TABLE doc.catalogo_precios DROP COLUMN IF EXISTS flg_antipilling;

-- ── Step 5: rebuild the active-row unique index without it ──
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalogo_precios_activo
    ON doc.catalogo_precios (
        operacion_id,
        COALESCE(color_x_cliente_id,    -1),
        COALESCE(tercero_id,            -1),
        COALESCE(articulo_tipo_id::int, -1),
        COALESCE(tenido_id,             -1),
        COALESCE(fibra::int,            -1)
    )
    WHERE fyh_elm IS NULL;

-- ── Step 6: doc.fn_get_precio — drop the antipilling dimension ──
-- Old 7-arg overload and everything that called it is gone as of Step 3b, so
-- this is a clean create — OR REPLACE only matters if a prior attempt already
-- got this far (re-running is then a no-op replace, not a fresh create).
CREATE OR REPLACE FUNCTION doc.fn_get_precio(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,
    p_tercero_id          INT,
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT
)
RETURNS NUMERIC(10,4)
LANGUAGE sql STABLE
SET search_path TO 'doc', 'public'
AS $$
    SELECT cp.precio_kg
    FROM doc.catalogo_precios cp
    WHERE
        cp.operacion_id = p_operacion_id
        -- Client dimension: specific color, OR client-level wildcard, OR universal
        AND (cp.color_x_cliente_id IS NULL OR cp.color_x_cliente_id = p_color_x_cliente_id)
        AND (cp.tercero_id         IS NULL OR cp.tercero_id         = p_tercero_id)
        -- A color_x_cliente row must not be matched as a tercero-level row
        AND NOT (cp.color_x_cliente_id IS NULL AND cp.tercero_id IS NOT NULL
                 AND cp.tercero_id <> p_tercero_id)
        AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   = p_articulo_tipo_id)
        AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p_tenido_id)
        AND (cp.fibra              IS NULL OR cp.fibra              = p_fibra)
        AND cp.fyh_elm IS NULL
    ORDER BY
        -- color_x_cliente_id wins over tercero_id (implies the client + specific color)
        (CASE WHEN cp.color_x_cliente_id IS NOT NULL THEN 2 ELSE 0 END
       + CASE WHEN cp.tercero_id         IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN cp.articulo_tipo_id   IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN cp.tenido_id          IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN cp.fibra              IS NOT NULL THEN 1 ELSE 0 END) DESC,
        cp.fyh_cre DESC
    LIMIT 1;
$$;

-- ── Step 7: doc.upsert_catalogo_precio — drop p_flg_antipilling ──
DROP FUNCTION IF EXISTS doc.upsert_catalogo_precio(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, BOOLEAN, NUMERIC);

CREATE OR REPLACE FUNCTION doc.upsert_catalogo_precio(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,          -- set for color-specific rate
    p_tercero_id          INT,          -- set for client flat rate (mutually exclusive with above)
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT,
    p_precio_kg           NUMERIC(10,4)
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'receta', 'doc', 'public'
AS $$
DECLARE
    v_usr_id       INT := get_user_id();
    v_id           BIGINT;
    v_receta_id    INT;
    v_costo_kg     NUMERIC(10,4);
    v_tenido_op_id SMALLINT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('upsert_catalogo_precio', v_usr_id, jsonb_build_object(
        'operacion_id', p_operacion_id,
        'color_x_cliente_id', p_color_x_cliente_id,
        'tercero_id', p_tercero_id,
        'articulo_tipo_id', p_articulo_tipo_id,
        'tenido_id', p_tenido_id,
        'fibra', p_fibra,
        'precio_kg', p_precio_kg
    ));

    IF p_color_x_cliente_id IS NOT NULL AND p_tercero_id IS NOT NULL THEN
        RAISE EXCEPTION 'color_x_cliente_id and tercero_id are mutually exclusive';
    END IF;

    SELECT id INTO v_tenido_op_id FROM mes.operacion WHERE codigo = 'TENIDO';

    -- Cost snapshot is contextual only (see patch 46 header) — no longer tied to
    -- a specific recipe variant. Grab whichever approved recipe matches the other
    -- dimensions; prefer the base (non-antipilling) one, tie-break most recent.
    IF p_operacion_id = v_tenido_op_id THEN
        SELECT rt.id INTO v_receta_id
        FROM receta.tenido rt
        WHERE rt.color_x_cliente_id = p_color_x_cliente_id
          AND rt.articulo_tipo_id   = p_articulo_tipo_id
          AND rt.fibra               = p_fibra
          AND rt.tenido_id           = p_tenido_id
          AND rt.flg_produccion      = true
        ORDER BY rt.flg_antipilling ASC, rt.fyh_produccion DESC NULLS LAST
        LIMIT 1;

        IF v_receta_id IS NOT NULL THEN
            v_costo_kg := doc.fn_get_costo_receta(v_receta_id);
        END IF;
    END IF;

    -- Normalize TENIDO article type to its pricing family AFTER the recipe/cost
    -- lookup above (recipes match the literal type) so the catalog row is stored
    -- under the same bucket the price lookup normalizes to.
    IF p_operacion_id = v_tenido_op_id THEN
        p_articulo_tipo_id := doc.fn_familia_precio(
            p_articulo_tipo_id,
            COALESCE(p_tercero_id,
                     (SELECT cxc.tercero_id FROM color_x_cliente cxc WHERE cxc.id = p_color_x_cliente_id))
        );
    END IF;

    UPDATE doc.catalogo_precios
    SET fyh_elm = NOW(), usr_elm = v_usr_id
    WHERE
        operacion_id = p_operacion_id
        AND COALESCE(color_x_cliente_id,    -1) = COALESCE(p_color_x_cliente_id,    -1)
        AND COALESCE(tercero_id,            -1) = COALESCE(p_tercero_id,            -1)
        AND COALESCE(articulo_tipo_id::int, -1) = COALESCE(p_articulo_tipo_id::int, -1)
        AND COALESCE(tenido_id,             -1) = COALESCE(p_tenido_id,             -1)
        AND COALESCE(fibra::int,            -1) = COALESCE(p_fibra::int,            -1)
        AND fyh_elm IS NULL;

    INSERT INTO doc.catalogo_precios (
        operacion_id, color_x_cliente_id, tercero_id, articulo_tipo_id,
        tenido_id, fibra, precio_kg, costo_kg, usr_cre
    ) VALUES (
        p_operacion_id, p_color_x_cliente_id, p_tercero_id, p_articulo_tipo_id,
        p_tenido_id, p_fibra, p_precio_kg, v_costo_kg, v_usr_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ── Step 8: doc.fn_precio_info — unchanged signature, still previews cost/margin
-- for a given recipe variant (p_flg_antipilling) against the single catalog price.
-- Internal fn_get_precio call updated to the new 6-arg overload.
CREATE OR REPLACE FUNCTION doc.fn_precio_info(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,
    p_tercero_id          INT,
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT,
    p_flg_antipilling     BOOLEAN DEFAULT NULL
)
RETURNS TABLE (
    receta_id  INT,
    costo_kg   NUMERIC(10,4),
    precio_kg  NUMERIC(10,4),
    margen     NUMERIC(8,6)    -- (precio_kg - costo_kg) / precio_kg; NULL if no price
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'receta', 'doc', 'public'
AS $$
DECLARE
    v_receta_id  INT;
    v_costo_kg   NUMERIC(10,4);
    v_precio_kg  NUMERIC(10,4);
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Find approved recipe matching p_flg_antipilling variant.
    -- NULL → skip recipe lookup (non-TENIDO or ANTIPILLING op).
    IF p_flg_antipilling IS NOT NULL THEN
        SELECT rt.id INTO v_receta_id
        FROM receta.tenido rt
        WHERE rt.color_x_cliente_id = p_color_x_cliente_id
          AND rt.articulo_tipo_id   = p_articulo_tipo_id
          AND rt.fibra               = p_fibra
          AND rt.tenido_id           = p_tenido_id
          AND rt.flg_antipilling     = p_flg_antipilling
          AND rt.flg_produccion      = true
        LIMIT 1;
    END IF;

    -- Compute chemical cost (NULL if no recipe)
    IF v_receta_id IS NOT NULL THEN
        v_costo_kg := doc.fn_get_costo_receta(v_receta_id);
    END IF;

    -- Fetch current catalog price. TENIDO: normalize article type to its pricing
    -- family so the preview shows the price that will actually bill. Recipe
    -- lookup above stays on the literal type. No antipilling dimension in the
    -- catalog lookup — both variants bill at the same precio_kg.
    v_precio_kg := doc.fn_get_precio(
        p_operacion_id, p_color_x_cliente_id, p_tercero_id,
        CASE WHEN p_operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
             THEN doc.fn_familia_precio(
                    p_articulo_tipo_id,
                    COALESCE(p_tercero_id,
                             (SELECT cxc.tercero_id FROM color_x_cliente cxc WHERE cxc.id = p_color_x_cliente_id)))
             ELSE p_articulo_tipo_id END,
        p_tenido_id, p_fibra
    );

    RETURN QUERY SELECT
        v_receta_id,
        v_costo_kg,
        v_precio_kg,
        CASE
            WHEN v_precio_kg IS NOT NULL AND v_costo_kg IS NOT NULL AND v_precio_kg > 0
            THEN ROUND((v_precio_kg - v_costo_kg) / v_precio_kg, 6)
            ELSE NULL
        END;
END;
$$;

-- ── Step 9: doc.get_precios_partida — drop antipilling arg from fn_get_precio calls ──
CREATE OR REPLACE FUNCTION doc.get_precios_partida(p_partida_ids BIGINT[])
RETURNS TABLE (
    partida_id      BIGINT,
    operacion_id    SMALLINT,
    operacion       TEXT,
    es_antipilling  BOOLEAN,
    precio_kg       NUMERIC(10,4),
    sin_precio      BOOLEAN
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'public'
AS $$
    WITH partidas AS (
        -- DISTINCT ON (p.id): all lots in a partida share the same articulo_tipo/fibra;
        -- take the first to avoid row multiplication from multiple assigned lots.
        SELECT DISTINCT ON (p.id)
            p.id                          AS partida_id,
            p.color_x_cliente_id,
            p.tercero_id,
            p.tenido_id,
            p.flg_antipilling,
            p.articulo_tipo_id::smallint  AS articulo_tipo_id,
            ar.fibra::smallint            AS fibra,
            -- Distinct completed operaciones across ALL ops for this partida (repartida included)
            ARRAY(
                SELECT DISTINCT opp.operacion_id
                FROM mes.partida_paso opp
                WHERE opp.partida_id = p.id
                  AND EXISTS (
                      SELECT 1 FROM mes.partida_paso_ejecucion pe_c
                      WHERE pe_c.partida_paso_id = opp.id AND pe_c.estado = 'COMPLETADO'
                  )
            ) AS operacion_ids
        FROM mes.partida p
        -- fibra only — articulo_tipo_id comes directly from partida
        JOIN mes.partida_componente opi ON opi.partida_id = p.id AND opi.lote_id IS NOT NULL
        JOIN inventario.lote opi_l      ON opi_l.id = opi.lote_id
        JOIN item_rollo_detalle ird      ON ird.item_id = opi_l.item_id
        JOIN articulo ar                 ON ar.id = ird.articulo_id
        WHERE p.id = ANY(p_partida_ids) AND p.fyh_elm IS NULL
        ORDER BY p.id
    ),
    lineas AS (
        -- Base line per completed operacion
        SELECT
            pt.partida_id,
            op.id::smallint                         AS operacion_id,
            op.nombre                               AS operacion,
            false                                   AS es_antipilling,
            doc.fn_get_precio(
                op.id::smallint,
                pt.color_x_cliente_id,
                pt.tercero_id,
                -- TENIDO: normalize article type to its pricing family (client-aware)
                CASE WHEN op.codigo = 'TENIDO'
                     THEN doc.fn_familia_precio(pt.articulo_tipo_id, pt.tercero_id)
                     ELSE pt.articulo_tipo_id END,
                CASE WHEN op.codigo = 'TENIDO' THEN pt.tenido_id ELSE NULL END,
                pt.fibra
            )                                       AS precio_kg
        FROM partidas pt
        JOIN LATERAL unnest(pt.operacion_ids) AS oid ON true
        JOIN mes.operacion op ON op.id = oid

        UNION ALL

        -- Antipilling service charge line: billed when TENIDO completed + partida has flag.
        -- Client-level only — only tercero_id matters (Urban vs others).
        SELECT
            pt.partida_id,
            antipil_op.id::smallint,
            'Antipilling',
            true,
            doc.fn_get_precio(
                antipil_op.id::smallint,
                NULL,
                pt.tercero_id,
                NULL, NULL, NULL
            )
        FROM partidas pt
        JOIN mes.operacion antipil_op ON antipil_op.codigo = 'ANTIPILLING'
        JOIN mes.operacion tenido_op  ON tenido_op.codigo  = 'TENIDO'
        WHERE pt.flg_antipilling = true
          AND tenido_op.id = ANY(pt.operacion_ids)
    )
    SELECT
        l.partida_id,
        l.operacion_id,
        l.operacion,
        l.es_antipilling,
        l.precio_kg,
        (l.precio_kg IS NULL) AS sin_precio
    FROM lineas l
    ORDER BY l.partida_id, l.operacion_id, l.es_antipilling;
$$;

-- ── Step 10: doc.vw_pendientes_facturacion — drop antipilling arg from fn_get_precio calls ──
CREATE OR REPLACE VIEW doc.vw_pendientes_facturacion AS
WITH lineas AS (
    SELECT
        lrd.entrega_id,              -- ingress entrega (material origin, client-recognizable)
        gr_ing.serie,
        gr_ing.correlativo,
        gr_ing.fecha_emision::DATE         AS fecha_emision,
        p.tercero_id,
        t.nombre                           AS cliente,
        p.id                               AS partida_id,
        o.id::SMALLINT                     AS operacion_id,
        o.nombre                           AS operacion,
        o.codigo                           AS op_codigo,
        false                              AS es_antipilling,
        p.articulo_tipo_id::SMALLINT       AS articulo_tipo_id,
        atn.nombre                         AS articulo_tipo,
        p.color_x_cliente_id,
        c.color,
        p.tenido_id,
        ten.tenido,
        ar.fibra::SMALLINT                 AS fibra,
        p.tercero_id                       AS partida_tercero_id,
        p.flg_antipilling,
        -- Billing weight: source_lote.cantidad = pre-production input weight (authoritative).
        -- Falls back to dispatch grd.cantidad for lotes predating origen_lote_id
        -- (historical data or MLR-confectioned rolls with no source lote).
        SUM(COALESCE(source_l.cantidad, grd.cantidad)) AS peso_kg
    FROM doc.entrega gr              -- DESPACHO_CLIENTE: billing trigger
    JOIN doc.entrega_tipo grt    ON grt.id = gr.entrega_tipo_id
                                      AND grt.codigo = 'DESPACHO_CLIENTE'
    JOIN doc.entrega_detalle grd ON grd.entrega_id = gr.id
    -- Dispatched lote is always a dyed OUTPUT lote (documento_tipo = 'partida_paso_ejecucion')
    JOIN inventario.lote l             ON l.id = grd.lote_id
                                      AND l.documento_tipo = 'partida_paso_ejecucion'
    -- Ingress entrega + source lote carried forward in lote_rollo_detalle by registrar_produccion
    LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    LEFT JOIN doc.entrega gr_ing          ON gr_ing.id = lrd.entrega_id
    -- Source lote: input lote before dyeing — used for billing weight (input weight)
    LEFT JOIN inventario.lote source_l          ON source_l.id = lrd.origen_lote_id
    -- Trace: output lote → ejecucion → paso → partida
    JOIN mes.partida_paso_ejecucion pe_out ON pe_out.id = l.documento_id
    JOIN mes.partida_paso opp_out ON opp_out.id = pe_out.partida_paso_id
    JOIN mes.partida p            ON p.id = opp_out.partida_id
                                          AND p.fyh_elm IS NULL
    JOIN tercero t                         ON t.id = p.tercero_id
    -- Only completed operations from the SAME partida that produced this output lote.
    -- A repartida roll is billed separately when its own output is dispatched.
    JOIN mes.partida_paso opp ON opp.partida_id = p.id
        AND EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe_c WHERE pe_c.partida_paso_id = opp.id AND pe_c.estado = 'COMPLETADO')
    JOIN mes.operacion o                   ON o.id = opp.operacion_id
    -- fibra needs articulo join; articulo_tipo_id comes directly from partida
    JOIN LATERAL (
        SELECT ar2.fibra
        FROM item_rollo_detalle ird2
        JOIN articulo ar2 ON ar2.id = ird2.articulo_id
        WHERE ird2.item_id = l.item_id
        LIMIT 1
    ) ar ON true
    JOIN articulo_tipo atn             ON atn.id = p.articulo_tipo_id
    JOIN color_x_cliente cxc           ON cxc.id = p.color_x_cliente_id
    JOIN public.color c                ON c.id = cxc.color_id
    LEFT JOIN tenido ten               ON ten.id = p.tenido_id
                                      AND o.codigo = 'TENIDO'
    WHERE gr.fyh_elm IS NULL
    GROUP BY
        lrd.entrega_id,
        gr_ing.serie, gr_ing.correlativo, gr_ing.fecha_emision,
        p.tercero_id, t.nombre,
        p.id, o.id, o.nombre, o.codigo,
        p.articulo_tipo_id, atn.nombre,
        p.color_x_cliente_id, c.color,
        p.tenido_id, ten.tenido,
        ar.fibra, p.flg_antipilling
),
-- Antipilling surcharge lines: one per TENIDO-completed+dispatched row where flag is set.
-- operacion_id is the ANTIPILLING ghost op — distinct from TENIDO for factura_detalle keying.
antipilling AS (
    SELECT
        l.entrega_id, l.serie, l.correlativo, l.fecha_emision,
        l.tercero_id, l.cliente, l.partida_id,
        (SELECT o.id FROM mes.operacion o WHERE o.codigo = 'ANTIPILLING')::SMALLINT AS operacion_id,
        'Antipilling'::TEXT AS operacion,
        'ANTIPILLING'::TEXT AS op_codigo,
        true                AS es_antipilling,
        l.articulo_tipo_id, l.articulo_tipo,
        l.color_x_cliente_id, l.color,
        l.tenido_id, l.tenido,
        l.fibra, l.partida_tercero_id, l.flg_antipilling,
        l.peso_kg
    FROM lineas l
    WHERE l.flg_antipilling = true
      AND l.op_codigo = 'TENIDO'
),
all_lineas AS (
    SELECT * FROM lineas
    UNION ALL
    SELECT * FROM antipilling
)
SELECT
    l.entrega_id,
    l.serie,
    l.correlativo,
    l.fecha_emision,
    l.tercero_id,
    l.cliente,
    l.partida_id,
    l.operacion_id,
    l.operacion,
    l.es_antipilling,
    l.articulo_tipo_id,
    l.articulo_tipo,
    l.color_x_cliente_id,
    l.color,
    l.tenido_id,
    l.tenido,
    l.peso_kg                               AS peso_total,
    billed.peso_facturado,
    l.peso_kg - billed.peso_facturado       AS peso_pendiente,
    px.precio_kg,
    ROUND((l.peso_kg - billed.peso_facturado) * px.precio_kg, 2) AS subtotal,
    (px.precio_kg IS NULL)                  AS sin_precio,
    -- "[tenido|operacion] [articulo_tipo] [color] - Ref. [ingress_serie]-[ingress_correlativo]"
    -- tenido name replaces operation name for TENIDO lines (client-facing, not internal op label)
    CASE WHEN l.es_antipilling
         THEN 'Antipilling'
         ELSE COALESCE(l.tenido, l.operacion)
    END
    || ' ' || l.articulo_tipo || ' ' || l.color
    || COALESCE(' - Ref. ' || l.serie || '-' || l.correlativo, '')
                                            AS descripcion
FROM all_lineas l
LEFT JOIN LATERAL (
    SELECT
        CASE WHEN l.es_antipilling
             -- ANTIPILLING op: client-level only — only tercero_id matters (Urban vs others)
             THEN doc.fn_get_precio(
                     l.operacion_id, NULL, l.partida_tercero_id,
                     NULL, NULL, NULL
                  )
             -- Base operacion: same precio_kg regardless of antipilling variant
             ELSE doc.fn_get_precio(
                     l.operacion_id, l.color_x_cliente_id, l.partida_tercero_id,
                     -- TENIDO: normalize article type to its pricing family (client-aware)
                     CASE WHEN l.op_codigo = 'TENIDO'
                          THEN doc.fn_familia_precio(l.articulo_tipo_id, l.partida_tercero_id)
                          ELSE l.articulo_tipo_id END,
                     CASE WHEN l.op_codigo = 'TENIDO' THEN l.tenido_id ELSE NULL END,
                     l.fibra
                  )
        END AS precio_kg
) px ON true
-- Quantity-based: row stays visible until all dispatched kg are invoiced.
-- Key: (ingress_entrega × partida × service dimensions) — supports partial billing.
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(fd.cantidad), 0) AS peso_facturado
    FROM doc.factura_detalle fd
    JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
    WHERE fd.entrega_id  IS NOT DISTINCT FROM l.entrega_id
      AND fd.partida_id         = l.partida_id
      AND fd.operacion_id       = l.operacion_id
      AND fd.articulo_tipo_id   = l.articulo_tipo_id
      AND fd.color_x_cliente_id = l.color_x_cliente_id
      AND fd.tenido_id IS NOT DISTINCT FROM l.tenido_id
      AND fd.es_antipilling     = l.es_antipilling
) billed ON true
WHERE l.peso_kg - billed.peso_facturado > 0.001;

-- ── Step 11: doc.vw_aprobados_sin_despacho — same fn_get_precio update ──
CREATE OR REPLACE VIEW doc.vw_aprobados_sin_despacho AS
WITH lineas AS (
    SELECT
        lrd.entrega_id,              -- ingress entrega (material origin)
        gr_ing.serie,
        gr_ing.correlativo,
        gr_ing.fecha_emision::DATE         AS fecha_emision,
        p.tercero_id,
        t.nombre                           AS cliente,
        p.id                               AS partida_id,
        o.id::SMALLINT                     AS operacion_id,
        o.nombre                           AS operacion,
        o.codigo                           AS op_codigo,
        false                              AS es_antipilling,
        p.articulo_tipo_id::SMALLINT       AS articulo_tipo_id,
        atn.nombre                         AS articulo_tipo,
        p.color_x_cliente_id,
        c.color,
        p.tenido_id,
        ten.tenido,
        ar.fibra::SMALLINT                 AS fibra,
        p.tercero_id                       AS partida_tercero_id,
        p.flg_antipilling,
        SUM(COALESCE(source_l.cantidad, l.cantidad)) AS peso_kg
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion pe_out ON pe_out.id = l.documento_id
    JOIN mes.partida_paso opp_out          ON opp_out.id = pe_out.partida_paso_id
    JOIN mes.partida p                     ON p.id = opp_out.partida_id AND p.fyh_elm IS NULL
    JOIN tercero t                         ON t.id = p.tercero_id
    LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    LEFT JOIN doc.entrega gr_ing          ON gr_ing.id = lrd.entrega_id
    LEFT JOIN inventario.lote source_l          ON source_l.id = lrd.origen_lote_id
    JOIN mes.partida_paso opp ON opp.partida_id = p.id
        AND EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe_c WHERE pe_c.partida_paso_id = opp.id AND pe_c.estado = 'COMPLETADO')
    JOIN mes.operacion o ON o.id = opp.operacion_id
    JOIN LATERAL (
        SELECT ar2.fibra
        FROM item_rollo_detalle ird2
        JOIN articulo ar2 ON ar2.id = ird2.articulo_id
        WHERE ird2.item_id = l.item_id
        LIMIT 1
    ) ar ON true
    JOIN articulo_tipo atn             ON atn.id = p.articulo_tipo_id
    JOIN color_x_cliente cxc           ON cxc.id = p.color_x_cliente_id
    JOIN public.color c                ON c.id = cxc.color_id
    LEFT JOIN tenido ten               ON ten.id = p.tenido_id AND o.codigo = 'TENIDO'
    WHERE
        l.documento_tipo = 'partida_paso_ejecucion'
        AND l.fyh_elm IS NULL
        AND NOT EXISTS (
            SELECT 1
            FROM doc.entrega_detalle grd2
            JOIN doc.entrega gr2       ON gr2.id = grd2.entrega_id AND gr2.fyh_elm IS NULL
            JOIN doc.entrega_tipo grt2 ON grt2.id = gr2.entrega_tipo_id
                                             AND grt2.codigo = 'DESPACHO_CLIENTE'
            WHERE grd2.lote_id = l.id
        )
    GROUP BY
        lrd.entrega_id,
        gr_ing.serie, gr_ing.correlativo, gr_ing.fecha_emision,
        p.tercero_id, t.nombre,
        p.id, o.id, o.nombre, o.codigo,
        p.articulo_tipo_id, atn.nombre,
        p.color_x_cliente_id, c.color,
        p.tenido_id, ten.tenido,
        ar.fibra, p.flg_antipilling
),
antipilling AS (
    SELECT
        l.entrega_id, l.serie, l.correlativo, l.fecha_emision,
        l.tercero_id, l.cliente, l.partida_id,
        (SELECT o.id FROM mes.operacion o WHERE o.codigo = 'ANTIPILLING')::SMALLINT AS operacion_id,
        'Antipilling'::TEXT AS operacion,
        'ANTIPILLING'::TEXT AS op_codigo,
        true                AS es_antipilling,
        l.articulo_tipo_id, l.articulo_tipo,
        l.color_x_cliente_id, l.color,
        l.tenido_id, l.tenido,
        l.fibra, l.partida_tercero_id, l.flg_antipilling,
        l.peso_kg
    FROM lineas l
    WHERE l.flg_antipilling = true
      AND l.op_codigo = 'TENIDO'
),
all_lineas AS (
    SELECT * FROM lineas
    UNION ALL
    SELECT * FROM antipilling
)
SELECT
    l.entrega_id,
    l.serie,
    l.correlativo,
    l.fecha_emision,
    l.tercero_id,
    l.cliente,
    l.partida_id,
    l.operacion_id,
    l.operacion,
    l.es_antipilling,
    l.articulo_tipo_id,
    l.articulo_tipo,
    l.color_x_cliente_id,
    l.color,
    l.tenido_id,
    l.tenido,
    l.peso_kg                               AS peso_total,
    billed.peso_facturado,
    l.peso_kg - billed.peso_facturado       AS peso_pendiente,
    px.precio_kg,
    ROUND((l.peso_kg - billed.peso_facturado) * px.precio_kg, 2) AS subtotal,
    (px.precio_kg IS NULL)                  AS sin_precio,
    CASE WHEN l.es_antipilling
         THEN 'Antipilling'
         ELSE COALESCE(l.tenido, l.operacion)
    END
    || ' ' || l.articulo_tipo || ' ' || l.color
    || COALESCE(' - Ref. ' || l.serie || '-' || l.correlativo, '')
                                            AS descripcion
FROM all_lineas l
LEFT JOIN LATERAL (
    SELECT
        CASE WHEN l.es_antipilling
             THEN doc.fn_get_precio(
                     l.operacion_id, NULL, l.partida_tercero_id,
                     NULL, NULL, NULL
                  )
             ELSE doc.fn_get_precio(
                     l.operacion_id, l.color_x_cliente_id, l.partida_tercero_id,
                     CASE WHEN l.op_codigo = 'TENIDO'
                          THEN doc.fn_familia_precio(l.articulo_tipo_id, l.partida_tercero_id)
                          ELSE l.articulo_tipo_id END,
                     CASE WHEN l.op_codigo = 'TENIDO' THEN l.tenido_id ELSE NULL END,
                     l.fibra
                  )
        END AS precio_kg
) px ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(fd.cantidad), 0) AS peso_facturado
    FROM doc.factura_detalle fd
    JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
    WHERE fd.entrega_id  IS NOT DISTINCT FROM l.entrega_id
      AND fd.partida_id         = l.partida_id
      AND fd.operacion_id       = l.operacion_id
      AND fd.articulo_tipo_id   = l.articulo_tipo_id
      AND fd.color_x_cliente_id = l.color_x_cliente_id
      AND fd.tenido_id IS NOT DISTINCT FROM l.tenido_id
      AND fd.es_antipilling     = l.es_antipilling
) billed ON true
WHERE l.peso_kg - billed.peso_facturado > 0.001;

-- ── Step 11b: doc.registrar_despacho (funciones/despacho.sql) — same fn_get_precio
-- fallback lookup, also passes v_partida.flg_antipilling as the 7th arg. This is
-- the venta-module dispatch entry point (mid-flight, uncommitted elsewhere in this
-- repo) — included here so the live function doesn't break once the old overload
-- is dropped below. Only the fn_get_precio call changes; rest of the body is
-- reproduced as-is. Note: unlike fn_precio_info/get_precios_partida, this call
-- site never normalized articulo_tipo_id via fn_familia_precio for TENIDO —
-- pre-existing gap, out of scope here, left as found.
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
    FOR v_tipo_codigo IN SELECT unnest(ARRAY['VENTA_EGRESO','DESPACHO_CLIENTE'])
    LOOP
        SELECT jsonb_agg(item) INTO v_items_grupo
        FROM jsonb_array_elements(p_datos->'items') item
        WHERE (v_tipo_codigo = 'VENTA_EGRESO'    AND (item->>'propietario_id')::int = 1)
           OR (v_tipo_codigo = 'DESPACHO_CLIENTE' AND (item->>'propietario_id')::int IS DISTINCT FROM 1);

        CONTINUE WHEN v_items_grupo IS NULL;

        SELECT id INTO v_tipo_id FROM doc.entrega_tipo WHERE codigo = v_tipo_codigo;
        v_guia := (p_datos->'guias')->v_tipo_codigo;

        PERFORM doc.crear_entrega(jsonb_build_object(
            'entrega_tipo_id', v_tipo_id,
            'tercero_id',      v_tercero_id,
            'serie',           v_guia->>'serie',
            'correlativo',     v_guia->>'correlativo',
            'fecha_emision',   COALESCE(v_guia->>'fecha_emision', now()::text),
            'items',           v_items_grupo
        ));

        SELECT currval(pg_get_serial_sequence('doc.entrega','id')) INTO v_entrega_id;
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

        -- Ownership guard: this cargo's dispatched items (by root partida) must not mix owners.
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
                v_partida.fibra
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

-- ── Step 13: recreate doc.vw_precios_pendientes without the variant dimension ──
-- One row per missing (operacion, client/color, articulo_tipo, tenido, fibra)
-- combo — no more false/true expansion for TENIDO.
CREATE OR REPLACE VIEW doc.vw_precios_pendientes AS
SELECT DISTINCT
    op.id                   AS operacion_id,
    op.nombre               AS operacion,
    p.color_x_cliente_id,
    cxc.color_id,
    c.color,
    cxc.tercero_id,
    t.nombre                AS cliente,
    p.articulo_tipo_id,
    aty.nombre              AS articulo_tipo,
    CASE WHEN op.codigo = 'TENIDO' THEN p.tenido_id ELSE NULL END AS tenido_id,
    ten.tenido,
    ar.fibra
FROM mes.partida p
JOIN color_x_cliente cxc           ON cxc.id = p.color_x_cliente_id
JOIN public.color c                ON c.id   = cxc.color_id
JOIN tercero t                     ON t.id   = cxc.tercero_id
JOIN mes.partida_paso opp ON opp.partida_id = p.id
    AND EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe_c WHERE pe_c.partida_paso_id = opp.id AND pe_c.estado = 'COMPLETADO')
JOIN mes.operacion op              ON op.id = opp.operacion_id
CROSS JOIN LATERAL (
    SELECT ar2.fibra::smallint AS fibra
    FROM mes.partida_componente opi2
    JOIN inventario.lote opi2_l  ON opi2_l.id = opi2.lote_id
    JOIN item_rollo_detalle ird2 ON ird2.item_id = opi2_l.item_id
    JOIN articulo ar2            ON ar2.id = ird2.articulo_id
    WHERE opi2.partida_id = p.id AND opi2.lote_id IS NOT NULL
    LIMIT 1
) ar
JOIN public.articulo_tipo aty    ON aty.id = p.articulo_tipo_id
LEFT JOIN tenido ten             ON ten.id = p.tenido_id AND op.codigo = 'TENIDO'
WHERE
    p.fyh_elm IS NULL
    AND p.estado_facturacion <> 'facturado'
    AND NOT EXISTS (
        SELECT 1 FROM doc.catalogo_precios cp
        WHERE cp.operacion_id = op.id
          AND (cp.color_x_cliente_id IS NULL OR cp.color_x_cliente_id = p.color_x_cliente_id)
          AND (cp.tercero_id         IS NULL OR cp.tercero_id         = p.tercero_id)
          -- TENIDO: compare against the pricing family (client-aware), not the literal type
          AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   =
                CASE WHEN op.codigo = 'TENIDO'
                     THEN doc.fn_familia_precio(p.articulo_tipo_id, p.tercero_id)
                     ELSE p.articulo_tipo_id END)
          AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p.tenido_id)
          AND (cp.fibra              IS NULL OR cp.fibra              = ar.fibra)
          AND cp.fyh_elm IS NULL
    )
    -- TENIDO only: require an approved recipe (any variant) — no recipe means no cost basis
    AND (op.codigo <> 'TENIDO' OR EXISTS (
        SELECT 1 FROM receta.tenido rt
        WHERE rt.flg_produccion = true
          AND (rt.color_x_cliente_id IS NULL OR rt.color_x_cliente_id = p.color_x_cliente_id)
          AND rt.articulo_tipo_id = p.articulo_tipo_id
          AND rt.fibra = ar.fibra
          AND (rt.tenido_id IS NULL OR rt.tenido_id = p.tenido_id)
    ));

-- ── Step 14: recreate doc.vw_catalogo_precios_historico without the column ──
CREATE OR REPLACE VIEW doc.vw_catalogo_precios_historico AS
SELECT
    cp.id,
    cp.operacion_id,
    op.nombre               AS operacion,
    cp.color_x_cliente_id,
    c.color,
    cp.tercero_id,
    t.nombre                AS cliente,
    cp.articulo_tipo_id,
    aty.nombre               AS articulo_tipo,
    cp.tenido_id,
    ten.tenido,
    cp.fibra,
    cp.precio_kg,
    cp.costo_kg,
    cp.usr_cre,
    cp.fyh_cre,
    cp.usr_elm,
    cp.fyh_elm,
    (cp.fyh_elm IS NULL)     AS activo
FROM doc.catalogo_precios cp
JOIN mes.operacion op             ON op.id = cp.operacion_id
LEFT JOIN color_x_cliente cxc     ON cxc.id = cp.color_x_cliente_id
LEFT JOIN public.color c          ON c.id   = cxc.color_id
LEFT JOIN tercero t                ON t.id   = COALESCE(cp.tercero_id, cxc.tercero_id)
LEFT JOIN public.articulo_tipo aty ON aty.id = cp.articulo_tipo_id
LEFT JOIN tenido ten                ON ten.id = cp.tenido_id
ORDER BY cp.fyh_cre DESC;

-- ── Step 15: grants ──
GRANT SELECT ON doc.vw_catalogo_precios_historico TO authenticated;
GRANT SELECT ON doc.vw_precios_pendientes         TO authenticated;
GRANT SELECT ON doc.vw_pendientes_facturacion     TO authenticated;
GRANT SELECT ON doc.vw_aprobados_sin_despacho     TO authenticated;
GRANT EXECUTE ON FUNCTION doc.upsert_catalogo_precio(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_precios_partida(BIGINT[])                                                 TO authenticated;
GRANT EXECUTE ON FUNCTION doc.fn_precio_info(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, BOOLEAN)          TO authenticated;

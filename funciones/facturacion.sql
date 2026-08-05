-- ═══════════════════════════════════════════════════════════════
-- Facturación / Pricing functions
-- Depends on: migration/07 (doc.catalogo_precios, doc.factura),
--             migration/05 (inventario.lote), funciones/core.sql
--
-- Pricing workflow:
--   1. Client onboarded → insert ANTIPILLING wildcard row (tercero_id, precio_kg=0.15/0.10)
--   2. Recipe approved → vw_precios_pendientes surfaces the gap
--   3. Admin calls fn_precio_info (optionally twice, flg_antipilling=false/true, to
--      compare both recipe variants' cost/margin), then upsert_catalogo_precio ONCE
--      — precio_kg is a single row, same rate with or without antipilling.
--   4. Dispatch → vw_pendientes_facturacion → registrar_factura_cliente
--
-- Antipilling:
--   Two separate concerns:
--   a) receta.tenido rows have flg_antipilling=false/true — the recipe used
--      (antipilling recipe uses different/more chemicals → higher costo_kg).
--      catalogo_precios does NOT carry this dimension — precio_kg is the same
--      for both variants; costo_kg on the catalog row is a non-authoritative
--      snapshot only (see patch 46 for the full history — flg_antipilling was
--      removed from catalogo_precios after a stopgap index widening).
--   b) ANTIPILLING ghost operation row (client wildcard) — the service charge billed
--      as a separate invoice line when partida.flg_antipilling = true
--   Legacy equivalent: adicional_id=0/1 rows + hardcoded CASE WHEN cliente='Urban'
-- ═══════════════════════════════════════════════════════════════


-- ── doc.fn_get_precio ─────────────────────────────────────────
-- Returns the applicable precio_kg for a given service combination.
--
-- NULL dimensions in catalog rows are wildcards: a row with
-- color_x_cliente_id = NULL matches any client/color value.
-- Match priority: most non-NULL dimensions matched first (most specific).
-- Tie-break: most recently created row (fyh_cre DESC).
-- Returns NULL if no active catalog entry covers the combination.
--
-- ⚠ NO NULL GUARD HERE, DELIBERATELY. A NULL p_grupo_articulo_id matches only
-- WILDCARD rows and silently returns the wrong price — so a guard is tempting.
-- But this is LANGUAGE sql precisely so the planner INLINES it into
-- vw_precios_estado / vw_pendientes_facturacion / vw_aprobados_sin_despacho,
-- which call it per row; converting to plpgsql to allow RAISE would make it an
-- opaque per-row call in all three. The guard lives in the plpgsql entry points
-- instead (fn_precio_info, upsert_catalogo_precio) — those are the RPC surface
-- where a caller can actually supply a bad key. The views cannot: partida
-- .grupo_articulo_id is NOT NULL as of migration 32.
CREATE OR REPLACE FUNCTION doc.fn_get_precio(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,
    p_tercero_id          INT,
    p_grupo_articulo_id   INT,
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
        AND (cp.grupo_articulo_id  IS NULL OR cp.grupo_articulo_id  = p_grupo_articulo_id)
        AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p_tenido_id)
        AND (cp.fibra              IS NULL OR cp.fibra              = p_fibra)
        AND cp.fyh_elm IS NULL
    ORDER BY
        -- color_x_cliente_id wins over tercero_id (implies the client + specific color)
        (CASE WHEN cp.color_x_cliente_id IS NOT NULL THEN 2 ELSE 0 END
       + CASE WHEN cp.tercero_id         IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN cp.grupo_articulo_id  IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN cp.tenido_id          IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN cp.fibra              IS NOT NULL THEN 1 ELSE 0 END) DESC,
        cp.fyh_cre DESC
    LIMIT 1;
$$;


-- ── doc.fn_familia_precio ─────────────────────────────────────
-- Maps a grupo_articulo to its commercial PRICING family (bucket).
-- Replaces the legacy hardcoded CASE that normalized tipo_articulo_id before
-- matching catalogo_precios. The mapping lives as data in
-- doc.articulo_tipo_familia (seeded in
-- migration/patches/25_articulo_tipo_familia.sql, re-keyed onto grupo in
-- migration/33 — the table keeps its legacy NAME until migration 34 renames it
-- to doc.grupo_articulo_familia):
--   - tercero_id IS NULL → default family for all clients
--   - tercero_id = <id>  → per-client override (flat-rate clients → family 20)
-- Client-specific row wins over the default; no mapping → prices as itself.
--
-- Used ONLY for the TENIDO price lookup. Recipes match on the LITERAL
-- grupo_articulo and must NOT be normalized.
--
-- ⚠ ONE HOP ONLY, over a SELF-REFERENCING table. familia_grupo_id points at a
-- grupo used as a bucket label, so a bucket head can itself be mapped — and one
-- is: defaults send 4,9→18 while the flat-rate override sends 4,9→20. That
-- resolves correctly today only because ORDER BY picks the client row first.
-- Do NOT add a third mapping layer; fix it properly with the doc.familia_precio
-- header (GRUPO_ARTICULO_HANDOFF.md backlog).
--
-- ⚠ Returns INT now, not SMALLINT — it feeds fn_get_precio's
-- p_grupo_articulo_id. Callers that cast the result to SMALLINT will truncate
-- once grupo ids exceed 32767.
CREATE OR REPLACE FUNCTION doc.fn_familia_precio(
    p_grupo_articulo_id INT,
    p_tercero_id        INT
)
RETURNS INT
LANGUAGE sql STABLE
SET search_path TO 'doc', 'public'
AS $$
    SELECT COALESCE(
        (SELECT f.familia_grupo_id
         FROM doc.articulo_tipo_familia f
         WHERE f.grupo_articulo_id = p_grupo_articulo_id
           AND (f.tercero_id = p_tercero_id OR f.tercero_id IS NULL)
         ORDER BY f.tercero_id NULLS LAST   -- specific client beats default
         LIMIT 1),
        p_grupo_articulo_id                 -- no mapping → itself
    );
$$;


-- ── doc.upsert_familia_precio ─────────────────────────────────
-- Creates or updates a grupo_articulo → pricing-family mapping, read back
-- by fn_familia_precio above. Applies to TENIDO pricing only.
--   - p_tercero_id NULL → default mapping for all clients
--   - p_tercero_id <id> → per-client override
--
-- Legacy articulo_tipo_id/familia_id columns are left NULL on every write
-- here on purpose — they're being phased out (migration 34 drops them; see
-- migration/patches/49, which dropped their NOT NULL so this insert is even
-- possible). Do not backfill them from grupo_articulo.origen_articulo_tipo_id.
--
-- Manual dedup instead of relying on the table's unique indexes:
-- uq_articulo_tipo_familia_default/_cliente are still partial indexes on the
-- legacy articulo_tipo_id column (index swap onto grupo_articulo_id is also
-- part of 34) and Postgres never treats NULL = NULL, so they cannot catch a
-- duplicate mapping for a grupo written through this function.
CREATE OR REPLACE FUNCTION doc.upsert_familia_precio(
    p_grupo_articulo_id  INT,
    p_tercero_id         INT,          -- NULL = default for all clients
    p_familia_grupo_id   INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $$
DECLARE
    v_usr_id INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_grupo_articulo_id IS NULL OR p_familia_grupo_id IS NULL THEN
        RAISE EXCEPTION 'grupo_articulo_id y familia_grupo_id son obligatorios';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('upsert_familia_precio', v_usr_id, jsonb_build_object(
        'grupo_articulo_id', p_grupo_articulo_id,
        'tercero_id', p_tercero_id,
        'familia_grupo_id', p_familia_grupo_id
    ));

    UPDATE doc.articulo_tipo_familia
    SET familia_grupo_id = p_familia_grupo_id,
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE grupo_articulo_id = p_grupo_articulo_id
      AND tercero_id IS NOT DISTINCT FROM p_tercero_id;

    IF NOT FOUND THEN
        INSERT INTO doc.articulo_tipo_familia
            (grupo_articulo_id, tercero_id, familia_grupo_id, usr_cre)
        VALUES
            (p_grupo_articulo_id, p_tercero_id, p_familia_grupo_id, v_usr_id);
    END IF;
END;
$$;


-- ── doc.fn_get_costo_receta ───────────────────────────────────
-- Returns the chemical cost per kg of fabric for a given dyeing recipe.
-- Unit conversion via item_insumo_detalle.medida (canonical unit per item):
--   g/L → quantity × 5 L/kg liquor ratio ÷ 1000 g/kg  (matches legacy view logic)
--   %   → quantity × 10 g/L per % ÷ 1000 g/kg
-- factor_stock applied after unit conversion: recipe quantities are in usage-form units
-- (e.g. diluted solution), price is per solid-equivalent kg from stock.
--
-- Price source priority:
--   1. Most recent doc.factura_proveedor_detalle.precio_unitario
--      (actual invoice price, ex-IGV — authoritative per migration/16)
--   2. Most recent doc.compra_detalle.precio_unitario
--      (estimated/agreed price — fallback when invoice not yet received)
--
-- Returns NULL if the recipe has no insumos or no price data found for any insumo.
-- Returns 0 if all prices resolve to 0 (e.g. items with zero cost).
CREATE OR REPLACE FUNCTION doc.fn_get_costo_receta(p_receta_id INT)
RETURNS NUMERIC(10,4)
LANGUAGE sql STABLE
SET search_path TO 'receta', 'doc', 'public'
AS $$
    SELECT ROUND(
        SUM(
            tpi.cantidad
            * CASE iid.medida
                WHEN 'g/L' THEN (5.0  / 1000.0)
                WHEN '%'   THEN (10.0 / 1000.0)
                ELSE            (1.0  / 1000.0)
              END
            * iid.factor_stock
            * COALESCE(
                -- Authoritative: latest supplier invoice line (ex-IGV)
                (
                    SELECT fpd.precio_unitario
                    FROM doc.factura_proveedor_detalle fpd
                    WHERE fpd.item_id = tpi.item_id
                    ORDER BY fpd.fyh_cre DESC
                    LIMIT 1
                ),
                -- Fallback: latest purchase order estimated price
                (
                    SELECT cd.precio_unitario
                    FROM doc.compra_detalle cd
                    WHERE cd.item_id = tpi.item_id
                    ORDER BY cd.fyh_cre DESC
                    LIMIT 1
                ),
                0
            )
        ),
        4
    )
    FROM receta.tenido_paso tp
    JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
    JOIN public.item_insumo_detalle iid ON iid.item_id = tpi.item_id
    WHERE tp.receta_id = p_receta_id;
$$;


-- ── doc.fn_precio_info ────────────────────────────────────────
-- Pricing UI helper: returns current chemical cost, active catalog
-- price, and derived margin for a given TENIDO service combination.
-- Designed to power the price-setting form.
--
-- Lookup:
--   - Finds the approved recipe (flg_produccion = true) matching the
--     dyeing dimensions (color_x_cliente_id, grupo_articulo_id, fibra,
--     tenido_id, flg_antipilling).
--   - Computes chemical cost via fn_get_costo_receta.
--   - Fetches current catalog price via fn_get_precio.
--
-- margen = (precio_kg - costo_kg) / precio_kg (NULL if no price set).
-- p_flg_antipilling drives the recipe lookup only (for costo_kg) — it is NOT
-- passed to the catalog lookup, which has no antipilling dimension: precio_kg
-- is the same whether or not antipilling applies.
-- Pass NULL for non-TENIDO operations — returns price only, no cost.
--
-- For the price-setting form: call twice (false + true) to compare both
-- recipe variants' cost/margin against the single precio_kg being set.
CREATE OR REPLACE FUNCTION doc.fn_precio_info(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,
    p_tercero_id          INT,
    p_grupo_articulo_id   INT,
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

    -- ⚠ NULL-KEY GUARD — TENIDO ONLY, deliberately narrow. This is the RPC
    -- surface: a caller still sending the retired articulo_tipo key, or a
    -- partida predating migration 30, arrives here as NULL. Without a guard
    -- fn_get_precio's `cp.grupo_articulo_id = p_grupo_articulo_id` equality
    -- never holds, so ONLY wildcard rows match and a plausible-looking wrong
    -- price comes back with no error.
    --
    -- Why NOT unconditional: NULL is a LEGITIMATE value here for operations
    -- with no article dimension — the ANTIPILLING lookup passes NULL for
    -- grupo/tenido/fibra by design (see get_precios_partida), and that must keep
    -- resolving its client-level wildcard row. Guarding every op would break it.
    -- TENIDO is the only operation that genuinely requires the key, because it
    -- is the only one routed through fn_familia_precio.
    --
    -- (fn_get_precio itself has no guard on purpose — it is LANGUAGE sql so the
    -- planner can inline it into the per-row billing views. See its header.)
    IF p_grupo_articulo_id IS NULL
       AND p_operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO') THEN
        RAISE EXCEPTION 'fn_precio_info: TENIDO requiere grupo_articulo_id (recibido NULL). '
                        'El key articulo_tipo_id fue retirado en la migración 33.'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    -- Find approved recipe matching p_flg_antipilling variant.
    -- NULL → skip recipe lookup (non-TENIDO or ANTIPILLING op).
    IF p_flg_antipilling IS NOT NULL THEN
        SELECT rt.id INTO v_receta_id
        FROM receta.tenido rt
        WHERE rt.color_x_cliente_id = p_color_x_cliente_id
          AND rt.grupo_articulo_id  = p_grupo_articulo_id
          AND rt.fibra               = p_fibra
          AND rt.tenido_id           = p_tenido_id
          AND rt.flg_antipilling     = p_flg_antipilling
          AND rt.flg_produccion      = true
          -- receta.tenido is shared across recipe types; pin to Teñido (7) so a
          -- desmontado/rebaje row on the same keys can't be returned. Matches the
          -- gate in doc.vw_precios_pendientes.
          AND rt.tipo_receta_id      = 7
        LIMIT 1;
    END IF;

    -- Compute chemical cost (NULL if no recipe)
    IF v_receta_id IS NOT NULL THEN
        v_costo_kg := doc.fn_get_costo_receta(v_receta_id);
    END IF;

    -- Fetch current catalog price. TENIDO: normalize the grupo to its pricing
    -- family so the preview shows the price that will actually bill. Recipe
    -- lookup above stays on the LITERAL grupo. No antipilling dimension in the
    -- catalog lookup — both variants bill at the same precio_kg.
    v_precio_kg := doc.fn_get_precio(
        p_operacion_id, p_color_x_cliente_id, p_tercero_id,
        CASE WHEN p_operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
             THEN doc.fn_familia_precio(
                    p_grupo_articulo_id,
                    COALESCE(p_tercero_id,
                             (SELECT cxc.tercero_id FROM color_x_cliente cxc WHERE cxc.id = p_color_x_cliente_id)))
             ELSE p_grupo_articulo_id END,
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

-- ── doc.upsert_catalogo_precio ────────────────────────────────
-- Changes a price: closes the currently active row (sets fyh_elm)
-- and inserts a new active row. Both happen atomically.
-- Returns the new row id.
--
-- costo_kg is a non-authoritative cost snapshot only (see patch 46) —
-- catalogo_precios has no antipilling dimension, so this just grabs
-- whichever approved recipe matches the other dimensions (base preferred,
-- tie-broken by most recently approved). Does not update automatically if
-- purchase prices or the recipe change later; fn_precio_info recomputes
-- cost live for margin preview, so this snapshot is informational only.
--
-- Replaces the legacy insertar_catalogo_precio_v2 pattern.
--
-- ⚠ NO NULL GUARD on p_grupo_articulo_id, unlike fn_precio_info. NULL here is
-- MEANINGFUL, not a mistake: it is how a WILDCARD catalog row is created ("this
-- price applies to any substrate"), which is exactly how the ANTIPILLING
-- client-level rows are stored. Guarding it would make wildcard rows
-- uncreatable and break the client-onboarding step in the header workflow.
CREATE OR REPLACE FUNCTION doc.upsert_catalogo_precio(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,          -- set for color-specific rate
    p_tercero_id          INT,          -- set for client flat rate (mutually exclusive with above)
    p_grupo_articulo_id   INT,          -- NULL = wildcard row (any substrate)
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
        'grupo_articulo_id', p_grupo_articulo_id,
        'tenido_id', p_tenido_id,
        'fibra', p_fibra,
        'precio_kg', p_precio_kg
    ));

    IF p_color_x_cliente_id IS NOT NULL AND p_tercero_id IS NOT NULL THEN
        RAISE EXCEPTION 'color_x_cliente_id and tercero_id are mutually exclusive';
    END IF;

    SELECT id INTO v_tenido_op_id FROM mes.operacion WHERE codigo = 'TENIDO';

    -- Cost snapshot is contextual only — no longer tied to a specific recipe
    -- variant. Grab whichever approved recipe matches the other dimensions;
    -- prefer the base (non-antipilling) one, tie-break most recent.
    IF p_operacion_id = v_tenido_op_id THEN
        SELECT rt.id INTO v_receta_id
        FROM receta.tenido rt
        WHERE rt.color_x_cliente_id = p_color_x_cliente_id
          AND rt.grupo_articulo_id  = p_grupo_articulo_id
          AND rt.fibra               = p_fibra
          AND rt.tenido_id           = p_tenido_id
          AND rt.flg_produccion      = true
          -- receta.tenido is shared across recipe types; pin to Teñido (7) so the
          -- cost snapshot can't be taken from a desmontado/rebaje row on the same
          -- keys. Matches the gate in doc.vw_precios_pendientes.
          AND rt.tipo_receta_id      = 7
        ORDER BY rt.flg_antipilling ASC, rt.fyh_produccion DESC NULLS LAST
        LIMIT 1;

        IF v_receta_id IS NOT NULL THEN
            v_costo_kg := doc.fn_get_costo_receta(v_receta_id);
        END IF;
    END IF;

    -- Normalize the TENIDO grupo to its pricing family AFTER the recipe/cost
    -- lookup above (recipes match the LITERAL grupo) so the catalog row is stored
    -- under the same bucket the price lookup normalizes to.
    IF p_operacion_id = v_tenido_op_id THEN
        p_grupo_articulo_id := doc.fn_familia_precio(
            p_grupo_articulo_id,
            COALESCE(p_tercero_id,
                     (SELECT cxc.tercero_id FROM color_x_cliente cxc WHERE cxc.id = p_color_x_cliente_id))
        );
    END IF;

    -- The COALESCE(...,-1) shape must stay in lockstep with
    -- uq_catalogo_precios_activo (re-keyed onto grupo_articulo_id in
    -- migration/33b). If they diverge, this close-then-insert stops matching the
    -- row the index considers a duplicate and the INSERT below fails on the
    -- unique violation instead of replacing cleanly.
    UPDATE doc.catalogo_precios
    SET fyh_elm = NOW(), usr_elm = v_usr_id
    WHERE
        operacion_id = p_operacion_id
        AND COALESCE(color_x_cliente_id,   -1) = COALESCE(p_color_x_cliente_id,   -1)
        AND COALESCE(tercero_id,           -1) = COALESCE(p_tercero_id,           -1)
        AND COALESCE(grupo_articulo_id,    -1) = COALESCE(p_grupo_articulo_id,    -1)
        AND COALESCE(tenido_id,            -1) = COALESCE(p_tenido_id,            -1)
        AND COALESCE(fibra::int,           -1) = COALESCE(p_fibra::int,           -1)
        AND fyh_elm IS NULL;

    INSERT INTO doc.catalogo_precios (
        operacion_id, color_x_cliente_id, tercero_id, grupo_articulo_id,
        tenido_id, fibra, precio_kg, costo_kg, usr_cre
    ) VALUES (
        p_operacion_id, p_color_x_cliente_id, p_tercero_id, p_grupo_articulo_id,
        p_tenido_id, p_fibra, p_precio_kg, v_costo_kg, v_usr_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;


-- ── doc.get_precios_partida ───────────────────────────────────
-- Returns resolved price lines for a set of partidas.
-- One row per completed operacion per partida, plus a second row
-- for antipilling when partida.flg_antipilling = true.
--
-- All dimensions come directly from mes.partida — including fibra
-- (declared at partida creation, see funciones/core.sql crear_partida).
-- No roll lookup: pricing must not depend on partida_componente still
-- holding assigned rolls (they can move off — reproceso reassignment,
-- full consumption, dispatch — while the partida keeps its own pricing
-- identity and completed-step history).
-- sin_precio = true flags combinations missing from the catalog.
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
        SELECT
            p.id                          AS partida_id,
            p.color_x_cliente_id,
            p.tercero_id,
            p.tenido_id,
            p.flg_antipilling,
            p.grupo_articulo_id           AS grupo_articulo_id,
            p.fibra::smallint             AS fibra,
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
        WHERE p.id = ANY(p_partida_ids) AND p.fyh_elm IS NULL
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
                -- TENIDO: normalize the grupo to its pricing family (client-aware)
                CASE WHEN op.codigo = 'TENIDO'
                     THEN doc.fn_familia_precio(pt.grupo_articulo_id, pt.tercero_id)
                     ELSE pt.grupo_articulo_id END,
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


-- ── doc.vw_precios_estado ─────────────────────────────────────
-- Every billable combination produced by active partidas, WITH its currently
-- resolved rate. One row per (operacion, client/color, articulo_tipo, tenido,
-- fibra) combo; estado says whether that combo already has a price.
--
--   estado = 'sin_precio'  → no active catalog row resolves; needs a rate set
--   estado = 'con_precio'  → precio_kg is the rate that will actually bill
--
-- TENIDO does not expand into false/true antipilling variants — catalogo_precios
-- prices the base and antipilling recipe the same (flg_antipilling was removed
-- from the pricing dimensions; see patch 46).
--
-- The price is resolved through doc.fn_get_precio — the SAME function billing
-- uses — instead of a local EXISTS. That matters: fn_get_precio scores by
-- specificity and carries the color_x_cliente-vs-tercero guard, so a combo can
-- never be listed as pending here while billing quietly resolves a wildcard for
-- it (or the reverse). Do not reintroduce a second matching implementation.
--
-- No catalog row id is exposed on purpose: upsert_catalogo_precio keys on the
-- dimensions, not on a row id, so these columns are already everything the
-- pricing drawer needs to set or change a rate.
--
-- ⚠ BREAKING COLUMN RENAME (migration 33): articulo_tipo_id/articulo_tipo →
-- grupo_articulo_id/grupo_articulo. The pricing drawer selects these by name and
-- must move in the same deploy. Renamed rather than aliased to the old names on
-- purpose — a silent alias would leave the frontend sending a key that no longer
-- means what it says, which is the failure this migration exists to end.
CREATE OR REPLACE VIEW doc.vw_precios_estado AS
WITH combos AS (
    SELECT DISTINCT
        op.id                   AS operacion_id,
        op.codigo               AS operacion_codigo,
        op.nombre               AS operacion,
        p.color_x_cliente_id,
        cxc.color_id,
        c.color,
        cxc.tercero_id,
        t.nombre                AS cliente,
        p.grupo_articulo_id,
        ga.nombre               AS grupo_articulo,
        CASE WHEN op.codigo = 'TENIDO' THEN p.tenido_id ELSE NULL END AS tenido_id,
        ten.tenido,
        p.fibra
    FROM mes.partida p
    JOIN color_x_cliente cxc           ON cxc.id = p.color_x_cliente_id
    JOIN public.color c                ON c.id   = cxc.color_id
    JOIN tercero t                     ON t.id   = cxc.tercero_id
    JOIN mes.partida_paso opp ON opp.partida_id = p.id
        AND EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe_c WHERE pe_c.partida_paso_id = opp.id AND pe_c.estado = 'COMPLETADO')
    JOIN mes.operacion op              ON op.id = opp.operacion_id
    -- INNER JOIN is safe: partida.grupo_articulo_id is NOT NULL as of migration 32.
    JOIN grupo_articulo ga           ON ga.id  = p.grupo_articulo_id
    LEFT JOIN tenido ten             ON ten.id = p.tenido_id AND op.codigo = 'TENIDO'
    WHERE
        p.fyh_elm IS NULL
        AND p.partida_origen_id IS NULL  -- ignore reproceso (only price the original partida)
        AND p.estado_facturacion <> 'facturado'
        -- TENIDO only: require an approved recipe (any variant) — no recipe means no cost basis
        AND (op.codigo <> 'TENIDO' OR EXISTS (
            SELECT 1 FROM receta.tenido rt
            WHERE rt.flg_produccion = true
              AND rt.tipo_receta_id = 7
              AND (rt.color_x_cliente_id IS NULL OR rt.color_x_cliente_id = p.color_x_cliente_id)
              AND rt.grupo_articulo_id = p.grupo_articulo_id
              AND rt.fibra = p.fibra
              AND (rt.tenido_id IS NULL OR rt.tenido_id = p.tenido_id)
        ))
)
SELECT
    k.operacion_id,
    k.operacion,
    k.color_x_cliente_id,
    k.color_id,
    k.color,
    k.tercero_id,
    k.cliente,
    k.grupo_articulo_id,
    k.grupo_articulo,
    k.tenido_id,
    k.tenido,
    k.fibra,
    pr.precio_kg,
    CASE WHEN pr.precio_kg IS NULL THEN 'sin_precio' ELSE 'con_precio' END AS estado
FROM combos k
-- TENIDO: normalize the grupo to its pricing family exactly as billing does.
-- The combo columns keep the LITERAL grupo (that is what the drawer edits).
LEFT JOIN LATERAL doc.fn_get_precio(
    k.operacion_id::smallint,
    k.color_x_cliente_id,
    k.tercero_id,
    CASE WHEN k.operacion_codigo = 'TENIDO'
         THEN doc.fn_familia_precio(k.grupo_articulo_id, k.tercero_id)
         ELSE k.grupo_articulo_id END,
    k.tenido_id,
    k.fibra::smallint
) AS pr(precio_kg) ON true;

GRANT SELECT ON doc.vw_precios_estado TO authenticated;


-- ── doc.vw_precios_pendientes ─────────────────────────────────
-- Combinations from active partidas that have no active catalog entry.
-- Drives the pricing workflow: operator sees what needs a rate set.
-- Equivalent to legacy vw_recetas_precio_pendiente.
--
-- Now a thin filter over doc.vw_precios_estado so the pending list and the
-- priced list can never disagree about what "has a price" means. Column list
-- is unchanged for existing callers (precio_kg/estado are additive).
CREATE OR REPLACE VIEW doc.vw_precios_pendientes AS
SELECT
    operacion_id, operacion,
    color_x_cliente_id, color_id, color,
    tercero_id, cliente,
    grupo_articulo_id, grupo_articulo,
    tenido_id, tenido,
    fibra
FROM doc.vw_precios_estado
WHERE estado = 'sin_precio';

GRANT SELECT ON doc.vw_precios_pendientes TO authenticated;

-- NOTE: for the existing rate card (all active + superseded catalog rows),
-- use doc.vw_catalogo_precios_historico (migration/08_views.sql) — already
-- built, granted, and consumed by consulta-precios/page.tsx. Filter it
-- WHERE activo for the active-only slice. Do not add another view over
-- doc.catalogo_precios here; that one already is the catalog lens.

-- ── doc.registrar_factura_cliente ─────────────────────────────
-- Records an externally-issued client invoice.
-- Totals (subtotal, igv, total) are always computed from detail
-- lines — never accepted as input. The physical document is a
-- reference; the system is the source of truth.
--
-- p_factura: single JSONB — header fields + lineas array:
-- {
--   "tercero_id":        1,
--   "tipo_comprobante":  "01",
--   "serie":             "F001",
--   "numero":            123,
--   "fecha_emision":     "2026-04-12",
--   "fecha_vencimiento": "2026-05-12",   -- nullable
--   "moneda":            "USD",           -- defaults 'USD'
--   "tipo_cambio":       3.75,            -- nullable
--   "observacion":       "...",           -- nullable
--   "lineas": [
--     {
--       "entrega_id":   456,        -- ingress entrega CLIENTE_ENVIO_PROCESO (nullable for ad-hoc/MLR rolls)
--       "partida_id":         123,        -- traceability (nullable)
--       "operacion_id":       1,          -- service billed (nullable for ad-hoc)
--       "es_antipilling":     false,
--       "grupo_articulo_id":  2,          -- billing dimensions (nullable for ad-hoc)
--       "color_x_cliente_id": 45,
--       "tenido_id":          7,          -- null for non-dyeing ops
--       "descripcion":        "Teñido Jersey Rojo - Ref. T001-00123",
--       "cantidad":           42.5,
--       "unidad_id":          3,
--       "precio_unitario":    3.50,
--       "igv_porcentaje":     18          -- defaults 18
--     }
--   ]
-- }
CREATE OR REPLACE FUNCTION doc.registrar_factura_cliente(p_factura JSONB)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'public'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     INT := get_user_id();
    v_factura_id BIGINT;
    v_subtotal   NUMERIC(12,2);
    v_igv        NUMERIC(12,2);
    v_total      NUMERIC(12,2);
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_factura_cliente', v_usr_id, p_factura);

    IF NOT (p_factura ? 'lineas') OR jsonb_array_length(p_factura->'lineas') = 0 THEN
        RAISE EXCEPTION 'La factura debe tener al menos una línea de detalle.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_factura->'lineas') l
        WHERE COALESCE((l->>'precio_unitario')::NUMERIC, 0) <= 0
    ) THEN
        RAISE EXCEPTION 'Todas las líneas deben tener un precio unitario mayor a cero.';
    END IF;

    -- Clean break, same as crear_partida (migration 30 decision 7): reject the
    -- retired key outright rather than accept it silently and drop it on the
    -- floor. A caller still sending articulo_tipo_id is stale and needs to know.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_factura->'lineas') l
        WHERE l ? 'articulo_tipo_id'
    ) THEN
        RAISE EXCEPTION 'articulo_tipo_id fue retirado (migración 33) — envíe grupo_articulo_id.';
    END IF;

    -- Insert header with placeholder totals; updated after lines are inserted
    INSERT INTO doc.factura (
        tipo_comprobante, serie, numero, tercero_id,
        fecha_emision, fecha_vencimiento,
        moneda, tipo_cambio,
        subtotal, igv, total,
        estado, observacion, usr_cre
    ) VALUES (
        (p_factura->>'tipo_comprobante')::CHAR(2),
        p_factura->>'serie',
        (p_factura->>'numero')::INT,
        (p_factura->>'tercero_id')::INT,
        (p_factura->>'fecha_emision')::DATE,
        (p_factura->>'fecha_vencimiento')::DATE,
        COALESCE(p_factura->>'moneda', 'USD')::CHAR(3),
        (p_factura->>'tipo_cambio')::NUMERIC,
        0, 0, 0,
        'emitida',
        p_factura->>'observacion',
        v_usr_id
    )
    RETURNING id INTO v_factura_id;

    INSERT INTO doc.factura_detalle (
        factura_id,
        entrega_id,
        partida_id,
        operacion_id,
        es_antipilling,
        grupo_articulo_id,
        color_x_cliente_id,
        tenido_id,
        descripcion,
        cantidad,
        unidad_id,
        precio_unitario,
        igv_porcentaje,
        usr_cre
    )
    SELECT
        v_factura_id,
        (l->>'entrega_id')::BIGINT,
        (l->>'partida_id')::BIGINT,
        (l->>'operacion_id')::SMALLINT,
        COALESCE((l->>'es_antipilling')::BOOLEAN, false),
        (l->>'grupo_articulo_id')::INT,
        (l->>'color_x_cliente_id')::INT,
        (l->>'tenido_id')::INT,
        l->>'descripcion',
        (l->>'cantidad')::NUMERIC,
        (l->>'unidad_id')::INT,
        (l->>'precio_unitario')::NUMERIC,
        COALESCE((l->>'igv_porcentaje')::NUMERIC, 18),
        v_usr_id
    FROM jsonb_array_elements(p_factura->'lineas') l;

    -- Compute totals from generated columns on detail lines
    SELECT SUM(subtotal_linea), SUM(igv_linea), SUM(total_linea)
    INTO v_subtotal, v_igv, v_total
    FROM doc.factura_detalle
    WHERE factura_id = v_factura_id;

    UPDATE doc.factura
    SET subtotal = v_subtotal,
        igv      = v_igv,
        total    = v_total
    WHERE id = v_factura_id;

    -- Auto-close partidas that are now fully billed
    UPDATE mes.partida p
    SET estado_facturacion = 'facturado',
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE p.id IN (
        SELECT DISTINCT (l->>'partida_id')::BIGINT
        FROM jsonb_array_elements(p_factura->'lineas') l
        WHERE l->>'partida_id' IS NOT NULL
    )
    AND NOT EXISTS (
        SELECT 1 FROM doc.vw_pendientes_facturacion vpf
        WHERE vpf.partida_id = p.id
    )
    AND NOT EXISTS (
        SELECT 1 FROM doc.vw_aprobados_sin_despacho vas
        WHERE vas.partida_id = p.id
    );

    RETURN v_factura_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_factura_cliente - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$$;


-- ── doc.vw_pendientes_facturacion ─────────────────────────────
-- Live view of billable lines with remaining unbilled weight.
-- One row per (ingress entrega × partida × operacion × billing dimensions × antipilling).
--
-- entrega_id = the CLIENTE_ENVIO_PROCESO entrega (client's own reference,
-- appears on invoice description as "Ref. [serie]-[correlativo]").
-- Weight is aggregated across ALL dispatch events that trace back to the same
-- ingress entrega + partida combination.
--
-- Quantity-based tracking (SAP/Odoo approach):
--   peso_total     = total kg dispatched for this (entrega × partida × service)
--   peso_facturado = kg already billed in factura_detalle for same key
--   peso_pendiente = peso_total - peso_facturado  (> 0 → row visible)
-- This supports partial billing: one partida can be billed across multiple
-- invoices, and one invoice can cover multiple partidas.
-- The key for matching is (entrega_id, partida_id, operacion_id,
-- grupo_articulo_id, color_x_cliente_id, tenido_id, es_antipilling).
--
-- Usage:
--   - entrega list screen:
--       SELECT DISTINCT entrega_id, serie, correlativo, cliente, ...
--       GROUP BY ingress entrega to show pending kg per entrega
--   - Invoice creation preview:
--       WHERE entrega_id = ANY(selected_ids)
--   - sin_precio = true: rate missing, operator must set before billing
--
-- Join path:
--   DESPACHO_CLIENTE entrega → grd.lote_id (dyed output lote)
--   → lote_rollo_detalle.entrega_id (ingress entrega, carried by registrar_produccion)
--   → output lote.documento_id → partida_paso → partida → partida
--   → completed partida_paso → operacion
--   → item_rollo_detalle → articulo (fibra)
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
        p.grupo_articulo_id,
        ga.nombre                          AS grupo_articulo,
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
    -- fibra needs articulo join; grupo_articulo_id comes directly from partida
    JOIN LATERAL (
        SELECT ar2.fibra
        FROM item_rollo_detalle ird2
        JOIN articulo ar2 ON ar2.id = ird2.articulo_id
        WHERE ird2.item_id = l.item_id
        LIMIT 1
    ) ar ON true
    -- INNER JOIN is safe: partida.grupo_articulo_id is NOT NULL as of migration 32.
    JOIN grupo_articulo ga              ON ga.id = p.grupo_articulo_id
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
        p.grupo_articulo_id, ga.nombre,
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
        l.grupo_articulo_id, l.grupo_articulo,
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
    l.grupo_articulo_id,
    l.grupo_articulo,
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
    || ' ' || l.grupo_articulo || ' ' || l.color
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
                     -- TENIDO: normalize the grupo to its pricing family (client-aware)
                     CASE WHEN l.op_codigo = 'TENIDO'
                          THEN doc.fn_familia_precio(l.grupo_articulo_id, l.partida_tercero_id)
                          ELSE l.grupo_articulo_id END,
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
      AND fd.grupo_articulo_id  = l.grupo_articulo_id
      AND fd.color_x_cliente_id = l.color_x_cliente_id
      AND fd.tenido_id IS NOT DISTINCT FROM l.tenido_id
      AND fd.es_antipilling     = l.es_antipilling
) billed ON true
WHERE l.peso_kg - billed.peso_facturado > 0.001;

GRANT SELECT ON doc.vw_pendientes_facturacion TO authenticated;


-- ── doc.vw_aprobados_sin_despacho ─────────────────────────────
-- Output lotes produced but not yet dispatched to the client.
-- Non-overlapping with vw_pendientes_facturacion: once a lote gets a
-- DESPACHO_CLIENTE entrega it disappears from here and appears there instead.
--
-- Entry point: inventario.lote WHERE documento_tipo = 'partida_paso_ejecucion'
-- + NOT EXISTS a live DESPACHO_CLIENTE entrega referencing that lote.
--
-- Weight: COALESCE(source_lote.cantidad, output_lote.cantidad)
-- — same pre-production input weight logic; grd.cantidad fallback is
--   unavailable here (no dispatch detail row exists).
--
-- Billing key, peso_facturado tracking, precio lookup, antipilling CTE,
-- and final SELECT are identical to vw_pendientes_facturacion so that
-- registrar_factura_cliente can drive both views with the same line format.
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
        p.grupo_articulo_id,
        ga.nombre                          AS grupo_articulo,
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
    -- INNER JOIN is safe: partida.grupo_articulo_id is NOT NULL as of migration 32.
    JOIN grupo_articulo ga              ON ga.id = p.grupo_articulo_id
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
        p.grupo_articulo_id, ga.nombre,
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
        l.grupo_articulo_id, l.grupo_articulo,
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
    l.grupo_articulo_id,
    l.grupo_articulo,
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
    || ' ' || l.grupo_articulo || ' ' || l.color
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
                          THEN doc.fn_familia_precio(l.grupo_articulo_id, l.partida_tercero_id)
                          ELSE l.grupo_articulo_id END,
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
      AND fd.grupo_articulo_id  = l.grupo_articulo_id
      AND fd.color_x_cliente_id = l.color_x_cliente_id
      AND fd.tenido_id IS NOT DISTINCT FROM l.tenido_id
      AND fd.es_antipilling     = l.es_antipilling
) billed ON true
WHERE l.peso_kg - billed.peso_facturado > 0.001;

GRANT SELECT ON doc.vw_aprobados_sin_despacho TO authenticated;


-- ── doc.get_factura_cliente ───────────────────────────────────
-- Returns a full invoice with line-item breakdown for display/dropdown.
-- Lines include service description, kg, unit price, and computed amounts
-- from generated columns — no arithmetic in the function.
CREATE OR REPLACE FUNCTION doc.get_factura_cliente(p_factura_id BIGINT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'public'
AS $$
SELECT jsonb_build_object(
    'id',               f.id,
    'tipo_comprobante', f.tipo_comprobante,
    'serie',            f.serie,
    'numero',           f.numero,
    'tercero_id',       f.tercero_id,
    'cliente',          t.nombre,
    'fecha_emision',    f.fecha_emision,
    'fecha_vencimiento',f.fecha_vencimiento,
    'moneda',           f.moneda,
    'tipo_cambio',      f.tipo_cambio,
    'subtotal',         f.subtotal,
    'igv',              f.igv,
    'total',            f.total,
    'estado',           f.estado,
    'observacion',      f.observacion,
    'lineas', COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'id',               fd.id,
                'descripcion',      fd.descripcion,
                'operacion_id',     fd.operacion_id,
                'operacion',        o.nombre,
                'es_antipilling',   fd.es_antipilling,
                'partida_id',       fd.partida_id,
                'entrega_id', fd.entrega_id,
                'cantidad',         fd.cantidad,
                'unidad',           u.codigo,
                'precio_unitario',  fd.precio_unitario,
                'igv_porcentaje',   fd.igv_porcentaje,
                'subtotal_linea',   fd.subtotal_linea,
                'igv_linea',        fd.igv_linea,
                'total_linea',      fd.total_linea
            ) ORDER BY fd.id
        )
        FROM doc.factura_detalle fd
        LEFT JOIN mes.operacion o ON o.id = fd.operacion_id
        LEFT JOIN unidad u        ON u.id = fd.unidad_id
        WHERE fd.factura_id = f.id
    ), '[]'::jsonb)
)
FROM doc.factura f
JOIN tercero t ON t.id = f.tercero_id
WHERE f.id = p_factura_id;
$$;


-- ── doc.anular_factura_cliente ────────────────────────────────
-- Cancels a client invoice. Sets estado='anulada' and reverts
-- estado_facturacion on any partida that was closed by this invoice
-- but now has unbilled weight again (per vw_pendientes_facturacion,
-- which already excludes anulada invoices from peso_facturado).
CREATE OR REPLACE FUNCTION doc.anular_factura_cliente(p_factura_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'public'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     INT := get_user_id();
    v_estado     factura_estado_enum;
    v_partidas   BIGINT[];
    v_reverted   INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_factura_cliente', v_usr_id, jsonb_build_object('factura_id', p_factura_id));

    SELECT estado INTO v_estado
    FROM doc.factura WHERE id = p_factura_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_id;
    END IF;
    IF v_estado = 'anulada' THEN
        RAISE EXCEPTION 'Factura #% ya está anulada.', p_factura_id;
    END IF;

    -- Block voiding an invoice that still has active customer payments.
    IF EXISTS (
        SELECT 1
        FROM doc.cobro_factura cf
        JOIN doc.cobro c ON c.id = cf.cobro_id
        WHERE cf.factura_id = p_factura_id
          AND c.estado = 'registrado'
    ) THEN
        RAISE EXCEPTION 'No se puede anular la factura #%: tiene cobros activos aplicados. Anule primero los cobros.', p_factura_id;
    END IF;

    -- Collect partidas referenced by this invoice before cancelling
    SELECT ARRAY(
        SELECT DISTINCT partida_id
        FROM doc.factura_detalle
        WHERE factura_id = p_factura_id AND partida_id IS NOT NULL
    ) INTO v_partidas;

    UPDATE doc.factura
    SET estado = 'anulada', estado_pago = 'anulado', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_factura_id;

    -- Revert 'facturado' partidas that now have pending weight again.
    -- vw_pendientes_facturacion excludes anulada invoices, so after the
    -- UPDATE above it reflects the true unbilled state.
    UPDATE mes.partida p
    SET estado_facturacion = 'pendiente',
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE p.id = ANY(v_partidas)
      AND p.estado_facturacion = 'facturado'
      AND (
          EXISTS (SELECT 1 FROM doc.vw_pendientes_facturacion vpf WHERE vpf.partida_id = p.id)
          OR EXISTS (SELECT 1 FROM doc.vw_aprobados_sin_despacho vas WHERE vas.partida_id = p.id)
      );

    GET DIAGNOSTICS v_reverted = ROW_COUNT;

    RETURN format('Factura #%s anulada. %s partida(s) revertida(s) a pendiente.',
        p_factura_id, v_reverted);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_factura_cliente - User: %, factura: %, Error: %', v_usr_id, p_factura_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.anular_factura_cliente(bigint) TO authenticated;


-- ── doc.get_precio_info_partida ───────────────────────────────
-- Frontend wrapper: derives all pricing dimensions from a partida
-- and calls fn_precio_info for each completed operacion.
-- Returns one row per op (+ antipilling variant when partida has the flag).
-- Frontend only needs to pass the partida id.
CREATE OR REPLACE FUNCTION doc.get_precio_info_partida(p_partida_id BIGINT)
RETURNS TABLE (
    operacion_id   SMALLINT,
    operacion      TEXT,
    es_antipilling BOOLEAN,
    receta_id      INT,
    costo_kg       NUMERIC(10,4),
    precio_kg      NUMERIC(10,4),
    margen         NUMERIC(8,6)
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'receta', 'doc', 'mes', 'public'
AS $$
DECLARE
    v_p          mes.partida%ROWTYPE;
    v_fibra      SMALLINT;
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_p FROM mes.partida WHERE id = p_partida_id AND fyh_elm IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida % no encontrada', p_partida_id;
    END IF;

    SELECT ar.fibra::SMALLINT INTO v_fibra
    FROM mes.partida_componente pc
    JOIN inventario.lote l      ON l.id = pc.lote_id
    JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
    JOIN articulo ar            ON ar.id = ird.articulo_id
    WHERE pc.partida_id = p_partida_id AND pc.lote_id IS NOT NULL
    LIMIT 1;

    -- Base line per completed operacion
    RETURN QUERY
    SELECT
        op.id::SMALLINT,
        op.nombre,
        false,
        (pi).*
    FROM mes.partida_paso pp
    JOIN mes.operacion op ON op.id = pp.operacion_id
    JOIN LATERAL doc.fn_precio_info(
        op.id::SMALLINT,
        v_p.color_x_cliente_id,
        v_p.tercero_id,
        v_p.grupo_articulo_id,
        CASE WHEN op.codigo = 'TENIDO' THEN v_p.tenido_id ELSE NULL END,
        v_fibra,
        CASE WHEN op.codigo = 'TENIDO' THEN v_p.flg_antipilling ELSE NULL END
    ) pi ON true
    WHERE pp.partida_id = p_partida_id
      AND EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
      );

    -- Antipilling surcharge line (when TENIDO completed + flag set)
    IF v_p.flg_antipilling THEN
        RETURN QUERY
        SELECT
            antipil_op.id::SMALLINT,
            'Antipilling'::TEXT,
            true,
            (pi).*
        FROM mes.operacion antipil_op
        JOIN LATERAL doc.fn_precio_info(
            antipil_op.id::SMALLINT,
            NULL, v_p.tercero_id,
            NULL, NULL, NULL, NULL
        ) pi ON true
        WHERE antipil_op.codigo = 'ANTIPILLING'
          AND EXISTS (
              SELECT 1 FROM mes.partida_paso pp2
              JOIN mes.operacion op2 ON op2.id = pp2.operacion_id AND op2.codigo = 'TENIDO'
              JOIN mes.partida_paso_ejecucion pe2 ON pe2.partida_paso_id = pp2.id AND pe2.estado = 'COMPLETADO'
              WHERE pp2.partida_id = p_partida_id
          );
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.fn_familia_precio(INT, INT)                                           TO authenticated;
GRANT EXECUTE ON FUNCTION doc.upsert_familia_precio(INT, INT, INT)                                 TO authenticated;
GRANT EXECUTE ON FUNCTION doc.fn_precio_info(SMALLINT, INT, INT, INT, INT, SMALLINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION doc.fn_get_costo_receta(INT)                                             TO authenticated;
GRANT EXECUTE ON FUNCTION doc.upsert_catalogo_precio(SMALLINT, INT, INT, INT, INT, SMALLINT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_precios_partida(BIGINT[])                                        TO authenticated;
GRANT EXECUTE ON FUNCTION doc.registrar_factura_cliente(JSONB)                                     TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_factura_cliente(BIGINT)                                          TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_precio_info_partida(BIGINT)                                      TO authenticated;

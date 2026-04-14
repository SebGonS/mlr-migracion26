-- ═══════════════════════════════════════════════════════════════
-- Facturación / Pricing functions
-- Depends on: migration/15_catalogo_precios.sql,
--             migration/17_billing_document_links.sql
-- ═══════════════════════════════════════════════════════════════


-- ── doc.fn_get_precio ─────────────────────────────────────────
-- Returns the applicable precio_kg (and precio_antipilling) for a
-- given service combination on a given date (defaults to today).
--
-- NULL dimensions in catalog rows are wildcards: a row with
-- color_x_cliente_id = NULL matches any client/color value.
-- Match priority: most non-NULL dimensions matched first (most specific).
-- Tie-break: most recently created row (fyh_cre DESC).
-- Returns NULL if no active catalog entry covers the combination.
CREATE OR REPLACE FUNCTION doc.fn_get_precio(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,
    p_tercero_id          INT,
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT
)
RETURNS TABLE (precio_kg NUMERIC(10,4), precio_antipilling NUMERIC(10,4))
LANGUAGE sql STABLE
SET search_path TO 'doc', 'public'
AS $$
    SELECT cp.precio_kg, cp.precio_antipilling
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


-- ── doc.fn_get_costo_receta ───────────────────────────────────
-- Returns the chemical cost per kg for a given dyeing recipe.
-- Cost = SUM(insumo.cantidad × item_unit_price) across all pasos.
-- cantidad is in kg-chemical / kg-fabric (OWF fraction, e.g. 0.02 = 2%).
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
            tpi.cantidad * COALESCE(
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
    WHERE tp.receta_id = p_receta_id;
$$;


-- ── doc.fn_precio_info ────────────────────────────────────────
-- Pricing UI helper: returns current chemical cost, active catalog
-- price, and derived margin for a given TENIDO service combination.
-- Designed to power the price-setting form.
--
-- Lookup:
--   - Finds the approved recipe (flg_produccion = true) matching the
--     dyeing dimensions (color_x_cliente_id, articulo_tipo_id, fibra,
--     tenido_id, flg_antipilling).
--   - Computes chemical cost via fn_get_costo_receta.
--   - Fetches current catalog price via fn_get_precio.
--
-- margen = (precio_kg - costo_kg) / precio_kg (NULL if no price set).
--
-- Only meaningful for TENIDO operations. For PLANCHADO/PERCHADO,
-- pass p_receta_id = NULL — returns price only, no cost.
--
-- p_flg_antipilling: when true, also returns the antipilling surcharge margin.
CREATE OR REPLACE FUNCTION doc.fn_precio_info(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,
    p_tercero_id          INT,
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT,
    p_flg_antipilling     BOOLEAN DEFAULT false
)
RETURNS TABLE (
    receta_id           INT,
    costo_kg            NUMERIC(10,4),
    precio_kg           NUMERIC(10,4),
    precio_antipilling  NUMERIC(10,4),
    margen              NUMERIC(8,6),   -- (precio - costo) / precio; NULL if no price
    margen_antipilling  NUMERIC(8,6)    -- NULL if flg_antipilling=false or no price set
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'receta', 'doc', 'public'
AS $$
DECLARE
    v_receta_id  INT;
    v_costo_kg   NUMERIC(10,4);
    v_precio     RECORD;
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Find approved recipe for these dyeing dimensions (NULL = no recipe, e.g. non-TENIDO op)
    SELECT rt.id INTO v_receta_id
    FROM receta.tenido rt
    WHERE rt.color_x_cliente_id = p_color_x_cliente_id
      AND rt.articulo_tipo_id   = p_articulo_tipo_id
      AND rt.fibra               = p_fibra
      AND rt.tenido_id           = p_tenido_id
      AND rt.flg_antipilling     = p_flg_antipilling
      AND rt.flg_produccion      = true
    LIMIT 1;

    -- Compute chemical cost (NULL if no recipe)
    IF v_receta_id IS NOT NULL THEN
        v_costo_kg := doc.fn_get_costo_receta(v_receta_id);
    END IF;

    -- Fetch current catalog price
    SELECT p.precio_kg, p.precio_antipilling
    INTO v_precio
    FROM doc.fn_get_precio(
        p_operacion_id,
        p_color_x_cliente_id,
        p_tercero_id,
        p_articulo_tipo_id,
        p_tenido_id,
        p_fibra
    ) p;

    RETURN QUERY SELECT
        v_receta_id,
        v_costo_kg,
        v_precio.precio_kg,
        v_precio.precio_antipilling,
        CASE
            WHEN v_precio.precio_kg IS NOT NULL AND v_costo_kg IS NOT NULL
                 AND v_precio.precio_kg > 0
            THEN ROUND((v_precio.precio_kg - v_costo_kg) / v_precio.precio_kg, 6)
            ELSE NULL
        END,
        CASE
            WHEN p_flg_antipilling
                 AND v_precio.precio_antipilling IS NOT NULL AND v_costo_kg IS NOT NULL
                 AND v_precio.precio_antipilling > 0
            THEN ROUND((v_precio.precio_antipilling - v_costo_kg) / v_precio.precio_antipilling, 6)
            ELSE NULL
        END;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.fn_precio_info(SMALLINT, INT, INT, SMALLINT, INT, SMALLINT, BOOLEAN)
    TO authenticated;

GRANT EXECUTE ON FUNCTION doc.fn_get_costo_receta(INT)
    TO authenticated;


-- ── doc.upsert_catalogo_precio ────────────────────────────────
-- Changes a price: closes the currently active row (sets fyh_elm)
-- and inserts a new active row. Both happen atomically.
-- Returns the new row id.
--
-- costo_kg is auto-computed from the approved recipe matching the
-- given dimensions (color_x_cliente_id, articulo_tipo_id, fibra,
-- tenido_id). NULL when no approved recipe exists (non-TENIDO ops,
-- or recipe not yet approved). Stored as a snapshot — does not
-- update automatically if purchase prices change later.
--
-- Replaces the legacy insertar_catalogo_precio_v2 pattern.
CREATE OR REPLACE FUNCTION doc.upsert_catalogo_precio(
    p_operacion_id        SMALLINT,
    p_color_x_cliente_id  INT,          -- set for color-specific rate
    p_tercero_id          INT,          -- set for client flat rate (mutually exclusive with above)
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT,
    p_precio_kg           NUMERIC(10,4),
    p_precio_antipilling  NUMERIC(10,4) DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'receta', 'doc', 'public'
AS $$
DECLARE
    v_usr_id    INT := get_user_id();
    v_id        BIGINT;
    v_receta_id INT;
    v_costo_kg  NUMERIC(10,4);
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_color_x_cliente_id IS NOT NULL AND p_tercero_id IS NOT NULL THEN
        RAISE EXCEPTION 'color_x_cliente_id and tercero_id are mutually exclusive';
    END IF;

    -- Auto-compute cost from the approved recipe (NULL if none — non-TENIDO or no recipe yet)
    SELECT rt.id INTO v_receta_id
    FROM receta.tenido rt
    WHERE rt.color_x_cliente_id = p_color_x_cliente_id
      AND rt.articulo_tipo_id   = p_articulo_tipo_id
      AND rt.fibra               = p_fibra
      AND rt.tenido_id           = p_tenido_id
      AND rt.flg_produccion      = true
    LIMIT 1;

    IF v_receta_id IS NOT NULL THEN
        v_costo_kg := doc.fn_get_costo_receta(v_receta_id);
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
        tenido_id, fibra, precio_kg, precio_antipilling, costo_kg, usr_cre
    ) VALUES (
        p_operacion_id, p_color_x_cliente_id, p_tercero_id, p_articulo_tipo_id,
        p_tenido_id, p_fibra, p_precio_kg, p_precio_antipilling, v_costo_kg, v_usr_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;


-- ── doc.fn_precios_partida ────────────────────────────────────
-- Returns resolved price lines for a set of partidas.
-- One row per completed operacion per partida, plus a second row
-- for antipilling when partida.flg_antipilling = true.
--
-- All dimensions come directly from doc.partida — no need to
-- inspect orden_produccion_paso. tenido_id lives on partida.
-- sin_precio = true flags combinations missing from the catalog.
CREATE OR REPLACE FUNCTION doc.fn_precios_partida(p_partida_ids BIGINT[])
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
            -- Distinct completed operaciones across ALL ops for this partida (reproceso included)
            ARRAY(
                SELECT DISTINCT opp.operacion_id
                FROM mes.orden_produccion op
                JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op.id
                WHERE op.partida_id = p.id
                  AND op.flg_elm = false
                  AND opp.estado = 'COMPLETADO'
            ) AS operacion_ids
        FROM doc.partida p
        -- fibra only — articulo_tipo_id comes directly from partida
        JOIN mes.orden_produccion op_r    ON op_r.partida_id = p.id AND op_r.flg_elm = false
        JOIN mes.orden_produccion_item opi ON opi.orden_produccion_id = op_r.id
        JOIN item_rollo_detalle ird        ON ird.item_id = opi.item_id
        JOIN articulo ar                   ON ar.id = ird.articulo_id
        WHERE p.id = ANY(p_partida_ids) AND p.flg_elm = false
        ORDER BY p.id
    ),
    lineas AS (
        -- Base line per completed operacion
        SELECT
            pt.partida_id,
            op.id::smallint                         AS operacion_id,
            op.nombre                               AS operacion,
            false                                   AS es_antipilling,
            (doc.fn_get_precio(
                op.id::smallint,
                pt.color_x_cliente_id,
                pt.tercero_id,
                pt.articulo_tipo_id,
                -- tenido_id only relevant for TENIDO operation
                CASE WHEN op.codigo = 'TENIDO' THEN pt.tenido_id ELSE NULL END,
                pt.fibra
            )).precio_kg                            AS precio_kg
        FROM partidas pt
        JOIN LATERAL unnest(pt.operacion_ids) AS oid ON true
        JOIN mes.operacion op ON op.id = oid

        UNION ALL

        -- Antipilling surcharge line (TENIDO only, when flag is set)
        SELECT
            pt.partida_id,
            op.id::smallint,
            'Antipilling',
            true,
            (doc.fn_get_precio(
                op.id::smallint,
                pt.color_x_cliente_id,
                pt.tercero_id,
                pt.articulo_tipo_id,
                pt.tenido_id,
                pt.fibra
            )).precio_antipilling
        FROM partidas pt
        JOIN mes.operacion op ON op.codigo = 'TENIDO'
        WHERE pt.flg_antipilling = true
          AND op.id = ANY(pt.operacion_ids)
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


-- ── doc.vw_precios_pendientes ─────────────────────────────────
-- Distinct (operacion, color_x_cliente, articulo_tipo, tenido, fibra)
-- combinations from active partidas that have no active catalog entry.
-- Drives the pricing workflow: operator sees what needs a rate set.
-- Equivalent to legacy vw_recetas_precio_pendiente.
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
FROM doc.partida p
JOIN color_x_cliente cxc           ON cxc.id = p.color_x_cliente_id
JOIN public.color c                ON c.id   = cxc.color_id
JOIN tercero t                     ON t.id   = cxc.tercero_id
-- ALL OPs for this partida — covers reproceso operations too
JOIN mes.orden_produccion op_h     ON op_h.partida_id = p.id AND op_h.flg_elm = false
JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op_h.id
                                   AND opp.estado = 'COMPLETADO'
JOIN mes.operacion op              ON op.id = opp.operacion_id
-- fibra from articulo (articulo_tipo_id now directly on partida)
CROSS JOIN LATERAL (
    SELECT ar2.fibra::smallint AS fibra
    FROM mes.orden_produccion_item opi2
    JOIN item_rollo_detalle ird2 ON ird2.item_id = opi2.item_id
    JOIN articulo ar2            ON ar2.id = ird2.articulo_id
    WHERE opi2.orden_produccion_id = op_h.id
    LIMIT 1
) ar
JOIN public.articulo_tipo aty    ON aty.id = p.articulo_tipo_id
LEFT JOIN tenido ten             ON ten.id = p.tenido_id AND op.codigo = 'TENIDO'
WHERE
    p.flg_elm = false
    AND p.estado_facturacion <> 'facturado'
    -- No active catalog row exists for this combination
    AND NOT EXISTS (
        SELECT 1 FROM doc.catalogo_precios cp
        WHERE cp.operacion_id = op.id
          AND (cp.color_x_cliente_id IS NULL OR cp.color_x_cliente_id = p.color_x_cliente_id)
          AND (cp.tercero_id         IS NULL OR cp.tercero_id         = p.tercero_id)
          AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   = p.articulo_tipo_id)
          AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p.tenido_id)
          AND (cp.fibra              IS NULL OR cp.fibra              = ar.fibra)
          AND cp.fyh_elm IS NULL
    );

GRANT SELECT ON doc.vw_precios_pendientes TO authenticated;


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
--       "guia_remision_id":   456,        -- dispatch guia (nullable for ad-hoc)
--       "partida_id":         123,        -- traceability (nullable)
--       "operacion_id":       1,          -- service billed (nullable for ad-hoc)
--       "es_antipilling":     false,
--       "articulo_tipo_id":   2,          -- billing dimensions (nullable for ad-hoc)
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
SET search_path TO 'iam', 'doc', 'public'
AS $$
DECLARE
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
        guia_remision_id,
        partida_id,
        operacion_id,
        es_antipilling,
        articulo_tipo_id,
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
        (l->>'guia_remision_id')::BIGINT,
        (l->>'partida_id')::BIGINT,
        (l->>'operacion_id')::SMALLINT,
        COALESCE((l->>'es_antipilling')::BOOLEAN, false),
        (l->>'articulo_tipo_id')::SMALLINT,
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

    RETURN v_factura_id;
END;
$$;


-- ── doc.vw_pendientes_facturacion ─────────────────────────────
-- Live view of billable lines not yet invoiced.
-- One row per (dispatch guia × operacion × billing dimensions × antipilling).
--
-- Unbilled = no matching factura_detalle row for that exact
-- (guia_remision_id, operacion_id, articulo_tipo_id,
--  color_x_cliente_id, tenido_id, es_antipilling) key.
-- Partial billing is handled naturally: if TENIDO is billed but
-- PLANCHADO isn't, the PLANCHADO row still appears here.
--
-- Usage:
--   - Guia list screen:
--       SELECT DISTINCT guia_remision_id, serie, correlativo, cliente, ...
--       GROUP BY guia to show pending kg per guia
--   - Invoice creation preview:
--       WHERE guia_remision_id = ANY(selected_ids)
--   - sin_precio = true: rate missing, operator must set before billing
--
-- Join path:
--   dispatch guia → guia_detalle.lote_id
--   → orden_produccion_item.lote_id → orden_produccion → partida
--   → completed orden_produccion_paso → operacion
--   → item_rollo_detalle → articulo (articulo_tipo_id, fibra)
CREATE OR REPLACE VIEW doc.vw_pendientes_facturacion AS
WITH lineas AS (
    SELECT
        gr.id                               AS guia_remision_id,
        gr.serie,
        gr.correlativo,
        gr.fecha_emision::DATE              AS fecha_emision,
        gr.tercero_id,
        t.nombre                            AS cliente,
        p.id                                AS partida_id,
        o.id::SMALLINT                      AS operacion_id,
        o.nombre                            AS operacion,
        o.codigo                            AS op_codigo,
        false                               AS es_antipilling,
        p.articulo_tipo_id::SMALLINT        AS articulo_tipo_id,
        atn.nombre                          AS articulo_tipo,
        p.color_x_cliente_id,
        c.color,
        p.tenido_id,
        ten.tenido,
        ar.fibra::SMALLINT                  AS fibra,
        p.tercero_id                        AS partida_tercero_id,
        p.flg_antipilling,
        SUM(grd.cantidad)                   AS peso_kg
    FROM doc.guia_remision gr
    JOIN doc.guia_remision_tipo grt    ON grt.id = gr.guia_remision_tipo_id
                                      AND grt.codigo = 'DESPACHO_CLIENTE'
    JOIN tercero t                     ON t.id = gr.tercero_id
    JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
    -- Dispatched lote is always a dyed OUTPUT lote (documento_tipo = 'ORDEN_PRODUCCION_PASO')
    JOIN inventario.lote l             ON l.id = grd.lote_id
                                      AND l.documento_tipo = 'ORDEN_PRODUCCION_PASO'
    -- Trace: dyed output lote → OPP → OP → partida
    JOIN mes.orden_produccion_paso opp_out ON opp_out.id = l.documento_id
    JOIN mes.orden_produccion op_out       ON op_out.id  = opp_out.orden_produccion_id
                                          AND op_out.flg_elm = false
    JOIN doc.partida p                     ON p.id = op_out.partida_id
                                          AND p.flg_elm = false
    -- Only completed operations from the SAME OP that produced this output lote.
    -- A reproceso roll is billed separately when its own output is dispatched.
    JOIN mes.orden_produccion_paso opp     ON opp.orden_produccion_id = op_out.id
                                          AND opp.estado = 'COMPLETADO'
    JOIN mes.operacion o                   ON o.id = opp.operacion_id
    -- fibra still needs articulo join; articulo_tipo_id now comes directly from partida
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
    WHERE gr.flg_elm = false
    GROUP BY
        gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id, t.nombre,
        p.id, o.id, o.nombre, o.codigo,
        p.articulo_tipo_id, atn.nombre,
        p.color_x_cliente_id, c.color,
        p.tenido_id, ten.tenido,
        ar.fibra, p.tercero_id, p.flg_antipilling
),
-- Antipilling surcharge lines: same grouping, different price column
antipilling AS (
    SELECT
        l.guia_remision_id, l.serie, l.correlativo, l.fecha_emision,
        l.tercero_id, l.cliente, l.partida_id,
        l.operacion_id, l.operacion, l.op_codigo,
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
    l.guia_remision_id,
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
    l.peso_kg,
    px.precio_kg,
    ROUND(l.peso_kg * px.precio_kg, 2)      AS subtotal,
    (px.precio_kg IS NULL)                  AS sin_precio,
    -- Auto-generated description; operator may override at invoice time
    CASE WHEN l.es_antipilling
         THEN 'Antipilling ' || l.articulo_tipo || ' ' || l.color
         ELSE l.operacion   || ' ' || l.articulo_tipo || ' ' || l.color
    END                                     AS descripcion
FROM all_lineas l
LEFT JOIN LATERAL (
    SELECT
        CASE WHEN l.es_antipilling
             THEN (doc.fn_get_precio(
                     l.operacion_id, l.color_x_cliente_id, l.partida_tercero_id,
                     l.articulo_tipo_id, l.tenido_id, l.fibra
                  )).precio_antipilling
             ELSE (doc.fn_get_precio(
                     l.operacion_id, l.color_x_cliente_id, l.partida_tercero_id,
                     l.articulo_tipo_id,
                     CASE WHEN l.op_codigo = 'TENIDO' THEN l.tenido_id ELSE NULL END,
                     l.fibra
                  )).precio_kg
        END AS precio_kg
) px ON true
-- Unbilled: no matching factura_detalle row
WHERE NOT EXISTS (
    SELECT 1 FROM doc.factura_detalle fd
    WHERE fd.guia_remision_id    = l.guia_remision_id
      AND fd.operacion_id        = l.operacion_id
      AND fd.articulo_tipo_id    = l.articulo_tipo_id
      AND fd.color_x_cliente_id  = l.color_x_cliente_id
      AND fd.tenido_id IS NOT DISTINCT FROM l.tenido_id
      AND fd.es_antipilling      = l.es_antipilling
);

GRANT SELECT ON doc.vw_pendientes_facturacion TO authenticated;

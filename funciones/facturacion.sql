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


-- ── doc.upsert_catalogo_precio ────────────────────────────────
-- Changes a price: closes the currently active row (sets fyh_fin)
-- and inserts a new active row. Both happen atomically.
-- Returns the new row id.
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
SET search_path TO 'iam', 'doc', 'public'
AS $$
DECLARE
    v_usr_id INT := get_user_id();
    v_id     BIGINT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_color_x_cliente_id IS NOT NULL AND p_tercero_id IS NOT NULL THEN
        RAISE EXCEPTION 'color_x_cliente_id and tercero_id are mutually exclusive';
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
        tenido_id, fibra, precio_kg, precio_antipilling, usr_cre
    ) VALUES (
        p_operacion_id, p_color_x_cliente_id, p_tercero_id, p_articulo_tipo_id,
        p_tenido_id, p_fibra, p_precio_kg, p_precio_antipilling, v_usr_id
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
            ar.articulo_tipo_id::smallint AS articulo_tipo_id,
            ar.fibra::smallint            AS fibra,
            -- Distinct completed operaciones for this partida
            ARRAY(
                SELECT DISTINCT opp.operacion_id
                FROM mes.orden_produccion op
                JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op.id
                WHERE op.partida_id = p.id
                  AND opp.estado = 'COMPLETADO'
            ) AS operacion_ids
        FROM doc.partida p
        -- Derive articulo_tipo_id + fibra from the assigned production lots
        JOIN mes.orden_produccion op_r   ON op_r.partida_id = p.id AND op_r.flg_elm = false
        JOIN mes.orden_produccion_item opi ON opi.orden_produccion_id = op_r.id
        JOIN item_rollo_detalle ird       ON ird.item_id = opi.item_id
        JOIN articulo ar                  ON ar.id = ird.articulo_id
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
    ar.articulo_tipo_id,
    aty.nombre              AS articulo_tipo,
    CASE WHEN op.codigo = 'TENIDO' THEN p.tenido_id ELSE NULL END AS tenido_id,
    ten.tenido,
    ar.fibra
FROM doc.partida p
JOIN color_x_cliente cxc         ON cxc.id = p.color_x_cliente_id
JOIN public.color c              ON c.id   = cxc.color_id
JOIN tercero t                   ON t.id   = cxc.tercero_id
JOIN mes.orden_produccion op_h   ON op_h.partida_id = p.id AND op_h.flg_elm = false
JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op_h.id
                                   AND opp.estado = 'COMPLETADO'
JOIN mes.operacion op            ON op.id = opp.operacion_id
-- Derive articulo_tipo_id + fibra from one assigned lot (all share the same articulo_tipo)
CROSS JOIN LATERAL (
    SELECT ar2.articulo_tipo_id::smallint AS articulo_tipo_id,
           ar2.fibra::smallint            AS fibra
    FROM mes.orden_produccion_item opi2
    JOIN item_rollo_detalle ird2 ON ird2.item_id = opi2.item_id
    JOIN articulo ar2            ON ar2.id = ird2.articulo_id
    WHERE opi2.orden_produccion_id = op_h.id
    LIMIT 1
) ar
JOIN public.articulo_tipo aty    ON aty.id = ar.articulo_tipo_id
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
          AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   = ar.articulo_tipo_id)
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

    -- Insert factura header (totals computed from lines below)
    INSERT INTO doc.factura (
        tipo_comprobante, serie, numero, tercero_id,
        fecha_emision, fecha_vencimiento, moneda, tipo_cambio,
        subtotal, igv, total, estado, usr_cre
    ) VALUES (
        p_tipo_comprobante, p_serie, p_numero, p_tercero_id,
        p_fecha_emision, p_fecha_vencimiento, p_moneda, p_tipo_cambio,
        0, 0, 0, 'emitida', v_usr_id
    )
    RETURNING id INTO v_factura_id;

    -- Link dispatch guias to this invoice (unique constraint prevents double billing)
    INSERT INTO doc.factura_guia_remision (factura_id, guia_remision_id, usr_cre)
    SELECT v_factura_id, g, v_usr_id
    FROM unnest(p_guia_remision_ids) g;

    -- Insert aggregated charge lines
    INSERT INTO doc.factura_detalle (
        factura_id,
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
    FROM jsonb_array_elements(p_lineas) l;

    -- Recompute header totals from generated columns on detail lines
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


-- ── doc.fn_get_dispatch_guias_pendientes ──────────────────────
-- Returns dispatch guias (DESPACHO_CLIENTE) not yet billed.
-- This is the invoice creation screen's first step: operator
-- selects one or more guias, then calls fn_get_lineas_factura_preview
-- to see the aggregated charge lines before confirming.
CREATE OR REPLACE FUNCTION doc.fn_get_dispatch_guias_pendientes(
    p_tercero_id INT DEFAULT NULL
)
RETURNS TABLE (
    guia_remision_id  BIGINT,
    serie             TEXT,
    correlativo       TEXT,
    fecha_emision     DATE,
    tercero_id        INT,
    cliente           TEXT,
    total_kg          NUMERIC(12,4),
    n_rollos          BIGINT
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'public'
AS $$
    SELECT
        gr.id,
        gr.serie,
        gr.correlativo,
        gr.fecha_emision::DATE,
        gr.tercero_id,
        t.nombre,
        SUM(grd.cantidad)   AS total_kg,
        COUNT(grd.id)       AS n_rollos
    FROM doc.guia_remision gr
    JOIN doc.guia_remision_tipo grt ON grt.id = gr.guia_remision_tipo_id
                                   AND grt.codigo = 'DESPACHO_CLIENTE'
    JOIN tercero t                  ON t.id = gr.tercero_id
    JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
    WHERE
        gr.flg_elm = false
        AND (p_tercero_id IS NULL OR gr.tercero_id = p_tercero_id)
        -- Not yet billed
        AND NOT EXISTS (
            SELECT 1 FROM doc.factura_guia_remision fgr
            WHERE fgr.guia_remision_id = gr.id
        )
    GROUP BY gr.id, gr.serie, gr.correlativo, gr.fecha_emision, gr.tercero_id, t.nombre
    ORDER BY gr.fecha_emision, gr.serie, gr.correlativo;
$$;

GRANT EXECUTE ON FUNCTION doc.fn_get_dispatch_guias_pendientes(INT) TO authenticated;


-- ── doc.fn_get_lineas_factura_preview ─────────────────────────
-- Given a set of dispatch guia IDs, returns aggregated billing
-- lines ready for the operator to review and confirm.
--
-- Aggregation key: (operacion × articulo_tipo × color_x_cliente
--                   × tenido × es_antipilling)
-- Weight: SUM of dispatched kg across all selected guias for
--   each combination.
-- Price: resolved from catalog via fn_get_precio.
-- Description: auto-generated; operator may override before
--   passing to registrar_factura_cliente.
--
-- sin_precio = true flags combinations with no active catalog
-- entry — operator must set a rate before confirming the invoice.
--
-- Join path:
--   dispatch guia → guia_detalle.lote_id
--   → lote = orden_produccion_item.lote_id
--   → orden_produccion → partida (price dimensions)
--   → item_rollo_detalle → articulo (articulo_tipo_id, fibra)
CREATE OR REPLACE FUNCTION doc.fn_get_lineas_factura_preview(
    p_guia_remision_ids BIGINT[]
)
RETURNS TABLE (
    operacion_id        SMALLINT,
    operacion           TEXT,
    es_antipilling      BOOLEAN,
    articulo_tipo_id    SMALLINT,
    articulo_tipo       TEXT,
    color_x_cliente_id  INT,
    color               TEXT,
    tenido_id           INT,
    tenido              TEXT,
    partida_id          BIGINT,   -- NULL when multiple partidas aggregate into one line
    peso_kg             NUMERIC(12,4),
    precio_kg           NUMERIC(10,4),
    subtotal            NUMERIC(12,2),
    sin_precio          BOOLEAN,
    descripcion         TEXT
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'inventario', 'public'
AS $$
    WITH base AS (
        SELECT
            o.id::SMALLINT                  AS operacion_id,
            o.nombre                        AS operacion,
            o.codigo                        AS op_codigo,
            ar.articulo_tipo_id::SMALLINT   AS articulo_tipo_id,
            atn.nombre                      AS articulo_tipo,
            p.color_x_cliente_id,
            c.color,
            p.tenido_id,
            ten.tenido,
            ar.fibra::SMALLINT              AS fibra,
            p.tercero_id                    AS partida_tercero_id,
            p.flg_antipilling,
            -- Keep partida_id only when all rolls in this group share the same partida
            MIN(p.id)                       AS partida_id_min,
            MAX(p.id)                       AS partida_id_max,
            SUM(grd.cantidad)               AS peso_kg
        FROM doc.guia_remision gr
        JOIN doc.guia_remision_tipo grt  ON grt.id = gr.guia_remision_tipo_id
                                        AND grt.codigo = 'DESPACHO_CLIENTE'
        JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
        JOIN inventario.lote l           ON l.id = grd.lote_id
        JOIN mes.orden_produccion_item opi ON opi.lote_id = l.id
        JOIN mes.orden_produccion op_h   ON op_h.id = opi.orden_produccion_id
                                        AND op_h.flg_elm = false
        JOIN doc.partida p               ON p.id = op_h.partida_id
                                        AND p.flg_elm = false
        JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op_h.id
                                          AND opp.estado = 'COMPLETADO'
        JOIN mes.operacion o             ON o.id = opp.operacion_id
        JOIN LATERAL (
            SELECT ar2.articulo_tipo_id, ar2.fibra
            FROM item_rollo_detalle ird2
            JOIN articulo ar2 ON ar2.id = ird2.articulo_id
            WHERE ird2.item_id = opi.item_id
            LIMIT 1
        ) ar ON true
        JOIN articulo_tipo atn           ON atn.id = ar.articulo_tipo_id
        JOIN color_x_cliente cxc         ON cxc.id = p.color_x_cliente_id
        JOIN public.color c              ON c.id = cxc.color_id
        LEFT JOIN tenido ten             ON ten.id = p.tenido_id AND o.codigo = 'TENIDO'
        WHERE gr.id = ANY(p_guia_remision_ids)
          AND gr.flg_elm = false
        GROUP BY
            o.id, o.nombre, o.codigo,
            ar.articulo_tipo_id, atn.nombre,
            p.color_x_cliente_id, c.color,
            p.tenido_id, ten.tenido,
            ar.fibra, p.tercero_id, p.flg_antipilling
    )

    -- Base service lines
    SELECT
        b.operacion_id,
        b.operacion,
        false                                                       AS es_antipilling,
        b.articulo_tipo_id,
        b.articulo_tipo,
        b.color_x_cliente_id,
        b.color,
        b.tenido_id,
        b.tenido,
        CASE WHEN b.partida_id_min = b.partida_id_max
             THEN b.partida_id_min ELSE NULL END                    AS partida_id,
        b.peso_kg,
        px.precio_kg,
        ROUND(b.peso_kg * px.precio_kg, 2)                         AS subtotal,
        (px.precio_kg IS NULL)                                      AS sin_precio,
        b.operacion || ' ' || b.articulo_tipo || ' ' || b.color    AS descripcion
    FROM base b
    LEFT JOIN LATERAL (
        SELECT precio_kg FROM doc.fn_get_precio(
            b.operacion_id,
            b.color_x_cliente_id,
            b.partida_tercero_id,
            b.articulo_tipo_id,
            CASE WHEN b.op_codigo = 'TENIDO' THEN b.tenido_id ELSE NULL END,
            b.fibra
        )
    ) px ON true

    UNION ALL

    -- Antipilling surcharge lines
    SELECT
        b.operacion_id,
        'Antipilling'                                               AS operacion,
        true                                                        AS es_antipilling,
        b.articulo_tipo_id,
        b.articulo_tipo,
        b.color_x_cliente_id,
        b.color,
        b.tenido_id,
        b.tenido,
        CASE WHEN b.partida_id_min = b.partida_id_max
             THEN b.partida_id_min ELSE NULL END                    AS partida_id,
        b.peso_kg,
        px.precio_antipilling                                       AS precio_kg,
        ROUND(b.peso_kg * px.precio_antipilling, 2)                AS subtotal,
        (px.precio_antipilling IS NULL)                             AS sin_precio,
        'Antipilling ' || b.articulo_tipo || ' ' || b.color        AS descripcion
    FROM base b
    LEFT JOIN LATERAL (
        SELECT precio_antipilling FROM doc.fn_get_precio(
            b.operacion_id,
            b.color_x_cliente_id,
            b.partida_tercero_id,
            b.articulo_tipo_id,
            b.tenido_id,
            b.fibra
        )
    ) px ON true
    WHERE b.flg_antipilling = true
      AND b.op_codigo = 'TENIDO'

    ORDER BY operacion_id, articulo_tipo_id, color_x_cliente_id, es_antipilling;
$$;

GRANT EXECUTE ON FUNCTION doc.fn_get_lineas_factura_preview(BIGINT[]) TO authenticated;

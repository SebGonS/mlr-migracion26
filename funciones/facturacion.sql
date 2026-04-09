-- ═══════════════════════════════════════════════════════════════
-- Facturación / Pricing functions
-- Depends on: migration/15_catalogo_precios.sql
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
    p_articulo_tipo_id    SMALLINT,
    p_tenido_id           INT,
    p_fibra               SMALLINT,
    p_fecha               DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (precio_kg NUMERIC(10,4), precio_antipilling NUMERIC(10,4))
LANGUAGE sql STABLE
SET search_path TO 'doc', 'public'
AS $$
    SELECT cp.precio_kg, cp.precio_antipilling
    FROM doc.catalogo_precios cp
    WHERE
        cp.operacion_id = p_operacion_id
        AND (cp.color_x_cliente_id IS NULL OR cp.color_x_cliente_id = p_color_x_cliente_id)
        AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   = p_articulo_tipo_id)
        AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p_tenido_id)
        AND (cp.fibra              IS NULL OR cp.fibra              = p_fibra)
        -- Active on the requested date
        AND cp.fyh_elm IS NULL
    ORDER BY
        -- Most specific match first
        (CASE WHEN cp.color_x_cliente_id IS NOT NULL THEN 1 ELSE 0 END
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
    p_color_x_cliente_id  INT,
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

    -- Close the currently active row for this exact key combination.
    UPDATE doc.catalogo_precios
    SET fyh_elm = NOW(), usr_elm = v_usr_id
    WHERE
        operacion_id = p_operacion_id
        AND COALESCE(color_x_cliente_id,    -1) = COALESCE(p_color_x_cliente_id,    -1)
        AND COALESCE(articulo_tipo_id::int, -1) = COALESCE(p_articulo_tipo_id::int, -1)
        AND COALESCE(tenido_id,             -1) = COALESCE(p_tenido_id,             -1)
        AND COALESCE(fibra::int,            -1) = COALESCE(p_fibra::int,            -1)
        AND fyh_elm IS NULL;

    INSERT INTO doc.catalogo_precios (
        operacion_id, color_x_cliente_id, articulo_tipo_id,
        tenido_id, fibra, precio_kg, precio_antipilling, usr_cre
    ) VALUES (
        p_operacion_id, p_color_x_cliente_id, p_articulo_tipo_id,
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
        SELECT
            p.id                  AS partida_id,
            p.color_x_cliente_id,
            p.tenido_id,
            p.flg_antipilling,
            ar.articulo_tipo_id,
            ar.fibra,
            -- Distinct completed operaciones for this partida
            ARRAY(
                SELECT DISTINCT opp.operacion_id
                FROM mes.orden_produccion op
                JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op.id
                WHERE op.partida_id = p.id
                  AND opp.estado = 'COMPLETADO'
            ) AS operacion_ids
        FROM doc.partida p
        JOIN public.articulo ar ON ar.id = p.articulo_id
        WHERE p.id = ANY(p_partida_ids)
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
JOIN public.articulo ar          ON ar.id  = p.articulo_id
JOIN public.articulo_tipo aty    ON aty.id = ar.articulo_tipo_id
JOIN color_x_cliente cxc         ON cxc.id = p.color_x_cliente_id
JOIN public.color c              ON c.id   = cxc.color_id
JOIN tercero t                   ON t.id   = cxc.tercero_id
JOIN mes.orden_produccion op_h   ON op_h.partida_id = p.id
JOIN mes.orden_produccion_paso opp ON opp.orden_produccion_id = op_h.id
                                   AND opp.estado = 'COMPLETADO'
JOIN mes.operacion op            ON op.id = opp.operacion_id
LEFT JOIN tenido ten             ON ten.id = p.tenido_id AND op.codigo = 'TENIDO'
WHERE
    p.flg_elm = false
    AND p.estado_facturacion <> 'facturado'
    -- No active catalog row exists for this combination
    AND NOT EXISTS (
        SELECT 1 FROM doc.catalogo_precios cp
        WHERE cp.operacion_id = op.id
          AND (cp.color_x_cliente_id IS NULL OR cp.color_x_cliente_id = p.color_x_cliente_id)
          AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   = ar.articulo_tipo_id)
          AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p.tenido_id)
          AND (cp.fibra              IS NULL OR cp.fibra              = ar.fibra)
          AND cp.fyh_elm IS NULL
    );

GRANT SELECT ON doc.vw_precios_pendientes TO authenticated;


-- ── doc.registrar_factura_cliente ─────────────────────────────
-- Records an externally-issued invoice into doc.factura and links
-- it to partidas via doc.factura_detalle. Updates estado_facturacion
-- on all referenced partidas to 'facturado'.
--
-- p_lineas: array of JSONB, each:
--   { "partida_id": 123,
--     "operacion_id": 1,
--     "descripcion": "Teñido jersey 42.5 kg",
--     "cantidad": 42.5,
--     "unidad_id": 3,
--     "precio_unitario": 3.50,
--     "igv_porcentaje": 18,
--     "es_antipilling": false }
CREATE OR REPLACE FUNCTION doc.registrar_factura_cliente(
    p_tercero_id        INT,
    p_tipo_comprobante  CHAR(2),
    p_serie             TEXT,
    p_numero            INT,
    p_fecha_emision     DATE,
    p_fecha_vencimiento DATE,
    p_tipo_cambio       NUMERIC(10,4),
    p_lineas            JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $$
DECLARE
    v_usr_id        INT := get_user_id();
    v_factura_id    BIGINT;
    v_subtotal      NUMERIC(12,2);
    v_igv           NUMERIC(12,2);
    v_total         NUMERIC(12,2);
    v_unidad_id     INT;
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
        p_fecha_emision, p_fecha_vencimiento, 'USD', p_tipo_cambio,
        0, 0, 0, 'emitida', v_usr_id
    )
    RETURNING id INTO v_factura_id;

    -- Insert detail lines
    INSERT INTO doc.factura_detalle (
        factura_id, partida_id, descripcion,
        cantidad, unidad_id, precio_unitario, igv_porcentaje, usr_cre
    )
    SELECT
        v_factura_id,
        (l->>'partida_id')::BIGINT,
        l->>'descripcion',
        (l->>'cantidad')::NUMERIC,
        (l->>'unidad_id')::INT,
        (l->>'precio_unitario')::NUMERIC,
        (l->>'igv_porcentaje')::NUMERIC,
        v_usr_id
    FROM jsonb_array_elements(p_lineas) l;

    -- Recompute header totals from generated columns on detail lines
    SELECT
        SUM(subtotal_linea),
        SUM(igv_linea),
        SUM(total_linea)
    INTO v_subtotal, v_igv, v_total
    FROM doc.factura_detalle
    WHERE factura_id = v_factura_id;

    UPDATE doc.factura
    SET subtotal = v_subtotal,
        igv      = v_igv,
        total    = v_total
    WHERE id = v_factura_id;

    -- Close billing status on all referenced partidas
    UPDATE doc.partida
    SET estado_facturacion = 'facturado',
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE id IN (
        SELECT DISTINCT (l->>'partida_id')::BIGINT
        FROM jsonb_array_elements(p_lineas) l
        WHERE l->>'partida_id' IS NOT NULL
    );

    RETURN v_factura_id;
END;
$$;

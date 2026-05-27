-- ============================================================================
-- DISPATCH MODULE
-- ============================================================================
-- doc.vw_despacho_pendiente  — listing view: partidas with dyed stock pending dispatch
-- doc.get_despacho_partida   — detail function: pre-built payload for crear_guia
-- doc.get_guia_remision      — getter: full guia with items and linked lotes
-- doc.anular_guia_remision   — cancellation: reverses movements, marks guia deleted
--
-- Flow:
--   1. Frontend queries vw_despacho_pendiente to list dispatchable partidas.
--   2. User selects a partida → frontend calls get_despacho_partida(partida_id).
--   3. Function returns pre-grouped guia payloads (one per propietario group).
--   4. Frontend lets user filter/adjust lotes, add serie/correlativo/fecha_emision.
--   5. Frontend calls doc.crear_guia once per guia payload.
--
-- propietario split:
--   • propietario_id = 1 (MLR-owned rolls — MLR/* or OSWALDO/* clients) → VENTA_EGRESO
--   • propietario_id ≠ 1 (client-owned rolls)                          → DESPACHO_CLIENTE
--
-- Reversal tipo mapping (used by anular_guia_remision):
--   COMPRA_ING  → DEV_PROV_EGR
--   SERV_ING    → DEV_CLI_EGR
--   SERV_EGR    → SERV_DEV_ING
--   VENTA_EGR   → DEV_CLI_ING
-- Stock direction is derived from location fields: origen IS NOT NULL → debit, destino IS NOT NULL → credit.
-- ============================================================================


-- ── doc.vw_despacho_pendiente ─────────────────────────────────────────────
-- Partidas that have dyed roll lotes with available stock not yet dispatched.
-- Query-driven: a partida appears iff SUM(cantidad_disponible) > 0 on its dyed lotes.
-- Partial dispatch is handled naturally — remaining lotes keep the partida in view.
-- tiene_mixto = true means two guias will be needed (MLR-owned + client-owned rolls).
-- ─────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS doc.vw_despacho_pendiente;
CREATE OR REPLACE VIEW doc.vw_despacho_pendiente AS
SELECT
    p.id                                                                            AS partida_id,
    p.numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                                     AS codigo,
    p.estado_produccion AS estado,
    p.tercero_id,
    t.nombre                                                                        AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.tono,
    p.fecha_acordada,
    COUNT(DISTINCT l.id)                                                            AS rolls_pendientes,
    ROUND(SUM(sa.cantidad_disponible)::NUMERIC, 2)                                  AS kg_pendientes,
    BOOL_OR(l.propietario_id = 1)                                                   AS tiene_rolls_mlr,
    BOOL_OR(l.propietario_id IS DISTINCT FROM 1)                                    AS tiene_rolls_cliente,
    (BOOL_OR(l.propietario_id = 1)
     AND BOOL_OR(l.propietario_id IS DISTINCT FROM 1))                              AS tiene_mixto
FROM mes.partida p
JOIN tercero t                      ON t.id                    = p.tercero_id
LEFT JOIN vw_colores vc             ON vc.color_x_cliente_id   = p.color_x_cliente_id
JOIN mes.partida_paso pp            ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                    AND pe.estado = 'COMPLETADO'   -- only completed steps produce output lotes
JOIN inventario.lote l
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
JOIN inventario.lote_rollo_detalle lrd
    ON  lrd.lote_id    = l.id
    AND lrd.flg_tenido = true           -- dyed rolls only
JOIN inventario.vw_stock_lotes sa  ON sa.lote_id = l.id
GROUP BY
    p.id, p.numero, p.estado_produccion, p.tercero_id, t.nombre,
    p.color_x_cliente_id, vc.color, vc.tono, p.fecha_acordada
HAVING SUM(sa.cantidad_disponible) > 0;

GRANT SELECT ON doc.vw_despacho_pendiente TO authenticated;


-- ── doc.get_despacho_partida ──────────────────────────────────────────────
-- Returns a pre-built dispatch payload for a single partida.
--
-- Result shape:
-- {
--   "partida_id": 123,
--   "codigo": "2025-0042",
--   "tercero_id": 7,
--   "cliente": "Acme S.A.",
--   "guias": [
--     {
--       "guia_remision_tipo_id": 2,
--       "guia_remision_tipo_codigo": "DESPACHO_CLIENTE",
--       "guia_remision_tipo_nombre": "Servicio – Despacho de material procesado a cliente",
--       "tercero_id": 7,
--       "rolls": 12,
--       "kg_total": 245.60,
--       "items": [
--         { "item_id": 44, "lote_id": 901, "ubicacion_id": 3, "cantidad": 20.50, "propietario_id": 7 },
--         ...
--       ]
--     },
--     { ... }   -- second entry only present when tiene_mixto = true
--   ]
-- }
--
-- Frontend adds serie, correlativo, fecha_emision to each guia entry and
-- calls doc.crear_guia once per entry.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_despacho_partida(p_partida_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'inventario', 'public'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id int := get_user_id();
    v_result JSONB;
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT jsonb_build_object(
        'partida_id', p.id,
        'codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT
                          || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'tercero_id', p.tercero_id,
        'cliente',    t.nombre,
        'guias',      COALESCE(guias_agg.guias, '[]'::jsonb)
    )
    INTO v_result
    FROM mes.partida p
    JOIN tercero t ON t.id = p.tercero_id
    LEFT JOIN LATERAL (
        SELECT jsonb_agg(
            jsonb_build_object(
                'guia_remision_tipo_id',     grt.id,
                'guia_remision_tipo_codigo', grt.codigo,
                'guia_remision_tipo_nombre', grt.nombre,
                'tercero_id',                p.tercero_id,
                'rolls',                     lotes_agg.roll_count,
                'kg_total',                  ROUND(lotes_agg.kg_total::NUMERIC, 2),
                'items',                     lotes_agg.items
            )
            ORDER BY grt.codigo  -- deterministic: DESPACHO_CLIENTE before VENTA_EGRESO
        ) AS guias
        FROM (
            SELECT
                CASE WHEN l.propietario_id = 1
                     THEN 'VENTA_EGRESO'
                     ELSE 'DESPACHO_CLIENTE'
                END                             AS tipo_codigo,
                COUNT(*)                        AS roll_count,
                SUM(sa.cantidad_disponible)     AS kg_total,
                jsonb_agg(
                    jsonb_build_object(
                        'item_id',        l.item_id,
                        'lote_id',        l.id,
                        'ubicacion_id',   sa.ubicacion_id,
                        'cantidad',       ROUND(sa.cantidad_disponible::NUMERIC, 2),
                        'propietario_id', l.propietario_id
                    )
                    ORDER BY l.id
                )                               AS items
            FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                                AND pe.estado = 'COMPLETADO'
            JOIN inventario.lote l
                ON  l.documento_tipo = 'partida_paso_ejecucion'
                AND l.documento_id   = pe.id
            JOIN inventario.lote_rollo_detalle lrd
                ON  lrd.lote_id    = l.id
                AND lrd.flg_tenido = true
            JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
            WHERE pp.partida_id = p.id
            GROUP BY
                CASE WHEN l.propietario_id = 1 THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END
        ) lotes_agg
        JOIN doc.guia_remision_tipo grt ON grt.codigo = lotes_agg.tipo_codigo
    ) guias_agg ON true
    WHERE p.id = p_partida_id;

    IF v_result IS NULL THEN
        RAISE EXCEPTION
            'Partida % no encontrada o sin stock de rollos teñidos pendiente de despacho',
            p_partida_id;
    END IF;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in get_despacho_partida - User: %, partida: %, Error: %',
        v_usr_id, p_partida_id, v_message;
    RAISE;
END;
$$;


-- ── doc.get_guia_remision ─────────────────────────────────────
-- Full read: guia header + items (with lote and item detail).
-- Used for dispatch confirmation screen and guia history view.
-- doc.get_guia_remision defined in core.sql

-- ── doc.anular_guia_remision ──────────────────────────────────
-- Cancels a guia and reverses all its inventory movements.
--
-- Guards (outbound guias — flg_emitida = true):
--   • Blocks if any non-anulada factura_cliente references this guia.
--
-- Guards (inbound guias — flg_emitida = false):
--   • Blocks if any lote created by this guia has downstream movements
--     (production consumption, re-dispatch, adjustment). These lotes
--     can no longer be "un-received".
--
-- Reversal: posts one counter-movement per original movement,
-- swapping origen/destino. Uses the natural paired movement tipo:
--   COMPRA_ING  → DEV_PROV_EGR
--   SERV_ING    → DEV_CLI_EGR
--   SERV_EGR    → SERV_DEV_ING
--   VENTA_EGR   → DEV_CLI_ING
--
-- For inbound guias: sets fyh_elm on lotes that were created
-- by this guia (document trace: lote.documento_id = guia_id).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_guia_remision(p_guia_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'public'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_guia            RECORD;
    v_reversal_tipo   SMALLINT;
    v_doc_mov_id      BIGINT;
    v_mov_count       INT;
    v_lote_count      INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_guia_remision', v_usr_id, jsonb_build_object('guia_id', p_guia_id));

    SELECT gr.id, gr.fyh_elm, grt.flg_emitida, grt.codigo AS tipo_codigo,
           grt.item_movimiento_tipo_id
    INTO v_guia
    FROM doc.guia_remision gr
    JOIN doc.guia_remision_tipo grt ON grt.id = gr.guia_remision_tipo_id
    WHERE gr.id = p_guia_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_guia_id;
    END IF;
    IF v_guia.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_guia_id;
    END IF;

    -- ── Outbound guard: block if any active client invoice references this guia
    IF v_guia.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM doc.factura_detalle fd
            JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
            WHERE fd.guia_remision_id = p_guia_id
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: está referenciada en facturas activas. Anule primero las facturas.',
                p_guia_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote has downstream movements
    IF NOT v_guia.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN inventario.item_movimientos im ON im.lote_id = l.id
            WHERE l.documento_tipo = 'GUIA_REMISION'
              AND l.documento_id   = p_guia_id
              AND l.fyh_elm        IS NULL
              -- Any movement NOT from this guia means the lote was used downstream
              AND NOT (im.documento_tipo = 'GUIA_REMISION' AND im.documento_id = p_guia_id)
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más lotes recibidos ya tienen movimientos posteriores (consumo, producción o redespacho).',
                p_guia_id;
        END IF;
    END IF;

    -- ── Resolve reversal movement tipo
    SELECT imt2.id INTO v_reversal_tipo
    FROM inventario.item_movimiento_tipo imt1
    JOIN inventario.item_movimiento_tipo imt2 ON imt2.codigo = CASE imt1.codigo
        WHEN 'COMPRA_ING' THEN 'DEV_PROV_EGR'
        WHEN 'SERV_ING'   THEN 'DEV_CLI_EGR'
        WHEN 'SERV_EGR'   THEN 'SERV_DEV_ING'
        WHEN 'VENTA_EGR'  THEN 'DEV_CLI_ING'
        ELSE NULL
    END
    WHERE imt1.id = v_guia.item_movimiento_tipo_id;

    IF v_reversal_tipo IS NULL THEN
        RAISE EXCEPTION
            'Guía #%: no existe tipo de movimiento de reversal para el tipo de guía "%". Contactar administrador.',
            p_guia_id, v_guia.tipo_codigo;
    END IF;

    -- ── Shared doc_movimiento_id for all reversal movements
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- ── Post reversal movements (swaps origen_ubicacion_id ↔ destino_ubicacion_id)
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id,
        item_id, lote_id,
        item_movimiento_tipo_id,
        origen_ubicacion_id,
        destino_ubicacion_id,
        cantidad, fecha_hora,
        documento_tipo, documento_id,
        observacion
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id,
        v_reversal_tipo,
        im.destino_ubicacion_id,   -- swap: destination becomes the new origin
        im.origen_ubicacion_id,    -- swap: origin becomes the new destination
        im.cantidad,
        NOW(),
        'GUIA_REMISION',
        p_guia_id,
        'ANULACION guía #' || p_guia_id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'GUIA_REMISION'
      AND im.documento_id   = p_guia_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    -- ── For inbound guias: retire the lotes that were created by this guia
    IF NOT v_guia.flg_emitida THEN
        UPDATE inventario.lote
        SET usr_elm = v_usr_id, fyh_elm = NOW()
        WHERE documento_tipo = 'GUIA_REMISION'
          AND documento_id   = p_guia_id
          AND fyh_elm        IS NULL;

        GET DIAGNOSTICS v_lote_count = ROW_COUNT;
    END IF;

    -- ── Mark guia as cancelled
    UPDATE doc.guia_remision
    SET usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE id = p_guia_id;

    RETURN format('Guía #%s anulada. %s movimiento(s) revertido(s)%s.',
        p_guia_id,
        v_mov_count,
        CASE WHEN NOT v_guia.flg_emitida THEN format(', %s lote(s) dado(s) de baja', v_lote_count) ELSE '' END
    );
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_guia_remision - User: %, guia: %, Error: %',
        v_usr_id, p_guia_id, v_message;
    RAISE;
END;
$function$;


GRANT EXECUTE ON FUNCTION doc.get_despacho_partida(bigint)  TO authenticated;
-- doc.get_guia_remision grant is in core.sql
GRANT EXECUTE ON FUNCTION doc.anular_guia_remision(bigint)  TO authenticated;

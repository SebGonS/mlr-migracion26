-- ============================================================================
-- DISPATCH MODULE
-- ============================================================================
-- doc.vw_despacho_pendiente  — listing view: partidas with dyed stock pending dispatch
-- doc.get_despacho_partida   — detail function: pre-built payload for crear_entrega
-- doc.get_entrega      — getter: full entrega with items and linked lotes
-- doc.anular_entrega   — cancellation: reverses movements, marks entrega deleted
--
-- Flow:
--   1. Frontend queries vw_despacho_pendiente to list dispatchable partidas.
--   2. User selects a partida → frontend calls get_despacho_partida(partida_id).
--   3. Function returns pre-grouped entrega payloads (one per propietario group).
--   4. Frontend lets user filter/adjust lotes, add serie/correlativo/fecha_emision.
--   5. Frontend calls doc.crear_entrega once per entrega payload.
--
-- propietario split:
--   • propietario_id = 1 (MLR-owned rolls — MLR/* or OSWALDO/* clients) → VENTA_EGRESO
--   • propietario_id ≠ 1 (client-owned rolls)                          → DESPACHO_CLIENTE
--
-- Reversal tipo mapping (used by anular_entrega):
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
-- tiene_mixto = true means two entregas will be needed (MLR-owned + client-owned rolls).
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
WHERE l.estado_calidad = 'APROBADO'
GROUP BY
    p.id, p.numero, p.estado_produccion, p.tercero_id, t.nombre,
    p.color_x_cliente_id, vc.color, vc.tono, p.fecha_acordada
HAVING SUM(sa.cantidad_disponible) > 0;

GRANT SELECT ON doc.vw_despacho_pendiente TO authenticated;


-- ── doc.get_despacho_partida ──────────────────────────────────────────────
-- Pre-builds the dispatch payload for one or more partidas (all must share
-- the same tercero_id). Groups rolls by ownership into DESPACHO_CLIENTE and
-- VENTA_EGRESO entries; frontend adds serie/correlativo/fecha_emision to each
-- and calls doc.crear_entrega once per entry.
--
-- Result shape:
-- {
--   "tercero_id": 7,
--   "cliente":    "Acme S.A.",
--   "partidas":   ["2026-0001", "2026-0003"],
--   "entregas": [
--     {
--       "entrega_tipo_id": 2, "entrega_tipo_codigo": "DESPACHO_CLIENTE", ...,
--       "rolls": 32, "kg_total": 480.60,
--       "items": [{ "item_id":44, "lote_id":901, "ubicacion_id":3, "cantidad":20.50, "propietario_id":7,
--                  "color_x_cliente_id":12, "color":"AZUL", "tono":"MARINO", "color_hex":"#001f5b",
--                  "ancho":"1.50", "articulo_id":3, "articulo_nombre":"RIB" }, ...]
--     }
--   ]
-- }
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_despacho_partida(p_partida_ids BIGINT[])
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'inventario', 'public'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     int := get_user_id();
    v_n_terceros int;
    v_tercero_id int;
    v_cliente    text;
    v_result     JSONB;
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT COUNT(DISTINCT p.tercero_id)
    INTO   v_n_terceros
    FROM   mes.partida p
    WHERE  p.id = ANY(p_partida_ids);

    IF v_n_terceros = 0 THEN
        RAISE EXCEPTION 'No se encontraron las partidas indicadas';
    END IF;
    IF v_n_terceros > 1 THEN
        RAISE EXCEPTION 'Las partidas seleccionadas pertenecen a distintos clientes';
    END IF;

    SELECT p.tercero_id, t.nombre
    INTO   v_tercero_id, v_cliente
    FROM   mes.partida p
    JOIN   tercero t ON t.id = p.tercero_id
    WHERE  p.id = ANY(p_partida_ids)
    LIMIT  1;

    SELECT jsonb_build_object(
        'tercero_id', v_tercero_id,
        'cliente',    v_cliente,
        'partidas',   (
            SELECT jsonb_agg(
                EXTRACT(YEAR FROM fyh_cre)::TEXT || '-' || LPAD(numero::TEXT, 4, '0')
                ORDER BY fyh_cre
            )
            FROM mes.partida WHERE id = ANY(p_partida_ids)
        ),
        'entregas', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'entrega_tipo_id',     grt.id,
                    'entrega_tipo_codigo', grt.codigo,
                    'entrega_tipo_nombre', grt.nombre,
                    'tercero_id',          v_tercero_id,
                    'rolls',               lotes_agg.roll_count,
                    'kg_total',            ROUND(lotes_agg.kg_total::NUMERIC, 2),
                    'items',               lotes_agg.items
                )
                ORDER BY grt.codigo
            )
            FROM (
                SELECT
                    CASE WHEN l.propietario_id = 1
                         THEN 'VENTA_EGRESO'
                         ELSE 'DESPACHO_CLIENTE'
                    END                         AS tipo_codigo,
                    COUNT(*)                    AS roll_count,
                    SUM(sa.cantidad_disponible) AS kg_total,
                    jsonb_agg(
                        jsonb_build_object(
                            'item_id',              l.item_id,
                            'lote_id',              l.id,
                            'ubicacion_id',         sa.ubicacion_id,
                            'cantidad',             ROUND(sa.cantidad_disponible::NUMERIC, 2),
                            'propietario_id',       l.propietario_id,
                            'color_x_cliente_id',   lrd.color_x_cliente_id,
                            'color',                vc.color,
                            'tono',                 vc.tono,
                            'color_hex',            vc.color_x_cliente_hex,
                            'ancho',                lrd.ancho,
                            'articulo_id',          ird.articulo_id,
                            'articulo_nombre',      art.nombre,
                            'entrega_serie',        ent.serie,
                            'entrega_correlativo',  ent.correlativo
                        )
                        ORDER BY l.id
                    ) AS items
                FROM mes.partida_paso pp
                JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                                    AND pe.estado = 'COMPLETADO'
                JOIN inventario.lote l
                    ON  l.documento_tipo = 'partida_paso_ejecucion'
                    AND l.documento_id   = pe.id
                JOIN inventario.lote_rollo_detalle lrd
                    ON  lrd.lote_id    = l.id
                    AND lrd.flg_tenido = true
                LEFT JOIN vw_colores vc             ON vc.color_x_cliente_id = lrd.color_x_cliente_id
                LEFT JOIN inventario.item_rollo_detalle ird ON ird.item_id   = l.item_id
                LEFT JOIN articulo art              ON art.id                = ird.articulo_id
                LEFT JOIN doc.entrega ent           ON ent.id               = lrd.entrega_id
                JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
                WHERE pp.partida_id = ANY(p_partida_ids)
                  AND l.estado_calidad = 'APROBADO'
                GROUP BY
                    CASE WHEN l.propietario_id = 1 THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END
            ) lotes_agg
            JOIN doc.entrega_tipo grt ON grt.codigo = lotes_agg.tipo_codigo
        ), '[]'::jsonb)
    )
    INTO v_result;

    IF (v_result->>'entregas') = '[]' THEN
        RAISE EXCEPTION 'Las partidas seleccionadas no tienen rollos teñidos con stock disponible para despachar';
    END IF;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in get_despacho_partida - User: %, partidas: %, Error: %',
        v_usr_id, p_partida_ids, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.get_despacho_partida(bigint[]) TO authenticated;


-- ── doc.get_entrega ─────────────────────────────────────
-- Full read: entrega header + items (with lote and item detail).
-- Used for dispatch confirmation screen and entrega history view.
-- doc.get_entrega defined in core.sql

-- ── doc.anular_entrega ──────────────────────────────────
-- Cancels a entrega and reverses all its inventory movements.
--
-- Guards (outbound entregas — flg_emitida = true):
--   • Blocks if any non-anulada factura_cliente references this entrega.
--
-- Guards (inbound entregas — flg_emitida = false):
--   • Blocks if any lote created by this entrega has downstream movements
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
-- For inbound entregas: sets fyh_elm on lotes that were created
-- by this entrega (document trace: lote.documento_id = entrega_id).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_entrega(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'public'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_entrega            RECORD;
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
    VALUES ('anular_entrega', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT gr.id, gr.fyh_elm, grt.flg_emitida, grt.codigo AS tipo_codigo,
           grt.item_movimiento_tipo_id
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id;
    END IF;

    -- ── Outbound guard: block if any active client invoice references this entrega
    IF v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM doc.factura_detalle fd
            JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
            WHERE fd.entrega_id = p_entrega_id
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: está referenciada en facturas activas. Anule primero las facturas.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote has downstream movements
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN inventario.item_movimientos im ON im.lote_id = l.id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
              -- Any movement NOT from this entrega means the lote was used downstream
              AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id)
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más lotes recibidos ya tienen movimientos posteriores (consumo, producción o redespacho).',
                p_entrega_id;
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
    WHERE imt1.id = v_entrega.item_movimiento_tipo_id;

    IF v_reversal_tipo IS NULL THEN
        RAISE EXCEPTION
            'Guía #%: no existe tipo de movimiento de reversal para el tipo de guía "%". Contactar administrador.',
            p_entrega_id, v_entrega.tipo_codigo;
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
        'entrega',
        p_entrega_id,
        'ANULACION guía #' || p_entrega_id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega'
      AND im.documento_id   = p_entrega_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    -- ── For inbound entregas: retire the lotes that were created by this entrega
    IF NOT v_entrega.flg_emitida THEN
        UPDATE inventario.lote
        SET usr_elm = v_usr_id, fyh_elm = NOW()
        WHERE documento_tipo = 'entrega'
          AND documento_id   = p_entrega_id
          AND fyh_elm        IS NULL;

        GET DIAGNOSTICS v_lote_count = ROW_COUNT;
    END IF;

    -- ── Mark entrega as cancelled
    UPDATE doc.entrega
    SET usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE id = p_entrega_id;

    RETURN format('Guía #%s anulada. %s movimiento(s) revertido(s)%s.',
        p_entrega_id,
        v_mov_count,
        CASE WHEN NOT v_entrega.flg_emitida THEN format(', %s lote(s) dado(s) de baja', v_lote_count) ELSE '' END
    );
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;


-- ── doc.registrar_numero_entrega ─────────────────────────────────────────────
-- Backfills the legal serie/correlativo onto a headless entrega after the
-- EXTERNAL system (GRE) issues the number. The dispatch movement is posted at
-- crear_entrega time (serie NULL); this transcribes the number once it's known.
--
-- serie/correlativo are written together (the chk_entrega_doc_fields both-or-neither
-- CHECK enforces this). Only headless entregas (serie IS NULL) are eligible — a
-- entrega that already carries a number must be corrected by anulando + reissuing,
-- not silently overwritten. Collisions are caught by the UNIQUE
-- (tercero_id, serie, correlativo, entrega_tipo_id) constraint.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_numero_entrega(
    p_entrega_id     BIGINT,
    p_serie       TEXT,
    p_correlativo TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_serie_actual text;
    v_fyh_elm      timestamptz;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_serie IS NULL OR trim(p_serie) = ''
       OR p_correlativo IS NULL OR trim(p_correlativo) = '' THEN
        RAISE EXCEPTION 'Se requieren serie y correlativo para numerar la guía.';
    END IF;

    SELECT gr.serie, gr.fyh_elm
    INTO   v_serie_actual, v_fyh_elm
    FROM   doc.entrega gr
    WHERE  gr.id = p_entrega_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% está anulada y no puede numerarse.', p_entrega_id;
    END IF;
    IF v_serie_actual IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya tiene número (%-%). Para corregirlo, anule y reemita.',
            p_entrega_id, v_serie_actual, (SELECT correlativo FROM doc.entrega WHERE id = p_entrega_id);
    END IF;

    BEGIN
        UPDATE doc.entrega
        SET serie       = trim(p_serie),
            correlativo = trim(p_correlativo),
            usr_mod     = v_usr_id,
            fyh_mod     = now()
        WHERE id = p_entrega_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'El número %-% ya existe para este cliente y tipo de guía.',
            trim(p_serie), trim(p_correlativo);
    END;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_numero_entrega', v_usr_id,
            jsonb_build_object('entrega_id', p_entrega_id,
                               'serie', trim(p_serie),
                               'correlativo', trim(p_correlativo)));

    RETURN format('Guía #%s numerada como %s-%s.', p_entrega_id, trim(p_serie), trim(p_correlativo));

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_numero_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;


-- ── doc.vw_entregas_sin_numerar ──────────────────────────────────────────────
-- Worklist of headless entregas (serie IS NULL) awaiting their external GRE
-- number. Drives the "guías pendientes de numerar" screen so a dispatched
-- (or received) document never sits untracked. flg_emitida lets the frontend
-- split outbound dispatch from inbound receipt; partidas shows which production
-- orders the dispatched rolls belong to.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW doc.vw_entregas_sin_numerar AS
SELECT
    gr.id                                   AS entrega_id,
    gr.entrega_tipo_id,
    grt.codigo                              AS tipo_codigo,
    grt.nombre                              AS tipo_nombre,
    grt.flg_emitida,
    gr.tercero_id,
    t.nombre                                AS tercero,
    gr.fecha_emision,
    gr.fyh_cre,
    COUNT(grd.id)                           AS lineas,
    COALESCE(SUM(grd.n_rollos), 0)          AS rollos,
    ROUND(COALESCE(SUM(grd.cantidad), 0)::numeric, 2) AS kg_total,
    ARRAY_AGG(DISTINCT EXTRACT(YEAR FROM p.fyh_cre)::TEXT
                       || '-' || LPAD(p.numero::TEXT, 4, '0'))
        FILTER (WHERE p.id IS NOT NULL)     AS partidas
FROM doc.entrega gr
JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
JOIN tercero t                  ON t.id  = gr.tercero_id
LEFT JOIN doc.entrega_detalle grd ON grd.entrega_id = gr.id
LEFT JOIN inventario.lote l ON l.id = grd.lote_id
LEFT JOIN mes.partida_paso_ejecucion pe
       ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
LEFT JOIN mes.partida p       ON p.id = pp.partida_id
WHERE gr.serie   IS NULL
  AND gr.fyh_elm IS NULL
GROUP BY gr.id, gr.entrega_tipo_id, grt.codigo, grt.nombre, grt.flg_emitida,
         gr.tercero_id, t.nombre, gr.fecha_emision, gr.fyh_cre;

GRANT SELECT ON doc.vw_entregas_sin_numerar TO authenticated;


-- GRANT for get_despacho_partida(bigint[]) is above the function definition
-- doc.get_entrega grant is in core.sql
GRANT EXECUTE ON FUNCTION doc.anular_entrega(bigint)  TO authenticated;
GRANT EXECUTE ON FUNCTION doc.registrar_numero_entrega(bigint, text, text) TO authenticated;

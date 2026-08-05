-- ============================================================================
-- DEVOLUTIONS MODULE
-- ============================================================================
-- doc.registrar_devolucion_cliente       — inbound: client returns service/sold rolls
-- doc.registrar_devolucion_crudo_cliente — outbound: MLR returns unprocessed rolls to client
-- doc.registrar_devolucion_proveedor     — outbound: MLR returns insumos to supplier
-- doc.anular_devolucion_cliente          — undo a registrar_devolucion_cliente
-- doc.anular_devolucion_crudo_cliente    — undo a registrar_devolucion_crudo_cliente
-- doc.anular_devolucion_proveedor        — undo a registrar_devolucion_proveedor
--
-- All three registrar_* write directly to doc.entrega / doc.entrega_detalle /
-- inventario.item_movimientos (same tables as crear_entrega — not wrappers).
--
-- entrega_tipo mapping:
--   DEVOLUCION_CLIENTE_SERVICIO (8) — client returns rolls sent for service
--   DEVOLUCION_CLIENTE_VENTA    (7) — client returns rolls they purchased from MLR
--   DEVOLUCION_CLIENTE_CRUDO    (5) — MLR sends back unprocessed client rolls
--   DEVOLUCION_PROVEEDOR        (6) — MLR returns insumos to supplier
--
-- Anulación (doc.anular_entrega / doc.actualizar_entrega refuse DEVOLUCION%
-- tipos and redirect here — see funciones/despacho.sql and funciones/core.sql):
-- DEV_CLI_ING/DEV_CLI_EGR/DEV_PROV_EGR/SERV_DEV_ING are real, valorizable
-- business events (not anulación scaffolding), so undoing one posts a
-- dedicated non-valorizable *_REV counterpart (migration/patches/42) rather
-- than reusing the forward devolution codes or crear_entrega's generic
-- reversal CASE — a reversal must not look like a second real return/dispatch.
-- ============================================================================


-- ── doc.registrar_devolucion_cliente ─────────────────────────────────────────
-- Inbound receipt: client returns rolls previously dispatched by MLR.
-- Covers both service returns (tipo 8) and sold-product returns (tipo 7);
-- caller selects which via entrega_tipo_id.
--
-- Guards:
--   1. entrega_tipo_id must resolve to DEVOLUCION_CLIENTE_SERVICIO or DEVOLUCION_CLIENTE_VENTA.
--   2. tercero_id must be an active client.
--   3. Each lote must have saldo = 0 — already out of stock (dispatched, not yet returned).
--   4. Each lote must have at least one prior outbound movement to this client.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_devolucion_cliente(p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_entrega_id    BIGINT;
    v_entrega_tipo  entrega_tipo%ROWTYPE;
    v_doc_mov_id    BIGINT;
    v_fecha_mov     TIMESTAMPTZ;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_entrega_tipo
    FROM entrega_tipo
    WHERE id = (p_datos->>'entrega_tipo_id')::SMALLINT;

    IF NOT FOUND OR v_entrega_tipo.codigo NOT IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'entrega_tipo_id inválido: use DEVOLUCION_CLIENTE_SERVICIO (8) o DEVOLUCION_CLIENTE_VENTA (7)';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tercero WHERE id = (p_datos->>'tercero_id')::INT AND flg_cliente = true
    ) THEN
        RAISE EXCEPTION 'tercero_id % no corresponde a un cliente', (p_datos->>'tercero_id');
    END IF;

    -- Guard: lotes must be fully out of stock (saldo = 0 ↔ absent from vw_stock_lotes)
    SELECT jsonb_agg(jsonb_build_object(
        'lote_id',             ei.lote_id,
        'cantidad_disponible', sl.cantidad_disponible
    ))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT (i->>'lote_id')::int AS lote_id
        FROM jsonb_array_elements(p_datos->'items') i
    ) ei
    JOIN inventario.vw_stock_lotes sl ON sl.lote_id = ei.lote_id;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución inválida: los siguientes lotes aún tienen stock positivo (¿ya devueltos o nunca despachados?)'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: each lote must have been dispatched to this client at least once
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT (i->>'lote_id')::int AS lote_id
        FROM jsonb_array_elements(p_datos->'items') i
    ) ei
    WHERE NOT EXISTS (
        SELECT 1
        FROM inventario.item_movimientos im
        JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE im.lote_id       = ei.lote_id
          AND e.tercero_id     = (p_datos->>'tercero_id')::INT
          AND im.origen_ubicacion_id IS NOT NULL  -- outbound (EGRESO) direction
    );

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución inválida: los siguientes lotes no registran despacho previo a este cliente'
            USING DETAIL = v_error_payload::text;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_devolucion_cliente', v_usr_id, p_datos);

    v_fecha_mov := COALESCE((p_datos->>'fecha_recepcion')::TIMESTAMPTZ, now());
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (
        v_entrega_tipo.id,
        (p_datos->>'tercero_id')::INT,
        p_datos->>'serie',
        p_datos->>'correlativo',
        v_fecha_mov,
        v_fecha_mov
    )
    RETURNING id INTO v_entrega_id;

    WITH items AS (
        SELECT
            COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
            (item->>'item_id')::INT                             AS item_id,
            (item->>'cantidad')::NUMERIC(12,4)                  AS cantidad,
            (item->>'lote_id')::INT                             AS lote_id,
            (item->>'ubicacion_id')::INT                        AS ubicacion_id
        FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)
    ),
    det AS (
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id
        FROM items
        RETURNING id, linea
    )
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, fecha_hora,
        documento_tipo, documento_id, documento_linea_id)
    SELECT
        v_doc_mov_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
        i.ubicacion_id,   -- incoming destination location
        i.cantidad, v_fecha_mov,
        'entrega', v_entrega_id, d.id
    FROM items i
    JOIN det d ON d.linea = i.linea;

    -- Link this return to the SAME venta its original dispatch belonged to
    -- (entrega.venta_id — see migration/27_venta.sql). Assumes all returned
    -- lotes in one call trace to a single venta (reasonable: single tercero
    -- already enforced above).
    UPDATE doc.entrega
    SET venta_id = (
        SELECT e2.venta_id
        FROM inventario.item_movimientos im
        JOIN doc.entrega e2 ON e2.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE im.lote_id = ANY(
            SELECT (item->>'lote_id')::int FROM jsonb_array_elements(p_datos->'items') item
        )
        AND im.origen_ubicacion_id IS NOT NULL  -- outbound direction: the original dispatch
        AND e2.venta_id IS NOT NULL
        LIMIT 1
    )
    WHERE id = v_entrega_id;

    -- Fulfillment cache: a return un-dispatches rolls — refresh every partida touched.
    -- See doc.recompute_estado_comercial's closed call-site list (funciones/despacho.sql).
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM doc.entrega_detalle ed
        JOIN inventario.lote l ON l.id = ed.lote_id
        JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        JOIN mes.partida p ON p.id = pp.partida_id
        WHERE ed.entrega_id = v_entrega_id
    ) root;

    RETURN format('Devolución de cliente registrada. Guía #%s creada.', v_entrega_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT,
        v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_devolucion_cliente - User: %, Params: %, Error: %',
        v_usr_id, p_datos::TEXT, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.registrar_devolucion_cliente(jsonb) TO authenticated;


-- ── doc.registrar_devolucion_crudo_cliente ────────────────────────────────────
-- Outbound: MLR sends client rolls back unprocessed (DEVOLUCION_CLIENTE_CRUDO, tipo 5).
-- Use when a client's service partida is cancelled and rolls must be returned undyed.
--
-- Guards:
--   1. tercero_id must be an active client.
--   2. Each lote must be ROLLO item_tipo (insumos cannot be returned via this path).
--   3. Each lote must have been received from this client (prior SERV_ING movement).
--   4. Sufficient available stock (rolls must still be physically at MLR).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_devolucion_crudo_cliente(p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_entrega_id    BIGINT;
    v_entrega_tipo  entrega_tipo%ROWTYPE;
    v_doc_mov_id    BIGINT;
    v_fecha_mov     TIMESTAMPTZ;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_entrega_tipo FROM entrega_tipo WHERE codigo = 'DEVOLUCION_CLIENTE_CRUDO';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tipo DEVOLUCION_CLIENTE_CRUDO no encontrado en entrega_tipo';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tercero WHERE id = (p_datos->>'tercero_id')::INT AND flg_cliente = true
    ) THEN
        RAISE EXCEPTION 'tercero_id % no corresponde a un cliente', (p_datos->>'tercero_id');
    END IF;

    -- Guard: only ROLLO lotes allowed (not insumos)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id, 'item_tipo', it.codigo))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT (i->>'lote_id')::int AS lote_id
        FROM jsonb_array_elements(p_datos->'items') i
    ) ei
    JOIN inventario.lote l  ON l.id = ei.lote_id
    JOIN item               ON item.id = l.item_id
    JOIN item_tipo it       ON it.id = item.item_tipo_id
    WHERE it.codigo <> 'ROLLO';

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución de crudo inválida: solo se pueden devolver rollos (no insumos)'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: lotes must have entered MLR from this client (SERV_ING movement via entrega)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT (i->>'lote_id')::int AS lote_id
        FROM jsonb_array_elements(p_datos->'items') i
    ) ei
    WHERE NOT EXISTS (
        SELECT 1
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'SERV_ING'
        JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE im.lote_id   = ei.lote_id
          AND e.tercero_id = (p_datos->>'tercero_id')::INT
    );

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución de crudo inválida: los siguientes lotes no ingresaron como material de servicio de este cliente'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: sufficient available stock to dispatch
    WITH entrega_items AS (
        SELECT
            (i->>'item_id')::int        AS item_id,
            (i->>'lote_id')::int        AS lote_id,
            (i->>'ubicacion_id')::int   AS ubicacion_id,
            SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_datos->'items') i
        GROUP BY 1, 2, 3
    )
    SELECT jsonb_agg(jsonb_build_object(
        'item_id',            items.item_id,
        'lote_id',            items.lote_id,
        'saldo_disponible',   COALESCE(sl.cantidad_disponible, 0),
        'cantidad_requerida', items.cantidad
    ))
    INTO v_error_payload
    FROM entrega_items items
    LEFT JOIN inventario.vw_stock_lotes sl
        ON sl.lote_id = items.lote_id AND sl.item_id = items.item_id
    WHERE COALESCE(sl.cantidad_disponible, 0) < items.cantidad;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente para devolución de crudo'
            USING DETAIL = v_error_payload::text;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_devolucion_crudo_cliente', v_usr_id, p_datos);

    v_fecha_mov := COALESCE((p_datos->>'fecha_emision')::TIMESTAMPTZ, now());
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (
        v_entrega_tipo.id,
        (p_datos->>'tercero_id')::INT,
        p_datos->>'serie',
        p_datos->>'correlativo',
        v_fecha_mov,
        NULL
    )
    RETURNING id INTO v_entrega_id;

    WITH items AS (
        SELECT
            COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
            (item->>'item_id')::INT                             AS item_id,
            (item->>'cantidad')::NUMERIC(12,4)                  AS cantidad,
            (item->>'lote_id')::INT                             AS lote_id,
            (item->>'ubicacion_id')::INT                        AS ubicacion_id,
            (item->>'n_rollos')::INT                            AS n_rollos
        FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)
    ),
    det AS (
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos
        FROM items
        RETURNING id, linea
    )
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, documento_linea_id)
    SELECT
        v_doc_mov_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
        i.ubicacion_id,  -- origin stock location at MLR
        NULL,            -- destination is client (external)
        i.cantidad, v_fecha_mov,
        'entrega', v_entrega_id, d.id
    FROM items i
    JOIN det d ON d.linea = i.linea;

    -- Link this return to the SAME venta its original dispatch belonged to.
    UPDATE doc.entrega
    SET venta_id = (
        SELECT e2.venta_id
        FROM inventario.item_movimientos im
        JOIN doc.entrega e2 ON e2.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE im.lote_id = ANY(
            SELECT (item->>'lote_id')::int FROM jsonb_array_elements(p_datos->'items') item
        )
        AND im.origen_ubicacion_id IS NOT NULL
        AND e2.venta_id IS NOT NULL
        LIMIT 1
    )
    WHERE id = v_entrega_id;

    -- Fulfillment cache: crudo rolls returned un-dispatched too — refresh every partida touched.
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM doc.entrega_detalle ed
        JOIN inventario.lote l ON l.id = ed.lote_id
        JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        JOIN mes.partida p ON p.id = pp.partida_id
        WHERE ed.entrega_id = v_entrega_id
    ) root;

    RETURN format('Devolución de crudo a cliente registrada. Guía #%s creada.', v_entrega_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT,
        v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_devolucion_crudo_cliente - User: %, Params: %, Error: %',
        v_usr_id, p_datos::TEXT, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.registrar_devolucion_crudo_cliente(jsonb) TO authenticated;


-- ── doc.registrar_devolucion_proveedor ────────────────────────────────────────
-- Outbound: MLR returns insumos to a supplier (DEVOLUCION_PROVEEDOR, tipo 6).
-- Use for defective, excess, or mis-shipped raw materials.
--
-- Guards:
--   1. tercero_id must be an active supplier.
--   2. Each lote must be INSUMO item_tipo — rolls cannot be returned via this path.
--   3. Sufficient available stock per lote.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_devolucion_proveedor(p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_entrega_id    BIGINT;
    v_entrega_tipo  entrega_tipo%ROWTYPE;
    v_doc_mov_id    BIGINT;
    v_fecha_mov     TIMESTAMPTZ;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_entrega_tipo FROM entrega_tipo WHERE codigo = 'DEVOLUCION_PROVEEDOR';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tipo DEVOLUCION_PROVEEDOR no encontrado en entrega_tipo';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tercero WHERE id = (p_datos->>'tercero_id')::INT AND flg_proveedor = true
    ) THEN
        RAISE EXCEPTION 'tercero_id % no corresponde a un proveedor', (p_datos->>'tercero_id');
    END IF;

    -- Guard: only INSUMO lotes (not rolls)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id, 'item_tipo', it.codigo))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT (i->>'lote_id')::int AS lote_id
        FROM jsonb_array_elements(p_datos->'items') i
    ) ei
    JOIN inventario.lote l  ON l.id = ei.lote_id
    JOIN item               ON item.id = l.item_id
    JOIN item_tipo it       ON it.id = item.item_tipo_id
    WHERE it.codigo <> 'INSUMO';

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución a proveedor inválida: solo se pueden devolver insumos (no rollos)'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: sufficient available stock
    WITH entrega_items AS (
        SELECT
            (i->>'item_id')::int        AS item_id,
            (i->>'lote_id')::int        AS lote_id,
            (i->>'ubicacion_id')::int   AS ubicacion_id,
            SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_datos->'items') i
        GROUP BY 1, 2, 3
    )
    SELECT jsonb_agg(jsonb_build_object(
        'item_id',            items.item_id,
        'lote_id',            items.lote_id,
        'saldo_disponible',   COALESCE(sl.cantidad_disponible, 0),
        'cantidad_requerida', items.cantidad
    ))
    INTO v_error_payload
    FROM entrega_items items
    LEFT JOIN inventario.vw_stock_lotes sl
        ON sl.lote_id = items.lote_id AND sl.item_id = items.item_id
    WHERE COALESCE(sl.cantidad_disponible, 0) < items.cantidad;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente para devolución a proveedor'
            USING DETAIL = v_error_payload::text;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_devolucion_proveedor', v_usr_id, p_datos);

    v_fecha_mov := COALESCE((p_datos->>'fecha_emision')::TIMESTAMPTZ, now());
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (
        v_entrega_tipo.id,
        (p_datos->>'tercero_id')::INT,
        p_datos->>'serie',
        p_datos->>'correlativo',
        v_fecha_mov,
        NULL
    )
    RETURNING id INTO v_entrega_id;

    WITH items AS (
        SELECT
            COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
            (item->>'item_id')::INT                             AS item_id,
            (item->>'cantidad')::NUMERIC(12,4)                  AS cantidad,
            (item->>'lote_id')::INT                             AS lote_id,
            (item->>'ubicacion_id')::INT                        AS ubicacion_id
        FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)
    ),
    det AS (
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id
        FROM items
        RETURNING id, linea
    )
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, documento_linea_id)
    SELECT
        v_doc_mov_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
        i.ubicacion_id,  -- origin stock location at MLR
        NULL,            -- destination is supplier (external)
        i.cantidad, v_fecha_mov,
        'entrega', v_entrega_id, d.id
    FROM items i
    JOIN det d ON d.linea = i.linea;

    RETURN format('Devolución a proveedor registrada. Guía #%s creada.', v_entrega_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT,
        v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_devolucion_proveedor - User: %, Params: %, Error: %',
        v_usr_id, p_datos::TEXT, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.registrar_devolucion_proveedor(jsonb) TO authenticated;


-- ── doc.anular_devolucion_cliente ─────────────────────────────────────────────
-- Undo a registrar_devolucion_cliente entrega (DEVOLUCION_CLIENTE_SERVICIO or
-- DEVOLUCION_CLIENTE_VENTA — both inbound). Posts the *_REV counterpart of
-- whichever code was used, swapping origen/destino, then marks the entrega
-- anulada. Does not touch inventario.lote — the returned lote pre-existed the
-- devolución (it was never created by this entrega).
--
-- Guard: blocks if the returned lote has any movement posted after this
-- devolución's own movements (e.g. it was redispatched or consumed since) —
-- reversing the ingress at that point would drive stock negative/inconsistent.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_devolucion_cliente(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int := get_user_id();
    v_entrega       RECORD;
    v_reversal_tipo SMALLINT;
    v_doc_mov_id    BIGINT;
    v_mov_count     INT;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT gr.id, gr.fyh_elm, grt.codigo AS tipo_codigo
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_entrega.tipo_codigo NOT IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'Guía #% no es una devolución de cliente (tipo %); use doc.anular_entrega.',
            p_entrega_id, v_entrega.tipo_codigo;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id;
    END IF;

    -- Guard: lote must not have moved again since this devolución was posted
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT im.lote_id, im.id
        FROM inventario.item_movimientos im
        WHERE im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id
    ) ei
    WHERE EXISTS (
        SELECT 1 FROM inventario.item_movimientos im2
        WHERE im2.lote_id = ei.lote_id
          AND im2.id > ei.id
          AND NOT (im2.documento_tipo = 'entrega' AND im2.documento_id = p_entrega_id)
    );

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'No se puede anular la devolución #%: uno o más rollos devueltos ya tienen movimientos posteriores.', p_entrega_id
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard (2026-07-30): crear_reproceso reassigns a lote via
    -- mes.partida_componente, never via item_movimientos, so the guard above
    -- alone misses a roll already committed to an active rework partida.
    SELECT jsonb_agg(jsonb_build_object('lote_id', ed.lote_id, 'rework_partida_id', pc.partida_id))
    INTO v_error_payload
    FROM doc.entrega_detalle ed
    JOIN mes.partida_componente pc ON pc.lote_id = ed.lote_id
    JOIN mes.partida p ON p.id = pc.partida_id
    WHERE ed.entrega_id = p_entrega_id AND p.estado_produccion <> 'CANCELADA';

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'No se puede anular la devolución #%: uno o más rollos ya fueron movidos a una partida de reproceso.', p_entrega_id
            USING DETAIL = v_error_payload::text;
    END IF;

    SELECT id INTO v_reversal_tipo
    FROM inventario.item_movimiento_tipo
    WHERE codigo = CASE v_entrega.tipo_codigo
        WHEN 'DEVOLUCION_CLIENTE_VENTA'    THEN 'DEV_CLI_ING_REV'
        WHEN 'DEVOLUCION_CLIENTE_SERVICIO' THEN 'SERV_DEV_ING_REV'
    END;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_devolucion_cliente', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, observacion,
        reversion_movimiento_id)
    SELECT
        v_doc_mov_id, im.item_id, im.lote_id, v_reversal_tipo,
        im.destino_ubicacion_id, im.origen_ubicacion_id,   -- swap
        im.cantidad, NOW(), 'entrega', p_entrega_id,
        'ANULACION devolución #' || p_entrega_id,
        im.id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    UPDATE doc.entrega SET usr_elm = v_usr_id, fyh_elm = NOW() WHERE id = p_entrega_id;

    -- Fulfillment cache: undoing a return re-dispatches the rolls — refresh.
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM doc.entrega_detalle ed
        JOIN inventario.lote l ON l.id = ed.lote_id
        JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        JOIN mes.partida p ON p.id = pp.partida_id
        WHERE ed.entrega_id = p_entrega_id
    ) root;

    RETURN format('Devolución #%s anulada. %s movimiento(s) revertido(s).', p_entrega_id, v_mov_count);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT,
        v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_devolucion_cliente - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.anular_devolucion_cliente(BIGINT) TO authenticated;


-- ── doc.anular_devolucion_crudo_cliente ───────────────────────────────────────
-- Undo a registrar_devolucion_crudo_cliente entrega (outbound: DEV_CLI_EGR).
-- No downstream guard needed — once dispatched the rolls are outside MLR's
-- inventory, so nothing here can have moved them further.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_devolucion_crudo_cliente(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int := get_user_id();
    v_entrega       RECORD;
    v_reversal_tipo SMALLINT;
    v_doc_mov_id    BIGINT;
    v_mov_count     INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT gr.id, gr.fyh_elm, grt.codigo AS tipo_codigo
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_entrega.tipo_codigo <> 'DEVOLUCION_CLIENTE_CRUDO' THEN
        RAISE EXCEPTION 'Guía #% no es una devolución de crudo a cliente (tipo %); use doc.anular_entrega.',
            p_entrega_id, v_entrega.tipo_codigo;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id;
    END IF;

    SELECT id INTO v_reversal_tipo FROM inventario.item_movimiento_tipo WHERE codigo = 'DEV_CLI_EGR_REV';

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_devolucion_crudo_cliente', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, observacion,
        reversion_movimiento_id)
    SELECT
        v_doc_mov_id, im.item_id, im.lote_id, v_reversal_tipo,
        im.destino_ubicacion_id, im.origen_ubicacion_id,   -- swap
        im.cantidad, NOW(), 'entrega', p_entrega_id,
        'ANULACION devolución #' || p_entrega_id,
        im.id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    UPDATE doc.entrega SET usr_elm = v_usr_id, fyh_elm = NOW() WHERE id = p_entrega_id;

    -- Fulfillment cache: undoing a crudo return re-dispatches the rolls — refresh.
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM doc.entrega_detalle ed
        JOIN inventario.lote l ON l.id = ed.lote_id
        JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        JOIN mes.partida p ON p.id = pp.partida_id
        WHERE ed.entrega_id = p_entrega_id
    ) root;

    RETURN format('Devolución #%s anulada. %s movimiento(s) revertido(s).', p_entrega_id, v_mov_count);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT,
        v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_devolucion_crudo_cliente - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.anular_devolucion_crudo_cliente(BIGINT) TO authenticated;


-- ── doc.anular_devolucion_proveedor ───────────────────────────────────────────
-- Undo a registrar_devolucion_proveedor entrega (outbound: DEV_PROV_EGR).
-- Gated by comercial.editar — same permission namespace as registrar_devolucion_proveedor
-- (fixed here to comercial.crear; there is no compras.* permission in iam.permiso,
-- the "compras" role is granted comercial.crear/editar — see migration/10_auth.sql:687-689).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_devolucion_proveedor(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int := get_user_id();
    v_entrega       RECORD;
    v_reversal_tipo SMALLINT;
    v_doc_mov_id    BIGINT;
    v_mov_count     INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT gr.id, gr.fyh_elm, grt.codigo AS tipo_codigo
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_entrega.tipo_codigo <> 'DEVOLUCION_PROVEEDOR' THEN
        RAISE EXCEPTION 'Guía #% no es una devolución a proveedor (tipo %); use doc.anular_entrega.',
            p_entrega_id, v_entrega.tipo_codigo;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id;
    END IF;

    SELECT id INTO v_reversal_tipo FROM inventario.item_movimiento_tipo WHERE codigo = 'DEV_PROV_EGR_REV';

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_devolucion_proveedor', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, observacion,
        reversion_movimiento_id)
    SELECT
        v_doc_mov_id, im.item_id, im.lote_id, v_reversal_tipo,
        im.destino_ubicacion_id, im.origen_ubicacion_id,   -- swap
        im.cantidad, NOW(), 'entrega', p_entrega_id,
        'ANULACION devolución #' || p_entrega_id,
        im.id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    UPDATE doc.entrega SET usr_elm = v_usr_id, fyh_elm = NOW() WHERE id = p_entrega_id;

    RETURN format('Devolución #%s anulada. %s movimiento(s) revertido(s).', p_entrega_id, v_mov_count);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT,
        v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_devolucion_proveedor - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.anular_devolucion_proveedor(BIGINT) TO authenticated;

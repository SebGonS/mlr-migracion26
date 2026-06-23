-- ═══════════════════════════════════════════════════════════════
-- COMPRAS — Purchase / Procurement Functions
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────
-- crear_compra
-- Creates a purchase event with line items and optional entrega links.
-- Inventory movements are handled by the entrega, not here.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.crear_compra(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_compra_id bigint;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_compra', v_usr_id, p_datos);

    -- Validate entregas belong to the declared proveedor
    IF p_datos->'entrega_ids' IS NOT NULL AND jsonb_array_length(p_datos->'entrega_ids') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.entrega gr
            WHERE gr.id IN (
                SELECT jsonb_array_elements_text(p_datos->'entrega_ids')::bigint
            )
            AND gr.tercero_id IS DISTINCT FROM (p_datos->>'tercero_id')::INT
        ) THEN
            RAISE EXCEPTION 'Una o más guías no pertenecen al proveedor indicado.';
        END IF;
    END IF;

    -- Validate facturas belong to the declared proveedor
    IF p_datos->'factura_ids' IS NOT NULL AND jsonb_array_length(p_datos->'factura_ids') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.factura_proveedor fp
            WHERE fp.id IN (
                SELECT jsonb_array_elements_text(p_datos->'factura_ids')::bigint
            )
            AND fp.tercero_id IS DISTINCT FROM (p_datos->>'tercero_id')::INT
        ) THEN
            RAISE EXCEPTION 'Una o más facturas no pertenecen al proveedor indicado.';
        END IF;
    END IF;

    -- Insert header
    INSERT INTO doc.compra(tercero_id, fecha, observacion, usr_cre)
    VALUES (
        (p_datos->>'tercero_id')::INT,
        COALESCE((p_datos->>'fecha')::DATE, CURRENT_DATE),
        p_datos->>'observacion',
        v_usr_id
    )
    RETURNING id INTO v_compra_id;

    -- Insert line items
    INSERT INTO doc.compra_detalle(compra_id, item_id, cantidad, precio_unitario, usr_cre)
    SELECT v_compra_id,
           (d->>'item_id')::INT,
           (d->>'cantidad')::NUMERIC,
           (d->>'precio_unitario')::NUMERIC,
           v_usr_id
    FROM jsonb_array_elements(COALESCE(p_datos->'detalle', '[]'::jsonb)) d;

    -- Link entregas
    IF p_datos->'entrega_ids' IS NOT NULL AND jsonb_array_length(p_datos->'entrega_ids') > 0 THEN
        INSERT INTO doc.compra_entrega(compra_id, entrega_id)
        SELECT v_compra_id, jsonb_array_elements_text(p_datos->'entrega_ids')::bigint
        ON CONFLICT DO NOTHING;
    END IF;

    -- Link facturas
    IF p_datos->'factura_ids' IS NOT NULL AND jsonb_array_length(p_datos->'factura_ids') > 0 THEN
        INSERT INTO doc.compra_factura_proveedor(compra_id, factura_proveedor_id, usr_cre)
        SELECT v_compra_id, jsonb_array_elements_text(p_datos->'factura_ids')::bigint, v_usr_id
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN v_compra_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in crear_compra - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- actualizar_compra
-- Updates editable fields of a purchase order.
-- Blocked if the compra is already anulada.
-- Optional full-replace semantics when key is present:
--   'detalle'     → replaces all line items
--   'entrega_ids'    → replaces all entrega links
--   'factura_ids' → replaces all factura links
-- tercero_id is immutable after creation.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.actualizar_compra(
    p_compra_id bigint,
    p_datos     jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message   text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_fyh_elm   timestamptz;
    v_tercero_id int;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_compra', v_usr_id,
            jsonb_build_object('compra_id', p_compra_id) || p_datos);

    SELECT fyh_elm, tercero_id INTO v_fyh_elm, v_tercero_id
    FROM doc.compra WHERE id = p_compra_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;
    IF v_fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Compra #% ya está anulada.', p_compra_id;
    END IF;

    UPDATE doc.compra
    SET fecha       = COALESCE((p_datos->>'fecha')::DATE, fecha),
        observacion = p_datos->>'observacion',
        usr_mod     = v_usr_id,
        fyh_mod     = NOW()
    WHERE id = p_compra_id;

    -- Replace line items only when 'detalle' key is explicitly present
    IF p_datos ? 'detalle' THEN
        DELETE FROM doc.compra_detalle WHERE compra_id = p_compra_id;

        IF jsonb_array_length(p_datos->'detalle') > 0 THEN
            INSERT INTO doc.compra_detalle (compra_id, item_id, cantidad, precio_unitario, usr_cre)
            SELECT p_compra_id,
                   (d->>'item_id')::INT,
                   (d->>'cantidad')::NUMERIC,
                   (d->>'precio_unitario')::NUMERIC,
                   v_usr_id
            FROM jsonb_array_elements(p_datos->'detalle') d;
        END IF;
    END IF;

    -- Replace entrega links only when 'entrega_ids' key is explicitly present
    IF p_datos ? 'entrega_ids' THEN
        IF jsonb_array_length(p_datos->'entrega_ids') > 0 THEN
            IF EXISTS (
                SELECT 1 FROM doc.entrega
                WHERE id IN (SELECT jsonb_array_elements_text(p_datos->'entrega_ids')::bigint)
                  AND tercero_id IS DISTINCT FROM v_tercero_id
            ) THEN
                RAISE EXCEPTION 'Una o más guías no pertenecen al proveedor de la compra #%.', p_compra_id;
            END IF;
        END IF;

        DELETE FROM doc.compra_entrega WHERE compra_id = p_compra_id;

        IF jsonb_array_length(p_datos->'entrega_ids') > 0 THEN
            INSERT INTO doc.compra_entrega(compra_id, entrega_id)
            SELECT p_compra_id, jsonb_array_elements_text(p_datos->'entrega_ids')::bigint
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    -- Replace factura links only when 'factura_ids' key is explicitly present
    IF p_datos ? 'factura_ids' THEN
        IF jsonb_array_length(p_datos->'factura_ids') > 0 THEN
            IF EXISTS (
                SELECT 1 FROM doc.factura_proveedor
                WHERE id IN (SELECT jsonb_array_elements_text(p_datos->'factura_ids')::bigint)
                  AND tercero_id IS DISTINCT FROM v_tercero_id
            ) THEN
                RAISE EXCEPTION 'Una o más facturas no pertenecen al proveedor de la compra #%.', p_compra_id;
            END IF;
        END IF;

        DELETE FROM doc.compra_factura_proveedor WHERE compra_id = p_compra_id;

        IF jsonb_array_length(p_datos->'factura_ids') > 0 THEN
            INSERT INTO doc.compra_factura_proveedor(compra_id, factura_proveedor_id, usr_cre)
            SELECT p_compra_id, jsonb_array_elements_text(p_datos->'factura_ids')::bigint, v_usr_id
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    RETURN format('Compra #%s actualizada.', p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- registrar_factura_proveedor
-- Creates a supplier invoice (SUNAT comprobante) and optionally
-- links it to an existing compra.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_factura_proveedor(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     int    := get_user_id();
    v_factura_id bigint;
    v_compra_id  bigint := (p_datos->>'compra_id')::BIGINT;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_factura_proveedor', v_usr_id, p_datos);

    IF COALESCE((p_datos->>'subtotal')::NUMERIC, 0) <= 0 THEN
        RAISE EXCEPTION 'El subtotal debe ser mayor a cero.';
    END IF;
    IF COALESCE((p_datos->>'total')::NUMERIC, 0) <= 0 THEN
        RAISE EXCEPTION 'El total debe ser mayor a cero.';
    END IF;

    -- subtotal + igv must equal total (tolerance matches table CHECK: < 0.01)
    IF ABS(
        (p_datos->>'total')::NUMERIC -
        (COALESCE((p_datos->>'subtotal')::NUMERIC, 0) + COALESCE((p_datos->>'igv')::NUMERIC, 0))
    ) > 0.01 THEN
        RAISE EXCEPTION 'Total (%) no coincide con subtotal + IGV (% + % = %)',
            p_datos->>'total',
            p_datos->>'subtotal',
            p_datos->>'igv',
            COALESCE((p_datos->>'subtotal')::NUMERIC, 0) + COALESCE((p_datos->>'igv')::NUMERIC, 0);
    END IF;

    -- tipo_cambio required for USD invoices
    IF COALESCE(p_datos->>'moneda', 'USD') = 'USD'
       AND (p_datos->>'tipo_cambio') IS NULL THEN
        RAISE EXCEPTION 'Se requiere tipo_cambio para facturas en USD.';
    END IF;

    INSERT INTO doc.factura_proveedor(
        tercero_id, serie, numero,
        fecha_emision, fecha_vencimiento,
        tipo_pago, moneda, tipo_cambio,
        subtotal, igv, total,
        observacion, usr_cre
    )
    VALUES (
        (p_datos->>'tercero_id')::INT,
        p_datos->>'serie',
        (p_datos->>'numero')::INT,
        (p_datos->>'fecha_emision')::DATE,
        (p_datos->>'fecha_vencimiento')::DATE,
        COALESCE((p_datos->>'tipo_pago')::tipo_pago_enum, 'al contado'),
        COALESCE(p_datos->>'moneda', 'USD'),
        (p_datos->>'tipo_cambio')::NUMERIC,
        (p_datos->>'subtotal')::NUMERIC,
        COALESCE((p_datos->>'igv')::NUMERIC, 0),
        (p_datos->>'total')::NUMERIC,
        p_datos->>'observacion',
        v_usr_id
    )
    RETURNING id INTO v_factura_id;

    -- Insert detail lines if provided
    -- p_datos->'lineas': [{item_id, cantidad, precio_unitario, igv_porcentaje?}]
    IF p_datos ? 'lineas' AND jsonb_array_length(p_datos->'lineas') > 0 THEN
        INSERT INTO doc.factura_proveedor_detalle (
            factura_proveedor_id, item_id, cantidad, precio_unitario, igv_porcentaje, usr_cre
        )
        SELECT
            v_factura_id,
            (l->>'item_id')::INT,
            (l->>'cantidad')::NUMERIC,
            (l->>'precio_unitario')::NUMERIC,
            COALESCE((l->>'igv_porcentaje')::NUMERIC, 18),
            v_usr_id
        FROM jsonb_array_elements(p_datos->'lineas') l;
    END IF;

    -- Link to compra if provided
    IF v_compra_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM doc.compra
            WHERE id = v_compra_id
              AND tercero_id = (p_datos->>'tercero_id')::INT
        ) THEN
            RAISE EXCEPTION 'Compra #% no encontrada o no pertenece al mismo proveedor.', v_compra_id;
        END IF;

        INSERT INTO doc.compra_factura_proveedor(compra_id, factura_proveedor_id, usr_cre)
        VALUES (v_compra_id, v_factura_id, v_usr_id)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN v_factura_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_factura_proveedor - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- registrar_letra
-- SAP clearing model: one payment document (letra) issued to a
-- tercero that can clear one or more supplier invoices.
--
-- p_datos shape:
-- {
--   "tercero_id":          INT,
--   "numero":              TEXT   (optional),
--   "monto":               NUMERIC,
--   "fecha_giro":          DATE   (optional),
--   "fecha_vencimiento":   DATE,
--   "banco":               TEXT   (optional),
--   "facturas": [
--     { "factura_proveedor_id": BIGINT, "monto_aplicado": NUMERIC }
--   ]
-- }
--
-- Returns the new letra.id.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_letra(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int    := get_user_id();
    v_tercero_id    int    := (p_datos->>'tercero_id')::INT;
    v_letra_id      bigint;
    v_total_aplicado numeric;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_letra', v_usr_id, p_datos);

    -- All linked facturas must belong to the same tercero as the letra
    IF p_datos ? 'facturas' AND jsonb_array_length(p_datos->'facturas') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.factura_proveedor fp
            WHERE fp.id IN (
                SELECT (f->>'factura_proveedor_id')::bigint
                FROM jsonb_array_elements(p_datos->'facturas') f
            )
            AND fp.tercero_id IS DISTINCT FROM v_tercero_id
        ) THEN
            RAISE EXCEPTION 'Una o más facturas no pertenecen al tercero indicado (%).', v_tercero_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM doc.factura_proveedor fp
            WHERE fp.id IN (
                SELECT (f->>'factura_proveedor_id')::bigint
                FROM jsonb_array_elements(p_datos->'facturas') f
            )
            AND fp.estado_pago IN ('total', 'anulado')
        ) THEN
            RAISE EXCEPTION 'Una o más facturas ya están completamente pagadas o anuladas.';
        END IF;
    END IF;

    -- Validate sum of monto_aplicado does not exceed letra monto
    SELECT COALESCE(SUM((f->>'monto_aplicado')::NUMERIC), 0)
    INTO v_total_aplicado
    FROM jsonb_array_elements(COALESCE(p_datos->'facturas', '[]'::jsonb)) f;

    IF v_total_aplicado > (p_datos->>'monto')::NUMERIC THEN
        RAISE EXCEPTION 'Monto aplicado total (%) excede monto de letra (%).',
            v_total_aplicado, (p_datos->>'monto')::NUMERIC;
    END IF;

    -- Create the letra header
    INSERT INTO doc.letra(
        tercero_id, numero, monto,
        fecha_giro, fecha_vencimiento, banco, usr_cre
    )
    VALUES (
        v_tercero_id,
        p_datos->>'numero',
        (p_datos->>'monto')::NUMERIC,
        (p_datos->>'fecha_giro')::DATE,
        (p_datos->>'fecha_vencimiento')::DATE,
        p_datos->>'banco',
        v_usr_id
    )
    RETURNING id INTO v_letra_id;

    -- Link to invoices via clearing junction
    IF p_datos ? 'facturas' AND jsonb_array_length(p_datos->'facturas') > 0 THEN
        INSERT INTO doc.letra_factura(letra_id, factura_proveedor_id, monto_aplicado, fyh_cre)
        SELECT
            v_letra_id,
            (f->>'factura_proveedor_id')::bigint,
            (f->>'monto_aplicado')::NUMERIC,
            NOW()
        FROM jsonb_array_elements(p_datos->'facturas') f;

        -- Mark linked facturas as credito payment type
        UPDATE doc.factura_proveedor
        SET tipo_pago = 'credito', usr_mod = v_usr_id, fyh_mod = NOW()
        WHERE id IN (
            SELECT (f->>'factura_proveedor_id')::bigint
            FROM jsonb_array_elements(p_datos->'facturas') f
        );
    END IF;

    RETURN v_letra_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_letra - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- pagar_letra
-- Marks a letra as paid. Cascades estado_pago to the factura:
--   all paid → 'total' | some paid → 'parcial'
-- ───────────────────────────────────────────────────────────────
-- p_cuenta_financiera_id: account the letra is paid FROM. When supplied,
--   posts a tesoreria EGRESO. Optional (NULL) for backward compatibility.
-- estado_pago is now amount-based (paid letras + cash pagos), reconciled
--   by doc.recalcular_estado_pago_factura_proveedor (funciones/pagos_proveedor.sql).
-- Drop the pre-treasury 2-arg signature so the new overload is unambiguous.
DROP FUNCTION IF EXISTS doc.pagar_letra(bigint, date);
CREATE OR REPLACE FUNCTION doc.pagar_letra(
    p_letra_id             bigint,
    p_fecha_pago           date   DEFAULT CURRENT_DATE,
    p_cuenta_financiera_id int    DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'tesoreria'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_letra           doc.letra%ROWTYPE;
    v_facturas_count  int := 0;
    v_factura_rec     record;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_letra FROM doc.letra WHERE id = p_letra_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Letra #% no encontrada.', p_letra_id;
    END IF;
    IF v_letra.estado NOT IN ('emitida', 'vencida') THEN
        RAISE EXCEPTION 'La letra #% ya está en estado %. Solo se pueden pagar letras emitidas o vencidas.',
            p_letra_id, v_letra.estado;
    END IF;

    UPDATE doc.letra
    SET estado     = 'pagada',
        fecha_pago = p_fecha_pago,
        usr_mod    = v_usr_id,
        fyh_mod    = NOW()
    WHERE id = p_letra_id;

    -- Cash ledger (EGRESO). No-op when no paying account supplied.
    PERFORM tesoreria.registrar_movimiento(
        p_cuenta_financiera_id := p_cuenta_financiera_id,
        p_tipo                 := 'EGRESO',
        p_monto                := v_letra.monto,
        p_moneda               := 'USD',
        p_documento_tipo       := 'letra',
        p_documento_id         := p_letra_id,
        p_fecha                := p_fecha_pago,
        p_medio_pago           := 'LETRA',
        p_referencia           := v_letra.numero,
        p_glosa                := format('Pago letra #%s proveedor %s', p_letra_id, v_letra.tercero_id)
    );

    -- Recompute estado_pago (amount-based) on every factura this letra cleared.
    FOR v_factura_rec IN
        SELECT factura_proveedor_id FROM doc.letra_factura WHERE letra_id = p_letra_id
    LOOP
        PERFORM doc.recalcular_estado_pago_factura_proveedor(v_factura_rec.factura_proveedor_id);
        v_facturas_count := v_facturas_count + 1;
    END LOOP;

    RETURN format('Letra #%s pagada el %s. %s factura(s) actualizada(s).',
        p_letra_id, p_fecha_pago, v_facturas_count);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in pagar_letra - User: %, letra: %, Error: %', v_usr_id, p_letra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- fn_refresh_compra_detalle_qtys  (manual re-sync utility)
-- Recomputes cantidad_recibida from posted movements.
-- Not called automatically — ingresar_compra increments inline.
-- Use this for manual data corrections or backfills only.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.fn_refresh_compra_detalle_qtys(p_compra_id BIGINT)
RETURNS void
LANGUAGE sql
SET search_path TO 'doc', 'inventario', 'public'
AS $$
    UPDATE doc.compra_detalle cd
    SET cantidad_recibida = COALESCE((
        SELECT SUM(im.cantidad)
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE imt.codigo = 'COMPRA_ING'
          AND im.item_id = cd.item_id
          AND im.documento_tipo = 'entrega'
          AND im.documento_id IN (
              SELECT entrega_id FROM doc.compra_entrega
              WHERE compra_id = p_compra_id
          )
    ), 0)
    WHERE cd.compra_id = p_compra_id;
$$;

-- ───────────────────────────────────────────────────────────────
-- vincular_entregas_compra
-- Links one or more entregas to an existing compra.
-- Validates each entrega belongs to the compra's proveedor.
-- Idempotent: ON CONFLICT DO NOTHING.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.vincular_entregas_compra(
    p_compra_id bigint,
    p_entrega_ids  jsonb   -- [1, 2, 3]
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     int := get_user_id();
    v_proveedor  int;
    v_linked     int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT tercero_id INTO v_proveedor
    FROM doc.compra WHERE id = p_compra_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    -- All entregas must belong to the same tercero as the compra
    IF EXISTS (
        SELECT 1 FROM doc.entrega
        WHERE id IN (SELECT jsonb_array_elements_text(p_entrega_ids)::bigint)
          AND tercero_id IS DISTINCT FROM v_proveedor
    ) THEN
        RAISE EXCEPTION 'Una o más guías no pertenecen al proveedor de la compra #%.', p_compra_id;
    END IF;

    INSERT INTO doc.compra_entrega(compra_id, entrega_id)
    SELECT p_compra_id, jsonb_array_elements_text(p_entrega_ids)::bigint
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_linked = ROW_COUNT;

    RETURN format('%s guía(s) vinculada(s) a compra #%s.', v_linked, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in vincular_entregas_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- desvincular_entregas_compra
-- Removes one or more entrega links from a compra.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.desvincular_entregas_compra(
    p_compra_id bigint,
    p_entrega_ids  jsonb   -- [1, 2, 3]
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id   int := get_user_id();
    v_unlinked int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM doc.compra WHERE id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    DELETE FROM doc.compra_entrega
    WHERE compra_id = p_compra_id
      AND entrega_id IN (
          SELECT jsonb_array_elements_text(p_entrega_ids)::bigint
      );

    GET DIAGNOSTICS v_unlinked = ROW_COUNT;

    RETURN format('%s guía(s) desvinculada(s) de compra #%s.', v_unlinked, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in desvincular_entregas_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- vincular_facturas_compra
-- Links one or more facturas to an existing compra.
-- Validates each factura belongs to the compra's proveedor.
-- Idempotent: ON CONFLICT DO NOTHING.
-- ───────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS doc.vincular_factura_compra(bigint, bigint, text);

CREATE OR REPLACE FUNCTION doc.vincular_facturas_compra(
    p_compra_id   bigint,
    p_factura_ids jsonb   -- [1, 2, 3]
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_proveedor int;
    v_linked    int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT tercero_id INTO v_proveedor
    FROM doc.compra WHERE id = p_compra_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM doc.factura_proveedor
        WHERE id IN (SELECT jsonb_array_elements_text(p_factura_ids)::bigint)
          AND tercero_id IS DISTINCT FROM v_proveedor
    ) THEN
        RAISE EXCEPTION 'Una o más facturas no pertenecen al proveedor de la compra #%.', p_compra_id;
    END IF;

    INSERT INTO doc.compra_factura_proveedor(compra_id, factura_proveedor_id, usr_cre)
    SELECT p_compra_id, jsonb_array_elements_text(p_factura_ids)::bigint, v_usr_id
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_linked = ROW_COUNT;

    RETURN format('%s factura(s) vinculada(s) a compra #%s.', v_linked, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in vincular_facturas_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- desvincular_facturas_compra
-- Removes one or more factura links from a compra.
-- ───────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS doc.desvincular_factura_compra(bigint, bigint);

CREATE OR REPLACE FUNCTION doc.desvincular_facturas_compra(
    p_compra_id   bigint,
    p_factura_ids jsonb   -- [1, 2, 3]
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id   int := get_user_id();
    v_unlinked int;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM doc.compra WHERE id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    DELETE FROM doc.compra_factura_proveedor
    WHERE compra_id = p_compra_id
      AND factura_proveedor_id IN (
          SELECT jsonb_array_elements_text(p_factura_ids)::bigint
      );

    GET DIAGNOSTICS v_unlinked = ROW_COUNT;

    RETURN format('%s factura(s) desvinculada(s) de compra #%s.', v_unlinked, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in desvincular_facturas_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- marcar_compra_recibida
-- Conciliation shortcut: closes all lines by setting cantidad_recibida = cantidad.
-- Use when stock was already set via inventory count and no movements should be posted.
-- Blocks ingresar_compra from double-posting afterward.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.marcar_compra_recibida(p_compra_id bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id  int := get_user_id();
    v_rows    int;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('marcar_compra_recibida', v_usr_id, jsonb_build_object('compra_id', p_compra_id));

    IF NOT EXISTS (SELECT 1 FROM doc.compra WHERE id = p_compra_id AND fyh_elm IS NULL) THEN
        RAISE EXCEPTION 'Compra #% no encontrada o anulada.', p_compra_id;
    END IF;

    UPDATE doc.compra_detalle
    SET cantidad_recibida = cantidad
    WHERE compra_id = p_compra_id
      AND cantidad_recibida < cantidad;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Compra #% ya está completamente recibida.', p_compra_id;
    END IF;

    RETURN format('Compra #%s marcada como recibida (%s línea(s) cerrada(s)).', p_compra_id, v_rows);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in marcar_compra_recibida - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.crear_compra(jsonb)                           TO authenticated;
GRANT EXECUTE ON FUNCTION doc.actualizar_compra(bigint, jsonb)              TO authenticated;
GRANT EXECUTE ON FUNCTION doc.registrar_factura_proveedor(jsonb)            TO authenticated;
GRANT EXECUTE ON FUNCTION doc.registrar_letra(jsonb)                        TO authenticated;
GRANT EXECUTE ON FUNCTION doc.pagar_letra(bigint, date, int)                TO authenticated;
GRANT EXECUTE ON FUNCTION doc.vincular_entregas_compra(bigint, jsonb)          TO authenticated;
GRANT EXECUTE ON FUNCTION doc.desvincular_entregas_compra(bigint, jsonb)       TO authenticated;
GRANT EXECUTE ON FUNCTION doc.vincular_facturas_compra(bigint, jsonb)       TO authenticated;
GRANT EXECUTE ON FUNCTION doc.desvincular_facturas_compra(bigint, jsonb)    TO authenticated;
GRANT EXECUTE ON FUNCTION doc.marcar_compra_recibida(bigint)                TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- get_compra
-- Full read: compra header + line items + linked entregas + linked
-- supplier invoices. Designed for document-detail screens.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_compra(p_compra_id BIGINT)
RETURNS JSONB
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $$
SELECT jsonb_build_object(
    'id',          c.id,
    'tercero_id',  c.tercero_id,
    'proveedor',   t.nombre,
    'fecha',       c.fecha,
    'observacion', c.observacion,
    'fyh_elm',     c.fyh_elm,
    'fyh_cre',     c.fyh_cre,
    'detalle', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id',                cd.id,
            'item_id',           cd.item_id,
            'item_codigo',       i.codigo,
            'item_nombre',       i.nombre,
            'cantidad',          cd.cantidad,
            'precio_unitario',   cd.precio_unitario,
            'cantidad_recibida', cd.cantidad_recibida
        ) ORDER BY cd.id)
        FROM doc.compra_detalle cd
        JOIN item i ON i.id = cd.item_id
        WHERE cd.compra_id = c.id
    ), '[]'::jsonb),
    'entregas', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'entrega_id', gr.id,
            'serie',            gr.serie,
            'correlativo',      gr.correlativo,
            'fecha_emision',    gr.fecha_emision,
            'tipo',             grt.nombre
        ) ORDER BY gr.fecha_emision, gr.id)
        FROM doc.compra_entrega cgr
        JOIN doc.entrega gr         ON gr.id = cgr.entrega_id
        JOIN doc.entrega_tipo grt   ON grt.id = gr.entrega_tipo_id
        WHERE cgr.compra_id = c.id
    ), '[]'::jsonb),
    'facturas', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'factura_proveedor_id', fp.id,
            'serie',                fp.serie,
            'numero',               fp.numero,
            'fecha_emision',        fp.fecha_emision,
            'total',                fp.total,
            'moneda',               fp.moneda,
            'estado_pago',          fp.estado_pago,
            'observacion',          fp.observacion
        ) ORDER BY fp.fecha_emision, fp.id)
        FROM doc.compra_factura_proveedor cfp
        JOIN doc.factura_proveedor fp ON fp.id = cfp.factura_proveedor_id
        WHERE cfp.compra_id = c.id
    ), '[]'::jsonb)
)
FROM doc.compra c
JOIN tercero t ON t.id = c.tercero_id
WHERE c.id = p_compra_id;
$$;


-- ───────────────────────────────────────────────────────────────
-- get_factura_proveedor
-- Full read: supplier invoice header + line items + linked letras
-- (with monto_aplicado) + linked compras.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_factura_proveedor(p_factura_id BIGINT)
RETURNS JSONB
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $$
SELECT jsonb_build_object(
    'id',                fp.id,
    'tercero_id',        fp.tercero_id,
    'proveedor',         t.nombre,
    'serie',             fp.serie,
    'numero',            fp.numero,
    'fecha_emision',     fp.fecha_emision,
    'fecha_vencimiento', fp.fecha_vencimiento,
    'tipo_pago',         fp.tipo_pago,
    'moneda',            fp.moneda,
    'tipo_cambio',       fp.tipo_cambio,
    'subtotal',          fp.subtotal,
    'igv',               fp.igv,
    'total',             fp.total,
    'estado_pago',       fp.estado_pago,
    'observacion',       fp.observacion,
    'fyh_cre',           fp.fyh_cre,
    'lineas', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id',              fpd.id,
            'item_id',         fpd.item_id,
            'item_codigo',     i.codigo,
            'item_nombre',     i.nombre,
            'cantidad',        fpd.cantidad,
            'precio_unitario', fpd.precio_unitario,
            'igv_porcentaje',  fpd.igv_porcentaje,
            'subtotal_linea',  fpd.subtotal_linea,
            'igv_linea',       fpd.igv_linea,
            'total_linea',     fpd.total_linea
        ) ORDER BY fpd.id)
        FROM doc.factura_proveedor_detalle fpd
        JOIN item i ON i.id = fpd.item_id
        WHERE fpd.factura_proveedor_id = fp.id
    ), '[]'::jsonb),
    'letras', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'letra_id',           l.id,
            'numero',             l.numero,
            'monto',              l.monto,
            'monto_aplicado',     lf.monto_aplicado,
            'fecha_vencimiento',  l.fecha_vencimiento,
            'fecha_pago',         l.fecha_pago,
            'banco',              l.banco,
            'estado',             l.estado
        ) ORDER BY l.fecha_vencimiento, l.id)
        FROM doc.letra_factura lf
        JOIN doc.letra l ON l.id = lf.letra_id
        WHERE lf.factura_proveedor_id = fp.id
          AND l.estado != 'anulada'
    ), '[]'::jsonb),
    'compras', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'compra_id',   c.id,
            'fecha',       c.fecha,
            'observacion', c.observacion,
            'monto_total', COALESCE((
                SELECT SUM(cd.cantidad * cd.precio_unitario)
                FROM doc.compra_detalle cd WHERE cd.compra_id = c.id
            ), 0),
            'total_items', COALESCE((
                SELECT COUNT(*) FROM doc.compra_detalle cd WHERE cd.compra_id = c.id
            ), 0),
            'fyh_elm',     c.fyh_elm
        ) ORDER BY c.fecha, c.id)
        FROM doc.compra_factura_proveedor cfp
        JOIN doc.compra c ON c.id = cfp.compra_id
        WHERE cfp.factura_proveedor_id = fp.id
    ), '[]'::jsonb)
)
FROM doc.factura_proveedor fp
JOIN tercero t ON t.id = fp.tercero_id
WHERE fp.id = p_factura_id;
$$;


-- ───────────────────────────────────────────────────────────────
-- get_letra
-- Full read: letra header + all linked facturas with monto_aplicado.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_letra(p_letra_id BIGINT)
RETURNS JSONB
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $$
SELECT jsonb_build_object(
    'id',                l.id,
    'tercero_id',        l.tercero_id,
    'proveedor',         t.nombre,
    'numero',            l.numero,
    'monto',             l.monto,
    'fecha_giro',        l.fecha_giro,
    'fecha_vencimiento', l.fecha_vencimiento,
    'fecha_pago',        l.fecha_pago,
    'banco',             l.banco,
    'estado',            l.estado,
    'observacion',       l.observacion,
    'facturas', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'factura_proveedor_id', fp.id,
            'serie',                fp.serie,
            'numero',               fp.numero,
            'fecha_emision',        fp.fecha_emision,
            'total',                fp.total,
            'moneda',               fp.moneda,
            'monto_aplicado',       lf.monto_aplicado,
            'estado_pago',          fp.estado_pago
        ) ORDER BY fp.fecha_emision, fp.id)
        FROM doc.letra_factura lf
        JOIN doc.factura_proveedor fp ON fp.id = lf.factura_proveedor_id
        WHERE lf.letra_id = l.id
    ), '[]'::jsonb)
)
FROM doc.letra l
JOIN tercero t ON t.id = l.tercero_id
WHERE l.id = p_letra_id;
$$;


-- ───────────────────────────────────────────────────────────────
-- anular_compra
-- Soft-deletes a compra (sets fyh_elm).
-- Blocked if any linked factura_proveedor is not anulada.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_compra(p_compra_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id int := get_user_id();
    v_found  boolean;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_compra', v_usr_id, jsonb_build_object('compra_id', p_compra_id));

    SELECT (fyh_elm IS NOT NULL) INTO v_found
    FROM doc.compra WHERE id = p_compra_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;
    IF v_found THEN
        RAISE EXCEPTION 'Compra #% ya está anulada.', p_compra_id;
    END IF;

    -- Block if any linked factura is still active
    IF EXISTS (
        SELECT 1
        FROM doc.compra_factura_proveedor cfp
        JOIN doc.factura_proveedor fp ON fp.id = cfp.factura_proveedor_id
        WHERE cfp.compra_id = p_compra_id
          AND fp.estado_pago <> 'anulado'
    ) THEN
        RAISE EXCEPTION 'No se puede anular la compra #%: tiene facturas activas vinculadas. Anule primero las facturas.', p_compra_id;
    END IF;

    UPDATE doc.compra
    SET usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE id = p_compra_id;

    RETURN format('Compra #%s anulada.', p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;


-- ───────────────────────────────────────────────────────────────
-- anular_factura_proveedor
-- Cancels a supplier invoice. Blocked if any linked letra is 'pagada'
-- (money already moved). Letters in other states (emitida, vencida,
-- protestada) are left as-is; the UI can show them as clearing a
-- cancelled invoice.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_factura_proveedor(p_factura_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     int := get_user_id();
    v_estado_pago estado_pago_enum;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_factura_proveedor', v_usr_id, jsonb_build_object('factura_id', p_factura_id));

    SELECT estado_pago INTO v_estado_pago
    FROM doc.factura_proveedor WHERE id = p_factura_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_id;
    END IF;
    IF v_estado_pago = 'anulado' THEN
        RAISE EXCEPTION 'Factura #% ya está anulada.', p_factura_id;
    END IF;

    -- Block if any letra that cleared this invoice is already paid
    IF EXISTS (
        SELECT 1
        FROM doc.letra_factura lf
        JOIN doc.letra l ON l.id = lf.letra_id
        WHERE lf.factura_proveedor_id = p_factura_id
          AND l.estado = 'pagada'
    ) THEN
        RAISE EXCEPTION 'No se puede anular la factura #%: tiene letras pagadas vinculadas. Revisar con contabilidad.', p_factura_id;
    END IF;

    UPDATE doc.factura_proveedor
    SET estado_pago = 'anulado', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_factura_id;

    RETURN format('Factura proveedor #%s anulada.', p_factura_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_factura_proveedor - User: %, factura: %, Error: %', v_usr_id, p_factura_id, v_message;
    RAISE;
END;
$function$;


-- ───────────────────────────────────────────────────────────────
-- anular_letra
-- Cancels a payment letter. Blocked if already pagada/anulada.
-- Cascades to recalculate estado_pago on every linked factura:
--   no pagada letras remain → 'pendiente'
--   all non-anulada letras pagada → 'total'
--   mix of paid and unpaid → 'parcial'
-- Facturas already anuladas are skipped.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_letra(p_letra_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_estado_actual letra_estado_enum;
    v_facturas_count int;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_letra', v_usr_id, jsonb_build_object('letra_id', p_letra_id));

    SELECT estado INTO v_estado_actual
    FROM doc.letra WHERE id = p_letra_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Letra #% no encontrada.', p_letra_id;
    END IF;
    IF v_estado_actual = 'pagada' THEN
        RAISE EXCEPTION 'No se puede anular la letra #%: ya fue pagada. Revisar con contabilidad.', p_letra_id;
    END IF;
    IF v_estado_actual = 'anulada' THEN
        RAISE EXCEPTION 'Letra #% ya está anulada.', p_letra_id;
    END IF;

    UPDATE doc.letra
    SET estado = 'anulada', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_letra_id;

    -- Cascade: recalculate estado_pago for every factura cleared by this letra.
    -- Skip facturas already anuladas.
    UPDATE doc.factura_proveedor fp
    SET estado_pago = CASE
            -- No paid letra at all → fully unpaid again
            WHEN NOT EXISTS (
                SELECT 1
                FROM doc.letra_factura lf2
                JOIN doc.letra l2 ON l2.id = lf2.letra_id
                WHERE lf2.factura_proveedor_id = fp.id
                  AND l2.estado = 'pagada'
            ) THEN 'pendiente'
            -- All non-anulada letras are paid → fully settled
            WHEN NOT EXISTS (
                SELECT 1
                FROM doc.letra_factura lf2
                JOIN doc.letra l2 ON l2.id = lf2.letra_id
                WHERE lf2.factura_proveedor_id = fp.id
                  AND l2.estado NOT IN ('pagada', 'anulada')
            ) THEN 'total'
            -- Mix: some paid, some still open
            ELSE 'parcial'
        END,
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE fp.id IN (
        SELECT factura_proveedor_id FROM doc.letra_factura WHERE letra_id = p_letra_id
    )
    AND fp.estado_pago <> 'anulado';

    GET DIAGNOSTICS v_facturas_count = ROW_COUNT;

    RETURN format('Letra #%s anulada. %s factura(s) recalculada(s).', p_letra_id, v_facturas_count);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_letra - User: %, letra: %, Error: %', v_usr_id, p_letra_id, v_message;
    RAISE;
END;
$function$;


GRANT EXECUTE ON FUNCTION doc.get_compra(bigint)                   TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_factura_proveedor(bigint)        TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_letra(bigint)                    TO authenticated;
GRANT EXECUTE ON FUNCTION doc.anular_compra(bigint)                TO authenticated;
GRANT EXECUTE ON FUNCTION doc.anular_factura_proveedor(bigint)     TO authenticated;
GRANT EXECUTE ON FUNCTION doc.anular_letra(bigint)                 TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- actualizar_factura_proveedor
-- Updates editable header fields of a supplier invoice.
-- Never touches estado_pago (owned by pagar_letra / anular_letra /
-- anular_factura_proveedor) or tercero_id (immutable after creation).
-- Optionally replaces all line items when 'lineas' key is present.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.actualizar_factura_proveedor(
    p_factura_id bigint,
    p_datos      jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id      int := get_user_id();
    v_estado_pago estado_pago_enum;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_factura_proveedor', v_usr_id,
            jsonb_build_object('factura_id', p_factura_id) || p_datos);

    SELECT estado_pago INTO v_estado_pago
    FROM doc.factura_proveedor WHERE id = p_factura_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_id;
    END IF;
    IF v_estado_pago = 'anulado' THEN
        RAISE EXCEPTION 'Factura #% ya está anulada.', p_factura_id;
    END IF;
    IF v_estado_pago = 'total' THEN
        RAISE EXCEPTION 'Factura #% ya está completamente pagada y no puede modificarse.', p_factura_id;
    END IF;

    -- Validate subtotal + igv ≈ total
    IF ABS(
        (p_datos->>'total')::NUMERIC -
        (COALESCE((p_datos->>'subtotal')::NUMERIC, 0) +
         COALESCE((p_datos->>'igv')::NUMERIC, 0))
    ) > 0.01 THEN
        RAISE EXCEPTION 'Total (%) no coincide con subtotal + IGV (% + % = %)',
            p_datos->>'total',
            p_datos->>'subtotal',
            p_datos->>'igv',
            COALESCE((p_datos->>'subtotal')::NUMERIC, 0) +
            COALESCE((p_datos->>'igv')::NUMERIC, 0);
    END IF;

    -- tipo_cambio required for USD
    IF COALESCE(p_datos->>'moneda', 'USD') = 'USD'
       AND (p_datos->>'tipo_cambio') IS NULL THEN
        RAISE EXCEPTION 'Se requiere tipo_cambio para facturas en USD.';
    END IF;

    UPDATE doc.factura_proveedor
    SET
        serie             = p_datos->>'serie',
        numero            = (p_datos->>'numero')::INT,
        fecha_emision     = (p_datos->>'fecha_emision')::DATE,
        fecha_vencimiento = (p_datos->>'fecha_vencimiento')::DATE,
        tipo_pago         = COALESCE((p_datos->>'tipo_pago')::tipo_pago_enum, tipo_pago),
        moneda            = COALESCE(p_datos->>'moneda', moneda),
        tipo_cambio       = (p_datos->>'tipo_cambio')::NUMERIC,
        subtotal          = (p_datos->>'subtotal')::NUMERIC,
        igv               = COALESCE((p_datos->>'igv')::NUMERIC, 0),
        total             = (p_datos->>'total')::NUMERIC,
        observacion       = p_datos->>'observacion',
        usr_mod           = v_usr_id,
        fyh_mod           = NOW()
    WHERE id = p_factura_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_id;
    END IF;

    -- Replace line items only when 'lineas' key is explicitly present
    IF p_datos ? 'lineas' THEN
        -- Block if any letra is already paid (covers parcial estado_pago)
        IF EXISTS (
            SELECT 1 FROM doc.letra_factura lf
            JOIN doc.letra l ON l.id = lf.letra_id
            WHERE lf.factura_proveedor_id = p_factura_id
              AND l.estado = 'pagada'
        ) THEN
            RAISE EXCEPTION 'No se pueden modificar las líneas de la factura #%: tiene letras pagadas vinculadas.', p_factura_id;
        END IF;

        DELETE FROM doc.factura_proveedor_detalle
        WHERE factura_proveedor_id = p_factura_id;

        IF jsonb_array_length(p_datos->'lineas') > 0 THEN
            INSERT INTO doc.factura_proveedor_detalle(
                factura_proveedor_id, item_id, cantidad,
                precio_unitario, igv_porcentaje, usr_cre
            )
            SELECT
                p_factura_id,
                (l->>'item_id')::INT,
                (l->>'cantidad')::NUMERIC,
                (l->>'precio_unitario')::NUMERIC,
                COALESCE((l->>'igv_porcentaje')::NUMERIC, 18),
                v_usr_id
            FROM jsonb_array_elements(p_datos->'lineas') l;
        END IF;
    END IF;

    RETURN format('Factura #%s actualizada.', p_factura_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_factura_proveedor - User: %, factura: %, Error: %',
        v_usr_id, p_factura_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.actualizar_factura_proveedor(bigint, jsonb) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- doc.marcar_letras_vencidas
-- Transitions emitida → vencida for all letras past their due date.
-- Called by pg_cron; not user-facing.
-- Returns the number of letras transitioned.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.marcar_letras_vencidas()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'doc', 'public'
AS $$
DECLARE
    v_count int;
BEGIN
    UPDATE doc.letra
    SET estado  = 'vencida',
        fyh_mod = NOW()
    WHERE estado = 'emitida'
      AND fecha_vencimiento < CURRENT_DATE;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count > 0 THEN
        RAISE LOG 'marcar_letras_vencidas: % letra(s) marcada(s) como vencida.', v_count;
    END IF;

    RETURN v_count;
END;
$$;

-- ───────────────────────────────────────────────────────────────
-- doc.ingresar_compra
-- Posts stock movements for purchased items (insumos or rolls) against a compra.
-- Primary use case: insumos (chemicals, dyes, etc.).
-- Roll purchases are rare but supported via the same function.
--
-- Item type is detected automatically — no caller flag needed:
--   INSUMO → one lote per line, cantidad = received quantity
--   ROLLO  → one lote per roll, n_rollos required, cantidad = per-roll weight
--
-- To also register the physical entrega (SUNAT document), call doc.crear_entrega
-- separately with tipo=COMPRA_INGRESO and compra_id. Independent — never posts
-- movements. Can be called before or after this function.
--
-- p_datos shape:
-- {
--   "compra_id":   123,
--   "ubicacion_id": 5,      -- optional, defaults to ALM_CRU
--   "items": [
--     { "item_id": 101, "cantidad": 50.5 },                              -- insumo
--     { "item_id": 254, "cantidad": 380.0, "n_rollos": 19 },             -- rolls (prorated)
--     { "item_id": 278, "cantidad": 1.2,   "n_rollos": 1, "prorate": false } -- roll (per-roll weight)
--   ]
-- }
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.ingresar_compra(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'inventario', 'mes', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int     := get_user_id();
    v_compra_id     bigint  := (p_datos->>'compra_id')::bigint;
    v_mov_tipo_id   smallint;
    v_doc_mov_id    bigint;
    v_ubicacion_id  int;
    v_lote_id       int;
    v_elem          jsonb;
    v_item_id       int;
    v_cantidad      numeric;
    v_n_rollos      int;
    v_prorate       boolean;
    v_peso_rollo    numeric;
    v_flg_rib       boolean;
    v_flg_rollo     boolean;
    v_precio        numeric;
    v_fecha_mov     TIMESTAMPTZ;
    v_detalle_id      bigint;     -- compra_detalle line (≈ EBELP) for documento_linea_id
    v_entrega_id      bigint;     -- optional browsable guía (inbound delivery)
    v_entrega_tipo_id smallint;
    v_tercero_id      int;
    v_has_guia        boolean;
    v_linea           smallint := 0;
    i               int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('ingresar_compra', v_usr_id, p_datos);

    IF NOT EXISTS (SELECT 1 FROM doc.compra WHERE id = v_compra_id AND fyh_elm IS NULL) THEN
        RAISE EXCEPTION 'Compra % no existe o fue eliminada', v_compra_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM doc.compra_detalle
        WHERE compra_id = v_compra_id AND cantidad_recibida < cantidad
    ) THEN
        RAISE EXCEPTION 'Compra % ya está completamente recibida.', v_compra_id;
    END IF;

    SELECT id INTO STRICT v_mov_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'COMPRA_ING';

    IF (p_datos->>'ubicacion_id') IS NOT NULL THEN
        v_ubicacion_id := (p_datos->>'ubicacion_id')::int;
    ELSE
        SELECT ub.id INTO STRICT v_ubicacion_id
        FROM inventario.ubicacion ub
        JOIN inventario.almacen alm ON alm.id = ub.almacen_id
        WHERE alm.codigo = 'ALM_CRU' LIMIT 1;
    END IF;

    v_fecha_mov  := COALESCE((p_datos->>'fecha_recepcion')::TIMESTAMPTZ, now());
    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    -- Optional supplier guía: create a browsable inbound delivery (entrega) and
    -- link it to the compra. Stock still posts against the PO below; the entrega
    -- is the logistics/browse record (≈ SAP inbound delivery), NOT a stock event.
    v_has_guia := (p_datos ? 'guia') AND (p_datos->'guia'->>'correlativo') IS NOT NULL;
    IF v_has_guia THEN
        SELECT tercero_id INTO v_tercero_id FROM doc.compra WHERE id = v_compra_id;
        SELECT id INTO STRICT v_entrega_tipo_id
        FROM doc.entrega_tipo WHERE codigo = 'COMPRA_INGRESO';

        INSERT INTO doc.entrega (entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
        VALUES (
            v_entrega_tipo_id, v_tercero_id,
            p_datos->'guia'->>'serie',
            p_datos->'guia'->>'correlativo',
            COALESCE((p_datos->'guia'->>'fecha')::TIMESTAMPTZ, v_fecha_mov),
            v_fecha_mov
        )
        RETURNING id INTO v_entrega_id;

        INSERT INTO doc.compra_entrega (compra_id, entrega_id)
        VALUES (v_compra_id, v_entrega_id)
        ON CONFLICT DO NOTHING;
    END IF;

    FOR v_elem IN SELECT jsonb_array_elements(p_datos->'items') LOOP
        v_item_id  := (v_elem->>'item_id')::int;
        v_cantidad := (v_elem->>'cantidad')::numeric;
        v_n_rollos := (v_elem->>'n_rollos')::int;  -- NULL for insumos

        SELECT EXISTS (
            SELECT 1 FROM item i
            JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
            WHERE i.id = v_item_id
        ) INTO v_flg_rollo;

        SELECT id, precio_unitario INTO v_detalle_id, v_precio
        FROM doc.compra_detalle
        WHERE compra_id = v_compra_id AND item_id = v_item_id
        ORDER BY id LIMIT 1;

        IF v_flg_rollo AND v_n_rollos IS NOT NULL THEN
            -- Roll path: one lote per roll
            v_prorate    := COALESCE((v_elem->>'prorate')::boolean, true);

            SELECT COALESCE(ird.flg_rib, false) INTO v_flg_rib
            FROM item_rollo_detalle ird WHERE ird.item_id = v_item_id;

            v_peso_rollo := CASE
                WHEN v_prorate THEN v_cantidad / v_n_rollos
                ELSE v_cantidad
            END;

            FOR i IN 1 .. v_n_rollos LOOP
                INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
                VALUES (v_item_id, 'compra', v_compra_id, v_peso_rollo, NULL, v_usr_id)
                RETURNING id INTO v_lote_id;

                INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id, flg_tenido)
                VALUES (v_lote_id, v_entrega_id, false);   -- entrega_id NULL when no guía

                INSERT INTO inventario.item_movimientos (
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, destino_ubicacion_id,
                    cantidad, precio_unitario, fecha_hora, documento_tipo, documento_id, documento_linea_id, observacion, usr_cre
                ) VALUES (
                    v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                    NULL, v_ubicacion_id,
                    v_peso_rollo, v_precio, v_fecha_mov, 'compra', v_compra_id, v_detalle_id,
                    'Ingreso compra #' || v_compra_id, v_usr_id
                );
            END LOOP;

        ELSE
            -- Insumo path (primary): one lote for the full received quantity
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
            VALUES (v_item_id, 'compra', v_compra_id, v_cantidad, NULL, v_usr_id)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id,
                cantidad, precio_unitario, fecha_hora, documento_tipo, documento_id, documento_linea_id, observacion, usr_cre
            ) VALUES (
                v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                NULL, v_ubicacion_id,
                v_cantidad, v_precio, v_fecha_mov, 'compra', v_compra_id, v_detalle_id,
                'Ingreso compra #' || v_compra_id, v_usr_id
            );

        END IF;

        -- Guía line (browsable inbound-delivery detail) — declared receipt per item
        IF v_has_guia THEN
            v_linea := v_linea + 1;
            INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, n_rollos, ubicacion_id)
            VALUES (v_entrega_id, v_linea, v_item_id, v_cantidad, v_n_rollos, v_ubicacion_id);
        END IF;

        UPDATE doc.compra_detalle
        SET cantidad_recibida = cantidad_recibida + v_cantidad
        WHERE compra_id = v_compra_id AND item_id = v_item_id;

    END LOOP;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Ingreso de compra',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id = v_usr_id), 'sistema')
               || ' ingresó stock contra compra #' || v_compra_id,
           'info',
           jsonb_build_object('objeto_tipo', 'compra', 'compra_id', v_compra_id, 'doc_movimiento_id', v_doc_mov_id)
    FROM iam.user_rol ur
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras', 'inventario') AND v_usr_id <> ur.user_id;

    RETURN v_doc_mov_id;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
        v_hint = PG_EXCEPTION_HINT, v_context = PG_EXCEPTION_CONTEXT,
        v_sqlstate = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'ingresar_compra: % | detail: % | hint: % | context: % | state: %',
        v_message, v_detail, v_hint, v_context, v_sqlstate;
END;
$$;

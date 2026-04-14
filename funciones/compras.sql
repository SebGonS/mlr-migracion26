-- ═══════════════════════════════════════════════════════════════
-- COMPRAS — Purchase / Procurement Functions
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────
-- crear_compra
-- Creates a purchase event with line items and optional guia links.
-- Inventory movements are handled by the guia, not here.
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

    -- Validate guias belong to the declared proveedor
    IF p_datos->'guia_ids' IS NOT NULL AND jsonb_array_length(p_datos->'guia_ids') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.guia_remision gr
            WHERE gr.id IN (
                SELECT jsonb_array_elements_text(p_datos->'guia_ids')::bigint
            )
            AND gr.tercero_id IS DISTINCT FROM (p_datos->>'tercero_id')::INT
        ) THEN
            RAISE EXCEPTION 'Una o más guías no pertenecen al proveedor indicado.';
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

    -- Link guias
    IF p_datos->'guia_ids' IS NOT NULL AND jsonb_array_length(p_datos->'guia_ids') > 0 THEN
        INSERT INTO doc.compra_guia_remision(compra_id, guia_remision_id)
        SELECT v_compra_id, jsonb_array_elements_text(p_datos->'guia_ids')::bigint
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

    -- subtotal + igv must equal total (within rounding tolerance)
    IF ABS(
        (p_datos->>'total')::NUMERIC -
        ((p_datos->>'subtotal')::NUMERIC + (p_datos->>'igv')::NUMERIC)
    ) > 0.02 THEN
        RAISE EXCEPTION 'Total (%) no coincide con subtotal + IGV (% + % = %)',
            p_datos->>'total',
            p_datos->>'subtotal',
            p_datos->>'igv',
            (p_datos->>'subtotal')::NUMERIC + (p_datos->>'igv')::NUMERIC;
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
        UPDATE doc.compra
        SET factura_proveedor_id = v_factura_id,
            usr_mod = v_usr_id, fyh_mod = NOW()
        WHERE id = v_compra_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Compra #% no encontrada.', v_compra_id;
        END IF;
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
CREATE OR REPLACE FUNCTION doc.pagar_letra(
    p_letra_id   bigint,
    p_fecha_pago date DEFAULT CURRENT_DATE
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_estado_actual   letra_estado_enum;
    v_facturas_count  int;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado
    INTO v_estado_actual
    FROM doc.letra WHERE id = p_letra_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Letra #% no encontrada.', p_letra_id;
    END IF;
    IF v_estado_actual NOT IN ('emitida', 'vencida') THEN
        RAISE EXCEPTION 'La letra #% ya está en estado %. Solo se pueden pagar letras emitidas o vencidas.',
            p_letra_id, v_estado_actual;
    END IF;

    UPDATE doc.letra
    SET estado     = 'pagada',
        fecha_pago = p_fecha_pago,
        usr_mod    = v_usr_id,
        fyh_mod    = NOW()
    WHERE id = p_letra_id;

    -- Cascade estado_pago to every factura cleared by this letra.
    -- A factura is 'total' when none of its linked letras remain unpaid.
    UPDATE doc.factura_proveedor fp
    SET estado_pago = CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM doc.letra_factura lf2
                JOIN doc.letra l2 ON l2.id = lf2.letra_id
                WHERE lf2.factura_proveedor_id = fp.id
                  AND l2.estado NOT IN ('pagada', 'anulada')
            ) THEN 'total'
            ELSE 'parcial'
        END,
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE fp.id IN (
        SELECT factura_proveedor_id FROM doc.letra_factura WHERE letra_id = p_letra_id
    );

    GET DIAGNOSTICS v_facturas_count = ROW_COUNT;

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
-- vincular_guias_compra
-- Links one or more guias to an existing compra.
-- Validates each guia belongs to the compra's proveedor.
-- Idempotent: ON CONFLICT DO NOTHING.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.vincular_guias_compra(
    p_compra_id bigint,
    p_guia_ids  jsonb   -- [1, 2, 3]
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

    -- All guias must belong to the same tercero as the compra
    IF EXISTS (
        SELECT 1 FROM doc.guia_remision
        WHERE id IN (SELECT jsonb_array_elements_text(p_guia_ids)::bigint)
          AND tercero_id IS DISTINCT FROM v_proveedor
    ) THEN
        RAISE EXCEPTION 'Una o más guías no pertenecen al proveedor de la compra #%.', p_compra_id;
    END IF;

    INSERT INTO doc.compra_guia_remision(compra_id, guia_remision_id)
    SELECT p_compra_id, jsonb_array_elements_text(p_guia_ids)::bigint
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_linked = ROW_COUNT;

    RETURN format('%s guía(s) vinculada(s) a compra #%s.', v_linked, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in vincular_guias_compra - User: %, compra: %, Error: %', v_usr_id, p_compra_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- vincular_factura_compra
-- Links a factura_proveedor to a compra via the junction table.
-- Idempotent (ON CONFLICT DO NOTHING). Validates same proveedor.
-- A compra can be linked to multiple facturas (e.g. factura-en-0
-- + real invoice, or split shipments).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.vincular_factura_compra(
    p_compra_id  bigint,
    p_factura_id bigint,
    p_nota       text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_compra_prov  int;
    v_factura_prov int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT tercero_id INTO v_compra_prov
    FROM doc.compra WHERE id = p_compra_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    SELECT tercero_id INTO v_factura_prov
    FROM doc.factura_proveedor WHERE id = p_factura_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_id;
    END IF;

    IF v_compra_prov <> v_factura_prov THEN
        RAISE EXCEPTION 'Proveedor de compra (%) y factura (%) no coinciden.',
            v_compra_prov, v_factura_prov;
    END IF;

    INSERT INTO doc.compra_factura_proveedor (compra_id, factura_proveedor_id, nota, usr_cre)
    VALUES (p_compra_id, p_factura_id, p_nota, v_usr_id)
    ON CONFLICT DO NOTHING;

    RETURN format('Factura #% vinculada a compra #%.', p_factura_id, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in vincular_factura_compra - User: %, compra: %, factura: %, Error: %',
        v_usr_id, p_compra_id, p_factura_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- desvincular_factura_compra
-- Removes a specific compra ↔ factura link from the junction.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.desvincular_factura_compra(
    p_compra_id  bigint,
    p_factura_id bigint
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    DELETE FROM doc.compra_factura_proveedor
    WHERE compra_id = p_compra_id AND factura_proveedor_id = p_factura_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vínculo entre compra #% y factura #% no encontrado.', p_compra_id, p_factura_id;
    END IF;

    RETURN format('Factura #% desvinculada de compra #%.', p_factura_id, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in desvincular_factura_compra - User: %, compra: %, factura: %, Error: %',
        v_usr_id, p_compra_id, p_factura_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.vincular_factura_compra(bigint, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION doc.desvincular_factura_compra(bigint, bigint)    TO authenticated;

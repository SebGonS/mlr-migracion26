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
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_compra', v_usr_id, p_datos);

    -- Validate guias belong to the declared proveedor
    IF p_datos->'guia_ids' IS NOT NULL AND jsonb_array_length(p_datos->'guia_ids') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.guia_remision gr
            WHERE gr.id IN (
                SELECT jsonb_array_elements_text(p_datos->'guia_ids')::bigint
            )
            AND gr.emisor_proveedor_id IS DISTINCT FROM (p_datos->>'proveedor_id')::INT
        ) THEN
            RAISE EXCEPTION 'Una o más guías no pertenecen al proveedor indicado.';
        END IF;
    END IF;

    -- Insert header
    INSERT INTO doc.compra(proveedor_id, fecha, observacion, usr_cre)
    VALUES (
        (p_datos->>'proveedor_id')::INT,
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
        proveedor_id, serie, numero,
        fecha_emision, fecha_vencimiento,
        tipo_pago, moneda, tipo_cambio,
        subtotal, igv, total,
        observacion, usr_cre
    )
    VALUES (
        (p_datos->>'proveedor_id')::INT,
        p_datos->>'serie',
        (p_datos->>'numero')::INT,
        (p_datos->>'fecha_emision')::DATE,
        (p_datos->>'fecha_vencimiento')::DATE,
        COALESCE((p_datos->>'tipo_pago')::tipo_pago_enum, 'contado'),
        COALESCE(p_datos->>'moneda', 'USD'),
        (p_datos->>'tipo_cambio')::NUMERIC,
        (p_datos->>'subtotal')::NUMERIC,
        COALESCE((p_datos->>'igv')::NUMERIC, 0),
        (p_datos->>'total')::NUMERIC,
        p_datos->>'observacion',
        v_usr_id
    )
    RETURNING id INTO v_factura_id;

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
-- registrar_letras
-- Replaces pending letras for a factura with a new set.
-- Idempotent: calling again overwrites previous pending letras.
-- Validates sum of letras does not exceed factura total.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_letras(
    p_factura_proveedor_id bigint,
    p_letras jsonb          -- [{monto, fecha_vencimiento, fecha_giro?, banco?, numero?}]
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_total        numeric;
    v_total_letras numeric;
BEGIN
    SELECT total INTO v_total
    FROM doc.factura_proveedor
    WHERE id = p_factura_proveedor_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_proveedor_id;
    END IF;

    SELECT SUM((l->>'monto')::NUMERIC)
    INTO v_total_letras
    FROM jsonb_array_elements(p_letras) l;

    IF v_total_letras > v_total THEN
        RAISE EXCEPTION 'Monto total de letras (%) excede total de factura (%).',
            v_total_letras, v_total;
    END IF;

    -- Idempotent: wipe pending letras and rewrite
    DELETE FROM doc.letra
    WHERE factura_proveedor_id = p_factura_proveedor_id
      AND estado = 'pendiente';

    INSERT INTO doc.letra(
        factura_proveedor_id, numero, monto,
        fecha_giro, fecha_vencimiento, banco, usr_cre
    )
    SELECT
        p_factura_proveedor_id,
        l->>'numero',
        (l->>'monto')::NUMERIC,
        (l->>'fecha_giro')::DATE,
        (l->>'fecha_vencimiento')::DATE,
        l->>'banco',
        v_usr_id
    FROM jsonb_array_elements(p_letras) l;

    -- Mark factura as paid by letras
    UPDATE doc.factura_proveedor
    SET tipo_pago = 'letras', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_factura_proveedor_id;

    RETURN format('%s letras registradas para factura #%s.', jsonb_array_length(p_letras), p_factura_proveedor_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_letras - User: %, factura: %, Error: %', v_usr_id, p_factura_proveedor_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- pagar_letra
-- Marks a letra as paid. Cascades estado_pago to the factura:
--   all paid → 'pagado' | some paid → 'parcial'
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
    v_usr_id        int := get_user_id();
    v_factura_id    bigint;
    v_estado_actual letra_estado_enum;
    v_todas_pagadas boolean;
BEGIN
    SELECT factura_proveedor_id, estado
    INTO v_factura_id, v_estado_actual
    FROM doc.letra WHERE id = p_letra_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Letra #% no encontrada.', p_letra_id;
    END IF;
    IF v_estado_actual <> 'pendiente' THEN
        RAISE EXCEPTION 'La letra #% ya está en estado %. Solo se pueden pagar letras pendientes.',
            p_letra_id, v_estado_actual;
    END IF;

    UPDATE doc.letra
    SET estado     = 'pagada',
        fecha_pago = p_fecha_pago,
        usr_mod    = v_usr_id,
        fyh_mod    = NOW()
    WHERE id = p_letra_id;

    -- Cascade to factura estado_pago
    SELECT NOT EXISTS (
        SELECT 1 FROM doc.letra
        WHERE factura_proveedor_id = v_factura_id
          AND estado = 'pendiente'
    ) INTO v_todas_pagadas;

    UPDATE doc.factura_proveedor
    SET estado_pago = CASE WHEN v_todas_pagadas THEN 'pagado' ELSE 'parcial' END,
        usr_mod     = v_usr_id,
        fyh_mod     = NOW()
    WHERE id = v_factura_id;

    RETURN format('Letra #% pagada el %%.%s',
        p_letra_id,
        p_fecha_pago,
        CASE WHEN v_todas_pagadas
             THEN ' Factura #' || v_factura_id || ' totalmente pagada.'
             ELSE '' END
    );
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
    SELECT proveedor_id INTO v_proveedor
    FROM doc.compra WHERE id = p_compra_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    -- All guias must belong to the same proveedor as the compra
    IF EXISTS (
        SELECT 1 FROM doc.guia_remision
        WHERE id IN (SELECT jsonb_array_elements_text(p_guia_ids)::bigint)
          AND emisor_proveedor_id IS DISTINCT FROM v_proveedor
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
-- Links an existing factura_proveedor to an existing compra.
-- Validates both belong to the same proveedor.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.vincular_factura_compra(
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
    v_usr_id          int := get_user_id();
    v_compra_prov     int;
    v_factura_prov    int;
BEGIN
    SELECT proveedor_id INTO v_compra_prov
    FROM doc.compra WHERE id = p_compra_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    SELECT proveedor_id INTO v_factura_prov
    FROM doc.factura_proveedor WHERE id = p_factura_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura #% no encontrada.', p_factura_id;
    END IF;

    IF v_compra_prov <> v_factura_prov THEN
        RAISE EXCEPTION 'Proveedor de compra (%) y factura (%) no coinciden.',
            v_compra_prov, v_factura_prov;
    END IF;

    UPDATE doc.compra
    SET factura_proveedor_id = p_factura_id,
        usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_compra_id;

    RETURN format('Factura #% vinculada a compra #%.', p_factura_id, p_compra_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in vincular_factura_compra - User: %, compra: %, factura: %, Error: %',
        v_usr_id, p_compra_id, p_factura_id, v_message;
    RAISE;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- funciones/pagos_proveedor.sql — AP cash payments (Layer A)
-- The non-letra way to settle a supplier invoice, plus the shared
-- amount-based estado_pago recalculator used by both pagos and letras.
-- Re-runnable (CREATE OR REPLACE).
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────
-- doc.recalcular_estado_pago_factura_proveedor(p_factura_proveedor_id)
-- (INTERNAL) Amount-based settlement state of a supplier invoice.
-- Paid amount = PAID letras + non-anulado cash pagos applied to it.
--   (emitida/vencida letras are commitments, not payments — they show
--    as open balance in vw_cuentas_por_pagar but don't reduce estado_pago)
-- Replaces the old letra-state-only cascade that lived in pagar_letra.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.recalcular_estado_pago_factura_proveedor(p_factura_proveedor_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'doc'
AS $function$
DECLARE
    v_total       numeric;
    v_estado_pago estado_pago_enum;
    v_pagado      numeric;
BEGIN
    SELECT total, estado_pago INTO v_total, v_estado_pago
    FROM doc.factura_proveedor WHERE id = p_factura_proveedor_id FOR UPDATE;

    IF NOT FOUND THEN RETURN; END IF;
    IF v_estado_pago = 'anulado' THEN RETURN; END IF;   -- voided invoice is terminal

    SELECT
        COALESCE((
            SELECT SUM(lf.monto_aplicado)
            FROM doc.letra_factura lf
            JOIN doc.letra l ON l.id = lf.letra_id
            WHERE lf.factura_proveedor_id = p_factura_proveedor_id
              AND l.estado = 'pagada'
        ), 0)
      + COALESCE((
            SELECT SUM(pf.monto_aplicado)
            FROM doc.pago_proveedor_factura pf
            JOIN doc.pago_proveedor p ON p.id = pf.pago_id
            WHERE pf.factura_proveedor_id = p_factura_proveedor_id
              AND p.estado = 'registrado'
        ), 0)
    INTO v_pagado;

    UPDATE doc.factura_proveedor
    SET estado_pago = CASE
            WHEN v_pagado <= 0                THEN 'pendiente'
            WHEN v_pagado <  v_total - 0.005  THEN 'parcial'
            ELSE                                   'total'
        END,
        usr_mod = get_user_id(),
        fyh_mod = NOW()
    WHERE id = p_factura_proveedor_id;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- doc.registrar_pago_proveedor(p_datos jsonb)  →  bigint (pago_id)
-- p_datos: same shape as registrar_cobro but settles facturas de
-- proveedor. Posts a tesoreria EGRESO.
-- {
--   "tercero_id": INT, "fecha": DATE, "medio_pago": ...,
--   "cuenta_financiera_id": INT, "monto": NUMERIC, "moneda": CHAR,
--   "tipo_cambio": NUMERIC, "referencia": TEXT, "observacion": TEXT,
--   "facturas": [ { "factura_proveedor_id": INT, "monto_aplicado": NUMERIC }, ... ]
-- }
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_pago_proveedor(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'tesoreria'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int     := get_user_id();
    v_tercero_id      int     := (p_datos->>'tercero_id')::INT;
    v_monto           numeric := (p_datos->>'monto')::NUMERIC;
    v_cuenta_id       int     := (p_datos->>'cuenta_financiera_id')::INT;
    v_pago_id         bigint;
    v_total_aplicado  numeric;
    v_factura_rec     record;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_pago_proveedor', v_usr_id, p_datos);

    -- Linked facturas must belong to this supplier and be open
    IF p_datos ? 'facturas' AND jsonb_array_length(p_datos->'facturas') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.factura_proveedor fp
            WHERE fp.id IN (
                SELECT (x->>'factura_proveedor_id')::bigint
                FROM jsonb_array_elements(p_datos->'facturas') x
            )
            AND fp.tercero_id IS DISTINCT FROM v_tercero_id
        ) THEN
            RAISE EXCEPTION 'Una o más facturas no pertenecen al proveedor indicado (%).', v_tercero_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM doc.factura_proveedor fp
            WHERE fp.id IN (
                SELECT (x->>'factura_proveedor_id')::bigint
                FROM jsonb_array_elements(p_datos->'facturas') x
            )
            AND fp.estado_pago IN ('total', 'anulado')
        ) THEN
            RAISE EXCEPTION 'Una o más facturas ya están totalmente pagadas o anuladas.';
        END IF;
    END IF;

    SELECT COALESCE(SUM((x->>'monto_aplicado')::NUMERIC), 0)
    INTO v_total_aplicado
    FROM jsonb_array_elements(COALESCE(p_datos->'facturas', '[]'::jsonb)) x;

    IF v_total_aplicado > v_monto + 0.005 THEN
        RAISE EXCEPTION 'Monto aplicado total (%) excede el monto del pago (%).',
            v_total_aplicado, v_monto;
    END IF;

    INSERT INTO doc.pago_proveedor(
        tercero_id, fecha, medio_pago, cuenta_financiera_id,
        monto, moneda, tipo_cambio, referencia, observacion, usr_cre
    )
    VALUES (
        v_tercero_id,
        COALESCE((p_datos->>'fecha')::DATE, CURRENT_DATE),
        COALESCE((p_datos->>'medio_pago')::medio_pago_enum, 'TRANSFERENCIA'),
        v_cuenta_id,
        v_monto,
        COALESCE(p_datos->>'moneda', 'USD'),
        (p_datos->>'tipo_cambio')::NUMERIC,
        p_datos->>'referencia',
        p_datos->>'observacion',
        v_usr_id
    )
    RETURNING id INTO v_pago_id;

    IF p_datos ? 'facturas' AND jsonb_array_length(p_datos->'facturas') > 0 THEN
        INSERT INTO doc.pago_proveedor_factura(pago_id, factura_proveedor_id, monto_aplicado, usr_cre)
        SELECT v_pago_id, (x->>'factura_proveedor_id')::bigint, (x->>'monto_aplicado')::NUMERIC, v_usr_id
        FROM jsonb_array_elements(p_datos->'facturas') x;

        FOR v_factura_rec IN
            SELECT DISTINCT (x->>'factura_proveedor_id')::bigint AS fp_id
            FROM jsonb_array_elements(p_datos->'facturas') x
        LOOP
            PERFORM doc.recalcular_estado_pago_factura_proveedor(v_factura_rec.fp_id);
        END LOOP;
    END IF;

    PERFORM tesoreria.registrar_movimiento(
        p_cuenta_financiera_id := v_cuenta_id,
        p_tipo                 := 'EGRESO',
        p_monto                := v_monto,
        p_moneda               := COALESCE(p_datos->>'moneda', 'USD'),
        p_documento_tipo       := 'pago_proveedor',
        p_documento_id         := v_pago_id,
        p_fecha                := COALESCE((p_datos->>'fecha')::DATE, CURRENT_DATE),
        p_tipo_cambio          := (p_datos->>'tipo_cambio')::NUMERIC,
        p_medio_pago           := COALESCE((p_datos->>'medio_pago')::medio_pago_enum, 'TRANSFERENCIA'),
        p_referencia           := p_datos->>'referencia',
        p_glosa                := format('Pago #%s proveedor %s', v_pago_id, v_tercero_id)
    );

    RETURN v_pago_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_pago_proveedor - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- doc.anular_pago_proveedor(p_pago_id)  →  text
-- Soft-anula the payment, posts a reversing INGRESO, recomputes
-- estado_pago on every supplier invoice it had settled.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_pago_proveedor(p_pago_id bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'tesoreria'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id      int := get_user_id();
    v_pago        doc.pago_proveedor%ROWTYPE;
    v_factura_rec record;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_pago FROM doc.pago_proveedor WHERE id = p_pago_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pago #% no encontrado.', p_pago_id;
    END IF;
    IF v_pago.estado = 'anulado' THEN
        RAISE EXCEPTION 'Pago #% ya está anulado.', p_pago_id;
    END IF;

    UPDATE doc.pago_proveedor
    SET estado = 'anulado', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_pago_id;

    IF v_pago.cuenta_financiera_id IS NOT NULL THEN
        PERFORM tesoreria.registrar_movimiento(
            p_cuenta_financiera_id := v_pago.cuenta_financiera_id,
            p_tipo                 := 'INGRESO',
            p_monto                := v_pago.monto,
            p_moneda               := v_pago.moneda,
            p_documento_tipo       := 'pago_proveedor',
            p_documento_id         := p_pago_id,
            p_tipo_cambio          := v_pago.tipo_cambio,
            p_medio_pago           := v_pago.medio_pago,
            p_referencia           := v_pago.referencia,
            p_glosa                := format('Anulación pago #%s', p_pago_id)
        );
    END IF;

    FOR v_factura_rec IN
        SELECT factura_proveedor_id FROM doc.pago_proveedor_factura WHERE pago_id = p_pago_id
    LOOP
        PERFORM doc.recalcular_estado_pago_factura_proveedor(v_factura_rec.factura_proveedor_id);
    END LOOP;

    RETURN format('Pago #%s anulado.', p_pago_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_pago_proveedor - User: %, pago: %, Error: %', v_usr_id, p_pago_id, v_message;
    RAISE;
END;
$function$;

-- ── Grants / Revokes ───────────────────────────────────────────
GRANT EXECUTE ON FUNCTION doc.registrar_pago_proveedor(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION doc.anular_pago_proveedor(bigint)   TO authenticated;
-- Internal helper — invoked from pagar_letra and the pago functions only.
REVOKE ALL ON FUNCTION doc.recalcular_estado_pago_factura_proveedor(bigint) FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- funciones/cobranza.sql — Accounts Receivable (Layer A)
-- Customer collections against doc.factura. Mirrors the AP letra flow.
-- Re-runnable (CREATE OR REPLACE).
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────
-- doc.recalcular_estado_pago_factura(p_factura_id)  (INTERNAL)
-- Derives factura.estado_pago from the sum of non-anulado cobros.
--   anulada factura            → 'anulado'
--   applied = 0                → 'pendiente'
--   0 < applied < total        → 'parcial'
--   applied >= total           → 'total'
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.recalcular_estado_pago_factura(p_factura_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'doc'
AS $function$
DECLARE
    v_total    numeric;
    v_estado   factura_estado_enum;
    v_aplicado numeric;
BEGIN
    SELECT total, estado INTO v_total, v_estado
    FROM doc.factura WHERE id = p_factura_id FOR UPDATE;

    IF NOT FOUND THEN RETURN; END IF;

    IF v_estado = 'anulada' THEN
        UPDATE doc.factura SET estado_pago = 'anulado'
        WHERE id = p_factura_id AND estado_pago <> 'anulado';
        RETURN;
    END IF;

    SELECT COALESCE(SUM(cf.monto_aplicado), 0) INTO v_aplicado
    FROM doc.cobro_factura cf
    JOIN doc.cobro c ON c.id = cf.cobro_id
    WHERE cf.factura_id = p_factura_id
      AND c.estado = 'registrado';

    UPDATE doc.factura
    SET estado_pago = CASE
            WHEN v_aplicado <= 0                 THEN 'pendiente'
            WHEN v_aplicado <  v_total - 0.005   THEN 'parcial'
            ELSE                                      'total'
        END
    WHERE id = p_factura_id;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- doc.registrar_cobro(p_datos jsonb)  →  bigint (cobro_id)
-- p_datos:
-- {
--   "tercero_id": INT,
--   "fecha": "2026-06-15",
--   "medio_pago": "TRANSFERENCIA",
--   "cuenta_financiera_id": INT,        -- where the money landed
--   "monto": 1000.00,
--   "moneda": "USD",
--   "tipo_cambio": 3.75,
--   "referencia": "OP-12345",
--   "observacion": "...",
--   "facturas": [ { "factura_id": INT, "monto_aplicado": NUMERIC }, ... ]
-- }
-- Posts a tesoreria INGRESO and cascades estado_pago to each factura.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_cobro(p_datos jsonb)
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
    v_cobro_id        bigint;
    v_total_aplicado  numeric;
    v_factura_rec     record;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_cobro', v_usr_id, p_datos);

    -- Linked facturas must belong to this client and be issued & open
    IF p_datos ? 'facturas' AND jsonb_array_length(p_datos->'facturas') > 0 THEN
        IF EXISTS (
            SELECT 1 FROM doc.factura f
            WHERE f.id IN (
                SELECT (x->>'factura_id')::bigint
                FROM jsonb_array_elements(p_datos->'facturas') x
            )
            AND f.tercero_id IS DISTINCT FROM v_tercero_id
        ) THEN
            RAISE EXCEPTION 'Una o más facturas no pertenecen al cliente indicado (%).', v_tercero_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM doc.factura f
            WHERE f.id IN (
                SELECT (x->>'factura_id')::bigint
                FROM jsonb_array_elements(p_datos->'facturas') x
            )
            AND (f.estado <> 'emitida' OR f.estado_pago IN ('total', 'anulado'))
        ) THEN
            RAISE EXCEPTION 'Una o más facturas no están emitidas, o ya están totalmente cobradas/anuladas.';
        END IF;
    END IF;

    -- Sum of applications cannot exceed the cobro amount
    SELECT COALESCE(SUM((x->>'monto_aplicado')::NUMERIC), 0)
    INTO v_total_aplicado
    FROM jsonb_array_elements(COALESCE(p_datos->'facturas', '[]'::jsonb)) x;

    IF v_total_aplicado > v_monto + 0.005 THEN
        RAISE EXCEPTION 'Monto aplicado total (%) excede el monto del cobro (%).',
            v_total_aplicado, v_monto;
    END IF;

    -- Header
    INSERT INTO doc.cobro(
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
    RETURNING id INTO v_cobro_id;

    -- Apply to invoices + cascade estado_pago
    IF p_datos ? 'facturas' AND jsonb_array_length(p_datos->'facturas') > 0 THEN
        INSERT INTO doc.cobro_factura(cobro_id, factura_id, monto_aplicado, usr_cre)
        SELECT v_cobro_id, (x->>'factura_id')::bigint, (x->>'monto_aplicado')::NUMERIC, v_usr_id
        FROM jsonb_array_elements(p_datos->'facturas') x;

        FOR v_factura_rec IN
            SELECT DISTINCT (x->>'factura_id')::bigint AS factura_id
            FROM jsonb_array_elements(p_datos->'facturas') x
        LOOP
            PERFORM doc.recalcular_estado_pago_factura(v_factura_rec.factura_id);
        END LOOP;
    END IF;

    -- Cash ledger (INGRESO). No-op when no account routed.
    PERFORM tesoreria.registrar_movimiento(
        p_cuenta_financiera_id := v_cuenta_id,
        p_tipo                 := 'INGRESO',
        p_monto                := v_monto,
        p_moneda               := COALESCE(p_datos->>'moneda', 'USD'),
        p_documento_tipo       := 'cobro',
        p_documento_id         := v_cobro_id,
        p_fecha                := COALESCE((p_datos->>'fecha')::DATE, CURRENT_DATE),
        p_tipo_cambio          := (p_datos->>'tipo_cambio')::NUMERIC,
        p_medio_pago           := COALESCE((p_datos->>'medio_pago')::medio_pago_enum, 'TRANSFERENCIA'),
        p_referencia           := p_datos->>'referencia',
        p_glosa                := format('Cobro #%s cliente %s', v_cobro_id, v_tercero_id)
    );

    RETURN v_cobro_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_cobro - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- doc.anular_cobro(p_cobro_id)  →  text
-- Soft-anula the receipt, posts a reversing EGRESO, and recomputes
-- estado_pago on every factura it had touched (now that its applied
-- amount no longer counts).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_cobro(p_cobro_id bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'tesoreria'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id      int := get_user_id();
    v_cobro       doc.cobro%ROWTYPE;
    v_factura_rec record;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_cobro FROM doc.cobro WHERE id = p_cobro_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cobro #% no encontrado.', p_cobro_id;
    END IF;
    IF v_cobro.estado = 'anulado' THEN
        RAISE EXCEPTION 'Cobro #% ya está anulado.', p_cobro_id;
    END IF;

    UPDATE doc.cobro
    SET estado = 'anulado', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_cobro_id;

    -- Reverse the cash entry (counter-movement, ledger stays append-only)
    IF v_cobro.cuenta_financiera_id IS NOT NULL THEN
        PERFORM tesoreria.registrar_movimiento(
            p_cuenta_financiera_id := v_cobro.cuenta_financiera_id,
            p_tipo                 := 'EGRESO',
            p_monto                := v_cobro.monto,
            p_moneda               := v_cobro.moneda,
            p_documento_tipo       := 'cobro',
            p_documento_id         := p_cobro_id,
            p_tipo_cambio          := v_cobro.tipo_cambio,
            p_medio_pago           := v_cobro.medio_pago,
            p_referencia           := v_cobro.referencia,
            p_glosa                := format('Anulación cobro #%s', p_cobro_id)
        );
    END IF;

    -- Recompute estado_pago on every factura this cobro had applied to
    FOR v_factura_rec IN
        SELECT factura_id FROM doc.cobro_factura WHERE cobro_id = p_cobro_id
    LOOP
        PERFORM doc.recalcular_estado_pago_factura(v_factura_rec.factura_id);
    END LOOP;

    RETURN format('Cobro #%s anulado.', p_cobro_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_cobro - User: %, cobro: %, Error: %', v_usr_id, p_cobro_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- doc.get_cobro(p_cobro_id)  →  jsonb  (header + applied facturas)
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_cobro(p_cobro_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'tesoreria'
AS $function$
DECLARE
    v_result jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT jsonb_build_object(
        'id',                   c.id,
        'tercero_id',           c.tercero_id,
        'cliente_nombre',       t.nombre,
        'fecha',                c.fecha,
        'medio_pago',           c.medio_pago,
        'cuenta_financiera_id', c.cuenta_financiera_id,
        'cuenta_nombre',        cf.nombre,
        'monto',                c.monto,
        'moneda',               c.moneda,
        'tipo_cambio',          c.tipo_cambio,
        'referencia',           c.referencia,
        'observacion',          c.observacion,
        'estado',               c.estado,
        'facturas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'factura_id',     cofa.factura_id,
                'factura_numero', f.serie || '-' || f.numero::text,
                'monto_aplicado', cofa.monto_aplicado,
                'estado_pago',    f.estado_pago
            ))
            FROM doc.cobro_factura cofa
            JOIN doc.factura f ON f.id = cofa.factura_id
            WHERE cofa.cobro_id = c.id
        ), '[]'::jsonb)
    )
    INTO v_result
    FROM doc.cobro c
    JOIN tercero t ON t.id = c.tercero_id
    LEFT JOIN tesoreria.cuenta_financiera cf ON cf.id = c.cuenta_financiera_id
    WHERE c.id = p_cobro_id;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Cobro #% no encontrado.', p_cobro_id;
    END IF;

    RETURN v_result;
END;
$function$;

-- ── Grants / Revokes ───────────────────────────────────────────
GRANT EXECUTE ON FUNCTION doc.registrar_cobro(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION doc.anular_cobro(bigint)   TO authenticated;
GRANT EXECUTE ON FUNCTION doc.get_cobro(bigint)      TO authenticated;
-- Internal helper — invoked only from SECURITY DEFINER callers.
REVOKE ALL ON FUNCTION doc.recalcular_estado_pago_factura(bigint) FROM PUBLIC, anon, authenticated;

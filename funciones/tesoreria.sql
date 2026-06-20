-- ═══════════════════════════════════════════════════════════════
-- funciones/tesoreria.sql — cash & bank (Layer A)
-- Account catalog + the internal movimiento ledger writer.
-- Re-runnable (CREATE OR REPLACE).
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────
-- tesoreria.registrar_movimiento  (INTERNAL — no permission gate)
-- The single writer for the cash ledger. Called only by other
-- SECURITY DEFINER functions (registrar_cobro, pagar_letra, …).
-- Returns the new movimiento.id.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tesoreria.registrar_movimiento(
    p_cuenta_financiera_id INT,
    p_tipo                  tesoreria_mov_tipo_enum,
    p_monto                 NUMERIC,
    p_moneda                CHAR,
    p_documento_tipo        TEXT,
    p_documento_id          BIGINT,
    p_fecha                 DATE            DEFAULT CURRENT_DATE,
    p_tipo_cambio           NUMERIC         DEFAULT NULL,
    p_medio_pago            medio_pago_enum DEFAULT NULL,
    p_referencia            TEXT            DEFAULT NULL,
    p_glosa                 TEXT            DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'tesoreria'
AS $function$
DECLARE
    v_mov_id bigint;
BEGIN
    IF p_cuenta_financiera_id IS NULL THEN
        RETURN NULL;   -- nothing to post (e.g. payment not yet routed to an account)
    END IF;

    INSERT INTO tesoreria.movimiento(
        cuenta_financiera_id, tipo, fecha, monto, moneda, tipo_cambio,
        medio_pago, referencia, documento_tipo, documento_id, glosa
    )
    VALUES (
        p_cuenta_financiera_id, p_tipo, COALESCE(p_fecha, CURRENT_DATE),
        p_monto, p_moneda, p_tipo_cambio,
        p_medio_pago, p_referencia, p_documento_tipo, p_documento_id, p_glosa
    )
    RETURNING id INTO v_mov_id;

    RETURN v_mov_id;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- tesoreria.crear_cuenta_financiera(p_datos jsonb)
-- p_datos: { codigo, nombre, tipo, moneda, banco?, numero_cuenta?, cci? }
-- Returns the new cuenta_financiera.id.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tesoreria.crear_cuenta_financiera(p_datos jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'tesoreria'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id  int := get_user_id();
    v_id      int;
BEGIN
    IF NOT jwt_has_permission('configuracion.operacional') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.operacional'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_cuenta_financiera', v_usr_id, p_datos);

    INSERT INTO tesoreria.cuenta_financiera(
        codigo, nombre, tipo, moneda, banco, numero_cuenta, cci, usr_cre
    )
    VALUES (
        p_datos->>'codigo',
        p_datos->>'nombre',
        (p_datos->>'tipo')::tesoreria_cuenta_tipo_enum,
        p_datos->>'moneda',
        p_datos->>'banco',
        p_datos->>'numero_cuenta',
        p_datos->>'cci',
        v_usr_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in crear_cuenta_financiera - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- tesoreria.actualizar_cuenta_financiera(p_id, p_datos jsonb)
-- Editable: nombre, banco, numero_cuenta, cci, flg_activo.
-- codigo/tipo/moneda are immutable once set (re-create instead).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tesoreria.actualizar_cuenta_financiera(
    p_id    INT,
    p_datos jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'tesoreria'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.operacional') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.operacional'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE tesoreria.cuenta_financiera
    SET nombre        = COALESCE(p_datos->>'nombre', nombre),
        banco         = COALESCE(p_datos->>'banco', banco),
        numero_cuenta = COALESCE(p_datos->>'numero_cuenta', numero_cuenta),
        cci           = COALESCE(p_datos->>'cci', cci),
        flg_activo    = COALESCE((p_datos->>'flg_activo')::boolean, flg_activo),
        usr_mod       = v_usr_id,
        fyh_mod       = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuenta financiera #% no encontrada.', p_id;
    END IF;

    RETURN format('Cuenta financiera #%s actualizada.', p_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_cuenta_financiera - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ── Grants / Revokes ───────────────────────────────────────────
GRANT EXECUTE ON FUNCTION tesoreria.crear_cuenta_financiera(jsonb)          TO authenticated;
GRANT EXECUTE ON FUNCTION tesoreria.actualizar_cuenta_financiera(int, jsonb) TO authenticated;
-- Internal ledger writer — only SECURITY DEFINER callers may post to it.
REVOKE ALL ON FUNCTION tesoreria.registrar_movimiento(
    int, tesoreria_mov_tipo_enum, numeric, character, text, bigint,
    date, numeric, medio_pago_enum, text, text
) FROM PUBLIC, anon, authenticated;

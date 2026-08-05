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

    -- Replace line items only when 'detalle' key is explicitly present.
    -- Diffed by item_id (frontend sends the full grid, no line ids) so that
    -- lines which persist keep their compra_detalle.id — and therefore keep
    -- entrega_detalle.compra_detalle_id (LIPS→EKPO) intact — instead of being
    -- dropped and recreated.
    IF p_datos ? 'detalle' THEN
        -- A line can only be removed if no *active* entrega is linked to it.
        -- entrega_detalle rows are never deleted (audit trail), so an
        -- anulada entrega must not keep blocking the line forever.
        IF EXISTS (
            SELECT 1
            FROM doc.compra_detalle cd
            WHERE cd.compra_id = p_compra_id
              AND NOT EXISTS (
                  SELECT 1 FROM jsonb_array_elements(p_datos->'detalle') d
                  WHERE (d->>'item_id')::INT = cd.item_id
              )
              AND EXISTS (
                  SELECT 1
                  FROM doc.entrega_detalle ed
                  JOIN doc.entrega e ON e.id = ed.entrega_id
                  WHERE ed.compra_detalle_id = cd.id
                    AND e.fyh_elm IS NULL
              )
        ) THEN
            RAISE EXCEPTION 'No se puede eliminar una línea con entregas ya vinculadas. Desvincule la entrega correspondiente primero.';
        END IF;

        -- Update lines that persist (same item_id) in place.
        UPDATE doc.compra_detalle cd
        SET cantidad        = (d->>'cantidad')::NUMERIC,
            precio_unitario = (d->>'precio_unitario')::NUMERIC
        FROM jsonb_array_elements(p_datos->'detalle') d
        WHERE cd.compra_id = p_compra_id
          AND cd.item_id = (d->>'item_id')::INT;

        -- Insert lines for newly added items.
        INSERT INTO doc.compra_detalle (compra_id, item_id, cantidad, precio_unitario, usr_cre)
        SELECT p_compra_id,
               (d->>'item_id')::INT,
               (d->>'cantidad')::NUMERIC,
               (d->>'precio_unitario')::NUMERIC,
               v_usr_id
        FROM jsonb_array_elements(p_datos->'detalle') d
        WHERE NOT EXISTS (
            SELECT 1 FROM doc.compra_detalle cd
            WHERE cd.compra_id = p_compra_id AND cd.item_id = (d->>'item_id')::INT
        );

        -- Clear stale EKPO links from anulada entregas before deleting — the guard
        -- above only allows the delete through when no *active* entrega remains,
        -- but the FK itself has no ON DELETE clause and would otherwise RESTRICT.
        UPDATE doc.entrega_detalle ed
        SET compra_detalle_id = NULL
        FROM doc.compra_detalle cd, doc.entrega e
        WHERE e.id = ed.entrega_id
          AND ed.compra_detalle_id = cd.id
          AND cd.compra_id = p_compra_id
          AND e.fyh_elm IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM jsonb_array_elements(p_datos->'detalle') d
              WHERE (d->>'item_id')::INT = cd.item_id
          );

        -- Delete lines the user removed (already confirmed above to be unlinked).
        DELETE FROM doc.compra_detalle cd
        WHERE cd.compra_id = p_compra_id
          AND NOT EXISTS (
              SELECT 1 FROM jsonb_array_elements(p_datos->'detalle') d
              WHERE (d->>'item_id')::INT = cd.item_id
          );
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
    -- Recomputes cantidad_recibida from item_movimientos (ground truth).
    -- All COMPRA_ING movements are anchored to an entrega (even when the
    -- entrega is headless). Line match: compra_detalle_id when pinned,
    -- item_id fallback for single-compra deliveries.
    -- DEV_PROV_EGR movements posted by doc.anular_entrega (reversing a
    -- COMPRA_INGRESO) share the same documento_id as the original entrega,
    -- so they're netted out here. A standalone devolución a proveedor
    -- entrega is never compra_entrega-linked, so it can't leak in.
    UPDATE doc.compra_detalle cd
    SET cantidad_recibida = COALESCE((
        SELECT SUM(im.cantidad * CASE imt.codigo WHEN 'COMPRA_ING' THEN 1 ELSE -1 END)
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE imt.codigo IN ('COMPRA_ING', 'DEV_PROV_EGR')
          AND im.item_id = cd.item_id
          AND im.documento_tipo = 'entrega'
          AND im.documento_id IN (
              SELECT ed.entrega_id
              FROM doc.entrega_detalle ed
              JOIN doc.compra_entrega ce ON ce.entrega_id = ed.entrega_id
              WHERE ce.compra_id = p_compra_id
                AND (ed.compra_detalle_id = cd.id
                     OR (ed.compra_detalle_id IS NULL AND ed.item_id = cd.item_id))
          )
    ), 0)
    WHERE cd.compra_id = p_compra_id;
$$;

-- vincular_entregas_compra replaced by reconciliar_entrega_compra
DROP FUNCTION IF EXISTS doc.vincular_entregas_compra(bigint, jsonb);

-- ───────────────────────────────────────────────────────────────
-- reconciliar_entrega_compra
-- Links a standalone entrega (guia that arrived without a PO) to
-- an existing compra, resolving line-item matching down to
-- entrega_detalle.compra_detalle_id.
--
-- p_datos shape:
-- {
--   "entrega_id": 123,
--   "compra_id":  456,
--   "lineas": [                        -- optional explicit mapping
--     { "entrega_detalle_id": 1, "compra_detalle_id": 2 }
--   ]
-- }
--
-- When "lineas" is absent, auto-matches each entrega_detalle line
-- to the first compra_detalle row with the same item_id.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.reconciliar_entrega_compra(p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message       text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int    := get_user_id();
    v_entrega_id    bigint := (p_datos->>'entrega_id')::bigint;
    v_compra_id     bigint := (p_datos->>'compra_id')::bigint;
    v_entrega_tercero int;
    v_compra_tercero  int;
    v_tipo          text;
    v_linea         jsonb;
    v_matched       int := 0;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('reconciliar_entrega_compra', v_usr_id, p_datos);

    -- Validate entrega
    SELECT et.codigo, e.tercero_id
    INTO v_tipo, v_entrega_tercero
    FROM doc.entrega e
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
    WHERE e.id = v_entrega_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Entrega #% no encontrada.', v_entrega_id;
    END IF;
    IF v_tipo <> 'COMPRA_INGRESO' THEN
        RAISE EXCEPTION 'Entrega #% no es de tipo COMPRA_INGRESO.', v_entrega_id;
    END IF;

    -- Validate compra
    SELECT tercero_id INTO v_compra_tercero
    FROM doc.compra WHERE id = v_compra_id AND fyh_elm IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra #% no encontrada o anulada.', v_compra_id;
    END IF;

    -- Same supplier
    IF v_entrega_tercero IS DISTINCT FROM v_compra_tercero THEN
        RAISE EXCEPTION 'La entrega #% pertenece a un proveedor distinto a la compra #%.',
            v_entrega_id, v_compra_id;
    END IF;

    -- Header link (idempotent)
    INSERT INTO doc.compra_entrega(compra_id, entrega_id)
    VALUES (v_compra_id, v_entrega_id)
    ON CONFLICT DO NOTHING;

    IF p_datos ? 'lineas' AND jsonb_array_length(p_datos->'lineas') > 0 THEN
        -- Explicit line mapping
        FOR v_linea IN SELECT jsonb_array_elements(p_datos->'lineas') LOOP
            UPDATE doc.entrega_detalle
            SET compra_detalle_id = (v_linea->>'compra_detalle_id')::bigint
            WHERE id = (v_linea->>'entrega_detalle_id')::bigint
              AND entrega_id = v_entrega_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'entrega_detalle #% no pertenece a entrega #%.',
                    v_linea->>'entrega_detalle_id', v_entrega_id;
            END IF;
            v_matched := v_matched + 1;
        END LOOP;
    ELSE
        -- Auto-match by item_id
        UPDATE doc.entrega_detalle ed
        SET compra_detalle_id = (
            SELECT cd.id
            FROM doc.compra_detalle cd
            WHERE cd.compra_id = v_compra_id
              AND cd.item_id   = ed.item_id
            ORDER BY cd.id
            LIMIT 1
        )
        WHERE ed.entrega_id = v_entrega_id;

        GET DIAGNOSTICS v_matched = ROW_COUNT;

        -- Warn if any line couldn't be matched
        IF EXISTS (
            SELECT 1 FROM doc.entrega_detalle
            WHERE entrega_id = v_entrega_id AND compra_detalle_id IS NULL
        ) THEN
            RAISE WARNING 'Algunas líneas de entrega #% no tienen ítem equivalente en compra #%. Revise con lineas explícitas.',
                v_entrega_id, v_compra_id;
        END IF;
    END IF;

    PERFORM doc.fn_refresh_compra_detalle_qtys(v_compra_id);

    RETURN format('Entrega #%s reconciliada con compra #%s (%s línea(s) mapeada(s)).',
                  v_entrega_id, v_compra_id, v_matched);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in reconciliar_entrega_compra - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$function$;

-- ───────────────────────────────────────────────────────────────
-- desvincular_entregas_compra
-- Removes one or more entrega links from a compra.
-- Also clears the compra_detalle_id on affected entrega_detalle
-- lines so they no longer count toward any PO receipt.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.desvincular_entregas_compra(
    p_compra_id   bigint,
    p_entrega_ids jsonb   -- [1, 2, 3]
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

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('desvincular_entregas_compra', v_usr_id,
            jsonb_build_object('compra_id', p_compra_id, 'entrega_ids', p_entrega_ids));

    IF NOT EXISTS (SELECT 1 FROM doc.compra WHERE id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra #% no encontrada.', p_compra_id;
    END IF;

    -- Clear line-level PO references on entrega_detalle lines
    UPDATE doc.entrega_detalle
    SET compra_detalle_id = NULL
    WHERE entrega_id IN (SELECT jsonb_array_elements_text(p_entrega_ids)::bigint)
      AND compra_detalle_id IN (
          SELECT id FROM doc.compra_detalle WHERE compra_id = p_compra_id
      );

    -- Remove header link
    DELETE FROM doc.compra_entrega
    WHERE compra_id = p_compra_id
      AND entrega_id IN (SELECT jsonb_array_elements_text(p_entrega_ids)::bigint);

    GET DIAGNOSTICS v_unlinked = ROW_COUNT;

    PERFORM doc.fn_refresh_compra_detalle_qtys(p_compra_id);

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
GRANT EXECUTE ON FUNCTION doc.reconciliar_entrega_compra(jsonb)               TO authenticated;
GRANT EXECUTE ON FUNCTION doc.desvincular_entregas_compra(bigint, jsonb)       TO authenticated;
GRANT EXECUTE ON FUNCTION doc.vincular_facturas_compra(bigint, jsonb)       TO authenticated;
GRANT EXECUTE ON FUNCTION doc.desvincular_facturas_compra(bigint, jsonb)    TO authenticated;
GRANT EXECUTE ON FUNCTION doc.marcar_compra_recibida(bigint)                TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- registrar_compra_completa
-- One-shot: compra + entrega + stock + factura in a single transaction.
-- Designed for the majority flow where supplier delivers everything at once
-- with a matching guía and factura.
--
-- All three documents are optional independently:
--   • guia absent   → stock posts against compra only (no browsable delivery)
--   • factura absent → compra + stock registered, invoice entered separately
--   • both present  → full one-shot (most common)
--
-- p_datos shape:
-- {
--   "tercero_id":   45,
--   "fecha":        "2026-06-25",     -- compra date; defaults to today
--   "observacion":  "...",
--   "ubicacion_id": 5,                -- stock destination; defaults to ALM_CRU
--   "guia": {                         -- optional
--     "serie":       "T001",
--     "correlativo": "00001285",
--     "fecha":       "2026-06-25"
--   },
--   "factura": {                      -- optional
--     "serie":            "F001",
--     "numero":           "00001234",
--     "fecha_emision":    "2026-06-25",
--     "fecha_vencimiento":"2026-07-25",
--     "subtotal":         1000.00,
--     "igv":              180.00,
--     "total":            1180.00,
--     "moneda":           "USD",
--     "tipo_cambio":      3.75,
--     "tipo_pago":        "al contado"
--   },
--   "items": [
--     { "item_id": 71,  "cantidad": 25, "precio_unitario": 15.00, "n_rollos": 2 },
--     { "item_id": 196, "cantidad": 30, "precio_unitario": 12.50 }
--   ]
-- }
--
-- Returns: { "compra_id": N, "entrega_id": N|null, "factura_id": N|null }
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_compra_completa(p_datos jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'inventario', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     int    := get_user_id();
    v_tercero_id int    := (p_datos->>'tercero_id')::int;
    v_compra_id  bigint;
    v_entrega_id bigint;
    v_factura_id bigint;
    v_elem       jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_compra_completa', v_usr_id, p_datos);

    IF v_tercero_id IS NULL THEN
        RAISE EXCEPTION 'tercero_id es requerido.';
    END IF;

    -- ── 1. Compra (PO) ───────────────────────────────────────────
    INSERT INTO doc.compra (tercero_id, fecha, observacion, usr_cre)
    VALUES (v_tercero_id,
            COALESCE((p_datos->>'fecha')::DATE, CURRENT_DATE),
            p_datos->>'observacion',
            v_usr_id)
    RETURNING id INTO v_compra_id;

    INSERT INTO doc.compra_detalle (compra_id, item_id, cantidad, precio_unitario, usr_cre)
    SELECT v_compra_id,
           (item->>'item_id')::int,
           (item->>'cantidad')::numeric,
           (item->>'precio_unitario')::numeric,
           v_usr_id
    FROM jsonb_array_elements(p_datos->'items') item;

    -- ── 2. Entrega + stock ───────────────────────────────────────
    -- Always creates an entrega (headless when no guia) and posts stock.
    SELECT doc.registrar_entrega_compra(jsonb_build_object(
        'compra_id',    v_compra_id,
        'serie',        NULLIF(p_datos->'guia'->>'serie', ''),
        'correlativo',  NULLIF(p_datos->'guia'->>'correlativo', ''),
        'fecha',        COALESCE(p_datos->'guia'->>'fecha', p_datos->>'fecha'),
        'ubicacion_id', p_datos->>'ubicacion_id',
        'items', (
            SELECT jsonb_agg(jsonb_build_object(
                'item_id',  item->>'item_id',
                'cantidad', item->>'cantidad',
                'n_rollos', item->>'n_rollos'
            ))
            FROM jsonb_array_elements(p_datos->'items') item
        )
    )) INTO v_entrega_id;

    -- ── 3. Factura proveedor ─────────────────────────────────────
    IF p_datos ? 'factura' AND (p_datos->'factura'->>'numero') IS NOT NULL THEN
        SELECT doc.registrar_factura_proveedor(
            p_datos->'factura'
            || jsonb_build_object(
                'tercero_id', v_tercero_id,
                'compra_id',  v_compra_id,
                'lineas', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'item_id',        item->>'item_id',
                        'cantidad',       item->>'cantidad',
                        'precio_unitario',item->>'precio_unitario'
                    ))
                    FROM jsonb_array_elements(p_datos->'items') item
                )
            )
        ) INTO v_factura_id;
    END IF;

    RETURN jsonb_build_object(
        'compra_id',  v_compra_id,
        'entrega_id', v_entrega_id,
        'factura_id', v_factura_id
    );

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
        v_hint    = PG_EXCEPTION_HINT, v_context = PG_EXCEPTION_CONTEXT,
        v_sqlstate = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'registrar_compra_completa: % | detail: % | hint: % | context: % | state: %',
        v_message, v_detail, v_hint, v_context, v_sqlstate;
END;
$$;

-- ───────────────────────────────────────────────────────────────
-- registrar_entrega_compra
-- Primary reception RPC. Always creates an entrega + posts stock.
-- compra_id is optional: omit for orderless receipt (guia arrives
-- before PO). Link to a PO later via reconciliar_entrega_compra.
-- serie/correlativo are optional: omit for headless receipt (stock
-- arrives before the guia paper). Backfill via actualizar_referencia_entrega.
--
-- p_datos shape:
-- {
--   "compra_id":    123,         -- optional
--   "tercero_id":   45,          -- required when no compra_id
--   "serie":        "T001",      -- optional
--   "correlativo":  "00001285",  -- optional
--   "fecha":        "2026-06-20",-- optional, defaults to now()
--   "ubicacion_id": 5,           -- optional, defaults to ALM_CRU
--   "items": [
--     { "item_id": 71,  "cantidad": 25, "compra_detalle_id": 445 },
--     { "item_id": 196, "cantidad": 25, "n_rollos": 2 }
--   ]
-- }
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_entrega_compra(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'inventario', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int      := get_user_id();
    v_compra_id       bigint   := (p_datos->>'compra_id')::bigint;
    v_entrega_id      bigint;
    v_entrega_tipo_id smallint;
    v_tercero_id      int;
    v_ubicacion_id    int;
    v_fecha_mov       timestamptz;
    v_doc_mov_id      bigint;
    v_mov_tipo_id     smallint;
    v_elem            jsonb;
    v_item_id         int;
    v_cantidad        numeric;
    v_n_rollos        int;
    v_detalle_id      bigint;   -- entrega_detalle.id  (LIPS line)
    v_compra_det_id   bigint;   -- compra_detalle.id   (EKPO link)
    v_lote_id         int;
    v_linea           smallint := 0;
    v_flg_rollo       boolean;
    v_flg_rib         boolean;
    v_prorate         boolean;
    v_peso_rollo      numeric;
    i                 int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_entrega_compra', v_usr_id, p_datos);

    SELECT id INTO STRICT v_entrega_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'COMPRA_INGRESO';

    IF v_compra_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM doc.compra WHERE id = v_compra_id AND fyh_elm IS NULL) THEN
            RAISE EXCEPTION 'Compra #% no existe o fue anulada.', v_compra_id;
        END IF;
        SELECT tercero_id INTO v_tercero_id FROM doc.compra WHERE id = v_compra_id;
    ELSE
        v_tercero_id := (p_datos->>'tercero_id')::int;
        IF v_tercero_id IS NULL THEN
            RAISE EXCEPTION 'tercero_id requerido cuando no se especifica compra_id.';
        END IF;
    END IF;

    v_fecha_mov := COALESCE((p_datos->>'fecha')::timestamptz, now());

    INSERT INTO doc.entrega (entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (v_entrega_tipo_id, v_tercero_id, p_datos->>'serie', p_datos->>'correlativo',
            v_fecha_mov, v_fecha_mov)
    RETURNING id INTO v_entrega_id;

    -- Stock always posts via entrega — resolve movement infra before item loop
    v_doc_mov_id := nextval('inventario.mov_doc_seq');
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

    IF v_compra_id IS NOT NULL THEN
        INSERT INTO doc.compra_entrega (compra_id, entrega_id)
        VALUES (v_compra_id, v_entrega_id)
        ON CONFLICT DO NOTHING;
    END IF;

    FOR v_elem IN SELECT jsonb_array_elements(p_datos->'items') LOOP
        v_item_id       := (v_elem->>'item_id')::int;
        v_cantidad      := (v_elem->>'cantidad')::numeric;
        v_n_rollos      := (v_elem->>'n_rollos')::int;
        v_linea         := v_linea + 1;

        -- Resolve EKPO link: explicit from payload, or auto-match by item_id
        v_compra_det_id := (v_elem->>'compra_detalle_id')::bigint;
        IF v_compra_det_id IS NULL AND v_compra_id IS NOT NULL THEN
            SELECT id INTO v_compra_det_id
            FROM doc.compra_detalle
            WHERE compra_id = v_compra_id AND item_id = v_item_id
            ORDER BY id LIMIT 1;
        END IF;

        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, n_rollos, compra_detalle_id)
        VALUES (v_entrega_id, v_linea, v_item_id, v_cantidad, v_n_rollos, v_compra_det_id)
        RETURNING id INTO v_detalle_id;

        SELECT EXISTS (
            SELECT 1 FROM item i
            JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
            WHERE i.id = v_item_id
        ) INTO v_flg_rollo;

        IF v_flg_rollo AND v_n_rollos IS NOT NULL THEN
            v_prorate    := COALESCE((v_elem->>'prorate')::boolean, true);
            v_peso_rollo := CASE WHEN v_prorate THEN v_cantidad / v_n_rollos ELSE v_cantidad END;

            SELECT COALESCE(flg_rib, false) INTO v_flg_rib
            FROM item_rollo_detalle WHERE item_id = v_item_id;

            FOR i IN 1 .. v_n_rollos LOOP
                INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
                VALUES (v_item_id, 'entrega', v_entrega_id, v_peso_rollo, NULL, v_usr_id)
                RETURNING id INTO v_lote_id;

                INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id, flg_tenido)
                VALUES (v_lote_id, v_entrega_id, false);

                INSERT INTO inventario.item_movimientos (
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    destino_ubicacion_id, cantidad, fecha_hora,
                    documento_tipo, documento_id, documento_linea_id, usr_cre
                ) VALUES (
                    v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                    v_ubicacion_id, v_peso_rollo, v_fecha_mov,
                    'entrega', v_entrega_id, v_detalle_id, v_usr_id
                );
            END LOOP;

        ELSE
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
            VALUES (v_item_id, 'entrega', v_entrega_id, v_cantidad, NULL, v_usr_id)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                destino_ubicacion_id, cantidad, fecha_hora,
                documento_tipo, documento_id, documento_linea_id, usr_cre
            ) VALUES (
                v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                v_ubicacion_id, v_cantidad, v_fecha_mov,
                'entrega', v_entrega_id, v_detalle_id, v_usr_id
            );
        END IF;

    END LOOP;

    -- Sync PO receipt counter when linked to a compra
    IF v_compra_id IS NOT NULL THEN
        PERFORM doc.fn_refresh_compra_detalle_qtys(v_compra_id);
    END IF;

    -- Notify warehouse roles
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Ingreso de compra',
           COALESCE((SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id = v_usr_id), 'sistema')
               || CASE WHEN v_compra_id IS NOT NULL
                        THEN ' ingresó stock contra compra #' || v_compra_id
                        ELSE ' registró entrega sin compra asociada'
                  END,
           'info',
           jsonb_build_object(
               'objeto_tipo',    'entrega',
               'entrega_id',     v_entrega_id,
               'compra_id',      v_compra_id,
               'doc_movimiento_id', v_doc_mov_id
           )
    FROM iam.user_rol ur
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras', 'inventario')
      AND v_usr_id <> ur.user_id;

    RETURN v_entrega_id;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
        v_hint    = PG_EXCEPTION_HINT, v_context = PG_EXCEPTION_CONTEXT,
        v_sqlstate = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'registrar_entrega_compra: % | detail: % | hint: % | context: % | state: %',
        v_message, v_detail, v_hint, v_context, v_sqlstate;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.registrar_entrega_compra(jsonb)               TO authenticated;
GRANT EXECUTE ON FUNCTION doc.registrar_compra_completa(jsonb)              TO authenticated;

-- ───────────────────────────────────────────────────────────────
-- registrar_muestra_ingreso
-- Reception of a free supplier sample (muestra gratuita). Posts a
-- MUESTRA_ING movement — non-valorizable (flg_valorizable=false), so
-- inventario.fn_trg_actualizar_map skips it: physical stock rises but
-- the moving-average cost (MAP) is NOT touched. This is the correct
-- behaviour for a zero-cost item:
--   • A zero-priced COMPRA_ING (recalc) would DRAG the MAP down.
--   • An AJUSTE_POS would value the sample at current MAP — fabricating
--     inventory value on something received for free, and losing the
--     supplier provenance.
-- MUESTRA_ING does neither: no cost distortion, full provenance via the
-- MUESTRA_INGRESO entrega (tercero + optional remito serie/correlativo).
-- Never links to doc.compra.
--
-- p_datos shape:
-- {
--   "tercero_id":   45,           -- required: who sent the sample
--   "serie":        "REM",        -- optional: sample remito serie
--   "correlativo":  "000123",     -- optional: sample remito number
--   "fecha":        "2026-07-16", -- optional, defaults to now()
--   "ubicacion_id": 5,            -- optional, defaults to ALM_CRU
--   "observacion":  "Muestra …",  -- optional, stamped on each movement
--   "items": [
--     { "item_id": 71,  "cantidad": 15 },              -- insumo (typical)
--     { "item_id": 196, "cantidad": 4, "n_rollos": 1 } -- rollo (rare)
--   ]
-- }
-- ───────────────────────────────────────────────────────────────
-- SELECT * FROM item WHERE nombre ILIKE '%remazol%';
-- SELECT * FROM inventario.ubicacion JOIN inventario.almacen A ON A.id = almacen_id WHERE A.codigo = 'ALM_CRU';
-- SELECT doc.registrar_muestra_ingreso(jsonb_build_object(
--     'tercero_id', 275,
--     'serie', 'EC',
--     'correlativo', '20013',
--     'fecha', '2026-07-16',
--     'ubicacion_id', 7,
--     'observacion', 'Muestra de prueba',
--     'items', jsonb_build_array(
--         jsonb_build_object('item_id', 328, 'cantidad', 25)    )
-- ));
CREATE OR REPLACE FUNCTION doc.registrar_muestra_ingreso(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'inventario', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int      := get_user_id();
    v_entrega_id      bigint;
    v_entrega_tipo_id smallint;
    v_tercero_id      int;
    v_ubicacion_id    int;
    v_fecha_mov       timestamptz;
    v_observacion     text;
    v_doc_mov_id      bigint;
    v_mov_tipo_id     smallint;
    v_elem            jsonb;
    v_item_id         int;
    v_cantidad        numeric;
    v_n_rollos        int;
    v_detalle_id      bigint;
    v_lote_id         int;
    v_linea           smallint := 0;
    v_flg_rollo       boolean;
    v_prorate         boolean;
    v_peso_rollo      numeric;
    i                 int;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_muestra_ingreso', v_usr_id, p_datos);

    v_tercero_id := (p_datos->>'tercero_id')::int;
    IF v_tercero_id IS NULL THEN
        RAISE EXCEPTION 'tercero_id requerido: la muestra debe registrar su procedencia.';
    END IF;

    SELECT id INTO STRICT v_entrega_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'MUESTRA_INGRESO';

    SELECT id INTO STRICT v_mov_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'MUESTRA_ING';

    v_fecha_mov   := COALESCE((p_datos->>'fecha')::timestamptz, now());
    v_observacion := p_datos->>'observacion';

    INSERT INTO doc.entrega (entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (v_entrega_tipo_id, v_tercero_id, p_datos->>'serie', p_datos->>'correlativo',
            v_fecha_mov, v_fecha_mov)
    RETURNING id INTO v_entrega_id;

    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    IF (p_datos->>'ubicacion_id') IS NOT NULL THEN
        v_ubicacion_id := (p_datos->>'ubicacion_id')::int;
    ELSE
        SELECT ub.id INTO STRICT v_ubicacion_id
        FROM inventario.ubicacion ub
        JOIN inventario.almacen alm ON alm.id = ub.almacen_id
        WHERE alm.codigo = 'ALM_CRU' LIMIT 1;
    END IF;

    FOR v_elem IN SELECT jsonb_array_elements(p_datos->'items') LOOP
        v_item_id  := (v_elem->>'item_id')::int;
        v_cantidad := (v_elem->>'cantidad')::numeric;
        v_n_rollos := (v_elem->>'n_rollos')::int;
        v_linea    := v_linea + 1;

        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, n_rollos)
        VALUES (v_entrega_id, v_linea, v_item_id, v_cantidad, v_n_rollos)
        RETURNING id INTO v_detalle_id;

        SELECT EXISTS (
            SELECT 1 FROM item i
            JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
            WHERE i.id = v_item_id
        ) INTO v_flg_rollo;

        IF v_flg_rollo AND v_n_rollos IS NOT NULL THEN
            v_prorate    := COALESCE((v_elem->>'prorate')::boolean, true);
            v_peso_rollo := CASE WHEN v_prorate THEN v_cantidad / v_n_rollos ELSE v_cantidad END;

            FOR i IN 1 .. v_n_rollos LOOP
                INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
                VALUES (v_item_id, 'entrega', v_entrega_id, v_peso_rollo, NULL, v_usr_id)
                RETURNING id INTO v_lote_id;

                INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id, flg_tenido)
                VALUES (v_lote_id, v_entrega_id, false);

                INSERT INTO inventario.item_movimientos (
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    destino_ubicacion_id, cantidad, fecha_hora,
                    documento_tipo, documento_id, documento_linea_id, observacion, usr_cre
                ) VALUES (
                    v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                    v_ubicacion_id, v_peso_rollo, v_fecha_mov,
                    'entrega', v_entrega_id, v_detalle_id, v_observacion, v_usr_id
                );
            END LOOP;

        ELSE
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
            VALUES (v_item_id, 'entrega', v_entrega_id, v_cantidad, NULL, v_usr_id)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                destino_ubicacion_id, cantidad, fecha_hora,
                documento_tipo, documento_id, documento_linea_id, observacion, usr_cre
            ) VALUES (
                v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                v_ubicacion_id, v_cantidad, v_fecha_mov,
                'entrega', v_entrega_id, v_detalle_id, v_observacion, v_usr_id
            );
        END IF;

    END LOOP;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Ingreso de muestra',
           COALESCE((SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id = v_usr_id), 'sistema')
               || ' registró una muestra sin costo (no valorizada).',
           'info',
           jsonb_build_object(
               'objeto_tipo',       'entrega',
               'entrega_id',        v_entrega_id,
               'doc_movimiento_id', v_doc_mov_id
           )
    FROM iam.user_rol ur
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras', 'inventario')
      AND v_usr_id <> ur.user_id;

    RETURN v_entrega_id;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
        v_hint    = PG_EXCEPTION_HINT, v_context = PG_EXCEPTION_CONTEXT,
        v_sqlstate = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'registrar_muestra_ingreso: % | detail: % | hint: % | context: % | state: %',
        v_message, v_detail, v_hint, v_context, v_sqlstate;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.registrar_muestra_ingreso(jsonb)              TO authenticated;

-- ───────────────────────────────────────────────────────────────
-- actualizar_referencia_entrega
-- Backfills the physical guia reference (serie + correlativo + fecha)
-- on an existing headless entrega.  The entrega must be of type
-- COMPRA_INGRESO and must not already have a reference set.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.actualizar_referencia_entrega(
    p_entrega_id  bigint,
    p_serie       text,
    p_correlativo text,
    p_fecha       date DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id   int := get_user_id();
    v_tipo     text;
    v_existing text;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_referencia_entrega', v_usr_id,
            jsonb_build_object('entrega_id', p_entrega_id,
                               'serie', p_serie, 'correlativo', p_correlativo));

    SELECT et.codigo, e.correlativo
    INTO v_tipo, v_existing
    FROM doc.entrega e
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
    WHERE e.id = p_entrega_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Entrega #% no encontrada.', p_entrega_id;
    END IF;
    IF v_tipo <> 'COMPRA_INGRESO' THEN
        RAISE EXCEPTION 'Entrega #% no es de tipo COMPRA_INGRESO (es %).', p_entrega_id, v_tipo;
    END IF;
    IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'Entrega #% ya tiene referencia (%). Use otra función para correcciones contables.', p_entrega_id, v_existing;
    END IF;
    IF p_correlativo IS NULL OR p_correlativo = '' THEN
        RAISE EXCEPTION 'correlativo es requerido.';
    END IF;

    UPDATE doc.entrega
    SET serie          = NULLIF(p_serie, ''),
        correlativo    = p_correlativo,
        fecha_emision  = COALESCE(p_fecha::timestamptz, fecha_emision)
    WHERE id = p_entrega_id;

    RETURN format('Entrega #%s actualizada con referencia %s-%s.',
                  p_entrega_id, p_serie, p_correlativo);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_referencia_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.actualizar_referencia_entrega(bigint, text, text, date) TO authenticated;

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

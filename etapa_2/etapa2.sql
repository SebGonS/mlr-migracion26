
-- ═══════════════════════════════════════════════════════════════
-- COMPRA FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION doc.crear_compra(p_compra jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_compra_id INT;
    v_usr_id int := get_user_id();
BEGIN
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_compra', v_usr_id, p_compra);

    INSERT INTO compra (proveedor_id, fecha_remision, usr_cre, fyh_cre)
    VALUES (
        (p_compra->>'proveedor_id')::INT,
        (p_compra->>'fecha_remision')::TIMESTAMPTZ,
        v_usr_id,
        now()
    )
    RETURNING id INTO v_compra_id;

    INSERT INTO doc.compra_detalle(compra_id, item_id, cantidad, precio_unitario)
    SELECT v_compra_id,
           (d->>'item_id')::INT,
           (d->>'cantidad')::NUMERIC(12,2),
           (d->>'precio_unitario')::NUMERIC(12,4)
    FROM jsonb_array_elements(p_compra->'compra_detalles') AS d;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Nueva Compra Creada',
           COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario = v_usr_id), 'sistema')
               || ' registró una nueva compra',
           'info',
           jsonb_build_object('objeto_tipo','compra','compra_id', v_compra_id)
    FROM iam.user_rol ur
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','compras','inventario')
      AND v_usr_id <> ur.user_id;

    RETURN format('Compra con ID %s creada correctamente.', v_compra_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in crear_compra - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_compra::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


CREATE OR REPLACE FUNCTION doc.actualizar_compra(p_compra_id INT, p_compra jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_usr_id    int := get_user_id();
    v_has_guias boolean;
BEGIN
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_compra', v_usr_id, jsonb_build_object('compra_id', p_compra_id, 'compra', p_compra));

    -- Guard: compra must exist
    IF NOT EXISTS (SELECT 1 FROM compra WHERE id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra con ID % no existe', p_compra_id;
    END IF;

    -- Guard: cannot edit if guias are already linked
    SELECT EXISTS(SELECT 1 FROM doc.compra_guia_remision WHERE compra_id = p_compra_id)
    INTO v_has_guias;

    IF v_has_guias THEN
        RAISE EXCEPTION 'No se puede modificar la compra %, ya tiene guías de remisión asociadas', p_compra_id;
    END IF;

    -- Update header
    UPDATE compra SET
        proveedor_id   = COALESCE((p_compra->>'proveedor_id')::INT, proveedor_id),
        fecha_remision = COALESCE((p_compra->>'fecha_remision')::TIMESTAMPTZ, fecha_remision),
        usr_mod        = v_usr_id,
        fyh_mod        = now()
    WHERE id = p_compra_id;

    -- Replace details: delete old, insert new
    DELETE FROM doc.compra_detalle WHERE compra_id = p_compra_id;

    INSERT INTO doc.compra_detalle(compra_id, item_id, cantidad, precio_unitario)
    SELECT p_compra_id,
           (d->>'item_id')::INT,
           (d->>'cantidad')::NUMERIC(12,2),
           (d->>'precio_unitario')::NUMERIC(12,4)
    FROM jsonb_array_elements(p_compra->'compra_detalles') AS d;

    RETURN format('Compra con ID %s actualizada correctamente.', p_compra_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in actualizar_compra - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_compra::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


CREATE OR REPLACE FUNCTION doc.eliminar_compra(p_compra_id INT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_usr_id    int := get_user_id();
    v_has_guias boolean;
BEGIN
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('eliminar_compra', v_usr_id, jsonb_build_object('compra_id', p_compra_id));

    -- Guard: compra must exist
    IF NOT EXISTS (SELECT 1 FROM compra WHERE id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra con ID % no existe', p_compra_id;
    END IF;

    -- Guard: cannot delete if guias are already linked
    SELECT EXISTS(SELECT 1 FROM doc.compra_guia_remision WHERE compra_id = p_compra_id)
    INTO v_has_guias;

    IF v_has_guias THEN
        RAISE EXCEPTION 'No se puede eliminar la compra %, ya tiene guías de remisión asociadas', p_compra_id;
    END IF;

    DELETE FROM doc.compra_detalle WHERE compra_id = p_compra_id;
    DELETE FROM compra WHERE id = p_compra_id;

    RETURN format('Compra con ID %s eliminada correctamente.', p_compra_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in eliminar_compra - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_compra_id::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


CREATE OR REPLACE FUNCTION doc.get_compra(p_compra_id INT)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path TO 'public', 'doc'
AS $$
SELECT jsonb_build_object(
    'id', c.id,
    'proveedor_id', c.proveedor_id,
    'fecha_remision', c.fecha_remision,
    'fyh_cre', c.fyh_cre,
    'usr_cre', c.usr_cre,
    'compra_detalles', (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', cd.id,
                'item_id', cd.item_id,
                'item_nombre', i.nombre,
                'item_codigo', i.codigo,
                'cantidad', cd.cantidad,
                'precio_unitario', cd.precio_unitario,
                'subtotal', cd.cantidad * cd.precio_unitario
            ) ORDER BY cd.id
        ), '[]'::jsonb)
        FROM doc.compra_detalle cd
        JOIN item i ON i.id = cd.item_id
        WHERE cd.compra_id = c.id
    ),
    'guias_remision', (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'guia_remision_id', gr.id,
                'serie', gr.serie,
                'correlativo', gr.correlativo,
                'fecha_emision', gr.fecha_emision,
                'fecha_recepcion', gr.fecha_recepcion
            ) ORDER BY gr.fecha_recepcion
        ), '[]'::jsonb)
        FROM doc.compra_guia_remision cgr
        JOIN doc.guia_remision gr ON gr.id = cgr.guia_remision_id
        WHERE cgr.compra_id = c.id
    )
)
FROM compra c
WHERE c.id = p_compra_id;
$$;

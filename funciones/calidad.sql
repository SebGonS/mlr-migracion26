CREATE OR REPLACE FUNCTION calidad.crear_inspeccion(p_inspeccion jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','calidad','inventario','mes'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_inspeccion_id BIGINT;
    v_usr_id int := get_user_id();
BEGIN
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_inspeccion', v_usr_id, p_inspeccion);

    -- Parent: inspeccion
    INSERT INTO calidad.inspeccion (lote_id, orden_produccion_paso_id, resultado, observacion, empleado_id)
    VALUES (
        (p_inspeccion->>'lote_id')::INT,
        (p_inspeccion->>'orden_produccion_paso_id')::BIGINT,
        (p_inspeccion->>'resultado')::calidad_estado_enum,
        p_inspeccion->>'observacion',
        (p_inspeccion->>'empleado_id')::INT
    )
    RETURNING id INTO v_inspeccion_id;

    -- Children: defectos + fotos (fotos nested inside each defecto in the JSON)
    WITH defectos_inserted AS (
        INSERT INTO calidad.inspeccion_defecto (inspeccion_id, tipo_defecto_id, cantidad, observacion)
        SELECT v_inspeccion_id,
               (d.value->>'tipo_defecto_id')::SMALLINT,
               COALESCE((d.value->>'cantidad')::SMALLINT, 1),
               d.value->>'observacion'
        FROM jsonb_array_elements(p_inspeccion->'defectos') WITH ORDINALITY AS d(value, ordinality)
        ORDER BY d.ordinality
        RETURNING id
    ),
    defectos_mapped AS (
        SELECT id, ROW_NUMBER() OVER () AS idx
        FROM defectos_inserted
    )
    INSERT INTO calidad.inspeccion_foto (inspeccion_defecto_id, ruta_archivo, etiqueta, observacion)
    SELECT dm.id,
           f->>'ruta_archivo',
           f->>'etiqueta',
           f->>'observacion'
    FROM jsonb_array_elements(p_inspeccion->'defectos') WITH ORDINALITY AS d(value, ordinality)
    JOIN defectos_mapped dm ON dm.idx = d.ordinality
    CROSS JOIN LATERAL jsonb_array_elements(d.value->'fotos') AS f;

    -- Update lote quality status
    UPDATE inventario.lote
    SET estado_calidad = (p_inspeccion->>'resultado')::calidad_estado_enum
    WHERE id = (p_inspeccion->>'lote_id')::INT;

    -- Notification
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Nueva Inspección de Calidad',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
             || ' registró una inspección con resultado '
             || (p_inspeccion->>'resultado'),
           'info',
           jsonb_build_object('objeto_tipo','inspeccion','inspeccion_id', v_inspeccion_id)
    FROM iam.user_rol ur
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','calidad') AND v_usr_id <> ur.user_id;

       RETURN jsonb_build_object(
        'inspeccion_id', v_inspeccion_id,
        'defecto_ids', (
            SELECT jsonb_agg(id ORDER BY id)
            FROM calidad.inspeccion_defecto
            WHERE inspeccion_id = v_inspeccion_id
        ),
        'message', format('Inspección %s creada', v_inspeccion_id)
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in crear_inspeccion - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_inspeccion::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


CREATE OR REPLACE FUNCTION calidad.get_inspeccion(p_inspeccion_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','calidad','inventario','mes'
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', i.id,
        'lote_id', i.lote_id,
        'orden_produccion_paso_id', i.orden_produccion_paso_id,
        'resultado', i.resultado,
        'observacion', i.observacion,
        'empleado_id', i.empleado_id,
        'empleado', e.nombre,
        'fyh_inspeccion', i.fyh_inspeccion,
        'fyh_cre', i.fyh_cre,

        'defectos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', id2.id,
                'tipo_defecto_id', id2.tipo_defecto_id,
                'tipo_defecto_codigo', td.codigo,
                'tipo_defecto_nombre', td.nombre,
                'severidad', td.severidad,
                'cantidad', id2.cantidad,
                'observacion', id2.observacion,
                'fotos', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', f.id,
                        'ruta_archivo', f.ruta_archivo,
                        'etiqueta', f.etiqueta,
                        'observacion', f.observacion
                    ) ORDER BY f.id)
                    FROM calidad.inspeccion_foto f
                    WHERE f.inspeccion_defecto_id = id2.id
                ), '[]'::jsonb)
            ) ORDER BY td.severidad DESC, id2.id)
            FROM calidad.inspeccion_defecto id2
            JOIN calidad.tipo_defecto td ON td.id = id2.tipo_defecto_id
            WHERE id2.inspeccion_id = i.id
        ), '[]'::jsonb)
    )
    INTO v_result
    FROM calidad.inspeccion i
    LEFT JOIN mes.empleado e ON e.id = i.empleado_id
    WHERE i.id = p_inspeccion_id;

    RETURN v_result;
END;
$function$;

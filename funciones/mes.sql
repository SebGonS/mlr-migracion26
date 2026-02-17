-- ═══════════════════════════════════════════════════════════════
-- 29. GET PROGRAMACION POR FECHA (daily board)
-- ═══════════════════════════════════════════════════════════════


CREATE OR REPLACE FUNCTION mes.get_programacion_diaria(p_fecha DATE)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes','inventario'
AS $$
SELECT COALESCE(jsonb_agg(row_obj), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'id',                 prog.id,
        'maquina_id',         prog.maquina_id,
        'secuencia',          prog.secuencia,
        'nota',               prog.nota,
        'paso_id',            opp.id,
        'operacion',          o.nombre,
        'operacion_codigo',   o.codigo,  -- ADD
        'paso_estado',        opp.estado,
        'orden_id',           op.id,
        'orden_tipo',         op.tipo,   -- ADD (assuming this field exists)
        'partida_id',         op.partida_id,
        'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'cliente',            c.cliente,
        'color',              vc.color,
        'color_hex',          vc.color_hex,
        'tono',               vc.tono,   -- ADD (if in your view)
        'tenido',             t.tenido,  -- ADD (if applicable),
        'ancho',              p.ancho,
        'malla',              p.malla,
        'rendimiento',        p.rendimiento,
        'articulo',           vpa.articulo_nombre,
        'fibra',              vpa.fibra,
        'total_rollos',       vpa.total_rollos,
        'cantidad_total',     vpa.cantidad_total,
        'cantidad_regular',   vpa.cantidad_regular,
        'cantidad_rib',       vpa.cantidad_rib
    ) AS row_obj
    FROM mes.programacion prog
    JOIN mes.orden_produccion_paso opp ON opp.id = prog.orden_produccion_paso_id
    JOIN mes.operacion o ON o.id = opp.operacion_id
    JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
    JOIN doc.partida p ON p.id = op.partida_id
    LEFT JOIN tenido t ON t.id = p.tenido_id
    LEFT JOIN cliente c ON c.id = p.cliente_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN partida_resumen_tenido vpa ON vpa.partida_id=p.id
    WHERE prog.fecha = p_fecha
    ORDER BY prog.maquina_id,prog.secuencia
) sub;
$$;

CREATE OR REPLACE FUNCTION mes.get_pasos_sin_programar()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes'
AS $$
SELECT COALESCE(jsonb_agg(row_obj), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'paso_id',            opp.id,
        'orden_id',           op.id,
        'operacion',          o.nombre,
        'operacion_codigo',   o.codigo,
        'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'cliente',            c.cliente,
        'color',              vc.color,
        'color_hex',          vc.color_hex,
        'tono',               vc.tono,
        'tenido',             t.tenido  -- ADD (if applicable)
    ) AS row_obj
    FROM mes.orden_produccion_paso opp
    JOIN mes.operacion o ON o.id = opp.operacion_id
    JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
    JOIN doc.partida p ON p.id = op.partida_id
    LEFT JOIN tenido t ON t.id = p.tenido_id
    LEFT JOIN cliente c ON c.id = p.cliente_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE opp.estado = 'PENDIENTE'
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog 
          WHERE prog.orden_produccion_paso_id = opp.id
      )
    ORDER BY p.fyh_cre DESC
) sub;
$$;



-- ═══════════════════════════════════════════════════════════════
-- GUARDAR PROGRAMACION - Full replace for date range or machine
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.guardar_programacion(
    p_fecha DATE,
    p_programaciones JSONB  -- Full schedule: [{"orden_produccion_paso_id": 1, "maquina_id": 5, "secuencia": 1, "nota": ""}, ...]
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes'
AS $function$
DECLARE
    v_usr_id INT := get_user_id();
    v_paso RECORD;
    v_invalid_pasos JSONB := '[]';
    v_deleted INT;
    v_inserted INT;
BEGIN
    -- 1. VALIDATE paso states  //Convertir a select into para no usar bucles
    SELECT jsonb_agg(
        jsonb_build_object(
            'paso_id', opp.id,
            'estado', opp.estado
        )
    )
    INTO v_invalid_pasos
    FROM jsonb_array_elements(p_programaciones) elem
    JOIN mes.orden_produccion_paso opp
      ON opp.id = (elem->>'orden_produccion_paso_id')::BIGINT
    WHERE opp.estado IN ('COMPLETADO', 'OMITIDO');

    IF v_invalid_pasos IS NOT NULL THEN
        RAISE EXCEPTION 'Pasos no programables: %', v_invalid_pasos;
    END IF;


DELETE FROM mes.programacion
    WHERE fecha = p_fecha;

 INSERT INTO mes.programacion (
        orden_produccion_paso_id,
        maquina_id,
        fecha,
        secuencia,
        nota
    )
    SELECT
        (elem->>'orden_produccion_paso_id')::BIGINT,
        (elem->>'maquina_id')::INT,
        p_fecha,
        (elem->>'secuencia')::SMALLINT,
        elem->>'nota'
    FROM jsonb_array_elements(p_programaciones) elem;

    -- 4. Sync maquina_asignada_id on pasos
    UPDATE mes.orden_produccion_paso opp
    SET maquina_asignada_id = (elem->>'maquina_id')::INT
    FROM jsonb_array_elements(p_programaciones) AS elem
    WHERE opp.id = (elem->>'orden_produccion_paso_id')::BIGINT;

    RETURN 'Programación guardada correctamente para ' || p_fecha;
END;
$function$;



/* Frontend Flow

┌─────────────────────────────────────────────────────────────┐
│  TABLERO PROGRAMACION - 2026-02-06                          │
├──────────────┬──────────────┬──────────────┬───────────────┤
│  MAQUINA 1   │  MAQUINA 2   │  MAQUINA 3   │ SIN ASIGNAR   │
├──────────────┼──────────────┼──────────────┼───────────────┤
│ ┌──────────┐ │ ┌──────────┐ │              │ ┌───────────┐ │
│ │ Paso #12 │ │ │ Paso #45 │ │              │ │ Paso #78  │ │
│ │ seq: 1   │ │ │ seq: 1   │ │              │ │ PENDIENTE │ │
│ └──────────┘ │ └──────────┘ │              │ └───────────┘ │
│ ┌──────────┐ │ ┌──────────┐ │              │ ┌───────────┐ │
│ │ Paso #14 │ │ │ Paso #50 │ │              │ │ Paso #80  │ │
│ │ seq: 2   │ │ │ seq: 2   │ │              │ │ PENDIENTE │ │
│ └──────────┘ │ └──────────┘ │              │ └───────────┘ │
└──────────────┴──────────────┴──────────────┴───────────────┘
                              [ GUARDAR ]
On save, frontend sends:


{
  "fecha": "2026-02-06",
  "programaciones": [
    {"orden_produccion_paso_id": 12, "maquina_id": 1, "secuencia": 1, "nota": null},
    {"orden_produccion_paso_id": 14, "maquina_id": 1, "secuencia": 2, "nota": null},
    {"orden_produccion_paso_id": 45, "maquina_id": 2, "secuencia": 1, "nota": null},
    {"orden_produccion_paso_id": 50, "maquina_id": 2, "secuencia": 2, "nota": null}
  ]
}
Items dragged to "SIN ASIGNAR" are simply not included → deleted on save.

Why Single Function?
Separate Functions	Single Bulk Function
Multiple API calls	One API call on save
Race conditions possible	Atomic transaction
Complex frontend state sync	Frontend is source of truth
Need optimistic updates	Simple: save = replace
Want me to add this to your funciones.sql?*/


CREATE OR REPLACE FUNCTION mes.generar_receta(p_paso_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes','doc'
AS $function$
DECLARE
    v_receta        jsonb;
    v_receta_id     int;
    v_maquina_id    int;
    v_maq_nombre    text;
    v_maq_codigo    text;
    v_adjustment    numeric;
    v_rb            numeric;
    v_peso          numeric;
    v_cantidad      numeric;
    v_cantidad_regular numeric;
    v_cantidad_rib  numeric;
    v_volumen       numeric;
    v_usr_id        int := get_user_id();
    v_orden_id      bigint;
    v_op_nombre     text;
    v_message       text;
    v_detail        text;
    v_hint          text;
    v_context       text;
    v_sqlstate      text;
BEGIN
    -- 1. Validate paso, get receta + machine + relacion_bano
    SELECT opp.receta_id, opp.maquina_asignada_id, COALESCE(opp.relacion_bano,m.relacion_bano),
           opp.orden_produccion_id, o.nombre
    INTO v_receta_id, v_maquina_id, v_rb, v_orden_id, v_op_nombre
    FROM mes.orden_produccion_paso opp
    LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
    LEFT JOIN mes.maquina m ON m.id = opp.maquina_asignada_id
    WHERE opp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;

    IF v_receta_id IS NULL THEN
        RAISE EXCEPTION 'Paso ID % sin receta encontrada.', p_paso_id;
    END IF;

    -- 2. Machine info
    SELECT m.nombre, m.codigo
    INTO v_maq_nombre, v_maq_codigo
    FROM mes.maquina m
    WHERE m.id = v_maquina_id;
    -- 3. Roll aggregation
    SELECT SUM(l.cantidad), SUM(CASE ird.flg_rib WHEN false THEN 1 ELSE 0 END) cantidad_regular, SUM(CASE ird.flg_rib WHEN true THEN 1 ELSE 0 END) cantidad_rib
    INTO v_peso, v_cantidad_regular, v_cantidad_rib
    FROM mes.orden_produccion_paso_item oppi
    JOIN mes.orden_produccion_item opi ON oppi.orden_produccion_item_id = opi.id
    JOIN inventario.lote l ON opi.lote_id=l.id
    JOIN item_rollo_detalle ird ON ird.item_id=l.item_id
    WHERE oppi.orden_produccion_paso_id = p_paso_id;

    v_cantidad:= v_cantidad_regular + v_cantidad_rib;

    -- 4. Volumen
    v_volumen := CASE
        WHEN v_maq_nombre != 'BRAZOLI (1)' AND v_cantidad <= 12 THEN v_peso * 7
        ELSE v_peso * v_rb
    END;

    -- 5. Build JSON
    SELECT jsonb_build_object(
        'receta_id', opp.receta_id,
        'partida_id', p.id,
        'cliente_id', p.cliente_id,
        'cliente', cli.cliente,
        'orden_produccion_id', op.id,
        'tipo_receta', tr.tipo_receta,
        'tipo_articulo_id', r.tipo_articulo_id,
        'tipo_articulo', a.tipo_articulo,
        'peso', v_peso,
        'cantidad', v_cantidad,
        'cantidad_regular', v_cantidad_regular,
        'cantidad_rib', v_cantidad_rib,
        'volumen', ROUND(v_volumen::NUMERIC, 2),
        'maquina', jsonb_build_object(
            'id', v_maquina_id,
            'codigo', v_maq_codigo,
            'nombre', v_maq_nombre
        ),
        'pasos', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'orden', rp.orden,
                    'paso_id', rp.paso_id,
                    'paso', pa.paso
                ) ORDER BY rp.orden
            )
            FROM receta_x_paso rp
            JOIN paso pa ON rp.paso_id = pa.id
            WHERE rp.receta_id = r.id
        ),
        'insumos', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'insumo_id', i.id,
                    'orden', ri.orden,
                    'codigo', i.codigo,
                    'insumo', i.nombre,
                    'cantidad', ri.cantidad,
                    'medida', iid.medida,
                    'cantidad_requerida_kg', CASE
                        WHEN iid.medida = 'g/L' THEN ri.cantidad  * v_volumen
                        WHEN iid.medida = '%'   THEN ri.cantidad  * v_peso * 10
                    END
                )
            )
            FROM receta_x_insumo ri
            JOIN item i ON ri.insumo_id = i.legacy_id
            JOIN item_insumo_detalle iid ON iid.item_id=i.id
            WHERE ri.receta_id = r.id
        )
    ) INTO v_receta
    FROM orden_produccion_paso opp
    LEFT JOIN receta2 r ON r.id = opp.receta_id
    LEFT JOIN orden_produccion op ON op.id = opp.orden_produccion_id
    LEFT JOIN doc.partida p ON p.id = op.partida_id
    LEFT JOIN tipo_receta tr ON tr.id = r.tipo_receta_id
    LEFT JOIN tipo_articulo a ON a.id = r.tipo_articulo_id
    LEFT JOIN cliente cli ON cli.id = p.cliente_id
    WHERE opp.id = p_paso_id;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Receta Generada',
           COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name
                     FROM profiles WHERE id_usuario = v_usr_id), 'sistema')
           || format(' generó la receta del paso %s (orden #%s)', v_op_nombre, v_orden_id), 'info',
           jsonb_build_object('objeto_tipo','orden_produccion_paso','paso_id', p_paso_id, 'orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','supervisor_produccion') AND v_usr_id <> ur.user_id;

    RETURN v_receta;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in generar_receta - User: %, ID: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- 21. INICIAR PASO
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.iniciar_paso(p_paso_id BIGINT, p_datos jsonb DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_estado       orden_produccion_paso_estado_enum;
    v_orden_id     bigint;
    v_op_nombre    text;
    v_secuencia      smallint;
BEGIN
    SELECT opp.estado, opp.orden_produccion_id, o.nombre, opp.secuencia
    INTO v_estado, v_orden_id, v_op_nombre, v_secuencia
    FROM mes.orden_produccion_paso opp
    LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
    WHERE opp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;
    IF v_estado <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'Solo se puede iniciar un paso en estado PENDIENTE. Estado actual: %', v_estado;
    END IF;
    IF EXISTS (SELECT 1 FROM mes.orden_produccion_paso WHERE secuencia < v_secuencia AND orden_produccion_id=v_orden_id AND estado NOT IN ('COMPLETADO','OMITIDO')) THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque hay pasos anteriores no completados.', v_op_nombre;
    END IF;

    UPDATE mes.orden_produccion_paso
    SET estado      = 'EN_PROCESO',
        fyh_inicio  = NOW(),
        empleado_id = COALESCE((p_datos->>'empleado_id')::SMALLINT, empleado_id),
        maquina_asignada_id = COALESCE((p_datos->>'maquina_asignada_id')::INT, maquina_asignada_id)
    WHERE id = p_paso_id;

    -- Auto-start the parent orden if still CREADA/PLANIFICADA/PROGRAMADA/LIBERADA
    UPDATE mes.orden_produccion
    SET estado = 'EN_PROCESO', fyh_inicio = COALESCE(fyh_inicio, NOW())
    WHERE id = v_orden_id AND estado IN ('CREADA','PLANIFICADA','PROGRAMADA','LIBERADA');

    -- Update machine state
    IF (p_datos->>'maquina_asignada_id') IS NOT NULL THEN
        UPDATE mes.maquina SET estado_actual = 'activa'
        WHERE id = (p_datos->>'maquina_asignada_id')::INT;
    END IF;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Paso Iniciado',
           COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name
                     FROM profiles WHERE id_usuario = v_usr_id), 'sistema')
           || format(' inició el paso %s (orden #%s)', v_op_nombre, v_orden_id), 'info',
           jsonb_build_object('objeto_tipo','orden_produccion_paso','paso_id', p_paso_id, 'orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','supervisor_produccion') AND v_usr_id <> ur.user_id;

    RETURN format('Paso %s (#%s) iniciado correctamente.', v_op_nombre, p_paso_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in iniciar_paso - User: %, ID: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- 23. REGISTRAR CONSUMO EN PASO (chemicals/auxiliaries)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_consumo_paso(p_paso_id BIGINT, p_consumos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_consumos   jsonb;
    v_saldo     numeric;
    v_egr_tipo_id smallint;
    v_error_payload jsonb;
BEGIN
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_consumo_paso', v_usr_id, jsonb_build_object('paso_id', p_paso_id, 'consumos', p_consumos));

    SELECT id INTO v_egr_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

    WITH consumos AS (
    SELECT
        (i->>'item_id')::int AS item_id,
        SUM((i->>'cantidad')::numeric) AS cantidad
    FROM jsonb_array_elements(p_consumos) i
    GROUP BY 1
),
errores AS (
    SELECT
        c.item_id,
        it.nombre AS item_nombre,
        c.cantidad,
        COALESCE(SUM(sa.cantidad_disponible), 0) AS cantidad_disponible
    FROM consumos c
    LEFT JOIN inventario.vw_stock_actual sa
        ON sa.item_id = c.item_id
    JOIN item it
        ON it.id = c.item_id
    GROUP BY c.item_id, it.nombre, c.cantidad
    HAVING COALESCE(SUM(sa.cantidad_disponible), 0) < c.cantidad
)
SELECT jsonb_agg(
    jsonb_build_object(
        'item_id', item_id,
        'item_nombre', item_nombre,
        'saldo_disponible', cantidad_disponible,
        'cantidad_requerida', cantidad
    )
)
INTO v_error_payload
FROM errores;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION
            'Stock insuficiente para emitir la guía'
            USING
                DETAIL  = v_error_payload::text;
    END IF;

v_consumos:= mes.calcular_fifo(p_consumos);
        INSERT INTO inventario.item_movimientos(
            item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad,
            documento_tipo, documento_id, observacion
        ) SELECT 
            (v_consumo->>'item_id')::INT,
            (v_consumo->>'lote_id')::INT,
            v_egr_tipo_id,
            (v_consumo->>'ubicacion_id')::INT,
            (v_consumo->>'cantidad')::NUMERIC(12,2),
            'ORDEN_PRODUCCION_PASO',
            p_paso_id,
            p_consumo->>'observacion'
        FROM jsonb_array_elements(v_consumos) v_consumo
        JOIN jsonb_array_elements(p_consumos) p_consumo
        ON v_consumo->>'item_id' = p_consumo->>'item_id'
        ;
    RETURN format('%s consumos registrados para paso #%s.', jsonb_array_length(v_consumos), p_paso_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_consumo_paso - User: %, paso: %, Error: %, Detail: %',
              v_usr_id, p_paso_id, v_message, v_detail;
    RAISE;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- 22. FINALIZAR PASO
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.finalizar_paso(p_paso_id BIGINT, p_datos jsonb DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_estado       orden_produccion_paso_estado_enum;
    v_orden_id     bigint;
    v_maquina_id   int;
    v_op_nombre    text;
    v_todos_completos boolean;
BEGIN
    SELECT opp.estado, opp.orden_produccion_id, opp.maquina_asignada_id, o.nombre
    INTO v_estado, v_orden_id, v_maquina_id, v_op_nombre
    FROM mes.orden_produccion_paso opp
    LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
    WHERE opp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;
    IF v_estado <> 'EN_PROCESO' THEN
        RAISE EXCEPTION 'Solo se puede finalizar un paso EN_PROCESO. Estado actual: %', v_estado;
    END IF;

    -- Process consumptions (recipe + manual) if provided
    IF p_datos->'consumos' IS NOT NULL AND jsonb_array_length(p_datos->'consumos') > 0 THEN
        PERFORM mes.registrar_consumo_paso(p_paso_id, p_datos->'consumos');
    END IF;

    UPDATE mes.orden_produccion_paso
    SET estado  = 'COMPLETADO',
        fyh_fin = NOW()
    WHERE id = p_paso_id;

    -- Release machine
    IF v_maquina_id IS NOT NULL THEN
        UPDATE mes.maquina SET estado_actual = 'espera'
        WHERE id = v_maquina_id;
    END IF;

    -- Check if ALL pasos are done -> auto-complete orden
    SELECT NOT EXISTS (
        SELECT 1 FROM mes.orden_produccion_paso
        WHERE orden_produccion_id = v_orden_id
          AND estado NOT IN ('COMPLETADO','OMITIDO')
    ) INTO v_todos_completos;

    IF v_todos_completos THEN
        UPDATE mes.orden_produccion
        SET estado = 'FINALIZADA', fyh_fin = NOW()
        WHERE id = v_orden_id;
    END IF;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Paso Completado',
           COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name
                     FROM profiles WHERE id_usuario = v_usr_id), 'sistema')
           || format(' completó el paso %s (orden #%s)', v_op_nombre, v_orden_id), 'info',
           jsonb_build_object('objeto_tipo','orden_produccion_paso','paso_id', p_paso_id, 'orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','supervisor_produccion') AND v_usr_id <> ur.user_id;

    RETURN format('Paso %s (#%s) completado.%s', v_op_nombre, p_paso_id,
                  CASE WHEN v_todos_completos THEN ' Orden #' || v_orden_id || ' FINALIZADA.' ELSE '' END);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in finalizar_paso - User: %, ID: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION mes.calcular_fifo(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','inventario','mes'
AS $function$
DECLARE
    v_consumos jsonb;
BEGIN
    WITH fifo AS (
        SELECT
            st.lote_id,
            st.item_id,
            st.ubicacion_id,
            st.cantidad_disponible,
            st.fecha_hora_ingreso,
            (i->>'cantidad')::NUMERIC AS cantidad_solicitada,
            SUM(st.cantidad_disponible) OVER (
                PARTITION BY st.item_id ORDER BY st.fecha_hora_ingreso
            ) AS cantidad_acumulada
        FROM vw_stock_actual st
        JOIN jsonb_array_elements(p_items) i
            ON (i->>'item_id')::INT = st.item_id
    ),
    inventario_prev AS (
        SELECT
            *,
            LAG(cantidad_acumulada, 1, 0) OVER (
                PARTITION BY item_id ORDER BY fecha_hora_ingreso
            ) AS acumulado_previo
        FROM fifo
    ),
    inventario_consumo AS (
        SELECT
            lote_id,
            item_id,
            ubicacion_id,
            LEAST(
                cantidad_disponible,
                GREATEST(cantidad_solicitada - acumulado_previo, 0)
            ) AS cantidad_a_usar
        FROM inventario_prev
        WHERE acumulado_previo < cantidad_solicitada
    )
    SELECT jsonb_agg(jsonb_build_object(
        'lote_id', lote_id,
        'item_id', item_id,
        'ubicacion_id', ubicacion_id,
        'cantidad', cantidad_a_usar
    )) INTO v_consumos
    FROM inventario_consumo;

    RETURN v_consumos;
END;
$function$;





-- ═══════════════════════════════════════════════════════════════
-- 24. REGISTRAR ITEMS PROCESADOS EN PASO (roll tracking)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_items_procesados(p_paso_id BIGINT, p_items jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id int := get_user_id();
    v_deleted int;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM mes.orden_produccion_paso
        WHERE id = p_paso_id AND estado IN ('PENDIENTE', 'EN_PROCESO', 'COMPLETADO')
    ) THEN
        RAISE EXCEPTION 'Paso #% no encontrado o en estado que no permite registrar items.', p_paso_id;
    END IF;

    INSERT INTO mes.orden_produccion_paso_item(
        orden_produccion_paso_id, orden_produccion_item_id
    )
    SELECT p_paso_id,
           (i->>'orden_produccion_item_id')::INT
    FROM jsonb_array_elements(p_items) i
    ON CONFLICT (orden_produccion_paso_id, orden_produccion_item_id)
    DO UPDATE SET usr_mod = v_usr_id, fyh_mod = NOW();
    DELETE FROM mes.orden_produccion_paso_item
    WHERE orden_produccion_paso_id = p_paso_id
      AND orden_produccion_item_id NOT IN (
          SELECT (i->>'orden_produccion_item_id')::INT
          FROM jsonb_array_elements(p_items) i
      );
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN format('%s items procesados registrados para paso #%s. %s items eliminados.', jsonb_array_length(p_items), p_paso_id, v_deleted);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_items_procesados - User: %, paso: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- ACTUALIZAR PESOS DE ORDEN PRODUCCION ITEMS
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.actualizar_pesos_orden_items(p_orden_id BIGINT, p_peso int)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes','inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_estado    orden_produccion_estado_enum;
    v_count     int;
BEGIN
    -- Validar que la orden existe y no está en estado terminal
    SELECT estado INTO v_estado
    FROM mes.orden_produccion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden de producción con ID % no encontrada.', p_orden_id;
    END IF;

    IF v_estado IN ('TECO','CERRADA','CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden modificar pesos de una orden en estado %.', v_estado;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_pesos_orden_items', v_usr_id, jsonb_build_object('orden_id', p_orden_id, 'peso', p_peso));
    
    ---Confuigurar cantidad de items para proratear peso
    SELECT COUNT(*)
    INTO v_count
    FROM mes.orden_produccion_item
    WHERE orden_id = p_orden_id;

    IF v_count = 0 THEN
    RAISE EXCEPTION 'La orden % no tiene items', p_orden_id;
    END IF;

    p_peso := p_peso / v_count;

    -- Actualizar peso_kg para cada item
    UPDATE inventario.lote 
    SET cantidad = p_peso,
        detalle = jsonb_set(detalle, '{fyh_peso}', to_jsonb(NOW()))
    FROM mes.orden_produccion_item opi
    WHERE opi.orden_produccion_id = p_orden_id
      AND opi.lote_id = inventario.lote.id AND opi.item_id = inventario.lote.item_id AND opi.ubicacion_id = inventario.lote.ubicacion_id;


    RETURN format('%s pesos actualizados para orden #%s.', v_count, p_orden_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_pesos_orden_items - User: %, orden: %, Error: %, Detail: %',
              v_usr_id, p_orden_id, v_message, v_detail;
    RAISE;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- 25. REGISTRAR PRODUCCION (create output lotes)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_produccion(p_orden_paso_id BIGINT, p_output jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','mes','doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int := get_user_id();
    v_orden_id      bigint;
    v_partida_id    bigint;
    v_detalles      jsonb;
    v_propietario_id int;
    v_ing_tipo_id   smallint;
    v_error_payload jsonb;
BEGIN
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_produccion', v_usr_id, jsonb_build_object('orden_paso_id', p_orden_paso_id, 'output', p_output));

    -- 1. Paso must be EN_PROCESO; derive orden and partida
    SELECT opp.orden_produccion_id, op.partida_id
    INTO v_orden_id, v_partida_id
    FROM mes.orden_produccion_paso opp
    JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
    WHERE opp.id = p_orden_paso_id AND opp.estado IN ('EN_PROCESO','COMPLETADO') AND flg_final=TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso #% no encontrado o no está EN_PROCESO | COMPLETADO o no esta marcado como paso final.', p_orden_paso_id;
    END IF;
    
    PERFORM 1
    FROM doc.partida_detalle
    WHERE partida_id = v_partida_id
    FOR UPDATE;

    -- 2. Validate items exist in partida_detalle and quantity <= planned
    WITH solicitado AS (
        SELECT (i->>'item_id')::INT AS item_id, (i->>'cantidad')::NUMERIC AS cantidad
        FROM jsonb_array_elements(p_output) i
    ),
    errores AS (
        SELECT s.item_id, s.cantidad AS cantidad_solicitada,vppr.cantidad_rollos AS cantidad_producida, pd.cantidad AS cantidad_planificada
        FROM solicitado s
        LEFT JOIN doc.partida_detalle pd ON pd.partida_id = v_partida_id AND pd.item_id = s.item_id
        LEFT JOIN mes.vw_partida_produccion_rollos vppr ON vppr.partida_id = v_partida_id AND vppr.item_id = s.item_id
        WHERE pd.id IS NULL OR s.cantidad > pd.cantidad OR COALESCE(vppr.cantidad_rollos, 0)+s.cantidad > pd.cantidad
    )
    SELECT jsonb_agg(jsonb_build_object(
        'item_id', item_id,
        'cantidad_solicitada', cantidad_solicitada,
        'cantidad_producida', cantidad_producida,
        'cantidad_planificada', cantidad_planificada
    ))
    INTO v_error_payload
    FROM errores;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Items no válidos o cantidad excede lo planificado en partida'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- 3. Build lote detalles from partida specs
    SELECT p.cliente_id,
           jsonb_build_object(
               'tenido_id', p.tenido_id,
               'color_x_cliente_id', p.color_x_cliente_id,
               'malla', p.malla,
               'rendimiento', p.rendimiento,
               'ancho', p.ancho,
               'flg_antipilling', p.flg_antipilling
           )
    INTO v_propietario_id, v_detalles
    FROM doc.partida p WHERE p.id = v_partida_id;

    SELECT id INTO v_ing_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING';

    -- 4. Create lotes and ingress movements (set-based)
    WITH input_items AS (
        SELECT
            (i->>'item_id')::INT AS item_id,
            (i->>'cantidad')::NUMERIC(10,2) AS cantidad,
            (i->>'ubicacion_id')::INT AS destino_ubicacion_id
        FROM jsonb_array_elements(p_output) i
    ),
    new_lotes AS (
        INSERT INTO inventario.lote(
            item_id, documento_tipo, documento_id,
            cantidad, detalles, propietario_id
        )
        SELECT item_id, 'ORDEN_PRODUCCION', v_orden_id,
               cantidad, v_detalles, v_propietario_id
        FROM input_items
        RETURNING id, item_id, cantidad
    )
    INSERT INTO inventario.item_movimientos(
        item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad,
        documento_tipo, documento_id
    )
    SELECT nl.item_id, nl.id, v_ing_tipo_id,
           ii.destino_ubicacion_id,
           nl.cantidad,
           'ORDEN_PRODUCCION', v_orden_id
    FROM new_lotes nl
    JOIN input_items ii ON ii.item_id = nl.item_id;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Producción Registrada',
           COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name
                     FROM profiles WHERE id_usuario = v_usr_id), 'sistema')
           || format(' registró %s lotes de producción en orden #%s', jsonb_array_length(p_output), v_orden_id), 'info',
           jsonb_build_object('objeto_tipo','orden_produccion','orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','calidad') AND v_usr_id <> ur.user_id;

    RETURN format('%s lotes creados para orden #%s.', jsonb_array_length(p_output), v_orden_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_produccion - User: %, orden_paso: %, Error: %, Detail: %',
              v_usr_id, p_orden_paso_id, v_message, v_detail;
    RAISE;
END;
$function$;



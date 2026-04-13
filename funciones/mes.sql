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
        'id',                        prog.id,
        'maquina_id',                prog.maquina_id,
        'secuencia',                 prog.secuencia,
        'nota',                      prog.nota,
        'actividad_tipo',            prog.actividad_tipo,
        -- Production paso fields (null when actividad_tipo = 'LAVADO_MAQUINA')
        'paso_id',                   opp.id,
        'operacion',                 o.nombre,
        'operacion_codigo',          o.codigo,
        'paso_estado',               opp.estado,
        'orden_id',                  op.id,
        'orden_tipo',                op.tipo,
        'partida_id',                op.partida_id,
        'partida_codigo',            EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'op_codigo',                 EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') || '-' ||
                                         (SELECT numbered.rn::TEXT
                                          FROM (SELECT id, ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY fyh_cre, id) AS rn
                                                FROM mes.orden_produccion) numbered
                                          WHERE numbered.id = op.id),
        'cliente',                   c.nombre,
        'articulo_tipo_id',          p.articulo_tipo_id,
        'color',                     vc.color,
        'color_hex',                 vc.color_hex,
        'tono',                      vc.tono,
        'tenido',                    t.tenido,
        'ancho',                     p.ancho,
        'malla',                     p.malla,
        'rendimiento',               p.rendimiento,
        'articulo',                  vpa.articulo_nombre,
        'fibra',                     vpa.fibra,
        'total_rollos',              vpa.total_rollos,
        'cantidad_total',            vpa.cantidad_total,
        'cantidad_regular',          vpa.cantidad_regular,
        'cantidad_rib',              vpa.cantidad_rib,
        -- Lavado maquina fields (null when actividad_tipo = 'ORDEN_PRODUCCION_PASO')
        'lavado_id',                 lm.id,
        'lavado_estado',             lm.estado,
        'receta_lavado_maquina_id',  lm.receta_id  -- FIX BUG5: was lm.receta_lavado_maquina_id (old column name)
    ) AS row_obj
    FROM mes.programacion prog
    LEFT JOIN mes.orden_produccion_paso opp  ON prog.actividad_tipo = 'ORDEN_PRODUCCION_PASO' AND opp.id = prog.actividad_id
    LEFT JOIN mes.operacion o                ON o.id = opp.operacion_id
    LEFT JOIN mes.orden_produccion op        ON op.id = opp.orden_produccion_id
    LEFT JOIN doc.partida p                  ON p.id = op.partida_id
    LEFT JOIN tenido t                       ON t.id = p.tenido_id
    LEFT JOIN tercero c                      ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc                  ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN vw_partida_resumen_tenido vpa     ON vpa.partida_id = p.id
    LEFT JOIN mes.lavado_maquina lm          ON prog.actividad_tipo = 'LAVADO_MAQUINA' AND lm.id = prog.actividad_id
    WHERE prog.fecha = p_fecha
    ORDER BY prog.maquina_id, prog.secuencia
) sub;
$$;

-- Legacy name kept for backward compatibility — now delegates to get_actividades_sin_programar
-- Returns only ORDEN_PRODUCCION_PASO type (same shape as before for existing consumers)
CREATE OR REPLACE FUNCTION mes.get_pasos_sin_programar()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes'
AS $$
SELECT COALESCE(jsonb_agg(row_obj), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'actividad_tipo',     'ORDEN_PRODUCCION_PASO',
        'paso_id',            opp.id,
        'orden_id',           op.id,
        'operacion',          o.nombre,
        'operacion_codigo',   o.codigo,
        'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'op_codigo',          EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') || '-' ||
                                  (SELECT numbered.rn::TEXT
                                   FROM (SELECT id, ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY fyh_cre, id) AS rn
                                         FROM mes.orden_produccion) numbered
                                   WHERE numbered.id = op.id),
        'articulo_tipo_id',   p.articulo_tipo_id,
        'cliente',            c.nombre,
        'color',              vc.color,
        'color_hex',          vc.color_hex,
        'tono',               vc.tono,
        'tenido',             t.tenido
    ) AS row_obj
    FROM mes.orden_produccion_paso opp
    JOIN mes.operacion o ON o.id = opp.operacion_id
    JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
    JOIN doc.partida p ON p.id = op.partida_id
    LEFT JOIN tenido t ON t.id = p.tenido_id
    LEFT JOIN tercero c ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE opp.estado = 'PENDIENTE'
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog
          WHERE prog.actividad_tipo = 'ORDEN_PRODUCCION_PASO' AND prog.actividad_id = opp.id
      )
    ORDER BY p.fyh_cre DESC
) sub;
$$;

-- Unified: returns both unprogrammed production pasos AND unprogrammed lavados
-- Frontend uses actividad_tipo to render the correct card type
CREATE OR REPLACE FUNCTION mes.get_actividades_sin_programar()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes'
AS $$
SELECT COALESCE(jsonb_agg(row_obj ORDER BY fyh_cre DESC), '[]'::jsonb)
FROM (
    -- Production pasos (PENDIENTE, not yet on board)
    SELECT
        p.fyh_cre,
        jsonb_build_object(
            'actividad_tipo',     'ORDEN_PRODUCCION_PASO',
            'actividad_id',       opp.id,
            'paso_id',            opp.id,
            'orden_id',           op.id,
            'operacion',          o.nombre,
            'operacion_codigo',   o.codigo,
            'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
            'op_codigo',          EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') || '-' ||
                                      (SELECT numbered.rn::TEXT
                                       FROM (SELECT id, ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY fyh_cre, id) AS rn
                                             FROM mes.orden_produccion) numbered
                                       WHERE numbered.id = op.id),
            'articulo_tipo_id',   p.articulo_tipo_id,
            'cliente',            c.nombre,
            'color',              vc.color,
            'color_hex',          vc.color_hex,
            'tono',               vc.tono,
            'tenido',             t.tenido
        ) AS row_obj
    FROM mes.orden_produccion_paso opp
    JOIN mes.operacion o ON o.id = opp.operacion_id
    JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
    JOIN doc.partida p ON p.id = op.partida_id
    LEFT JOIN tenido t ON t.id = p.tenido_id
    LEFT JOIN tercero c ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE opp.estado = 'PENDIENTE'
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog
          WHERE prog.actividad_tipo = 'ORDEN_PRODUCCION_PASO' AND prog.actividad_id = opp.id
      )

    UNION ALL

    -- Machine wash activities (PENDIENTE, not yet on board)
    SELECT
        lm.fyh_cre,
        jsonb_build_object(
            'actividad_tipo',            'LAVADO_MAQUINA',
            'actividad_id',              lm.id,
            'lavado_id',                 lm.id,
            'receta_lavado_maquina_id',  lm.receta_id,  -- FIX BUG5: was lm.receta_lavado_maquina_id
            'maquina_id',                lm.maquina_id,
            'nota',                      lm.nota
        ) AS row_obj
    FROM mes.lavado_maquina lm
    WHERE lm.estado = 'PENDIENTE'
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog
          WHERE prog.actividad_tipo = 'LAVADO_MAQUINA' AND prog.actividad_id = lm.id
      )
) sub;
$$;



-- ═══════════════════════════════════════════════════════════════
-- GUARDAR PROGRAMACION - Full replace for a given date
-- Accepts both production pasos and lavado_maquina activities
-- Each element: { actividad_tipo, actividad_id, maquina_id, secuencia, nota? }
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.guardar_programacion(
    p_fecha DATE,
    p_programaciones JSONB
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes'
AS $function$
DECLARE
    v_usr_id         INT := get_user_id();
    v_invalid_pasos  JSONB;
    v_invalid_lavados JSONB;
BEGIN
    IF NOT jwt_has_permission('produccion.programar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.programar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Validate production pasos: must not be COMPLETADO or OMITIDO
    SELECT jsonb_agg(jsonb_build_object('actividad_id', opp.id, 'estado', opp.estado))
    INTO v_invalid_pasos
    FROM jsonb_array_elements(p_programaciones) elem
    JOIN mes.orden_produccion_paso opp ON opp.id = (elem->>'actividad_id')::BIGINT
    WHERE elem->>'actividad_tipo' = 'ORDEN_PRODUCCION_PASO'
      AND opp.estado IN ('COMPLETADO', 'OMITIDO');

    IF v_invalid_pasos IS NOT NULL THEN
        RAISE EXCEPTION 'Pasos no programables (ya COMPLETADO/OMITIDO): %', v_invalid_pasos;
    END IF;

    -- 2. Validate lavados: must not be COMPLETADO
    SELECT jsonb_agg(jsonb_build_object('actividad_id', lm.id, 'estado', lm.estado))
    INTO v_invalid_lavados
    FROM jsonb_array_elements(p_programaciones) elem
    JOIN mes.lavado_maquina lm ON lm.id = (elem->>'actividad_id')::BIGINT
    WHERE elem->>'actividad_tipo' = 'LAVADO_MAQUINA'
      AND lm.estado = 'COMPLETADO';

    IF v_invalid_lavados IS NOT NULL THEN
        RAISE EXCEPTION 'Lavados no programables (ya COMPLETADO): %', v_invalid_lavados;
    END IF;

    -- 3. Full replace for the date
    DELETE FROM mes.programacion WHERE fecha = p_fecha;

    INSERT INTO mes.programacion (actividad_tipo, actividad_id, maquina_id, fecha, secuencia, nota)
    SELECT
        elem->>'actividad_tipo',
        (elem->>'actividad_id')::BIGINT,
        (elem->>'maquina_id')::INT,
        p_fecha,
        (elem->>'secuencia')::SMALLINT,
        elem->>'nota'
    FROM jsonb_array_elements(p_programaciones) elem;

    -- 4. Sync maquina_asignada_id on production pasos only
    UPDATE mes.orden_produccion_paso opp
    SET maquina_asignada_id = (elem->>'maquina_id')::INT
    FROM jsonb_array_elements(p_programaciones) AS elem
    WHERE elem->>'actividad_tipo' = 'ORDEN_PRODUCCION_PASO'
      AND opp.id = (elem->>'actividad_id')::BIGINT;

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
SET search_path TO 'iam','notification','public','receta','mes','doc'
AS $function$
DECLARE
    v_receta           jsonb;
    v_receta_id        int;
    v_maquina_id       int;
    v_maq_nombre       text;
    v_maq_codigo       text;
    v_rb               numeric;
    v_peso             numeric;
    v_cantidad         numeric;
    v_cantidad_regular numeric;
    v_cantidad_rib     numeric;
    v_volumen          numeric;
    v_usr_id           int := get_user_id();
    v_orden_id         bigint;
    v_op_nombre        text;
    v_message          text;
    v_detail           text;
    v_hint             text;
    v_context          text;
    v_sqlstate         text;
BEGIN
    IF NOT jwt_has_permission('produccion.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Validate paso, get receta + machine + relacion_bano
    SELECT opp.receta_id, opp.maquina_asignada_id, COALESCE(opp.relacion_bano, m.relacion_bano),
           opp.orden_produccion_id, o.nombre
    INTO v_receta_id, v_maquina_id, v_rb, v_orden_id, v_op_nombre
    FROM mes.orden_produccion_paso opp
    LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
    LEFT JOIN mes.maquina m   ON m.id = opp.maquina_asignada_id
    WHERE opp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;
    IF v_receta_id IS NULL THEN
        RAISE EXCEPTION 'Paso ID % sin receta asignada.', p_paso_id;
    END IF;

    -- 2. Machine info
    SELECT m.nombre, m.codigo INTO v_maq_nombre, v_maq_codigo
    FROM mes.maquina m WHERE m.id = v_maquina_id;

    -- 3. Roll aggregation (weight + count)
    SELECT
        SUM(l.cantidad),
        SUM(CASE ird.flg_rib WHEN false THEN 1 ELSE 0 END),
        SUM(CASE ird.flg_rib WHEN true  THEN 1 ELSE 0 END)
    INTO v_peso, v_cantidad_regular, v_cantidad_rib
    FROM mes.orden_produccion_paso_item oppi
    JOIN mes.orden_produccion_item opi ON oppi.orden_produccion_item_id = opi.id
    JOIN inventario.lote l             ON opi.lote_id = l.id
    JOIN item_rollo_detalle ird        ON ird.item_id = l.item_id
    WHERE oppi.orden_produccion_paso_id = p_paso_id;

    v_cantidad := COALESCE(v_cantidad_regular, 0) + COALESCE(v_cantidad_rib, 0);

    -- 4. Bath volume
    v_volumen := CASE
        WHEN v_maq_nombre != 'BRAZOLI (1)' AND v_cantidad <= 12 THEN v_peso * 7
        ELSE v_peso * v_rb
    END;

    -- 5. Build JSON
    -- pasos: chemistry steps with nested insumos (new hierarchical model)
    -- Breaking change from flat insumos[]: frontend flattens pasos[].insumos[] for consumption form
    SELECT jsonb_build_object(
        'receta_id',         opp.receta_id,
        'partida_id',        p.id,
        'tercero_id',        p.tercero_id,
        'cliente',           cli.nombre,
        'orden_produccion_id', op.id,
        'tipo_receta',       tr.tipo_receta,
        'articulo_tipo_id',  r.articulo_tipo_id,
        'articulo_tipo',     at.nombre,
        'fibra',             r.fibra,
        'peso',              v_peso,
        'cantidad',          v_cantidad,
        'cantidad_regular',  v_cantidad_regular,
        'cantidad_rib',      v_cantidad_rib,
        'volumen',           ROUND(v_volumen::NUMERIC, 2),
        'maquina',           jsonb_build_object(
                                 'id',     v_maquina_id,
                                 'codigo', v_maq_codigo,
                                 'nombre', v_maq_nombre
                             ),
        'pasos', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'orden',        rtp.orden,
                    'operacion_id', ro.id,
                    'operacion',    ro.nombre,
                    'ph',           rtp.ph,
                    'temperatura',  rtp.temperatura,
                    'tiempo_min',   rtp.tiempo_min,
                    'nota',         rtp.nota,
                    'insumos', (
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'item_id',              rtpi.item_id,
                                'orden',                rtpi.orden,
                                'codigo',               i.codigo,
                                'nombre',               i.nombre,
                                'cantidad',             rtpi.cantidad,
                                'medida',               iid.medida,
                                'cantidad_requerida_kg', CASE
                                    WHEN iid.medida = 'g/L' THEN rtpi.cantidad * v_volumen * iid.factor_stock
                                    WHEN iid.medida = '%'   THEN rtpi.cantidad * v_peso * 10 * iid.factor_stock
                                END
                            ) ORDER BY rtpi.orden
                        )
                        FROM receta.tenido_paso_insumo rtpi
                        JOIN item i                ON i.id   = rtpi.item_id
                        JOIN item_insumo_detalle iid ON iid.item_id = rtpi.item_id
                        WHERE rtpi.paso_id = rtp.id
                    )
                ) ORDER BY rtp.orden
            )
            FROM receta.tenido_paso rtp
            JOIN receta.operacion ro ON ro.id = rtp.operacion_id
            WHERE rtp.receta_id = r.id
        )
    ) INTO v_receta
    FROM mes.orden_produccion_paso opp
    JOIN receta.tenido r          ON r.id  = opp.receta_id
    JOIN mes.orden_produccion op  ON op.id = opp.orden_produccion_id
    JOIN doc.partida p            ON p.id  = op.partida_id
    LEFT JOIN tipo_receta tr      ON tr.id  = r.tipo_receta_id
    JOIN articulo_tipo at         ON at.id  = r.articulo_tipo_id
    LEFT JOIN tercero cli         ON cli.id = p.tercero_id
    WHERE opp.id = p_paso_id;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Receta Generada',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
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
    v_requiere_receta       boolean;
    v_check boolean;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT opp.estado, opp.orden_produccion_id, o.nombre, opp.secuencia,o.requiere_receta,CASE WHEN (o.requiere_receta AND opp.receta_id IS NULL)or (o.requiere_maquina AND opp.maquina_asignada_id IS NULL) THEN false ELSE true END
    INTO v_estado, v_orden_id, v_op_nombre, v_secuencia, v_requiere_receta, v_check
    FROM mes.orden_produccion_paso opp
    LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
    WHERE opp.id = p_paso_id;
    ---EVALUAR mejora futura
-- -- current (verbose)
-- CASE WHEN (o.requiere_receta AND opp.receta_id IS NULL)
--       OR  (o.requiere_maquina AND opp.maquina_asignada_id IS NULL)
--      THEN false ELSE true END

-- -- cleaner
-- (NOT o.requiere_receta OR opp.receta_id IS NOT NULL)
-- AND (NOT o.requiere_maquina OR opp.maquina_asignada_id IS NOT NULL)

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;
    IF v_estado <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'Solo se puede iniciar un paso en estado PENDIENTE. Estado actual: %', v_estado;
    END IF;
    IF NOT v_check THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque no se han cumplido los requisitos de receta o maquina asignadas.', v_op_nombre;
    END IF;
    IF EXISTS (SELECT 1 FROM mes.orden_produccion_paso WHERE secuencia < v_secuencia AND orden_produccion_id=v_orden_id AND estado NOT IN ('COMPLETADO','OMITIDO')) THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque hay pasos anteriores no completados.', v_op_nombre;
    END IF;
    IF v_requiere_receta AND NOT EXISTS (SELECT 1 FROM mes.orden_produccion_paso_item WHERE orden_produccion_paso_id = p_paso_id) THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque no tiene rollos asignados.', v_op_nombre;
    END IF;

    UPDATE mes.orden_produccion_paso
    SET estado      = 'EN_PROCESO',
        fyh_inicio  = NOW(),
        empleado_id = COALESCE((p_datos->>'empleado_id')::SMALLINT, empleado_id),
        maquina_asignada_id = COALESCE((p_datos->>'maquina_asignada_id')::INT, maquina_asignada_id)
    WHERE id = p_paso_id;

    -- Auto-start (or revert) the parent orden to EN_PROCESO
    UPDATE mes.orden_produccion
    SET estado = 'EN_PROCESO', fyh_inicio = COALESCE(fyh_inicio, NOW()), fyh_fin = NULL
    WHERE id = v_orden_id AND estado IN ('CREADA','PLANIFICADA','PROGRAMADA','LIBERADA','FINALIZADA');

    -- Auto-start the partida if still CONFIRMADA
    UPDATE doc.partida
    SET estado = 'EN_PRODUCCION'
    WHERE id = (SELECT partida_id FROM mes.orden_produccion WHERE id = v_orden_id)
      AND estado = 'CONFIRMADA';

    -- Update machine state
    IF (p_datos->>'maquina_asignada_id') IS NOT NULL THEN
        UPDATE mes.maquina SET estado_actual = 'activa'
        WHERE id = (p_datos->>'maquina_asignada_id')::INT;
    END IF;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Paso Iniciado',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
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
    v_usr_id            int := get_user_id();
    v_consumos          jsonb;
    v_saldo             numeric;
    v_egr_tipo_id       smallint;
    v_error_payload     jsonb;
    v_doc_movimiento_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

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
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;
        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario,
            documento_tipo, documento_id, observacion
        ) SELECT
            v_doc_movimiento_id,
            (v_consumo->>'item_id')::INT,
            (v_consumo->>'lote_id')::INT,
            v_egr_tipo_id,
            (v_consumo->>'ubicacion_id')::INT,
            (v_consumo->>'cantidad')::NUMERIC,
            (SELECT iv.precio_promedio FROM inventario.item_valoracion iv
             WHERE iv.item_id = (v_consumo->>'item_id')::INT),
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
-- ACTUALIZAR PESOS DE ORDEN PRODUCCION ITEMS
-- Correction function for post-assignment weight adjustments.
-- Distributes totals separately for rib vs regular rolls.
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS mes.actualizar_pesos_orden_items(BIGINT, NUMERIC);

CREATE OR REPLACE FUNCTION mes.actualizar_pesos_orden_items(
    p_orden_id      BIGINT,
    p_peso_regular  NUMERIC,        -- total kg for regular rolls; NULL = skip
    p_peso_rib      NUMERIC         -- total kg for rib rolls;     NULL = skip
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes','inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_estado            orden_produccion_estado_enum;
    v_count_regular     int;
    v_count_rib         int;
    v_peso_por_regular  numeric;
    v_peso_por_rib      numeric;
    v_count             int;
    v_pesaje_pos_id     smallint;
    v_pesaje_neg_id     smallint;
    v_doc_movimiento_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado INTO v_estado
    FROM mes.orden_produccion WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden de producción con ID % no encontrada.', p_orden_id;
    END IF;
    IF v_estado IN ('TECO','CERRADA','CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden modificar pesos de una orden en estado %.', v_estado;
    END IF;

    -- Count rolls by type
    SELECT
        COUNT(*) FILTER (WHERE ird.flg_rib = false),
        COUNT(*) FILTER (WHERE ird.flg_rib = true)
    INTO v_count_regular, v_count_rib
    FROM mes.orden_produccion_item opi
    JOIN inventario.lote l      ON l.id = opi.lote_id AND l.flg_elm = false
    JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
    WHERE opi.orden_produccion_id = p_orden_id;

    IF v_count_regular = 0 AND v_count_rib = 0 THEN
        RAISE EXCEPTION 'La orden % no tiene items', p_orden_id;
    END IF;
    IF p_peso_regular IS NOT NULL AND v_count_regular = 0 THEN
        RAISE EXCEPTION 'Se proporcionó peso_regular pero la orden #% no tiene rollos regulares asignados.', p_orden_id;
    END IF;
    IF p_peso_rib IS NOT NULL AND v_count_rib = 0 THEN
        RAISE EXCEPTION 'Se proporcionó peso_rib pero la orden #% no tiene rollos rib asignados.', p_orden_id;
    END IF;

    v_peso_por_regular := CASE WHEN v_count_regular > 0 AND p_peso_regular IS NOT NULL
                               THEN ROUND(p_peso_regular / v_count_regular, 4) END;
    v_peso_por_rib     := CASE WHEN v_count_rib > 0 AND p_peso_rib IS NOT NULL
                               THEN ROUND(p_peso_rib / v_count_rib, 4) END;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_pesos_orden_items', v_usr_id,
            jsonb_build_object('orden_id', p_orden_id, 'peso_regular', p_peso_regular, 'peso_rib', p_peso_rib));

    SELECT id INTO v_pesaje_pos_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_POS';
    SELECT id INTO v_pesaje_neg_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_NEG';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    WITH rolls AS (
        SELECT
            l.id        AS lote_id,
            l.item_id,
            l.cantidad  AS peso_anterior,
            sa.ubicacion_id,
            ird.flg_rib,
            CASE WHEN ird.flg_rib THEN v_peso_por_rib ELSE v_peso_por_regular END AS peso_nuevo
        FROM mes.orden_produccion_item opi
        JOIN inventario.lote l      ON l.id = opi.lote_id AND l.flg_elm = false
        JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
        JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id
        WHERE opi.orden_produccion_id = p_orden_id
          AND CASE WHEN ird.flg_rib THEN v_peso_por_rib     IS NOT NULL
                   ELSE                  v_peso_por_regular IS NOT NULL END
    ),
    pesajes AS (
        INSERT INTO inventario.pesaje (orden_produccion_id, lote_id, peso_real, usr_cre)
        SELECT p_orden_id, r.lote_id, r.peso_nuevo, v_usr_id
        FROM rolls r
        ON CONFLICT (lote_id) DO UPDATE
            SET peso_real           = EXCLUDED.peso_real,
                orden_produccion_id = EXCLUDED.orden_produccion_id
        RETURNING id, lote_id
    ),
    movimientos AS (
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, documento_tipo, documento_id
        )
        SELECT
            v_doc_movimiento_id,
            r.item_id, r.lote_id,
            CASE WHEN r.peso_nuevo > r.peso_anterior THEN v_pesaje_pos_id ELSE v_pesaje_neg_id END,
            CASE WHEN r.peso_nuevo < r.peso_anterior THEN r.ubicacion_id ELSE NULL END,
            CASE WHEN r.peso_nuevo > r.peso_anterior THEN r.ubicacion_id ELSE NULL END,
            ABS(r.peso_nuevo - r.peso_anterior),
            'ORDEN_PRODUCCION', p_orden_id
        FROM rolls r
        JOIN pesajes p ON p.lote_id = r.lote_id
        WHERE ABS(r.peso_nuevo - r.peso_anterior) > 0
    )
    UPDATE inventario.lote l
    SET cantidad = r.peso_nuevo
    FROM rolls r
    WHERE l.id = r.lote_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN format(
        '%s pesos actualizados para orden #%s (%s regulares × %s kg, %s rib × %s kg).',
        v_count, p_orden_id,
        COALESCE(v_count_regular, 0), COALESCE(v_peso_por_regular::text, 'sin cambio'),
        COALESCE(v_count_rib, 0),     COALESCE(v_peso_por_rib::text,     'sin cambio')
    );

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_pesos_orden_items - User: %, orden: %, Error: %, Detail: %',
              v_usr_id, p_orden_id, v_message, v_detail;
    RAISE;
END;
$function$;


CREATE OR REPLACE FUNCTION mes.actualizar_pesos_individuales_orden(
    p_orden_id  BIGINT,
    p_items     jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_estado            orden_produccion_estado_enum;
    v_count             int;
    v_pesaje_pos_id     smallint;
    v_pesaje_neg_id     smallint;
    v_doc_movimiento_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado INTO v_estado
    FROM mes.orden_produccion WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden de producción con ID % no encontrada.', p_orden_id;
    END IF;
    IF v_estado IN ('TECO', 'CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden modificar pesos de una orden en estado %.', v_estado;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_pesos_individuales_orden', v_usr_id,
            jsonb_build_object('orden_id', p_orden_id, 'items', p_items));

    SELECT id INTO v_pesaje_pos_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_POS';
    SELECT id INTO v_pesaje_neg_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_NEG';

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    WITH
    input_items AS (
        SELECT (i->>'id')::BIGINT AS opi_id, (i->>'peso_kg')::NUMERIC AS peso_nuevo
        FROM jsonb_array_elements(p_items) i
    ),
    lotes_data AS (
        SELECT
            ii.peso_nuevo,
            l.id AS lote_id,
            l.item_id,
            l.cantidad AS peso_anterior,
            sa.ubicacion_id,
            ii.peso_nuevo - l.cantidad AS diferencia
        FROM input_items ii
        JOIN mes.orden_produccion_item opi ON opi.id = ii.opi_id
            AND opi.orden_produccion_id = p_orden_id
        JOIN inventario.lote l ON l.id = opi.lote_id AND l.item_id = opi.item_id
        JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id
    ),
    pesajes AS (
        INSERT INTO inventario.pesaje (orden_produccion_id, lote_id, peso_real, usr_cre)
        SELECT p_orden_id, ld.lote_id, ld.peso_nuevo, v_usr_id
        FROM lotes_data ld
        ON CONFLICT (lote_id) DO UPDATE
            SET peso_real = EXCLUDED.peso_real,
                orden_produccion_id = EXCLUDED.orden_produccion_id
        RETURNING id, lote_id
    ),
    movimientos AS (
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, documento_tipo, documento_id
        )
        SELECT
            v_doc_movimiento_id,
            ld.item_id, ld.lote_id,
            CASE WHEN ld.diferencia > 0 THEN v_pesaje_pos_id ELSE v_pesaje_neg_id END,
            CASE WHEN ld.diferencia < 0 THEN ld.ubicacion_id ELSE NULL END,
            CASE WHEN ld.diferencia > 0 THEN ld.ubicacion_id ELSE NULL END,
            ABS(ld.diferencia),
            'ORDEN_PRODUCCION', p_orden_id
        FROM lotes_data ld
        JOIN pesajes p ON p.lote_id = ld.lote_id
        WHERE ld.diferencia <> 0
    )
    UPDATE inventario.lote l
    SET cantidad = ld.peso_nuevo
    FROM lotes_data ld
    WHERE l.id = ld.lote_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN format('%s pesos actualizados individualmente para orden #%s.', v_count, p_orden_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
        v_hint = PG_EXCEPTION_HINT, v_context = PG_EXCEPTION_CONTEXT,
        v_sqlstate = RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_pesos_individuales_orden - User: %, orden: %, Error: %, Detail: %',
              v_usr_id, p_orden_id, v_message, v_detail;
    RAISE;
END;
$function$;



-- UPDATE mes.orden_produccion
-- SET estado = 'EN_PROCESO'
-- WHERE id=8098;
-- UPDATE mes.orden_produccion_paso
-- SET estado = 'PENDIENTE'
-- WHERE fyh_inicio::date=now()::date and secuencia=3
-- RETURNING id;

-- SELECT id, flg_genera_produccion FROM mes.orden_produccion_paso WHERE id = 4488;

-- UPDATE mes.orden_produccion_paso opp SET estado='PENDIENTE' WHERE orden_produccion_id =8099 AND secuencia =4
-- SELECT * FROM inventario.item_movimientos WHERE documento_tipo='ORDEN_PRODUCCION_PASO' AND documento_id=4488;

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
    v_error_payload jsonb;
    v_deleted int;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM mes.orden_produccion_paso
        WHERE id = p_paso_id AND estado IN ('PENDIENTE', 'EN_PROCESO', 'COMPLETADO')
    ) THEN
        RAISE EXCEPTION 'Paso #% no encontrado o en estado que no permite registrar items.', p_paso_id;
    END IF;

 -- 2. Validation (adjust as needed for UN vs KG)
    WITH errores AS (
        SELECT (i->>'orden_produccion_item_id')::INT AS orden_produccion_item_id
        FROM jsonb_array_elements(p_items) i
        JOIN mes.orden_produccion_paso_item oppi ON oppi.orden_produccion_item_id = (i->>'orden_produccion_item_id')::INT
        JOIN mes.orden_produccion_paso opp ON opp.id = oppi.orden_produccion_paso_id
        WHERE opp.flg_genera_produccion=true and opp.id != p_paso_id
    )
    SELECT jsonb_agg(jsonb_build_object(
        'orden_produccion_item_id', orden_produccion_item_id
    ))
    INTO v_error_payload
    FROM errores;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Items seleccionados ya fueron usados para generar produccion'
            USING DETAIL = v_error_payload::text;
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
-- 25. REGISTRAR PRODUCCION (create output lotes)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_produccion(
    p_orden_paso_id BIGINT,
    p_output jsonb,
    p_ubicacion_id INT  -- single destination for all lotes
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','mes','doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_orden_id          bigint;
    v_partida_id        bigint;
    v_ing_tipo_id       smallint;
    v_egr_tipo_id       smallint;
    v_consumed          int;
    -- Loop variables for output lote creation
    v_elem              jsonb;
    v_input_lote_id     int;
    v_peso_salida       numeric;
    v_out_item_id       int;
    v_out_propietario   int;
    v_new_lote_id           int;
    v_guia_remision_id      bigint;
    v_doc_movimiento_id     BIGINT;
    -- Partida attributes copied to each output lrd row
    v_partida_ancho             TEXT;
    v_partida_malla             TEXT;
    v_partida_rendimiento       TEXT;
    v_partida_color_x_cliente   INT;
    v_partida_tenido_id         INT;
    v_partida_flg_antipilling   BOOLEAN;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_produccion', v_usr_id, jsonb_build_object(
        'orden_paso_id', p_orden_paso_id, 'output', p_output, 'ubicacion_id', p_ubicacion_id
    ));

    -- 1. Paso must be EN_PROCESO/COMPLETADO and flagged final
    SELECT opp.orden_produccion_id, op.partida_id
    INTO v_orden_id, v_partida_id
    FROM mes.orden_produccion_paso opp
    JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
    WHERE opp.id = p_orden_paso_id AND opp.estado IN ('EN_PROCESO','COMPLETADO') AND flg_genera_produccion=TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso #% no encontrado o no está EN_PROCESO | COMPLETADO o no esta marcado como paso final.', p_orden_paso_id;
    END IF;

    PERFORM 1
    FROM doc.partida_detalle
    WHERE partida_id = v_partida_id
    FOR UPDATE;
-- Lock existing production lotes for this orden paso
PERFORM 1
FROM inventario.lote
WHERE documento_tipo = 'ORDEN_PRODUCCION_PASO' AND documento_id = p_orden_paso_id
FOR UPDATE;
-- Lock input roll lotes to prevent concurrent consumption
PERFORM 1
FROM inventario.lote l
JOIN mes.orden_produccion_item opi ON opi.lote_id = l.id
JOIN mes.orden_produccion_paso_item oppi ON oppi.orden_produccion_item_id = opi.id
WHERE oppi.orden_produccion_paso_id = p_orden_paso_id
FOR UPDATE OF l;
PERFORM 1
FROM mes.orden_produccion
WHERE id = v_orden_id
FOR UPDATE;
    -- 2. Validate all input_lote_ids are assigned to this paso
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_output) i
        WHERE NOT EXISTS (
            SELECT 1 FROM mes.orden_produccion_paso_item oppi
            JOIN mes.orden_produccion_item opi ON opi.id = oppi.orden_produccion_item_id
            WHERE oppi.orden_produccion_paso_id = p_orden_paso_id
              AND opi.lote_id = (i->>'input_lote_id')::INT
        )
    ) THEN
        RAISE EXCEPTION 'Uno o más input_lote_id no están asignados a este paso de producción.';
    END IF;

    SELECT id INTO v_ing_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING';
    SELECT id INTO v_egr_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

    -- Fetch partida attributes once; copied to every output lrd row
    SELECT ancho, malla, rendimiento, color_x_cliente_id, tenido_id, flg_antipilling
    INTO v_partida_ancho, v_partida_malla, v_partida_rendimiento,
         v_partida_color_x_cliente, v_partida_tenido_id, v_partida_flg_antipilling
    FROM doc.partida WHERE id = v_partida_id;

    -- Single posting id shared by backflush + output movements
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- 4a. Backflush: consume input rolls assigned to this paso
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad,
        documento_tipo, documento_id
    )
    SELECT
        v_doc_movimiento_id,
        opi.item_id,
        opi.lote_id,
        v_egr_tipo_id,
        opi.ubicacion_id,
        l.cantidad,
        'ORDEN_PRODUCCION_PASO',
        p_orden_paso_id
    FROM mes.orden_produccion_paso_item oppi
    JOIN mes.orden_produccion_item opi ON opi.id = oppi.orden_produccion_item_id
    JOIN inventario.lote l ON l.id = opi.lote_id
    WHERE oppi.orden_produccion_paso_id = p_orden_paso_id;

    GET DIAGNOSTICS v_consumed = ROW_COUNT;

    -- 4b. Create output lotes (same item_id as input), PROD_ING movements,
    --     and lote_rollo_detalle carrying guia_remision_id forward.
    FOR v_elem IN SELECT value FROM jsonb_array_elements(p_output)
    LOOP
        v_input_lote_id := (v_elem->>'input_lote_id')::INT;
        v_peso_salida   := (v_elem->>'peso_salida')::NUMERIC;

        -- Inherit item_id, propietario, and billing anchor from input lote
        SELECT l.item_id, l.propietario_id, lrd.guia_remision_id
        INTO v_out_item_id, v_out_propietario, v_guia_remision_id
        FROM inventario.lote l
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
        WHERE l.id = v_input_lote_id;

        INSERT INTO inventario.lote(item_id, documento_tipo, documento_id, cantidad, propietario_id)
        VALUES (v_out_item_id, 'ORDEN_PRODUCCION_PASO', p_orden_paso_id, v_peso_salida, v_out_propietario)
        RETURNING id INTO v_new_lote_id;

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            destino_ubicacion_id, cantidad, documento_tipo, documento_id
        )
        VALUES (v_doc_movimiento_id, v_out_item_id, v_new_lote_id, v_ing_tipo_id,
                p_ubicacion_id, v_peso_salida, 'ORDEN_PRODUCCION_PASO', p_orden_paso_id);

        -- Batch classification: carry ingress guia forward; populate all roll identity attributes
        INSERT INTO inventario.lote_rollo_detalle(
            lote_id, guia_remision_id,
            ancho, malla, rendimiento,
            color_x_cliente_id, tenido_id,
            flg_tenido, flg_antipilling
        )
        VALUES (
            v_new_lote_id, v_guia_remision_id,
            v_partida_ancho, v_partida_malla, v_partida_rendimiento,
            v_partida_color_x_cliente, v_partida_tenido_id,
            true, v_partida_flg_antipilling
        );
    END LOOP;

    -- 5. Notifications
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Producción Registrada',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' registró %s lotes de producción en orden #%s', jsonb_array_length(p_output), v_orden_id), 'info',
           jsonb_build_object('objeto_tipo','orden_produccion','orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','calidad') AND v_usr_id <> ur.user_id;

    RETURN format('%s rollos consumidos, %s lotes creados para orden #%s.', v_consumed, jsonb_array_length(p_output), v_orden_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_produccion - User: %, orden_paso: %, Error: %, Detail: %',
              v_usr_id, p_orden_paso_id, v_message, v_detail;
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
    v_flg_genera_produccion    boolean;
    v_todos_completos boolean;
    v_prod_result  text;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT opp.estado, opp.orden_produccion_id, opp.maquina_asignada_id, o.nombre, opp.flg_genera_produccion
    INTO v_estado, v_orden_id, v_maquina_id, v_op_nombre, v_flg_genera_produccion
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

    -- Register production output atomically (final step only)
    IF v_flg_genera_produccion AND p_datos->'produccion' IS NOT NULL AND jsonb_array_length(p_datos->'produccion') > 0 THEN
        v_prod_result := mes.registrar_produccion(
            p_paso_id,
            p_datos->'produccion',
            (p_datos->>'ubicacion_id')::INT
        );
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
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' completó el paso %s (orden #%s)', v_op_nombre, v_orden_id), 'info',
           jsonb_build_object('objeto_tipo','orden_produccion_paso','paso_id', p_paso_id, 'orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','supervisor_produccion') AND v_usr_id <> ur.user_id;

    RETURN format('Paso %s (#%s) completado.%s%s', v_op_nombre, p_paso_id,
                  CASE WHEN v_prod_result IS NOT NULL THEN ' ' || v_prod_result ELSE '' END,
                  CASE WHEN v_todos_completos THEN ' Orden #' || v_orden_id || ' FINALIZADA.' ELSE '' END);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in finalizar_paso - User: %, ID: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- INICIAR LAVADO — start a machine wash activity
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.iniciar_lavado(p_lavado_id BIGINT, p_datos jsonb DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id      INT := get_user_id();
    v_estado      orden_produccion_paso_estado_enum;
    v_maquina_id  INT;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado, maquina_id
    INTO v_estado, v_maquina_id
    FROM mes.lavado_maquina
    WHERE id = p_lavado_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lavado con ID % no encontrado.', p_lavado_id;
    END IF;
    IF v_estado <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'Solo se puede iniciar un lavado en estado PENDIENTE. Estado actual: %', v_estado;
    END IF;

    UPDATE mes.lavado_maquina
    SET estado      = 'EN_PROCESO',
        fyh_inicio  = NOW(),
        empleado_id = COALESCE((p_datos->>'empleado_id')::SMALLINT, empleado_id),
        usr_mod     = v_usr_id,
        fyh_mod     = NOW()
    WHERE id = p_lavado_id;

    UPDATE mes.maquina SET estado_actual = 'activa' WHERE id = v_maquina_id;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Lavado Iniciado',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' inició lavado de maquina #%s', v_maquina_id), 'info',
           jsonb_build_object('objeto_tipo','lavado_maquina','lavado_id', p_lavado_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta') AND v_usr_id <> ur.user_id;

    RETURN format('Lavado #%s iniciado correctamente.', p_lavado_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in iniciar_lavado - User: %, ID: %, Error: %', v_usr_id, p_lavado_id, v_message;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- FINALIZAR LAVADO — complete a machine wash, record chemical consumption
-- p_datos.consumos[] optional: [{ item_id, cantidad, observacion? }]
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.finalizar_lavado(p_lavado_id BIGINT, p_datos jsonb DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            INT := get_user_id();
    v_estado            orden_produccion_paso_estado_enum;
    v_maquina_id        INT;
    v_consumos          jsonb;
    v_saldo             numeric;
    v_egr_tipo_id       smallint;
    v_error_payload     jsonb;
    v_doc_movimiento_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado, maquina_id
    INTO v_estado, v_maquina_id
    FROM mes.lavado_maquina
    WHERE id = p_lavado_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lavado con ID % no encontrado.', p_lavado_id;
    END IF;
    IF v_estado <> 'EN_PROCESO' THEN
        RAISE EXCEPTION 'Solo se puede finalizar un lavado EN_PROCESO. Estado actual: %', v_estado;
    END IF;

    -- Register chemical consumption if provided
    IF p_datos->'consumos' IS NOT NULL AND jsonb_array_length(p_datos->'consumos') > 0 THEN
        SELECT id INTO v_egr_tipo_id
        FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

        -- Stock check
        WITH consumos AS (
            SELECT (i->>'item_id')::INT AS item_id, SUM((i->>'cantidad')::numeric) AS cantidad
            FROM jsonb_array_elements(p_datos->'consumos') i GROUP BY 1
        ),
        errores AS (
            SELECT c.item_id, it.nombre AS item_nombre, c.cantidad,
                   COALESCE(SUM(sa.cantidad_disponible), 0) AS cantidad_disponible
            FROM consumos c
            LEFT JOIN inventario.vw_stock_actual sa ON sa.item_id = c.item_id
            JOIN item it ON it.id = c.item_id
            GROUP BY c.item_id, it.nombre, c.cantidad
            HAVING COALESCE(SUM(sa.cantidad_disponible), 0) < c.cantidad
        )
        SELECT jsonb_agg(jsonb_build_object(
            'item_id', item_id, 'item_nombre', item_nombre,
            'saldo_disponible', cantidad_disponible, 'cantidad_requerida', cantidad
        ))
        INTO v_error_payload FROM errores;

        IF v_error_payload IS NOT NULL THEN
            RAISE EXCEPTION 'Stock insuficiente para registrar consumo de lavado'
                USING DETAIL = v_error_payload::text;
        END IF;

        -- FIFO resolution + movements
        v_consumos := mes.calcular_fifo(p_datos->'consumos');
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;
        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario,
            documento_tipo, documento_id, observacion
        )
        SELECT
            v_doc_movimiento_id,
            (v_consumo->>'item_id')::INT,
            (v_consumo->>'lote_id')::INT,
            v_egr_tipo_id,
            (v_consumo->>'ubicacion_id')::INT,
            (v_consumo->>'cantidad')::NUMERIC,
            (SELECT iv.precio_promedio FROM inventario.item_valoracion iv
             WHERE iv.item_id = (v_consumo->>'item_id')::INT),
            'LAVADO_MAQUINA',
            p_lavado_id,
            p_consumo->>'observacion'
        FROM jsonb_array_elements(v_consumos) v_consumo
        JOIN jsonb_array_elements(p_datos->'consumos') p_consumo
            ON v_consumo->>'item_id' = p_consumo->>'item_id';
    END IF;

    UPDATE mes.lavado_maquina
    SET estado  = 'COMPLETADO',
        fyh_fin = NOW(),
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE id = p_lavado_id;

    UPDATE mes.maquina SET estado_actual = 'espera' WHERE id = v_maquina_id;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Lavado Completado',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' completó lavado de maquina #%s', v_maquina_id), 'info',
           jsonb_build_object('objeto_tipo','lavado_maquina','lavado_id', p_lavado_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta') AND v_usr_id <> ur.user_id;

    RETURN format('Lavado #%s completado.', p_lavado_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in finalizar_lavado - User: %, ID: %, Error: %', v_usr_id, p_lavado_id, v_message;
    RAISE;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- mes.registrar_backfill_orden
-- Retroactively registers production for an already-created orden.
-- Iterates pasos in the caller-supplied order, calls iniciar_paso +
-- finalizar_paso for each (preserving all inventory egress side-effects),
-- then patches the real timestamps and optional backfill note.
--
-- p_data keys:
--   orden_produccion_id  INT     (required — for validation only)
--   pasos                ARRAY   (required, must be in secuencia order)
--     paso_id            BIGINT  (required)
--     fyh_inicio         TIMESTAMPTZ (required)
--     fyh_fin            TIMESTAMPTZ (required)
--     empleado_id        SMALLINT (optional — who performed the step)
--     maquina_asignada_id INT    (optional — pre-assign machine before iniciar)
--     consumos           ARRAY   (optional — same shape as finalizar_paso expects)
--     produccion         ARRAY   (optional — same shape as finalizar_paso expects)
--     observacion_backfill TEXT  (optional)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_backfill_orden(p_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id           INT := get_user_id();
    v_orden_id         INT;
    v_paso             JSONB;
    v_paso_id          BIGINT;
    v_paso_count       INT := 0;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_orden_id := (p_data->>'orden_produccion_id')::INT;

    IF v_orden_id IS NULL THEN
        RAISE EXCEPTION 'orden_produccion_id es requerido.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM mes.orden_produccion WHERE id = v_orden_id) THEN
        RAISE EXCEPTION 'Orden de producción % no encontrada.', v_orden_id;
    END IF;
    IF jsonb_array_length(p_data->'pasos') = 0 THEN
        RAISE EXCEPTION 'Se requiere al menos un paso en p_data.pasos.';
    END IF;

    FOR v_paso IN SELECT * FROM jsonb_array_elements(p_data->'pasos') LOOP
        v_paso_id := (v_paso->>'paso_id')::BIGINT;

        IF v_paso_id IS NULL THEN
            RAISE EXCEPTION 'Cada paso debe incluir paso_id.';
        END IF;
        IF (v_paso->>'fyh_inicio') IS NULL OR (v_paso->>'fyh_fin') IS NULL THEN
            RAISE EXCEPTION 'Cada paso debe incluir fyh_inicio y fyh_fin (paso_id=%).', v_paso_id;
        END IF;

        -- iniciar_paso enforces prerequisite ordering naturally via secuencia check.
        -- Passes empleado_id + maquina_asignada_id through p_datos.
        PERFORM mes.iniciar_paso(v_paso_id, v_paso);

        -- finalizar_paso handles consumos, produccion, machine release, and
        -- auto-finalizes the orden when all pasos are done.
        PERFORM mes.finalizar_paso(v_paso_id, v_paso);

        -- Patch real timestamps and backfill note over the NOW() values set above.
        UPDATE mes.orden_produccion_paso
        SET fyh_inicio           = (v_paso->>'fyh_inicio')::TIMESTAMPTZ,
            fyh_fin              = (v_paso->>'fyh_fin')::TIMESTAMPTZ,
            observacion_backfill = v_paso->>'observacion_backfill',
            usr_mod              = v_usr_id,
            fyh_mod              = NOW()
        WHERE id = v_paso_id;

        v_paso_count := v_paso_count + 1;
    END LOOP;

    RETURN format('Backfill completado: %s paso(s) registrados para orden %s.',
                  v_paso_count, v_orden_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_backfill_orden - User: %, Orden: %, Error: %',
              v_usr_id, v_orden_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.registrar_backfill_orden(JSONB) TO authenticated;

-- ── mes.vw_proyeccion_tenido ──────────────────────────────────
-- Machine schedule projection for any date (filter by fecha as needed).
--
-- Outputs offsets from each machine's shift start, NOT absolute wall-clock
-- times. The frontend adds its own hora_inicio per machine to get actual times:
--   wall_clock_start = hora_inicio_maquina + offset_inicio
--   wall_clock_end   = hora_inicio_maquina + offset_fin
--
-- A 20-minute break between consecutive batches is included in the offsets.
-- peso_produccion is computed relative to a 24-h window from shift start,
-- so it is also independent of hora_inicio.
--
-- EN_PROCESO items use now() for remaining time — only meaningful for today.
--
-- Duration source : mes.tiempos_estandar_tenido via assigned recipe
--                   (lookup key: valor × tenido × flg_antipilling)
-- Wash duration   : mes.tiempos_estandar_lavado via receta.lavado_maquina.tipo_lavado_mq_id
CREATE OR REPLACE VIEW mes.vw_proyeccion_tenido AS
WITH pasos AS (
    SELECT
        p.fecha,
        p.maquina_id,
        p.secuencia,
        'TENIDO'::text                                      AS tipo_registro,
        p.actividad_id,
        co.color,
        te.tenido,
        val.valor,
        rt.flg_antipilling,
        COALESCE((
            SELECT SUM(l.cantidad)
            FROM mes.orden_produccion_paso_item  oppi
            JOIN mes.orden_produccion_item       opi  ON opi.id = oppi.orden_produccion_item_id
            JOIN inventario.lote                 l    ON l.id   = opi.lote_id
            WHERE oppi.orden_produccion_paso_id = opp.id
        ), 0)::numeric                                      AS kilos,
        CASE
            WHEN opp.estado = 'EN_PROCESO' THEN
                GREATEST(interval '0',
                    te_std.duracion - (now() - opp.fyh_inicio))
            ELSE
                te_std.duracion
        END                                                 AS duracion,
        opp.fyh_inicio
    FROM mes.programacion                 p
    JOIN mes.orden_produccion_paso        opp    ON opp.id  = p.actividad_id
    JOIN receta.tenido                    rt     ON rt.id   = opp.receta_id
    JOIN color_x_cliente                  cxc    ON cxc.id  = rt.color_x_cliente_id
    LEFT JOIN color                       co     ON co.id   = cxc.color_id
    LEFT JOIN tenido                      te     ON te.id   = rt.tenido_id
    LEFT JOIN valor                       val    ON val.id  = cxc.valor_id
    LEFT JOIN mes.tiempos_estandar_tenido te_std
           ON te_std.valor_id        = cxc.valor_id
          AND te_std.tenido_id       = rt.tenido_id
          AND te_std.flg_antipilling = rt.flg_antipilling
          AND te_std.flg_activo      = true
    WHERE p.actividad_tipo  = 'ORDEN_PRODUCCION_PASO'
      AND opp.estado       IN ('PENDIENTE', 'EN_PROCESO')
      AND opp.receta_id     IS NOT NULL
),
lavados AS (
    SELECT
        p.fecha,
        p.maquina_id,
        p.secuencia,
        'LAVADO'::text  AS tipo_registro,
        p.actividad_id,
        NULL::text      AS color,
        NULL::text      AS tenido,
        NULL::text      AS valor,
        NULL::boolean   AS flg_antipilling,
        NULL::numeric   AS kilos,
        CASE
            WHEN lm.estado = 'EN_PROCESO' THEN
                GREATEST(interval '0', tel.duracion - (now() - lm.fyh_inicio))
            ELSE
                tel.duracion
        END             AS duracion,
        lm.fyh_inicio
    FROM mes.programacion             p
    JOIN mes.lavado_maquina           lm  ON lm.id                 = p.actividad_id
    JOIN receta.lavado_maquina        rlm ON rlm.id                = lm.receta_id
    LEFT JOIN mes.tiempos_estandar_lavado tel ON tel.tipo_lavado_mq_id = rlm.tipo_lavado_mq_id
                                            AND tel.flg_activo        = true
    WHERE p.actividad_tipo = 'LAVADO_MAQUINA'
      AND lm.estado IN ('PENDIENTE', 'EN_PROCESO')
),
union_total AS (
    SELECT * FROM pasos
    UNION ALL
    SELECT * FROM lavados
),
con_offsets AS (
    SELECT *,
        cumsum - COALESCE(duracion, interval '0') + break   AS offset_inicio,
        cumsum + break                                       AS offset_fin
    FROM (
        SELECT *,
            SUM(COALESCE(duracion, interval '0')) OVER (
                PARTITION BY maquina_id, fecha ORDER BY secuencia
            ) AS cumsum,
            -- 20-min break after each preceding item (none before the first)
            (ROW_NUMBER() OVER (
                PARTITION BY maquina_id, fecha ORDER BY secuencia
            ) - 1) * interval '20 minutes' AS break
        FROM union_total
    ) s
)
SELECT *,
    CASE
        WHEN tipo_registro = 'LAVADO'               THEN NULL
        WHEN offset_inicio >= interval '12 hours'   THEN 0
        WHEN offset_fin    <= interval '12 hours'   THEN kilos
        ELSE ROUND((
            EXTRACT(EPOCH FROM (interval '12 hours' - offset_inicio))
            / NULLIF(EXTRACT(EPOCH FROM duracion), 0)
            * kilos
        )::numeric, 2)
    END AS produccion_dia,
    CASE
        WHEN tipo_registro = 'LAVADO'               THEN NULL
        WHEN offset_inicio >= interval '24 hours'   THEN 0
        WHEN offset_fin    <= interval '24 hours'   THEN kilos
        ELSE ROUND((
            EXTRACT(EPOCH FROM (interval '24 hours' - offset_inicio))
            / NULLIF(EXTRACT(EPOCH FROM duracion), 0)
            * kilos
        )::numeric, 2)
    END AS produccion_total
FROM con_offsets
ORDER BY fecha, maquina_id, secuencia;

GRANT SELECT ON mes.vw_proyeccion_tenido TO authenticated;

-- ── mes.get_proyeccion_tenido ─────────────────────────────────
-- Returns the schedule projection for a given date with absolute
-- hora_inicio / hora_fin intervals from midnight, ready for display.
--
-- p_horas: per-machine shift start times as JSON object keyed by
--   maquina_id (text). Machines absent from the object default to 07:00.
--   Example: '{"1": "07:00", "2": "07:30", "5": "07:15"}'
--
-- hora_inicio / hora_fin are intervals from midnight so the frontend
-- can display them directly as wall-clock times without any math.
-- They may exceed 24h for items running into the next day.
--
-- produccion_dia / produccion_total come unchanged from the view.
CREATE OR REPLACE FUNCTION mes.get_proyeccion_tenido(
    p_fecha date,
    p_horas jsonb DEFAULT '{}'
)
RETURNS TABLE(
    fecha            date,
    maquina_id       int,
    secuencia        smallint,
    tipo_registro    text,
    actividad_id     bigint,
    color            text,
    tenido           text,
    valor            text,
    flg_antipilling  boolean,
    kilos            numeric,
    duracion         interval,
    fyh_inicio       timestamptz,
    hora_inicio      interval,
    hora_fin         interval,
    produccion_dia   numeric,
    produccion_total numeric
)
LANGUAGE sql STABLE AS
$$
    SELECT
        v.fecha,
        v.maquina_id,
        v.secuencia,
        v.tipo_registro,
        v.actividad_id,
        v.color,
        v.tenido,
        v.valor,
        v.flg_antipilling,
        v.kilos,
        v.duracion,
        v.fyh_inicio,
        -- Shift start for this machine (default 07:00 if not supplied)
        make_interval(
            hours => EXTRACT(hour   FROM COALESCE(
                (p_horas->>(v.maquina_id::text))::time, '07:00'::time
            ))::int,
            mins  => EXTRACT(minute FROM COALESCE(
                (p_horas->>(v.maquina_id::text))::time, '07:00'::time
            ))::int
        ) + v.offset_inicio                                 AS hora_inicio,
        make_interval(
            hours => EXTRACT(hour   FROM COALESCE(
                (p_horas->>(v.maquina_id::text))::time, '07:00'::time
            ))::int,
            mins  => EXTRACT(minute FROM COALESCE(
                (p_horas->>(v.maquina_id::text))::time, '07:00'::time
            ))::int
        ) + v.offset_fin                                    AS hora_fin,
        v.produccion_dia,
        v.produccion_total
    FROM mes.vw_proyeccion_tenido v
    WHERE v.fecha = p_fecha
    ORDER BY v.maquina_id, v.secuencia;
$$;

-- get_proyeccion_tenido is an internal helper; frontend calls mes.get_proyeccion.

-- ── mes.get_proyeccion ────────────────────────────────────────
-- Single entry point for the projection dashboard.
-- Returns { detail: [...], resumen: [...] } in one RPC call.
-- The MATERIALIZED CTE ensures get_proyeccion_tenido executes once;
-- both the detail array and the resumen aggregation read from the
-- same in-memory result set (PG12+ materializes CTEs referenced >1 time
-- automatically — the keyword makes that intent explicit).
CREATE OR REPLACE FUNCTION mes.get_proyeccion(
    p_fecha date,
    p_horas jsonb DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public', 'mes'
AS $$
    WITH base AS MATERIALIZED (
        SELECT * FROM mes.get_proyeccion_tenido(p_fecha, p_horas)
    ),
    resumen AS (
        SELECT
            m.id                                                AS maquina_id,
            m.codigo                                            AS maquina_codigo,
            m.nombre,
            COALESCE(ROUND(SUM(b.produccion_dia),   2), 0)     AS produccion_dia,
            COALESCE(ROUND(SUM(b.produccion_total), 2), 0)     AS produccion_total
        FROM base b
        JOIN mes.maquina m ON m.id = b.maquina_id
        GROUP BY ROLLUP((m.id, m.codigo, m.nombre))
        ORDER BY m.id NULLS LAST
    )
    SELECT jsonb_build_object(
        'detail',  COALESCE((SELECT jsonb_agg(row_to_json(b)) FROM base    b), '[]'),
        'resumen', COALESCE((SELECT jsonb_agg(row_to_json(r)) FROM resumen r), '[]')
    );
$$;

GRANT EXECUTE ON FUNCTION mes.get_proyeccion(date, jsonb) TO authenticated;

-- ── mes.set_tiempo_estandar_tenido ────────────────────────────
-- Upserts a dyeing standard time by deactivating the current active
-- entry (preserving history) and inserting a new one.
CREATE OR REPLACE FUNCTION mes.set_tiempo_estandar_tenido(
    p_valor_id        smallint,
    p_tenido_id       int,
    p_flg_antipilling boolean,
    p_duracion        interval
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'mes'
AS $$
DECLARE
    v_usr_id  int := get_user_id();
    v_old_id  smallint;
    v_new_id  smallint;
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE mes.tiempos_estandar_tenido
    SET    flg_activo = false,
           usr_mod    = v_usr_id,
           fyh_mod    = NOW()
    WHERE  valor_id        = p_valor_id
      AND  tenido_id       = p_tenido_id
      AND  flg_antipilling = p_flg_antipilling
      AND  flg_activo      = true
    RETURNING id INTO v_old_id;

    INSERT INTO mes.tiempos_estandar_tenido
        (valor_id, tenido_id, flg_antipilling, duracion, flg_activo, usr_cre)
    VALUES
        (p_valor_id, p_tenido_id, p_flg_antipilling, p_duracion, true, v_usr_id)
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'id',          v_new_id,
        'anterior_id', v_old_id,
        'duracion',    p_duracion::text
    );
END;
$$;

GRANT EXECUTE ON FUNCTION mes.set_tiempo_estandar_tenido(smallint, int, boolean, interval) TO authenticated;

-- ── mes.set_tiempo_estandar_lavado ────────────────────────────
-- Upserts a wash cycle standard time by deactivating the current
-- active entry (preserving history) and inserting a new one.
CREATE OR REPLACE FUNCTION mes.set_tiempo_estandar_lavado(
    p_tipo_lavado_mq_id smallint,
    p_duracion          interval
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'mes'
AS $$
DECLARE
    v_usr_id  int := get_user_id();
    v_old_id  smallint;
    v_new_id  smallint;
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE mes.tiempos_estandar_lavado
    SET    flg_activo = false,
           usr_mod    = v_usr_id,
           fyh_mod    = NOW()
    WHERE  tipo_lavado_mq_id = p_tipo_lavado_mq_id
      AND  flg_activo        = true
    RETURNING id INTO v_old_id;

    INSERT INTO mes.tiempos_estandar_lavado
        (tipo_lavado_mq_id, duracion, flg_activo, usr_cre)
    VALUES
        (p_tipo_lavado_mq_id, p_duracion, true, v_usr_id)
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'id',          v_new_id,
        'anterior_id', v_old_id,
        'duracion',    p_duracion::text
    );
END;
$$;

GRANT EXECUTE ON FUNCTION mes.set_tiempo_estandar_lavado(smallint, interval) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- 35. VIEWS: tiempos estándar con etiquetas
-- ═══════════════════════════════════════════════════════════════

-- ── mes.vw_tiempos_estandar_tenido ────────────────────────────
-- Active and historical standard dyeing times with human-readable labels.
-- flg_activo = true → currently in use; false → historical (superseded).
CREATE OR REPLACE VIEW mes.vw_tiempos_estandar_tenido AS
SELECT
    te.id,
    te.valor_id,
    val.valor           AS valor,
    te.tenido_id,
    t.tenido            AS tenido,
    te.flg_antipilling,
    te.duracion,
    te.flg_activo,
    te.fyh_cre,
    te.fyh_mod
FROM mes.tiempos_estandar_tenido te
JOIN valor  val ON val.id = te.valor_id
JOIN tenido t   ON t.id  = te.tenido_id
ORDER BY val.valor, t.tenido, te.flg_antipilling, te.flg_activo DESC, te.id DESC;

GRANT SELECT ON mes.vw_tiempos_estandar_tenido TO authenticated;

-- ── mes.vw_tiempos_estandar_lavado ────────────────────────────
-- Active and historical standard wash-cycle times with human-readable labels.
CREATE OR REPLACE VIEW mes.vw_tiempos_estandar_lavado AS
SELECT
    te.id,
    te.tipo_lavado_mq_id,
    tlm.nombre          AS tipo_lavado_maquina,
    te.duracion,
    te.flg_activo,
    te.fyh_cre,
    te.fyh_mod
FROM mes.tiempos_estandar_lavado te
JOIN tipo_lavado_maquina tlm ON tlm.id = te.tipo_lavado_mq_id
ORDER BY tlm.nombre, te.flg_activo DESC, te.id DESC;

GRANT SELECT ON mes.vw_tiempos_estandar_lavado TO authenticated;
GRANT SELECT ON mes.maquina TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- ANULAR PRODUCCION
-- Reverses a completed production paso:
--   - Posts PROD_ING_REV for each output lote (removes from stock)
--   - Posts PROD_CONSUMO_REV for each input lote (restores to stock)
--   - Soft-deletes output lotes + their lote_rollo_detalle rows
--   - Resets paso → EN_PROCESO, orden → EN_PROCESO
--
-- Guard: fails if any output lote has downstream movements
--        (SERV_EGR, VENTA_EGR, etc.) — those must be reversed first.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.anular_produccion(p_orden_paso_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','mes','doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_orden_id          bigint;
    v_estado            orden_produccion_paso_estado_enum;
    v_ing_rev_id        smallint;
    v_consumo_rev_id    smallint;
    v_doc_movimiento_id bigint;
    v_output_count      int;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Paso must exist and be COMPLETADO
    SELECT opp.estado, opp.orden_produccion_id
    INTO v_estado, v_orden_id
    FROM mes.orden_produccion_paso opp
    WHERE opp.id = p_orden_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso #% no encontrado.', p_orden_paso_id;
    END IF;
    IF v_estado <> 'COMPLETADO' THEN
        RAISE EXCEPTION 'Solo se puede anular un paso COMPLETADO. Estado actual: %', v_estado;
    END IF;

    -- 2. Guard: no downstream movements on output lotes
    IF EXISTS (
        SELECT 1
        FROM inventario.lote l
        JOIN inventario.item_movimientos im     ON im.lote_id = l.id
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE l.documento_tipo = 'ORDEN_PRODUCCION_PASO'
          AND l.documento_id   = p_orden_paso_id
          AND l.flg_elm        = false
          AND imt.codigo NOT IN ('PROD_ING', 'PROD_ING_REV')
    ) THEN
        RAISE EXCEPTION
            'No se puede anular el paso #%: uno o más lotes de salida ya tienen movimientos posteriores (despacho, ajuste, etc.). Anule esos documentos primero.',
            p_orden_paso_id;
    END IF;

    -- 3. Lock rows
    PERFORM 1 FROM inventario.lote
    WHERE documento_tipo = 'ORDEN_PRODUCCION_PASO' AND documento_id = p_orden_paso_id
    FOR UPDATE;

    PERFORM 1 FROM mes.orden_produccion WHERE id = v_orden_id FOR UPDATE;

    -- 4. Fetch reversal movement type IDs
    SELECT id INTO v_ing_rev_id     FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING_REV';
    SELECT id INTO v_consumo_rev_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV';

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- 5. PROD_ING_REV: reverse ingress of output lotes
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad, documento_tipo, documento_id
    )
    SELECT
        v_doc_movimiento_id,
        l.item_id,
        l.id,
        v_ing_rev_id,
        sa.ubicacion_id,
        l.cantidad,
        'ORDEN_PRODUCCION_PASO',
        p_orden_paso_id
    FROM inventario.lote l
    JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id
    WHERE l.documento_tipo = 'ORDEN_PRODUCCION_PASO'
      AND l.documento_id   = p_orden_paso_id
      AND l.flg_elm        = false;

    GET DIAGNOSTICS v_output_count = ROW_COUNT;

    -- 6. PROD_CONSUMO_REV: restore input lotes consumed by this paso
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id
    )
    SELECT
        v_doc_movimiento_id,
        opi.item_id,
        opi.lote_id,
        v_consumo_rev_id,
        opi.ubicacion_id,
        l.cantidad,
        'ORDEN_PRODUCCION_PASO',
        p_orden_paso_id
    FROM mes.orden_produccion_paso_item oppi
    JOIN mes.orden_produccion_item opi ON opi.id = oppi.orden_produccion_item_id
    JOIN inventario.lote l             ON l.id   = opi.lote_id
    WHERE oppi.orden_produccion_paso_id = p_orden_paso_id;

    -- 7. Soft-delete output lotes + their batch classification rows
    UPDATE inventario.lote
    SET flg_elm = true, usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE documento_tipo = 'ORDEN_PRODUCCION_PASO'
      AND documento_id   = p_orden_paso_id
      AND flg_elm        = false;

    DELETE FROM inventario.lote_rollo_detalle
    WHERE lote_id IN (
        SELECT id FROM inventario.lote
        WHERE documento_tipo = 'ORDEN_PRODUCCION_PASO'
          AND documento_id   = p_orden_paso_id
    );

    -- 8. Reset paso back to EN_PROCESO
    UPDATE mes.orden_produccion_paso
    SET estado  = 'EN_PROCESO',
        fyh_fin = NULL
    WHERE id = p_orden_paso_id;

    -- 9. Reset orden back to EN_PROCESO if it was auto-completed
    UPDATE mes.orden_produccion
    SET estado = 'EN_PROCESO', fyh_fin = NULL
    WHERE id = v_orden_id AND estado = 'FINALIZADA';

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_produccion', v_usr_id, jsonb_build_object('orden_paso_id', p_orden_paso_id));

    RETURN format('Producción del paso #% anulada: % lotes de salida revertidos.', p_orden_paso_id, v_output_count);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_produccion - User: %, paso: %, Error: %, Detail: %',
              v_usr_id, p_orden_paso_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.anular_produccion(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_pesos_orden_items(BIGINT, NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_pesos_individuales_orden(BIGINT, JSONB) TO authenticated;
GRANT USAGE on SCHEMA mes TO authenticated;

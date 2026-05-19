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
        'paso_id',                   pp.id,
        'operacion',                 o.nombre,
        'operacion_codigo',          o.codigo,
        'paso_estado',               COALESCE((
                                         SELECT CASE
                                             WHEN bool_or(pe.estado = 'COMPLETADO') THEN 'COMPLETADO'
                                             WHEN bool_or(pe.estado = 'EN_PROCESO')  THEN 'EN_PROCESO'
                                             WHEN bool_or(pe.estado = 'OMITIDO')     THEN 'OMITIDO'
                                             ELSE 'PENDIENTE'
                                         END
                                         FROM mes.partida_paso_ejecucion pe
                                         WHERE pe.partida_paso_id = pp.id
                                     ), 'PENDIENTE'),
        'partida_id',                  p.id,
        'partida_id',                p.id,
        'partida_codigo',            EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
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
        -- Lavado maquina fields (null when actividad_tipo = 'partida_paso')
        'lavado_id',                 lm.id,
        'lavado_estado',             lm.estado,
        'receta_lavado_maquina_id',  lm.receta_id  -- FIX BUG5: was lm.receta_lavado_maquina_id (old column name)
    ) AS row_obj
    FROM mes.programacion prog
    LEFT JOIN mes.partida_paso pp  ON prog.actividad_tipo = 'partida_paso' AND pp.id = prog.actividad_id
    LEFT JOIN mes.operacion o       ON o.id = pp.operacion_id
    LEFT JOIN mes.partida p         ON p.id = pp.partida_id
    LEFT JOIN tenido t              ON t.id = p.tenido_id
    LEFT JOIN tercero c             ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc         ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN vw_partida_resumen_tenido vpa ON vpa.partida_id = p.id
    LEFT JOIN mes.lavado_maquina lm ON prog.actividad_tipo = 'LAVADO_MAQUINA' AND lm.id = prog.actividad_id
    WHERE prog.fecha = p_fecha
    ORDER BY prog.maquina_id, prog.secuencia
) sub;
$$;

-- Legacy name kept for backward compatibility — now delegates to get_actividades_sin_programar
-- Returns only partida_paso type (same shape as before for existing consumers)
CREATE OR REPLACE FUNCTION mes.get_pasos_sin_programar()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes'
AS $$
SELECT COALESCE(jsonb_agg(row_obj), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'actividad_tipo',     'partida_paso',
        'paso_id',            pp.id,
        'partida_id',           p.id,
        'operacion',          o.nombre,
        'operacion_codigo',   o.codigo,
        'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'articulo_tipo_id',   p.articulo_tipo_id,
        'fibra',              p.fibra,
        'cliente',            c.nombre,
        'color',              vc.color,
        'color_hex',          vc.color_hex,
        'tono',               vc.tono,
        'tenido',             t.tenido
    ) AS row_obj
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    JOIN mes.partida p   ON p.id = pp.partida_id
    LEFT JOIN tenido t   ON t.id = p.tenido_id
    LEFT JOIN tercero c  ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('EN_PROCESO','COMPLETADO','OMITIDO')
      )
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog
          WHERE prog.actividad_tipo = 'partida_paso' AND prog.actividad_id = pp.id
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
            'actividad_tipo',     'partida_paso',
            'actividad_id',       pp.id,
            'paso_id',            pp.id,
            'partida_id',           p.id,
            'operacion',          o.nombre,
            'operacion_codigo',   o.codigo,
            'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
            'articulo_tipo_id',   p.articulo_tipo_id,
            'cliente',            c.nombre,
            'color',              vc.color,
            'color_hex',          vc.color_hex,
            'tono',               vc.tono,
            'tenido',             t.tenido
        ) AS row_obj
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    JOIN mes.partida p   ON p.id = pp.partida_id
    LEFT JOIN tenido t   ON t.id = p.tenido_id
    LEFT JOIN tercero c  ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('EN_PROCESO','COMPLETADO','OMITIDO')
      )
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog
          WHERE prog.actividad_tipo = 'partida_paso' AND prog.actividad_id = pp.id
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
    SELECT jsonb_agg(jsonb_build_object('actividad_id', pp.id))
    INTO v_invalid_pasos
    FROM jsonb_array_elements(p_programaciones) elem
    JOIN mes.partida_paso pp ON pp.id = (elem->>'actividad_id')::BIGINT
    WHERE elem->>'actividad_tipo' = 'partida_paso'
      AND EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id
            AND pe.estado IN ('COMPLETADO', 'OMITIDO')
      );

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
    {"partida_paso_id": 12, "maquina_id": 1, "secuencia": 1, "nota": null},
    {"partida_paso_id": 14, "maquina_id": 1, "secuencia": 2, "nota": null},
    {"partida_paso_id": 45, "maquina_id": 2, "secuencia": 1, "nota": null},
    {"partida_paso_id": 50, "maquina_id": 2, "secuencia": 2, "nota": null}
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
RETURNS jsonb
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
    v_partida_id         bigint;
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
    SELECT pp.receta_id, pp.maquina_planificada_id, COALESCE(pp.relacion_bano_objetivo, m.relacion_bano),
           pp.partida_id, o.nombre
    INTO v_receta_id, v_maquina_id, v_rb, v_partida_id, v_op_nombre
    FROM mes.partida_paso pp
    LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
    LEFT JOIN mes.maquina m   ON m.id = pp.maquina_planificada_id
    WHERE pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;
    IF v_receta_id IS NULL THEN
        RAISE EXCEPTION 'Paso ID % sin receta asignada.', p_paso_id;
    END IF;

    -- 2. Machine info
    SELECT m.nombre, m.codigo INTO v_maq_nombre, v_maq_codigo
    FROM mes.maquina m WHERE m.id = v_maquina_id;

    -- 3. Roll aggregation (weight + count) from all components of this order
    SELECT
        SUM(l.cantidad),
        SUM(CASE ird.flg_rib WHEN false THEN 1 ELSE 0 END),
        SUM(CASE ird.flg_rib WHEN true  THEN 1 ELSE 0 END)
    INTO v_peso, v_cantidad_regular, v_cantidad_rib
    FROM mes.partida_componente opi
    JOIN inventario.lote l    ON l.id   = opi.lote_id
    JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
    WHERE opi.partida_id = v_partida_id;

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
        'receta_id',         pp.receta_id,
        'partida_id',        p.id,
        'tercero_id',        p.tercero_id,
        'cliente',           cli.nombre,
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
    FROM mes.partida_paso pp
    JOIN receta.tenido r     ON r.id   = pp.receta_id
    JOIN mes.partida p       ON p.id   = pp.partida_id
    LEFT JOIN tipo_receta tr ON tr.id  = r.tipo_receta_id
    JOIN articulo_tipo at    ON at.id  = r.articulo_tipo_id
    LEFT JOIN tercero cli    ON cli.id = p.tercero_id
    WHERE pp.id = p_paso_id;

    -- Write scaled chemical reservations into partida_componente (RESB chemical rows)
    DELETE FROM mes.partida_componente
    WHERE partida_paso_id = p_paso_id AND item_id IS NOT NULL;

    INSERT INTO mes.partida_componente (partida_id, item_id, partida_paso_id, cantidad_reservada, usr_cre)
    SELECT v_partida_id,
           rtpi.item_id,
           p_paso_id,
           CASE
               WHEN iid.medida = 'g/L' THEN rtpi.cantidad * v_volumen * iid.factor_stock
               WHEN iid.medida = '%'   THEN rtpi.cantidad * v_peso * 10 * iid.factor_stock
           END,
           v_usr_id
    FROM receta.tenido_paso rtp
    JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id  = rtp.id
    JOIN item_insumo_detalle iid        ON iid.item_id   = rtpi.item_id
    WHERE rtp.receta_id = v_receta_id;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Receta Generada',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' generó la receta del paso %s (orden #%s)', v_op_nombre, v_partida_id), 'info',
           jsonb_build_object('objeto_tipo','partida_paso','paso_id', p_paso_id, 'partida_id', v_partida_id)
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_partida_id        bigint;
    v_op_nombre       text;
    v_secuencia       smallint;
    v_requiere_receta boolean;
    v_requiere_maquina boolean;
    v_receta_id       int;
    v_ejecucion_id    bigint;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT pp.partida_id, o.nombre, pp.secuencia, o.requiere_receta, o.requiere_maquina, pp.receta_id
    INTO v_partida_id, v_op_nombre, v_secuencia, v_requiere_receta, v_requiere_maquina, v_receta_id
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    WHERE pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;

    -- Guard: paso already has an active or completed run
    IF EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = p_paso_id AND estado IN ('EN_PROCESO','OMITIDO')
    ) THEN
        RAISE EXCEPTION 'El paso % ya tiene una ejecución en curso o fue omitido.', v_op_nombre;
    END IF;

    IF v_requiere_receta AND v_receta_id IS NULL THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque no tiene receta asignada.', v_op_nombre;
    END IF;
    IF v_requiere_maquina AND (p_datos->>'maquina_id') IS NULL THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque no se proporcionó una máquina.', v_op_nombre;
    END IF;

    -- Guard: previous pasos in sequence must be complete and have no active run
    IF EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        WHERE pp.partida_id = v_partida_id
          AND pp.secuencia < v_secuencia
          AND (
              NOT EXISTS (
                  SELECT 1 FROM mes.partida_paso_ejecucion pe
                  WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('COMPLETADO','OMITIDO')
              )
              OR EXISTS (
                  SELECT 1 FROM mes.partida_paso_ejecucion pe
                  WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
              )
          )
    ) THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque hay pasos anteriores no completados o en ejecución.', v_op_nombre;
    END IF;

    IF v_requiere_receta AND NOT EXISTS (
        SELECT 1 FROM mes.partida_componente WHERE partida_id = v_partida_id
    ) THEN
        RAISE EXCEPTION 'No se puede iniciar el paso % porque la orden no tiene rollos asignados.', v_op_nombre;
    END IF;

    -- Create execution run record
    INSERT INTO mes.partida_paso_ejecucion(partida_paso_id, estado, maquina_id, empleado_id, fyh_inicio, programacion_id, usr_cre)
    VALUES (
        p_paso_id, 'EN_PROCESO',
        (p_datos->>'maquina_id')::INT,
        (p_datos->>'empleado_id')::SMALLINT,
        NOW(),
        (p_datos->>'programacion_id')::BIGINT,
        v_usr_id
    )
    RETURNING id INTO v_ejecucion_id;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    -- Update machine state
    IF (p_datos->>'maquina_id') IS NOT NULL THEN
        UPDATE mes.maquina SET estado_actual = 'activa'
        WHERE id = (p_datos->>'maquina_id')::INT;
    END IF;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Paso Iniciado',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' inició el paso %s (orden #%s)', v_op_nombre, v_partida_id), 'info',
           jsonb_build_object('objeto_tipo','partida_paso','paso_id', p_paso_id, 'partida_id', v_partida_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','supervisor_produccion') AND v_usr_id <> ur.user_id;

    RETURN jsonb_build_object(
        'ejecucion_id', v_ejecucion_id,
        'message', format('Paso %s (#%s) iniciado correctamente.', v_op_nombre, p_paso_id)
    );
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
    v_ejecucion_id      BIGINT;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT pe.id INTO v_ejecucion_id
    FROM mes.partida_paso_ejecucion pe
    WHERE pe.partida_paso_id = p_paso_id AND pe.estado = 'EN_PROCESO'
    ORDER BY pe.fyh_inicio DESC LIMIT 1;

    IF v_ejecucion_id IS NULL THEN
        RAISE EXCEPTION 'Paso #% no tiene una ejecución EN_PROCESO activa.', p_paso_id;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_consumo_paso', v_usr_id, jsonb_build_object('paso_id', p_paso_id, 'ejecucion_id', v_ejecucion_id, 'consumos', p_consumos));

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
        COALESCE(sg.cantidad_total, 0) AS cantidad_disponible
    FROM consumos c
    LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = c.item_id
    JOIN item it ON it.id = c.item_id
    WHERE COALESCE(sg.cantidad_total, 0) < c.cantidad
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
            documento_tipo, documento_id, motivo_id, observacion
        ) SELECT
            v_doc_movimiento_id,
            (v_consumo->>'item_id')::INT,
            (v_consumo->>'lote_id')::INT,
            v_egr_tipo_id,
            (v_consumo->>'ubicacion_id')::INT,
            (v_consumo->>'cantidad')::NUMERIC,
            (SELECT iv.precio_promedio FROM inventario.item_valoracion iv
             WHERE iv.item_id = (v_consumo->>'item_id')::INT),
            'partida_paso_ejecucion',
            v_ejecucion_id,
            (p_consumo->>'motivo_id')::SMALLINT,
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
-- 23b. REGISTRAR MATIZADO — named operator transaction
--      Thin wrapper: resolves MATIZADO motivo internally so callers
--      never need to know or pass a raw motivo_id.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_matizado(p_paso_id BIGINT, p_consumos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes'
AS $function$
DECLARE
    v_augmented jsonb;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT jsonb_agg(item || jsonb_build_object('motivo_id', m.id))
    INTO v_augmented
    FROM jsonb_array_elements(p_consumos) AS item
    CROSS JOIN (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO') m;

    RETURN mes.registrar_consumo_paso(p_paso_id, v_augmented);
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.registrar_matizado(BIGINT, jsonb) TO authenticated;



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
        FROM inventario.vw_stock_lotes_ubicacion st
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



-- Moved to inventario.corregir_pesaje_produccion (funciones/inventario.sql).
-- Kept as DROP only to remove any stale deployment of the old mes-schema version.
DROP FUNCTION IF EXISTS mes.actualizar_pesos_partida_items(BIGINT, NUMERIC);
DROP FUNCTION IF EXISTS mes.actualizar_pesos_partida_items(BIGINT, NUMERIC, NUMERIC);
 
CREATE OR REPLACE FUNCTION mes.actualizar_pesos_individuales_partida(
    p_partida_id  BIGINT,
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
    v_estado            partida_estado_produccion_enum;
    v_count             int;
    v_pesaje_pos_id     smallint;
    v_pesaje_neg_id     smallint;
    v_doc_movimiento_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado_produccion INTO v_estado
    FROM mes.partida WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden de producción con ID % no encontrada.', p_partida_id;
    END IF;
    IF v_estado IN ('TECO', 'CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden modificar pesos de una orden en estado %.', v_estado;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_pesos_individuales_partida', v_usr_id,
            jsonb_build_object('partida_id', p_partida_id, 'items', p_items));

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
        JOIN mes.partida_componente opi ON opi.id = ii.opi_id
            AND opi.partida_id = p_partida_id
        JOIN inventario.lote l ON l.id = opi.lote_id AND l.item_id = opi.item_id
        JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    ),
    pesajes AS (
        INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, usr_cre)
        SELECT ld.lote_id, 'CORRECCION', ld.peso_nuevo, v_usr_id
        FROM lotes_data ld
        ON CONFLICT (lote_id) DO UPDATE
            SET peso_real = EXCLUDED.peso_real,
                tipo      = EXCLUDED.tipo
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
            'partida', p_partida_id
        FROM lotes_data ld
        JOIN pesajes p ON p.lote_id = ld.lote_id
        WHERE ld.diferencia <> 0
    )
    UPDATE inventario.lote l
    SET cantidad = ld.peso_nuevo
    FROM lotes_data ld
    WHERE l.id = ld.lote_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN format('%s pesos actualizados individualmente para orden #%s.', v_count, p_partida_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
        v_hint = PG_EXCEPTION_HINT, v_context = PG_EXCEPTION_CONTEXT,
        v_sqlstate = RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_pesos_individuales_partida - User: %, orden: %, Error: %, Detail: %',
              v_usr_id, p_partida_id, v_message, v_detail;
    RAISE;
END;
$function$;



-- UPDATE mes.partida
-- SET estado = 'EN_PROCESO'
-- WHERE id=8098;
-- UPDATE mes.partida_paso
-- SET estado = 'PENDIENTE'
-- WHERE fyh_inicio::date=now()::date and secuencia=3
-- RETURNING id;

-- SELECT id FROM mes.partida_paso WHERE id = 4488;

-- UPDATE mes.partida_paso pp SET estado='PENDIENTE' WHERE partida_id =8099 AND secuencia =4
-- SELECT * FROM inventario.item_movimientos WHERE documento_tipo='partida_paso' AND documento_id=4488;

-- ═══════════════════════════════════════════════════════════════
-- 24. REGISTRAR ITEMS PROCESADOS EN PASO (DEPRECATED)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_items_procesados(p_paso_id BIGINT, p_items jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes'
AS $function$
BEGIN
    RAISE EXCEPTION 'registrar_items_procesados está deprecado. El asignación de rollos es automática al iniciar el paso.'
        USING ERRCODE = 'feature_not_supported';
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- 25. REGISTRAR PRODUCCION (create output lotes)
-- ═══════════════════════════════════════════════════════════════
-- p_datos shape: {output: [{input_lote_id, peso_salida?}, ...], ubicacion_id, peso_rollos?, peso_rib?}
CREATE OR REPLACE FUNCTION mes.registrar_produccion(p_ejecucion_id BIGINT, p_datos JSONB)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','mes','doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
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
    v_flg_rib               BOOLEAN;
    v_lote_cantidad         NUMERIC;
    -- Distributed weight per roll when totals are provided
    v_count_regular         INT;
    v_count_rib             INT;
    v_peso_por_regular      NUMERIC;
    v_peso_por_rib          NUMERIC;
    -- True when peso_salida came from a physical measurement (per-roll), not prorated
    v_peso_salida_is_medido BOOLEAN;
    -- Partida attributes copied to each output lrd row
    v_partida_ancho             TEXT;
    v_partida_malla             TEXT;
    v_partida_rendimiento       TEXT;
    v_partida_color_x_cliente   INT;
    v_partida_tenido_id         INT;
    v_partida_flg_antipilling   BOOLEAN;
    v_p_output                  JSONB;
    v_ubicacion_id              INT;
    v_peso_rollos               NUMERIC;
    v_peso_rib                  NUMERIC;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_p_output    := p_datos->'output';
    v_ubicacion_id := (p_datos->>'ubicacion_id')::INT;
    v_peso_rollos  := (p_datos->>'peso_rollos')::NUMERIC;
    v_peso_rib     := (p_datos->>'peso_rib')::NUMERIC;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_produccion', v_usr_id, p_datos || jsonb_build_object('ejecucion_id', p_ejecucion_id));

    -- 1. Resolve partida from the execution run
    SELECT pp.partida_id
    INTO v_partida_id
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    WHERE pe.id = p_ejecucion_id AND pe.estado = 'EN_PROCESO';
    v_partida_id := v_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ejecución #% no encontrada o no está EN_PROCESO.', p_ejecucion_id;
    END IF;

    PERFORM 1 FROM mes.partida_detalle WHERE partida_id = v_partida_id FOR UPDATE;

    -- Lock existing output lotes for this execution run
    PERFORM 1 FROM inventario.lote
    WHERE documento_tipo = 'partida_paso_ejecucion' AND documento_id = p_ejecucion_id
    FOR UPDATE;

    -- Lock input roll lotes to prevent concurrent consumption
    PERFORM 1
    FROM inventario.lote l
    JOIN mes.partida_componente pc ON pc.lote_id = l.id
    WHERE pc.partida_id = v_partida_id
    FOR UPDATE OF l;

    PERFORM 1 FROM mes.partida WHERE id = v_partida_id FOR UPDATE;

    -- 2. Validate all input_lote_ids belong to this partida
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_p_output) i
        WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_componente pc
            WHERE pc.partida_id = v_partida_id
              AND pc.lote_id = (i->>'input_lote_id')::INT
        )
    ) THEN
        RAISE EXCEPTION 'Uno o más input_lote_id no pertenecen a esta orden.';
    END IF;

    SELECT id INTO v_ing_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING';
    SELECT id INTO v_egr_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

    -- Fetch partida attributes once; copied to every output lrd row
    SELECT ancho, malla, rendimiento, color_x_cliente_id, tenido_id, flg_antipilling
    INTO v_partida_ancho, v_partida_malla, v_partida_rendimiento,
         v_partida_color_x_cliente, v_partida_tenido_id, v_partida_flg_antipilling
    FROM mes.partida WHERE id = v_partida_id;

    -- If total weights provided, pre-count rib vs regular output rolls and compute per-roll weight
    IF v_peso_rollos IS NOT NULL OR v_peso_rib IS NOT NULL THEN
        SELECT
            COUNT(*) FILTER (WHERE ird.flg_rib = false),
            COUNT(*) FILTER (WHERE ird.flg_rib = true)
        INTO v_count_regular, v_count_rib
        FROM jsonb_array_elements(v_p_output) i
        JOIN inventario.lote l      ON l.id = (i->>'input_lote_id')::INT
        JOIN item_rollo_detalle ird ON ird.item_id = l.item_id;

        IF v_peso_rollos IS NOT NULL THEN
            IF v_count_regular = 0 THEN
                RAISE EXCEPTION 'Se proporcionó peso_rollos pero no hay rollos regulares en el output.';
            END IF;
            v_peso_por_regular := ROUND(v_peso_rollos / v_count_regular, 4);
        END IF;
        IF v_peso_rib IS NOT NULL THEN
            IF v_count_rib = 0 THEN
                RAISE EXCEPTION 'Se proporcionó peso_rib pero no hay rollos rib en el output.';
            END IF;
            v_peso_por_rib := ROUND(v_peso_rib / v_count_rib, 4);
        END IF;
    END IF;

    -- Single posting id shared by backflush + output movements
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- 4a. Backflush: consume input rolls assigned to this execution run
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad,
        documento_tipo, documento_id
    )
    SELECT
        v_doc_movimiento_id,
        l.item_id,
        pc.lote_id,
        v_egr_tipo_id,
        sa.ubicacion_id,
        l.cantidad,
        'partida_paso_ejecucion',
        p_ejecucion_id
    FROM (SELECT DISTINCT (i->>'input_lote_id')::INT AS lote_id FROM jsonb_array_elements(v_p_output) i) inp
    JOIN mes.partida_componente pc ON pc.lote_id = inp.lote_id AND pc.partida_id = v_partida_id
    JOIN inventario.lote l ON l.id = pc.lote_id
    LEFT JOIN LATERAL (
        SELECT ubicacion_id FROM inventario.vw_stock_lotes_ubicacion WHERE lote_id = pc.lote_id LIMIT 1
    ) sa ON true;

    GET DIAGNOSTICS v_consumed = ROW_COUNT;

    -- 4b. Create output lotes (same item_id as input), PROD_ING movements,
    --     and lote_rollo_detalle carrying guia_remision_id forward.
    FOR v_elem IN SELECT value FROM jsonb_array_elements(v_p_output)
    LOOP
        v_input_lote_id := (v_elem->>'input_lote_id')::INT;

        -- Inherit item_id, propietario, billing anchor, rib flag, and original quantity from input lote
        SELECT l.item_id, l.propietario_id, lrd.guia_remision_id, ird.flg_rib, l.cantidad
        INTO v_out_item_id, v_out_propietario, v_guia_remision_id, v_flg_rib, v_lote_cantidad
        FROM inventario.lote l
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
        JOIN item_rollo_detalle ird             ON ird.item_id = l.item_id
        WHERE l.id = v_input_lote_id;

        -- Resolve output weight.
        -- Totals param (prorated) takes precedence over per-roll peso_salida.
        -- v_peso_salida_is_medido: true only when weight is a physical measurement,
        -- not a prorated calculation — drives whether a pesaje audit record is created.
        IF v_flg_rib AND v_peso_por_rib IS NOT NULL THEN
            v_peso_salida         := v_peso_por_rib;
            v_peso_salida_is_medido := false;
        ELSIF NOT v_flg_rib AND v_peso_por_regular IS NOT NULL THEN
            v_peso_salida         := v_peso_por_regular;
            v_peso_salida_is_medido := false;
        ELSE
            v_peso_salida         := (v_elem->>'peso_salida')::NUMERIC;
            v_peso_salida_is_medido := true;
        END IF;

        IF v_peso_salida IS NULL THEN
            IF v_lote_cantidad IS NULL THEN
                RAISE EXCEPTION 'Falta peso_salida para el lote de entrada #%. Proporcione peso_salida en el array o use p_peso_rollos/p_peso_rib.', v_input_lote_id;
            END IF;
            v_peso_salida := v_lote_cantidad;
            v_peso_salida_is_medido := false;
        END IF;

        INSERT INTO inventario.lote(item_id, documento_tipo, documento_id, cantidad, propietario_id)
        VALUES (v_out_item_id, 'partida_paso_ejecucion', p_ejecucion_id, v_peso_salida, v_out_propietario)
        RETURNING id INTO v_new_lote_id;

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            destino_ubicacion_id, cantidad, documento_tipo, documento_id
        )
        VALUES (v_doc_movimiento_id, v_out_item_id, v_new_lote_id, v_ing_tipo_id,
                v_ubicacion_id, v_peso_salida, 'partida_paso_ejecucion', p_ejecucion_id);

        -- Batch classification: carry ingress guia + parent-batch link forward;
        -- populate dyeing identity from partida.
        INSERT INTO inventario.lote_rollo_detalle(
            lote_id, guia_remision_id, origen_lote_id,
            ancho, malla, rendimiento,
            color_x_cliente_id, tenido_id,
            flg_tenido, flg_antipilling
        )
        VALUES (
            v_new_lote_id, v_guia_remision_id, v_input_lote_id,
            v_partida_ancho, v_partida_malla, v_partida_rendimiento,
            v_partida_color_x_cliente, v_partida_tenido_id,
            true, v_partida_flg_antipilling
        );

        -- Output weighing audit: only when weight was physically measured per-roll,
        -- not when prorated from p_peso_rollos/p_peso_rib totals.
        IF v_peso_salida_is_medido THEN
            INSERT INTO inventario.pesaje(lote_id, tipo, peso_real, usr_cre)
            VALUES (v_new_lote_id, 'SALIDA', v_peso_salida, v_usr_id);
        END IF;
    END LOOP;

    -- 5. Sync confirmed roll count onto the order item (idempotent: overwrites to current lote count)
    UPDATE mes.partida_detalle pd
    SET cantidad_producida = sub.total,
        usr_mod            = v_usr_id,
        fyh_mod            = NOW()
    FROM (
        SELECT l.item_id, COUNT(*) AS total
        FROM inventario.lote l
        JOIN inventario.item_movimientos im
            ON  im.lote_id                 = l.id
            AND im.item_movimiento_tipo_id = v_ing_tipo_id
        WHERE l.documento_tipo = 'partida_paso_ejecucion'
          AND l.documento_id   = p_ejecucion_id
          AND l.fyh_elm        IS NULL
        GROUP BY l.item_id
    ) sub
    WHERE pd.partida_id = v_partida_id
      AND pd.item_id    = sub.item_id;

    -- 6. Notifications
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Producción Registrada',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' registró %s lotes de producción en orden #%s', jsonb_array_length(v_p_output), v_partida_id), 'info',
           jsonb_build_object('objeto_tipo','partida','partida_id', v_partida_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','calidad') AND v_usr_id <> ur.user_id;

    RETURN format('%s rollos consumidos, %s lotes creados para orden #%s.', v_consumed, jsonb_array_length(v_p_output), v_partida_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_produccion - User: %, ejecucion: %, Error: %, Detail: %',
              v_usr_id, p_ejecucion_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.registrar_produccion(BIGINT, JSONB) TO authenticated;

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
    v_partida_id     bigint;
    v_maquina_id   int;
    v_ejecucion_id bigint;
    v_op_nombre    text;
    v_prod_result       text;
    v_variance_payload  jsonb;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Fetch paso info and its active execution run in one shot
    SELECT pp.partida_id, o.nombre, pe.id, pe.maquina_id
    INTO v_partida_id, v_op_nombre, v_ejecucion_id, v_maquina_id
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
    WHERE pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso #% no encontrado o sin ejecución EN_PROCESO.', p_paso_id;
    END IF;

    -- Process recipe consumptions if provided
    IF p_datos->'consumos' IS NOT NULL AND jsonb_array_length(p_datos->'consumos') > 0 THEN
        PERFORM mes.registrar_consumo_paso(p_paso_id, p_datos->'consumos');
    END IF;

    -- Process matizado corrections — same consumo path, motivo resolved internally
    IF p_datos->'matizados' IS NOT NULL AND jsonb_array_length(p_datos->'matizados') > 0 THEN
        PERFORM mes.registrar_consumo_paso(
            p_paso_id,
            (SELECT jsonb_agg(item || jsonb_build_object('motivo_id', m.id))
             FROM jsonb_array_elements(p_datos->'matizados') AS item
             CROSS JOIN (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO') m)
        );
    END IF;

    -- Variance alert: actual consumptions vs partida_componente chemical reservations (>10%)
    SELECT jsonb_agg(jsonb_build_object(
        'item_id',       pc.item_id,
        'item_nombre',   it.nombre,
        'planificado',   pc.cantidad_reservada,
        'real',          COALESCE(actual.total, 0),
        'variacion_pct', ROUND(
            (ABS(COALESCE(actual.total, 0) - pc.cantidad_reservada)
             / NULLIF(pc.cantidad_reservada, 0)) * 100, 2
        )
    ))
    INTO v_variance_payload
    FROM mes.partida_componente pc
    JOIN item it ON it.id = pc.item_id
    LEFT JOIN (
        SELECT item_id, SUM(ABS(cantidad)) AS total
        FROM inventario.item_movimientos
        WHERE documento_tipo = 'partida_paso_ejecucion'
          AND documento_id = v_ejecucion_id
        GROUP BY item_id
    ) actual ON actual.item_id = pc.item_id
    WHERE pc.partida_paso_id = p_paso_id
      AND pc.item_id IS NOT NULL
      AND pc.cantidad_reservada > 0
      AND ABS(COALESCE(actual.total, 0) - pc.cantidad_reservada)
          / NULLIF(pc.cantidad_reservada, 0) > 0.10;

    IF v_variance_payload IS NOT NULL THEN
        INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
        SELECT ur.user_id,
               'Variación de consumo en paso',
               format('Paso %s (#%s): variación > 10%% respecto a receta.', v_op_nombre, p_paso_id),
               'warning',
               jsonb_build_object('objeto_tipo','partida_paso','paso_id', p_paso_id,
                                  'partida_id', v_partida_id, 'variaciones', v_variance_payload)
        FROM iam.user_rol ur
        JOIN iam.rol r ON ur.rol_id = r.id
        WHERE r.code IN ('jefe_planta','supervisor_produccion');
    END IF;

    -- Register production output if caller submitted it (TENIDO step)
    -- p_datos->'produccion' shape: {output: [...], ubicacion_id: N, peso_rollos?: N, peso_rib?: N}
    IF (p_datos->'produccion'->'output') IS NOT NULL
       AND jsonb_array_length(p_datos->'produccion'->'output') > 0 THEN
        v_prod_result := mes.registrar_produccion(v_ejecucion_id, p_datos->'produccion');
    END IF;

    -- Close the execution run with actual measured params
    UPDATE mes.partida_paso_ejecucion
    SET estado             = 'COMPLETADO',
        fyh_fin            = NOW(),
        ph_real            = COALESCE((p_datos->>'ph_real')::NUMERIC,            ph_real),
        temperatura_real   = COALESCE((p_datos->>'temperatura_real')::NUMERIC,   temperatura_real),
        relacion_bano_real = COALESCE((p_datos->>'relacion_bano_real')::NUMERIC, relacion_bano_real),
        cantidad           = COALESCE((p_datos->>'cantidad')::NUMERIC,           cantidad),
        notas              = COALESCE(p_datos->>'notas',                         notas),
        usr_mod            = v_usr_id,
        fyh_mod            = NOW()
    WHERE id = v_ejecucion_id;

    -- Release machine
    IF v_maquina_id IS NOT NULL THEN
        UPDATE mes.maquina SET estado_actual = 'espera'
        WHERE id = v_maquina_id;
    END IF;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Paso Completado',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' completó el paso %s (orden #%s)', v_op_nombre, v_partida_id), 'info',
           jsonb_build_object('objeto_tipo','partida_paso','paso_id', p_paso_id, 'partida_id', v_partida_id)
    FROM iam.user_rol ur LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta','supervisor_produccion') AND v_usr_id <> ur.user_id;

    RETURN format('Paso %s (#%s) completado.%s', v_op_nombre, p_paso_id,
                  CASE WHEN v_prod_result IS NOT NULL THEN ' ' || v_prod_result ELSE '' END);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in finalizar_paso - User: %, ID: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- mes.omitir_paso
-- Marks a paso as intentionally skipped with no execution.
-- Creates an OMITIDO ejecucion as a terminal marker, satisfying
-- the sequence gate for subsequent pasos.
-- Requires produccion.editar — deliberate process deviation.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.omitir_paso(p_paso_id BIGINT, p_datos JSONB DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_partida_id  bigint;
    v_op_nombre text;
    v_secuencia smallint;
BEGIN
    IF NOT jwt_has_permission('produccion.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT pp.partida_id, o.nombre, pp.secuencia
    INTO v_partida_id, v_op_nombre, v_secuencia
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    WHERE pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso con ID % no encontrado.', p_paso_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = p_paso_id AND estado IN ('EN_PROCESO','COMPLETADO')
    ) THEN
        RAISE EXCEPTION 'El paso % ya tiene una ejecución en curso o completada; no se puede omitir.', v_op_nombre;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        WHERE pp.partida_id = v_partida_id
          AND pp.secuencia < v_secuencia
          AND (
              NOT EXISTS (
                  SELECT 1 FROM mes.partida_paso_ejecucion pe
                  WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('COMPLETADO','OMITIDO')
              )
              OR EXISTS (
                  SELECT 1 FROM mes.partida_paso_ejecucion pe
                  WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
              )
          )
    ) THEN
        RAISE EXCEPTION 'No se puede omitir el paso % porque hay pasos anteriores no completados o en ejecución.', v_op_nombre;
    END IF;

    INSERT INTO mes.partida_paso_ejecucion(partida_paso_id, estado, fyh_inicio, fyh_fin, notas, usr_cre)
    VALUES (p_paso_id, 'OMITIDO', NOW(), NOW(), p_datos->>'notas', v_usr_id);

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    RETURN format('Paso %s (#%s) omitido.', v_op_nombre, p_paso_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in omitir_paso - User: %, Paso: %, Error: %', v_usr_id, p_paso_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.omitir_paso(BIGINT, JSONB) TO authenticated;


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
    v_estado      partida_paso_estado_enum;
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
    v_estado            partida_paso_estado_enum;
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
                   COALESCE(sg.cantidad_total, 0) AS cantidad_disponible
            FROM consumos c
            LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = c.item_id
            JOIN item it ON it.id = c.item_id
            WHERE COALESCE(sg.cantidad_total, 0) < c.cantidad
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
-- mes.registrar_ejecucion_partida
-- Primary end-of-day production reporting function.
-- The factory runs on paper intraday (notepad per station with start/end times and roll counts);
-- the operations supervisor transcribes one partida at a time into this function.
-- The partida and its partida_paso rows must already exist (created via crear_partida).
-- Inserts each ejecucion as COMPLETADO with the supplied historical timestamps,
-- then calls registrar_consumo_paso / registrar_produccion for inventory side-effects.
-- Pasos must be supplied in ascending secuencia order — the caller is responsible for ordering.
-- Idempotent guard: rejects if any paso already has an ejecucion (prevents double-submission).
--
-- p_data keys:
--   partida_id           INT         (required)
--   pasos                ARRAY       (required, in secuencia order)
--     paso_id            BIGINT      (required)
--     fyh_inicio         TIMESTAMPTZ (required)
--     fyh_fin            TIMESTAMPTZ (required)
--     empleado_id        SMALLINT    (optional)
--     maquina_id         INT         (optional)
--     cantidad           NUMERIC     (optional — roll count confirmed in this run)
--     ph_real            NUMERIC     (optional)
--     temperatura_real   NUMERIC     (optional)
--     relacion_bano_real NUMERIC     (optional)
--     consumos           ARRAY       (optional — same shape as registrar_consumo_paso)
--     produccion         OBJECT      (optional — same shape as registrar_produccion)
--     observacion        TEXT        (optional — stored in notas)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.registrar_ejecucion_partida(p_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id           INT := get_user_id();
    v_partida_id         INT;
    v_paso             JSONB;
    v_paso_id          BIGINT;
    v_ejecucion_id     BIGINT;
    v_paso_count       INT := 0;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_partida_id := (p_data->>'partida_id')::INT;

    IF v_partida_id IS NULL THEN
        RAISE EXCEPTION 'partida_id es requerido.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM mes.partida WHERE id = v_partida_id) THEN
        RAISE EXCEPTION 'Orden de producción % no encontrada.', v_partida_id;
    END IF;
    IF jsonb_array_length(p_data->'pasos') = 0 THEN
        RAISE EXCEPTION 'Se requiere al menos un paso en p_data.pasos.';
    END IF;

    -- Idempotency guard: reject if any paso already has an ejecucion.
    IF EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        WHERE pp.partida_id = v_partida_id
    ) THEN
        RAISE EXCEPTION
            'La partida % ya tiene ejecuciones registradas. Para corregir una ejecución use anular_produccion.',
            v_partida_id;
    END IF;

    FOR v_paso IN SELECT * FROM jsonb_array_elements(p_data->'pasos') LOOP
        v_paso_id := (v_paso->>'paso_id')::BIGINT;

        IF v_paso_id IS NULL THEN
            RAISE EXCEPTION 'Cada paso debe incluir paso_id.';
        END IF;
        IF (v_paso->>'fyh_inicio') IS NULL OR (v_paso->>'fyh_fin') IS NULL THEN
            RAISE EXCEPTION 'Cada paso debe incluir fyh_inicio y fyh_fin (paso_id=%).', v_paso_id;
        END IF;

        -- Direct INSERT: ejecucion is COMPLETADO from the start with historical timestamps.
        -- fyh_cre mirrors fyh_inicio so the row looks correct in reporting.
        -- No trigger on partida_paso_ejecucion overrides fyh_cre, so this is safe.
        INSERT INTO mes.partida_paso_ejecucion(
            partida_paso_id,
            estado,
            fyh_inicio,
            fyh_fin,
            empleado_id,
            maquina_id,
            ph_real,
            temperatura_real,
            relacion_bano_real,
            cantidad,
            notas,
            usr_cre,
            fyh_cre
        ) VALUES (
            v_paso_id,
            'COMPLETADO',
            (v_paso->>'fyh_inicio')::TIMESTAMPTZ,
            (v_paso->>'fyh_fin')::TIMESTAMPTZ,
            (v_paso->>'empleado_id')::SMALLINT,
            (v_paso->>'maquina_id')::INT,
            (v_paso->>'ph_real')::NUMERIC,
            (v_paso->>'temperatura_real')::NUMERIC,
            (v_paso->>'relacion_bano_real')::NUMERIC,
            (v_paso->>'cantidad')::NUMERIC,
            v_paso->>'observacion',
            v_usr_id,
            (v_paso->>'fyh_inicio')::TIMESTAMPTZ
        ) RETURNING id INTO v_ejecucion_id;

        IF v_paso->'consumos' IS NOT NULL AND jsonb_array_length(v_paso->'consumos') > 0 THEN
            PERFORM mes.registrar_consumo_paso(v_paso_id, v_paso->'consumos');
        END IF;

        IF v_paso->'produccion' IS NOT NULL THEN
            PERFORM mes.registrar_produccion(v_ejecucion_id, v_paso->'produccion');
        END IF;

        PERFORM mes.actualizar_estado_partida(v_partida_id);

        v_paso_count := v_paso_count + 1;
    END LOOP;

    RETURN format('Ejecución registrada: %s paso(s) confirmados para orden %s.',
                  v_paso_count, v_partida_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_ejecucion_partida - User: %, Orden: %, Error: %',
              v_usr_id, v_partida_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.registrar_ejecucion_partida(JSONB) TO authenticated;

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
            FROM mes.partida_componente opi
            JOIN inventario.lote        l   ON l.id = opi.lote_id
            WHERE opi.partida_id = pp.partida_id
        ), 0)::numeric                                      AS kilos,
        CASE
            WHEN pe.estado = 'EN_PROCESO' THEN
                GREATEST(interval '0',
                    te_std.duracion - (now() - pe.fyh_inicio))
            ELSE
                te_std.duracion
        END                                                 AS duracion,
        pe.fyh_inicio
    FROM mes.programacion                 p
    JOIN mes.partida_paso        pp    ON pp.id  = p.actividad_id
    LEFT JOIN mes.partida_paso_ejecucion pe
           ON pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
    JOIN receta.tenido                    rt     ON rt.id   = pp.receta_id
    JOIN color_x_cliente                  cxc    ON cxc.id  = rt.color_x_cliente_id
    LEFT JOIN color                       co     ON co.id   = cxc.color_id
    LEFT JOIN tenido                      te     ON te.id   = rt.tenido_id
    LEFT JOIN valor                       val    ON val.id  = cxc.valor_id
    LEFT JOIN mes.tiempos_estandar_tenido te_std
           ON te_std.valor_id        = cxc.valor_id
          AND te_std.tenido_id       = rt.tenido_id
          AND te_std.flg_antipilling = rt.flg_antipilling
          AND te_std.flg_activo      = true
    WHERE p.actividad_tipo  = 'partida_paso'
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe2
          WHERE pe2.partida_paso_id = pp.id AND pe2.estado = 'COMPLETADO'
      )
      AND pp.receta_id     IS NOT NULL
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
    IF NOT jwt_has_permission('produccion.configurar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.configurar'
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
    IF NOT jwt_has_permission('produccion.configurar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.configurar'
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
CREATE OR REPLACE FUNCTION mes.anular_produccion(p_ejecucion_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','mes','doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_partida_id          bigint;
    v_estado            paso_ejecucion_estado_enum;
    v_ing_rev_id        smallint;
    v_consumo_rev_id    smallint;
    v_doc_movimiento_id bigint;
    v_output_count      int;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Ejecucion must exist and be COMPLETADO
    SELECT pe.estado, pp.partida_id
    INTO v_estado, v_partida_id
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    WHERE pe.id = p_ejecucion_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ejecución #% no encontrada.', p_ejecucion_id;
    END IF;
    IF v_estado <> 'COMPLETADO' THEN
        RAISE EXCEPTION 'Solo se puede anular una ejecución COMPLETADA. Estado actual: %', v_estado;
    END IF;

    -- 2. Guard: no downstream movements on output lotes
    IF EXISTS (
        SELECT 1
        FROM inventario.lote l
        JOIN inventario.item_movimientos im      ON im.lote_id = l.id
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE l.documento_tipo = 'partida_paso_ejecucion'
          AND l.documento_id   = p_ejecucion_id
          AND l.fyh_elm        IS NULL
          AND imt.codigo NOT IN ('PROD_ING', 'PROD_ING_REV')
    ) THEN
        RAISE EXCEPTION
            'No se puede anular la ejecución #%: uno o más lotes de salida ya tienen movimientos posteriores (despacho, ajuste, etc.). Anule esos documentos primero.',
            p_ejecucion_id;
    END IF;

    -- 3. Lock rows
    PERFORM 1 FROM inventario.lote
    WHERE documento_tipo = 'partida_paso_ejecucion' AND documento_id = p_ejecucion_id
    FOR UPDATE;

    PERFORM 1 FROM mes.partida WHERE id = v_partida_id FOR UPDATE;

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
        'partida_paso_ejecucion',
        p_ejecucion_id
    FROM inventario.lote l
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id   = p_ejecucion_id
      AND l.fyh_elm        IS NULL;

    GET DIAGNOSTICS v_output_count = ROW_COUNT;

    -- 6. PROD_CONSUMO_REV: restore input lotes consumed by this execution run
    --    Re-credit each roll back to its original origin (m.origen_ubicacion_id).
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id
    )
    SELECT
        v_doc_movimiento_id,
        m.item_id,
        m.lote_id,
        v_consumo_rev_id,
        m.origen_ubicacion_id,
        m.cantidad,
        'partida_paso_ejecucion',
        p_ejecucion_id
    FROM inventario.item_movimientos m
    WHERE m.documento_tipo = 'partida_paso_ejecucion'
      AND m.documento_id   = p_ejecucion_id
      AND m.item_movimiento_tipo_id = (
          SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'
      );

    -- 7. Soft-delete output lotes + their batch classification rows
    UPDATE inventario.lote
    SET usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE documento_tipo = 'partida_paso_ejecucion'
      AND documento_id   = p_ejecucion_id
      AND fyh_elm        IS NULL;

    DELETE FROM inventario.lote_rollo_detalle
    WHERE lote_id IN (
        SELECT id FROM inventario.lote
        WHERE documento_tipo = 'partida_paso_ejecucion'
          AND documento_id   = p_ejecucion_id
    );

    -- 8. Reset execution run back to EN_PROCESO
    UPDATE mes.partida_paso_ejecucion
    SET estado  = 'EN_PROCESO',
        fyh_fin = NULL,
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    WHERE id = p_ejecucion_id;

    -- 9. Decrement confirmed output count and re-derive partida state
    UPDATE mes.partida_detalle
    SET cantidad_producida = GREATEST(0, cantidad_producida - v_output_count),
        usr_mod            = v_usr_id,
        fyh_mod            = NOW()
    WHERE partida_id = v_partida_id;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_produccion', v_usr_id, jsonb_build_object('ejecucion_id', p_ejecucion_id));

    RETURN format('Producción de ejecución #% anulada: % lotes de salida revertidos.', p_ejecucion_id, v_output_count);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_produccion - User: %, ejecucion: %, Error: %, Detail: %',
              v_usr_id, p_ejecucion_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.anular_produccion(BIGINT) TO authenticated;
-- GRANT removed: mes.actualizar_pesos_partida_items moved to inventario.corregir_pesaje_produccion
GRANT EXECUTE ON FUNCTION mes.actualizar_pesos_individuales_partida(BIGINT, JSONB) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- ACTUALIZAR ESTADO PARTIDA — centralized production state machine
-- ═══════════════════════════════════════════════════════════════
-- Called by iniciar_paso, finalizar_paso, anular_produccion after
-- mutating partida_paso.estado. Derives estado_produccion from
-- the current paso states rather than each caller guessing.
--
-- Transition rules (never touches CERRADA/CANCELADA):
--   any paso EN_PROCESO            → EN_PRODUCCION (set fyh_inicio once)
--   all pasos COMPLETADO/OMITIDO   → TECO          (set fyh_fin once)
--   (else: no change — handles mid-annulment back-to EN_PRODUCCION naturally)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.actualizar_estado_partida(p_partida_id BIGINT)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public','mes'
AS $$
DECLARE
    v_hay_en_proceso   boolean;
    v_todos_terminados boolean;
    v_hay_pasos        boolean;
BEGIN
    SELECT
        BOOL_OR(EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
        )),
        BOOL_AND(EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('COMPLETADO','OMITIDO')
        )),
        COUNT(*) > 0
    INTO v_hay_en_proceso, v_todos_terminados, v_hay_pasos
    FROM mes.partida_paso pp
    WHERE pp.partida_id = p_partida_id;

    IF NOT v_hay_pasos THEN RETURN; END IF;

    IF v_todos_terminados THEN
        UPDATE mes.partida
        SET estado_produccion = 'TECO',
            fyh_fin           = COALESCE(fyh_fin, NOW()),
            fyh_mod           = NOW()
        WHERE id = p_partida_id
          AND estado_produccion NOT IN ('CERRADA','CANCELADA');
    ELSIF v_hay_en_proceso THEN
        UPDATE mes.partida
        SET estado_produccion = 'EN_PRODUCCION',
            fyh_inicio        = COALESCE(fyh_inicio, NOW()),
            fyh_fin           = NULL,
            fyh_mod           = NOW()
        WHERE id = p_partida_id
          AND estado_produccion NOT IN ('CERRADA','CANCELADA');
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION mes.actualizar_estado_partida(BIGINT) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- CERRAR PARTIDA — three-axis settlement gate (TECO → CERRADA)
-- ═══════════════════════════════════════════════════════════════
--
-- PARTIDA LIFECYCLE (estado_produccion)
-- ─────────────────────────────────────
--  PENDIENTE     Created by crear_partida. Steps planned, no execution yet.
--  EN_PRODUCCION Set by actualizar_estado_partida when the first paso iniciar
--                call lands (any partida_paso_ejecucion IN EN_PROCESO).
--  TECO          Technical Completion (≈ SAP TECO). Set by actualizar_estado_partida
--                when every partida_paso (fyh_elm IS NULL) has a terminal ejecucion
--                (COMPLETADO or OMITIDO) and none are EN_PROCESO.
--                After TECO, no further paso execution is allowed.
--  CERRADA       Final state. Reached only via cerrar_partida, after all three
--                settlement axes are satisfied (see below).
--  CANCELADA     Set by anular_produccion. Reverses all inventory movements
--                produced by registrar_produccion and removes ejecucion rows.
--
-- estado_produccion is NEVER written directly by application code; it is always
-- driven by actualizar_estado_partida (called from iniciar_paso, finalizar_paso,
-- omitir_paso, anular_produccion).
--
-- PASO EXECUTION LIFECYCLE (partida_paso_ejecucion.estado)
-- ─────────────────────────────────────────────────────────
--  EN_PROCESO    Created by iniciar_paso.
--  COMPLETADO    Set by finalizar_paso. Terminal — cannot reopen.
--  OMITIDO       Set by omitir_paso. Terminal — satisfies sequence gate for
--                downstream pasos but records no consumption/output.
--
--  A paso is considered done (for sequencing and TECO purposes) when it has at
--  least one ejecucion in COMPLETADO or OMITIDO, and none in EN_PROCESO.
--  Lagging continuations (split runs: e.g., 10 + 10 from 20 assigned rolls) are
--  recorded as separate ejecucion rows; a new run can start once the prior one
--  is COMPLETADO (send-ahead model — physical workflow enforces quantity).
--
-- THREE-AXIS SETTLEMENT GATE
-- ──────────────────────────
--  Axis 1 — Production (MES):
--    estado_produccion = TECO
--    Set by this module (mes.*). Requires all child reprocesos to also be
--    TECO / CERRADA / CANCELADA before cerrar_partida is allowed.
--
--  Axis 2 — Dispatch (comercial):
--    estado_comercial IN ('ENTREGADA', 'DEVUELTA_PARCIAL', 'DEVUELTA_TOTAL')
--    Set by the despacho/comercial module (doc.guia_remision flows). Indicates
--    that finished goods have been delivered to or returned from the client.
--
--  Axis 3 — Billing (facturación):
--    estado_facturacion = 'facturado'
--    Set by the facturacion module when a doc.factura covering this partida is
--    emitted. A partida without an invoice cannot be closed.
--
-- Permission: produccion.administrar (admin, jefe_planta only).
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.cerrar_partida(p_partida_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes','doc'
AS $$
DECLARE
    v_message            text; v_detail text;
    v_usr_id             int := get_user_id();
    v_estado_produccion  partida_estado_produccion_enum;
    v_estado_comercial   partida_estado_comercial_enum;
    v_estado_facturacion partida_facturacion_enum;
    v_target_qty         numeric;
    v_output_qty         numeric;
    v_warning            text := '';
BEGIN
    IF NOT jwt_has_permission('produccion.administrar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.administrar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado_produccion, estado_comercial, estado_facturacion
    INTO v_estado_produccion, v_estado_comercial, v_estado_facturacion
    FROM mes.partida
    WHERE id = p_partida_id
      AND fyh_elm IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida % no encontrada.', p_partida_id;
    END IF;

    IF v_estado_produccion <> 'TECO' THEN
        RAISE EXCEPTION
            'Solo se puede cerrar una partida en estado TECO. Estado actual: %',
            v_estado_produccion;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mes.partida
        WHERE partida_origen_id = p_partida_id
          AND estado_produccion NOT IN ('TECO','CERRADA','CANCELADA')
    ) THEN
        RAISE EXCEPTION
            'Partida % tiene reprocesos activos pendientes. Finalícelos antes de cerrar.',
            p_partida_id;
    END IF;

    IF v_estado_comercial NOT IN ('ENTREGADA','DEVUELTA_PARCIAL','DEVUELTA_TOTAL') THEN
        RAISE EXCEPTION
            'Partida % no puede cerrarse: estado comercial % no indica entrega registrada.',
            p_partida_id, v_estado_comercial;
    END IF;

    IF v_estado_facturacion <> 'facturado' THEN
        RAISE EXCEPTION
            'Partida % no puede cerrarse: facturación en estado %. Se requiere facturación completa.',
            p_partida_id, v_estado_facturacion;
    END IF;

    -- Soft warning: actual output (this partida + reprocesos) vs billing target
    SELECT COALESCE(SUM(pd.cantidad), 0)
    INTO v_target_qty
    FROM mes.partida_detalle pd
    WHERE pd.partida_id = p_partida_id;

    SELECT COUNT(l.id)
    INTO v_output_qty
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
                                      AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    WHERE pp.partida_id IN (
        SELECT id FROM mes.partida
        WHERE id = p_partida_id OR partida_origen_id = p_partida_id
    )
    AND l.fyh_elm IS NULL;

    IF v_output_qty < v_target_qty THEN
        v_warning := format(' ATENCIÓN: producción total (%s rollos) es menor al objetivo (%s rollos). Verifique antes de cerrar.', v_output_qty, v_target_qty);
    END IF;

    UPDATE mes.partida
    SET estado_produccion = 'CERRADA',
        fyh_mod           = NOW(),
        usr_mod           = v_usr_id
    WHERE id = p_partida_id;

    RETURN format('Partida #%s cerrada correctamente.%s', p_partida_id, v_warning);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL;
    RAISE LOG 'Error in cerrar_partida - User: %, partida: %, Error: %', v_usr_id, p_partida_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION mes.cerrar_partida(BIGINT) TO authenticated;
GRANT USAGE on SCHEMA mes TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- CREAR REPROCESO
-- Branches failing rolls into a rework child partida.
--
-- p_lotes: JSON array of lote_id integers — the rolls that failed QC.
--
-- What it does:
--   1. Creates a child partida inheriting all commercial/production attributes.
--      partida_origen_id links back to the parent; estado_comercial is locked
--      to PENDIENTE by the chk_rework_comercial_locked constraint.
--   2. Copies the paso structure (planning intent only, no execution rows).
--   3. Moves the failing rolls from the parent's partida_componente to the
--      child's by updating partida_id — preserving cantidad_reservada.
--
-- Billing and commercial settlement always run on the parent.
-- partida_detalle on the parent is intentionally untouched: the planned
-- quantity is the billing anchor (MLR absorbs rework cost internally).
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.crear_reproceso(
    p_partida_id BIGINT,
    p_lotes      JSONB
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes','inventario'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_usr_id    INT := get_user_id();
    v_origen    mes.partida%ROWTYPE;
    v_child_id  BIGINT;
BEGIN
    IF NOT jwt_has_permission('produccion.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_origen
    FROM mes.partida
    WHERE id = p_partida_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida % no encontrada.', p_partida_id;
    END IF;

    IF v_origen.estado_produccion NOT IN ('EN_PRODUCCION','TECO') THEN
        RAISE EXCEPTION 'Reproceso requiere partida EN_PRODUCCION o TECO. Estado actual: %.',
            v_origen.estado_produccion;
    END IF;

    IF jsonb_array_length(p_lotes) = 0 THEN
        RAISE EXCEPTION 'Se requiere al menos un lote para crear reproceso.';
    END IF;

    -- Validate every supplied lote belongs to this partida
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_lotes) e
        WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_componente pc
            WHERE pc.partida_id = p_partida_id
              AND pc.lote_id    = (e.value::TEXT)::INT
        )
    ) THEN
        RAISE EXCEPTION 'Uno o más lotes no pertenecen a la partida %.', p_partida_id;
    END IF;

    -- Create rework child partida
    INSERT INTO mes.partida (
        partida_origen_id, prioridad_id, tercero_id, tenido_id,
        color_x_cliente_id, articulo_tipo_id, fibra, malla, rendimiento,
        ancho, flg_antipilling, fecha_acordada, estado_produccion, usr_cre
    )
    VALUES (
        p_partida_id, v_origen.prioridad_id, v_origen.tercero_id, v_origen.tenido_id,
        v_origen.color_x_cliente_id, v_origen.articulo_tipo_id, v_origen.fibra,
        v_origen.malla, v_origen.rendimiento, v_origen.ancho, v_origen.flg_antipilling,
        v_origen.fecha_acordada, 'CREADA', v_usr_id
    )
    RETURNING id INTO v_child_id;

    -- Copy paso structure (planning intent only — no execution rows)
    INSERT INTO mes.partida_paso (
        partida_id, secuencia, operacion_id, maquina_planificada_id,
        receta_id, tiempo_estandar, ph_objetivo, temperatura_objetivo,
        relacion_bano_objetivo, usr_cre
    )
    SELECT
        v_child_id, secuencia, operacion_id, maquina_planificada_id,
        receta_id, tiempo_estandar, ph_objetivo, temperatura_objetivo,
        relacion_bano_objetivo, v_usr_id
    FROM mes.partida_paso
    WHERE partida_id = p_partida_id
    ORDER BY secuencia;

    -- Move failing rolls to child partida (preserves cantidad_reservada)
    UPDATE mes.partida_componente
    SET partida_id = v_child_id
    WHERE partida_id = p_partida_id
      AND lote_id IN (
          SELECT (e.value::TEXT)::INT FROM jsonb_array_elements(p_lotes) e
      );

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_reproceso', v_usr_id,
            jsonb_build_object('partida_id', p_partida_id, 'lotes', p_lotes));

    RETURN jsonb_build_object(
        'reproceso_partida_id', v_child_id,
        'partida_origen_id',    p_partida_id,
        'lotes_movidos',        jsonb_array_length(p_lotes),
        'message', format('Reproceso %s creado desde partida %s con %s rollo(s).',
                          v_child_id, p_partida_id, jsonb_array_length(p_lotes))
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in crear_reproceso - User: %, Partida: %, Error: %, Detail: %',
                  v_usr_id, p_partida_id, v_message, v_detail;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.crear_reproceso(BIGINT, JSONB) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- GET PARTIDA  (canonical — overrides the copy in core.sql)
-- ═══════════════════════════════════════════════════════════════
-- Returns full production order detail: header, pasos (with flg_ultimo),
-- materiales_reservados (input rolls), produccion (output lotes + QC),
-- partida_detalles (planned output), resumen_progreso, resumen_consumo_total.
CREATE OR REPLACE FUNCTION mes.get_partida(p_partida_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public','inventario','doc','mes','calidad'
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- Header
        'id', p.id,
        'partida_origen_id', p.partida_origen_id,
        'numero', p.numero,
        'codigo', EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'prioridad_id', p.prioridad_id,
        'prioridad', pri.prioridad,
        'tercero_id', p.tercero_id,
        'cliente', c.nombre,
        'color_x_cliente_id', p.color_x_cliente_id,
        'color', vc.color,
        'color_hex', vc.color_hex,
        'color_x_cliente_hex', vc.color_x_cliente_hex,
        'tono', vc.tono,
        'articulo_tipo_id', p.articulo_tipo_id,
        'articulo_tipo', at.nombre,
        'flg_antipilling', p.flg_antipilling,
        'tenido_id', p.tenido_id,
        'tenido', tenido.tenido,
        'malla', p.malla,
        'rendimiento', p.rendimiento,
        'ancho', p.ancho,
        'estado_comercial', p.estado_comercial,
        'estado_produccion', p.estado_produccion,
        'estado_facturacion', p.estado_facturacion,
        'fecha_acordada', p.fecha_acordada,
        'fyh_inicio', p.fyh_inicio,
        'fyh_fin', p.fyh_fin,
        'fyh_cre', p.fyh_cre,

        -- Planned output items
        'partida_detalles', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', pd.id,
                'item_id', pd.item_id,
                'item_tipo_codigo', vi.item_tipo_codigo,
                'item_codigo', vi.item_codigo,
                'item_nombre', vi.item_nombre,
                'cantidad', pd.cantidad,
                'unidad', u.codigo,
                'unidad_id', u.id,
                'cantidad_producida', pd.cantidad_producida,
                'fyh_mod', pd.fyh_mod
            ) ORDER BY pd.id)
            FROM mes.partida_detalle pd
            LEFT JOIN vw_items vi ON vi.item_id = pd.item_id
            LEFT JOIN unidad u ON u.id = pd.unidad_id
            WHERE pd.partida_id = p.id
        ), '[]'::jsonb),

        'resumen_progreso', jsonb_build_object(
            'total_pasos', (SELECT COUNT(*) FROM mes.partida_paso WHERE partida_id = p.id),
            'pasos_completados', (
                SELECT COUNT(*) FROM mes.partida_paso
                WHERE partida_id = p.id
                  AND EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe
                              WHERE pe.partida_paso_id = mes.partida_paso.id AND pe.estado = 'COMPLETADO')
            ),
            'porcentaje_completado', (
                SELECT ROUND(
                    COUNT(DISTINCT ppe.partida_paso_id) FILTER (WHERE ppe.estado = 'COMPLETADO')::NUMERIC
                    / NULLIF(COUNT(DISTINCT pp.id), 0) * 100, 2
                )
                FROM mes.partida_paso pp
                LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
                WHERE pp.partida_id = p.id
            )
        ),

        'resumen_consumo_total', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'item_id', subq.item_id,
                'item_codigo', subq.item_codigo,
                'item_nombre', subq.item_nombre,
                'cantidad_total', subq.cantidad_total,
                'unidad', subq.unidad
            ))
            FROM (
                SELECT m.item_id, vi.item_codigo, vi.item_nombre,
                       vi.unidad_codigo AS unidad, SUM(m.cantidad) AS cantidad_total
                FROM inventario.item_movimientos m
                JOIN vw_items vi ON vi.item_id = m.item_id
                WHERE m.documento_tipo = 'partida_paso_ejecucion'
                  AND m.documento_id IN (
                      SELECT pe.id FROM mes.partida_paso_ejecucion pe
                      JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
                      WHERE pp.partida_id = p.id
                  )
                GROUP BY m.item_id, vi.item_codigo, vi.item_nombre, vi.unidad_codigo
            ) subq
        ), '[]'::jsonb),

        -- Steps
        'pasos', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', opp.id,
                    'secuencia', opp.secuencia,
                    'operacion_id', opp.operacion_id,
                    'operacion_codigo', o.codigo,
                    'operacion_nombre', o.nombre,
                    'maquina_planificada_id', opp.maquina_planificada_id,
                    'maquina_planificada_nombre', maquina.nombre,
                    'ph_objetivo', opp.ph_objetivo,
                    'relacion_bano_objetivo', opp.relacion_bano_objetivo,
                    'temperatura_objetivo', opp.temperatura_objetivo,
                    'tiempo_estandar', opp.tiempo_estandar,
                    'receta_id', opp.receta_id,
                    -- True for the last non-omitted step; frontend shows production output form here.
                    'flg_ultimo', (
                        opp.secuencia = (
                            SELECT MAX(pp2.secuencia)
                            FROM mes.partida_paso pp2
                            WHERE pp2.partida_id = p_partida_id
                              AND NOT EXISTS (
                                  SELECT 1 FROM mes.partida_paso_ejecucion pe2
                                  WHERE pe2.partida_paso_id = pp2.id AND pe2.estado = 'OMITIDO'
                              )
                        )
                    ),
                    'estado', COALESCE((
                        SELECT CASE
                            WHEN bool_or(pe.estado = 'COMPLETADO') THEN 'COMPLETADO'
                            WHEN bool_or(pe.estado = 'EN_PROCESO')  THEN 'EN_PROCESO'
                            WHEN bool_or(pe.estado = 'OMITIDO')     THEN 'OMITIDO'
                            ELSE 'PENDIENTE'
                        END
                        FROM mes.partida_paso_ejecucion pe
                        WHERE pe.partida_paso_id = opp.id
                    ), 'PENDIENTE'),
                    'ejecucion', (
                        SELECT jsonb_build_object(
                            'id',                  pe.id,
                            'maquina_id',          pe.maquina_id,
                            'empleado_id',         pe.empleado_id,
                            'fyh_inicio',          pe.fyh_inicio,
                            'fyh_fin',             pe.fyh_fin,
                            'ph_real',             pe.ph_real,
                            'temperatura_real',    pe.temperatura_real,
                            'relacion_bano_real',  pe.relacion_bano_real,
                            'cantidad',            pe.cantidad,
                            'notas',               pe.notas
                        )
                        FROM mes.partida_paso_ejecucion pe
                        WHERE pe.partida_paso_id = opp.id
                        ORDER BY pe.fyh_inicio DESC LIMIT 1
                    ),
                    'consumo', COALESCE((
                        SELECT jsonb_agg(jsonb_build_object(
                            'id', m.id,
                            'item_id', m.item_id,
                            'item_codigo', vi_mov.item_codigo,
                            'item_nombre', vi_mov.item_nombre,
                            'lote_id', m.lote_id,
                            'cantidad', m.cantidad,
                            'unidad', vi_mov.unidad_codigo,
                            'origen_ubicacion_id', m.origen_ubicacion_id,
                            'origen_ubicacion', ubi.nombre,
                            'origen_almacen', al.nombre
                        ) ORDER BY m.fyh_cre)
                        FROM inventario.item_movimientos m
                        LEFT JOIN vw_items vi_mov ON vi_mov.item_id = m.item_id
                        LEFT JOIN inventario.ubicacion ubi ON ubi.id = m.origen_ubicacion_id
                        LEFT JOIN inventario.almacen al ON al.id = ubi.almacen_id
                        WHERE m.documento_tipo = 'partida_paso_ejecucion'
                          AND m.documento_id IN (
                              SELECT pe.id FROM mes.partida_paso_ejecucion pe
                              WHERE pe.partida_paso_id = opp.id
                          )
                    ), '[]'::jsonb)
                ) ORDER BY opp.secuencia
            )
            FROM mes.partida_paso opp
            LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
            LEFT JOIN mes.maquina ON maquina.id = opp.maquina_planificada_id
            WHERE opp.partida_id = p.id
        ), '[]'::jsonb),

        -- Input rolls reserved for this order
        'materiales_reservados', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', opi.id,
                'lote_id', opi.lote_id,
                'lote_codigo', EXTRACT(YEAR FROM l.fyh_cre)%100 || '-' || LPAD(l.secuencia::TEXT, 5, '0'),
                'item_id', l.item_id,
                'item_codigo', vi_mat.item_codigo,
                'item_nombre', vi_mat.item_nombre,
                'cantidad', l.cantidad,
                'unidad', vi_mat.unidad_codigo,
                'estado_calidad', l.estado_calidad,
                'guia_remision_id',   lrd_in.guia_remision_id,
                'ancho',              lrd_in.ancho,
                'malla',              lrd_in.malla,
                'flg_tenido',         lrd_in.flg_tenido,
                'flg_antipilling',    lrd_in.flg_antipilling,
                'color_x_cliente_id', lrd_in.color_x_cliente_id,
                'tenido_id',          lrd_in.tenido_id
            ) ORDER BY opi.id)
            FROM mes.partida_componente opi
            LEFT JOIN inventario.lote l ON l.id = opi.lote_id
            LEFT JOIN vw_items vi_mat ON vi_mat.item_id = l.item_id
            LEFT JOIN inventario.lote_rollo_detalle lrd_in ON lrd_in.lote_id = l.id
            WHERE opi.partida_id = p.id
        ), '[]'::jsonb),

        -- Finished goods produced
        'produccion', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', l.id,
                'lote_codigo', EXTRACT(YEAR FROM l.fyh_cre)%100 || '-' || LPAD(l.secuencia::TEXT, 5, '0'),
                'item_id', l.item_id,
                'item_codigo', vi_prod.item_codigo,
                'item_nombre', vi_prod.item_nombre,
                'cantidad', l.cantidad,
                'unidad', vi_prod.unidad_codigo,
                'estado_calidad', l.estado_calidad,
                'fyh_cre', l.fyh_cre,
                'guia_remision_id',   lrd_out.guia_remision_id,
                'ancho',              lrd_out.ancho,
                'malla',              lrd_out.malla,
                'rendimiento',        lrd_out.rendimiento,
                'flg_tenido',         lrd_out.flg_tenido,
                'flg_antipilling',    lrd_out.flg_antipilling,
                'color_x_cliente_id', lrd_out.color_x_cliente_id,
                'tenido_id',          lrd_out.tenido_id,
                'inspecciones', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', insp.id,
                        'resultado', insp.resultado,
                        'observacion', insp.observacion,
                        'empleado_id', insp.empleado_id,
                        'empleado_nombre', CONCAT(emp.nombre, ' ', emp.apellido),
                        'fyh_inspeccion', insp.fyh_inspeccion
                    ) ORDER BY insp.fyh_inspeccion DESC)
                    FROM calidad.inspeccion insp
                    LEFT JOIN mes.empleado emp ON emp.id = insp.empleado_id
                    WHERE insp.lote_id = l.id
                ), '[]'::jsonb)
            ) ORDER BY l.fyh_cre)
            FROM inventario.lote l
            JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
            JOIN mes.partida_paso opp ON opp.id = pe.partida_paso_id AND opp.partida_id = p.id
            LEFT JOIN vw_items vi_prod ON vi_prod.item_id = l.item_id
            LEFT JOIN inventario.lote_rollo_detalle lrd_out ON lrd_out.lote_id = l.id
            WHERE l.documento_tipo = 'partida_paso_ejecucion'
        ), '[]'::jsonb)

    ) INTO v_result
    FROM mes.partida p
    LEFT JOIN prioridad pri       ON pri.id = p.prioridad_id
    LEFT JOIN tercero c           ON c.id = p.tercero_id
    LEFT JOIN tenido              ON tenido.id = p.tenido_id
    LEFT JOIN vw_colores vc       ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN articulo_tipo at    ON at.id = p.articulo_tipo_id
    WHERE p.id = p_partida_id;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.get_partida(BIGINT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- GET COMPONENTES DISPONIBLES
-- Returns rolls assigned to a partida that still have stock
-- (i.e., not yet net-consumed by a production run).
-- Using vw_stock_lotes as the availability gate is intentional:
-- it handles annulled production correctly because anular_produccion
-- posts a counter-movement that restores stock, whereas a PROD_CONSUMO
-- movement-existence check would incorrectly hide re-available rolls.
-- Empty array = all rolls consumed; frontend can disable the form.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.get_componentes_disponibles(p_partida_id BIGINT)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario'
AS $function$
SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
        'lote_id',            pc.lote_id,
        'item_id',            l.item_id,
        'item_codigo',        i.codigo,
        'item_nombre',        i.nombre,
        'lote_codigo',        EXTRACT(YEAR FROM l.fyh_cre)%100 || '-' || LPAD(l.secuencia::TEXT, 5, '0'),
        'cantidad',           l.cantidad,
        'cantidad_reservada', pc.cantidad_reservada,
        'saldo_actual',       (
            SELECT SUM(cantidad_disponible)
            FROM inventario.vw_stock_lotes
            WHERE lote_id = pc.lote_id
        ),
        'estado_calidad',     l.estado_calidad,
        'flg_rib',            ird.flg_rib,
        'ancho',              lrd.ancho,
        'malla',              lrd.malla
    )
ORDER BY pc.lote_id), '[]'::jsonb)
FROM mes.partida_componente pc
JOIN inventario.lote l                      ON l.id        = pc.lote_id
JOIN item i                                 ON i.id        = l.item_id
LEFT JOIN item_rollo_detalle ird             ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id
WHERE pc.partida_id = p_partida_id
  AND pc.lote_id IS NOT NULL
  AND EXISTS (
      SELECT 1 FROM inventario.vw_stock_lotes
      WHERE lote_id = pc.lote_id
  );
$function$;

GRANT EXECUTE ON FUNCTION mes.get_componentes_disponibles(BIGINT) TO authenticated;

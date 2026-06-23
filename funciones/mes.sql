-- ═══════════════════════════════════════════════════════════════
-- 29. GET PROGRAMACION POR FECHA (daily board)
-- ═══════════════════════════════════════════════════════════════
-- SELECT mes.get_programacion_diaria('2026-05-28'::DATE);
-- SELECT * FROM mes.programacion WHERE id=1732
-- SELECT * FROm articulo WHERE nombre ILIKE '%gam%'

CREATE OR REPLACE FUNCTION mes.get_programacion_diaria(p_fecha DATE)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes','inventario','receta'
AS $$
WITH partidas_del_dia AS MATERIALIZED (
    -- Single scan of programacion for the date; both entregas_partida and rollos_partida reference this.
    SELECT pp2.partida_id
    FROM mes.programacion prog2
    JOIN mes.partida_paso pp2 ON pp2.id = prog2.actividad_id
    WHERE prog2.fecha = p_fecha AND prog2.actividad_tipo = 'partida_paso'
),
entregas_partida AS (
    SELECT
        pc.partida_id,
        jsonb_agg(DISTINCT jsonb_build_object(
            'tipo',   CASE WHEN lrd.entrega_id IS NOT NULL THEN 'entrega' ELSE 'os' END,
            'id',     COALESCE(lrd.entrega_id, lrd.orden_servicio_id),
            'codigo', COALESCE(gr.serie || '-' || gr.correlativo, os.serie || '-' || os.correlativo::text)
        )) AS entregas
    FROM mes.partida_componente        pc
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id
    LEFT JOIN doc.entrega        gr  ON gr.id = lrd.entrega_id
    LEFT JOIN doc.orden_servicio       os  ON os.id = lrd.orden_servicio_id
    WHERE pc.lote_id IS NOT NULL
      AND pc.partida_id IN (SELECT partida_id FROM partidas_del_dia)
    GROUP BY pc.partida_id
),
rollos_partida AS (
    SELECT
        pc.partida_id,
        COUNT(*) FILTER (WHERE ird.flg_rib = false) AS cantidad_regular,
        COUNT(*) FILTER (WHERE ird.flg_rib = true)  AS cantidad_rib,
        COUNT(*)                                     AS total_rollos
    FROM mes.partida_componente pc
    JOIN inventario.lote l      ON l.id        = pc.lote_id
    JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
    WHERE pc.lote_id IS NOT NULL
      AND pc.partida_id IN (SELECT partida_id FROM partidas_del_dia)
    GROUP BY pc.partida_id
)
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
        'receta_tenido_id',          pp.receta_id,
        'tipo_receta',               tr.tipo_receta,
        'paso_estado',               pp.estado,
        'partida_id',                p.id,
        'partida_origen_id',         p.partida_origen_id,
        'partida_codigo',            EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'cliente',                   c.nombre,
        'articulo_tipo_id',          p.articulo_tipo_id,
        'color',                     vc.color,
        'color_hex',                 vc.color_hex,
        'valor',                     vclr.valor,
        'tenido',                    t.tenido,
        'ancho',                     p.ancho,
        'malla',                     p.malla,
        'rendimiento',               p.rendimiento,
        'articulo',                  at.nombre,
        'fibra',                     p.fibra,
        'flg_antipilling',           p.flg_antipilling,
        'flg_doble_bolsa',           p.flg_doble_bolsa,
        'observacion',               p.observacion,
        'total_rollos',              rp.total_rollos,
        'cantidad_total',            rp.total_rollos,
        'cantidad_regular',          rp.cantidad_regular,
        'cantidad_rib',              rp.cantidad_rib,
        'entregas',                     gp.entregas,
        'ejecucion_fyh_inicio',      ppe.fyh_inicio,
        -- Lavado maquina fields (null when actividad_tipo = 'partida_paso')
        'lavado_id',                 lm.id,
        'lavado_estado',             lm.estado,
        'lavado_nota',               lm.nota,
        'lavado_fyh_inicio',         lm.fyh_inicio,
        'lavado_fyh_fin',            lm.fyh_fin,
        'empleado_id',               lm.empleado_id,
        'empleado',                  NULLIF(TRIM(COALESCE(emp.nombre,'') || ' ' || COALESCE(emp.apellido,'')), ''),
        'receta_lavado_maquina_id',  lm.receta_id,
        'tipo_lavado',               tlm.nombre,
        'color_origen',              vo.valor,
        'color_destino',             vd.valor
    ) AS row_obj
    FROM mes.programacion prog
    LEFT JOIN mes.partida_paso pp         ON prog.actividad_tipo = 'partida_paso' AND pp.id = prog.actividad_id
    LEFT JOIN mes.operacion o             ON o.id = pp.operacion_id
    LEFT JOIN receta.tenido rt            ON rt.id = pp.receta_id
    LEFT JOIN tipo_receta tr              ON tr.id = rt.tipo_receta_id
    LEFT JOIN mes.partida p               ON p.id = pp.partida_id
    LEFT JOIN tenido t                    ON t.id = p.tenido_id
    LEFT JOIN tercero c                   ON c.id = p.tercero_id
    LEFT JOIN vw_colores vc               ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN color_x_cliente cxc         ON cxc.id = p.color_x_cliente_id
    LEFT JOIN public.valor vclr           ON vclr.id = cxc.valor_id
    LEFT JOIN articulo_tipo at            ON at.id         = p.articulo_tipo_id
    LEFT JOIN rollos_partida rp           ON rp.partida_id = p.id
    LEFT JOIN entregas_partida gp            ON gp.partida_id = p.id
    LEFT JOIN mes.lavado_maquina lm       ON prog.actividad_tipo = 'LAVADO_MAQUINA' AND lm.id = prog.actividad_id
    LEFT JOIN receta.lavado_maquina rlm   ON rlm.id = lm.receta_id
    LEFT JOIN tipo_lavado_maquina tlm     ON tlm.id = rlm.tipo_lavado_mq_id
    LEFT JOIN public.valor vo             ON vo.id  = rlm.valor_origen_id
    LEFT JOIN public.valor vd             ON vd.id  = rlm.valor_destino_id
    LEFT JOIN mes.empleado emp            ON emp.id = lm.empleado_id
    LEFT JOIN mes.partida_paso_ejecucion ppe ON prog.actividad_tipo = 'partida_paso' AND ppe.partida_paso_id = pp.id AND ppe.estado = 'EN_PROCESO'
    WHERE prog.fecha = p_fecha
    ORDER BY prog.maquina_id, prog.secuencia
) sub;
$$;
-- SELECT mes.get_actividades_sin_programar();
-- SELECT mes.get_actividades_sin_programar();
-- Unified: returns both unprogrammed production pasos AND unprogrammed lavados
-- Frontend uses actividad_tipo to render the correct card type
CREATE OR REPLACE FUNCTION mes.get_actividades_sin_programar()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public','doc','mes','inventario','receta'
AS $$
WITH
pasos_pendientes AS MATERIALIZED (
    SELECT pp.id AS partida_paso_id, pp.partida_id
    FROM mes.partida_paso pp
    JOIN mes.partida p ON p.id = pp.partida_id
    WHERE p.estado_produccion NOT IN ('CERRADA', 'CANCELADA', 'TECO')
      AND p.fyh_elm IS NULL
      AND pp.estado NOT IN ('COMPLETADO', 'OMITIDO')
      AND EXISTS (
          SELECT 1 FROM mes.partida_componente pc
          WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
      )
      AND NOT EXISTS (
          SELECT 1 FROM mes.programacion prog
          WHERE prog.actividad_tipo = 'partida_paso'
            AND prog.actividad_id = pp.id
            AND prog.fecha >= CURRENT_DATE
      )
),
entregas_partida AS (
    SELECT
        pc.partida_id,
        jsonb_agg(DISTINCT jsonb_build_object(
            'tipo',   CASE WHEN lrd.entrega_id IS NOT NULL THEN 'entrega' ELSE 'os' END,
            'id',     COALESCE(lrd.entrega_id, lrd.orden_servicio_id),
            'codigo', COALESCE(gr.serie || '-' || gr.correlativo, os.serie || '-' || os.correlativo::text)
        )) AS entregas
    FROM mes.partida_componente        pc
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id
    LEFT JOIN doc.entrega        gr  ON gr.id = lrd.entrega_id
    LEFT JOIN doc.orden_servicio       os  ON os.id = lrd.orden_servicio_id
    WHERE pc.lote_id IS NOT NULL
      AND pc.partida_id IN (SELECT partida_id FROM pasos_pendientes)
    GROUP BY pc.partida_id
),
rollos_partida AS (
    SELECT
        pc.partida_id,
        COUNT(*) FILTER (WHERE ird.flg_rib = false) AS cantidad_regular,
        COUNT(*) FILTER (WHERE ird.flg_rib = true)  AS cantidad_rib,
        COUNT(*)                                     AS total_rollos
    FROM mes.partida_componente pc
    JOIN inventario.lote l      ON l.id        = pc.lote_id
    JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
    WHERE pc.lote_id IS NOT NULL
      AND pc.partida_id IN (SELECT partida_id FROM pasos_pendientes)
    GROUP BY pc.partida_id
)
SELECT COALESCE(jsonb_agg(row_obj ORDER BY fyh_cre DESC), '[]'::jsonb)
FROM (
    -- Production pasos (PENDIENTE, not yet on board)
    SELECT
        p.fyh_cre,
        jsonb_build_object(
            'actividad_tipo',     'partida_paso',
            'actividad_id',       pp.id,
            'paso_id',            pp.id,
            'partida_id',         p.id,
            'partida_origen_id',  p.partida_origen_id,
            'operacion_id',       o.id,
            'operacion',          o.nombre,
            'operacion_codigo',   o.codigo,
            'partida_codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
            'articulo_tipo_id',   p.articulo_tipo_id,
            'articulo_tipo',           at.nombre,
            'cliente',            c.nombre,
            'color',              vc.color,
            'color_hex',          vc.color_hex,
            'valor',              vclr.valor,
            'tenido',             t.tenido,
            'ancho',              p.ancho,
            'malla',              p.malla,
            'rendimiento',        p.rendimiento,
            'fibra',              p.fibra,
            'receta_tenido_id',   pp.receta_id,
            'tipo_receta',        tr.tipo_receta,
            'total_rollos',       rp.total_rollos,
            'cantidad_regular',   rp.cantidad_regular,
            'cantidad_rib',       rp.cantidad_rib,
            'entregas',              gp.entregas,
            'ejecucion_fyh_inicio', ppe.fyh_inicio
        ) AS row_obj
    FROM pasos_pendientes pend
    JOIN mes.partida_paso pp     ON pp.id = pend.partida_paso_id
    JOIN mes.operacion o         ON o.id  = pp.operacion_id
    JOIN mes.partida p           ON p.id  = pp.partida_id
    LEFT JOIN receta.tenido rt      ON rt.id  = pp.receta_id
    LEFT JOIN tipo_receta tr        ON tr.id  = rt.tipo_receta_id
    LEFT JOIN articulo_tipo at      ON at.id  = p.articulo_tipo_id
    LEFT JOIN tenido t              ON t.id   = p.tenido_id
    LEFT JOIN tercero c             ON c.id   = p.tercero_id
    LEFT JOIN vw_colores vc         ON vc.color_x_cliente_id = p.color_x_cliente_id
    LEFT JOIN color_x_cliente cxc   ON cxc.id = p.color_x_cliente_id
    LEFT JOIN public.valor vclr     ON vclr.id = cxc.valor_id
    LEFT JOIN entregas_partida gp      ON gp.partida_id = p.id
    LEFT JOIN rollos_partida rp     ON rp.partida_id = p.id
    LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id AND ppe.estado = 'EN_PROCESO'

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
    LEFT JOIN mes.programacion prog_lav
           ON prog_lav.actividad_tipo = 'LAVADO_MAQUINA'
          AND prog_lav.actividad_id   = lm.id
          AND prog_lav.fecha         >= CURRENT_DATE
    WHERE lm.estado = 'PENDIENTE'
      AND prog_lav.id IS NULL
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
    v_usr_id          INT := get_user_id();
    v_invalid_lavados JSONB;
    v_partida_id      BIGINT;
BEGIN
    IF NOT jwt_has_permission('produccion.programar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.programar'
            USING ERRCODE = 'insufficient_privilege';
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

    -- Advance/revert PLANIFICADA ↔ PROGRAMADA for every affected partida.
    -- actualizar_estado_partida is the single owner of estado_produccion.
    FOR v_partida_id IN
        SELECT DISTINCT pp.partida_id
        FROM mes.partida_paso pp
        WHERE pp.id IN (
            SELECT (elem->>'actividad_id')::BIGINT
            FROM jsonb_array_elements(p_programaciones) elem
            WHERE elem->>'actividad_tipo' = 'partida_paso'
        )
        UNION
        SELECT DISTINCT pp.partida_id
        FROM mes.partida_paso pp
        JOIN mes.programacion prog ON prog.actividad_tipo = 'partida_paso'
                                  AND prog.actividad_id = pp.id
        WHERE prog.fecha = p_fecha
    LOOP
        PERFORM mes.actualizar_estado_partida(v_partida_id);
    END LOOP;

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
-- SELECT mes.generar_receta(7513)
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
    v_rb               numeric;  -- effective bath ratio (resolved after batch weight is known)
    v_rb_paso          numeric;  -- order-step override (pp.relacion_bano_objetivo)
    v_rb_maquina       numeric;  -- machine standard ratio
    v_cap_min_kg       numeric;  -- machine minimum operational load (kg)
    v_peso             numeric;
    v_cantidad         numeric;
    v_cantidad_regular numeric;
    v_cantidad_rib     numeric;
    v_volumen          numeric;
    v_peso_volumen     numeric;  -- effective weight for volume calc (floored to cap_min_kg)
    v_flg_cap_minima   boolean;  -- true when batch is below machine minimum
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

    -- 1. Validate paso, get receta + machine capacity data.
    -- Machine resolved from programacion if the paso is already scheduled
    -- (scheduled machine is authoritative over planning intent).
    -- Falls back to maquina_planificada_id when not yet on the board.
    SELECT pp.receta_id,
           COALESCE(prog.maquina_id, pp.maquina_planificada_id),
           pp.relacion_bano_objetivo,
           m.relacion_bano, m.capacidad_min_kg,
           pp.partida_id, o.nombre
    INTO v_receta_id, v_maquina_id, v_rb_paso,
         v_rb_maquina, v_cap_min_kg,
         v_partida_id, v_op_nombre
    FROM mes.partida_paso pp
    LEFT JOIN mes.operacion o   ON o.id   = pp.operacion_id
    LEFT JOIN mes.programacion prog
           ON prog.actividad_tipo = 'partida_paso' AND prog.actividad_id = pp.id
    LEFT JOIN mes.maquina m     ON m.id   = COALESCE(prog.maquina_id, pp.maquina_planificada_id)
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
    --    Guard: all rolls must be weighed before recipe generation so that
    --    lote.cantidad reflects real weight, not the entrega-declared estimate.
    IF EXISTS (
        SELECT 1
        FROM mes.partida_componente pc
        JOIN inventario.lote l ON l.id = pc.lote_id
        WHERE pc.partida_id = v_partida_id
          AND pc.lote_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id
          )
    ) THEN
        RAISE EXCEPTION 'Todos los rollos deben estar pesados antes de generar la receta.'
            USING ERRCODE = 'P0001';
    END IF;

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

    -- 4. Resolve effective bath ratio, then compute volume.
    -- Order-step override wins; otherwise use machine's configured ratio.
    -- When batch weight is below machine minimum, volume is floored to cap_min_kg * rb
    -- so the bath covers the machine drum properly — g/L chemicals scale up accordingly.
    -- % chemicals always scale on actual fabric weight (v_peso), not the floor.
    v_rb           := COALESCE(v_rb_paso, v_rb_maquina);
    v_flg_cap_minima := v_cap_min_kg IS NOT NULL AND v_peso < v_cap_min_kg;
    v_peso_volumen := CASE WHEN v_flg_cap_minima THEN v_cap_min_kg ELSE v_peso END;
    v_volumen      := v_peso_volumen * v_rb;

    -- 5. Build JSON
    -- pasos: chemistry steps with nested insumos (new hierarchical model)
    -- Breaking change from flat insumos[]: frontend flattens pasos[].insumos[] for consumption form
    SELECT jsonb_build_object(
        'receta_id',         pp.receta_id,
        'partida_id',        p.id,
        'partida_origen_id', p.partida_origen_id,
        'tercero_id',        p.tercero_id,
        'observacion',       p.observacion,
        'flg_doble_bolsa',   p.flg_doble_bolsa,
        'flg_antipilling',   p.flg_antipilling,
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
        'cap_minima_aplicada', v_flg_cap_minima,
        'cap_min_kg',        v_cap_min_kg,
        'maquina',           jsonb_build_object(
                                 'id',     v_maquina_id,
                                 'codigo', v_maq_codigo,
                                 'nombre', v_maq_nombre
                             ),
        'costo_quimicos_kg', doc.fn_get_costo_receta(r.id),
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
                                'item_id',               rtpi.item_id,
                                'orden',                 rtpi.orden,
                                'codigo',                i.codigo,
                                'nombre',                i.nombre,
                                'cantidad',              rtpi.cantidad,
                                'medida',                iid.medida,
                                -- g/L × volume(L) and % × peso(kg) × 10 both yield GRAMS;
                                -- ÷1000 → kg (the item stock unit). 7 decimals keeps the
                                -- recipe's 4 gram-decimals after the 3-place shift (frontend ×1000 to show g).
                                'cantidad_requerida_kg', ROUND(CASE
                                    WHEN iid.medida = 'g/L' THEN rtpi.cantidad * v_volumen / 1000
                                    WHEN iid.medida = '%'   THEN rtpi.cantidad * v_peso * 10 / 1000
                                END, 7),
                                'precio_kg',             pr.precio_kg,
                                'costo_insumo',          ROUND(CASE
                                    WHEN iid.medida = 'g/L' THEN rtpi.cantidad * v_volumen / 1000
                                    WHEN iid.medida = '%'   THEN rtpi.cantidad * v_peso * 10 / 1000
                                    ELSE 0
                                END * pr.precio_kg, 4)
                            ) ORDER BY rtpi.orden
                        )
                        FROM receta.tenido_paso_insumo rtpi
                        JOIN item i                  ON i.id        = rtpi.item_id
                        JOIN item_insumo_detalle iid  ON iid.item_id = rtpi.item_id
                        LEFT JOIN LATERAL (
                            SELECT COALESCE(
                                (SELECT fpd.precio_unitario FROM doc.factura_proveedor_detalle fpd
                                 WHERE fpd.item_id = rtpi.item_id ORDER BY fpd.fyh_cre DESC LIMIT 1),
                                (SELECT cd.precio_unitario FROM doc.compra_detalle cd
                                 WHERE cd.item_id = rtpi.item_id ORDER BY cd.fyh_cre DESC LIMIT 1),
                                0
                            ) AS precio_kg
                        ) pr ON true
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
           -- ÷1000: g/L×L and %×kg×10 yield GRAMS; reserved qty is stored in kg (stock unit). 7 dp = 4 gram-decimals.
           ROUND(CASE
               WHEN iid.medida = 'g/L' THEN SUM(rtpi.cantidad) * v_volumen * iid.factor_stock / 1000
               WHEN iid.medida = '%'   THEN SUM(rtpi.cantidad) * v_peso    * 10 * iid.factor_stock / 1000
           END, 7),
           v_usr_id
    FROM receta.tenido_paso rtp
    JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id  = rtp.id
    JOIN item_insumo_detalle iid        ON iid.item_id   = rtpi.item_id
    WHERE rtp.receta_id = v_receta_id
    GROUP BY rtpi.item_id, iid.medida, iid.factor_stock;

    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id, 'Receta Generada',
           COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido
                     FROM usuario WHERE id = v_usr_id), 'sistema')
           || format(' generó la receta del paso %s (orden #%s)', v_op_nombre, v_partida_id), 'info',
           jsonb_build_object('objeto_tipo','partida_paso','paso_id', p_paso_id, 'partida_id', v_partida_id, 'partida_origen_id', (v_receta->>'partida_origen_id')::bigint)
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

    -- Create execution run record.
    -- fyh_inicio / fyh_cre accept a historical timestamp for backfill; live callers omit it → NOW().
    INSERT INTO mes.partida_paso_ejecucion(partida_paso_id, estado, maquina_id, empleado_id, fyh_inicio, programacion_id, receta_id, usr_cre, fyh_cre)
    VALUES (
        p_paso_id, 'EN_PROCESO',
        (p_datos->>'maquina_id')::INT,
        (p_datos->>'empleado_id')::SMALLINT,
        COALESCE((p_datos->>'fyh_inicio')::TIMESTAMPTZ, NOW()),
        (p_datos->>'programacion_id')::BIGINT,
        v_receta_id,
        v_usr_id,
        COALESCE((p_datos->>'fyh_inicio')::TIMESTAMPTZ, NOW())
    )
    RETURNING id INTO v_ejecucion_id;

    UPDATE mes.partida_paso SET estado = 'EN_PROCESO', fyh_mod = NOW() WHERE id = p_paso_id;

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
    v_usr_id            int     := get_user_id();
    v_consumos          jsonb;
    v_consumos_std      jsonb;
    v_egr_tipo_id       smallint;
    v_error_payload     jsonb;
    v_doc_movimiento_id BIGINT;
    v_ejecucion_id      BIGINT;
    v_fung_count        int := 0;
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
    VALUES ('registrar_consumo_paso', v_usr_id,
            jsonb_build_object('paso_id', p_paso_id, 'ejecucion_id', v_ejecucion_id, 'consumos', p_consumos));

    SELECT id INTO v_egr_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

    -- Stock check: fungible items bypass (may go negative)
    WITH consumos AS (
        SELECT (i->>'item_id')::int AS item_id, SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_consumos) i
        GROUP BY 1
    ),
    errores AS (
        SELECT c.item_id, it.nombre AS item_nombre, c.cantidad,
               COALESCE(sg.cantidad_total, 0) AS cantidad_disponible
        FROM consumos c
        LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = c.item_id
        JOIN item it ON it.id = c.item_id
        WHERE COALESCE(sg.cantidad_total, 0) < c.cantidad
          AND it.flg_fungible = FALSE
    )
    SELECT jsonb_agg(jsonb_build_object(
        'item_id', item_id, 'item_nombre', item_nombre,
        'saldo_disponible', cantidad_disponible, 'cantidad_requerida', cantidad
    ))
    INTO v_error_payload FROM errores;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente para emitir la guía'
            USING DETAIL = v_error_payload::text;
    END IF;

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- ── Non-fungible: FIFO lot resolution ───────────────────────
    SELECT jsonb_agg(i)
    INTO v_consumos_std
    FROM jsonb_array_elements(p_consumos) i
    JOIN item it ON it.id = (i->>'item_id')::int
    WHERE it.flg_fungible = FALSE;

    IF v_consumos_std IS NOT NULL THEN
        v_consumos := mes.calcular_fifo(v_consumos_std);

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario,
            documento_tipo, documento_id, motivo_id, observacion
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
            'partida_paso_ejecucion',
            v_ejecucion_id,
            p_consumo.motivo_id,
            p_consumo.observacion
        FROM jsonb_array_elements(v_consumos) v_consumo
        -- motivo_id/observacion taken from first entry per item_id
        JOIN (
            SELECT (pc->>'item_id') AS item_id,
                   MIN((pc->>'motivo_id')::SMALLINT) AS motivo_id,
                   MIN(pc->>'observacion')            AS observacion
            FROM jsonb_array_elements(p_consumos) pc
            GROUP BY pc->>'item_id'
        ) p_consumo ON v_consumo->>'item_id' = p_consumo.item_id;
    END IF;

    -- ── Fungible: lotless consumption ────────────────────────────
    -- Fallback chain for origen_ubicacion_id:
    --   1. highest-balance location from item_saldo
    --   2. last known ingress location from item_movimientos
    --   3. item_tipo.ubicacion_default_id
    --   4. NULL → trigger uses factor=-1, debits item_saldo(item_id, NULL)
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad, precio_unitario,
        documento_tipo, documento_id, motivo_id, observacion
    )
    SELECT
        v_doc_movimiento_id,
        fung.item_id,
        NULL,
        v_egr_tipo_id,
        COALESCE(
            (SELECT ubicacion_id FROM inventario.item_saldo
             WHERE item_id = fung.item_id
             ORDER BY cantidad_actual DESC LIMIT 1),
            (SELECT im2.origen_ubicacion_id FROM inventario.item_movimientos im2
             WHERE im2.item_id = fung.item_id
               AND im2.origen_ubicacion_id IS NOT NULL
             ORDER BY im2.id DESC LIMIT 1),
            (SELECT ity.ubicacion_default_id FROM item it2
             JOIN item_tipo ity ON ity.id = it2.item_tipo_id
             WHERE it2.id = fung.item_id)
        ),
        fung.cantidad,
        (SELECT precio_promedio FROM inventario.item_valoracion WHERE item_id = fung.item_id),
        'partida_paso_ejecucion',
        v_ejecucion_id,
        pc.motivo_id,
        pc.observacion
    FROM (
        SELECT (i->>'item_id')::int AS item_id,
               SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_consumos) i
        JOIN item it ON it.id = (i->>'item_id')::int
        WHERE it.flg_fungible = TRUE
        GROUP BY 1
    ) fung
    JOIN (
        SELECT (pc->>'item_id') AS item_id,
               MIN((pc->>'motivo_id')::SMALLINT) AS motivo_id,
               MIN(pc->>'observacion')            AS observacion
        FROM jsonb_array_elements(p_consumos) pc
        GROUP BY pc->>'item_id'
    ) pc ON fung.item_id::text = pc.item_id;

    GET DIAGNOSTICS v_fung_count = ROW_COUNT;

    RETURN format('%s consumos registrados para paso #%s.',
                  COALESCE(jsonb_array_length(v_consumos), 0) + v_fung_count,
                  p_paso_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_consumo_paso - User: %, paso: %, Error: %, Detail: %',
              v_usr_id, p_paso_id, v_message, v_detail;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- 23b-0. VALIDAR DISPONIBILIDAD — pre-flight stock check
--        Read-only. Frontend calls this before finalizar_paso to
--        show availability inline. bloqueante=true means the item
--        has a deficit and is not fungible — submission must wait.
--        bloqueante=false with deficit means fungible: warn but allow.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.validar_disponibilidad(p_consumos jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'inventario', 'mes'
AS $function$
SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
        'item_id',            agg.item_id,
        'item_nombre',        agg.item_nombre,
        'cantidad_requerida', agg.cantidad_requerida,
        'cantidad_disponible', agg.cantidad_disponible,
        'deficit',            GREATEST(agg.cantidad_requerida - agg.cantidad_disponible, 0),
        'flg_fungible',       agg.flg_fungible,
        'bloqueante',         (agg.cantidad_disponible < agg.cantidad_requerida
                               AND NOT agg.flg_fungible)
    )
    ORDER BY agg.bloqueante DESC, agg.item_nombre
), '[]'::jsonb)
FROM (
    SELECT
        it.id                                      AS item_id,
        it.nombre                                  AS item_nombre,
        SUM((i->>'cantidad')::numeric)             AS cantidad_requerida,
        COALESCE(sg.cantidad_total, 0)             AS cantidad_disponible,
        it.flg_fungible,
        (COALESCE(sg.cantidad_total, 0) < SUM((i->>'cantidad')::numeric)
         AND NOT it.flg_fungible)                  AS bloqueante
    FROM jsonb_array_elements(p_consumos) i
    JOIN item it           ON it.id = (i->>'item_id')::int
    LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = it.id
    GROUP BY it.id, it.nombre, it.flg_fungible, sg.cantidad_total
) agg;
$function$;

GRANT EXECUTE ON FUNCTION mes.validar_disponibilidad(jsonb) TO authenticated;


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


-- ═══════════════════════════════════════════════════════════════
-- 23b-i. GET MATIZADO — current net matizado consumos for a paso
--        Aggregates by item across FIFO lots. Excludes already-
--        reversed amounts so the result always reflects the net
--        state (useful for pre-populating the correction form).
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.get_matizado(p_ejecucion_id BIGINT)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario'
AS $function$
SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
        'item_id',     agg.item_id,
        'item_codigo', agg.item_codigo,
        'item_nombre', agg.item_nombre,
        'cantidad',    agg.cantidad
    )
    ORDER BY agg.item_nombre
), '[]'::jsonb)
FROM (
    SELECT m.item_id, i.codigo AS item_codigo, i.nombre AS item_nombre,
           SUM(m.cantidad) AS cantidad
    FROM inventario.item_movimientos m
    JOIN item i ON i.id = m.item_id
    WHERE m.documento_tipo          = 'partida_paso_ejecucion'
      AND m.documento_id            = p_ejecucion_id
      AND m.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo   WHERE codigo = 'PROD_CONSUMO')
      AND m.motivo_id               = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO')
    GROUP BY m.item_id, i.codigo, i.nombre
) agg;
$function$;

GRANT EXECUTE ON FUNCTION mes.get_matizado(BIGINT) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- 23c. CORREGIR MATIZADO — surgical post-completion correction
--      Works on a COMPLETADO execution. Reverses existing MATIZADO
--      consumos and posts new ones with the supplied quantities.
--      Step state (COMPLETADO) and output lotes are untouched.
--      One correction per execution; use anular_produccion to redo
--      from scratch if a second correction is needed.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.corregir_matizado(p_ejecucion_id BIGINT, p_consumos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id              int     := get_user_id();
    v_consumo_tipo_id     smallint;
    v_consumo_rev_id      smallint;
    v_matizado_motivo_id  smallint;
    v_doc_movimiento_id   BIGINT;
    v_rev_count           int;
    v_consumos_fifo       jsonb;
    v_consumos_std        jsonb;
    v_error_payload       jsonb;
    v_fung_count          int := 0;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Validate ejecucion exists and is COMPLETADO
    IF NOT EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion
        WHERE id = p_ejecucion_id AND estado = 'COMPLETADO'
    ) THEN
        RAISE EXCEPTION 'Ejecución #% no encontrada o no está COMPLETADA.', p_ejecucion_id;
    END IF;

    -- 2. Fetch movement type / motivo IDs
    SELECT id INTO v_consumo_tipo_id    FROM inventario.item_movimiento_tipo   WHERE codigo = 'PROD_CONSUMO';
    SELECT id INTO v_consumo_rev_id     FROM inventario.item_movimiento_tipo   WHERE codigo = 'PROD_CONSUMO_REV';
    SELECT id INTO v_matizado_motivo_id FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO';

    -- 3. Guard: one correction per execution — motivo_id on REV distinguishes this from anular_produccion
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos
        WHERE documento_tipo          = 'partida_paso_ejecucion'
          AND documento_id            = p_ejecucion_id
          AND item_movimiento_tipo_id = v_consumo_rev_id
          AND motivo_id               = v_matizado_motivo_id
    ) THEN
        RAISE EXCEPTION
            'La ejecución #% ya tiene una corrección de matizado aplicada. Para corregir nuevamente use anular_produccion y rehaga el paso desde cero.',
            p_ejecucion_id;
    END IF;

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- 4. Reverse all existing MATIZADO consumos for this execution
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id, motivo_id
    )
    SELECT
        v_doc_movimiento_id,
        m.item_id,
        m.lote_id,
        v_consumo_rev_id,
        m.origen_ubicacion_id,
        m.cantidad,
        'partida_paso_ejecucion',
        p_ejecucion_id,
        v_matizado_motivo_id
    FROM inventario.item_movimientos m
    WHERE m.documento_tipo          = 'partida_paso_ejecucion'
      AND m.documento_id            = p_ejecucion_id
      AND m.item_movimiento_tipo_id = v_consumo_tipo_id
      AND m.motivo_id               = v_matizado_motivo_id;

    GET DIAGNOSTICS v_rev_count = ROW_COUNT;

    -- v_rev_count = 0 is valid: retroactive registration (matizado was never recorded)

    -- 5. Stock check against new quantities (reversal already visible within this tx)
    WITH consumos AS (
        SELECT (i->>'item_id')::int AS item_id, SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_consumos) i
        GROUP BY 1
    ),
    errores AS (
        SELECT c.item_id, it.nombre AS item_nombre, c.cantidad,
               COALESCE(sg.cantidad_total, 0) AS cantidad_disponible
        FROM consumos c
        LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = c.item_id
        JOIN item it ON it.id = c.item_id
        WHERE COALESCE(sg.cantidad_total, 0) < c.cantidad
          AND it.flg_fungible = FALSE
    )
    SELECT jsonb_agg(jsonb_build_object(
        'item_id', item_id, 'item_nombre', item_nombre,
        'saldo_disponible', cantidad_disponible, 'cantidad_requerida', cantidad
    ))
    INTO v_error_payload FROM errores;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente para corregir matizado'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- ── Non-fungible: FIFO ───────────────────────────────────────
    SELECT jsonb_agg(item || jsonb_build_object('motivo_id', v_matizado_motivo_id))
    INTO v_consumos_std
    FROM jsonb_array_elements(p_consumos) AS item
    JOIN item it ON it.id = (item->>'item_id')::int
    WHERE it.flg_fungible = FALSE;

    IF v_consumos_std IS NOT NULL THEN
        v_consumos_fifo := mes.calcular_fifo(v_consumos_std);

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario,
            documento_tipo, documento_id, motivo_id
        )
        SELECT
            v_doc_movimiento_id,
            (v->>'item_id')::INT,
            (v->>'lote_id')::INT,
            v_consumo_tipo_id,
            (v->>'ubicacion_id')::INT,
            (v->>'cantidad')::NUMERIC,
            (SELECT iv.precio_promedio FROM inventario.item_valoracion iv
             WHERE iv.item_id = (v->>'item_id')::INT),
            'partida_paso_ejecucion',
            p_ejecucion_id,
            v_matizado_motivo_id
        FROM jsonb_array_elements(v_consumos_fifo) v;
    END IF;

    -- ── Fungible: lotless with fallback chain ────────────────────
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad, precio_unitario,
        documento_tipo, documento_id, motivo_id
    )
    SELECT
        v_doc_movimiento_id,
        fung.item_id,
        NULL,
        v_consumo_tipo_id,
        COALESCE(
            (SELECT ubicacion_id FROM inventario.item_saldo
             WHERE item_id = fung.item_id
             ORDER BY cantidad_actual DESC LIMIT 1),
            (SELECT im2.origen_ubicacion_id FROM inventario.item_movimientos im2
             WHERE im2.item_id = fung.item_id
               AND im2.origen_ubicacion_id IS NOT NULL
             ORDER BY im2.id DESC LIMIT 1),
            (SELECT ity.ubicacion_default_id FROM item it2
             JOIN item_tipo ity ON ity.id = it2.item_tipo_id
             WHERE it2.id = fung.item_id)
        ),
        fung.cantidad,
        (SELECT precio_promedio FROM inventario.item_valoracion WHERE item_id = fung.item_id),
        'partida_paso_ejecucion',
        p_ejecucion_id,
        v_matizado_motivo_id
    FROM (
        SELECT (i->>'item_id')::int AS item_id,
               SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_consumos) i
        JOIN item it ON it.id = (i->>'item_id')::int
        WHERE it.flg_fungible = TRUE
        GROUP BY 1
    ) fung;

    GET DIAGNOSTICS v_fung_count = ROW_COUNT;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('corregir_matizado', v_usr_id,
            jsonb_build_object('ejecucion_id', p_ejecucion_id, 'consumos', p_consumos));

    RETURN CASE
        WHEN v_rev_count = 0
        THEN format('Matizado registrado retroactivamente en ejecución #%s.', p_ejecucion_id)
        ELSE format('Matizado corregido en ejecución #%s: %s movimientos revertidos, nuevos consumos registrados.', p_ejecucion_id, v_rev_count)
    END;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in corregir_matizado - User: %, ejecucion: %, Error: %, Detail: %',
              v_usr_id, p_ejecucion_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.corregir_matizado(BIGINT, jsonb) TO authenticated;


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
    -- Pre-aggregate by item_id before joining to stock: duplicate item_ids in p_items
    -- would otherwise double every stock lot in the window partition, causing the running
    -- sum to be inflated and silently dropping some of the requested quantity.
    WITH input_agg AS (
        SELECT (i->>'item_id')::INT AS item_id, SUM((i->>'cantidad')::NUMERIC) AS cantidad
        FROM jsonb_array_elements(p_items) i
        GROUP BY 1
    ),
    fifo AS (
        SELECT
            st.lote_id,
            st.item_id,
            st.ubicacion_id,
            st.cantidad_disponible,
            st.fecha_hora_ingreso,
            inp.cantidad AS cantidad_solicitada,
            SUM(st.cantidad_disponible) OVER (
                PARTITION BY st.item_id ORDER BY st.fecha_hora_ingreso
            ) AS cantidad_acumulada
        FROM inventario.vw_stock_lotes_ubicacion st
        JOIN input_agg inp ON inp.item_id = st.item_id
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
    v_entrega_id      bigint;
    v_orden_servicio_id     bigint;
    v_factura_hilo          TEXT;
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
    --     and lote_rollo_detalle carrying entrega_id forward.
    FOR v_elem IN SELECT value FROM jsonb_array_elements(v_p_output)
    LOOP
        v_input_lote_id := (v_elem->>'input_lote_id')::INT;

        -- Inherit item_id, propietario, billing anchor, rib flag, and original quantity from input lote
        SELECT l.item_id, l.propietario_id, lrd.entrega_id, lrd.orden_servicio_id, lrd.factura_hilo, ird.flg_rib, l.cantidad
        INTO v_out_item_id, v_out_propietario, v_entrega_id, v_orden_servicio_id, v_factura_hilo, v_flg_rib, v_lote_cantidad
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

        -- Batch classification: carry ingress doc anchor + factura_hilo + parent-batch link forward;
        -- populate dyeing identity from partida.
        INSERT INTO inventario.lote_rollo_detalle(
            lote_id, entrega_id, orden_servicio_id, factura_hilo, origen_lote_id,
            ancho, malla, rendimiento,
            color_x_cliente_id, tenido_id,
            flg_tenido, flg_antipilling
        )
        VALUES (
            v_new_lote_id, v_entrega_id, v_orden_servicio_id, v_factura_hilo, v_input_lote_id,
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

    -- 5. Sync confirmed roll count onto the order item.
    -- Recounts all non-deleted output lotes across ALL ejecuciones for this partida,
    -- not just the current run — correct for send-ahead (multiple runs on same paso).
    UPDATE mes.partida_detalle pd
    SET cantidad_producida = (
        SELECT COUNT(*)
        FROM inventario.lote l
        JOIN mes.partida_paso_ejecucion pe
            ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        WHERE pp.partida_id = v_partida_id
          AND l.item_id     = pd.item_id
          AND l.fyh_elm     IS NULL
    ),
    usr_mod = v_usr_id,
    fyh_mod = NOW()
    WHERE pd.partida_id = v_partida_id;

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
    v_usr_id            int := get_user_id();
    v_partida_id        bigint;
    v_maquina_id        int;
    v_ejecucion_id      bigint;
    v_op_nombre         text;
    v_op_codigo         text;
    v_rollos_asignados  int;
    v_prod_result       text;
    v_variance_payload  jsonb;
    v_peso_kg           numeric;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Fetch paso info and its active execution run in one shot
    SELECT pp.partida_id, o.nombre, o.codigo, pe.id, pe.maquina_id
    INTO v_partida_id, v_op_nombre, v_op_codigo, v_ejecucion_id, v_maquina_id
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
    WHERE pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso #% no encontrado o sin ejecución EN_PROCESO.', p_paso_id;
    END IF;

    -- Cantidad guard: existing COMPLETADO runs + this submission must not exceed assigned rolls.
    -- Mirrors the same guard in the backfill function. Skipped when cantidad is not submitted.
    IF (p_datos->>'cantidad_rollos') IS NOT NULL THEN
        SELECT COUNT(*) INTO v_rollos_asignados
        FROM mes.partida_componente
        WHERE partida_id = v_partida_id AND lote_id IS NOT NULL;

        IF (p_datos->>'cantidad_rollos')::NUMERIC +
           COALESCE((
               SELECT SUM(pe2.cantidad_rollos)
               FROM mes.partida_paso_ejecucion pe2
               WHERE pe2.partida_paso_id = p_paso_id
                 AND pe2.estado = 'COMPLETADO'
           ), 0) > v_rollos_asignados
        THEN
            RAISE EXCEPTION 'La cantidad (%) excede los % rollos asignados a la partida.',
                (p_datos->>'cantidad_rollos')::NUMERIC, v_rollos_asignados;
        END IF;
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

    -- Snapshot peso_kg at close time: immune to future reproceso splits.
    -- Final step (registrar_produccion called): use output lote weights.
    -- Non-final step: prorate total input roll weight by this run's roll fraction.
    SELECT COALESCE(
        (SELECT SUM(l.cantidad) FROM inventario.lote l
         WHERE l.documento_tipo = 'partida_paso_ejecucion'
           AND l.documento_id   = v_ejecucion_id
           AND l.fyh_elm IS NULL),
        (SELECT ROUND(
             SUM(l.cantidad)
             * COALESCE((p_datos->>'cantidad_rollos')::numeric, MAX(totals.cnt))
             / NULLIF(MAX(totals.cnt), 0),
             4)
         FROM mes.partida_componente pc
         JOIN inventario.lote l ON l.id = pc.lote_id
         CROSS JOIN (
             SELECT COUNT(*)::numeric AS cnt
             FROM mes.partida_componente
             WHERE partida_id = v_partida_id AND lote_id IS NOT NULL
         ) totals
         WHERE pc.partida_id = v_partida_id AND pc.lote_id IS NOT NULL)
    ) INTO v_peso_kg;

    -- Close the execution run with actual measured params.
    -- fyh_fin accepts a historical timestamp for backfill; live callers omit it → NOW().
    UPDATE mes.partida_paso_ejecucion
    SET estado             = 'COMPLETADO',
        fyh_fin            = COALESCE((p_datos->>'fyh_fin')::TIMESTAMPTZ, NOW()),
        ph_real            = COALESCE((p_datos->>'ph_real')::NUMERIC,            ph_real),
        temperatura_real   = COALESCE((p_datos->>'temperatura_real')::NUMERIC,   temperatura_real),
        relacion_bano_real = COALESCE((p_datos->>'relacion_bano_real')::NUMERIC, relacion_bano_real),
        cantidad_rollos    = COALESCE((p_datos->>'cantidad_rollos')::NUMERIC,           cantidad_rollos),
        cantidad_scrap     = COALESCE((p_datos->>'cantidad_scrap')::NUMERIC,     cantidad_scrap),
        notas              = COALESCE(p_datos->>'notas',                         notas),
        ancho_entrada      = COALESCE((p_datos->>'ancho_entrada')::NUMERIC,      ancho_entrada),
        ancho_salida       = COALESCE((p_datos->>'ancho_salida')::NUMERIC,       ancho_salida),
        velocidad          = COALESCE((p_datos->>'velocidad')::NUMERIC,          velocidad),
        entrada            = COALESCE((p_datos->>'entrada')::NUMERIC,            entrada),
        salida             = COALESCE((p_datos->>'salida')::NUMERIC,             salida),
        rendimiento        = COALESCE((p_datos->>'rendimiento')::NUMERIC,        rendimiento),
        pases              = COALESCE((p_datos->>'pases')::SMALLINT,             pases),
        malla_alimentacion = COALESCE((p_datos->>'malla_alimentacion')::NUMERIC, malla_alimentacion),
        peso_kg            = v_peso_kg,
        usr_mod            = v_usr_id,
        fyh_mod            = NOW()
    WHERE id = v_ejecucion_id;

    -- Paso is COMPLETADO only when cumulative confirmed quantity covers all assigned rolls.
    -- Multiple ejecuciones per paso are normal (one machine run per batch subset).
    UPDATE mes.partida_paso
    SET estado = CASE
            WHEN (
                SELECT COALESCE(SUM(pe.cantidad_rollos) FILTER (WHERE pe.estado = 'COMPLETADO'), 0)
                FROM mes.partida_paso_ejecucion pe
                WHERE pe.partida_paso_id = p_paso_id
            ) >= (
                SELECT COUNT(*)
                FROM mes.partida_componente pc
                WHERE pc.partida_id = v_partida_id
                  AND pc.lote_id IS NOT NULL
            ) THEN 'COMPLETADO'::partida_paso_estado_enum
            ELSE 'EN_PROCESO'::partida_paso_estado_enum
        END,
        fyh_mod = NOW()
    WHERE id = p_paso_id;

    -- TERMOFIJADO extension: fields with no cross-operation meaning.
    -- ancho_entrada / ancho_salida / temperatura_real are on the base update above.
    IF v_op_codigo = 'TERMOFIJADO' THEN
        INSERT INTO mes.partida_paso_ejecucion_termofijado (
            ejecucion_id,
            ancho_marco, vel_maquina, vel_alimentacion,
            densidad_entrada, densidad_salida,
            lm, galga,
            usr_cre, fyh_cre
        ) VALUES (
            v_ejecucion_id,
            (p_datos->>'ancho_marco')::numeric,
            (p_datos->>'vel_maquina')::numeric,
            (p_datos->>'vel_alimentacion')::numeric,
            (p_datos->>'densidad_entrada')::numeric,
            (p_datos->>'densidad_salida')::numeric,
            (p_datos->>'lm')::numeric,
            (p_datos->>'galga')::numeric,
            v_usr_id, NOW()
        )
        ON CONFLICT (ejecucion_id) DO UPDATE SET
            ancho_marco      = EXCLUDED.ancho_marco,
            vel_maquina      = EXCLUDED.vel_maquina,
            vel_alimentacion = EXCLUDED.vel_alimentacion,
            densidad_entrada = EXCLUDED.densidad_entrada,
            densidad_salida  = EXCLUDED.densidad_salida,
            lm               = EXCLUDED.lm,
            galga            = EXCLUDED.galga,
            usr_mod          = v_usr_id,
            fyh_mod          = NOW();
    END IF;

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

    UPDATE mes.partida_paso SET estado = 'OMITIDO', fyh_mod = NOW() WHERE id = p_paso_id;

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
-- mes.revertir_inicio_paso
-- Undo an accidental Iniciar: an EN_PROCESO run with no work recorded
-- reverts to PENDIENTE and its run row is deleted.
--
-- Self-service (produccion.ejecutar, no motivo) because the guards make
-- it non-destructive — there is nothing to unwind. Anything with recorded
-- consumos or output must go through anular_produccion instead.
--
-- Guard: the paso must have an EN_PROCESO run.
-- Guard: no item_movimientos on the run (no consumos / matizados).
-- Guard: no output lotes created by the run.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.revertir_inicio_paso(p_paso_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int := get_user_id();
    v_partida_id    bigint;
    v_op_nombre     text;
    v_maquina_id    int;
    v_ejecucion_id  bigint;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Resolve the active run for this paso
    SELECT pp.partida_id, o.nombre, pe.id, pe.maquina_id
    INTO   v_partida_id, v_op_nombre, v_ejecucion_id, v_maquina_id
    FROM   mes.partida_paso pp
    JOIN   mes.operacion o ON o.id = pp.operacion_id
    JOIN   mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
    WHERE  pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso #% no tiene una ejecución EN_PROCESO para revertir.', p_paso_id;
    END IF;

    -- Guard: nothing consumed on this run
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos
        WHERE documento_tipo = 'partida_paso_ejecucion'
          AND documento_id   = v_ejecucion_id
    ) THEN
        RAISE EXCEPTION
            'No se puede deshacer el inicio del paso %: ya tiene consumos registrados. Use anular_produccion.',
            v_op_nombre;
    END IF;

    -- Guard: no output lotes produced by this run
    IF EXISTS (
        SELECT 1 FROM inventario.lote
        WHERE documento_tipo = 'partida_paso_ejecucion'
          AND documento_id   = v_ejecucion_id
    ) THEN
        RAISE EXCEPTION
            'No se puede deshacer el inicio del paso %: ya registró producción. Use anular_produccion.',
            v_op_nombre;
    END IF;

    -- iniciar_paso only inserted the run row — safe to DELETE
    DELETE FROM mes.partida_paso_ejecucion WHERE id = v_ejecucion_id;

    -- Reset paso: PENDIENTE if this was the only run, else keep EN_PROCESO (partial batches remain)
    UPDATE mes.partida_paso
    SET estado = CASE
            WHEN EXISTS (
                SELECT 1 FROM mes.partida_paso_ejecucion
                WHERE partida_paso_id = p_paso_id
            ) THEN 'EN_PROCESO'::partida_paso_estado_enum
            ELSE 'PENDIENTE'::partida_paso_estado_enum
        END,
        fyh_mod = NOW()
    WHERE id = p_paso_id;

    -- Release the machine the start had marked active
    IF v_maquina_id IS NOT NULL THEN
        UPDATE mes.maquina SET estado_actual = 'espera' WHERE id = v_maquina_id;
    END IF;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('revertir_inicio_paso', v_usr_id,
            jsonb_build_object('paso_id', p_paso_id, 'ejecucion_id', v_ejecucion_id));

    RETURN format('Inicio del paso %s (#%s) deshecho. El paso vuelve a estar disponible.',
                  v_op_nombre, p_paso_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in revertir_inicio_paso - User: %, Paso: %, Error: %, Detail: %',
              v_usr_id, p_paso_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.revertir_inicio_paso(BIGINT) TO authenticated;


-- iniciar_lavado / finalizar_lavado removed — superseded by iniciar_lavado_maquina,
-- finalizar_lavado_maquina, and registrar_lavado_maquina (support backdated timestamps).

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
--     cantidad_scrap     NUMERIC     (optional — rolls condemned mid-execution)
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
    v_receta_id        INT;
    v_paso_count       INT := 0;
    v_already_executed BIGINT;
    v_rollos_asignados INT;
    v_overflow_paso    BIGINT;
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

    SELECT COUNT(*) INTO v_rollos_asignados
    FROM mes.partida_componente
    WHERE partida_id = v_partida_id AND lote_id IS NOT NULL;
    IF jsonb_array_length(p_data->'pasos') = 0 THEN
        RAISE EXCEPTION 'Se requiere al menos un paso en p_data.pasos.';
    END IF;

    -- Idempotency guard: reject exact duplicate runs (same paso_id + fyh_inicio + maquina_id).
    -- Allows multiple runs per paso: interrupted/restarted steps and parallel runs on different machines.
    SELECT pe.partida_paso_id INTO v_already_executed
    FROM mes.partida_paso_ejecucion pe
    JOIN (
        SELECT (el->>'paso_id')::BIGINT         AS paso_id,
               (el->>'fyh_inicio')::TIMESTAMPTZ AS fyh_inicio,
               (el->>'maquina_id')::INT         AS maquina_id
        FROM jsonb_array_elements(p_data->'pasos') el
    ) submitted ON submitted.paso_id   = pe.partida_paso_id
               AND submitted.fyh_inicio = pe.fyh_inicio
               AND submitted.maquina_id IS NOT DISTINCT FROM pe.maquina_id
    LIMIT 1;

    IF v_already_executed IS NOT NULL THEN
        RAISE EXCEPTION
            'Ya existe una ejecución para el paso % con el mismo fyh_inicio y máquina. Posible envío duplicado.',
            v_already_executed;
    END IF;

    -- Cantidad guard: per-paso, existing + submitted cantidad must not exceed assigned roll count.
    -- Only checked when cantidad is provided; NULL means not recorded for this run.
    SELECT s.paso_id INTO v_overflow_paso
    FROM (
        SELECT
            sub.paso_id,
            COALESCE(SUM(pe.cantidad_rollos), 0) + sub.cantidad_submitted AS total
        FROM (
            SELECT (el->>'paso_id')::BIGINT          AS paso_id,
                   SUM((el->>'cantidad_rollos')::NUMERIC)   AS cantidad_submitted
            FROM jsonb_array_elements(p_data->'pasos') el
            WHERE (el->>'cantidad_rollos') IS NOT NULL
            GROUP BY (el->>'paso_id')::BIGINT
        ) sub
        LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = sub.paso_id
        GROUP BY sub.paso_id, sub.cantidad_submitted
    ) s
    WHERE s.total > v_rollos_asignados
    LIMIT 1;

    IF v_overflow_paso IS NOT NULL THEN
        RAISE EXCEPTION
            'El paso % excede los % rollos asignados a la partida.',
            v_overflow_paso, v_rollos_asignados;
    END IF;

    FOR v_paso IN SELECT * FROM jsonb_array_elements(p_data->'pasos') LOOP
        v_paso_id := (v_paso->>'paso_id')::BIGINT;

        IF v_paso_id IS NULL THEN
            RAISE EXCEPTION 'Cada paso debe incluir paso_id.';
        END IF;

        SELECT receta_id INTO v_receta_id FROM mes.partida_paso WHERE id = v_paso_id;
        IF (v_paso->>'fyh_inicio') IS NULL OR (v_paso->>'fyh_fin') IS NULL THEN
            RAISE EXCEPTION 'Cada paso debe incluir fyh_inicio y fyh_fin (paso_id=%).', v_paso_id;
        END IF;

        -- Insert as EN_PROCESO first so registrar_consumo_paso and registrar_produccion
        -- can find the row via their estado = 'EN_PROCESO' guard.
        -- fyh_fin is withheld until after inventory side-effects are written, then patched
        -- to the historical timestamp.  fyh_cre mirrors fyh_inicio so reporting looks correct.
        -- No trigger on partida_paso_ejecucion overrides fyh_cre, so this is safe.
        INSERT INTO mes.partida_paso_ejecucion(
            partida_paso_id,
            estado,
            fyh_inicio,
            fyh_fin,
            empleado_id,
            maquina_id,
            receta_id,
            ph_real,
            temperatura_real,
            relacion_bano_real,
            cantidad_rollos,
            cantidad_scrap,
            notas,
            ancho_entrada,
            ancho_salida,
            velocidad,
            entrada,
            salida,
            rendimiento,
            pases,
            malla_alimentacion,
            usr_cre,
            fyh_cre
        ) VALUES (
            v_paso_id,
            'EN_PROCESO',
            (v_paso->>'fyh_inicio')::TIMESTAMPTZ,
            NULL,                                   -- patched to historical value below
            (v_paso->>'empleado_id')::SMALLINT,
            (v_paso->>'maquina_id')::INT,
            v_receta_id,
            (v_paso->>'ph_real')::NUMERIC,
            (v_paso->>'temperatura_real')::NUMERIC,
            (v_paso->>'relacion_bano_real')::NUMERIC,
            (v_paso->>'cantidad_rollos')::NUMERIC,
            (v_paso->>'cantidad_scrap')::NUMERIC,
            v_paso->>'observacion',
            (v_paso->>'ancho_entrada')::NUMERIC,
            (v_paso->>'ancho_salida')::NUMERIC,
            (v_paso->>'velocidad')::NUMERIC,
            (v_paso->>'entrada')::NUMERIC,
            (v_paso->>'salida')::NUMERIC,
            (v_paso->>'rendimiento')::NUMERIC,
            (v_paso->>'pases')::SMALLINT,
            (v_paso->>'malla_alimentacion')::NUMERIC,
            v_usr_id,
            (v_paso->>'fyh_inicio')::TIMESTAMPTZ
        ) RETURNING id INTO v_ejecucion_id;

        IF v_paso->'consumos' IS NOT NULL AND jsonb_array_length(v_paso->'consumos') > 0 THEN
            PERFORM mes.registrar_consumo_paso(v_paso_id, v_paso->'consumos');
        END IF;

        IF v_paso->'produccion' IS NOT NULL THEN
            PERFORM mes.registrar_produccion(v_ejecucion_id, v_paso->'produccion');
        END IF;

        -- Seal the ejecucion with the historical end timestamp + snapshotted weight.
        UPDATE mes.partida_paso_ejecucion
        SET estado  = 'COMPLETADO',
            fyh_fin = (v_paso->>'fyh_fin')::TIMESTAMPTZ,
            peso_kg = COALESCE(
                (SELECT SUM(l.cantidad) FROM inventario.lote l
                 WHERE l.documento_tipo = 'partida_paso_ejecucion'
                   AND l.documento_id   = v_ejecucion_id
                   AND l.fyh_elm IS NULL),
                (SELECT ROUND(
                     SUM(l.cantidad)
                     * COALESCE((v_paso->>'cantidad_rollos')::numeric, MAX(totals.cnt))
                     / NULLIF(MAX(totals.cnt), 0),
                     4)
                 FROM mes.partida_componente pc
                 JOIN inventario.lote l ON l.id = pc.lote_id
                 CROSS JOIN (
                     SELECT COUNT(*)::numeric AS cnt
                     FROM mes.partida_componente
                     WHERE partida_id = v_partida_id AND lote_id IS NOT NULL
                 ) totals
                 WHERE pc.partida_id = v_partida_id AND pc.lote_id IS NOT NULL)
            )
        WHERE id = v_ejecucion_id;

        UPDATE mes.partida_paso
        SET estado = CASE
                WHEN (
                    SELECT COALESCE(SUM(pe.cantidad_rollos) FILTER (WHERE pe.estado = 'COMPLETADO'), 0)
                    FROM mes.partida_paso_ejecucion pe
                    WHERE pe.partida_paso_id = v_paso_id
                ) >= (
                    SELECT COUNT(*)
                    FROM mes.partida_componente pc
                    WHERE pc.partida_id = v_partida_id
                      AND pc.lote_id IS NOT NULL
                ) THEN 'COMPLETADO'::partida_paso_estado_enum
                ELSE 'EN_PROCESO'::partida_paso_estado_enum
            END,
            fyh_mod = NOW()
        WHERE id = v_paso_id;

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
    LEFT JOIN receta.tenido               rt     ON rt.id   = pp.receta_id
    LEFT JOIN color_x_cliente             cxc    ON cxc.id  = rt.color_x_cliente_id
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
    v_partida_id        bigint;
    v_paso_id           bigint;
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
    SELECT pe.estado, pp.partida_id, pp.id
    INTO v_estado, v_partida_id, v_paso_id
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

    -- 6. PROD_CONSUMO_REV: restore input lotes consumed by this execution run.
    --    Nets against any prior partial reversals (e.g. corregir_matizado) so
    --    already-reversed lots are not double-credited. Only lotes with net
    --    unconsumed quantity receive a reversal row.
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id
    )
    SELECT
        v_doc_movimiento_id,
        agg.item_id,
        agg.lote_id,
        v_consumo_rev_id,
        agg.origen_ubicacion_id,
        agg.net_cantidad,
        'partida_paso_ejecucion',
        p_ejecucion_id
    FROM (
        SELECT
            m.item_id,
            m.lote_id,
            m.origen_ubicacion_id,
            SUM(CASE WHEN m.item_movimiento_tipo_id = v_consumo_rev_id THEN -m.cantidad ELSE m.cantidad END) AS net_cantidad
        FROM inventario.item_movimientos m
        WHERE m.documento_tipo          = 'partida_paso_ejecucion'
          AND m.documento_id            = p_ejecucion_id
          AND m.item_movimiento_tipo_id IN (
              v_consumo_rev_id,
              (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO')
          )
        GROUP BY m.item_id, m.lote_id, m.origen_ubicacion_id
        HAVING SUM(CASE WHEN m.item_movimiento_tipo_id = v_consumo_rev_id THEN -m.cantidad ELSE m.cantidad END) > 0
    ) agg;

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

    UPDATE mes.partida_paso SET estado = 'EN_PROCESO', fyh_mod = NOW() WHERE id = v_paso_id;

    -- 9. Recount confirmed output — same logic as registrar_produccion so both
    -- functions always agree. The soft-delete above already excludes reversed lotes.
    UPDATE mes.partida_detalle pd
    SET cantidad_producida = (
        SELECT COUNT(*)
        FROM inventario.lote l
        JOIN mes.partida_paso_ejecucion pe
            ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        WHERE pp.partida_id = v_partida_id
          AND l.item_id     = pd.item_id
          AND l.fyh_elm     IS NULL
    ),
    usr_mod = v_usr_id,
    fyh_mod = NOW()
    WHERE pd.partida_id = v_partida_id;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_produccion', v_usr_id, jsonb_build_object('ejecucion_id', p_ejecucion_id));

    RETURN format('Producción de ejecución #%s anulada: %s lotes de salida revertidos.', p_ejecucion_id, v_output_count);

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
    v_hay_programacion boolean;
    v_estado_actual    partida_estado_produccion_enum;
BEGIN
    SELECT estado_produccion INTO v_estado_actual
    FROM mes.partida WHERE id = p_partida_id;

    -- Never touch terminal states
    IF v_estado_actual IN ('CERRADA', 'CANCELADA') THEN RETURN; END IF;

    -- Use paso-level estado, not ejecucion-level: a paso that still has rolls to process
    -- stays EN_PROCESO even when its last ejecucion is COMPLETADO (split-run model).
    -- Reading pp.estado avoids the premature-TECO bug where the first partial run closes
    -- its ejecucion but the paso itself is correctly still open.
    SELECT
        BOOL_OR(pp.estado = 'EN_PROCESO'),
        BOOL_AND(pp.estado IN ('COMPLETADO','OMITIDO')),
        COUNT(*) > 0
    INTO v_hay_en_proceso, v_todos_terminados, v_hay_pasos
    FROM mes.partida_paso pp
    WHERE pp.partida_id = p_partida_id;

    -- Execution-layer transitions take priority
    IF v_hay_pasos AND v_todos_terminados THEN
        UPDATE mes.partida
        SET estado_produccion = 'TECO',
            fyh_fin           = COALESCE(fyh_fin, NOW()),
            fyh_mod           = NOW()
        WHERE id = p_partida_id;
        RETURN;
    END IF;

    IF v_hay_pasos AND v_hay_en_proceso THEN
        UPDATE mes.partida
        SET estado_produccion = 'EN_PRODUCCION',
            fyh_inicio        = COALESCE(fyh_inicio, NOW()),
            fyh_fin           = NULL,
            fyh_mod           = NOW()
        WHERE id = p_partida_id;
        RETURN;
    END IF;

    -- Planning-layer transitions: only when no execution has started
    IF v_estado_actual NOT IN ('EN_PRODUCCION', 'TECO') THEN
        IF NOT v_hay_pasos THEN RETURN; END IF;  -- no steps yet, stay CREADA

        SELECT EXISTS (
            SELECT 1
            FROM mes.partida_paso pp
            JOIN mes.programacion prog
              ON prog.actividad_tipo = 'partida_paso'
             AND prog.actividad_id   = pp.id
             AND prog.fecha         >= CURRENT_DATE
            WHERE pp.partida_id = p_partida_id
        ) INTO v_hay_programacion;

        IF v_hay_programacion THEN
            UPDATE mes.partida SET estado_produccion = 'PROGRAMADA', fyh_mod = NOW()
            WHERE id = p_partida_id AND estado_produccion != 'PROGRAMADA';
        ELSE
            UPDATE mes.partida SET estado_produccion = 'PLANIFICADA', fyh_mod = NOW()
            WHERE id = p_partida_id AND estado_produccion != 'PLANIFICADA';
        END IF;
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
--    Set by the despacho/comercial module (doc.entrega flows). Indicates
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

    -- Rework children are TECO-terminal: commercial settlement (estado_comercial,
    -- estado_facturacion) always runs on the parent order. Close the parent once
    -- all reprocesos are in TECO/CERRADA/CANCELADA — not each child individually.
    IF EXISTS (SELECT 1 FROM mes.partida WHERE id = p_partida_id AND partida_origen_id IS NOT NULL) THEN
        RAISE EXCEPTION
            'Partida % es un reproceso y no puede cerrarse directamente. Cierre la partida origen una vez que todos sus reprocesos estén en TECO.',
            p_partida_id;
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

    -- Soft warning: approved family output vs intended demand. Reads the same
    -- definition the commercial views use (mes.vw_partida_familia) so the number
    -- can't drift between here, get_partida_familia, and the board. p_partida_id
    -- is guaranteed to be a root (children were rejected above), which is the
    -- grain of vw_partida_familia.
    SELECT demanda_rollos, producido_bueno
    INTO   v_target_qty, v_output_qty
    FROM   mes.vw_partida_familia
    WHERE  partida_id = p_partida_id;

    IF v_output_qty < v_target_qty THEN
        v_warning := format(' ATENCIÓN: producción aprobada (%s rollos) es menor al objetivo (%s rollos). Verifique antes de cerrar.', v_output_qty, v_target_qty);
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
-- p_datos shape:
--   {
--     "lotes": [1, 2, 3],            required — lote IDs to rework
--     "pasos": [                      optional — if omitted, child is created with no pasos (blank draft)
--       {
--         "operacion_id": 5,          required per paso
--         "secuencia": 1,             optional (defaults to array position)
--         "receta_id": 42,            optional — corrective recipe (different from original)
--         "maquina_planificada_id": 3,optional
--         "ph_objetivo": 6.5,         optional
--         "temperatura_objetivo": 80, optional
--         "relacion_bano_objetivo": 1.5, optional
--         "tiempo_estandar": 120      optional
--       }
--     ],
--     "fecha_acordada": "2026-06-01" optional — override delivery date
--   }
--
-- Immutable (always inherited from root): tercero_id, articulo_tipo_id, fibra,
--   flg_antipilling, malla, ancho, rendimiento, color_x_cliente_id, tenido_id.
-- Billing and commercial settlement always run on the root order.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.crear_reproceso(
    p_partida_id BIGINT,
    p_datos      JSONB
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
    v_root_id   BIGINT;
    v_lotes     JSONB;
BEGIN
    IF NOT jwt_has_permission('produccion.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_lotes := p_datos->'lotes';

    IF v_lotes IS NULL OR jsonb_array_length(v_lotes) = 0 THEN
        RAISE EXCEPTION 'Se requiere al menos un lote para crear reproceso.';
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

    -- Flat rework topology: all children link to the original root.
    -- If p_partida_id is itself a rework child, the new sibling links to the same root.
    v_root_id := COALESCE(v_origen.partida_origen_id, v_origen.id);

    -- Validate every supplied lote against the whole family (two valid sources):
    --   A) input rolls already in partida_componente of any family member
    --   B) output lotes (PROD_ING) from paso_ejecucion of any family member (post-final-paso re-dye)
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_lotes) e
        WHERE NOT (
            EXISTS (
                SELECT 1 FROM mes.partida_componente pc
                JOIN mes.partida p ON p.id = pc.partida_id
                WHERE pc.lote_id = (e.value::TEXT)::INT
                  AND (p.id = v_root_id OR p.partida_origen_id = v_root_id)
            )
            OR
            EXISTS (
                SELECT 1 FROM inventario.lote l
                JOIN mes.partida_paso_ejecucion pe
                    ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
                JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
                WHERE l.id = (e.value::TEXT)::INT
                  AND pp.partida_id IN (
                      SELECT id FROM mes.partida
                      WHERE id = v_root_id OR partida_origen_id = v_root_id
                  )
                  AND l.fyh_elm IS NULL
            )
        )
    ) THEN
        RAISE EXCEPTION 'Uno o más lotes no pertenecen a la familia de la partida %.', v_root_id;
    END IF;

    -- Create rework child. Immutable specs always inherited; fecha_acordada overridable.
    INSERT INTO mes.partida (
        partida_origen_id, prioridad_id, tercero_id, tenido_id,
        color_x_cliente_id, articulo_tipo_id, fibra, malla, rendimiento,
        ancho, flg_antipilling, fecha_acordada, estado_produccion, usr_cre
    )
    VALUES (
        v_root_id, v_origen.prioridad_id, v_origen.tercero_id, v_origen.tenido_id,
        v_origen.color_x_cliente_id, v_origen.articulo_tipo_id, v_origen.fibra,
        v_origen.malla, v_origen.rendimiento, v_origen.ancho, v_origen.flg_antipilling,
        COALESCE((p_datos->>'fecha_acordada')::date, v_origen.fecha_acordada),
        'CREADA', v_usr_id
    )
    RETURNING id INTO v_child_id;

    -- Paso structure: caller-specified (flexible subset + corrective recipe), or no pasos
    -- (blank draft — planner adds steps after creation). Rework children intentionally skip
    -- PLANIFICADA/PROGRAMADA — iniciar_paso has no estado_produccion guard so execution
    -- can begin from CREADA immediately once steps are defined.
    IF p_datos->'pasos' IS NOT NULL AND jsonb_array_length(p_datos->'pasos') > 0 THEN
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            receta_id, tiempo_estandar, ph_objetivo, temperatura_objetivo,
            relacion_bano_objetivo, usr_cre
        )
        SELECT
            v_child_id,
            COALESCE((e->>'secuencia')::smallint, rn::smallint),
            (e->>'operacion_id')::smallint,
            (e->>'maquina_planificada_id')::int,
            (e->>'receta_id')::int,
            (e->>'tiempo_estandar')::int,
            (e->>'ph_objetivo')::numeric,
            (e->>'temperatura_objetivo')::numeric,
            (e->>'relacion_bano_objetivo')::numeric,
            v_usr_id
        FROM jsonb_array_elements(p_datos->'pasos') WITH ORDINALITY AS arr(e, rn);
    -- If no pasos provided, child is created as a blank draft — planner adds steps explicitly.
    END IF;


    -- Auto-create partida_detalle for the rework child.
    -- Mirrors root's item structure; cantidad = rolls being reworked (one roll = one billing unit).
    INSERT INTO mes.partida_detalle (partida_id, item_id, cantidad, unidad_id, usr_cre)
    SELECT v_child_id, pd.item_id, COUNT(l.id), pd.unidad_id, v_usr_id
    FROM mes.partida_detalle pd
    LEFT JOIN inventario.lote l ON l.item_id = pd.item_id
        AND l.id IN (SELECT (e.value::TEXT)::INT FROM jsonb_array_elements(v_lotes) e)
    WHERE pd.partida_id = v_root_id
    GROUP BY pd.item_id, pd.unidad_id
    HAVING COUNT(l.id) > 0;

    -- Case A: move input rolls (already in partida_componente of any family member).
    UPDATE mes.partida_componente
    SET partida_id = v_child_id
    WHERE lote_id IN (SELECT (e.value::TEXT)::INT FROM jsonb_array_elements(v_lotes) e)
      AND partida_id IN (
          SELECT id FROM mes.partida
          WHERE id = v_root_id OR partida_origen_id = v_root_id
      );

    -- Reset quality state so rolls enter the rework cycle as pending inspection.
    -- Applies to all reworked lotes (both input rolls and output rolls being re-dyed).
    -- The previous QC result is preserved in calidad.inspeccion; estado_calidad reflects
    -- the current production context, not historical determinations.
    UPDATE inventario.lote
    SET estado_calidad = 'PENDIENTE'
    WHERE id IN (SELECT (e.value::TEXT)::INT FROM jsonb_array_elements(v_lotes) e);

    -- Case B: register output lotes as input for the rework child (post-final-paso re-dye).
    -- These PROD_ING lotes have no partida_componente entry yet.
    INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada, usr_cre)
    SELECT v_child_id, l.id, l.cantidad, v_usr_id
    FROM inventario.lote l
    WHERE l.id IN (SELECT (e.value::TEXT)::INT FROM jsonb_array_elements(v_lotes) e)
      AND l.documento_tipo = 'partida_paso_ejecucion'
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_componente pc
          WHERE pc.lote_id = l.id AND pc.partida_id = v_child_id
      );

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_reproceso', v_usr_id,
            p_datos || jsonb_build_object('partida_id', p_partida_id));

    PERFORM mes.actualizar_estado_partida(v_child_id);

    RETURN jsonb_build_object(
        'reproceso_partida_id', v_child_id,
        'partida_origen_id',    v_root_id,
        'lotes_movidos',        jsonb_array_length(v_lotes),
        'message', format('Reproceso %s creado desde partida %s con %s rollo(s).',
                          v_child_id, p_partida_id, jsonb_array_length(v_lotes))
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
        'flg_doble_bolsa', p.flg_doble_bolsa,
        'observacion', p.observacion,

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
                       vi.unidad_codigo AS unidad,
                       SUM(CASE WHEN m.item_movimiento_tipo_id = (
                               SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV'
                           ) THEN -m.cantidad ELSE m.cantidad END) AS cantidad_total
                FROM inventario.item_movimientos m
                JOIN vw_items vi ON vi.item_id = m.item_id
                WHERE m.documento_tipo = 'partida_paso_ejecucion'
                  AND m.documento_id IN (
                      SELECT pe.id FROM mes.partida_paso_ejecucion pe
                      JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
                      WHERE pp.partida_id = p.id
                  )
                  AND m.item_movimiento_tipo_id IN (
                      SELECT id FROM inventario.item_movimiento_tipo WHERE codigo IN ('PROD_CONSUMO', 'PROD_CONSUMO_REV')
                  )
                GROUP BY m.item_id, vi.item_codigo, vi.item_nombre, vi.unidad_codigo
                HAVING SUM(CASE WHEN m.item_movimiento_tipo_id = (
                               SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV'
                           ) THEN -m.cantidad ELSE m.cantidad END) > 0
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
                    'cantidad_procesada', (
                        SELECT COALESCE(SUM(pe.cantidad_rollos) FILTER (WHERE pe.estado = 'COMPLETADO'), 0)
                        FROM mes.partida_paso_ejecucion pe
                        WHERE pe.partida_paso_id = opp.id
                    ),
                    'estado', opp.estado,
                    'consumo', COALESCE((
                        SELECT jsonb_agg(jsonb_build_object(
                            'item_id',             sub.item_id,
                            'item_codigo',         sub.item_codigo,
                            'item_nombre',         sub.item_nombre,
                            'lote_id',             sub.lote_id,
                            'cantidad',            sub.cantidad,
                            'unidad',              sub.unidad,
                            'motivo_id',           sub.motivo_id,
                            'motivo_codigo',       sub.motivo_codigo,
                            'origen_ubicacion_id', sub.origen_ubicacion_id,
                            'origen_ubicacion',    sub.origen_ubicacion,
                            'origen_almacen',      sub.origen_almacen
                        ) ORDER BY sub.item_nombre)
                        FROM (
                            SELECT m.item_id, vi_mov.item_codigo, vi_mov.item_nombre, m.lote_id,
                                   SUM(CASE WHEN mt.codigo = 'PROD_CONSUMO_REV' THEN -m.cantidad ELSE m.cantidad END) AS cantidad,
                                   vi_mov.unidad_codigo AS unidad, m.motivo_id, mot.codigo AS motivo_codigo,
                                   m.origen_ubicacion_id, ubi.nombre AS origen_ubicacion, al.nombre AS origen_almacen
                            FROM inventario.item_movimientos m
                            LEFT JOIN vw_items vi_mov ON vi_mov.item_id = m.item_id
                            LEFT JOIN inventario.item_movimiento_tipo mt ON mt.id = m.item_movimiento_tipo_id
                            LEFT JOIN inventario.item_movimiento_motivo mot ON mot.id = m.motivo_id
                            LEFT JOIN inventario.ubicacion ubi ON ubi.id = m.origen_ubicacion_id
                            LEFT JOIN inventario.almacen al ON al.id = ubi.almacen_id
                            WHERE m.documento_tipo = 'partida_paso_ejecucion'
                              AND m.documento_id IN (
                                  SELECT pe.id FROM mes.partida_paso_ejecucion pe
                                  WHERE pe.partida_paso_id = opp.id
                              )
                              AND m.item_movimiento_tipo_id IN (
                                  SELECT id FROM inventario.item_movimiento_tipo WHERE codigo IN ('PROD_CONSUMO', 'PROD_CONSUMO_REV')
                              )
                            GROUP BY m.item_id, vi_mov.item_codigo, vi_mov.item_nombre, m.lote_id,
                                     vi_mov.unidad_codigo, m.motivo_id, mot.codigo,
                                     m.origen_ubicacion_id, ubi.nombre, al.nombre
                            HAVING SUM(CASE WHEN mt.codigo = 'PROD_CONSUMO_REV' THEN -m.cantidad ELSE m.cantidad END) > 0
                        ) sub
                    ), '[]'::jsonb),
                    'ejecuciones', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',                  pe.id,
                                'receta_id',           pe.receta_id,
                                'maquina_id',          pe.maquina_id,
                                'empleado_id',         pe.empleado_id,
                                'estado',              pe.estado,
                                'fyh_inicio',          pe.fyh_inicio,
                                'fyh_fin',             pe.fyh_fin,
                                'ph_real',             pe.ph_real,
                                'temperatura_real',    pe.temperatura_real,
                                'relacion_bano_real',  pe.relacion_bano_real,
                                'cantidad_rollos',     pe.cantidad_rollos,
                                'notas',               pe.notas,
                                'ancho_entrada',       pe.ancho_entrada,
                                'ancho_salida',        pe.ancho_salida,
                                'velocidad',           pe.velocidad,
                                'entrada',             pe.entrada,
                                'salida',              pe.salida,
                                'rendimiento',         pe.rendimiento,
                                'pases',               pe.pases,
                                'malla_alimentacion',  pe.malla_alimentacion,
                                'termofijado', CASE WHEN pt.ejecucion_id IS NOT NULL THEN jsonb_build_object(
                                    'ancho_marco',      pt.ancho_marco,
                                    'vel_maquina',      pt.vel_maquina,
                                    'vel_alimentacion', pt.vel_alimentacion,
                                    'densidad_entrada', pt.densidad_entrada,
                                    'densidad_salida',  pt.densidad_salida,
                                    'lm',               pt.lm,
                                    'galga',            pt.galga
                                ) END,
                                'consumo', COALESCE((
                                    SELECT jsonb_agg(jsonb_build_object(
                                        'id',                  m.id,
                                        'item_id',             m.item_id,
                                        'item_codigo',         vi_mov.item_codigo,
                                        'item_nombre',         vi_mov.item_nombre,
                                        'lote_id',             m.lote_id,
                                        'cantidad',            m.cantidad,
                                        'unidad',              vi_mov.unidad_codigo,
                                        'motivo_id',           m.motivo_id,
                                        'motivo_codigo',       mot.codigo,
                                        'origen_ubicacion_id', m.origen_ubicacion_id,
                                        'origen_ubicacion',    ubi.nombre,
                                        'origen_almacen',      al.nombre
                                    ) ORDER BY m.fyh_cre)
                                    FROM inventario.item_movimientos m
                                    LEFT JOIN vw_items vi_mov ON vi_mov.item_id = m.item_id
                                    LEFT JOIN inventario.item_movimiento_motivo mot ON mot.id = m.motivo_id
                                    LEFT JOIN inventario.ubicacion ubi ON ubi.id = m.origen_ubicacion_id
                                    LEFT JOIN inventario.almacen al ON al.id = ubi.almacen_id
                                    WHERE m.documento_tipo          = 'partida_paso_ejecucion'
                                      AND m.documento_id            = pe.id
                                      AND m.item_movimiento_tipo_id = (
                                          SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'
                                      )
                                ), '[]'::jsonb)
                            ) ORDER BY pe.fyh_inicio
                        )
                        FROM mes.partida_paso_ejecucion pe
                        LEFT JOIN mes.partida_paso_ejecucion_termofijado pt ON pt.ejecucion_id = pe.id
                        WHERE pe.partida_paso_id = opp.id
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
                'entrega_id',   lrd_in.entrega_id,
                'entrega_serie',         gr_in.serie,
                'entrega_correlativo',   gr_in.correlativo,
                'orden_servicio_id',  lrd_in.orden_servicio_id,
                'os_serie',           os_in.serie,
                'os_correlativo',     os_in.correlativo,
                'factura_hilo',       lrd_in.factura_hilo,
                'ancho',              lrd_in.ancho,
                'malla',              lrd_in.malla,
                'flg_tenido',         lrd_in.flg_tenido,
                'flg_antipilling',    lrd_in.flg_antipilling,
                'color_x_cliente_id', lrd_in.color_x_cliente_id,
                'tenido_id',          lrd_in.tenido_id,
                'peso_real',          ps.peso_real,
                'flg_pesado',         (ps.lote_id IS NOT NULL)
            ) ORDER BY opi.id)
            FROM mes.partida_componente opi
            LEFT JOIN inventario.lote l ON l.id = opi.lote_id
            LEFT JOIN vw_items vi_mat ON vi_mat.item_id = l.item_id
            LEFT JOIN inventario.lote_rollo_detalle lrd_in ON lrd_in.lote_id = l.id
            LEFT JOIN doc.entrega gr_in ON gr_in.id = lrd_in.entrega_id
            LEFT JOIN doc.orden_servicio os_in ON os_in.id = lrd_in.orden_servicio_id
            LEFT JOIN inventario.pesaje ps ON ps.lote_id = l.id
            WHERE opi.partida_id = p.id
              AND opi.lote_id IS NOT NULL
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
                'entrega_id',   lrd_out.entrega_id,
                'entrega_serie',         gr_out.serie,
                'entrega_correlativo',   gr_out.correlativo,
                'orden_servicio_id',  lrd_out.orden_servicio_id,
                'os_serie',           os_out.serie,
                'os_correlativo',     os_out.correlativo,
                'factura_hilo',       lrd_out.factura_hilo,
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
            LEFT JOIN doc.entrega gr_out ON gr_out.id = lrd_out.entrega_id
            LEFT JOIN doc.orden_servicio os_out ON os_out.id = lrd_out.orden_servicio_id
            WHERE l.documento_tipo = 'partida_paso_ejecucion'
        ), '[]'::jsonb),

        -- Lotes flagged for reproceso — two sources:
        --   1. output lotes (post-production) where estado_calidad = 'REPROCESO'
        --   2. input lotes (pre-output QC) where reserved roll was flagged before final paso completed
        'lotes_reproceso', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'lote_id',    src.lote_id,
                'lote_codigo', src.lote_codigo,
                'item_nombre', src.item_nombre,
                'cantidad',   src.cantidad,
                'unidad',     src.unidad
            ) ORDER BY src.lote_id)
            FROM (
                -- Source 1: output lotes produced by this partida's executions
                SELECT l.id AS lote_id,
                       EXTRACT(YEAR FROM l.fyh_cre)%100 || '-' || LPAD(l.secuencia::TEXT, 5, '0') AS lote_codigo,
                       vi.item_nombre,
                       l.cantidad,
                       vi.unidad_codigo AS unidad
                FROM inventario.lote l
                JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
                JOIN mes.partida_paso opp          ON opp.id = pe.partida_paso_id AND opp.partida_id = p.id
                LEFT JOIN vw_items vi ON vi.item_id = l.item_id
                WHERE l.documento_tipo = 'partida_paso_ejecucion'
                  AND l.estado_calidad = 'REPROCESO'
                UNION ALL
                -- Source 2: reserved input lotes flagged before production completes
                SELECT l.id AS lote_id,
                       EXTRACT(YEAR FROM l.fyh_cre)%100 || '-' || LPAD(l.secuencia::TEXT, 5, '0') AS lote_codigo,
                       vi.item_nombre,
                       l.cantidad,
                       vi.unidad_codigo AS unidad
                FROM mes.partida_componente pc
                JOIN inventario.lote l ON l.id = pc.lote_id
                LEFT JOIN vw_items vi ON vi.item_id = l.item_id
                WHERE pc.partida_id = p.id
                  AND pc.lote_id IS NOT NULL
                  AND l.estado_calidad = 'REPROCESO'
            ) src
        ), '[]'::jsonb),

        -- Direct rework partidas (partida_origen_id = this partida; no grandchildren)
        'reprocesos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id',                 ph.id,
                'codigo',             EXTRACT(YEAR FROM ph.fyh_cre)::TEXT || '-' || LPAD(ph.numero::TEXT, 4, '0'),
                'estado_produccion',  ph.estado_produccion,
                'estado_comercial',   ph.estado_comercial
            ) ORDER BY ph.fyh_cre)
            FROM mes.partida ph
            WHERE ph.partida_origen_id = p.id
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
-- GET PARTIDA FAMILIA  (commercial / merged rework view)
-- ═══════════════════════════════════════════════════════════════
-- Companion to get_partida (which is the single-order plant/operational
-- view). This is the ADMIN/COMMERCIAL view: it folds a partida and all its
-- reprocesos into one fulfillment picture so you can judge "did we deliver
-- what the original order intended?" without navigating each rework.
--
-- Accepts ANY family member id and resolves to the root internally, so the
-- frontend can pass a child id and still get the family rollup.
--
-- Fulfillment math is NOT a sum across the family — intent lives only on the
-- root, and rolls move between members. All counting is delegated to
-- mes.vw_partida_familia / mes.vw_partida_familia_output so the definition of
-- a "produced" roll matches cerrar_partida exactly.
--
-- Returns:
--   header (root)             id, codigo, cliente, articulo, color, estados…
--   cumplimiento              family totals (demanda / bueno / faltante / %)
--   cumplimiento_por_item     same totals split by output item_id
--   miembros[]                root + each reproceso with its own tally
CREATE OR REPLACE FUNCTION mes.get_partida_familia(p_partida_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'inventario', 'mes'
AS $function$
DECLARE
    v_root_id BIGINT;
    v_result  JSONB;
BEGIN
    -- Resolve to the family root: any member resolves to the original.
    SELECT COALESCE(p.partida_origen_id, p.id) INTO v_root_id
    FROM mes.partida p
    WHERE p.id = p_partida_id AND p.fyh_elm IS NULL;

    IF v_root_id IS NULL THEN
        RAISE EXCEPTION 'Partida % no encontrada.', p_partida_id;
    END IF;

    SELECT jsonb_build_object(
        -- Header (root)
        'root_id',             r.id,
        'codigo',              EXTRACT(YEAR FROM r.fyh_cre)::TEXT
                                   || '-' || LPAD(r.numero::TEXT, 4, '0'),
        'tercero_id',          r.tercero_id,
        'cliente',             c.nombre,
        'articulo_tipo_id',    r.articulo_tipo_id,
        'articulo_tipo',       at.nombre,
        'color_x_cliente_id',  r.color_x_cliente_id,
        'color',               vc.color,
        'color_hex',           vc.color_hex,
        'estado_produccion',   r.estado_produccion,
        'estado_comercial',    r.estado_comercial,
        'estado_facturacion',  r.estado_facturacion,
        'prioridad_id',        r.prioridad_id,
        'prioridad',           pri.prioridad,
        'fecha_acordada',      r.fecha_acordada,
        'fyh_cre',             r.fyh_cre,
        'num_reprocesos',      (SELECT COUNT(*) FROM mes.partida rw
                                 WHERE rw.partida_origen_id = r.id),
        'tiene_rework_activo', EXISTS (SELECT 1 FROM mes.partida rw
                                 WHERE rw.partida_origen_id = r.id
                                   AND rw.estado_produccion NOT IN ('TECO','CERRADA','CANCELADA')),

        -- Family-level fulfillment totals. Computed straight from the shared
        -- terminal-deliverable base view filtered to THIS family — no whole-table
        -- aggregation (the rollup view mes.vw_partida_familia is for the board,
        -- not for single-row getters). The dedup rule stays DRY in the base view;
        -- only the trivial arithmetic (faltante, %) is repeated here.
        'cumplimiento', (
            SELECT jsonb_build_object(
                'demanda_rollos',          dem.demanda,
                'producido_bueno',         sal.bueno,
                'producido_pendiente',     sal.pendiente,
                'producido_reproceso',     sal.reproceso,
                'producido_terminal',      sal.terminal,
                'faltante',                GREATEST(0, dem.demanda - sal.bueno),
                'porcentaje_cumplimiento', CASE WHEN dem.demanda > 0
                                                THEN ROUND(sal.bueno::numeric / dem.demanda * 100, 0)
                                                ELSE NULL END,
                'flg_cumplida',            (sal.bueno >= dem.demanda AND dem.demanda > 0)
            )
            FROM (
                SELECT COALESCE(SUM(cantidad), 0) AS demanda
                FROM mes.partida_detalle WHERE partida_id = v_root_id
            ) dem
            CROSS JOIN (
                SELECT
                    COUNT(*) FILTER (WHERE estado_calidad = 'APROBADO')  AS bueno,
                    COUNT(*) FILTER (WHERE estado_calidad = 'PENDIENTE') AS pendiente,
                    COUNT(*) FILTER (WHERE estado_calidad = 'REPROCESO') AS reproceso,
                    COUNT(*)                                             AS terminal
                FROM mes.vw_partida_familia_output WHERE root_id = v_root_id
            ) sal
        ),

        -- Per-item breakdown: intent (root detalle) vs terminal output (family)
        'cumplimiento_por_item', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'item_id',             it.item_id,
                'item_codigo',         vi.item_codigo,
                'item_nombre',         vi.item_nombre,
                'demanda_rollos',      it.demanda,
                'producido_bueno',     it.bueno,
                'producido_pendiente', it.pendiente,
                'producido_reproceso', it.reproceso,
                'faltante',            GREATEST(0, it.demanda - it.bueno)
            ) ORDER BY vi.item_nombre)
            FROM (
                SELECT
                    COALESCE(dd.item_id, oo.item_id) AS item_id,
                    COALESCE(dd.demanda, 0)          AS demanda,
                    COALESCE(oo.bueno, 0)            AS bueno,
                    COALESCE(oo.pendiente, 0)        AS pendiente,
                    COALESCE(oo.reproceso, 0)        AS reproceso
                FROM (
                    SELECT item_id, SUM(cantidad) AS demanda
                    FROM mes.partida_detalle
                    WHERE partida_id = v_root_id
                    GROUP BY item_id
                ) dd
                FULL JOIN (
                    SELECT item_id,
                        COUNT(*) FILTER (WHERE estado_calidad = 'APROBADO')  AS bueno,
                        COUNT(*) FILTER (WHERE estado_calidad = 'PENDIENTE') AS pendiente,
                        COUNT(*) FILTER (WHERE estado_calidad = 'REPROCESO') AS reproceso
                    FROM mes.vw_partida_familia_output
                    WHERE root_id = v_root_id
                    GROUP BY item_id
                ) oo ON oo.item_id = dd.item_id
            ) it
            LEFT JOIN vw_items vi ON vi.item_id = it.item_id
        ), '[]'::jsonb),

        -- Members: root + each reproceso, with its own terminal output tally
        'miembros', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id',                 m.id,
                'codigo',             EXTRACT(YEAR FROM m.fyh_cre)::TEXT
                                          || '-' || LPAD(m.numero::TEXT, 4, '0'),
                'rol',                CASE WHEN m.partida_origen_id IS NULL
                                           THEN 'ORIGEN' ELSE 'REPROCESO' END,
                'estado_produccion',  m.estado_produccion,
                'estado_comercial',   m.estado_comercial,
                'fyh_cre',            m.fyh_cre,
                'producido_bueno',    (SELECT COUNT(*) FROM mes.vw_partida_familia_output o
                                        WHERE o.partida_id = m.id AND o.estado_calidad = 'APROBADO'),
                'producido_terminal', (SELECT COUNT(*) FROM mes.vw_partida_familia_output o
                                        WHERE o.partida_id = m.id)
            ) ORDER BY m.partida_origen_id NULLS FIRST, m.fyh_cre)
            FROM mes.partida m
            WHERE (m.id = v_root_id OR m.partida_origen_id = v_root_id)
              AND m.fyh_elm IS NULL
        ), '[]'::jsonb)

    ) INTO v_result
    FROM mes.partida r
    LEFT JOIN tercero c        ON c.id  = r.tercero_id
    LEFT JOIN articulo_tipo at ON at.id = r.articulo_tipo_id
    LEFT JOIN vw_colores vc    ON vc.color_x_cliente_id = r.color_x_cliente_id
    LEFT JOIN prioridad pri    ON pri.id = r.prioridad_id
    WHERE r.id = v_root_id;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.get_partida_familia(BIGINT) TO authenticated;

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


-- ═══════════════════════════════════════════════════════════════
-- LAVADO MAQUINA — execution lifecycle
--
-- crear_lavado_maquina   → PENDIENTE  (record created; programacion can now reference its id)
-- iniciar_lavado_maquina → EN_PROCESO (fyh_inicio stamped)
-- finalizar_lavado_maquina → COMPLETADO (insumos consumed via PROD_CONSUMO/LAVADO_MAQUINA,
--                                         machine ultimo_mantenimiento updated)
--
-- Insumos come directly from receta.lavado_maquina_paso_insumo — fixed absolute quantities,
-- no scaling (unlike production recipes). All pasos aggregated by item_id.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION mes.crear_lavado_maquina(p_datos JSONB)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta'
AS $$
DECLARE
    v_id        BIGINT;
    v_usr_id    INT     := get_user_id();
    v_receta_id INT     := (p_datos->>'receta_id')::INT;
    v_maq_id    INT     := (p_datos->>'maquina_id')::INT;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM receta.lavado_maquina WHERE id = v_receta_id AND flg_activo = true
    ) THEN
        RAISE EXCEPTION 'Receta lavado máquina id=% no existe o no está activa.', v_receta_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM mes.maquina WHERE id = v_maq_id AND fyh_elm IS NULL
    ) THEN
        RAISE EXCEPTION 'Máquina id=% no encontrada.', v_maq_id;
    END IF;

    INSERT INTO mes.lavado_maquina(
        receta_id, maquina_id, empleado_id, nota,
        estado, usr_cre, fyh_cre
    ) VALUES (
        v_receta_id,
        v_maq_id,
        (p_datos->>'empleado_id')::SMALLINT,
        p_datos->>'nota',
        'PENDIENTE',
        v_usr_id, now()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;$$;


CREATE OR REPLACE FUNCTION mes.iniciar_lavado_maquina(p_id BIGINT, p_datos JSONB DEFAULT '{}')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta'
AS $$
DECLARE
    v_usr_id INT := get_user_id();
    v_lavado mes.lavado_maquina%ROWTYPE;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_lavado FROM mes.lavado_maquina WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'lavado_maquina id=% no encontrado.', p_id;
    END IF;

    IF v_lavado.estado <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'lavado_maquina id=% en estado % — se esperaba PENDIENTE.', p_id, v_lavado.estado;
    END IF;

    UPDATE mes.lavado_maquina SET
        estado      = 'EN_PROCESO',
        fyh_inicio  = COALESCE((p_datos->>'fyh_inicio')::TIMESTAMPTZ, now()),
        empleado_id = COALESCE((p_datos->>'empleado_id')::SMALLINT, empleado_id),
        usr_mod     = v_usr_id,
        fyh_mod     = now()
    WHERE id = p_id;
END;$$;


CREATE OR REPLACE FUNCTION mes.finalizar_lavado_maquina(p_id BIGINT, p_datos JSONB DEFAULT '{}')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta'
AS $$
DECLARE
    v_usr_id            INT := get_user_id();
    v_lavado            mes.lavado_maquina%ROWTYPE;
    v_egr_tipo_id       SMALLINT;
    v_motivo_id         SMALLINT;
    v_doc_movimiento_id BIGINT;
    v_insumos           JSONB;
    v_consumos          JSONB;
    v_error_payload     JSONB;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_lavado FROM mes.lavado_maquina WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'lavado_maquina id=% no encontrado.', p_id;
    END IF;

    IF v_lavado.estado <> 'EN_PROCESO' THEN
        RAISE EXCEPTION 'lavado_maquina id=% en estado % — se esperaba EN_PROCESO.', p_id, v_lavado.estado;
    END IF;

    -- Aggregate insumos across all recipe pasos, summed by item (fixed quantities, no scaling)
    SELECT jsonb_agg(jsonb_build_object('item_id', item_id, 'cantidad', cantidad))
    INTO v_insumos
    FROM (
        SELECT lmpi.item_id, SUM(lmpi.cantidad) AS cantidad
        FROM receta.lavado_maquina_paso     lmp
        JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id = lmp.id
        WHERE lmp.receta_id = v_lavado.receta_id
        GROUP BY lmpi.item_id
    ) agg;

    IF v_insumos IS NOT NULL THEN
        -- Stock check
        WITH consumos AS (
            SELECT (i->>'item_id')::INT    AS item_id,
                   (i->>'cantidad')::NUMERIC AS cantidad
            FROM jsonb_array_elements(v_insumos) i
        )
        SELECT jsonb_agg(jsonb_build_object(
            'item_id',           c.item_id,
            'item_nombre',       it.nombre,
            'saldo_disponible',  COALESCE(sg.cantidad_total, 0),
            'cantidad_requerida', c.cantidad
        ))
        INTO v_error_payload
        FROM consumos c
        LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = c.item_id
        JOIN item it ON it.id = c.item_id
        WHERE COALESCE(sg.cantidad_total, 0) < c.cantidad;

        IF v_error_payload IS NOT NULL THEN
            RAISE EXCEPTION 'Stock insuficiente para lavado_maquina id=%', p_id
    USING DETAIL = v_error_payload::text;
        END IF;

        SELECT id INTO v_egr_tipo_id
        FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

        SELECT id INTO v_motivo_id
        FROM inventario.item_movimiento_motivo
        WHERE item_movimiento_tipo_id = v_egr_tipo_id AND codigo = 'LAVADO_MAQUINA';

        v_consumos := mes.calcular_fifo(v_insumos);
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario,
            documento_tipo, documento_id, motivo_id
        )
        SELECT
            v_doc_movimiento_id,
            (c->>'item_id')::INT,
            (c->>'lote_id')::INT,
            v_egr_tipo_id,
            (c->>'ubicacion_id')::INT,
            (c->>'cantidad')::NUMERIC,
            (SELECT iv.precio_promedio FROM inventario.item_valoracion iv
             WHERE iv.item_id = (c->>'item_id')::INT),
            'lavado_maquina',
            p_id,
            v_motivo_id
        FROM jsonb_array_elements(v_consumos) c;
    END IF;

    UPDATE mes.lavado_maquina SET
        estado  = 'COMPLETADO',
        fyh_fin = COALESCE((p_datos->>'fyh_fin')::TIMESTAMPTZ, now()),
        nota    = COALESCE(p_datos->>'nota', nota),
        usr_mod = v_usr_id,
        fyh_mod = now()
    WHERE id = p_id;

    UPDATE mes.maquina SET
        ultimo_mantenimiento = now(),
        usr_mod = v_usr_id,
        fyh_mod = now()
    WHERE id = v_lavado.maquina_id;
END;$$;


-- ═══════════════════════════════════════════════════════════════
-- REGISTRAR LAVADO MAQUINA — atomic backdating shortcut
-- Creates the record and immediately completes it in one transaction.
-- Use when recording after the fact with known start/end timestamps.
-- For live execution use crear → iniciar → finalizar instead.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION mes.registrar_lavado_maquina(p_datos JSONB)
-- {receta_id, maquina_id, fyh_inicio, fyh_fin, empleado_id?, nota?}
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta'
AS $$
DECLARE
    v_id                BIGINT;
    v_usr_id            INT     := get_user_id();
    v_receta_id         INT     := (p_datos->>'receta_id')::INT;
    v_maq_id            INT     := (p_datos->>'maquina_id')::INT;
    v_egr_tipo_id       SMALLINT;
    v_motivo_id         SMALLINT;
    v_doc_movimiento_id BIGINT;
    v_insumos           JSONB;
    v_consumos          JSONB;
    v_error_payload     JSONB;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF (p_datos->>'fyh_inicio') IS NULL OR (p_datos->>'fyh_fin') IS NULL THEN
        RAISE EXCEPTION 'fyh_inicio y fyh_fin son requeridos para registrar_lavado_maquina.';
    END IF;

    IF (p_datos->>'fyh_inicio')::TIMESTAMPTZ >= (p_datos->>'fyh_fin')::TIMESTAMPTZ THEN
        RAISE EXCEPTION 'fyh_inicio debe ser anterior a fyh_fin.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM receta.lavado_maquina WHERE id = v_receta_id AND flg_activo = true
    ) THEN
        RAISE EXCEPTION 'Receta lavado máquina id=% no existe o no está activa.', v_receta_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM mes.maquina WHERE id = v_maq_id AND fyh_elm IS NULL
    ) THEN
        RAISE EXCEPTION 'Máquina id=% no encontrada.', v_maq_id;
    END IF;

    -- Aggregate insumos across all recipe pasos, summed by item
    SELECT jsonb_agg(jsonb_build_object('item_id', item_id, 'cantidad', cantidad))
    INTO v_insumos
    FROM (
        SELECT lmpi.item_id, SUM(lmpi.cantidad) AS cantidad
        FROM receta.lavado_maquina_paso        lmp
        JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id = lmp.id
        WHERE lmp.receta_id = v_receta_id
        GROUP BY lmpi.item_id
    ) agg;

    IF v_insumos IS NOT NULL THEN
        -- Stock check
        WITH consumos AS (
            SELECT (i->>'item_id')::INT      AS item_id,
                   (i->>'cantidad')::NUMERIC AS cantidad
            FROM jsonb_array_elements(v_insumos) i
        )
        SELECT jsonb_agg(jsonb_build_object(
            'item_id',            c.item_id,
            'item_nombre',        it.nombre,
            'saldo_disponible',   COALESCE(sg.cantidad_total, 0),
            'cantidad_requerida', c.cantidad
        ))
        INTO v_error_payload
        FROM consumos c
        LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = c.item_id
        JOIN item it ON it.id = c.item_id
        WHERE COALESCE(sg.cantidad_total, 0) < c.cantidad;

        IF v_error_payload IS NOT NULL THEN
            RAISE EXCEPTION 'Stock insuficiente para registrar lavado'
                USING DETAIL = v_error_payload::text;
        END IF;

        SELECT id INTO v_egr_tipo_id
        FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';

        SELECT id INTO v_motivo_id
        FROM inventario.item_movimiento_motivo
        WHERE item_movimiento_tipo_id = v_egr_tipo_id AND codigo = 'LAVADO_MAQUINA';

        v_consumos := mes.calcular_fifo(v_insumos);
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;
    END IF;

    -- Insert directly as COMPLETADO
    INSERT INTO mes.lavado_maquina(
        receta_id, maquina_id, empleado_id, nota,
        estado, fyh_inicio, fyh_fin,
        usr_cre, fyh_cre
    ) VALUES (
        v_receta_id,
        v_maq_id,
        (p_datos->>'empleado_id')::SMALLINT,
        p_datos->>'nota',
        'COMPLETADO',
        (p_datos->>'fyh_inicio')::TIMESTAMPTZ,
        (p_datos->>'fyh_fin')::TIMESTAMPTZ,
        v_usr_id, now()
    )
    RETURNING id INTO v_id;

    IF v_consumos IS NOT NULL THEN
        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario,
            documento_tipo, documento_id, motivo_id
        )
        SELECT
            v_doc_movimiento_id,
            (c->>'item_id')::INT,
            (c->>'lote_id')::INT,
            v_egr_tipo_id,
            (c->>'ubicacion_id')::INT,
            (c->>'cantidad')::NUMERIC,
            (SELECT iv.precio_promedio FROM inventario.item_valoracion iv
             WHERE iv.item_id = (c->>'item_id')::INT),
            'lavado_maquina',
            v_id,
            v_motivo_id
        FROM jsonb_array_elements(v_consumos) c;
    END IF;

    UPDATE mes.maquina SET
        ultimo_mantenimiento = (p_datos->>'fyh_fin')::TIMESTAMPTZ,
        usr_mod = v_usr_id,
        fyh_mod = now()
    WHERE id = v_maq_id;

    RETURN v_id;
END;$$;

GRANT EXECUTE ON FUNCTION mes.crear_lavado_maquina(JSONB)              TO authenticated;
GRANT EXECUTE ON FUNCTION mes.iniciar_lavado_maquina(BIGINT, JSONB)    TO authenticated;
GRANT EXECUTE ON FUNCTION mes.finalizar_lavado_maquina(BIGINT, JSONB)  TO authenticated;
GRANT EXECUTE ON FUNCTION mes.registrar_lavado_maquina(JSONB)          TO authenticated;

-- ── mes.generar_receta_lavado_maquina ─────────────────────────────────────────
-- Returns the wash recipe for a scheduled mes.lavado_maquina execution.
-- Quantities are fixed (no bath-ratio scaling); every insumo is returned as-is.
CREATE OR REPLACE FUNCTION mes.generar_receta_lavado_maquina(p_lavado_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','receta','doc'
AS $function$
DECLARE
    v_usr_id   INT := get_user_id();
    v_receta   jsonb;
    v_message  text;
    v_detail   text;
    v_hint     text;
    v_context  text;
    v_sqlstate text;
BEGIN
    IF NOT jwt_has_permission('produccion.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT jsonb_build_object(
        'lavado_maquina_id',  lm.id,
        'receta_id',          r.id,
        'tipo_lavado',        tlm.nombre,
        'color_origen_id',    r.valor_origen_id,
        'color_origen',       vo.valor,
        'color_destino_id',   r.valor_destino_id,
        'color_destino',      vd.valor,
        'maquina_id',         lm.maquina_id,
        'maquina',            jsonb_build_object('id', m.id, 'codigo', m.codigo, 'nombre', m.nombre),
        'estado',             lm.estado,
        'fyh_cre',            lm.fyh_cre,
        'pasos', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'orden',       lmp.orden,
                    'operacion_id', ro.id,
                    'operacion',   ro.nombre,
                    'ph',          lmp.ph,
                    'temperatura', lmp.temperatura,
                    'tiempo_min',  lmp.tiempo_min,
                    'nota',        lmp.nota,
                    'insumos', (
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'item_id',  lmpi.item_id,
                                'orden',    lmpi.orden,
                                'codigo',   i.codigo,
                                'nombre',   i.nombre,
                                'cantidad', lmpi.cantidad,
                                'medida',   'kg'
                            ) ORDER BY lmpi.orden
                        )
                        FROM receta.lavado_maquina_paso_insumo lmpi
                        JOIN item i ON i.id = lmpi.item_id
                        WHERE lmpi.paso_id = lmp.id
                    )
                ) ORDER BY lmp.orden
            )
            FROM receta.lavado_maquina_paso lmp
            JOIN receta.operacion ro ON ro.id = lmp.operacion_id
            WHERE lmp.receta_id = r.id
        )
    ) INTO v_receta
    FROM mes.lavado_maquina         lm
    JOIN receta.lavado_maquina      r   ON r.id   = lm.receta_id
    JOIN mes.maquina                m   ON m.id   = lm.maquina_id
    LEFT JOIN tipo_lavado_maquina   tlm ON tlm.id = r.tipo_lavado_mq_id
    LEFT JOIN public.valor          vo  ON vo.id  = r.valor_origen_id
    LEFT JOIN public.valor          vd  ON vd.id  = r.valor_destino_id
    WHERE lm.id = p_lavado_id;

    IF v_receta IS NULL THEN
        RAISE EXCEPTION 'lavado_maquina id=% no encontrado.', p_lavado_id;
    END IF;

    RETURN v_receta;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in generar_receta_lavado_maquina - User: %, ID: %, Error: %', v_usr_id, p_lavado_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.generar_receta_lavado_maquina(BIGINT) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- TRANSFERIR ROLLO ENTRE PARTIDAS
-- Reassigns a roll lote from one partida to another.
-- Use cases: missing roll routed to a sibling order for dyeing,
-- then returned to the original order at dispatch.
--
-- Guards:
--   1. Roll must be currently assigned to partida_origen.
--   2. Roll must not have been consumed yet (PROD_CONSUMO movement
--      is posted at the final closure step — compactado).
--   3. Origen must not be TECO / CERRADA / CANCELADA.
--   4. Destino must exist and not be TECO / CERRADA / CANCELADA.
--   5. Roll must not already be assigned to destino.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.transferir_rollo_partida(
    p_lote_id           INT,
    p_partida_origen    BIGINT,
    p_partida_destino   BIGINT,
    p_observacion       TEXT DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes','inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id         int  := get_user_id();
    v_estado_origen  partida_estado_produccion_enum;
    v_estado_destino partida_estado_produccion_enum;
BEGIN
    IF NOT jwt_has_permission('produccion.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Roll assigned to origen
    IF NOT EXISTS (
        SELECT 1 FROM mes.partida_componente
        WHERE lote_id = p_lote_id AND partida_id = p_partida_origen
    ) THEN
        RAISE EXCEPTION 'El rollo (lote #%) no está asignado a la partida #%.',
            p_lote_id, p_partida_origen;
    END IF;

    -- 2. Roll not yet consumed (compactado has not posted its PROD_CONSUMO)
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = p_lote_id AND imt.codigo = 'PROD_CONSUMO'
    ) THEN
        RAISE EXCEPTION 'El rollo (lote #%) ya fue consumido en producción y no puede trasladarse.',
            p_lote_id;
    END IF;

    -- 3. Origen state
    SELECT estado_produccion INTO v_estado_origen FROM mes.partida WHERE id = p_partida_origen;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida origen #% no encontrada.', p_partida_origen;
    END IF;
    IF v_estado_origen IN ('TECO', 'CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'La partida origen #% está en estado % y no permite modificaciones.',
            p_partida_origen, v_estado_origen;
    END IF;

    -- 4. Destino state
    SELECT estado_produccion INTO v_estado_destino FROM mes.partida WHERE id = p_partida_destino;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida destino #% no encontrada.', p_partida_destino;
    END IF;
    IF v_estado_destino IN ('TECO', 'CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'La partida destino #% está en estado % y no puede recibir rollos.',
            p_partida_destino, v_estado_destino;
    END IF;

    -- 5. Not already in destino (unique index would fire anyway, but explicit error is clearer)
    IF EXISTS (
        SELECT 1 FROM mes.partida_componente
        WHERE lote_id = p_lote_id AND partida_id = p_partida_destino
    ) THEN
        RAISE EXCEPTION 'El rollo (lote #%) ya está asignado a la partida destino #%.',
            p_lote_id, p_partida_destino;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('transferir_rollo_partida', v_usr_id,
            jsonb_build_object(
                'lote_id',         p_lote_id,
                'partida_origen',  p_partida_origen,
                'partida_destino', p_partida_destino,
                'observacion',     p_observacion
            ));

    UPDATE mes.partida_componente
    SET partida_id = p_partida_destino,
        usr_mod    = v_usr_id,
        fyh_mod    = now()
    WHERE lote_id    = p_lote_id
      AND partida_id = p_partida_origen;

    RETURN format('Rollo (lote #%s) trasladado de partida #%s a partida #%s.',
                  p_lote_id, p_partida_origen, p_partida_destino);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in transferir_rollo_partida - User: %, lote: %, origen: %, destino: %, Error: %',
              v_usr_id, p_lote_id, p_partida_origen, p_partida_destino, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.transferir_rollo_partida(INT, BIGINT, BIGINT, TEXT) TO authenticated;

    
-- SELECT mes.get_actividades_sin_programar()

-- SELECT * FROm mes.partida_paso_ejecucion WHERE id=9378
-- Error
-- Pasos no programables (ya COMPLETADO/OMITIDO): [{"actividad_id": 9378}]

-- ═══════════════════════════════════════════════════════════════
-- REPORTE PRODUCCIÓN ACABADO — por DÍA DE PRODUCCIÓN (corte 07:00 Lima)
-- El "día" del cliente va de las 07:00 a las 07:00 del día siguiente
-- (NO medianoche). Una ejecución que cruza las 07:00 se parte en
-- filas proporcionales atribuidas a cada día de producción.
-- Reconcilia exactamente con get_reporte_produccion_acabado_turno:
--   día D = turno DÍA(D) + turno NOCHE(D).
-- Perú (America/Lima) no usa horario de verano → la aritmética en
--   hora local de pared es exacta (sin saltos DST).
-- Filters: p_operacion_id (NULL = todas), p_solo_reproceso
--   TRUE  → solo reprocesos (partida_origen_id IS NOT NULL)
--   FALSE → solo originales
--   NULL  → todos
-- Output: one row per (ejecucion × día de producción), prorated rollos + kg.
-- SELECT mes.get_reporte_produccion_acabado('2026-06-01','2026-06-11');
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.get_reporte_produccion_acabado(
    p_fecha_desde    DATE,
    p_fecha_hasta    DATE,
    p_operacion_id   INT     DEFAULT NULL,
    p_solo_reproceso BOOLEAN DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario'
AS $$
WITH ejecuciones AS (
    SELECT
        ppe.id              AS ejecucion_id,
        ppe.fyh_inicio,
        ppe.fyh_fin,
        ppe.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local,
        ppe.fyh_fin    AT TIME ZONE 'America/Lima' AS fin_local,
        ppe.maquina_id,
        pp.operacion_id,
        p.id                AS partida_id,
        p.numero            AS partida_numero,
        p.fyh_cre           AS partida_fyh_cre,
        p.tercero_id,
        p.partida_origen_id,
        ppe.cantidad_rollos AS rollos_total,
        ppe.peso_kg         AS kg_total,
        EXTRACT(EPOCH FROM (ppe.fyh_fin - ppe.fyh_inicio)) AS duracion_total_seg
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    WHERE ppe.estado    = 'COMPLETADO'
      AND ppe.fyh_fin   IS NOT NULL
      AND (p_operacion_id   IS NULL OR pp.operacion_id = p_operacion_id)
      AND (p_solo_reproceso IS NULL
           OR (p_solo_reproceso = TRUE  AND p.partida_origen_id IS NOT NULL)
           OR (p_solo_reproceso = FALSE AND p.partida_origen_id IS     NULL))
      -- Loose pre-filter (±1 día); la atribución exacta al día se hace por segmento.
      AND DATE(ppe.fyh_inicio AT TIME ZONE 'America/Lima') <= p_fecha_hasta + 1
      AND DATE(ppe.fyh_fin   AT TIME ZONE 'America/Lima') >= p_fecha_desde - 1
),
-- Expande cada ejecución en un segmento por día de producción (corte 07:00).
-- Genera inicios de día desde las 07:00 del día previo al inicio, en pasos
-- de 24 h → siempre en 07:00; el día = fecha del inicio del segmento.
segmentos AS (
    SELECT
        e.*,
        slot.dia_start::date                                 AS dia,
        GREATEST(e.inicio_local, slot.dia_start)             AS seg_inicio,
        LEAST(e.fin_local, slot.dia_start + interval '24 hours') AS seg_fin
    FROM ejecuciones e
    CROSS JOIN LATERAL generate_series(
        date_trunc('day', e.inicio_local) - interval '17 hours',  -- 07:00 del día previo
        e.fin_local,
        interval '24 hours'
    ) AS slot(dia_start)
    -- fecha = día de producción (07:00→07:00); filtro exacto al rango pedido
    WHERE slot.dia_start::date BETWEEN p_fecha_desde AND p_fecha_hasta
      -- descarta segmentos sin solape real
      AND LEAST(e.fin_local, slot.dia_start + interval '24 hours')
        > GREATEST(e.inicio_local, slot.dia_start)
),
segmentos_fraccion AS (
    SELECT
        s.*,
        CASE
            WHEN s.duracion_total_seg > 0
            THEN EXTRACT(EPOCH FROM (s.seg_fin - s.seg_inicio)) / s.duracion_total_seg
            ELSE 1.0
        END AS fraccion
    FROM segmentos s
),
-- Reparto de rollos por RESTO MAYOR (Hamilton) dentro de cada ejecución:
-- los enteros por segmento suman EXACTO al total en rango de la ejecución,
-- sin inflar (redondear cada segmento por separado sí inflaba).
--   rollos_target   = entero objetivo del tramo en rango
--   rollos_base     = piso por segmento
--   leftover R      = rollos_target - Σ pisos; va a los R restos mayores
-- kg queda continuo (sin redondear aquí); se formatea al mostrar.
segmentos_rollos AS (
    SELECT
        sf.*,
        FLOOR(COALESCE(sf.rollos_total, 0) * sf.fraccion)::int AS rollos_base,
        (ROUND(SUM(COALESCE(sf.rollos_total, 0) * sf.fraccion)
               OVER (PARTITION BY sf.ejecucion_id)))::int      AS rollos_target,
        (SUM(FLOOR(COALESCE(sf.rollos_total, 0) * sf.fraccion))
               OVER (PARTITION BY sf.ejecucion_id))::int       AS rollos_base_sum,
        ROW_NUMBER() OVER (
            PARTITION BY sf.ejecucion_id
            ORDER BY (COALESCE(sf.rollos_total, 0) * sf.fraccion)
                     - FLOOR(COALESCE(sf.rollos_total, 0) * sf.fraccion) DESC,
                     sf.seg_inicio
        )                                                       AS rem_rank
    FROM segmentos_fraccion sf
)
SELECT COALESCE(jsonb_agg(row_obj ORDER BY dia, operacion, ejecucion_id), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'fecha',              sr.dia,
        'ejecucion_id',       sr.ejecucion_id,
        'operacion_id',       sr.operacion_id,
        'operacion',          o.nombre,
        'operacion_codigo',   o.codigo,
        'maquina_id',         sr.maquina_id,
        'maquina',            m.nombre,
        'partida_id',         sr.partida_id,
        'partida_codigo',     EXTRACT(YEAR FROM sr.partida_fyh_cre)::TEXT || '-' || LPAD(sr.partida_numero::TEXT, 4, '0'),
        'cliente',            c.nombre,
        'es_reproceso',       sr.partida_origen_id IS NOT NULL,
        'partida_origen_id',  sr.partida_origen_id,
        -- base + 1 si el segmento está entre los R restos mayores de la ejecución
        'rollos',             sr.rollos_base
                              + CASE WHEN sr.rem_rank <= (sr.rollos_target - sr.rollos_base_sum)
                                     THEN 1 ELSE 0 END,
        'kg',                 ROUND((COALESCE(sr.kg_total, 0) * sr.fraccion)::numeric, 4),
        'fyh_inicio',         sr.fyh_inicio,
        'fyh_fin',            sr.fyh_fin,
        'fraccion',           ROUND(sr.fraccion::numeric, 4)
    )                    AS row_obj,
    sr.dia               AS dia,
    o.nombre             AS operacion,
    sr.ejecucion_id      AS ejecucion_id
    FROM segmentos_rollos sr
    JOIN mes.operacion o  ON o.id  = sr.operacion_id
    JOIN mes.partida p    ON p.id  = sr.partida_id
    LEFT JOIN mes.maquina m  ON m.id  = sr.maquina_id
    LEFT JOIN tercero c   ON c.id  = sr.tercero_id
) sub;
$$;

GRANT EXECUTE ON FUNCTION mes.get_reporte_produccion_acabado(DATE, DATE, INT, BOOLEAN) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- REPORTE PRODUCCIÓN ACABADO — por TURNO (corte 07:00 / 19:00 Lima)
-- Variante de get_reporte_produccion_acabado: en vez de cortar a
-- medianoche, corta en los límites de turno y prorratea.
--   DIA   = 07:00 → 19:00
--   NOCHE = 19:00 → 07:00 (del día siguiente)
-- fecha = día en que INICIA el turno: un turno NOCHE que arranca el
--   15 a las 19:00 se atribuye al 15, aunque termine el 16.
-- Perú (America/Lima) no usa horario de verano → la aritmética en
--   hora local de pared es exacta (sin saltos DST).
-- SELECT mes.get_reporte_produccion_acabado_turno('2026-06-01','2026-06-11');
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.get_reporte_produccion_acabado_turno(
    p_fecha_desde    DATE,
    p_fecha_hasta    DATE,
    p_operacion_id   INT     DEFAULT NULL,
    p_solo_reproceso BOOLEAN DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario'
AS $$
WITH ejecuciones AS (
    SELECT
        ppe.id              AS ejecucion_id,
        ppe.fyh_inicio,
        ppe.fyh_fin,
        ppe.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local,
        ppe.fyh_fin    AT TIME ZONE 'America/Lima' AS fin_local,
        ppe.maquina_id,
        pp.operacion_id,
        p.id                AS partida_id,
        p.numero            AS partida_numero,
        p.fyh_cre           AS partida_fyh_cre,
        p.tercero_id,
        p.partida_origen_id,
        ppe.cantidad_rollos AS rollos_total,
        ppe.peso_kg         AS kg_total,
        EXTRACT(EPOCH FROM (ppe.fyh_fin - ppe.fyh_inicio)) AS duracion_total_seg
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    WHERE ppe.estado    = 'COMPLETADO'
      AND ppe.fyh_fin   IS NOT NULL
      AND (p_operacion_id   IS NULL OR pp.operacion_id = p_operacion_id)
      AND (p_solo_reproceso IS NULL
           OR (p_solo_reproceso = TRUE  AND p.partida_origen_id IS NOT NULL)
           OR (p_solo_reproceso = FALSE AND p.partida_origen_id IS     NULL))
      -- Loose pre-filter (±1 día); la atribución exacta al turno se hace por segmento.
      AND DATE(ppe.fyh_inicio AT TIME ZONE 'America/Lima') <= p_fecha_hasta + 1
      AND DATE(ppe.fyh_fin   AT TIME ZONE 'America/Lima') >= p_fecha_desde - 1
),
-- Expande cada ejecución en un segmento por turno que atraviesa.
-- Genera límites de turno desde las 19:00 del día previo al inicio,
-- en pasos de 12 h → 19:00, 07:00, 19:00, ... (siempre en :00).
segmentos AS (
    SELECT
        e.*,
        slot.shift_start::date                                AS dia,
        CASE WHEN EXTRACT(HOUR FROM slot.shift_start) = 7
             THEN 'DIA' ELSE 'NOCHE' END                      AS turno,
        GREATEST(e.inicio_local, slot.shift_start)            AS seg_inicio,
        LEAST(e.fin_local, slot.shift_start + interval '12 hours') AS seg_fin
    FROM ejecuciones e
    CROSS JOIN LATERAL generate_series(
        date_trunc('day', e.inicio_local) - interval '5 hours',  -- 19:00 del día previo
        e.fin_local,
        interval '12 hours'
    ) AS slot(shift_start)
    -- fecha = día de inicio del turno; filtro exacto al rango pedido
    WHERE slot.shift_start::date BETWEEN p_fecha_desde AND p_fecha_hasta
      -- descarta segmentos sin solape real
      AND LEAST(e.fin_local, slot.shift_start + interval '12 hours')
        > GREATEST(e.inicio_local, slot.shift_start)
),
segmentos_fraccion AS (
    SELECT
        s.*,
        CASE
            WHEN s.duracion_total_seg > 0
            THEN EXTRACT(EPOCH FROM (s.seg_fin - s.seg_inicio)) / s.duracion_total_seg
            ELSE 1.0
        END AS fraccion
    FROM segmentos s
),
-- Reparto de rollos por RESTO MAYOR (Hamilton) dentro de cada ejecución:
-- los enteros por segmento suman EXACTO al total en rango de la ejecución,
-- sin inflar (redondear cada segmento por separado sí inflaba).
-- kg queda continuo (sin redondear aquí); se formatea al mostrar.
segmentos_rollos AS (
    SELECT
        sf.*,
        FLOOR(COALESCE(sf.rollos_total, 0) * sf.fraccion)::int AS rollos_base,
        (ROUND(SUM(COALESCE(sf.rollos_total, 0) * sf.fraccion)
               OVER (PARTITION BY sf.ejecucion_id)))::int      AS rollos_target,
        (SUM(FLOOR(COALESCE(sf.rollos_total, 0) * sf.fraccion))
               OVER (PARTITION BY sf.ejecucion_id))::int       AS rollos_base_sum,
        ROW_NUMBER() OVER (
            PARTITION BY sf.ejecucion_id
            ORDER BY (COALESCE(sf.rollos_total, 0) * sf.fraccion)
                     - FLOOR(COALESCE(sf.rollos_total, 0) * sf.fraccion) DESC,
                     sf.seg_inicio
        )                                                       AS rem_rank
    FROM segmentos_fraccion sf
)
SELECT COALESCE(jsonb_agg(row_obj ORDER BY dia, turno, operacion, ejecucion_id), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'fecha',              sr.dia,
        'turno',              sr.turno,
        'ejecucion_id',       sr.ejecucion_id,
        'operacion_id',       sr.operacion_id,
        'operacion',          o.nombre,
        'operacion_codigo',   o.codigo,
        'maquina_id',         sr.maquina_id,
        'maquina',            m.nombre,
        'partida_id',         sr.partida_id,
        'partida_codigo',     EXTRACT(YEAR FROM sr.partida_fyh_cre)::TEXT || '-' || LPAD(sr.partida_numero::TEXT, 4, '0'),
        'cliente',            c.nombre,
        'es_reproceso',       sr.partida_origen_id IS NOT NULL,
        'partida_origen_id',  sr.partida_origen_id,
        -- base + 1 si el segmento está entre los R restos mayores de la ejecución
        'rollos',             sr.rollos_base
                              + CASE WHEN sr.rem_rank <= (sr.rollos_target - sr.rollos_base_sum)
                                     THEN 1 ELSE 0 END,
        'kg',                 ROUND((COALESCE(sr.kg_total, 0) * sr.fraccion)::numeric, 4),
        'fyh_inicio',         sr.fyh_inicio,
        'fyh_fin',            sr.fyh_fin,
        'fraccion',           ROUND(sr.fraccion::numeric, 4)
    )                    AS row_obj,
    sr.dia               AS dia,
    sr.turno             AS turno,
    o.nombre             AS operacion,
    sr.ejecucion_id      AS ejecucion_id
    FROM segmentos_rollos sr
    JOIN mes.operacion o  ON o.id  = sr.operacion_id
    JOIN mes.partida p    ON p.id  = sr.partida_id
    LEFT JOIN mes.maquina m  ON m.id  = sr.maquina_id
    LEFT JOIN tercero c   ON c.id  = sr.tercero_id
) sub;
$$;

GRANT EXECUTE ON FUNCTION mes.get_reporte_produccion_acabado_turno(DATE, DATE, INT, BOOLEAN) TO authenticated;
-- ═══════════════════════════════════════════════════════════════
-- REPORTE MATIZADOS — corrección de color en máquina por insumo
-- Un matizado es un consumo extra de insumo (motivo MATIZADO) sobre
-- una ejecución de paso, para ajustar el tono de una partida.
-- Equivalente nuevo del legacy get_componentes_matizado, pero como
-- reporte por rango de fecha en vez de por partida.
--
-- Grano: una fila por MOVIMIENTO (evento de matizado).
-- Fecha: fecha_hora del movimiento (hora Lima).
--
-- Reversiones: una ejecución corregida (corregir_matizado) genera
--   consumo original (PROD_CONSUMO, factor -1) + reversión
--   (PROD_CONSUMO_REV, factor +1) + nuevo consumo. Todos llevan el
--   motivo MATIZADO. 'cantidad' se firma con (-factor) para que el
--   consumo sume positivo y la reversión negativo → SUM(cantidad)
--   = consumo neto. 'es_reversion' marca las filas de anulación.
--   p_incluir_reversiones = FALSE las oculta (solo consumos, factor -1).
--
-- Filtros: p_cliente_id (NULL = todos), p_insumo_id (NULL = todos).
-- SELECT mes.get_reporte_matizados('2026-06-01','2026-06-18');
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.get_reporte_matizados(
    p_fecha_desde         DATE,
    p_fecha_hasta         DATE,
    p_cliente_id          INT     DEFAULT NULL,
    p_insumo_id           INT     DEFAULT NULL,
    p_incluir_reversiones BOOLEAN DEFAULT TRUE
)
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario'
AS $$
SELECT COALESCE(jsonb_agg(row_obj ORDER BY fecha, partida_numero, insumo, movimiento_id), '[]'::jsonb)
FROM (
    SELECT jsonb_build_object(
        'movimiento_id',    m.id,
        'fecha',            DATE(m.fecha_hora AT TIME ZONE 'America/Lima'),
        'fyh_movimiento',   m.fecha_hora,
        'turno',            CASE WHEN EXTRACT(HOUR FROM m.fecha_hora AT TIME ZONE 'America/Lima') BETWEEN 7 AND 18
                                 THEN 'DIA' ELSE 'NOCHE' END,
        'ejecucion_id',     ppe.id,
        'partida_id',       p.id,
        'partida_codigo',   EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'cliente',          c.nombre,
        'es_reproceso',     p.partida_origen_id IS NOT NULL,
        'operacion_id',     pp.operacion_id,
        'operacion',        o.nombre,
        'operacion_codigo', o.codigo,
        'maquina_id',       ppe.maquina_id,
        'maquina',          mq.nombre,
        'insumo_id',        i.id,
        'insumo_codigo',    i.codigo,
        'insumo',           i.nombre,
        'unidad',           u.codigo,
        'es_reversion',     t.factor = 1,
        -- consumo positivo, reversión negativo (firma por -factor)
        'cantidad',         ROUND((m.cantidad * (-t.factor))::numeric, 5),
        'precio_unitario',  m.precio_unitario,
        'monto',            ROUND((m.cantidad * (-t.factor) * COALESCE(m.precio_unitario, 0))::numeric, 4)
    )                 AS row_obj,
    DATE(m.fecha_hora AT TIME ZONE 'America/Lima') AS fecha,
    p.numero          AS partida_numero,
    i.nombre          AS insumo,
    m.id              AS movimiento_id
    FROM inventario.item_movimientos m
    JOIN inventario.item_movimiento_tipo   t  ON t.id  = m.item_movimiento_tipo_id
    JOIN inventario.item_movimiento_motivo mo ON mo.id = m.motivo_id AND mo.codigo = 'MATIZADO'
    JOIN item    i ON i.id = m.item_id
    JOIN unidad  u ON u.id = i.unidad_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = m.documento_id
                                       AND m.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.partida      p  ON p.id  = pp.partida_id
    JOIN mes.operacion    o  ON o.id  = pp.operacion_id
    LEFT JOIN mes.maquina mq ON mq.id = ppe.maquina_id
    LEFT JOIN tercero     c  ON c.id  = p.tercero_id
    WHERE DATE(m.fecha_hora AT TIME ZONE 'America/Lima') BETWEEN p_fecha_desde AND p_fecha_hasta
      AND (p_cliente_id IS NULL OR p.tercero_id = p_cliente_id)
      AND (p_insumo_id  IS NULL OR m.item_id    = p_insumo_id)
      AND (p_incluir_reversiones OR t.factor = -1)   -- factor -1 = consumo; +1 = reversión
) sub;
$$;

GRANT EXECUTE ON FUNCTION mes.get_reporte_matizados(DATE, DATE, INT, INT, BOOLEAN) TO authenticated;

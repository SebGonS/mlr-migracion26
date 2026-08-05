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
    v_usr_id        int  := get_user_id();
    v_lote_id       int  := (p_inspeccion->>'lote_id')::INT;
    v_ejecucion_id  BIGINT;
    v_es_output     BOOLEAN;
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Resolve lote type and ejecucion_id.
    -- Output rolls: auto-populate from lote.documento_id so the per-ejecucion
    -- view filter can detect this inspection even if the caller omits the field.
    -- Input rolls: caller must supply partida_paso_ejecucion_id explicitly.
    SELECT l.documento_tipo = 'partida_paso_ejecucion',
           COALESCE(
               (p_inspeccion->>'partida_paso_ejecucion_id')::BIGINT,
               CASE WHEN l.documento_tipo = 'partida_paso_ejecucion'
                    THEN l.documento_id::BIGINT END
           )
    INTO v_es_output, v_ejecucion_id
    FROM inventario.lote l
    WHERE l.id = v_lote_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lote % no encontrado.', v_lote_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Eligibility: output roll or input roll in a running partida
    IF NOT (
        v_es_output
        OR EXISTS (
            SELECT 1 FROM mes.partida_componente pc
            JOIN mes.partida p ON p.id = pc.partida_id
            WHERE pc.lote_id = v_lote_id AND p.estado_produccion = 'EN_PRODUCCION'
        )
    ) THEN
        RAISE EXCEPTION 'Lote % no está asociado a una partida activa.', v_lote_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Input rolls must link to an active paso so the view filter works correctly
    IF NOT v_es_output AND v_ejecucion_id IS NULL THEN
        RAISE EXCEPTION 'Se requiere partida_paso_ejecucion_id para inspección de rollo de entrada.'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Input rolls: verify the lote is actually a component of the partida owning this ejecucion
    IF NOT v_es_output THEN
        IF NOT EXISTS (
            SELECT 1
            FROM mes.partida_componente pc2
            JOIN mes.partida_paso pp2        ON pp2.partida_id = pc2.partida_id
            JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp2.id
            WHERE pc2.lote_id = v_lote_id AND ppe.id = v_ejecucion_id
        ) THEN
            RAISE EXCEPTION 'Lote % no es componente de la partida en ejecución %.', v_lote_id, v_ejecucion_id
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_inspeccion', v_usr_id, p_inspeccion);

    -- Parent: inspeccion
    INSERT INTO calidad.inspeccion (lote_id, partida_paso_ejecucion_id, resultado, observacion, empleado_id)
    VALUES (
        v_lote_id,
        v_ejecucion_id,
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
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS idx
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
        'partida_paso_ejecucion_id', i.partida_paso_ejecucion_id,
        'resultado', i.resultado,
        'observacion', i.observacion,
        'empleado_id', i.empleado_id,
        'empleado', e.nombre,
        'fyh_inspeccion', i.fyh_inspeccion,
        'fyh_cre', i.fyh_cre,
        'color_id', vc.color_id,
        'color_nombre', vc.color,
        'color_hex', vc.color_hex,
        'color_x_cliente_hex', vc.color_x_cliente_hex,

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
    LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.id = i.partida_paso_ejecucion_id
    LEFT JOIN mes.partida_paso           pp  ON pp.id  = ppe.partida_paso_id
    LEFT JOIN mes.partida                p   ON p.id   = pp.partida_id
    LEFT JOIN vw_colores                 vc  ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE i.id = p_inspeccion_id;

    RETURN v_result;
END;
$function$;


-- Adding p_solo_output changes arity; CREATE OR REPLACE won't replace the old
-- 1-arg overload, so drop it explicitly to avoid leaving a stale duplicate.
DROP FUNCTION IF EXISTS calidad.get_lotes_pendientes_partida(bigint);
-- Drop the 2-arg signature too: adding flg_rib changes the RETURNS TABLE shape,
-- which CREATE OR REPLACE cannot do in place (return-type change requires a drop).
DROP FUNCTION IF EXISTS calidad.get_lotes_pendientes_partida(bigint, boolean);
CREATE OR REPLACE FUNCTION calidad.get_lotes_pendientes_partida(
    p_partida_id bigint,
    p_solo_output boolean DEFAULT false
)
RETURNS TABLE (
    lote_id                   int,
    lote_codigo               text,
    item_id                   int,
    item_nombre               text,
    item_codigo               text,
    partida_paso_ejecucion_id bigint,
    operacion_id              smallint,
    operacion_codigo          text,
    maquina_id                int,
    maquina_codigo            text,
    ancho                     text,
    peso                      numeric,
    color_id                  int,
    color_nombre              text,
    color_hex                 text,
    color_x_cliente_hex       text,
    fecha_creacion_lote       timestamptz,
    -- Actual production/output date (resolving ejecución's fyh_fin). Prefer this over
    -- fecha_creacion_lote for display: the latter is the migration timestamp for backfilled
    -- rolls. Null for in-process input rolls whose ejecución hasn't finished.
    fecha_produccion          timestamptz,
    -- Display-only label for a RIB / Regular badge. Lives on item_rollo_detalle
    -- (PK item_id), so it's a property of the item, not the lote — rib and regular
    -- are distinct item_ids that may share a display nombre. item_id is the grouping
    -- discriminator; flg_rib is just shown, not filtered or keyed on. Left nullable:
    -- a missing detail row reads as unknown, not a misleading "Regular".
    flg_rib                   boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam','public','calidad','inventario','mes'
AS $$
    -- p_solo_output: when true, restricts to finished output rolls (es_output) —
    -- for the "final QC" flow, so mid-process componente/input rolls from earlier
    -- pasos don't bleed into a screen meant to show only closure-step output.
    SELECT
        v.lote_id,
        v.lote_codigo,
        v.item_id,
        v.item_nombre,
        v.item_codigo,
        v.partida_paso_ejecucion_id,
        v.operacion_id,
        v.operacion_codigo,
        v.maquina_id,
        v.maquina_codigo,
        v.ancho,
        l.cantidad  AS peso,
        v.color_id,
        v.color_nombre,
        v.color_hex,
        v.color_x_cliente_hex,
        v.fecha_creacion_lote,
        v.fecha_produccion,
        ird.flg_rib
    FROM calidad.vw_lotes_pendientes_inspeccion v
    JOIN inventario.lote l ON l.id = v.lote_id
    LEFT JOIN item_rollo_detalle ird ON ird.item_id = v.item_id
    WHERE v.partida_id = p_partida_id
      AND (NOT p_solo_output OR v.es_output)
    ORDER BY v.partida_paso_ejecucion_id, v.fecha_creacion_lote;
$$;


CREATE OR REPLACE FUNCTION calidad.bulk_aprobar_lotes(
    p_lote_ids    int[],
    p_empleado_id int  DEFAULT NULL,
    p_observacion text DEFAULT NULL
)
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
    v_usr_id    int := get_user_id();
    v_approved  int;
    v_results   jsonb;
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('bulk_aprobar_lotes', v_usr_id,
            jsonb_build_object('lote_ids', p_lote_ids, 'empleado_id', p_empleado_id));

    WITH lotes_resueltos AS (
        -- Resolve ejecucion_id via the view — handles both output rolls
        -- (documento_tipo = 'partida_paso_ejecucion') and input rolls
        -- (ejecucion resolved via the active lateral join in the view).
        SELECT v.lote_id, v.partida_paso_ejecucion_id
        FROM calidad.vw_lotes_pendientes_inspeccion v
        WHERE v.lote_id = ANY(p_lote_ids)
    ),
    ins AS (
        INSERT INTO calidad.inspeccion (lote_id, partida_paso_ejecucion_id, resultado, observacion, empleado_id)
        SELECT lr.lote_id, lr.partida_paso_ejecucion_id, 'APROBADO', p_observacion, p_empleado_id
        FROM lotes_resueltos lr
        WHERE NOT EXISTS (
            SELECT 1 FROM calidad.inspeccion ci
            WHERE ci.lote_id                   = lr.lote_id
              AND ci.partida_paso_ejecucion_id = lr.partida_paso_ejecucion_id
        )
        RETURNING id AS inspeccion_id, lote_id
    ),
    upd AS (
        UPDATE inventario.lote
        SET estado_calidad = 'APROBADO'
        WHERE id IN (SELECT lote_id FROM ins)
    )
    SELECT COUNT(*)::int,
           jsonb_agg(jsonb_build_object('lote_id', lote_id, 'inspeccion_id', inspeccion_id))
    INTO v_approved, v_results
    FROM ins;

    IF v_approved > 0 THEN
        INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
        SELECT ur.user_id,
               'Aprobación Masiva de Calidad',
               COALESCE(
                   (SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido
                    FROM usuario WHERE id = v_usr_id),
                   'sistema'
               ) || ' aprobó ' || v_approved || ' rollo(s) en bloque',
               'info',
               jsonb_build_object('objeto_tipo', 'bulk_aprobacion', 'lote_ids', p_lote_ids)
        FROM iam.user_rol ur
        LEFT JOIN iam.rol r ON ur.rol_id = r.id
        WHERE r.code IN ('jefe_planta', 'calidad')
          AND v_usr_id <> ur.user_id;
    END IF;

    RETURN jsonb_build_object(
        'aprobados',  v_approved,
        'resultados', COALESCE(v_results, '[]'::jsonb)
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in bulk_aprobar_lotes - User: %, Lotes: %, Error: %, Detail: %',
                  v_usr_id, p_lote_ids, v_message, v_detail;
        RAISE;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════
-- BULK RECHAZAR LOTES
-- Symmetric counterpart to bulk_aprobar_lotes for non-discrete shared defects
-- (e.g. tone off-spec across a full batch) where per-roll forms are impractical.
--
-- Diverges from bulk_aprobar_lotes intentionally on one point:
--   bulk_aprobar_lotes silently skips ineligible lotes.
--   bulk_rechazar_lotes raises on ANY ineligible lote — because a bulk rejection
--   implies a shared defect verdict; partial application would be misleading.
--
-- Does NOT create a reproceso — inspection recording only.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION calidad.bulk_rechazar_lotes(
    p_lote_ids    int[],
    p_resultado   calidad_estado_enum,  -- REPROCESO | BAJA
    p_observacion text,
    p_empleado_id int  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','calidad','inventario','mes'
AS $function$
DECLARE
    v_message      text;
    v_detail       text;
    v_hint         text;
    v_context      text;
    v_sqlstate     text;
    v_usr_id       int := get_user_id();
    v_rechazados   int;
    v_results      jsonb;
    v_ineligibles  int[];
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Strict eligibility gate: raise if ANY supplied lote is not pending QC.
    SELECT ARRAY_AGG(u) INTO v_ineligibles
    FROM UNNEST(p_lote_ids) u
    WHERE NOT EXISTS (
        SELECT 1 FROM calidad.vw_lotes_pendientes_inspeccion v WHERE v.lote_id = u
    );

    IF v_ineligibles IS NOT NULL THEN
        RAISE EXCEPTION 'Lotes no elegibles para inspección: %. Deben estar pendientes de QC.',
            v_ineligibles;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('bulk_rechazar_lotes', v_usr_id,
            jsonb_build_object('lote_ids', p_lote_ids, 'resultado', p_resultado, 'empleado_id', p_empleado_id));

    WITH lotes_resueltos AS (
        SELECT v.lote_id, v.partida_paso_ejecucion_id
        FROM calidad.vw_lotes_pendientes_inspeccion v
        WHERE v.lote_id = ANY(p_lote_ids)
    ),
    ins AS (
        INSERT INTO calidad.inspeccion (lote_id, partida_paso_ejecucion_id, resultado, observacion, empleado_id)
        SELECT lr.lote_id, lr.partida_paso_ejecucion_id, p_resultado, p_observacion, p_empleado_id
        FROM lotes_resueltos lr
        WHERE NOT EXISTS (
            SELECT 1 FROM calidad.inspeccion ci
            WHERE ci.lote_id                   = lr.lote_id
              AND ci.partida_paso_ejecucion_id = lr.partida_paso_ejecucion_id
        )
        RETURNING id AS inspeccion_id, lote_id
    ),
    upd AS (
        UPDATE inventario.lote
        SET estado_calidad = p_resultado
        WHERE id IN (SELECT lote_id FROM ins)
    )
    SELECT COUNT(*)::int,
           jsonb_agg(jsonb_build_object('lote_id', lote_id, 'inspeccion_id', inspeccion_id))
    INTO v_rechazados, v_results
    FROM ins;

    IF v_rechazados > 0 THEN
        INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
        SELECT ur.user_id,
               'Rechazo Masivo de Calidad',
               COALESCE(
                   (SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido
                    FROM usuario WHERE id = v_usr_id),
                   'sistema'
               ) || ' rechazó ' || v_rechazados || ' rollo(s) como ' || p_resultado,
               'warning',
               jsonb_build_object('objeto_tipo', 'bulk_rechazo', 'lote_ids', p_lote_ids, 'resultado', p_resultado)
        FROM iam.user_rol ur
        LEFT JOIN iam.rol r ON ur.rol_id = r.id
        WHERE r.code IN ('jefe_planta', 'calidad')
          AND v_usr_id <> ur.user_id;
    END IF;

    RETURN jsonb_build_object(
        'rechazados', v_rechazados,
        'resultados', COALESCE(v_results, '[]'::jsonb)
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in bulk_rechazar_lotes - User: %, Lotes: %, Resultado: %, Error: %, Detail: %',
                  v_usr_id, p_lote_ids, p_resultado, v_message, v_detail;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION calidad.bulk_rechazar_lotes(int[], calidad_estado_enum, text, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- DAR DE BAJA LOTE — whole-roll condemnation (≈ SAP mvt 551)
--
-- Posts a PROD_SCRAP movement and soft-deletes the output lote.
-- Prerequisite: lote.estado_calidad must already be 'BAJA'
-- (set by crear_inspeccion with resultado='BAJA').
--
-- Only applies to production output lotes (documento_tipo = 'partida_paso_ejecucion').
-- Guards against downstream movements (same pattern as anular_produccion).
-- Recounts partida_detalle.cantidad_producida after the write-off.
--
-- Valuation: flg_valorizable on PROD_SCRAP is true by default. For client-owned
-- rolls (lote.propietario_id references a tercero marked as cliente), the PROD_SCRAP
-- movement is posted without valuation — same logic as SERV_EGR movements.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION calidad.dar_de_baja_lote(p_lote_id INT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','calidad','inventario','mes'
AS $function$
DECLARE
    v_message        text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id         int  := get_user_id();
    v_estado_calidad calidad_estado_enum;
    v_documento_tipo text;
    v_partida_id     bigint;
    v_scrap_tipo_id  smallint;
    v_doc_mov_id     bigint;
    v_ubicacion_id   int;
    v_item_id        int;
    v_cantidad       numeric;
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 1. Resolve lote
    SELECT l.estado_calidad, l.documento_tipo, l.item_id, l.cantidad
    INTO v_estado_calidad, v_documento_tipo, v_item_id, v_cantidad
    FROM inventario.lote l
    WHERE l.id = p_lote_id AND l.fyh_elm IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lote % no encontrado o ya anulado.', p_lote_id;
    END IF;

    IF v_estado_calidad <> 'BAJA' THEN
        RAISE EXCEPTION
            'Lote % debe tener estado_calidad = BAJA para dar de baja. Estado actual: %.',
            p_lote_id, v_estado_calidad;
    END IF;

    IF v_documento_tipo <> 'partida_paso_ejecucion' THEN
        RAISE EXCEPTION
            'dar_de_baja_lote solo aplica a lotes de salida de producción (documento_tipo = partida_paso_ejecucion). Tipo actual: %.',
            v_documento_tipo;
    END IF;

    -- 2. Guard: no downstream movements beyond the original PROD_ING
    IF EXISTS (
        SELECT 1
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id   = p_lote_id
          AND imt.codigo NOT IN ('PROD_ING', 'PROD_ING_REV')
    ) THEN
        RAISE EXCEPTION
            'Lote % tiene movimientos posteriores (despacho, ajuste, etc.). Anule esos documentos antes de dar de baja.',
            p_lote_id;
    END IF;

    -- 3. Resolve partida for cantidad_producida recount
    SELECT pp.partida_id
    INTO v_partida_id
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN inventario.lote l   ON l.documento_id = pe.id AND l.documento_tipo = 'partida_paso_ejecucion'
    WHERE l.id = p_lote_id;

    -- 4. Lock
    PERFORM 1 FROM inventario.lote WHERE id = p_lote_id FOR UPDATE;

    -- 5. Post PROD_SCRAP movement
    SELECT id INTO v_scrap_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_SCRAP';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    SELECT sa.ubicacion_id INTO v_ubicacion_id
    FROM inventario.vw_stock_lotes_ubicacion sa
    WHERE sa.lote_id = p_lote_id
    LIMIT 1;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad, documento_tipo, documento_id
    )
    VALUES (
        v_doc_mov_id, v_item_id, p_lote_id, v_scrap_tipo_id,
        v_ubicacion_id, v_cantidad, 'calidad_baja', p_lote_id
    );

    -- 6. Soft-delete lote (lote_rollo_detalle kept for traceability)
    UPDATE inventario.lote
    SET fyh_elm = NOW(), usr_elm = v_usr_id
    WHERE id = p_lote_id;

    -- 7. Recount cantidad_producida (same pattern as registrar_produccion / anular_produccion)
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

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('dar_de_baja_lote', v_usr_id, jsonb_build_object('lote_id', p_lote_id));

    RETURN format('Lote #%s dado de baja. Movimiento PROD_SCRAP registrado.', p_lote_id);

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in dar_de_baja_lote - User: %, Lote: %, Error: %, Detail: %',
                  v_usr_id, p_lote_id, v_message, v_detail;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION calidad.dar_de_baja_lote(INT) TO authenticated;


GRANT EXECUTE ON FUNCTION calidad.crear_inspeccion(jsonb)               TO authenticated;
GRANT EXECUTE ON FUNCTION calidad.get_inspeccion(bigint)                 TO authenticated;
GRANT EXECUTE ON FUNCTION calidad.get_lotes_pendientes_partida(bigint, boolean)   TO authenticated;
GRANT EXECUTE ON FUNCTION calidad.bulk_aprobar_lotes(int[], int, text)   TO authenticated;

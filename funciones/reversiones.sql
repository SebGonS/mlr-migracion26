-- ═══════════════════════════════════════════════════════════════
-- REVERSIONES — Admin-Only Undo Operations
-- ═══════════════════════════════════════════════════════════════
-- All functions require elevated permissions and accept a mandatory
-- p_motivo TEXT parameter logged to logs_api for auditability.
--
-- Conventions:
--   - Counter-movements are always posted; rows are never deleted
--     from item_movimientos (audit trail preserved).
--   - Hard DELETE is used only for calidad.inspeccion rows (that
--     table has no soft-delete columns).
--   - State is reset to the last stable pre-action value.
--
-- Prerequisite: migration/23_reversal_movement_types.sql
--
-- Functions:
--   inventario.anular_pesaje                  (inventario.editar)
--   inventario.revertir_cuadre_preparado      (inventario.editar)
--   inventario.anular_cuadre_ejecutado        (inventario.editar)
--   mes.anular_omision_paso                   (produccion.administrar)
--   mes.anular_transferencia_rollo            (produccion.administrar)
--   calidad.anular_inspeccion                 (calidad.crear)
--   calidad.revertir_baja_lote                (calidad.crear)
--   calidad.bulk_anular_decision_calidad      (calidad.crear)
-- ═══════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────
-- inventario.anular_pesaje
-- Reverts the weighing of a single input roll.
-- Resets lote.cantidad to the entrega-declared weight, posts a
-- counter-movement, and removes the pesaje row.
--
-- Guard: roll must not have entered production (no PROD_CONSUMO).
-- Guard: lote must have a entrega_detalle link (origin weight).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.anular_pesaje(
    p_lote_id   BIGINT,
    p_motivo    TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','doc'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int     := get_user_id();
    v_item_id           int;
    v_entrega_id        bigint;
    v_peso_actual       numeric;
    v_peso_declarado    numeric;
    v_ubicacion_id      int;
    v_pesaje_pos_id     smallint;
    v_pesaje_neg_id     smallint;
    v_doc_mov_id        bigint;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para anular el pesaje.';
    END IF;

    -- Resolve lote + originating entrega header
    SELECT l.item_id, l.cantidad, lrd.entrega_id
    INTO   v_item_id, v_peso_actual, v_entrega_id
    FROM   inventario.lote l
    JOIN   inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    WHERE  l.id = p_lote_id AND l.fyh_elm IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lote % no encontrado, ya anulado, o sin registro de rollo asociado.', p_lote_id;
    END IF;

    IF v_entrega_id IS NULL THEN
        RAISE EXCEPTION 'Lote % no tiene guía de ingreso asociada.', p_lote_id;
    END IF;

    -- Declared weight: prefer a per-roll line (lote_id set directly).
    -- Fall back to an aggregated line (lote_id NULL, n_rollos > 1, used by
    -- compra-sourced ingresos — see funciones/compras.sql) prorated evenly
    -- across its declared roll count.
    SELECT grd.cantidad INTO v_peso_declarado
    FROM doc.entrega_detalle grd
    WHERE grd.lote_id = p_lote_id;

    IF NOT FOUND THEN
        SELECT grd.cantidad / NULLIF(grd.n_rollos, 0) INTO v_peso_declarado
        FROM doc.entrega_detalle grd
        WHERE grd.entrega_id = v_entrega_id
          AND grd.item_id    = v_item_id
          AND grd.lote_id IS NULL;
    END IF;

    IF v_peso_declarado IS NULL THEN
        RAISE EXCEPTION 'Lote % (guía %): no se encontró línea de entrega_detalle para determinar el peso declarado.',
            p_lote_id, v_entrega_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventario.pesaje WHERE lote_id = p_lote_id) THEN
        RAISE EXCEPTION 'Lote % no tiene registro de pesaje activo.', p_lote_id;
    END IF;

    -- Guard: no downstream beyond PESAJE_POS/NEG and the lote's own ingress
    -- movement (roll not yet in production). The ingress movement itself
    -- (documento_tipo='entrega', documento_id=v_entrega_id) is what created
    -- the lote and is not a downstream event — exclude it, mirroring the
    -- equivalent guard in doc.anular_entrega.
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = p_lote_id
          AND imt.codigo NOT IN ('PESAJE_POS', 'PESAJE_NEG')
          AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = v_entrega_id)
    ) THEN
        RAISE EXCEPTION
            'Lote % ya tiene movimientos de producción u otros. No se puede anular el pesaje.',
            p_lote_id;
    END IF;

    PERFORM 1 FROM inventario.lote WHERE id = p_lote_id FOR UPDATE;

    -- Post counter-movement only if weight actually changed from declared
    IF v_peso_actual <> v_peso_declarado THEN
        SELECT id INTO v_pesaje_pos_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_POS';
        SELECT id INTO v_pesaje_neg_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_NEG';

        SELECT sa.ubicacion_id INTO v_ubicacion_id
        FROM   inventario.vw_stock_lotes_ubicacion sa
        WHERE  sa.lote_id = p_lote_id
        LIMIT  1;

        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, documento_tipo, documento_id
        )
        VALUES (
            v_doc_mov_id,
            v_item_id,
            p_lote_id,
            CASE WHEN v_peso_actual > v_peso_declarado THEN v_pesaje_neg_id ELSE v_pesaje_pos_id END,
            CASE WHEN v_peso_actual > v_peso_declarado THEN v_ubicacion_id  ELSE NULL END,
            CASE WHEN v_peso_actual < v_peso_declarado THEN v_ubicacion_id  ELSE NULL END,
            ABS(v_peso_actual - v_peso_declarado),
            'anulacion_pesaje',
            p_lote_id
        );
    END IF;

    UPDATE inventario.lote SET cantidad = v_peso_declarado WHERE id = p_lote_id;
    DELETE FROM inventario.pesaje WHERE lote_id = p_lote_id;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_pesaje', v_usr_id,
            jsonb_build_object('lote_id', p_lote_id, 'motivo', p_motivo,
                               'peso_revertido', v_peso_actual,
                               'peso_restaurado', v_peso_declarado));

    RETURN format('Pesaje del lote #%s anulado. Peso restaurado a %s kg (peso declarado en guía).',
                  p_lote_id, v_peso_declarado);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_pesaje - User: %, Lote: %, Error: %, Detail: %',
              v_usr_id, p_lote_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION inventario.anular_pesaje(BIGINT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- inventario.revertir_cuadre_preparado
-- Reopens a cuadre from preparado → borrador.
-- No movements were posted at preparado state; this is a pure
-- state flip with no inventory side effects.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.revertir_cuadre_preparado(
    p_cuadre_id BIGINT,
    p_motivo    TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para revertir el cuadre.';
    END IF;

    UPDATE inventario.cuadre
    SET estado  = 'borrador',
        usr_mod = v_usr_id,
        fyh_mod = now()
    WHERE id = p_cuadre_id AND estado = 'preparado';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuadre % no existe o no está en estado preparado.', p_cuadre_id;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('revertir_cuadre_preparado', v_usr_id,
            jsonb_build_object('cuadre_id', p_cuadre_id, 'motivo', p_motivo));

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in revertir_cuadre_preparado - User: %, Cuadre: %, Error: %, Detail: %',
              v_usr_id, p_cuadre_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION inventario.revertir_cuadre_preparado(BIGINT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- inventario.anular_cuadre_ejecutado
-- Reverses all adjustment movements posted by finalizar_cuadre:
--   AJUSTE_NEG (faltantes): restores deducted stock per lote
--   AJUSTE_POS (sobrantes): removes surplus lotes + soft-deletes them
-- Resets cuadre back to borrador.
--
-- Guard: no downstream movements on surplus lotes created by this cuadre.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.anular_cuadre_ejecutado(
    p_cuadre_id BIGINT,
    p_motivo    TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int  := get_user_id();
    v_cuadre_estado     text;
    v_tipo_ajuste_pos   smallint;
    v_tipo_ajuste_neg   smallint;
    v_doc_mov_id        bigint;
    v_orig_doc_mov_ids  bigint[];
    v_count_neg         int;
    v_count_pos         int;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para anular el cuadre.';
    END IF;

    SELECT estado INTO v_cuadre_estado FROM inventario.cuadre WHERE id = p_cuadre_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuadre % no encontrado.', p_cuadre_id;
    END IF;
    IF v_cuadre_estado <> 'ejecutado' THEN
        RAISE EXCEPTION 'El cuadre #% está en estado %. Solo se pueden anular cuadres en estado ejecutado.',
            p_cuadre_id, v_cuadre_estado;
    END IF;

    SELECT id INTO v_tipo_ajuste_pos FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS';
    SELECT id INTO v_tipo_ajuste_neg FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_NEG';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- Scope to only the movements posted by the most recent finalizar_cuadre
    -- call (its single doc_movimiento_id batch). A cuadre may have been
    -- finalized more than once historically (finalize -> anular -> finalize
    -- again); reversing the whole documento_id history would also re-touch
    -- prior, already-settled batches and (worse) the counter-movements this
    -- same call is about to insert, since they share documento_id too.
    SELECT ARRAY[MAX(im.doc_movimiento_id)]
    INTO   v_orig_doc_mov_ids
    FROM   inventario.item_movimientos im
    JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE  im.documento_tipo = 'cuadre'
      AND  im.documento_id   = p_cuadre_id
      AND  imt.codigo IN ('AJUSTE_NEG','AJUSTE_POS');

    -- Guard: surplus lotes created by this batch must have no downstream movements
    IF EXISTS (
        SELECT 1
        FROM   inventario.lote l
        JOIN   inventario.item_movimientos im      ON im.lote_id = l.id
        JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE  l.documento_tipo = 'cuadre'
          AND  l.documento_id   = p_cuadre_id
          AND  EXISTS (
              SELECT 1 FROM inventario.item_movimientos im2
              JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
              WHERE im2.lote_id = l.id
                AND im2.doc_movimiento_id = ANY(v_orig_doc_mov_ids)
                AND imt2.codigo = 'AJUSTE_POS'
          )
          AND  im.doc_movimiento_id <> ALL(v_orig_doc_mov_ids)
    ) THEN
        RAISE EXCEPTION
            'No se puede anular el cuadre #%: los lotes de sobrante ya tienen movimientos posteriores. Anule esos documentos primero.',
            p_cuadre_id;
    END IF;

    -- Reverse AJUSTE_NEG (faltantes): restore each deducted lote back to stock
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, precio_unitario, documento_tipo, documento_id,
        reversion_movimiento_id
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id, v_tipo_ajuste_pos,
        im.origen_ubicacion_id,   -- was taken from here → restore to same location
        im.cantidad,
        im.precio_unitario,
        'cuadre', p_cuadre_id,
        im.id
    FROM   inventario.item_movimientos im
    JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE  im.documento_tipo   = 'cuadre'
      AND  im.documento_id     = p_cuadre_id
      AND  im.doc_movimiento_id = ANY(v_orig_doc_mov_ids)
      AND  imt.codigo          = 'AJUSTE_NEG';

    GET DIAGNOSTICS v_count_neg = ROW_COUNT;

    -- Reverse AJUSTE_POS (sobrantes): remove each surplus lote from stock
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad, precio_unitario, documento_tipo, documento_id,
        reversion_movimiento_id
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id, v_tipo_ajuste_neg,
        im.destino_ubicacion_id,  -- was added here → remove from same location
        im.cantidad,
        im.precio_unitario,
        'cuadre', p_cuadre_id,
        im.id
    FROM   inventario.item_movimientos im
    JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE  im.documento_tipo   = 'cuadre'
      AND  im.documento_id     = p_cuadre_id
      AND  im.doc_movimiento_id = ANY(v_orig_doc_mov_ids)
      AND  imt.codigo          = 'AJUSTE_POS';

    GET DIAGNOSTICS v_count_pos = ROW_COUNT;

    -- Soft-delete surplus lotes created by the batch being reversed
    UPDATE inventario.lote l
    SET fyh_elm = NOW(), usr_elm = v_usr_id
    WHERE l.documento_tipo = 'cuadre'
      AND l.documento_id   = p_cuadre_id
      AND l.fyh_elm        IS NULL
      AND EXISTS (
          SELECT 1
          FROM   inventario.item_movimientos im
          JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
          WHERE  im.lote_id = l.id
            AND  im.doc_movimiento_id = ANY(v_orig_doc_mov_ids)
            AND  imt.codigo = 'AJUSTE_POS'
      );

    -- Reset cuadre to borrador
    UPDATE inventario.cuadre
    SET estado       = 'borrador',
        fecha_cierre = NULL,
        usr_mod      = v_usr_id,
        fyh_mod      = NOW()
    WHERE id = p_cuadre_id;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_cuadre_ejecutado', v_usr_id,
            jsonb_build_object('cuadre_id', p_cuadre_id, 'motivo', p_motivo,
                               'faltantes_revertidos', v_count_neg,
                               'sobrantes_revertidos', v_count_pos));

    RETURN format('Cuadre #%s anulado: %s ajuste(s) de faltante y %s ajuste(s) de sobrante revertidos.',
                  p_cuadre_id, v_count_neg, v_count_pos);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_cuadre_ejecutado - User: %, Cuadre: %, Error: %, Detail: %',
              v_usr_id, p_cuadre_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION inventario.anular_cuadre_ejecutado(BIGINT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- mes.anular_omision_paso
-- Reopens a paso that was previously omitted by omitir_paso.
-- Deletes the OMITIDO ejecucion row (no movements were posted)
-- and resets partida_paso.estado back to PENDIENTE.
--
-- Guard: no subsequent paso in COMPLETADO state (sequence integrity).
-- Guard: partida not CERRADA or CANCELADA.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mes.anular_omision_paso(
    p_paso_id   BIGINT,
    p_motivo    TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id         int  := get_user_id();
    v_partida_id     bigint;
    v_secuencia      smallint;
    v_op_nombre      text;
    v_partida_estado partida_estado_produccion_enum;
    v_ejecucion_id   bigint;
BEGIN
    IF NOT jwt_has_permission('produccion.administrar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.administrar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para anular la omisión.';
    END IF;

    SELECT pp.partida_id, pp.secuencia, o.nombre
    INTO   v_partida_id, v_secuencia, v_op_nombre
    FROM   mes.partida_paso pp
    JOIN   mes.operacion o ON o.id = pp.operacion_id
    WHERE  pp.id = p_paso_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paso % no encontrado.', p_paso_id;
    END IF;

    SELECT estado_produccion INTO v_partida_estado FROM mes.partida WHERE id = v_partida_id;

    IF v_partida_estado IN ('CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'La partida #% está en estado % y no permite modificaciones.',
            v_partida_id, v_partida_estado;
    END IF;

    SELECT id INTO v_ejecucion_id
    FROM   mes.partida_paso_ejecucion
    WHERE  partida_paso_id = p_paso_id AND estado = 'OMITIDO'
    LIMIT  1;

    IF v_ejecucion_id IS NULL THEN
        RAISE EXCEPTION 'El paso % (#%) no tiene una ejecución OMITIDO activa.', v_op_nombre, p_paso_id;
    END IF;

    -- Guard: no subsequent paso COMPLETADO that depended on this omission
    IF EXISTS (
        SELECT 1
        FROM   mes.partida_paso pp2
        JOIN   mes.partida_paso_ejecucion pe2 ON pe2.partida_paso_id = pp2.id
        WHERE  pp2.partida_id = v_partida_id
          AND  pp2.secuencia  > v_secuencia
          AND  pe2.estado     = 'COMPLETADO'
    ) THEN
        RAISE EXCEPTION
            'No se puede anular la omisión del paso % porque hay pasos posteriores ya completados que dependen de él.',
            v_op_nombre;
    END IF;

    -- omitir_paso only inserted an ejecucion row with no movements — safe to DELETE
    DELETE FROM mes.partida_paso_ejecucion WHERE id = v_ejecucion_id;

    UPDATE mes.partida_paso
    SET estado  = 'PENDIENTE',
        fyh_mod = NOW()
    WHERE id = p_paso_id;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_omision_paso', v_usr_id,
            jsonb_build_object('paso_id', p_paso_id, 'ejecucion_id', v_ejecucion_id,
                               'motivo', p_motivo));

    RETURN format('Omisión del paso %s (#%s) anulada. El paso está disponible para ejecución.',
                  v_op_nombre, p_paso_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_omision_paso - User: %, Paso: %, Error: %, Detail: %',
              v_usr_id, p_paso_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.anular_omision_paso(BIGINT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- mes.anular_transferencia_rollo
-- Symmetric inverse of mes.transferir_rollo_partida.
-- Moves a roll back from p_partida_actual to p_partida_original
-- by reversing the partida_componente assignment.
--
-- Guard: roll must not have been consumed (no PROD_CONSUMO).
-- Guard: p_partida_actual not CERRADA/CANCELADA.
-- Guard: p_partida_original not CERRADA/CANCELADA.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mes.anular_transferencia_rollo(
    p_lote_id           INT,
    p_partida_actual    BIGINT,
    p_partida_original  BIGINT,
    p_motivo            TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','mes','inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id           int := get_user_id();
    v_estado_actual    partida_estado_produccion_enum;
    v_estado_original  partida_estado_produccion_enum;
BEGIN
    IF NOT jwt_has_permission('produccion.administrar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.administrar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para anular la transferencia.';
    END IF;

    -- Roll must currently be in p_partida_actual
    IF NOT EXISTS (
        SELECT 1 FROM mes.partida_componente
        WHERE lote_id = p_lote_id AND partida_id = p_partida_actual
    ) THEN
        RAISE EXCEPTION 'El rollo (lote #%) no está asignado a la partida #%.',
            p_lote_id, p_partida_actual;
    END IF;

    -- Roll must not have been consumed in p_partida_actual
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = p_lote_id AND imt.codigo = 'PROD_CONSUMO'
    ) THEN
        RAISE EXCEPTION
            'El rollo (lote #%) ya fue consumido en producción. No se puede revertir la transferencia.',
            p_lote_id;
    END IF;

    -- Estado checks
    SELECT estado_produccion INTO v_estado_actual FROM mes.partida WHERE id = p_partida_actual;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida actual #% no encontrada.', p_partida_actual;
    END IF;
    IF v_estado_actual IN ('CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'La partida actual #% está en estado % y no permite modificaciones.',
            p_partida_actual, v_estado_actual;
    END IF;

    SELECT estado_produccion INTO v_estado_original FROM mes.partida WHERE id = p_partida_original;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida original #% no encontrada.', p_partida_original;
    END IF;
    IF v_estado_original IN ('CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'La partida original #% está en estado % y no puede recibir rollos.',
            p_partida_original, v_estado_original;
    END IF;

    -- Not already in p_partida_original
    IF EXISTS (
        SELECT 1 FROM mes.partida_componente
        WHERE lote_id = p_lote_id AND partida_id = p_partida_original
    ) THEN
        RAISE EXCEPTION 'El rollo (lote #%) ya está asignado a la partida original #%.',
            p_lote_id, p_partida_original;
    END IF;

    UPDATE mes.partida_componente
    SET partida_id = p_partida_original,
        usr_mod    = v_usr_id,
        fyh_mod    = now()
    WHERE lote_id    = p_lote_id
      AND partida_id = p_partida_actual;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_transferencia_rollo', v_usr_id,
            jsonb_build_object('lote_id', p_lote_id,
                               'partida_actual', p_partida_actual,
                               'partida_original', p_partida_original,
                               'motivo', p_motivo));

    RETURN format('Rollo (lote #%s) revertido de partida #%s a partida #%s.',
                  p_lote_id, p_partida_actual, p_partida_original);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_transferencia_rollo - User: %, Lote: %, Error: %, Detail: %',
              v_usr_id, p_lote_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION mes.anular_transferencia_rollo(INT, BIGINT, BIGINT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- calidad.anular_inspeccion
-- Removes a QC inspection record and resets lote.estado_calidad.
-- If other inspections exist for the same lote, the most recent
-- one's resultado is restored; otherwise resets to PENDIENTE.
--
-- Note: calidad.inspeccion has no soft-delete columns, so rows
-- are hard-deleted in FK order (foto → defecto → inspeccion).
-- The motivo is preserved in logs_api for audit.
--
-- Guard: lote must not have been dispatched (VENTA_EGR/SERV_EGR)
--        or scrapped (PROD_SCRAP).
-- Guard: lote must still be alive (fyh_elm IS NULL).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION calidad.anular_inspeccion(
    p_inspeccion_id BIGINT,
    p_motivo        TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','calidad','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_lote_id       int;
    v_resultado     calidad_estado_enum;
    v_nuevo_estado  calidad_estado_enum;
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para anular la inspección.';
    END IF;

    SELECT ci.lote_id, ci.resultado
    INTO   v_lote_id, v_resultado
    FROM   calidad.inspeccion ci
    WHERE  ci.id = p_inspeccion_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inspección #% no encontrada.', p_inspeccion_id;
    END IF;

    -- Lote must still be alive, UNLESS it was soft-deleted by mes.anular_produccion
    -- reversing the very step that created it (PROD_ING_REV, no PROD_SCRAP). That case
    -- predates the guard added to anular_produccion that now blocks it going forward —
    -- this branch exists only to unblock inspections already orphaned that way. There is
    -- nothing to restore (the roll legitimately no longer exists); just drop the record.
    IF EXISTS (SELECT 1 FROM inventario.lote WHERE id = v_lote_id AND fyh_elm IS NOT NULL) THEN
        IF EXISTS (
            SELECT 1 FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE im.lote_id = v_lote_id AND imt.codigo = 'PROD_SCRAP'
        ) THEN
            RAISE EXCEPTION
                'El lote #% ya fue dado de baja. Use calidad.revertir_baja_lote primero.', v_lote_id;
        END IF;
        -- else: lote was reversed via mes.anular_produccion — fall through and delete
        -- the orphaned inspection below.
    END IF;

    -- Guard: no dispatch or scrap movements
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = v_lote_id
          AND imt.codigo IN ('VENTA_EGR', 'SERV_EGR', 'PROD_SCRAP')
    ) THEN
        RAISE EXCEPTION
            'El lote #% ya fue despachado o dado de baja. No se puede anular la inspección.',
            v_lote_id;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_inspeccion', v_usr_id,
            jsonb_build_object('inspeccion_id', p_inspeccion_id, 'lote_id', v_lote_id,
                               'resultado_original', v_resultado, 'motivo', p_motivo));

    -- Hard-delete in FK order: foto → defecto → inspeccion
    DELETE FROM calidad.inspeccion_foto
    WHERE inspeccion_defecto_id IN (
        SELECT id FROM calidad.inspeccion_defecto WHERE inspeccion_id = p_inspeccion_id
    );
    DELETE FROM calidad.inspeccion_defecto WHERE inspeccion_id = p_inspeccion_id;
    DELETE FROM calidad.inspeccion           WHERE id          = p_inspeccion_id;

    -- Reset estado_calidad to the latest remaining inspection or PENDIENTE
    SELECT ci2.resultado INTO v_nuevo_estado
    FROM   calidad.inspeccion ci2
    WHERE  ci2.lote_id = v_lote_id
    ORDER  BY ci2.fyh_cre DESC
    LIMIT  1;

    UPDATE inventario.lote
    SET estado_calidad = COALESCE(v_nuevo_estado, 'PENDIENTE')
    WHERE id = v_lote_id;

    RETURN format('Inspección #%s (resultado: %s) del lote #%s anulada. Estado_calidad restaurado a %s.',
                  p_inspeccion_id, v_resultado, v_lote_id,
                  COALESCE(v_nuevo_estado::text, 'PENDIENTE'));

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_inspeccion - User: %, Inspeccion: %, Error: %, Detail: %',
              v_usr_id, p_inspeccion_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION calidad.anular_inspeccion(BIGINT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- calidad.revertir_baja_lote
-- Reverses dar_de_baja_lote:
--   - Posts PROD_SCRAP_REV to restore the roll to stock
--   - Un-deletes the lote (clears fyh_elm / usr_elm)
--   - Resets estado_calidad to BAJA (inspection still exists)
--   - Recounts partida_detalle.cantidad_producida
--
-- Guard: lote must be soft-deleted (fyh_elm IS NOT NULL).
-- Guard: PROD_SCRAP movement must exist.
-- Guard: no movements beyond PROD_ING, PROD_ING_REV, PROD_SCRAP.
-- Requires: migration/23_reversal_movement_types.sql (PROD_SCRAP_REV).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION calidad.revertir_baja_lote(
    p_lote_id   INT,
    p_motivo    TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','calidad','inventario','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int     := get_user_id();
    v_item_id           int;
    v_cantidad          numeric;
    v_partida_id        bigint;
    v_ubicacion_id      int;
    v_scrap_rev_tipo_id smallint;
    v_doc_mov_id        bigint;
    v_scrap_mov_id      bigint;
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para revertir la baja.';
    END IF;

    -- Lote must be soft-deleted
    SELECT l.item_id, l.cantidad
    INTO   v_item_id, v_cantidad
    FROM   inventario.lote l
    WHERE  l.id = p_lote_id AND l.fyh_elm IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lote % no encontrado o no está dado de baja (fyh_elm IS NULL).', p_lote_id;
    END IF;

    -- PROD_SCRAP must exist
    IF NOT EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = p_lote_id AND imt.codigo = 'PROD_SCRAP'
    ) THEN
        RAISE EXCEPTION 'Lote % no tiene movimiento PROD_SCRAP. No puede revertirse con esta función.', p_lote_id;
    END IF;

    -- Guard: no movements beyond PROD_ING / PROD_ING_REV / PROD_SCRAP
    IF EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = p_lote_id
          AND imt.codigo NOT IN ('PROD_ING', 'PROD_ING_REV', 'PROD_SCRAP')
    ) THEN
        RAISE EXCEPTION
            'Lote % tiene movimientos posteriores a la baja. Anule esos documentos primero.',
            p_lote_id;
    END IF;

    -- Resolve partida for cantidad_producida recount
    SELECT pp.partida_id INTO v_partida_id
    FROM   mes.partida_paso_ejecucion pe
    JOIN   mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN   inventario.lote l   ON l.documento_id = pe.id AND l.documento_tipo = 'partida_paso_ejecucion'
    WHERE  l.id = p_lote_id;

    -- Restore to the same location the PROD_SCRAP movement took from
    SELECT im.id, im.origen_ubicacion_id INTO v_scrap_mov_id, v_ubicacion_id
    FROM   inventario.item_movimientos im
    JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE  im.lote_id = p_lote_id AND imt.codigo = 'PROD_SCRAP'
    LIMIT  1;

    SELECT id INTO v_scrap_rev_tipo_id
    FROM   inventario.item_movimiento_tipo WHERE codigo = 'PROD_SCRAP_REV';

    IF v_scrap_rev_tipo_id IS NULL THEN
        RAISE EXCEPTION 'Tipo PROD_SCRAP_REV no encontrado. Aplique migration/23_reversal_movement_types.sql primero.';
    END IF;

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- PROD_SCRAP_REV: ingress — restores roll to stock at its original location
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id,
        reversion_movimiento_id
    )
    VALUES (
        v_doc_mov_id, v_item_id, p_lote_id, v_scrap_rev_tipo_id,
        v_ubicacion_id, v_cantidad, 'calidad_baja', p_lote_id,
        v_scrap_mov_id
    );

    -- Un-delete lote
    UPDATE inventario.lote
    SET fyh_elm = NULL, usr_elm = NULL
    WHERE id = p_lote_id;

    -- Reset estado_calidad: inspection that condemned it still exists, so stay at BAJA
    UPDATE inventario.lote SET estado_calidad = 'BAJA' WHERE id = p_lote_id;

    -- Recount cantidad_producida (same pattern as registrar_produccion / anular_produccion)
    UPDATE mes.partida_detalle pd
    SET cantidad_producida = (
        SELECT COUNT(*)
        FROM   inventario.lote l2
        JOIN   mes.partida_paso_ejecucion pe2
                   ON pe2.id = l2.documento_id AND l2.documento_tipo = 'partida_paso_ejecucion'
        JOIN   mes.partida_paso pp2 ON pp2.id = pe2.partida_paso_id
        WHERE  pp2.partida_id = v_partida_id
          AND  l2.item_id     = pd.item_id
          AND  l2.fyh_elm     IS NULL
    ),
    usr_mod = v_usr_id,
    fyh_mod = NOW()
    WHERE pd.partida_id = v_partida_id;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('revertir_baja_lote', v_usr_id,
            jsonb_build_object('lote_id', p_lote_id, 'motivo', p_motivo));

    RETURN format('Baja del lote #%s revertida. Lote restaurado al inventario con estado_calidad BAJA.',
                  p_lote_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in revertir_baja_lote - User: %, Lote: %, Error: %, Detail: %',
              v_usr_id, p_lote_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION calidad.revertir_baja_lote(INT, TEXT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- calidad.bulk_anular_decision_calidad
-- Batch wrapper: calls anular_inspeccion for the most recent
-- inspection of each lote_id. Partial success is allowed —
-- each lote is processed independently and failures are
-- collected in the return payload without aborting the batch.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION calidad.bulk_anular_decision_calidad(
    p_lote_ids  INT[],
    p_motivo    TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','calidad','inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int     := get_user_id();
    v_lote_id       int;
    v_inspeccion_id bigint;
    v_success       jsonb   := '[]'::jsonb;
    v_failed        jsonb   := '[]'::jsonb;
    v_result_msg    text;
BEGIN
    IF NOT jwt_has_permission('calidad.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere calidad.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_motivo IS NULL OR trim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere motivo para la anulación masiva.';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('bulk_anular_decision_calidad', v_usr_id,
            jsonb_build_object('lote_ids', p_lote_ids, 'motivo', p_motivo));

    FOREACH v_lote_id IN ARRAY p_lote_ids LOOP
        -- Most recent inspection for this lote
        SELECT ci.id INTO v_inspeccion_id
        FROM   calidad.inspeccion ci
        WHERE  ci.lote_id = v_lote_id
        ORDER  BY ci.fyh_cre DESC
        LIMIT  1;

        IF v_inspeccion_id IS NULL THEN
            v_failed := v_failed || jsonb_build_object(
                'lote_id', v_lote_id,
                'error', 'Sin inspección activa para este lote'
            );
            CONTINUE;
        END IF;

        BEGIN
            SELECT calidad.anular_inspeccion(v_inspeccion_id, p_motivo) INTO v_result_msg;
            v_success := v_success || jsonb_build_object(
                'lote_id',       v_lote_id,
                'inspeccion_id', v_inspeccion_id,
                'message',       v_result_msg
            );
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT;
            v_failed := v_failed || jsonb_build_object(
                'lote_id',       v_lote_id,
                'inspeccion_id', v_inspeccion_id,
                'error',         v_message
            );
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'anulados', jsonb_array_length(v_success),
        'fallidos', jsonb_array_length(v_failed),
        'total',    jsonb_array_length(v_success) + jsonb_array_length(v_failed),
        'success',  v_success,
        'failed',   v_failed
    );

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in bulk_anular_decision_calidad - User: %, Lotes: %, Error: %, Detail: %',
              v_usr_id, p_lote_ids, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION calidad.bulk_anular_decision_calidad(INT[], TEXT) TO authenticated;


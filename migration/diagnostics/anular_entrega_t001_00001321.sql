-- ═══════════════════════════════════════════════════════════════
-- Anulación de guía t001-00001321 (entrega #11466, ingreso)
-- Partidas afectadas: 6349, 6350, 6351
--
-- Bugs encontrados y arreglados en funciones/reversiones.sql
-- (inventario.anular_pesaje) durante este trabajo, 2026-07-10:
--   1. Join a columna inexistente (lote_rollo_detalle.entrega_detalle_id)
--      -> corregido a lote_rollo_detalle.entrega_id + entrega_detalle.lote_id.
--   2. Guías de compra (como esta) guardan una sola línea agregada por
--      item en doc.entrega_detalle (lote_id NULL, cantidad total, n_rollos),
--      no una línea por rollo -> se agregó fallback que prorratea
--      cantidad / n_rollos cuando no hay línea 1:1 por lote.
--   3. El guard "sin movimientos posteriores" no excluía el propio
--      movimiento de ingreso del lote (p.ej. COMPRA_ING) -> se agregó
--      la misma exclusión que ya usa doc.anular_entrega
--      (documento_tipo='entrega' AND documento_id=<esta guía>).
--
-- Orden de ejecución (correr cada bloque y revisar el resultado):
--   1. Redesplegar la función corregida
--   2. Anular el pesaje de los 60 rollos bloqueantes
--   3. Verificar que ya no queda nada bloqueando
--   4. Anular la guía
--   5. Verificación final
-- ═══════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────
-- 1) Redesplegar inventario.anular_pesaje (versión corregida)
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
-- 2) Anular el pesaje de los 60 rollos bloqueantes
-- ───────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_lote_id BIGINT;
    v_motivo  TEXT := 'Anulación guía t001-00001321 (entrega #11466)';
BEGIN
    FOREACH v_lote_id IN ARRAY ARRAY[
        171027,171028,171029,171030,171031,171032,171033,171034,171035,171036,
        171037,171038,171039,171040,171041,171042,171043,171044,171045,171046,
        171047,171048,171049,171050,171051,171052,171053,171054,171055,171056,
        171057,171058,171059,171060,171061,171062,171063,171064,171065,171066,
        171067,171068,171069,171070,171071,171072,171073,171074,171075,171076,
        171077,171078,171079,171080,171081,171082,171083,171084,171085,171086
    ]::BIGINT[]
    LOOP
        RAISE NOTICE '%', inventario.anular_pesaje(v_lote_id, v_motivo);
    END LOOP;
END $$;


-- ───────────────────────────────────────────────────────────────
-- 3) Verificar que ya no queda nada bloqueando
-- ───────────────────────────────────────────────────────────────
SELECT doc.get_entrega_anulacion_preview(11466);
-- Esperado: bloqueo_movimiento_posterior = null, partidas_afectadas = []

SELECT pc.partida_id, pc.lote_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE l.documento_tipo = 'entrega' AND l.documento_id = 11466;
-- Esperado: 0 filas


-- CONFIRMADO (2026-07-10): inventario.pesaje ya no tiene fila para 171027
-- (anular_pesaje sí funcionó). Los 60 lotes siguen bloqueados en la preview
-- porque el ingreso original (SERV_ING, ya excluido correctamente por
-- documento_tipo='entrega') y el pesaje (PESAJE_NEG original + PESAJE_POS
-- de reverso, ninguno excluido) son movimientos que NUNCA se borran. El
-- guard de anular_entrega y esta preview no excluían PESAJE_POS/PESAJE_NEG
-- como sí hace el propio guard de anular_pesaje.
--
-- Arreglado en funciones/despacho.sql (doc.get_entrega_anulacion_preview y
-- doc.anular_entrega): ambos ahora excluyen codigo IN ('PESAJE_POS',
-- 'PESAJE_NEG') del check de "movimiento posterior", y en su lugar
-- verifican directamente si queda una fila activa en inventario.pesaje
-- (bloqueo_pesaje_activo en la preview; guard dedicado en anular_entrega).


-- ───────────────────────────────────────────────────────────────
-- 3c) Redesplegar doc.get_entrega_anulacion_preview y doc.anular_entrega
-- (versión corregida)
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_entrega_anulacion_preview(p_entrega_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'mes', 'public'
AS $function$
DECLARE
    v_entrega RECORD;
    v_result  jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT gr.id, gr.fyh_elm, grt.flg_emitida, grt.codigo AS tipo_codigo
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;

    SELECT jsonb_build_object(
        'entrega_id',   p_entrega_id,
        'ya_anulada',   v_entrega.fyh_elm IS NOT NULL,
        'flg_emitida',  v_entrega.flg_emitida,

        'bloqueo_factura', CASE WHEN v_entrega.flg_emitida THEN (
            SELECT jsonb_agg(DISTINCT f.id)
            FROM doc.factura_detalle fd
            JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
            WHERE fd.entrega_id = p_entrega_id
        ) END,

        'bloqueo_movimiento_posterior', CASE WHEN NOT v_entrega.flg_emitida THEN (
            -- PESAJE_POS/PESAJE_NEG movements (original + any reversal posted
            -- by inventario.anular_pesaje) are excluded here: they're pesaje-
            -- domain history, never deleted per this schema's audit-trail
            -- convention, and are resolved via bloqueo_pesaje_activo below
            -- (current pesaje state) rather than by presence of old movements.
            SELECT jsonb_agg(DISTINCT l.id)
            FROM inventario.lote l
            JOIN inventario.item_movimientos im ON im.lote_id = l.id
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE l.documento_tipo = 'entrega' AND l.documento_id = p_entrega_id
              AND l.fyh_elm IS NULL
              AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id)
              AND imt.codigo NOT IN ('PESAJE_POS', 'PESAJE_NEG')
        ) END,

        'bloqueo_pesaje_activo', CASE WHEN NOT v_entrega.flg_emitida THEN (
            -- Lotes still weighed (inventario.pesaje not yet reversed via
            -- inventario.anular_pesaje). Must be cleared before anulación.
            SELECT jsonb_agg(DISTINCT l.id)
            FROM inventario.lote l
            JOIN inventario.pesaje ps ON ps.lote_id = l.id
            WHERE l.documento_tipo = 'entrega' AND l.documento_id = p_entrega_id
              AND l.fyh_elm IS NULL
        ) END,

        'partidas_afectadas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'partida_id',         p.id,
                'numero',             p.numero,
                'estado_produccion',  p.estado_produccion,
                'rollos_de_esta_guia', sub.n_rollos,
                'tiene_pesaje', EXISTS (
                    SELECT 1 FROM mes.partida_componente pc2
                    JOIN inventario.pesaje ps ON ps.lote_id = pc2.lote_id
                    WHERE pc2.partida_id = p.id AND pc2.lote_id IS NOT NULL
                ),
                'tiene_ejecucion', EXISTS (
                    SELECT 1 FROM mes.partida_paso_ejecucion pe
                    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
                    WHERE pp.partida_id = p.id
                )
            ))
            FROM (
                SELECT pc.partida_id, COUNT(*) AS n_rollos
                FROM mes.partida_componente pc
                JOIN inventario.lote l ON l.id = pc.lote_id
                WHERE l.documento_tipo = 'entrega'
                  AND l.documento_id   = p_entrega_id
                  AND pc.lote_id IS NOT NULL
                GROUP BY pc.partida_id
            ) sub
            JOIN mes.partida p ON p.id = sub.partida_id
            WHERE p.estado_produccion NOT IN ('CANCELADA', 'TECO', 'CERRADA')
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.get_entrega_anulacion_preview(BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION doc.anular_entrega(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'public'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_entrega            RECORD;
    v_reversal_tipo   SMALLINT;
    v_doc_mov_id      BIGINT;
    v_mov_count       INT;
    v_lote_count      INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_entrega', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT gr.id, gr.fyh_elm, grt.flg_emitida, grt.codigo AS tipo_codigo,
           grt.item_movimiento_tipo_id
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id;
    END IF;

    -- Devolution tipos have dedicated anulación RPCs (funciones/devoluciones.sql):
    -- their forward movement codes are real business events, not anulación
    -- scaffolding, so they reverse via dedicated *_REV codes, not this
    -- function's generic CASE map.
    IF v_entrega.tipo_codigo IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_cliente para anular esta devolución (%).', v_entrega.tipo_codigo;
    END IF;
    IF v_entrega.tipo_codigo = 'DEVOLUCION_CLIENTE_CRUDO' THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_crudo_cliente para anular esta devolución.';
    END IF;
    IF v_entrega.tipo_codigo = 'DEVOLUCION_PROVEEDOR' THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_proveedor para anular esta devolución.';
    END IF;

    -- ── Outbound guard: block if any active client invoice references this entrega
    IF v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM doc.factura_detalle fd
            JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
            WHERE fd.entrega_id = p_entrega_id
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: está referenciada en facturas activas. Anule primero las facturas.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote has downstream movements.
    -- PESAJE_POS/PESAJE_NEG are excluded here: pesaje-domain movements are
    -- never deleted (audit-trail convention), so old/reversed pesaje history
    -- would otherwise block forever. Active (unreversed) pesaje is caught by
    -- the dedicated guard below instead.
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN inventario.item_movimientos im ON im.lote_id = l.id
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
              -- Any movement NOT from this entrega means the lote was used downstream
              AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id)
              AND imt.codigo NOT IN ('PESAJE_POS', 'PESAJE_NEG')
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más lotes recibidos ya tienen movimientos posteriores (consumo, producción o redespacho).',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote still has an active
    -- (unreversed) pesaje record — must run inventario.anular_pesaje first.
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN inventario.pesaje ps ON ps.lote_id = l.id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más lotes recibidos tienen pesaje activo. Anule el pesaje (inventario.anular_pesaje) primero.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote is still reserved on an active partida
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN mes.partida_componente pc ON pc.lote_id = l.id
            JOIN mes.partida pr             ON pr.id      = pc.partida_id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
              AND pr.estado_produccion NOT IN ('CANCELADA', 'TECO', 'CERRADA')
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más rollos recibidos están reservados en una partida activa. Anule la partida (mes.anular_partida) antes de anular la guía.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Resolve reversal movement tipo
    SELECT imt2.id INTO v_reversal_tipo
    FROM inventario.item_movimiento_tipo imt1
    JOIN inventario.item_movimiento_tipo imt2 ON imt2.codigo = CASE imt1.codigo
        WHEN 'COMPRA_ING' THEN 'DEV_PROV_EGR'
        WHEN 'SERV_ING'   THEN 'DEV_CLI_EGR'
        WHEN 'SERV_EGR'   THEN 'SERV_DEV_ING'
        WHEN 'VENTA_EGR'  THEN 'DEV_CLI_ING'
        ELSE NULL
    END
    WHERE imt1.id = v_entrega.item_movimiento_tipo_id;

    IF v_reversal_tipo IS NULL THEN
        RAISE EXCEPTION
            'Guía #%: no existe tipo de movimiento de reversal para el tipo de guía "%". Contactar administrador.',
            p_entrega_id, v_entrega.tipo_codigo;
    END IF;

    -- ── Shared doc_movimiento_id for all reversal movements
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- ── Post reversal movements (swaps origen_ubicacion_id ↔ destino_ubicacion_id)
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id,
        item_id, lote_id,
        item_movimiento_tipo_id,
        origen_ubicacion_id,
        destino_ubicacion_id,
        cantidad, fecha_hora,
        documento_tipo, documento_id,
        observacion
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id,
        v_reversal_tipo,
        im.destino_ubicacion_id,   -- swap: destination becomes the new origin
        im.origen_ubicacion_id,    -- swap: origin becomes the new destination
        im.cantidad,
        NOW(),
        'entrega',
        p_entrega_id,
        'ANULACION guía #' || p_entrega_id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega'
      AND im.documento_id   = p_entrega_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    -- ── For inbound entregas: retire the lotes that were created by this entrega
    IF NOT v_entrega.flg_emitida THEN
        UPDATE inventario.lote
        SET usr_elm = v_usr_id, fyh_elm = NOW()
        WHERE documento_tipo = 'entrega'
          AND documento_id   = p_entrega_id
          AND fyh_elm        IS NULL;

        GET DIAGNOSTICS v_lote_count = ROW_COUNT;
    END IF;

    -- ── Mark entrega as cancelled
    UPDATE doc.entrega
    SET usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE id = p_entrega_id;

    RETURN format('Guía #%s anulada. %s movimiento(s) revertido(s)%s.',
        p_entrega_id,
        v_mov_count,
        CASE WHEN NOT v_entrega.flg_emitida THEN format(', %s lote(s) dado(s) de baja', v_lote_count) ELSE '' END
    );
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.anular_entrega(BIGINT) TO authenticated;


-- ───────────────────────────────────────────────────────────────
-- 3d) Reverificar la preview con las funciones corregidas
-- ───────────────────────────────────────────────────────────────
SELECT doc.get_entrega_anulacion_preview(11466);
-- Esperado ahora: bloqueo_movimiento_posterior = null, bloqueo_pesaje_activo = null,
-- partidas_afectadas = []


-- ───────────────────────────────────────────────────────────────
-- 4) Anular la guía de ingreso
-- Descomentar y correr solo después de confirmar el paso 3d.
-- ───────────────────────────────────────────────────────────────
-- SELECT doc.anular_entrega(11466);


-- ───────────────────────────────────────────────────────────────
-- 5) Verificación final
-- ───────────────────────────────────────────────────────────────
SELECT id, fyh_elm FROM doc.entrega WHERE id = 11466;
SELECT id, estado_produccion FROM mes.partida WHERE id IN (6349, 6350, 6351);

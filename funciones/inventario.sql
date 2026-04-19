-- ═══════════════════════════════════════════════════════════════
-- INVENTARIO FUNCTIONS — cuadre de inventario (reconciliation)
-- ═══════════════════════════════════════════════════════════════
-- Replaces public.{crear,get,update,finalizar}_cuadre_inventario
-- and public.get_insumo_movimientos_cuadre.
--
-- Key changes from legacy:
--   • insumo_id → item_id
--   • stock snapshot sourced from inventario.vw_stock_general (INSUMO tipo)
--     joined with inventario.item_valoracion for MAP + stock_valorado
--   • adjustments posted directly to inventario.item_movimientos
--     (AJUSTE_POS / AJUSTE_NEG) — no longer uses entrada/salida_inventario
--   • AJUSTE_NEG uses mes.calcular_fifo() for lote-level FIFO resolution
--   • AJUSTE_POS creates a new inventario.lote per surplus item
-- ═══════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────
-- inventario.crear_cuadre
-- Snapshots current insumo stock + MAP into cuadre_detalle.
-- Returns the new cuadre_id (BIGINT).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.crear_cuadre()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','inventario','mes'
AS $$
DECLARE
    v_cuadre_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO inventario.cuadre (usr_cre)
    VALUES (get_user_id())
    RETURNING id INTO v_cuadre_id;

    -- Source from item catalog (all INSUMOs), not vw_stock_general.
    -- vw_stock_general only includes items with qty > 0 — items fully consumed
    -- wouldn't appear on the count sheet, preventing discovery of phantom stock.
    -- cantidad_sistema = 0 for items with no open lotes; operators can still flag them.
    INSERT INTO inventario.cuadre_detalle (
        cuadre_id,
        item_id,
        cantidad_sistema,
        precio_promedio_sistema,
        stock_valorado_sistema,
        ult_precio_compra
    )
    SELECT
        v_cuadre_id,
        i.id,
        COALESCE(sg.cantidad_total, 0),
        COALESCE(iv.precio_promedio, 0),
        COALESCE(iv.stock_valorado,  0),
        -- last purchase price: most recent COMPRA_ING movement for this item
        (SELECT im2.precio_unitario
         FROM inventario.item_movimientos im2
         JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
         WHERE im2.item_id = i.id
           AND imt2.codigo = 'COMPRA_ING'
         ORDER BY im2.fecha_hora DESC NULLS LAST
         LIMIT 1)
    FROM item i
    JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
    LEFT JOIN inventario.vw_stock_general  sg ON sg.item_id  = i.id
    LEFT JOIN inventario.item_valoracion   iv ON iv.item_id  = i.id
    WHERE i.flg_elm = false;

    RETURN v_cuadre_id;
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- inventario.get_cuadre
-- Returns full cuadre header + detalle as JSONB.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.get_cuadre(p_cuadre_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','inventario','mes'
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'cuadre_id',    c.id,
        'fecha_cuadre', c.fecha_cuadre,
        'fecha_cierre', c.fecha_cierre,
        'estado',       c.estado,
        'usr_cre',      c.usr_cre,
        'fyh_cre',      c.fyh_cre,
        'detalle', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id',                      cd.id,
                    'item_id',                 cd.item_id,
                    'item_codigo',             i.codigo,
                    'item_nombre',             i.nombre,
                    'cantidad_sistema',        cd.cantidad_sistema,
                    'cantidad_contada',        cd.cantidad_contada,
                    'precio_promedio_sistema', cd.precio_promedio_sistema,
                    'stock_valorado_sistema',  cd.stock_valorado_sistema,
                    'ult_precio_compra',       cd.ult_precio_compra
                ) ORDER BY i.nombre
            ) FILTER (WHERE cd.id IS NOT NULL),
            '[]'::jsonb
        )
    )
    INTO result
    FROM inventario.cuadre c
    LEFT JOIN inventario.cuadre_detalle cd ON cd.cuadre_id = c.id
    LEFT JOIN item i ON i.id = cd.item_id
    WHERE c.id = p_cuadre_id
    GROUP BY c.id;

    IF result IS NULL THEN
        RAISE EXCEPTION 'Cuadre % no existe', p_cuadre_id;
    END IF;

    RETURN result;
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- inventario.update_cuadre_detalles
-- Bulk-updates cantidad_contada from a JSONB array.
-- Expected format: [{"id": 101, "cantidad_contada": 12.3}, ...]
-- id here is inventario.cuadre_detalle.id (BIGINT).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.update_cuadre_detalles(p_json JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','inventario','mes'
AS $$
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE inventario.cuadre_detalle d
    SET cantidad_contada = u.cantidad_contada,
        fyh_mod          = now(),
        usr_mod          = get_user_id()
    FROM jsonb_to_recordset(p_json) AS u(id bigint, cantidad_contada numeric)
    WHERE d.id = u.id;
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- inventario.finalizar_cuadre
-- Validates all items counted, then posts adjustments:
--   AJUSTE_NEG (faltante): sistema > contada
--     → FIFO-resolves existing lotes via mes.calcular_fifo()
--     → stamps MAP price at time of adjustment
--   AJUSTE_POS (sobrante): contada > sistema
--     → creates a new inventario.lote per item
--     → enters at current MAP so weighted average stays stable
-- Both directions share one doc_movimiento_id (one posting event).
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.finalizar_cuadre(p_cuadre_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','inventario','mes'
AS $$
DECLARE
    v_faltantes         JSONB;
    v_cuadre_estado     inventario.cuadre_estado_enum;
    v_fecha_cierre      TIMESTAMPTZ;
    v_doc_movimiento_id BIGINT;
    v_tipo_ajuste_neg   SMALLINT;
    v_tipo_ajuste_pos   SMALLINT;
    v_ubicacion_id      INT;
    v_fifo_result       JSONB;
    v_rec               RECORD;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Guard: all items must have been counted
    SELECT jsonb_agg(jsonb_build_object('id', id, 'item_id', item_id))
    INTO v_faltantes
    FROM inventario.cuadre_detalle
    WHERE cuadre_id = p_cuadre_id AND cantidad_contada IS NULL;

    IF v_faltantes IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'Hay items sin cantidad contada',
            DETAIL  = v_faltantes::text,
            HINT    = 'Completa los conteos antes de ejecutar el cuadre';
    END IF;

    -- Guard: cuadre must be in borrador or preparado
    SELECT estado, fecha_cierre
    INTO v_cuadre_estado, v_fecha_cierre
    FROM inventario.cuadre WHERE id = p_cuadre_id;

    IF v_fecha_cierre IS NOT NULL OR v_cuadre_estado NOT IN ('borrador','preparado') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'El cuadre no puede ejecutarse',
            DETAIL  = jsonb_build_object(
                          'estado',       v_cuadre_estado,
                          'fecha_cierre', v_fecha_cierre
                      )::text,
            HINT    = 'Solo cuadres en borrador o preparado pueden ejecutarse';
    END IF;

    -- Cache movement type IDs and default ALM_INS location
    SELECT id INTO v_tipo_ajuste_neg FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_NEG';
    SELECT id INTO v_tipo_ajuste_pos FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS';
    SELECT u.id INTO v_ubicacion_id
    FROM inventario.ubicacion u
    JOIN inventario.almacen a ON a.id = u.almacen_id
    WHERE a.codigo = 'ALM_INS'
    LIMIT 1;

    -- One posting event for the entire cuadre
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- ── AJUSTE_NEG: sistema > contada (faltantes físicos) ──────────────────
    -- Build FIFO input from all short items in one call, then post movements.
    SELECT mes.calcular_fifo(
        jsonb_agg(
            jsonb_build_object(
                'item_id',  item_id,
                'cantidad', cantidad_sistema - cantidad_contada
            )
        )
    )
    INTO v_fifo_result
    FROM inventario.cuadre_detalle
    WHERE cuadre_id = p_cuadre_id
      AND cantidad_sistema > cantidad_contada;

    IF v_fifo_result IS NOT NULL THEN
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad,
            precio_unitario,
            documento_tipo, documento_id
        )
        SELECT
            v_doc_movimiento_id,
            (f->>'item_id')::INT,
            (f->>'lote_id')::INT,
            v_tipo_ajuste_neg,
            (f->>'ubicacion_id')::INT,
            (f->>'cantidad')::NUMERIC,
            iv.precio_promedio,        -- stamp MAP at time of adjustment
            'CUADRE',
            p_cuadre_id
        FROM jsonb_array_elements(v_fifo_result) f
        LEFT JOIN inventario.item_valoracion iv ON iv.item_id = (f->>'item_id')::INT;
    END IF;

    -- ── AJUSTE_POS: contada > sistema (sobrantes físicos) ──────────────────
    -- Create a new lote per surplus item and post ingress movement.
    -- Uses CURRENT MAP from item_valoracion (not snapshot): purchases between
    -- cuadre creation and finalization may have changed the price, and the
    -- surplus item was physically present all along at current value.
    -- Falls back to precio_promedio_sistema if no MAP row exists yet.
    FOR v_rec IN
        SELECT cd.item_id,
               cd.cantidad_contada - cd.cantidad_sistema AS diferencia,
               COALESCE(iv.precio_promedio, cd.precio_promedio_sistema, 0) AS precio
        FROM inventario.cuadre_detalle cd
        LEFT JOIN inventario.item_valoracion iv ON iv.item_id = cd.item_id
        WHERE cd.cuadre_id = p_cuadre_id
          AND cd.cantidad_contada > cd.cantidad_sistema
    LOOP
        WITH ins_lote AS (
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad)
            VALUES (v_rec.item_id, 'CUADRE', p_cuadre_id, v_rec.diferencia)
            RETURNING id
        ),
        ins_lrd AS (
            -- Stub lote_rollo_detalle for surplus ROLLO lotes found during cuadre.
            -- No guia_remision_id — these rolls have no ingress document.
            INSERT INTO inventario.lote_rollo_detalle (lote_id, flg_tenido)
            SELECT ins_lote.id, false
            FROM ins_lote
            WHERE EXISTS (
                SELECT 1 FROM item i
                JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
                WHERE i.id = v_rec.item_id
            )
        )
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            destino_ubicacion_id, cantidad,
            precio_unitario,
            documento_tipo, documento_id
        )
        SELECT
            v_doc_movimiento_id,
            v_rec.item_id,
            ins_lote.id,
            v_tipo_ajuste_pos,
            v_ubicacion_id,
            v_rec.diferencia,
            v_rec.precio,    -- enter at MAP so weighted average stays stable
            'CUADRE',
            p_cuadre_id
        FROM ins_lote;
    END LOOP;

    -- Close the cuadre
    UPDATE inventario.cuadre
    SET fecha_cierre = now(),
        estado       = 'ejecutado',
        usr_mod      = get_user_id(),
        fyh_mod      = now()
    WHERE id = p_cuadre_id;

    RETURN jsonb_build_object(
        'message',    'Cuadre finalizado correctamente',
        'cuadre_id',  p_cuadre_id
    );
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- inventario.get_item_movimientos_cuadre
-- Returns movement history for one item in the time window covered
-- by the given cuadre (previous cuadre close → this cuadre snapshot).
-- Replaces public.get_insumo_movimientos_cuadre.
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.get_item_movimientos_cuadre(
    p_item_id   INT,
    p_cuadre_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','inventario','mes'
AS $$
DECLARE
    v_fyh_desde TIMESTAMPTZ;
    v_fyh_hasta TIMESTAMPTZ;
BEGIN
    SELECT ult_cuadre_ejecutado_fecha, fecha_cuadre
    INTO v_fyh_desde, v_fyh_hasta
    FROM inventario.vw_cuadre
    WHERE cuadre_id = p_cuadre_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuadre % no existe', p_cuadre_id;
    END IF;

    RETURN (
        SELECT jsonb_agg(
            jsonb_build_object(
                'id',             im.id,
                'tipo_codigo',    imt.codigo,
                'tipo_nombre',    imt.nombre,
                'cantidad',       im.cantidad * imt.factor,
                'precio',         im.precio_unitario,
                'documento_tipo', im.documento_tipo,
                'documento_id',   im.documento_id,
                'fecha_hora',     im.fecha_hora
            ) ORDER BY im.fecha_hora
        )
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.item_id   = p_item_id
          AND im.fecha_hora >= COALESCE(v_fyh_desde, '2020-01-01')
          AND im.fecha_hora <  v_fyh_hasta
    );
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- inventario.registrar_pesaje_produccion
--
-- Primary ingress weighing flow. Called after rolls are assigned to a
-- partida (via partida_guia_remision) but BEFORE any production order exists.
--
-- Scoped to the full partida — all rolls linked to the partida through its
-- ingress guias are weighed in one call. The client tracks weighing at
-- partida level ("is partida X already weighed?").
--
-- Distributes total weight evenly by roll type:
--   p_peso_regular → split across non-rib rolls linked to the partida
--   p_peso_rib     → split across rib rolls linked to the partida
--   Pass NULL to skip that type.
--
-- For each roll: upserts inventario.pesaje, posts PESAJE_POS/NEG
-- movement for the delta, updates lote.cantidad.
--
-- Idempotent: safe to call again for corrections before production
-- starts. Raises if any roll already has a PROD_CONSUMO movement.
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS inventario.registrar_pesaje_partida(BIGINT, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS inventario.registrar_pesaje_produccion(BIGINT, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION inventario.registrar_pesaje_produccion(
    p_partida_id    BIGINT,
    p_peso_regular  NUMERIC,        -- total kg for regular rolls; NULL = skip
    p_peso_rib      NUMERIC         -- total kg for rib rolls;     NULL = skip
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','mes','doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_pesaje_pos_id     smallint;
    v_pesaje_neg_id     smallint;
    v_doc_movimiento_id bigint;
    v_count_regular     int;
    v_count_rib         int;
    v_peso_por_regular  numeric;
    v_peso_por_rib      numeric;
    v_updated           int := 0;
BEGIN
    IF NOT jwt_has_permission('inventario.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM doc.partida WHERE id = p_partida_id) THEN
        RAISE EXCEPTION 'Partida #% no encontrada.', p_partida_id;
    END IF;

    -- Guard: no roll linked to this partida may already be in production
    IF EXISTS (
        SELECT 1
        FROM doc.partida_guia_remision pgr
        JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = pgr.guia_remision_id
        JOIN inventario.item_movimientos im  ON im.lote_id = grd.lote_id
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE pgr.partida_id = p_partida_id
          AND imt.codigo = 'PROD_CONSUMO'
    ) THEN
        RAISE EXCEPTION
            'No se puede modificar pesos de la partida #%: uno o más rollos ya tienen movimientos de producción.',
            p_partida_id;
    END IF;

    -- Count rolls by type linked to this partida via its ingress guias
    SELECT
        COUNT(*) FILTER (WHERE ird.flg_rib = false),
        COUNT(*) FILTER (WHERE ird.flg_rib = true)
    INTO v_count_regular, v_count_rib
    FROM doc.partida_guia_remision pgr
    JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = pgr.guia_remision_id
    JOIN inventario.lote l      ON l.id = grd.lote_id AND l.flg_elm = false
    JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
    WHERE pgr.partida_id = p_partida_id;

    IF v_count_regular = 0 AND v_count_rib = 0 THEN
        RAISE EXCEPTION 'La partida #% no tiene rollos asignados.', p_partida_id;
    END IF;
    IF p_peso_regular IS NOT NULL AND v_count_regular = 0 THEN
        RAISE EXCEPTION 'Se proporcionó peso_regular pero la partida #% no tiene rollos regulares asignados.', p_partida_id;
    END IF;
    IF p_peso_rib IS NOT NULL AND v_count_rib = 0 THEN
        RAISE EXCEPTION 'Se proporcionó peso_rib pero la partida #% no tiene rollos rib asignados.', p_partida_id;
    END IF;

    v_peso_por_regular := CASE WHEN v_count_regular > 0 AND p_peso_regular IS NOT NULL
                               THEN ROUND(p_peso_regular / v_count_regular, 4) END;
    v_peso_por_rib     := CASE WHEN v_count_rib > 0 AND p_peso_rib IS NOT NULL
                               THEN ROUND(p_peso_rib / v_count_rib, 4) END;

    SELECT id INTO v_pesaje_pos_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_POS';
    SELECT id INTO v_pesaje_neg_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_NEG';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- Upsert pesaje + post weight-delta movement + update lote.cantidad
    WITH rolls AS (
        SELECT
            l.id        AS lote_id,
            l.item_id,
            l.cantidad  AS peso_anterior,
            sa.ubicacion_id,
            ird.flg_rib,
            CASE WHEN ird.flg_rib THEN v_peso_por_rib ELSE v_peso_por_regular END AS peso_nuevo
        FROM doc.partida_guia_remision pgr
        JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = pgr.guia_remision_id
        JOIN inventario.lote l      ON l.id = grd.lote_id AND l.flg_elm = false
        JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
        JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id
        WHERE pgr.partida_id = p_partida_id
          AND CASE WHEN ird.flg_rib THEN v_peso_por_rib     IS NOT NULL
                   ELSE                  v_peso_por_regular IS NOT NULL END
    ),
    pesajes AS (
        INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, usr_cre)
        SELECT r.lote_id, 'INGRESO', r.peso_nuevo, v_usr_id
        FROM rolls r
        ON CONFLICT (lote_id) DO UPDATE
            SET peso_real = EXCLUDED.peso_real,
                tipo      = EXCLUDED.tipo
        RETURNING lote_id
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
            CASE WHEN r.peso_nuevo > r.peso_anterior THEN v_pesaje_pos_id
                 ELSE v_pesaje_neg_id END,
            CASE WHEN r.peso_nuevo < r.peso_anterior THEN r.ubicacion_id ELSE NULL END,
            CASE WHEN r.peso_nuevo > r.peso_anterior THEN r.ubicacion_id ELSE NULL END,
            ABS(r.peso_nuevo - r.peso_anterior),
            'PARTIDA', p_partida_id
        FROM rolls r
        JOIN pesajes p ON p.lote_id = r.lote_id
        WHERE r.peso_nuevo <> r.peso_anterior
    )
    UPDATE inventario.lote l
    SET cantidad = r.peso_nuevo
    FROM rolls r
    WHERE l.id = r.lote_id;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_pesaje_produccion', v_usr_id, jsonb_build_object(
        'partida_id', p_partida_id,
        'peso_regular', p_peso_regular,
        'peso_rib', p_peso_rib
    ));

    RETURN format(
        'Pesaje registrado para partida #%s: %s rollos actualizados (%s regulares × %s kg, %s rib × %s kg).',
        p_partida_id, v_updated,
        COALESCE(v_count_regular, 0), COALESCE(v_peso_por_regular::text, 'sin cambio'),
        COALESCE(v_count_rib, 0),     COALESCE(v_peso_por_rib::text,     'sin cambio')
    );

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_pesaje_produccion - User: %, partida: %, Error: %, Detail: %',
              v_usr_id, p_partida_id, v_message, v_detail;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION inventario.registrar_pesaje_produccion(BIGINT, NUMERIC, NUMERIC) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- inventario.corregir_pesaje_produccion
--
-- NOT YET IN USE — future feature for post-production weight correction.
--
-- Companion to registrar_pesaje_produccion for the rare case where
-- weights need to be corrected AFTER production has started (e.g.
-- scale malfunction discovered mid-run). Unlike the primary flow,
-- this does NOT guard against PROD_CONSUMO movements — correction
-- is explicitly allowed on in-progress orders.
--
-- Writes tipo='CORRECCION' on pesaje to distinguish from the ingress event.
--
-- Guard: blocks if order is TECO / CERRADA / CANCELADA.
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS mes.actualizar_pesos_orden_items(BIGINT, NUMERIC);
DROP FUNCTION IF EXISTS inventario.corregir_pesaje_produccion(BIGINT, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION inventario.corregir_pesaje_produccion(
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
        RAISE EXCEPTION 'No se pueden corregir pesos de una orden en estado %.', v_estado;
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
    VALUES ('corregir_pesaje_produccion', v_usr_id,
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
        INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, usr_cre)
        SELECT r.lote_id, 'CORRECCION', r.peso_nuevo, v_usr_id
        FROM rolls r
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
        '%s pesos corregidos para orden #%s (%s regulares × %s kg, %s rib × %s kg).',
        v_count, p_orden_id,
        COALESCE(v_count_regular, 0), COALESCE(v_peso_por_regular::text, 'sin cambio'),
        COALESCE(v_count_rib, 0),     COALESCE(v_peso_por_rib::text,     'sin cambio')
    );

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in corregir_pesaje_produccion - User: %, orden: %, Error: %, Detail: %',
              v_usr_id, p_orden_id, v_message, v_detail;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION inventario.corregir_pesaje_produccion(BIGINT, NUMERIC, NUMERIC) TO authenticated;


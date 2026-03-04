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
    INSERT INTO inventario.cuadre (usr_cre)
    VALUES (get_user_id())
    RETURNING id INTO v_cuadre_id;

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
        sg.item_id,
        sg.cantidad_total,
        COALESCE(iv.precio_promedio, 0),
        COALESCE(iv.stock_valorado,  0),
        -- last purchase price: most recent COMPRA_ING movement for this item
        (SELECT im2.precio_unitario
         FROM inventario.item_movimientos im2
         JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
         WHERE im2.item_id = sg.item_id
           AND imt2.codigo = 'COMPRA_ING'
         ORDER BY im2.fecha_hora DESC NULLS LAST
         LIMIT 1)
    FROM inventario.vw_stock_general sg
    JOIN item      i  ON i.id  = sg.item_id
    JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
    LEFT JOIN inventario.item_valoracion iv ON iv.item_id = sg.item_id;

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

    -- Cache movement type IDs and default ALM-INS location
    SELECT id INTO v_tipo_ajuste_neg FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_NEG';
    SELECT id INTO v_tipo_ajuste_pos FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS';
    SELECT u.id INTO v_ubicacion_id
    FROM inventario.ubicacion u
    JOIN inventario.almacen a ON a.id = u.almacen_id
    WHERE a.codigo = 'ALM-INS'
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
    FOR v_rec IN
        SELECT item_id,
               cantidad_contada - cantidad_sistema AS diferencia,
               COALESCE(precio_promedio_sistema, 0) AS precio
        FROM inventario.cuadre_detalle
        WHERE cuadre_id = p_cuadre_id
          AND cantidad_contada > cantidad_sistema
    LOOP
        WITH ins_lote AS (
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad)
            VALUES (v_rec.item_id, 'CUADRE', p_cuadre_id, v_rec.diferencia)
            RETURNING id
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

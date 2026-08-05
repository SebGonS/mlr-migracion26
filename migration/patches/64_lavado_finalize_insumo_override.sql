-- ═══════════════════════════════════════════════════════════════
-- Patch 64: finalizar_lavado_maquina accepts an insumos REDEFINITION
--
-- Machine-wash recipes are theoretical and routinely need manual adjustment
-- before running. Previously finalizar_lavado_maquina always posted the
-- recipe aggregate verbatim, with no way for the operator to correct it —
-- so washes with an off recipe were skipped and piled up in PENDIENTE.
--
-- Now, when p_datos.insumos is supplied it REDEFINES the consumption:
--   • authoritative list of {item_id, cantidad} (kg) — adjusted amounts,
--     added or removed items;
--   • rows with cantidad <= 0 are dropped;
--   • an empty/all-zero list posts NO movements ("sin consumo").
-- When p_datos.insumos is absent, the legacy recipe-aggregate path runs
-- unchanged (backward compatible).
--
-- Frontend: the finalize/transcribe modal pre-fills this list from
-- mes.generar_receta_lavado_maquina and lets the operator edit it.
-- Canonical source: funciones/mes.sql
-- ═══════════════════════════════════════════════════════════════

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
    v_fyh_fin           TIMESTAMPTZ;
BEGIN
    IF NOT jwt_has_permission('produccion.ejecutar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.ejecutar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_lavado FROM mes.lavado_maquina WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'lavado_maquina id=% no encontrado.', p_id;
    END IF;

    -- PENDIENTE accepted for backdated transcription (fyh_inicio supplied in payload).
    -- EN_PROCESO is the normal live path.
    IF v_lavado.estado NOT IN ('EN_PROCESO', 'PENDIENTE') THEN
        RAISE EXCEPTION 'lavado_maquina id=% en estado % — se esperaba EN_PROCESO o PENDIENTE.', p_id, v_lavado.estado;
    END IF;

    v_fyh_fin := COALESCE((p_datos->>'fyh_fin')::TIMESTAMPTZ, now());

    -- Consumption source:
    --   • If p_datos.insumos is supplied it REDEFINES what is consumed — the
    --     operator's list is authoritative (adjusted quantities, added/removed
    --     items, or an empty/all-zero list for "sin consumo"). Rows with
    --     cantidad <= 0 are dropped; if none remain, v_insumos is NULL and no
    --     movements are posted. Machine-wash recipes are theoretical and
    --     routinely need manual adjustment before running, so this is the
    --     normal path from the finalize UI.
    --   • Otherwise fall back to the recipe aggregate (legacy behavior),
    --     summed by item across all pasos (fixed quantities, no scaling).
    IF p_datos ? 'insumos' THEN
        SELECT jsonb_agg(jsonb_build_object(
                   'item_id',  (e->>'item_id')::INT,
                   'cantidad', (e->>'cantidad')::NUMERIC))
        INTO v_insumos
        FROM jsonb_array_elements(p_datos->'insumos') e
        WHERE (e->>'cantidad')::NUMERIC > 0;
    ELSE
        SELECT jsonb_agg(jsonb_build_object('item_id', item_id, 'cantidad', cantidad))
        INTO v_insumos
        FROM (
            SELECT lmpi.item_id, SUM(lmpi.cantidad) AS cantidad
            FROM receta.lavado_maquina_paso     lmp
            JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id = lmp.id
            WHERE lmp.receta_id = v_lavado.receta_id
            GROUP BY lmpi.item_id
        ) agg;
    END IF;

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
            documento_tipo, documento_id, motivo_id, fecha_hora
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
            v_motivo_id,
            v_fyh_fin
        FROM jsonb_array_elements(v_consumos) c;
    END IF;

    UPDATE mes.lavado_maquina SET
        estado      = 'COMPLETADO',
        fyh_inicio  = COALESCE(fyh_inicio, (p_datos->>'fyh_inicio')::TIMESTAMPTZ, now()),
        fyh_fin     = v_fyh_fin,
        nota        = COALESCE(p_datos->>'nota', nota),
        usr_mod     = v_usr_id,
        fyh_mod     = now()
    WHERE id = p_id;

    UPDATE mes.maquina SET
        ultimo_mantenimiento = v_fyh_fin,
        usr_mod = v_usr_id,
        fyh_mod = now()
    WHERE id = v_lavado.maquina_id;
END;$$;

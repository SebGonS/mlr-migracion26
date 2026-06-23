-- ============================================================================
-- OPERATIONS PATCH: Full restore → production → dispatch → return flow
-- for 4 partidas being returned by clients for rework.
--
-- CONFIRMED STATE (from diagnostics)
-- ─────────────────────────────────────────────────────────────────────────────
-- 4388  Textil Valy (260)  input rolls in stock (SERV_ING only, saldo>0)
--       ejecucion 7930: 19 rolls 423.4407 kg  — no output lotes
--       ejecucion 7931:  3 rolls  66.8591 kg  — no output lotes
--       Flow: PROD_CONSUMO inputs → PROD_ING outputs → DESPACHO → DEVOLUCION
--
-- 4577  Faride (228)  input rolls dispatched directly (SERV_ING+SERV_EGR, saldo=0)
--       ejecucion 8173: 20 rolls 426.8000 kg  — no output lotes
--       Flow: restore ghost SERV_EGR → PROD_CONSUMO → PROD_ING → DESPACHO → DEVOLUCION
--
-- 4918  Textil Valy (260)  same as 4577
--       ejecucion 8592: 22 rolls 493.9000 kg  — no output lotes
--       Flow: restore ghost SERV_EGR → PROD_CONSUMO → PROD_ING → DESPACHO → DEVOLUCION
--
-- 5090  Textil Valy (260)  output lotes dispatched via entrega 778 (saldo=0)
--       lotes 122731-122748 (18 rolls)
--       Flow: DEVOLUCION only
--
-- entrega GROUPING (one header per tercero)
--   DESPACHO_CLIENTE:          Valy → 4388+4918 outputs | Faride → 4577 outputs
--   DEVOLUCION_CLIENTE_SERVICIO: Valy → 4388+4918+5090  | Faride → 4577
--
-- Single DO block — ends with ROLLBACK. Verify RAISE NOTICE output then COMMIT.
-- ============================================================================


-- ── PRE-FLIGHT (read-only, already verified) ─────────────────────────────────
-- Re-run these selects to confirm state before executing the DO block.

-- Ghost ejecuciones must still have 0 lotes
SELECT pp.partida_id, pe.id AS ejecucion_id, pp.secuencia,
       (SELECT COUNT(*) FROM inventario.lote l
        WHERE l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id) AS lotes_existentes
FROM mes.partida_paso pp
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE pp.partida_id IN (4388, 4577, 4918) AND pe.estado = 'COMPLETADO'
ORDER BY pp.partida_id, pp.secuencia;
-- EXPECT: lotes_existentes = 0 for all

-- 5090 dispatched lotes must still be at saldo 0
SELECT l.id, ls.cantidad_actual
FROM inventario.lote l
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id AND ls.ubicacion_id = 9
WHERE l.id IN (122731,122732,122733,122734,122735,122736,122737,122738,
               122739,122740,122741,122742,122743,122744,122745,122746,122747,122748);
-- EXPECT: cantidad_actual = 0 for all 18


-- ── MAIN ACTION ──────────────────────────────────────────────────────────────
-- ROLLBACK/COMMIT must live OUTSIDE the DO block in PostgreSQL.
BEGIN;

DO $$
DECLARE
    -- Movement / entrega tipo IDs
    v_serv_dev_tipo_id    INT;
    v_prod_consumo_tipo_id INT;
    v_prod_ing_tipo_id    INT;
    v_serv_egr_tipo_id    INT;
    v_despacho_tipo_id    INT;
    v_devolucion_tipo_id  INT;

    v_ubicacion_id  INT := 9;
    v_fecha_retorno         TIMESTAMPTZ := NOW();
    v_fecha_despacho_valy   TIMESTAMPTZ := NOW();
    v_fecha_despacho_faride TIMESTAMPTZ := NOW();

    -- Production manifest — rows in (partida_id, secuencia) order.
    -- Input rolls are sliced sequentially by lote_id within each partida.
    v_manifest JSONB := '[
        {"partida_id": 4388, "ejecucion_id": 7930, "n_rolls": 19, "total_kg": 423.4407},
        {"partida_id": 4388, "ejecucion_id": 7931, "n_rolls":  3, "total_kg":  66.8591},
        {"partida_id": 4577, "ejecucion_id": 8173, "n_rolls": 20, "total_kg": 426.8000},
        {"partida_id": 4918, "ejecucion_id": 8592, "n_rolls": 22, "total_kg": 493.9000}
    ]';

    v_entry          JSONB;
    v_partida_id     BIGINT;
    v_ejecucion_id   BIGINT;
    v_n_rolls        INT;
    v_total_kg       NUMERIC;
    v_partida_offset INT;
    v_prev_partida   BIGINT := -1;

    v_ancho       TEXT;
    v_malla       TEXT;
    v_rendimiento TEXT;
    v_color_x_cli INT;
    v_tenido_id   INT;
    v_flg_antipil BOOLEAN;

    v_doc_mov_id    BIGINT;
    v_entrega_despacho_valy   BIGINT;
    v_entrega_despacho_faride BIGINT;
    v_entrega_dev_valy        BIGINT;
    v_entrega_dev_faride      BIGINT;

    v_lote_rec      RECORD;
    v_new_lote_id   INT;
    v_roll_idx      INT;
    v_peso_roll     NUMERIC;
    v_peso_acum     NUMERIC;
    v_peso_por_roll NUMERIC;
    v_created       INT;
    v_linea_valy    SMALLINT;
    v_linea_faride  SMALLINT;
    v_n             INT;
BEGIN
    -- Resolve tipo IDs
    SELECT id INTO v_serv_dev_tipo_id     FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_DEV_ING';
    SELECT id INTO v_prod_consumo_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';
    SELECT id INTO v_prod_ing_tipo_id     FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING';
    SELECT id INTO v_serv_egr_tipo_id     FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_EGR';
    SELECT id INTO v_despacho_tipo_id     FROM doc.entrega_tipo WHERE codigo = 'DESPACHO_CLIENTE';
    SELECT id INTO v_devolucion_tipo_id   FROM doc.entrega_tipo WHERE codigo = 'DEVOLUCION_CLIENTE_SERVICIO';

    -- ═══════════════════════════════════════════════════════════════════════
    -- STEP 1: Restore ghost SERV_EGR for 4577 and 4918
    -- Their input rolls were dispatched directly (no production registered).
    -- Post SERV_DEV_ING to bring them back before consuming in production.
    -- ═══════════════════════════════════════════════════════════════════════
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id, observacion
    )
    SELECT v_doc_mov_id, l.item_id, l.id, v_serv_dev_tipo_id,
           v_ubicacion_id, l.cantidad,
           'partida_paso_ejecucion', pc_ejecucion.ejecucion_id,
           'Reversa ghost SERV_EGR — restaurar antes de registrar produccion'
    FROM mes.partida_componente pc
    JOIN inventario.lote l ON l.id = pc.lote_id
    JOIN LATERAL (
        SELECT pe.id AS ejecucion_id
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
        WHERE pp.partida_id = pc.partida_id AND pe.estado = 'COMPLETADO'
        ORDER BY pp.secuencia LIMIT 1
    ) pc_ejecucion ON true
    WHERE pc.partida_id IN (4577, 4918);

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'STEP 1 — Restored % ghost-dispatched input lotes (4577+4918)', v_n;

    -- ═══════════════════════════════════════════════════════════════════════
    -- STEP 2: Production — PROD_CONSUMO inputs + PROD_ING output lotes
    -- Covers 4388, 4577, 4918. One doc_mov_id per ejecucion.
    -- ═══════════════════════════════════════════════════════════════════════
    v_partida_offset := 0;

    FOR v_entry IN SELECT value FROM jsonb_array_elements(v_manifest)
    LOOP
        v_partida_id   := (v_entry->>'partida_id')::BIGINT;
        v_ejecucion_id := (v_entry->>'ejecucion_id')::BIGINT;
        v_n_rolls      := (v_entry->>'n_rolls')::INT;
        v_total_kg     := (v_entry->>'total_kg')::NUMERIC;

        IF v_partida_id <> v_prev_partida THEN
            v_partida_offset := 0;
            v_prev_partida   := v_partida_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM inventario.lote
            WHERE documento_tipo = 'partida_paso_ejecucion' AND documento_id = v_ejecucion_id
        ) THEN
            RAISE NOTICE 'STEP 2 — SKIP ejecucion % (lotes already exist)', v_ejecucion_id;
            v_partida_offset := v_partida_offset + v_n_rolls;
            CONTINUE;
        END IF;

        SELECT ancho, malla, rendimiento, color_x_cliente_id, tenido_id, flg_antipilling
        INTO v_ancho, v_malla, v_rendimiento, v_color_x_cli, v_tenido_id, v_flg_antipil
        FROM mes.partida WHERE id = v_partida_id;

        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

        -- Backflush: consume the input rolls for this ejecucion slice
        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, documento_tipo, documento_id
        )
        SELECT v_doc_mov_id, l.item_id, sub.lote_id, v_prod_consumo_tipo_id,
               ls.ubicacion_id, l.cantidad,
               'partida_paso_ejecucion', v_ejecucion_id
        FROM (
            SELECT pc.lote_id, ROW_NUMBER() OVER (ORDER BY pc.lote_id) AS rn
            FROM mes.partida_componente pc WHERE pc.partida_id = v_partida_id
        ) sub
        JOIN inventario.lote l        ON l.id = sub.lote_id
        JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
        WHERE sub.rn > v_partida_offset AND sub.rn <= v_partida_offset + v_n_rolls;

        -- Create output lotes (one per input roll, prorated weight)
        v_peso_por_roll := ROUND(v_total_kg / v_n_rolls, 4);
        v_peso_acum     := 0;
        v_roll_idx      := 0;
        v_created       := 0;

        FOR v_lote_rec IN (
            SELECT sub.lote_id, l.item_id, l.propietario_id,
                   lrd.entrega_id, lrd.orden_servicio_id, lrd.factura_hilo
            FROM (
                SELECT pc.lote_id, ROW_NUMBER() OVER (ORDER BY pc.lote_id) AS rn
                FROM mes.partida_componente pc WHERE pc.partida_id = v_partida_id
            ) sub
            JOIN inventario.lote l ON l.id = sub.lote_id
            LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
            WHERE sub.rn > v_partida_offset AND sub.rn <= v_partida_offset + v_n_rolls
            ORDER BY sub.rn
        )
        LOOP
            v_roll_idx  := v_roll_idx + 1;
            v_peso_roll := CASE
                WHEN v_roll_idx = v_n_rolls THEN ROUND(v_total_kg - v_peso_acum, 4)
                ELSE v_peso_por_roll
            END;
            v_peso_acum := v_peso_acum + v_peso_roll;

            INSERT INTO inventario.lote(item_id, documento_tipo, documento_id, cantidad, propietario_id)
            VALUES (v_lote_rec.item_id, 'partida_paso_ejecucion', v_ejecucion_id, v_peso_roll, v_lote_rec.propietario_id)
            RETURNING id INTO v_new_lote_id;

            INSERT INTO inventario.item_movimientos(
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                destino_ubicacion_id, cantidad, documento_tipo, documento_id
            )
            VALUES (v_doc_mov_id, v_lote_rec.item_id, v_new_lote_id, v_prod_ing_tipo_id,
                    v_ubicacion_id, v_peso_roll, 'partida_paso_ejecucion', v_ejecucion_id);

            INSERT INTO inventario.lote_rollo_detalle(
                lote_id, entrega_id, orden_servicio_id, factura_hilo, origen_lote_id,
                ancho, malla, rendimiento, color_x_cliente_id, tenido_id, flg_tenido, flg_antipilling
            )
            VALUES (
                v_new_lote_id,
                v_lote_rec.entrega_id, v_lote_rec.orden_servicio_id, v_lote_rec.factura_hilo,
                v_lote_rec.lote_id,
                v_ancho, v_malla, v_rendimiento, v_color_x_cli, v_tenido_id,
                true, v_flg_antipil
            );

            v_created := v_created + 1;
        END LOOP;

        RAISE NOTICE 'STEP 2 — ejecucion=%  partida=%  lotes=%  kg=%.4f',
            v_ejecucion_id, v_partida_id, v_created, v_peso_acum;

        v_partida_offset := v_partida_offset + v_n_rolls;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════
    -- STEP 3: Dispatch entregas — one per tercero (output lotes from Step 2)
    -- Textil Valy (260): 4388 + 4918
    -- Faride       (228): 4577
    -- ═══════════════════════════════════════════════════════════════════════

    -- 3a. Valy dispatch (4388 + 4918)
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;
    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, fecha_emision)
    VALUES (v_despacho_tipo_id, 260, v_fecha_despacho_valy)
    RETURNING id INTO v_entrega_despacho_valy;

    v_linea_valy := 0;

    FOR v_lote_rec IN (
        SELECT l.id AS lote_id, l.item_id, l.cantidad
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
        JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
        WHERE pp.partida_id IN (4388, 4918) AND pe.estado = 'COMPLETADO' AND l.fyh_elm IS NULL
        ORDER BY pp.partida_id, l.id
    )
    LOOP
        v_linea_valy := v_linea_valy + 1;
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos)
        VALUES (v_entrega_despacho_valy, v_linea_valy, v_lote_rec.item_id, v_lote_rec.cantidad, v_lote_rec.lote_id, v_ubicacion_id, 1);
        INSERT INTO inventario.item_movimientos(doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id)
        VALUES (v_doc_mov_id, v_lote_rec.item_id, v_lote_rec.lote_id, v_serv_egr_tipo_id, v_ubicacion_id, NULL, v_lote_rec.cantidad, v_fecha_despacho_valy, 'entrega', v_entrega_despacho_valy);
    END LOOP;

    RAISE NOTICE 'STEP 3 — DESPACHO Valy entrega_id=%  lineas=%', v_entrega_despacho_valy, v_linea_valy;

    -- 3b. Faride dispatch (4577)
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;
    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, fecha_emision)
    VALUES (v_despacho_tipo_id, 228, v_fecha_despacho_faride)
    RETURNING id INTO v_entrega_despacho_faride;

    v_linea_faride := 0;

    FOR v_lote_rec IN (
        SELECT l.id AS lote_id, l.item_id, l.cantidad
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
        JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
        WHERE pp.partida_id = 4577 AND pe.estado = 'COMPLETADO' AND l.fyh_elm IS NULL
        ORDER BY l.id
    )
    LOOP
        v_linea_faride := v_linea_faride + 1;
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos)
        VALUES (v_entrega_despacho_faride, v_linea_faride, v_lote_rec.item_id, v_lote_rec.cantidad, v_lote_rec.lote_id, v_ubicacion_id, 1);
        INSERT INTO inventario.item_movimientos(doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id)
        VALUES (v_doc_mov_id, v_lote_rec.item_id, v_lote_rec.lote_id, v_serv_egr_tipo_id, v_ubicacion_id, NULL, v_lote_rec.cantidad, v_fecha_despacho_faride, 'entrega', v_entrega_despacho_faride);
    END LOOP;

    RAISE NOTICE 'STEP 3 — DESPACHO Faride entrega_id=%  lineas=%', v_entrega_despacho_faride, v_linea_faride;

    -- ═══════════════════════════════════════════════════════════════════════
    -- STEP 4: Return entregas — one per tercero
    -- Textil Valy (260): 4388 output + 4918 output + 5090 lotes 122731-122748
    -- Faride       (228): 4577 output
    -- flg_emitida=false → no stock check, stock restored to ubicacion 9.
    -- ═══════════════════════════════════════════════════════════════════════

    -- 4a. Valy return
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;
    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, fecha_emision, fecha_recepcion)
    VALUES (v_devolucion_tipo_id, 260, v_fecha_retorno, v_fecha_retorno)
    RETURNING id INTO v_entrega_dev_valy;

    v_linea_valy := 0;

    FOR v_lote_rec IN (
        -- 4388 + 4918 output lotes
        SELECT l.id AS lote_id, l.item_id, l.cantidad
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
        JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
        WHERE pp.partida_id IN (4388, 4918) AND pe.estado = 'COMPLETADO' AND l.fyh_elm IS NULL
        UNION ALL
        -- 5090 dispatched output lotes
        SELECT l.id, l.item_id, l.cantidad
        FROM inventario.lote l
        WHERE l.id IN (122731,122732,122733,122734,122735,122736,122737,122738,
                       122739,122740,122741,122742,122743,122744,122745,122746,122747,122748)
        ORDER BY lote_id
    )
    LOOP
        v_linea_valy := v_linea_valy + 1;
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id)
        VALUES (v_entrega_dev_valy, v_linea_valy, v_lote_rec.item_id, v_lote_rec.cantidad, v_lote_rec.lote_id, v_ubicacion_id);
        INSERT INTO inventario.item_movimientos(doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id, observacion)
        VALUES (v_doc_mov_id, v_lote_rec.item_id, v_lote_rec.lote_id, v_serv_dev_tipo_id, NULL, v_ubicacion_id, v_lote_rec.cantidad, v_fecha_retorno, 'entrega', v_entrega_dev_valy, 'Devolucion para reproceso — Textil Valy');
    END LOOP;

    RAISE NOTICE 'STEP 4 — DEVOLUCION Valy entrega_id=%  lineas=%', v_entrega_dev_valy, v_linea_valy;

    -- 4b. Faride return
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;
    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, fecha_emision, fecha_recepcion)
    VALUES (v_devolucion_tipo_id, 228, v_fecha_retorno, v_fecha_retorno)
    RETURNING id INTO v_entrega_dev_faride;

    v_linea_faride := 0;

    FOR v_lote_rec IN (
        SELECT l.id AS lote_id, l.item_id, l.cantidad
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
        JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
        WHERE pp.partida_id = 4577 AND pe.estado = 'COMPLETADO' AND l.fyh_elm IS NULL
        ORDER BY l.id
    )
    LOOP
        v_linea_faride := v_linea_faride + 1;
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id)
        VALUES (v_entrega_dev_faride, v_linea_faride, v_lote_rec.item_id, v_lote_rec.cantidad, v_lote_rec.lote_id, v_ubicacion_id);
        INSERT INTO inventario.item_movimientos(doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id, observacion)
        VALUES (v_doc_mov_id, v_lote_rec.item_id, v_lote_rec.lote_id, v_serv_dev_tipo_id, NULL, v_ubicacion_id, v_lote_rec.cantidad, v_fecha_retorno, 'entrega', v_entrega_dev_faride, 'Devolucion para reproceso — Faride');
    END LOOP;

    RAISE NOTICE 'STEP 4 — DEVOLUCION Faride entrega_id=%  lineas=%', v_entrega_dev_faride, v_linea_faride;

    RAISE NOTICE '──────────────────────────────────────────────────────';
    RAISE NOTICE 'Done. Switch ROLLBACK → COMMIT below to persist.';
END;
$$;

ROLLBACK;
-- COMMIT;


-- ── SECTION 2: REOPEN PARTIDAS TO TECO ───────────────────────────────────────
-- Enables crear_reproceso (requires EN_PRODUCCION or TECO).
-- Run after the DO block is COMMITTED.

-- Preview
SELECT id, estado_produccion FROM mes.partida WHERE id IN (4388, 4577, 4918, 5090);

-- Execute (uncomment when ready)
/*
UPDATE mes.partida
SET estado_produccion = 'TECO',
    usr_mod = 1,
    fyh_mod = NOW()
WHERE id IN (4388, 4577, 4918, 5090)
  AND estado_produccion = 'CERRADA';
*/


-- ── POST-VERIFY ───────────────────────────────────────────────────────────────
-- All output lotes should show cantidad_actual > 0 and last movement = SERV_DEV_ING.
SELECT
    pp.partida_id,
    l.id          AS lote_id,
    ls.cantidad_actual,
    imt_last.codigo AS last_mov
FROM mes.partida_paso pp
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id AND ls.ubicacion_id = 9
LEFT JOIN LATERAL (
    SELECT imt.codigo FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.lote_id = l.id ORDER BY im.fyh_cre DESC LIMIT 1
) imt_last ON true
WHERE pp.partida_id IN (4388, 4577, 4918) AND pe.estado = 'COMPLETADO'
UNION ALL
SELECT 5090, l.id, ls.cantidad_actual, imt_last.codigo
FROM inventario.lote l
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id AND ls.ubicacion_id = 9
LEFT JOIN LATERAL (
    SELECT imt.codigo FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.lote_id = l.id ORDER BY im.fyh_cre DESC LIMIT 1
) imt_last ON true
WHERE l.id IN (122731,122732,122733,122734,122735,122736,122737,122738,
               122739,122740,122741,122742,122743,122744,122745,122746,122747,122748)
ORDER BY partida_id, lote_id;
-- EXPECT: cantidad_actual > 0, last_mov = 'SERV_DEV_ING' for all rows.

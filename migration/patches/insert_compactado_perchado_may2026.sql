-- ═══════════════════════════════════════════════════════════════════════════════
-- INSERT: compactado + perchado runs — May–Jun 2026 live operational data
--
-- These are NOT legacy backfills. Data recorded on physical sheets and never
-- entered into the system.
--
-- COMPACTADO (mersan/serteks sheet):
--   25/05  5163  Mersan    12 rollos
--   25/05  5209  Serteks 1 10 rollos
--   25/05  5179  Serteks 2 16 rollos
--
-- PERCHADO (percha sheet, 28/05–05/06):
--   24 distinct partidas, 28 ejecuciones total.
--   Midnight-crossing runs: fecha_fin advanced +1 day where hora_fin < hora_inicio.
--   Null hora_fin: 5231 (machine failure mid-shift — fyh_fin stored as NULL).
--   Typo corrected: 5940 16::30 → 16:30.
--   Partida 4700: maquina column blank on sheet → resolved to Percha machine.
--   Multi-run partidas: 5229 ×2, 5235 ×3, 5242 ×2.
--
-- Behavior:
--   - Skips partidas that have rework children (partida_origen_id = partida.id)
--     → NOTICE issued, manual audit required
--   - Reuses existing paso when (partida_id, operacion_id) already exists
--   - Re-run safe: ejecucion skipped when fyh_inicio already exists for that paso
--   - COMPACTADO: ejecucion inserted EN_PROCESO, registrar_produccion called when
--     last step and input lotes not yet consumed, then finalized to COMPLETADO
--   - PERCHADO: ejecucion inserted directly as COMPLETADO (no production recording)
--   - actualizar_estado_partida called for all processed partidas → TECO when done
--
-- JWT note: jwt_has_permission returns NULL (not FALSE) without a session JWT,
--   so the guard in registrar_produccion silently passes when run as DB admin.
-- UTC offset: Peru UTC-5 → stored as local + 5 h, consistent with codebase.
--
-- REVERSAL:
--   DELETE FROM inventario.item_movimientos
--   WHERE documento_tipo = 'partida_paso_ejecucion'
--     AND documento_id IN (
--         SELECT pe.id FROM mes.partida_paso_ejecucion pe
--         JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
--         WHERE pp.partida_id IN (
--             5163,5209,5179,
--             5094,4700,5233,5231,5234,5232,5229,5243,6392,5230,
--             5242,5238,5235,5239,5240,5241,5236,5941,5943,5940,5942,
--             5196,5175,5968
--         )
--     );
--   DELETE FROM inventario.lote
--   WHERE documento_tipo = 'partida_paso_ejecucion'
--     AND documento_id IN (
--         SELECT pe.id FROM mes.partida_paso_ejecucion pe
--         JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
--         WHERE pp.partida_id IN (
--             5163,5209,5179,
--             5094,4700,5233,5231,5234,5232,5229,5243,6392,5230,
--             5242,5238,5235,5239,5240,5241,5236,5941,5943,5940,5942,
--             5196,5175,5968
--         )
--     );
--   DELETE FROM mes.partida_paso_ejecucion
--   WHERE partida_paso_id IN (
--       SELECT pp.id FROM mes.partida_paso pp
--       JOIN mes.operacion o ON o.id = pp.operacion_id
--       WHERE o.codigo IN ('COMPACTADO','PERCHADO')
--         AND pp.partida_id IN (
--             5163,5209,5179,
--             5094,4700,5233,5231,5234,5232,5229,5243,6392,5230,
--             5242,5238,5235,5239,5240,5241,5236,5941,5943,5940,5942,
--             5196,5175,5968
--         )
--   );
--   DELETE FROM mes.partida_paso
--   WHERE operacion_id IN (SELECT id FROM mes.operacion WHERE codigo IN ('COMPACTADO','PERCHADO'))
--     AND partida_id IN (
--         5163,5209,5179,
--         5094,4700,5233,5231,5234,5232,5229,5243,6392,5230,
--         5242,5238,5235,5239,5240,5241,5236,5941,5943,5940,5942,
--         5196,5175,5968
--     );
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_compact_op_id  SMALLINT;
    v_perch_op_id    SMALLINT;
    v_mersan_id      INT;
    v_serteks1_id    INT;
    v_serteks2_id    INT;
    v_percha_id      INT;

    v_paso_id        BIGINT;
    v_ejecucion_id   BIGINT;
    v_secuencia      SMALLINT;
    v_fyh_inicio     TIMESTAMPTZ;
    v_fyh_fin        TIMESTAMPTZ;
    v_is_last_step   BOOLEAN;
    v_output_json    JSONB;
    v_count          INT;

    rec              RECORD;
BEGIN
    SELECT id INTO STRICT v_compact_op_id FROM mes.operacion WHERE codigo = 'COMPACTADO';
    SELECT id INTO STRICT v_perch_op_id   FROM mes.operacion WHERE codigo = 'PERCHADO';
    SELECT id INTO STRICT v_mersan_id     FROM mes.maquina   WHERE nombre = 'Mersan';
    SELECT id INTO STRICT v_serteks1_id   FROM mes.maquina   WHERE nombre = 'Serteks 1';
    SELECT id INTO STRICT v_serteks2_id   FROM mes.maquina   WHERE nombre = 'Serteks 2';
    SELECT id INTO STRICT v_percha_id     FROM mes.maquina   WHERE nombre = 'Percha';

    -- ═══════════════════════════════════════════════════════════════════════════
    -- COMPACTADO  (mersan / serteks sheet)
    -- Ejecucion inserted EN_PROCESO so registrar_produccion can run,
    -- then finalized to COMPLETADO manually.
    -- ═══════════════════════════════════════════════════════════════════════════
    FOR rec IN
        SELECT partida::bigint AS partida_id, v_mersan_id::int AS maquina_id,
               TO_DATE(fecha, 'DD/MM/YYYY') AS fecha, hora_inicio::time, hora_final::time AS hora_fin, rollos::numeric
        FROM public.mersan WHERE partida::text ~ '^\d+$' AND hora_inicio IS NOT NULL AND hora_final IS NOT NULL
        UNION ALL
        SELECT partida::bigint, v_serteks1_id::int,
               TO_DATE(fecha, 'DD/MM/YYYY') AS fecha, hora_inicio::time, hora_final::time AS hora_fin, rollos::numeric
        FROM public.sertks1 WHERE partida::text ~ '^\d+$' AND hora_inicio IS NOT NULL AND hora_final IS NOT NULL
        UNION ALL
        SELECT partida::bigint, v_serteks2_id::int,
               TO_DATE(fecha, 'DD/MM/YYYY') AS fecha, hora_inicio::time, hora_final::time AS hora_fin, rollos::numeric
        FROM public.sertks2 WHERE partida::text ~ '^\d+$' AND hora_inicio IS NOT NULL AND hora_final IS NOT NULL
    LOOP
        IF NOT EXISTS (SELECT 1 FROM mes.partida WHERE id = rec.partida_id) THEN
            RAISE NOTICE 'COMPACTADO: partida % no existe en mes.partida — saltado', rec.partida_id;
            CONTINUE;
        END IF;

        IF EXISTS (SELECT 1 FROM mes.partida WHERE partida_origen_id = rec.partida_id) THEN
            RAISE NOTICE 'COMPACTADO: partida % tiene reprocesos — saltado', rec.partida_id;
            CONTINUE;
        END IF;

        v_fyh_inicio := ((rec.fecha + rec.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ;
        v_fyh_fin    := ((rec.fecha + rec.hora_fin)::TIMESTAMP   + INTERVAL '5 hours')::TIMESTAMPTZ;

        SELECT id INTO v_paso_id FROM mes.partida_paso
        WHERE partida_id = rec.partida_id AND operacion_id = v_compact_op_id;

        IF NOT FOUND THEN
            SELECT COALESCE(MAX(secuencia), 0) + 1 INTO v_secuencia
            FROM mes.partida_paso WHERE partida_id = rec.partida_id;

            INSERT INTO mes.partida_paso (
                partida_id, secuencia, operacion_id, maquina_planificada_id,
                estado, usr_cre, fyh_cre
            ) VALUES (
                rec.partida_id, v_secuencia, v_compact_op_id, rec.maquina_id,
                'EN_PROCESO'::partida_paso_estado_enum, NULL, v_fyh_inicio
            ) RETURNING id INTO v_paso_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion
            WHERE partida_paso_id = v_paso_id AND fyh_inicio = v_fyh_inicio
        ) THEN
            RAISE NOTICE 'COMPACTADO: ejecucion ya existe para paso %, partida % — saltado', v_paso_id, rec.partida_id;
            CONTINUE;
        END IF;

        INSERT INTO mes.partida_paso_ejecucion (
            partida_paso_id, estado, maquina_id, fyh_inicio, cantidad, usr_cre, fyh_cre
        ) VALUES (
            v_paso_id, 'EN_PROCESO', rec.maquina_id, v_fyh_inicio, rec.rollos, NULL, v_fyh_inicio
        ) RETURNING id INTO v_ejecucion_id;

        -- Call registrar_produccion only when this is the last paso and lotes not yet consumed
        SELECT NOT EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            WHERE pp.partida_id = rec.partida_id
              AND pp.id         != v_paso_id
              AND pp.estado     NOT IN ('COMPLETADO', 'OMITIDO')
        ) INTO v_is_last_step;

        IF v_is_last_step THEN
            SELECT jsonb_agg(jsonb_build_object('input_lote_id', pc.lote_id, 'peso_salida', l.cantidad))
            INTO v_output_json
            FROM mes.partida_componente pc
            JOIN inventario.lote l ON l.id = pc.lote_id
            WHERE pc.partida_id = rec.partida_id
              AND pc.lote_id IS NOT NULL
              -- registrar_produccion requires lote_rollo_detalle; skip lotes without it
              AND EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle WHERE lote_id = pc.lote_id)
              AND NOT EXISTS (
                  SELECT 1 FROM inventario.item_movimientos im
                  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                  WHERE im.lote_id = pc.lote_id AND imt.codigo = 'PROD_CONSUMO'
              );

            IF v_output_json IS NOT NULL THEN
                IF EXISTS (SELECT 1 FROM mes.partida WHERE id = rec.partida_id AND estado_produccion IN ('TECO', 'CERRADA')) THEN
                    RAISE NOTICE 'COMPACTADO: partida % ya es TECO/CERRADA — omitiendo registrar_produccion, solo ejecucion', rec.partida_id;
                ELSE
                    PERFORM mes.registrar_produccion(v_ejecucion_id, jsonb_build_object('output', v_output_json));
                    RAISE NOTICE 'COMPACTADO: registrar_produccion OK para partida %', rec.partida_id;
                END IF;
            ELSE
                RAISE NOTICE 'COMPACTADO: produccion ya registrada o sin lotes para partida % — solo ejecucion', rec.partida_id;
            END IF;
        END IF;

        UPDATE mes.partida_paso_ejecucion
        SET estado = 'COMPLETADO', fyh_fin = v_fyh_fin, fyh_mod = NOW()
        WHERE id = v_ejecucion_id;

        UPDATE mes.partida_paso SET estado = 'COMPLETADO', fyh_mod = NOW() WHERE id = v_paso_id;

        RAISE NOTICE 'COMPACTADO: partida % — COMPLETADO (last_step=%)', rec.partida_id, v_is_last_step;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════════
    -- PERCHADO  (percha sheet — 28/05 to 05/06)
    --
    -- Step 1: ensure one paso per distinct partida (skip reworks)
    -- Step 2: bulk-insert all ejecuciones (re-run safe via fyh_inicio guard)
    -- Step 3: mark all pasos COMPLETADO
    -- Step 4: state machine
    --
    -- fecha_fin = fecha + 1 day for runs that cross midnight
    -- (hora_fin < hora_inicio on sheet → written explicitly below)
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Step 1 — create missing pasos
    FOR rec IN
        SELECT DISTINCT v.partida_id
        FROM (VALUES
            (5094::bigint),(4700),(5233),(5231),(5234),(5232),(5229),
            (5243),(6392),(5230),(5242),(5238),(5235),(5239),(5240),
            (5241),(5236),(5941),(5943),(5940),(5942),(5196),(5175),(5968)
        ) v(partida_id)
        WHERE EXISTS     (SELECT 1 FROM mes.partida WHERE id = v.partida_id)
          AND NOT EXISTS (SELECT 1 FROM mes.partida WHERE partida_origen_id = v.partida_id)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM mes.partida_paso
            WHERE partida_id = rec.partida_id AND operacion_id = v_perch_op_id
        ) THEN
            SELECT COALESCE(MAX(secuencia), 0) + 1 INTO v_secuencia
            FROM mes.partida_paso WHERE partida_id = rec.partida_id;

            INSERT INTO mes.partida_paso (
                partida_id, secuencia, operacion_id, maquina_planificada_id,
                estado, usr_cre, fyh_cre
            ) VALUES (
                rec.partida_id, v_secuencia, v_perch_op_id, v_percha_id,
                'COMPLETADO'::partida_paso_estado_enum, NULL, NOW()
            );
            RAISE NOTICE 'PERCHADO: paso creado para partida %', rec.partida_id;
        ELSE
            RAISE NOTICE 'PERCHADO: reutilizando paso existente para partida %', rec.partida_id;
        END IF;
    END LOOP;

    -- Step 2 — bulk-insert ejecuciones
    -- Columns: partida_id, fecha_inicio, hora_inicio, fecha_fin, hora_fin, rollos, pases
    -- fecha_fin is advanced +1 day for midnight-crossing runs.
    -- NULL fecha_fin / hora_fin → fyh_fin stored as NULL (5231 machine failure).
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id,
        fyh_inicio, fyh_fin,
        cantidad, pases,
        usr_cre, fyh_cre
    )
    SELECT
        pp.id,
        'COMPLETADO',
        v_percha_id,
        (r.fecha_inicio + r.hora_inicio + INTERVAL '5 hours')::TIMESTAMPTZ,
        CASE WHEN r.hora_fin IS NOT NULL
             THEN (r.fecha_fin + r.hora_fin + INTERVAL '5 hours')::TIMESTAMPTZ
             ELSE NULL
        END,
        r.rollos,
        r.pases,
        NULL,
        (r.fecha_inicio + r.hora_inicio + INTERVAL '5 hours')::TIMESTAMPTZ
    FROM (VALUES
        -- ── 28/05 ──────────────────────────────────────────────────────────
        (5094::bigint, DATE '2026-05-28', TIME '08:30', DATE '2026-05-28', TIME '11:30', 19::numeric, 3::smallint),
        (4700::bigint, DATE '2026-05-28', TIME '11:30', DATE '2026-05-28', TIME '14:45', 20::numeric, 2::smallint),
        -- ── 29/05 ──────────────────────────────────────────────────────────
        (5233::bigint, DATE '2026-05-29', TIME '08:00', DATE '2026-05-29', TIME '12:00', 20::numeric, 3::smallint),
        (5231::bigint, DATE '2026-05-29', TIME '01:00', NULL::DATE,        NULL::TIME,   20::numeric, 3::smallint), -- machine failure, no end time
        (5234::bigint, DATE '2026-05-29', TIME '19:00', DATE '2026-05-30', TIME '11:00', 20::numeric, 3::smallint), -- midnight cross
        (5232::bigint, DATE '2026-05-29', TIME '12:00', DATE '2026-05-30', TIME '02:00', 20::numeric, 3::smallint), -- midnight cross
        (5229::bigint, DATE '2026-05-29', TIME '02:00', DATE '2026-05-29', TIME '03:30', 20::numeric, 3::smallint),
        -- ── 01/06 ──────────────────────────────────────────────────────────
        (5229::bigint, DATE '2026-06-01', TIME '07:30', DATE '2026-06-01', TIME '08:30', 10::numeric, 1::smallint),
        (5243::bigint, DATE '2026-06-01', TIME '08:30', DATE '2026-06-02', TIME '01:30', 20::numeric, 3::smallint), -- midnight cross
        (6392::bigint, DATE '2026-06-01', TIME '11:30', DATE '2026-06-01', TIME '15:30', 20::numeric, 3::smallint),
        (5230::bigint, DATE '2026-06-01', TIME '15:30', DATE '2026-06-01', TIME '18:30', 20::numeric, 3::smallint),
        (5242::bigint, DATE '2026-06-01', TIME '09:00', DATE '2026-06-02', TIME '00:00', 20::numeric, 3::smallint), -- midnight cross (ends at midnight)
        (5238::bigint, DATE '2026-06-01', TIME '00:00', DATE '2026-06-01', TIME '03:00', 20::numeric, 3::smallint),
        (5235::bigint, DATE '2026-06-01', TIME '03:00', DATE '2026-06-01', TIME '06:00', 20::numeric, 3::smallint),
        -- ── 02/06 ──────────────────────────────────────────────────────────
        (5235::bigint, DATE '2026-06-02', TIME '01:00', DATE '2026-06-02', TIME '03:30', 20::numeric, 2::smallint),
        -- ── 03/06 ──────────────────────────────────────────────────────────
        (5235::bigint, DATE '2026-06-03', TIME '07:10', DATE '2026-06-03', TIME '08:10', 10::numeric, 1::smallint),
        (5239::bigint, DATE '2026-06-03', TIME '08:10', DATE '2026-06-03', TIME '11:00', 20::numeric, 3::smallint),
        (5240::bigint, DATE '2026-06-03', TIME '11:10', DATE '2026-06-03', TIME '14:00', 20::numeric, 3::smallint),
        (5242::bigint, DATE '2026-06-03', TIME '14:30', DATE '2026-06-03', TIME '17:00', 20::numeric, 3::smallint),
        (5241::bigint, DATE '2026-06-03', TIME '17:00', DATE '2026-06-03', TIME '19:00', 20::numeric, 3::smallint),
        -- ── 04/06 ──────────────────────────────────────────────────────────
        (5236::bigint, DATE '2026-06-04', TIME '07:10', DATE '2026-06-04', TIME '10:10', 20::numeric, 3::smallint),
        (5941::bigint, DATE '2026-06-04', TIME '10:10', DATE '2026-06-04', TIME '12:00', 20::numeric, 2::smallint),
        (5943::bigint, DATE '2026-06-04', TIME '12:30', DATE '2026-06-04', TIME '14:30', 20::numeric, 2::smallint),
        (5940::bigint, DATE '2026-06-04', TIME '14:30', DATE '2026-06-04', TIME '16:30', 20::numeric, 2::smallint), -- typo 16::30 corrected
        (5942::bigint, DATE '2026-06-04', TIME '16:30', DATE '2026-06-04', TIME '18:40', 20::numeric, 2::smallint),
        -- ── 05/06 ──────────────────────────────────────────────────────────
        (5196::bigint, DATE '2026-06-05', TIME '09:30', DATE '2026-06-05', TIME '11:00', 16::numeric, 2::smallint),
        (5175::bigint, DATE '2026-06-05', TIME '11:00', DATE '2026-06-05', TIME '15:00', 19::numeric, 3::smallint),
        (5968::bigint, DATE '2026-06-05', TIME '15:00', DATE '2026-06-05', TIME '17:00', 16::numeric, 2::smallint)
    ) r(partida_id, fecha_inicio, hora_inicio, fecha_fin, hora_fin, rollos, pases)
    JOIN mes.partida_paso pp
        ON pp.partida_id = r.partida_id AND pp.operacion_id = v_perch_op_id
    WHERE
        -- skip reworks
        NOT EXISTS (SELECT 1 FROM mes.partida WHERE partida_origen_id = r.partida_id)
        -- re-run guard: skip if ejecucion with same fyh_inicio already exists for this paso
        AND NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id
              AND pe.fyh_inicio = (r.fecha_inicio + r.hora_inicio + INTERVAL '5 hours')::TIMESTAMPTZ
        );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'PERCHADO: % ejecuciones insertadas', v_count;

    -- Step 3 — ensure all pasos are COMPLETADO (covers pre-existing pasos in other states)
    UPDATE mes.partida_paso pp
    SET estado = 'COMPLETADO', fyh_mod = NOW()
    FROM (VALUES
        (5094::bigint),(4700),(5233),(5231),(5234),(5232),(5229),
        (5243),(6392),(5230),(5242),(5238),(5235),(5239),(5240),
        (5241),(5236),(5941),(5943),(5940),(5942),(5196),(5175),(5968)
    ) v(partida_id)
    WHERE pp.partida_id = v.partida_id
      AND pp.operacion_id = v_perch_op_id
      AND pp.estado != 'COMPLETADO';

    -- ═══════════════════════════════════════════════════════════════════════════
    -- State machine — advance all non-rework affected partidas
    -- ═══════════════════════════════════════════════════════════════════════════
    FOR rec IN
        SELECT v.partida_id
        FROM (VALUES
            (5163::bigint),(5209),(5179),
            (5094),(4700),(5233),(5231),(5234),(5232),(5229),
            (5243),(6392),(5230),(5242),(5238),(5235),(5239),(5240),
            (5241),(5236),(5941),(5943),(5940),(5942),(5196),(5175),(5968)
        ) v(partida_id)
        WHERE EXISTS     (SELECT 1 FROM mes.partida WHERE id = v.partida_id)
          AND NOT EXISTS (SELECT 1 FROM mes.partida WHERE partida_origen_id = v.partida_id)
    LOOP
        PERFORM mes.actualizar_estado_partida(rec.partida_id);
    END LOOP;

END;
$$;

-- ── Validation ────────────────────────────────────────────────────────────────
SELECT
    o.codigo                                  AS operacion,
    pp.partida_id,
    pp.secuencia,
    pp.estado                                 AS paso_estado,
    m.nombre                                  AS maquina,
    pe.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local,
    pe.fyh_fin    AT TIME ZONE 'America/Lima' AS fin_local,
    pe.cantidad                               AS rollos,
    pe.pases,
    p.estado_produccion
FROM mes.partida_paso pp
JOIN mes.operacion o               ON o.id  = pp.operacion_id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN mes.partida p                 ON p.id  = pp.partida_id
LEFT JOIN mes.maquina m            ON m.id  = pe.maquina_id
WHERE pp.partida_id IN (
    5163,5209,5179,
    5094,4700,5233,5231,5234,5232,5229,5243,6392,5230,
    5242,5238,5235,5239,5240,5241,5236,5941,5943,5940,5942,
    5196,5175,5968
)
ORDER BY pp.partida_id, o.codigo, pe.fyh_inicio;


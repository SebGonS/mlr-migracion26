-- ═══════════════════════════════════════════════════════════════════════════════
-- INSERT: perchado runs — 23/06–26/06 2026
--
-- Extension of insert_compactado_perchado_may2026.sql (covers 28/05–19/06).
-- Data transcribed from physical percha sheet.
--
-- Rows:
--   23/06  6173 YUSEFT       20r 2p  10:00–12:00
--   23/06  6174 YUSEFT       20r 2p  13:00–14:50
--   23/06  4699 DAMARIZ      20r 1p  15:00–16:50
--   23/06  6109 RYL          20r 2p  16:50–18:00
--   24/06  6092 RYL          20r 2p  15:30–17:30
--   25/06  6181 DAMARIZ      20r 2p  13:00–16:00
--   25/06  6183 DAMARIZ      20r 2p  16:00–19:00
--   26/06  6182 DAMARIZ      20r 2p  07:30–12:00
--   26/06  6184 DAMARIZ      20r 2p  13:00–16:00
--   26/06  6204 RYL          20r 2p  16:30–19:00
--
-- No midnight-crossing runs in this batch.
-- Re-run safe: ejecucion skipped when fyh_inicio already exists for that paso.
--
-- REVERSAL:
--   DELETE FROM mes.partida_paso_ejecucion
--   WHERE partida_paso_id IN (
--       SELECT pp.id FROM mes.partida_paso pp
--       JOIN mes.operacion o ON o.id = pp.operacion_id
--       WHERE o.codigo = 'PERCHADO'
--         AND pp.partida_id IN (6173,6174,4699,6109,6092,6181,6183,6182,6184,6204)
--   );
--   DELETE FROM mes.partida_paso
--   WHERE operacion_id IN (SELECT id FROM mes.operacion WHERE codigo = 'PERCHADO')
--     AND partida_id IN (6173,6174,4699,6109,6092,6181,6183,6182,6184,6204);
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_perch_op_id  SMALLINT;
    v_percha_id    INT;
    v_paso_id      BIGINT;
    v_secuencia    SMALLINT;
    v_count        INT;
    rec            RECORD;
BEGIN
    SELECT id INTO STRICT v_perch_op_id FROM mes.operacion WHERE codigo = 'PERCHADO';
    SELECT id INTO STRICT v_percha_id   FROM mes.maquina   WHERE nombre = 'Percha';

    -- ── Step 1: ensure one paso per partida ───────────────────────────────────
    FOR rec IN
        SELECT DISTINCT v.partida_id
        FROM (VALUES
            (6173::bigint),(6174),(4699),(6109),
            (6092),
            (6181),(6183),
            (6182),(6184),(6204)
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

    -- ── Step 2: bulk-insert ejecuciones ───────────────────────────────────────
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id,
        fyh_inicio, fyh_fin,
        cantidad_rollos, pases, peso_kg,
        usr_cre, fyh_cre
    )
    SELECT
        pp.id,
        'COMPLETADO',
        v_percha_id,
        (r.fecha_inicio + r.hora_inicio + INTERVAL '5 hours')::TIMESTAMPTZ,
        (r.fecha_fin    + r.hora_fin    + INTERVAL '5 hours')::TIMESTAMPTZ,
        r.rollos,
        r.pases,
        (SELECT ROUND(SUM(l.cantidad) * r.rollos / NULLIF(COUNT(pc.lote_id)::numeric, 0), 4)
         FROM mes.partida_componente pc
         JOIN inventario.lote l ON l.id = pc.lote_id
         WHERE pc.partida_id = r.partida_id AND pc.lote_id IS NOT NULL),
        NULL,
        (r.fecha_inicio + r.hora_inicio + INTERVAL '5 hours')::TIMESTAMPTZ
    FROM (VALUES
        -- ── 23/06 ──────────────────────────────────────────────────────────
        (6173::bigint, DATE '2026-06-23', TIME '10:00', DATE '2026-06-23', TIME '12:00', 20::numeric, 2::smallint),
        (6174::bigint, DATE '2026-06-23', TIME '13:00', DATE '2026-06-23', TIME '14:50', 20::numeric, 2::smallint),
        (4699::bigint, DATE '2026-06-23', TIME '15:00', DATE '2026-06-23', TIME '16:50', 20::numeric, 1::smallint),
        (6109::bigint, DATE '2026-06-23', TIME '16:50', DATE '2026-06-23', TIME '18:00', 20::numeric, 2::smallint),
        -- ── 24/06 ──────────────────────────────────────────────────────────
        (6092::bigint, DATE '2026-06-24', TIME '15:30', DATE '2026-06-24', TIME '17:30', 20::numeric, 2::smallint),
        -- ── 25/06 ──────────────────────────────────────────────────────────
        (6181::bigint, DATE '2026-06-25', TIME '13:00', DATE '2026-06-25', TIME '16:00', 20::numeric, 2::smallint),
        (6183::bigint, DATE '2026-06-25', TIME '16:00', DATE '2026-06-25', TIME '19:00', 20::numeric, 2::smallint),
        -- ── 26/06 ──────────────────────────────────────────────────────────
        (6182::bigint, DATE '2026-06-26', TIME '07:30', DATE '2026-06-26', TIME '12:00', 20::numeric, 2::smallint),
        (6184::bigint, DATE '2026-06-26', TIME '13:00', DATE '2026-06-26', TIME '16:00', 20::numeric, 2::smallint), -- ⚠ verify: 6184 may be a typo
        (6204::bigint, DATE '2026-06-26', TIME '16:30', DATE '2026-06-26', TIME '19:00', 20::numeric, 2::smallint)
    ) r(partida_id, fecha_inicio, hora_inicio, fecha_fin, hora_fin, rollos, pases)
    JOIN mes.partida_paso pp
        ON pp.partida_id = r.partida_id AND pp.operacion_id = v_perch_op_id
    WHERE
        NOT EXISTS (SELECT 1 FROM mes.partida WHERE partida_origen_id = r.partida_id)
        AND NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id
              AND pe.fyh_inicio = (r.fecha_inicio + r.hora_inicio + INTERVAL '5 hours')::TIMESTAMPTZ
        );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'PERCHADO 23jun-26jun: % ejecuciones insertadas', v_count;

    -- ── Step 3: mark all pasos COMPLETADO ─────────────────────────────────────
    UPDATE mes.partida_paso pp
    SET estado = 'COMPLETADO', fyh_mod = NOW()
    FROM (VALUES
        (6173::bigint),(6174),(4699),(6109),
        (6092),
        (6181),(6183),
        (6182),(6184),(6204)
    ) v(partida_id)
    WHERE pp.partida_id = v.partida_id
      AND pp.operacion_id = v_perch_op_id
      AND pp.estado != 'COMPLETADO';

    -- ── Step 4: advance state machine ─────────────────────────────────────────
    FOR rec IN
        SELECT v.partida_id
        FROM (VALUES
            (6173::bigint),(6174),(4699),(6109),
            (6092),
            (6181),(6183),
            (6182),(6184),(6204)
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
    pp.partida_id,
    pp.secuencia,
    pp.estado                                 AS paso_estado,
    pe.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local,
    pe.fyh_fin    AT TIME ZONE 'America/Lima' AS fin_local,
    pe.cantidad_rollos                        AS rollos,
    pe.pases,
    p.estado_produccion
FROM mes.partida_paso pp
JOIN mes.operacion o               ON o.id = pp.operacion_id AND o.codigo = 'PERCHADO'
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN mes.partida p                 ON p.id = pp.partida_id
WHERE pp.partida_id IN (6173,6174,4699,6109,6092,6181,6183,6182,6184,6204)
ORDER BY pe.fyh_inicio;

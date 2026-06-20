-- ═══════════════════════════════════════════════════════════════════════════════
-- PATCH: compactado + perchado runs — May 2026 live data (not in legacy tables)
--
-- Source sheets  : mersan, serteks1, serteks2 → COMPACTADO
--                  percha                     → PERCHADO
--
-- New machines registered: mersan, serteks1, serteks2 (tipo COMPACT)
-- Existing machine used  : first PERCH-tipo machine for percha run
--
-- UTC offset     : local (Peru UTC-5) → +5 h, consistent with 06_migrar_* pattern
-- Idempotency    : ON CONFLICT (partida_paso_id) on ejecucion (1:1 with paso);
--                  paso guarded by ON CONFLICT (partida_id, secuencia) DO NOTHING
--
-- REVERSAL (run to undo):
-- DELETE FROM mes.partida_paso_ejecucion
-- WHERE partida_paso_id IN (
--     SELECT pp.id FROM mes.partida_paso pp
--     JOIN mes.operacion o ON o.id = pp.operacion_id
--     WHERE o.codigo IN ('COMPACTADO','PERCHADO')
--       AND pp.partida_id IN (5163, 5209, 5179, 5094)
-- );
-- DELETE FROM mes.partida_paso
-- WHERE operacion_id IN (SELECT id FROM mes.operacion WHERE codigo IN ('COMPACTADO','PERCHADO'))
--   AND partida_id IN (5163, 5209, 5179, 5094);
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_compact_op_id  SMALLINT;
    v_perch_op_id    SMALLINT;
    v_compact_tipo   SMALLINT;
    v_perch_tipo     SMALLINT;
    v_mersan_id      INT;
    v_serteks1_id    INT;
    v_serteks2_id    INT;
    v_percha_id      INT;
    v_count          INT;
BEGIN
    -- ── Operations ───────────────────────────────────────────────────────────
    SELECT id INTO STRICT v_compact_op_id FROM mes.operacion WHERE codigo = 'COMPACTADO';
    SELECT id INTO STRICT v_perch_op_id   FROM mes.operacion WHERE codigo = 'PERCHADO';

    -- ── Machine tipos ─────────────────────────────────────────────────────────
    SELECT id INTO STRICT v_compact_tipo FROM mes.maquina_tipo WHERE codigo = 'COMPACT';
    SELECT id INTO STRICT v_perch_tipo   FROM mes.maquina_tipo WHERE codigo = 'PERCH';

    -- ── Register new compactadoras ────────────────────────────────────────────
    INSERT INTO mes.maquina (nombre, maquina_tipo_id, capacidad_min_kg, capacidad_max_kg, fyh_cre)
    VALUES ('mersan',   v_compact_tipo, 30, 120, NOW())
    ON CONFLICT (nombre) DO NOTHING;

    INSERT INTO mes.maquina (nombre, maquina_tipo_id, capacidad_min_kg, capacidad_max_kg, fyh_cre)
    VALUES ('serteks1', v_compact_tipo, 30, 120, NOW())
    ON CONFLICT (nombre) DO NOTHING;

    INSERT INTO mes.maquina (nombre, maquina_tipo_id, capacidad_min_kg, capacidad_max_kg, fyh_cre)
    VALUES ('serteks2', v_compact_tipo, 30, 120, NOW())
    ON CONFLICT (nombre) DO NOTHING;

    SELECT id INTO STRICT v_mersan_id   FROM mes.maquina WHERE nombre = 'mersan';
    SELECT id INTO STRICT v_serteks1_id FROM mes.maquina WHERE nombre = 'serteks1';
    SELECT id INTO STRICT v_serteks2_id FROM mes.maquina WHERE nombre = 'serteks2';

    -- ── Existing percha machine ───────────────────────────────────────────────
    SELECT id INTO STRICT v_percha_id
    FROM mes.maquina
    WHERE maquina_tipo_id = v_perch_tipo
    ORDER BY id
    LIMIT 1;

    -- ═══════════════════════════════════════════════════════════════════════════
    -- COMPACTADO runs (mersan, serteks1, serteks2)
    -- ═══════════════════════════════════════════════════════════════════════════
    WITH
    raw_data (partida_id, maquina_id, fecha, hora_inicio, hora_fin, rollos) AS (
        VALUES
            (5163, v_mersan_id,   DATE '2026-05-25', TIME '07:30', TIME '09:30', 12),
            (5209, v_serteks1_id, DATE '2026-05-25', TIME '08:50', TIME '10:00', 10),
            (5179, v_serteks2_id, DATE '2026-05-25', TIME '07:30', TIME '09:30', 16)
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq
        FROM mes.partida_paso
        WHERE partida_id IN (SELECT partida_id FROM raw_data)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT
            r.partida_id,
            r.maquina_id,
            r.fecha,
            r.hora_inicio,
            r.hora_fin,
            r.rollos::NUMERIC AS cantidad,
            (COALESCE(sb.max_seq, 0) + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha))::SMALLINT AS secuencia
        FROM raw_data r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT
            rk.partida_id,
            rk.secuencia,
            v_compact_op_id,
            rk.maquina_id,
            'COMPLETADO'::partida_paso_estado_enum,
            NULL,
            ((rk.fecha + rk.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id,
        fyh_inicio, fyh_fin,
        cantidad,
        usr_cre, fyh_cre
    )
    SELECT
        pi.paso_id,
        'COMPLETADO',
        rk.maquina_id,
        pi.fyh_inicio_paso,
        ((rk.fecha + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ,
        rk.cantidad,
        NULL,
        pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha + rk.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'COMPACTADO (2026-05): % ejecuciones insertadas', v_count;

    -- ═══════════════════════════════════════════════════════════════════════════
    -- PERCHADO run (percha machine)
    -- ═══════════════════════════════════════════════════════════════════════════
    WITH
    raw_data (partida_id, maquina_id, fecha, hora_inicio, hora_fin, rollos, pases) AS (
        VALUES
            (5094, v_percha_id, DATE '2026-05-28', TIME '08:30', TIME '11:30', 19, 3)
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq
        FROM mes.partida_paso
        WHERE partida_id IN (SELECT partida_id FROM raw_data)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT
            r.partida_id,
            r.maquina_id,
            r.fecha,
            r.hora_inicio,
            r.hora_fin,
            r.rollos::NUMERIC AS cantidad,
            r.pases::SMALLINT AS pases,
            (COALESCE(sb.max_seq, 0) + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha))::SMALLINT AS secuencia
        FROM raw_data r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT
            rk.partida_id,
            rk.secuencia,
            v_perch_op_id,
            rk.maquina_id,
            'COMPLETADO'::partida_paso_estado_enum,
            NULL,
            ((rk.fecha + rk.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id,
        fyh_inicio, fyh_fin,
        cantidad, pases,
        usr_cre, fyh_cre
    )
    SELECT
        pi.paso_id,
        'COMPLETADO',
        rk.maquina_id,
        pi.fyh_inicio_paso,
        ((rk.fecha + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ,
        rk.cantidad,
        rk.pases,
        NULL,
        pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha + rk.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'PERCHADO (2026-05): % ejecuciones insertadas', v_count;

END;
$$;

-- ── Quick validation ──────────────────────────────────────────────────────────
SELECT
    o.codigo,
    pp.partida_id,
    pp.secuencia,
    pe.fyh_inicio,
    pe.fyh_fin,
    pe.cantidad,
    pe.pases,
    m.nombre AS maquina
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
LEFT JOIN mes.maquina m ON m.id = pe.maquina_id
WHERE o.codigo IN ('COMPACTADO', 'PERCHADO')
  AND pp.partida_id IN (5163, 5209, 5179, 5094)
ORDER BY o.codigo, pp.partida_id;
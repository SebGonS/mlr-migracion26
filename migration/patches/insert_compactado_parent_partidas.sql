-- ═══════════════════════════════════════════════════════════════════════════════
-- PATCH: compactado — parent partidas + rework 5944 reroute
--
-- Companion to insert_compactado_perchado_may2026.sql, which skips partidas
-- that have any rework child. This script handles those manually, routing each
-- run to either the parent or the correct rework based on precheck analysis.
--
-- REGISTER ON PARENT (reworks all closed / predating this run):
--   mersan : 3888 (2026-06-05), 5062 (2026-06-05)
--   sertks1: 3888 (2026-05-29), 4410 (2026-05-27)
--   sertks2: 4390 (2026-06-05), 4566 (2026-06-01), 4955 (2026-05-26),
--             5234 (2026-05-29), 5906 (2026-06-05), 5907 (2026-06-01)
--
-- EXCLUDED — already registered inside a rework (DO NOT re-insert):
--   4328 / rework 5983 Jun 5  (5983 COMPACTADO Jun 4–7, alineado=true)
--   5906 / rework 5966 Jun 2  (5966 COMPACTADO Jun 1–2, alineado=true)
--   5907 / rework 5980 Jun 3  (5980 COMPACTADO Jun 2–3, alineado=true)
--
-- REROUTE TO REWORK:
--   5179 → 5944: sertks2 sheet recorded under partida 5179, but run date
--     (2026-05-25) is post-tenido (5944 last exec 2026-05-21) and 5944 has no
--     COMPACTADO paso yet — compactado belongs to the rework.
--
-- registrar_produccion called on last-step partidas (same logic as main script).
--
-- REVERSAL:
--   DELETE FROM inventario.item_movimientos
--   WHERE documento_tipo = 'partida_paso_ejecucion'
--     AND documento_id IN (
--         SELECT pe.id FROM mes.partida_paso_ejecucion pe
--         JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
--         WHERE pp.partida_id IN (3888,4390,4410,4566,4955,5062,5234,5906,5907,5944)
--     );
--   DELETE FROM inventario.lote
--   WHERE documento_tipo = 'partida_paso_ejecucion'
--     AND documento_id IN (
--         SELECT pe.id FROM mes.partida_paso_ejecucion pe
--         JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
--         WHERE pp.partida_id IN (3888,4390,4410,4566,4955,5062,5234,5906,5907,5944)
--     );
--   DELETE FROM mes.partida_paso_ejecucion
--   WHERE partida_paso_id IN (
--       SELECT pp.id FROM mes.partida_paso pp
--       JOIN mes.operacion o ON o.id = pp.operacion_id
--       WHERE o.codigo = 'COMPACTADO'
--         AND pp.partida_id IN (3888,4390,4410,4566,4955,5062,5234,5906,5907,5944)
--   );
--   DELETE FROM mes.partida_paso
--   WHERE operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'COMPACTADO')
--     AND partida_id IN (3888,4390,4410,4566,4955,5062,5234,5906,5907,5944);
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_compact_op_id  SMALLINT;
    v_mersan_id      INT;
    v_serteks1_id    INT;
    v_serteks2_id    INT;

    v_paso_id        BIGINT;
    v_ejecucion_id   BIGINT;
    v_secuencia      SMALLINT;
    v_fyh_inicio     TIMESTAMPTZ;
    v_fyh_fin        TIMESTAMPTZ;
    v_is_last_step   BOOLEAN;
    v_output_json    JSONB;

    rec              RECORD;
BEGIN
    SELECT id INTO STRICT v_compact_op_id FROM mes.operacion WHERE codigo = 'COMPACTADO';
    SELECT id INTO STRICT v_mersan_id     FROM mes.maquina   WHERE nombre = 'Mersan';
    SELECT id INTO STRICT v_serteks1_id   FROM mes.maquina   WHERE nombre = 'Serteks 1';
    SELECT id INTO STRICT v_serteks2_id   FROM mes.maquina   WHERE nombre = 'Serteks 2';

    -- ═══════════════════════════════════════════════════════════════════════════
    -- PART 1: Register on parent partidas
    -- No rework-skip guard. Filtered to only the specific IDs confirmed above.
    -- Rows already registered inside reworks are excluded by date filter.
    -- ═══════════════════════════════════════════════════════════════════════════
    FOR rec IN
        SELECT partida::bigint AS partida_id, v_mersan_id::int AS maquina_id,
               TO_DATE(fecha, 'DD/MM/YYYY') AS fecha,
               REPLACE(hora_inicio, '.', ':')::time AS hora_inicio,
               REPLACE(hora_final,  '.', ':')::time AS hora_fin,
               rollos::numeric
        FROM public.mersan
        WHERE partida::text ~ '^\d+$'
          AND partida::bigint IN (3888, 5062)
          AND fecha IS NOT NULL AND TRIM(fecha) != ''
        UNION ALL
        SELECT partida::bigint, v_serteks1_id::int,
               TO_DATE(fecha, 'DD/MM/YYYY') AS fecha,
               REPLACE(hora_inicio, '.', ':')::time AS hora_inicio,
               REPLACE(hora_final,  '.', ':')::time AS hora_fin,
               rollos::numeric
        FROM public.sertks1
        WHERE partida::text ~ '^\d+$'
          AND partida::bigint IN (3888, 4410)
          AND fecha IS NOT NULL AND TRIM(fecha) != ''
        UNION ALL
        SELECT partida::bigint, v_serteks2_id::int,
               TO_DATE(fecha, 'DD/MM/YYYY') AS fecha,
               REPLACE(hora_inicio, '.', ':')::time AS hora_inicio,
               REPLACE(hora_final,  '.', ':')::time AS hora_fin,
               rollos::numeric
        FROM public.sertks2
        WHERE partida::text ~ '^\d+$'
          AND partida::bigint IN (4390, 4566, 4955, 5234, 5906, 5907)
          AND fecha IS NOT NULL AND TRIM(fecha) != ''
          -- exclude runs already registered inside reworks (confirmed alineado=true)
          AND NOT (partida::bigint = 5906 AND TO_DATE(fecha, 'DD/MM/YYYY') = DATE '2026-06-02')
          AND NOT (partida::bigint = 5907 AND TO_DATE(fecha, 'DD/MM/YYYY') = DATE '2026-06-03')
    LOOP
        IF rec.hora_inicio IS NULL THEN
            RAISE NOTICE 'COMPACTADO (parent): partida % sin hora_inicio — revisar manualmente (hora_fin=%)', rec.partida_id, rec.hora_fin;
            CONTINUE;
        END IF;

        v_fyh_inicio := ((rec.fecha + rec.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ;
        v_fyh_fin    := CASE WHEN rec.hora_fin IS NOT NULL
                             THEN ((rec.fecha + rec.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                             ELSE NULL
                        END;

        IF NOT EXISTS (SELECT 1 FROM mes.partida WHERE id = rec.partida_id) THEN
            RAISE NOTICE 'COMPACTADO (parent): partida % no existe en mes.partida — saltado', rec.partida_id;
            CONTINUE;
        END IF;

        -- find or create paso (one per partida+operacion)
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

        -- re-run guard
        SELECT id INTO v_ejecucion_id FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = v_paso_id AND fyh_inicio = v_fyh_inicio;

        IF FOUND THEN
            IF v_fyh_fin IS NOT NULL THEN
                UPDATE mes.partida_paso_ejecucion
                SET estado = 'COMPLETADO', fyh_fin = v_fyh_fin, fyh_mod = NOW()
                WHERE id = v_ejecucion_id AND fyh_fin IS NULL;
                IF FOUND THEN
                    UPDATE mes.partida_paso SET estado = 'COMPLETADO', fyh_mod = NOW() WHERE id = v_paso_id;
                    RAISE NOTICE 'COMPACTADO (parent): ejecucion % partida % — fyh_fin parcheado', v_ejecucion_id, rec.partida_id;
                ELSE
                    RAISE NOTICE 'COMPACTADO (parent): ejecucion ya completa para paso %, partida % — saltado', v_paso_id, rec.partida_id;
                END IF;
            ELSE
                RAISE NOTICE 'COMPACTADO (parent): ejecucion ya existe para paso %, partida % — saltado', v_paso_id, rec.partida_id;
            END IF;
            CONTINUE;
        END IF;

        INSERT INTO mes.partida_paso_ejecucion (
            partida_paso_id, estado, maquina_id, fyh_inicio, cantidad_rollos, usr_cre, fyh_cre
        ) VALUES (
            v_paso_id, 'EN_PROCESO', rec.maquina_id, v_fyh_inicio, rec.rollos, NULL, v_fyh_inicio
        ) RETURNING id INTO v_ejecucion_id;

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
                    RAISE NOTICE 'COMPACTADO (parent): partida % ya es TECO/CERRADA — omitiendo registrar_produccion, solo ejecucion', rec.partida_id;
                ELSE
                    PERFORM mes.registrar_produccion(v_ejecucion_id, jsonb_build_object('output', v_output_json));
                    RAISE NOTICE 'COMPACTADO (parent): registrar_produccion OK para partida %', rec.partida_id;
                END IF;
            ELSE
                RAISE NOTICE 'COMPACTADO (parent): produccion ya registrada o sin lotes para partida % — solo ejecucion', rec.partida_id;
            END IF;
        END IF;

        UPDATE mes.partida_paso_ejecucion
        SET estado   = 'COMPLETADO',
            fyh_fin  = v_fyh_fin,
            fyh_mod  = NOW(),
            peso_kg  = CASE WHEN v_is_last_step THEN peso_kg
                            ELSE (SELECT ROUND(
                                     SUM(l.cantidad) * rec.rollos
                                     / NULLIF(COUNT(pc.lote_id)::numeric, 0), 4)
                                  FROM mes.partida_componente pc
                                  JOIN inventario.lote l ON l.id = pc.lote_id
                                  WHERE pc.partida_id = rec.partida_id
                                    AND pc.lote_id IS NOT NULL)
                       END
        WHERE id = v_ejecucion_id;

        UPDATE mes.partida_paso SET estado = 'COMPLETADO', fyh_mod = NOW() WHERE id = v_paso_id;

        RAISE NOTICE 'COMPACTADO (parent): partida % — COMPLETADO (last_step=%)', rec.partida_id, v_is_last_step;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════════
    -- PART 2: 5179 → reroute to rework 5944
    -- sertks2 sheet recorded this run under partida 5179. The rework 5944 is
    -- EN_PRODUCCION with last execution 2026-05-21 (tenido); the 2026-05-25
    -- compactado is the natural next step of that rework, not the parent.
    -- ═══════════════════════════════════════════════════════════════════════════
    FOR rec IN
        SELECT
            5944::bigint            AS partida_id,
            v_serteks2_id::int      AS maquina_id,
            TO_DATE(fecha, 'DD/MM/YYYY') AS fecha,
            hora_inicio::time       AS hora_inicio,
            hora_final::time        AS hora_fin,
            rollos::numeric         AS rollos
        FROM public.sertks2
        WHERE partida::text = '5179'
          AND hora_inicio IS NOT NULL AND hora_final IS NOT NULL
    LOOP
        v_fyh_inicio := ((rec.fecha + rec.hora_inicio)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ;
        v_fyh_fin    := ((rec.fecha + rec.hora_fin)::TIMESTAMP   + INTERVAL '5 hours')::TIMESTAMPTZ;

        SELECT id INTO v_paso_id FROM mes.partida_paso
        WHERE partida_id = 5944 AND operacion_id = v_compact_op_id;

        IF NOT FOUND THEN
            SELECT COALESCE(MAX(secuencia), 0) + 1 INTO v_secuencia
            FROM mes.partida_paso WHERE partida_id = 5944;

            INSERT INTO mes.partida_paso (
                partida_id, secuencia, operacion_id, maquina_planificada_id,
                estado, usr_cre, fyh_cre
            ) VALUES (
                5944, v_secuencia, v_compact_op_id, rec.maquina_id,
                'EN_PROCESO'::partida_paso_estado_enum, NULL, v_fyh_inicio
            ) RETURNING id INTO v_paso_id;
        END IF;

        SELECT id INTO v_ejecucion_id FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = v_paso_id AND fyh_inicio = v_fyh_inicio;

        IF FOUND THEN
            IF v_fyh_fin IS NOT NULL THEN
                UPDATE mes.partida_paso_ejecucion
                SET estado = 'COMPLETADO', fyh_fin = v_fyh_fin, fyh_mod = NOW()
                WHERE id = v_ejecucion_id AND fyh_fin IS NULL;
                IF FOUND THEN
                    UPDATE mes.partida_paso SET estado = 'COMPLETADO', fyh_mod = NOW() WHERE id = v_paso_id;
                    RAISE NOTICE 'COMPACTADO (5944): ejecucion % — fyh_fin parcheado', v_ejecucion_id;
                ELSE
                    RAISE NOTICE 'COMPACTADO (5944): ejecucion ya completa — saltado';
                END IF;
            ELSE
                RAISE NOTICE 'COMPACTADO (5944): ejecucion ya existe — saltado';
            END IF;
            CONTINUE;
        END IF;

        INSERT INTO mes.partida_paso_ejecucion (
            partida_paso_id, estado, maquina_id, fyh_inicio, cantidad_rollos, usr_cre, fyh_cre
        ) VALUES (
            v_paso_id, 'EN_PROCESO', rec.maquina_id, v_fyh_inicio, rec.rollos, NULL, v_fyh_inicio
        ) RETURNING id INTO v_ejecucion_id;

        SELECT NOT EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            WHERE pp.partida_id = 5944
              AND pp.id         != v_paso_id
              AND pp.estado     NOT IN ('COMPLETADO', 'OMITIDO')
        ) INTO v_is_last_step;

        IF v_is_last_step THEN
            SELECT jsonb_agg(jsonb_build_object('input_lote_id', pc.lote_id, 'peso_salida', l.cantidad))
            INTO v_output_json
            FROM mes.partida_componente pc
            JOIN inventario.lote l ON l.id = pc.lote_id
            WHERE pc.partida_id = 5944
              AND pc.lote_id IS NOT NULL
              -- registrar_produccion requires lote_rollo_detalle; skip lotes without it
              AND EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle WHERE lote_id = pc.lote_id)
              AND NOT EXISTS (
                  SELECT 1 FROM inventario.item_movimientos im
                  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                  WHERE im.lote_id = pc.lote_id AND imt.codigo = 'PROD_CONSUMO'
              );

            IF v_output_json IS NOT NULL THEN
                IF EXISTS (SELECT 1 FROM mes.partida WHERE id = 5944 AND estado_produccion IN ('TECO', 'CERRADA')) THEN
                    RAISE NOTICE 'COMPACTADO (5944): ya es TECO/CERRADA — omitiendo registrar_produccion, solo ejecucion';
                ELSE
                    PERFORM mes.registrar_produccion(v_ejecucion_id, jsonb_build_object('output', v_output_json));
                    RAISE NOTICE 'COMPACTADO (5944): registrar_produccion OK';
                END IF;
            ELSE
                RAISE NOTICE 'COMPACTADO (5944): produccion ya registrada o sin lotes — solo ejecucion';
            END IF;
        END IF;

        UPDATE mes.partida_paso_ejecucion
        SET estado   = 'COMPLETADO',
            fyh_fin  = v_fyh_fin,
            fyh_mod  = NOW(),
            peso_kg  = CASE WHEN v_is_last_step THEN peso_kg
                            ELSE (SELECT ROUND(
                                     SUM(l.cantidad) * rec.rollos
                                     / NULLIF(COUNT(pc.lote_id)::numeric, 0), 4)
                                  FROM mes.partida_componente pc
                                  JOIN inventario.lote l ON l.id = pc.lote_id
                                  WHERE pc.partida_id = 5944
                                    AND pc.lote_id IS NOT NULL)
                       END
        WHERE id = v_ejecucion_id;

        UPDATE mes.partida_paso SET estado = 'COMPLETADO', fyh_mod = NOW() WHERE id = v_paso_id;

        RAISE NOTICE 'COMPACTADO (5944): COMPLETADO (last_step=%)', v_is_last_step;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════════
    -- State machine
    -- ═══════════════════════════════════════════════════════════════════════════
    FOR rec IN
        SELECT v.partida_id FROM (VALUES
            (3888::bigint), (4390), (4410), (4566), (4955),
            (5062), (5234), (5906), (5907),
            (5944)
        ) v(partida_id)
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
    pe.cantidad_rollos                        AS rollos,
    p.estado_produccion
FROM mes.partida_paso pp
JOIN mes.operacion o               ON o.id  = pp.operacion_id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN mes.partida p                 ON p.id  = pp.partida_id
LEFT JOIN mes.maquina m            ON m.id  = pe.maquina_id
WHERE pp.partida_id IN (3888,4390,4410,4566,4955,5062,5234,5906,5907,5944)
  AND o.codigo = 'COMPACTADO'
ORDER BY pp.partida_id, pe.fyh_inicio;

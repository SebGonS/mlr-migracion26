-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY MIGRATION: TENIDO ejecuciones batch
--
-- PURPOSE:
--   Create mes.partida_paso_ejecucion for every TENIDO paso that lacks one,
--   and call mes.registrar_produccion() to record the inventory effects
--   (PROD_CONSUMO on input rolls + PROD_ING on output dyed-roll lotes).
--
-- PREREQUISITE:
--   Script 07_ingresso_rollos_cliente must have run first so that
--   mes.partida_componente is populated for client-owned partidas.
--   MLR-owned rolls should already be in partida_componente via scripts 01/01_all.
--
-- SOURCE:
--   public.produccion_tenido WHERE tipo = 'Teñido'
--
-- RELATIONSHIP TO 11_data_migration.sql:
--   Migration 11 created mes.partida_paso for each normal Teñido run with
--     paso.id = produccion_tenido.id  (OVERRIDING SYSTEM VALUE)
--   So we join directly: mes.partida_paso pp WHERE pp.id = pt.id
--
-- MIDNIGHT-MERGE ("recordar juntar cuando se pasa de las 12"):
--   Two consecutive pt rows for the same partida where the first ends after
--   22:00 and the second is the next calendar day are the same physical run
--   split by the legacy app at midnight.
--   Collapsed into ONE logical run:
--     fyh_inicio = first row's hora_inicio
--     fyh_fin    = last row's hora_fin
--     primary paso = first pt row's paso (carries registrar_produccion call)
--     additional pasos in the group = timing-only COMPLETADO ejecucion (no
--       inventory effects — the primary already committed PROD_CONSUMO/PROD_ING)
--
-- WEIGHTS:
--   public.partida.peso_rollos / peso_rib  (partida-level total weight).
--   These are the same values used by script 07 for pesaje and lote.cantidad.
--
-- IDEMPOTENCY:
--   Pasos that already have at least one ejecucion are skipped.
--   Partidas with no rolls in partida_componente are skipped with a warning.
--
-- WORKFLOW:
--   1. Run SECTION 0 (PRE-FLIGHT) — verify counts and midnight-split pairs.
--   2. Run SECTION 1 (EXECUTE) — commits everything.
--   3. Run SECTION 2 (VERIFY) — confirm post-migration state.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Overview: how many TENIDO pasos exist vs how many have ejecuciones
SELECT
    COUNT(DISTINCT pp.partida_id)
        FILTER (WHERE pe.id IS NULL)                AS partidas_sin_ejecucion,
    COUNT(DISTINCT pp.partida_id)
        FILTER (WHERE pe.id IS NOT NULL)             AS partidas_ya_con_ejecucion,
    COUNT(pp.id)
        FILTER (WHERE pe.id IS NULL)                AS pasos_sin_ejecucion,
    COUNT(pp.id)
        FILTER (WHERE pe.id IS NOT NULL)             AS pasos_ya_con_ejecucion,
    -- Rolls readiness
    COUNT(DISTINCT pp.partida_id)
        FILTER (WHERE pe.id IS NULL
            AND NOT EXISTS (
                SELECT 1 FROM mes.partida_componente pc
                WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL
            ))                                       AS partidas_sin_componente_aun
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
JOIN mes.partida mp  ON mp.id = pp.partida_id AND mp.estado_produccion != 'CANCELADA'
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id;


-- Detected midnight-split pairs (will be collapsed into one ejecucion)
WITH annotated AS (
    SELECT
        pt.id, pt.partida_id, pt.fecha, pt.hora_inicio, pt.hora_fin,
        LAG(pt.fecha)    OVER w AS prev_fecha,
        LAG(pt.hora_fin) OVER w AS prev_hora_fin
    FROM public.produccion_tenido pt
    JOIN mes.partida mp ON mp.id = pt.partida_id AND mp.estado_produccion != 'CANCELADA'
    WHERE pt.tipo = 'Teñido'
    WINDOW w AS (PARTITION BY pt.partida_id ORDER BY pt.fecha, pt.id)
),
with_groups AS (
    SELECT *,
        CASE
            WHEN prev_fecha IS NOT NULL
             AND fecha = prev_fecha + 1
             AND prev_hora_fin > '22:00'::time
            THEN 0 ELSE 1
        END AS new_group_flag
    FROM annotated
),
with_run AS (
    SELECT *,
        SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group
    FROM with_groups
),
merged AS (
    SELECT
        partida_id, run_group,
        COUNT(*)         AS n_rows,
        MIN(id)          AS pt_id_primary,
        MAX(id)          AS pt_id_last,
        MIN(fecha)       AS fecha_inicio,
        MAX(fecha)       AS fecha_fin,
        MIN(hora_inicio) AS hora_inicio,
        MAX(hora_fin)    AS hora_fin
    FROM with_run
    GROUP BY partida_id, run_group
    HAVING COUNT(*) > 1
)
SELECT
    m.*,
    pp1.id AS paso_primary,
    pp2.id AS paso_continuation,
    pe1.id AS eje_primary_existente,
    pe2.id AS eje_continuation_existente
FROM merged m
LEFT JOIN mes.partida_paso pp1 ON pp1.id = m.pt_id_primary
LEFT JOIN mes.partida_paso pp2 ON pp2.id = m.pt_id_last
LEFT JOIN mes.partida_paso_ejecucion pe1 ON pe1.partida_paso_id = pp1.id
LEFT JOIN mes.partida_paso_ejecucion pe2 ON pe2.partida_paso_id = pp2.id
ORDER BY m.partida_id, m.run_group;


-- Partidas with rolls but no partida_componente entries (script 07 not yet run for these)
SELECT
    mp.id               AS partida_id,
    mp.estado_produccion,
    pub.rollos,
    pub.rib,
    pub.peso_rollos,
    pub.peso_rib,
    pub.entrega
FROM mes.partida mp
JOIN public.partida pub ON pub.id = mp.id
WHERE mp.estado_produccion != 'CANCELADA'
  AND pub.rollos > 0
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc
      WHERE pc.partida_id = mp.id AND pc.lote_id IS NOT NULL
  )
  AND EXISTS (
      SELECT 1 FROM mes.partida_paso pp
      JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
      WHERE pp.partida_id = mp.id
      AND NOT EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id)
  )
ORDER BY mp.id;


-- Ghost-egress warning: rolls assigned to eligible partidas that already have
-- SERV_EGR or PROD_CONSUMO movements — these will cause registrar_produccion
-- to fail (roll no longer available) or produce double-consumption.
-- Run rollback_ultimo_paso or repair_os_ingress first for these partidas.
SELECT
    pc.partida_id,
    l.id                    AS lote_id,
    l.codigo                AS lote_codigo,
    imt.codigo              AS movimiento_existente,
    im.fyh_cre::date        AS fecha_mov
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
JOIN inventario.item_movimientos im ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('SERV_EGR', 'PROD_CONSUMO')
WHERE pc.lote_id IS NOT NULL
  AND EXISTS (
      SELECT 1 FROM mes.partida_paso pp
      JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
      WHERE pp.partida_id = pc.partida_id
        AND NOT EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id)
  )
ORDER BY pc.partida_id, l.id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — EXECUTE
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_usr_admin         INT         := 1;

    -- Resolved once
    v_ubicacion_id      INT;

    -- Per-run state
    r_run               RECORD;
    v_cont_paso_id      BIGINT;
    v_paso_id           BIGINT;
    v_ejecucion_id      BIGINT;
    v_roll_count        INT;
    v_output_json       JSONB;
    v_payload           JSONB;
    v_result            TEXT;
    v_fyh_inicio        TIMESTAMPTZ;
    v_fyh_fin           TIMESTAMPTZ;
    v_peso_rollos       NUMERIC;
    v_peso_rib          NUMERIC;
    v_created           INT := 0;
    v_no_rolls          INT := 0;
BEGIN
    -- ── Resolve reference data ────────────────────────────────────────────────
    SELECT ub.id INTO v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_PT'
    LIMIT 1;

    IF v_ubicacion_id IS NULL THEN
        RAISE EXCEPTION 'Ubicación ALM_PT no encontrada.';
    END IF;

    -- ── Process each merged run group ─────────────────────────────────────────
    --   One row per logical dyeing run (midnight-merged when applicable).
    --   primary_paso_id  = the paso that will receive registrar_produccion.
    --   continuation_ids = pasos for the remaining rows in a midnight-split group.
    --
    FOR r_run IN
        WITH pt_annotated AS (
            SELECT
                pt.id, pt.partida_id, pt.fecha, pt.hora_inicio, pt.hora_fin,
                LAG(pt.fecha)    OVER w AS prev_fecha,
                LAG(pt.hora_fin) OVER w AS prev_hora_fin
            FROM public.produccion_tenido pt
            JOIN mes.partida mp ON mp.id = pt.partida_id
            WHERE pt.tipo = 'Teñido'
              AND mp.estado_produccion != 'CANCELADA'
            WINDOW w AS (PARTITION BY pt.partida_id ORDER BY pt.fecha, pt.id)
        ),
        with_groups AS (
            SELECT *,
                CASE
                    WHEN prev_fecha IS NOT NULL
                     AND fecha = prev_fecha + 1
                     AND prev_hora_fin > '22:00'::time
                    THEN 0 ELSE 1
                END AS new_group_flag
            FROM pt_annotated
        ),
        with_run AS (
            SELECT *,
                SUM(new_group_flag) OVER (
                    PARTITION BY partida_id ORDER BY fecha, id
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS run_group
            FROM with_groups
        ),
        run_primary AS (
            SELECT partida_id, run_group, MIN(id) AS pt_id_primary
            FROM with_run
            GROUP BY partida_id, run_group
        ),
        merged AS (
            SELECT
                wr.partida_id,
                wr.run_group,
                rp.pt_id_primary,
                ARRAY_AGG(wr.id ORDER BY wr.fecha, wr.id)
                    FILTER (WHERE wr.id <> rp.pt_id_primary) AS pt_ids_continuation,
                MIN(wr.fecha)       AS fecha_inicio,
                MAX(wr.fecha)       AS fecha_fin,
                MIN(wr.hora_inicio) AS hora_inicio,
                MAX(wr.hora_fin)    AS hora_fin
            FROM with_run wr
            JOIN run_primary rp ON rp.partida_id = wr.partida_id
                                AND rp.run_group  = wr.run_group
            GROUP BY wr.partida_id, wr.run_group, rp.pt_id_primary
        )
        SELECT
            m.partida_id,
            m.run_group,
            m.pt_id_primary,
            m.pt_ids_continuation,
            -- Primary paso (paso.id = pt.id from migration 11)
            pp_primary.id                           AS primary_paso_id,
            pp_primary.estado                       AS primary_paso_estado,
            -- Timestamps (UTC offset already in legacy: add 5h for -05 tz)
            ((m.fecha_inicio + COALESCE(m.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ  AS fyh_inicio,
            CASE WHEN m.hora_fin IS NOT NULL
                 THEN ((m.fecha_fin + m.hora_fin)::TIMESTAMP
                     + INTERVAL '5 hours')::TIMESTAMPTZ
                 ELSE NULL
            END                                     AS fyh_fin,
            -- Partida-level weights
            pub.peso_rollos,
            pub.peso_rib
        FROM merged m
        JOIN mes.partida_paso pp_primary ON pp_primary.id = m.pt_id_primary
        JOIN public.partida pub ON pub.id = m.partida_id
        -- Skip entirely if the primary paso already has an ejecucion
        WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp_primary.id
        )
        ORDER BY m.partida_id, m.run_group
    LOOP

        v_paso_id    := r_run.primary_paso_id;
        v_fyh_inicio := r_run.fyh_inicio;
        v_fyh_fin    := r_run.fyh_fin;
        v_peso_rollos := r_run.peso_rollos;
        v_peso_rib    := r_run.peso_rib;

        -- ── Guard: rolls must exist in partida_componente ────────────────────
        SELECT COUNT(*) INTO v_roll_count
        FROM mes.partida_componente pc
        WHERE pc.partida_id = r_run.partida_id AND pc.lote_id IS NOT NULL;

        IF v_roll_count = 0 THEN
            RAISE NOTICE 'Partida #%: sin rollos en partida_componente — saltando (run script 07 first).',
                r_run.partida_id;
            v_no_rolls := v_no_rolls + 1;
            CONTINUE;
        END IF;

        -- ── Create ejecucion in EN_PROCESO (required by registrar_produccion) ─
        INSERT INTO mes.partida_paso_ejecucion (
            partida_paso_id, estado, maquina_id,
            fyh_inicio, cantidad,
            usr_cre, fyh_cre
        )
        VALUES (
            v_paso_id,
            'EN_PROCESO',
            (SELECT maquina_planificada_id FROM mes.partida_paso WHERE id = v_paso_id),
            v_fyh_inicio,
            v_roll_count,
            v_usr_admin,
            v_fyh_inicio
        )
        RETURNING id INTO v_ejecucion_id;

        -- ── Build registrar_produccion payload ───────────────────────────────
        SELECT jsonb_agg(jsonb_build_object('input_lote_id', pc.lote_id))
        INTO v_output_json
        FROM mes.partida_componente pc
        WHERE pc.partida_id = r_run.partida_id AND pc.lote_id IS NOT NULL;

        v_payload := jsonb_build_object('ubicacion_id', v_ubicacion_id, 'output', v_output_json);

        IF v_peso_rollos IS NOT NULL AND v_peso_rollos > 0 THEN
            v_payload := v_payload || jsonb_build_object('peso_rollos', v_peso_rollos);
        END IF;
        IF v_peso_rib IS NOT NULL AND v_peso_rib > 0 THEN
            v_payload := v_payload || jsonb_build_object('peso_rib', v_peso_rib);
        END IF;

        -- ── Call registrar_produccion ────────────────────────────────────────
        v_result := mes.registrar_produccion(v_ejecucion_id, v_payload);
        RAISE NOTICE 'Partida #% paso %: registrar_produccion → %',
            r_run.partida_id, v_paso_id, v_result;

        -- ── Close the primary ejecucion ──────────────────────────────────────
        UPDATE mes.partida_paso_ejecucion
        SET estado   = 'COMPLETADO',
            fyh_fin  = v_fyh_fin,
            usr_mod  = v_usr_admin,
            fyh_mod  = NOW()
        WHERE id = v_ejecucion_id;

        -- ── Mark primary paso COMPLETADO ─────────────────────────────────────
        UPDATE mes.partida_paso
        SET estado  = 'COMPLETADO',
            usr_mod = v_usr_admin,
            fyh_mod = NOW()
        WHERE id = v_paso_id;

        -- ── Continuation pasos (midnight-merge: extra rows in the same run) ──
        --   These get a timing-only COMPLETADO ejecucion; no second inventory call.
        IF r_run.pt_ids_continuation IS NOT NULL THEN
            FOREACH v_cont_paso_id IN ARRAY r_run.pt_ids_continuation LOOP

                -- Skip if this continuation paso already has an ejecucion
                IF EXISTS (
                    SELECT 1 FROM mes.partida_paso_ejecucion pe
                    WHERE pe.partida_paso_id = v_cont_paso_id
                ) THEN
                    RAISE NOTICE 'Partida #% paso % (continuation): ya tiene ejecucion — saltando.',
                        r_run.partida_id, v_cont_paso_id;
                    CONTINUE;
                END IF;

                INSERT INTO mes.partida_paso_ejecucion (
                    partida_paso_id, estado, maquina_id,
                    fyh_inicio, fyh_fin, cantidad,
                    usr_cre, fyh_cre
                )
                SELECT
                    v_cont_paso_id,
                    'COMPLETADO',
                    pp_cont.maquina_planificada_id,
                    v_fyh_inicio,
                    v_fyh_fin,
                    v_roll_count,
                    v_usr_admin,
                    v_fyh_inicio
                FROM mes.partida_paso pp_cont
                WHERE pp_cont.id = v_cont_paso_id;

                UPDATE mes.partida_paso
                SET estado  = 'COMPLETADO',
                    usr_mod = v_usr_admin,
                    fyh_mod = NOW()
                WHERE id = v_cont_paso_id;

                RAISE NOTICE 'Partida #% paso % (continuation): ejecucion timing-only creada.',
                    r_run.partida_id, v_cont_paso_id;
            END LOOP;
        END IF;

        -- ── Advance partida state ────────────────────────────────────────────
        PERFORM mes.actualizar_estado_partida(r_run.partida_id);

        RAISE NOTICE 'Partida #%: estado → %',
            r_run.partida_id,
            (SELECT estado_produccion FROM mes.partida WHERE id = r_run.partida_id);

        v_created := v_created + 1;
    END LOOP;

    RAISE NOTICE '══════════════════════════════════════════════';
    RAISE NOTICE 'RESUMEN:';
    RAISE NOTICE '  ejecuciones creadas (primarias) : %', v_created;
    RAISE NOTICE '  saltadas (sin rolls)             : %', v_no_rolls;
    RAISE NOTICE '══════════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VERIFY
-- ═══════════════════════════════════════════════════════════════════════════════

-- Pasos that still have no ejecucion after the migration
SELECT
    pp.partida_id,
    pp.id             AS paso_id,
    pp.secuencia,
    o.codigo          AS operacion,
    pp.estado         AS paso_estado,
    mp.estado_produccion,
    (
        SELECT COUNT(*) FROM mes.partida_componente pc
        WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL
    )                 AS rolls_in_componente
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
JOIN mes.partida mp   ON mp.id = pp.partida_id AND mp.estado_produccion != 'CANCELADA'
WHERE NOT EXISTS (
    SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id
)
ORDER BY pp.partida_id, pp.secuencia;


-- Sample: output lotes and movements created for the last 10 partidas processed
SELECT
    mp.id              AS partida_id,
    mp.estado_produccion,
    pp.secuencia,
    pe.id              AS ejecucion_id,
    pe.estado          AS eje_estado,
    pe.fyh_inicio,
    pe.fyh_fin,
    COUNT(DISTINCT l.id)   AS output_lotes,
    COUNT(DISTINCT im.id)  AS movimientos
FROM mes.partida mp
JOIN mes.partida_paso pp ON pp.partida_id = mp.id
JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
LEFT JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion'
                            AND l.documento_id = pe.id
LEFT JOIN inventario.item_movimientos im ON im.documento_tipo = 'partida_paso_ejecucion'
                                        AND im.documento_id = pe.id
WHERE pe.fyh_cre > NOW() - INTERVAL '1 hour'
GROUP BY mp.id, mp.estado_produccion, pp.secuencia, pe.id, pe.estado, pe.fyh_inicio, pe.fyh_fin
ORDER BY pe.id DESC
LIMIT 20;


-- Count summary post-migration
SELECT
    COUNT(DISTINCT pp.partida_id) FILTER (WHERE pe.id IS NOT NULL)  AS partidas_con_ejecucion,
    COUNT(DISTINCT pp.partida_id) FILTER (WHERE pe.id IS NULL)      AS partidas_sin_ejecucion,
    COUNT(pp.id)  FILTER (WHERE pe.id IS NOT NULL)                  AS pasos_con_ejecucion,
    COUNT(pp.id)  FILTER (WHERE pe.id IS NULL)                      AS pasos_sin_ejecucion
FROM mes.partida_paso pp
JOIN mes.operacion o  ON o.id  = pp.operacion_id AND o.codigo = 'TENIDO'
JOIN mes.partida mp   ON mp.id = pp.partida_id   AND mp.estado_produccion != 'CANCELADA'
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id;

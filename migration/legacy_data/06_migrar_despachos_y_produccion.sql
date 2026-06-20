-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL (run only to undo this migration — deletes ALL pasos for these
-- operations including any manually entered post-migration)
-- ─────────────────────────────────────────────────────────────────────────────
-- DELETE FROM mes.partida_paso_ejecucion
-- WHERE partida_paso_id IN (
--     SELECT pp.id FROM mes.partida_paso pp
--     JOIN mes.operacion o ON o.id = pp.operacion_id
--     WHERE o.codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
-- );
-- DELETE FROM mes.partida_paso
-- WHERE operacion_id IN (
--     SELECT id FROM mes.operacion
--     WHERE codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
-- );
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY MIGRATION: acabados de producción → mes.partida_paso + ejecucion
----1. Termofijado (recordar - rib) termofijaddo
--2. Tenido (recordar juntar cuando se pasa de las 12) produccion_tenido
--3. Compactado (recordar juntar cuando se pasa de las 12) compactado
-- VOLTEADO: no legacy source table found in schema.sql — not migratable from legacy data.

-- Sources        : public.termofijado, public.perchado, public.compactado
-- NOT included   : public.produccion_tenido → already migrated in 11_data_migration.sql
-- Target         : mes.partida_paso + mes.partida_paso_ejecucion
--
-- Relationship to 11_data_migration.sql:
--   mes.partida.id = public.partida.id (OVERRIDING SYSTEM VALUE in 11_data_migration)
--   so termofijado/perchado/compactado.partida_id maps directly to mes.partida.id. ✓
--
--   TENIDO pasos were created with id = produccion_tenido.id (also OVERRIDING).
--   11_data_migration called setval() after those inserts, so our auto-generated
--   finishing paso IDs start above MAX(existing paso id) — no collisions. ✓
--
--   TENIDO paso filter in 11_data_migration also required:
--     EXISTS (SELECT 1 FROM receta2 WHERE id = p.receta_id)
--   Partidas without a recipe got NO TENIDO paso. If those partidas also have
--   finishing op rows they would land at secuencia 1 with no prior TENIDO —
--   inconsistent history. Run SECTION 0 (PRE-FLIGHT) first to surface these.
--
-- NO inventory side-effects:
--   registrar_produccion (PROD_CONSUMO + PROD_ING) is only called for TENIDO.
--   Finishing operations record timing/machine data only. The dyed roll lotes
--   from the TENIDO migration are already in inventario.lote + partida_componente
--   and remain the implicit roll reference for these pasos.
--
-- Idempotency guard:
--   Each section checks NOT EXISTS (paso for this operacion_id on this partida).
--   This covers both "already migrated by a previous run" and "manually entered
--   via the app post-migration". ON CONFLICT on secuencia alone is insufficient
--   because secuencias shift if pasos were added out of order.
--   CANCELADA partidas are skipped; TECO/CERRADA are included (they hold the
--   historical production data we need.
--
-- partida_paso.estado:
--   Set directly to COMPLETADO on insert (migration 19 added this column).
--   All legacy rows represent completed historical runs.
--
-- Secuencia continuity:
--   seq_base is recomputed inside each DO block from the live state of
--   mes.partida_paso, so within the same session:
--     TERMOFIJADO appends after TENIDO pasos
--     PERCHADO    appends after TENIDO + TERMOFIJADO
--     COMPACTADO  appends after all of the above
--   Run sections in order within the same session/transaction.
--
-- Midnight-split ("juntar cuando se pasa de las 12"):
--   ALL tables (termofijado, perchado, compactado) exhibit this: the legacy app
--   created two rows when a run crossed midnight. Adjacent-night pairs
--   (same partida, date+1, prev hora_fin > '22:00') are collapsed into one
--   ejecucion: first row's hora_inicio + last row's hora_fin + summed rollos.
--   DRY-RUN sections show detected merges before writing anything.
--
-- Termofijado rib note ("recordar - rib"):
--   termofijado.rollos includes rib rolls (tracked together in legacy).
--   cantidad on the ejecucion covers both.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT: partidas with finishing ops but NO TENIDO paso
-- Run this before executing any section. Decide how to handle each case:
--   Option A: accept the gap — finishing pasos land at secuencia 1 (historical
--             data is better than nothing if the dyeing run wasn't recorded)
--   Option B: exclude those partidas — add their IDs to the NOT IN(...) filters
--             in each section's eligible_raw CTE
-- ═══════════════════════════════════════════════════════════════════════════════

WITH no_tenido AS (
    SELECT p.id AS partida_id, p.estado_produccion
    FROM mes.partida p
    WHERE p.estado_produccion != 'CANCELADA'
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_paso pp
          JOIN mes.operacion o ON o.id = pp.operacion_id
          WHERE pp.partida_id = p.id AND o.codigo = 'TENIDO'
      )
)
SELECT
    'termofijado'           AS fuente,
    COUNT(DISTINCT t.partida_id) AS partidas_afectadas,
    array_agg(DISTINCT t.partida_id ORDER BY t.partida_id) AS partida_ids
FROM public.termofijado t
JOIN no_tenido nt ON nt.partida_id = t.partida_id
UNION ALL
SELECT 'perchado', COUNT(DISTINCT ph.partida_id),
    array_agg(DISTINCT ph.partida_id ORDER BY ph.partida_id)
FROM public.perchado ph
JOIN no_tenido nt ON nt.partida_id = ph.partida_id
UNION ALL
SELECT 'compactado', COUNT(DISTINCT c.partida_id),
    array_agg(DISTINCT c.partida_id ORDER BY c.partida_id)
FROM public.compactado c
JOIN no_tenido nt ON nt.partida_id = c.partida_id;




-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — TERMOFIJADO
-- Source   : public.termofijado (Lycra / J Poly / French Terry articles only)
-- maquina  : not tracked in legacy → maquina_planificada_id = NULL
-- cantidad : rollos (includes rib — tracked together in legacy)
-- Midnight-split merge applied.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH annotated AS (
    SELECT
        id, partida_id, fecha, hora_inicio, hora_fin, rollos,
        LAG(fecha)     OVER w AS prev_fecha,
        LAG(hora_fin)  OVER w AS prev_hora_fin
    FROM public.termofijado
    WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
),
grouped AS (
    SELECT *,
        CASE
            WHEN prev_fecha IS NOT NULL
             AND fecha = prev_fecha + 1
             AND prev_hora_fin > '22:00'::time
            THEN 0 ELSE 1
        END AS new_group_flag
    FROM annotated
),
runs AS (
    SELECT *,
        SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group
    FROM grouped
),
run_summary AS (
    SELECT
        partida_id, run_group,
        COUNT(*)         AS n_rows,
        MIN(id)          AS anchor_id,
        MIN(fecha)       AS fecha_inicio,
        MAX(fecha)       AS fecha_fin,
        MIN(hora_inicio) AS hora_inicio,
        MAX(hora_fin)    AS hora_fin,
        SUM(rollos)      AS rollos_total
    FROM runs
    GROUP BY partida_id, run_group
)
SELECT * FROM run_summary WHERE n_rows > 1
ORDER BY partida_id, run_group;

SELECT
    COUNT(*)                                                                    AS total_rows,
    COUNT(DISTINCT t.partida_id)                                                AS partidas_distintas,
    COUNT(*) FILTER (
        WHERE t.partida_id IN (
            SELECT id FROM mes.partida WHERE estado_produccion != 'CANCELADA'
        )
    )                                                                           AS rows_elegibles,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            JOIN mes.operacion o ON o.id = pp.operacion_id
            WHERE pp.partida_id = t.partida_id AND o.codigo = 'TERMOFIJADO'
        )
    )                                                                           AS partidas_ya_migradas,
    MIN(t.fecha) AS fecha_min,
    MAX(t.fecha) AS fecha_max
FROM public.termofijado t;

-- ─────────────────────────────────────────────────────────────────────────────
-- EXECUTE — TERMOFIJADO (with midnight merge)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id  SMALLINT;
    v_count  INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'TERMOFIJADO';

    WITH
    eligible_raw AS (
        SELECT t.id, t.partida_id, t.fecha, t.hora_inicio, t.hora_fin, t.rollos
        FROM public.termofijado t
        JOIN mes.partida p ON p.id = t.partida_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              WHERE pp.partida_id = t.partida_id AND pp.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT
            *,
            LAG(fecha)     OVER w AS prev_fecha,
            LAG(hora_fin)  OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE
                WHEN prev_fecha IS NOT NULL
                 AND fecha = prev_fecha + 1
                 AND prev_hora_fin > '22:00'::time
                THEN 0 ELSE 1
            END AS new_group_flag
        FROM annotated
    ),
    run_groups AS (
        SELECT *,
            SUM(new_group_flag) OVER (
                PARTITION BY partida_id ORDER BY fecha, id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS run_group
        FROM grouped
    ),
    runs AS (
        SELECT
            partida_id,
            run_group,
            MIN(id)          AS anchor_id,
            MIN(fecha)       AS fecha_inicio,
            MAX(fecha)       AS fecha_fin,
            MIN(hora_inicio) AS hora_inicio,
            MAX(hora_fin)    AS hora_fin,
            SUM(rollos)      AS rollos_total
        FROM run_groups
        GROUP BY partida_id, run_group
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq
        FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT
            r.*,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM runs r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado,
            usr_cre, fyh_cre
        )
        SELECT
            rk.partida_id,
            rk.secuencia,
            v_op_id,
            NULL,
            'COMPLETADO'::partida_paso_estado_enum,
            NULL,
            ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id,
                  fyh_cre AS fyh_inicio_paso
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
        NULL,
        pi.fyh_inicio_paso,
        CASE WHEN rk.hora_fin IS NOT NULL
             THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
             ELSE NULL
        END,
        rk.rollos_total::NUMERIC,
        NULL,
        pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'TERMOFIJADO: % ejecuciones insertadas', v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — PERCHADO
-- Source   : public.perchado (F Poly articles only)
-- maquina  : not tracked in legacy → maquina_planificada_id = NULL
-- pases    → partida_paso_ejecucion.pases
-- Midnight-split merge applied.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH annotated AS (
    SELECT
        id, partida_id, fecha, hora_inicio, hora_fin, rollos, pases,
        LAG(fecha)     OVER w AS prev_fecha,
        LAG(hora_fin)  OVER w AS prev_hora_fin
    FROM public.perchado
    WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
),
grouped AS (
    SELECT *,
        CASE
            WHEN prev_fecha IS NOT NULL
             AND fecha = prev_fecha + 1
             AND prev_hora_fin > '22:00'::time
            THEN 0 ELSE 1
        END AS new_group_flag
    FROM annotated
),
runs AS (
    SELECT *,
        SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group
    FROM grouped
),
run_summary AS (
    SELECT
        partida_id, run_group,
        COUNT(*)         AS n_rows,
        MIN(id)          AS anchor_id,
        MIN(fecha)       AS fecha_inicio,
        MAX(fecha)       AS fecha_fin,
        MIN(hora_inicio) AS hora_inicio,
        MAX(hora_fin)    AS hora_fin,
        SUM(rollos)      AS rollos_total,
        MAX(pases)       AS pases
    FROM runs
    GROUP BY partida_id, run_group
)
SELECT * FROM run_summary WHERE n_rows > 1
ORDER BY partida_id, run_group;

SELECT
    COUNT(*)                                                                AS total_rows,
    COUNT(DISTINCT ph.partida_id)                                           AS partidas_distintas,
    COUNT(*) FILTER (
        WHERE ph.partida_id IN (
            SELECT id FROM mes.partida WHERE estado_produccion != 'CANCELADA'
        )
    )                                                                       AS rows_elegibles,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            JOIN mes.operacion o ON o.id = pp.operacion_id
            WHERE pp.partida_id = ph.partida_id AND o.codigo = 'PERCHADO'
        )
    )                                                                       AS partidas_ya_migradas,
    MIN(ph.fecha) AS fecha_min,
    MAX(ph.fecha) AS fecha_max
FROM public.perchado ph;

-- ─────────────────────────────────────────────────────────────────────────────
-- EXECUTE — PERCHADO (with midnight merge)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id  SMALLINT;
    v_count  INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'PERCHADO';

    WITH
    eligible_raw AS (
        SELECT ph.id, ph.partida_id, ph.fecha, ph.hora_inicio, ph.hora_fin,
               ph.rollos, ph.pases
        FROM public.perchado ph
        JOIN mes.partida p ON p.id = ph.partida_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              WHERE pp.partida_id = ph.partida_id AND pp.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT
            *,
            LAG(fecha)     OVER w AS prev_fecha,
            LAG(hora_fin)  OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE
                WHEN prev_fecha IS NOT NULL
                 AND fecha = prev_fecha + 1
                 AND prev_hora_fin > '22:00'::time
                THEN 0 ELSE 1
            END AS new_group_flag
        FROM annotated
    ),
    run_groups AS (
        SELECT *,
            SUM(new_group_flag) OVER (
                PARTITION BY partida_id ORDER BY fecha, id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS run_group
        FROM grouped
    ),
    -- One row per merged run: anchor = first legacy row's id (for traceability)
    runs AS (
        SELECT
            partida_id,
            run_group,
            MIN(id)          AS anchor_id,
            MIN(fecha)       AS fecha_inicio,
            MAX(fecha)       AS fecha_fin,
            MIN(hora_inicio) AS hora_inicio,
            MAX(hora_fin)    AS hora_fin,
            SUM(rollos)      AS rollos_total,
            MAX(pases)       AS pases
        FROM run_groups
        GROUP BY partida_id, run_group
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq
        FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT
            r.*,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM runs r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado,
            usr_cre, fyh_cre
        )
        SELECT
            rk.partida_id,
            rk.secuencia,
            v_op_id,
            NULL,
            'COMPLETADO'::partida_paso_estado_enum,
            NULL,
            ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id,
                  fyh_cre AS fyh_inicio_paso
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
        NULL,
        pi.fyh_inicio_paso,
        CASE WHEN rk.hora_fin IS NOT NULL
             THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
             ELSE NULL
        END,
        rk.rollos_total::NUMERIC,
        rk.pases::SMALLINT,
        NULL,
        pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'PERCHADO: % ejecuciones insertadas', v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — COMPACTADO
-- Source   : public.compactado
-- maquina  : maquina_id present → mapped to both maquina_planificada_id and
--            partida_paso_ejecucion.maquina_id
-- cantidad : rollos + rib (both roll types go through compactado)
-- tipo_partida / estado columns in legacy have no target → ignored
-- Midnight-split merge applied.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH annotated AS (
    SELECT
        id, partida_id, fecha, hora_inicio, hora_fin, rollos, rib, maquina_id,
        LAG(fecha)     OVER w AS prev_fecha,
        LAG(hora_fin)  OVER w AS prev_hora_fin
    FROM public.compactado
    WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
),
grouped AS (
    SELECT *,
        CASE
            WHEN prev_fecha IS NOT NULL
             AND fecha = prev_fecha + 1
             AND prev_hora_fin > '22:00'::time
            THEN 0 ELSE 1
        END AS new_group_flag
    FROM annotated
),
runs AS (
    SELECT *,
        SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group
    FROM grouped
),
run_summary AS (
    SELECT
        partida_id, run_group,
        COUNT(*)                    AS n_rows,
        MIN(id)                     AS anchor_id,
        MIN(fecha)                  AS fecha_inicio,
        MAX(fecha)                  AS fecha_fin,
        MIN(hora_inicio)            AS hora_inicio,
        MAX(hora_fin)               AS hora_fin,
        SUM(rollos)                 AS rollos_total,
        SUM(COALESCE(rib, 0))       AS rib_total,
        MAX(maquina_id)             AS maquina_id
    FROM runs
    GROUP BY partida_id, run_group
)
SELECT * FROM run_summary WHERE n_rows > 1
ORDER BY partida_id, run_group;

SELECT
    COUNT(*)                                                                AS total_rows,
    COUNT(DISTINCT c.partida_id)                                            AS partidas_distintas,
    COUNT(*) FILTER (
        WHERE c.partida_id IN (
            SELECT id FROM mes.partida WHERE estado_produccion != 'CANCELADA'
        )
    )                                                                       AS rows_elegibles,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            JOIN mes.operacion o ON o.id = pp.operacion_id
            WHERE pp.partida_id = c.partida_id AND o.codigo = 'COMPACTADO'
        )
    )                                                                       AS partidas_ya_migradas,
    MIN(c.fecha) AS fecha_min,
    MAX(c.fecha) AS fecha_max
FROM public.compactado c;

-- ─────────────────────────────────────────────────────────────────────────────
-- EXECUTE — COMPACTADO (with midnight merge)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id  SMALLINT;
    v_count  INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'COMPACTADO';

    WITH
    eligible_raw AS (
        SELECT c.id, c.partida_id, c.fecha, c.hora_inicio, c.hora_fin,
               c.rollos, c.rib, c.maquina_id
        FROM public.compactado c
        JOIN mes.partida p ON p.id = c.partida_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              WHERE pp.partida_id = c.partida_id AND pp.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT
            *,
            LAG(fecha)     OVER w AS prev_fecha,
            LAG(hora_fin)  OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE
                WHEN prev_fecha IS NOT NULL
                 AND fecha = prev_fecha + 1
                 AND prev_hora_fin > '22:00'::time
                THEN 0 ELSE 1
            END AS new_group_flag
        FROM annotated
    ),
    run_groups AS (
        SELECT *,
            SUM(new_group_flag) OVER (
                PARTITION BY partida_id ORDER BY fecha, id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS run_group
        FROM grouped
    ),
    runs AS (
        SELECT
            partida_id,
            run_group,
            MIN(id)                     AS anchor_id,
            MIN(fecha)                  AS fecha_inicio,
            MAX(fecha)                  AS fecha_fin,
            MIN(hora_inicio)            AS hora_inicio,
            MAX(hora_fin)               AS hora_fin,
            SUM(rollos)                 AS rollos_total,
            SUM(COALESCE(rib, 0))       AS rib_total,
            MAX(maquina_id)             AS maquina_id
        FROM run_groups
        GROUP BY partida_id, run_group
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq
        FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT
            r.*,
            r.rollos_total + r.rib_total AS cantidad_total,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM runs r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado,
            usr_cre, fyh_cre
        )
        SELECT
            rk.partida_id,
            rk.secuencia,
            v_op_id,
            rk.maquina_id,
            'COMPLETADO'::partida_paso_estado_enum,
            NULL,
            ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id,
                  fyh_cre AS fyh_inicio_paso
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
        CASE WHEN rk.hora_fin IS NOT NULL
             THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
             ELSE NULL
        END,
        rk.cantidad_total::NUMERIC,
        NULL,
        pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'COMPACTADO: % ejecuciones insertadas', v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 4 — CONTINUATION: fill missing ejecuciones for partidas that already
-- had at least one paso per operation (skipped by main blocks).
-- Guard is per-run (fyh_inicio match) instead of per-partida.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- CONTINUATION — TERMOFIJADO
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id  SMALLINT;
    v_count  INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'TERMOFIJADO';

    WITH
    eligible_raw AS (
        SELECT t.id, t.partida_id, t.fecha, t.hora_inicio, t.hora_fin, t.rollos
        FROM public.termofijado t
        JOIN mes.partida p ON p.id = t.partida_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              WHERE pp.partida_id = t.partida_id AND pp.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT *, LAG(fecha) OVER w AS prev_fecha, LAG(hora_fin) OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE
                WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
                     AND prev_hora_fin > '22:00'::time
                THEN 0 ELSE 1
            END AS new_group_flag
        FROM annotated
    ),
    run_groups AS (
        SELECT *, SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group FROM grouped
    ),
    runs AS (
        SELECT partida_id, run_group,
               MIN(id) AS anchor_id, MIN(fecha) AS fecha_inicio, MAX(fecha) AS fecha_fin,
               MIN(hora_inicio) AS hora_inicio, MAX(hora_fin) AS hora_fin,
               SUM(rollos) AS rollos_total
        FROM run_groups GROUP BY partida_id, run_group
    ),
    filtered_runs AS (
        SELECT r.* FROM runs r
        WHERE NOT EXISTS (
            SELECT 1
            FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
            WHERE pp.partida_id = r.partida_id AND pp.operacion_id = v_op_id
              AND pe.fyh_inicio = ((r.fecha_inicio + COALESCE(r.hora_inicio, '06:00'::time))::TIMESTAMP
                                    + INTERVAL '5 hours')::TIMESTAMPTZ
        )
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM filtered_runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT r.*,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM filtered_runs r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT rk.partida_id, rk.secuencia, v_op_id, NULL,
               'COMPLETADO'::partida_paso_estado_enum, NULL,
               ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                   + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, usr_cre, fyh_cre
    )
    SELECT pi.paso_id, 'COMPLETADO', NULL, pi.fyh_inicio_paso,
           CASE WHEN rk.hora_fin IS NOT NULL
                THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                ELSE NULL END,
           rk.rollos_total::NUMERIC, NULL, pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'TERMOFIJADO continuation: % ejecuciones insertadas', v_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- CONTINUATION — PERCHADO
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id  SMALLINT;
    v_count  INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'PERCHADO';

    WITH
    eligible_raw AS (
        SELECT ph.id, ph.partida_id, ph.fecha, ph.hora_inicio, ph.hora_fin,
               ph.rollos, ph.pases
        FROM public.perchado ph
        JOIN mes.partida p ON p.id = ph.partida_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              WHERE pp.partida_id = ph.partida_id AND pp.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT *, LAG(fecha) OVER w AS prev_fecha, LAG(hora_fin) OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE
                WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
                     AND prev_hora_fin > '22:00'::time
                THEN 0 ELSE 1
            END AS new_group_flag
        FROM annotated
    ),
    run_groups AS (
        SELECT *, SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group FROM grouped
    ),
    runs AS (
        SELECT partida_id, run_group,
               MIN(id) AS anchor_id, MIN(fecha) AS fecha_inicio, MAX(fecha) AS fecha_fin,
               MIN(hora_inicio) AS hora_inicio, MAX(hora_fin) AS hora_fin,
               SUM(rollos) AS rollos_total, MAX(pases) AS pases
        FROM run_groups GROUP BY partida_id, run_group
    ),
    filtered_runs AS (
        SELECT r.* FROM runs r
        WHERE NOT EXISTS (
            SELECT 1
            FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
            WHERE pp.partida_id = r.partida_id AND pp.operacion_id = v_op_id
              AND pe.fyh_inicio = ((r.fecha_inicio + COALESCE(r.hora_inicio, '06:00'::time))::TIMESTAMP
                                    + INTERVAL '5 hours')::TIMESTAMPTZ
        )
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM filtered_runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT r.*,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM filtered_runs r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT rk.partida_id, rk.secuencia, v_op_id, NULL,
               'COMPLETADO'::partida_paso_estado_enum, NULL,
               ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                   + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, pases, usr_cre, fyh_cre
    )
    SELECT pi.paso_id, 'COMPLETADO', NULL, pi.fyh_inicio_paso,
           CASE WHEN rk.hora_fin IS NOT NULL
                THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                ELSE NULL END,
           rk.rollos_total::NUMERIC, rk.pases::SMALLINT, NULL, pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'PERCHADO continuation: % ejecuciones insertadas', v_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- CONTINUATION — COMPACTADO
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id  SMALLINT;
    v_count  INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'COMPACTADO';

    WITH
    eligible_raw AS (
        SELECT c.id, c.partida_id, c.fecha, c.hora_inicio, c.hora_fin,
               c.rollos, c.rib, c.maquina_id
        FROM public.compactado c
        JOIN mes.partida p ON p.id = c.partida_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              WHERE pp.partida_id = c.partida_id AND pp.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT *, LAG(fecha) OVER w AS prev_fecha, LAG(hora_fin) OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE
                WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
                     AND prev_hora_fin > '22:00'::time
                THEN 0 ELSE 1
            END AS new_group_flag
        FROM annotated
    ),
    run_groups AS (
        SELECT *, SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group FROM grouped
    ),
    runs AS (
        SELECT partida_id, run_group,
               MIN(id) AS anchor_id, MIN(fecha) AS fecha_inicio, MAX(fecha) AS fecha_fin,
               MIN(hora_inicio) AS hora_inicio, MAX(hora_fin) AS hora_fin,
               SUM(rollos) AS rollos_total, SUM(COALESCE(rib, 0)) AS rib_total,
               MAX(maquina_id) AS maquina_id
        FROM run_groups GROUP BY partida_id, run_group
    ),
    filtered_runs AS (
        SELECT r.* FROM runs r
        WHERE NOT EXISTS (
            SELECT 1
            FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
            WHERE pp.partida_id = r.partida_id AND pp.operacion_id = v_op_id
              AND pe.fyh_inicio = ((r.fecha_inicio + COALESCE(r.hora_inicio, '06:00'::time))::TIMESTAMP
                                    + INTERVAL '5 hours')::TIMESTAMPTZ
        )
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM filtered_runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT r.*,
               r.rollos_total + r.rib_total AS cantidad_total,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM filtered_runs r
        LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT rk.partida_id, rk.secuencia, v_op_id, rk.maquina_id,
               'COMPLETADO'::partida_paso_estado_enum, NULL,
               ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                   + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, usr_cre, fyh_cre
    )
    SELECT pi.paso_id, 'COMPLETADO', rk.maquina_id, pi.fyh_inicio_paso,
           CASE WHEN rk.hora_fin IS NOT NULL
                THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                ELSE NULL END,
           rk.cantidad_total::NUMERIC, NULL, pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'COMPACTADO continuation: % ejecuciones insertadas', v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 5 — REWORK REASSIGNMENT
-- Rework partidas (partida_origen_id IS NOT NULL) were created by
-- 11_data_migration.sql with their own TENIDO paso. That paso's fyh_cre is the
-- cutoff: any finishing op row with fecha >= cutoff_date was part of the rework
-- cycle and belongs on the rework partida, not the original.
--
-- Steps:
--   1. DRY RUN — show pasos currently misassigned on original partidas
--   2. DELETE those pasos + ejecuciones from original partidas
--   3. Re-migrate each operation targeting the rework partida_id
-- ═══════════════════════════════════════════════════════════════════════════════

SELECT
    rp.id                                                   AS rework_partida_id,
    rp.partida_origen_id                                    AS original_partida_id,
    (pp_ten.fyh_cre - INTERVAL '5 hours')::date             AS rework_cutoff_date,
    o.codigo                                                AS operacion,
    COUNT(pp.id)                                            AS pasos_a_reasignar
FROM mes.partida rp
JOIN mes.partida_paso pp_ten ON pp_ten.partida_id = rp.id
JOIN mes.operacion o_ten     ON o_ten.id = pp_ten.operacion_id AND o_ten.codigo = 'TENIDO'
JOIN mes.partida_paso pp     ON pp.partida_id = rp.partida_origen_id
JOIN mes.operacion o         ON o.id = pp.operacion_id
WHERE rp.partida_origen_id IS NOT NULL
  AND o.codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
  AND pp.fyh_cre >= pp_ten.fyh_cre
GROUP BY rp.id, rp.partida_origen_id, pp_ten.fyh_cre, o.codigo
ORDER BY rp.id, o.codigo;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: delete misassigned finishing op pasos from original partidas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_count INT;
BEGIN
    WITH rework_cutoffs AS (
        SELECT rp.partida_origen_id AS original_id, MIN(pp.fyh_cre) AS cutoff
        FROM mes.partida rp
        JOIN mes.partida_paso pp ON pp.partida_id = rp.id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE rp.partida_origen_id IS NOT NULL AND o.codigo = 'TENIDO'
        GROUP BY rp.partida_origen_id
    ),
    bad_pasos AS (
        SELECT pp.id
        FROM rework_cutoffs rc
        JOIN mes.partida_paso pp ON pp.partida_id = rc.original_id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE o.codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
          AND pp.fyh_cre >= rc.cutoff
    )
    DELETE FROM mes.partida_paso_ejecucion
    WHERE partida_paso_id IN (SELECT id FROM bad_pasos);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Rework cleanup: % ejecuciones eliminadas de partidas originales', v_count;

    WITH rework_cutoffs AS (
        SELECT rp.partida_origen_id AS original_id, MIN(pp.fyh_cre) AS cutoff
        FROM mes.partida rp
        JOIN mes.partida_paso pp ON pp.partida_id = rp.id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE rp.partida_origen_id IS NOT NULL AND o.codigo = 'TENIDO'
        GROUP BY rp.partida_origen_id
    ),
    bad_pasos AS (
        SELECT pp.id
        FROM rework_cutoffs rc
        JOIN mes.partida_paso pp ON pp.partida_id = rc.original_id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE o.codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
          AND pp.fyh_cre >= rc.cutoff
    )
    DELETE FROM mes.partida_paso WHERE id IN (SELECT id FROM bad_pasos);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Rework cleanup: % pasos eliminados de partidas originales', v_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: re-migrate TERMOFIJADO under rework partidas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id SMALLINT;
    v_count INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'TERMOFIJADO';

    WITH
    rework_map AS (
        SELECT rp.id AS rework_id, rp.partida_origen_id AS orig_id,
               MIN(pp.fyh_cre) AS cutoff
        FROM mes.partida rp
        JOIN mes.partida_paso pp ON pp.partida_id = rp.id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE rp.partida_origen_id IS NOT NULL AND o.codigo = 'TENIDO'
        GROUP BY rp.id, rp.partida_origen_id
    ),
    eligible_raw AS (
        SELECT t.id,
               rm.rework_id AS partida_id,
               t.fecha, t.hora_inicio, t.hora_fin, t.rollos
        FROM public.termofijado t
        JOIN rework_map rm ON rm.orig_id = t.partida_id
        JOIN mes.partida p  ON p.id = rm.rework_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND t.fecha >= (rm.cutoff - INTERVAL '5 hours')::date
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_paso pp2
              WHERE pp2.partida_id = rm.rework_id AND pp2.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT *, LAG(fecha) OVER w AS prev_fecha, LAG(hora_fin) OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
                      AND prev_hora_fin > '22:00'::time THEN 0 ELSE 1
            END AS new_group_flag FROM annotated
    ),
    run_groups AS (
        SELECT *, SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group FROM grouped
    ),
    runs AS (
        SELECT partida_id, run_group,
               MIN(id) AS anchor_id, MIN(fecha) AS fecha_inicio, MAX(fecha) AS fecha_fin,
               MIN(hora_inicio) AS hora_inicio, MAX(hora_fin) AS hora_fin,
               SUM(rollos) AS rollos_total
        FROM run_groups GROUP BY partida_id, run_group
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT r.*,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM runs r LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT rk.partida_id, rk.secuencia, v_op_id, NULL,
               'COMPLETADO'::partida_paso_estado_enum, NULL,
               ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                   + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, usr_cre, fyh_cre
    )
    SELECT pi.paso_id, 'COMPLETADO', NULL, pi.fyh_inicio_paso,
           CASE WHEN rk.hora_fin IS NOT NULL
                THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                ELSE NULL END,
           rk.rollos_total::NUMERIC, NULL, pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'TERMOFIJADO rework: % ejecuciones insertadas', v_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: re-migrate PERCHADO under rework partidas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id SMALLINT;
    v_count INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'PERCHADO';

    WITH
    rework_map AS (
        SELECT rp.id AS rework_id, rp.partida_origen_id AS orig_id,
               MIN(pp.fyh_cre) AS cutoff
        FROM mes.partida rp
        JOIN mes.partida_paso pp ON pp.partida_id = rp.id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE rp.partida_origen_id IS NOT NULL AND o.codigo = 'TENIDO'
        GROUP BY rp.id, rp.partida_origen_id
    ),
    eligible_raw AS (
        SELECT ph.id,
               rm.rework_id AS partida_id,
               ph.fecha, ph.hora_inicio, ph.hora_fin, ph.rollos, ph.pases
        FROM public.perchado ph
        JOIN rework_map rm ON rm.orig_id = ph.partida_id
        JOIN mes.partida p  ON p.id = rm.rework_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND ph.fecha >= (rm.cutoff - INTERVAL '5 hours')::date
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_paso pp2
              WHERE pp2.partida_id = rm.rework_id AND pp2.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT *, LAG(fecha) OVER w AS prev_fecha, LAG(hora_fin) OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
                      AND prev_hora_fin > '22:00'::time THEN 0 ELSE 1
            END AS new_group_flag FROM annotated
    ),
    run_groups AS (
        SELECT *, SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group FROM grouped
    ),
    runs AS (
        SELECT partida_id, run_group,
               MIN(id) AS anchor_id, MIN(fecha) AS fecha_inicio, MAX(fecha) AS fecha_fin,
               MIN(hora_inicio) AS hora_inicio, MAX(hora_fin) AS hora_fin,
               SUM(rollos) AS rollos_total, MAX(pases) AS pases
        FROM run_groups GROUP BY partida_id, run_group
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT r.*,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM runs r LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT rk.partida_id, rk.secuencia, v_op_id, NULL,
               'COMPLETADO'::partida_paso_estado_enum, NULL,
               ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                   + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, pases, usr_cre, fyh_cre
    )
    SELECT pi.paso_id, 'COMPLETADO', NULL, pi.fyh_inicio_paso,
           CASE WHEN rk.hora_fin IS NOT NULL
                THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                ELSE NULL END,
           rk.rollos_total::NUMERIC, rk.pases::SMALLINT, NULL, pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'PERCHADO rework: % ejecuciones insertadas', v_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: re-migrate COMPACTADO under rework partidas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_op_id SMALLINT;
    v_count INT;
BEGIN
    SELECT id INTO STRICT v_op_id FROM mes.operacion WHERE codigo = 'COMPACTADO';

    WITH
    rework_map AS (
        SELECT rp.id AS rework_id, rp.partida_origen_id AS orig_id,
               MIN(pp.fyh_cre) AS cutoff
        FROM mes.partida rp
        JOIN mes.partida_paso pp ON pp.partida_id = rp.id
        JOIN mes.operacion o     ON o.id = pp.operacion_id
        WHERE rp.partida_origen_id IS NOT NULL AND o.codigo = 'TENIDO'
        GROUP BY rp.id, rp.partida_origen_id
    ),
    eligible_raw AS (
        SELECT c.id,
               rm.rework_id AS partida_id,
               c.fecha, c.hora_inicio, c.hora_fin, c.rollos, c.rib, c.maquina_id
        FROM public.compactado c
        JOIN rework_map rm ON rm.orig_id = c.partida_id
        JOIN mes.partida p  ON p.id = rm.rework_id
        WHERE p.estado_produccion != 'CANCELADA'
          AND c.fecha >= (rm.cutoff - INTERVAL '5 hours')::date
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_paso pp2
              WHERE pp2.partida_id = rm.rework_id AND pp2.operacion_id = v_op_id
          )
    ),
    annotated AS (
        SELECT *, LAG(fecha) OVER w AS prev_fecha, LAG(hora_fin) OVER w AS prev_hora_fin
        FROM eligible_raw
        WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id)
    ),
    grouped AS (
        SELECT *,
            CASE WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
                      AND prev_hora_fin > '22:00'::time THEN 0 ELSE 1
            END AS new_group_flag FROM annotated
    ),
    run_groups AS (
        SELECT *, SUM(new_group_flag) OVER (
            PARTITION BY partida_id ORDER BY fecha, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group FROM grouped
    ),
    runs AS (
        SELECT partida_id, run_group,
               MIN(id) AS anchor_id, MIN(fecha) AS fecha_inicio, MAX(fecha) AS fecha_fin,
               MIN(hora_inicio) AS hora_inicio, MAX(hora_fin) AS hora_fin,
               SUM(rollos) AS rollos_total, SUM(COALESCE(rib, 0)) AS rib_total,
               MAX(maquina_id) AS maquina_id
        FROM run_groups GROUP BY partida_id, run_group
    ),
    seq_base AS (
        SELECT partida_id, MAX(secuencia) AS max_seq FROM mes.partida_paso
        WHERE partida_id IN (SELECT DISTINCT partida_id FROM runs)
        GROUP BY partida_id
    ),
    ranked AS (
        SELECT r.*, r.rollos_total + r.rib_total AS cantidad_total,
            (COALESCE(sb.max_seq, 0)
                + ROW_NUMBER() OVER (PARTITION BY r.partida_id ORDER BY r.fecha_inicio, r.anchor_id)
            )::SMALLINT AS secuencia
        FROM runs r LEFT JOIN seq_base sb ON sb.partida_id = r.partida_id
    ),
    paso_insert AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT rk.partida_id, rk.secuencia, v_op_id, rk.maquina_id,
               'COMPLETADO'::partida_paso_estado_enum, NULL,
               ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                   + INTERVAL '5 hours')::TIMESTAMPTZ
        FROM ranked rk
        ON CONFLICT (partida_id, secuencia) DO NOTHING
        RETURNING id AS paso_id, partida_id, fyh_cre AS fyh_inicio_paso
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, usr_cre, fyh_cre
    )
    SELECT pi.paso_id, 'COMPLETADO', rk.maquina_id, pi.fyh_inicio_paso,
           CASE WHEN rk.hora_fin IS NOT NULL
                THEN ((rk.fecha_fin + rk.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
                ELSE NULL END,
           rk.cantidad_total::NUMERIC, NULL, pi.fyh_inicio_paso
    FROM paso_insert pi
    JOIN ranked rk
        ON  rk.partida_id = pi.partida_id
        AND ((rk.fecha_inicio + COALESCE(rk.hora_inicio, '06:00'::time))::TIMESTAMP
                + INTERVAL '5 hours')::TIMESTAMPTZ = pi.fyh_inicio_paso;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'COMPACTADO rework: % ejecuciones insertadas', v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- POST-MIGRATION VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

SELECT
    o.codigo,
    COUNT(pp.id)                                                            AS pasos_total,
    COUNT(pe.id)                                                            AS ejecuciones,
    COUNT(pe.id) FILTER (WHERE pe.estado  = 'COMPLETADO')                  AS completados,
    COUNT(pp.id) FILTER (WHERE pp.estado  = 'COMPLETADO')                  AS pasos_completados,
    COUNT(pe.id) FILTER (WHERE pe.fyh_fin IS NULL)                         AS sin_fyh_fin
FROM mes.operacion o
JOIN mes.partida_paso pp ON pp.operacion_id = o.id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE o.codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
GROUP BY o.codigo
ORDER BY o.codigo;

SELECT
    'termofijado'  AS fuente,
    COUNT(*) FILTER (WHERE partida_id IN (
        SELECT id FROM mes.partida WHERE estado_produccion != 'CANCELADA'
    ))             AS total_elegible_en_fuente,
    (SELECT COUNT(*) FROM mes.partida_paso pp
     JOIN mes.operacion o ON o.id = pp.operacion_id
     WHERE o.codigo = 'TERMOFIJADO')  AS pasos_migrados
FROM public.termofijado
UNION ALL
SELECT
    'perchado',
    COUNT(*) FILTER (WHERE partida_id IN (
        SELECT id FROM mes.partida WHERE estado_produccion != 'CANCELADA'
    )),
    (SELECT COUNT(*) FROM mes.partida_paso pp
     JOIN mes.operacion o ON o.id = pp.operacion_id
     WHERE o.codigo = 'PERCHADO')
FROM public.perchado
UNION ALL
SELECT
    'compactado',
    COUNT(*) FILTER (WHERE partida_id IN (
        SELECT id FROM mes.partida WHERE estado_produccion != 'CANCELADA'
    )),
    (SELECT COUNT(*) FROM mes.partida_paso pp
     JOIN mes.operacion o ON o.id = pp.operacion_id
     WHERE o.codigo = 'COMPACTADO')
FROM public.compactado;

SELECT pp.id, pp.partida_id, pp.secuencia, o.codigo
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE o.codigo IN ('TERMOFIJADO', 'PERCHADO', 'COMPACTADO')
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id
  )
ORDER BY pp.partida_id, pp.secuencia
LIMIT 20;


SELECT * FROM mes.maquina WHERE codigo ILIKE '%perch%'
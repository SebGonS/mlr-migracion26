-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY REBUILD: per-partida finishing TIMELINE → mes.partida_paso + ejecucion
--
-- SUPERSEDES 06_migrar_despachos_y_produccion.sql.
--   The old script assigned secuencia by FIXED operation order — it ran a
--   TERMOFIJADO block, then a PERCHADO block, then a COMPACTADO block, each
--   appending after the previous max. Result: secuencia encoded the *order the
--   sections ran*, not the order the operations actually happened. It also routed
--   reworks with a single ">= cutoff" rule that breaks for >1 rework per partida.
--
-- WHAT THIS REBUILD DOES DIFFERENTLY
--   1. Reconstructs ONE chronological timeline per partida by UNION-ing all legacy
--      finishing events (perchado, termofijado, compactado) — plus auditoria and
--      despacho markers — ordered by their real timestamp.
--   2. Routes each event to the correct mes.partida (original vs rework child) by
--      the dyeing CYCLE it falls into. Reworks are separate partidas; the cycle a
--      finishing event belongs to is the dyeing run whose start time most recently
--      precedes it. Handles any number of reworks per partida.
--   3. Derives secuencia from chronological position within the TARGET partida,
--      continuing after the already-migrated non-finishing pasos (TENIDO, etc.).
--
-- SOURCES (read from legacy_schema/schema.sql shapes):
--   public.perchado     (id, partida_id, fecha, hora_inicio, hora_fin, rollos, pases)
--   public.termofijado  (id, partida_id, fecha, hora_inicio, hora_fin, rollos)     rollos incl. rib
--   public.compactado   (id, partida_id, fecha, hora_inicio, hora_fin, rollos, rib, maquina_id)
--   public.auditoria    (id, partida_id, fecha_auditoria, estado)        date only — MARKER
--   public.despacho     (id, partida_id, fecha_despacho, rollos, rib, nfactura)   date only — MARKER
--
-- EXCLUDED: public.produccion_tenido.
--   TENIDO was already migrated by 11_data_migration.sql (originals = pasos with
--   id = pt.id; reworks = separate partidas). We read those existing TENIDO pasos
--   ONLY as cycle anchors for routing — we never read produccion_tenido here and
--   never touch TENIDO rows. (Per request: excluded to avoid noise.)
--
-- AUDITORIA / DESPACHO: there is NO mes.operacion for these — they belong to the
--   calidad / doc layers, not the production route. They appear in SECTION 0 for
--   timeline context (and as natural upper bounds on a cycle), but are NEVER
--   inserted as partida_paso rows here.
--
-- TARGET TABLES:
--   mes.partida_paso            (estado added by migration 19; pases lives on ejecucion)
--   mes.partida_paso_ejecucion  (pases column added by migration 18)
--
-- NO inventory side-effects: registrar_produccion (PROD_CONSUMO/PROD_ING) is only
--   for TENIDO. Finishing pasos record timing/machine/qty only.
--
-- TIMEZONE: legacy stored local Peru time (UTC-5). All timestamps = local + 5h,
--   consistent with 11_data_migration and the rest of the codebase.
--
-- MIDNIGHT-SPLIT ("juntar cuando se pasa de las 12"): the legacy app wrote two
--   rows when a run crossed midnight. Adjacent rows (same partida + same op,
--   date+1, prev hora_fin > 22:00) are collapsed into one run:
--   first hora_inicio … last hora_fin, summed rollos.
--
-- SAFETY — DO NOT BLANKET-DELETE: the May–Jun 2026 finishing data
--   (insert_compactado_perchado_may2026.sql, from mersan/sertks sheets + hardcoded
--   perchado) is NOT in these legacy tables. The rebuild in SECTION 2 is scoped to
--   the "legacy universe" only (partidas that actually appear in the three legacy
--   tables, plus their rework children), so patch data survives.
--
-- HOW TO RUN: sections in order, same session.
--   SECTION 0 — read-only timeline (eyeball the reconstruction).
--   SECTION 1 — builds TEMP table tmp_acabados_corr and previews the proposed rows
--               (NO writes). Review this before SECTION 2.
--   SECTION 2 — scoped delete of legacy-era finishing pasos + insert from temp.
--   SECTION 3 — post-rebuild validation.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — TIMELINE RECONSTRUCTION  (read-only)
--
-- One unified, chronologically-ordered event stream per legacy partida. Shows
-- where every finishing event, audit and dispatch sits relative to the dyeing
-- runs, and which mes.partida (original or rework child) each finishing event
-- would route to. Markers (TENIDO/AUDITORIA/DESPACHO) are shown for context.
-- ═══════════════════════════════════════════════════════════════════════════════
WITH
-- ── Cycle targets: every (legacy_partida_id → target mes.partida, cycle_start) ──
--   Original partida: cycle_start = earliest TENIDO paso (fallback partida.fyh_inicio).
--   Each rework child: cycle_start = its own dyeing start (partida.fyh_cre).
cycle_targets AS (
    SELECT
        mp.id AS legacy_partida_id,
        mp.id AS target_partida_id,
        false AS es_reproceso,
        COALESCE(
            (SELECT MIN(pp.fyh_cre)
               FROM mes.partida_paso pp
               JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
              WHERE pp.partida_id = mp.id),
            mp.fyh_inicio, mp.fyh_cre
        ) AS cycle_start
    FROM mes.partida mp
    WHERE mp.partida_origen_id IS NULL
    UNION ALL
    SELECT
        rp.partida_origen_id,
        rp.id,
        true,
        rp.fyh_cre
    FROM mes.partida rp
    WHERE rp.partida_origen_id IS NOT NULL
),
-- ── Raw finishing events, normalized across the three tables ──────────────────
raw_events AS (
    SELECT 'PERCHADO'::text AS op, ph.id AS src_id, ph.partida_id, ph.fecha,
           ph.hora_inicio, ph.hora_fin,
           ph.rollos::numeric AS cantidad, ph.pases::smallint AS pases, NULL::int AS maquina_id
    FROM public.perchado ph
    UNION ALL
    SELECT 'TERMOFIJADO', t.id, t.partida_id, t.fecha,
           t.hora_inicio, t.hora_fin,
           t.rollos::numeric, NULL::smallint, NULL::int
    FROM public.termofijado t
    UNION ALL
    SELECT 'COMPACTADO', c.id, c.partida_id, c.fecha,
           c.hora_inicio, c.hora_fin,
           (c.rollos + COALESCE(c.rib, 0))::numeric, NULL::smallint, c.maquina_id
    FROM public.compactado c
),
-- ── Midnight-split merge, partitioned per (partida, op) ───────────────────────
annotated AS (
    SELECT *,
           LAG(fecha)    OVER w AS prev_fecha,
           LAG(hora_fin) OVER w AS prev_hora_fin
    FROM raw_events
    WINDOW w AS (PARTITION BY partida_id, op ORDER BY fecha, src_id)
),
grouped AS (
    SELECT *,
        CASE WHEN prev_fecha IS NOT NULL
              AND fecha = prev_fecha + 1
              AND prev_hora_fin > '22:00'::time
             THEN 0 ELSE 1 END AS new_group_flag
    FROM annotated
),
run_groups AS (
    SELECT *,
        SUM(new_group_flag) OVER (
            PARTITION BY partida_id, op ORDER BY fecha, src_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group
    FROM grouped
),
merged_events AS (
    SELECT
        partida_id AS legacy_partida_id,
        op AS operacion_codigo,
        MIN(src_id)      AS anchor_src_id,
        MIN(fecha)       AS fecha_inicio,
        MAX(fecha)       AS fecha_fin,
        MIN(hora_inicio) AS hora_inicio,
        MAX(hora_fin)    AS hora_fin,
        SUM(cantidad)    AS cantidad,
        MAX(pases)       AS pases,
        MAX(maquina_id)  AS maquina_id,
        COUNT(*)         AS n_merged
    FROM run_groups
    GROUP BY partida_id, op, run_group
),
-- ── All timeline events (finishing + markers + tenido anchors) ────────────────
events AS (
    -- finishing events
    SELECT
        me.legacy_partida_id,
        me.operacion_codigo,
        'legacy_'||lower(me.operacion_codigo) AS origen,
        ((me.fecha_inicio + COALESCE(me.hora_inicio, '06:00'::time))::timestamp
            + INTERVAL '5 hours')::timestamptz AS fyh_inicio,
        CASE WHEN me.hora_fin IS NOT NULL
             THEN ((me.fecha_fin + me.hora_fin)::timestamp + INTERVAL '5 hours')::timestamptz
        END AS fyh_fin,
        me.cantidad, me.pases, me.maquina_id, me.n_merged,
        NULL::text AS nota
    FROM merged_events me

    UNION ALL
    -- existing TENIDO pasos (anchors, read from new schema — NOT produccion_tenido)
    SELECT
        CASE WHEN mp.partida_origen_id IS NULL THEN mp.id ELSE mp.partida_origen_id END,
        'TENIDO',
        CASE WHEN mp.partida_origen_id IS NULL THEN 'mes_tenido' ELSE 'mes_tenido_reproceso' END,
        COALESCE(pe.fyh_inicio, pp.fyh_cre),
        pe.fyh_fin,
        pe.cantidad, NULL, pe.maquina_id, 1,
        'partida='||mp.id::text||CASE WHEN mp.partida_origen_id IS NOT NULL
                                      THEN ' (reproceso de '||mp.partida_origen_id||')' ELSE '' END
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
    JOIN mes.partida mp  ON mp.id = pp.partida_id
    LEFT JOIN LATERAL (
        SELECT * FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id
        ORDER BY pe.fyh_inicio LIMIT 1
    ) pe ON true

    UNION ALL
    -- auditoria markers (date only → 20:00 local so it sorts after same-day prod)
    SELECT a.partida_id, 'AUDITORIA', 'legacy_auditoria',
           ((a.fecha_auditoria + '20:00'::time)::timestamp + INTERVAL '5 hours')::timestamptz,
           NULL, NULL, NULL, NULL, 1,
           'estado='||COALESCE(a.estado,'(null)')
    FROM public.auditoria a
    WHERE a.fecha_auditoria IS NOT NULL

    UNION ALL
    -- despacho markers (date only → 23:00 local)
    SELECT d.partida_id, 'DESPACHO', 'legacy_despacho',
           ((d.fecha_despacho + '23:00'::time)::timestamp + INTERVAL '5 hours')::timestamptz,
           NULL, (d.rollos + COALESCE(d.rib,0))::numeric, NULL, NULL, 1,
           'nfactura='||COALESCE(d.nfactura,'(s/f)')
    FROM public.despacho d
    WHERE d.flg_elm = false AND d.fecha_despacho IS NOT NULL
)
SELECT
    e.legacy_partida_id,
    ROW_NUMBER() OVER (PARTITION BY e.legacy_partida_id ORDER BY e.fyh_inicio, e.operacion_codigo) AS orden,
    e.operacion_codigo,
    e.origen,
    -- routed target (NULL for markers / tenido which carry their own partida in nota)
    CASE WHEN e.operacion_codigo IN ('PERCHADO','TERMOFIJADO','COMPACTADO')
         THEN route.target_partida_id END AS target_partida_id,
    CASE WHEN e.operacion_codigo IN ('PERCHADO','TERMOFIJADO','COMPACTADO')
         THEN route.es_reproceso END AS routed_a_reproceso,
    e.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local,
    e.fyh_fin    AT TIME ZONE 'America/Lima' AS fin_local,
    e.cantidad,
    e.pases,
    e.maquina_id,
    NULLIF(e.n_merged, 1) AS rows_unidas_medianoche,
    e.nota
FROM events e
LEFT JOIN LATERAL (
    SELECT ct.target_partida_id, ct.es_reproceso
    FROM cycle_targets ct
    WHERE ct.legacy_partida_id = e.legacy_partida_id
      AND ct.cycle_start <= e.fyh_inicio
    ORDER BY ct.cycle_start DESC
    LIMIT 1
) route ON e.operacion_codigo IN ('PERCHADO','TERMOFIJADO','COMPACTADO')
ORDER BY e.legacy_partida_id, e.fyh_inicio, e.operacion_codigo;



-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — BUILD CORRECTED ROWS  (TEMP table + preview, NO writes)
--
-- Produces tmp_acabados_corr: exactly the partida_paso rows that SHOULD exist for
-- the legacy finishing operations, with:
--   * target_partida_id  — routed by dyeing cycle (original vs rework child)
--   * secuencia          — chronological rank within the target, AFTER non-finishing
--                          pasos. Computed from a base that EXCLUDES finishing ops,
--                          so it is identical whether or not SECTION 2 has deleted
--                          the old finishing pasos yet (stable preview ↔ apply).
--   * fyh_inicio/fin, cantidad, pases, maquina_id
--
-- Review the preview SELECT before running SECTION 2.
-- ═══════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS tmp_acabados_corr;

CREATE TEMP TABLE tmp_acabados_corr AS
WITH
cycle_targets AS (
    SELECT mp.id AS legacy_partida_id, mp.id AS target_partida_id,
        COALESCE(
            (SELECT MIN(pp.fyh_cre) FROM mes.partida_paso pp
               JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo = 'TENIDO'
              WHERE pp.partida_id = mp.id),
            mp.fyh_inicio, mp.fyh_cre) AS cycle_start
    FROM mes.partida mp
    WHERE mp.partida_origen_id IS NULL
    UNION ALL
    SELECT rp.partida_origen_id, rp.id, rp.fyh_cre
    FROM mes.partida rp
    WHERE rp.partida_origen_id IS NOT NULL
),
raw_events AS (
    SELECT 'PERCHADO'::text AS op, ph.id AS src_id, ph.partida_id, ph.fecha,
           ph.hora_inicio, ph.hora_fin,
           ph.rollos::numeric AS cantidad, ph.pases::smallint AS pases, NULL::int AS maquina_id
    FROM public.perchado ph
    UNION ALL
    SELECT 'TERMOFIJADO', t.id, t.partida_id, t.fecha, t.hora_inicio, t.hora_fin,
           t.rollos::numeric, NULL::smallint, NULL::int
    FROM public.termofijado t
    UNION ALL
    SELECT 'COMPACTADO', c.id, c.partida_id, c.fecha, c.hora_inicio, c.hora_fin,
           (c.rollos + COALESCE(c.rib, 0))::numeric, NULL::smallint, c.maquina_id
    FROM public.compactado c
),
annotated AS (
    SELECT *,
           LAG(fecha)    OVER w AS prev_fecha,
           LAG(hora_fin) OVER w AS prev_hora_fin
    FROM raw_events
    WINDOW w AS (PARTITION BY partida_id, op ORDER BY fecha, src_id)
),
grouped AS (
    SELECT *,
        CASE WHEN prev_fecha IS NOT NULL AND fecha = prev_fecha + 1
              AND prev_hora_fin > '22:00'::time THEN 0 ELSE 1 END AS new_group_flag
    FROM annotated
),
run_groups AS (
    SELECT *,
        SUM(new_group_flag) OVER (
            PARTITION BY partida_id, op ORDER BY fecha, src_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS run_group
    FROM grouped
),
merged_events AS (
    SELECT
        partida_id AS legacy_partida_id, op AS operacion_codigo,
        MIN(src_id)      AS anchor_src_id,
        MIN(fecha)       AS fecha_inicio, MAX(fecha) AS fecha_fin,
        MIN(hora_inicio) AS hora_inicio,  MAX(hora_fin) AS hora_fin,
        SUM(cantidad)    AS cantidad, MAX(pases) AS pases, MAX(maquina_id) AS maquina_id
    FROM run_groups
    GROUP BY partida_id, op, run_group
),
events_ts AS (
    SELECT
        me.*,
        ((me.fecha_inicio + COALESCE(me.hora_inicio, '06:00'::time))::timestamp
            + INTERVAL '5 hours')::timestamptz AS fyh_inicio,
        CASE WHEN me.hora_fin IS NOT NULL
             THEN ((me.fecha_fin + me.hora_fin)::timestamp + INTERVAL '5 hours')::timestamptz
        END AS fyh_fin
    FROM merged_events me
),
-- route each event to the cycle whose start most recently precedes it
routed AS (
    SELECT
        e.*,
        COALESCE(route.target_partida_id, fallback.target_partida_id) AS target_partida_id
    FROM events_ts e
    LEFT JOIN LATERAL (
        SELECT ct.target_partida_id
        FROM cycle_targets ct
        WHERE ct.legacy_partida_id = e.legacy_partida_id
          AND ct.cycle_start <= e.fyh_inicio
        ORDER BY ct.cycle_start DESC LIMIT 1
    ) route ON true
    -- fallback (event predates every recorded dyeing run): earliest cycle = original
    LEFT JOIN LATERAL (
        SELECT ct.target_partida_id
        FROM cycle_targets ct
        WHERE ct.legacy_partida_id = e.legacy_partida_id
        ORDER BY ct.cycle_start ASC LIMIT 1
    ) fallback ON true
),
-- secuencia base: max secuencia of NON-finishing pasos on the target (stable
-- across SECTION 2's delete, which only removes finishing pasos)
seq_base AS (
    SELECT pp.partida_id, MAX(pp.secuencia) AS max_seq
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    WHERE o.codigo NOT IN ('TERMOFIJADO','PERCHADO','COMPACTADO')
    GROUP BY pp.partida_id
)
SELECT
    r.target_partida_id,
    (COALESCE(sb.max_seq, 0)
        + ROW_NUMBER() OVER (PARTITION BY r.target_partida_id
                             ORDER BY r.fyh_inicio, r.anchor_src_id)
    )::smallint AS secuencia,
    r.operacion_codigo,
    op.id        AS operacion_id,
    r.legacy_partida_id,
    r.anchor_src_id,
    r.fyh_inicio,
    r.fyh_fin,
    r.cantidad,
    r.pases,
    -- only set maquina if it actually exists in mes.maquina (avoid FK violation)
    (SELECT m.id FROM mes.maquina m WHERE m.id = r.maquina_id) AS maquina_id
FROM routed r
JOIN mes.operacion op ON op.codigo = r.operacion_codigo
JOIN mes.partida tgt  ON tgt.id = r.target_partida_id
                     AND tgt.estado_produccion != 'CANCELADA'
LEFT JOIN seq_base sb ON sb.partida_id = r.target_partida_id;

-- ── Preview 1: full proposed row set ────────────────────────────────────────────
SELECT
    c.target_partida_id,
    c.secuencia,
    c.operacion_codigo,
    c.legacy_partida_id,
    (c.legacy_partida_id <> c.target_partida_id) AS ruteado_a_reproceso,
    c.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local,
    c.fyh_fin    AT TIME ZONE 'America/Lima' AS fin_local,
    c.cantidad, c.pases, c.maquina_id, c.anchor_src_id
FROM tmp_acabados_corr c
ORDER BY c.target_partida_id, c.secuencia;

-- ── Preview 2: counts by operation + how many got routed to a rework child ──────
SELECT
    operacion_codigo,
    COUNT(*)                                                       AS pasos_propuestos,
    COUNT(*) FILTER (WHERE legacy_partida_id <> target_partida_id) AS ruteados_a_reproceso,
    COUNT(*) FILTER (WHERE maquina_id IS NOT NULL)                 AS con_maquina
FROM tmp_acabados_corr
GROUP BY operacion_codigo
ORDER BY operacion_codigo;

-- ── Preview 3: SAFETY — partidas in legacy tables that ALSO carry patch-era
--    finishing data (May/Jun 2026). If any appear, SECTION 2's scoped delete would
--    remove that patch data too — inspect before proceeding. Expected: 0 rows.
SELECT DISTINCT pp.partida_id, o.codigo AS operacion, pe.fyh_inicio AT TIME ZONE 'America/Lima' AS inicio_local
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id AND o.codigo IN ('PERCHADO','TERMOFIJADO','COMPACTADO')
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE pe.fyh_inicio >= '2026-05-01'
  AND pp.partida_id IN (
        SELECT id FROM mes.partida
        WHERE id            IN (SELECT partida_id FROM public.perchado    UNION
                                SELECT partida_id FROM public.termofijado UNION
                                SELECT partida_id FROM public.compactado)
           OR partida_origen_id IN (SELECT partida_id FROM public.perchado    UNION
                                    SELECT partida_id FROM public.termofijado UNION
                                    SELECT partida_id FROM public.compactado)
      )
ORDER BY pp.partida_id;



-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — REBUILD  (DESTRUCTIVE — review SECTION 1 first)
--
-- Scope = the "legacy universe": every mes.partida that appears in the three legacy
-- finishing tables, plus its rework children. Patch-only partidas (not in legacy
-- tables) are untouched.
--
-- Step 1: delete existing finishing pasos (+ ejecuciones) for scope partidas.
--         Finishing ejecuciones have no inventory rows and no chemical componente
--         rows, so this is safe (only TENIDO carries those).
-- Step 2: insert the corrected pasos from tmp_acabados_corr, then their ejecuciones
--         (1:1 via the unique (partida_id, secuencia)).
--
-- REVERSAL: re-run SECTION 2 — it is fully idempotent (delete-then-insert over the
--   same deterministic temp set). To undo entirely, run the DELETE in step 1 alone.
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_del_ejec  INT;
    v_del_paso  INT;
    v_ins_paso  INT;
    v_ins_ejec  INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tmp_acabados_corr) THEN
        RAISE EXCEPTION 'tmp_acabados_corr está vacía — corré SECTION 1 antes de SECTION 2.';
    END IF;

    -- ── Step 1: scoped delete ─────────────────────────────────────────────────
    CREATE TEMP TABLE tmp_scope_partidas ON COMMIT DROP AS
    SELECT DISTINCT p.id
    FROM mes.partida p
    WHERE p.id IN (SELECT partida_id FROM public.perchado    UNION
                   SELECT partida_id FROM public.termofijado UNION
                   SELECT partida_id FROM public.compactado)
       OR p.partida_origen_id IN (SELECT partida_id FROM public.perchado    UNION
                                  SELECT partida_id FROM public.termofijado UNION
                                  SELECT partida_id FROM public.compactado);

    WITH bad_pasos AS (
        SELECT pp.id
        FROM mes.partida_paso pp
        JOIN mes.operacion o ON o.id = pp.operacion_id
        WHERE o.codigo IN ('TERMOFIJADO','PERCHADO','COMPACTADO')
          AND pp.partida_id IN (SELECT id FROM tmp_scope_partidas)
    )
    DELETE FROM mes.partida_paso_ejecucion WHERE partida_paso_id IN (SELECT id FROM bad_pasos);
    GET DIAGNOSTICS v_del_ejec = ROW_COUNT;

    WITH bad_pasos AS (
        SELECT pp.id
        FROM mes.partida_paso pp
        JOIN mes.operacion o ON o.id = pp.operacion_id
        WHERE o.codigo IN ('TERMOFIJADO','PERCHADO','COMPACTADO')
          AND pp.partida_id IN (SELECT id FROM tmp_scope_partidas)
    )
    DELETE FROM mes.partida_paso WHERE id IN (SELECT id FROM bad_pasos);
    GET DIAGNOSTICS v_del_paso = ROW_COUNT;

    -- ── Step 2: insert corrected pasos, then ejecuciones ─────────────────────
    WITH ins AS (
        INSERT INTO mes.partida_paso (
            partida_id, secuencia, operacion_id, maquina_planificada_id,
            estado, usr_cre, fyh_cre
        )
        SELECT
            c.target_partida_id, c.secuencia, c.operacion_id, c.maquina_id,
            'COMPLETADO'::partida_paso_estado_enum, NULL, c.fyh_inicio
        FROM tmp_acabados_corr c
        RETURNING id AS paso_id, partida_id, secuencia
    )
    INSERT INTO mes.partida_paso_ejecucion (
        partida_paso_id, estado, maquina_id, fyh_inicio, fyh_fin,
        cantidad, pases, usr_cre, fyh_cre
    )
    SELECT
        ins.paso_id, 'COMPLETADO', c.maquina_id, c.fyh_inicio, c.fyh_fin,
        c.cantidad, c.pases, NULL, c.fyh_inicio
    FROM ins
    JOIN tmp_acabados_corr c
      ON c.target_partida_id = ins.partida_id
     AND c.secuencia         = ins.secuencia;
    GET DIAGNOSTICS v_ins_ejec = ROW_COUNT;

    SELECT COUNT(*) INTO v_ins_paso FROM tmp_acabados_corr;

    RAISE NOTICE '═══════════════ REBUILD ACABADOS ═══════════════';
    RAISE NOTICE '  ejecuciones eliminadas : %', v_del_ejec;
    RAISE NOTICE '  pasos eliminados       : %', v_del_paso;
    RAISE NOTICE '  pasos insertados       : %', v_ins_paso;
    RAISE NOTICE '  ejecuciones insertadas : %', v_ins_ejec;
    RAISE NOTICE '═════════════════════════════════════════════════';
END;
$$;



-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — POST-REBUILD VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- 3a. Counts: legacy rows (merged) vs migrated pasos, per operation.
SELECT
    op.codigo,
    (SELECT COUNT(*) FROM tmp_acabados_corr c WHERE c.operacion_codigo = op.codigo) AS esperados_temp,
    COUNT(pp.id)  AS pasos_actuales,
    COUNT(pe.id)  AS ejecuciones,
    COUNT(pe.id) FILTER (WHERE pe.fyh_fin IS NULL) AS sin_fyh_fin
FROM mes.operacion op
LEFT JOIN mes.partida_paso pp ON pp.operacion_id = op.id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE op.codigo IN ('TERMOFIJADO','PERCHADO','COMPACTADO')
GROUP BY op.codigo
ORDER BY op.codigo;

-- 3b. Sequence sanity: per partida, secuencias must be gap-free and finishing ops
--     must all sit AFTER the last non-finishing (TENIDO) paso. Lists violations.
WITH per_partida AS (
    SELECT
        pp.partida_id,
        MAX(pp.secuencia) FILTER (WHERE o.codigo NOT IN ('TERMOFIJADO','PERCHADO','COMPACTADO')) AS max_no_fin,
        MIN(pp.secuencia) FILTER (WHERE o.codigo IN ('TERMOFIJADO','PERCHADO','COMPACTADO'))     AS min_fin,
        COUNT(*) AS n_pasos,
        MAX(pp.secuencia) AS max_seq
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    GROUP BY pp.partida_id
)
SELECT *
FROM per_partida
WHERE (min_fin IS NOT NULL AND max_no_fin IS NOT NULL AND min_fin <= max_no_fin)  -- finishing before tenido
   OR (max_seq <> n_pasos)                                                        -- gap / non-contiguous
ORDER BY partida_id
LIMIT 50;

-- 3c. Any finishing paso left without an ejecucion (should be none).
SELECT pp.partida_id, pp.secuencia, o.codigo
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE o.codigo IN ('TERMOFIJADO','PERCHADO','COMPACTADO')
  AND NOT EXISTS (SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id)
ORDER BY pp.partida_id, pp.secuencia
LIMIT 50;

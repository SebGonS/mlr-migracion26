-- ============================================================================
-- 05 · Insert ejecuciones for the step-04 pasos               (paso-backfill step 05)
-- ============================================================================
-- WHAT: step 04 created empty pasos for the unmigrated runs (normal TENIDO +
--   PERCHADO). This step fills them: ONE ejecucion per run, grouping the runs the
--   same way step 03 did (estado-chain) so shift-split TENIDO runs collapse into
--   one ejecucion at insert time — including the run_ejec=0 splits (4773/4239/
--   4853/330) that couldn't be merged in step 03 because they had no ejecucion yet.
--
-- SCOPE DISCRIMINATOR: join staging → its paso via new_paso_id (INNER, so rows
--   pointing at a step-03-deleted rework-lead paso drop out), then keep only rows
--   whose (paso.partida_id, paso.operacion_id) group has ZERO ejecuciones. Every
--   MIGRATED group has ≥1 (migration-11 / the legacy finishing-migration script,
--   or the surviving completion after step 03); only step-04 groups have none. Keying on the PASO's partida (not
--   staging's) also excludes reworks — their pasos live under child partidas whose
--   group already has an ejecucion. (NB: usr_cre=4 is NOT reliable — pre-existing
--   pasos also carry it.) §0 previews the scope BEFORE §1 mutates.
--
-- RUN GROUPING: within (new_paso_id, legacy_maquina) ordered by time, a new run
--   starts at any row whose previous row is NOT a lead ('En Proceso Teñido').
--   PERCHADO rows have legacy_estado = NULL → every row is its own run (1:1).
--
-- MERGED VALUES: fyh_inicio = MIN(fyh_inicio) [lead's real start];
--   fyh_fin = MAX(fyh_fin) over the run EXCLUDING lead rows (completion's real end
--   for TENIDO, the row's own end for PERCHADO, NULL for an open TENIDO run → then
--   EN_PROCESO); rollos/kg = SUM; estado from fyh_fin. maquina_id = NULL (legacy
--   machine id is not mapped to mes.maquina here).
--   MIDNIGHT: a single-row run crossing 00:00 has hora_fin < hora_inicio under one
--   fecha → run_fin computes before run_inicio; §1a bumps it +1 day. NOTE the same
--   flaw pre-exists in migration-11 (single-row tenido) and the finishing migration
--   (their fyh_fin = fecha+hora_fin+5h ignores the crossing) — a global "+1 day
--   where fyh_fin < fyh_inicio" cleanup is a separate follow-up, not done here.
--
-- SKIP: the 3 app-duplicated open TENIDO runs (4153, 4410, 5199) — the new app
--   already recorded those post-go-live. Their staging rows keep new_ejecucion_id
--   NULL. (Harmless no-op if those partidas turn out to be out of scope.)
--
-- PREREQUISITES: steps 00–04 applied. Run BEFORE step 06.
--
-- ⚠ DRY-RUN §0, run §1 in the open transaction, read §2, then COMMIT.
-- ============================================================================


-- ── Section 0 · DRY RUN — scope + run preview ─────────────────────────────────
-- (a) in-scope staging rows by operacion (groups with zero ejecuciones). Expect
--     only TENIDO + PERCHADO — no COMPACTADO/TERMOFIJADO.
SELECT le.operacion_codigo,
       COUNT(DISTINCT (mypp.partida_id, mypp.operacion_id)) AS empty_groups,
       COUNT(*)                                             AS scope_rows
FROM migration.legacy_executions le
JOIN mes.partida_paso mypp ON mypp.id = le.new_paso_id   -- INNER: drops deleted-paso (rework-lead) rows
WHERE NOT EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion e ON e.partida_paso_id = pp.id
        WHERE pp.partida_id = mypp.partida_id AND pp.operacion_id = mypp.operacion_id)
GROUP BY le.operacion_codigo
ORDER BY 1;

-- (b) runs that will be inserted, by operacion + open/skip
WITH scoped AS (
    SELECT le.partida_id, le.new_paso_id, le.legacy_maquina, le.legacy_estado,
           le.fyh_inicio, le.legacy_id, le.operacion_codigo AS operacion
    FROM migration.legacy_executions le
    JOIN mes.partida_paso mypp ON mypp.id = le.new_paso_id
    WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion e ON e.partida_paso_id = pp.id
            WHERE pp.partida_id = mypp.partida_id AND pp.operacion_id = mypp.operacion_id)
),
marked AS (
    SELECT s.*,
           CASE WHEN LAG(s.legacy_estado) OVER w IS DISTINCT FROM 'En Proceso Teñido'
                THEN 1 ELSE 0 END AS is_new_run
    FROM scoped s
    WINDOW w AS (PARTITION BY s.new_paso_id, s.legacy_maquina ORDER BY s.fyh_inicio, s.legacy_id)
),
runs AS (
    SELECT m.*, SUM(is_new_run) OVER (PARTITION BY m.new_paso_id, m.legacy_maquina
                                      ORDER BY m.fyh_inicio, m.legacy_id) AS run_seq
    FROM marked m
)
SELECT operacion,
       COUNT(*)                                               AS runs,
       COUNT(*) FILTER (WHERE partida_id IN (4153,4410,5199)) AS in_appdup_partidas
FROM (SELECT DISTINCT operacion, new_paso_id, legacy_maquina, run_seq, partida_id
      FROM runs) g
GROUP BY operacion ORDER BY operacion;


-- ── Section 1 · Insert ejecuciones + back-fill ───────────────────────────────
BEGIN;

-- per-staging-row run assignment + windowed run aggregates (kept for back-fill)
CREATE TEMP TABLE _run_rows AS
WITH scoped AS (
    SELECT le.id AS staging_id, le.legacy_id, le.partida_id, le.new_paso_id,
           le.legacy_maquina, le.legacy_estado,
           le.fyh_inicio, le.fyh_fin, le.legacy_rollos, le.legacy_kilos
    FROM migration.legacy_executions le
    JOIN mes.partida_paso mypp ON mypp.id = le.new_paso_id
    WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion e ON e.partida_paso_id = pp.id
            WHERE pp.partida_id = mypp.partida_id AND pp.operacion_id = mypp.operacion_id)
),
marked AS (
    SELECT s.*,
           CASE WHEN LAG(s.legacy_estado) OVER w IS DISTINCT FROM 'En Proceso Teñido'
                THEN 1 ELSE 0 END AS is_new_run
    FROM scoped s
    WINDOW w AS (PARTITION BY s.new_paso_id, s.legacy_maquina ORDER BY s.fyh_inicio, s.legacy_id)
),
runs AS (
    SELECT m.*, SUM(is_new_run) OVER (PARTITION BY m.new_paso_id, m.legacy_maquina
                                      ORDER BY m.fyh_inicio, m.legacy_id) AS run_seq
    FROM marked m
)
SELECT r.staging_id, r.partida_id, r.new_paso_id, r.legacy_maquina, r.run_seq,
       MIN(r.fyh_inicio) OVER wr AS run_inicio,
       MAX(r.fyh_fin) FILTER (WHERE r.legacy_estado IS DISTINCT FROM 'En Proceso Teñido')
                      OVER wr    AS run_fin,
       SUM(r.legacy_rollos) OVER wr AS run_rollos,
       SUM(r.legacy_kilos)  OVER wr AS run_kilos
FROM runs r
WINDOW wr AS (PARTITION BY r.new_paso_id, r.legacy_maquina, r.run_seq);

-- 1a. one ejecucion per run (skip the 3 app-duplicated open runs)
CREATE TEMP TABLE _new_ejec AS
WITH ins AS (
    INSERT INTO mes.partida_paso_ejecucion
        (partida_paso_id, estado, fyh_inicio, fyh_fin, cantidad_rollos, peso_kg, usr_cre, fyh_cre)
    SELECT
        r.new_paso_id,
        (CASE WHEN r.run_fin IS NOT NULL THEN 'COMPLETADO' ELSE 'EN_PROCESO' END)::paso_ejecucion_estado_enum,
        r.run_inicio, r.run_fin, r.run_rollos, r.run_kilos, 4, r.run_inicio
    FROM (
        SELECT DISTINCT new_paso_id, legacy_maquina, run_seq, partida_id,
               run_inicio,
               -- MIDNIGHT FIX: a single-row run that crossed 00:00 has hora_fin <
               -- hora_inicio under the same fecha, so run_fin computes EARLIER than
               -- run_inicio. Bump it a day so the end follows the start.
               CASE WHEN run_fin < run_inicio THEN run_fin + interval '1 day'
                    ELSE run_fin END AS run_fin,
               run_rollos, run_kilos
        FROM _run_rows
        WHERE NOT (partida_id IN (4153,4410,5199) AND run_fin IS NULL)   -- skip app-dup opens
    ) r
    RETURNING id, partida_paso_id, fyh_inicio
)
SELECT * FROM ins;

-- 1b. back-fill new_ejecucion_id onto the staging rows (via paso + run start)
UPDATE migration.legacy_executions le
SET new_ejecucion_id = ne.id
FROM _run_rows rr
JOIN _new_ejec ne ON ne.partida_paso_id = rr.new_paso_id
                 AND ne.fyh_inicio       = rr.run_inicio
WHERE le.id = rr.staging_id;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) in-scope staging rows: got an ejecucion vs skipped (skipped = app-dup opens)
SELECT COUNT(*)                           AS scope_rows,
       COUNT(new_ejecucion_id)            AS got_ejecucion,
       COUNT(*) - COUNT(new_ejecucion_id) AS skipped_rows
FROM migration.legacy_executions le
WHERE le.new_paso_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM _run_rows rr WHERE rr.staging_id = le.id);

-- (b) ejecuciones inserted, by operacion + estado
SELECT op.codigo, ppe.estado, COUNT(*) AS ejecuciones
FROM _new_ejec ne
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ne.id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op ON op.id = pp.operacion_id
GROUP BY op.codigo, ppe.estado ORDER BY op.codigo, ppe.estado;

-- (c) QUANTITY PRESERVATION — the merge must neither lose nor double-count rolls.
--     inserted_rollos (one row per merged ejecucion) must EQUAL the summed legacy
--     rollos of the scope rows that actually got an ejecucion (skipped app-dup rows
--     excluded). The two numbers must match exactly.
SELECT
  (SELECT SUM(ppe.cantidad_rollos)
     FROM _new_ejec ne JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ne.id) AS inserted_rollos,
  (SELECT SUM(le.legacy_rollos)
     FROM migration.legacy_executions le
     WHERE le.new_ejecucion_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM _run_rows rr WHERE rr.staging_id = le.id))    AS scope_rollos_linked;

-- (d) TIMESTAMP sanity: no ejecucion ends before it starts; how many are true
--     merges (>1 legacy row folded into one ejecucion).
SELECT
  COUNT(*) FILTER (WHERE ppe.fyh_fin IS NOT NULL AND ppe.fyh_fin < ppe.fyh_inicio) AS bad_time_order,
  COUNT(*)                                                                          AS ejecuciones,
  (SELECT COUNT(*) FROM (
        SELECT new_ejecucion_id FROM migration.legacy_executions
        WHERE new_ejecucion_id IS NOT NULL
        GROUP BY new_ejecucion_id HAVING COUNT(*) > 1) m)                            AS merged_from_multi_rows
FROM _new_ejec ne JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ne.id;

DROP TABLE _run_rows;
DROP TABLE _new_ejec;

-- COMMIT;    -- ← uncomment after §2: got_ejecucion + skipped_rows = scope_rows
-- ROLLBACK;  -- ← if anything is off


SELECT op.codigo,
       COUNT(*) FILTER (WHERE ppe.fyh_fin IS NOT NULL AND ppe.fyh_fin < ppe.fyh_inicio) AS end_before_start,
       COUNT(*) AS total
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op    ON op.id = pp.operacion_id
GROUP BY op.codigo ORDER BY 2 DESC;

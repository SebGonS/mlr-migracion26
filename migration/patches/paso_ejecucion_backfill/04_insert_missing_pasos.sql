-- ============================================================================
-- 04 · Insert missing pasos for unlinked staging rows            (paso-backfill step 04)
-- ============================================================================
-- WHAT: step 02 left staging rows unlinked (new_paso_id IS NULL) wherever the
--   partida had no existing paso for that operacion — migration-11 skipped them
--   (TENIDO recipe filter), and 06b didn't cover all finishing. This step creates
--   ONE paso per unlinked (partida_id, operacion_id) group (the new "one paso per
--   operation" model), back-fills new_paso_id so step 05 can hang ejecuciones off
--   it, and normalizes each affected partida's secuencia by operation priority.
--
-- COUNTS (expected, from step-02 verify #1): ~4853 TENIDO + 849 PERCHADO +
--   1 COMPACTADO staging rows → far fewer pasos (one per partida+operacion).
--
-- WHY ONE PASO PER GROUP: an unlinked (partida, operacion) has NO existing paso
--   (else step 02 would have linked it), so exactly one new paso is created and
--   the back-fill join (partida_id, operacion_id) is unambiguous. Multiple
--   unlinked runs of the same group share that one paso — they become multiple
--   ejecuciones under it in step 05.
--
-- SECUENCIA: assigned by operation priority
--   PREPARADO→TERMOFIJADO→TENIDO→LAVADO_HIDRO→SECADO→VOLTEADO→PERCHADO→COMPACTADO.
--   New pasos get a provisional high secuencia (collision-free), then EVERY paso
--   of each affected partida is renumbered 1..N by priority (ties: fyh_cre, id) via
--   a negate-then-flip so the UNIQUE(partida_id, secuencia) never transiently
--   collides. Nothing FK-references secuencia; it is display/routing order only.
--   (A partida with several same-operacion pasos not yet consolidated gets them
--   consecutively here; step 06 collapses those.)
--
-- PASO FIELDS: fyh_cre = MIN(fyh_inicio) of the group (earliest production start,
--   matching migration-11's convention); usr_cre = 4 (migration user);
--   maquina_planificada_id / receta_id = NULL (unknown for these historical rows).
--
-- ORPHAN PARTIDAS: some legacy partidas were deleted/excluded in prior migrations
--   (e.g. migration/14_nuke_partidas_ar505.sql). Their staging rows are marked
--   status='ORPHAN_PARTIDA' and skipped — there is no partida to attach a paso to.
--
-- PREREQUISITES: steps 00–02 applied. Independent of step 03. Run BEFORE step 05.
--
-- ⚠ DRY-RUN §0, run §1 in the open transaction, read §2, then COMMIT.
-- ============================================================================


-- ── Section 0 · DRY RUN — what will be inserted vs ignored ────────────────────
-- new_pasos / staging_rows count only rows whose partida EXISTS in mes.partida;
-- orphan_rows = rows for partidas deleted/excluded in prior migrations (ignored).
SELECT le.operacion_codigo,
       COUNT(DISTINCT le.partida_id) FILTER (
           WHERE EXISTS (SELECT 1 FROM mes.partida p WHERE p.id = le.partida_id))  AS new_pasos,
       COUNT(*) FILTER (
           WHERE EXISTS (SELECT 1 FROM mes.partida p WHERE p.id = le.partida_id))  AS staging_rows,
       COUNT(*) FILTER (
           WHERE NOT EXISTS (SELECT 1 FROM mes.partida p WHERE p.id = le.partida_id)) AS orphan_rows
FROM migration.legacy_executions le
WHERE le.new_paso_id IS NULL
GROUP BY le.operacion_codigo
ORDER BY 1;


-- ── Section 1 · Insert + back-fill + renumber ─────────────────────────────────
BEGIN;

-- 1a. Mark staging rows whose partida was deliberately removed from mes.partida in
--     a prior migration (deleted/nuked legacy orders — verified out-of-band). Their
--     partida no longer exists, so there is nothing to attach a paso to: ignore.
UPDATE migration.legacy_executions le
SET status = 'ORPHAN_PARTIDA'
WHERE le.new_paso_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM mes.partida p WHERE p.id = le.partida_id);

-- 1b. one paso per unlinked (partida, operacion) FOR EXISTING partidas; provisional
--     collision-free secuencia. Capture the inserted rows for back-fill + verify.
CREATE TEMP TABLE _new_pasos AS
WITH ins AS (
    INSERT INTO mes.partida_paso (partida_id, secuencia, operacion_id, usr_cre, fyh_cre)
    SELECT
        g.partida_id,
        (1000 + ROW_NUMBER() OVER (PARTITION BY g.partida_id ORDER BY g.operacion_id))::smallint,
        g.operacion_id,
        4,
        g.fyh_cre
    FROM (
        SELECT partida_id, operacion_id, MIN(fyh_inicio) AS fyh_cre
        FROM migration.legacy_executions
        WHERE new_paso_id IS NULL
          AND EXISTS (SELECT 1 FROM mes.partida p WHERE p.id = partida_id)
        GROUP BY partida_id, operacion_id
    ) g
    RETURNING id, partida_id, operacion_id
)
SELECT * FROM ins;

-- 1c. back-fill new_paso_id onto the unlinked staging rows from the new pasos
UPDATE migration.legacy_executions le
SET new_paso_id = np.id,
    status      = 'LINKED'
FROM _new_pasos np
WHERE le.new_paso_id IS NULL
  AND np.partida_id   = le.partida_id
  AND np.operacion_id = le.operacion_id;

-- 1d. renumber secuencia 1..N by operation priority for every affected partida.
--     Phase 1: assign the final rank as a NEGATIVE (unique per partida → no clash
--     with the positive/provisional values still present).
UPDATE mes.partida_paso pp
SET secuencia = -ranked.new_seq
FROM (
    SELECT pp2.id,
           ROW_NUMBER() OVER (
               PARTITION BY pp2.partida_id
               ORDER BY CASE op.codigo
                   WHEN 'PREPARADO'    THEN 1 WHEN 'TERMOFIJADO' THEN 2
                   WHEN 'TENIDO'       THEN 3 WHEN 'LAVADO_HIDRO' THEN 4
                   WHEN 'SECADO'       THEN 5 WHEN 'VOLTEADO'    THEN 6
                   WHEN 'PERCHADO'     THEN 7 WHEN 'COMPACTADO'  THEN 8
                   ELSE 99 END,
                   pp2.fyh_cre, pp2.id) AS new_seq
    FROM mes.partida_paso pp2
    JOIN mes.operacion op ON op.id = pp2.operacion_id
    WHERE pp2.partida_id IN (SELECT partida_id FROM _new_pasos)
) ranked
WHERE pp.id = ranked.id;

--     Phase 2: flip the negatives to their final positive value (targets don't yet
--     exist as positives → no transient collision).
UPDATE mes.partida_paso pp
SET secuencia = -pp.secuencia
WHERE pp.partida_id IN (SELECT partida_id FROM _new_pasos)
  AND pp.secuencia < 0;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) every non-orphan staging row is now linked — expect 0
SELECT COUNT(*) AS still_unlinked
FROM migration.legacy_executions
WHERE new_paso_id IS NULL
  AND status <> 'ORPHAN_PARTIDA';

-- (a2) how many rows were ignored as orphan partidas (informational)
SELECT COUNT(*) AS orphan_partida_rows
FROM migration.legacy_executions
WHERE status = 'ORPHAN_PARTIDA';

-- (b) new paso count by operacion (should match §0 new_pasos)
SELECT op.codigo, COUNT(*) AS pasos_inserted
FROM _new_pasos np
JOIN mes.operacion op ON op.id = np.operacion_id
GROUP BY op.codigo ORDER BY op.codigo;

-- (c) secuencia is a clean 1..N per affected partida — expect 0 bad partidas
SELECT COUNT(*) AS partidas_with_bad_secuencia
FROM (
    SELECT partida_id
    FROM mes.partida_paso
    WHERE partida_id IN (SELECT partida_id FROM _new_pasos)
    GROUP BY partida_id
    HAVING COUNT(*) <> COUNT(DISTINCT secuencia)   -- duplicate secuencia
        OR MIN(secuencia) <> 1                     -- doesn't start at 1
        OR MAX(secuencia) <> COUNT(*)              -- has a gap
) bad;

-- (d) eyeball a few affected partidas' routing
SELECT pp.partida_id, pp.secuencia, op.codigo
FROM mes.partida_paso pp
JOIN mes.operacion op ON op.id = pp.operacion_id
WHERE pp.partida_id IN (SELECT DISTINCT partida_id FROM _new_pasos ORDER BY partida_id LIMIT 5)
ORDER BY pp.partida_id, pp.secuencia;

DROP TABLE _new_pasos;

-- COMMIT;    -- ← uncomment after §2: still_unlinked=0, bad_secuencia=0
-- ROLLBACK;  -- ← if anything is off

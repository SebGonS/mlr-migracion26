-- ============================================================================
-- 06 · Consolidate multiple same-operacion pasos into one       (paso-backfill step 06)
-- ============================================================================
-- WHAT: the new model is ONE paso per (partida, operacion) with 1..N ejecuciones.
--   Several sources left MULTIPLE pasos per group:
--     · migration-11 created one paso PER tenido run (a 3-run partida → 3 pasos);
--     · normal shift-splits left a lead paso + a completion paso (step 03 emptied
--       the lead's ejecucion but left both pasos);
--     · compactado rib/regular recorded as two pasos.
--   This step collapses each group to the canonical MIN(paso.id): re-parents its
--   ejecuciones + partida_componente reservations onto the canonical, drops the
--   now-empty extra pasos, and renumbers secuencia.
--
-- CANONICAL = MIN(paso.id) per (partida_id, operacion_id) group with >1 paso.
--   (Reworks are already single-paso per child partida — not affected.)
--
-- SCOPE = MIGRATION-ORIGIN pasos only (fyh_cre < go-live). The dry-run showed 78
--   VOLTEADO "duplicates" are EMPTY app-created pasos (two per partida at secuencia
--   5 & 7) — the app legitimately routes one operacion at multiple positions, so
--   "one paso per operacion" is a migration goal, NOT a universal invariant. App
--   pasos are left untouched. The COMPACTADO groups are mostly SEPARATE runs (1334
--   different-timespan vs 19 rib/regular same-timespan) → collapsing to one paso
--   with N ejecuciones (the runs) is exactly the target model; no summing.
--   NOTE: §1d renumbers all pasos of an affected (migration) partida; the rare
--   migration+app mixed partida would get its app pasos reordered by priority too.
--
-- COMPONENTE: mes.partida_paso → partida_componente is ON DELETE CASCADE with a
--   UNIQUE(partida_paso_id, item_id). We move non-conflicting reservations to the
--   canonical; any that would collide (canonical already reserves that item) are
--   left on the extra paso and cascade-drop when it's deleted (no loss — the
--   canonical already holds the reservation). §0 reports whether any exist at all.
--
-- SEQUENCE: after dropping pasos, renumber each affected partida 1..N by operation
--   priority (same negate-then-flip as step 04).
--
-- PREREQUISITES: steps 00–05 applied. This is the last core step; nothing after it
--   relies on pp.id = pt.id.
--
-- ⚠ DRY-RUN §0, run §1 in the open transaction, read §2, then COMMIT.
-- ============================================================================


-- ── Section 0 · DRY RUN — what will consolidate ───────────────────────────────
-- (a) groups with >1 paso, by operacion
SELECT op.codigo,
       COUNT(*)                                 AS extra_pasos,       -- pasos that will be dropped
       COUNT(DISTINCT g.partida_id)             AS partidas_affected
FROM (
    SELECT pp.id, pp.partida_id, pp.operacion_id,
           MIN(pp.id) OVER (PARTITION BY pp.partida_id, pp.operacion_id) AS canonical_id,
           COUNT(*)   OVER (PARTITION BY pp.partida_id, pp.operacion_id) AS n_pasos
    FROM mes.partida_paso pp
    WHERE pp.fyh_cre < '2026-05-25 15:27:52+00'::timestamptz   -- migration-origin only (app pasos untouched)
) g
JOIN mes.operacion op ON op.id = g.operacion_id
WHERE g.n_pasos > 1 AND g.id <> g.canonical_id      -- the non-canonical (extra) pasos
GROUP BY op.codigo ORDER BY 2 DESC;

-- (b) ejecuciones sitting on those extra pasos (will be re-parented — expect these
--     to be preserved, count must survive)
SELECT COUNT(*) AS ejecuciones_to_reparent
FROM mes.partida_paso_ejecucion ppe
WHERE ppe.partida_paso_id IN (
    SELECT id FROM (
        SELECT pp.id, MIN(pp.id) OVER w AS canonical_id, COUNT(*) OVER w AS n
        FROM mes.partida_paso pp
        WHERE pp.fyh_cre < '2026-05-25 15:27:52+00'::timestamptz
        WINDOW w AS (PARTITION BY pp.partida_id, pp.operacion_id)
    ) x WHERE n > 1 AND id <> canonical_id);

-- (c) componente reservations on the extra pasos + how many would CONFLICT on the
--     canonical (same item already reserved there → those cascade-drop, not moved)
WITH extra AS (
    SELECT pp.id AS paso_id, pp.partida_id, pp.operacion_id,
           MIN(pp.id) OVER w AS canonical_id, COUNT(*) OVER w AS n
    FROM mes.partida_paso pp
    WHERE pp.fyh_cre < '2026-05-25 15:27:52+00'::timestamptz
    WINDOW w AS (PARTITION BY pp.partida_id, pp.operacion_id)
)
SELECT COUNT(*)                                                          AS componente_on_extras,
       COUNT(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM mes.partida_componente pc2
           WHERE pc2.partida_paso_id = e.canonical_id AND pc2.item_id = pc.item_id)) AS would_conflict
FROM extra e
JOIN mes.partida_componente pc ON pc.partida_paso_id = e.paso_id
WHERE e.n > 1 AND e.paso_id <> e.canonical_id;


-- ── Section 1 · Consolidate ───────────────────────────────────────────────────
BEGIN;

-- map of extra pasos → their canonical (groups with >1 paso only)
CREATE TEMP TABLE _consolidate AS
SELECT x.id AS paso_id, x.partida_id, x.canonical_id
FROM (
    SELECT pp.id, pp.partida_id,
           MIN(pp.id) OVER w AS canonical_id,
           COUNT(*)   OVER w AS n_pasos
    FROM mes.partida_paso pp
    WHERE pp.fyh_cre < '2026-05-25 15:27:52+00'::timestamptz   -- migration-origin only
    WINDOW w AS (PARTITION BY pp.partida_id, pp.operacion_id)
) x
WHERE x.n_pasos > 1 AND x.id <> x.canonical_id;

-- 1a. re-parent ejecuciones onto the canonical paso
UPDATE mes.partida_paso_ejecucion ppe
SET partida_paso_id = c.canonical_id, usr_mod = 4, fyh_mod = now()
FROM _consolidate c
WHERE ppe.partida_paso_id = c.paso_id;

-- 1b. move non-conflicting componente reservations to the canonical; conflicting
--     ones stay and cascade-drop with the paso (canonical already reserves them)
UPDATE mes.partida_componente pc
SET partida_paso_id = c.canonical_id
FROM _consolidate c
WHERE pc.partida_paso_id = c.paso_id
  AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc2
                  WHERE pc2.partida_paso_id = c.canonical_id AND pc2.item_id = pc.item_id);

-- 1c. drop the now-empty extra pasos (cascades any leftover conflicting componente)
DELETE FROM mes.partida_paso pp
USING _consolidate c
WHERE pp.id = c.paso_id;

-- 1d. renumber secuencia 1..N by operation priority for affected partidas
--     (negate-then-flip, collision-free — same as step 04)
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
    WHERE pp2.partida_id IN (SELECT DISTINCT partida_id FROM _consolidate)
) ranked
WHERE pp.id = ranked.id;

UPDATE mes.partida_paso pp
SET secuencia = -pp.secuencia
WHERE pp.partida_id IN (SELECT DISTINCT partida_id FROM _consolidate)
  AND pp.secuencia < 0;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) no (partida, operacion) has >1 MIGRATION paso anymore — expect 0.
--     (App pasos with the same operacion are legitimate routing and are excluded.)
SELECT COUNT(*) AS groups_still_multi
FROM (
    SELECT partida_id, operacion_id
    FROM mes.partida_paso
    WHERE fyh_cre < '2026-05-25 15:27:52+00'::timestamptz
    GROUP BY partida_id, operacion_id
    HAVING COUNT(*) > 1
) x;

-- (b) no ejecucion was orphaned (all still point at a live paso) — expect 0
SELECT COUNT(*) AS orphaned_ejecuciones
FROM mes.partida_paso_ejecucion ppe
WHERE NOT EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.id = ppe.partida_paso_id);

-- (c) affected partidas have clean 1..N secuencia — expect 0 bad
SELECT COUNT(*) AS partidas_with_bad_secuencia
FROM (
    SELECT partida_id
    FROM mes.partida_paso
    WHERE partida_id IN (SELECT DISTINCT partida_id FROM _consolidate)
    GROUP BY partida_id
    HAVING COUNT(*) <> COUNT(DISTINCT secuencia)
        OR MIN(secuencia) <> 1
        OR MAX(secuencia) <> COUNT(*)
) bad;

DROP TABLE _consolidate;

-- COMMIT;    -- ← after §2: groups_still_multi = 0, orphaned = 0, bad_secuencia = 0
-- ROLLBACK;  -- ← if anything is off






-- ============================================================================
-- PATCH 40 · Fix inverted fyh_inicio/fyh_fin on 24 post-go-live ejecuciones
-- ============================================================================
-- WHAT: The app's ejecucion-finalize function has a bug: when a step crosses
--   midnight (local time), it writes fyh_fin using the start-date + end-hour
--   instead of the end-date + end-hour, producing fyh_fin < fyh_inicio.
--   This patch corrects the 24 affected rows (snapshot fix). The app bug is
--   still active — notify the app team; new rows will arrive until it is fixed.
--
-- NOT migration data: all fyh_inicio >= go-live cutoff (2026-05-25 15:27:52+00).
--   The migration cleanup (cleanup_midnight_fyh_fin.sql) fixed 692 pre-go-live
--   rows by the same +1 day rule; these were intentionally left for the app team.
--
-- Three fix groups (identified by gap analysis):
--
--   A (+1 day, 17 rows): fyh_inicio is early UTC morning; fyh_fin is the
--      previous calendar day. Overnight shift: finalize used start-date for
--      end-timestamp. Fix: fyh_fin + interval '1 day'.
--
--   B (swap, 6 rows): fyh_fin is only 40 min–10 h before fyh_inicio on the
--      same (or adjacent) UTC day. Operator entered start/end in wrong order
--      or UI accepted reversed values. Fix: swap fyh_inicio ↔ fyh_fin.
--
--   C (+2 days, 1 row): ejec 9695 (partida 6120, TERMOFIJADO). fyh_fin is
--      2026-06-13 21:00, two calendar days before fyh_inicio 2026-06-15 20:25.
--      Fix: fyh_fin + interval '2 days' → 2026-06-15 21:00 (35 min duration).
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- ── Section 0 · DRY RUN — verify scope before touching anything ───────────────
SELECT ppe.id AS ejec_id, pp.partida_id, op.codigo,
       ppe.fyh_inicio, ppe.fyh_fin,
       ppe.fyh_inicio - ppe.fyh_fin AS gap,
       CASE
           WHEN ppe.id IN (9270,9345,9861,9615,9691,9858)                THEN 'B-swap'
           WHEN ppe.id = 9695                                             THEN 'C-plus2days'
           ELSE                                                                'A-plus1day'
       END AS fix_group,
       CASE
           WHEN ppe.id IN (9270,9345,9861,9615,9691,9858)
               THEN ppe.fyh_fin                   -- new fyh_inicio after swap
           ELSE ppe.fyh_inicio END                                       AS new_fyh_inicio,
       CASE
           WHEN ppe.id IN (9270,9345,9861,9615,9691,9858)
               THEN ppe.fyh_inicio                -- new fyh_fin after swap
           WHEN ppe.id = 9695
               THEN ppe.fyh_fin + interval '2 days'
           ELSE    ppe.fyh_fin + interval '1 day'
       END                                                               AS new_fyh_fin
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op    ON op.id = pp.operacion_id
WHERE ppe.id IN (
    -- Group A: +1 day (17 rows)
    10191, 9259, 9228, 9242, 8900, 2300, 9276, 2014, 9287, 1997,
    9251, 9312, 9415, 10150, 10164, 10012, 10359,
    -- Group B: swap (6 rows)
    9270, 9345, 9861, 9615, 9691, 9858,
    -- Group C: +2 days (1 row)
    9695
)
ORDER BY fix_group, pp.partida_id;


-- ── Section 1 · Apply fixes ───────────────────────────────────────────────────
BEGIN;

-- A: overnight date-off-by-one → add one day to fyh_fin
UPDATE mes.partida_paso_ejecucion
SET fyh_fin = fyh_fin + interval '1 day',
    usr_mod = 4, fyh_mod = now()
WHERE id IN (
    10191, 9259, 9228, 9242, 8900, 2300, 9276, 2014, 9287, 1997,
    9251, 9312, 9415, 10150, 10164, 10012, 10359
);

-- B: same-day inversion → swap inicio and fin
UPDATE mes.partida_paso_ejecucion
SET fyh_inicio = fyh_fin,
    fyh_fin    = fyh_inicio,
    usr_mod = 4, fyh_mod = now()
WHERE id IN (9270, 9345, 9861, 9615, 9691, 9858);

-- C: two-day entry error → add two days to fyh_fin
UPDATE mes.partida_paso_ejecucion
SET fyh_fin = fyh_fin + interval '2 days',
    usr_mod = 4, fyh_mod = now()
WHERE id = 9695;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) no remaining inverted timestamps among the 24 — expect 0
SELECT COUNT(*) AS still_inverted
FROM mes.partida_paso_ejecucion
WHERE id IN (
    10191, 9259, 9228, 9242, 8900, 2300, 9276, 2014, 9287, 1997,
    9251, 9312, 9415, 10150, 10164, 10012, 10359,
    9270, 9345, 9861, 9615, 9691, 9858,
    9695
)
AND fyh_fin < fyh_inicio;

-- (b) sanity: all durations positive and under 36 hours (spot-check reasonableness)
SELECT id, fyh_fin - fyh_inicio AS duration
FROM mes.partida_paso_ejecucion
WHERE id IN (
    10191, 9259, 9228, 9242, 8900, 2300, 9276, 2014, 9287, 1997,
    9251, 9312, 9415, 10150, 10164, 10012, 10359,
    9270, 9345, 9861, 9615, 9691, 9858,
    9695
)
ORDER BY duration DESC;

-- (c) updated count — expect 24
SELECT COUNT(*) AS rows_updated
FROM mes.partida_paso_ejecucion
WHERE id IN (
    10191, 9259, 9228, 9242, 8900, 2300, 9276, 2014, 9287, 1997,
    9251, 9312, 9415, 10150, 10164, 10012, 10359,
    9270, 9345, 9861, 9615, 9691, 9858,
    9695
)
AND fyh_mod >= now() - interval '1 minute';

-- COMMIT;   -- ← after §2: still_inverted = 0, all durations sensible
-- ROLLBACK;

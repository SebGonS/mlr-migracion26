-- ============================================================================
-- CLEANUP · Fix midnight-crossing fyh_fin on MIGRATION ejecuciones
-- ============================================================================
-- WHAT: migration-11 (single-row tenido) and the legacy finishing migration
--   compute fyh_fin = (fecha + hora_fin + 5h). A run that crossed 00:00 has
--   hora_fin < hora_inicio under ONE fecha, so its fyh_fin lands EARLIER than
--   fyh_inicio (end before start). Step 05 already fixed its own inserts; this
--   fixes the pre-existing committed rows.
--
-- FIX: where fyh_fin < fyh_inicio, the run crossed one midnight → add 1 day.
--
-- SCOPE: MIGRATION-origin only (fyh_inicio before go-live). The handful of
--   POST-go-live app rows with the same symptom (SECADO/PREPARADO/LAVADO_HIDRO)
--   are LIVE production records — NOT touched here; §0 surfaces them so the app
--   team can own the fix (likely an ejecucion-finalize bug, code + data).
--
-- This is a standalone cleanup, not part of the 00–06 backfill sequence. Safe to
-- run any time; idempotent (a fixed row is no longer < fyh_inicio).
-- ============================================================================

-- ── Section 0 · What has the bug, split by origin ─────────────────────────────
SELECT op.codigo,
       COUNT(*) FILTER (WHERE ppe.fyh_fin < ppe.fyh_inicio
                          AND ppe.fyh_inicio <  '2026-05-25 15:27:52+00'::timestamptz) AS migration_bad,
       COUNT(*) FILTER (WHERE ppe.fyh_fin < ppe.fyh_inicio
                          AND ppe.fyh_inicio >= '2026-05-25 15:27:52+00'::timestamptz) AS app_bad_DO_NOT_TOUCH
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op    ON op.id = pp.operacion_id
WHERE ppe.fyh_fin IS NOT NULL AND ppe.fyh_fin < ppe.fyh_inicio
GROUP BY op.codigo ORDER BY 2 DESC;


-- ── Section 1 · Fix migration rows (+1 day) ───────────────────────────────────
BEGIN;

UPDATE mes.partida_paso_ejecucion ppe
SET fyh_fin = ppe.fyh_fin + interval '1 day',
    usr_mod = 4, fyh_mod = now()
WHERE ppe.fyh_fin IS NOT NULL
  AND ppe.fyh_fin < ppe.fyh_inicio
  AND ppe.fyh_inicio < '2026-05-25 15:27:52+00'::timestamptz;   -- migration-origin only


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) migration rows still end-before-start — expect 0. (A non-zero here would be
--     a run that crossed TWO midnights; paste it and we widen the fix.)
SELECT COUNT(*) AS migration_still_bad
FROM mes.partida_paso_ejecucion ppe
WHERE ppe.fyh_fin IS NOT NULL
  AND ppe.fyh_fin < ppe.fyh_inicio
  AND ppe.fyh_inicio < '2026-05-25 15:27:52+00'::timestamptz;

-- (b) the app rows we intentionally left alone (still present = expected)
SELECT COUNT(*) AS app_rows_left_untouched
FROM mes.partida_paso_ejecucion ppe
WHERE ppe.fyh_fin IS NOT NULL
  AND ppe.fyh_fin < ppe.fyh_inicio
  AND ppe.fyh_inicio >= '2026-05-25 15:27:52+00'::timestamptz;

-- (c) sanity: no fixed row is now absurdly long (>24h) — spot any that need review
SELECT COUNT(*) AS fixed_over_24h
FROM mes.partida_paso_ejecucion ppe
WHERE ppe.usr_mod = 4 AND ppe.fyh_mod::date = CURRENT_DATE
  AND ppe.fyh_fin - ppe.fyh_inicio > interval '24 hours';

-- COMMIT;    -- ← after (a) = 0
-- ROLLBACK;  -- ← if anything is off

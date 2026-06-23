-- ============================================================================
-- 30 · Fix mis-assigned LAVADO_HIDRO pasos → TENIDO  (migration backfill)
-- ============================================================================
-- WHY: migration/11_data_migration.sql (lines ~894-899) split tipo_receta into
-- TENIDO vs LAVADO_HIDRO by recipe label. But every produccion_tenido row IS a
-- TEÑIDO-machine run — `tipo` only selects the recipe, never a different
-- operation (confirmed with client). So Rebaje/Mojar/Lavado x*/Lavado Hidrofilo
-- recipes produced LAVADO_HIDRO pasos that should be TENIDO. The recipe identity
-- is preserved in receta_id; only operacion_id was wrong.
--
-- SCOPE: produccion_tenido is the ONLY dyeing-run source among the four migrated
-- legacy tables (produccion_tenido, perchado, compactado, termofijado), so the
-- mis-split could only have produced LAVADO_HIDRO pasos. Targeting operacion =
-- LAVADO_HIDRO therefore CANNOT touch the correctly-migrated COMPACTADO /
-- PERCHADO / TERMOFIJADO pasos (they carry their own codes).
--
-- CUTOFF: pp.fyh_cre::date <= MAX(produccion_tenido.fecha).
--   migration-11 set partida_paso.fyh_cre to the ACTUAL production timestamp
--   (pt.fecha + hora_inicio + 5h), NOT now() at migration run time (confirmed
--   at migration/11_data_migration.sql line ~1525). So this comparison cleanly
--   separates migrated pasos (fyh_cre = legacy date) from app-created pasos
--   (fyh_cre = now() at creation, always after MAX(pt.fecha)).
--   Migration run timestamp (derived from mes.maquina/inventario.almacen cluster):
--   2026-05-25 13:27:52 UTC  (+2h tolerance → cutoff 2026-05-25 15:27:52 UTC).
--
-- OUTCOME (verified 2026-06-22): all 32 LAVADO_HIDRO pasos scoped to dyeing
--   partidas are post-go-live app-created reworks (fyh_cre > 2026-05-25).
--   The migration-11 bug produced zero orphaned rows — pasos were never bulk-
--   inserted for those mis-mapped tipos. This patch is a confirmed no-op.
--   Kept as documented evidence of the domain fact and investigation.
--
-- IDEMPOTENT: no-op by design (0 rows match the date-scoped WHERE).
-- ============================================================================

-- ── DRY RUN — expect 32 rows ──────────────────────────────────────────────────
SELECT pp.id          AS paso_id,
       p.id           AS partida_id,
       COALESCE(p.partida_origen_id, p.id) AS root_id,
       op.codigo      AS operacion_actual,
       pp.fyh_cre::date AS paso_fecha
FROM mes.partida_paso pp
JOIN mes.operacion op ON op.id = pp.operacion_id
JOIN mes.partida   p  ON p.id  = pp.partida_id
WHERE pp.operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'LAVADO_HIDRO')
  AND pp.fyh_cre <= '2026-05-25 18:27:52+00'::timestamptz
  AND EXISTS (
        SELECT 1 FROM produccion_tenido pt
        WHERE pt.partida_id = COALESCE(p.partida_origen_id, p.id)
      )
ORDER BY partida_id;


-- ── PATCH ─────────────────────────────────────────────────────────────────────
BEGIN;

UPDATE mes.partida_paso pp
SET    operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO'),
       usr_mod      = 4,
       fyh_mod      = now()
FROM   mes.partida p
WHERE  pp.partida_id   = p.id
  AND  pp.operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'LAVADO_HIDRO')
  AND  pp.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
  AND  EXISTS (
        SELECT 1 FROM produccion_tenido pt
        WHERE pt.partida_id = COALESCE(p.partida_origen_id, p.id)
       );

COMMIT;

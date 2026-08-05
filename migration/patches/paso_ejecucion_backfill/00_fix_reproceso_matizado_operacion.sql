-- ============================================================================
-- 00 · Fix tipo_receta.operacion_id for 'Reproceso Matizado'   (paso-backfill step 00)
-- ============================================================================
-- WHY: migration/11_data_migration.sql line 892 had a typo:
--   'Repartida Matizado' instead of 'Reproceso Matizado'
-- The UPDATE that was supposed to assign operacion_id = TENIDO never matched
-- tipo_receta id=10, leaving operacion_id = NULL.
-- Effect: ~78 produccion_tenido rows of tipo 'Reproceso Matizado' are
-- invisible to the §2 validation (JOIN to mes.operacion fails on NULL).
--
-- IDEMPOTENT: re-running is a no-op (operacion_id already set).
-- VERIFY: SELECT id, tipo_receta, operacion_id FROM tipo_receta WHERE id = 10;
--   Before: operacion_id = NULL. After: operacion_id = (TENIDO id).
-- ============================================================================

BEGIN;

UPDATE tipo_receta
SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
WHERE tipo_receta = 'Reproceso Matizado'
  AND operacion_id IS NULL;

COMMIT;

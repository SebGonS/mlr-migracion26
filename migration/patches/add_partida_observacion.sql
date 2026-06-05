-- ============================================================================
-- Patch: add observacion to mes.partida + backfill from legacy
-- ============================================================================
-- The legacy public.partida table had an observacion text column used for
-- order-level free-text notes. It was not included in the initial migration.
-- IDs are preserved 1:1 (migration used OVERRIDING SYSTEM VALUE with p.id).
-- ============================================================================

ALTER TABLE mes.partida
    ADD COLUMN IF NOT EXISTS observacion TEXT;

-- Backfill from legacy — skip empty strings
UPDATE mes.partida np
SET observacion = lp.observacion
FROM public.partida lp
WHERE np.id = lp.id
  AND lp.observacion IS NOT NULL
  AND lp.observacion <> '';

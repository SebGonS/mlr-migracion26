-- ============================================================================
-- Patch: backfill flg_doble_bolsa + observacion on existing reproceso children;
-- unwind flg_antipilling propagation
-- ============================================================================
-- mes.crear_reproceso() inherited flg_antipilling from the origin partida but
-- never copied flg_doble_bolsa or observacion, leaving every rework child with
-- those two columns at their defaults (false / NULL) regardless of the root
-- partida's values. Fixed in funciones/mes.sql (crear_reproceso INSERT) — the
-- first UPDATE below backfills children created before that fix.
--
-- Separately, flg_antipilling should NOT have been propagated: a rework's
-- corrective recipe normally doesn't re-apply antipilling to a roll that
-- already has it, so a copied flag misleads recipe generation into treating
-- it as if it still needs the treatment. Also fixed in crear_reproceso (the
-- flag is no longer copied; a note is left in observacion instead). The
-- second UPDATE below unwinds the flag on existing children and leaves the
-- same note, so historical data matches the new policy.
-- ============================================================================

-- 1) Backfill flg_doble_bolsa / observacion — only children still at the
--    untouched default, so a manual edit made on a child after its creation
--    is left alone.
UPDATE mes.partida child
SET flg_doble_bolsa = root.flg_doble_bolsa,
    observacion      = root.observacion
FROM mes.partida root
WHERE child.partida_origen_id = root.id
  AND child.flg_doble_bolsa = false
  AND child.observacion IS NULL
  AND (root.flg_doble_bolsa = true OR root.observacion IS NOT NULL);

-- 2) Unwind flg_antipilling propagation — only children whose flag still
--    matches an antipilling root (i.e. was copied, not manually set after
--    the fact), and skip if the note was already appended (idempotent).
UPDATE mes.partida child
SET flg_antipilling = false,
    observacion = concat_ws(' | ', child.observacion, 'Origen con antipilling')
FROM mes.partida root
WHERE child.partida_origen_id = root.id
  AND child.flg_antipilling = true
  AND root.flg_antipilling = true
  AND (child.observacion IS NULL
       OR child.observacion NOT LIKE '%Origen con antipilling%');

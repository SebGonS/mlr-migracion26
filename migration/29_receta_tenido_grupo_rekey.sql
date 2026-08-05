-- ═══════════════════════════════════════════════════════════════
-- Step 29: add grupo_articulo_id to receta.tenido + backfill (PREP ONLY)
--
-- DEPENDS ON: migration 28 (grupo_articulo seeded 1:1 from articulo_tipo).
--
-- SCOPE — deliberately additive and inert. This migration ONLY adds the new
-- FK column and backfills it. It does NOT create the grupo unique index, does
-- NOT touch trg_bu_tenido_immutable, and does NOT change any function. Nothing
-- reads grupo_articulo_id yet, so behaviour is identical before and after.
--
-- WHY SO THIN: the recipe identity flip (index swap, immutability guard, and
-- converting crear_tenido / actualizar_tenido / transicionar_tenido /
-- resolver_tenido_id / solicitar_si_ausente) cannot land safely in isolation —
-- the matcher resolver_tenido_id reads mes.partida, which gains its own
-- grupo_articulo_id in migration 30. Doing the whole flip there, in one pass,
-- avoids a split-brain window where new recipes carry a NULL grupo that a later
-- backfill could collide under the unique index. So 29 just gets the data
-- ready; 30 performs the switchover across receta + partida together.
--
-- The recipe-side function bodies for 30 are specified in project memory
-- (grupo-articulo-dye-substrate): crear_tenido/actualizar_tenido accept EITHER
-- grupo_articulo_id (authoritative) or articulo_tipo_id (back-compat) and keep
-- both in sync via grupo_articulo.origen_articulo_tipo_id; transicionar_tenido
-- supersede keys on grupo_articulo_id; then create uq_receta_tenido_aprobada_grupo,
-- extend the immutability trigger's column list, re-run this backfill for any
-- interim rows, and drop the old uq_receta_tenido_aprobada.
--
-- fibra STAYS in the recipe key — it is the *run* dimension (colores jaspeados:
-- run < required), not derivable. Only articulo_tipo_id → grupo_articulo_id.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Add the column ─────────────────────────────────────────
ALTER TABLE receta.tenido
    ADD COLUMN IF NOT EXISTS grupo_articulo_id INT REFERENCES grupo_articulo(id);

-- ── 2. Backfill from the 1:1 seed ─────────────────────────────
-- Safe to run now (and again in 30 for interim rows): trg_bu_tenido_immutable
-- does not guard grupo_articulo_id, so this cannot trip its "recipe has
-- completed executions" check. Every non-NULL articulo_tipo_id maps to exactly
-- one seeded grupo (migration 28). NULL articulo_tipo_id rows (wildcard
-- recipes) stay NULL — still wildcards.
UPDATE receta.tenido rt
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = rt.articulo_tipo_id
  AND rt.grupo_articulo_id IS NULL;

-- ── 3. Abort-guard ────────────────────────────────────────────
-- No approved recipe should be left without a grupo. If this fires, migration
-- 28's seed is incomplete — STOP and fix 28, do not proceed to 30.
DO $$
DECLARE v_orphans INT;
BEGIN
    SELECT COUNT(*) INTO v_orphans
    FROM receta.tenido
    WHERE flg_produccion = true
      AND articulo_tipo_id IS NOT NULL
      AND grupo_articulo_id IS NULL;
    IF v_orphans > 0 THEN
        RAISE EXCEPTION
            'Migration 29 abort: % approved recipe(s) have articulo_tipo_id but no grupo_articulo_id — migration 28 seed is incomplete.',
            v_orphans;
    END IF;
END $$;

-- ── VERIFY ────────────────────────────────────────────────────
-- Rows still unmapped (expect only genuine wildcard / NULL-articulo_tipo rows):
  -- SELECT id, color_x_cliente_id, articulo_tipo_id, tenido_id, flg_produccion
  -- FROM receta.tenido WHERE grupo_articulo_id IS NULL;
--
-- grupo and articulo_tipo must partition approved recipes identically (0 rows):
--   SELECT color_x_cliente_id, fibra, tenido_id, flg_antipilling,
--          COUNT(DISTINCT articulo_tipo_id), COUNT(DISTINCT grupo_articulo_id)
--   FROM receta.tenido WHERE flg_produccion
--   GROUP BY 1,2,3,4 HAVING COUNT(DISTINCT grupo_articulo_id) <> COUNT(DISTINCT articulo_tipo_id);


UPDATE articulo SET fibra = 1
WHERE fibra IS NULL
  AND nombre IN ('Gam 30/1','Spun 20/1','Gam 50/1 Card','F Lycra 20/1 Pei','Full Lycra Melange');
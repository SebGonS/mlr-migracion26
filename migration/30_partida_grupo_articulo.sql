-- ═══════════════════════════════════════════════════════════════
-- Step 30: add grupo_articulo_id to mes.partida + backfill (PREP ONLY)
--
-- DEPENDS ON: 28 (grupos seeded), 29 (receta.tenido.grupo_articulo_id backfilled).
--
-- SCOPE — additive and inert, exactly like 29 was for receta.tenido. This adds
-- the column, backfills it, and relaxes articulo_tipo_id to nullable. It does
-- NOT swap the crear_partida guard, does NOT add the fibra ceiling, and does
-- NOT touch any function. Behaviour is identical before and after.
--
-- WHY SO THIN: the actual flip (migration 31) has to move six functions at once
-- — crear_partida, resolver_tenido_id, solicitar_si_ausente, crear_tenido,
-- actualizar_tenido, transicionar_tenido — plus create the grupo unique index on
-- receta.tenido. Those can't be split: the moment the grupo index exists, any
-- recipe written by a not-yet-converted writer lands with a NULL grupo, which
-- the index treats as distinct, and a later backfill then collides. Index and
-- writers move together or not at all. Same landmine 29 was slimmed to avoid.
--
-- WHY articulo_tipo_id BECOMES NULLABLE: a true mixed batch has no single
-- articulo_tipo — that is the whole point. It stays populated for pure batches
-- (derived from the grupo's origen) so the downstream consumers that still read
-- it keep working until migration 32 moves them:
--   * despacho.sql snapshots partida.articulo_tipo_id onto venta lines
--   * facturacion resolves the TENIDO price through articulo_tipo_familia
-- Until 32 lands, a MIX partida therefore prices via the mes.partida.precio_kg
-- override, not the catalog. That is a deliberate interim, not a defect.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Add the column ─────────────────────────────────────────
ALTER TABLE mes.partida
    ADD COLUMN IF NOT EXISTS grupo_articulo_id INT REFERENCES grupo_articulo(id);

-- ── 2. Backfill from the 1:1 seed ─────────────────────────────
-- Every partida has a NOT NULL articulo_tipo_id, and migration 28 seeded exactly
-- one grupo per articulo_tipo, so this maps completely. Pure data move — no
-- trigger on mes.partida guards these columns.
UPDATE mes.partida p
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = p.articulo_tipo_id
  AND p.grupo_articulo_id IS NULL;

-- ── 3. Abort-guard ────────────────────────────────────────────
-- Every live partida must now carry a grupo. If this fires, migration 28's seed
-- is incomplete — STOP, fix 28, do not proceed to 31.
DO $$
DECLARE v_orphans INT;
BEGIN
    SELECT COUNT(*) INTO v_orphans
    FROM mes.partida
    WHERE fyh_elm IS NULL
      AND grupo_articulo_id IS NULL;
    IF v_orphans > 0 THEN
        RAISE EXCEPTION
            'Migration 30 abort: % live partida(s) have no grupo_articulo_id — migration 28 seed is incomplete.',
            v_orphans;
    END IF;
END $$;

-- ── 4. Relax articulo_tipo_id ─────────────────────────────────
-- Required before a mix partida can exist (a mix has no single type).
-- The column is NOT dropped: migration 32's consumers still read it.
ALTER TABLE mes.partida ALTER COLUMN articulo_tipo_id DROP NOT NULL;

-- ── VERIFY ────────────────────────────────────────────────────
-- Both keys must partition live partidas identically (expect 0 rows):
--   SELECT p.articulo_tipo_id, COUNT(DISTINCT p.grupo_articulo_id)
--   FROM mes.partida p WHERE p.fyh_elm IS NULL
--   GROUP BY 1 HAVING COUNT(DISTINCT p.grupo_articulo_id) <> 1;
--
-- Spot-check the two workaround artifacts carry a grupo like everything else:
--   SELECT p.id, p.articulo_tipo_id, p.grupo_articulo_id, g.codigo
--   FROM mes.partida p JOIN grupo_articulo g ON g.id = p.grupo_articulo_id
--   WHERE g.origen_articulo_tipo_id IN (15, 20);

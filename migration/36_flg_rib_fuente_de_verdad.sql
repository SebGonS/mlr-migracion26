-- ═══════════════════════════════════════════════════════════════
-- Step 36: flg_rib gets a real source of truth — the fabric, not the roll
--
-- DEPENDS ON: 35 (rib fabrics exist as real articulos).
--
-- WHY THIS IS SMALLER THAN IT LOOKED ────────────────────────────────
-- The original plan for 36 was: rewrite ~40 read sites across mes.sql,
-- 08_views.sql, calidad.sql and inventario.sql to derive rib-ness from the
-- articulo instead of reading item_rollo_detalle.flg_rib, then drop the column.
--
-- That turned out to be solving the wrong layer. item_rollo_detalle.flg_rib
-- lives on the SAME ROW as articulo_id (both columns on one PK'd table) — it
-- was never independent information, even before migration 35. The boolean
-- concept itself (MLR genuinely tracks peso_regular vs peso_rib as a permanent
-- business split) doesn't need to change. Only WHERE it's allowed to be set
-- independently of the fabric needs to change — because that independence is
-- exactly what let the original forged-rib pattern happen: someone could
-- create a roll with articulo_id = J 30/1 and flg_rib = true simultaneously,
-- asserting two contradictory things on one row.
--
-- WHAT THIS DOES ─────────────────────────────────────────────────
--   1. Adds articulo.flg_rib — ONE row per fabric (5 rows) instead of one
--      per roll (148,000+), and directly admin-editable, not name-derived
--      going forward (the ILIKE '%rib%' rule below is a ONE-TIME backfill
--      source, not a standing derivation — see the note at §1).
--   2. A BEFORE INSERT/UPDATE trigger on item_rollo_detalle derives
--      flg_rib from articulo_id automatically, overriding whatever a caller
--      supplies. This is the actual fix: it makes the original bug
--      STRUCTURALLY IMPOSSIBLE to repeat — a roll's flg_rib can never again
--      disagree with its own articulo, because nothing sets it directly
--      anymore.
--   3. Backfills existing rows to match (defensive; should already agree
--      post-35, this confirms it).
--
-- WHAT THIS DELIBERATELY DOES NOT DO ─────────────────────────────
-- Does NOT touch the ~40 existing read sites (mes.sql, 08_views.sql,
-- calidad.sql, inventario.sql, core.sql, compras.sql). They keep reading
-- item_rollo_detalle.flg_rib exactly as before — that read is now safe
-- forever, because the trigger guarantees the value. Converting those sites
-- to join articulo.flg_rib directly is CODE CLEANUP (fewer joins, one
-- source of truth visible in the query), not a correctness fix, and is
-- deferred to whenever it's convenient. Rewriting ~40 sites in one pass,
-- across 6 files, without the file-by-file dependent-checking rigor the
-- pricing conversion needed, is exactly the kind of scope that produces a
-- missed overload/view-column surprise — not worth the risk for a change
-- that isn't buying correctness.
--
-- Does NOT drop item_rollo_detalle.flg_rib. It is now a maintained,
-- always-correct CACHE of articulo.flg_rib, not dead weight — the ~40 sites
-- still read it, and it costs one join elimination per query. Dropping it is
-- only worth doing alongside the cleanup pass above, if ever.
-- ═══════════════════════════════════════════════════════════════


-- ── §1. articulo.flg_rib — the real source of truth ──────────────
-- Backfill source: nombre ILIKE '%rib%', the SAME rule confirmed empirically
-- in migration 35 (decision 13) against live production/recipe data — not a
-- guess repeated here, the same validated fact. This is a ONE-TIME backfill,
-- not a standing rule: the column is a normal editable boolean afterward, so
-- a future genuinely-rib fabric with a different name can still be flagged
-- correctly by a person. No trigger derives this column from nombre; only
-- the reverse (item_rollo_detalle FROM articulo) is automatic.
ALTER TABLE articulo ADD COLUMN IF NOT EXISTS flg_rib BOOLEAN NOT NULL DEFAULT false;

UPDATE articulo
SET flg_rib = true
WHERE nombre ILIKE '%rib%' AND flg_rib = false;


-- ── §2. Auto-derive item_rollo_detalle.flg_rib from the fabric ───
-- BEFORE INSERT OR UPDATE (not just INSERT): migration 35's own §3 repointed
-- articulo_id on existing rows — that exact operation, done by hand this
-- time, is what this trigger makes automatic and impossible to get wrong
-- going forward. If articulo_id changes, flg_rib recomputes with it.
--
-- Plain SELECT INTO, not STRICT: articulo_id is NOT NULL + FK-enforced, so a
-- matching row always exists; no ambiguity or missing-row case is reachable.
--
-- Fires alongside trg_bi_item_rollo_detalle_audit / trg_bu_..._audit
-- (migration/12) — independent columns, no ordering dependency between them.
CREATE OR REPLACE FUNCTION public.fn_trg_derive_flg_rib_item_rollo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    SELECT a.flg_rib INTO NEW.flg_rib
    FROM articulo a
    WHERE a.id = NEW.articulo_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_biu_item_rollo_detalle_derive_flg_rib ON item_rollo_detalle;
CREATE TRIGGER trg_biu_item_rollo_detalle_derive_flg_rib
BEFORE INSERT OR UPDATE OF articulo_id ON item_rollo_detalle
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_derive_flg_rib_item_rollo();


-- ── §3. Backfill existing rows to match ───────────────────────────
-- Defensive, not corrective — post-35, every row should already agree (rib
-- rolls point at rib articulos, regular rolls point at non-rib articulos).
-- This closes any straggler rather than assuming the invariant already holds.
UPDATE item_rollo_detalle ird
SET flg_rib = a.flg_rib
FROM articulo a
WHERE a.id = ird.articulo_id
  AND ird.flg_rib IS DISTINCT FROM a.flg_rib;


-- ── §4. Abort-guard ────────────────────────────────────────────────
DO $$
DECLARE v_desacuerdo INT;
BEGIN
    SELECT COUNT(*) INTO v_desacuerdo
    FROM item_rollo_detalle ird
    JOIN articulo a ON a.id = ird.articulo_id
    WHERE ird.flg_rib IS DISTINCT FROM a.flg_rib;

    IF v_desacuerdo > 0 THEN
        RAISE EXCEPTION
            'Migración 36 abortada: % fila(s) de item_rollo_detalle en desacuerdo con articulo.flg_rib tras el backfill.',
            v_desacuerdo;
    END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- VERIFY
-- ═══════════════════════════════════════════════════════════════
-- 1. articulo.flg_rib landed on exactly the expected 5 fabrics (3 genuine +
--    2 from migration 35):
--   SELECT id, nombre, flg_rib FROM articulo WHERE flg_rib = true ORDER BY id;
--
-- 2. Zero disagreement, same query the abort-guard used — confirms clean
--    even after commit, not just mid-transaction:
--   SELECT COUNT(*) FROM item_rollo_detalle ird
--   JOIN articulo a ON a.id = ird.articulo_id
--   WHERE ird.flg_rib IS DISTINCT FROM a.flg_rib;
--
-- 3. The trigger actually fires — repoint a throwaway row's articulo_id and
--    confirm flg_rib follows without being set explicitly (run in a
--    transaction you roll back, do not commit test data):
--   BEGIN;
--   UPDATE item_rollo_detalle SET articulo_id = (SELECT id FROM articulo WHERE nombre ILIKE '%rib%' LIMIT 1)
--   WHERE item_id = (SELECT item_id FROM item_rollo_detalle LIMIT 1)
--   RETURNING item_id, articulo_id, flg_rib;   -- flg_rib should read true
--   ROLLBACK;
--
-- 4. Roll counts still unchanged from migration 35's baseline (5190 rib /
--    142933 regular) — this migration touches no rolls, only adds a
--    derivation, so this should be identical:
--   SELECT SUM(CASE WHEN flg_rib THEN 1 ELSE 0 END) AS rib,
--          SUM(CASE WHEN flg_rib THEN 0 ELSE 1 END) AS regular
--   FROM item_rollo_detalle;
--
-- NEXT (optional, not urgent): convert the ~40 read sites in mes.sql,
-- 08_views.sql, calidad.sql, inventario.sql from ird.flg_rib to a join on
-- articulo.flg_rib, then drop item_rollo_detalle.flg_rib. Do this as ordinary
-- cleanup, file by file, with the same dependent-checking care the pricing
-- conversion needed — not as a single mechanical pass.


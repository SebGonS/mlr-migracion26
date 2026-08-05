-- ═══════════════════════════════════════════════════════════════
-- Step 35: rib becomes a real fabric (articulo), stops being a flag on the body
--
-- DEPENDS ON: 28-33b. Independent of 34 (which is deferred — articulo_tipo_id
-- columns stay for reference; nothing here needs them dropped).
--
-- WHY ─────────────────────────────────────────────────────────────
-- Rib trim has never had an identity. To receive a rib roll, someone created a
-- DUPLICATE ITEM pointing at the BODY's articulo with flg_rib = true:
--
--     item "Rollo J 30/1"      → item_rollo_detalle(articulo_id = J 30/1, flg_rib = false)
--     item "Rollo Rib J 30/1"  → item_rollo_detalle(articulo_id = J 30/1, flg_rib = true)
--                                                                  ↑ forged
--
-- So the database currently ASSERTS that ~5,190 rib rolls ARE jersey/gamuza/poly
-- body fabric. That is not a missing fact, it is a false one. Root cause is the
-- same 1:N that produced the forged mixes (migration 28): a roll could only
-- reference one fabric, and the bath needed two, so the second was disguised as
-- the first.
--
-- grupo_articulo_miembro (N:M) already removes that constraint. One real rib
-- fabric can be a member of MANY body grupos — exactly what the old model made
-- impossible. No restructuring needed; this migration is data, not schema.
--
-- WHAT THIS DOES ──────────────────────────────────────────────────
--   1. Creates real rib articulos (seed block — EDIT BEFORE RUNNING).
--   2. Adds each as a member of every body grupo that actually has rib rolls.
--   3. REPOINTS the forged items' articulo_id → the rib fabric. This is what
--      makes history stop lying: the rolls already exist and already point at
--      these items.
--   4. Creates clean replacement items for new receipts.
--   5. Soft-deletes the forged items so the old path cannot be used again.
--
-- ⚠ REPOINTING IS NOT "INVENTING DATA" — it is the opposite, and the
-- distinction matters because migration 28 decision 9 went the other way.
-- There, re-attributing a forged-mix roll required inventing a 50/50 split
-- between two fabrics, so the rolls were left alone. Here nothing is invented:
-- the roll IS rib, the schema just says otherwise. Replacing a known-false
-- claim with a true one is a correction, not a fabrication.
--
-- WHAT THIS DOES NOT DO ───────────────────────────────────────────
-- flg_rib is NOT retired. It stays written and read, deliberately: ~20 sites in
-- funciones/mes.sql, migration/08_views.sql and funciones/calidad.sql use it for
-- cantidad_regular/cantidad_rib counts, and registrar_pesaje_produccion uses it
-- to prorate peso_regular/peso_rib. Those must move to deriving rib-ness from
-- the articulo before the flag can go. That is a follow-up (36), and until it
-- lands the NEW rib items below MUST still carry flg_rib = true or every roll
-- count and weight proration silently breaks.
--
-- Routing is unaffected — verified 2026-07-19 that NOTHING routes on flg_rib
-- (no paso/operacion selection reads it). Construction-based routing is a
-- separate, later concern.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- §0. PRECHECK — run these FIRST, by hand. Do not skip.
-- ═══════════════════════════════════════════════════════════════
--
-- (a) Is articulo.articulo_tipo_id nullable? The new rib fabrics have no
--     articulo_tipo (that entity is retiring). If this returns 'NO', either
--     make it nullable or assign a throwaway tipo in §1.
--   SELECT column_name, is_nullable, data_type
--   FROM information_schema.columns
--   WHERE table_schema='public' AND table_name='articulo'
--   ORDER BY ordinal_position;
--
-- (b) How many forged items are in scope, and under which bodies?
--     Expect ~37 (20 at fibra=1, 17 at fibra=2 as of 2026-07-19).
--   SELECT a.fibra, COUNT(DISTINCT i.id) AS items,
--          string_agg(DISTINCT a.nombre, ' | ' ORDER BY a.nombre) AS cuerpos
--   FROM item_rollo_detalle ird
--   JOIN item i     ON i.id = ird.item_id
--   JOIN articulo a ON a.id = ird.articulo_id
--   WHERE ird.flg_rib = true AND i.fyh_elm IS NULL
--   GROUP BY a.fibra;
--
-- (c) GENUINE ribs must be excluded — they already have their own identity and
--     must NOT be touched. Confirmed rule (2026-07-19): an articulo whose own
--     nombre contains 'rib' is a real rib fabric that has been dyed under its
--     own identity (e.g. Rib Lycrado). Item names always say "Rib X" and are
--     NOT the signal; only articulo.nombre is.
--   SELECT id, nombre, fibra FROM articulo WHERE nombre ILIKE '%rib%';
--
-- (d) Nothing already occupies the codes/names §1 wants to create:
--   SELECT id, nombre, codigo FROM articulo
--   WHERE codigo IN ('RIBALGODON','RIBPOLIESTER');
--
-- (e) RESOLVED 2026-07-20 — articulo.articulo_tipo_id IS NOT NULL (confirmed via
--     §0a). Checked whether the three genuine ribs share one bucket tipo to
--     point at instead of creating new ones — they do NOT:
--         Rib Lycrado (3) → articulo_tipo 3  'Rib Lycrado'
--         Rib Acanalado(49)→ articulo_tipo 32 'Rib Acanalado'
--         Rib BVD (57)     → articulo_tipo 34 'Rib BVD'
--     Every genuine articulo has its OWN 1:1 articulo_tipo, same name — the
--     "near-duplicate shadow table" the original 28-34 rationale described.
--     There is no shared "Rib" bucket to borrow. §1 therefore creates one
--     matching articulo_tipo per new rib, following the SAME 1:1 pattern
--     already used by every other row — not a special case, and not a
--     revival of articulo_tipo as a meaningful key (nothing reads it for
--     pricing/recipes; it only exists to satisfy the FK).


-- ═══════════════════════════════════════════════════════════════
-- §1. SEED — the real rib fabrics.  ⚠ EDIT THIS BLOCK BEFORE RUNNING.
-- ═══════════════════════════════════════════════════════════════
-- Two fabrics, split on the body's fibra. Rationale and confidence differ per
-- row — read before accepting:
--
--  · Rib Algodón (fibra 1) — STRONG inference, effectively forced by chemistry.
--    Cotton-body baths run RX/DIR only (no disperse). A polyester rib in such a
--    bath would come out UNDYED, and these garments ship matching. So the rib
--    dyed in those baths is necessarily cellulosic.
--
--  · Rib Poliéster (fibra 2) — WEAKER, inferred from context, not forced.
--    Poly-body baths carry RX *and* DISP, which would dye either a cotton or a
--    poly rib acceptably. So "the rib under poly bodies is polyester" is a
--    reasonable read of intent, NOT a chemical necessity. Flagged so it can be
--    corrected without anyone assuming it was verified.
--
-- Operationally low-risk either way: a member's fibra only affects
-- vw_grupo_articulo.fibra_max (a MAX ceiling), and neither rib exceeds the body
-- it sits with, so the ceiling does not move.
--
-- GRANULARITY is deliberately coarse, consistent with existing practice —
-- 'F Poly' already lumps 12 blend variants under one recipe, and granularity is
-- a shade-tolerance judgement (handoff decision 3). If the plant later says
-- cotton rib is really 3 fabrics by yarn count, subdividing is ADDITIVE: create
-- the articulo, move membership. Nothing here needs undoing.
--
-- Adding a row: give nombre, codigo (UPPER, alnum only — matches the
-- articulo.codigo convention), fibra, and the body fibra it serves.
-- ⚠ NOT a TEMP TABLE, deliberately. First attempt used TEMP ... ON COMMIT DROP
-- and failed immediately ("relation _rib_seed does not exist") on the very next
-- statement — this environment executes each statement as a separate round
-- trip, almost certainly through a transaction-pooled connection, so a
-- session-scoped temp table can vanish before the script's next line even
-- though it's still "the same script". A real table survives that; it is
-- dropped explicitly at the end of this file instead of relying on session
-- teardown. DROP first for re-run safety (a prior failed attempt may have left
-- it behind).
DROP TABLE IF EXISTS _rib_seed;
CREATE TABLE _rib_seed (
    nombre        TEXT,
    codigo        TEXT,
    fibra         SMALLINT,
    fibra_cuerpo  SMALLINT   -- which body fibra this rib is used with
);

INSERT INTO _rib_seed (nombre, codigo, fibra, fibra_cuerpo) VALUES
    ('Rib Algodón',   'RIBALGODON',   1, 1),
    ('Rib Poliéster', 'RIBPOLIESTER', 2, 2);

-- §0(e): articulo.articulo_tipo_id is NOT NULL, and no shared "Rib" bucket
-- tipo exists to point at — every genuine rib has its own 1:1 tipo. So each
-- new rib fabric gets a matching articulo_tipo row first, same name, same
-- 1:1 shape as every other row in the table. codigo_canon on both tables is
-- set by their respective trg_bi_*_codigo_canon triggers.
--
-- Two SEPARATE statements, not one chained INSERT...WITH...RETURNING: on a
-- re-run after a partial failure, a CTE scoped to "just inserted" rows would
-- silently skip the articulo insert for any tipo that already existed from a
-- prior attempt. A plain lookup in the second statement finds the tipo either
-- way, so this is safe to re-run.
INSERT INTO articulo_tipo (nombre, codigo)
SELECT s.nombre, s.codigo
FROM _rib_seed s
WHERE NOT EXISTS (SELECT 1 FROM articulo_tipo t WHERE t.codigo = s.codigo);

INSERT INTO articulo (nombre, codigo, fibra, articulo_tipo_id)
SELECT s.nombre, s.codigo, s.fibra, t.id
FROM _rib_seed s
JOIN articulo_tipo t ON t.codigo = s.codigo
WHERE NOT EXISTS (SELECT 1 FROM articulo a WHERE a.codigo = s.codigo);


-- ═══════════════════════════════════════════════════════════════
-- §2. MEMBERSHIP — put each rib into the body grupos that actually use it
-- ═══════════════════════════════════════════════════════════════
-- Only grupos that HAVE rib rolls get a rib member. This is not a schema
-- assertion, it is a physical fact already in the data: those baths already
-- contained rib, which is exactly why the forged items exist.
--
-- ⚠ Existing approved recipes stay valid. A grupo going from {J 30/1} to
-- {J 30/1, Rib Algodón} is not a change of process — the bath ALWAYS held both.
-- Recipes bind to grupo_articulo_id (not to firma or membership), so nothing is
-- invalidated. The firma UNIQUE index recalculates via trigger; body grupos
-- differ by body, so no firma collision is reachable.
--
-- Genuine rib fabrics are excluded (a.nombre NOT ILIKE '%rib%'): a real rib
-- already has its own grupo and must not receive a generic rib member.
INSERT INTO grupo_articulo_miembro (grupo_articulo_id, articulo_id, fyh_cre)
SELECT DISTINCT gm.grupo_articulo_id, rib.id, NOW()
FROM item_rollo_detalle ird
JOIN item i          ON i.id = ird.item_id AND i.fyh_elm IS NULL
JOIN articulo a      ON a.id = ird.articulo_id
JOIN grupo_articulo_miembro gm ON gm.articulo_id = a.id
JOIN grupo_articulo g          ON g.id = gm.grupo_articulo_id AND g.fyh_elm IS NULL
JOIN _rib_seed s     ON s.fibra_cuerpo = a.fibra
JOIN articulo rib    ON rib.codigo = s.codigo
WHERE ird.flg_rib = true
  AND a.nombre NOT ILIKE '%rib%'          -- never touch a genuine rib fabric
ON CONFLICT (grupo_articulo_id, articulo_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- §3. REPOINT — the forged items now reference the rib fabric
-- ═══════════════════════════════════════════════════════════════
-- This is the step that fixes history. Rolls point at items; items point at
-- articulo. Repointing here re-resolves every already-received rib roll from
-- "is jersey" to "is rib".
--
-- flg_rib is left TRUE on purpose — see the header. It is redundant with the
-- articulo now, but ~20 count/pesaje sites still read it, and they move in 36.
--
-- ⚠ item.codigo goes STALE here and is not repaired. fn_trg_gen_codigo_item_rollo
-- only fires AFTER INSERT and only when codigo IS NULL, so a repointed item keeps
-- e.g. 'R-RB-J301PEI-1' while pointing at Rib Algodón. Accepted, not overlooked:
-- these items are soft-deleted in §5, so the stale code is a historical label on
-- a closed record. Do NOT "fix" it by regenerating — the code appears on printed
-- guías and past documents must keep reading as they were issued.
UPDATE item_rollo_detalle ird
SET articulo_id = rib.id,
    fyh_mod     = NOW()
FROM item i, articulo a, _rib_seed s, articulo rib
WHERE i.id  = ird.item_id
  AND a.id  = ird.articulo_id
  AND s.fibra_cuerpo = a.fibra
  AND rib.codigo = s.codigo
  AND ird.flg_rib = true
  AND i.fyh_elm IS NULL
  AND a.nombre NOT ILIKE '%rib%';         -- genuine ribs already point at themselves


-- ═══════════════════════════════════════════════════════════════
-- §4. CLEAN ITEMS — what new rib receipts land on
-- ═══════════════════════════════════════════════════════════════
-- One item per rib fabric, replacing ~37 near-identical forged ones. The body
-- association is NOT lost: it lives on the partida, which is where it belongs.
--
-- ⚠ CLIENT-FACING NAME CHANGE. Guías/paperwork that print the item name will
-- read 'Rollo Rib Algodón' instead of 'Rollo Rib J 30/1'. Confirm that is
-- acceptable on printed documents before running; if the body reference must
-- appear, keep per-body items instead and adjust §5 to not soft-delete them.
--
-- codigo is written explicitly rather than left to the trigger: item.codigo is
-- NOT NULL, so it cannot be inserted NULL for the trigger's `WHERE codigo IS
-- NULL` to match. Format mirrors fn_trg_gen_codigo_item_rollo exactly:
-- R-RB-{articulo.codigo}-{fibra}.
--
-- item_tipo_id / unidad_id are copied from an existing rollo item so this does
-- not hardcode ids that differ per environment.
WITH plantilla AS (
    SELECT i.item_tipo_id, i.unidad_id
    FROM item i
    JOIN item_rollo_detalle ird ON ird.item_id = i.id
    WHERE i.fyh_elm IS NULL
    LIMIT 1
),
nuevos AS (
    INSERT INTO item (codigo, codigo_canon, nombre, item_tipo_id, unidad_id, fyh_cre)
    SELECT
        UPPER('R-RB-' || rib.codigo || '-' || rib.fibra),
        LOWER('r-rb-' || rib.codigo || '-' || rib.fibra),
        'Rollo ' || rib.nombre,
        p.item_tipo_id,
        p.unidad_id,
        NOW()
    FROM _rib_seed s
    JOIN articulo rib ON rib.codigo = s.codigo
    CROSS JOIN plantilla p
    WHERE NOT EXISTS (
        SELECT 1 FROM item i2
        WHERE i2.codigo = UPPER('R-RB-' || rib.codigo || '-' || rib.fibra)
    )
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (item_id, articulo_id, flg_rib, fyh_cre)
SELECT n.id, rib.id, true, NOW()     -- flg_rib TRUE: still load-bearing until 36
FROM nuevos n
JOIN _rib_seed s  ON UPPER('R-RB-' || s.codigo || '-' || s.fibra) = n.codigo
JOIN articulo rib ON rib.codigo = s.codigo;


-- ═══════════════════════════════════════════════════════════════
-- §5. CLOSE THE OLD PATH — soft-delete the forged items
-- ═══════════════════════════════════════════════════════════════
-- Soft-delete the ITEM, never the articulo — same pattern as migration 28's
-- forged-mix handling. Rolls are received against items, so this blocks new
-- receipts while every historical roll still joins cleanly.
--
-- Identified by "was repointed in §3": flg_rib = true AND articulo is now one of
-- the seeded ribs, but the item is not one of the §4 replacements.
UPDATE item i
SET fyh_elm = NOW(),
    usr_elm = NULL          -- system migration, no acting user
FROM item_rollo_detalle ird, articulo rib, _rib_seed s
WHERE ird.item_id = i.id
  AND rib.id = ird.articulo_id
  AND rib.codigo = s.codigo
  AND ird.flg_rib = true
  AND i.fyh_elm IS NULL
  AND i.codigo <> UPPER('R-RB-' || rib.codigo || '-' || rib.fibra);  -- keep §4's


-- ═══════════════════════════════════════════════════════════════
-- §6. ABORT-GUARD
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_huerfanos INT;
    v_sin_item  INT;
    v_genuinos  INT;
BEGIN
    -- Every live flg_rib item must now point at a rib fabric, not a body.
    SELECT COUNT(*) INTO v_huerfanos
    FROM item_rollo_detalle ird
    JOIN item i     ON i.id = ird.item_id AND i.fyh_elm IS NULL
    JOIN articulo a ON a.id = ird.articulo_id
    WHERE ird.flg_rib = true
      AND a.nombre NOT ILIKE '%rib%';

    -- Each seeded rib fabric must have exactly one live receiving item.
    SELECT COUNT(*) INTO v_sin_item
    FROM _rib_seed s
    JOIN articulo rib ON rib.codigo = s.codigo
    WHERE NOT EXISTS (
        SELECT 1 FROM item_rollo_detalle ird
        JOIN item i ON i.id = ird.item_id AND i.fyh_elm IS NULL
        WHERE ird.articulo_id = rib.id
    );

    -- Genuine ribs must be untouched: still their own articulo, still membered.
    SELECT COUNT(*) INTO v_genuinos
    FROM articulo a
    WHERE a.nombre ILIKE '%rib%'
      AND a.codigo NOT IN (SELECT codigo FROM _rib_seed)
      AND NOT EXISTS (
          SELECT 1 FROM grupo_articulo_miembro gm WHERE gm.articulo_id = a.id
      );

    IF v_huerfanos > 0 OR v_sin_item > 0 OR v_genuinos > 0 THEN
        RAISE EXCEPTION
            'Migración 35 abortada: % item(s) rib aún apuntan al cuerpo, % tela(s) rib sin item receptor, % rib genuino(s) sin grupo.',
            v_huerfanos, v_sin_item, v_genuinos;
    END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- CLEANUP — drop the seed staging table now that §1-§6 are done with it.
-- Not ON COMMIT DROP (see §1's note); dropped explicitly instead.
-- ═══════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS _rib_seed;


-- ═══════════════════════════════════════════════════════════════
-- VERIFY — run these AFTER the script above, in a fresh query/connection.
-- Written against the literal codes, not _rib_seed (already dropped by the
-- CLEANUP step, and these are meant to be re-run independently later anyway).
-- ═══════════════════════════════════════════════════════════════
-- 1. Historical rolls now resolve to a rib fabric (was: the body's name):
--   SELECT a.nombre AS tela, COUNT(*) AS rollos
--   FROM inventario.lote l
--   JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
--   JOIN articulo a ON a.id = ird.articulo_id
--   WHERE ird.flg_rib = true
--   GROUP BY a.nombre ORDER BY rollos DESC;
--
-- 2. One rib fabric now spans many body grupos — the thing the old 1:N
--    forbade, and the reason the forged items existed:
--   SELECT a.nombre AS rib, COUNT(*) AS grupos_cuerpo
--   FROM grupo_articulo_miembro gm
--   JOIN articulo a ON a.id = gm.articulo_id
--   WHERE a.codigo IN ('RIBALGODON','RIBPOLIESTER')
--   GROUP BY a.nombre;
--
-- 3. Roll counts did NOT move. flg_rib is untouched, so cantidad_regular /
--    cantidad_rib must be identical before and after. Capture before running:
--   SELECT SUM(CASE WHEN ird.flg_rib THEN 1 ELSE 0 END) AS rib,
--          SUM(CASE WHEN ird.flg_rib THEN 0 ELSE 1 END) AS regular
--   FROM inventario.lote l
--   JOIN item_rollo_detalle ird ON ird.item_id = l.item_id;
--
-- 4. The receipt picker is clean — ~37 forged items gone, 2 live rib items:
--   SELECT i.codigo, i.nombre, i.fyh_elm IS NULL AS activo
--   FROM item i JOIN item_rollo_detalle ird ON ird.item_id = i.id
--   WHERE ird.flg_rib = true ORDER BY activo DESC, i.codigo;
--
-- NEXT (migration 36): retire flg_rib. Move the ~20 count/pesaje sites to derive
-- rib-ness from the articulo, then drop item_rollo_detalle.flg_rib. Do not start
-- it until this has soaked — the flag is the only thing keeping roll counts and
-- weight proration correct today.


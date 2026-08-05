-- ═══════════════════════════════════════════════════════════════
-- Step 37: decompose articulo.nombre — construction becomes real data
--
-- DEPENDS ON: 35, 36 (rib is a fabric, flg_rib has a source of truth).
--
-- WHY ─────────────────────────────────────────────────────────────
-- articulo.nombre is a concatenated spec string:
--
--     J        30/1        Pei         Poly / 6535 / …
--     ↑           ↑           ↑              ↑
--   construction  yarn      prep        fiber/blend
--
-- and articulo_tipo, fibra and flg_rib are three LOSSY PROJECTIONS of it —
-- each capturing a different slice badly. Migrations 28-36 replaced the first
-- and third. This one extracts the attribute those were really groping at:
-- construction (the knit structure), which is what any future routing rule has
-- to key on.
--
-- ⚠ ROUTING IS THE POINT, AND IT MUST NOT KEY ON flg_rib. `Rib Lycrado` NEEDS
-- termofijado despite being rib — so "is rib" and "needs finishing" are
-- orthogonal facts. Routing keys on construction + composition, never on the
-- rib flag, even now that the flag is trustworthy (migration 36). Being
-- CORRECT does not make it the right DIMENSION.
--
-- WHAT THIS DOES ──────────────────────────────────────────────────
--   1. Fixes 3 articulos with NULL codigo/codigo_canon (pre-existing gap).
--   2. Creates the `construccion` catalog + articulo.construccion_id FK.
--   3. Adds articulo.titulo (yarn count) and articulo.preparacion, nullable.
--   4. Backfills ONLY what parses unambiguously — 43 of 49 rows. The rest stay
--      NULL on purpose, for someone who knows the fabrics to fill in.
--
-- NULL IS A FIRST-CLASS ANSWER HERE. These columns are normal editable
-- attributes, NOT trigger-derived from nombre. The parse below is a ONE-TIME
-- backfill, not a standing rule — a future fabric named anything at all can be
-- classified correctly by a person. Do not add a trigger that re-derives these
-- from nombre; that would re-create the lossy-projection problem this migration
-- exists to end.
--
-- WHAT THIS DELIBERATELY OMITS ────────────────────────────────────
-- No composition/blend column (`Poly`, `6535`, `3070`, `Alg 100%`). That data
-- is entangled with `fibra` (= count of dye systems needed), and the backlogged
-- "dye systems as an explicit set" rework is where both belong together. Adding
-- a `mezcla TEXT` now would produce a SECOND lossy projection of composition to
-- reconcile against `fibra` later — the exact mistake being unwound.
-- ═══════════════════════════════════════════════════════════════


-- ── §1. Fix the 3 articulos with NULL codigo ─────────────────────
-- Gam 30/1 (63), Spun 20/1 (64), F Lycra 20/1 Pei (65) — the three highest
-- ids, created AFTER migration 04's codigo backfill. trg_bi_articulo_codigo_canon
-- only derives codigo_canon FROM codigo; nothing generates codigo itself, so
-- manually-created articulos silently get neither. Same formula as
-- migration/04_alter_legacy_tables.sql so the values are consistent with the
-- other 46 rows. The trigger fills codigo_canon on UPDATE.
UPDATE articulo
SET codigo = UPPER(regexp_replace(nombre, '[^a-zA-Z0-9]', '', 'g'))
WHERE codigo IS NULL;


-- ── §2. construccion catalog ─────────────────────────────────────
-- A catalog table, not a TEXT column or enum: this is the routing key, so it
-- needs a stable id that routing rules can reference without depending on a
-- spelling. Matches house style (colorante_tipo, insumo_tipo, tipo_receta).
CREATE TABLE IF NOT EXISTS construccion (
    id           SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo       TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL UNIQUE,
    nombre       TEXT NOT NULL,
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_bi_construccion_codigo_canon ON construccion;
CREATE TRIGGER trg_bi_construccion_codigo_canon
BEFORE INSERT OR UPDATE ON construccion
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

-- ⚠ 'FRANELA' IS AN ASSUMPTION, FLAGGED FOR CONFIRMATION.
-- The `F` prefix (17 rows — the largest single group) could mean Franela OR
-- Felpa. That matters because *felpa francesa* IS French Terry in Spanish —
-- so `F Poly` and `French Terry` (id 16) may be the SAME construction under two
-- naming conventions, or two genuinely different fabrics.
--
-- Seeded as separate rows because that is the reversible direction: if the
-- plant confirms they are the same, merging is two statements —
--     UPDATE articulo SET construccion_id = (SELECT id FROM construccion WHERE codigo='FRANELA')
--     WHERE construccion_id = (SELECT id FROM construccion WHERE codigo='FRENCHTERRY');
--     DELETE FROM construccion WHERE codigo = 'FRENCHTERRY';
-- Splitting a wrongly-merged pair afterwards would instead need per-row
-- judgement on all 18. Guess in the direction that is cheap to undo.
INSERT INTO construccion (codigo, nombre) VALUES
    ('JERSEY',      'Jersey'),
    ('FRANELA',     'Franela'),
    ('GAMUZA',      'Gamuza'),
    ('RIB',         'Rib'),
    ('FRENCHTERRY', 'French Terry'),
    ('MINIWAFLE',   'MiniWafle')
ON CONFLICT (codigo) DO NOTHING;

GRANT SELECT ON construccion TO authenticated;


-- ── §3. The new articulo columns ─────────────────────────────────
-- All nullable. NULL means "not yet classified", which is a real and expected
-- state for 6 rows after this runs — not a defect to be defaulted away.
ALTER TABLE articulo
    ADD COLUMN IF NOT EXISTS construccion_id SMALLINT REFERENCES construccion(id),
    ADD COLUMN IF NOT EXISTS titulo          TEXT,   -- yarn count, e.g. '30/1', '20/9'
    ADD COLUMN IF NOT EXISTS preparacion     TEXT;   -- 'Peinado' | 'Cardado'


-- ── §4. Backfill construccion — prefix match, unambiguous rows only ──
-- Order matters only in that each pattern is mutually exclusive; verified
-- against the full 49-row census (2026-07-20).
UPDATE articulo a SET construccion_id = c.id
FROM construccion c
WHERE c.codigo = 'JERSEY'
  AND a.construccion_id IS NULL
  AND a.nombre ~ '^J '           -- 'J 30/1 Pei', 'J Poly 6535', 'J Lycra'
  AND a.nombre NOT LIKE '%-%';   -- excludes the forged mix 'J 30/1- Gam 50/1'

UPDATE articulo a SET construccion_id = c.id
FROM construccion c
WHERE c.codigo = 'FRANELA' AND a.construccion_id IS NULL AND a.nombre ~ '^F ';

UPDATE articulo a SET construccion_id = c.id
FROM construccion c
WHERE c.codigo = 'GAMUZA' AND a.construccion_id IS NULL AND a.nombre ~* '^Gam';

-- Rib matches on the flg_rib column (migration 36's source of truth), NOT on the
-- name — same rule, but reading the fact we already established rather than
-- re-deriving it from a string.
UPDATE articulo a SET construccion_id = c.id
FROM construccion c
WHERE c.codigo = 'RIB' AND a.construccion_id IS NULL AND a.flg_rib = true;

UPDATE articulo a SET construccion_id = c.id
FROM construccion c
WHERE c.codigo = 'FRENCHTERRY' AND a.construccion_id IS NULL AND a.nombre ~* '^French';

UPDATE articulo a SET construccion_id = c.id
FROM construccion c
WHERE c.codigo = 'MINIWAFLE' AND a.construccion_id IS NULL AND a.nombre ~* '^MiniWafle';

-- DELIBERATELY LEFT NULL (6 rows) — each needs a person, not a regex:
--   Full Lycra (6), Full Lycra 30/1 (22), Full Lycra Melange (45)
--       'Full Lycra' describes COMPOSITION (high elastane), not a knit structure.
--       The underlying construction is probably Jersey, but that is a guess.
--   Spun (59), Spun 20/1 (64)
--       'Spun' is a SPINNING METHOD (staple-fibre yarn), not a construction.
--   J 30/1- Gam 50/1 (28)
--       The forged two-fabric mix (handoff decision 9). Genuinely has TWO
--       constructions; a single FK cannot express it. Leave NULL — do not
--       pick one. Its rolls are all still in stock and never consumed.


-- ── §5. Backfill titulo + preparacion ────────────────────────────
-- Yarn count: first NN/NN occurrence. Blend ratios ('6535', '3070', '5050')
-- have no slash and are correctly skipped.
UPDATE articulo
SET titulo = (regexp_match(nombre, '(\d+/\d+)'))[1]
WHERE titulo IS NULL AND nombre ~ '\d+/\d+';

UPDATE articulo SET preparacion = 'Peinado'
WHERE preparacion IS NULL AND nombre ~* '\mPei\M';

UPDATE articulo SET preparacion = 'Cardado'
WHERE preparacion IS NULL AND nombre ~* '\mCard\M';


-- ── §6. Abort-guard ──────────────────────────────────────────────
DO $$
DECLARE
    v_sin_codigo    INT;
    v_sin_constr    INT;
    v_rib_mal       INT;
BEGIN
    SELECT COUNT(*) INTO v_sin_codigo
    FROM articulo WHERE codigo IS NULL OR codigo_canon IS NULL;

    -- EXACTLY 6 rows are expected to remain unclassified (see §4's list).
    -- More means a pattern under-matched; FEWER means one over-matched and
    -- silently classified a row that needs human judgement — the worse of the
    -- two, since it looks like success. Checked with <>, not >.
    SELECT COUNT(*) INTO v_sin_constr
    FROM articulo WHERE construccion_id IS NULL;

    -- Every rib fabric must have landed on RIB — cross-checks §4 against
    -- migration 36's flg_rib, which is independently maintained.
    SELECT COUNT(*) INTO v_rib_mal
    FROM articulo a
    LEFT JOIN construccion c ON c.id = a.construccion_id
    WHERE a.flg_rib = true AND COALESCE(c.codigo, '') <> 'RIB';

    IF v_sin_codigo > 0 OR v_sin_constr <> 6 OR v_rib_mal > 0 THEN
        RAISE EXCEPTION
            'Migración 37 abortada: % articulo(s) sin codigo, % sin construccion (se esperaban 6), % rib mal clasificado(s).',
            v_sin_codigo, v_sin_constr, v_rib_mal;
    END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- VERIFY
-- ═══════════════════════════════════════════════════════════════
-- 1. Distribution — expect J 14, F 17, Gam 5, Rib 5, FrenchTerry 1,
--    MiniWafle 1, NULL 6:
--   SELECT COALESCE(c.nombre, '(sin clasificar)') AS construccion, COUNT(*)
--   FROM articulo a LEFT JOIN construccion c ON c.id = a.construccion_id
--   GROUP BY 1 ORDER BY 2 DESC;
--
-- 2. The 6 unclassified rows are exactly the ones §4 names:
--   SELECT id, nombre FROM articulo WHERE construccion_id IS NULL ORDER BY id;
--
-- 3. Spot-check the parse end to end:
--   SELECT a.id, a.nombre, c.nombre AS construccion, a.titulo, a.preparacion, a.fibra
--   FROM articulo a LEFT JOIN construccion c ON c.id = a.construccion_id
--   ORDER BY c.nombre NULLS LAST, a.nombre;
--
-- OPEN QUESTION FOR THE PLANT — blocks nothing, cheap to resolve:
--   Is `F` (17 rows: F Poly, F Lycra, F Alg 100%) the same construction as
--   `French Terry` (1 row)? If *felpa* and *French Terry* name one fabric here,
--   run the two-statement merge in §2's comment. If they are distinct knits,
--   confirm what `F` stands for and rename the catalog row accordingly.
--
-- NEXT: with construction as data, routing rules can key on
-- (construccion_id, fibra, composition) instead of the flg_rib heuristic the
-- backlog warns against. Composition is still un-normalized — that is the
-- dye-systems rework, not started.

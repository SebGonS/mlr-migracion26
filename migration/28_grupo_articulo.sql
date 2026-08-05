-- ═══════════════════════════════════════════════════════════════
-- Step 28: grupo_articulo — extract the dye substrate out of articulo_tipo
--
-- WHY ─────────────────────────────────────────────────────────────
-- articulo_tipo currently does four jobs at once:
--   1. product taxonomy        (articulo.articulo_tipo_id)
--   2. recipe identity         (receta.tenido.articulo_tipo_id)
--   3. pricing bucket          (doc.catalogo_precios.articulo_tipo_id + articulo_tipo_familia)
--   4. batch composition guard (mes.partida.articulo_tipo_id)
--
-- Jobs 2-4 are properties of "the fabric the bath dyes as one unit", which
-- has no entity. A dye bath may legitimately hold rolls of several articulos;
-- that combination has its own chemistry, its own cost, and its own price.
-- Job 1 is vacuous: articulo_tipo is a near-duplicate of articulo (same
-- names, ~1:1 in live data — there is no 'Jersey' or 'Gamuza' node, the
-- values ARE fabric specs like 'J 30/1 Pei'). So articulo_tipo retires
-- entirely once 2-4 move here (see migrations 29-31).
--
-- ROOT CAUSE: articulo.articulo_tipo_id is a SINGLE FK (1:N). A fabric
-- belongs to exactly one type, so a mixed batch CANNOT reference existing
-- fabrics — operators must forge new ones. The workaround is live in prod:
--   'Jersey/Gamuza'    → articulo_tipo with ZERO articulos (pure placeholder)
--   'J 30/1-Gam 50/1'  → forged articulo + forged items 'Rollo J 30/1- Gam 50/1'
-- Those rows ARE this entity, hand-built. The duplicate master data is the
-- mechanical consequence of modelling an N:M relationship as 1:N.
--
-- NAMING: this is the DYE SUBSTRATE — "what goes in the bath together" —
-- NOT a generic article bucket. It is not the pricing family (that stays
-- separate as grupo_articulo_familia in migration 31: pricing-similarity and
-- dyeing-similarity cross-cut) and it is not a product taxonomy (if a real
-- Jersey/Gamuza/Franela taxonomy is wanted later, that is a NEW entity, not
-- this one). Do not file other groupings here — that accretion is exactly
-- how articulo_tipo ended up with four jobs.
--
-- WHAT THIS FILE DOES ─────────────────────────────────────────────
-- Additive only (plus one dead-column drop, see bottom). Creates
-- grupo_articulo + grupo_articulo_miembro and seeds one grupo per existing
-- articulo_tipo, with that type's articulos as members. Nothing reads it yet
-- — zero behaviour change. Seeding this way preserves current recipe
-- granularity exactly: 'F Poly' becomes ONE grupo holding all 12 blend
-- variants, which is how they resolve a recipe today.
--
-- THE GUARDRAIL ───────────────────────────────────────────────────
-- Consumers bind to grupo_articulo.id ONLY — never to (articulo_tipo, fibra).
-- That surrogate is what lets the backlogged attribute-normalisation work
-- rewrite grupo_articulo_miembro's columns later without touching receta,
-- catalogo_precios, or mes.partida. Do not let a consumer reach through
-- grupo_articulo_miembro to key on a member tuple.
--
-- NOT IN THIS FILE (deliberate — separate migrations, separate review) ──
--   29: receta.tenido re-key to grupo_articulo_id (+ re-key
--       uq_receta_tenido_aprobada; mind trg_bu_tenido_immutable's column list)
--   30: crear_partida guard swap + fibra ceiling check
--   31: doc.catalogo_precios re-key + articulo_tipo_familia → grupo_articulo_familia
--   32: fibra renames — articulo.fibra→fibra_requerida (what the fabric NEEDS)
--       vs partida/receta/catalogo .fibra→fibra_ejecutada (what we CHOSE to
--       run). 69 refs across 5 funciones/ files + the crear_partida JSON
--       contract. Mechanical, breaking, own pass.
--   33: retire articulo_tipo once nothing references it.
--
-- fibra is NOT a grupo_articulo column. Per the fibra memory: `run` may be
-- LESS than `required` on purpose (colores jaspeados — reactive-only on a
-- cotton/poly leaves the poly white). grupo_articulo CONSTRAINS fibra as an
-- upper bound (migration 30); it does not determine it.
-- ═══════════════════════════════════════════════════════════════

-- ── grupo_articulo ────────────────────────────────────────────
-- The fabric a bath dyes as one unit. Identity is its MEMBER SET:
--   1 member  → a pure batch (today's articulo_tipo, one-to-one)
--   N members → a mixed batch (today's forged articulo_tipo)
-- Recipe, cost basis and price bind to this id.
CREATE TABLE IF NOT EXISTS grupo_articulo (
    id           INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo       TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL UNIQUE,
    nombre       TEXT NOT NULL,

    -- Canonical signature of the member set (sorted articulo_ids, comma-joined).
    -- Maintained by trigger from grupo_articulo_miembro; UNIQUE so the same
    -- combination cannot be defined twice and drift into two recipes/prices.
    -- NULL while a grupo has no members yet (seeding, or an orphan awaiting
    -- fixup) — Postgres UNIQUE permits multiple NULLs by design.
    firma        TEXT UNIQUE,

    -- Migration cross-reference (nullable; drops in 33 with articulo_tipo).
    -- Same pattern as tercero.cliente_id.
    origen_articulo_tipo_id SMALLINT REFERENCES articulo_tipo(id),

    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    usr_elm INT, fyh_elm TIMESTAMPTZ
);

CREATE TRIGGER trg_bi_grupo_articulo_codigo_canon
BEFORE INSERT OR UPDATE ON grupo_articulo
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

CREATE UNIQUE INDEX IF NOT EXISTS uq_grupo_articulo_origen_at
    ON grupo_articulo(origen_articulo_tipo_id) WHERE origen_articulo_tipo_id IS NOT NULL;

-- ── grupo_articulo_miembro ────────────────────────────────────
-- N:M — THE point of this migration. A fabric may belong to its own pure
-- grupo AND to any number of mixes. That is exactly what the 1:N
-- articulo.articulo_tipo_id made impossible, and why the forged articulos exist.
--
-- Keyed on articulo (NOT articulo_tipo): articulo is the real catalog entity;
-- articulo_tipo is a near-duplicate of it. Keying members here is what makes
-- articulo_tipo's substrate role redundant and therefore retirable in 33.
--
-- Forged legacy articulos (e.g. 'J 30/1- Gam 50/1') STAY as members even after
-- their mix is re-pointed at the real fabrics: that fabric really was in those
-- baths, so history joins cleanly. New rolls are blocked by soft-deleting the
-- ITEM (item.fyh_elm), not the articulo — rolls are received against items, and
-- articulo has no soft-delete columns.
CREATE TABLE IF NOT EXISTS grupo_articulo_miembro (
    grupo_articulo_id INT NOT NULL REFERENCES grupo_articulo(id) ON DELETE CASCADE,
    articulo_id       INT NOT NULL REFERENCES articulo(id),
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (grupo_articulo_id, articulo_id)
);
CREATE INDEX IF NOT EXISTS idx_grupo_articulo_miembro_articulo
    ON grupo_articulo_miembro(articulo_id);

-- ── firma maintenance ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_grupo_articulo_recalc_firma(p_grupo_articulo_id INT)
RETURNS VOID LANGUAGE sql AS $$
    UPDATE grupo_articulo SET firma = (
        SELECT string_agg(articulo_id::text, ',' ORDER BY articulo_id)
        FROM grupo_articulo_miembro WHERE grupo_articulo_id = p_grupo_articulo_id
    )
    WHERE id = p_grupo_articulo_id;
$$;

CREATE OR REPLACE FUNCTION fn_trg_grupo_articulo_firma()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM fn_grupo_articulo_recalc_firma(NEW.grupo_articulo_id);
    END IF;
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        PERFORM fn_grupo_articulo_recalc_firma(OLD.grupo_articulo_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_aiud_grupo_articulo_miembro_firma
AFTER INSERT OR UPDATE OR DELETE ON grupo_articulo_miembro
FOR EACH ROW EXECUTE FUNCTION fn_trg_grupo_articulo_firma();

-- ── vw_grupo_articulo ─────────────────────────────────────────
-- Read model. fibra_max is the CEILING migration 30 enforces (partida.fibra
-- <= fibra_max): if any member needs disperse, the bath does. It is NOT the
-- batch's fibra — running fewer systems is a legitimate choice (colores
-- jaspeados). Never assign from this; only compare against it.
--
-- fibra_max SEMANTICS: a fabric's fibra is |{dye classes it needs}| —
-- cotton={reactive}=1, cotton/poly blend={reactive,disperse}=2. A mix needs
-- the UNION of its members' classes, so the true ceiling is |union|. MAX() is
-- a correct shortcut ONLY because MLR's classes are NESTED today
-- ({reactive} ⊂ {reactive,disperse}): everything has a cotton base, disperse
-- is the sole add-on, and there is no disperse-only fabric. If a pure-poly
-- (disperse-only) or a third class (e.g. acid, for wool/nylon) ever enters,
-- MAX UNDERCOUNTS — two disjoint fibra=1 fabrics would truly need 2 — and this
-- must become a set-union over an explicit dye-system model (the fibra side of
-- the backlogged attribute-normalisation; see the fibra memory).
--
-- CONTAINED HERE for now (kept runnable as a self-contained migration while
-- unverified). ON FINALIZE: move this view + its GRANT to migration/08_views.sql
-- per the views-live-in-08 convention, and delete it from here.
CREATE OR REPLACE VIEW vw_grupo_articulo AS
SELECT
    g.id                                  AS grupo_articulo_id,
    g.codigo,
    g.nombre,
    g.firma,
    COUNT(gm.articulo_id)::int            AS n_miembros,
    COUNT(gm.articulo_id) > 1             AS flg_mezcla,
    MAX(a.fibra)                          AS fibra_max,
    bool_or(a.fibra IS NULL)              AS flg_fibra_incompleta,
    string_agg(a.nombre, ' + ' ORDER BY a.nombre) AS miembros
FROM grupo_articulo g
LEFT JOIN grupo_articulo_miembro gm ON gm.grupo_articulo_id = g.id
LEFT JOIN articulo a                ON a.id = gm.articulo_id
WHERE g.fyh_elm IS NULL
GROUP BY g.id, g.codigo, g.nombre, g.firma;

-- ═══════════════════════════════════════════════════════════════
-- SEED — one grupo per articulo_tipo, members = that type's articulos.
-- Behaviour-preserving by construction: whatever resolves a recipe today
-- via articulo_tipo resolves the same one via its seeded grupo.
--
-- ⚠ PRECHECK FIRST — articulo_tipo.codigo was NEVER enforced NOT NULL/UNIQUE.
-- migration/04_alter_legacy_tables.sql backfills it as
-- UPPER(regexp_replace(nombre,'[^a-zA-Z0-9]','','g')) and then leaves the
-- enforcement steps COMMENTED OUT pending review. grupo_articulo.codigo is
-- both NOT NULL and UNIQUE, so a duplicate or NULL code aborts this seed:
--
--   SELECT codigo, COUNT(*) FROM articulo_tipo
--   WHERE codigo IS NOT NULL GROUP BY codigo HAVING COUNT(*) > 1;
--   SELECT id, nombre FROM articulo_tipo WHERE codigo IS NULL;
--
-- The strip-non-alphanum formula collides readily ('J 30/1' and 'J-30/1'
-- both → 'J301'). Fix collisions in articulo_tipo before seeding — do NOT
-- paper over them here; these codes are about to become a real key.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO grupo_articulo (codigo, nombre, origen_articulo_tipo_id)
SELECT at.codigo, at.nombre, at.id
FROM articulo_tipo at
WHERE NOT EXISTS (
    SELECT 1 FROM grupo_articulo g WHERE g.origen_articulo_tipo_id = at.id
);

INSERT INTO grupo_articulo_miembro (grupo_articulo_id, articulo_id)
SELECT g.id, a.id
FROM grupo_articulo g
JOIN articulo a ON a.articulo_tipo_id = g.origen_articulo_tipo_id
ON CONFLICT DO NOTHING;

GRANT SELECT ON grupo_articulo          TO authenticated;
GRANT SELECT ON grupo_articulo_miembro  TO authenticated;
GRANT SELECT ON vw_grupo_articulo       TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- articulo.grupo_articulo (legacy text column) — DROP DEFERRED, kept.
--
-- The bare drop (attempted 2026-07-18) reported 5 live dependents, all legacy
-- views retained for debugging:
--   vw_despacho, vw_partidas_resumen_v2, vw_partidas_x_programar,
--   vw_produccion_acabados, vw_resumen_auditorias
--
-- Dropping the column is COSMETIC, not functional: the new grupo_articulo
-- TABLE (public.grupo_articulo) does NOT collide with this COLUMN
-- (articulo.grupo_articulo) — different namespaces — so nothing in this
-- migration or 29/30 needs it gone. Deferred to a future cleanup migration
-- that runs only after those legacy views are retired.
-- Do NOT run this with CASCADE — that would destroy the five views.
-- ═══════════════════════════════════════════════════════════════

-- ALTER TABLE articulo DROP COLUMN IF EXISTS grupo_articulo;  -- deferred; see above

-- ═══════════════════════════════════════════════════════════════
-- VERIFY — run before migration 29. None are auto-fixed:
-- the fixups need a human who knows the fabrics.
-- ═══════════════════════════════════════════════════════════════

-- 1. MEMBERLESS grupos. 'Jersey/Gamuza' (grupo_articulo_id=17, articulo_tipo_id=20)
--    RESOLVED 2026-07-18: confirmed completely dead — zero articulos ever
--    created under articulo_tipo_id=20, zero partidas ever declared it, zero
--    rolls ever touched it (all three verify queries empty). Not a real mix
--    placeholder with history to honor — just an unused stub. Soft-delete,
--    do not populate membership:
--      UPDATE grupo_articulo SET fyh_elm = now(), usr_elm = <you> WHERE id = 17;
--      SELECT * FROM vw_grupo_articulo WHERE n_miembros = 0;  -- re-check: should be empty after the above

-- 2. FORGED-MIX grupos: single member whose articulo name encodes a
--    combination. Expect 'J 30/1-Gam 50/1'. Re-point at the real fabrics,
--    KEEP the forged articulo as a member (history), then soft-delete its
--    items so no new rolls land:
--      UPDATE item SET fyh_elm = now(), usr_elm = <you>
--      WHERE id IN (SELECT item_id FROM item_rollo_detalle ird
--                   JOIN articulo a ON a.id = ird.articulo_id
--                   WHERE a.nombre = 'J 30/1- Gam 50/1');
--      SELECT * FROM vw_grupo_articulo WHERE miembros LIKE '%-%' OR miembros LIKE '%/%';

-- 3. NULL fibra on members — blocks the migration-30 ceiling check.
--    Known: Gam 50/1 Card, F Lycra 20/1 Pei, Full Lycra Melange, Gam 30/1,
--    Spun 20/1. NOTE: item names LIE here — fn_trg_gen_codigo_item_rollo does
--    COALESCE(fibra::text,'1'), so 'Rollo Gam 30/1 1 fibra(s)' reads "1 fibra"
--    while articulo.fibra IS NULL. Resolve from the fabric, not the item name.
--      SELECT * FROM vw_grupo_articulo WHERE flg_fibra_incompleta;

-- 4. Sanity: no articulo orphaned from every grupo.
--      SELECT a.id, a.nombre FROM articulo a
--      WHERE NOT EXISTS (SELECT 1 FROM grupo_articulo_miembro gm WHERE gm.articulo_id = a.id);

-- ── FIXUP TEMPLATE for the forged mixes (do NOT run blind) ──
-- Confirm the intended member fabrics with the plant first — the names only
-- suggest membership, they don't prove it, and a wrong member set silently
-- mis-costs and mis-prices every batch on that grupo.
--
-- BEGIN;
--   INSERT INTO grupo_articulo_miembro (grupo_articulo_id, articulo_id)
--   SELECT (SELECT id FROM grupo_articulo WHERE codigo_canon = 'jerseygamuza'), a.id
--   FROM articulo a WHERE a.nombre IN ('J 30/1', 'Gam 50/1');
--   SELECT * FROM vw_grupo_articulo WHERE codigo = 'JERSEYGAMUZA';  -- eyeball
-- COMMIT;



-- SELECT * FROM vw_grupo_articulo WHERE n_miembros = 0;                              -- 1
-- SELECT * FROM vw_grupo_articulo WHERE miembros LIKE '%-%' OR miembros LIKE '%/%';  -- 2
-- SELECT * FROM vw_grupo_articulo WHERE flg_fibra_incompleta;                        -- 3
-- SELECT a.id, a.nombre FROM articulo a                                             -- 4
-- WHERE NOT EXISTS (SELECT 1 FROM grupo_articulo_miembro gm WHERE gm.articulo_id = a.id);


-- SELECT DISTINCT a.id, a.nombre, a.fibra
-- FROM mes.partida p
-- JOIN mes.partida_detalle pd ON pd.partida_id = p.id
-- JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
-- JOIN articulo a ON a.id = ird.articulo_id
-- WHERE p.articulo_tipo_id = 17;   -- Jersey/Gamuza (grupo_articulo_id 17 = articulo_tipo 20)


-- SELECT id, origen_articulo_tipo_id FROM grupo_articulo WHERE id = 17;
-- SELECT id, nombre FROM articulo_tipo WHERE nombre = 'Jersey/Gamuza';


-- SELECT DISTINCT a.id, a.nombre, a.fibra
-- FROM mes.partida p
-- JOIN mes.partida_detalle pd ON pd.partida_id = p.id
-- JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
-- JOIN articulo a ON a.id = ird.articulo_id
-- WHERE p.articulo_tipo_id = 20;   -- Jersey/Gamuza, confirmed


-- SELECT a.id, a.nombre FROM articulo a WHERE a.articulo_tipo_id = 20;
-- SELECT p.id, p.numero, p.fyh_cre FROM mes.partida p WHERE p.articulo_tipo_id = 20 LIMIT 20;

SELECT i.* FROm item i
JOIN item_rollo_detalle ird ON i.id=ird.item_id
JOIN articulo a ON a.id = ird.articulo_id
JOIN articulo_tipo at ON at.id=a.articulo_tipo_id
WHERE at.nombre='J 30/1-Gam 50/1'

SELECT * FROM inventario.vw_lotes_rollos_stock WHERE item_id IN (261,288)

SELECT COUNT(*) FROM grupo_articulo;                       -- expect 32
SELECT * FROM vw_grupo_articulo WHERE n_miembros = 0;       -- expect Jersey/Gamuza only
SELECT * FROM vw_grupo_articulo WHERE flg_fibra_incompleta; -- expect 6 (5 NULL-fibra + the memberless one)
SELECT id, codigo, origen_articulo_tipo_id
FROM grupo_articulo WHERE origen_articulo_tipo_id IN (15, 20);   -- the two artifacts, stable keys

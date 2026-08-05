-- ═══════════════════════════════════════════════════════════════
-- Step 33: pricing + billing move to grupo_articulo — the last articulo_tipo readers
--
-- DEPENDS ON: 28-32.
--
-- ⚠ SHIPS WITH migration 32, NOT after it. From 32 onward nothing writes
-- articulo_tipo_id, so new partidas and recipes carry NULL. Every reader below has
-- to move in the same deploy or it silently degrades — pass a NULL articulo_tipo to
-- fn_get_precio and its `cp.articulo_tipo_id = p_articulo_tipo_id` equality never
-- holds, so only WILDCARD catalog rows match and the real price is lost with no error.
--
-- ⚠ APPLY ORDER:
--     1. Run THIS file (adds + backfills grupo columns on all three tables).
--     2. Re-apply funciones/facturacion.sql, funciones/despacho.sql,
--        funciones/receta.sql, funciones/mes.sql.
--   DDL first here (unlike 31/32): the converted pricing functions reference
--   grupo_articulo_id and doc.articulo_tipo_familia.familia_grupo_id, which must
--   exist first.
--   These are SQL/plpgsql functions whose bodies bind at creation, so applying them
--   against the old schema fails outright rather than degrading — a safe ordering.
--
-- WHAT'S NOT HERE: articulo_tipo_id columns are NOT dropped anywhere. They keep
-- their historical values for lookup and simply stop being written. Dropping them
-- (and articulo_tipo itself) is migration 34, once this has soaked. 34 also renames
-- doc.articulo_tipo_familia → doc.grupo_articulo_familia and swaps its partial
-- unique indexes onto grupo_articulo_id (see §2).
-- ═══════════════════════════════════════════════════════════════

-- ── 1. doc.catalogo_precios ───────────────────────────────────
-- NULL articulo_tipo_id means WILDCARD ("any article type") and must stay NULL —
-- the backfill only maps concrete values, so wildcards remain wildcards.
ALTER TABLE doc.catalogo_precios
    ADD COLUMN IF NOT EXISTS grupo_articulo_id INT REFERENCES grupo_articulo(id);

UPDATE doc.catalogo_precios cp
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = cp.articulo_tipo_id
  AND cp.grupo_articulo_id IS NULL;

-- ── 2. doc.articulo_tipo_familia — re-keyed IN PLACE ──────────
-- Familia stays a SEPARATE concept from grupo — pricing-similarity and
-- dyeing-similarity cross-cut, and collapsing them would re-overload grupo the way
-- articulo_tipo was overloaded. This table answers "which price bucket does this
-- substrate bill under, for this client", which is not the same question as
-- "what dyes together".
--
-- Both sides re-key: the mapped grupo AND the familia bucket itself (familia_id was
-- an articulo_tipo id used as a label; it becomes a grupo id).
--
-- ⚠ ALTER IN PLACE, not a new table. EVERY column here re-keys — there is no payload
-- to preserve — so "new table + INSERT…SELECT" would re-derive the pairing through
-- two joins on origen_articulo_tipo_id, where a miss on either side drops the row
-- silently (and ON CONFLICT DO NOTHING hides it further). Altering keeps the
-- legacy↔grupo pairing 1:1 BY IDENTITY: the row just gains columns. It also avoids a
-- divergence window, since fn_familia_precio keeps reading THIS table until
-- funciones/facturacion.sql lands. Same shape as §1/§3 and migrations 28-32:
-- add alongside, soak, drop in 34.
--
-- RENAME → doc.grupo_articulo_familia happens in 34, with dropping
-- articulo_tipo_id/familia_id and swapping the partial unique indexes onto
-- grupo_articulo_id. The existing uq_articulo_tipo_familia_* indexes still enforce
-- correctly meanwhile: migration 28 seeds one grupo per articulo_tipo, so the
-- mapping is 1:1 and no new collision is reachable. Existing GRANT carries over.
ALTER TABLE doc.articulo_tipo_familia
    ADD COLUMN IF NOT EXISTS grupo_articulo_id INT REFERENCES grupo_articulo(id),
    -- ⚠ SELF-REFERENCE — DEFERRED, NOT ENDORSED. familia_grupo_id points at a grupo
    -- used purely as a bucket LABEL, inherited from the legacy tipo→tipo
    -- normalization CASE (patch 25). A price family is an equivalence class over
    -- grupos: it has no privileged member and wants its own header
    -- (doc.familia_precio) with this table reduced to a membership bridge.
    -- Deferred to keep 33 scoped — see GRUPO_ARTICULO_HANDOFF.md backlog.
    -- Two consequences are live TODAY, not theoretical:
    --   · fn_familia_precio resolves in ONE hop, so a head that is itself mapped
    --     (defaults send 4,9→18 while the flat-rate override sends 4,9→20) is only
    --     resolved correctly by ORDER BY luck. Do not add a third layer.
    --   · a soft-deleted grupo can take a live pricing bucket with it — see the
    --     familia 20 note in §4.
    ADD COLUMN IF NOT EXISTS familia_grupo_id  INT REFERENCES grupo_articulo(id);

-- Subject side: which grupo does this row map.
UPDATE doc.articulo_tipo_familia f
SET grupo_articulo_id = gs.id
FROM grupo_articulo gs
WHERE gs.origen_articulo_tipo_id = f.articulo_tipo_id
  AND f.grupo_articulo_id IS NULL;

-- Bucket side: which grupo labels the family it maps INTO.
UPDATE doc.articulo_tipo_familia f
SET familia_grupo_id = gf.id
FROM grupo_articulo gf
WHERE gf.origen_articulo_tipo_id = f.familia_id
  AND f.familia_grupo_id IS NULL;

-- ── 3. doc.venta_detalle ──────────────────────────────────────
-- Billing dims here are SNAPSHOTS taken at dispatch, deliberately decoupled from
-- live master data so an invoice can't shift under a partida edit. grupo_articulo_id
-- joins that snapshot set; historical rows are backfilled so old invoices still
-- resolve a substrate.
ALTER TABLE doc.venta_detalle
    ADD COLUMN IF NOT EXISTS grupo_articulo_id INT REFERENCES grupo_articulo(id);

UPDATE doc.venta_detalle vd
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = vd.articulo_tipo_id
  AND vd.grupo_articulo_id IS NULL;

-- ── 4. Abort-guard ────────────────────────────────────────────
-- Anything with a concrete articulo_tipo_id must have resolved a grupo. Wildcards
-- (NULL articulo_tipo_id) are expected and excluded.
DO $$
DECLARE v_cp INT; v_vd INT; v_fam INT;
BEGIN
    SELECT COUNT(*) INTO v_cp FROM doc.catalogo_precios
    WHERE articulo_tipo_id IS NOT NULL AND grupo_articulo_id IS NULL AND fyh_elm IS NULL;

    SELECT COUNT(*) INTO v_vd FROM doc.venta_detalle
    WHERE articulo_tipo_id IS NOT NULL AND grupo_articulo_id IS NULL;

    -- Both sides must resolve. Neither column is nullable in the legacy table, so
    -- unlike §1/§3 there are no wildcards to exclude — any NULL is a real failure.
    SELECT COUNT(*) INTO v_fam FROM doc.articulo_tipo_familia
    WHERE grupo_articulo_id IS NULL OR familia_grupo_id IS NULL;

    IF v_cp > 0 OR v_vd > 0 OR v_fam > 0 THEN
        RAISE EXCEPTION
            'Migración 33 abortada: % precio(s), % línea(s) de venta y % fila(s) de familia sin grupo resuelto.',
            v_cp, v_vd, v_fam;
    END IF;
END $$;

-- ── ⚠ FAMILIA 20 IS A LIVE PRICING BUCKET ─────────────────────
-- GRUPO_ARTICULO_HANDOFF.md decision 10 says the grupo with
-- origen_articulo_tipo_id = 20 ('Jersey/Gamuza') is completely dead — 0 articulos,
-- 0 partidas, 0 rolls — and should be soft-deleted.
--
-- It is dead as a SUBSTRATE. It is NOT dead as a PRICING BUCKET: patch 25 seeds
-- familia_id = 20 as the flat-rate family for clients 1/11/22 (11 rows each), and
-- after this migration familia_grupo_id points at exactly that grupo.
--
-- Nothing here breaks (no lookup filters grupo_articulo.fyh_elm), but the two facts
-- are now coupled: soft-deleting that grupo as "cleanup" would silently drop three
-- clients to wildcard pricing the moment anything starts filtering fyh_elm.
-- DO NOT soft-delete it until familia stops labelling buckets with grupos — i.e.
-- until the doc.familia_precio header lands. This is the deferred self-reference
-- costing something real, not a hypothetical.
--   SELECT DISTINCT t.id, t.nombre FROM doc.articulo_tipo_familia f
--   JOIN tercero t ON t.id = f.tercero_id WHERE f.familia_id = 20;

-- ── VERIFY ────────────────────────────────────────────────────
-- Every familia row re-keyed on both sides (expect 0):
--   SELECT COUNT(*) FROM doc.articulo_tipo_familia
--   WHERE grupo_articulo_id IS NULL OR familia_grupo_id IS NULL;

-- Re-key agrees with the legacy key row-for-row (expect 0 — this is the check the
-- in-place ALTER makes possible; a new table could not express it):
--   SELECT COUNT(*) FROM doc.articulo_tipo_familia f
--   JOIN grupo_articulo gs ON gs.id = f.grupo_articulo_id
--   JOIN grupo_articulo gf ON gf.id = f.familia_grupo_id
--   WHERE gs.origen_articulo_tipo_id <> f.articulo_tipo_id
--      OR gf.origen_articulo_tipo_id <> f.familia_id;
--
-- Active catalog rows still resolve the same bucket — spot-check a TENIDO price
-- before and after re-applying the functions; the number must not move.



SELECT 'atf.grupo_articulo_id' AS obj,
       to_regclass('doc.articulo_tipo_familia') IS NOT NULL AS tbl,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='doc' AND table_name='articulo_tipo_familia'
                 AND column_name='grupo_articulo_id') AS present
UNION ALL SELECT 'atf.familia_grupo_id', true,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='doc' AND table_name='articulo_tipo_familia'
                 AND column_name='familia_grupo_id')
UNION ALL SELECT 'doc.grupo_articulo_familia (should NOT exist)',
       true, to_regclass('doc.grupo_articulo_familia') IS NOT NULL
UNION ALL SELECT 'catalogo_precios.grupo_articulo_id', true,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='doc' AND table_name='catalogo_precios'
                 AND column_name='grupo_articulo_id')
UNION ALL SELECT 'venta_detalle.grupo_articulo_id', true,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='doc' AND table_name='venta_detalle'
                 AND column_name='grupo_articulo_id');
SELECT COUNT(*) FILTER (WHERE grupo_articulo_id IS NULL) AS sin_grupo,
       COUNT(*) FILTER (WHERE familia_grupo_id  IS NULL) AS sin_familia,
       COUNT(*) AS total
FROM doc.articulo_tipo_familia;


SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       md5(p.prosrc)                             AS body_hash,
       p.prosrc LIKE '%flg_antipilling%'         AS menciona_antipilling,
       p.prosrc LIKE '%grupo_articulo%'          AS menciona_grupo
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'doc'
  AND p.proname IN ('fn_get_precio','fn_familia_precio','fn_precio_info',
                    'upsert_catalogo_precio','get_precios_partida',
                    'registrar_despacho','fn_descripcion_linea')
ORDER BY p.proname;

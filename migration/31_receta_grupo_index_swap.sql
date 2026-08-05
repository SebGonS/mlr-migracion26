-- ═══════════════════════════════════════════════════════════════
-- Step 31: swap receta.tenido's active-recipe identity to grupo_articulo_id
--
-- DEPENDS ON: 28 (grupos seeded), 29 (receta.tenido.grupo_articulo_id),
--             30 (mes.partida.grupo_articulo_id).
--
-- ⚠ APPLY ORDER — NOT OPTIONAL:
--     1. Re-apply funciones/receta.sql FIRST (converted crear_tenido /
--        actualizar_tenido / transicionar_tenido now write grupo_articulo_id).
--     2. THEN run this file.
--   Reversed, there is a window where a stale writer inserts a recipe with a
--   NULL grupo under a live unique index. The index treats NULLs as distinct, so
--   nothing rejects it, and step 2's backfill then collides. This ordering is the
--   whole reason the function changes went to funciones/ instead of being
--   transcribed in here.
--
-- WHAT MOVES: only the *identity* of an approved recipe — from
--   (color, articulo_tipo, fibra, tenido, antipilling)
-- to
--   (color, GRUPO, fibra, tenido, antipilling)
-- fibra STAYS: it is the *run* dimension (colores jaspeados — run may be less
-- than the fabric requires), not derivable from the substrate.
--
-- articulo_tipo_id is NOT dropped. Converted writers keep it populated (derived
-- from grupo_articulo.origen_articulo_tipo_id) because consumers still read it —
-- notably fn_precio_info's recipe lookup — until migration 32. For a MIX grupo
-- the origen is NULL, so mix recipes carry a NULL articulo_tipo_id by design.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Preconditions ──────────────────────────────────────────
DO $$
DECLARE
    v_null_fibra INT;
    v_unconverted INT;
BEGIN
    -- (a) The fibra ceiling in migration 32 reads MAX(articulo.fibra), and MAX()
    --     SKIPS NULLs — so an unset fibra silently yields a NULL ceiling that
    --     passes everything. Fix those five articulos before proceeding:
    --       UPDATE articulo SET fibra = 1 WHERE fibra IS NULL AND nombre IN
    --         ('Gam 30/1','Spun 20/1','Gam 50/1 Card','F Lycra 20/1 Pei','Full Lycra Melange');
    SELECT COUNT(*) INTO v_null_fibra
    FROM grupo_articulo g
    JOIN grupo_articulo_miembro gm ON gm.grupo_articulo_id = g.id
    JOIN articulo a                ON a.id = gm.articulo_id
    WHERE g.fyh_elm IS NULL AND a.fibra IS NULL;

    IF v_null_fibra > 0 THEN
        RAISE EXCEPTION
            'Migración 31 abortada: % artículo(s) miembro(s) de grupo aún tienen articulo.fibra en NULL. Ejecutar primero el UPDATE de fibra (ver comentario arriba).',
            v_null_fibra;
    END IF;

    -- (b) Prove funciones/receta.sql was re-applied BEFORE this file: the
    --     converted crear_tenido references grupo_articulo_id in its body.
    SELECT COUNT(*) INTO v_unconverted
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'receta'
      AND p.proname = 'crear_tenido'
      AND p.prosrc NOT LIKE '%grupo_articulo_id%';

    IF v_unconverted > 0 THEN
        RAISE EXCEPTION
            'Migración 31 abortada: receta.crear_tenido no ha sido convertida. Volver a aplicar funciones/receta.sql ANTES de ejecutar este archivo.';
    END IF;
END $$;

-- ── 1. Catch interim rows ─────────────────────────────────────
-- Belt-and-suspenders for anything written between 29 and now by a pre-conversion
-- writer. Safe to repeat: trg_bu_tenido_immutable does not guard grupo_articulo_id
-- yet (step 2 adds it), so this cannot trip the "has completed executions" check.
UPDATE receta.tenido rt
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = rt.articulo_tipo_id
  AND rt.grupo_articulo_id IS NULL;

UPDATE mes.partida p
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = p.articulo_tipo_id
  AND p.grupo_articulo_id IS NULL;

-- ── 2. Extend the immutability guard ──────────────────────────
-- SAME trigger, SAME name (trg_bu_tenido_immutable) — only its guarded column
-- list changes, to add grupo_articulo_id. It is now an identity column, so
-- re-pointing an already-executed recipe at a different substrate must be blocked
-- exactly like color/fibra/tenido already are.
--
-- Postgres cannot ALTER a trigger's UPDATE OF column list (ALTER TRIGGER only
-- renames), so it has to be recreated. Done as create → drop → rename, the same
-- pattern as the index in step 3, so the guard is never absent even for an
-- instant. During the brief overlap both triggers fire; harmless, since
-- fn_trg_tenido_immutable is a read-only check that either raises or returns NEW.
--
-- MUST come AFTER step 1's backfill: once grupo_articulo_id is guarded, the
-- backfill itself would trip the check on recipes with completed executions.
DROP TRIGGER IF EXISTS trg_bu_tenido_immutable_new ON receta.tenido;
CREATE TRIGGER trg_bu_tenido_immutable_new
BEFORE UPDATE OF color_x_cliente_id, grupo_articulo_id, articulo_tipo_id,
                 fibra, tenido_id, tipo_receta_id
ON receta.tenido
FOR EACH ROW EXECUTE FUNCTION receta.fn_trg_tenido_immutable();

DROP TRIGGER IF EXISTS trg_bu_tenido_immutable ON receta.tenido;
ALTER TRIGGER trg_bu_tenido_immutable_new ON receta.tenido
    RENAME TO trg_bu_tenido_immutable;

-- ── 3. Swap the active-recipe unique index ────────────────────
-- The index KEEPS its name: uq_receta_tenido_aprobada. Only its definition
-- changes (articulo_tipo_id → grupo_articulo_id). A '_grupo' suffix would bake a
-- transition artifact into the schema that reads as meaningless once articulo_tipo
-- retires in migration 33.
--
-- Build under a temp name → drop old → rename, rather than drop-then-create, so
-- the single-approved-recipe invariant is never unguarded even for an instant —
-- and without depending on the client wrapping this file in a transaction.
--
-- ⚠ tipo_receta_id IS PART OF THE KEY. migration/06_receta_tables.sql documents
-- this index WITHOUT it, but that definition is STALE — the live index carries a
-- sixth column, and the data proves it must: ~50 groups of approved recipes share
-- (color, articulo_tipo, fibra, tenido, antipilling) and differ ONLY in
-- tipo_receta_id (e.g. recetas 5540/6983 → tipo 4 vs 7). They coexist today, so
-- the live index permits them.
--
-- That is correct behaviour, not drift in the data: receta.tenido is shared
-- across recipe types, and two other places already treat tipo_receta_id as
-- identity — transicionar_tenido's supersede is scoped by
-- `tipo_receta_id IS NOT DISTINCT FROM`, and fn_precio_info pins
-- `rt.tipo_receta_id = 7` precisely so "a desmontado/rebaje row on the same keys"
-- can't be returned. Omitting it here would narrow the index and turn every one
-- of those legitimate pairs into a violation.
--
-- If the CREATE still fails, nothing has been dropped yet — inspect first:
--   SELECT color_x_cliente_id, grupo_articulo_id, fibra, tenido_id, flg_antipilling,
--          tipo_receta_id, COUNT(*), array_agg(id)
--   FROM receta.tenido WHERE flg_produccion GROUP BY 1,2,3,4,5,6 HAVING COUNT(*) > 1;
CREATE UNIQUE INDEX IF NOT EXISTS uq_receta_tenido_aprobada_new
    ON receta.tenido(color_x_cliente_id, grupo_articulo_id, fibra, tenido_id,
                     flg_antipilling, tipo_receta_id)
    WHERE flg_produccion = true;

-- SCHEMA-QUALIFY BOTH. An index lives in its table's schema (receta), and this
-- file cannot assume 'receta' is in the session search_path. Unqualified, the
-- DROP silently reports "does not exist, skipping" and the RENAME errors with
-- "relation does not exist" — while the index sits there untouched. The CREATE
-- above needs no qualifier only because its TABLE is qualified (ON receta.tenido),
-- so the index inherits that schema.
-- NOTE: in ALTER INDEX ... RENAME TO, the NEW name must stay unqualified — it
-- cannot move schemas.
DROP INDEX IF EXISTS receta.uq_receta_tenido_aprobada;
ALTER INDEX receta.uq_receta_tenido_aprobada_new RENAME TO uq_receta_tenido_aprobada;


SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'receta' AND tablename = 'tenido';

-- ── VERIFY ────────────────────────────────────────────────────
-- No approved recipe left without a grupo (expect 0):
--   SELECT COUNT(*) FROM receta.tenido
--   WHERE flg_produccion AND grupo_articulo_id IS NULL AND articulo_tipo_id IS NOT NULL;
--
-- Index swap landed (expect only ..._grupo):
--   SELECT indexname FROM pg_indexes
--   WHERE tablename = 'tenido' AND indexname LIKE 'uq_receta_tenido_aprobada%';
SELECT indexname FROM pg_indexes
WHERE schemaname = 'receta' AND tablename = 'tenido'
  AND indexname LIKE 'uq_receta_tenido_aprobada%';


-- the two colliding rows, full identity
SELECT id, color_x_cliente_id, articulo_tipo_id, grupo_articulo_id, fibra,
       tenido_id, flg_antipilling, tipo_receta_id, estado_id, flg_produccion,
       fyh_cre, fyh_produccion
FROM receta.tenido
WHERE color_x_cliente_id = 279 AND grupo_articulo_id = 20
  AND fibra = 1 AND tenido_id = 4 AND flg_antipilling = false
  AND flg_produccion = true
ORDER BY fyh_cre;

-- is this the only collision?
SELECT color_x_cliente_id, grupo_articulo_id, fibra, tenido_id, flg_antipilling,
       COUNT(*), array_agg(id ORDER BY fyh_cre) AS receta_ids,
       array_agg(DISTINCT tipo_receta_id) AS tipos
FROM receta.tenido
WHERE flg_produccion = true
GROUP BY 1,2,3,4,5
HAVING COUNT(*) > 1;


SELECT indexdef FROM pg_indexes
WHERE schemaname = 'receta' AND tablename = 'tenido'
  AND indexname = 'uq_receta_tenido_aprobada';

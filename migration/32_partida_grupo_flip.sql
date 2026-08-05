-- ═══════════════════════════════════════════════════════════════
-- Step 32: production flip — grupo_articulo becomes the partida's substrate key
--
-- DEPENDS ON: 28 (grupos), 29 (receta.grupo_articulo_id), 30 (partida.grupo_articulo_id),
--             31 (receta active-recipe index on grupo).
--
-- ⚠ APPLY ORDER:
--     1. Re-apply funciones/core.sql   (crear_partida, actualizar_partida)
--     2. Re-apply funciones/receta.sql (resolver_tenido_id, solicitar_si_ausente)
--     3. THEN run this file.
--   The precondition block below refuses to run if step 1 was skipped.
--
-- WHAT CHANGED IN THE FUNCTIONS (they live in funciones/, not transcribed here):
--   crear_partida
--     · CLEAN BREAK: payload takes grupo_articulo_id; articulo_tipo_id is no longer
--       accepted and is derived from grupo_articulo.origen_articulo_tipo_id.
--     · Composition guard RESTORED and re-keyed: every assigned roll's articulo must
--       be a member of the partida's grupo (grupo_articulo_miembro). This replaces
--       the old articulo_tipo equality test, which had been removed from the file
--       leaving crear_partida with NO fabric guard at all.
--     · Fibra ceiling ADDED: partida.fibra <= MAX(member articulo.fibra). Running
--       FEWER systems than the substrate needs is legitimate (colores jaspeados);
--       running MORE is not.
--   actualizar_partida  · same substrate-identity treatment on the CREADA branch.
--   resolver_tenido_id  · THE MIXED-BATCH WALL IS GONE. It no longer counts distinct
--       (articulo_tipo, fibra) across rolls and raises. It matches on the partida's
--       DECLARED grupo + fibra. That RAISE is why the forged articulos and flg_rib
--       existed — disguising two fabrics as one was the only way past it.
--   solicitar_si_ausente · same: spec taken from the partida, not inferred from rolls.
--
-- STILL PENDING (migration 33, pricing): catalogo_precios + articulo_tipo_familia
-- re-key, fn_get_precio / fn_familia_precio / fn_precio_info / upsert_catalogo_precio,
-- the despacho.sql snapshot onto venta lines, and venta's own articulo_tipo_id.
-- Until then a MIX partida (articulo_tipo_id NULL) has no catalog price — price it
-- via the mes.partida.precio_kg override. Pure partidas are unaffected.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Precondition: functions converted first ────────────────
DO $$
DECLARE v_unconverted INT;
BEGIN
    SELECT COUNT(*) INTO v_unconverted
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'mes'
      AND p.proname = 'crear_partida'
      AND p.prosrc NOT LIKE '%grupo_articulo_miembro%';

    IF v_unconverted > 0 THEN
        RAISE EXCEPTION
            'Migración 32 abortada: mes.crear_partida no ha sido convertida. Volver a aplicar funciones/core.sql ANTES de ejecutar este archivo.';
    END IF;
END $$;

-- ── 1. Catch any partida created through the guard gap ────────
-- Idempotent; covers rows written between migration 30 and now.
UPDATE mes.partida p
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = p.articulo_tipo_id
  AND p.grupo_articulo_id IS NULL;

-- ── articulo_tipo_id: legacy, left to drift ───────────────────
-- No bridge, no trigger, no derivation. 32 and 33 deploy together, so there is no
-- window in which a stale reader needs it populated. New rows simply get NULL;
-- historical rows keep their values for lookup. Both columns are already nullable
-- (mes.partida relaxed in migration 30; receta.tenido never had NOT NULL).
--
-- CONSEQUENCE — every reader must move in the SAME deploy, not just pricing:
--   · facturacion.sql  — fn_get_precio / fn_familia_precio / fn_precio_info /
--                        upsert_catalogo_precio + the billing views  (migration 33)
--   · despacho.sql     — snapshots it onto venta lines                (migration 33)
--   · receta.get_tenido_versiones — FUNCTIONAL, not display: it matches versions by
--                        (color, articulo_tipo, fibra, tenido, antipilling). With a
--                        NULL the row-comparison yields NULL and it returns EMPTY.
--   · display only — mes.sql partida/receta JSON output, receta.get_tenido,
--                        receta.vw_tenido: show grupo instead, else the UI blanks.
--
-- ── 2. Make the substrate key mandatory ───────────────────────
-- Every live partida now carries a grupo (30 backfilled, step 1 caught stragglers,
-- crear_partida requires it). Fails loudly rather than silently if something slipped.
ALTER TABLE mes.partida ALTER COLUMN grupo_articulo_id SET NOT NULL;

-- ── VERIFY ────────────────────────────────────────────────────
-- 1. Rolls sitting in a partida whose grupo does not list their fabric. These are
--    NOT rejected retroactively (the guard validates incoming payloads only), but
--    each is either a real mix whose grupo needs its membership extended, or a
--    mis-assignment made while crear_partida had no guard. Expect 0.
--      SELECT p.id, p.numero, g.codigo AS grupo, array_agg(DISTINCT a.nombre) AS telas
--      FROM mes.partida p
--      JOIN grupo_articulo g          ON g.id = p.grupo_articulo_id
--      JOIN mes.partida_componente pc ON pc.partida_id = p.id AND pc.lote_id IS NOT NULL
--      JOIN inventario.lote l         ON l.id = pc.lote_id
--      JOIN item_rollo_detalle ird    ON ird.item_id = l.item_id
--      JOIN articulo a                ON a.id = ird.articulo_id
--      WHERE p.fyh_elm IS NULL
--        AND NOT EXISTS (SELECT 1 FROM grupo_articulo_miembro gm
--                        WHERE gm.grupo_articulo_id = p.grupo_articulo_id
--                          AND gm.articulo_id = a.id)
--      GROUP BY p.id, p.numero, g.codigo ORDER BY p.id DESC;
--
-- 2. Partidas breaching the new fibra ceiling (pre-existing data only; expect 0):
--      SELECT p.id, p.fibra, v.fibra_max, v.codigo
--      FROM mes.partida p JOIN vw_grupo_articulo v ON v.grupo_articulo_id = p.grupo_articulo_id
--      WHERE p.fyh_elm IS NULL AND v.fibra_max IS NOT NULL AND p.fibra > v.fibra_max;
--
-- 3. Smoke-test the matcher on a known partida — must return the same recipe as before:
--      SELECT receta.resolver_tenido_id(<partida_id>, NULL);

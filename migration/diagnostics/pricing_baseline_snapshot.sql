-- ═══════════════════════════════════════════════════════════════
-- Pricing baseline snapshot — before/after harness for migration 33b
--
-- WHY: converting the pricing functions from articulo_tipo_id to
-- grupo_articulo_id CANNOT be verified by "did it error". A wrong key does not
-- error — the equality just never holds, so only WILDCARD catalog rows match and
-- the resolved price silently changes (usually to a different number, sometimes
-- to NULL). The only real check is: every partida resolves the SAME precio_kg
-- before and after.
--
-- Spot-checking one partida is not enough. The failure is per-catalog-row: a
-- partida whose price came from a wildcard row is UNAFFECTED and will match
-- perfectly, while the specific-row ones break. Checking a single partida has a
-- good chance of checking exactly the one that cannot break.
--
-- USAGE:
--   1. BEFORE 33b:  run §1 (creates + fills the snapshot).
--   2. Run 33b + re-apply funciones/facturacion.sql, despacho.sql.
--   3. AFTER:       run §2 (diff). Expect ZERO rows.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. BEFORE — capture ───────────────────────────────────────
-- Real table, not TEMP: steps 1 and 3 are different sessions.
-- Scoped to partidas with completed work and a client — the billable population.
DROP TABLE IF EXISTS doc.tmp_pricing_baseline;

CREATE TABLE doc.tmp_pricing_baseline AS
SELECT
    gp.partida_id,
    gp.operacion_id,
    gp.operacion,
    gp.es_antipilling,
    gp.precio_kg,
    gp.sin_precio
FROM doc.get_precios_partida(
    ARRAY(
        SELECT p.id
        FROM mes.partida p
        WHERE p.fyh_elm IS NULL
          AND p.tercero_id IS NOT NULL
          AND EXISTS (
              SELECT 1 FROM mes.partida_paso pp
              JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
              WHERE pp.partida_id = p.id AND pe.estado = 'COMPLETADO'
          )
    )::bigint[]
) gp;

-- Sanity — how much is actually covered, and how much was ALREADY unpriced.
-- Pre-existing NULLs are fine (they stay NULL); what matters is that the set
-- does not GROW. A large sin_precio count here means the baseline is weak,
-- because unpriced rows can't detect a regression.
SELECT COUNT(*)                                        AS lineas,
       COUNT(DISTINCT partida_id)                      AS partidas,
       COUNT(*) FILTER (WHERE sin_precio)              AS ya_sin_precio,
       COUNT(*) FILTER (WHERE NOT sin_precio)          AS con_precio_verificable
FROM doc.tmp_pricing_baseline;

-- ── 2. AFTER — diff ───────────────────────────────────────────
-- Expect ZERO rows. Any row is a real regression; do not proceed to invoicing.
-- IS DISTINCT FROM so NULL→value and value→NULL both surface (plain <> would
-- swallow exactly the case we care most about).
--
--   SELECT b.partida_id, b.operacion, b.es_antipilling,
--          b.precio_kg AS antes, a.precio_kg AS despues,
--          CASE WHEN a.partida_id IS NULL           THEN 'línea desapareció'
--               WHEN b.precio_kg IS NOT NULL
--                AND a.precio_kg IS NULL            THEN 'precio perdido'
--               WHEN b.precio_kg IS NULL
--                AND a.precio_kg IS NOT NULL        THEN 'precio nuevo (revisar)'
--               ELSE 'precio cambió' END            AS diagnostico
--   FROM doc.tmp_pricing_baseline b
--   FULL JOIN doc.get_precios_partida(
--       ARRAY(SELECT DISTINCT partida_id FROM doc.tmp_pricing_baseline)::bigint[]
--   ) a
--     ON  a.partida_id     = b.partida_id
--     AND a.operacion_id   = b.operacion_id
--     AND a.es_antipilling = b.es_antipilling
--   WHERE a.precio_kg IS DISTINCT FROM b.precio_kg
--      OR a.partida_id IS NULL OR b.partida_id IS NULL
--   ORDER BY 1, 2;
--
-- If rows appear, the likely cause is a catalog row whose grupo_articulo_id
-- backfill missed, or a familia bucket that re-keyed to a different grupo.
-- Check the specific partida's dimensions against doc.catalogo_precios before
-- touching any function.

-- ── 3. Cleanup (only after the diff is clean) ─────────────────
--   DROP TABLE doc.tmp_pricing_baseline;

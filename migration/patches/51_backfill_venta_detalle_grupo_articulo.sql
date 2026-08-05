-- 51_backfill_venta_detalle_grupo_articulo.sql
--
-- Fixes: migration/diagnostics/venta_detalle_schema_check.sql confirmed all
-- 6,704 doc.venta_detalle rows inserted by migrate_despacho_to_venta.sql have
-- articulo_tipo_id set but grupo_articulo_id NULL. migration/33_pricing_
-- grupo_articulo.sql's backfill ran once, before those rows existed, so they
-- were never caught. doc.vw_venta reads grupo_articulo_id, not
-- articulo_tipo_id, so these lines currently show no article classification.
--
-- Same backfill logic as 33's original UPDATE, naturally scoped to just these
-- rows since grupo_articulo_id IS NULL is currently true for exactly them
-- (confirmed: missing_grupo count == migrated_rows_missing_grupo count, 6704
-- both ways — no other row is affected).
--
-- Pattern: §0 dry-run (read-only) -> §1 UPDATE in a txn -> §2 verify -> COMMIT.

-- ── §0. DRY RUN — read only, confirms scope before writing ──────────────────
SELECT COUNT(*) AS rows_to_backfill
FROM doc.venta_detalle vd
JOIN grupo_articulo g ON g.origen_articulo_tipo_id = vd.articulo_tipo_id
WHERE vd.grupo_articulo_id IS NULL
  AND vd.articulo_tipo_id IS NOT NULL;
-- Expect: 6704

SELECT COUNT(*) AS would_remain_unmatched
FROM doc.venta_detalle vd
WHERE vd.grupo_articulo_id IS NULL
  AND vd.articulo_tipo_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM grupo_articulo g WHERE g.origen_articulo_tipo_id = vd.articulo_tipo_id);
-- Expect: 0 (every articulo_tipo_id in use already resolves a grupo per §5 of the check)


-- ── §1. UPDATE — run in a transaction, do NOT autocommit ────────────────────
BEGIN;

UPDATE doc.venta_detalle vd
SET grupo_articulo_id = g.id
FROM grupo_articulo g
WHERE g.origen_articulo_tipo_id = vd.articulo_tipo_id
  AND vd.grupo_articulo_id IS NULL;
--
-- -- expect 6704
-- -- (check the actual row count reported by the UPDATE before verifying)


-- ── §2. VERIFY — still inside the open transaction, before COMMIT ───────────
SELECT COUNT(*) FILTER (WHERE articulo_tipo_id IS NOT NULL AND grupo_articulo_id IS NULL) AS still_missing,
       COUNT(*) AS total
FROM doc.venta_detalle;
-- Expect: still_missing = 0

-- -- Spot check: a few migrated rows now resolve a grupo consistent with their articulo_tipo_id
SELECT vd.id, vd.articulo_tipo_id, at.nombre AS articulo_tipo_nombre,
       vd.grupo_articulo_id, ga.nombre AS grupo_articulo_nombre
FROM doc.venta_detalle vd
JOIN articulo_tipo at ON at.id = vd.articulo_tipo_id
JOIN grupo_articulo ga ON ga.id = vd.grupo_articulo_id
WHERE vd.usr_cre = 4
ORDER BY vd.id
LIMIT 20;

-- doc.vw_venta now shows classification for these lines (spot check one venta)
SELECT * FROM doc.vw_venta WHERE venta_id = 1;

-- ── COMMIT only after §2 checks out ──────────────────────────────────────────
-- COMMIT;

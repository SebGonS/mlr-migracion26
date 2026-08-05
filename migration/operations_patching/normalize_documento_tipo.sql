-- ============================================================================
-- N1 · Canonicalize documento_tipo strings (lote + item_movimientos)
-- ============================================================================
-- WHAT: the "Rename guia_remision → entrega" commit renamed the TABLE but left the
--   literal documento_tipo strings on existing rows stale. Collapse the variants
--   onto the canonical set (05_new_tables legend): 'entrega', 'cuadre'.
--     GUIA_REMISION / guia_remision → entrega
--     CUADRE                        → cuadre
--   Pure string relabel — documento_id, lote_rollo_detalle.entrega_id, serie,
--   correlativo and every anchor stay exactly as they are. No rows move.
--
-- WHY: anything filtering documento_tipo='entrega' (views/reports/app) currently
--   MISSES the ~7k already-migrated rolls stuck under the old strings.
--
-- ⚠ DRY-RUN §0 (incl. resolve guard), run §1, read §2, then COMMIT.
-- ============================================================================

-- ── §0 · DRY RUN — counts + resolve guard ─────────────────────────────────────
-- (a) how many rows each relabel touches
SELECT 'lote'            AS tbl, documento_tipo, COUNT(*) AS rows
FROM inventario.lote            WHERE documento_tipo IN ('GUIA_REMISION','guia_remision','CUADRE')
GROUP BY 1,2
UNION ALL
SELECT 'item_movimientos', documento_tipo, COUNT(*)
FROM inventario.item_movimientos WHERE documento_tipo IN ('GUIA_REMISION','guia_remision','CUADRE')
GROUP BY 1,2
ORDER BY 1,2;

-- (b) resolve guard — every stale-string lote's documento_id MUST point at a live
--     row in the canonical table. Expect documento_id_unresolved = 0 everywhere.
SELECT l.documento_tipo, COUNT(*) AS lotes,
       COUNT(*) FILTER (WHERE e.id IS NULL) AS documento_id_unresolved
FROM inventario.lote l
LEFT JOIN doc.entrega e ON e.id = l.documento_id
WHERE l.documento_tipo IN ('GUIA_REMISION','guia_remision')
GROUP BY 1
UNION ALL
SELECT l.documento_tipo, COUNT(*),
       COUNT(*) FILTER (WHERE c.id IS NULL)
FROM inventario.lote l
LEFT JOIN inventario.cuadre c ON c.id = l.documento_id
WHERE l.documento_tipo = 'CUADRE'
GROUP BY 1;


-- ── §1 · Execute (run ONLY if §0(b) unresolved = 0) ───────────────────────────
BEGIN;

UPDATE inventario.lote
SET    documento_tipo = 'entrega'
WHERE  documento_tipo IN ('GUIA_REMISION','guia_remision');

UPDATE inventario.lote
SET    documento_tipo = 'cuadre'
WHERE  documento_tipo = 'CUADRE';

UPDATE inventario.item_movimientos
SET    documento_tipo = 'entrega'
WHERE  documento_tipo IN ('GUIA_REMISION','guia_remision');

UPDATE inventario.item_movimientos
SET    documento_tipo = 'cuadre'
WHERE  documento_tipo = 'CUADRE';


-- ── §2 · Verify (expect 0/0) ──────────────────────────────────────────────────
SELECT
  (SELECT COUNT(*) FROM inventario.lote
     WHERE documento_tipo IN ('GUIA_REMISION','guia_remision','CUADRE'))            AS lote_stale_left,
  (SELECT COUNT(*) FROM inventario.item_movimientos
     WHERE documento_tipo IN ('GUIA_REMISION','guia_remision','CUADRE'))            AS movim_stale_left;

-- COMMIT;    -- ← after §2 both 0
-- ROLLBACK;  -- ← if anything is off

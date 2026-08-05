-- ============================================================================
-- MERGE · Collapse leading-zero guia variants into one entrega
-- ============================================================================
-- WHAT: N2 preserved guias verbatim, so leading-zero format variants of the SAME
--   physical guia landed as separate headers for the same tercero:
--     {047-736, 47-736}, {00000442, 442}, {0718-0818, 718-818}, {008, 08}, …
--   This folds each variant cluster into ONE entrega. Normalization is per-numeric-
--   segment leading-zero strip: regexp_replace(corr,'(^|\D)0+(\d)','\1\2','g').
--   So 047-736 ≡ 47-736 merge, but 001-59 (→1-59) ≠ 59 stays apart (correct).
--
-- SCOPE: CLIENTE_ENVIO_PROCESO entregas only, clusters of (tercero, serie,
--   corr_norm) with >1 distinct correlativo. Canonical = MIN(id) (oldest / app-
--   known); partners fold in and are deleted. Nothing else is touched.
--
-- Reference surface cleared before delete (reassign-before-delete — never orphan):
--   FKs        : doc.entrega_detalle, inventario.lote_rollo_detalle,
--                doc.compra_entrega, doc.factura_detalle
--   polymorphic: inventario.lote / inventario.item_movimientos (documento_tipo='entrega')
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- ── §0 · DRY RUN — the clusters + what gets reassigned ────────────────────────
WITH norm AS (
    SELECT e.id, e.tercero_id, e.entrega_tipo_id, e.serie, e.correlativo,
           regexp_replace(e.correlativo, '(^|\D)0+(\d)', '\1\2', 'g') AS corr_norm
    FROM doc.entrega e
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id AND et.codigo = 'CLIENTE_ENVIO_PROCESO'
    WHERE e.correlativo IS NOT NULL
),
grp AS (
    SELECT id,
           MIN(id)  OVER w AS canonical_id,
           COUNT(*) OVER w AS n
    FROM norm
    WINDOW w AS (PARTITION BY tercero_id, entrega_tipo_id, serie, corr_norm)
),
partners AS (SELECT id AS partner_id, canonical_id FROM grp WHERE n > 1 AND id <> canonical_id)
SELECT
    (SELECT COUNT(DISTINCT canonical_id) FROM partners)                              AS clusters,
    (SELECT COUNT(*) FROM partners)                                                  AS partner_entregas_to_delete,
    (SELECT COUNT(*) FROM doc.entrega_detalle ed  JOIN partners p ON p.partner_id = ed.entrega_id)  AS detalle_lines_moved,
    (SELECT COUNT(*) FROM inventario.lote_rollo_detalle lrd JOIN partners p ON p.partner_id = lrd.entrega_id) AS lrd_moved,
    (SELECT COUNT(*) FROM inventario.lote l WHERE l.documento_tipo='entrega'
        AND l.documento_id IN (SELECT partner_id FROM partners))                     AS lotes_moved,
    (SELECT COUNT(*) FROM inventario.item_movimientos im WHERE im.documento_tipo='entrega'
        AND im.documento_id IN (SELECT partner_id FROM partners))                    AS movim_moved,
    (SELECT COUNT(*) FROM doc.compra_entrega  ce JOIN partners p ON p.partner_id = ce.entrega_id)   AS compra_links,
    (SELECT COUNT(*) FROM doc.factura_detalle fd JOIN partners p ON p.partner_id = fd.entrega_id)   AS factura_links;


-- ── §1 · Merge ────────────────────────────────────────────────────────────────
BEGIN;

CREATE TEMP TABLE _merge ON COMMIT DROP AS
WITH norm AS (
    SELECT e.id, e.tercero_id, e.entrega_tipo_id, e.serie,
           regexp_replace(e.correlativo, '(^|\D)0+(\d)', '\1\2', 'g') AS corr_norm
    FROM doc.entrega e
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id AND et.codigo = 'CLIENTE_ENVIO_PROCESO'
    WHERE e.correlativo IS NOT NULL
),
grp AS (
    SELECT id,
           MIN(id)  OVER w AS canonical_id,
           COUNT(*) OVER w AS n
    FROM norm
    WINDOW w AS (PARTITION BY tercero_id, entrega_tipo_id, serie, corr_norm)
)
SELECT id AS partner_id, canonical_id FROM grp WHERE n > 1 AND id <> canonical_id;

-- 1. entrega_detalle: move partner lines onto canonical with fresh, non-colliding
--    linea = (canonical's current max) + running number across all moving lines.
WITH base AS (
    SELECT DISTINCT m.canonical_id,
           COALESCE((SELECT MAX(ed.linea) FROM doc.entrega_detalle ed
                     WHERE ed.entrega_id = m.canonical_id), 0) AS base_linea
    FROM _merge m
),
moving AS (
    SELECT ed.id AS ed_id, m.canonical_id,
           row_number() OVER (PARTITION BY m.canonical_id ORDER BY ed.id) AS rn
    FROM doc.entrega_detalle ed
    JOIN _merge m ON m.partner_id = ed.entrega_id
)
UPDATE doc.entrega_detalle ed
SET entrega_id = mv.canonical_id,
    linea      = (b.base_linea + mv.rn)::smallint
FROM moving mv
JOIN base b ON b.canonical_id = mv.canonical_id
WHERE ed.id = mv.ed_id;

-- 2. billing anchor
UPDATE inventario.lote_rollo_detalle lrd
SET entrega_id = m.canonical_id
FROM _merge m WHERE lrd.entrega_id = m.partner_id;

-- 3. lote origin (polymorphic)
UPDATE inventario.lote l
SET documento_id = m.canonical_id
FROM _merge m
WHERE l.documento_tipo = 'entrega' AND l.documento_id = m.partner_id;

-- 4. movements (polymorphic)
UPDATE inventario.item_movimientos im
SET documento_id = m.canonical_id
FROM _merge m
WHERE im.documento_tipo = 'entrega' AND im.documento_id = m.partner_id;

-- 5. compra_entrega (defensive — expect 0; PK-safe: drop dup, move rest)
DELETE FROM doc.compra_entrega ce USING _merge m
WHERE ce.entrega_id = m.partner_id
  AND EXISTS (SELECT 1 FROM doc.compra_entrega c2
              WHERE c2.compra_id = ce.compra_id AND c2.entrega_id = m.canonical_id);
UPDATE doc.compra_entrega ce
SET entrega_id = m.canonical_id
FROM _merge m WHERE ce.entrega_id = m.partner_id;

-- 6. factura_detalle (defensive — expect 0)
UPDATE doc.factura_detalle fd
SET entrega_id = m.canonical_id
FROM _merge m WHERE fd.entrega_id = m.partner_id;

-- 7. delete the now-unreferenced partner entregas
DELETE FROM doc.entrega e USING _merge m WHERE e.id = m.partner_id;


-- ── §2 · Verify (expect all 0) ────────────────────────────────────────────────
SELECT
  (SELECT COUNT(*) FROM doc.entrega e        JOIN _merge m ON m.partner_id = e.id)             AS partners_surviving,
  (SELECT COUNT(*) FROM doc.entrega_detalle ed JOIN _merge m ON m.partner_id = ed.entrega_id)  AS dangling_detalle,
  (SELECT COUNT(*) FROM inventario.lote_rollo_detalle lrd JOIN _merge m ON m.partner_id = lrd.entrega_id) AS dangling_lrd,
  (SELECT COUNT(*) FROM inventario.lote l WHERE l.documento_tipo='entrega'
      AND l.documento_id IN (SELECT partner_id FROM _merge))                                   AS dangling_lote,
  (SELECT COUNT(*) FROM inventario.item_movimientos im WHERE im.documento_tipo='entrega'
      AND im.documento_id IN (SELECT partner_id FROM _merge))                                  AS dangling_movim,
  -- no canonical ended with a duplicate linea
  (SELECT COUNT(*) FROM (
       SELECT entrega_id, linea FROM doc.entrega_detalle
       WHERE entrega_id IN (SELECT canonical_id FROM _merge)
       GROUP BY entrega_id, linea HAVING COUNT(*) > 1) x)                                      AS dup_linea;

-- COMMIT;    -- ← after §2 all 0
-- ROLLBACK;  -- ← if anything is off

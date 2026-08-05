-- ═══════════════════════════════════════════════════════════════
-- Patch 60: backfill reversion_movimiento_id on historical rows
-- ---------------------------------------------------------------------
-- migration/40b added inventario.item_movimientos.reversion_movimiento_id
-- and updated every reversal-issuing function to populate it going
-- forward. This patch fills it in retroactively for rows posted before
-- that change existed, using the same matching logic the live functions
-- use — the only option for historical data, since the link was never
-- persisted before now.
--
-- Safety principles (apply to every section below):
--   * Idempotent — every UPDATE only touches rows where
--     reversion_movimiento_id IS NULL, so re-running this file is a no-op
--     the second time.
--   * Read-only w.r.t. business columns — only ever sets the new metadata
--     column; cantidad/precio_unitario/motivo_id/etc. are never touched.
--   * Conservative — a match is only made when it is unambiguous (exact
--     cantidad match, aligned group counts, or a unique candidate). Where
--     ambiguous (e.g. multiple original rows could equally match one
--     reversal), the row is left NULL rather than guessed — identical to
--     the rule the live functions themselves apply going forward.
-- Requires: migration/40b_movimiento_reversal_link.sql
-- ═══════════════════════════════════════════════════════════════


-- ── A. corregir_matizado: PROD_CONSUMO_REV (motivo=MATIZADO) ─────────────
-- corregir_matizado is guarded to one correction per execution, and its
-- reversal INSERT...SELECT copies m.cantidad verbatim — so within one
-- ejecución, an original MATIZADO consumo and its reversal always share
-- (item_id, lote_id, cantidad). Multiple dosing events for the same
-- item/lote can exist, so pair positionally (by id order) within that key
-- and only where both sides have the same row count for that key.
WITH originales AS (
    SELECT m.id, m.documento_id, m.item_id, m.lote_id, m.cantidad,
           ROW_NUMBER() OVER (PARTITION BY m.documento_id, m.item_id, m.lote_id, m.cantidad ORDER BY m.id) AS rn,
           COUNT(*)     OVER (PARTITION BY m.documento_id, m.item_id, m.lote_id, m.cantidad) AS grp_count
    FROM inventario.item_movimientos m
    WHERE m.documento_tipo          = 'partida_paso_ejecucion'
      AND m.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO')
      AND m.motivo_id               = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO')
),
reversales AS (
    SELECT m.id, m.documento_id, m.item_id, m.lote_id, m.cantidad,
           ROW_NUMBER() OVER (PARTITION BY m.documento_id, m.item_id, m.lote_id, m.cantidad ORDER BY m.id) AS rn,
           COUNT(*)     OVER (PARTITION BY m.documento_id, m.item_id, m.lote_id, m.cantidad) AS grp_count
    FROM inventario.item_movimientos m
    WHERE m.documento_tipo          = 'partida_paso_ejecucion'
      AND m.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV')
      AND m.motivo_id               = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO')
      AND m.reversion_movimiento_id IS NULL
)
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = orig.id
FROM   reversales rv
JOIN   originales orig
       ON  orig.documento_id = rv.documento_id
       AND orig.item_id      = rv.item_id
       AND orig.lote_id IS NOT DISTINCT FROM rv.lote_id
       AND orig.cantidad     = rv.cantidad
       AND orig.rn           = rv.rn
       AND orig.grp_count    = rv.grp_count
WHERE  rev.id = rv.id;


-- ── B. anular_produccion: PROD_ING_REV ↔ PROD_ING ─────────────────────────
-- Each output lote has exactly one PROD_ING row and, if the run was
-- undone, exactly one PROD_ING_REV row — unambiguous, match by lote_id.
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = orig.id
FROM   inventario.item_movimientos orig
WHERE  rev.item_movimiento_tipo_id  = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING_REV')
  AND  rev.reversion_movimiento_id IS NULL
  AND  orig.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING')
  AND  orig.lote_id = rev.lote_id;


-- ── C. anular_produccion: PROD_CONSUMO_REV (general, motivo IS NULL) ─────
-- anular_produccion's own consumo-reversal insert does not set motivo_id,
-- which cleanly separates it from section A's MATIZADO-motivo reversals.
-- Only link when exactly one original PROD_CONSUMO row (any motivo) shares
-- (documento_id, item_id, lote_id) AND its cantidad exactly matches the
-- reversal's — the same "single contributing original" rule the live
-- function applies. A lote partially reversed earlier by corregir_matizado
-- has no original row whose cantidad equals the later net reversal, so it
-- naturally falls through and stays NULL rather than mismatching.
WITH candidatos_originales AS (
    SELECT m.documento_id, m.item_id, m.lote_id, m.cantidad, m.id,
           COUNT(*) OVER (PARTITION BY m.documento_id, m.item_id, m.lote_id, m.cantidad) AS n
    FROM inventario.item_movimientos m
    WHERE m.documento_tipo          = 'partida_paso_ejecucion'
      AND m.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO')
)
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = orig.id
FROM   candidatos_originales orig
WHERE  rev.item_movimiento_tipo_id  = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV')
  AND  rev.motivo_id               IS NULL
  AND  rev.reversion_movimiento_id IS NULL
  AND  orig.documento_id = rev.documento_id
  AND  orig.item_id      = rev.item_id
  AND  orig.lote_id IS NOT DISTINCT FROM rev.lote_id
  AND  orig.cantidad     = rev.cantidad
  AND  orig.n            = 1;


-- ── D. revertir_baja_lote: PROD_SCRAP_REV ↔ PROD_SCRAP ────────────────────
-- A lote has exactly one PROD_SCRAP row and, if un-scrapped, exactly one
-- PROD_SCRAP_REV row — unambiguous, match by lote_id.
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = orig.id
FROM   inventario.item_movimientos orig
WHERE  rev.item_movimiento_tipo_id  = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_SCRAP_REV')
  AND  rev.reversion_movimiento_id IS NULL
  AND  orig.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_SCRAP')
  AND  orig.lote_id = rev.lote_id;


-- ── E. anular_cuadre_ejecutado: AJUSTE_POS/NEG counter-postings ──────────
-- Reversal reuses the OPPOSITE type code of what it cancels (AJUSTE_NEG
-- reversed by inserting AJUSTE_POS and vice versa), so type alone can't
-- separate original from reversal. doc_movimiento_id is assigned from a
-- monotonic sequence (nextval), so within one (cuadre, lote) pair the row
-- with the LATER doc_movimiento_id is always the reversal. Only link when
-- exactly 2 AJUSTE rows exist for that (cuadre, lote) — a lote finalized,
-- reversed, then finalized+reversed again would have 4 rows and is left
-- ambiguous/NULL rather than guessed.
WITH pares AS (
    SELECT documento_id, lote_id,
           (ARRAY_AGG(id ORDER BY doc_movimiento_id ASC))[1] AS original_id,
           (ARRAY_AGG(id ORDER BY doc_movimiento_id ASC))[2] AS reversion_id,
           COUNT(*) AS n
    FROM inventario.item_movimientos
    WHERE documento_tipo = 'cuadre'
      AND item_movimiento_tipo_id IN (
          (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS'),
          (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_NEG')
      )
    GROUP BY documento_id, lote_id
)
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = pares.original_id
FROM   pares
WHERE  rev.id = pares.reversion_id
  AND  pares.n = 2
  AND  rev.reversion_movimiento_id IS NULL;


-- ── F. anular_devolucion_*: *_REV ↔ original entrega movement ────────────
-- Within one entrega_id, only two movement-type codes are ever present:
-- the forward devolución type and, if anulled, its _REV counterpart — no
-- need to hardcode the REV→original code map (registrar_devolucion_cliente
-- resolves its type dynamically via entrega_tipo.item_movimiento_tipo_id).
-- Match by (documento_id, lote_id, cantidad), positional by id, only where
-- both sides have equal counts for that key.
WITH originales AS (
    SELECT m.id, m.documento_id, m.lote_id, m.cantidad,
           ROW_NUMBER() OVER (PARTITION BY m.documento_id, m.lote_id, m.cantidad ORDER BY m.id) AS rn,
           COUNT(*)     OVER (PARTITION BY m.documento_id, m.lote_id, m.cantidad) AS grp_count
    FROM inventario.item_movimientos m
    JOIN inventario.item_movimiento_tipo t ON t.id = m.item_movimiento_tipo_id
    WHERE m.documento_tipo = 'entrega'
      AND t.codigo NOT IN ('DEV_CLI_ING_REV', 'SERV_DEV_ING_REV', 'DEV_CLI_EGR_REV', 'DEV_PROV_EGR_REV')
),
reversales AS (
    SELECT m.id, m.documento_id, m.lote_id, m.cantidad,
           ROW_NUMBER() OVER (PARTITION BY m.documento_id, m.lote_id, m.cantidad ORDER BY m.id) AS rn,
           COUNT(*)     OVER (PARTITION BY m.documento_id, m.lote_id, m.cantidad) AS grp_count
    FROM inventario.item_movimientos m
    JOIN inventario.item_movimiento_tipo t ON t.id = m.item_movimiento_tipo_id
    WHERE m.documento_tipo = 'entrega'
      AND t.codigo IN ('DEV_CLI_ING_REV', 'SERV_DEV_ING_REV', 'DEV_CLI_EGR_REV', 'DEV_PROV_EGR_REV')
      AND m.reversion_movimiento_id IS NULL
)
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = orig.id
FROM   reversales rv
JOIN   originales orig
       ON  orig.documento_id = rv.documento_id
       AND orig.lote_id IS NOT DISTINCT FROM rv.lote_id
       AND orig.cantidad     = rv.cantidad
       AND orig.rn           = rv.rn
       AND orig.grp_count    = rv.grp_count
WHERE  rev.id = rv.id;


-- ── Verification (read-only — inspect after running, not part of the fix)
-- Per-family coverage: how many reversal rows got linked vs remain NULL.
-- SELECT t.codigo, COUNT(*) FILTER (WHERE m.reversion_movimiento_id IS NOT NULL) AS linked,
--        COUNT(*) FILTER (WHERE m.reversion_movimiento_id IS NULL)     AS unlinked
-- FROM inventario.item_movimientos m
-- JOIN inventario.item_movimiento_tipo t ON t.id = m.item_movimiento_tipo_id
-- WHERE t.codigo LIKE '%\_REV' ESCAPE '\' OR t.codigo IN ('AJUSTE_POS','AJUSTE_NEG')
-- GROUP BY t.codigo ORDER BY t.codigo;

-- ═══════════════════════════════════════════════════════════════
-- Patch 61: fix backward (physically-impossible) links from patch 60
-- ---------------------------------------------------------------------
-- Bug: patch 60's section C ("anular_produccion: general PROD_CONSUMO_REV")
-- matched a reversal to "the" original whenever the group had exactly one
-- candidate sharing (documento_id, item_id, lote_id, cantidad) — but never
-- checked that the candidate actually predated the reversal. Verified live
-- (2026-07-30): 287 of section C's 403 links point at an original whose id
-- is HIGHER than the reversal's own id — i.e. "reversed" a movement that
-- did not exist yet at posting time. Sections A/B/D/E were checked and are
-- clean (0 invalid rows each) — this defect is isolated to section C.
-- Also verified: 0 of the 287 touch a MATIZADO-motivo original, so
-- reporte.vw_matizado was never corrupted by this — but the column itself
-- is wrong regardless and must be corrected, since it's meant to be
-- trustworthy ledger metadata, not just BI-view input.
--
-- Fix, in two parts:
--   1. Reset every backward link (orig.id > rev.id) to NULL — a targeted,
--      generic correction (not scoped by movement type), so it self-heals
--      regardless of which section produced a given bad link.
--   2. Re-match every still-unlinked reversal (freed rows + rows that were
--      already NULL) using "nearest preceding, unclaimed" — process
--      reversals in id order; for each, claim the highest-id original that
--      (a) shares the key, (b) precedes the reversal, and (c) hasn't
--      already been claimed by an earlier-processed reversal in this run.
--      Implemented as a procedural loop, not a single set-based UPDATE:
--      the earlier bug's root cause was exactly this kind of ambiguity,
--      and a loop claims one original at a time so two reversals can never
--      race for the same original within one statement.
--
-- Idempotent: only touches rows where reversion_movimiento_id IS NULL (or
-- is a detected backward link); safe to re-run.
-- Requires: migration/40b, patches/60 (already applied).
-- ═══════════════════════════════════════════════════════════════

-- ── Step 1: reset backward links ──────────────────────────────────────
UPDATE inventario.item_movimientos rev
SET    reversion_movimiento_id = NULL
FROM   inventario.item_movimientos orig
WHERE  rev.reversion_movimiento_id = orig.id
  AND  orig.id > rev.id;


-- ── Step 2: re-match with "nearest preceding, unclaimed" ──────────────
DO $$
DECLARE
    v_prod_consumo_id     smallint;
    v_prod_consumo_rev_id smallint;
    v_matizado_motivo_id  smallint;
    r          RECORD;
    v_orig_id  BIGINT;
BEGIN
    SELECT id INTO v_prod_consumo_id     FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';
    SELECT id INTO v_prod_consumo_rev_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV';
    SELECT id INTO v_matizado_motivo_id  FROM inventario.item_movimiento_motivo WHERE codigo = 'MATIZADO';

    -- Section A: corregir_matizado (motivo = MATIZADO)
    FOR r IN (
        SELECT id, documento_id, item_id, lote_id, cantidad
        FROM inventario.item_movimientos
        WHERE documento_tipo          = 'partida_paso_ejecucion'
          AND item_movimiento_tipo_id = v_prod_consumo_rev_id
          AND motivo_id               = v_matizado_motivo_id
          AND reversion_movimiento_id IS NULL
        ORDER BY id
    ) LOOP
        SELECT o.id INTO v_orig_id
        FROM inventario.item_movimientos o
        WHERE o.documento_tipo          = 'partida_paso_ejecucion'
          AND o.item_movimiento_tipo_id = v_prod_consumo_id
          AND o.motivo_id               = v_matizado_motivo_id
          AND o.documento_id = r.documento_id
          AND o.item_id      = r.item_id
          AND o.lote_id IS NOT DISTINCT FROM r.lote_id
          AND o.cantidad     = r.cantidad
          AND o.id           < r.id
          AND NOT EXISTS (
              SELECT 1 FROM inventario.item_movimientos claimed
              WHERE claimed.reversion_movimiento_id = o.id
          )
        ORDER BY o.id DESC
        LIMIT 1;

        IF v_orig_id IS NOT NULL THEN
            UPDATE inventario.item_movimientos SET reversion_movimiento_id = v_orig_id WHERE id = r.id;
        END IF;
    END LOOP;

    -- Section C: anular_produccion general reversal (motivo IS NULL) —
    -- the family that had the bug. Original candidates can carry ANY
    -- motivo (anular_produccion doesn't care what the original's motivo
    -- was), matching the live function's own behavior.
    FOR r IN (
        SELECT id, documento_id, item_id, lote_id, cantidad
        FROM inventario.item_movimientos
        WHERE documento_tipo          = 'partida_paso_ejecucion'
          AND item_movimiento_tipo_id = v_prod_consumo_rev_id
          AND motivo_id               IS NULL
          AND reversion_movimiento_id IS NULL
        ORDER BY id
    ) LOOP
        SELECT o.id INTO v_orig_id
        FROM inventario.item_movimientos o
        WHERE o.documento_tipo          = 'partida_paso_ejecucion'
          AND o.item_movimiento_tipo_id = v_prod_consumo_id
          AND o.documento_id = r.documento_id
          AND o.item_id      = r.item_id
          AND o.lote_id IS NOT DISTINCT FROM r.lote_id
          AND o.cantidad     = r.cantidad
          AND o.id           < r.id
          AND NOT EXISTS (
              SELECT 1 FROM inventario.item_movimientos claimed
              WHERE claimed.reversion_movimiento_id = o.id
          )
        ORDER BY o.id DESC
        LIMIT 1;

        IF v_orig_id IS NOT NULL THEN
            UPDATE inventario.item_movimientos SET reversion_movimiento_id = v_orig_id WHERE id = r.id;
        END IF;
    END LOOP;

    -- Section F: anular_devolucion_* (*_REV vs non-REV within one entrega).
    -- No rows of this family exist yet (checked live), but included for
    -- consistency/future-proofing rather than leaving the same flawed
    -- shape dormant for whenever the feature is first used.
    FOR r IN (
        SELECT m.id, m.documento_id, m.lote_id, m.cantidad
        FROM inventario.item_movimientos m
        JOIN inventario.item_movimiento_tipo t ON t.id = m.item_movimiento_tipo_id
        WHERE m.documento_tipo = 'entrega'
          AND t.codigo IN ('DEV_CLI_ING_REV', 'SERV_DEV_ING_REV', 'DEV_CLI_EGR_REV', 'DEV_PROV_EGR_REV')
          AND m.reversion_movimiento_id IS NULL
        ORDER BY m.id
    ) LOOP
        SELECT o.id INTO v_orig_id
        FROM inventario.item_movimientos o
        JOIN inventario.item_movimiento_tipo ot ON ot.id = o.item_movimiento_tipo_id
        WHERE o.documento_tipo = 'entrega'
          AND ot.codigo NOT IN ('DEV_CLI_ING_REV', 'SERV_DEV_ING_REV', 'DEV_CLI_EGR_REV', 'DEV_PROV_EGR_REV')
          AND o.documento_id = r.documento_id
          AND o.lote_id IS NOT DISTINCT FROM r.lote_id
          AND o.cantidad     = r.cantidad
          AND o.id           < r.id
          AND NOT EXISTS (
              SELECT 1 FROM inventario.item_movimientos claimed
              WHERE claimed.reversion_movimiento_id = o.id
          )
        ORDER BY o.id DESC
        LIMIT 1;

        IF v_orig_id IS NOT NULL THEN
            UPDATE inventario.item_movimientos SET reversion_movimiento_id = v_orig_id WHERE id = r.id;
        END IF;
    END LOOP;
END $$;


-- ── Verification (read-only) ──────────────────────────────────────────
-- 1. Must return zero rows — confirms no backward links remain.
SELECT rev.id, rev.reversion_movimiento_id
FROM inventario.item_movimientos rev
JOIN inventario.item_movimientos orig ON orig.id = rev.reversion_movimiento_id
WHERE orig.id > rev.id;
--
-- 2. Coverage after the fix, per family.
SELECT t.codigo, mo.codigo AS motivo,
       COUNT(*) FILTER (WHERE m.reversion_movimiento_id IS NOT NULL) AS linked,
       COUNT(*) FILTER (WHERE m.reversion_movimiento_id IS NULL)     AS unlinked
FROM inventario.item_movimientos m
JOIN inventario.item_movimiento_tipo t ON t.id = m.item_movimiento_tipo_id
LEFT JOIN inventario.item_movimiento_motivo mo ON mo.id = m.motivo_id
WHERE t.codigo LIKE '%\_REV' ESCAPE '\' OR t.codigo IN ('AJUSTE_POS','AJUSTE_NEG')
GROUP BY t.codigo, mo.codigo ORDER BY t.codigo, motivo;


SELECT rev.id, rev.reversion_movimiento_id
FROM inventario.item_movimientos rev
JOIN inventario.item_movimiento_tipo t ON t.id = rev.item_movimiento_tipo_id
JOIN inventario.item_movimientos orig ON orig.id = rev.reversion_movimiento_id
WHERE orig.id > rev.id;
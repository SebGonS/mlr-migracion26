-- ============================================================================
-- PATCH 26 — mes.partida.precio_kg: optional price snapshot ("the price given")
-- ----------------------------------------------------------------------------
-- The sales/commercial side is deliberately scaled down: MLR does NOT emit
-- facturas de venta (no SUNAT FE; the incumbent system owns emitted docs).
-- Dispatch and devoluciones are accepted as headless entregas (movement only).
--
-- What we still want is "what was partida X priced at" — the per-kg rate only.
-- NOT amounts: no cantidad × precio, no IGV, no totals. That math stays out of
-- this system entirely.
--
--   precio_kg NULL     → derive from doc.catalogo_precios at the dispatch date
--                        (default path; the reliable catalog is the source).
--   precio_kg NOT NULL → override: a negotiated price that differs from the
--                        rate card, OR a frozen value immutable to later catalog
--                        edits / changes in fn_get_precio scoring.
--
-- Mirrored (for context) into the mes.partida CREATE in migration/07.
-- Idempotent.
-- ============================================================================

ALTER TABLE mes.partida
    ADD COLUMN IF NOT EXISTS precio_kg NUMERIC(10,4);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_partida_precio_kg_nonneg'
    ) THEN
        ALTER TABLE mes.partida
            ADD CONSTRAINT chk_partida_precio_kg_nonneg
            CHECK (precio_kg IS NULL OR precio_kg >= 0);
    END IF;
END $$;

COMMENT ON COLUMN mes.partida.precio_kg IS
    'Optional price snapshot (per-kg rate only, no amounts/IGV). NULL = derive from catalogo_precios; non-NULL = negotiated/frozen override.';

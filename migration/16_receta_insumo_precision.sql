-- ═══════════════════════════════════════════════════════════════
-- Migration 16: Increase decimal precision on recipe insumo quantities
--
-- Problem: NUMERIC(8,4) = max 9999.9999 — only 4 decimal places.
--          Some g/kg ratios require 6 decimal places (e.g. 0.123456 g/kg).
-- Solution: NUMERIC(10,6) = max 9999.999999 — same integer range, +2 decimals.
--
-- NOTE: NUMERIC(8,6) would be WRONG — it only allows 2 integer digits (max 99.xx).
--
-- Why the DROP/RECREATE on tenido_paso_insumo:
--   trg_bud_tenido_paso_insumo_immutable uses BEFORE UPDATE OF ... cantidad ...
--   PostgreSQL blocks ALTER COLUMN TYPE on any column named in a trigger's
--   column list. The fix is drop → alter → recreate in one transaction.
--   lavado_maquina_paso_insumo has no such column-list trigger, so it needs
--   only the plain ALTER.
--
-- Computed quantities in functions (generar_receta) now include explicit ROUND(…,4)
-- — see funciones/mes.sql for those changes (applied via CREATE OR REPLACE).
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ── Dyeing recipe step insumos ────────────────────────────────
-- Step 1: drop the column-list trigger that blocks the ALTER
DROP TRIGGER IF EXISTS trg_bud_tenido_paso_insumo_immutable
    ON receta.tenido_paso_insumo;

-- Step 2: widen the column
ALTER TABLE receta.tenido_paso_insumo
    ALTER COLUMN cantidad TYPE NUMERIC(10,6);

-- Step 3: recreate the trigger (identical definition, new column type)
CREATE TRIGGER trg_bud_tenido_paso_insumo_immutable
BEFORE UPDATE OF item_id, cantidad, medida, orden
ON receta.tenido_paso_insumo
FOR EACH ROW EXECUTE FUNCTION receta.fn_trg_tenido_paso_insumo_immutable();

-- ── Machine wash recipe step insumos ─────────────────────────
-- No column-list trigger on this table — plain ALTER is enough.
ALTER TABLE receta.lavado_maquina_paso_insumo
    ALTER COLUMN cantidad TYPE NUMERIC(10,6);

COMMIT;

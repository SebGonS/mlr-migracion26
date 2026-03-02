-- ═══════════════════════════════════════════════════════════════
-- Step 4: ALTER pre-existing legacy tables
-- These tables already exist in the DB — we're adding columns/constraints.
-- All use ADD COLUMN IF NOT EXISTS / DROP COLUMN IF EXISTS for idempotency.
-- ═══════════════════════════════════════════════════════════════

-- ── color ──────────────────────────────────────────────────────
ALTER TABLE color ADD COLUMN IF NOT EXISTS codigo text;
ALTER TABLE color ADD COLUMN IF NOT EXISTS hex text;

UPDATE color
SET codigo = UPPER(regexp_replace(color, '[^a-zA-Z0-9]', '', 'g'))
WHERE codigo IS NULL;

ALTER TABLE color
ADD CONSTRAINT IF NOT EXISTS color_codigo_uk UNIQUE (codigo);

-- ── color_x_cliente ────────────────────────────────────────────
ALTER TABLE color_x_cliente ADD COLUMN IF NOT EXISTS hex text;

-- ── estado ─────────────────────────────────────────────────────
-- FIX (BUG 6): drop then re-add typed columns safely.
-- Only safe if no views/functions depend on the old column type.
ALTER TABLE estado
    DROP COLUMN IF EXISTS estado_produccion,
    DROP COLUMN IF EXISTS estado_comercial;
ALTER TABLE estado
    ADD COLUMN IF NOT EXISTS estado_produccion orden_produccion_estado_enum,
    ADD COLUMN IF NOT EXISTS estado_comercial  partida_estado_enum;

-- ── articulo_tipo (renamed from tipo_articulo) ─────────────────
-- Step 1: rename table and column
-- ALTER TABLE tipo_articulo RENAME TO articulo_tipo;
-- ALTER TABLE articulo_tipo RENAME COLUMN tipo_articulo TO nombre;

-- Step 2: add codigo_canon (derived from nombre)
ALTER TABLE articulo_tipo ADD COLUMN IF NOT EXISTS codigo_canon TEXT;
UPDATE articulo_tipo SET codigo_canon = lower(unaccent(nombre)) WHERE codigo_canon IS NULL;
-- ALTER TABLE articulo_tipo ALTER COLUMN codigo_canon SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_articulo_tipo_cc ON articulo_tipo(codigo_canon);

-- Attach correct trigger (derives from nombre, not codigo)
DROP TRIGGER IF EXISTS trg_bi_articulo_tipo_codigo_canon ON articulo_tipo;
CREATE TRIGGER trg_bi_articulo_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON articulo_tipo
FOR EACH ROW EXECUTE FUNCTION fn_trg_set_codigo_canon_from_nombre();

-- ── articulo ───────────────────────────────────────────────────
-- Step 1: rename columns
-- ALTER TABLE articulo RENAME COLUMN articulo TO nombre;
-- ALTER TABLE articulo RENAME COLUMN tipo_articulo_id TO articulo_tipo_id;

-- Step 2: add codigo_canon (derived from nombre)
ALTER TABLE articulo ADD COLUMN IF NOT EXISTS codigo_canon TEXT;
UPDATE articulo SET codigo_canon = lower(unaccent(nombre)) WHERE codigo_canon IS NULL;
-- ALTER TABLE articulo ALTER COLUMN codigo_canon SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_articulo_cc ON articulo(codigo_canon);

-- Step 3: add fibra if not already present (backfill from item_rollo_detalle)
-- Sanity check first (must return 0 rows before proceeding):
-- SELECT articulo_id, COUNT(DISTINCT fibra)
--   FROM item_rollo_detalle GROUP BY articulo_id HAVING COUNT(DISTINCT fibra) > 1;
ALTER TABLE articulo ADD COLUMN IF NOT EXISTS fibra SMALLINT;
UPDATE articulo ar
   SET fibra = ird.fibra
  FROM item_rollo_detalle ird
 WHERE ird.articulo_id = ar.id
   AND ar.fibra IS NULL;

-- Attach correct trigger (derives from nombre, not codigo)
DROP TRIGGER IF EXISTS trg_bi_articulo_codigo_canon ON articulo;
CREATE TRIGGER trg_bi_articulo_codigo_canon
BEFORE INSERT OR UPDATE ON articulo
FOR EACH ROW EXECUTE FUNCTION fn_trg_set_codigo_canon_from_nombre();

-- ── item_rollo_detalle (old) ────────────────────────────────────
-- fibra column moved to articulo — drop from item_rollo_detalle
-- This only applies if the OLD item_rollo_detalle already exists with fibra.
-- If creating fresh, this runs silently (IF EXISTS covers the column).
ALTER TABLE item_rollo_detalle DROP COLUMN IF EXISTS fibra;

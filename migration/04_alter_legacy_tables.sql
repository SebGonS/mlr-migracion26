-- ═══════════════════════════════════════════════════════════════
-- Step 4: ALTER pre-existing legacy tables
-- All operations use DO $$ guards / ADD COLUMN IF NOT EXISTS
-- so the script is idempotent and safe to re-run.
-- ═══════════════════════════════════════════════════════════════

-- ── tipo_lavado_maquina ────────────────────────────────────────
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tipo_lavado_maquina' AND column_name = 'tipo_lavado_mq'
    ) THEN
        ALTER TABLE tipo_lavado_maquina RENAME COLUMN tipo_lavado_mq TO nombre;
    END IF;
END $$;

-- ── color ──────────────────────────────────────────────────────
ALTER TABLE color ADD COLUMN IF NOT EXISTS codigo text;
ALTER TABLE color ADD COLUMN IF NOT EXISTS hex    text;

UPDATE color
SET codigo = UPPER(regexp_replace(color, '[^a-zA-Z0-9]', '', 'g'))
WHERE codigo IS NULL;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'color_codigo_uk' AND table_name = 'color'
    ) THEN
        ALTER TABLE color ADD CONSTRAINT color_codigo_uk UNIQUE (codigo);
    END IF;
END $$;

ALTER TABLE color ADD COLUMN IF NOT EXISTS codigo_canon TEXT;
UPDATE color SET codigo_canon = lower(unaccent(codigo)) WHERE codigo_canon IS NULL AND codigo IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_color_cc ON color(codigo_canon);
DROP TRIGGER IF EXISTS trg_bi_color_codigo_canon ON color;
CREATE TRIGGER trg_bi_color_codigo_canon
BEFORE INSERT OR UPDATE ON color
FOR EACH ROW EXECUTE FUNCTION fn_trg_set_codigo_canon();

-- Auto-gen: derive codigo from color name if not provided (fires before canon trigger)
DROP TRIGGER IF EXISTS trg_bi_gen_codigo_color ON color;
CREATE TRIGGER trg_bi_gen_codigo_color
BEFORE INSERT ON color
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_gen_codigo_color();

-- ── color_x_cliente ────────────────────────────────────────────
ALTER TABLE color_x_cliente ADD COLUMN IF NOT EXISTS hex text;
ALTER TABLE color_x_cliente ADD COLUMN IF NOT EXISTS tercero_id INT REFERENCES tercero(id);

-- ── estado ─────────────────────────────────────────────────────
ALTER TABLE estado
    DROP COLUMN IF EXISTS estado_produccion,
    DROP COLUMN IF EXISTS estado_comercial;
ALTER TABLE estado
    ADD COLUMN IF NOT EXISTS estado_produccion orden_produccion_estado_enum,
    ADD COLUMN IF NOT EXISTS estado_comercial  partida_estado_enum;

-- ═══════════════════════════════════════════════════════════════
-- articulo_tipo (prod table: tipo_articulo) and articulo
-- ─────────────────────────────────────────────────────────────
-- These are the only catalog tables without a 'codigo' column in prod.
-- Strategy: ALTER TABLE RENAME (atomic, preserves all FK constraints
-- automatically — Postgres updates dependent tables/indexes on rename).
-- We also add 'codigo' for consistency with every other catalog table.
--
-- After running, review backfilled codes for collisions/truncation before
-- enforcing NOT NULL / UNIQUE on codigo (commented steps at the bottom).
-- ═══════════════════════════════════════════════════════════════

-- ── tipo_articulo → articulo_tipo ──────────────────────────────

-- 1. Rename table (idempotent: skips if already renamed)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'tipo_articulo') THEN
        ALTER TABLE tipo_articulo RENAME TO articulo_tipo;
    END IF;
END $$;

-- 2. Rename column tipo_articulo → nombre
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'articulo_tipo' AND column_name = 'tipo_articulo'
    ) THEN
        ALTER TABLE articulo_tipo RENAME COLUMN tipo_articulo TO nombre;
    END IF;
END $$;

-- 3. Add codigo and backfill (UPPER + strip non-alphanum, same formula as color.codigo)
ALTER TABLE articulo_tipo ADD COLUMN IF NOT EXISTS codigo TEXT;
UPDATE articulo_tipo
SET codigo = UPPER(regexp_replace(nombre, '[^a-zA-Z0-9]', '', 'g'))
WHERE codigo IS NULL;

-- 4. Add codigo_canon and backfill from codigo
ALTER TABLE articulo_tipo ADD COLUMN IF NOT EXISTS codigo_canon TEXT;
UPDATE articulo_tipo SET codigo_canon = lower(unaccent(codigo)) WHERE codigo_canon IS NULL AND codigo IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_articulo_tipo_cc ON articulo_tipo(codigo_canon);

-- 5. Attach standard trigger
DROP TRIGGER IF EXISTS trg_bi_articulo_tipo_codigo_canon ON articulo_tipo;
CREATE TRIGGER trg_bi_articulo_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON articulo_tipo
FOR EACH ROW EXECUTE FUNCTION fn_trg_set_codigo_canon();

-- REVIEW BEFORE ENFORCING:
--   SELECT codigo, COUNT(*) FROM articulo_tipo GROUP BY codigo HAVING COUNT(*) > 1;
-- Then enforce:
--   ALTER TABLE articulo_tipo ALTER COLUMN codigo SET NOT NULL;
--   ALTER TABLE articulo_tipo ADD CONSTRAINT articulo_tipo_codigo_uk UNIQUE (codigo);

-- ── articulo ───────────────────────────────────────────────────

-- 1. Rename articulo → nombre
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'articulo' AND column_name = 'articulo'
    ) THEN
        ALTER TABLE articulo RENAME COLUMN articulo TO nombre;
    END IF;
END $$;

-- 2. Rename tipo_articulo_id → articulo_tipo_id
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'articulo' AND column_name = 'tipo_articulo_id'
    ) THEN
        ALTER TABLE articulo RENAME COLUMN tipo_articulo_id TO articulo_tipo_id;
    END IF;
END $$;

-- 3. Add codigo and backfill
ALTER TABLE articulo ADD COLUMN IF NOT EXISTS codigo TEXT;
UPDATE articulo
SET codigo = UPPER(regexp_replace(nombre, '[^a-zA-Z0-9]', '', 'g'))
WHERE codigo IS NULL;

-- 4. Add codigo_canon and backfill from codigo
ALTER TABLE articulo ADD COLUMN IF NOT EXISTS codigo_canon TEXT;
UPDATE articulo SET codigo_canon = lower(unaccent(codigo)) WHERE codigo_canon IS NULL AND codigo IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_articulo_cc ON articulo(codigo_canon);

-- 5. Add fibra and backfill from item_rollo_detalle
--    MUST run before item_rollo_detalle.fibra is dropped (step below).
--    Pre-check (run manually, must return 0 rows before proceeding):
--      SELECT articulo_id, COUNT(DISTINCT fibra) n
--      FROM item_rollo_detalle GROUP BY articulo_id HAVING COUNT(DISTINCT fibra) > 1;
ALTER TABLE articulo ADD COLUMN IF NOT EXISTS fibra SMALLINT;

UPDATE articulo ar
SET fibra = CASE
    WHEN ar.nombre ILIKE '%poly%' THEN 2
    ELSE COALESCE(
        (SELECT MAX(p.fibra)
         FROM partida p
         WHERE p.articulo_id = ar.id
           AND p.fibra IS NOT NULL),
        1   -- fallback if no partida data at all
    )
END
WHERE ar.fibra IS NULL
  AND ar.id IN (SELECT DISTINCT articulo_id FROM partida WHERE articulo_id IS NOT NULL);

-- 6. Attach standard trigger
DROP TRIGGER IF EXISTS trg_bi_articulo_codigo_canon ON articulo;
CREATE TRIGGER trg_bi_articulo_codigo_canon
BEFORE INSERT OR UPDATE ON articulo
FOR EACH ROW EXECUTE FUNCTION fn_trg_set_codigo_canon();

-- REVIEW BEFORE ENFORCING:
--   SELECT codigo, COUNT(*) FROM articulo GROUP BY codigo HAVING COUNT(*) > 1;
-- Then enforce:
--   ALTER TABLE articulo ALTER COLUMN codigo SET NOT NULL;
--   ALTER TABLE articulo ADD CONSTRAINT articulo_codigo_uk UNIQUE (codigo);

-- ── item_rollo_detalle.fibra ────────────────────────────────────
-- Drop fibra from item_rollo_detalle AFTER backfill above completes.
ALTER TABLE IF EXISTS item_rollo_detalle DROP COLUMN IF EXISTS fibra;

-- ── profiles → usuario ───────────────────────────────────────────
-- Rename legacy Supabase profiles table and its columns to Spanish conventions.
-- id (uuid, FK to auth.users) → auth_id
-- id_usuario (integer, true PK) → id
-- first_name → nombre, last_name → apellido
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'profiles') THEN
        ALTER TABLE public.profiles RENAME TO usuario;
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'usuario' AND column_name = 'id') THEN
        ALTER TABLE public.usuario RENAME COLUMN id TO auth_id;
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'usuario' AND column_name = 'id_usuario') THEN
        ALTER TABLE public.usuario RENAME COLUMN id_usuario TO id;
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'usuario' AND column_name = 'first_name') THEN
        ALTER TABLE public.usuario RENAME COLUMN first_name TO nombre;
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'usuario' AND column_name = 'last_name') THEN
        ALTER TABLE public.usuario RENAME COLUMN last_name TO apellido;
    END IF;
END $$;

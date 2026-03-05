# Migration Execution Order

Run each step in sequence. If any step fails, do NOT continue — diagnose first.

## Steps

| # | File | Notes |
|---|------|-------|
| 1 | `migration/01_extensions_schemas.sql` | Extensions + all schemas |
| 2 | `migration/02_enums.sql` | All ENUM types (safe, idempotent) |
| 3 | `migration/03_base_functions.sql` | `get_user_id()`, audit helpers, `fn_trg_immutable_codigo`, `fn_trg_prevent_hard_delete`, auto-gen code triggers |
| 4 | `migration/04_alter_legacy_tables.sql` | ALTER pre-existing tables (color, articulo, etc.) |
| 5 | `migration/05_new_tables_foundation.sql` | unidad, item, insumo_tipo, inventario.* tables |
| 6 | `migration/06_receta_tables.sql` | receta schema |
| 7 | `migration/07_new_tables_mes_doc_calidad.sql` | doc, mes, calidad tables |
| 8 | `migration/08_views.sql` | All views + grants |
| 9 | `migration/09_constraints_audit.sql` | Immutability/prevent-delete triggers, audit schema, lote sequence, all REVOKEs + per-table audit triggers |
| 10 | `migration/10_auth.sql` | JWT hook, RLS helper, RLS policies |
| 11 | `funciones/core.sql` | Core item/almacen functions |
| 12 | `funciones/mes.sql` | MES functions (BUG5 fixed in-file) |
| 13 | `funciones/calidad.sql` | QC functions |
| 14 | `funciones/receta.sql` | Recipe lifecycle functions |
| 15 | `funciones/compras.sql` | Procurement functions |
| 16 | `funciones/inventario.sql` | Cuadre de inventario functions (depends on `mes.calcular_fifo` from step 12) |
| **DATA** | | Run only after all DDL is verified |
| 17 | `migracion_data.sql` | Hex colors, etc. |
| 18a | `migracion_recetas.sql` lines 1–96 | PRE-MIGRATION PREP (outside transaction) — review output before 18b |
| 18b | `migracion_recetas.sql` lines 97–348 | `BEGIN...COMMIT` recipe migration |

## Project Structure

```
migration/          ← authoritative DDL (steps 1–10), run once on fresh DB
  01–10_*.sql
funciones/          ← business logic (steps 11–16), re-run freely on updates
  core.sql
  mes.sql
  calidad.sql
  receta.sql
  compras.sql
  inventario.sql
migracion_data.sql  ← seed data (step 17)
migracion_recetas.sql ← data migration (steps 18a/18b)
```

## Source of Truth

**The `migration/` numbered files are the authoritative DDL source.**

All future schema changes go into the relevant numbered `migration/` file.
Business logic changes go into the relevant `funciones/` file.

## Bugs Fixed Before Running

| Bug | File | Fix Applied |
|-----|------|-------------|
| BUG1 | `migration/05` | ALTER item_rollo_detalle moved after CREATE |
| BUG3 | `migration/04` | `tipo_articulo`/`articulo` use ALTER TABLE RENAME + ADD COLUMN `codigo` |
| BUG4 | `migration/06` | Stray `SELECT * FROM paso` removed |
| BUG5 | `funciones/mes.sql` | `lm.receta_lavado_maquina_id` → `lm.receta_id` |
| BUG6 | `migration/02` | `DROP TYPE IF EXISTS` replaced with safe DO $$ idempotent block |
| BUG7 | `migration/01` | `CREATE SCHEMA inventario` → `CREATE SCHEMA IF NOT EXISTS inventario` |

## articulo_tipo / articulo — post-migration checklist

Step 4 backfills `codigo` automatically but does **not** enforce uniqueness yet.
Before enforcing, run these checks and fix any collisions manually:

```sql
-- Check for duplicate codes (must return 0 rows before enforcing)
SELECT codigo, COUNT(*) FROM articulo_tipo GROUP BY codigo HAVING COUNT(*) > 1;
SELECT codigo, COUNT(*) FROM articulo      GROUP BY codigo HAVING COUNT(*) > 1;

-- Then enforce:
ALTER TABLE articulo_tipo ALTER COLUMN codigo SET NOT NULL;
ALTER TABLE articulo_tipo ADD CONSTRAINT articulo_tipo_codigo_uk UNIQUE (codigo);
ALTER TABLE articulo      ALTER COLUMN codigo SET NOT NULL;
ALTER TABLE articulo      ADD CONSTRAINT articulo_codigo_uk UNIQUE (codigo);
```

## Still Requires Manual Action

- **BUG2** (`medida_enum`): Uncomment the CREATE TYPE block in `02_enums.sql`
  ONLY if applying to a fresh DB. On the existing production DB, this type
  already exists as a legacy type — leave commented.

- **WARN A** (`funciones/core.sql` `get_item`): References old legacy column names
  (`ar.articulo`, `ta.tipo_articulo`). Update after step 4 runs successfully.

- **migracion_recetas.sql** step 18a: After running lines 1–96, run the
  diagnostic queries to review op_id mapping, correct any NULL rows, then
  proceed with 18b (the `BEGIN...COMMIT` block).

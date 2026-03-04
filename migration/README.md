# Migration Execution Order

Run each step in sequence. If any step fails, do NOT continue — diagnose first.

## Steps

| # | File | Notes |
|---|------|-------|
| 1 | `migration/01_extensions_schemas.sql` | Extensions + all schemas |
| 2 | `migration/02_enums.sql` | All ENUM types (safe, idempotent) |
| 3 | `migration/03_base_functions.sql` | fn_trg_set_codigo_canon + audit helpers |
| 4 | `migration/04_alter_legacy_tables.sql` | ALTER pre-existing tables (color, articulo, etc.) |
| 5 | `migration/05_new_tables_foundation.sql` | unidad, item, insumo_tipo, inventario.* tables |
| 6 | `migration/06_receta_tables.sql` | receta schema (fixed: articulo_id, no stray SELECT) |
| 7 | `migration/07_new_tables_mes_doc_calidad.sql` | doc, mes, calidad tables |
| 8 | `migration/08_views.sql` | All views |
| 9 | `constraints.sql` | Audit schema, triggers, REVOKEs |
| 10 | `funciones.sql` | Core item/almacen functions |
| 11 | `funciones/mes.sql` | MES functions (BUG5 fixed in-file) |
| 12 | `funciones/calidad.sql` | QC functions |
| 13 | `funciones/receta.sql` | Recipe lifecycle functions |
| 14 | `funciones/compras.sql` | Procurement functions |
| 15 | `auth.sql` | RLS policies |
| **DATA** | | Run only after all DDL is verified |
| 16 | `migracion_data.sql` | Hex colors, etc. |
| 17a | `migracion_recetas.sql` lines 1–96 | PRE-MIGRATION PREP (outside transaction) — review output before 17b |
| 17b | `migracion_recetas.sql` lines 97–348 | `BEGIN...COMMIT` recipe migration |

## Bugs Fixed Before Running

| Bug | File | Fix Applied |
|-----|------|-------------|
| BUG1 | `tablas.sql` | ALTER item_rollo_detalle moved after CREATE |
| BUG3 | `tablas.sql` | `tipo_articulo`/`articulo` replaced CREATE TABLE IF NOT EXISTS with actual ALTER TABLE RENAME + ADD COLUMN `codigo`; standard trigger restored |
| BUG4 | `recetas.sql` | Stray `SELECT * FROM paso` removed |
| BUG5 | `funciones/mes.sql` | `lm.receta_lavado_maquina_id` → `lm.receta_id` |
| BUG6 | `tablas.sql` | `DROP TYPE IF EXISTS` → `DROP TYPE IF EXISTS ... CASCADE` |
| BUG7 | `tablas.sql` | `CREATE SCHEMA inventario` → `CREATE SCHEMA IF NOT EXISTS inventario` |

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

- **WARN A** (`funciones.sql` `get_item`): References old legacy column names
  (`ar.articulo`, `ta.tipo_articulo`). Update after step 4 runs successfully.

- **migracion_recetas.sql** step 17a: After running lines 1–96, run the
  diagnostic queries to review op_id mapping, correct any NULL rows, then
  proceed with 17b (the `BEGIN...COMMIT` block).

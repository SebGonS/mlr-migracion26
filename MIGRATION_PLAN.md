# Migration Execution Plan — MLR Schema

## Overview

All SQL files are a mix of fresh DDL (new tables), ALTERs on legacy tables,
seed data, business functions, and data migration — all interleaved with no
guaranteed order. This document fixes the dependency/ordering problems so
production can be applied cleanly.

---

## CRITICAL BUGS (will hard-fail)

### BUG 1 — `tablas.sql` ~line 503: ALTER before CREATE on `item_rollo_detalle`
```sql
ALTER TABLE item_rollo_detalle DROP COLUMN IF EXISTS fibra;  -- ← fails: table doesn't exist yet
...
CREATE TABLE item_rollo_detalle(...);  -- ← table created much later
```
**Fix**: Move the `ALTER TABLE item_rollo_detalle DROP COLUMN...` to AFTER the `CREATE TABLE item_rollo_detalle` block.

---

### BUG 2 — `tablas.sql` ~line 508: `medida_enum` used but never defined
```sql
CREATE TABLE item_insumo_detalle(
   medida medida_enum NOT NULL,  -- ← medida_enum is not defined anywhere in these files
```
**Fix**: Add `CREATE TYPE medida_enum AS ENUM ('g_L', 'g_kg', 'mL_L', 'mL_kg', '%');` before this table, OR confirm it already exists in the legacy DB and document it.
Currently it exists as a legacy type. If applying to a fresh DB it will fail.

---

### BUG 3 — `tablas.sql` ~lines 454, 466: Wrong trigger on `articulo_tipo` and `articulo`
Both tables have `fn_trg_set_codigo_canon` attached but have NO `codigo` column.
That trigger reads `NEW.codigo` — every INSERT/UPDATE on these tables will fail:
```
ERROR: record "new" has no field "codigo"
```
**Fix Option A**: Add a `codigo TEXT UNIQUE` column to `articulo_tipo` and `articulo`.
**Fix Option B** (used below): Replace the trigger with `fn_trg_set_codigo_canon_from_nombre` that reads `NEW.nombre` instead.

---

### BUG 4 — `recetas.sql` line 160: Stray query
```sql
SELECT * FROM paso   -- ← this table does not exist; instant error
```
**Fix**: Delete this line.

---

### BUG 5 — `funciones/mes.sql` ~line 43: Stale column reference
```sql
'receta_lavado_maquina_id',  lm.receta_lavado_maquina_id
```
But `mes.lavado_maquina` now has `receta_id`, not `receta_lavado_maquina_id`.
**Fix**: Change to `lm.receta_id`.

---

### BUG 6 — `tablas.sql`: `DROP TYPE IF EXISTS` without CASCADE
```sql
DROP TYPE IF EXISTS orden_produccion_estado_enum;
DROP TYPE IF EXISTS partida_estado_enum;
```
If these types already exist and are in use by a column, DROP will fail
(no CASCADE). On a fresh DB this is fine; on migration it may error.
**Fix**: `DROP TYPE IF EXISTS orden_produccion_estado_enum CASCADE;` or remove
the DROPs entirely and use `DO $$ BEGIN CREATE TYPE ... EXCEPTION WHEN duplicate_object THEN null; END $$;`

---

### BUG 7 — `tablas.sql` line 226: `CREATE SCHEMA inventario` (no IF NOT EXISTS)
```sql
CREATE SCHEMA inventario;   -- fails if already exists
```
**Fix**: `CREATE SCHEMA IF NOT EXISTS inventario;`

---

## WARNINGS (may silently fail or cause runtime errors)

### WARN A — `funciones.sql` `get_item`: legacy column/table names
```sql
ar.articulo          -- column renamed to ar.nombre
ta.tipo_articulo     -- column renamed to ta.nombre
ar.tipo_articulo_id  -- column renamed to articulo_tipo_id
tipo_articulo ta     -- table renamed to articulo_tipo
```
Function creates fine (SQL language validates lazily), but calling it will
return an error. Update these aliases once migration is complete.

### WARN B — `recetas.sql`: `receta.tenido` schema vs migration function mismatch
- DDL in `recetas.sql` still has `articulo_tipo_id` + `fibra` (old columns)
- `funciones/receta.sql` `crear_tenido` expects `p_articulo_id` (new column)
- Migration step 7a (commented out in recetas.sql) converts old → new
**Decision**: The new DDL file (`06_receta_tables.sql` below) uses `articulo_id`
(final state). The data migration must JOIN `articulo` to derive it.

### WARN C — `migracion_recetas.sql`: PRE-MIGRATION section must run OUTSIDE transaction
Lines 1–96 (the `ALTER TABLE public.receta_paso ADD COLUMN...` block) must run,
be reviewed/corrected manually, then the `BEGIN...COMMIT` block (lines 97–348)
runs. The file is structured correctly — just make sure to run them as two
separate executions.

---

## FILE INVENTORY

| File | Content | Depends On |
|------|---------|------------|
| `tablas.sql` | Schemas, ENUMs, base tables, views, grants | Legacy tables pre-existing |
| `funciones.sql` | Item/almacen/guia functions | tablas.sql |
| `constraints.sql` | Audit schema, triggers, REVOKEs | tablas.sql |
| `recetas.sql` | receta schema DDL + migration notes | tablas.sql |
| `funciones/mes.sql` | MES scheduling functions | tablas.sql, recetas.sql |
| `funciones/calidad.sql` | QC functions | tablas.sql |
| `funciones/receta.sql` | Recipe lifecycle functions | recetas.sql |
| `funciones/compras.sql` | Procurement functions | tablas.sql |
| `auth.sql` | RLS policies | all tables |
| `migracion_data.sql` | Data migration (hex colors, etc.) | tablas.sql |
| `migracion_recetas.sql` | Recipe data migration | recetas.sql, item.legacy_id populated |

---

## CORRECT EXECUTION ORDER

Run the files in this exact sequence against the target DB.
Assumes legacy tables exist: `color`, `color_x_cliente`, `cliente`, `proveedor`,
`profiles`, `turno`, `estado`, `prioridad`, `tenido`, `tipo_receta`,
`tipo_lavado_maquina`, `valor`, `articulo` (old), `tipo_articulo` (old),
`item_rollo_detalle` (old, with fibra column).

```
Step 1:  migration/01_extensions_schemas.sql
Step 2:  migration/02_enums.sql
Step 3:  migration/03_base_functions.sql
Step 4:  migration/04_alter_legacy_tables.sql
Step 5:  migration/05_new_tables_foundation.sql
Step 6:  migration/06_receta_tables.sql
Step 7:  migration/07_new_tables_mes_doc_calidad.sql
Step 8:  migration/08_seeds.sql
Step 9:  migration/09_views.sql
Step 10: migration/10_constraints_audit.sql     (= constraints.sql, unchanged)
Step 11: funciones.sql                          (run as-is, note WARN A)
Step 12: funciones/mes.sql                      (AFTER fixing BUG 5)
Step 13: funciones/calidad.sql
Step 14: funciones/receta.sql
Step 15: funciones/compras.sql
Step 16: auth.sql
--- Data migration (run after DDL is complete) ---
Step 17: migracion_data.sql
Step 18: migracion_recetas.sql  (lines 1-96 first → review → then lines 97-348)
```

See `migration/` directory for Steps 1–10 with all bug fixes applied.

---

## LEGACY TABLES ASSUMED PRE-EXISTING

These tables are referenced but NOT created by any file here.
They must already exist in the target DB:

- `public.color` — used in `vw_colores`, ALTER adds `codigo`/`hex`
- `public.color_x_cliente` — used in `vw_colores`, ALTER adds `hex`
- `public.cliente` — FK target in many tables
- `public.proveedor` — FK target in `doc.compra`, `doc.factura_proveedor`
- `public.profiles` — FK target (usr_cre fields)
- `public.turno` — FK target in `mes.empleado`
- `public.estado` — ALTER adds enum columns
- `public.prioridad` — FK in `doc.partida`
- `public.tenido` — FK in `doc.partida` and `receta.tenido`
- `public.tipo_receta` — FK in `receta.tenido`
- `public.tipo_lavado_maquina` — FK in `receta.lavado_maquina`
- `public.valor` — FK in `receta.lavado_maquina`
- `public.articulo` (old schema: `articulo`, `tipo_articulo_id`, `fibra`)
- `public.tipo_articulo` → now renamed to `articulo_tipo`
- `public.item_rollo_detalle` (old, with `fibra` column) — migrated
- `public.receta2`, `public.receta_paso`, `public.receta_paso_insumo`
- `public.receta_lavado_maquina`, `public.receta_lavado_maquina_paso`, `public.receta_lavado_maquina_paso_insumo`
- `public.receta_operacion`
- `medida_enum` type (legacy)
- `logs_api` table (referenced in `funciones.sql`)

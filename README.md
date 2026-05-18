# mlr-migracion26 — MLR Database Migration

PostgreSQL/Supabase schema migration for Manufacturas la Real.

## Documentation

See [SCHEMA_MANUAL.md](SCHEMA_MANUAL.md) for the full reference: tables, functions, views, business flows, and design patterns.

See [FRONTEND_BACKEND_MAP.md](FRONTEND_BACKEND_MAP.md) for the page-by-page frontend → SQL mapping.

## File Structure

```
migration/
  01_extensions_schemas.sql   — extensions, schemas, storage bucket
  02_enums.sql                — all ENUM types
  03_base_functions.sql       — trigger functions (audit, code gen, canon)
  04_alter_legacy_tables.sql  — alters to pre-existing legacy tables
  05_new_tables_foundation.sql— item, tercero, inventario core
  06_receta_tables.sql        — receta schema
  07_new_tables_mes_doc_calidad.sql — doc, mes, calidad schemas
  08_views.sql                — all views
  09_constraints_audit.sql    — immutability, hard-delete guards, audit table, REVOKEs
  10_auth.sql                 — JWT hook, RLS policies
  11_data_migration.sql       — data migration from legacy tables
  12_triggers_audit.sql       — audit cre/mod/elm triggers (run after data migration)
  14_cuadre_cutoff.sql        — inventory cutoff trigger (blocks retroactive movements past a closed cuadre)
  15_alerts_schema.sql        — alert infrastructure (persistent notifications, alertas schema, pg_cron)

funciones/
  core.sql        — item query functions
  inventario.sql  — cuadre de inventario functions
  mes.sql         — production scheduling and execution functions
  receta.sql      — recipe lifecycle functions
  calidad.sql     — quality inspection functions
  compras.sql     — purchase and payment functions
  despacho.sql    — dispatch and delivery functions
  facturacion.sql — invoicing functions
  alertas.sql     — alert evaluation cron functions
```

## Apply Order

Run migration files 01 → 12, then 14 → 15 in order, then all funciones files (order within funciones doesn't matter).

## Future Improvements

- Individual roll tracking: 1 roll = 1 item (currently 1 roll = 1 lote under a shared item)
- Separate legal documents from movement documents
- Separate partida into commercial order and production order
- QC support mid-production (currently only on finished output)

# MLR Database Migration - Copilot Instructions

## Project Overview
**Manufacturas la Real (MLR)** is a textile dyeing & manufacturing ERP database migration to PostgreSQL. This codebase contains the complete data model for managing production orders, inventory, materials, and logistics workflows.

## Architecture & Core Domains

### Schema Organization (Critical Structure)
- **`public`**: Core master data (units, items, item types, color-client mappings)
- **`inventario`**: Warehouse management (almacenes/warehouses, locations, movement types)
- **`doc`**: Business documents (partidas/production orders, guías de remisión/shipment guides)
- **`mes`**: Manufacturing execution (production planning & templates)
- **`audit`**: Change tracking (all table modifications logged via triggers)

### Key Entities & Relationships

**Item Management** (central master data):
- `item` + `item_tipo` (ROLLO, INSUMO, ROLLO_TERMINADO)
- Polymorphic details: `item_insumo_detalle` | `item_rollo_detalle`
- Items referenced throughout: production (`doc.partida`), inventory movements, shipments

**Inventory Core**:
- `inventario.almacen` (warehouse) → `inventario.ubicacion` (physical locations)
- Item movements tied to document types via `inventario.item_movimiento_tipo`

**Production & Documents**:
- `doc.partida` (production order with 6 states: creado→fin)
- `doc.partida_detalle` lists items + quantities per order
- `doc.guia_remision` models 6 shipping scenarios (compra_ingreso, venta_egreso, etc.)
- `doc.guia_remision_detalle` tracks item movement by lote/location

**Materials**:
- `insumo_tipo` (QUIM, COLOR, AUX) + `colorante_tipo` (DIR, DISP, RX)
- `item_rollo_detalle` references `articulo` & `color_x_cliente` (customer-specific colors)

## Critical Patterns

### Audit & Tracking
**Every table** includes 4 standard fields + 2 delete flags:
```sql
usr_cre, fyh_cre, usr_mod, fyh_mod  -- created/modified by user & timestamp
flg_elm, usr_elm, fyh_elm           -- soft delete flag + deletion audit
```
**All tables** auto-populate these via `BEFORE INSERT/UPDATE/DELETE` triggers calling:
- `fn_trg_set_cre_fields()`, `fn_trg_set_mod_fields()`, `fn_trg_set_elm_fields()`
- `audit.fn_audit_row()` (logs full row JSON to `audit.data_audit`)

### Canonicalization & Uniqueness
Master data uses **dual codes**: `codigo` (user input) + `codigo_canon` (auto-generated via `lower(unaccent(codigo))`)
- Prevents duplicates with accents, case differences
- Used for lookups: `unidad`, `item_tipo`, `insumo_tipo`, `colorante_tipo`, etc.

### RLS (Row-Level Security)
Tables REVOKE direct INSERT/UPDATE on audit fields from `anon`, `authenticated` roles—only app via functions can set these.

### Views & JSON APIs
- `vw_items` (joins item + type + unit—used by `get_item()`)
- `vw_colores` (client-color mapping)
- Functions like `get_item()`, `crear_partida()`, `modificar_partida()` return/consume JSONB for client-friendly APIs

## Development Workflow

### File Organization
- **`tablas.sql`**: Schema definitions, triggers, master data inserts (1363 lines)
- **`funciones.sql`**: Business logic & stored procedures (911 lines)
- **`constraints.sql`**: Foreign keys & rules (currently empty; intended for complex constraints)

### Adding New Tables
1. Add `CREATE TABLE` in `tablas.sql`
2. Include 4 audit fields + triggers calling `fn_trg_set_*_fields()` and `audit.fn_audit_row()`
3. Add REVOKE statements for RLS
4. Use `codigo_canon` pattern for all master data
5. Define `CREATE OR REPLACE FUNCTION` for CRUD operations in `funciones.sql`

### Modifying Functions
Functions follow naming: `[schema].crear_*()`, `modificar_*()`, `eliminar_*()`, `get_*()`.  
All consume/return JSONB. Example: `doc.crear_partida(p_partida jsonb)`.  
Error handling via `EXCEPTION` blocks capturing `SQLSTATE`, `detail`, `hint`.

## Dependencies & External Refs
- PostgreSQL extensions: `unaccent` (canonicalization)
- Supabase auth assumed (references `get_user_id()` function—ensure defined)
- Assumes `articulo`, `cliente`, `proveedor`, `color`, `tipo_articulo` tables exist upstream

## Common Pitfalls & Fixes
- **Missing `medida_enum` definition**: Used in `item_insumo_detalle` but not yet created—define with values (g, kg, L, etc.)
- **`item_rollo_detalle` comment**: References `(Note: ensure table 'articulo' exists)` in comments—verify FK during migration
- **Trigger duplicates**: Some tables have duplicate `trg_bu_*_audit` triggers—consolidate when deploying
- **`constraints.sql` empty**: Complex multi-table constraints should be added here

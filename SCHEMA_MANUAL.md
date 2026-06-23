# MLR Database Schema Manual

**Manufacturas la Real — Supabase/PostgreSQL backend**
Last updated: 2026-06-02

This document is the authoritative reference for all schemas, tables, functions, views, and triggers in the MLR system.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Schemas](#2-schemas)
3. [Global Design Patterns](#3-global-design-patterns)
4. [ENUM Types](#4-enum-types)
5. [Schema: `public` — Master Data](#5-schema-public--master-data)
6. [Schema: `inventario` — Inventory](#6-schema-inventario--inventory)
7. [Schema: `doc` — Commercial Documents](#7-schema-doc--commercial-documents)
8. [Schema: `mes` — Manufacturing Execution](#8-schema-mes--manufacturing-execution)
9. [Schema: `receta` — Recipes](#9-schema-receta--recipes)
10. [Schema: `calidad` — Quality Control](#10-schema-calidad--quality-control)
11. [Schema: `audit` — Audit Trail](#11-schema-audit--audit-trail)
12. [Schema: `notification` and `alertas` — Notifications](#12-schema-notification-and-alertas--notifications)
13. [IAM: Roles and Permissions](#13-iam-roles-and-permissions)
14. [Trigger Catalog](#14-trigger-catalog)
15. [Function Catalog](#15-function-catalog)
16. [Views Reference](#16-views-reference)
17. [Key Business Flows (End-to-End)](#17-key-business-flows-end-to-end)
18. [Migration Execution Order](#18-migration-execution-order)

---

## 1. Architecture Overview

MLR is a textile dyeing/finishing service company. The database models:

- **Client rolls arrive** as raw fabric (crudo) → tracked as inventory lots (`inventario.lote`).
- **Production orders** (`mes.partida`) capture what the client wants processed (color, type, quantity) and drive the physical execution through a sequence of operations (dyeing, washing, drying, etc.).
- **Recipes** (`receta.tenido`, `receta.lavado_maquina`) define the chemical steps and ingredients for each operation.
- **Quality inspections** (`calidad.inspeccion`) are recorded per roll after each production step.
- **Inventory movements** (`inventario.item_movimientos`) record every stock change with full traceability. Stock balances are pre-computed in `lote_saldo` and `item_saldo` (trigger-maintained cache, see §3.7).
- **Commercial documents** (entregas, facturas, compras) record the paper trail for receiving, dispatching, and billing.

### High-Level Flow

```
CLIENT SENDS ROLLS
      │
      ▼
doc.entrega (CLIENTE_ENVIO_PROCESO)
      │  creates inventario.lote per roll
      ▼
mes.partida  ←── mes.partida_detalle (what to process: item × qty)
      │
      ├── mes.partida_paso  (sequence: TENIDO → LAVADO_HIDRO → SECADO…)
      │         │
      │         ▼
      │   mes.partida_paso_ejecucion  (actual execution run per paso)
      │         │
      │         ▼
      │   calidad.inspeccion  (QC per roll per paso)
      │
      └── mes.partida_componente  (roll + chemical reservations)

ROLLS DISPATCHED
      │
      ▼
doc.entrega (DESPACHO_CLIENTE) → doc.factura
```

---

## 2. Schemas

| Schema | Purpose |
|--------|---------|
| `public` | Master data shared across all modules (items, terceros, units, legacy tables) |
| `inventario` | Lot and movement tracking — the stock ledger |
| `doc` | Commercial documents: delivery notes, purchase orders, invoices |
| `mes` | Manufacturing Execution System: machines, operations, production orders, scheduling |
| `receta` | Dyeing and machine-wash recipes with chemical step details |
| `calidad` | Quality control inspections, defects, photos |
| `audit` | Immutable row-change audit trail |
| `iam` | Roles, permissions, and user-role assignments |

---

## 3. Global Design Patterns

### 3.1 `codigo` / `codigo_canon`

Every catalog/master table has:
- `codigo TEXT NOT NULL UNIQUE` — human-readable code, set by user or auto-generated.
- `codigo_canon TEXT NOT NULL UNIQUE` — derived by `fn_trg_set_codigo_canon()`: `lower(unaccent(codigo))`. Used for case-insensitive duplicate detection.

`codigo` is **immutable once set**. `fn_trg_immutable_codigo()` raises `'codigo is immutable'` on any UPDATE that changes it. To rename an entity, soft-delete it and create a new one.

### 3.2 Audit Columns

Present on every writable table:

| Column | Type | Set by |
|--------|------|--------|
| `usr_cre` | `INT` → `usuario.id` | `fn_trg_set_cre_fields()` BEFORE INSERT |
| `fyh_cre` | `TIMESTAMPTZ DEFAULT NOW()` | same |
| `usr_mod` | `INT` → `usuario.id` | `fn_trg_set_mod_fields()` BEFORE UPDATE |
| `fyh_mod` | `TIMESTAMPTZ` | same |

`get_user_id()` reads `id_usuario` from `auth.jwt()` — zero DB queries. Clients cannot override these columns; REVOKEs in step 9 strip column-level write access.

### 3.3 Soft Delete

Tables with these columns support soft delete:

| Column | Type | Set by |
|--------|------|--------|
| `flg_elm` | `BOOLEAN` | Application code |
| `usr_elm` | `INT` | `fn_trg_set_elm_fields()` BEFORE UPDATE |
| `fyh_elm` | `TIMESTAMPTZ` | same |

The trigger fires only when `flg_elm` transitions `false → true`, setting `usr_elm`/`fyh_elm` once. Hard deletes are blocked on `doc.entrega`, `inventario.lote`, `mes.partida`, and `doc.factura` (once emitted/annulled) by `fn_trg_prevent_hard_delete()`.

### 3.4 `doc_movimiento_id` — Posting Events

`inventario.item_movimientos.doc_movimiento_id BIGINT NOT NULL` groups all lines from one posting transaction (≡ SAP MBLNR). Generated from sequence `inventario.mov_doc_seq`.

### 3.5 `documento_tipo` / `documento_id` — Polymorphic Link

| `documento_tipo` | `documento_id` points to |
|-----------------|--------------------------|
| `'compra'` | `doc.compra.id` |
| `'PARTIDA'` | `mes.partida.id` |
| `'partida_paso_ejecucion'` | `mes.partida_paso_ejecucion.id` |
| `'cuadre'` | `inventario.cuadre.id` |
| `'LAVADO_MAQUINA'` | `mes.lavado_maquina.id` |

Used on both `inventario.lote` (what created this lot) and `inventario.item_movimientos` (what business event triggered the movement).

### 3.6 Auto-generated Codes

| Table | Trigger | Format |
|-------|---------|--------|
| `mes.maquina` | `fn_trg_gen_codigo_maquina()` | `{tipo}-001`, `{tipo}-002` |
| `inventario.ubicacion` | `fn_trg_gen_codigo_ubicacion()` | `INS-01`, `INS-02` |
| `color` | `fn_trg_gen_codigo_color()` | `ROJONEGRO` |
| `item` (rollo) | `fn_trg_gen_codigo_item_rollo()` | `R-RB-ART-2-T` |
| `item` (insumo) | `fn_trg_gen_codigo_item_insumo()` | `I-COL-DIR-AZUL-MARINO` |
| `inventario.lote` | `trfn_generar_secuencia_lote()` | `secuencia` = `YY-NNNNN` |

### 3.7 Saldo Cache Tables

Stock is logged to `item_movimientos` (append-only ledger) and simultaneously maintained in:

| Table | Key | Value |
|-------|-----|-------|
| `inventario.lote_saldo` | `(lote_id, ubicacion_id)` | `cantidad_actual NUMERIC(12,4)` |
| `inventario.item_saldo` | `(item_id, ubicacion_id)` | `cantidad_actual NUMERIC(12,4)` |

Both use `UNIQUE NULLS NOT DISTINCT` so that `ubicacion_id = NULL` (no specific location) is a valid distinct key. Updated by `trg_ai_im_sync_cantidad_actual` AFTER INSERT on `item_movimientos`. Never write to these tables directly. All stock views read from them.

**Three-path sync logic** (from `fn_trg_sync_cantidad_actual`):

| Condition | Effect |
|-----------|--------|
| `destino_ubicacion_id IS NOT NULL` | Credit: add `+cantidad` to `item_saldo(item_id, destino)` and `lote_saldo(lote_id, destino)` |
| `origen_ubicacion_id IS NOT NULL` | Debit: add `-cantidad` to `item_saldo(item_id, origen)` and `lote_saldo(lote_id, origen)` |
| Both NULL | Location-agnostic: use `item_movimiento_tipo.factor` to credit/debit `item_saldo(item_id, NULL)`. No `lote_saldo` update (no lot to reference). Used for fungible chemical consumption. |

Transfer movements (`both locations set`) fire both the destino and origen blocks in sequence. `lote_saldo` is only updated when `lote_id IS NOT NULL` on the movement row.

### 3.8 Generated Stored Columns

Financial and quantity totals are database-computed to eliminate rounding drift:

| Column | Formula |
|--------|---------|
| `item_movimientos.monto` | `cantidad * precio_unitario` |
| `factura_proveedor_detalle.subtotal_linea` | `ROUND(cantidad * precio_unitario, 2)` |
| `factura_proveedor_detalle.igv_linea` | `ROUND(cantidad * precio_unitario * igv_porcentaje / 100, 2)` |
| `factura_proveedor_detalle.total_linea` | `ROUND(cantidad * precio_unitario * (1 + igv_porcentaje/100), 2)` |
| `factura_detalle` has the same three generated columns | — |

These are `GENERATED ALWAYS AS (...) STORED` — they cannot be inserted or updated by clients.

### 3.9 Identity Column Variants

Most tables use `GENERATED ALWAYS AS IDENTITY` (cannot supply an ID manually). Exceptions that use `GENERATED BY DEFAULT AS IDENTITY` (manual ID allowed, required for data migration):
- `receta.tenido`
- `receta.lavado_maquina`

---

## 4. ENUM Types

All enums are defined in `migration/02_enums.sql`. They are also exposed to the frontend via `public.vw_enums` (see §15).

### Inventory

| Enum | Values (in order) |
|------|------------------|
| `calidad_estado_enum` | `PENDIENTE`, `APROBADO`, `REPROCESO`, `BAJA` |
| `item_movimiento_tipo_categoria_enum` | `COMPRA`, `VENTA`, `PRODUCCION`, `PROCESO_EXTERNO`, `DEVOLUCION`, `AJUSTE`, `TRANSFERENCIA` |

**calidad_estado_enum notes:**
- `PENDIENTE` — not yet inspected (initial state)
- `APROBADO` — passed QC; terminal
- `REPROCESO` — failed, material must be reprocessed via `crear_reproceso()`; terminal
- `BAJA` — condemned; written off via `dar_de_baja_lote()`; terminal

### Manufacturing

| Enum | Values (in order) |
|------|------------------|
| `partida_estado_produccion_enum` | `CREADA`, `PLANIFICADA`, `PROGRAMADA`, `EN_PRODUCCION`, `TECO`, `CERRADA`, `CANCELADA` |
| `partida_estado_comercial_enum` | `PENDIENTE`, `ENTREGA_PARCIAL`, `ENTREGADA`, `DEVUELTA_PARCIAL`, `DEVUELTA_TOTAL` |
| `partida_paso_estado_enum` | `PENDIENTE`, `EN_PROCESO`, `COMPLETADO`, `OMITIDO` |
| `paso_ejecucion_estado_enum` | `EN_PROCESO`, `COMPLETADO`, `OMITIDO` |
| `partida_tipo_enum` | `NORMAL`, `REPROCESO` (defined but not currently used on any table) |
| `maquina_estado_enum` | `activa`, `espera`, `configuracion`, `averia`, `mantenimiento` |

**paso_ejecucion_estado_enum** has no `PENDIENTE` because a `partida_paso_ejecucion` row only exists once the step has started.

**partida_paso_estado_enum** is used by `mes.lavado_maquina.estado` (needs `PENDIENTE` for scheduled but not yet started washes). Production steps (`partida_paso`) derive their state from the presence/state of ejecucion rows — they have no `estado` column.

### Procurement

| Enum | Values |
|------|--------|
| `tipo_pago_enum` | `al contado`, `credito` |
| `estado_pago_enum` | `pendiente`, `parcial`, `total`, `anulado` |
| `letra_estado_enum` | `emitida`, `pagada`, `vencida`, `protestada`, `anulada` |

### Billing

| Enum | Values |
|------|--------|
| `factura_estado_enum` | `borrador`, `emitida`, `anulada` |
| `partida_facturacion_enum` | `pendiente`, `parcial`, `facturado` |

**medida_enum** — `g_L`, `g_kg`, `mL_L`, `mL_kg`, `%` — used by `item_insumo_detalle.medida`. May exist as a legacy type from a prior migration.

---

## 5. Schema: `public` — Master Data

### 5.1 `unidad` — Unit of Measure

```
id          INT GENERATED ALWAYS AS IDENTITY PK
codigo      TEXT NOT NULL UNIQUE
codigo_canon TEXT NOT NULL UNIQUE
nombre      TEXT NOT NULL
usr_cre, fyh_cre, usr_mod, fyh_mod
```
Pre-seeded: `kg`, `g`, `mg`, `ton`, `L`, `mL`, `UN`.

### 5.2 `unidad_conversion` — Conversion Factors

```
de_unidad_id  INT FK→unidad   )
a_unidad_id   INT FK→unidad   ) PK together
factor        NUMERIC(18,6) NOT NULL
```
Used when scaling recipe ingredient quantities across measurement systems.

### 5.3 `item_tipo`, `insumo_tipo`, `colorante_tipo` — Classifiers

All three follow the same pattern: `id SMALLINT IDENTITY PK`, `codigo`, `codigo_canon`, `nombre`. Seeded values:

| Table | Values |
|-------|--------|
| `item_tipo` | `ROLLO`, `INSUMO` |
| `insumo_tipo` | `QUIM`, `COL`, `AUX` |
| `colorante_tipo` | `DIR`, `DISP`, `RX` |

**`item_tipo.ubicacion_default_id`** — `INT FK→inventario.ubicacion`, added in migration 19. Optional preferred warehouse bin for fungible consumption postings when no explicit location is provided. NULL = movement posts to the location-agnostic `item_saldo(item_id, NULL)` bucket.

### 5.4 `item` — Universal Product Catalog

```
id            INT GENERATED ALWAYS AS IDENTITY PK
codigo        TEXT NOT NULL UNIQUE        -- immutable
codigo_canon  TEXT NOT NULL UNIQUE
nombre        TEXT NOT NULL
item_tipo_id  INT NOT NULL FK→item_tipo
unidad_id     INT NOT NULL FK→unidad
stock_minimo  NUMERIC(12,4)               -- reorder alert threshold; nullable
flg_fungible  BOOLEAN NOT NULL DEFAULT false  -- added migration 19
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
```

**`flg_fungible`** — when `true`, the item can be consumed without a `lote_id` on the movement row, and stock can go negative. All INSUMO items are seeded with `flg_fungible = true` (migration 19). ROLLOs remain `false` (each roll is physically tracked by lot).

`codigo` is auto-generated by AFTER INSERT triggers on the detalle tables — do not set it manually. The `item` row is created first with a placeholder `codigo`, then the trigger on the detalle fires to set the real one.

### 5.5 `item_rollo_detalle` — Fabric Roll Extension (1:1 with ROLLO items)

```
item_id       INT PK FK→item
articulo_id   INT NOT NULL FK→articulo
flg_rib       BOOLEAN NOT NULL DEFAULT false
usr_cre, fyh_cre, usr_mod, fyh_mod
```

### 5.6 `item_insumo_detalle` — Chemical Supply Extension (1:1 with INSUMO items)

```
item_id           INT PK FK→item
medida            medida_enum NOT NULL       -- dose unit
insumo_tipo_id    SMALLINT NOT NULL FK→insumo_tipo
colorante_tipo_id SMALLINT FK→colorante_tipo -- NULL if not a dye
factor_stock      NUMERIC(8,6) NOT NULL DEFAULT 1
usr_cre, fyh_cre, usr_mod, fyh_mod
```

### 5.7 `tercero` — Trading Parties

```
id            INT GENERATED ALWAYS AS IDENTITY PK
codigo        TEXT NOT NULL UNIQUE            -- immutable
codigo_canon  TEXT NOT NULL UNIQUE
nombre        TEXT NOT NULL                   -- commercial name
razon_social  TEXT                            -- legal name (SUNAT)
ruc           TEXT UNIQUE                     -- 11-digit Peruvian tax ID
direccion     TEXT
telefono      TEXT
correo        TEXT
procedencia   TEXT
flg_cliente   BOOLEAN NOT NULL DEFAULT false
flg_proveedor BOOLEAN NOT NULL DEFAULT false
cliente_id    INT FK→cliente                  -- legacy cross-ref
cliente_id2   INT FK→cliente
proveedor_id  INT FK→proveedor
usr_cre INT FK→usuario, fyh_cre, usr_mod INT FK→usuario, fyh_mod, usr_elm, fyh_elm
```

Row `id = 1` is always MLR itself (Manufacturas la Real). A `tercero` can be both client and supplier simultaneously (`flg_cliente = true AND flg_proveedor = true`).

### 5.8 `articulo` and `articulo_tipo` — Fabric Types

`articulo_tipo` (knit structure families: Jersey, Rib, Interlock…): `id SMALLINT IDENTITY PK`, `nombre`, `codigo`, `codigo_canon`.

`articulo` (specific fabric variants):
```
id               INT PK
nombre           TEXT NOT NULL
articulo_tipo_id SMALLINT NOT NULL FK→articulo_tipo
codigo           TEXT UNIQUE
codigo_canon     TEXT UNIQUE
fibra            SMALLINT      -- 1 (cotton), 2 (polyester)…
```

### 5.9 `color` and `color_x_cliente`

`color` — master color catalog with `hex` (HTML color code).

`color_x_cliente` — client-specific color mapping: `(cliente_id, color_id, valor_id, hex, tercero_id)`. Each client can have their own name/shade for a color. This is the FK used throughout production and recipes.

### 5.10 `doc.catalogo_precios` — Billing Price Catalog

```
id                 BIGINT IDENTITY PK
operacion_id       SMALLINT NOT NULL FK→mes.operacion
color_x_cliente_id INT FK→color_x_cliente    -- NULL when pricing by tercero
tercero_id         INT FK→tercero             -- NULL when pricing by color
articulo_tipo_id   SMALLINT FK→articulo_tipo
tenido_id          INT FK→tenido
fibra              SMALLINT
flg_antipilling    BOOLEAN
precio_kg          NUMERIC(10,4) NOT NULL CHECK (precio_kg >= 0)
costo_kg           NUMERIC(10,4) CHECK (costo_kg IS NULL OR costo_kg >= 0)
usr_cre, fyh_cre, usr_elm, fyh_elm
CONSTRAINT chk_precio_client_dim
    CHECK (color_x_cliente_id IS NULL OR tercero_id IS NULL)
```

Lookup table for billing rates. Either `color_x_cliente_id` or `tercero_id` is specified, not both (`chk_precio_client_dim`). Used by `crear_factura()` to pre-fill invoice line prices.

---

## 6. Schema: `inventario` — Inventory

### 6.1 `almacen` and `ubicacion` — Location Hierarchy

**`almacen`** — warehouse:
```
id           INT IDENTITY PK
codigo       TEXT NOT NULL UNIQUE   -- convention: ALM_XXX; immutable
codigo_canon TEXT NOT NULL UNIQUE
nombre       TEXT NOT NULL
usr_cre, fyh_cre, usr_mod, fyh_mod
```

**`ubicacion`** — bin/location within a warehouse:
```
id           INT IDENTITY PK
almacen_id   INT NOT NULL FK→almacen
codigo       TEXT NOT NULL         -- auto-generated: XXX-01, XXX-02…
codigo_canon TEXT NOT NULL
nombre       TEXT NOT NULL
usr_cre, fyh_cre, usr_mod, fyh_mod
UNIQUE (almacen_id, codigo_canon)
```

### 6.2 `lote` — Stock Lot

```
id             INT GENERATED ALWAYS AS IDENTITY PK
secuencia      INT NOT NULL              -- annual number; set by trigger
item_id        INT NOT NULL FK→item
documento_tipo TEXT                      -- polymorphic: who created this lot
documento_id   BIGINT
cantidad       NUMERIC(10,4) CHECK (cantidad > 0)
detalles       JSONB                     -- ad-hoc attributes
estado_calidad calidad_estado_enum DEFAULT 'PENDIENTE'
propietario_id INT FK→tercero            -- client ownership
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
```

`secuencia` is set by `trfn_generar_secuencia_lote()` on BEFORE INSERT, drawing from `lote_secuencia_anual`. The human-visible lot code is `{YY}-{secuencia:05}` (e.g. `26-00042`), computed in views.

### 6.3 `lote_secuencia_anual` — Annual Counter

```
ano          INT PK
ultimo_valor INT NOT NULL DEFAULT 0
```
One row per year. Incremented by the `BEFORE INSERT` trigger on `lote`.

### 6.4 `lote_rollo_detalle` — Roll Lot Attributes

```
lote_id            INT PK FK→lote
entrega_id   BIGINT FK→doc.entrega  -- billing anchor
origen_lote_id     INT FK→lote                  -- for output lots from production
ancho              TEXT
malla              TEXT
rendimiento        TEXT
color_x_cliente_id INT FK→color_x_cliente        -- set by registrar_produccion()
tenido_id          INT FK→tenido
flg_tenido         BOOLEAN NOT NULL DEFAULT false
flg_antipilling    BOOLEAN NOT NULL DEFAULT false
usr_cre, fyh_cre, usr_mod, fyh_mod
```

Created at ingress (for inbound raw rolls, set `entrega_id`). Updated by `registrar_produccion()` on production output lots (sets `flg_tenido`, `color_x_cliente_id`, `tenido_id`, `flg_antipilling`, `origen_lote_id`).

### 6.5 `lote_saldo` and `item_saldo` — Balance Cache

```
-- lote_saldo
lote_id         INT NOT NULL FK→lote
ubicacion_id    INT FK→ubicacion          -- nullable (no location = global)
cantidad_actual NUMERIC(12,4) NOT NULL DEFAULT 0
UNIQUE NULLS NOT DISTINCT (lote_id, ubicacion_id)

-- item_saldo
item_id         INT NOT NULL FK→item
ubicacion_id    INT FK→ubicacion
cantidad_actual NUMERIC(12,4) NOT NULL DEFAULT 0
UNIQUE NULLS NOT DISTINCT (item_id, ubicacion_id)
```

Never written directly — maintained by `trg_ai_im_sync_cantidad_actual` AFTER INSERT on `item_movimientos`. A movement with `destino_ubicacion_id IS NOT NULL` increases the destination balance; `origen_ubicacion_id IS NOT NULL` decreases the origin balance. A pure ingress (only `destino` set) increases stock; pure egress (only `origen` set) decreases it.

### 6.6 `item_movimiento_tipo` — Movement Type Catalog

```
id                  SMALLINT IDENTITY PK
codigo              TEXT NOT NULL UNIQUE
codigo_canon        TEXT NOT NULL UNIQUE
nombre              TEXT NOT NULL
categoria           item_movimiento_tipo_categoria_enum NOT NULL
factor              SMALLINT NOT NULL CHECK (factor IN (1, -1, 0))
descripcion         TEXT
flg_afecta_stock    BOOLEAN NOT NULL DEFAULT true
flg_valorizable     BOOLEAN NOT NULL DEFAULT true
flg_recalcula_costo BOOLEAN NOT NULL DEFAULT false
req_partner         BOOLEAN NOT NULL DEFAULT false
req_origen          BOOLEAN NOT NULL DEFAULT false
req_destino         BOOLEAN NOT NULL DEFAULT false
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
```

`factor` is now semantically informational — actual direction is inferred from `origen_ubicacion_id` / `destino_ubicacion_id` presence in `item_movimientos`. The `flg_*` flags control trigger behavior (MAP update, stock update). Key codes:

**Additional columns added in migration 19:**
- `reversal_tipo_id SMALLINT FK→item_movimiento_tipo` — explicit reversal pairing (≈ SAP XRUEM). E.g. `PROD_CONSUMO.reversal_tipo_id → PROD_CONSUMO_REV`. Used by `anular_ejecucion()` to know which movement type to post when reversing.

| Code | Categoria | `flg_recalcula_costo` | Meaning |
|------|-----------|----------------------|---------|
| `COMPRA_ING` | COMPRA | true | Purchase receipt; recalculates MAP |
| `SERV_ING` | PROCESO_EXTERNO | false | Client material received |
| `SERV_EGR` | PROCESO_EXTERNO | false | Processed material dispatched |
| `PROD_CONSUMO` | PRODUCCION | false | Roll consumed into dyeing |
| `PROD_ING` | PRODUCCION | false | Dyed roll enters stock |
| `PROD_CONSUMO_REV` | PRODUCCION | false | Reversal of PROD_CONSUMO |
| `PROD_ING_REV` | PRODUCCION | false | Reversal of PROD_ING |
| `PROD_SCRAP` | PRODUCCION | false | Roll condemned mid-execution |
| `AJUSTE_POS` | AJUSTE | false | Surplus from physical count |
| `AJUSTE_NEG` | AJUSTE | false | Deficit from physical count |
| `MUESTRA_ING` / `MUESTRA_EGR` | AJUSTE | false | Non-valorizable samples |
| `INT_TRANSFER_ING` / `INT_TRANSFER_EGR` | TRANSFERENCIA | false | Location transfers |

### 6.7 `item_movimiento_motivo` — Movement Reason Codes

```
id                      SMALLINT IDENTITY PK
item_movimiento_tipo_id SMALLINT NOT NULL FK→item_movimiento_tipo
codigo                  TEXT NOT NULL
nombre                  TEXT NOT NULL
UNIQUE (item_movimiento_tipo_id, codigo)
```
Sub-codes per movement type (e.g. `MATIZADO`, `LAVADO_MAQUINA`, `CONFECCION`, `SOBRANTE_FISICO`). Optional on each movement line.

### 6.8 `item_movimientos` — The Stock Ledger

```
id                       BIGINT IDENTITY PK
doc_movimiento_id        BIGINT NOT NULL              -- posting event ID
item_id                  INT NOT NULL FK→item
lote_id                  INT FK→lote                  -- nullable for item-level moves
item_movimiento_tipo_id  SMALLINT NOT NULL FK→item_movimiento_tipo
origen_ubicacion_id      INT FK→ubicacion             -- NULL = pure ingress
destino_ubicacion_id     INT FK→ubicacion             -- NULL = pure egress
cantidad                 NUMERIC(12,4) NOT NULL CHECK (cantidad > 0)
precio_unitario          NUMERIC(12,4)                -- NULL for non-valorizable
monto                    NUMERIC(16,4) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED
fecha_hora               TIMESTAMPTZ NOT NULL DEFAULT now()
documento_tipo           TEXT                         -- polymorphic
documento_id             INT
motivo_id                SMALLINT FK→item_movimiento_motivo
observacion              TEXT
usr_cre                  INT
fyh_cre                  TIMESTAMPTZ DEFAULT NOW()
```

**Append-only.** Never update or delete rows. The cutoff trigger (`fn_trg_check_corte_cuadre`) fires BEFORE INSERT/UPDATE and raises an exception if `fecha_hora` is before the last executed cuadre's `fecha_cuadre`.

### 6.9 `item_valoracion` — Moving Average Price (MAP)

```
item_id         INT PK FK→item
precio_promedio NUMERIC(12,4) NOT NULL DEFAULT 0
stock_qty       NUMERIC(12,4) NOT NULL DEFAULT 0
stock_valorado  NUMERIC(16,4) NOT NULL DEFAULT 0
fyh_mod         TIMESTAMPTZ DEFAULT now()
```

Maintained by `trg_ai_item_movimientos_map` AFTER INSERT on `item_movimientos`:
- `flg_recalcula_costo = true` → new MAP = `(current_stock_value + new_qty × price) / (current_qty + new_qty)`
- `flg_valorizable = true`, recalcula = false → qty/value adjusted at existing MAP
- `flg_valorizable = false` → no change to valoracion

### 6.10 `pesaje` — Weighing Gate

```
id          INT IDENTITY PK
lote_id     INT NOT NULL FK→lote
tipo        TEXT NOT NULL CHECK (tipo IN ('INGRESO', 'SALIDA', 'CORRECCION'))
peso_real   NUMERIC(12,4)
observacion TEXT
usr_cre     INT
fyh_cre     TIMESTAMPTZ DEFAULT NOW()
```

A roll must have a `pesaje` record before it can be consumed in production. `vw_pesaje_pendiente` surfaces partidas where this gate is uncleared.

### 6.11 `cuadre` and `cuadre_detalle` — Inventory Reconciliation

**`cuadre`**:
```
id           BIGINT IDENTITY PK
fecha_cuadre TIMESTAMPTZ NOT NULL DEFAULT now()  -- cutoff timestamp
fecha_cierre TIMESTAMPTZ                          -- set when ejecutado
estado       inventario.cuadre_estado_enum NOT NULL DEFAULT 'borrador'
usr_cre INT FK→usuario, fyh_cre, usr_mod INT FK→usuario, fyh_mod
```
States: `borrador → preparado → ejecutado | cancelado`.

**`cuadre_detalle`**:
```
id                      BIGINT IDENTITY PK
cuadre_id               BIGINT NOT NULL FK→cuadre
item_id                 INT NOT NULL FK→item
cantidad_sistema        NUMERIC(12,4)    -- snapshot at cuadre creation
precio_promedio_sistema NUMERIC(12,6)
stock_valorado_sistema  NUMERIC(14,4)
ult_precio_compra       NUMERIC(12,4)
cantidad_contada        NUMERIC(12,4)    -- operator-entered physical count
usr_mod INT FK→usuario, fyh_mod
UNIQUE (cuadre_id, item_id)
```

Once `ejecutado`, `fn_trg_check_corte_cuadre()` blocks all movements with timestamps before `fecha_cuadre`. This makes cuadre cutoff permanent and prevents retroactive postings from corrupting the reconciled baseline.

---

## 7. Schema: `doc` — Commercial Documents

### 7.1 `entrega_tipo` — Delivery Note Type Catalog

```
id                      SMALLINT IDENTITY PK
codigo                  TEXT NOT NULL UNIQUE
codigo_canon            TEXT NOT NULL UNIQUE
nombre                  TEXT
flg_emitida             BOOLEAN NOT NULL  -- true=we issue, false=we receive
flg_cliente             BOOLEAN
item_movimiento_tipo_id SMALLINT FK→inventario.item_movimiento_tipo
usr_cre, fyh_cre, usr_mod, fyh_mod
```

| Code | `flg_emitida` | Linked movement type |
|------|--------------|---------------------|
| `COMPRA_INGRESO` | false | `COMPRA_ING` |
| `CLIENTE_ENVIO_PROCESO` | false | `SERV_ING` |
| `DESPACHO_CLIENTE` | true | `SERV_EGR` |
| `VENTA_EGRESO` | true | `VENTA_EGR` |
| `DEVOLUCION_CLIENTE_CRUDO` | true | `DEV_CLI_EGR` |
| `DEVOLUCION_PROVEEDOR` | true | `DEV_PROV_EGR` |
| `DEVOLUCION_CLIENTE_VENTA` | false | `DEV_CLI_ING` |
| `DEVOLUCION_CLIENTE_SERVICIO` | false | `SERV_DEV_ING` |

### 7.2 `entrega` and `entrega_detalle`

**`entrega`**:
```
id                    BIGINT IDENTITY PK
entrega_tipo_id SMALLINT NOT NULL FK→entrega_tipo
tercero_id            INT NOT NULL FK→tercero
serie                 TEXT NOT NULL
correlativo           TEXT NOT NULL
fecha_emision         TIMESTAMPTZ NOT NULL
fecha_recepcion       TIMESTAMPTZ DEFAULT now()
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
UNIQUE (tercero_id, serie, correlativo, entrega_tipo_id)
```
Hard delete blocked. Soft delete is the only way to void a entrega.

**`entrega_detalle`**:
```
id               BIGINT IDENTITY PK
entrega_id BIGINT NOT NULL FK→entrega
item_id          INT NOT NULL FK→item
lote_id          INT FK→lote
ubicacion_id     INT FK→ubicacion
cantidad         NUMERIC(12,4) NOT NULL CHECK (cantidad > 0)
UNIQUE (entrega_id, item_id, lote_id, ubicacion_id)
```

### 7.3 `compra`, `compra_detalle`, `compra_entrega`

**`compra`**:
```
id         BIGINT IDENTITY PK
tercero_id INT NOT NULL FK→tercero   -- supplier
fecha      DATE NOT NULL DEFAULT CURRENT_DATE
observacion TEXT
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
```

**`compra_detalle`**:
```
id              BIGINT IDENTITY PK
compra_id       BIGINT NOT NULL FK→compra
item_id         INT NOT NULL FK→item
cantidad        NUMERIC(12,4) NOT NULL CHECK (cantidad > 0)
precio_unitario NUMERIC(12,4) NOT NULL CHECK (precio_unitario >= 0)
```

**`compra_entrega`** — junction (M:M between compra and entrega):
```
compra_id        BIGINT NOT NULL FK→compra
entrega_id BIGINT NOT NULL FK→entrega
PRIMARY KEY (compra_id, entrega_id)
```

**`compra_factura_proveedor`** — junction (M:M between compra and factura_proveedor):
```
compra_id            BIGINT NOT NULL FK→compra
factura_proveedor_id BIGINT NOT NULL FK→factura_proveedor
PRIMARY KEY (compra_id, factura_proveedor_id)
```

### 7.4 `factura_proveedor` and `factura_proveedor_detalle`

**`factura_proveedor`**:
```
id               BIGINT IDENTITY PK
tercero_id       INT NOT NULL FK→tercero
serie            TEXT NOT NULL
numero           INT NOT NULL
fecha_emision    DATE NOT NULL
fecha_vencimiento DATE
tipo_pago        tipo_pago_enum NOT NULL DEFAULT 'al contado'
moneda           CHAR(3) NOT NULL DEFAULT 'USD'
tipo_cambio      NUMERIC(10,4)         -- required when moneda = 'USD'
subtotal         NUMERIC(12,2) NOT NULL DEFAULT 0
igv              NUMERIC(12,2) NOT NULL DEFAULT 0
total            NUMERIC(12,2) NOT NULL DEFAULT 0
estado_pago      estado_pago_enum NOT NULL DEFAULT 'pendiente'
observacion      TEXT
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
UNIQUE (tercero_id, serie, numero)
CONSTRAINT chk_factura_montos
    CHECK (subtotal > 0 AND igv >= 0 AND total > 0
           AND ABS(total - (subtotal + igv)) < 0.01)
```
The `chk_factura_montos` constraint enforces that `total = subtotal + igv` to within 1 cent and that amounts are positive.

**`factura_proveedor_detalle`**:
```
id                   BIGINT IDENTITY PK
factura_proveedor_id BIGINT NOT NULL FK→factura_proveedor
item_id              INT NOT NULL FK→item
cantidad             NUMERIC(12,4) NOT NULL CHECK (cantidad > 0)
precio_unitario      NUMERIC(12,4) NOT NULL CHECK (precio_unitario >= 0)
igv_porcentaje       NUMERIC(5,2) NOT NULL DEFAULT 18
                         CHECK (igv_porcentaje IN (0, 18))
subtotal_linea       NUMERIC(12,2) GENERATED ALWAYS AS (ROUND(cantidad * precio_unitario, 2)) STORED
igv_linea            NUMERIC(12,2) GENERATED ALWAYS AS (...) STORED
total_linea          NUMERIC(12,2) GENERATED ALWAYS AS (...) STORED
```
Detail lines are optional (header-only invoices are valid). Their existence is checked by `vw_compras_item_mes` to decide which cost source to use.

### 7.5 `letra` and `letra_factura` — Payment Letters

**`letra`** (letra de cambio / promissory note):
```
id                BIGINT IDENTITY PK
tercero_id        INT NOT NULL FK→tercero
numero            TEXT                          -- document number (nullable)
monto             NUMERIC(12,2) NOT NULL CHECK (monto > 0)
fecha_giro        DATE                          -- draw date (nullable)
fecha_vencimiento DATE NOT NULL                 -- due date
banco             TEXT                          -- collecting bank
estado            letra_estado_enum NOT NULL DEFAULT 'emitida'
fecha_pago        DATE                          -- set by pagar_letra()
observacion       TEXT
usr_cre, fyh_cre, usr_mod, fyh_mod
```

**`letra_factura`** — applies a letra to one or more invoices:
```
id                   BIGINT IDENTITY PK
letra_id             BIGINT NOT NULL FK→letra
factura_proveedor_id BIGINT NOT NULL FK→factura_proveedor
monto_aplicado       NUMERIC(12,2) NOT NULL CHECK (monto_aplicado > 0)
UNIQUE (letra_id, factura_proveedor_id)
```
`registrar_letras()` validates that `SUM(monto_aplicado)` across all active letras on a factura does not exceed `factura.total`.

### 7.6 `factura` and `factura_detalle` — Customer Invoices

**`factura`**:
```
id                BIGINT IDENTITY PK
tipo_comprobante  CHAR(2) NOT NULL DEFAULT '01'
                      CHECK (tipo_comprobante IN ('01','03','07','08'))
serie             TEXT NOT NULL
numero            INT NOT NULL
tercero_id        INT NOT NULL FK→tercero
fecha_emision     DATE NOT NULL DEFAULT CURRENT_DATE
fecha_vencimiento DATE
moneda            CHAR(3) NOT NULL DEFAULT 'USD'
tipo_cambio       NUMERIC(10,4)
subtotal          NUMERIC(12,2) NOT NULL DEFAULT 0
igv               NUMERIC(12,2) NOT NULL DEFAULT 0
total             NUMERIC(12,2) NOT NULL DEFAULT 0
estado            factura_estado_enum NOT NULL DEFAULT 'borrador'
factura_origen_id BIGINT FK→factura     -- for notas de crédito/débito
observacion       TEXT
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
UNIQUE (serie, numero)
CONSTRAINT chk_factura_montos
    CHECK (subtotal >= 0 AND igv >= 0 AND total >= 0
           AND ABS(total - (subtotal + igv)) < 0.01)
CONSTRAINT chk_nota_requiere_origen
    CHECK (tipo_comprobante NOT IN ('07','08') OR factura_origen_id IS NOT NULL)
```

`tipo_comprobante` codes: `01` = Factura, `03` = Boleta, `07` = Nota de Crédito, `08` = Nota de Débito. Notas (`07`, `08`) must reference an original invoice via `factura_origen_id`.

Hard delete is blocked once `estado != 'borrador'`.

**`factura_detalle`**:
```
id                  BIGINT IDENTITY PK
factura_id          BIGINT NOT NULL FK→factura
partida_id          BIGINT FK→mes.partida
entrega_id    BIGINT FK→doc.entrega
operacion_id        SMALLINT FK→mes.operacion
es_antipilling      BOOLEAN NOT NULL DEFAULT false
articulo_tipo_id    SMALLINT FK→articulo_tipo
color_x_cliente_id  INT FK→color_x_cliente
tenido_id           INT FK→tenido
descripcion         TEXT NOT NULL
cantidad            NUMERIC(12,4) NOT NULL CHECK (cantidad > 0)
unidad_id           INT NOT NULL FK→unidad
precio_unitario     NUMERIC(12,4) NOT NULL CHECK (precio_unitario >= 0)
igv_porcentaje      NUMERIC(5,2) NOT NULL DEFAULT 18 CHECK (igv_porcentaje IN (0, 18))
subtotal_linea      NUMERIC(12,2) GENERATED ALWAYS AS (...) STORED
igv_linea           NUMERIC(12,2) GENERATED ALWAYS AS (...) STORED
total_linea         NUMERIC(12,2) GENERATED ALWAYS AS (...) STORED
```
`partida_id` links billing back to the production order for `actualizar_estado_facturacion_partida()`.

---

## 8. Schema: `mes` — Manufacturing Execution

### 8.1 `operacion` — Macro Process Steps

```
id              SMALLINT IDENTITY PK
codigo          TEXT NOT NULL UNIQUE
codigo_canon    TEXT NOT NULL UNIQUE
nombre          TEXT NOT NULL UNIQUE
requiere_receta BOOLEAN DEFAULT false
requiere_maquina BOOLEAN DEFAULT true
usr_cre, fyh_cre, usr_mod, fyh_mod
```

Pre-seeded: `TERMOFIJADO`, `TENIDO`, `LAVADO_HIDRO`, `SECADO`, `PLANCHADO`, `PERCHADO`, `COMPACTADO`, `VOLTEADO`. Not the same as `receta.operacion` (chemistry micro-steps).

### 8.2 `maquina_tipo` and `maquina`

**`maquina_tipo`**:
```
id            SMALLINT IDENTITY PK
codigo        TEXT NOT NULL UNIQUE
codigo_canon  TEXT NOT NULL UNIQUE
nombre        TEXT UNIQUE
operacion_id  SMALLINT FK→mes.operacion   -- added in migration 17
usr_cre, fyh_cre, usr_mod, fyh_mod
```
`operacion_id` links a machine type to the production operation it performs.

**`maquina`**:
```
id               INT IDENTITY PK
codigo           TEXT NOT NULL UNIQUE     -- auto-gen: {tipo}-001
codigo_canon     TEXT NOT NULL UNIQUE
nombre           TEXT NOT NULL
maquina_tipo_id  SMALLINT FK→maquina_tipo
estado_actual    maquina_estado_enum NOT NULL DEFAULT 'espera'
ultimo_mantenimiento TIMESTAMPTZ
horas_totales    INT
capacidad_min_kg INT NOT NULL CHECK (capacidad_min_kg > 0)
capacidad_max_kg INT NOT NULL CHECK (capacidad_max_kg >= capacidad_min_kg)
relacion_bano    NUMERIC(5,2)
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
```

### 8.3 `empleado_rol` and `empleado`

**`empleado_rol`**: `id SMALLINT IDENTITY PK`, `codigo`, `codigo_canon`, `nombre`, `descripcion`.

**`empleado`**:
```
id         SMALLINT IDENTITY PK
nombre     TEXT
apellido   TEXT
rol_id     SMALLINT NOT NULL FK→empleado_rol
turno_id   SMALLINT FK→turno
activo     BOOLEAN NOT NULL DEFAULT true
perfil_id  INT FK→usuario               -- auth link (nullable)
usr_cre, fyh_cre, usr_mod, fyh_mod
```

### 8.4 `ruta_plantilla` and `ruta_plantilla_detalle`

Reusable route templates:
```
-- ruta_plantilla_detalle
ruta_plantilla_id INT NOT NULL FK→ruta_plantilla
operacion_id      SMALLINT NOT NULL FK→operacion
secuencia         SMALLINT NOT NULL
ph                NUMERIC(4,2)
temperatura       NUMERIC(5,2)
tiempo_estandar   INT
UNIQUE (ruta_plantilla_id, secuencia)
```

### 8.5 `partida` — Production Order

```
id                  BIGINT IDENTITY PK
numero              INT GENERATED BY DEFAULT AS IDENTITY  -- human order number
partida_origen_id   BIGINT FK→partida (self)             -- rework parent
prioridad_id        INT FK→prioridad
tercero_id          INT NOT NULL FK→tercero
tenido_id           INT NOT NULL FK→tenido
color_x_cliente_id  INT NOT NULL FK→color_x_cliente
articulo_tipo_id    SMALLINT NOT NULL FK→articulo_tipo
fibra               SMALLINT NOT NULL
malla               TEXT
rendimiento         TEXT
ancho               TEXT
flg_antipilling     BOOLEAN NOT NULL DEFAULT false
fecha_acordada      DATE
observacion         TEXT
estado_produccion   partida_estado_produccion_enum NOT NULL DEFAULT 'CREADA'
estado_comercial    partida_estado_comercial_enum NOT NULL DEFAULT 'PENDIENTE'
estado_facturacion  partida_facturacion_enum NOT NULL DEFAULT 'pendiente'
CONSTRAINT chk_rework_comercial_locked
    CHECK (partida_origen_id IS NULL OR estado_comercial = 'PENDIENTE')
fyh_programacion    TIMESTAMPTZ
fyh_inicio          TIMESTAMPTZ
fyh_fin             TIMESTAMPTZ
usr_cre, fyh_cre, usr_mod, fyh_mod, usr_elm, fyh_elm
```

**Production state machine:**
```
CREADA
  │  (add partida_paso rows)
  ▼
PLANIFICADA
  │  (add programacion rows)
  ▼
PROGRAMADA
  │  (first partida_paso_ejecucion created)
  ▼
EN_PRODUCCION
  │  (all pasos COMPLETADO or OMITIDO)
  ▼
TECO  ─── (close after commercial + billing settlement) ──► CERRADA
  │
  └── CANCELADA (any time before CERRADA)
```

`fyh_programacion` / `fyh_inicio` / `fyh_fin` are set by `actualizar_estado_partida()` when the state transitions to PROGRAMADA, EN_PRODUCCION, and TECO/CERRADA respectively.

**`partida_detalle`**:
```
id                 BIGINT IDENTITY PK
partida_id         BIGINT NOT NULL FK→partida
item_id            INT NOT NULL FK→item
cantidad           NUMERIC(12,2) NOT NULL CHECK (cantidad > 0)   -- roll count target
cantidad_producida NUMERIC(12,2) NOT NULL DEFAULT 0
unidad_id          INT NOT NULL FK→unidad
usr_cre, fyh_cre, usr_mod, fyh_mod
UNIQUE (partida_id, item_id)
```

### 8.6 `partida_paso` — Planned Route Step

```
id                     BIGINT IDENTITY PK
partida_id             BIGINT NOT NULL FK→partida
secuencia              SMALLINT NOT NULL
operacion_id           SMALLINT NOT NULL FK→operacion
maquina_planificada_id INT FK→maquina           -- planning intent
receta_id              INT FK→receta.tenido     -- required when requiere_receta=true
tiempo_estandar        INT                      -- minutes
ph_objetivo            NUMERIC(4,2)
temperatura_objetivo   NUMERIC(5,2)
relacion_bano_objetivo NUMERIC(5,2)
usr_cre, fyh_cre, usr_mod, fyh_mod
UNIQUE (partida_id, secuencia)
```

**`estado partida_paso_estado_enum NOT NULL DEFAULT 'PENDIENTE'`** was added as a stored column in migration 19. Execution functions (`crear_ejecucion`, `finalizar_ejecucion`) keep it in sync. States: `PENDIENTE → EN_PROCESO → COMPLETADO | OMITIDO`. The `vw_pasos` view includes a redundant CASE derivation as a fallback for rows that pre-date the migration.

### 8.7 `partida_paso_ejecucion` — Execution Run

```
id               BIGINT IDENTITY PK
partida_paso_id  BIGINT NOT NULL FK→partida_paso
estado           paso_ejecucion_estado_enum NOT NULL DEFAULT 'EN_PROCESO'
maquina_id       INT FK→maquina
empleado_id      SMALLINT FK→empleado
fyh_inicio       TIMESTAMPTZ NOT NULL DEFAULT now()  -- set on creation
fyh_fin          TIMESTAMPTZ                          -- set on COMPLETADO/OMITIDO
ph_real          NUMERIC(4,2)
temperatura_real NUMERIC(5,2)
relacion_bano_real NUMERIC(5,2)
cantidad         NUMERIC(12,4)          -- actual batch weight
cantidad_scrap   NUMERIC(12,4)          -- weight condemned mid-run
notas            TEXT
receta_id        INT FK→receta.tenido   -- snapshot of paso.receta_id at iniciar time; immutable
-- Finishing operation measurements (added migration 18)
ancho_entrada    NUMERIC(6,2)
ancho_salida     NUMERIC(6,2)
velocidad        NUMERIC(6,2)           -- HIDRO, SECADO, COMPACTADO
entrada          NUMERIC(6,2)           -- HIDRO: weight in
salida           NUMERIC(6,2)           -- HIDRO: weight out
rendimiento      NUMERIC(6,4)           -- COMPACTADO: yield ratio
pases            SMALLINT               -- PERCHADO: pass count
malla_alimentacion NUMERIC(5,2)         -- SECADO
programacion_id  BIGINT FK→programacion
usr_cre, fyh_cre, usr_mod, fyh_mod
```

`fyh_inicio` defaults to `now()` — a run begins the moment the row is created by `crear_ejecucion()`.

**`mes.partida_paso_ejecucion_termofijado`** — TERMOFIJADO-specific extension (1:1 with ejecucion):
```
ejecucion_id       BIGINT PK FK→partida_paso_ejecucion
ancho_marco        NUMERIC(6,2)
vel_maquina        NUMERIC(6,2)
vel_alimentacion   NUMERIC(6,2)
densidad_entrada   NUMERIC(8,4)
densidad_salida    NUMERIC(8,4)
lm                 NUMERIC(6,2)    -- stitch length
galga              NUMERIC(5,1)    -- gauge
```

### 8.8 `partida_componente` — Component Reservations

```
id                 BIGINT IDENTITY PK
partida_id         BIGINT NOT NULL FK→partida
lote_id            INT FK→lote           -- roll row: NOT NULL
item_id            INT FK→item           -- insumo row: NOT NULL
partida_paso_id    BIGINT FK→partida_paso  -- insumo row: NOT NULL; CASCADE on delete
cantidad_reservada NUMERIC(12,4)
usr_cre, fyh_cre, usr_mod, fyh_mod
CONSTRAINT chk_resb_tipo CHECK (
    (lote_id IS NOT NULL AND item_id IS NULL AND partida_paso_id IS NULL)
    OR
    (item_id IS NOT NULL AND lote_id IS NULL AND partida_paso_id IS NOT NULL)
)
```

Partial unique indexes enforce one roll per order and one chemical per step:
- `UNIQUE (partida_id, lote_id) WHERE lote_id IS NOT NULL` — roll uniqueness
- `UNIQUE (partida_paso_id, item_id) WHERE item_id IS NOT NULL` — insumo uniqueness

`partida_paso_id ON DELETE CASCADE` — when a paso is deleted, its insumo reservations are cleaned up automatically.

### 8.9 `programacion` — Machine Schedule

```
id              BIGINT IDENTITY PK
actividad_tipo  TEXT NOT NULL
                    CHECK (actividad_tipo IN ('partida_paso', 'LAVADO_MAQUINA'))
actividad_id    BIGINT NOT NULL       -- FK to partida_paso.id or lavado_maquina.id
maquina_id      INT NOT NULL FK→maquina
fecha           DATE NOT NULL
secuencia       SMALLINT NOT NULL     -- order within machine's day
nota            TEXT
usr_cre, fyh_cre, usr_mod, fyh_mod
UNIQUE (maquina_id, fecha, secuencia)
```

`actividad_tipo = 'partida_paso'` (links to the *plan*, not the execution). The `partida_paso_ejecucion` row links back to `programacion` via its `programacion_id`.

### 8.10 `lavado_maquina` — Machine Wash Execution

```
id          BIGINT IDENTITY PK
receta_id   INT NOT NULL FK→receta.lavado_maquina
maquina_id  INT NOT NULL FK→maquina
estado      partida_paso_estado_enum NOT NULL DEFAULT 'PENDIENTE'
empleado_id SMALLINT FK→empleado
fyh_inicio  TIMESTAMPTZ
fyh_fin     TIMESTAMPTZ
nota        TEXT
usr_cre, fyh_cre, usr_mod, fyh_mod
```

Standalone activities, not tied to a production order. Scheduled via `programacion` with `actividad_tipo = 'LAVADO_MAQUINA'`.

### 8.11 `tiempos_estandar_tenido` and `tiempos_estandar_lavado` — Standard Time Catalog

```
-- tiempos_estandar_tenido
valor_id        SMALLINT NOT NULL FK→valor    -- machine capacity / type
tenido_id       INT NOT NULL FK→tenido
flg_antipilling BOOLEAN NOT NULL DEFAULT false
duracion        INTERVAL NOT NULL
flg_activo      BOOLEAN NOT NULL DEFAULT true
```

```
-- tiempos_estandar_lavado
tipo_lavado_mq_id SMALLINT NOT NULL FK→tipo_lavado_maquina
duracion          INTERVAL NOT NULL
flg_activo        BOOLEAN NOT NULL DEFAULT true
```

Used by scheduling functions to estimate duration on the planning board.

---

## 9. Schema: `receta` — Recipes

### 9.1 `receta.operacion` — Chemistry Operations Catalog

```
id           SMALLINT IDENTITY PK
codigo       TEXT NOT NULL UNIQUE
codigo_canon TEXT NOT NULL UNIQUE
nombre       TEXT NOT NULL
```
Micro-level steps within a recipe: `TINTURA`, `LAVADO`, `NEUTRALIZADO`, `SUAVIZADO`, `JABONADO`, `MATIZADO`, `BLANQUEO_QUIMICO`, etc. Different from `mes.operacion` (macro production steps).

### 9.2 `estado_desarrollo_color` — Recipe Development State

```
id     SMALLINT IDENTITY PK
nombre TEXT NOT NULL
codigo TEXT NOT NULL UNIQUE
```
Values: `INGRESADO`, `EN_DESARROLLO`, `ENVIADO_CLIENTE`, `APROBADO`, `RECHAZADO`, `CANCELADO`, `RE_LAB`, `HISTORICO`.

### 9.3 `receta.tenido` — Dyeing Recipe

```
id                 INT GENERATED BY DEFAULT AS IDENTITY PK  -- manual override allowed
color_x_cliente_id INT FK→color_x_cliente
articulo_tipo_id   SMALLINT FK→articulo_tipo
fibra              SMALLINT
tenido_id          INT FK→tenido                -- legacy dyeing method
flg_antipilling    BOOLEAN NOT NULL DEFAULT false
tipo_receta_id     SMALLINT FK→tipo_receta
estado_id          SMALLINT NOT NULL FK→estado_desarrollo_color
flg_produccion     BOOLEAN NOT NULL DEFAULT false
fyh_produccion     TIMESTAMPTZ
usr_cre INT FK→usuario, fyh_cre, usr_mod INT FK→usuario, fyh_mod
```

**Partial unique index:** `UNIQUE (color_x_cliente_id, articulo_tipo_id, fibra, tenido_id, flg_antipilling) WHERE flg_produccion = true` — only one APROBADO recipe per spec at a time.

**`flg_produccion`** is maintained by `fn_trg_receta_tenido_flg_produccion()` BEFORE INSERT/UPDATE: `flg_produccion = (estado.codigo = 'APROBADO')`. Cannot be set by clients.

**Immutability:** Once a recipe has at least one `partida_paso_ejecucion` with `estado = 'COMPLETADO'`, identity fields (`color_x_cliente_id`, `articulo_tipo_id`, `fibra`, `tenido_id`, `flg_antipilling`, `tipo_receta_id`) raise an exception on UPDATE. Lifecycle fields (`estado_id`, `fyh_produccion`) remain writable.

### 9.4 `receta.tenido_paso` and `receta.tenido_paso_insumo`

**`tenido_paso`**:
```
id           INT IDENTITY PK
receta_id    INT NOT NULL FK→tenido
operacion_id SMALLINT NOT NULL FK→receta.operacion
orden        SMALLINT NOT NULL
ph           NUMERIC(4,2)
temperatura  NUMERIC(5,2)
tiempo_min   SMALLINT
nota         TEXT
UNIQUE (receta_id, orden)
```

**`tenido_paso_insumo`**:
```
id       INT IDENTITY PK
paso_id  INT NOT NULL FK→tenido_paso ON DELETE CASCADE
item_id  INT NOT NULL FK→item
cantidad NUMERIC(10,6) NOT NULL       -- high precision for small dosages
medida   TEXT NOT NULL DEFAULT 'g_kg'
             CHECK (medida IN ('g_kg', 'pct'))
orden    SMALLINT NOT NULL
UNIQUE (paso_id, orden)
```
`ON DELETE CASCADE` — deleting a paso removes all its insumo rows.

### 9.5 `receta.lavado_maquina`

```
id                INT GENERATED BY DEFAULT AS IDENTITY PK
tipo_lavado_mq_id SMALLINT FK→tipo_lavado_maquina
valor_origen_id   SMALLINT FK→valor             -- from-color/value
valor_destino_id  SMALLINT FK→valor             -- to-color/value
flg_activo        BOOLEAN DEFAULT true
usr_cre INT FK→usuario, fyh_cre, usr_mod INT FK→usuario, fyh_mod
```

`UNIQUE (tipo_lavado_mq_id, valor_origen_id, valor_destino_id) WHERE flg_activo = true` — only one active recipe per machine-type/color-transition pair.

Immutable once it has completed `mes.lavado_maquina` executions (`trg_bu_lavado_maquina_immutable`).

### 9.6 `receta.lavado_maquina_paso` and `receta.lavado_maquina_paso_insumo`

Same structure as `tenido_paso` / `tenido_paso_insumo` but referencing `receta.lavado_maquina` instead of `receta.tenido`. `paso_insumo.orden UNIQUE (paso_id, orden)`.

---

## 10. Schema: `calidad` — Quality Control

### 10.1 `tipo_defecto` — Defect Catalog

```
id           SMALLINT IDENTITY PK
codigo       TEXT NOT NULL UNIQUE
codigo_canon TEXT NOT NULL UNIQUE
nombre       TEXT NOT NULL
descripcion  TEXT
severidad    SMALLINT DEFAULT 1       -- 1=minor, 2=major, 3=critical
activo       BOOLEAN DEFAULT true
```

Pre-seeded (12 rows): `LINEA`, `MANCHA`, `HUECO`, `HILO_ROTO`, `CAIDA_MALLA`, `HILO_GRUESO`, `CONTAMINACION`, `TONO_DESIGUAL`, `BARRADO`, `PILLING`, `RESTOS_QUIMICOS`, `ENCOGIMIENTO`. Write requires `calidad.editar`.

### 10.2 `inspeccion` — QC Inspection Header

```
id                        BIGINT IDENTITY PK
lote_id                   INT NOT NULL FK→lote
partida_paso_ejecucion_id BIGINT FK→partida_paso_ejecucion
resultado                 calidad_estado_enum NOT NULL
observacion               TEXT
empleado_id               INT FK→empleado
fyh_inspeccion            TIMESTAMPTZ DEFAULT now()
usr_cre                   INT
fyh_cre                   TIMESTAMPTZ DEFAULT NOW()
```

Creating an inspection via `calidad.crear_inspeccion()` also updates `inventario.lote.estado_calidad` to match `resultado`.

### 10.3 `inspeccion_defecto` and `inspeccion_foto`

```
-- inspeccion_defecto
id              BIGINT IDENTITY PK
inspeccion_id   BIGINT NOT NULL FK→inspeccion
tipo_defecto_id SMALLINT NOT NULL FK→tipo_defecto
cantidad        SMALLINT DEFAULT 1
observacion     TEXT

-- inspeccion_foto
id                    BIGINT IDENTITY PK
inspeccion_defecto_id BIGINT NOT NULL FK→inspeccion_defecto  -- photo belongs to a defect
ruta_archivo          TEXT NOT NULL                          -- Supabase Storage path
etiqueta              TEXT
observacion           TEXT
usr_cre               INT
fyh_cre               TIMESTAMPTZ DEFAULT now()
```

**Note:** Photos are attached to defects, not directly to inspections. An inspection can have multiple defects; each defect can have multiple photos.

---

## 11. Schema: `audit` — Audit Trail

### `audit.data_audit`

```
id               BIGINT IDENTITY PK
schema_name      TEXT
table_name       TEXT
row_id           BIGINT
operacion        TEXT          -- 'INSERT', 'UPDATE', 'DELETE'
old_data         JSONB
new_data         JSONB
usr_id           INT
fyh_cambio       TIMESTAMPTZ DEFAULT now()
ip_address       TEXT
user_agent       TEXT
```

Insert-only. Populated by `audit.fn_audit_row()` on every INSERT/UPDATE/DELETE on audited tables.

**Audited tables:** `tercero`, `mes.partida`, `mes.partida_detalle`, `doc.entrega`, `doc.entrega_detalle`, `mes.ruta_plantilla`, `mes.ruta_plantilla_detalle`, `mes.partida_paso`, `doc.factura_proveedor`, `doc.compra`, `doc.letra`, `doc.factura`.

---

## 12. Schema: `notification` and `alertas` — Notifications

### 12.1 `notification.notifications` — Persistent Notification Log

The notification system serves two distinct purposes sharing one table:

| `tipo` value | Purpose | Resolved by |
|-------------|---------|-------------|
| `'info'`, `'warning'`, `'task'` | Transient event notifications (e.g. "inspection recorded") | User acknowledgement (`fyh_leido`) |
| `'alert'` | Persistent system alerts (e.g. "stock below reorder point") | Condition clearing (`fyh_resuelta`) |

Key columns added in migration 15:
```
objeto_tipo   TEXT      -- 'partida', 'item', 'entrega', 'partida_paso'
objeto_id     BIGINT    -- PK of the referenced entity
fyh_resuelta  TIMESTAMPTZ  -- NULL = condition still active; NOT NULL = resolved
categoria     TEXT      -- alert subtype (see below)
```

**Deduplication index:** `UNIQUE (user_id, categoria, objeto_tipo, objeto_id) WHERE tipo = 'alert' AND fyh_resuelta IS NULL` — prevents a user from receiving the same active alert twice. Each alert recipient gets their own row.

### 12.2 Alert Categories

| `categoria` | Condition | Fired by | Notifies |
|-------------|-----------|----------|---------|
| `partida_vencida` | `partida.fecha_acordada < now()` AND not CERRADA/CANCELADA | `alertas.check_partidas_vencidas()` | `jefe_planta`, `compras` |
| `rollo_sin_programar` | `CLIENTE_ENVIO_PROCESO` entrega older than 5 days with unassigned in-stock rolls | `alertas.check_rollos_sin_programar()` | `jefe_planta`, `supervisor_produccion` |
| `stock_bajo` | Item stock < `stock_minimo` (or < 7-day rolling average when no minimum set); items inactive for 90+ days and without `stock_minimo` are skipped | `alertas.check_stock_bajo()` | `inventario`, `compras` |
| `stock_paso` | A planned paso with `requiere_receta=true` has insufficient insumo stock to cover recipe demand (`dose × batch_kg`) | `alertas.check_stock_pasos()` | `jefe_planta`, `supervisor_produccion`, `inventario`, `compras` |

Each alert function follows the same pattern: **OPEN** (INSERT new alert rows for active conditions; skip if unresolved alert already exists) → **CLOSE** (stamp `fyh_resuelta = now()` on alerts whose condition has cleared). Both operations run in every invocation, so alerts auto-resolve without human intervention.

### 12.3 `pg_cron` Schedules

| Job name | Schedule | Function |
|----------|----------|----------|
| `letras-vencidas` | `0 5 * * *` (midnight Lima time) | `doc.marcar_letras_vencidas()` |
| `alerta-partidas-vencidas` | `0 13 * * *` (8am Lima time) | `alertas.check_partidas_vencidas()` |
| `alerta-rollos-sin-programar` | `0 13 * * *` | `alertas.check_rollos_sin_programar()` |
| `alerta-stock-bajo` | `0 */6 * * *` (every 6h) | `alertas.check_stock_bajo()` |
| `alerta-stock-pasos` | `30 */6 * * *` (every 6h, offset 30m) | `alertas.check_stock_pasos()` |

All alert functions are `SECURITY DEFINER`, callable by `pg_cron` only (`REVOKE EXECUTE ... FROM PUBLIC, authenticated, anon`). The offset on `alerta-stock-pasos` prevents contention with `alerta-stock-bajo`.

### 12.4 `doc.marcar_letras_vencidas()`

Runs nightly. Sets `letra.estado = 'vencida'` for all letras where `estado = 'emitida'` AND `fecha_vencimiento < CURRENT_DATE`. Does not send notifications — state change alone is sufficient (the `vw_cuentas_por_pagar` view surfaces overdue days).

---

## 13. IAM: Roles and Permissions

### 13.1 Architecture

**JWT-driven RBAC.** On every login and token refresh, `custom_access_token_hook` fires:
1. Bridges `auth.users.id` (UUID) → `public.usuario.id` (INT).
2. Collects all permission codes across all assigned roles via `iam.user_rol → iam.rol_permiso → iam.permiso`.
3. Injects three claims into the JWT: `user_permissions` (string array), `user_roles` (string array), `id_usuario` (INT).

**`jwt_has_permission(code TEXT) → BOOLEAN`** — checks `(auth.jwt()->'user_permissions') ? code`. `STABLE` (result cached per query, not per row) and `SECURITY DEFINER`. Called from both RLS policies and function guards.

**Two protection layers:**
- **RLS policies** — control `SELECT` on all business tables. All writes bypass RLS because they go through `SECURITY DEFINER` functions.
- **Function guards** — every write function checks `jwt_has_permission(...)` at the top of `BEGIN`. This is the canonical write gate.

Users can hold multiple roles. The JWT always carries the union of all permissions across all assigned roles.

---

### 13.2 Permission Codes

Permissions follow the pattern `domain.action`. There are 20 codes across 6 domains.

#### COMERCIAL
| Code | Owns |
|------|------|
| `comercial.ver` | Read partidas, guías, compras, facturas, letras |
| `comercial.crear` | Create partidas, guías de remisión, purchase orders |
| `comercial.editar` | Edit commercial docs, register facturas and letras |

> **Note:** `comercial` bundles sales documents (partidas, client invoices, guías de salida) and purchasing documents (compras, facturas proveedor, letras) under one domain. Acceptable for current operational model; candidate for split into `ventas` + `compras` if responsibilities diverge.

#### INVENTARIO
| Code | Owns |
|------|------|
| `inventario.ver` | Read stock, lotes, movements, items, valuations |
| `inventario.crear` | Create items; ingest stock (purchase receipts, service entries) |
| `inventario.editar` | Adjust stock; update weights and MAP valuations |

#### PRODUCCIÓN
| Code | Owns |
|------|------|
| `produccion.ver` | Read orders, pasos, schedule, washes, recipes |
| `produccion.crear` | Create production orders |
| `produccion.editar` | Edit pasos and order structure post-creation |
| `produccion.ejecutar` | Start/finish pasos and washes; register consumptions and output |
| `produccion.programar` | Save and modify machine schedule |
| `produccion.administrar` | Close production orders (requires all three axes settled) |
| `produccion.configurar` | Manage recipes, route templates, articles, standard times |

#### CALIDAD
| Code | Owns |
|------|------|
| `calidad.ver` | Read inspections and QC results |
| `calidad.crear` | Register QC inspections |
| `calidad.editar` | Edit existing inspections; manage defect type catalog |

#### CONFIGURACIÓN
| Code | Owns |
|------|------|
| `configuracion.ver` | Read users, roles, system configuration |
| `configuracion.admin` | Manage users and roles — IAM only |
| `configuracion.operacional` | Manage machine instances, machine types, operation types, employee role types, warehouses and locations |

> **Separation rationale:** `configuracion.admin` is pure IAM (who can log in, what roles exist). `configuracion.operacional` is plant infrastructure (what physical assets and operational catalogs exist). A plant manager needs the latter without the former.

#### CATÁLOGOS
| Code | Owns |
|------|------|
| `catalogos.editar` | Create/edit shared master data: units, insumo types, colorant types, colors |

> Defect types (`calidad.tipo_defecto`) are NOT in `catalogos.editar` — they are owned by `calidad.editar` because the quality domain owns its own catalog.

---

### 13.3 RLS Tier Structure

#### Tier 1 — Catalog tables (open SELECT to all `authenticated`)

These are reference/dropdown tables. Any authenticated user can read them.

**Write guards on Tier 1 tables:**

| Table(s) | Write permission |
|---|---|
| `public.unidad`, `insumo_tipo`, `colorante_tipo`, `color` | `catalogos.editar` |
| `calidad.tipo_defecto` | `calidad.editar` |
| `public.articulo` | `produccion.configurar` |
| `public.articulo_tipo` | `configuracion.admin` |
| `mes.operacion`, `receta.operacion`, `mes.maquina_tipo`, `mes.empleado_rol` | `configuracion.operacional` |

#### Tier 2 — Business tables (READ gated by domain permission)

All writes go through `SECURITY DEFINER` functions, not RLS.

| Domain | Read gate | Tables |
|---|---|---|
| Inventario | `inventario.ver` | `item`, `item_insumo_detalle`, `item_rollo_detalle`, `almacen`, `ubicacion`, `lote`, `item_movimientos`, `pesaje`, `lote_rollo_detalle` |
| Comercial | `comercial.ver` | `doc.*` (all commercial document tables) |
| Partida (bridge) | `comercial.ver` **OR** `produccion.ver` | `mes.partida`, `mes.partida_detalle` — see §13.4 |
| Producción | `produccion.ver` | `mes.maquina`, `mes.empleado`, `mes.ruta_plantilla`, `mes.ruta_plantilla_detalle`, `mes.partida_componente`, `mes.partida_paso`, `mes.partida_paso_ejecucion`, `mes.programacion`, `mes.lavado_maquina` |
| Recetas | `produccion.ver` | `receta.tenido`, `receta.tenido_paso`, `receta.tenido_paso_insumo`, `receta.lavado_maquina`, `receta.lavado_maquina_paso`, `receta.lavado_maquina_paso_insumo` |
| Calidad | `calidad.ver` | `calidad.inspeccion`, `calidad.inspeccion_defecto`, `calidad.inspeccion_foto` |

#### Tier 3 — IAM tables

| Table | Access |
|---|---|
| `iam.rol` | Open to all authenticated (needed for dropdowns) |
| `iam.permiso`, `iam.user_rol`, `iam.rol_permiso` | `configuracion.ver` |
| `public.usuario` | Own row always; all rows with `configuracion.ver` |

---

### 13.4 Key Design Patterns

#### The `mes.partida` bridge entity

`mes.partida` (the production order) was created by the commercial flow, so it lives in the `comercial.ver` RLS tier. But it is also the root entity that every production, quality, and inventory operation references. To avoid forcing all operational roles to carry `comercial.ver` just to read an order header, `mes.partida` and `mes.partida_detalle` carry **two PERMISSIVE SELECT policies** — one for `comercial.ver` and one for `produccion.ver`. PostgreSQL combines PERMISSIVE policies with OR, so either permission grants visibility.

**Consequence:** roles that need complete production order context need at least one of `comercial.ver` or `produccion.ver`. This is always true for any operational role, so it is not a burden in practice.

#### `produccion.ejecutar` implies inventory writes

`registrar_consumo_paso` and `registrar_produccion` (both guarded by `produccion.ejecutar`) post rows to `inventario.item_movimientos`. This write is protected by the function guard, not by an `inventario.editar` check. This is intentional — the consumption action belongs to the production domain even though it has an inventory side-effect.

**Implication:** never remove `inventario.ver` from a role that has `produccion.ejecutar`. Operators need it to look up and validate lots before consuming them.

#### Cross-domain reads are not noise

Every operational role carries `.ver` permissions outside its primary domain. This is structural, not a "fat role" problem. Examples:
- Production roles need `comercial.ver` (or `produccion.ver`) to see the partida header.
- Quality roles need `produccion.ver` and `inventario.ver` to inspect a production step in context.
- Purchasing roles need `inventario.ver` to see stock and `produccion.ver` for consumption data.

A cross-domain `.ver` is only noise if the role has no legitimate reason to ever display that data to the user. The fat-role test is: **would a real person in this role be harmed by losing this permission?**

#### Recipes are access-controlled at the table level

`receta.*` business tables have RLS enabled with `produccion.ver` as the SELECT gate. The application accesses recipe data through SECURITY DEFINER functions and views — direct table queries are also gated, but writes are exclusively through functions.

---

### 13.5 Roles Reference

| Role | Primary domain | Write permissions | Context reads |
|---|---|---|---|
| `admin` | All | All 20 permissions | — |
| `jefe_planta` | produccion + inventario + calidad | `produccion.*` (all), `inventario.*` (all), `calidad.*` (all), `catalogos.editar`, `configuracion.operacional` | `comercial.ver`, `configuracion.ver` |
| `supervisor_produccion` | produccion | `produccion.configurar/crear/editar/ejecutar/programar/administrar` | `comercial.ver`, `inventario.ver`, `calidad.ver` |
| `operador_produccion` | produccion (execution) | `produccion.ejecutar` | `produccion.ver`, `inventario.ver`, `calidad.ver` |
| `calidad` | calidad | `calidad.crear`, `calidad.editar` | `calidad.ver`, `produccion.ver`, `inventario.ver` |
| `inventario` | inventario | `inventario.*` (all), `catalogos.editar` | `produccion.ver`, `comercial.ver` |
| `compras` | comercial/procurement | `comercial.*` (all), `inventario.crear`, `catalogos.editar` | `inventario.ver`, `produccion.ver` |
| `sistema` | automated | `produccion.ejecutar`, `inventario.editar` | `produccion.ver`, `inventario.ver`, `calidad.ver` — never assign to humans |

> `supervisor_produccion` has `produccion.ejecutar` because supervisors in this operation personally execute production steps on the floor, in addition to planning and configuration work.

---

### 13.6 Role Assignment Rules

#### Rule 1 — Classify every permission as Primary or Context before assigning

| Category | Definition | Allowed actions |
|---|---|---|
| **Primary** | Why the role exists; the domain it owns | Any — `.ver`, `.crear`, `.editar`, `.ejecutar`, etc. |
| **Context** | Cross-domain reads the role needs to do its primary job | `.ver` only |

A write permission (`.crear`, `.editar`, `.ejecutar`, `.configurar`, `.administrar`, `.admin`, `.operacional`) that falls in a **context domain** is wrong. Remove it or justify it explicitly.

#### Rule 2 — The noise test before blending two roles

Before assigning a second role to a user, for each role list its write permissions and ask: are all of them within the user's actual responsibilities? If any write falls outside — that is noise. Do not blend; create a dedicated role instead.

Cross-domain `.ver` permissions are **never noise** — they are structural.

#### Rule 3 — When to blend vs when to create a new role

**Blend** when: the union adds only `.ver` permissions outside primary domains, and applies to ≤ 2 users.

**Create a new role** when: blending adds ≥ 1 unwanted write outside the user's primary domain, OR ≥ 2 users share the same non-standard profile.

#### Rule 4 — Elevated permissions require explicit justification

`produccion.administrar` and `configuracion.admin` must appear on a role only when the job description explicitly includes closing/finalizing production orders or managing user accounts. Do not include them transitively.

#### Rule 5 — Role names describe function, not title

Use function names: `operador_produccion`, `tecnico_planta`, `compras`. Avoid title names: `gerente`, `jefe_X`, `asistente` — titles change; functions don't.

#### Rule 6 — Domain ownership of catalog data

Each domain owns its own catalog:
- Shared master data (units, input types, colors) → `catalogos.editar`
- Defect types → `calidad.editar`
- Product articles → `produccion.configurar`
- Machine types, operation types → `configuracion.operacional`
- Article types → `configuracion.admin`

Do not re-route catalog writes to a different domain's permission for convenience.

---

### 13.7 Future Considerations (deferred, do not act until the need is real)

| Item | Description | Trigger condition |
|---|---|---|
| Split `comercial` → `ventas` + `compras` | Sales and purchasing share one domain; a sales person can create purchase orders and vice versa | When sales and purchasing are handled by separate people with different access requirements |
| Split `produccion.configurar` → `receta.editar` + `configuracion.produccion` | Recipe editing and machine/standard time configuration are bundled; forces "recipe only" users to get machine write access | When ≥ 2 distinct role profiles need "half" of what `produccion.configurar` grants |

---

## 14. Trigger Catalog

### BEFORE INSERT triggers

| Trigger | Table | Function | Effect |
|---------|-------|----------|--------|
| `trg_bi_set_cre` | Every audited table | `fn_trg_set_cre_fields()` | Sets `usr_cre = get_user_id()`, `fyh_cre = now()` |
| `trg_bi_set_codigo_canon` | Every catalog table | `fn_trg_set_codigo_canon()` | Sets `codigo_canon = lower(unaccent(codigo))` |
| `trg_bi_lote_secuencia` | `inventario.lote` | `trfn_generar_secuencia_lote()` | Increments `lote_secuencia_anual.ultimo_valor` for the current year; sets `lote.secuencia` |
| `trg_bi_maquina_codigo` | `mes.maquina` | `fn_trg_gen_codigo_maquina()` | Auto-generates `codigo = '{tipo}-{NNN}'` if NULL |
| `trg_bi_ubicacion_codigo` | `inventario.ubicacion` | `fn_trg_gen_codigo_ubicacion()` | Auto-generates `codigo` from almacen abbreviation + counter |
| `trg_bi_check_corte` | `inventario.item_movimientos` | `fn_trg_check_corte_cuadre()` | Raises `insufficient_privilege` if `fecha_hora < last_executed_cuadre.fecha_cuadre` |

### BEFORE UPDATE triggers

| Trigger | Table | Function | Effect |
|---------|-------|----------|--------|
| `trg_bu_set_mod` | Every audited table | `fn_trg_set_mod_fields()` | Sets `usr_mod`, `fyh_mod`; preserves `usr_cre`/`fyh_cre` |
| `trg_bu_set_elm` | Soft-delete tables | `fn_trg_set_elm_fields()` | On `flg_elm` false→true: sets `usr_elm`, `fyh_elm` once |
| `trg_bu_immutable_codigo` | Every catalog table | `fn_trg_immutable_codigo()` | Raises exception if `OLD.codigo != NEW.codigo` |
| `trg_bu_receta_tenido_identidad` | `receta.tenido` | `fn_trg_receta_tenido_immutable()` | Raises exception if identity fields change once the recipe has completed executions |
| `trg_bu_lavado_maquina` | `receta.lavado_maquina` | `fn_trg_lavado_maquina_immutable()` | Raises exception if recipe has completed `mes.lavado_maquina` rows |
| `trg_bu_check_corte` | `inventario.item_movimientos` | `fn_trg_check_corte_cuadre()` | Same cutoff check as BEFORE INSERT |

### BEFORE INSERT/UPDATE triggers

| Trigger | Table | Function | Effect |
|---------|-------|----------|--------|
| `trg_biu_receta_flg_produccion` | `receta.tenido` | `fn_trg_receta_tenido_flg_produccion()` | Sets `flg_produccion = (estado.codigo = 'APROBADO')`; client cannot override |

### BEFORE DELETE triggers

| Trigger | Table | Function | Effect |
|---------|-------|----------|--------|
| `trg_bd_prevent_delete` | `doc.entrega`, `inventario.lote`, `mes.partida`, `doc.factura` (once emitted/annulled) | `fn_trg_prevent_hard_delete()` | Raises exception; use soft delete (`flg_elm`) instead |

### AFTER INSERT triggers

| Trigger | Table | Function | Effect |
|---------|-------|----------|--------|
| `trg_ai_item_rollo_codigo` | `item_rollo_detalle` | `fn_trg_gen_codigo_item_rollo()` | Sets `item.codigo = 'R-{articulo}-{fibra}'` for the parent item |
| `trg_ai_item_insumo_codigo` | `item_insumo_detalle` | `fn_trg_gen_codigo_item_insumo()` | Sets `item.codigo = 'I-{tipo}-{name}'` for the parent item |
| `trg_ai_im_sync_saldo` | `inventario.item_movimientos` | `trg_ai_im_sync_cantidad_actual()` | Updates `lote_saldo` and `item_saldo` with UPSERT |
| `trg_ai_item_movimientos_map` | `inventario.item_movimientos` | `fn_trg_actualizar_map()` | Updates `item_valoracion` (MAP recalculation when `flg_recalcula_costo = true`) |

### AFTER INSERT/UPDATE/DELETE triggers (Audit)

| Trigger | Tables | Function | Effect |
|---------|--------|----------|--------|
| `trg_audit_*` | All audited tables (see §11) | `audit.fn_audit_row()` | Inserts `(table, row_id, operacion, old_data, new_data, usr_id)` into `audit.data_audit` |

### Supabase Auth hook

| Trigger | Table | Function | Effect |
|---------|-------|----------|--------|
| `trg_bi_auth_users_usuario` | `auth.users` | `fn_trg_bi_usuario_from_auth()` | On new user signup: inserts row into `public.usuario` with `first_name`/`last_name` from user metadata |

---

## 15. Function Catalog

All functions use `SECURITY DEFINER` and `SET search_path` to prevent path-injection attacks. Most gate access via `jwt_has_permission()` at the top of the function body.

### 14.1 Identity / Infrastructure

| Function | Returns | Permission | Notes |
|----------|---------|------------|-------|
| `public.get_user_id()` | `INT` | — | Reads `id_usuario` from JWT. Zero DB queries. |
| `public.jwt_has_permission(code TEXT)` | `BOOLEAN` | — | Checks `user_permissions` array in JWT. STABLE. |
| `public.custom_access_token_hook(event JSONB)` | `JSONB` | Supabase auth system | Injects permissions/roles into JWT on login. |

### 14.2 Item Functions

| Function | Returns | Permission |
|----------|---------|------------|
| `public.get_item(p_item_id BIGINT)` | `JSONB` | `inventario.ver` |
| `public.crear_item_insumo(p_item JSONB, p_item_id INT)` | `TEXT` | `inventario.crear` |
| `public.crear_item_rollo(p_item JSONB, p_item_id INT)` | `TEXT` | `inventario.crear` |

`get_item()` returns the `item` row plus its type-specific extension (rollo or insumo detalle) as a JSONB object.

### 14.3 Warehouse Functions

| Function | Returns | Permission |
|----------|---------|------------|
| `inventario.get_almacen(p_almacen_id INT)` | `JSONB` | `inventario.ver` |
| `inventario.crear_almacen(p_almacen JSONB)` | `TEXT` | `configuracion.operacional` |
| `inventario.modificar_almacen(p_almacen JSONB)` | `TEXT` | `configuracion.operacional` |
| `inventario.eliminar_almacen(p_almacen_id INT)` | `TEXT` | `configuracion.operacional` |

`crear_almacen` accepts nested `ubicaciones` array. `eliminar_almacen` soft-deletes the warehouse and sends a push notification.

### 14.4 Inventory / Cuadre Functions

| Function | Returns | Permission |
|----------|---------|------------|
| `inventario.crear_cuadre()` | `BIGINT` (cuadre_id) | `inventario.editar` |
| `inventario.get_cuadre(p_cuadre_id BIGINT)` | `JSONB` | `inventario.ver` |
| `inventario.update_cuadre_detalles(p_json JSONB)` | `VOID` | `inventario.editar` |
| `inventario.finalizar_cuadre(p_cuadre_id BIGINT)` | `JSONB` | `inventario.editar` |
| `inventario.get_item_movimientos_cuadre(p_item_id INT, p_cuadre_id BIGINT)` | `JSONB` | `inventario.ver` |

**`crear_cuadre()`:** Snapshots `item_saldo` for all INSUMO items (including zero-stock) into `cuadre_detalle`. Includes `precio_promedio_sistema` from `item_valoracion` and `ult_precio_compra` from the most recent `COMPRA_ING` movement.

**`finalizar_cuadre()`:**
1. Validates all items have `cantidad_contada` set.
2. For each deficit (sistema > contada): calls `calcular_fifo()` to resolve which lots to consume; posts `AJUSTE_NEG` movements.
3. For each surplus (contada > sistema): creates a new `inventario.lote` per item; posts `AJUSTE_POS` movement.
4. Updates `item_valoracion` for both directions.
5. Sets cuadre `estado = 'ejecutado'`, `fecha_cierre = now()`.
6. The cutoff trigger now blocks any movement with `fecha_hora < fecha_cuadre`.

**`update_cuadre_detalles(p_json)`:** Input shape `[{"id": INT, "cantidad_contada": NUMERIC}, ...]`. Idempotent — re-running with the same values is safe.

### 14.5 MES Scheduling Functions

| Function | Returns | Permission |
|----------|---------|------------|
| `mes.get_programacion_diaria(p_fecha DATE)` | `JSONB` | `produccion.ver` |
| `mes.get_actividades_sin_programar()` | `JSONB` | `produccion.ver` |
| `mes.guardar_programacion(p_fecha DATE, p_programaciones JSONB)` | `TEXT` | `produccion.programar` |

**`guardar_programacion()`:** Atomically replaces the full schedule for `p_fecha` (DELETE + INSERT). Input: array of `{actividad_tipo, actividad_id, maquina_id, secuencia, nota}`. Validates that each `actividad_id` references an existing entity of the declared type.

**`get_programacion_diaria()`:** Returns the board grouped by machine, including paso state, ejecucion data, and recipe info for each activity.

### 14.6 MES Production Execution Functions

**Create → Register → Finalize flow:**

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `mes.crear_ejecucion` | `(p_paso_id BIGINT)` | `BIGINT` (ejecucion_id) | `produccion.ejecutar` |
| `mes.generar_receta` | `(p_paso_id BIGINT)` | `JSONB` | `produccion.ver` |
| `mes.registrar_produccion` | `(p_ejecucion_id BIGINT, p_datos JSONB)` | `TEXT` | `produccion.ejecutar` |
| `mes.finalizar_ejecucion` | `(p_ejecucion_id BIGINT, p_resultado TEXT)` | `TEXT` | `produccion.ejecutar` |
| `mes.reabrir_ejecucion` | `(p_ejecucion_id BIGINT)` | `TEXT` | `produccion.editar` |
| `mes.anular_ejecucion` | `(p_ejecucion_id BIGINT)` | `TEXT` | `produccion.ejecutar` |

**`crear_ejecucion()`:** Inserts a `partida_paso_ejecucion` row with `estado = 'EN_PROCESO'`, `fyh_inicio = now()`. Calls `actualizar_estado_partida()` to advance the partida to `EN_PRODUCCION`.

**`generar_receta()`:** Reads the assigned `receta.tenido` for the paso; scales each `tenido_paso_insumo.cantidad` by the batch weight and unit conversion; returns `[{item_id, cantidad_scaled, medida, paso_order}, ...]`. Does not write to any table.

**`registrar_produccion(p_ejecucion_id, p_datos)`:** `p_datos` shape:
```jsonc
{
  "cantidad": NUMERIC,          // actual batch weight
  "ph_real": NUMERIC,
  "temperatura_real": NUMERIC,
  "relacion_bano_real": NUMERIC,
  "notas": TEXT,
  "output_lotes": [             // one entry per output roll
    { "item_id": INT, "cantidad": NUMERIC }
  ]
}
```
For each output lot: creates `inventario.lote` with `documento_tipo = 'partida_paso_ejecucion'`; creates `inventario.lote_rollo_detalle` with dye attributes (color, tenido, antipilling); posts `PROD_ING` movement; creates `inventario.pesaje` record. Also posts `PROD_CONSUMO` for the input rolls.

**`anular_ejecucion()`:** Deletes the ejecucion row; reverses inventory movements (posts `PROD_ING_REV` and `PROD_CONSUMO_REV`); soft-deletes output lotes.

### 14.7 MES Order Management Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `mes.actualizar_estado_partida` | `(p_partida_id BIGINT)` | `VOID` | internal |
| `mes.crear_reproceso` | `(p_partida_origen_id BIGINT)` | `BIGINT` (new partida_id) | `produccion.crear` |
| `mes.actualizar_componentes_partida` | `(p_partida_id BIGINT, p_rollos JSONB)` | `TEXT` | `produccion.editar` |
| `mes.actualizar_pesos_individuales_partida` | `(p_partida_id BIGINT, p_pesos JSONB)` | `TEXT` | `inventario.editar` |
| `mes.corregir_pesaje_produccion` | `(p_pesaje_id INT, p_peso_real NUMERIC)` | `TEXT` | `inventario.editar` |
| `mes.calcular_fifo` | `(p_movimientos JSONB)` | `JSONB` | internal |

**`actualizar_estado_partida()`:** Derives `estado_produccion` from paso states. Logic:
- Any paso EN_PROCESO → EN_PRODUCCION (sets `fyh_inicio` once)
- All pasos COMPLETADO or OMITIDO → TECO (sets `fyh_fin`)
- No pasos exist → stays CREADA
- Pasos exist but none started → PLANIFICADA or PROGRAMADA

**`calcular_fifo(p_movimientos)`:** Input `[{item_id, cantidad}, ...]`. Queries `lote_saldo` ordered by `lote.fyh_cre ASC` (oldest first). Returns `[{item_id, lote_id, ubicacion_id, cantidad}, ...]` resolving which lots to consume to fulfill the requested quantities.

### 14.8 MES Wash Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `mes.crear_lavado_maquina` | `(p_receta_id INT, p_maquina_id INT)` | `BIGINT` | `produccion.ejecutar` |
| `mes.completar_lavado_maquina` | `(p_lavado_id BIGINT)` | `TEXT` | `produccion.ejecutar` |

`completar_lavado_maquina()` sets `estado = 'COMPLETADO'`, `fyh_fin = now()`, and posts `PROD_CONSUMO` movements for each recipe ingredient (scaled to machine capacity).

### 14.9 Recipe Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `receta.crear_tenido` | `(p_data JSONB)` | `BIGINT` | `produccion.configurar` |
| `receta.actualizar_tenido` | `(p_receta_id INT, p_data JSONB)` | `TEXT` | `produccion.configurar` |
| `receta.transicionar_tenido` | `(p_receta_id INT, p_estado_codigo TEXT)` | `TEXT` | `produccion.configurar` |
| `receta.get_tenido` | `(p_receta_id INT)` | `JSONB` | `produccion.ver` |
| `receta.get_tenido_para_partida` | `(p_partida_id BIGINT)` | `JSONB` | `produccion.ver` |
| `receta.resolver_tenido_id` | `(p_color_x_cliente_id INT, p_articulo_tipo_id SMALLINT, p_fibra SMALLINT)` | `INT` | `produccion.ver` |
| `receta.crear_lavado_maquina` | `(p_data JSONB)` | `BIGINT` | `produccion.configurar` |
| `receta.activar_lavado_maquina` | `(p_receta_id INT)` | `TEXT` | `produccion.configurar` |
| `receta.desactivar_lavado_maquina` | `(p_receta_id INT)` | `TEXT` | `produccion.configurar` |
| `receta.actualizar_lavado_maquina` | `(p_receta_id INT, p_data JSONB)` | `TEXT` | `produccion.configurar` |
| `receta.get_lavado_maquina` | `(p_receta_id INT)` | `JSONB` | `produccion.ver` |

**`transicionar_tenido()`:** On transition to `APROBADO`: atomically moves any existing APROBADO recipe for the same `(color_x_cliente_id, articulo_tipo_id, fibra, tenido_id, flg_antipilling)` combination to `HISTORICO`, then sets the new one to `APROBADO`. This is the only safe way to approve a recipe.

**`get_tenido_para_partida()`:** Looks up recipes by matching the partida's `(color_x_cliente_id, articulo_tipo_id, fibra, flg_antipilling)` with `WHERE flg_produccion = true`. Returns both the best match and any approved alternatives.

### 14.10 Quality Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `calidad.crear_inspeccion` | `(p_inspeccion JSONB)` | `JSONB` | `calidad.crear` |
| `calidad.get_inspeccion` | `(p_inspeccion_id BIGINT)` | `JSONB` | `calidad.ver` |
| `calidad.actualizar_inspeccion` | `(p_inspeccion_id BIGINT, p_datos JSONB)` | `TEXT` | `calidad.editar` |
| `calidad.crear_tipo_defecto` | `(p_datos JSONB)` | `SMALLINT` | `calidad.editar` |
| `calidad.actualizar_tipo_defecto` | `(p_tipo_id SMALLINT, p_datos JSONB)` | `TEXT` | `calidad.editar` |

**`crear_inspeccion()` input shape:**
```jsonc
{
  "lote_id": INT,
  "partida_paso_ejecucion_id": BIGINT,
  "resultado": "APROBADO" | "REPROCESO" | "BAJA",
  "observacion": TEXT,
  "empleado_id": INT,
  "defectos": [
    {
      "tipo_defecto_id": INT,
      "cantidad": INT,
      "observacion": TEXT,
      "fotos": [{ "ruta_archivo": TEXT, "etiqueta": TEXT }]
    }
  ]
}
```
Also updates `inventario.lote.estado_calidad = resultado` and sends notifications to `jefe_planta` and `calidad` role users.

### 14.11 Purchase Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `doc.crear_compra` | `(p_datos JSONB)` | `BIGINT` | `comercial.crear` |
| `doc.actualizar_compra` | `(p_compra_id BIGINT, p_datos JSONB)` | `TEXT` | `comercial.editar` |
| `doc.anular_compra` | `(p_compra_id BIGINT)` | `TEXT` | `comercial.editar` |
| `doc.registrar_factura_proveedor` | `(p_datos JSONB)` | `BIGINT` | `comercial.crear` |
| `doc.actualizar_factura_proveedor` | `(p_factura_id BIGINT, p_datos JSONB)` | `TEXT` | `comercial.editar` |
| `doc.anular_factura_proveedor` | `(p_factura_id BIGINT)` | `TEXT` | `comercial.editar` |
| `doc.get_factura_proveedor` | `(p_factura_id BIGINT)` | `JSONB` | `comercial.ver` |
| `doc.registrar_letras` | `(p_factura_proveedor_id BIGINT, p_letras JSONB)` | `TEXT` | `comercial.editar` |
| `doc.pagar_letra` | `(p_letra_id BIGINT, p_fecha_pago DATE)` | `TEXT` | `comercial.editar` |
| `doc.vincular_entregas_compra` | `(p_compra_id BIGINT, p_entrega_ids JSONB)` | `TEXT` | `comercial.crear` |
| `doc.vincular_factura_compra` | `(p_compra_id BIGINT, p_factura_id BIGINT)` | `TEXT` | `comercial.editar` |

**`registrar_factura_proveedor()` validations:** `ABS(total - subtotal - igv) < 0.01`; `tipo_cambio` required for USD; optional `compra_id` linkage validated for matching `tercero_id`.

**`registrar_letras()` behavior:** Idempotent; replaces all `emitida` letras for the given factura with the new set. Validates `SUM(monto_aplicado) <= factura.total`. Sets `factura.tipo_pago = 'credito'`.

**`pagar_letra()` behavior:** Sets `letra.estado = 'pagada'`, `fecha_pago = p_fecha_pago`. Then derives factura `estado_pago`: if all linked letras are `pagada` → `'total'`; if at least one is → `'parcial'`.

### 14.12 Dispatch Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `doc.crear_entrega_despacho` | `(p_datos JSONB)` | `BIGINT` | `comercial.crear` |
| `doc.registrar_despacho` | `(p_entrega_id BIGINT, p_detalles JSONB)` | `TEXT` | `produccion.ejecutar` |
| `doc.anular_despacho` | `(p_entrega_id BIGINT)` | `TEXT` | `comercial.editar` |

`registrar_despacho()` posts `SERV_EGR` inventory movements and updates `partida.estado_comercial`.

### 14.13 Billing Functions

| Function | Signature | Returns | Permission |
|----------|-----------|---------|------------|
| `doc.crear_factura` | `(p_partida_id BIGINT)` | `BIGINT` | `comercial.crear` |
| `doc.emitir_factura` | `(p_factura_id BIGINT)` | `TEXT` | `comercial.editar` |
| `doc.anular_factura` | `(p_factura_id BIGINT)` | `TEXT` | `comercial.editar` |
| `doc.actualizar_linea_factura` | `(p_linea_id BIGINT, p_datos JSONB)` | `TEXT` | `comercial.editar` |
| `doc.actualizar_estado_facturacion_partida` | `(p_partida_id BIGINT)` | `VOID` | internal |

**`crear_factura()`:** Creates a `borrador` invoice. Attempts to look up `doc.catalogo_precios` for line prices. Returns `factura_id`.

**`emitir_factura()`:** Transitions `borrador → emitida`. Validates `total > 0`. Calls `actualizar_estado_facturacion_partida()`.

**`actualizar_estado_facturacion_partida()`:** Sets `partida.estado_facturacion` based on all linked `factura` rows: `pendiente` (no emitida facturas), `parcial` (at least one emitida, not full), `facturado` (full order value covered).

---

## 16. Views Reference

### `public` schema

| View | Key columns | Notes |
|------|-------------|-------|
| `vw_items` | `item_id`, `item_codigo`, `item_nombre`, `item_tipo_id`, `item_tipo_codigo`, `unidad_id`, `unidad_codigo` | Foundation join table used by most other views |
| `vw_colores` | `color_x_cliente_id`, `color_id`, `color`, `tono`, `cliente_id`, `tercero_id`, `hex` variants | Legacy backward-compat aliases kept |
| `vw_enums` | `schema`, `enum_type`, `value`, `sort_order` | All PostgreSQL enum values; used by frontend at boot for dropdown population |
| `vw_dashboard_kpis` | `partidas_activas`, `ordenes_activas`, `pasos_pendientes`, `pasos_en_proceso`, `rollos_en_planta`, `kg_en_planta` + month-over-month counts | Single-row view; frontend calls `.single()` |
| `vw_dashboard_actividad_reciente` | `tipo`, `descripcion`, `fyh`, `referencia_id`, `referencia_codigo` | Last 20 events in 30-day window |
| `vw_dashboard_tareas` | `tipo`, `descripcion`, `count`, `urgencia` | Actionable task counts; zero-count rows filtered out |

### `inventario` schema

| View | Notes |
|------|-------|
| `vw_stock_lotes` | Per-lot stock summing `lote_saldo` across locations. Filters `cantidad_actual > 0`. ≈ SAP MCHB. Foundation for FIFO and roll views. |
| `vw_stock_lotes_ubicacion` | Per-(lot, location) — exposes `ubicacion_id` for picking screens. |
| `vw_stock_items` | Item totals from `item_saldo`. O(1). ≈ SAP MARD. Use for availability gates. |
| `vw_stock_items_ubicacion` | Item stock per location — same but location-scoped. |
| `vw_stock_items_valorado` | Item stock + `precio_promedio` + computed `stock_valorado`. Financial view (≈ SAP MB52). Note: `stock_valorado` is computed as `SUM(cantidad_actual) × precio_promedio`, not the stored `item_valoracion.stock_valorado`, to avoid MAP accounting drift. |
| `vw_lotes_rollos_stock` | All rolls in stock with full attributes: color, width, mesh, weight, location, owner, ingress entrega. Joins `lote_rollo_detalle` for dye attributes (NULL for undyed rolls). |
| `vw_lotes_rollos_disponibles` | Available rolls: `vw_lotes_rollos_stock` minus rolls reserved by non-CERRADA/CANCELADA partidas. ≈ SAP MD04. |
| `vw_stock_rollos_crudos` | Undyed rolls in stock. Grouped by (item × propietario). |
| `vw_stock_rollos_tenidos` | Dyed rolls in stock. Grouped by full spec identity (color + tenido + dimensions + quality). |
| `vw_stock_insumos` | Insumo totals with tipo/colorante from `item_saldo`. |
| `vw_precio_promedio_insumos` | Weighted avg cost per insumo. Source priority: `factura_proveedor_detalle` > `compra_detalle` (fallback for items with no invoice lines). |
| `vw_lotes_disponibles` | All available lots (any type) with lote code, location, quantity. |
| `vw_item_proveedor_entrega` | Items × suppliers from inbound entregas. Purchase history lookup. |
| `vw_lotes_rollos_despachados` | Rolls with zero stock and a non-production egress. Linked back to originating partida. |
| `vw_items_movimientos` | Full movement history: item code, lot code, location names, type name, `cantidad_neta` (signed). |
| `vw_entregas_rollos_pendientes` | `CLIENTE_ENVIO_PROCESO` entregas with unassigned in-stock rolls. Shows `dias_espera`, pending/assigned counts and weights. |
| `vw_rollos_por_entrega` | Roll counts and weights per ingress entrega (crudo + tenido breakdown). |
| `vw_pesaje_pendiente` | *(in `mes` schema)* Partidas with a scheduled TENIDO paso and ≥1 unweighed assigned roll. Grouped by (partida, entrega, item) for the print-friendly weighing form. |

### `doc` schema

| View | Notes |
|------|-------|
| `vw_compras` | PO list: proveedor, facturas summary, payment status, receipt progress (`sin_lineas` / `pendiente` / `parcial` / `completo`). |
| `vw_facturas_proveedor` | Supplier invoices with `saldo_pendiente = total - monto_aplicado_total` and `dias_vencido`. |
| `vw_compras_item_mes` | Purchases by (supplier, item, month). Primary source: `factura_proveedor_detalle`; fallback: `compra_detalle`. `fuente` column distinguishes the two. |
| `vw_letras` | Letras with `monto_libre = monto - monto_aplicado_total` and overdue days. |
| `vw_cuentas_por_pagar` | AP clearing: one row per (factura × letra) pair. Facturas with no letra → NULL letra columns. Supports AP aging, payment schedule, unassigned-letter analysis. |
| `vw_compras_recepcion` | Receipt tracking per (compra, item): ordered vs received qty, `cantidad_pendiente`, per-line status. |

### `mes` schema

| View | Notes |
|------|-------|
| `vw_partidas` | Production orders: paso stats (total/completed/in-process/pending), material totals, production yield, duration in hours, billing state. `progreso_porcentaje` = completed pasos / total pasos. |
| `vw_partida_resumen_tenido` | Material summary per partida: roll count broken down by articulo / fibra / rib vs regular. |
| `vw_pasos` | Step details with derived `estado`, actual vs planned machine, full ejecucion data, TERMOFIJADO extension columns, scheduling board slot. |
| `vw_maquinas` | Machines with tipo details and associated `operacion_codigo`. |
| `vw_partida_produccion_rollos` | Roll output count per (partida, item type) from completed executions. |
| `vw_empleados_activos` | Active employees with `nombre_completo` and role. |
| `vw_pesaje_pendiente` | See above (inventario section). |

### `calidad` schema

| View | Notes |
|------|-------|
| `vw_lotes_pendientes_inspeccion` | Rolls eligible for QC. Three paths: (A) output roll from completed paso not yet inspected; (B) input roll in active partida not yet inspected against current paso; (C) rework input roll (same as B). |
| `vw_inspecciones` | Inspection list: lote, item, resultado, empleado, timestamp. |
| `vw_partidas_pendientes_calidad` | Partida-level QC task list: `lotes_pendientes_qc`, `operaciones_pendientes` (array), `lote_pendiente_mas_antiguo`, `lotes_en_produccion`, `lotes_asignados_total`, `tiene_rework_activo`. |

---

## 17. Key Business Flows (End-to-End)

### Flow 1: Client Sends Rolls for Processing

1. Client arrives with rolls. Create `doc.entrega` type `CLIENTE_ENVIO_PROCESO`.
2. Add one `doc.entrega_detalle` row per roll, each with a new `inventario.lote`.
3. `item_movimientos` row (type `SERV_ING`) is posted per roll → `lote_saldo` and `item_saldo` updated by trigger.
4. Create `inventario.lote_rollo_detalle` with `entrega_id` (billing anchor) and `flg_tenido = false`.
5. Rolls appear in `inventario.vw_entregas_rollos_pendientes` until assigned to a partida.

### Flow 2: Create and Plan a Production Order

1. Create `mes.partida` with client, color spec, fabric specs. `estado_produccion = 'CREADA'`.
2. Add `mes.partida_detalle` rows (planned roll counts by item type).
3. Add `mes.partida_paso` rows in sequence (e.g. TENIDO → LAVADO_HIDRO → SECADO). `estado_produccion → 'PLANIFICADA'`.
4. Assign rolls: add `mes.partida_componente` rows (roll type: `lote_id IS NOT NULL`).
5. Reserve chemicals: add `mes.partida_componente` rows (insumo type: `item_id IS NOT NULL, partida_paso_id IS NOT NULL, cantidad_reservada = scaled qty`).
6. Schedule: call `mes.guardar_programacion()` to assign pasos to machines/dates. `estado_produccion → 'PROGRAMADA'`.
7. Weigh rolls: create `inventario.pesaje` rows per roll (`vw_pesaje_pendiente` surfaces this gate).

### Flow 3: Execute a Production Step

1. Call `mes.crear_ejecucion(paso_id)` → new `partida_paso_ejecucion` (EN_PROCESO). `partida.estado_produccion → 'EN_PRODUCCION'`.
2. Call `mes.generar_receta(paso_id)` to get scaled ingredient list for the operator.
3. Operator runs the machine, records actual parameters.
4. Call `mes.registrar_produccion(ejecucion_id, {cantidad, ph_real, …, output_lotes: [...]})`:
   - Creates output `inventario.lote` rows (dyed rolls).
   - Creates `inventario.lote_rollo_detalle` with color/tenido/antipilling attributes.
   - Posts `PROD_ING` movements for each output roll.
   - Posts `PROD_CONSUMO` for input rolls.
5. Perform QC: call `calidad.crear_inspeccion()` for each output roll.
6. Call `mes.finalizar_ejecucion(ejecucion_id, 'COMPLETADO')`.
7. `mes.actualizar_estado_partida()` is called internally; partida advances toward `TECO`.

### Flow 3b: Rework (REPROCESO)

1. Call `mes.crear_reproceso(p_partida_origen_id)` → new child `mes.partida`.
2. Add a TENIDO `partida_paso` and execute as normal.
3. `estado_comercial` stays `'PENDIENTE'` (enforced by `chk_rework_comercial_locked`).
4. No second `PROD_CONSUMO` for the same input rolls.

### Flow 4: Dispatch to Client and Bill

1. Create `doc.entrega` type `DESPACHO_CLIENTE`.
2. Call `doc.registrar_despacho(entrega_id, detalles)` → `SERV_EGR` movements. Stock reaches zero for dispatched lots.
3. Update `partida.estado_comercial → 'ENTREGADA'`.
4. Call `doc.crear_factura(partida_id)` → `borrador` invoice.
5. Adjust line prices/quantities if needed (`actualizar_linea_factura()`).
6. Call `doc.emitir_factura(factura_id)` → `emitida`. `partida.estado_facturacion` updated.

### Flow 5: Inventory Reconciliation (Cuadre)

1. `inventario.crear_cuadre()` → opens count sheet; snapshots all INSUMO items.
2. Operators count physical stock → `inventario.update_cuadre_detalles()`.
3. `inventario.finalizar_cuadre(cuadre_id)`:
   - Deficits → `AJUSTE_NEG` (FIFO lots).
   - Surpluses → new lot + `AJUSTE_POS`.
   - Cuadre → `ejecutado`. Cutoff trigger now blocks earlier postings.

### Flow 6: Approve a Dyeing Recipe

1. `receta.crear_tenido(data)` → recipe in `EN_DESARROLLO`.
2. Add steps and ingredients via `receta.actualizar_tenido()`.
3. `receta.transicionar_tenido(id, 'ENVIADO_CLIENTE')`.
4. After client approval: `receta.transicionar_tenido(id, 'APROBADO')`.
   - Previous APROBADO for same spec → auto-moved to `HISTORICO`.

### Flow 7: Purchase Supplies

1. Create `doc.entrega` type `COMPRA_INGRESO` → `COMPRA_ING` movements → MAP recalculated.
2. `doc.crear_compra()` → PO with line items.
3. `doc.vincular_entregas_compra(compra_id, entrega_ids)`.
4. `doc.registrar_factura_proveedor(data)` → supplier invoice.
5. `doc.registrar_letras(factura_id, letras)` → payment schedule.
6. As payments clear: `doc.pagar_letra(letra_id, fecha_pago)`.

---

## 18. Migration Execution Order

Files must be applied in this exact order to a fresh database:

| Step | File | Creates / Changes |
|------|------|-------------------|
| 01 | `01_extensions_schemas.sql` | `unaccent` extension; schemas (`inventario`, `mes`, `receta`, `doc`, `calidad`, `audit`, `iam`); Supabase storage bucket + policies |
| 02 | `02_enums.sql` | All ENUM types; `public.vw_enums` |
| 03 | `03_base_functions.sql` | Trigger functions (`get_user_id`, code gen, audit, immutability) |
| 04 | `04_alter_legacy_tables.sql` | Alters existing legacy tables (`profiles→usuario`, `tipo_articulo→articulo_tipo`); backfills `codigo` columns |
| 05 | `05_new_tables_foundation.sql` | `unidad`, `item`, `item_*_detalle`, `tercero`, `inventario.*` foundation tables (including `lote_saldo`, `item_saldo`) |
| 06 | `06_receta_tables.sql` | `receta.*` tables; `estado_desarrollo_color` |
| 07 | `07_new_tables_mes_doc_calidad.sql` | `doc.*`, `mes.*`, `calidad.*` tables; `doc.catalogo_precios`, `mes.tiempos_estandar_*` |
| 08 | `08_views.sql` | All views |
| 09 | `09_constraints_audit.sql` | Immutability triggers, hard-delete guards, `audit.data_audit`, REVOKEs, lote sequence trigger, saldo sync trigger |
| 10 | `10_auth.sql` | JWT hook, RLS policies (all tiers), IAM schema seed (roles, permissions, rol_permiso) |
| 11a | `11_data_migration.sql` | Legacy data migration: color hex values, historical data backfill. Long-running; run with `SET statement_timeout = 0`. |
| 11b | `11_permissions_patch.sql` | New `configuracion.operacional` permission; RLS policy corrections for operational catalogs and `receta.*` tables; `produccion.ver` on `mes.partida`. Idempotent. |
| 12 | `12_triggers_audit.sql` | Installs audit INSERT/UPDATE/DELETE triggers and cre/mod/elm triggers. **Must run after step 11a** — running before data migration would corrupt legacy `usr_cre`/`fyh_cre` values. |
| 14 | `14_cuadre_cutoff.sql` | `fn_trg_check_corte_cuadre()` trigger on `item_movimientos` BEFORE INSERT/UPDATE; blocks retroactive postings after a cuadre is executed. |
| 15 | `15_alerts_schema.sql` | Creates `alertas` schema; extends `notification.notifications` with `objeto_tipo`, `objeto_id`, `fyh_resuelta`, `categoria` columns and deduplication index; registers 5 `pg_cron` schedules. Idempotent (unschedules first). |
| 16 | `16_receta_insumo_precision.sql` | Widens `receta.tenido_paso_insumo.cantidad` and `lavado_maquina_paso_insumo.cantidad` from `NUMERIC(8,4)` to `NUMERIC(10,6)` for sub-gram dosages. Drops and recreates the immutability trigger around the ALTER. |
| 17 | `17_maquina_tipo_operacion.sql` | Adds `maquina_tipo.operacion_id FK→mes.operacion`; backfills existing machine type → operation mappings. |
| 18 | `18_ejecucion_operaciones.sql` | Adds 8 operation-specific measurement columns to `partida_paso_ejecucion` (`ancho_entrada/salida`, `velocidad`, `entrada`, `salida`, `rendimiento`, `pases`, `malla_alimentacion`) plus `receta_id` snapshot. Creates `mes.partida_paso_ejecucion_termofijado` extension table. |
| 19a | `19_partida_paso_estado.sql` | Adds stored `estado partida_paso_estado_enum DEFAULT 'PENDIENTE'` column to `mes.partida_paso`; backfills from existing ejecucion rows. |
| 19b | `19_fungible_stock.sql` | Adds `item.flg_fungible BOOLEAN DEFAULT false`; `item_tipo.ubicacion_default_id`; `item_movimiento_tipo.reversal_tipo_id`; updates saldo sync trigger to handle null-null location-agnostic movements; sets all INSUMO items to `flg_fungible = true`. |

**Notes:**
- Steps 11a and 11b share the step-11 prefix but are independent files applied separately. 11a runs first (data), 11b can run at any time after step 10.
- Step 12 must follow 11a to avoid corrupting migrated audit timestamps.
- Steps 14–19 are applied in numeric order; each is idempotent or uses `IF NOT EXISTS` / `IF EXISTS`.
- `14_nuke_partidas_ar505.sql` is a one-time data correction (deletes specific production orders for a client), not part of the standard sequence. Do not run on a fresh database.

**Function files** (`funciones/*.sql`) — applied after all migration steps; re-runnable with `CREATE OR REPLACE`:

| File | Key functions |
|------|--------------|
| `funciones/core.sql` | `public.get_item`, warehouse management |
| `funciones/inventario.sql` | `inventario.crear_cuadre`, `finalizar_cuadre`, `calcular_fifo` |
| `funciones/mes.sql` | Full production execution flow, scheduling, wash management |
| `funciones/receta.sql` | Recipe lifecycle (`crear_tenido`, `transicionar_tenido`, etc.) |
| `funciones/calidad.sql` | QC inspections and defect catalog |
| `funciones/compras.sql` | Procurement: compras, facturas, letras, entrega linkage |
| `funciones/despacho.sql` | `registrar_despacho`, `anular_despacho` |
| `funciones/facturacion.sql` | `crear_factura`, `emitir_factura`, billing state management |
| `funciones/alertas.sql` | Alert infrastructure; `pg_cron` evaluators for overdue letras/facturas and unassigned rolls |

**Utility directories (not run as migrations):**
- `migration/patches/` — targeted data fixes (idempotent; run manually).
- `migration/operations/` — one-time bulk data operations (archived for reference after execution).
- `migration/diagnostics/` — read-only diagnostic queries.
- `migration/legacy_data/` — legacy data migration scripts (applied once during initial migration).

---

*End of manual.*

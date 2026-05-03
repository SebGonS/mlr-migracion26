# MLR Database Schema Manual

**Manufacturas la Real — Supabase/PostgreSQL backend**
Last updated: 2026-03-17

This document is the authoritative reference for all schemas, tables, functions, views, and triggers in the MLR system. It explains *what* each piece does, *why* it exists, and *how* the parts work together.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Schemas](#2-schemas)
3. [Global Design Patterns](#3-global-design-patterns)
4. [Schema: `public` — Master Data](#4-schema-public--master-data)
5. [Schema: `inventario` — Inventory](#5-schema-inventario--inventory)
6. [Schema: `doc` — Commercial Documents](#6-schema-doc--commercial-documents)
7. [Schema: `mes` — Manufacturing Execution](#7-schema-mes--manufacturing-execution)
8. [Schema: `receta` — Recipes](#8-schema-receta--recipes)
9. [Schema: `calidad` — Quality Control](#9-schema-calidad--quality-control)
10. [Schema: `audit` — Audit Trail](#10-schema-audit--audit-trail)
11. [Function Catalog](#11-function-catalog)
12. [Views Reference](#12-views-reference)
13. [Key Business Flows (End-to-End)](#13-key-business-flows-end-to-end)
14. [Migration Execution Order](#14-migration-execution-order)

---

## 1. Architecture Overview

MLR is a textile dyeing/finishing service company. The database models:

- **Client rolls arrive** as raw fabric (crudo) → tracked as inventory lots (`inventario.lote`).
- **Sales orders** (`doc.partida`) capture what the client wants processed (color, type, quantity).
- **Production orders** (`mes.orden_produccion`) are created against those sales orders and pass the rolls through a sequence of operations (dyeing, washing, drying, etc.).
- **Recipes** (`receta.tenido`, `receta.lavado_maquina`) define the chemical steps and ingredients for each operation.
- **Quality inspections** (`calidad.inspeccion`) are recorded per roll after each production step.
- **Inventory movements** (`inventario.item_movimientos`) record every stock change with full traceability.
- **Commercial documents** (guias, facturas, compras) record the paper trail for receiving, dispatching, and billing.

### High-Level Flow

```
CLIENT SENDS ROLLS
      │
      ▼
doc.guia_remision (CLIENTE_ENVIO_partida)
      │  creates inventario.lote per roll
      ▼
doc.partida  ←── partida_detalle (what to process: item × qty)
      │
      ▼
mes.orden_produccion
      │
      ├── mes.orden_produccion_paso  (sequence: TENIDO → LAVADO_HIDRO → SECADO…)
      │         │  each paso may reference receta.tenido or be a standalone op
      │         │
      │         ▼
      │   inventario.pesaje (weighing gate per roll)
      │         │
      │         ▼
      │   calidad.inspeccion  (QC per roll per paso)
      │
      ├── mes.orden_produccion_item  (which specific lotes go into this order)
      │
      └── mes.orden_produccion_paso_item (lote ↔ paso assignment)
              │
              ▼
        inventario.item_movimientos  (all stock in/out)

ROLLS DISPATCHED
      │
      ▼
doc.guia_remision (DESPACHO_CLIENTE)
      │
      ▼
doc.factura  (billing)
```

---

## 2. Schemas

| Schema | Purpose |
|--------|---------|
| `public` | Master data shared across all modules (items, terceros, units, legacy tables) |
| `inventario` | Lot and movement tracking — the stock ledger |
| `doc` | Commercial documents: sales orders, delivery notes, purchase orders, invoices |
| `mes` | Manufacturing Execution System: machines, operations, production orders, scheduling |
| `receta` | Dyeing and machine-wash recipes with chemical step details |
| `calidad` | Quality control inspections, defects, photos |
| `audit` | Immutable row-change audit trail |
| `iam` | Authentication/authorization (roles, user-role assignments) — defined separately |

---

## 3. Global Design Patterns

Understanding these patterns is essential for working with any table in the system.

### 3.1 `codigo` / `codigo_canon`

Every catalog/master table has:
- `codigo` — human-readable code, case-sensitive, set by the user or auto-generated.
- `codigo_canon` — automatically derived from `codigo` via the `fn_trg_set_codigo_canon()` trigger: lowercased and unaccented (uses `unaccent` extension). Used for case-insensitive uniqueness checks.

**Rule:** `codigo` is **immutable once set**. The `fn_trg_immutable_codigo()` trigger enforces this. To rename something, soft-delete it (`flg_elm = true`) and create a new record.

### 3.2 Audit Columns

Present on every writable table:

| Column | Type | Meaning |
|--------|------|---------|
| `usr_cre` | int → usuario.id | Who created the row |
| `fyh_cre` | timestamptz | When it was created |
| `usr_mod` | int → usuario.id | Who last modified it |
| `fyh_mod` | timestamptz | When it was last modified |

Triggers `fn_trg_set_cre_fields()` and `fn_trg_set_mod_fields()` fill these automatically from `get_user_id()`. **Clients cannot write audit columns** — REVOKEs in step 9 prevent this.

`get_user_id()` reads `id_usuario` from the JWT, injected at login by the `custom_access_token_hook`. It costs zero DB queries.

### 3.3 Soft Delete

Tables with `flg_elm` support soft delete:

| Column | Type | Meaning |
|--------|------|---------|
| `flg_elm` | boolean | true = deleted |
| `usr_elm` | int | Who deleted it |
| `fyh_elm` | timestamptz | When it was deleted |

The `fn_trg_set_elm_fields()` trigger auto-fills `usr_elm`/`fyh_elm` when `flg_elm` transitions from false → true.

**Hard deletes are blocked** on `doc.partida`, `doc.guia_remision`, `inventario.lote`, and `mes.orden_produccion` via the `fn_trg_prevent_hard_delete()` trigger. `doc.factura` blocks hard delete only once emitted/annulled.

### 3.4 `doc_movimiento_id` — Posting Events

`inventario.item_movimientos.doc_movimiento_id` groups all movement lines that belong to one **posting event** (analogous to SAP MBLNR / Materialbeleg). Multiple lines from one transaction share the same `doc_movimiento_id`. Generated from the sequence `inventario.mov_doc_seq`.

### 3.5 `documento_tipo` / `documento_id`

A polymorphic FK pattern. Used on `inventario.item_movimientos` and `inventario.lote` to link back to the originating business document without a hard FK:

| `documento_tipo` | `documento_id` | Meaning |
|-----------------|---------------|---------|
| `'COMPRA'` | doc.compra.id | Purchase receipt |
| `'ORDEN_PRODUCCION_PASO'` | mes.orden_produccion_paso.id | Production step output |
| `'CUADRE'` | inventario.cuadre.id | Inventory adjustment |
| `'LAVADO_MAQUINA'` | mes.lavado_maquina.id | Machine wash execution |

### 3.6 Auto-generated Codes

Several tables generate their own `codigo` if none is provided:

| Table | Generator function | Format example |
|-------|--------------------|----------------|
| `mes.maquina` | `fn_trg_gen_codigo_maquina()` | `JET-001` |
| `inventario.ubicacion` | `fn_trg_gen_codigo_ubicacion()` | `INS-01` |
| `color` | `fn_trg_gen_codigo_color()` | `ROJONEGRO` |
| `item` (rollo) | `fn_trg_gen_codigo_item_rollo()` | `R-RB-ART-2-T` |
| `item` (insumo) | `fn_trg_gen_codigo_item_insumo()` | `I-COL-DIR-AZUL-MARINO` |

---

## 4. Schema: `public` — Master Data

### 4.1 Item Model

The `item` table is the **universal product catalog**. Every product — rolls of fabric and chemical supplies — is an `item`. The type is declared via `item_tipo_id`.

```
item
 ├── item_tipo_id → item_tipo  ('ROLLO' | 'INSUMO')
 ├── unidad_id → unidad
 ├── item_rollo_detalle  (1:1, only for ROLLO items)
 └── item_insumo_detalle (1:1, only for INSUMO items)
```

**`item` (core)**

| Column | Notes |
|--------|-------|
| `codigo` | Auto-generated by type-specific triggers; immutable once set |
| `nombre` | Human label |
| `item_tipo_id` | References `item_tipo` |
| `unidad_id` | For ROLLOs = always `kg`. For INSUMOs = `kg`, `L`, etc. |
| `flg_elm` | Soft-delete |

**`item_rollo_detalle`** (1:1 extension for fabric rolls)

| Column | Notes |
|--------|-------|
| `articulo_id` | References the legacy `articulo` table (fabric type/knit structure) |
| `flg_tenido` | true = dyed fabric, false = crudo (raw) |
| `flg_rib` | true = rib variant (e.g. cuffs) |

**`item_insumo_detalle`** (1:1 extension for chemical supplies)

| Column | Notes |
|--------|-------|
| `insumo_tipo_id` | QUIM / COL / AUX |
| `colorante_tipo_id` | DIR / DISP / RX (only for COL type) |
| `medida` | Dose unit enum (g/L, g/kg, mL/L, mL/kg, %) |
| `factor_stock` | Conversion factor for stock reporting |

### 4.2 Units

**`unidad`** — Unit of measure catalog (kg, g, L, mL, UN, etc.)

**`unidad_conversion`** — Conversion factors between units (e.g. kg → g = 1000). Used when calculating recipe doses across units.

### 4.3 Classifier Tables

| Table | Purpose |
|-------|---------|
| `item_tipo` | ROLLO / INSUMO — discriminator for item |
| `insumo_tipo` | QUIM / COL / AUX — chemical supply category |
| `colorante_tipo` | DIR / DISP / RX — dye chemistry type |

### 4.4 `tercero` — Trading Parties

The unified entity for all external parties: clients, suppliers, or both simultaneously.

| Column | Notes |
|--------|-------|
| `codigo` | Short code, immutable |
| `nombre` | Commercial name |
| `razon_social` | Legal registered name |
| `ruc` | 11-digit Peruvian tax ID (SUNAT) |
| `flg_cliente` | This party is a client |
| `flg_proveedor` | This party is a supplier |
| `cliente_id` / `proveedor_id` | Legacy cross-references (to be dropped once legacy tables retire) |

Row `id=1` is always `MLR` (Manufacturas la Real itself).

---

## 5. Schema: `inventario` — Inventory

This schema is the **stock ledger**. All stock movements, lot tracking, valuation, and reconciliation live here.

### 5.1 Location Hierarchy

```
inventario.almacen  (warehouse)
    └── inventario.ubicacion  (bin/location within warehouse)
```

Warehouse codes use the convention `ALM_XXX` (e.g. `ALM_INS` for supplies warehouse, `ALM_CRU` for raw fabric). Location codes are auto-generated as `XXX-01`, `XXX-02`, etc.

### 5.2 `inventario.lote` — Lots

A **lot** is the minimum unit of stock identity. For rolls, **1 lot = 1 physical roll** (indivisible).

| Column | Notes |
|--------|-------|
| `secuencia` | Annual sequence number (auto-generated); displayed as `YY-NNNNN` |
| `item_id` | The item this lot is an instance of |
| `documento_tipo` / `documento_id` | What document created this lot (polymorphic) |
| `cantidad` | Weight in kg (must be > 0) |
| `detalles` | JSONB for ad-hoc attributes (e.g. `color_x_cliente_id`, `ancho`) |
| `estado_calidad` | QC state: PENDIENTE / APROBADO / RECHAZADO / REpartida / CUARENTENA |
| `propietario_id` | References `tercero.id` — the client who owns this material |

The sequence is maintained in `lote_secuencia_anual` (one row per year), incremented by the `trfn_generar_secuencia_lote()` trigger on INSERT.

### 5.3 `inventario.pesaje` — Weighing

Created when a roll is physically weighed on-site. This is the **weighing gate** that must exist before a roll can be consumed in production.

| Column | Notes |
|--------|-------|
| `lote_id` | The roll being weighed (NOT NULL) |
| `orden_produccion_id` | Which production order this weighing belongs to |
| `peso_real` | Actual weight recorded on scale |

### 5.4 `inventario.item_movimiento_tipo` — Movement Type Catalog

Each movement has a type that defines:
- `categoria` — COMPRA / VENTA / PRODUCCION / etc.
- `factor` — +1 (ingress) or -1 (egress)
- `flg_afecta_stock` — whether this moves stock
- `flg_valorizable` — whether this updates the moving average price
- `flg_recalcula_costo` — whether this recalculates the weighted average (true only for purchase receipts)
- `req_partner` / `req_origen` / `req_destino` — validation flags

Key movement type codes:

| Code | Direction | Meaning |
|------|-----------|---------|
| `COMPRA_ING` | + | Purchase receipt (recalculates MAP) |
| `SERV_ING` | + | Client sends material for processing |
| `SERV_EGR` | - | Processed material dispatched to client |
| `PROD_CONSUMO` | - | Chemical consumed in production |
| `PROD_ING` | + | Finished product enters stock |
| `AJUSTE_POS` / `AJUSTE_NEG` | +/- | Physical count adjustment |
| `MUESTRA_ING` / `MUESTRA_EGR` | +/- | Sample movements (non-valorizable) |

### 5.5 `inventario.item_movimientos` — The Stock Ledger

**The single source of truth for all stock.** Never update or delete rows — only append.

| Column | Notes |
|--------|-------|
| `doc_movimiento_id` | Groups all lines of one posting event |
| `item_id` | What moved |
| `lote_id` | Which specific lot |
| `item_movimiento_tipo_id` | Movement type (defines direction/behavior) |
| `origen_ubicacion_id` | Where it came from (NULL for ingress) |
| `destino_ubicacion_id` | Where it went (NULL for egress) |
| `cantidad` | Always positive; direction determined by `factor` on the type |
| `precio_unitario` | Unit price; NULL for non-valorizable movements |
| `monto` | Generated: `cantidad × precio_unitario` |
| `documento_tipo` / `documento_id` | Source document (polymorphic) |

### 5.6 `inventario.item_valoracion` — Moving Average Price (MAP)

One row per item. Maintained automatically by the `trg_ai_item_movimientos_map` trigger on every insert into `item_movimientos`.

| Column | Notes |
|--------|-------|
| `precio_promedio` | Current weighted average cost |
| `stock_qty` | Total qty on hand |
| `stock_valorado` | Total stock value |

**MAP recalculation logic (FIFO-like weighted average):**
- On `flg_recalcula_costo = true` (purchase receipt): new price incorporated into average.
- On egress: stock qty and value decrease at current MAP.
- On other ingress: stock qty increases but price doesn't change.

### 5.7 `inventario.cuadre` — Inventory Reconciliation

A **cuadre** (physical count reconciliation) captures the difference between system stock and physically counted stock.

States: `borrador` → `preparado` → `ejecutado` | `cancelado`

**`inventario.cuadre_detalle`** — one row per item, storing system qty, system MAP, last purchase price, and counted qty.

The `inventario.finalizar_cuadre()` function posts `AJUSTE_NEG` (deficits) and `AJUSTE_POS` (surpluses) movements to close the gap.

---

## 6. Schema: `doc` — Commercial Documents

### 6.1 `doc.partida` — Sales Order (the central document)

The **sales order** is the top-level commercial contract for one job. Everything downstream traces back to it.

| Column | Notes |
|--------|-------|
| `numero` | Human-facing sequential number |
| `tercero_id` | The client |
| `tenido_id` | Legacy tenido reference (dyeing type) |
| `color_x_cliente_id` | The specific color specification for this client |
| `malla` / `rendimiento` / `ancho` | Fabric specs |
| `flg_antipilling` | Whether antipilling process is required |
| `fecha_acordada` | Agreed delivery date |
| `estado` | `partida_estado_enum`: CREADA → CONFIRMADA → EN_PRODUCCION → ENTREGADA → FACTURADA → CERRADA |
| `estado_facturacion` | `partida_facturacion_enum`: pendiente / parcial / facturado (billing axis, independent of production state) |

**`doc.partida_detalle`** — Intent lines. One row per item type requested in the order.

| Column | Notes |
|--------|-------|
| `item_id` | References `item` (a ROLLO item type) |
| `cantidad` | Roll count requested |
| `unidad_id` | Unit (rolls) |

**Key rule:** `partida_detalle` is **pure intent/demand**. It has no `lote_id` — specific lots are assigned in `mes.orden_produccion_item` at execution time.

### 6.2 `doc.guia_remision` — Delivery Notes

Physical transport documents (guias de remisión). Direction (inbound/outbound) determined by `guia_remision_tipo.flg_emitida`:
- `flg_emitida = false` → MLR receives (inbound: purchases, client material arrivals)
- `flg_emitida = true` → MLR issues (outbound: dispatches, sales)

**`doc.guia_remision_tipo`** — catalog of guia types:

| Code | Direction | Meaning |
|------|-----------|---------|
| `COMPRA_INGRESO` | In | Inbound purchase of supplies |
| `CLIENTE_ENVIO_partida` | In | Client sends rolls for processing |
| `DESPACHO_CLIENTE` | Out | Processed rolls returned to client |
| `VENTA_EGRESO` | Out | Product sold to client |
| `DEVOLUCION_CLIENTE_CRUDO` | Out | Raw rolls returned to client (unprocessed) |
| `DEVOLUCION_PROVEEDOR` | Out | Returns to supplier |
| `DEVOLUCION_CLIENTE_VENTA` | In | Client returns sold product |
| `DEVOLUCION_CLIENTE_SERVICIO` | In | Client returns processed material |

Each `guia_remision_tipo` links to an `inventario.item_movimiento_tipo` so that inventory movements are automatically classified.

**`doc.guia_remision_detalle`** — line items on the delivery note. One row per roll. Has `lote_id` — lots are created at guia insertion time for inbound guias.

### 6.3 `doc.compra` — Purchase Record

Groups the purchase event. Links to:
- `doc.compra_detalle` — what was purchased (item × qty × price)
- `doc.compra_guia_remision` — which inbound guias cover this purchase
- `doc.factura_proveedor` — the supplier invoice

Inventory movements for a purchase are posted via the guia, not the compra directly.

### 6.4 `doc.factura_proveedor` — Supplier Invoice

| Column | Notes |
|--------|-------|
| `serie` / `numero` | SUNAT document number |
| `tipo_pago` | al contado / credito |
| `estado_pago` | pendiente / parcial / total / anulado |
| `moneda` | USD (default) or PEN |
| `tipo_cambio` | Exchange rate (required for USD) |

**`doc.letra`** — payment drafts (letras de cambio) linked to a supplier invoice. States: emitida → pagada / vencida / protestada / anulada.

### 6.5 `doc.factura` — Customer Invoice

Emitted customer invoices (SUNAT facturas, boletas, notas de crédito/débito).

| Column | Notes |
|--------|-------|
| `tipo_comprobante` | 01=Factura, 03=Boleta, 07=Nota Crédito, 08=Nota Débito |
| `serie` / `numero` | e.g. F001-0001 |
| `tercero_id` | The client being billed |
| `estado` | borrador → emitida → anulada |
| `factura_origen_id` | For notas de crédito/débito: the original invoice |

**`doc.factura_detalle`** — billing lines.

| Column | Notes |
|--------|-------|
| `partida_id` | Links billing back to the sales order |
| `cantidad` × `precio_unitario` | Line qty and price |
| `igv_porcentaje` | 18% standard, 0% for exports |
| `subtotal_linea` / `igv_linea` / `total_linea` | Generated stored columns (no rounding drift) |

---

## 7. Schema: `mes` — Manufacturing Execution

### 7.1 Machine Infrastructure

**`mes.maquina_tipo`** — machine categories (e.g. JIGGER, JET, RAMA).

**`mes.maquina`** — individual machines.

| Column | Notes |
|--------|-------|
| `codigo` | Auto-generated as `{tipo}-NNN` if not provided |
| `estado_actual` | `maquina_estado_enum`: activa / espera / configuracion / averia / mantenimiento |
| `capacidad_min_kg` / `capacidad_max_kg` | Load range for scheduling |
| `relacion_bano` | Bath ratio (water:fabric ratio for dyeing) |

**`mes.operacion`** — macro process steps (TENIDO, LAVADO_HIDRO, SECADO, etc.). Not to be confused with `receta.operacion` which is micro-chemistry steps.

| Column | Notes |
|--------|-------|
| `requiere_receta` | true = a receta.tenido must be assigned to this paso |
| `requiere_maquina` | true = a maquina must be assigned |

**`mes.empleado_rol`** / **`mes.empleado`** — workforce. Employees are linked to turno (shift) and rol.

**`mes.ruta_plantilla`** / **`mes.ruta_plantilla_detalle`** — reusable production route templates. A template is a sequence of operations (with standard time/pH/temp) that can be copied onto a new production order.

### 7.2 Production Order Hierarchy

```
doc.partida
    └── mes.orden_produccion  (one per job, can be NORMAL/REpartida/AJUSTE)
            ├── mes.orden_produccion_paso  (one per process step: TENIDO, LAVADO, etc.)
            │       └── mes.orden_produccion_paso_item  (which lot goes through this paso)
            └── mes.orden_produccion_item  (which physical lots are assigned to this order)
```

**`mes.orden_produccion`**

| Column | Notes |
|--------|-------|
| `partida_id` | Parent sales order |
| `tipo` | NORMAL / REpartida / AJUSTE |
| `orden_origen_id` | Self-FK: for REpartida, which original order this reprocesses |
| `estado` | Full lifecycle enum (see below) |

States: `CREADA → PLANIFICADA → PROGRAMADA → LIBERADA → EN_partida → PAUSADA → FINALIZADA → TECO → CERRADA` | `CANCELADA`

**`mes.orden_produccion_paso`** — one step in the production sequence.

| Column | Notes |
|--------|-------|
| `secuencia` | Order within the production order |
| `operacion_id` | What type of step this is |
| `maquina_asignada_id` | Which machine runs this step |
| `receta_id` | References `receta.tenido` (only when `operacion.requiere_receta = true`) |
| `estado` | PENDIENTE → EN_partida → COMPLETADO | OMITIDO |
| `flg_genera_produccion` | true = this paso generates output lots (inventory ingress) |
| `fyh_inicio` / `fyh_fin` | Actual start/end timestamps |

**`mes.orden_produccion_item`** — maps physical lots to a production order. The specific rolls assigned to process.

**`mes.orden_produccion_paso_item`** — maps specific lots to a specific step within the order.

### 7.3 Scheduling Board

**`mes.programacion`** — machine-centric daily schedule.

| Column | Notes |
|--------|-------|
| `actividad_tipo` | `'ORDEN_PRODUCCION_PASO'` or `'LAVADO_MAQUINA'` |
| `actividad_id` | FK to the corresponding entity (polymorphic) |
| `maquina_id` | Which machine |
| `fecha` | Date of the slot |
| `secuencia` | Order within that machine's day |

UNIQUE constraint `(maquina_id, fecha, secuencia)` prevents double-booking.

### 7.4 Machine Wash

Machine washes are **standalone activities** (not attached to a production order).

**`mes.lavado_maquina`** — one wash execution event.

| Column | Notes |
|--------|-------|
| `receta_id` | References `receta.lavado_maquina` |
| `maquina_id` | Which machine is being washed |
| `estado` | PENDIENTE → EN_partida → COMPLETADO | OMITIDO |

Chemical consumption during a wash is posted to `inventario.item_movimientos` with `documento_tipo = 'LAVADO_MAQUINA'`.

---

## 8. Schema: `receta` — Recipes

### 8.1 Why Two Recipe Tables

There are two separate, non-unified recipe headers:

| Table | Used by | Keyed by |
|-------|---------|---------|
| `receta.tenido` | `mes.orden_produccion_paso` | color × articulo_tipo × fibra × tenido × antipilling |
| `receta.lavado_maquina` | `mes.lavado_maquina` | machine type × from-value × to-value transition |

They are intentionally separate because they have different domain attributes and different consumers. Do not unify them.

### 8.2 `receta.operacion` — Chemistry Operations Catalog

Micro-level steps within a recipe (TINTURA, LAVADO, NEUTRALIZADO, SUAVIZADO, etc.). **Not the same as `mes.operacion`** (which are macro production steps). These are the within-step chemistry actions.

### 8.3 `receta.tenido` — Dyeing Recipe

One recipe per (color × fabric-type × fiber × dyeing-method × antipilling) combination.

| Column | Notes |
|--------|-------|
| `color_x_cliente_id` | The client's specific color spec |
| `articulo_tipo_id` | Fabric knit type |
| `fibra` | Fiber composition code |
| `tenido_id` | Legacy dyeing method reference |
| `flg_antipilling` | Whether this version includes antipilling |
| `estado_id` | Development state (see below) |
| `flg_produccion` | Auto-maintained by trigger: true only when estado = APROBADO |

Development states: `INGRESADO → EN_DESARROLLO → ENVIADO_CLIENTE → APROBADO | RECHAZADO | CANCELADO | RE_LAB → HISTORICO`

**Only one APROBADO recipe per spec can exist at a time.** Enforced by a partial unique index on `flg_produccion = true`. When a new recipe is approved, the existing APROBADO is automatically moved to HISTORICO by `receta.transicionar_tenido()`.

### 8.4 Recipe Steps

```
receta.tenido
    └── receta.tenido_paso  (ordered steps: TINTURA, LAVADO, NEUTRALIZADO…)
            └── receta.tenido_paso_insumo  (chemical × quantity per step)

receta.lavado_maquina
    └── receta.lavado_maquina_paso
            └── receta.lavado_maquina_paso_insumo
```

**`receta.tenido_paso`**

| Column | Notes |
|--------|-------|
| `receta_id` | Parent recipe |
| `operacion_id` | Chemistry operation (from `receta.operacion`) |
| `orden` | Step sequence |
| `ph` / `temperatura` / `tiempo_min` | Process parameters |

**`receta.tenido_paso_insumo`**

| Column | Notes |
|--------|-------|
| `paso_id` | Parent step |
| `item_id` | The chemical item to use |
| `cantidad` | Dose amount |
| `orden` | Display order |

**Immutability rule:** A `receta.lavado_maquina` recipe cannot be edited once it has completed executions (`trg_bu_lavado_maquina_immutable`).

---

## 9. Schema: `calidad` — Quality Control

### 9.1 `calidad.inspeccion` — QC Inspection

One inspection per roll per production step.

| Column | Notes |
|--------|-------|
| `lote_id` | The roll being inspected |
| `orden_produccion_paso_id` | Which step generated this roll |
| `resultado` | calidad_estado_enum: PENDIENTE / APROBADO / RECHAZADO / REpartida / CUARENTENA |
| `empleado_id` | Who performed the inspection |

Creating an inspection also **updates `inventario.lote.estado_calidad`** to match the result.

### 9.2 Defects and Photos

```
calidad.inspeccion
    └── calidad.inspeccion_defecto  (one per defect found)
            └── calidad.inspeccion_foto  (photos stored in Supabase Storage bucket 'calidad')
```

**`calidad.tipo_defecto`** — defect catalog with severity (1=minor, 3=critical):

LINEA, MANCHA, HUECO, HILO_ROTO, CAIDA_MALLA, BARRADO, TONO_DESIGUAL, PILLING, PESO_FUERA_SPEC, ANCHO_FUERA_SPEC, ENCOGIMIENTO, ARRUGA, ORILLO_DEFECTUOSO, etc.

---

## 10. Schema: `audit` — Audit Trail

### 10.1 `audit.data_audit`

Immutable log of every INSERT/UPDATE/DELETE on audited tables.

| Column | Notes |
|--------|-------|
| `schema_name` / `table_name` | What was changed |
| `row_id` | The row's `id` |
| `operacion` | INSERT / UPDATE / DELETE |
| `old_data` / `new_data` | Full row snapshots as JSONB |
| `usr_id` | Who made the change (from JWT) |

Populated by the `audit.fn_audit_row()` trigger, which is attached to all high-value tables.

**Which tables have full audit (INSERT+UPDATE+DELETE):**
`tercero`, `doc.partida`, `doc.partida_detalle`, `doc.guia_remision`, `doc.guia_remision_detalle`, `mes.ruta_plantilla`, `mes.ruta_plantilla_detalle`, `mes.orden_produccion_paso`, `doc.factura_proveedor`, `doc.compra`, `doc.letra`, `doc.factura`

---

## 11. Function Catalog

All functions use `SECURITY DEFINER` and explicit `SET search_path` to prevent search-path injection.

### 11.1 Core / Identity

| Function | Signature | Description |
|----------|-----------|-------------|
| `public.get_user_id()` | `() → int` | Returns `id_usuario` from JWT. Zero DB cost. |

### 11.2 Trigger Functions (not called directly)

| Function | Fires on | Description |
|----------|----------|-------------|
| `fn_trg_set_codigo_canon()` | BEFORE INSERT/UPDATE | Sets `codigo_canon = lower(unaccent(codigo))` |
| `fn_trg_set_cre_fields()` | BEFORE INSERT | Sets `usr_cre`, `fyh_cre` from JWT |
| `fn_trg_set_mod_fields()` | BEFORE UPDATE | Sets `usr_mod`, `fyh_mod`; preserves `usr_cre`/`fyh_cre` |
| `fn_trg_set_elm_fields()` | BEFORE UPDATE | Sets `usr_elm`, `fyh_elm` when `flg_elm` → true |
| `fn_trg_immutable_codigo()` | BEFORE UPDATE | Raises exception if `codigo` changes |
| `fn_trg_prevent_hard_delete()` | BEFORE DELETE | Raises exception on delete |
| `inventario.fn_trg_actualizar_map()` | AFTER INSERT on item_movimientos | Updates moving average price in `item_valoracion` |
| `inventario.trfn_generar_secuencia_lote()` | BEFORE INSERT on lote | Auto-increments annual lot sequence |
| `mes.fn_trg_gen_codigo_maquina()` | BEFORE INSERT on maquina | Generates `codigo` if null |
| `inventario.fn_trg_gen_codigo_ubicacion()` | BEFORE INSERT on ubicacion | Generates `codigo` if null |
| `fn_trg_gen_codigo_item_rollo()` | AFTER INSERT on item_rollo_detalle | Sets `item.codigo` for roll items |
| `fn_trg_gen_codigo_item_insumo()` | AFTER INSERT on item_insumo_detalle | Sets `item.codigo` for supply items |
| `fn_trg_receta_tenido_flg_produccion()` | BEFORE INSERT/UPDATE on receta.tenido | Maintains `flg_produccion = (estado = APROBADO)` |
| `receta.fn_trg_lavado_maquina_immutable()` | BEFORE UPDATE on receta.lavado_maquina | Blocks edit if completed executions exist |
| `audit.fn_audit_row()` | BEFORE INSERT/UPDATE/DELETE | Writes row snapshot to `audit.data_audit` |

### 11.3 Inventory Functions

| Function | Description |
|----------|-------------|
| `inventario.crear_cuadre()` → BIGINT | Creates a new inventory count sheet. Snapshots all INSUMO items (including zero-stock) into `cuadre_detalle`. Returns the new `cuadre_id`. |
| `inventario.get_cuadre(p_cuadre_id)` → JSONB | Returns full cuadre header + all detail lines as a JSONB object. |
| `inventario.update_cuadre_detalles(p_json)` | Bulk-updates `cantidad_contada` on cuadre detail rows. Input: `[{id, cantidad_contada}, ...]` |
| `inventario.finalizar_cuadre(p_cuadre_id)` → JSONB | Validates all items counted, then posts `AJUSTE_NEG` (deficits via FIFO) and `AJUSTE_POS` (surpluses, new lot per item) movements. Closes the cuadre as `ejecutado`. |
| `inventario.get_item_movimientos_cuadre(p_item_id, p_cuadre_id)` → JSONB | Returns movement history for one item between the previous cuadre close and this cuadre's snapshot date. |

### 11.4 MES Functions (funciones/mes.sql)

The mes.sql file contains the core manufacturing execution functions:

| Function | Description |
|----------|-------------|
| `mes.get_programacion_diaria(p_fecha)` → JSONB | Returns the full daily scheduling board for all machines on a given date. Includes both `ORDEN_PRODUCCION_PASO` and `LAVADO_MAQUINA` activities. |
| `mes.get_actividades_sin_programar()` → JSONB | Returns all unscheduled activities (both production steps and wash jobs) in a unified list. |
| `mes.get_pasos_sin_programar()` → JSONB | Backward-compat version returning only unscheduled production steps. |
| `mes.calcular_fifo(p_items JSONB)` → JSONB | Internal FIFO resolver. Given `[{item_id, cantidad}, ...]`, resolves which specific lots to consume in FIFO order. Returns `[{item_id, lote_id, ubicacion_id, cantidad}, ...]`. Used by `finalizar_cuadre` and production consumption. |
| `mes.iniciar_lavado(...)` | Starts a machine wash execution: sets estado = EN_partida, records fyh_inicio. |
| `mes.finalizar_lavado(...)` | Completes a machine wash: sets estado = COMPLETADO, records fyh_fin, posts chemical consumption movements. |

### 11.5 Recipe Functions

| Function | Description |
|----------|-------------|
| `receta.crear_tenido(p_color_x_cliente_id, p_articulo_tipo_id, p_fibra, p_tenido_id, ...)` → INT | Creates a new dyeing recipe in EN_DESARROLLO state. Steps/insumos are added separately via direct INSERT (guarded by estado check). Returns new `receta.tenido.id`. |
| `receta.transicionar_tenido(p_receta_id, p_estado_codigo)` | Transitions a recipe to a new state. On APROBADO: atomically moves any existing approved recipe for the same spec to HISTORICO first. |

### 11.6 Quality Functions

| Function | Description |
|----------|-------------|
| `calidad.crear_inspeccion(p_inspeccion JSONB)` → JSONB | Creates an inspection with nested defects and photos in one call. Updates `inventario.lote.estado_calidad`. Sends notifications to `jefe_planta` and `calidad` role users. Returns `{inspeccion_id, defecto_ids, message}`. |
| `calidad.get_inspeccion(p_inspeccion_id)` → JSONB | Returns full inspection with nested defects (sorted by severity) and their photos. |

### 11.7 Core Item Functions

| Function | Description |
|----------|-------------|
| `public.get_item(p_item_id)` → JSONB | Returns full item detail including type-specific extension (rollo or insumo details). |

### 11.8 Purchase Functions

| Function | Description |
|----------|-------------|
| `doc.crear_compra(p_datos JSONB)` → BIGINT | Creates a purchase record with line items and optional guia links. Validates guias belong to the declared supplier. Returns `compra_id`. |
| `doc.registrar_factura_proveedor(p_datos JSONB)` → BIGINT | Creates a supplier invoice. Validates subtotal+IGV=total. Requires `tipo_cambio` for USD invoices. Optionally links to an existing compra. |
| `doc.registrar_letras(p_factura_proveedor_id, p_letras JSONB)` → text | Idempotent: replaces pending letras for a factura with a new set. Validates total ≤ factura total. Marks factura as `tipo_pago = credito`. |
| `doc.pagar_letra(p_letra_id, p_fecha_pago)` → text | Marks a letra as pagada. Cascades `estado_pago` on the parent factura: all paid → total, some paid → parcial. |
| `doc.vincular_guias_compra(p_compra_id, p_guia_ids JSONB)` → text | Links guias to a compra. Validates same proveedor. Idempotent. |
| `doc.vincular_factura_compra(p_compra_id, p_factura_id)` → text | Links a factura_proveedor to a compra. Validates same proveedor. |

---

## 12. Views Reference

### `inventario` schema

| View | Description |
|------|-------------|
| `vw_stock_actual` | Current positive stock by lote/item/ubicacion. Foundation for all stock views. Filters `SUM(cantidad × factor) > 0`. |
| `vw_stock_general` | Aggregated stock by item (all types), total qty. |
| `vw_stock_rollos` | Roll stock with full fabric detail: articulo, color, tono, client, partida, antipilling. |
| `vw_stock_insumos` | Supply stock with insumo_tipo and colorante_tipo details. |
| `vw_lotes_disponibles` | All available lots with item info and lote code. |
| `vw_lotes_rollos_stock` | Detailed roll lots with location, weight, width, color, owner. |
| `vw_lotes_rollos_despachados` | Rolls that have been dispatched (SERV_EGR) and are no longer in stock. |
| `vw_items_movimientos` | Movement history with human-readable labels (item code, lot code, location names, type name). |
| `vw_item_proveedor_guia` | Items × suppliers derived from inbound guias. Used for purchase history. |
| `vw_cuadre` | Cuadre headers with the previous closed cuadre date (used for movement window calculation). |
| `vw_item_movimiento_categoria` | Readable labels for the movement category enum. |

### `doc` schema

| View | Description |
|------|-------------|
| `vw_partidas_lista_comercial` | Sales order list view for the commercial/admin UI. Aggregates totals (roll count, rib vs regular), days since creation, whether production orders exist. |
| `vw_compras` | Purchase list view with aggregated line totals, guia count, letter totals and payment status. |
| `partida_resumen_tenido` | Per-partida summary of rolls by articulo type: total, regular, rib counts. |

### `mes` schema

| View | Description |
|------|-------------|
| `vw_ordenes_produccion` | Production order list with step progress stats (total/completed/in-process/pending), material totals, duration. |
| `vw_pasos` | Production step details including operation, machine, step state, start/end times. |
| `vw_maquinas` | Machines with their type details. |
| `vw_partida_produccion_rollos` | Roll output count per sales order per item type (from completed production). |

### `calidad` schema

| View | Description |
|------|-------------|
| `vw_lotes_pendientes_inspeccion` | Rolls awaiting QC inspection (estado_calidad = PENDIENTE, from production steps). |
| `vw_inspecciones` | Inspection list with item/lot/employee details. |

### `public` schema

| View | Description |
|------|-------------|
| `vw_items` | Items with type and unit codes joined in. |
| `vw_colores` | Colors with client/tono info (legacy joins). |

---

## 13. Key Business Flows (End-to-End)

### Flow 1: Client Sends Rolls for Processing

1. Client arrives with rolls.
2. Create `doc.guia_remision` type `CLIENTE_ENVIO_partida`.
3. Add one `doc.guia_remision_detalle` row per roll, each with a new `inventario.lote`.
4. An `inventario.item_movimientos` row (type `SERV_ING`) is posted for each roll.
5. Rolls are now in stock with `propietario_id = client's tercero.id`.

### Flow 2: Create a Sales Order (Partida)

1. Create `doc.partida` with the client, color spec, and process requirements.
2. Add `doc.partida_detalle` rows declaring how many rolls of each item type.
3. Partida estado = `CREADA`.

### Flow 3: Create and Execute a Production Order

1. Create `mes.orden_produccion` linked to the partida.
2. Add `mes.orden_produccion_paso` rows in sequence (e.g. TERMOFIJADO → TENIDO → LAVADO_HIDRO → SECADO).
3. Assign the recipe (`receta.tenido`) to dyeing steps.
4. Add `mes.orden_produccion_item` rows: which specific lots go into this order.
5. Schedule: create `mes.programacion` rows mapping pasos to machines and dates.
6. Weigh rolls: create `inventario.pesaje` rows (one per roll). This is the weighing gate.
7. Execute each step (update `orden_produccion_paso.estado` to EN_partida → COMPLETADO).
8. For steps with `flg_genera_produccion = true`: create output lots and post `PROD_ING` movements.
9. QC: call `calidad.crear_inspeccion()` for each roll after each relevant step.

### Flow 4: Dispatch Processed Rolls to Client

1. Create `doc.guia_remision` type `DESPACHO_CLIENTE`.
2. Add one `guia_remision_detalle` per roll with its `lote_id`.
3. Post `SERV_EGR` movement for each roll. Stock reaches zero for those lots.
4. Rolls now appear in `vw_lotes_rollos_despachados`.

### Flow 5: Inventory Reconciliation (Cuadre)

1. Call `inventario.crear_cuadre()` → gets a `cuadre_id`. All INSUMO items are snapshotted.
2. Operators count physical stock. Call `inventario.update_cuadre_detalles()` with counted quantities.
3. Call `inventario.finalizar_cuadre(cuadre_id)`:
   - Deficits → `AJUSTE_NEG` movements (FIFO lot selection).
   - Surpluses → new lot + `AJUSTE_POS` movement per item.
   - Cuadre closes as `ejecutado`.

### Flow 6: Approve a Dyeing Recipe

1. Call `receta.crear_tenido()` → new recipe in EN_DESARROLLO.
2. Insert steps into `receta.tenido_paso` and `receta.tenido_paso_insumo`.
3. Call `receta.transicionar_tenido(id, 'ENVIADO_CLIENTE')`.
4. After client approval: call `receta.transicionar_tenido(id, 'APROBADO')`.
   - Any existing approved recipe for the same spec is auto-moved to HISTORICO.

### Flow 7: Purchase Supplies

1. Create `doc.guia_remision` type `COMPRA_INGRESO` (inbound from supplier).
2. Add `guia_remision_detalle` rows (insumo items with quantities). This creates lots and `COMPRA_ING` movements, updating the MAP.
3. Call `doc.crear_compra()` to create the purchase record with line items.
4. Link the guia to the compra: `doc.vincular_guias_compra()`.
5. Register the supplier invoice: `doc.registrar_factura_proveedor()`.
6. If paying by installments: `doc.registrar_letras()`, then `doc.pagar_letra()` as each payment clears.

---

## 14. Migration Execution Order

Files must be applied in this exact order to a fresh database:

| Step | File | What it creates |
|------|------|----------------|
| 01 | `01_extensions_schemas.sql` | `unaccent` extension; schemas; storage bucket + policies |
| 02 | `02_enums.sql` | All ENUM types |
| 03 | `03_base_functions.sql` | Trigger functions (canon code, audit, code gen) |
| 04 | `04_alter_legacy_tables.sql` | Alters existing legacy tables |
| 05 | `05_new_tables_foundation.sql` | `unidad`, `item`, `tercero`, `inventario.*` foundation |
| 06 | `06_receta_tables.sql` | `receta.*` tables |
| 07 | `07_new_tables_mes_doc_calidad.sql` | `doc.*`, `mes.*`, `calidad.*` tables |
| 08 | `08_views.sql` | All views |
| 09 | `09_constraints_audit.sql` | Immutability triggers, hard-delete guards, `audit.data_audit`, REVOKEs, lote sequence trigger |
| 10 | `10_auth.sql` | JWT hook, RLS policies |
| 11 | `11_data_migration.sql` | Migrates data from legacy tables |
| 12 | `12_triggers_audit.sql` | Audit INSERT/UPDATE triggers (must run AFTER data migration) |

**Function files** (`funciones/*.sql`) are applied after all migration steps. They can be re-run (all use `CREATE OR REPLACE`):

| File | Functions |
|------|-----------|
| `funciones/core.sql` | `public.get_item()` and related item query functions |
| `funciones/inventario.sql` | `inventario.crear_cuadre`, `get_cuadre`, `update_cuadre_detalles`, `finalizar_cuadre`, `get_item_movimientos_cuadre` |
| `funciones/mes.sql` | `mes.get_programacion_diaria`, `calcular_fifo`, `get_actividades_sin_programar`, `iniciar_lavado`, `finalizar_lavado` |
| `funciones/receta.sql` | `receta.crear_tenido`, `receta.transicionar_tenido` |
| `funciones/calidad.sql` | `calidad.crear_inspeccion`, `calidad.get_inspeccion` |
| `funciones/compras.sql` | `doc.crear_compra`, `registrar_factura_proveedor`, `registrar_letras`, `pagar_letra`, `vincular_guias_compra`, `vincular_factura_compra` |

---

*End of manual.*

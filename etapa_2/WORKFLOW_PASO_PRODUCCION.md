# MES - Production Step (Paso) Workflow Specification

## Overview

This document defines the frontend/backend contract for the production step lifecycle in the MES module. It covers roll assignment, recipe generation, step execution, material consumption, and production output registration.

---

## Step Lifecycle

```
PENDIENTE ──→ EN_PROCESO ──→ COMPLETADO
                              (or OMITIDO)
```

---

## 0. Planning Phase (while PENDIENTE)

Before a step can be started, two things must happen:

### Roll Assignment

Rolls must be assigned to the step via `registrar_items_procesados(paso_id, items[])`. This populates `orden_produccion_paso_item` — one row per roll (1 lot = 1 roll).

This is required before `generar_receta` can work, since the recipe calculation depends on total weight and roll count.

```
POST → registrar_items_procesados(paso_id, [
  { "orden_produccion_item_id": 10 },
  { "orden_produccion_item_id": 11 },
  ...
])
```

Rolls can be added/removed freely while the paso is PENDIENTE.

### Recipe Generation & Printing

For operations that require a recipe (`operacion.requiere_receta = true`):

```
POST → generar_receta(paso_id) → returns JSONB
```

`generar_receta` always generates live from current data:
- Reads recipe formula from `receta_x_insumo` (locked, cannot be edited once assigned)
- Reads roll count and weight from `orden_produccion_paso_item` + `inventario.lote`
- Calculates volume, chemical quantities based on current machine, RB, peso, roll count
- Returns a JSONB with full metadata header (peso, cantidad, volumen, maquina, etc.)

**The metadata header IS the validation mechanism.** The printed recipe shows the peso/rollos/volumen it was calculated for. If the operator sees a mismatch with reality (e.g., paper says 10 rolls but only 8 are present), they reprint.

**No snapshot is stored.** Since all recipe inputs are frozen once the step enters EN_PROCESO (recipe tables are locked, paso params/rolls can't be edited), `generar_receta` is deterministic after start — it will always produce the same output.

---

## 1. `iniciar_paso(paso_id, datos)`

**Trigger**: Operator clicks "Iniciar" on a pending step.

**Prerequisite**: If `operacion.requiere_receta = true`, rolls must be assigned to the step first.

**Backend behavior**:
- Validates `estado = 'PENDIENTE'`
- Validates all previous pasos (by secuencia) are COMPLETADO/OMITIDO
- Sets `estado = 'EN_PROCESO'`, `fyh_inicio = NOW()`
- Optionally assigns `empleado_id`, `maquina_asignada_id` from `p_datos`
- Auto-starts parent `orden_produccion` if still in CREADA/PLANIFICADA/PROGRAMADA/LIBERADA
- Updates machine state to `'activa'` if assigned
- Sends notification to `jefe_planta` / `supervisor_produccion`

**`p_datos` schema**:
```json
{
  "empleado_id": 5,
  "maquina_asignada_id": 12
}
```

**After this point**: paso parameters, roll assignments, and recipe data are effectively frozen (state checks prevent edits on EN_PROCESO steps).

---

## 2. During `EN_PROCESO`

While the step is in process, the operator MAY:

- **Update items processed** (`registrar_items_procesados`): Adjust roll tracking if needed 
---

## 3. `finalizar_paso(paso_id, datos)` — Main workflow event

**Trigger**: Operator clicks "Finalizar" on an in-process step.

**This is where consumption happens.** The frontend must orchestrate a confirmation screen BEFORE calling `finalizar_paso`.

### Frontend Flow (before calling backend):

```
Operator clicks "Finalizar"
         |
         v
+--------------------------------------------------+
|  Finalizar Paso: TENIDO (#42)                    |
|                                                  |
|  -- Consumos de Receta ----------------------    |
|  (from generar_receta output -> insumos array)   |
|                                                  |
|  Item              Sugerido   Actual             |
|  Colorante Rojo    2.50 kg    [2.50 kg]          |
|  Auxiliar pH       0.30 L     [0.30 L ]          |
|  Dispersante       1.00 kg    [1.00 kg]          |
|                                                  |
|  -- Consumos Adicionales (no receta) ----------  |
|  + [Agregar item]                                |
|                                                  |
|  [Confirmar y Finalizar]                         |
+--------------------------------------------------+
```

### How to populate recipe consumptions

1. Call `generar_receta(paso_id)` — returns full JSONB including `insumos` array
2. Each insumo has `insumo_id` (item_id), `insumo` (name), `cantidad_requerida_kg` (calculated amount)
3. Display as editable form pre-filled with `cantidad_requerida_kg`
4. Operator confirms or adjusts each quantity
5. Operator may add non-recipe items (manual consumption)

### Lot/Location Resolution: FIFO (automatic, no user selection)

All consumptions use FIFO (oldest lot first). The operator only provides `item_id` + `cantidad`. Lot and location are resolved by `mes.calcular_fifo()` inside `registrar_consumo_paso`.

If a single lot doesn't have enough stock, FIFO splits across multiple lots automatically.

### `p_datos` schema for `finalizar_paso`:

```json
{
  "consumos": [
    {
      "item_id": 101,
      "cantidad": 2.50,
      "observacion": null
    },
    {
      "item_id": 204,
      "cantidad": 0.80,
      "observacion": "Adicion extra por correccion pH"
    }
  ]
}
```

- `consumos`: Array of ALL confirmed consumptions (recipe + manual). Only `item_id` and `cantidad` required; lot/location resolved via FIFO by the backend (`calcular_fifo`). Each item becomes `inventario.item_movimientos` records with type `PROD_CONSUMO`.

### Backend behavior of `finalizar_paso`:

1. Validate `estado = 'EN_PROCESO'`
2. If `p_datos->'consumos'` exists → call `registrar_consumo_paso(paso_id, consumos)` (validates stock, resolves FIFO, creates PROD_CONSUMO movements) — **same transaction**
3. Set `estado = 'COMPLETADO'`, `fyh_fin = NOW()`
4. Release machine → set `maquina.estado_actual = 'espera'`
5. Check if ALL pasos in the orden are COMPLETADO/OMITIDO → auto-finalize orden
6. Send notification

If a step has no consumptions (e.g., SECADO, PLANCHADO), omit `consumos` from `p_datos` — `finalizar_paso` works exactly as before.

---

## 4. `registrar_produccion(orden_paso_id, output)` — Production Output

**Trigger**: On the final step (`flg_genera_produccion = true`), register finished product.

**Allowed states**: `EN_PROCESO` or `COMPLETADO` (can register output after step finishes).

**Backend behavior**:
- Validates paso is `flg_genera_produccion = true` and in allowed state
- Validates quantities don't exceed `partida_detalle` planned amounts
- Creates new `inventario.lote` records (finished product)
- Creates `PROD_ING` inventory movements (stock ingress)
- Sends notification to `jefe_planta` / `calidad`

```json
{
  "output": [
    { "item_id": 5, "cantidad": 45.2, "ubicacion_id": 3 },
    { "item_id": 6, "cantidad": 38.7, "ubicacion_id": 3 }
  ]
}
```

---

## 5. After `COMPLETADO` — Corrections

`registrar_items_procesados` is allowed on steps in `PENDIENTE`, `EN_PROCESO`, and `COMPLETADO` states:
- PENDIENTE: Planning — assign rolls before recipe generation
- EN_PROCESO: Execution — track items being processed
- COMPLETADO: Corrections — QC adjustments, forgotten registrations

The existing `ON CONFLICT DO UPDATE` handles upserts cleanly. Audit columns (`usr_mod`, `fyh_mod`) track all changes.

---

## Table Reference

### Key tables involved

| Table | Purpose |
|-------|---------|
| `mes.orden_produccion` | Production order header |
| `mes.orden_produccion_paso` | Steps in the production order (has `receta_id`) |
| `mes.orden_produccion_item` | Primary materials (rolls) assigned to the order (1 row = 1 lot = 1 roll) |
| `mes.orden_produccion_paso_item` | Which rolls are assigned to which step (planning + tracking) |
| `mes.operacion` | Operation catalog (`requiere_receta` flag) |
| `receta2` | Recipe header (legacy table, locked once assigned to a paso) |
| `receta_x_insumo` | Recipe formula lines (insumo + cantidad + medida) |
| `receta_x_paso` | Recipe process steps (dyeing process steps, not production steps) |
| `inventario.item_movimientos` | All inventory movements |
| `inventario.item_movimiento_tipo` | Movement types (`PROD_CONSUMO` = consumption, `PROD_ING` = output) |
| `inventario.vw_stock_actual` | Calculated available stock per item/lot/location |

### Functions

| Function | Purpose |
|----------|---------|
| `mes.generar_receta(paso_id)` | Generate recipe JSONB (always live, deterministic after EN_PROCESO) |
| `mes.iniciar_paso(paso_id, datos)` | Start a step (freezes all inputs by state transition) |
| `mes.finalizar_paso(paso_id, datos)` | Finish a step + register consumptions atomically |
| `mes.registrar_consumo_paso(paso_id, consumos)` | Create PROD_CONSUMO movements via FIFO (`calcular_fifo`) |
| `mes.calcular_fifo(items)` | Resolve lot/location via FIFO for a list of items |
| `mes.registrar_items_procesados(paso_id, items)` | Assign/update rolls on a step (PENDIENTE/EN_PROCESO/COMPLETADO) |
| `mes.registrar_produccion(orden_paso_id, output)` | Create finished product lots + PROD_ING movements (final step only) |

---

## Frontend API Calls Summary

### Planning (while PENDIENTE)
```
1. POST → registrar_items_procesados(paso_id, items[])
   Assign rolls to the step

2. POST → generar_receta(paso_id) → JSONB
   Generate and print recipe (always live, includes peso/rollos/volumen header)
```

### Starting a step
```
POST → iniciar_paso(paso_id, { empleado_id?, maquina_asignada_id? })
```

### Finishing a step (main event)
```
1. POST → generar_receta(paso_id) → get insumos array with calculated quantities
2. Show confirmation UI with editable quantities + optional manual additions
3. POST → finalizar_paso(paso_id, { consumos[]? })
   Backend handles FIFO lot resolution and inventory deduction atomically
```

### Production output (final step only)
```
POST → registrar_produccion(orden_paso_id, output[])
```

### After completion (corrections only)
```
POST → registrar_items_procesados(paso_id, items[])
```

---

## Data Integrity Model

Recipe inputs are frozen by state transitions, not by snapshots:

| Data | Locked when | Mechanism |
|------|-------------|-----------|
| Recipe formula (`receta_x_insumo`) | Assigned to paso | Application rule: no edits once assigned |
| Paso parameters (pH, temp, RB) | `iniciar_paso` | State check: only PENDIENTE pasos can be edited |
| Roll assignments (`paso_item`) | `iniciar_paso` | `registrar_items_procesados` allows PENDIENTE/EN_PROCESO/COMPLETADO but planning changes happen before start |
| Machine assignment | `iniciar_paso` | Set at start, frozen by state |
| Lot weight (`lote.cantidad`) | Before production | Set during receiving/weighing, stable during production |

`generar_receta` is deterministic after EN_PROCESO because all its inputs are frozen. No snapshot column needed.

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| No recipe snapshot | All inputs freeze at `iniciar_paso` via state transitions. `generar_receta` is deterministic — the function IS the snapshot. Printed recipe metadata (peso/rollos/volumen) lets operators self-validate. |
| Consumption happens at `finalizar`, not `iniciar` | Operator confirms actual quantities used, not just planned. Avoids reversals if step fails. Single transaction ensures atomicity. |
| Recipe quantities are pre-calculated but editable | Recipes are static but real-world usage varies. Operator accountability. |
| FIFO for lot/location resolution (all consumptions) | Too many chemical products to manually select lots. Oldest stock consumed first. Backend resolves via `calcular_fifo`. |
| Manual (non-recipe) consumption prompted at `finalizar` | Prompted alongside recipe items so operator registers everything in one screen. Purely optional. |
| Rolls assigned during PENDIENTE (planning) | `generar_receta` needs roll count/weight to calculate chemical quantities. 1 lot = 1 roll. Rolls are assigned before recipe generation. |
| `registrar_items_procesados` allows PENDIENTE/EN_PROCESO/COMPLETADO | PENDIENTE for planning (assign rolls), EN_PROCESO for tracking, COMPLETADO for corrections. |
| `orden_produccion_paso_item` is NOT for consumables | This table tracks primary materials (rolls/fabric) through steps. Chemical consumption goes through `inventario.item_movimientos` via `registrar_consumo_paso`. |
| Production output only on `flg_genera_produccion` steps | `registrar_produccion` creates finished product lots. Only allowed on the final step of the production route. |

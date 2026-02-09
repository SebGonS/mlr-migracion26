# MES - Production Step (Paso) Workflow Specification

## Overview

This document defines the frontend/backend contract for the production step lifecycle in the MES module. It covers step initiation, finalization, material consumption (recipe and ad-hoc), and item processing registration.

---

## Step Lifecycle

```
PENDIENTE ──→ EN_PROCESO ──→ COMPLETADO
                              (or OMITIDO)
```

### 1. `iniciar_paso(paso_id, datos)`

**Trigger**: Operator clicks "Iniciar" on a pending step.

**Backend behavior**:
- Validates `estado = 'PENDIENTE'`
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

**Frontend responsibility**: No consumption or item registration at this stage.

---

### 2. During `EN_PROCESO`

While the step is in process, the operator MAY:

- **Register items processed** (`registrar_items_procesados`): Track which rolls/fabric are going through this step. This is for primary material tracking (what items are being transformed), NOT for consumables.

---

### 3. `finalizar_paso(paso_id, datos)` — Main workflow event

**Trigger**: Operator clicks "Finalizar" on an in-process step.

**This is where consumption happens.** The frontend must orchestrate a confirmation screen BEFORE calling `finalizar_paso`.

#### Frontend Flow (before calling backend):

```
Operator clicks "Finalizar"
         │
         ▼
┌─────────────────────────────────────────────────┐
│  Finalizar Paso: TEÑIDO (#42)                   │
│                                                 │
│  ── Consumos de Receta ──────────────────────── │
│  (auto-populated from recipe x batch weight)    │
│                                                 │
│  Item              Sugerido   Actual            │
│  Colorante Rojo    2.50 kg    [2.50 kg]  ✎     │
│  Auxiliar pH       0.30 L     [0.30 L ]  ✎     │
│  Dispersante       1.00 kg    [1.00 kg]  ✎     │
│                                                 │
│  ── Consumos Adicionales (no receta) ────────── │
│  + [Agregar item]                               │
│                                                 │
│  ── Items Procesados (opcional) ─────────────── │
│  (rolls/fabric output quantities)               │
│  Rollo #123    45.2 kg  ✎                       │
│  Rollo #456    38.7 kg  ✎                       │
│  + [Agregar item procesado]                     │
│                                                 │
│  [Confirmar y Finalizar]                        │
└─────────────────────────────────────────────────┘
```

#### How to populate recipe consumptions

1. Read `receta_id` from the paso (`orden_produccion_paso.receta_id`)
2. If `receta_id IS NOT NULL`, fetch recipe detail (static data, never changes during production):
   ```sql
   SELECT rd.item_id, i.nombre, rd.cantidad_por_kg, rd.unidad_medida,
          rd.cantidad_por_kg * <batch_total_weight> AS cantidad_sugerida
   FROM mes.receta_detalle rd
   JOIN item i ON i.id = rd.item_id
   WHERE rd.receta_id = <receta_id>;
   ```
3. Display as editable form pre-filled with suggested quantities
4. Operator confirms or adjusts each quantity

#### Lot/Location Resolution: FIFO (automatic, no user selection)

Both recipe and manual consumptions use **FIFO** (oldest lot first). Lot and location are resolved automatically by the backend. The operator only provides `item_id` + `cantidad`.

```sql
-- FIFO resolution: oldest available lot with sufficient stock
SELECT lote_id, ubicacion_id, cantidad_disponible
FROM inventario.vw_stock_actual vs
JOIN inventario.lote l ON l.id = vs.lote_id
WHERE vs.item_id = <item_id>
  AND vs.cantidad_disponible >= <cantidad_requerida>
ORDER BY l.fyh_cre ASC
LIMIT 1;
```

If a single lot doesn't have enough stock, split across multiple lots (oldest first) until the required quantity is fulfilled.

#### `p_datos` schema for `finalizar_paso`:

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
  ],
  "items_procesados": [
    {
      "orden_produccion_item_id": 10,
      "cantidad": 45.2
    },
    {
      "orden_produccion_item_id": 11,
      "cantidad": 38.7
    }
  ]
}
```

- `consumos`: Array of ALL confirmed consumptions (recipe + manual). Only `item_id` and `cantidad` required; lot/location resolved via FIFO by the backend. Each item becomes an `inventario.item_movimientos` record with type `PROD_CONSUMO`.
- `items_procesados`: Optional. Array of items (rolls) processed in this step. Uses upsert (ON CONFLICT DO UPDATE).

#### Backend behavior of `finalizar_paso`:

1. Validate `estado = 'EN_PROCESO'`
2. If `p_datos->'consumos'` exists → resolve FIFO for each item, then call `registrar_consumo_paso(paso_id, consumos)` (validates stock, creates PROD_CONSUMO movements)
3. If `p_datos->'items_procesados'` exists → call `registrar_items_procesados(paso_id, items_procesados)`
4. Set `estado = 'COMPLETADO'`, `fyh_fin = NOW()`
5. Release machine → set `maquina.estado_actual = 'espera'`
6. Check if ALL pasos in the orden are COMPLETADO/OMITIDO → auto-finalize orden
7. Send notification

---

### 4. After `COMPLETADO` — Corrections

`registrar_items_procesados` is also allowed on steps in `COMPLETADO` state. This handles:
- Post-process weight adjustments (moisture changes)
- QC corrections
- Operator forgot to register a roll

The existing `ON CONFLICT DO UPDATE` handles upserts cleanly. Audit columns (`usr_mod`, `fyh_mod`) track all changes.

State check should be:
```sql
WHERE id = p_paso_id AND estado IN ('EN_PROCESO', 'COMPLETADO')
```

---

## Table Reference

### Key tables involved

| Table | Purpose |
|-------|---------|
| `mes.orden_produccion` | Production order header |
| `mes.orden_produccion_paso` | Steps in the production order (has `receta_id`) |
| `mes.orden_produccion_item` | Primary materials (rolls) assigned to the order |
| `mes.orden_produccion_paso_item` | Which rolls went through which step + quantities |
| `mes.operacion` | Operation catalog (`requiere_receta` flag) |
| `mes.receta_detalle` | Recipe formula lines (item + cantidad_por_kg) — TO BE CREATED |
| `inventario.item_movimientos` | All inventory movements |
| `inventario.item_movimiento_tipo` | Movement types (`PROD_CONSUMO` = consumption) |
| `inventario.vw_stock_actual` | Calculated available stock per item/lot/location |

### Relevant existing functions

| Function | Purpose |
|----------|---------|
| `mes.iniciar_paso(paso_id, datos)` | Start a step |
| `mes.finalizar_paso(paso_id, datos)` | Finish a step (to be modified to accept consumos + items_procesados) |
| `mes.registrar_consumo_paso(paso_id, consumos)` | Create PROD_CONSUMO inventory movements (to be modified: FIFO resolution moves here) |
| `mes.registrar_items_procesados(paso_id, items)` | Track rolls through steps (upsert) |

---

## Frontend API Calls Summary

### Starting a step
```
POST → iniciar_paso(paso_id, { empleado_id?, maquina_asignada_id? })
```

### During a step (optional)
```
POST → registrar_items_procesados(paso_id, items[])
```

### Finishing a step (main event)
```
1. GET recipe detail for paso's receta_id (if any) → pre-populate consumption form
2. Show confirmation UI with editable quantities + optional manual additions
3. POST → finalizar_paso(paso_id, { consumos[], items_procesados[]? })
   Backend handles FIFO lot resolution internally
```

### After completion (corrections only)
```
POST → registrar_items_procesados(paso_id, items[])
```

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| Consumption happens at `finalizar`, not `iniciar` | Operator confirms actual quantities used, not just planned. Avoids reversals if step fails. |
| Recipe quantities are pre-calculated but editable | Recipes are static but real-world usage varies. Operator accountability. |
| FIFO for lot/location resolution (all consumptions) | Too many products to manually select lots. Oldest stock consumed first. No manual override — backend resolves automatically. |
| Manual (non-recipe) consumption prompted at `finalizar` | Prompted alongside recipe items so operator registers everything in one screen. Purely optional. |
| Items processed allowed after COMPLETADO | Post-process weight changes, QC adjustments, forgotten registrations. Audit trail via usr_mod/fyh_mod. |
| No inventory reservation at `iniciar` | Recipes are static and readable anytime. Deducting only at finalization keeps inventory accurate and avoids reversal logic. |
| `orden_produccion_paso_item` is NOT for consumables | This table tracks primary materials (rolls/fabric) through steps. Chemical/auxiliary consumption goes through `inventario.item_movimientos` via `registrar_consumo_paso`. |

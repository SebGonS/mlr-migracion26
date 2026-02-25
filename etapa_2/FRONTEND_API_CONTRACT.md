# MES Paso — Frontend API Contract

## Step Lifecycle: PENDIENTE → EN_PROCESO → COMPLETADO

---

## API Calls (all are Supabase RPC calls)

### 1. Assign rolls to step (planning, while PENDIENTE)

Required before printing recipe on steps with `operacion.requiere_receta = true`.

```ts
await supabase.rpc('registrar_items_procesados', {
  p_paso_id: 42,
  p_items: [
    { orden_produccion_item_id: 10 },
    { orden_produccion_item_id: 11 }
  ]
})
```

Each item = 1 roll (1 lot). Can add/remove freely while PENDIENTE. Uses upsert.

### 2. Generate & print recipe (while PENDIENTE)

```ts
const { data } = await supabase.rpc('generar_receta', { p_paso_id: 42 })
// Returns JSONB as text — parse it
const receta = JSON.parse(data)
```

**Response structure:**
```json
{
  "receta_id": 15,
  "partida_id": 100,
  "cliente_id": 5,
  "cliente": "TEXTILES ABC",
  "orden_produccion_id": 30,
  "tipo_receta": "Tenido",
  "tipo_articulo_id": 8,
  "tipo_articulo": "JERSEY 24/1",
  "peso": 450.00,
  "cantidad": 10,
  "cantidad_regular": 8,
  "cantidad_rib": 2,
  "volumen": 3150.00,
  "maquina": { "id": 3, "codigo": "MAQ-03", "nombre": "BRAZOLI (1)" },
  "pasos": [
    {
      "orden": 1,
      "operacion_id": 5,
      "operacion": "Descrude",
      "ph": 7.0,
      "temperatura": 60.0,
      "tiempo_min": 20,
      "nota": null,
      "insumos": [
        {
          "item_id": 101,
          "orden": 1,
          "codigo": "COL-ROJO-01",
          "nombre": "Colorante Rojo",
          "cantidad": 2.5,
          "medida": "g/L",
          "cantidad_requerida_kg": 7875.00
        }
      ]
    }
  ]
}
```

> **Breaking change from old API**: `insumos[]` is no longer a flat top-level array. It is now nested inside each `pasos[]` entry. To build the consumption form, flatten: `pasos.flatMap(p => p.insumos ?? [])`.

Always generates live (no caching). The header (peso, cantidad, volumen) is printed on the recipe — operators self-validate against physical reality. If rolls/params change, reprint.

### 3. Start step

```ts
await supabase.rpc('iniciar_paso', {
  p_paso_id: 42,
  p_datos: { empleado_id: 5, maquina_asignada_id: 12 } // both optional
})
```

After this, paso params and roll assignments are frozen (state checks block edits).

### 4. Finalize step (with consumption confirmation)

**Frontend flow:**
1. Call `generar_receta(paso_id)` to get nested `pasos[].insumos[]`
2. Flatten: `const insumos = data.pasos.flatMap(p => p.insumos ?? [])`
3. Show confirmation dialog pre-filled with `cantidad_requerida_kg` per insumo
3. Let operator edit quantities and/or add non-recipe items
4. Send confirmed consumptions:

```ts
await supabase.rpc('finalizar_paso', {
  p_paso_id: 42,
  p_datos: {
    consumos: [
      { item_id: 101, cantidad: 7875.00 },
      { item_id: 204, cantidad: 800.00, observacion: "Extra por correccion pH" }
    ]
  }
})
```

- `consumos` is optional — omit for steps without recipe (SECADO, PLANCHADO, etc.)
- `item_id` + `cantidad` only — lot/location resolved automatically via FIFO
- Consumption + state change happen in one atomic transaction

### 5. Register production output (final step only)

Only on steps with `flg_genera_produccion = true`. Allowed during EN_PROCESO or after COMPLETADO.

```ts
await supabase.rpc('registrar_produccion', {
  p_orden_paso_id: 42,
  p_output: [
    { item_id: 5, cantidad: 45.2, ubicacion_id: 3 },
    { item_id: 6, cantidad: 38.7, ubicacion_id: 3 }
  ]
})
```

Creates finished product lots with PROD_ING inventory movements.

---

## UI States per Step Card

| Estado | Available actions |
|--------|-------------------|
| PENDIENTE | Assign rolls, Print recipe, Start step |
| EN_PROCESO | Finalize (with consumption dialog if `requiere_receta`), Register production (if `flg_genera_produccion`) |
| COMPLETADO | Register production (if `flg_genera_produccion`), Edit roll assignments (corrections) |
| OMITIDO | View only |

## Finalization Dialog (only if step has `receta_id`)

```
+--------------------------------------------------+
| Finalizar: TENIDO (#42)                          |
|                                                  |
| Consumos de Receta                               |
| (from generar_receta -> pasos[].insumos[])       |
|                                                  |
| Item              Sugerido      Actual           |
| Colorante Rojo    7,875.00 g    [7,875.00]       |
| Auxiliar pH         300.00 g    [  300.00]       |
|                                                  |
| Consumos Adicionales                             |
| + [Agregar item]  (item search + cantidad)       |
|                                                  |
| [Cancelar]              [Confirmar y Finalizar]  |
+--------------------------------------------------+
```

For steps WITHOUT `receta_id`: skip the dialog, call `finalizar_paso` directly with empty `p_datos`.

## Key Data Points

- `operacion.requiere_receta`: boolean — determines if recipe/consumption flow applies
- `orden_produccion_paso.flg_genera_produccion`: boolean — determines if production output is allowed
- `orden_produccion_paso.receta_id`: if not null, `generar_receta` works; if null, no recipe flow
- 1 `orden_produccion_item` = 1 lot = 1 roll

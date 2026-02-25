# Cambios: finalizar_paso ahora incluye produccion

## Que cambio

`finalizar_paso` ahora registra produccion atomicamente. Antes eran 2 RPCs separados desde el frontend — si el segundo fallaba, el paso quedaba COMPLETADO sin produccion registrada.

### Antes (2 calls, sin transaccion compartida)

```ts
// Call 1 — siempre
await supabase.rpc('finalizar_paso', {
  p_paso_id: 42,
  p_datos: {
    consumos: [{ item_id: 101, cantidad: 2.50 }]
  }
})

// Call 2 — solo si flg_genera_produccion, DESPUES de call 1
await supabase.rpc('registrar_produccion', {
  p_orden_paso_id: 42,
  p_output: [
    { item_id: 5, cantidad: 45.2 },
    { item_id: 6, cantidad: 38.7 }
  ],
  p_ubicacion_id: 3
})
```

**Problema**: Si call 1 ok y call 2 falla → paso COMPLETADO sin produccion. Estado parcial incorrecto.

### Ahora (1 call, todo atomico)

```ts
await supabase.rpc('finalizar_paso', {
  p_paso_id: 42,
  p_datos: {
    consumos: [
      { item_id: 101, cantidad: 2.50 }
    ],
    produccion: [
      { item_id: 5, cantidad: 45.2 },
      { item_id: 6, cantidad: 38.7 }
    ],
    ubicacion_id: 3
  }
})
```

Si cualquier parte falla (consumo, produccion, o update de estado), todo hace rollback.

## Shape de p_datos

```ts
interface FinalizarPasoDatos {
  // Opcional — omitir si el paso no tiene receta (SECADO, PLANCHADO, etc.)
  consumos?: Array<{
    item_id: number
    cantidad: number
    observacion?: string
  }>

  // Opcional — solo aplica si el paso tiene flg_genera_produccion = true
  // El backend lo ignora silenciosamente si flg_genera_produccion = false
  produccion?: Array<{
    item_id: number
    cantidad: number
  }>

  // Requerido si produccion tiene elementos
  ubicacion_id?: number  // destino unico para todos los lotes creados
}
```

**Validacion frontend** (form-level, antes de submit):
- `cantidad > 0` para cada fila
- `ubicacion_id` seleccionado (requerido)
- Al menos 1 fila de produccion

**Validacion backend** (atomica, bajo lock — NO duplicar en frontend):
- `item_id` existe en `partida_detalle` (siempre valido si el form se pre-pobla desde `partida.detalles`)
- `cantidad` acumulada no excede lo planificado (requiere consultar produccion previa de TODAS las ordenes de la partida — dato stale en frontend, el backend lo verifica bajo lock)

Si la validacion backend falla, devuelve excepcion con `DETAIL` que es un **array JSON** (puede haber multiples items con error):

```json
[
  {
    "item_id": 5,
    "cantidad_solicitada": 10,
    "cantidad_producida": 75,
    "cantidad_planificada": 80
  }
]
```

Todos los valores son **roll count** (no kg). El frontend parsea el `detail` del error y muestra cada violacion.

### Semantica de produccion[]

Cada fila en `produccion[]` = **1 rollo fisico** con su peso en kg:

```json
{
  "produccion": [
    { "item_id": 5, "cantidad": 45.2 },
    { "item_id": 5, "cantidad": 38.7 },
    { "item_id": 6, "cantidad": 12.0 }
  ]
}
```

- `cantidad` = peso del rollo en kg (se guarda en `lote.cantidad`)
- El backend **cuenta filas** por `item_id` para validar contra `partida_detalle.cantidad` (roll count)
- No confundir: la validacion es por numero de rollos, no por peso

## Orden de ejecucion interno (1 transaccion)

1. Validar paso EN_PROCESO
2. `registrar_consumo_paso()` — si `consumos` presente
3. `registrar_produccion()` — si `flg_genera_produccion = true` Y `produccion` presente
4. UPDATE paso → COMPLETADO
5. Liberar maquina
6. Check todos completos → auto-FINALIZAR orden
7. Notificaciones

## get_orden_produccion — partida.detalles agregado

`get_orden_produccion` ahora incluye `partida.detalles` para que el frontend pueda pre-poblar el formulario de produccion:

```json
{
  "partida": {
    "id": 100,
    "numero": 1,
    "codigo": "2026-0001",
    "cliente": "TEXTILES ABC",
    "detalles": [
      {
        "id": 55,
        "item_id": 5,
        "item_codigo": "JER-24-ROJO",
        "item_nombre": "JERSEY 24/1 ROJO",
        "cantidad": 80,
        "unidad_id": 1
      },
      {
        "id": 56,
        "item_id": 6,
        "item_codigo": "RIB-ROJO",
        "item_nombre": "RIB 1x1 ROJO",
        "cantidad": 5,
        "unidad_id": 1
      }
    ]
  }
}
```

`partida.detalles[].cantidad` = roll count (demanda de partida_detalle).

## registrar_produccion standalone — se mantiene

`registrar_produccion(p_orden_paso_id, p_output, p_ubicacion_id)` sigue existiendo como funcion independiente para **correcciones post-finalizacion** (registrar produccion despues de que el paso ya esta COMPLETADO). No se elimina.

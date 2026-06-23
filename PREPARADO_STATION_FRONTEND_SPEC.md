# Plant Station — Frontend Spec (Preparado, and every non-scheduled op)

Tablet-on-plant UI for the operator stations. This is the pattern for **every
operation EXCEPT teñido and termofijado** — those two are placed on the
scheduling board (`get_programacion_diaria`) in an arbitrary planner order. All
the others (PREPARADO, SECADO, PLANCHADO, PERCHADO, COMPACTADO, VOLTEADO) are
**not** scheduled; their worklist is *derived* from the programación + progress
and worked **FIFO**. The first station being built is **PREPARADO**
(`mes.operacion` id **11**, `requiere_receta=false`).

Same screen serves any non-scheduled station — only the `operacion_id` changes.

All backend pieces below exist and are granted to `authenticated`. Every write
function `RAISE`s a Spanish-text exception on failure — surface `error.message`
verbatim.

---

## 1. Worklist screen — direct query on `mes.vw_pasos`

No RPC. `vw_pasos` is granted to `authenticated` (RLS = `produccion.ver`), so the
station reads it straight through PostgREST:

```
vw_pasos?operacion_id=eq.11
        &partida_estado_produccion=in.(PROGRAMADA,EN_PRODUCCION)
        &estado=in.(PENDIENTE,EN_PROCESO)
        &order=partida_id.asc
```

What each clause does:
- `operacion_id=eq.11` → this station's operation.
- `partida_estado_produccion in (PROGRAMADA, EN_PRODUCCION)` → **the active-pipeline
  scope**. A partida flips to `PROGRAMADA` once it's on the board (its teñido/
  termofijado got scheduled) and `EN_PRODUCCION` once it starts. This is how
  "derived from la programación" is expressed — no polymorphic board join needed.
- `estado in (PENDIENTE, EN_PROCESO)` → the queue plus what's running here.
- `order=partida_id` → **FIFO** by partida creation order (board priority ignored).
  PREPARADO is secuencia 1, so every `PENDIENTE` row is already workable — no
  readiness gate needed. Mid-route stations (perchado, compactado) will need one;
  that's deferred until they're built (and will likely warrant a dedicated view
  rather than subqueries on this shared one — see footer).

Bucket rows by `estado`: `EN_PROCESO` → "En proceso" lane; `PENDIENTE` → "Cola".

Columns to read: `paso_id`, `ejecucion_id`, `partida_id`, `partida_codigo`, `cliente`,
`color`, `color_hex`, `requiere_maquina`, `fyh_inicio`, `estado`, `operacion_nombre`,
`maquina_id`.

> **Mid-route stations (perchado, compactado, …):** use `mes.vw_cola_estacion` instead
> of `vw_pasos` — same query shape but it carries `listo` / `fyh_listo` and is pre-scoped
> to active partidas (`estado_produccion`-driven, carryover-safe — NOT the board). Filter
> `operacion_id=eq.<op>&listo=is.true&order=fyh_listo.asc.nullslast`. PREPARADO doesn't
> need it (secuencia 1, always ready), so it stays on `vw_pasos` per above.

**Refresh** after every action; optionally poll ~30 s so a card another tablet
started drops off this one's queue.

> Teñido / termofijado stations do NOT use this screen — they use the scheduling
> board via `mes.get_programacion_diaria(fecha)`.

---

## 2. Iniciar (PENDIENTE → EN_PROCESO)

**RPC:** `iniciar_paso(p_paso_id, p_datos)`
- `p_datos = { "maquina_id": <int> }` **only if** the card's `requiere_maquina = true`
  (currently true for PREPARADO — see §6); `{}` otherwise.

---

## 3. Finalizar modal (EN_PROCESO → COMPLETADO)

**RPC:** `finalizar_paso(p_paso_id, p_datos)` — single atomic call.

```json
{
  "fyh_fin": "<ISO datetime, prefilled now>",
  "cantidad_rollos": <int, DEFAULT = assigned rolls (from get_partida)>,
  "cantidad_scrap": <kg, optional>,
  "notas": "<text, optional>",
  "consumos":  [{ "item_id": <int>, "cantidad": <kg> }],
  "matizados": [{ "item_id": <int>, "cantidad": <kg> }]
}
```

- **Cantidad (rollos):** prefill from the partida's assigned roll count — pull it from
  `get_partida` when the modal opens (the same call your finalize flow already makes),
  not from the worklist row. It's what closes the paso — blank or short leaves it
  EN_PROCESO and blocks teñido. Treat empty as an error.
- **Scrap (kg):** informational only — stamped on the run, **no** inventory effect.
- **Consumos / Matizados:** optionally pre-flight with
  `validar_disponibilidad(p_consumos)`; a `bloqueante:true` item blocks submit,
  fungible deficit warns. `finalizar_paso` re-checks and raises `Stock insuficiente…`
  with a JSON `DETAIL` if short.

---

## 4. Reversals

- **Deshacer inicio** (EN_PROCESO → PENDIENTE): `revertir_inicio_paso(p_paso_id)`.
  Refuses (clear message) if any consumo/output exists → use Anular instead.
  Operator-level, no reason. Confirm dialog.
- **Anular última finalización** (COMPLETADO → EN_PROCESO):
  `anular_produccion(p_ejecucion_id)` from the card's `ejecucion_id`. Confirm dialog.
  A finished paso leaves the queue, so expose this from an "Últimos finalizados"
  section or the partida detail. Whether operators see it at all is a policy
  decision (see §6).

---

## 5. Errors & permissions

- All actions require **`produccion.ejecutar`**. Hide buttons if the user lacks it.
- Show `error.message` (already human-readable). Stock shortfalls carry a JSON
  array in `error.details` (`item_nombre`, `saldo_disponible`, `cantidad_requerida`).

---

## 6. Open decisions that change this UI

1. **`requiere_maquina` on PREPARADO** (currently `true`): if prep is machineless,
   backend flips it to `false` and Iniciar drops the machine picker. Drive the
   picker off the card's `requiere_maquina` so the UI auto-adjusts. **Until then
   Iniciar errors without a `maquina_id`.**
2. **Scrap semantics:** informational (assumed) vs. real inventory write-off.
3. **Anular exposure:** operator self-service vs. supervisor-only + time-gated.
4. **Rolls-required-to-start:** backend does NOT block prep start with zero rolls;
   add a UI check on `total_rollos > 0` if you want it.

---

## Backend used (all live, no new endpoints)

| Action | How | Key |
|--------|-----|-----|
| Worklist | direct read `mes.vw_pasos` | `operacion_id`, `partida_estado_produccion`, `estado`, order `partida_id` |
| Iniciar | rpc `iniciar_paso` | `p_paso_id`, `p_datos` |
| Finalizar | rpc `finalizar_paso` | `p_paso_id`, `p_datos` |
| Pre-flight stock | rpc `validar_disponibilidad` | `p_consumos` |
| Deshacer inicio | rpc `revertir_inicio_paso` | `p_paso_id` |
| Anular finalización | rpc `anular_produccion` | `p_ejecucion_id` |

vw_pasos column added for the stations: **`partida_estado_produccion`** only — a free
column from the partida JOIN that's already in the view, so it adds no per-row cost to
existing `select('*')` consumers (the estación and ejecución pages). `listo`, `fyh_listo`
and `total_rollos` were prototyped then dropped: PREPARADO needs none of them (secuencia 1,
FIFO by `partida_id`, Cantidad default via `get_partida`), and as correlated subqueries
they'd burden the shared view. Revisit them — most likely as a dedicated station view —
when the mid-route finishing stations (perchado, compactado) are built.

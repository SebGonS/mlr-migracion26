# Venta per-item billing — build spec (2026-07-27)

Reshapes `doc.venta_detalle` from **charge-grain** (one row per operación, dims
snapshot from the partida) to the two grains the real invoice actually has:
an **item line** per product, and **charge sub-lines** per operation under it.
This is the SAP SD pricing-conditions pattern, kept lightweight (item = VBRP,
charges = the condition components that sum to the item's net rate).

**Why now, not backlog:** a partida's `grupo_articulo` is a *set* of co-dyed
articulos (jersey, rib, …). Different operations apply to different articulos
(termofijado/perchado hit jersey, not rib). Recording one partida-level charge
when the reality is per-articulo is **fake data, not an approximation**. The
per-roll `articulo_id` is already available at dispatch (`get_despacho_partida`
returns it from `item_rollo_detalle.articulo_id`), and op-applicability needs no
routing engine — the dispatcher **prunes** the inapplicable charges by hand.

**Sequence:** land this **before** the `mlr-db` baseline regen (so the clean
baseline is item-grain-native), and it **supersedes the charge-line half of**
`mlr-app/VENTA_REFERENCIA_FRONTEND_CHANGES.md` (the dispatch drawer gains the
per-articulo candidate-lines + prune step described below).

---

## Grain model

- **Weight + pieces are item-grain** — a property of the product (jersey-rojo weighs X, is N rolls).
- **Rate is charge-grain** — base dyeing, termofijado, perchado, antipilling; each an operation with its own rate. The item's rate = **sum of its applicable charges**.
- Storing weight on charge rows duplicates it (item fact on charge grain) → that's why it splits into two tables.

---

## Schema

### `doc.venta_detalle` — reshaped to the ITEM line (one per `articulo × tenido × color`)

Keep: `id, venta_id, linea, tipo, partida_id, color_x_cliente_id, tenido_id,
grupo_articulo_id, descripcion, usr_cre, fyh_cre`.

- **ADD `articulo_id INT REFERENCES articulo(id)`** — the specific fabric (the missing dimension; `grupo_articulo_id` stays as the *dye set* + catalog key). Nullable (historical rows have none — see History).
- **ADD `cantidad_rollos INT`** — pieces; the invoice records it, we currently can't.
- **ADD reference to the matching `entrega_detalle` line** — traceability only (see FK direction below). Independent of the numbers: `cantidad_kg`/`cantidad_rollos` are the **billed values stored on the line**, NOT derived through the link.
- **KEEP `cantidad_kg`** as the billed weight (stored, snapshot — not derived).
- **REMOVE `operacion_id`, `precio_kg`** → they move to `venta_detalle_cargo`.
- **REMOVE the generated `importe`** column → the item's importe = `cantidad_kg × SUM(cargo.precio_kg)`, computed in `vw_venta` (a generated column can't sum a child table).
- `flg_antipilling`: **drop from the line** — antipilling is now a *charge* (its own `operacion`), represented by a cargo row, not a line flag. (Decide at build: keep only if still wanted for the description string.)
- `item_id`: keep (VENTA product-sale lines still name the sold item).

### `doc.venta_detalle_cargo` — NEW, the CHARGE sub-line (one per `item line × operación`)

```
id                BIGINT PK
venta_detalle_id  BIGINT NOT NULL REFERENCES doc.venta_detalle(id) ON DELETE CASCADE
operacion_id      SMALLINT NOT NULL REFERENCES mes.operacion(id)
precio_kg         NUMERIC(12,4) NOT NULL          -- rate for THIS operation (catalog or typed)
usr_cre, fyh_cre
UNIQUE (venta_detalle_id, operacion_id)           -- one charge per op per item line
```
No weight here (that's item-grain). A cargo's importe = `precio_kg × parent.cantidad_kg`, computed in the view.

### `doc.entrega_detalle` — traceability reference

- **ADD `venta_detalle_id BIGINT REFERENCES doc.venta_detalle(id)`** (nullable). FK sits on the physical side because it's **one charge : many roll-lines** (all jersey-rojo rolls → one charge). Purely "which charge does this dispatched line bill under"; no derivation.

---

## Backend

- **`registrar_despacho`**: `p_datos.cargos` becomes per-item-line —
  `{ articulo_id, tenido_id, color_x_cliente_id, grupo_articulo_id, partida_id,
     tipo, cantidad_kg, cantidad_rollos, entrega_detalle_ids:[…],
     charges:[ { operacion_id, precio_kg }, … ] }`.
  Per cargo: insert one `venta_detalle` (item line) + N `venta_detalle_cargo`
  (charges); stamp `entrega_detalle.venta_detalle_id` on the referenced lines.
  Snapshot dims from the **roll's articulo**, not the partida.
- **Pricing** already supports per-operation rates: `fn_get_precio(p_operacion_id,
  color_x_cliente, tercero, grupo_articulo, tenido, fibra)` returns the rate for
  one operation. Base dyeing prices per `grupo_articulo` (same for jersey/rib —
  correct); termofijado/perchado/antipilling price per their own `operacion`.
  Candidate charges = `fn_get_precio` per applicable operation.
- **`vw_venta`**: item line + derived `precio_kg_total = SUM(cargo.precio_kg)` and
  `importe = cantidad_kg × precio_kg_total`; optionally expose the cargo breakdown
  (jsonb agg) for display. Add `articulo`, `cantidad_rollos`.
- **`fn_descripcion_linea`**: compose from the specific `articulo` (+ tenido, color)
  → "Jersey directo rojo", not the grupo.

## Frontend (dispatch drawer — supersedes the charge-line part of the ref handoff)

1. From `get_despacho_partida` (already returns per-roll `articulo_id`/`articulo_nombre`), group the dispatched rolls by `(articulo × tenido × color)` → candidate **item lines** (weight = Σ roll kg, pieces = roll count).
2. For each item line, generate candidate **charges** = the operaciones with their `fn_get_precio` rates.
3. Dispatcher **prunes** inapplicable charges (rib × termofijado). Remaining charges sum → the item line's rate.
4. Submit per-item cargos with their surviving charges. `VentaDetalleDrawer` then shows real per-product lines with their charge breakdown.

---

## History (migrated data stays coarse)

Legacy `despacho` is partida-grain — one `precio_unit` per partida-dispatch, no
per-item/per-op detail (the `rib` column is just a roll count). So historical
`venta_detalle` **cannot** be rebuilt to item-grain; don't fabricate it.

To keep ONE uniform model (no dual flat/two-level shape), migrate history into the
new structure minimally:
- For each existing `venta_detalle`, insert **one** `venta_detalle_cargo`
  (`operacion_id` = its current op, `precio_kg` = its current price), then drop the
  `operacion_id`/`precio_kg` columns.
- Historical item lines have `articulo_id = NULL` (partida-grain), one cargo,
  `entrega_detalle_id` NULL. Optionally backfill `cantidad_rollos` from
  `despacho.rollos_total`.
- Forward item lines have `articulo_id` set and N cargos. Same tables, `articulo_id`
  NULL marks the coarse historical rows.

---

## Open build-time decisions

- `flg_antipilling` — drop from the item line entirely, or keep only for the description string?
- Expose the cargo breakdown in `vw_venta` (jsonb) or keep the view at item-line net only?
- `cantidad_rollos` backfill for history — worth pulling from `despacho.rollos_total`, or leave NULL?

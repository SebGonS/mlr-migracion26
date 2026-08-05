## 0b. BREAKING CHANGE (2026-07-19) — `articulo_tipo_id` → `grupo_articulo_id`

`articulo_tipo` retired as the substrate/pricing key. Do a project-wide
`articulo_tipo_id`→`grupo_articulo_id` / `articulo_tipo`→`grupo_articulo` replace, then check
consistency against the affected objects below.

**New catalog tables** (source the substrate picker from these, not `articulo_tipo`) — full DDL
in `migration/28_grupo_articulo.sql`:

```sql
CREATE TABLE grupo_articulo (
    id           INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo       TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL UNIQUE,
    nombre       TEXT NOT NULL,
    firma        TEXT UNIQUE,               -- sorted member articulo_ids, comma-joined; identity of the set
    origen_articulo_tipo_id SMALLINT REFERENCES articulo_tipo(id),  -- migration cross-ref only
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    usr_elm INT, fyh_elm TIMESTAMPTZ
);

-- N:M — a fabric (articulo) can belong to its own pure grupo AND any number of mixes.
CREATE TABLE grupo_articulo_miembro (
    grupo_articulo_id INT NOT NULL REFERENCES grupo_articulo(id) ON DELETE CASCADE,
    articulo_id       INT NOT NULL REFERENCES articulo(id),
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (grupo_articulo_id, articulo_id)
);
```

Read model: `vw_grupo_articulo` (same file) — `grupo_articulo_id, codigo, nombre, firma,
n_miembros, flg_mezcla, fibra_max, miembros` (member names joined). Use this for display/pickers
rather than joining `grupo_articulo_miembro` directly.

**Affected views/functions** — verify each call site against the current definition in the
named file:
- `doc.vw_precios_estado`, `doc.vw_precios_pendientes`, `doc.vw_venta` (`funciones/facturacion.sql`, `funciones/despacho.sql`) — output columns
- `crear_partida` (`funciones/core.sql`) — payload key
- `registrar_despacho`, `fn_descripcion_linea` (`funciones/despacho.sql`)
- `get_tenido`, `vw_tenido`, `get_tenido_versiones` (`funciones/receta.sql`)
- `get_partida`, `get_partida_familia`, `generar_receta`, `get_actividades_*` (`funciones/mes.sql`)
- `fn_precio_info`, `get_precio_info_partida`, `upsert_catalogo_precio` (`funciones/facturacion.sql`)

**Not a rename — new validation:** `registrar_factura_cliente` now `RAISE EXCEPTION`s if any
`lineas[]` entry has an `articulo_tipo_id` key at all (not silently dropped). Send
`grupo_articulo_id`.

---

# Frontend integration: MLR dispatch commercial module (`venta`)

You have no prior context on this — everything you need is below or referenced by path.
Read `VENTA_MODULE_HANDOFF.md` and `VENTA_MODULE_CONSOLIDATED.sql` (both in the repo root)
before implementing anything here — they hold the full rationale and exact SQL, including
constraints the UI must respect that aren't obvious from payload shapes alone.

## Background, briefly

MLR just added a commercial "sale" layer (`doc.venta` / `doc.venta_detalle`) on top of the
existing physical dispatch machinery (`doc.entrega` / inventory movements). A `venta` groups
one client's dispatch, holds the reference to MLR's own externally-emitted factura (serie/
numero/fecha_venc — MLR does not emit invoices in-system, only references them), and its
charge lines capture what's billed per operation (tenido, termofijado, perchado, etc).

---

## 0. RESOLVED (2026-07-14) — `get_despacho_partida` now includes `partida_id` per item

If you already asked about this: **fixed on the backend, no frontend workaround needed.**
`doc.get_despacho_partida`'s `entregas[].items[]` objects now include `"partida_id"` (the
producing partida — root or rework child) alongside the existing fields. It maps directly
onto `registrar_despacho`'s `items[].partida_id`. This was purely additive — it is NOT part
of the ownership grouping, so multi-partida dispatch (selecting several partidas for the
same client in one preview call) is unaffected; nothing else about the response shape
changed. Re-fetch/re-check the RPC response shape if you cached an older version of it.

---

## 1. BREAKING CHANGE — fix this first, it's live-behavior-affecting

**`doc.crear_entrega` (Supabase RPC) now returns a plain `bigint` (the created `entrega_id`)
instead of a `text` success message.**

- Before: `"Guía de remisión con ID 123 creada correctamente."`
- Now: `123`

**Find every call site invoking the `crear_entrega` RPC** (`supabase.rpc('crear_entrega', ...)`
or equivalent) and update them:
- Anywhere the old text was shown directly as a toast/success message must now build its own
  message client-side from the returned id (e.g. `` `Guía #${id} creada correctamente.` ``).
- Anywhere the id was being parsed out of that string, simplify — the id is now the return
  value directly, no parsing needed.

**Known call sites** (there may be others — search, don't assume this is exhaustive):
- The two-step dispatch flow: `get_despacho_partida(partida_ids)` (preview) → `crear_entrega`
  called once per entrega group (frontend currently loops this itself).
- The client-material receipt flow (`CLIENTE_ENVIO_PROCESO` — client sends rolls in for
  processing).

---

## 2. New RPC: `doc.registrar_despacho` — the new dispatch write path

This **replaces** the old "call `crear_entrega` once per group" pattern as the write step.
`get_despacho_partida` is unchanged and still the right way to preview/list dispatchable
rolls — its output should now feed into `registrar_despacho` instead of driving direct
`crear_entrega` calls per group.

**One call does everything:** creates the entrega(s) (still via `crear_entrega` internally,
now reused correctly), opens/reuses the client's open `venta`, and inserts the charge lines
— in one transaction.

```jsonc
// doc.registrar_despacho(p_datos jsonb) → jsonb
// Request:
{
  "tercero_id": 7,                          // optional; derived from cargos' partidas if omitted
  "items": [                                 // the physical rolls to dispatch
    { "item_id": 44, "lote_id": 901, "ubicacion_id": 3, "cantidad": 20.50,
      "propietario_id": 7, "partida_id": 123 }
    // propietario_id: MLR's own tercero id (=1) → billed as a VENTA (sale) line.
    //                 any other tercero_id (the client) → billed as a SERVICIO line.
    // partida_id: the partida that produced this roll (root or rework child — server resolves).
  ],
  "guias": {                                 // optional per group; omit for headless (no serie/correlativo yet)
    "VENTA_EGRESO":     { "serie": "F001", "correlativo": "00012345", "fecha_emision": "2026-07-13" },
    "DESPACHO_CLIENTE":  { "serie": "T001", "correlativo": "00012345", "fecha_emision": "2026-07-13" }
  },
  "cargos": [                                // the commercial charge lines — what's being billed
    { "partida_id": 123, "operacion_id": 5, "cantidad_kg": 480.60,
      "precio_kg": 2.35,                     // OPTIONAL — omit to let the server pre-fill from the price catalog;
                                              // if provided, this is the user's manual override, and it freezes.
      "item_id": null,                       // only used for VENTA-type charges (selling MLR's own product)
      "descripcion": null }                  // optional manual label; server composes one if left blank
  ]
}

// Response:
{ "venta_id": 501, "entrega_ids": [9001, 9002], "cargo_ids": [3001, 3002] }
```

**Validation to surface client-side before calling this RPC** (the server enforces it too, but
a pre-emptive UI check is better UX): a single `cargos[].partida_id` cannot mix MLR-owned and
client-owned rolls in the same call — the server raises rather than guessing. If a partida's
dispatched rolls in this batch have inconsistent `propietario_id`, warn the user before submit.

## 3. `doc.facturar_venta` / `doc.anular_venta`

```
doc.facturar_venta(p_venta_id bigint, p_serie text, p_numero int, p_fecha_venc date DEFAULT NULL) → text
doc.anular_venta(p_venta_id bigint) → text
```
Stamps MLR's own (externally-emitted) factura reference on an open venta and closes it, or
voids the venta record. Needs a minimal UI surface — even a simple form on a venta detail
screen is enough for v1.

## 4. New read views

- **`doc.vw_venta`** — one row per venta line: header fields (tercero, factura ref, estado)
  joined with each `venta_detalle` line (tipo, operación, partida, composed `descripcion`,
  `cantidad_kg`, `precio_kg`, `importe`). Use this to list/display a sale.
- **`mes.vw_partida_comercial`** — one row per partida (root only): `total_terminal`,
  `dispatched_ahora`, `pendiente` (derived, always current), plus `venta_ids`,
  `factura_refs`, `total_kg_facturado`, `total_importe` rolled up from its ventas. Use this
  for a dispatched-vs-pending board/column and billing summary — it's the authoritative
  number, don't compute this client-side from raw movements.

---

## Suggested build order

1. **Fix the `crear_entrega` breaking change everywhere it's called.** Do this first — it's a
   correctness bug in production the moment the backend migration lands, independent of any
   new feature work.
2. **Build the one-shot "Registrar despacho" drawer**, mirroring whatever "Registrar compra"
   UI pattern already exists (the backend was explicitly designed to mirror that flow): reuse
   the existing `get_despacho_partida` preview UI, add per-operation charge inputs
   (price pre-filled, editable) and optional guía/factura fields, submit once via
   `registrar_despacho`.
3. **Surface `mes.vw_partida_comercial`** on whatever partida list/board view already exists.
4. **A venta list/detail screen** reading `doc.vw_venta`, with `facturar_venta`/`anular_venta`
   actions.

Read `VENTA_MODULE_HANDOFF.md`'s "Settled decisions" section before making any design choice
that isn't spelled out above — several non-obvious constraints (why billing snapshots
partida data instead of reading it live, why reworks aren't billed separately, why there's
no per-roll line on a venta) are already decided there and shouldn't be re-litigated.

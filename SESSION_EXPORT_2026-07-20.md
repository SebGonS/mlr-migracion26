# Session export — 2026-07-20

Handoff for continuing in a new project folder. Covers the pricing→grupo finish,
the rib arc (35–37), and the per-roll production-tracking design (38+). For the
grupo_articulo migration itself (28–34) the authority is
[GRUPO_ARTICULO_HANDOFF.md](GRUPO_ARTICULO_HANDOFF.md) — this file does not repeat it.

The migration files' own comment headers are the detailed record; this is the index
and the reasoning that lives only in conversation.

---

## Migration state at a glance

| # | what | state |
|---|---|---|
| 33 / 33b | pricing + billing re-keyed to `grupo_articulo_id` | ✅ applied, **verified** (baseline diff clean) |
| — | 5 views missed by 33b (`vw_partidas`, `vw_partida_familia`, `vw_auditoria_pendiente`, `vw_pesaje_pendiente`, `vw_catalogo_precios_historico`) | ✅ fixed + applied |
| 49 (patch) | `doc.articulo_tipo_familia` writable for grupos + `upsert_familia_precio` + `vw_familia_precio` | ⬜ **written, not applied** |
| 34 | drop `articulo_tipo_id` cols, retire `articulo_tipo`, rename familia table | ⬜ deferred on purpose (soak first) |
| 35 | rib → real fabric (`Rib Algodón`, `Rib Poliéster`); forged items repointed + soft-deleted | ✅ applied, **verified** (5190/142933 invariant held) |
| 36 | `articulo.flg_rib` = source of truth + derive-trigger on `item_rollo_detalle` | ✅ applied, **verified** |
| 37 | `construccion` catalog + `articulo.construccion_id/titulo/preparacion` decomposed from name | ✅ applied (checks passed) |
| 38 | per-roll tracking: `ejecucion_lote` + scope/progress views | ⬜ **rewritten, not applied** — see reconciliation below |
| 39+ | routing | ❌ not started — **blocked on one open decision** (below) |

---

## Live-DB reconciliation needed for 38

During the session a **bare `mes.partida_paso_lote` table + a neutered
`sincronizar_alcance_pasos()` (body `RETURN 0`)** were created live to unblock a
`core.sql` deploy. The design was then reworked. Current disk vs DB:

- **Disk:** `migration/38` rewritten (drops both in §0, creates `ejecucion_lote` +
  views). `funciones/core.sql` reverted — all `sincronizar_alcance_pasos` calls
  removed.
- **DB:** still has the bare table + no-op function, and (probably) the older
  `core.sql` whose bodies call that no-op. Harmless right now (no-op), but stale.

**To reconcile:** apply `migration/38`, then re-apply `funciones/core.sql`. Order
matters — 38 drops the function; core.sql (already call-free) must load after so no
body references it. Nothing was populated, so there's no data migration.

---

## Open decision that blocks routing (39)

**Does a fabric's finishing route key on `construccion_id` alone, or
`construccion_id + fibra + composition`?**

- Construction alone (rib vs jersey vs gamuza) is enough to express "rib isn't
  brushed."
- But "polyester *must* be heat-set, cotton doesn't" is a **fibra/composition**
  fact, not a construction one — so if that rule is real at MLR, the key needs more
  than construction.

This decides `ruta_plantilla`'s applicability key and is the one thing not to
guess — it's where the model meets the plant floor. Everything else in 38 is
settled. Get this answer, then write 39.

---

## Architecture decided this session — do not relitigate

**Rib (35–37).** Rib was never a fabric; it was `flg_rib=true` on a *clone item*
pointing at the body's articulo, so the DB asserted ~5,190 rib rolls *were* jersey.
Now: rib is a real `articulo`; `flg_rib` lives on `articulo` (5 rows) with a trigger
deriving the per-roll copy so the contradiction is structurally impossible;
construction is decomposed out of the name into `construccion_id`. The signal for
"genuine rib" is **`articulo.nombre ILIKE '%rib%'`**, never the item name.

**Per-roll tracking (38) — three concerns, kept apart:**
- **Planning** = *which rolls should pass an operation* → `vw_paso_lote_alcance`
  (derived view, today all-rolls, routing refines it later — **one** place to change).
- **Execution/audit** = *which rolls did, in which run, with what outcome* →
  `mes.ejecucion_lote` (append-only event log, hangs off the **run**, keyed to the
  **lote** not the reservation, surrogate PK so rework is representable).
- **Progress** = did / should → `vw_paso_progreso`. This is what replaces the buggy
  "20/22 forever" once routing lands.

**Principles that generated those choices (and killed earlier drafts):**
- **No stored `estado` per roll.** In-process/done is a fact about the *run*;
  storing it per roll is the `flg_rib` two-homes mistake again. "Not applicable" =
  absence from scope. "Pulled" = a `RETIRADO` event. `estado` dissolves.
- **Scope is derived, never synced.** A "sync function" or trigger maintaining a
  scope table is the tell that scope shouldn't be stored. Use a view.
- **Record everything, uniformly.** Every run→roll emits an event, teñido included.
  "Store only divergence" was rejected as operation-type conditional logic (the
  `flg_rib` smell) and because *did* is never derivable from *should* even when they
  match (≈ SAP AFRU: confirm every operation).
- **The MES does not write to the inventory ledger** between reservation and final
  consumption — so `ejecucion_lote` is the *only* per-roll process history, not a
  cache of movements. And a roll passing compactado is **not** a movement (same
  roll, same place, transformed in place) — don't push MES events into
  `item_movimientos`.
- **The rollo is the traced UNIT, not a "batch."** The batch is the partida (dye
  lot). Vocabulary trap: their `lote` = one roll = a serialized unit, despite the
  ERP name.
- **The partida grain is correct.** Dyeing is inherently batch-grain (shared bath).
  Routing adds a grain *below* (per-roll scope) and a master *above* (per-fabric
  route that `partida_paso` is copied from instead of hand-entered). `partida_paso`,
  `partida_paso_ejecucion`, `programacion` all keep their roles.

**"How much should pass through operation X" is exactly what routing answers, and
nothing else can.** The 20/22 bug is definitionally "no routing, so *should*
defaults to *all*." That's why routing isn't optional polish.

---

## Loose ends worth carrying over

- **37:** 6 articulos deliberately left `construccion_id = NULL` (Full Lycra ×3,
  Spun ×2, the forged mix `J 30/1- Gam 50/1`) — need a human, not a regex.
  And **Franela vs French Terry**: `F*` seeded as `FRANELA` separate from
  `FRENCHTERRY`; if the plant says *felpa* = French Terry, merge (2-statement recipe
  in 37 §2).
- **Backlog `doc.familia_precio` header:** the pricing family self-reference is
  deferred, not endorsed — see GRUPO_ARTICULO_HANDOFF.md decisions 12/backlog. The
  `Jersey/Gamuza` grupo stays alive as a live pricing bucket until it lands.
- **Frontend:** `FRONTEND_INTEGRATION_PROMPT.md` §0b has the grupo rename + the
  `registrar_factura_cliente` hard-reject. Not yet done by the frontend.
- **Environment gotcha:** the SQL client runs each statement as its own round trip
  (transaction-pooled). `TEMP TABLE ... ON COMMIT DROP` does **not** survive to the
  next statement — use a real table, drop it explicitly. Cost a failed run once.
- **`migration/_scratch/VENTA_MODULE_CONSOLIDATED.sql`** is a do-not-run reference
  copy; it's marked, just don't apply it.

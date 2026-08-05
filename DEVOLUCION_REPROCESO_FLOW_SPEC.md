# Devolución + Reproceso — flow architecture spec

**Status:** design-only. Written 2026-07-28, revised after user feedback. No build yet —
this is the spec to agree on first.

Related: `REPROCESO_GENEALOGY_TODO.md`, [[reproceso-reversal-missing-frontend]],
[[document-model-philosophy]], [[devoluciones-module]].

---

## 1. THREE distinct concepts (they were being conflated)

| # | scenario | boundary | direction | flow |
|---|---|---|---|---|
| **1** | **Return undyed crudo to client, service cancelled** | client | OUT (terminal) | devolución crudo cliente (`DEV_CLI_EGR`) |
| **2** | **Client returns dyed rolls (their QC), rolls reprocessed** | client, then internal | IN, then rework | devolución cliente (`DEV_CLI_ING`/`SERV_DEV_ING`) **→** reproceso |
| **3** | **Our QC fails the rolls, we reprocess** | internal only | rework | reproceso (no devolución) |

Two axes: **does material cross the client boundary?** (1,2 = yes; 3 = no) and **is there
rework afterward?** (2,3 = yes; 1 = no). #1 is a pure devolución; #3 is a pure reproceso;
#2 is the only one that chains both.

**The incident** was really a **#1** (undyed crudo, service issue) hand-posted as messy
`DEV_CLI_EGR`, but with the *rework* intent of #2/#3 muddying it — which is why it looked
ambiguous. Keeping the three flows distinct is the whole point of the fix.

---

## 2. Current state

### Devolución (client boundary) — `funciones/devoluciones.sql`
| function | concept | dir | movement | guard (function-level) | reversal |
|---|---|---|---|---|---|
| `registrar_devolucion_cliente` | #2 (in) | IN | `DEV_CLI_ING`/`SERV_DEV_ING` | out-of-stock + prior dispatch to client | `anular_devolucion_cliente` |
| `registrar_devolucion_crudo_cliente` | #1 | OUT | `DEV_CLI_EGR` | entered from client + **stock sufficient** | `anular_devolucion_crudo_cliente` |
| `registrar_devolucion_proveedor` | — | OUT | `DEV_PROV_EGR` | insumo + stock sufficient | `anular_devolucion_proveedor` |

### Reproceso (internal) — `funciones/mes.sql`
- `crear_reproceso` — **moves** lotes into a new rework child partida (`partida_origen_id` = flat
  family root). A roll is NOT consumed here — **rolls are only consumed at the last step** — it is
  *re-assigned* to the rework partida and runs the steps again.
- `mover_lotes_reproceso` / `anular_reproceso` — reverse the move (to the root, not the true
  immediate source — the genealogy bug in `REPROCESO_GENEALOGY_TODO.md`).

### What the data shows (verified 2026-07-28)
- **`DEV_CLI_ING` used 0×** — concept #2's proper inbound path is dead in practice.
- **No movement-level saldo/direction guard exists** — only `audit` + `corte_cuadre` (date)
  BEFORE-INSERT triggers; **no `cantidad_actual >= 0` constraint** on `lote_saldo`. The only real
  guard is *inside* the devolución functions, which direct inserts bypass.
- **The 3-lote incident is a DIRECTION mismatch, not an overdraw:** the extra `DEV_CLI_EGR` (factor
  −1) were hand-posted with `destino_ubicacion` (ingress direction). `lote_saldo` nets to 0
  (location accounting balances), while factor-sum goes negative. **Only 5 such
  factor/direction-mismatched movements exist in the entire 486k-row ledger** — isolated to this
  incident, not systemic.
- **The 131 "orphan" lotes are unrelated** — all crudo, no origen-link, not dispatched: a separate
  new crudo receipt for the same tercero, not the reworked output. So the incident is self-contained.

---

## 2b. ASSESSMENT — correctness + the venta/dispatch relationship

**Domain mapping (mostly right):** the 3 functions cover concept #1 (crudo out), concept #2
(cliente in), and proveedor; concept #3 is correctly *not* a devolución (it's reproceso). The
`SERVICIO` vs `VENTA` split inside `registrar_devolucion_cliente` correctly follows ownership
(`SERV_DEV_ING` = client-owned service material back; `DEV_CLI_ING` = MLR-owned sold goods back).
Gap: the `DEV_CLI_ING` (sold-goods) path is **unused in practice** — adoption/wiring, not code.

**The venta/dispatch relationship — should a devolución reference venta/dispatch?** Answer differs
per concept, and the current code gets it *half right*:

| concept | was it sold? | should reference venta? | should reference the dispatch entrega? | current code |
|---|---|---|---|---|
| #2 dyed return (client QC) | **yes** (dispatched, venta exists) | **YES** — the return partially reverses that sale | **YES** — which shipment it reverses | links `entrega.venta_id` ✓ but does NOT store the source dispatch entrega, and does NOT adjust billing ✗ |
| #1 crudo return (service cancelled) | **no** (never dyed/sold) | **NO** | reference the **ingress** entrega + cancelled partida/service | **wrongly copy-pastes the venta link** (resolves NULL, dead/misleading) ✗ |
| proveedor | n/a (a purchase) | no — reference **compra**, not venta | the receiving entrega | verify |

**Three concrete correctness issues:**
1. **Crudo return's venta link is wrong** (`registrar_devolucion_crudo_cliente` L356-369) — a
   copy-paste from the cliente function. Crudo was never sold; the subquery finds no outbound
   dispatch, so `venta_id` lands NULL, but the *intent* is wrong. Concept #1 should reference the
   **incoming** entrega (the `CLIENTE_ENVIO_PROCESO` guía the crudo arrived on) and the cancelled
   service partida — its provenance is ingress + service, never a sale.
2. **Returns don't adjust the commercial side.** Both cliente functions link `entrega.venta_id` and
   `recompute_estado_comercial`, but neither reduces `venta_detalle` billed qty nor issues a credit.
   So a dispatched-then-returned roll still shows as fully sold on the venta — the same over-count
   family as the Track-B venta discussion. **Decision needed:** for #2-then-reprocess-then-redispatch,
   probably leave the venta whole (goods come back and go out again under the same venta); for a
   *permanent* return, the venta should net/credit. The functions currently can't tell these apart.
3. **The source dispatch isn't stored.** A return entrega only *derives* the venta transiently to
   copy `venta_id`; it never records *which dispatch entrega* it reverses. Weak traceability — a
   return should point at its originating dispatch (entrega→entrega link), not just share a venta.

**Architecturally, the right model:** a devolución IS an `entrega` (logistics doc) that references
(a) the **thing it reverses** — for #2 the original *dispatch entrega* + its venta; for #1 the
original *ingress entrega* + cancelled partida — and (b) leaves the **commercial** adjustment
(credit vs. leave-whole-for-redispatch) as an explicit, separate decision, not an implicit
side effect. Today it conflates "link a venta" with "reverse a sale," and does neither cleanly.

---

## 3. Proposed architecture

### 3.1 Movement-layer integrity guard (BEFORE INSERT on `item_movimientos`)
Two rejections, both currently missing and both implicated:
- **(a) Direction matches factor** — an egress-type (`factor < 0`) must set `origen_ubicacion_id`
  (not `destino`); an ingress-type must set `destino`. This is *the* bug that produced the 3-lote
  mess and is the cheapest to enforce.
- **(b) No negative saldo** — reject an egress that would drive the lote's saldo at that ubicacion
  `< -0.01` (float-dust tolerance matches the existing 92-dust convention).
- Bulk historical loads (Track B) already disable `corte_cuadre`; add this guard to the same
  disable set for those, ON for all normal operation.
- Since the incident is only 5 movements, this is preventive hardening, not firefighting — but it
  makes both classes of error *structurally impossible* going forward.

### 3.2 Concept #3 (internal reproceso) — make `crear_reproceso` reachable
When rolls fail *our* QC, the path is `crear_reproceso` — a partida **move**, no devolución, no
consumption (rolls consume at last step). The gap is that it isn't reachable from every state a
roll can fail QC in. Fix = ensure `crear_reproceso` accepts lotes from the relevant states (or a
thin wrapper), so the roll moves to a rework child **in stock**, keeping the genealogy (§3.4).

### 3.3 Concept #2 (client QC return → reprocess) — two SEPARATE steps, different actors
Per your point: **the person who receives the devolución is not the one who reschedules the run.**
So do NOT chain them in one call. Two independent, sequenced actions:
1. **Reception (comercial):** `registrar_devolucion_cliente` — dyed rolls come back **in**
   (`DEV_CLI_ING`/`SERV_DEV_ING`), linked to the original venta, back in stock. (Fix: this path is
   currently unused — wire the UI/permission so comercial actually uses it.)
2. **Rescheduling (producción, later):** `crear_reproceso` on the returned-in-stock lote → rework
   child → runs steps → re-dispatch. Same `crear_reproceso` as concept #3; the only difference is
   the lote arrived via a devolución vs. failed internal QC.

### 3.4 Reproceso genealogy — a partida-move ledger, NOT item_movimientos
Correction from earlier draft: because a roll is **not consumed** during reproceso (only at the
last step), reproceso is a `partida_componente` **re-assignment**, not a `PROD_CONSUMO`/`PROD_ING`.
So it does not belong in `item_movimientos`. Adopt **option 1** from `REPROCESO_GENEALOGY_TODO.md`:
a `mes.partida_componente_movimiento(lote_id, partida_id_from, partida_id_to, motivo, fyh_cre)`
ledger, written by both `crear_reproceso` (the move) and `mover_lotes_reproceso` (the reversal).
This records the true immediate source (fixing the reversal-to-root bug) without a recursive-CTE
read model, and keeps consumption where it belongs — the last step.

### 3.5 Reversal symmetry
Concept #2 reverses in order: `anular_reproceso` (corrected per §3.4) then
`anular_devolucion_cliente`. Concept #1/#3 reverse via their own `anular_*`. Block reversal if the
downstream (reworked output / re-dispatch) already moved on.

**Gap found 2026-07-29 (existing code, resurfaced by §3.4):** `anular_devolucion_cliente`
(funciones/devoluciones.sql:593-611) already has a downstream guard — but it only checks
`inventario.item_movimientos` for rows after the devolución's own movement. Once `crear_reproceso`
stops writing to `item_movimientos` (§3.4 — reproceso becomes a `partida_componente`
re-assignment, not a movement), a roll already moved into a rework partida would show **zero**
downstream movement rows, and the guard would wrongly allow anulling the devolución out from under
an in-progress rework. Fix: add a second clause checking the new `partida_componente_movimiento`
ledger (or current `partida_componente` assignment) for a reassignment since the return, alongside
the existing `item_movimientos` check. Same shape as the §3.1 integrity gap — a guard written
against only one of two ledgers that both carry roll provenance.
`anular_devolucion_crudo_cliente`/`anular_devolucion_proveedor` need no such guard (correctly, per
their existing code comments): both are terminal egress to an external party, so nothing on our
side can move the roll further afterward.

---

## 4. Cleanup of the incident
- **3 lotes (136721/173125/173126):** `lote_saldo` already nets to 0 (material out). Decision:
  **final state = returned once (net 0)**, matching concept #1 (undyed crudo returned, service
  cancelled). Cleanup = delete the duplicate + mis-directed `DEV_CLI_EGR` so each lote is exactly
  `SERV_ING(+20)` + one `DEV_CLI_EGR(origen, −20)` = net 0, factor-sum and location agree. (This is
  also the natural test case for the §3.1(a) direction guard.)
- **131 crudo lotes:** unrelated separate receipt — leave alone.

---

## 4b. FUNCTION DESIGN (separate per concept)

### Settled decisions this drives
- **Venta is never credited/reversed.** A return links to the sale but does NOT touch
  `venta_detalle` — the goods get reworked + re-dispatched under the **same venta**. So the venta
  is a *link*, never a *reversal*. (Removes the "should we credit?" ambiguity entirely.)
- **`entrega_origen_id` is DERIVED, never a caller-supplied parameter.** Earlier draft of this
  section listed it as an input alongside `items[]`; corrected 2026-07-29. The lote_id is already
  in `items[]`, and the true origin is unambiguous from `item_movimientos` (last egress movement
  for concept #2's lote, last ingress movement for concept #1's lote) — trusting a caller-passed FK
  instead reopens exactly the class of bug §3.1's guard exists to close (a value that can silently
  disagree with the real ledger).
- **Mixed-origin batches are rejected, not silently assumed single-source.** The prior draft's
  single header-level `entrega_origen_id` implicitly assumed every lote in `items[]` derives to the
  same origin entrega and never validated it — an oversight, not a considered constraint. Fixed
  design: derive per lote, group by resolved origin; if `items[]` resolves to more than one origin
  entrega, reject with the offending lotes in `DETAIL` and require the caller to split into one call
  per origin entrega (mirrors the §3.1 guard's error style). Simpler than pushing the FK down to
  `entrega_detalle`, and a devolución spanning two unrelated shipments is a business smell worth
  surfacing, not quietly accommodating.
- **Each return entrega records what it reverses** via a new self-FK `doc.entrega.entrega_origen_id`
  → the original dispatch (concept #2) or ingress (concept #1) entrega, now populated by derivation
  above instead of a passed-in value. Replaces the current fragile "derive the venta transiently"
  trick with explicit entrega→entrega lineage.
- **Separate functions per concept**, no shared copy-paste; concept #3 stays `crear_reproceso`.

### Concept #1 — `registrar_devolucion_crudo_cliente` (redesign)
Return client's **undyed crudo**, service cancelled.
- **Input:** `tercero_id`, `items[]` (lote_id, item_id, cantidad, ubicacion_id, n_rollos), serie/correlativo, fecha. `entrega_origen_id` is NOT an input — derived per lote from its last `SERV_ING` movement (the `CLIENTE_ENVIO_PROCESO` guía it arrived on); reject if the batch resolves to more than one origin entrega.
- **Guards (keep):** client · ROLLO only · entered from this client (`SERV_ING`) · sufficient stock.
- **Movement:** `DEV_CLI_EGR` (origen set, destino NULL — goes to client). ✓
- **References:** `entrega.entrega_origen_id` = the derived **ingress** guía. **Remove the venta link entirely** (never sold).
- **New side effect (decide):** cancel the service — set the linked partida `estado_produccion = CANCELADA`. ⚠ open: full vs partial (crudo lote may be one componente of a multi-roll partida — cancel whole partida only if all its crudo is being returned).
- `recompute_estado_comercial`.

### Concept #2 — `registrar_devolucion_cliente` (redesign)
Client returns **dispatched dyed** rolls (their QC) → to be reprocessed.
- **Input:** `tercero_id`, `entrega_tipo_id` (SERVICIO/VENTA), `items[]`, serie/correlativo, fecha. `entrega_origen_id` is NOT an input — derived per lote from its last dispatch (`VENTA_EGR`/`SERV_EGR`) movement; reject if the batch resolves to more than one origin entrega.
- **Guards (keep):** client · out-of-stock (was dispatched) · prior dispatch to this client.
- **Movement:** `SERV_DEV_ING` (servicio / client-owned) | `DEV_CLI_ING` (venta / MLR-owned) — inbound (destino set). Ownership branch stays.
- **References:** `entrega.entrega_origen_id` = the derived dispatch guía; `entrega.venta_id` = its venta (**link only, `venta_detalle` untouched**).
- **Does NOT** chain reproceso (different actor, §3.3). Ends with the roll back in stock, flagged pending-reprocess.
- `recompute_estado_comercial` (roll un-dispatched).

### Concept #3 — internal QC fail → `crear_reproceso` (existing, unchanged here)
No devolución. Producción runs `crear_reproceso` on the failed lote → rework child partida →
re-runs steps → re-dispatch. Genealogy ledger deferred to mlr-db.

### The #2 → #3 handoff (two actors, two actions)
1. Comercial: `registrar_devolucion_cliente` (roll back in stock).
2. Producción, later: `crear_reproceso` on that in-stock roll. Same entry point as concept #3 —
   a returned roll and an internally-failed roll are identical once they're back in stock awaiting rework.

### `anular_*` symmetry (keep, adjust)
Each function keeps its `anular_*` (reverse the DEV_* movement via `*_REV`, delete the entrega).
Add: clear `entrega_origen_id` linkage on anular; for concept #1, un-cancel the partida.

### RESOLVED design decisions (2026-07-28)
1. **Entrega chain** — every physical event is its own `entrega`, linked by `entrega_origen_id` to
   its immediate predecessor, forming a chain back to the first dispatch:
   `ingress → (first) dispatch [venta_id] → return [→dispatch] → rework-dispatch [→return]`.
   The whole history is walkable; the sale is always reachable by following the chain to the
   dispatch that carries `venta_id`.
2. **Concept #1 partida rule** — returnable crudo must **not be committed to an active partida**.
   Enforced as a **GUARD** (reject with the offending partida in DETAIL), NOT an auto-cancel:
   cancelling a partida is a *producción* action, so comercial's return can't silently cancel
   another team's work order. Producción cancels the service order first → comercial returns the
   crudo. (Revised 2026-07-29 — was auto-cancel; a hidden cross-team side effect is wrong.)

### Deferred to mlr-db (built as tested migrations, not hand-patched here)
- **Shared `_crear_entrega_devolucion` helper** — the three public devolución functions duplicate
  the entrega→detalle→movements→logs→recompute skeleton. Keep the 3 public functions (distinct
  business events: different direction/guards/references), but extract the skeleton into one private
  helper. DRY on plumbing, separate on domain. Touches all 3 functions → its own tested migration.
- **Rollo-scoped movement integrity guard** (direction + non-negative saldo; rollos only, never
  insumos; must allow SAP-311 transfers). Cross-cutting + high blast radius → pgTAP-tested change.
- **`partida_componente` genealogy ledger** (reproceso immediate-source tracking).
3. **Rework does NOT bill — it's on MLR.** The rework-dispatch is a **plain entrega only**: no new
   venta, no `venta_detalle` line. It carries `entrega_origen_id` → the return (so the original
   venta is discoverable via the chain), but adds zero charge. The original venta stays exactly as
   dispatched — never credited, never re-billed.
4. **Pending-reprocess signal = DERIVED, no new state column** (designer's call). A roll is
   "pending reprocess" when it is **in stock** AND (returned: has `DEV_CLI_ING`/`SERV_DEV_ING`)
   **OR** (our-QC-failed: `calidad.inspeccion` rejected verdict) AND **not yet moved into a rework
   partida**. Surface via `vw_pendiente_reproceso` unifying both entry points — a returned roll and
   an internally-failed roll are the same thing once back in stock. Single-source-of-truth from
   movements + inspeccion, consistent with the rest of the ledger; no flag to keep in sync.

### On "is venta the right hub?" (no formal commercial order)
Venta is fine as the **outflow / billing hub** (it's the sales-side mirror of `compra` — records
what went out + price), but it is **reactive** (created at dispatch), so it is NOT the order
anchor. The real "commercial order" role is already filled by **`mes.partida`** — created at
intake, carries `estado_comercial`/`estado_facturacion`, links the client and the work. So the
model is dual and healthy: **partida = intent/work order (upstream), venta = fulfillment/billing
outflow (downstream)**, per [[document-model-philosophy]] (partida≈production order, venta≈billing
doc, entrega≈delivery). The lack of a formal sales order is not a gap — the partida is that
order. **Consequence for devolución/reproceso: the flow is partida-centric** (rework = a new
rework partida; concept-#1 cancels a partida), with venta as a *downstream link only* — which is
exactly why "rework doesn't bill" and "venta never reverses" fall out cleanly. Treating venta as
the hub only becomes wrong if you try to hang **pre-dispatch** commercial state on it; that belongs
on the partida.

---

## 5. Open decisions — RESOLVED (2026-07-28) except one

1. **Overdraw/direction guard** — user unsure one existed; **confirmed none does.** Add §3.1 (a)+(b).
   The incident was actually (a) direction, so lead with that. *(Open sub-question: guard all egress
   movement types, or a whitelist — recommend all.)*
2. **Chained vs. separate** — **SEPARATE** (reception actor ≠ rescheduling actor). §3.3.
3. **Genealogy model** — **partida-move ledger** (option 1), not item_movimientos, because rolls
   consume only at the last step. §3.4.
4. **3-lote final state** — **returned (net 0)**; the 131 orphans are unrelated so don't affect it. §4.

### Remaining to decide before build
- Guard type scope (all egress vs whitelist).
- Whether the §3.4 partida-move ledger is built now with this, or scoped alongside the broader
  "genealogy wall" work — it's additive and cheap, so leaning "now".
- Sequencing: guard (§3.1) is independent + highest safety/effort — likely ship first.

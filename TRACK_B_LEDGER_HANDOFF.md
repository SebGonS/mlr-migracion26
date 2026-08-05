# Track B — Physical Ledger Completion — HANDOFF (2026-07-28)

**Read this, then `dispatch-qc-cleanup.md` + `venta-sales-hub.md` memory files.** This is
the "what's mid-flight / tackle next" picture. Written because the prior conversation got
long; nothing here should need re-deriving — the numbers below are measured, not guessed.

---

## ✅ TRACK B AUTO-BACKFILL COMPLETE (2026-07-28) — read this first

All buildable tranches committed. **Dispatched-via-entrega 32,682 → 96,180 / 97,187 (98.96%)**,
ledger clean throughout (0 real overdraw, 0 egress-without-ingress, double-entry intact).

| phase | script | partidas / rolls |
|---|---|---|
| 1 | `backfill_track_b_phase1_single_line.sql` | 2,515 / 50,021 |
| 1b | `backfill_track_b_phase1b_multi_venta.sql` | 411 / 6,839 |
| 3a | `backfill_track_b_phase3a_partial_fill.sql` | 56 / 1,024 |
| 2 | `backfill_track_b_phase2_rework_anchored.sql` | 57 / 929 |
| 4 | `backfill_track_b_phase4_last_step_anchor.sql` | 264 / 5,001 |
| 5 | `backfill_track_b_phase5_patch57_redispatch.sql` | 86 / 1,640 (+ deleted the bogus PARTIDA egress + patch-57 restock) |

**Phase 5** = the patch-57 restocked rolls (deferred by the ORIGINAL Track-B, then parked by
patch 57). Their crudo lotes always existed; only their dispatch was migrated as a placeholder
`SERV_EGR('PARTIDA')`. Phase 5 deletes that placeholder + the patch-57 `SERV_DEV_ING` (net-0
noise) and builds the real consume→dye→dispatch. 89 leftover stay as clean in-stock crudo.

**The remaining 1,007 rolls (1.04%) are the HARD FLOOR — nothing recoverable left:**
- **779 over-count** (return-redispatch, despacho > capacity, roll counted twice). No physical
  roll exists → PERMANENTLY unrecordable (recording = fabrication).
- **51 rib rolls `peso_rib=0`** — no weight; original import skipped them; fabricating = inventing weight.
- **~177 excluded patch-57** — in LIVE partidas (don't touch) or NO venta (no commercial record).

**Rule settled (user):** creating **lotes** for existing partidas is OK when no evidence of prior
migration AND no equivalent anywhere in the rework tree; **never create/re-migrate a partida**
(one was hard-deleted at client request). Verified: **0 despacho rows reference a non-existent
partida**, so nothing committed re-migrated a deleted partida. `partida_componente` == legacy
`partida.cantidad` for 454/464 (componente IS the legacy roll set).

**Still open (NOT Track-B ledger):** 3 `DEV_CLI_EGR` lotes −200 kg (user's manual rework-staging,
reconcile when the rework flow is wired); per-shipment venta-linkage precision for the multi-venta
partidas (deterministic `grp_key`, deferred); mlr-db baseline regen.

---

## ~~PRIORITY TASK~~ (COMPLETE — see above): complete Track B — the ~64k lote-less dispatch rolls

> This is the highest-value remaining item, but it is **high-risk** (double-entry / overdraw):
> a rushed or naive backfill can slam tens of thousands of lotes negative. **Prioritize
> correctness and the dry-run → verify → commit discipline over speed.** Do NOT skip the
> weight-source investigation (step 1) — it gates whether a faithful reconstruction is even
> possible. Better to stop and ask than to fabricate movements.

**The problem in one line:** the commercial layer (ventas) bills ~97k historically-dispatched
rolls, but the **physical ledger (lotes + `item_movimientos`) only exists for ~1/3 of them** —
~64k dispatched rolls have **no lote and no movement at all**. They exist only as venta lines.

This is NOT a phantom-inventory or overdraw bug (see "Facts" below — inventory is truthful,
ledger is balanced). It's an **incomplete physical history**: dispatched rolls with no egress
record because they were never created as lotes.

### The numbers (measured 2026-07-28)
| quantity | value | source |
|---|---|---|
| legacy dispatched rolls | ~97,187 | `SUM(public.despacho.rollos_total)` where `flg_elm IS NOT TRUE` |
| legacy produced (partida capacity) | 94,771 rollos / **98,686 incl. rib** | `public.partida.rollos (+ rib)` |
| current migrated output lotes | **30,274** | `mes.partida_paso_ejecucion` output lotes |
| rolls with an egress movement (SERV_EGR/VENTA_EGR) | **~32,682** | `item_movimientos` |
| **dispatched rolls with NO movement / NO lote** | **~64,000** | the gap |
| dispatched partidas with NO current output lote | **3,433 of 5,018** | |

### What Track B is (and its current state)
"Track B" = the production/dispatch **physical backfill** — `migration/operations_patching/backfill_track_b_production.sql`.
It gave **10,116 rolls / 525 partidas** a real `consume→dye→dispatch` lifecycle (PROD_ING
ingress + SERV_EGR egress, historical timestamps). It **deferred 1,956 rolls** (documented:
supply<demand, no compactado, live partidas, one return) — those became the "PARTIDA ghost
egresses" we restocked in patch 57. **It never covered the ~64k backlog.** Completing Track B =
extending that approach to the rest.

### The hard constraints (why it wasn't already done — do NOT violate these)
1. **Double-entry or overdraw.** Every egress MUST have a matching ingress. Currently the ledger
   has **0 egress-without-ingress** and **0 real overdraw** (92 lotes at −0.0012 kg = float dust).
   Posting the ~64k egresses *without* also creating their produce ingress would slam 64k lotes
   negative. So each roll needs the FULL lifecycle rebuilt, not just an egress.
2. **Faithful weights, not estimates.** The despacho→venta migration *estimated* `cantidad_kg`
   (`rollos × avg-weight`) and it overshoots actual moved kg by ~21%. A ledger backfill needs a
   **defensible per-roll weight source**. `public.partida` has `peso_rollos` + `peso_rib`
   (partida-level weights) — **FIRST TRACK-B TASK: determine whether per-roll or only
   partida-level weight data exists**, because that decides faithful-vs-estimated movements.
3. **Historical timestamps.** Dispatch egresses must carry the legacy dispatch date
   (`fecha_despacho`), like existing ones (all SERV_EGR/VENTA_EGR are 2025–2026 historical, 0
   backdated-to-now). Only *corrections* (like patch 57's restock) use `now()`.
4. **Don't exceed partida capacity.** ~100 partidas legacy-dispatched more than `rollos+rib`
   (likely unrecorded return-redispatches — see Facts). Don't fabricate rolls beyond what the
   partida produced; cap at capacity and flag the excess.
5. **Commercial records already exist** — do NOT create new ventas. The job is physical only:
   create lotes + PROD_ING + SERV_EGR, then LINK them to the existing ventas/entregas
   (`entrega.venta_id`, `entrega_detalle.venta_detalle_id`).

### Suggested Track-B approach (validate each step, dry-run → verify → commit)
1. **Scope the source data** — can we get per-roll weights, or only partida-level `peso_rollos`/
   `peso_rib`? Check `public.despacho` (rollos/rib/rollos_total), `public.partida`
   (rollos/rib/peso_rollos/peso_rib), `public.produccion_tenido` (kilos/rollos). Decide the
   weight rule (real if available; else documented partida-level proration, explicitly labeled).
2. **Per partida, compute the roll set to create** = dispatched rolls not already represented by
   a lote. Respect capacity (`rollos+rib`), split rib vs regular.
3. **Create lotes** (`documento_tipo='partida_paso_ejecucion'`? confirm the pattern Track-B used —
   read `backfill_track_b_production.sql`). Set `estado_calidad` per the QC verdict (patch 58's
   rule — pool auditoria final verdict; OK→APROBADO, else PENDIENTE).
4. **Post PROD_ING** (ingress, historical date) + **SERV_EGR/VENTA_EGR** (egress, dispatch date)
   grouped under `doc_movimiento_id` (mov_doc_seq). Non-negative saldo by construction.
5. **Link** to the existing entrega/venta (or create the entrega if none). Reuse patch 59's
   pattern for wiring `entrega.venta_id`.
6. **Verify:** 0 overdraw, 0 egress-without-ingress, dispatched-with-movement climbs toward ~97k,
   billed-kg ≈ moved-kg closes.

Mirror the existing `backfill_track_b_production.sql` — **read it first**; don't reinvent its
lote/movement/genealogy conventions.

---

## Phase 2 (rework-anchored) — ✅ COMMITTED (2026-07-28)

`migration/operations_patching/backfill_track_b_phase2_rework_anchored.sql` — **57 partidas
/ 929 real rolls**. Gap partidas with NO own compactado ejec but a REWORK CHILD that has
one: consume the parent's pristine rolls, produce dyed output anchored to the CHILD's
compactado ejec (production under child), dispatch to the PARENT's venta (**model: parent
always gets the dispatch**). Validated: 0 children already-dispatched (no double-egress),
0 mixed propietario, 0 intra-scope sharing. §2 clean; dispatched-via-entrega → 89,539.
15 zero-supply rework partidas DEFERRED (parent raw consumed into the rework).

## Phase 3a — ✅ COMMITTED (2026-07-28)

`migration/operations_patching/backfill_track_b_phase3a_partial_fill.sql` — **56 partidas
/ 1,024 real rolls**. The PARTIAL-FILL fix for the shortfall (supply<demand) partidas that
Phase 1/1b's all-or-nothing gate skipped whole: backfills all pristine componente rolls,
**caps at supply, flags the 550-roll excess** (genuine legacy over-dispatch — never
fabricated). §2 clean (1024/1024/1024). Health: 0 new overdraw, dispatched-via-entrega
→ 88,610. **Validated the 1,024 lotes are `SERV_ING`-only** (0 post-go-live movement, 0
live-partida reservation) — nothing touched after ingress. **`partida_componente` was
confirmed == legacy `partida.cantidad` for 454/464 in-scope partidas**, so componente IS
the legacy roll set (the sourcing question is settled).

## Phase 1b — ✅ COMMITTED (2026-07-28)

`migration/operations_patching/backfill_track_b_phase1b_multi_venta.sql` — **411 partidas
/ 6,839 rolls** (the multi-line / multi-shipment set). Same mechanic as Phase 1; §2 clean
(double-entry 6839/6839/6839). **Ledger-first linkage (user's call):** one entrega per
partida → PRIMARY venta (lowest-id live venta); the 392 multi-venta partidas link all rolls
to that one venta — exact per-shipment split DEFERRED to the billing cleanup (deterministic
despacho→venta grp_key: `F:/R:/N:` keys, see `migrate_despacho_to_venta.sql`).

## Phase 1 — ✅ COMMITTED (2026-07-28)

**Post-commit verified:** 0 real overdraw (92 float-dust negatives unchanged), 0
egress-without-ingress (double-entry intact), rolls-dispatched-via-entrega climbed
~32,682 → **80,747**, Phase-1 §0 scope collapsed to 0. Clean.

**Script:** `migration/operations_patching/backfill_track_b_phase1_single_line.sql`
(mirrors `backfill_track_b_production.sql` **minus its phantom-egress DELETE** — these raw
rolls are still in stock, never egressed, so we just consume→dye→dispatch).

**Weight basis DECIDED = B (proration).** No per-roll measured weight exists in legacy
(checked despacho/partida/produccion_tenido/item_rollo_detalle). The raw input rolls'
`lote.cantidad` was already prorated from `partida.peso_rollos`/`peso_rib` (Σ input kg ==
measured partida total for 3,458/3,507 gap partidas). The dyed child **inherits** that
weight — that IS proration, matches Track-B convention, reconciles to the measured total.

**Scope = 2,515 partidas / 50,021 rolls** (the clean, unambiguous subset):
despacho-referenced ∧ no output lote ∧ **not live/new** (incl. post-go-live pesaje —
user's "no peso record in the new system") ∧ has COMPACTADO ejec ∧ **PRISTINE** supply ≥
demand ∧ exactly ONE live venta line. supply(50,367) − demand(50,021) = 346 leftover raw
stay in stock. The full in-scope backlog is 3,390 partidas; Phase 1 is the safe first cut.

**"Overdraw" = LEDGER DOUBLE-EGRESS ONLY (user clarified).** The **PRISTINE guard** is the
protection: an eligible raw roll must be raw, in-stock (`saldo>0`), and carry NO prior
`SERV_EGR/VENTA_EGR/SERV_DEV_ING/PROD_ING/PROD_CONSUMO`. ⇒ no lote egressed twice; dyed
children are new lotes; consumption is stock-backed; 0 intra-scope roll sharing ⇒ no lote
consumed twice in-run. This guard also excludes the **1,729 patch-57 restocked rolls**
(sig `SERV_ING→SERV_EGR→SERV_DEV_ING`, slated for manual re-dispatch/rework) — their 54
dependent partidas defer to supply<demand.
**Reservation correctness (`partida_componente`) intentionally NOT guarded — deferred (user).**
One overlap left in scope: partida **4237**'s rolls also reserved by LIVE partida **6418**
(EN_PRODUCCION) — a single valid ledger egress here; the reservation conflict is later cleanup.

**Mechanic per roll:** PROD_CONSUMO raw (nets 0) → new dyed child lote (inherits weight,
`estado_calidad=APROBADO`, `origen_lote_id`=raw) → PROD_ING → **one entrega per partida
linked to the EXISTING venta** (`entrega.venta_id`; NO new venta) → `SERV_EGR/VENTA_EGR`
on legacy `fecha_despacho` → `entrega_detalle.venta_detalle_id` = the partida's single
billing line. Historical dates; `corte_cuadre` trigger disabled for the load.

**§0 validated:** 2515 / 50021 / 50367, all guards 0. **Expected §2:** (a) 50021/50021/50021/0
(b) 50021/50021/50021 (c) 2515/0/50021/0/50021 (d) 0 (e) 0 → then COMMIT.

**Deferred to later phases (NOT touched):**
- **Phase 1b:** 412 multi-shipment partidas — historical billing lines are COARSE
  (`articulo_id` NULL, `cantidad_rollos` NULL/0; only `tenido_id`+`color_x_cliente_id`
  populated) and multi-line partidas share the same tenido×color across ventas, so
  roll→line needs a despacho→venta **shipment** split.
- **T2:** 76 partidas whose only COMPACTADO ejec lives on a REWORK child (anchor there).
- **T3 residual:** supply<demand (~60 partidas / **574 excess rolls = the real overdraw
  exposure**, no roll to source — never fabricate), patch-57 restock/rework rolls (1,729),
  no-supply (partida 4955), shared-with-live (4237).

---

## ✅ Committed this session (DB is live with all of these)

| patch | what |
|---|---|
| `patches/54_add_venta_referencia.sql` | `doc.venta.referencia_serie/correlativo` (TEXT, non-unique), backfilled 2,115 verbatim from legacy `despacho.nfactura` |
| `patches/55_venta_drop_factura_estado.sql` | dropped `factura_serie/numero/fecha_venc`, `estado`, `venta_estado_enum`, `uq_venta_factura`; reworked `registrar_despacho` (one venta per dispatch, no tab-reuse), `facturar_venta`→`asignar_referencia_venta`, `anular_venta`→soft-delete; reworked `vw_venta` + `vw_partida_comercial` |
| `patches/56_venta_detalle_item_grain.sql` | `venta_detalle` → item-grain (`+articulo_id, +cantidad_rollos`); new `doc.venta_detalle_cargo` (per-op charges); `+entrega_detalle.venta_detalle_id`; history→1-cargo migration; dropped `operacion_id/precio_kg/importe`. `registrar_despacho` reworked for per-articulo cargos (`fn_descripcion_linea`/`vw_venta` too) |
| `patches/57_restock_partida_ghost_egresos.sql` | restocked 1,955 bogus PARTIDA ghost egresses via `SERV_DEV_ING` (non-valorizable counterpart) |
| `patches/58_qc_auditoria_migration.sql` | legacy QC `public.auditoria` → `calidad.inspeccion` + `lote.estado_calidad`; **28,659 rolls PENDIENTE→APROBADO** (dispatchable); final-verdict-wins pooled on rework root; guards: existing-inspeccion, consumed/reserved rolls |
| `patches/59_bare_venta_ghost_entregas.sql` | 30 real-but-unbilled ghost entregas → bare ventas (56 item lines, NO cargo — no legacy rate); kg/rollos from ACTUAL lote weights so they reconcile with movements |

Frontend contract for 54–56 documented in `mlr-app/VENTA_REFERENCIA_FRONTEND_CHANGES.md`
(Part 1 referencia + Part 2 per-item billing).

---

## Key reconciliation FACTS (established — do not re-derive)

- **Inventory is NOT overstated.** Only 3,632 output lotes in stock (incl. the 1,955 restocked);
  only **61 "billed-but-in-stock"** (5 partidas, mostly partial-dispatch = benign). No pool of
  dispatched-but-in-stock rolls.
- **Ledger is balanced.** 0 egress-without-ingress; 0 real overdraw (92 @ −0.0012 = float dust);
  0 rolls egressed twice (no double-egress).
- **Commercial billing is faithful 1:1 with legacy** (6,704 despacho rows → 6,704 venta lines,
  `precio_unit` as-is). The migration introduced **zero** new/over-billing.
- **Over-dispatch was mostly a rib artifact.** Against `partida.rollos` alone: 2,486 "over".
  Against `partida.rollos + rib` (correct): only **100 partidas** over, total dispatched (97,187)
  is actually < capacity (98,686). The genuine return-redispatch exposure = ~100 partidas,
  ≤42 rolls each — legacy billed them (no devolución credits existed); we preserved, didn't
  invent-away. List them if the user wants case-by-case judgment.
- **billed-kg >> moved-kg is the Track-B gap, not a billing error** — most rolls have no
  physical lote.
- **QC touched lotes** (attribute update on existing lotes) — that's why it was doable; the
  ledger gap is lotes that don't exist, which is object-creation (hard). Same principle held
  throughout: touch what's real, don't fabricate what isn't.

---

## Other open items (lower priority than Track B)

- **Frontend follow-up** — implement `mlr-app/VENTA_REFERENCIA_FRONTEND_CHANGES.md` (referencia
  rename + per-item billing/dispatch-drawer prune step). Hand to the frontend agent.
- **`mlr-db` baseline regen** — sibling clean repo (`mlr-db`, Supabase migrations). Regenerate
  its baseline from a post-cleanup prod dump so it's native to all of the above. Do AFTER the
  frontend contract settles. See its `README.md`/`CLAUDE.md`.
- **The 2 legacy `devolucion` rows** — no-op (physical rework already happened; migrating would
  double-post). Documented, closed.
- **92 float-dust negative saldos** (−0.0012) — harmless; optional one-line cleanup.

---

## DB access / tooling

- Read-only role `claude_ro` (BYPASSRLS + SELECT on doc/mes/inventario/receta/public/calidad).
  Password in `%APPDATA%\postgresql\pgpass.conf`. Host `db.etsldmkjaniejslehqtw.supabase.co:5432`,
  db `postgres`.
- Run: `psql "host=db.etsldmkjaniejslehqtw.supabase.co port=5432 dbname=postgres user=claude_ro sslmode=require" -c "…"`
  — starts with `psql` (auto-reads pgpass), matches the `Bash(psql *)` allow rule, no prompt.
- **Writes (§1/COMMIT of any patch) are run by the USER** — `claude_ro` is read-only. Pattern
  every patch follows: §0 dry-run (read-only, I run) → §1 in a txn (user) → §2 verify → COMMIT.
- **Prefer grouped/aggregate queries** over raw row dumps (user's token-budget preference).
- `public.*` tables = the **legacy** system (despacho, partida, auditoria, produccion_tenido,
  devolucion, cliente). `doc/mes/inventario/calidad/receta` = the **new** schema.

## Memory files (auto-loaded)
`dispatch-qc-cleanup.md`, `venta-sales-hub.md`, `pricing-ownership-model.md`,
`grupo-articulo-dye-substrate.md`. Do NOT delete/modify the
`migration/diagnostics/auditoria_*` + `debug_qc_*` scripts (user's prior-design fallback).

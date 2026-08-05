# Venta Migration Session Handoff — 2026-07-20

**Read this first, then `PRICING_OWNERSHIP_MODEL.md` and `VENTA_MODULE_HANDOFF.md`.**
This file is the immediate "what's mid-flight" picture; those two are the settled
design record. Don't re-litigate anything marked DONE/VERIFIED below.

---

## Where things stand

### ✅ DONE & COMMITTED (do not redo)

1. **Track B production backfill** — 10,116 rolls / 525 partidas given a real
   consume→dye→dispatch lifecycle (`migration/operations_patching/backfill_track_b_production.sql`).
   1,956 rolls deferred with documented reasons (supply<demand, no compactado, live
   partidas, one return) — see `entrega-ingress-normalization` memory / project notes.
2. **Despacho → venta migration** — `migration/operations_patching/migrate_despacho_to_venta.sql`,
   RUN and verified. 6,704 legacy `despacho` rows → 2,115 `doc.venta` (961 FACTURADA +
   1,154 ABIERTA) + 6,704 `venta_detalle` lines. Pricing migrated **as-is** (validated
   per-kg, no roll conversion — see `PRICING_OWNERSHIP_MODEL.md`). MLR self-dispatches
   (tercero 1) included as ordinary VENTA sales per client decision. 42 factura
   conflicts resolved (most-kg wins, losers → ABIERTA + raw ref in `observacion`).
   353 MLR rows flagged as incomplete sales (only the dye charge was ever recorded).
3. **Design docs**: `PRICING_OWNERSHIP_MODEL.md` (kg-canonical pricing, ownership
   switch, migration rules — READ THIS before touching any pricing logic) and an
   audit section appended to `VENTA_MODULE_HANDOFF.md` §5.

### ⏳ IN PROGRESS — pick up here

**A. Null-factura cleanup (small, scoped, ready for final query)**

Diagnostic history: `null_factura_breakdown.sql` (v1) mis-flagged `G01-*`/`G03-*`/`G06-*`
internal refs as "correctable format" — bug in that query's regex (it didn't require a
real `F`/`B` factura prefix). Corrected version is
`migration/diagnostics/factura_format_fixable_v2.sql` — **I wrote it but the user has
not run it yet.** Run its §1 and §2 next.

What we know so far from the (buggy) v1 breakdown, for calibration:
- 1,036 ventas: `GI-*`/`G0x-*` internal refs — correctly NULL, no action.
- 55 ventas: lost the 42-conflict most-kg tiebreak — correctly NULL, client said "swallow it."
- 46 ventas: genuine multi-factura (comma-separated, e.g. `GI-631,632`) — correctly NULL.
- Genuinely fixable (real typo on an actual F/B factura): so far only **`F/002-0010502`**
  (stray slash) confirmed. `F-9460` is an edge case — looks real but has no `002`-style
  branch digits; **do not guess/fabricate** the missing digits, if fixed at all keep
  serie exactly `F` as written. `F002-0010805.10806` is NOT fixable — it's a
  period-separated multi-factura (two refs), same family as the comma cases, correctly
  stays NULL.

**Next step:** run `factura_format_fixable_v2.sql` §1/§2, get the real (small) list of
fixable rows + their collision check (§2 tests against both existing ventas' facturas
and against each other, since assigning them enters the same global-unique-index
universe as the original 42-conflict resolution). Then write a small
`UPDATE doc.venta SET factura_serie=…, factura_numero=…, estado='FACTURADA' WHERE id IN (...)`
scoped to just those rows — same dry-run → verify pattern as every other patch this
session (see `migrate_despacho_to_venta.sql` for the pattern to mirror: §0 dry-run,
§1 txn, §2 verify, then COMMIT).

**B. Per-roll price display (drafted, then reverted by user)**

The user spotted a venta line showing `precio_kg=25` for a VENTA product and initially
read it as "should be per-roll." **Verdict reached: the $25/kg figure is very likely
CORRECT** — it's squarely in the validated MLR sale-price range (~$24.10/kg average,
proven via `venta_price_partida_overlap.sql`'s economics test earlier this session).
The actual gap is that `doc.vw_venta` has **no per-roll column at all** to let staff
sanity-check kg vs roll pricing at a glance — this was always a known open item
(`PRICING_OWNERSHIP_MODEL.md` → "Open items" → "Per-roll invoice presentation").

I drafted an edit to `migration/08_views.sql`'s `doc.vw_venta` adding two computed
columns:
```sql
rollos.n_rollos AS rollos_despachados,
CASE WHEN rollos.n_rollos > 0 THEN ROUND(vd.importe / rollos.n_rollos, 2) END AS precio_rollo
```
computed via a `LEFT JOIN LATERAL` that traces `entrega_detalle → lote →
partida_paso_ejecucion → partida_paso → partida` for entregas where
`entrega.venta_id = v.id`, matched to `vd.partida_id` (root). NULL where it can't
resolve (unlinked entrega, lote-less migrated line) — **never a fallback estimate**,
per what we explicitly agreed (`importe / n_rollos from entrega_detalle`, not a
kg/roll ratio guess).

**The user reverted this edit** — said they just wanted a status read, not the change
applied yet. **The edit is NOT currently in `08_views.sql`.** If asked to proceed:
re-apply the same `LEFT JOIN LATERAL` addition to `doc.vw_venta` (additive,
`CREATE OR REPLACE VIEW`, safe to run standalone — touches no data). Confirm with the
user whether it was ever actually run against the live DB before this revert (if only
reverted at the file level and never run, there's nothing to undo DB-side; if it WAS
run, the view already has these columns and reverting the file alone doesn't remove
them — would need to re-run the original column list to truly revert).

**C. Possible schema mismatch — UNRESOLVED, higher priority than it looks**

While reading `08_views.sql` I noticed current `doc.vw_venta` joins
`venta_detalle.grupo_articulo_id → grupo_articulo` — but `migrate_despacho_to_venta.sql`
(the committed migration) inserted into **`articulo_tipo_id`**, not `grupo_articulo_id`.
This suggests `venta_detalle`'s schema may have moved from `articulo_tipo_id` to
`grupo_articulo_id` (consistent with the `grupo_articulo` migration mentioned in
project memory — migration/28, "extracts articulo_tipo's 3 hidden jobs and retires it").

**I wrote `migration/diagnostics/venta_detalle_schema_check.sql` to check this — it has
NOT been run yet.** This is the single most important unresolved thread: if
`grupo_articulo_id` is the real column and my migration wrote to a stale/unused
`articulo_tipo_id`, **all 6,704 migrated venta_detalle lines are missing their article
classification** and will display blank in any view that reads `grupo_articulo_id`
(including current `vw_venta`). Run this FIRST before anything else — if it confirms
the mismatch, the fix is a straightforward `UPDATE venta_detalle SET grupo_articulo_id = …`
backfill from the partida's actual grupo_articulo, not a re-migration.

### 📋 Still open, not started this session

- **41 unlinked outbound entregas** — `migration/diagnostics/unlinked_outbound_entregas.sql`
  written, not run. Either the entrega's partida has no despacho row, or a tercero
  mismatch. Small, non-blocking.
- **Auditoría/QC migration** (`public.auditoria` → `calidad.inspeccion` +
  `lote.estado_calidad`) — fully designed earlier this session (final-verdict-wins
  rule: latest `fecha_auditoria` per partida; pooled on rework original; validated
  against real timestamps — every Observado ended later-OK, zero held). **Never
  built.** This gates whether migrated dyed rolls even show as dispatchable in the
  live app's QC filter (`vw_despacho_pendiente` reads `estado_calidad='APROBADO'`).
- **~68k lote-less dispatches** — now have venta/commercial records (this session's
  migration), but zero physical trace (no lote, no entrega, no movement) because an
  earlier production-output migration never ran for them. Known, undecided whether/
  how to backfill.

---

## Key facts to NOT re-derive

- go-live cutoff: `'2026-05-25 15:27:52+00'::timestamptz`
- `despacho.precio_unit` is **uniformly per-kg**, migrate as-is, NEVER convert
  (disproven twice this session — see `pricing-ownership-model` memory for the full
  reasoning chain, it's worth reading before touching pricing again)
- `uq_venta_factura` unique index is **GLOBAL** `(factura_serie, factura_numero)`,
  confirmed via `pg_indexes` — NOT per-tercero. `migration/27_venta.sql`'s comment
  claiming "unique per client" is STALE, doesn't match the live DB.
- `venta_detalle` has no `lote_id` by design (handoff decision #11) — any per-roll
  computation must trace through `entrega_detalle`/lote genealogy, never assume a
  direct link.
- Migration user convention: `usr_cre = 4` for these patches — but that ID is reused
  by OTHER prior migrations too, so don't use `usr_cre=4` alone to scope a verify
  query; use the run's own temp tables when possible (see Track B backfill for the
  pattern).

Relevant memory files (auto-loaded): `venta-sales-hub.md`, `pricing-ownership-model.md`.

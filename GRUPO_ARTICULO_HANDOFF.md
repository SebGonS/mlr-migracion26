# grupo_articulo — Migration Handoff

**Status as of 2026-07-20.** Migrations 28–33b applied, verified (pricing baseline diff clean).
Migration 35 (rib → real articulo) applied, verified. **Next: migration 36 (retire `flg_rib`) —
see bottom of this file.**

> ### ✅ RESOLVED 2026-07-20 — the half-state below is closed
> 33b landed and was verified via `migration/diagnostics/pricing_baseline_snapshot.sql` §2 (zero-row
> diff — every partida resolves the same `precio_kg` as before the swap). All `funciones/*.sql` pricing
> paths are on `grupo_articulo_id`. Kept below for history; do not re-check the exposure queries, they're
> no longer meaningful (nothing writes `articulo_tipo_id` at all anymore, by design).

---

## The problem being solved

`articulo_tipo` was doing **four jobs**: product taxonomy, recipe identity, pricing bucket, and batch
composition guard. Jobs 2–4 are properties of *the fabric a bath dyes as one unit* — which had no entity.

Root cause: `articulo.articulo_tipo_id` is a **single FK (1:N)**, so a fabric belongs to exactly one type
and a mixed batch **cannot reference existing fabrics**. Operators had to forge new ones. The workarounds
were live in prod and are the proof:

| workaround | what it is |
|---|---|
| `J 30/1-Gam 50/1` (articulo_tipo 15) | forged articulo + items, so a two-fabric batch looks like one |
| `Jersey/Gamuza` (articulo_tipo 20) | placeholder type with **zero** articulos — never used, confirmed dead |
| `item_rollo_detalle.flg_rib` | receives rib under the **body's** articulo so it clears the type guard |

`grupo_articulo` is that missing entity: an **N:M set of articulos** that share a bath and a recipe.
Job 1 turned out to be vacuous — `articulo_tipo` is a near-duplicate of `articulo` (same names, ~1:1;
there is no `Jersey` node, the values *are* fabric specs like `J 30/1 Pei`), so it retires entirely.

---

## Migration status

| # | File | Contents | State |
|---|---|---|---|
| 28 | [migration/28_grupo_articulo.sql](migration/28_grupo_articulo.sql) | `grupo_articulo` + `grupo_articulo_miembro` + `vw_grupo_articulo`; seeded 1 grupo per articulo_tipo (**32 grupos**) | ✅ applied |
| 29 | [migration/29_receta_tenido_grupo_rekey.sql](migration/29_receta_tenido_grupo_rekey.sql) | `receta.tenido.grupo_articulo_id` + backfill; **the 5 NULL-fibra `UPDATE` is appended at the bottom** | ✅ applied |
| 30 | [migration/30_partida_grupo_articulo.sql](migration/30_partida_grupo_articulo.sql) | `mes.partida.grupo_articulo_id` + backfill; `articulo_tipo_id` → nullable | ✅ applied |
| 31 | [migration/31_receta_grupo_index_swap.sql](migration/31_receta_grupo_index_swap.sql) | active-recipe index re-keyed to grupo; immutability trigger extended | ✅ applied |
| 32 | [migration/32_partida_grupo_flip.sql](migration/32_partida_grupo_flip.sql) | `grupo_articulo_id` `SET NOT NULL`; **the mixed-batch wall deleted** | ✅ applied |
| 33 | [migration/33_pricing_grupo_articulo.sql](migration/33_pricing_grupo_articulo.sql) | grupo columns on `catalogo_precios`, `articulo_tipo_familia` (in place), `venta_detalle` | ✅ applied |
| 33b | [migration/33b_pricing_function_swap.sql](migration/33b_pricing_function_swap.sql) | `factura_detalle` grupo column (33's own gap) + explicit drops for the signature-changing functions/views, re-key `uq_catalogo_precios_activo` | ✅ applied |
| 33b | `funciones/facturacion.sql`, `despacho.sql`, `receta.sql`, `mes.sql`, `migration/08_views.sql` (vw_venta) | pricing/billing function + view conversions | ✅ applied, verified — [pricing_baseline_snapshot.sql](migration/diagnostics/pricing_baseline_snapshot.sql) §2 diff clean |
| 34 | — | drop `articulo_tipo_id` columns, rename `articulo_tipo_familia` → `grupo_articulo_familia` + swap its unique indexes, retire `articulo_tipo` | ⬜ deferred — deliberately not started, kept for reference; see decision 12 |
| 35 | [migration/35_rib_como_articulo.sql](migration/35_rib_como_articulo.sql) | rib retired as a `flg_rib` clone of the body articulo; two real fabrics created (`Rib Algodón`, `Rib Poliéster`), historical rolls repointed, forged items soft-deleted | ✅ applied, verified — see decision 13 |
| — | `migration/08_views.sql`: `mes.vw_partidas`, `mes.vw_partida_familia`, `calidad.vw_auditoria_pendiente`, `mes.vw_pesaje_pendiente`, `doc.vw_catalogo_precios_historico` | **found 2026-07-20, fixed same day** — these five views were never converted in 33b. They joined `articulo_tipo` off the source tables' `articulo_tipo_id` (`mes.partida.articulo_tipo_id` for the first four, `doc.catalogo_precios.articulo_tipo_id` for the last), which 32/33b leave to drift to NULL (no bridge, by design) — so every partida/price row created since the cutover showed NULL `articulo_tipo`/`articulo_tipo_id`, and `grupo_articulo_id`/`grupo_articulo` was never exposed at all. `vw_auditoria_pendiente` (QC audit board) and `vw_pesaje_pendiente` (weighing board) weren't in the original report — found by grepping the whole file for remaining `articulo_tipo` hits after fixing the three that were. Swapped all five to join `grupo_articulo` off `grupo_articulo_id` (each view dropped first — column rename, not append). `doc.vw_pendientes_proceso` was also flagged but is NOT the same bug: its `articulo_tipo_id` comes from `articulo.articulo_tipo_id` (taxonomy "Job 1", untouched until migration 34, still populated normally) — left as-is; whether it should also carry `grupo_articulo_id` is a product question (an `articulo` is N:M with `grupo_articulo`, not 1:1, so there's no single value to project per row without a policy call). | ✅ applied |
| 36 | — | retire `flg_rib` itself: ~20 count/pesaje sites in `funciones/mes.sql`, `migration/08_views.sql`, `funciones/calidad.sql` re-derive rib-ness from the articulo instead of the flag, then drop the column | ⬜ next |
| 49 (patch) | [migration/patches/49_familia_precio_grupo_writable.sql](migration/patches/49_familia_precio_grupo_writable.sql) | drops `NOT NULL` on `doc.articulo_tipo_familia.articulo_tipo_id`/`familia_id` — until 33, the table only ever had rows *read* (`fn_familia_precio`); there was no write path at all (`authenticated` had SELECT only), and the two legacy columns being `NOT NULL` + FK'd to `articulo_tipo` meant no row was insertable for any grupo without an `origen_articulo_tipo_id` (i.e. every grupo created after the migration/28 seed — none exist yet, but the wall was still there). New write path: `doc.upsert_familia_precio(p_grupo_articulo_id, p_tercero_id, p_familia_grupo_id)` in `funciones/facturacion.sql`, which deliberately never populates the two legacy columns (manual dedup, since the existing partial unique indexes are still keyed on `articulo_tipo_id` and don't see NULL-vs-NULL duplicates). Read model: `doc.vw_familia_precio` in `migration/08_views.sql`, with a `flg_bucket_remapped` column that surfaces the one-hop-only landmine `fn_familia_precio`'s comment warns about (a bucket that is itself mapped elsewhere). | ⬜ apply |

### Functions already converted (in `funciones/`, applied)

- [funciones/core.sql](funciones/core.sql) — `crear_partida` (clean break to `grupo_articulo_id`, composition
  guard vs `grupo_articulo_miembro`, **fibra ceiling**), `actualizar_partida`
- [funciones/receta.sql](funciones/receta.sql) — `crear_tenido`, `actualizar_tenido`, `transicionar_tenido`,
  `resolver_tenido_id` (**wall removed**), `solicitar_si_ausente`, all 3 immutability guards
- [funciones/mes.sql](funciones/mes.sql) — reproceso inherits `grupo_articulo_id`

---

## Settled decisions — do not relitigate

1. **A grupo is a set of fabrics that can share one bath and come out right.** Dye compatibility is the
   physical fact; the recipe is *downstream*. Never describe it as "per recipe" — that inverts cause and effect.
2. **A grupo exists per unique *recipe*, not per combination.** Compositions sharing a recipe share one grupo.
   Confirmed: body-alone and body+rib use the **same recipe** → one grupo, **no recipe duplication**
   (recipe count after == before).
3. **Granularity is a shade-tolerance judgement**, already being made: `F Poly` lumps 12 blend variants
   under one recipe.
4. **Identity is `firma`** (sorted member-id signature). `nombre` is a label only — pure grupos keep the
   former articulo_tipo name; mixes are named for the fabrics combined; **rib membership never enters the name**.
5. **`fibra` = number of dye systems**, and it is TWO attributes: `articulo.fibra` = *required*;
   `partida/receta/catalogo.fibra` = *run*. **Run may be LESS than required on purpose — colores jaspeados.**
   Hence a **ceiling**, never a derivation: `partida.fibra <= MAX(member articulo.fibra)`.
6. **Naming**: `grupo_articulo`, not `sustrato` (clearer in the Lima textile domain; *sustrato* reads as
   agricultural growing-medium in Peruvian Spanish).
7. **Clean break** on `crear_partida`'s payload — takes `grupo_articulo_id`, rejects `articulo_tipo_id`.
   The frontend must send the new key.
8. **No bridge trigger.** `articulo_tipo_id` is left to drift to NULL. 32+33 deploy together, so there is
   no gap to bridge. (An earlier trigger-based bridge was written and then removed — do not reintroduce it.)
9. **Forged mix `J 30/1-Gam 50/1`** = the **plain** articulos `J 30/1` (14) + `Gam 50/1` (9), confirmed.
   Its 57 rolls stay on the forged articulo 28 (all still in stock, never consumed); re-attributing them
   half-half would be inventing data.
10. **`Jersey/Gamuza` (grupo w/ `origen_articulo_tipo_id = 20`)** — dead as a *substrate*
    (0 articulos, 0 partidas, 0 rolls). Do not populate membership.
    **⚠ AMENDED 2026-07-19 — do NOT soft-delete it yet.** It is dead as a substrate but **live as a
    pricing bucket**: patch 25 seeds `familia_id = 20` as the flat-rate family for clients 1/11/22
    (11 rows each), and migration 33 points `familia_grupo_id` at exactly that grupo. Nothing filters
    `grupo_articulo.fyh_elm` today, so nothing breaks — but soft-deleting it as "cleanup" would silently
    drop three clients to wildcard pricing the moment anything starts filtering. Unblocks when the
    `doc.familia_precio` header lands (backlog).
11. **`familia` stays separate from `grupo`.** Pricing-similarity and dyeing-similarity cross-cut; merging
    them would re-overload grupo exactly as articulo_tipo was overloaded.
12. **Familia re-keys IN PLACE, not into a new table** (33 §2). Every column re-keys, so there is no payload
    to preserve — a new table would re-derive the pairing through two `origen_articulo_tipo_id` joins where
    a miss silently drops the row. `ALTER` keeps it 1:1 by identity and avoids a divergence window
    (`fn_familia_precio` reads the old table until `facturacion.sql` lands). Rename → `grupo_articulo_familia`
    in 34. **The rule is "does the table have content that survives the re-key"** — `catalogo_precios` and
    `venta_detalle` do, so those add a column alongside; familia does not.
13. **Rib retirement — the model, confirmed empirically 2026-07-20:**
    - **The signal for "genuine rib fabric" is `articulo.nombre ILIKE '%rib%'`**, not item name (item names
      always say "Rib X" regardless — that's not the tell). A genuine rib has its own dedicated identity: own
      `articulo_tipo` historically, own `grupo_articulo`, real approved recipes run under its own name. Example:
      `Rib Lycrado` (id 3), `Rib Acanalado` (id 49), `Rib BVD` (id 57) — each has its **own** 1:1 `articulo_tipo`
      (3, 32, 34 respectively, same name as the articulo), confirming `articulo_tipo` really is the "near-duplicate
      shadow of articulo" the original 28 rationale described — there is no shared "Rib" bucket tipo to borrow.
    - **Everything else with `flg_rib=true`** was a workaround, not a fabric: a *duplicate item* pointing at the
      **body's** articulo (e.g. item "Rollo Rib J 30/1" → `item_rollo_detalle.articulo_id` = J 30/1 itself), purely
      so a roll could exist with the flag set. ~37 such items existed pre-35 (20 at fibra=1, 17 at fibra=2),
      including several `Paquete de Cuellos`/`Paquete de Tiras` accessory items following the identical pattern.
      The database was asserting ~5,190 rib rolls **were** body fabric — a false claim, not a missing one.
    - **Resolution (migration 35):** two new real fabrics, `Rib Algodón` (fibra 1) and `Rib Poliéster` (fibra 2),
      split on which body fibra they served. Confidence differs: **Algodón is chemistry-forced** (cotton-body
      baths run RX/DIR only — a poly rib there would come out visibly undyed, so the rib dyed in those baths must
      be cellulosic). **Poliéster is inferred from context, not forced** (poly-body baths carry RX+DISP, which
      would dye either fiber acceptably) — correctable later without needing to undo anything, since subdividing
      a grupo membership is additive.
    - **History was repointed, not left alone** — the opposite call from decision 9's forged-mix rolls. There,
      honoring history meant leaving rolls alone because fixing them required inventing an unknowable 50/50 split.
      Here, repointing invents nothing: the roll **is** rib, the schema just said otherwise. Replacing a known-false
      claim with a true one is a correction. Verified via roll-count invariant: `flg_rib` counts (5190 rib /
      142933 regular) were bit-identical before and after — nothing was gained or lost, only re-labeled correctly.
    - **`flg_rib` is NOT retired yet** (migration 36, not started) — ~20 sites still read it for
      `cantidad_regular`/`cantidad_rib` counts and pesaje proration. It is written as `true` on the two new rib
      items so nothing breaks in the meantime.
    - **Routing is unaffected and was never blocked on this** — confirmed 2026-07-19 that nothing in the codebase
      routes a paso/operación on `flg_rib`. The backlog's "do not build termofijado routing on `flg_rib`, route on
      composition/construction" note stays valid guidance for *future* routing work, not a dependency of 35/36.
    - **Environment gotcha, costly to rediscover:** the SQL client used for these migrations executes each
      statement as a separate round trip (visible as multiple "Started executing query at Line N" entries for one
      pasted script), consistent with a transaction-pooled connection. `TEMP TABLE ... ON COMMIT DROP` does NOT
      survive to the next statement under this — use a real table, drop it explicitly at the end of the script.

---

## Hard-won gotchas — expensive to rediscover

- **`uq_receta_tenido_aprobada` has SIX columns** — it includes `tipo_receta_id`.
  [migration/06_receta_tables.sql](migration/06_receta_tables.sql) documented five and **did not match live**
  (corrected 2026-07-18). ~50 groups of approved recipes share the other five and differ only by recipe type.
  `resolver_tenido_id`'s `LIMIT 1` is only safe *because* of that column.
- **Never key on `grupo_articulo.id` in a patch.** The seed has no `ORDER BY`, so ids shift across re-seeds
  (Jersey/Gamuza was 17, then 19). Key on **`origen_articulo_tipo_id`** or `codigo_canon`.
- **Schema-qualify `DROP INDEX` / `ALTER INDEX`.** Indexes live in `receta`, which is not in the session
  `search_path`; unqualified they **silently no-op** ("does not exist, skipping") while the index sits there.
  `CREATE INDEX` **cannot** be qualified — it inherits the table's schema. Asymmetric, and it cost an hour.
- **Recipe immutability now blocks `EN_PROCESO` as well as `COMPLETADO`** (all 3 guards). Editing a recipe
  mid-run is stricter than before — **tell the lab**, they'll hit it. `OMITIDO` deliberately does not block.
- **`receta.get_tenido_versiones` is FUNCTIONAL, not display.** It matches versions on the whole spec tuple
  incl. `articulo_tipo_id`; with NULLs the row-comparison yields NULL and it returns **empty, silently**.
- **IDE SQL diagnostics are false positives** — the workspace uses a SQL Server (T-SQL) language server that
  cannot parse `$$`, `DO`, `IF NOT EXISTS` on indexes, or `ALTER INDEX … RENAME TO`. Set the dialect to
  PostgreSQL. Do not "fix" valid Postgres to satisfy it.
- **`crear_partida` had lost its fabric guard entirely** before this work (the `articulo_tipo` equality check
  had been removed from the file). 32 *restores* protection as a membership check — it is a tightening.

---

## DONE (2026-07-19) — migration 33's function conversions

All four `funciones/*.sql` files plus `migration/08_views.sql` (vw_venta) are
converted onto `grupo_articulo_id`. Not yet applied to the DB — apply
`migration/33b_pricing_function_swap.sql` first (drops), then re-apply the
files below in the order 33b's header specifies, in one session/transaction.

**Dependents the original task list did not name** (found by reading callers,
not by grepping function names — grep only finds textual references to
`fn_get_precio`/`fn_familia_precio`, and several of these never call either):
- `doc.vw_precios_estado`, `doc.vw_precios_pendientes` (transitive — the latter
  selects FROM the former, never mentions the function)
- `doc.factura_detalle` — 33 re-keyed catalogo_precios/articulo_tipo_familia/
  venta_detalle but missed this one. It's the anti-join key that stops
  already-invoiced lines being billed twice — the highest-consequence gap in
  the whole migration, now DDL'd in 33b §0.
- `doc.get_precio_info_partida` — undocumented caller of `fn_precio_info`
- `doc.vw_venta` — calls `fn_descripcion_linea`, whose signature also changes
  (SMALLINT→INT). Same overload trap as the pricing functions: the OLD
  overload isn't replaced, it survives as dead code still referencing
  `articulo_tipo`, silently blocking migration 34's `DROP TABLE articulo_tipo`
  unless explicitly dropped — now in 33b.
- `receta.vw_tenido` — no function-signature reason to need dropping, but
  **`CREATE OR REPLACE VIEW` cannot rename an existing output column** in
  Postgres (only append new ones). Every view converted here renames
  `articulo_tipo_id`/`articulo_tipo` → `grupo_articulo_id`/`grupo_articulo` in
  place, so re-applying its owning file fails with "cannot change name of view
  column" unless the view is dropped first. All affected views are now in
  33b's drop list for this reason, independent of any function dependency.

**Two silent bugs fixed as a byproduct of the rekey, not just renamed away**
(both are the same failure shape: an INNER join or row-comparison against
`articulo_tipo_id`, which is NULL for every MIXED grupo since the migration
31/32 clean break — NULL silently drops or nulls the whole result, no error):
- `receta.get_tenido_versiones` compared the full spec tuple by row equality;
  NULL anywhere makes the comparison evaluate NULL, so version history has
  been silently empty for every mixed-grupo recipe.
- `mes.generar_receta` used `JOIN articulo_tipo ON ... = r.articulo_tipo_id`
  (INNER); it has been silently unable to generate a recipe preview for any
  mixed-grupo TENIDO paso — `v_receta` comes back NULL with no downstream
  NULL check, so `RETURN v_receta` in preview mode hands the frontend NULL
  with no error.

**Pre-existing gap left AS-IS, not fixed** (out of scope, preserved per patch
46's own note): `doc.registrar_despacho`'s `fn_get_precio` call never routed
TENIDO through `fn_familia_precio`, unlike `fn_precio_info`/
`get_precios_partida`. Same behavior after conversion — not this migration's
job to fix.

**Verification before running 33b:** `doc.tmp_pricing_baseline` is already
captured (see `migration/diagnostics/pricing_baseline_snapshot.sql`). Run its
§2 diff after re-applying all files — expect zero rows.

---

## Prior planning notes for the task above (kept for history)

Run [migration/33_pricing_grupo_articulo.sql](migration/33_pricing_grupo_articulo.sql) **first** (DDL must
exist — these are SQL/plpgsql bodies that bind at creation, so they fail loudly against the old schema,
which is the safe direction), then convert:

**[funciones/facturacion.sql](funciones/facturacion.sql)** — the money path, where a wrong key is silent:
- `doc.fn_get_precio` — param `p_articulo_tipo_id` → `p_grupo_articulo_id`; match `cp.grupo_articulo_id`;
  keep the specificity scoring intact. **Add a NULL guard**: `RAISE` on a NULL `p_grupo_articulo_id`
  rather than falling through to wildcard rows. This is the fix for the failure mode in the READ FIRST
  box — it converts "the real price is lost with no error" into a loud error, and it is what makes
  deferring the `familia_precio` header safe. Same guard in `fn_precio_info`.
- `doc.fn_familia_precio` — param + read `familia_grupo_id` (still on `doc.articulo_tipo_familia`;
  it is re-keyed in place and only renamed in 34 — see decision 12)
- `doc.fn_precio_info` — **two** lookups: the catalog price *and* the recipe lookup at ~line 220
  (`rt.articulo_tipo_id`, which also pins `rt.tipo_receta_id = 7`)
- `doc.upsert_catalogo_precio` — params + the recipe lookup at ~line 327 + insert `grupo_articulo_id`
- the billing views around lines 411, 518–571, 816–962, 1001–1131

**[funciones/despacho.sql](funciones/despacho.sql)** — read `p.grupo_articulo_id` (~497) and snapshot it onto
venta lines (~527, 540, 546). Also `p_articulo_tipo_id` in the description helper (~688, 704).

**[funciones/receta.sql](funciones/receta.sql)** — `get_tenido_versiones` (**functional**, see gotchas),
`get_tenido` (~227, 302), `vw_tenido` (~872, 890).

**[funciones/mes.sql](funciones/mes.sql)** — display JSON only (~70, 113, 203, 228, 537, 612, 4116, 4504,
4560, 4672): output grupo instead, else the UI shows a blank article type.

**Verification that matters most:** pick a known pure partida and confirm `doc.fn_precio_info` returns the
**same `precio_kg`** before and after. A wrong key here doesn't error — it quietly resolves a wildcard.

---

## Open — needs the plant, not the database

1. **How many *real* rib fabrics exist?** Data says ≥2 (cotton rib `fibra=1` under J/Gam bodies, poly rib
   `fibra=2` under F Poly/J Poly). Needed to map the **33 forged rib items → a handful of real fabrics**.
2. **`Full Lycra Melange` fibra** — set to 1 with the others; confirm the melange yarn is cotton (→1) not a
   cotton/poly melange (→2).
3. **`Rib Lycrado` is `fibra = 2`** but `J Lycra` and `Full Lycra` are `1`. Elastane adds no dye system —
   so either it contains polyester, or that 2 is wrong. It drives a ceiling.
4. **`Paquete de Cuellos` (306) vs `Paquete Cuellos J 20/1` (324)** — same thing, duplicated?
5. **`Rollo Rib Rib Lycrado` (298)** — rib trim of a rib fabric, or a naming artifact?

---

## Backlog — deliberately deferred, do not fold in

- **`doc.familia_precio` — give the pricing family its own header; kill the self-reference.**
  `familia_id`/`familia_grupo_id` points at a *member* elected as the bucket label. That is not a domain
  fact: it is an artifact of `catalogo_precios` keying on `articulo_tipo_id`, so the bucket had to be
  spellable as an `articulo_tipo` to be joinable. The legacy design was a normalization function
  `f: tipo → tipo`, and patch 25 turned the hardcoded `CASE` into a table without changing its shape.
  `COALESCE(..., p_articulo_tipo_id)` ("no mapping → itself") only type-checks *because* domain and
  codomain are the same set.

  **What it costs today:**
  - `catalogo_precios.articulo_tipo_id` means *sometimes a literal type, sometimes a bucket* — patch 25
    lines 91–130 **overwrite** the column with family ids and then soft-close the collisions. One column,
    two meanings, resolved by rewriting the money table to express a taxonomy change.
  - `fn_familia_precio` resolves in **one hop** over a self-referencing table. Defaults send `4,9→18`
    while the flat-rate override sends `4,9→20`; correct today only by `ORDER BY` luck. Don't add a layer.
  - Retiring a member can kill a bucket — see amended decision 10 (familia 20).
  - A bucket can't be named or audited; "family 18" means "whatever grupo 18 is currently called".

  **Shape:** `doc.familia_precio (id, codigo, codigo_canon, nombre, audit…, flg_elm)`;
  `articulo_tipo_familia` becomes a pure membership bridge `(grupo_articulo_id, tercero_id, familia_id)`.
  Then **make membership total** — seed one singleton familia per grupo and key `catalogo_precios` on
  `familia_precio_id`, *not* `grupo_articulo_id`. That makes resolution a total function: no
  `COALESCE`-to-self, no transitivity trap, and a missing mapping becomes a constraint violation instead
  of a silent wildcard fallback. Cost: 32 singleton rows and one join hop.

  **Prohibition:** do **not** repeat patch 25's fix — rewriting `catalogo_precios` key values in place to
  express a taxonomy change. Move the mapping into the bridge and leave the money table's keys alone.

  **Prerequisite for:** soft-deleting the `Jersey/Gamuza` grupo (decision 10).

  Deferred because 32 is live and `articulo_tipo_id` is drifting to NULL — widening scope while a silent
  mispricing window is open is the wrong trade. Deferral costs one extra pass over the same four pricing
  functions (a param swap and one join hop), not a rewrite, and forecloses nothing. The *safety* half of
  this concern is handled in 33 by the NULL-grupo guard in `fn_get_precio` / `fn_precio_info`.

- ✅ [Rib → its own articulo — DONE 2026-07-20](migration/35_rib_como_articulo.sql) — was backlog, now applied
  and verified. Kept for history below; **decision 13** has the settled facts and **migration 36** (`flg_rib`
  retirement) is the remaining piece.
- **Fabric-spec normalization.** `articulo` names are concatenated specs — construction (`J`/`Gam`/`F`/`Rib`)
  × yarn count (`30/1`) × prep (`Pei`/`Card`) × fiber/blend (`Poly`, `6535`). `articulo_tipo`, `fibra` and
  `flg_rib` are three lossy projections of **one** un-normalized spec string; decomposing it resolves all three.
- **Dye systems as an explicit set.** `colorante_tipo` (`RX`/`DIR`/`DISP`) already exists as the *supply* side
  on `item_insumo_detalle`; the *demand* side is the lossy integer `fibra`. Mind two levels: fabric needs a
  fiber **affinity** (cellulosic/synthetic); recipe picks a **dye class** within it (`RX` and `DIR` are both
  cellulosic). `vw_grupo_articulo.fibra_max` uses `MAX()`, which equals `|union|` **only because MLR's classes
  are nested today** — a pure-poly or acid-dyed fabric would break it.
- **Formalize the commercial order.** The guía de remisión is the de-facto order (client rolls + processing
  spec); one guía fans out to N partidas; fulfillment is tracked bottom-up via guía depletion.
- **Cleanup**: `articulo.grupo_articulo` legacy text column (drop deferred — 5 legacy views depend on it:
  `vw_despacho`, `vw_partidas_resumen_v2`, `vw_partidas_x_programar`, `vw_produccion_acabados`,
  `vw_resumen_auditorias`; **never `CASCADE`**). Also the two forged-mix artifact fixups (decisions 9 & 10 above).

---

## Project memory

Durable context lives in these memory files — read them before starting:
`grupo-articulo-dye-substrate`, `fibra-dye-systems-not-fiber-count`.

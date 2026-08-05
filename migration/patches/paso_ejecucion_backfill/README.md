# Paso / Ejecucion Backfill

Migrates legacy production-execution history (`produccion_tenido`, `perchado`,
`compactado`, `termofijado`) into `mes.partida_paso` + `mes.partida_paso_ejecucion`,
collapsing the legacy per-run duplication into the new **one paso per
(partida, operacion), 1..N ejecuciones** model.

These files were pulled out of `migration/patches/` because their old numbers
(31/32/33/39) collided with unrelated patches that already used 32/33/34/35/36/37/38.
Run them **in the order below**, not by any global patch number.

## Run order & status

Numbered by **execution order**. Steps 03 (merge) and 04 (insert pasos) are
independent tracks — 03 ran first because it's self-contained (touches only the
already-migrated ejecuciones), so it takes the lower number.

| step | file | does | status |
|------|------|------|--------|
| 00 | `00_fix_reproceso_matizado_operacion.sql` | fixes `tipo_receta.operacion_id` for 'Reproceso Matizado' (migration-11 typo) | ✅ applied · idempotent |
| 01 | `01_staging_legacy_executions.sql` | builds `migration.legacy_executions` (one row per legacy record; carries `legacy_estado`) | ✅ applied |
| 02 | `02_link_staging_to_pasos.sql` | links staging rows to existing pasos — Step A reworks by `legacy_id`, Step B normal by (partida, operacion)→MIN | ✅ applied |
| 03 | `03_merge_split_tenido_ejecuciones.sql` | collapses shift-split TENIDO runs (lead+completion) into one ejecucion (completion = canonical); re-points the lead's consumption movements; annuls phantom rework child-partidas | ✅ **APPLIED** (§3 verified 0/0/0/0) |
| 04 | `04_insert_missing_pasos.sql` | INSERT one paso per unlinked (partida, operacion) (~4.8k TENIDO + 849 perchado + 1 compactado rows); back-fill new_paso_id; renumber secuencia by operation priority | 🟡 written · dry-run first |
| 05 | `05_insert_missing_ejecuciones.sql` | INSERT one ejecucion per run for (partida, operacion) groups with **zero** ejecuciones (the step-04 groups); estado-chain merges shift-split TENIDO; PERCHADO 1:1; skip 3 app-dup opens (4153, 4410, 5199) | 🟡 written · dry-run first |
| 06 | `06_consolidate_pasos.sql` | collapse **migration-origin** (partida, operacion) groups with >1 paso → canonical MIN; re-parent ejecuciones + componente; drop empty extras; renumber secuencia. App pasos left alone (app routes an op at multiple positions legitimately) | ✅ **APPLIED** (1896 ejec re-parented; 0/0/0 verify) |

**Sequence constraint:** step 03 (merge) must run **before 06** — it relies on
migration-11's `pp.id = pt.id` mapping, which step 06 destroys. Step 03 is
independent of step 04 (either order). Step 04 → 05 is a chain.

### Deferred (separate effort, not numbered here)

- **Midnight-crossing timestamp cleanup.** Staging + migration-11 + the finishing
  migration all compute `fyh_fin = fecha + hora_fin + 5h`, which ignores a run that
  crossed 00:00 (hora_fin < hora_inicio under one fecha) → those ejecuciones end
  *before* they start. Step 05 fixes its own inserts (+1 day where `run_fin <
  run_inicio`), but the pre-existing migration-11 tenido single-rows and finishing
  ejecuciones still have it. → **written: `cleanup_midnight_fyh_fin.sql`** (fixes
  the ~692 migration rows +1 day; leaves the 24 post-go-live app rows for the app
  team — a live ejecucion-finalize bug writing a midnight-crossing end on the same
  fecha, still producing new ones until the app code is fixed). Standalone.
- **Rework finishing-op remap.** → ✅ **DONE: `remap_rework_finishing.sql`** (committed).
  Moved **277** finishing ejecuciones (224 compactado + 52 perchado + 1 termo) from
  the original partida onto their rework CHILD partida, matched by roll count
  (finishing `cantidad_rollos` = rework `partida_detalle.cantidad`) + chronology
  (nearest preceding rework). ~600 stayed on the original (whole-batch finishing).
  Created a finishing paso under each target child + renumbered its secuencia.
  CAVEAT: roll-qty is a heuristic — a full-batch finishing coincidentally equal to a
  rework count and postdating it can be a false positive (accepted limit).
- **Output genealogy → last step.** → ✅ **DONE (single-last-step): `remap_output_to_last_step.sql`**
  (committed). The tenido output lotes are SYNTHETIC "expected output" (migration
  imported only dyeing, assigned expected output to tenido runs). Moved **7,736 lotes
  across 416 partidas** whose last step is a *single* finishing run → re-pointed
  `lote.documento_id` + the production ingreso to that ejec (egresos left on tenido).
  LEFT AS-IS: 459 tenido-last (already right) + 207 multi-last-step (deferred,
  see below).
  (original note kept below for context)
- **Output genealogy → multi-last-step.** → 🟡 **written: `remap_output_multi_last_step.sql`**
  Distributes the 207 remaining partidas. Each ejecucion is an independent run
  with its own output batch; lotes are ordered by id, ejecuciones by fyh_inicio,
  and each ejec claims a bucket sized by its `cantidad_rollos`. Overflow → last
  ejec. Rib/regular lotes sort naturally into their bucket via the ordered
  assignment (no explicit rib detection needed). Dry-run §0, then run §1+§2.
- **Output genealogy — original note.** migration-11 bolted production output lotes onto
  the TENIDO ejecucion as a bootstrap ("needed a tenido reference to generate
  output"). Physically the finished-goods output is produced at the **real last step
  (usually compactado)**. Re-pointing all tenido output lotes to the last-step
  ejecucion is a legitimate genealogy fix, but it's broader than this backfill
  (touches all tenido output; needs a tenido-run → last-step-ejecucion mapping).
  Do it as its own step **after** the backfill. Step 03 leaves output on the
  canonical (completion) tenido ejecucion for now — this does not block the repoint.

`01` is a destructive reset (`DROP … CREATE … INSERT`) — re-running it wipes
`new_paso_id`/`new_ejecucion_id`, so only re-run it *before* 02, or be ready to
re-run the whole chain.

## Old → new number map (for decoding stale comments elsewhere)

| conversation / old | here |
|---|---|
| patch 31 | 00 |
| patch 32 | 01 |
| patch 33 | 02 |
| patch 39 (merge) | 03 |
| patch 36 (fix fyh) | absorbed into 03 |
| patch 34 (insert pasos) | 04 |
| patch 37 (insert ejecuciones) | 05 |
| patch 35 (consolidate) | 06 |

## Prerequisites living outside this folder

- `migration/patches/30_fix_lavado_hidro_to_tenido.sql` — domain fact: every
  `produccion_tenido` row is a TENIDO run; `tipo` only selects the recipe.
  (Already applied; not moved.)
- `migration/11_data_migration.sql` — built the initial paso + ejecucion layer
  (§1416 normal pasos, §1443 rework child partidas, §3040 ejecuciones, §3078
  lote/movimiento re-stamp). Step 03 reconciles against this.
- `migration/diagnostics/validate_pasos_migration.sql`,
  `migration/diagnostics/debug_pxr_produccion_tenido_join.sql` — row-level checks.

> **Provenance note (unconfirmed):** the SQL headers in this folder say "06b" as
> shorthand for *the legacy finishing-migration script that built the COMPACTADO/
> PERCHADO/TERMOFIJADO pasos + ejecuciones*. **We have NOT confirmed which script
> actually ran** (`legacy_data/06_migrar_despachos_y_produccion.sql` vs
> `06b_acabados_timeline_rebuild.sql`) — "06b was run" is an assumption. What IS
> verified from live data: those finishing pasos + ejecuciones **exist and carry
> legacy `fyh_cre` dates** (Compactado 2025-02, Perchado 2025-03, Termofijado
> 2025-03), i.e. they were migrated from legacy by *some* script. Volteado / Secado
> / Lavado Hidro / Preparado have only post-go-live dates → app-created, no legacy
> source. The backfill keys on the live zero-ejecucion-group state, not on this
> provenance, so the open question doesn't affect correctness.

## Key domain facts established (so they don't get re-litigated)

- **produccion_tenido = TENIDO only.** `tipo != 'Teñido'` = a REPROCESO rework →
  migration-11 made it a child partida (`partida_origen_id`) + paso (`pp.id=pt.id`).
- **LAVADO_HIDRO** is a separate HIDRO-machine op sourced post-go-live; it does
  **not** come from produccion_tenido. The migration-11 tipo→LAVADO_HIDRO split was
  a bug and is not reproduced here.
- **Shift split:** a dyeing run crossing the 07:00 cutoff was recorded as a LEAD
  (`estado='En Proceso Teñido'`, real start, stunted end = null **or** midnight) +
  a COMPLETION (`estado='Teñido'`, placeholder 07:00 start, real end). Rolls never
  leave the machine — it is ONE run; the per-row quantities SUM to the run total.
  The split marker is **`legacy_estado`**, not `hora_fin` (326 leads stunt to
  midnight, not null). 30 of these splits are reworks (→ phantom child partidas).
- **No midnight-merge / no view logic ported** — the legacy display view
  (`vw_produccion_tenido_procesada`) is stale/irrelevant; we record actual events.
- Validation invariant: per partida, `SUM(produccion_tenido.rollos WHERE
  tipo='Teñido')` should ≈ `partida.rollos` (reworks re-dye the same rolls → over).

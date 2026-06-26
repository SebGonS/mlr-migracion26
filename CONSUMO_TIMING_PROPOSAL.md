# Production consumption timing — proposal & impact

Status: **PROPOSAL / not implemented.** Captures the decision to move recipe
consumption from completion (backflush) toward step start (issue-at-start), plus
the related spec-location cleanup. Nothing here is built yet.

Decided 2026-06-23.

---

## 1. Problem

Today production is **backflushed**: recipe consumption, matizado, and output are
all posted at step completion (`finalizar_paso`). For dyeing this is the weakest
fit because **runs span shifts / overnight** (production reports show the shift
jumps). Backflushing leaves chemical inventory **overstated for the whole run** —
chemicals physically charged into the bath at the *start* still read as on-hand
until the step is finalized hours/days later.

Standards: process industries (SAP PP-PI) **issue components at the operation/phase
(start)**, not at confirmation. Backflush (SAP REM) is only appropriate when
consumption ≈ output in time. MLR's overnight cycles are the textbook
issue-at-start case.

---

## 2. Current state (verified in code)

Step lifecycle and where each event posts today:

| Function | mes.sql | Role today |
|---|---|---|
| `iniciar_paso(paso_id, {maquina_id, empleado_id})` | 639 | Creates `partida_paso_ejecucion` (EN_PROCESO). **No consumption.** |
| `registrar_consumo_paso(paso_id, consumos)` | — | Standalone consumption (posts `documento_tipo='partida_paso_ejecucion'`). **Already callable independently.** |
| `registrar_matizado(paso_id, consumos)` / matizado via consumo path | 982 / 1797 | Extra dosing (motivo MATIZADO). Standalone fn exists; today bundled into `finalizar_paso`. |
| `registrar_produccion(ejecucion_id, {output,...})` | 1461 | **Output lote creation** (goods receipt). Called by `finalizar_paso` only when `produccion.output` is submitted — which the **frontend gates on `paso.flg_ultimo` (LAST step only)**. Rolls flow through earlier steps as the *same* lotes; only the final step creates output lotes (earlier steps snapshot prorated `peso_kg`). ⚠️ **Last-step rule is FRONTEND-enforced, not DB-enforced** — `registrar_produccion` creates output whenever `output` is passed. |
| `finalizar_paso(paso_id, datos)` | 1735 | Completion orchestrator: consumos → matizados → variance → optional output (last step) → snapshot `peso_kg` → close ejecucion COMPLETADO. **This is the backflush point.** |

Recipe generation:
- `generar_receta(paso_id, p_maquina_id, p_relacion_bano, p_commit)` (mes.sql:377).
  - Machine resolved from **`programacion`** (schedule) or `p_maquina_id` override —
    NOT from paso (`maquina_planificada` being dropped, patch 32).
  - Bath ratio precedence: **param > `paso.relacion_bano_objetivo` > machine standard**.
  - Weight from weighed roll lotes (guard: all rolls weighed first).
  - `p_commit=false` = **preview** (no `partida_componente` write) — already pre-run capable.
- `partida_componente` (≈ SAP RESB) holds recipe-scaled **expected** quantities =
  the variance baseline.

Key point: **the hooks already exist.** Consumption is already its own function;
a preview mode already exists; a start event (`iniciar_paso`) already exists.

---

## 3. Decision

**Split the backflush by timing, using the existing functions:**

1. **Planned consumption → step START.** Post the recipe-scaled goods issue when
   the run starts (call `registrar_consumo_paso` at/after `iniciar_paso`, against
   the `partida_componente` baseline), instead of inside `finalizar_paso`.
2. **Matizado → mid-run.** Have the station/UI call `registrar_matizado` (or the
   consumo path with MATIZADO motivo) **during** the run per dosing event, instead
   of bundling at the end. (Mechanism already built — this is a UI/usage change.)
3. **Output → completion of the LAST step.** Unchanged: `finalizar_paso` →
   `registrar_produccion`, gated by `flg_ultimo` (rolls flow through earlier steps
   as the same lotes; only the final step creates output lotes). Variance
   (actual vs `partida_componente`) at close.

Net: consume at start + matizado incrementally + output at end. Actual = start
consumption + matizados; variance vs the expected baseline stays meaningful.

---

## 4. Spec location (resolved)

**Governing principle: a spec lives at the layer where its VALIDATION CONTEXT
exists.** Machine-independent targets → `paso`. Machine-dependent params → where
the machine is known (`programacion` / `ejecucion`).

| Spec | Machine-coupled? | Planned home | Actual home | Notes |
|---|---|---|---|---|
| **Máquina** | — (it *is* the resource) | `programacion` (schedule) | `ejecucion.maquina_id` (set at `iniciar_paso`) | Drop `paso.maquina_planificada` (patch 32). paso = routing, not resourcing. |
| **`ph_objetivo`, `temperatura_objetivo`** | No — pure chemistry | **`paso`** (target) | `ejecucion._real` | Valid with no machine → stay on paso. |
| **Relación de baño** | **Yes** — default + min/max come from the machine | **`programacion`** (nullable custom; sits with the machine, validatable) | `ejecucion.relacion_bano_real` | **DROP `paso.relacion_bano_objetivo`.** Default = machine standard. |

Precedence for rb: **runtime (`ejecucion`/param) > `programacion` planned custom >
machine standard.**

Rationale (corrected 2026-06-23 after the "no machine ⇒ no min/max" point): bath
ratio is **not** a pure chemistry target like pH/temp — its default *and* its
min/max validation both come from the machine, and the recipe doesn't carry it
(`generar_receta` resolves it and scales chemicals by weight × rb). So rb is a
**run parameter**, not a paso target. A `relacion_bano_objetivo` on a (now
machine-less) paso is an unvalidatable orphan — a "deviation" from a baseline not
yet known. It must live where the machine is. pH/temp have no machine dependency,
so they correctly stay on paso. → **drop both `maquina_planificada` (done) and
`relacion_bano_objetivo` from paso; add nullable `relacion_bano` to `programacion`**
(null = machine standard). Central prep still validates: `generar_receta` reads the
scheduled machine + its `programacion.relacion_bano`.

---

## 5. Recipe generation timing (serves present + future)

- **Central prep (current):** `generar_receta(p_commit=false)` with the scheduled
  machine → preview → print → weigh chemicals before shift. No specs needed on paso.
- **Run start:** `iniciar_paso` confirms machine on the ejecucion → commit recipe →
  post planned consumption.
- **Tablet-at-station (future):** station sets machine+ratio at runtime, generates
  recipe (commit), doses, records matizado mid-run, output at end. **Same functions**
  — no redesign; the future is already reachable.
- **Keep single parametrized endpoints** (`generar_receta`, `registrar_consumo_paso`);
  do not fan out into per-flow variants.

### Parametrize vs fan out (the rule)

**Parametrize when the logic is identical and only inputs vary; fan out when
behavior / validation / side-effects genuinely differ.**

- Recipe gen + consumption: identical algorithm for every operation (scale recipe
  by weight × ratio, post consumption) → **parametrize**. Fanning out = N copies
  of the same logic → drift + maintenance.
- `finalizar_paso` is the correct **hybrid**: one shared function + thin
  per-operation branches (TENIDO/COMPACTADO/TERMOFIJADO field blocks, the
  TERMOFIJADO extension table). ~90% shared, op-specifics branch. NOT N endpoints.
  The frontend modal mirrors this (one modal, op-specific blocks).
- Contrast — the MIGO **ingress** wrappers (compra/OS/cliente) *are* separate
  endpoints, because their behavior truly differs (controlling doc, pre-fill,
  validation, anchoring). Production steps don't have that difference.

---

## 6. Scope & impact

**Functions touched:**
- `iniciar_paso` — optionally post planned consumption at start (or a thin
  `confirmar_receta` step that does it). New behavior.
- `finalizar_paso` — stop posting the *primary* recipe consumption (moved to start);
  keep matizado-at-close as fallback, output, variance, close.
- `registrar_consumo_paso` / `registrar_matizado` — unchanged; just called at
  different times.
- `generar_receta` — unchanged (already preview + parametrized).
- Schema: **drop `paso.relacion_bano_objetivo`** (machine-coupled orphan) and add
  **nullable `programacion.relacion_bano`** (null = machine standard); confirm
  `paso.maquina_planificada` drop (patch 32). Keep `ph_objetivo`/`temperatura_objetivo`
  on paso. `generar_receta` rb precedence becomes param > `programacion` > machine.
  No new tables.

**Reversal/cancellation:** consuming at start means a cancelled run must reverse the
start-consumption (PROD_CONSUMO_REV / `anular_produccion` already exist). More
reversals than backflush (which had nothing to undo pre-completion) — acceptable
trade for overnight inventory accuracy.

**Frontend:**
- Station/tablet records matizado mid-run (call `registrar_matizado` during the run).
- `finalizar_paso` form no longer carries the primary `consumos` (now at start).
- Central-prep flow keeps preview-print; only the *goods-issue timing* moves.

**Inventory/costing benefit:** point-in-time chemical on-hand becomes accurate
during the run; matizado events are distinct (better shade-correction costing/audit)
instead of lumped at close.

---

## 7. Open decisions

- **Exact start hook:** post consumption *inside* `iniciar_paso`, or a separate
  `confirmar_receta`/`comprometer_receta` step between start and run? (Latter is
  cleaner if "start the machine" and "commit the recipe" are distinct moments.)
- **Even-earlier consumption at central staging** (when chemicals are physically
  weighed out before the shift) vs at `iniciar_paso` (run start). Staging is more
  accurate but has no ejecucion yet → would attach consumption to paso/partida.
  Default recommendation: **`iniciar_paso`** (has the run record; standard
  issue-at-start). Revisit only if the staging→start gap proves material.
- Whether `finalizar_paso` should still accept `consumos` as a fallback for steps
  not started through the new path (backfill / corrections).
- **Harden the last-step output rule in the DB.** Output-only-on-last-step is
  currently FRONTEND-enforced (`flg_ultimo` gate in `FinalizarPasoModal`);
  `registrar_produccion` will create output whenever `output` is passed. Consider
  rejecting output on a non-last step server-side so the invariant can't be bypassed.

---

## 8. Sequencing

1. Land the spec-location decision (keep `relacion_bano_objetivo`; confirm patch 32).
2. Add planned-consumption-at-start (behind the chosen hook), keeping
   `finalizar_paso` consumption as fallback.
3. Wire the station UI to record matizado mid-run.
4. Once stable, remove the primary consumption from `finalizar_paso`.
5. Tablet-at-station builds on the same endpoints when ready.

Do NOT bundle this with the entrega rename or compra work — separate, production-
posting-critical change with its own test pass.

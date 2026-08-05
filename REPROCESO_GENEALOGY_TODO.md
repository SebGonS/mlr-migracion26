# Reproceso reversal: missing immediate-source tracking

## Status
Not started. Design-only note, written after manually fixing three affected
partidas (6470, 6495; 6467 turned out unaffected — see below). Pick up when
ready to design the broader genealogy/traceability layer.

## The bug
`mes.crear_reproceso` always sets a new rework child's `partida_origen_id` to
the flat family **root** (`funciones/mes.sql:3658` —
`v_root_id := COALESCE(v_origen.partida_origen_id, v_origen.id)`), even when
the rework was actually pulled from a **sibling** rework partida rather than
the root (`crear_reproceso` validates lotes against the whole family, not
just the root — funciones/mes.sql:3660-3688).

`mes.mover_lotes_reproceso` (called by `mes.anular_reproceso`) reverses a
rework by sending the rolls back to `v_child.partida_origen_id`
(funciones/mes.sql:3920-3921) — i.e. always the root, never the actual
immediate source. When a rework was created from a sibling, reversing it
silently misplaces the rolls onto the root instead of back onto the sibling
they came from.

This is intentional-by-omission, not a typo: `partida_origen_id` is a
deliberate flat hub so family queries stay a simple
`id = root OR partida_origen_id = root` instead of a recursive CTE. The
tradeoff is that the one-hop-back fact ("which partida did this roll sit on
immediately before this rework pulled it in") is never recorded anywhere.
The closest thing today is forensic reconstruction from `logs_api` — the
`crear_reproceso` call's `params->>'partida_id'` — which is not indexed for
this, has no retention guarantee, and requires manually cross-referencing
lote lists.

## Incident log (2026-07-24)
Three partidas were affected in the same production window:
- **6470**: created from 6430 (sibling of root 6168), reversed via
  `anular_reproceso` → rolls wrongly landed on 6168. Fixed by hand:
  `migration/diagnostics/fix_6470_repoint_componentes_to_6430.sql`.
- **6495**: created from 6434 (sibling of root 6400), **not yet reversed**
  when caught — fixed by doing `mover_lotes_reproceso`'s steps by hand
  targeting 6434 directly, bypassing the buggy function entirely:
  `migration/diagnostics/fix_6495_repoint_componentes_to_6434.sql`.
- **6467**: created from 6347, which turned out to **be** the root itself
  (no sibling in between) — `partida_origen_id` was coincidentally correct,
  so no fix was needed; reversed normally via `mes.anular_reproceso(6467)`.

Diagnostic trail: `migration/diagnostics/debug_6470_reproceso_origin*.sql`,
`debug_6470_safety_check_6430.sql`, `debug_6467_6497_reproceso_origin.sql`,
`debug_6467_6497_check.sql`, `debug_6495_safety_check_6434.sql`.

**Open question**: are there other reworks-of-reworks sitting un-reversed
right now whose `partida_origen_id` doesn't match their true immediate
source? Worth a one-off audit query before this is fully closed out (diff
each rework's `crear_reproceso.params->>'partida_id'` in `logs_api` against
its stored `partida_origen_id`, restricted to rows where they differ).

## Why this belongs in the bigger genealogy/traceability effort
Per [document-model-philosophy], `inventario.item_movimientos` is already
the single source of truth for lineage across every other document type
(entrega, QC splits, production). Reproceso lineage is currently the odd
one out — it lives only in `partida_origen_id` (flat, lossy on purpose) plus
incidental `logs_api` breadcrumbs, instead of flowing through the same
genealogy mechanism as everything else. `entrega-ingress-normalization`
already flags a "genealogy wall" as pending work; this is the same wall.

The right fix is almost certainly **not** a bolt-on column but folding
reproceso moves (both `crear_reproceso`'s pulls and
`mover_lotes_reproceso`'s reversals) into whatever the genealogy layer
becomes — so "where did this roll live immediately before" is a real query
against shared infrastructure, not per-incident archaeology.

## Sketch of options (unevaluated, for whenever this gets picked up)
1. **Ledger table**: `mes.partida_componente_movimiento(lote_id,
   partida_id_from, partida_id_to, motivo, fyh_cre)`, written by both
   `crear_reproceso` (Case A move) and `mover_lotes_reproceso`. Cheap,
   additive, doesn't touch the flat-hub read model. Reversal becomes a real
   lookup instead of `logs_api` archaeology.
2. **Fold into item_movimientos**: treat reproceso pulls/reversals as first-
   class movements alongside everything else genealogy already tracks —
   more consistent with the existing philosophy, but a bigger lift and needs
   to be scoped alongside the "genealogy wall" work already pending for
   entrega/dispatch.
3. Whatever comes out of that should also change the **frontend**: the
   reversal action currently a blind one-click "anular reproceso" — it
   should show the operator where the rolls are about to land (the real
   immediate source) with an overridable target, mirroring how
   `crear_reproceso` already lets you pick a source partida when creating a
   rework. Building this before the backend tracks the real source just
   moves the guesswork onto the operator.

## Related memory
- `document-model-philosophy`
- `entrega-ingress-normalization` (genealogy wall)
- `reproceso-reversal-missing-frontend` (older, narrower gap — this note
  supersedes it for the reversal-target-accuracy problem specifically)

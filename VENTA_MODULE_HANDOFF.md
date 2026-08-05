# Venta (Sales Hub) Module — Implementation Handoff

**Status (2026-07-13):** schema DONE, backend functions/views DONE, ONE BLOCKING ISSUE
open (see §0), frontend NOT STARTED. This file exists so the settled design is not
re-litigated. **Read "Settled decisions" before changing anything.**

**A consolidated, single-file copy of every table/function/view in this module lives in
`VENTA_MODULE_CONSOLIDATED.sql`** (project root) — read that instead of grepping across
`despacho.sql` / `devoluciones.sql` / `08_views.sql` for full code. This file stays the
prose/decision record; that file is the code reference. Keep both in sync when either changes.

---

## 0. RESOLVED — `estado_facturacion` / `doc.factura` pipeline: KEEP, permanently

`funciones/facturacion.sql` has a complete, already-wired, MLR-emits-its-own-factura
pipeline (`doc.registrar_factura_cliente`, `doc.vw_pendientes_facturacion`,
`doc.anular_factura_cliente`, `partida.estado_facturacion`) — confirmed **dead code, not
called by the frontend**. It's almost certainly the "basic outline on the financial aspect"
built by another agent before the venta direction was settled.

**Decision (2026-07-13): do NOT retire `estado_facturacion`, do NOT touch `doc.factura`.**
Keep this dormant pipeline parked as-is, unmodified, as insurance — if the client ever comes
back demanding payment-status tracking, the built-but-unused machinery is already there
rather than needing to be rebuilt. This is a deliberate "leave it alone" decision, not
negligence — don't "clean it up" or wire it to venta later without being asked again.

---

## 1. What was built

`migration/27_venta.sql` — additive-only, coherent, ready to run (after migration 26).
It is a *first-run-once* file (not idempotent, matching migrations 22/26). Creates the
commercial spine MLR was missing — the outbound mirror of `doc.compra`, analogous to
SAP `VBAK` / Odoo `sale.order`. **It is NOT `doc.factura`** (that's the invoice/billing
document; it stays dormant — see decision #2).

Four pieces:

- **`doc.venta`** — header/spine. `tercero_id`, `fecha`, `factura_serie/numero/fecha_venc`
  (1:1 reference to MLR's own externally-emitted factura), `estado` (`ABIERTA`→`FACTURADA`→`ANULADA`),
  audit. No internal correlativo (like `doc.compra`).
- **`doc.venta_detalle`** — charge lines. Columns:
  - `tipo` (`SERVICIO`|`VENTA`) — mirrors ownership (see #5)
  - `operacion_id` — what is billed (antipilling surcharge = its own operacion line)
  - `item_id` — product on `VENTA` (sale) lines; NULL on `SERVICIO` lines
  - **snapshot pricing dims** (see #4): `color_x_cliente_id`, `tenido_id`, `articulo_tipo_id`, `flg_antipilling`
  - `partida_id` — the INTENT partida (parent; see #6)
  - `descripcion` — NULL by default, composed at read time (see #10)
  - **frozen charge**: `cantidad_kg`, `precio_kg`, `importe` (generated)
- **`doc.entrega.venta_id`** — the structural link (N entregas → 1 venta). Nullable.
- RLS: `SELECT` gated by `comercial.ver`; **writes go through SECURITY DEFINER functions**
  (no write policy — matches `doc.cobro` in migration 26).

There is **no** `venta_factura` table and **no** `doc.factura` rows — both were considered
and rejected (see #3).

---

## 2. Remaining work

1. ✅ **DONE — `doc.registrar_despacho(p_datos jsonb)`** and **`doc.recompute_estado_comercial(p_partida_id)`**
   — written in `funciones/despacho.sql`, right after `get_despacho_partida`. One-shot: `items[]`
   (physical rolls) drives entrega/movements via the EXISTING `doc.crear_entrega` (reused, not
   reimplemented); a separate `cargos[]` array (the operations the dispatch user sums/charges)
   drives `venta_detalle`, with dims/price fetched automatically (partida intent snapshot,
   `fn_get_precio` pre-fill). Opens/reuses the `ABIERTA` venta per tercero. Calls
   `recompute_estado_comercial` for every distinct root partida touched.
   **Not yet validated against real data — two things to check before trusting in production:**
   - The ownership-mix guard (a cargo's partida dispatching both MLR-owned and client-owned rolls
     in the same call) currently **raises** rather than resolves. Confirm this scenario is truly
     impossible in practice, or decide how to handle it if not.
   - `recompute_estado_comercial`'s `DEVUELTA_PARCIAL`/`DEVUELTA_TOTAL` branch is a first-pass
     heuristic (dispatched-then-returned lote counting) — not verified against real return history.
2. ✅ **DONE — `doc.facturar_venta(venta_id, serie, numero, fecha_venc)`** and
   **`doc.anular_venta(venta_id)`** — `funciones/despacho.sql`, after `registrar_despacho`.
   `anular_venta` is a first pass: no cascade guard against still-active linked entregas —
   validate this is the desired behavior before relying on it.
3. ✅ **DONE — Returns stamp `entrega.venta_id`** — `registrar_devolucion_cliente` and
   `registrar_devolucion_crudo_cliente` (`funciones/devoluciones.sql`) now resolve the original
   dispatch entrega's `venta_id` and stamp it on the return entrega. **Also done: every
   fulfillment-affecting function now calls `doc.recompute_estado_comercial`** — the closed
   call-site list (registrar_despacho, registrar_devolucion_cliente,
   registrar_devolucion_crudo_cliente, anular_entrega, anular_devolucion_cliente,
   anular_devolucion_crudo_cliente) is fully wired. See §2b of the consolidated file for the
   exact patch snippets (these are edits inside larger pre-existing functions, not new ones).
4. ✅ **DONE — `mes.vw_partida_comercial` / `doc.vw_venta`** — `migration/08_views.sql`.
   `vw_partida_comercial` is the DERIVED authoritative fulfillment+billing projection at familia
   level (reuses `vw_partida_familia_output`'s dedup rule) — `partida.estado_comercial` only
   *caches* it. `vw_venta` is the sale read surface with composed line descriptions.
5. ✅ **DONE — `doc.fn_descripcion_linea()`** — `funciones/despacho.sql`. Composes
   `operacion — articulo_tipo · color · tenido [· Antipilling]` for SERVICIO lines, or the item
   name for VENTA lines. Used by `vw_venta`; a non-NULL `venta_detalle.descripcion` overrides it.
6. ✅ **RESOLVED — keep `partida.estado_facturacion` and the dormant `doc.factura` pipeline
   as-is** — see §0 above. Not retiring. Nothing to do here.
6b. ✅ **DONE (2026-07-14) — `doc.crear_entrega` now `RETURNS bigint`** (the created
   `entrega_id`), matching its sibling `doc.registrar_entrega_compra`. Was `RETURNS text`
   (a display message). `registrar_despacho` now does a clean `SELECT doc.crear_entrega(...)
   INTO v_entrega_id` — the `currval()` workaround is gone.
   **BREAKING CHANGE — frontend action required:** this changes the response shape for
   BOTH of `crear_entrega`'s existing direct callers — the receipt flow
   (`CLIENTE_ENVIO_PROCESO`) and the current two-step dispatch flow
   (`get_despacho_partida` → `crear_entrega`). Both must be updated to read the returned
   `bigint` id instead of the old text message. **The split into two dedicated functions
   (receipt vs. dispatch) considered earlier was explicitly NOT done** — this was the
   smaller, sufficient fix; the split remains a separate, optional architectural cleanup
   if `crear_entrega`'s mixed-flow scope is revisited later.
7. **Reference docs** — add the venta module to `SCHEMA_MANUAL.md`; add the dispatch flow to
   `FRONTEND_BACKEND_MAP.md`. Not started.
8. **Frontend** — the dispatch drawer (mirror the `registrar_compra` one-shot: entrega lines +
   price pre-filled from catalogo + factura ref), and the dispatched/pending views reading
   `vw_partida_comercial`. Not started — needs frontend codebase exploration first.

---

## 3. Settled decisions — DO NOT re-open

These were argued through at length. Each has a reason; changing one silently breaks the model.

1. **`venta` is the commercial spine (hub), the mirror of `compra`.** It ties `entrega` (guía),
   the factura reference, and `partida` (intent) together — the layer that was missing.
2. **Reference the factura, never reproduce it.** MLR does NOT emit facturas — the external .NET
   system + SUNAT do. `doc.factura` + migration 26 (`cobranza`) stay **dormant**. Do **not** create
   `doc.factura` rows for external invoices, and do **not** wire cobranza to venta.
3. **Factura ref = 3 columns on `doc.venta`, 1:1.** MLR delivers a sale all at once → one guía,
   one factura, no factura-en-cero. A `venta_factura` 1:N child table was built and **reverted** —
   it solved a cardinality MLR doesn't have.
4. **A billing line is a FROZEN record of a transaction — snapshot, don't derive, the pricing basis.**
   `venta_detalle` freezes `precio_kg`, `cantidad_kg`, AND the pricing-key dims
   (`color_x_cliente_id`, `tenido_id`, `articulo_tipo_id`, `flg_antipilling`), snapshot from the
   partida's **intent** at dispatch. Rationale: same reason the price froze — a document snapshots
   its content; and this **decouples billing from partida mutability** (the partida stays editable,
   bills never drift). `fibra` (intrinsic to the article), `ancho`, `rendimiento` are **derived**,
   NOT stored. Do **not** add more descriptive/lote attributes to the line.
5. **Ownership is the single truth, and the ledger already carries it.** `lote.propietario_id`:
   `= 1` (MLR) → `VENTA_EGR` (valorized, COGS) → `tipo='VENTA'`; `≠ 1` (client) → `SERV_EGR`
   (non-valorized) → `tipo='SERVICIO'`. `registrar_despacho` derives movement type AND `tipo`
   from the same fact so they cannot disagree. `venta_detalle.tipo` *mirrors* ownership, never re-decides it.
6. **Bill against intent (parent partida).** `venta_detalle.partida_id` = the intent partida
   (parent, `partida_origen_id IS NULL`). Reworks are **not** billed separately (MLR absorbs them);
   divergence (e.g. dye-to-black) is handled by the manual price, not by pointing at the rework child.
7. **Movements route through `entrega`, always** (`documento_tipo='entrega'`). `venta` never appears
   in `item_movimientos`. Headless entregas (both serie/correlativo NULL) are valid when there's no guía.
8. **Returns link via the existing `entrega.venta_id`; net is derived.** No junction, no stored net.
   (Matches SAP returns order / Odoo return picking + credit note: linked document + derived rollup.)
9. **Commercial status is derived, not hand-written.** Retire `partida.estado_facturacion`
   (venta owns billing status). Keep `partida.estado_comercial` as a dispatch cache.
10. **Description is composed from columns, not free-typed.** Generic item is *correct* (type/instance
    model: `item`+`item_rollo_detalle` = type; `lote`+`lote_rollo_detalle` = instance). Enrichment is
    order context from the partida, composed at presentation.
11. **`venta_detalle` grain = aggregate charge (per operation, kg), NOT per-roll.** No `lote_id` here;
    rolls live per-row on `entrega_detalle` and in `item_movimientos`.
12. **`partida.estado_comercial` is a cache, recomputed INLINE, not via trigger.** Fulfillment
    (dispatched − returned, at familia level) is always derived truth; the column is a fast-read
    materialization of it, same pattern as `compra_detalle.cantidad_recibida` ("Denormalized from
    ledger... Maintained by compras.sql after every entrega link or unlink" — follow that precedent,
    not a new one). A trigger on `item_movimientos` was considered and rejected: it would have to
    re-derive "which partida" via genealogy per roll, redoing work the caller already has for free
    (the function is always called *for* a specific partida). Instead: one shared function
    `recompute_estado_comercial(p_partida_id)` doing the familia fold, called at the END of every
    function whose movements affect fulfillment — this is the closed, enumerable call-site list,
    do not let it grow silently:
      - `registrar_despacho` (dispatch → fold increases)
      - `registrar_devolucion_cliente` / `registrar_devolucion_crudo_cliente` (return → fold DECREASES —
        the easy one to forget; a return must visibly un-dispatch the partida)
      - `anular_entrega` (dispatch reversal)
      - `anular_devolucion_cliente` / `anular_devolucion_crudo_cliente` (return reversal)
    Never branch business logic (e.g. "can this partida close?") on the cached column — always
    recompute/read the derived truth for decisions; the cache is for list/board display only.
    Returns do **not** touch `venta.estado` — fulfillment (partida) and billing (venta) are
    independent axes; a return can drop fulfillment while the venta stays `FACTURADA`.

---

## 4. Where things live (quick map)

- Ledger / physical truth: `inventario.item_movimientos` (per-lote, `documento_tipo`/`documento_id`).
- Movement types: `inventario.item_movimiento_tipo` seeds in `migration/05` (`SERV_EGR`, `VENTA_EGR`, …).
- Dispatch split helper: `doc.get_despacho_partida` in `funciones/despacho.sql`.
- Price lookup: `doc.fn_get_precio` (`funciones/facturacion.sql`); catalog `doc.catalogo_precios` (migration 07).
- Partida intent dims: `mes.partida` (`color_x_cliente_id`, `tenido_id`, `articulo_tipo_id`, `fibra`,
  `ancho`, `rendimiento`, `flg_antipilling`, `precio_kg` override).
- Per-roll actuals: `inventario.lote_rollo_detalle` (dyeing identity, set when dyeing completes).
- Returns: `funciones/devoluciones.sql`.
- Dormant billing (do not use): `doc.factura`, `doc.factura_detalle`, migration 26 cobranza.

---

## 5. Pricing/ownership model + audit (2026-07-16)

See **`PRICING_OWNERSHIP_MODEL.md`** (project root) for the domain rationale: kg is the
canonical pricing basis, per-roll is presentation only, and `propietario_id` is the single
accounting switch (revenue-service vs COGS-conversion vs on/off-book inventory). Audit
verdict: **the module already implements the core model** (settled decisions #4/#5/#6/#11).
Three edge gaps, none structural:

1. **VENTA one-line-invoice default is NOT enforced** — `registrar_despacho` makes one
   `venta_detalle` per caller-supplied `cargo[]`; `get_despacho_partida` builds only the
   physical `entregas[]`, never cargos. So the single-finished-product default is a
   frontend responsibility (dispatch drawer, §2.8) — a VENTA sale must default to ONE
   product cargo, not product + dyeing.
2. **No per-roll presentation** — add as a computed projection in `vw_venta`
   (`importe / n_rollos`), never a stored column, only if the client wants it.
3. **COGS/inventory-valuation half of the ownership switch is unmodeled** (dormant factura).

Migration consequences: the module assumes `precio_kg` is already per-kg, so the legacy
per-roll→per-kg normalization (MLR customers, `precio_unit>=10`) happens in the MIGRATION,
not here; and the auditoría migration must set `lote.estado_calidad='APROBADO'` (the gate
`vw_despacho_pendiente` reads), not only insert `calidad.inspeccion` rows.

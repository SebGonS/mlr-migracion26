# Pricing, Ownership & Invoicing — Domain Model (System-of-Record)

**Status (2026-07-17):** design decision record. Complements `VENTA_MODULE_HANDOFF.md`
(settled decisions #4/#5/#6/#11 already encode most of this). This file explains the
*why* behind the pricing model and states the rules the ERP should hold long-term —
NOT a reproduction of legacy behavior.

Motivating discovery: legacy `despacho.precio_unit` is **one overloaded field** — legacy
was never an invoice system, so it stored whatever the operator needed, constrained by a
limited schema. It never stored ownership explicitly, inferring "MLR client" from
`cliente.procedencia='MLR'` OR `cliente.cliente ~* '(MLR|Oswaldo)'`.

⚠ **CORRECTION (2026-07-17) — there is NO per-roll pricing in the data.** An earlier
version of this file (and the client's recollection) held that MLR clients were charged
*per roll* when `precio_unit >= 10`, requiring a ÷ kg/roll conversion on migration. That
is **wrong** and was disproven — see `migration/diagnostics/venta_price_partida_overlap.sql`:
a per-roll reading implies an average line of **$152.75 for ~137 kg of finished dyed
fabric = $1.12/kg — below raw yarn cost**, impossible; the per-kg reading gives
**$3,291.61 = $24.10/kg**, a real dyed-knit sale. **`precio_unit` is uniformly per-kg.
Migrate it as-is; never convert.** (The client flagged the cutoff as historical/PIT-unclear
— that was the unreliable part.)

What `>= 10` actually marks is **what the number means**, not its unit:
- `< 10`  → the **dyeing service rate** (~$1.95–2.05/kg)
- `>= 10` → the **sale price of the dyed roll** (~$24.10/kg = fabric + dyeing)

Both are per-kg. Verified structure (all legacy-era despacho, `flg_elm=false`):
- `precio_unit >= 10` occurs **only** for MLR clients — **zero** regular-client rows exceed
  10 (perfect separation; the ownership filter is trustworthy).
- Per partida the two are **alternatives, never additive**: 875 partidas carry only a sale
  price, 292 only a dye charge, and just **4 of 1,171 (0.3%)** carry both — and those are
  separate partial deliveries on different dates, each recorded with whatever the operator
  cared about that day. So the meaning is decided **per despacho row**, never per partida
  or per customer.
- Client fact: **every** MLR-filtered client was sold dyed rolls, no exceptions. Therefore
  the 292 partidas / 349 rows holding only a dye charge are **incomplete sale records** —
  the sale price was never stored and is not reconstructable from the data.

---

## Core principle

**Weight (kg) is the economic invariant. "Per roll" is presentation, never a pricing basis.**

Rolls have non-uniform weight, so a per-roll figure is not a stable *rate* — it only has
meaning as `total ÷ roll_count` after weights are known. Storing a per-roll rate is lossy
(hides the kg basis) and unstable (re-derives wrong when a lote weight is corrected).

Rule: **store the basis (`cantidad_kg`) and the rate (`precio_kg`); derive every
presentation (including per-roll) at read time.** Never persist a prorated per-roll value
as a source. — Already honored by `venta_detalle` (handoff #4, #11).

---

## Ownership is the accounting switch (one field, three consequences)

`lote.propietario_id` (`=1` MLR-owned, `≠1` client-owned) is not merely a movement-type
selector. It determines three accounting facts at once:

| propietario | dyeing is… | revenue | COGS | balance-sheet inventory |
|---|---|---|---|---|
| **client** (`≠1`) → SERVICIO / SERV_EGR | **service revenue** | dyeing, per kg | no fabric COGS (not MLR's) | client rolls = **custody only, off-book** |
| **MLR** (`=1`) → VENTA / VENTA_EGR | **conversion cost** | finished product, per kg | greige + dyeing conversion + overhead | MLR rolls = **valued inventory, on-book** |

The same physical activity (dyeing) is *revenue* on client material and a *COGS
conversion step* on MLR material. Legacy inferred ownership fragilely (name matching);
the ERP stores `propietario_id` as an explicit, immutable fact on the lote — retiring the
whole class of bugs the heuristic caused. — Already honored (handoff #5).

**Corollary the venta module does NOT yet cover:** the COGS / inventory-valuation half of
this switch (valuing MLR rolls at greige+conversion cost, excluding client rolls from
balance sheet). Out of current scope — `doc.factura` and valuation are dormant — but this
table is the reference for when a valuation layer is built.

---

## Invoicing structure

**A sale invoices as ONE line (the finished product) by default. Do NOT auto-split
"roll + dyeing."** The customer buys a finished dyed product; the greige+conversion
breakdown is MLR's internal COGS build-up, not a customer-facing itemization. Splitting
leaks cost structure and implies the parts are separately purchasable.

**Allow — never force — decomposition.** A transparent cost-plus contract ("$A for greige +
$B to dye") is legitimately two lines; `venta_detalle` supports N lines per venta, so
itemize only when a real commercial agreement does. Default single line.

- **SERVICIO** sale → one line: the dyeing operation, per kg (+ separate antipilling
  surcharge line where it applies — that IS a distinct charge, not a cost split).
- **VENTA** sale → one line: the finished product (`item_id`), per kg. Dyeing rides inside
  the product cost, not as its own charge line.

**CONFIRMED BY THE DATA (2026-07-17):** legacy never itemized roll + dyeing either. Per
partida the sale price and the dye charge are *alternatives* (875 vs 292 partidas), with
only 4/1,171 carrying both — and those are separate partial deliveries on different dates,
not itemization. The `>= 10` sale price (~$24.10/kg) is **all-in** (fabric + dyeing), which
is exactly the single-line model. The cost-plus decomposition remains a theoretical
allowance, not observed practice — do not build for it.

---

## Canonical vs "both first-class"

**One canonical pricing model — per-kg — with per-roll as pure invoice presentation.**
Do not make per-roll a first-class pricing concept: it doubles the pricing engine and
recreates the "which basis is authoritative?" ambiguity legacy suffers from. The only
temptation (a standardized finished SKU sold flat per piece) is a *degenerate* case
(`precio_kg × standard_weight`), not a parallel model.

Pricing UoM may *present* differently from stock UoM, but must always carry a
deterministic conversion to kg. No free-floating pricing units.

---

## Migration normalization (legacy `despacho` → `venta_detalle`)

Everything is **already** per-kg — there is **no unit conversion anywhere**. The
classification decides only `tipo` and completeness, never arithmetic:

1. `cantidad_kg` = `SUM(produccion_tenido.kilos WHERE tipo='Teñido')` pooled on the
   original partida (validated: 98.6% coverage, agrees with dispatched-lote weight to ~1.5%).
   Fallback for the ~68 missing pools: dispatched-lote weight, else `rollos × ~22.5`.
2. MLR client iff `cliente.procedencia='MLR'` OR `cliente.cliente ~* '(MLR|Oswaldo)'`.
   Set `tipo` / roll `propietario_id` from this **once**; the ERP carries it explicitly after.
   NOTE: the flag identifies clients who were **sold dyed rolls** (all of them were, per the
   client) — it is not a per-row basis marker.
3. `precio_kg = precio_unit` **as-is, in every case.** `tipo` + completeness by row:

   | row | `tipo` | `precio_kg` | status |
   |---|---|---|---|
   | regular client (4,226) | `SERVICIO` | dyeing rate ~$1.95 | ✅ complete |
   | MLR, `precio_unit >= 10` (2,125) | `VENTA` | sale price ~$24.10 | ✅ complete |
   | MLR, `precio_unit < 10` (353) | `VENTA` | ~$2.05 — **dye charge only** | ⚠️ incomplete sale |

   Preserve the raw `precio_unit` + inferred meaning in `venta.observacion` for audit.
   The **353 incomplete rows** are sales whose price was never recorded (only the dye
   component); the sale price is NOT reconstructable — migrate as-is (understated),
   catalog-price them, or flag them. OPEN DECISION.
4. **QC gate is a real prerequisite for dispatchability.** The live dispatch-pending view
   (`doc.vw_despacho_pendiente`) filters `lote.estado_calidad = 'APROBADO'`, and that column
   is a denormalized cache of the latest `calidad.inspeccion` verdict (set by
   `calidad.registrar_inspeccion`). So the auditoría migration must set
   `lote.estado_calidad = 'APROBADO'` on OK dyed rolls (not only insert `calidad.inspeccion`
   rows) or they won't appear as dispatchable. Ties this file to the auditoría fan-out.

So: **migrate `precio_unit` as-is.** No conversion, no threshold arithmetic. The `>= 10`
test only labels the row (sale vs dyeing rate) — it never transforms the number.

---

## Open items this model surfaces (not yet built)

- **Per-roll invoice presentation** — if the client wants per-roll display, add it as a
  *computed projection* in `vw_venta` (`importe / n_rollos` from `entrega_detalle`), never a
  stored column.
- **COGS / inventory valuation** — the on-book/off-book + conversion-cost half of the
  ownership switch. Dormant.
- **Invoice one-line default** — currently caller-driven via `cargos[]`; the single-line
  default for VENTA sales is a frontend/`get_despacho_partida` responsibility to enforce.

# Price Catalog — Edit Existing Rate (cotizaciones tabs)

**Status:** SPEC / not yet implemented
**Date:** 2026-08-04
**Scope:** frontend only (`mlr-app`). Zero DB/DDL changes.

---

## 1. Problem

There is no UI path to **update an existing price**. The backend fully supports
it (`doc.upsert_catalogo_precio` is SCD Type 2: closes the active row via
`fyh_elm`, inserts a new active row — never mutates `precio_kg` in place), and
the drawer already pre-fills the current price + flips its title to "Actualizar
Precio". The gap is purely the **list surface**: once a combination is priced it
vanishes, so there is no row left to click.

## 2. Root cause

`comercial/cotizaciones/page.tsx` loads from **`doc.vw_precios_pendientes`**,
which is `doc.vw_precios_estado` filtered to `WHERE estado = 'sin_precio'`
(`funciones/facturacion.sql`). Priced combos are structurally excluded.

`doc.vw_precios_estado` already carries everything needed — same combos plus
`precio_kg` and `estado ('con_precio' | 'sin_precio')` — and is already
`GRANT SELECT ... TO authenticated`.

## 3. Decision

- **Two tabs** in cotizaciones, both reading `vw_precios_estado`, split
  client-side by `estado`:
  - **Pendientes** (`sin_precio`) — the existing work-queue behavior/identity.
  - **Con precio / Catálogo** (`con_precio`) — browse + edit existing rates.
- Shared filters + "Fijar precio base" + partida-import live **above** the tabs.
- **`consulta-precios` is untouched.** It is the price *consumer* (read/query +
  history); the consumer must not know prices are settable. Editing lives only
  in the cotizaciones (administration) module. This is the module boundary and
  the reason we did NOT add an edit button there.
- **Drawer + backend unchanged** — both already handle the update case.

Rejected alternative: single table + `estado` dropdown filter. Buries the
catalog behind a default, muddies the "pendientes" count, and conflates a work
queue with a maintained registry.

## 4. Frontend changes — `mlr-app`

All in `src/app/v2/(dashboard)/comercial/cotizaciones/page.tsx` unless noted.

1. **Data source** — `load()` (~L177): `.from('vw_precios_pendientes')` →
   `.from('vw_precios_estado')`.

2. **Row type** (~L44):
   ```ts
   type PrecioRow = PrecioPendiente & {
     _key: string;
     precio_kg: number | null;
     estado: 'con_precio' | 'sin_precio';
   };
   ```
   Map `precio_kg` and `estado` in the `.map()` at ~L188.

3. **Tabs** (Mantine `Tabs`) wrapping the DataTable. Active tab drives a
   `estadoTab` state (`'sin_precio' | 'con_precio'`); add
   `if (r.estado !== estadoTab) return false;` to the `filtered` predicate
   (~L296). Per-tab counts from `rows.filter(r => r.estado === ...)`.

4. **"Precio actual" column** in the DataTable (~L512): render
   `$ precio_kg.toFixed(4)` or a "Sin precio" badge. Row click (~L511) already
   opens the drawer with the row — no other wiring needed.

5. **Header copy / count** (~L326, L347): make the "pendientes" label + the
   count ThemeIcon conditional on the active tab (queue vs catalog framing).

6. **(Open decision — see §6) Permission gating**: add
   `import { usePermissions } from '@/hooks/usePermissions';`, derive
   `const puedeEditar = can('comercial.editar');`, and hide the edit
   ActionIcon / "Fijar precio base" button + block row-click when false.
   Pattern already used in `comercial/familias-precio/page.tsx`.

**No changes to:** `UpsertCatalogoPrecioDrawer.tsx`, `consulta-precios/page.tsx`,
`familias-precio/page.tsx`, `src/types/supabase.ts` (both views are already
untyped / cast at fetch site).

## 5. Backend / DB changes

**NONE.** No migration, no new object, no GRANT. The feature consumes existing
objects. For the portfolio / mlr-db resync, these are the **contract objects**
this feature relies on (verify they exist and match after any DB resync):

| Object | File | Role |
|---|---|---|
| `doc.vw_precios_estado` | `funciones/facturacion.sql` | source view (con_precio + sin_precio + precio_kg) |
| `doc.vw_precios_pendientes` | `funciones/facturacion.sql` | still used by nothing after this change — kept for other callers; do NOT drop |
| `doc.upsert_catalogo_precio` | `funciones/facturacion.sql` | SCD-2 close-then-insert; keys on dimensions, not row id |
| `doc.fn_get_precio` | `funciones/facturacion.sql` | specificity-scored resolver (billing + views) |
| `doc.fn_precio_info` | `funciones/facturacion.sql` | drawer cost/margin preview + current price prefill |
| `doc.fn_familia_precio` | `funciones/facturacion.sql` | TENIDO grupo→pricing-family normalization |
| `doc.catalogo_precios` | `migration/07_new_tables_mes_doc_calidad.sql` | SCD-2 table (`fyh_cre`/`fyh_elm`) |

## 6. Open decision

**Permission gating on cotizaciones.** The page currently shows edit
affordances to everyone; the backend rejects unauthorized saves
(`upsert_catalogo_precio` raises on missing `comercial.editar`). Recommend
gating the UI too (consistency with familias-precio). If declined, ship §4.1–4.5
only and leave §4.6 out.

## 7. Resync checklist (portfolio + mlr-db)

- **mlr-db work folder:** no DDL to apply for this feature. Confirm the §5
  contract objects are present at parity with `mlr-migracion26`.
- **erp-mes-postgres-portfolio (sanitized, MLR→ACME, frozen 2026-05-25):**
  DB-only repo — this frontend feature does not land here. Only relevant if the
  §5 pricing objects were changed independently; they are not, by this spec.
- **mlr-app:** the actual change target (frontend). Not part of the DB portfolio.

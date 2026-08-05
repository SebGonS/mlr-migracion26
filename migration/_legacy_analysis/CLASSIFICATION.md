# Database Baseline Classification — MLR

Source dump: `prod_backup_20260721_2340.sql` (schema-only, data stripped)
Live stats: `pg_stat_user_tables` + `pg_stat_statements` (since 2026-06-13), run against production 2026-07-21.
Analysis: dependency-driven (FK graph + function-body parse + runtime scan/write stats). **Not** naming-based.

---

## TL;DR verdict

1. **`public` is a *mixed* schema.** It holds the active master/catalog data **and** the entire previous-generation system, side by side. The active/legacy boundary runs **through** `public`, not around it. Any split by schema name or table name is therefore wrong.
2. **The active application does not depend on the legacy cluster.** Zero active (domain-schema) functions reference any legacy-candidate table via a schema-qualified reference; the bare-name cross-check found only false positives (schema-name and PL/pgSQL variable collisions). The legacy tables are referenced only by other legacy `public` objects.
3. **Recommendation: build a clean baseline from the active set; do not carry the legacy cluster forward.** A single hand-authored `baseline.sql` (→ `0000_baseline` migration in the new Supabase repo), with the raw dump archived read-only as the audit fallback. A `legacy` schema inside the new project is the fallback option if you want the objects physically present, but it re-imports the cruft you're trying to escape.

---

## Method & signals

Three independent signals, combined. No single one is trusted alone.

| Signal | Source | What it proves | Blind spot |
|---|---|---|---|
| **FK-by-domain** | catalog FK edges | a `public` table FK'd by an active domain-schema table is load-bearing → **active** | misses non-FK usage (views, function bodies) |
| **`idx_scan`** | `pg_stat_user_tables` | the running app hits live tables by index; high scan = **active**, 0/NULL = not queried | append-only logs written by active code show 0 reads |
| **Qualified function refs** | parsed function bodies | `public.<t>` inside an active function body = real dependency | misses bare names resolved via `search_path` |

**Key methodological finding — bare-name matching is unreliable and must not be trusted.**
A first pass matching bare table names in function bodies produced 100+ false "conflicts":
- `inventario` matched the **schema** `inventario.*`, not the legacy `public.inventario` table (99 bogus hits).
- `estado`, `v_receta_id` matched **PL/pgSQL local variables** (`SELECT … INTO v_receta_id`).
- `item_tipo`, `prioridad`, `turno` are **active master** (high `idx_scan` / FK'd by domain), not legacy.

Only **schema-qualified** `public.<t>` references were used for the final conflict check. This is the same opaque-string trap that makes `pg_depend` alone insufficient — documented here so the baseline build applies the same discipline.

---

## Schema-level classification

| Schema | Verdict | Notes |
|---|---|---|
| `auth`, `storage`, `realtime`, `vault`, `pgsodium`, `graphql`, `graphql_public`, `pgbouncer`, `extensions`, `supabase_migrations` | **Platform — out of scope** | Supabase-managed. Never include in the baseline; Supabase recreates them. |
| `doc`, `mes`, `inventario`, `receta`, `calidad`, `iam`, `notification`, `alertas` | **Active application** | The current system. Nearly all objects active (exceptions flagged below). |
| `audit` | **Active** | `audit.data_audit` (250k rows, written daily) is the live audit trail. |
| `migration` | **Operational, keep separate** | `migration.legacy_executions` (13,984 rows) = migration bookkeeping. Not app data; keep out of the baseline schema, retain as history if useful. |
| `public` | **MIXED — see below** | The whole problem lives here. |

---

## The `public` split (the heart of the analysis)

### Tier A — ACTIVE master/catalog data (KEEP; cannot move)
Hard-anchored by domain FKs and/or heavy index traffic. These are the shared foundation every active schema reads.

| Table | idx_scan | Anchor |
|---|--:|---|
| `color_x_cliente` | 5,297,027 | FK by doc/mes/receta/inventario |
| `color` | 5,076,107 | heavy read |
| `articulo` | 527,389 | heavy read |
| `unidad` | 190,067 | FK by doc/mes |
| `tercero` | 180,685 | FK by 11 domain tables |
| `item` | 91,955 | FK by 14 domain tables |
| `item_rollo_detalle` | 67,893 | 1:1 ext of item |
| `item_tipo` | 52,235 | heavy read |
| `item_insumo_detalle` | 33,026 | 1:1 ext of item |
| `tenido` | 18,850 | FK by doc/mes/receta/inventario |
| `usuario` | 11,014 | FK by iam/mes/inventario/receta/notification |
| `grupo_articulo` | 11,183 | FK by doc/mes/receta (migration/28, recent) |
| `articulo_tipo` | 12,336 | FK by doc/mes/receta |
| `tipo_receta`, `valor`, `insumo_tipo`, `colorante_tipo`, `tipo_lavado_maquina`, `estado_desarrollo_color`, `prioridad`, `grupo_articulo_miembro`, `turno`, `intensidad`, `construccion` | 41–10,129 | FK by domain and/or steady read |

> Note: `grupo_articulo` / `grupo_articulo_miembro` are **recent** additions that happen to live in `public`. Location ≠ age. They are active.

### Tier B — ACTIVE append-only log (KEEP; 0 reads is expected)
| Table | Evidence |
|---|---|
| `logs_api` | 0 index scans but **written by active functions** — `INSERT INTO logs_api(...)` appears in live functions (confirmed via `pg_stat_statements`, e.g. `actualizar_pesos_individuales_partida`, `corregir_matizado`). Keep (candidate to relocate into a dedicated `log`/`audit` schema in the new project). |

### Tier C — LEGACY, superseded by a domain-schema equivalent (MOVE/DROP)
0 qualified refs from any active function; low/residual `idx_scan`; each has a named current replacement.

| Legacy `public` table | Superseded by | idx_scan |
|---|---|--:|
| `compra`, `compra_x_insumo`, `letra_compra` | `doc.compra*`, `doc.letra` | 0 |
| `despacho` | `doc.venta` / `doc.entrega` | 255 (residual) |
| `catalogo_precios` | `doc.catalogo_precios` | 112 (residual) |
| `partida`, `partida_estado_historial`, `partida_x_recetas`, `partida_x_extra` | `mes.partida*` | 0–33 |
| `produccion`, `produccion_tenido`, `programa_tenido`, `programacion` | `mes.partida_paso_ejecucion`, `mes.programacion` | 0 |
| `paso`, `maquina` | `mes.operacion`/`mes.partida_paso`, `mes.maquina` | 0–1 |
| `receta2`, `receta_x_paso`, `receta_x_insumo` | `receta.tenido*` | 0 |
| `receta_lavado_maquina`, `receta_lavado_maquina_x_paso`, `receta_lavado_maquina_x_insumo`, `lavado_maquina` | `receta.lavado_maquina*`, `mes.lavado_maquina` | 0 |
| `entrada_inventario*`, `salida_inventario*`, `salida_inventario_detalle_x_stock`, `inventario` | `inventario.item_movimientos` / `inventario.lote*` | 0 |
| `cuadre_inventario`, `cuadre_inventario_detalle` | `inventario.cuadre*` | 0 |
| `insumo`, `insumo_x_proveedor`, `insumos_precio`, `proveedor`, `proveedor_precio`, `cliente` | `item`+`item_insumo_detalle`, `tercero` | 0–22 |
| `tiempos_estandar_tenido`, `tiempos_estandar_lavado` | `mes.tiempos_estandar_*` | 0 |
| `adicional` | `flg_antipilling` boolean (per memory) | 10 |

### Tier D — LEGACY orphan / dead, no active replacement (MOVE/DROP)
0 qualified refs, 0 index scans. Old QC/color/planning features and pure junk.

- **QC/color (old):** `matizado`, `matizado_estados`, `observado`, `observado_estados`, `observado_motivos`, `observaciones_planta`, `desarrollo_color`, `historial_estado_color`, `detecciones`
- **Planning/planta (old):** `parada_tintoreria`, `retrasos_partida`, `motivo_parada`, `motivos_retraso`, `hora_inicio_maquina`, `metas_produccion_tenido`, `previo`, `extra`, `regla_peso_articulo`, `regla_peso_cliente_articulo`, `pasos_adicional_receta`, `estado`, `unidad_conversion`, `devolucion`, `auditoria` (old audit → superseded by `audit.data_audit`)
- **Acabados (old):** `perchado`, `compactado`, `termofijado`
- **Pure junk / temp / debug (DROP outright):** `tmp`, `tmp2`, `tmp_parche`, `tmp_receta`, `tmp_receta_casos`, `temp_id_partida`, `temp_id_receta`, `temp_insumos_corregidos`, `prod_tmp`, `parada_tmp`, `sertks1`, `sertks2`, `mersan`, `insumo_corregido`, `json_debug_log`, `receta_id`, `v_receta_id`, `id_receta_x_partida`

---

## Safety proof — no active object depends on the legacy cluster

- **FK graph:** every FK from an active domain schema into `public` targets a Tier-A table. No domain FK points at any Tier-C/D table.
- **Function bodies (qualified):** 0 of 366 functions in active schemas contain a `public.<legacy>` reference. The single qualified legacy reference in the entire codebase is `perchado`, inside a *legacy* `public` function.
- **Runtime:** Tier-C/D tables show 0 index scans (only backup/`pg_dump` sequential scans). No live query path touches them.

Residual `idx_scan` on a few Tier-C tables (`despacho` 255, `catalogo_precios` 112, `cliente` 22) comes from **legacy views still defined in `public`**, not from the active app. Those views are themselves legacy and move with their tables.

---

## Domain-schema objects needing a call (not legacy, but not clean baseline material)

| Object | Rows / activity | Recommendation |
|---|---|---|
| `doc.tmp_pricing_baseline` | 15,247 rows, written 2026-07-20 | Scratch table from pricing work living in `doc`. **Exclude from baseline**; confirm it's disposable. |
| `inventario.consumo_kg_fix_log` | 2,852 rows | One-off data-fix log. Keep as history or archive; don't model in baseline as a live table. |
| `mes.empleado`, `mes.empleado_rol`, `mes.partida_paso_lote`, `doc.factura`, `doc.factura_detalle`, `calidad.inspeccion_foto` | 0 rows | **Active but unused features.** Keep in baseline — they're current schema, just not exercised yet. |

---

## Functions / views / types / sequences / triggers — FINALIZED (build pass complete)

Classification method: schema-based default (any object in a domain schema is active by construction) for `doc/mes/inventario/receta/calidad/iam/notification/alertas/audit`; dependency-driven analysis for everything in `public`. For `public` objects: qualified-reference matching against the table tiers, plus two fixpoint passes — **trigger attachment** (a function is active if it fires on a KEEP table) and **call-graph propagation** (a function/view is active if a KEEP function/view calls it, iterated to a fixpoint; also covers column defaults and RLS policies calling a function).

| Object type | Kept | Excluded | Notes |
|---|--:|--:|---|
| Tables | 94 | 129 | Per the tiers above |
| Views | 101 | 37 | See enum-view note below |
| Functions | 229 | 138 | See utility-function note below |
| Types/enums | 21 | 19 | Kept if used by a kept table column or kept function signature |
| Sequences | 60 | 83 | Kept if owned by a kept table column, or referenced (`nextval`) in kept code |
| Triggers | 172 | ~21 | Kept iff both owning table AND target function are kept |
| Indexes | 44 | 80 | Kept iff owning table is kept (most excluded ones belong to platform tables like `auth.users`, not legacy app tables) |
| RLS policies | 95 | 11 | Kept iff owning table is kept |
| Constraints (PK/UNIQUE/CHECK) | 159 | — | Kept iff owning table is kept |
| FK constraints | 180 | — | Kept iff **both** owning and target table are kept (4 exceptions below) |

**Methodological finding — naive bare-name/table-only classification was insufficient and required two extra passes:**
1. A first function pass using only direct table references left **~49 utility functions unresolved** — cross-cutting helpers with no table reference at all (`get_user_id()`, `jwt_has_permission(text)`, `fn_trg_set_cre_fields()`, `fn_trg_set_mod_fields()`, `fn_trg_set_codigo_canon()`, etc.). These are called by active domain functions/triggers but reference no table themselves.
2. Resolved via a **trigger-attachment pass** (function KEEP if it fires via `EXECUTE FUNCTION` on a KEEP table) **and a call-graph pass** (function KEEP if any KEEP function, KEEP view, KEEP-table default expression, or KEEP-table RLS policy calls it — iterated to a fixpoint, since utility functions sometimes call other utility functions). Two hand-verified exceptions survived even this: `get_user_by_id()` (used only inside one legacy view over `entrada_inventario`) and `handle_new_user()` (orphaned — inserts into a `public.profiles` table that doesn't exist in this schema at all, and is not attached to any trigger; a dead Supabase-starter-template leftover). Both explicitly excluded.
3. **12 views** resolved to `UNRESOLVED` because they select only from `_enum` types (`estado_entrada_inventario_enum`, `motivo_salida_inventario_enum`, `tipo_pago_enum`, etc.), not tables — these are legacy display views for enum-backed lookups tied to the excluded `entrada_inventario`/`salida_inventario`/`letra`/`insumo` tables, plus a generic `vw_enums` dev-utility view. All excluded.

**Collation:** `public.case_insensitive` (ICU, case-insensitive) is used as a column collation on **`public.tipo_receta`** (Tier A, active) — confirmed via direct text search, not assumption. Kept in the baseline; would have been wrongly dropped by a naming-only pass since every *view* using it turned out to be legacy.

**Vestigial bridge FKs — found during assembly, resolved by user decision:** `public.tercero` carries `cliente_id`, `cliente_id2`, `proveedor_id`, and `public.color_x_cliente` carries `cliente_id` — leftover FK columns from the historical `cliente`/`proveedor` → `tercero` consolidation (see [[pricing-ownership-model]] and the `tercero` join convention in this project's memory). `tercero` already has its own `flg_cliente`/`flg_proveedor` discriminators; `color_x_cliente` already has the real `tercero_id` column. Zero active code references `cliente`/`proveedor` (confirmed in the safety proof above), so these are pure migration-artifact bridge columns, not a live dependency.
**Decision: keep the columns, drop only the FK constraints.** The columns remain as plain nullable integers (no longer FK-enforced) in case something still reads them for historical lookups; `cliente`/`proveedor` themselves stay excluded/archived. Dropped constraints: `tercero_cliente_id_fkey`, `tercero_cliente_id2_fkey`, `tercero_proveedor_id_fkey`, `color_x_cliente_fk_cliente_fkey`.

**Not carried into the baseline (by design, not oversight):** `COMMENT` objects (47, cosmetic/optional), `RULE` blocks (3 — redundant with `CREATE VIEW`, which already implicitly creates the same `_RETURN` rule), `EVENT TRIGGER` (6, all Supabase-platform-owned), `PUBLICATION`/`PUBLICATION TABLE` (Supabase auto-provisions `supabase_realtime`; zero app tables were actually added to it in this dump), `TABLE ATTACH`/`TABLE DATA` (all `realtime`/`storage` platform partitions), `SEQUENCE SET` (current production counter values — operational data, not schema; re-sync sequences at data-load time instead if real data is imported later).

---

## Uncertain bucket — RESOLVED

1. `doc.tmp_pricing_baseline` — **disposable.** Excluded from baseline; not archived.
2. `logs_api` — **keep, don't move.** Stays in `public` in the baseline (active log table, written by live code). `json_debug_log` remains excluded (pure debug junk, no writer found in active code).
3. `construccion`, `intensidad` — **confirmed part of Tier A (active master).** Included in baseline alongside the rest of Tier A.
4. `migration.legacy_executions` — **archive.** Excluded from the live baseline; carried into `archive_legacy.sql` for historical reference, not into `0000_baseline.sql`.

---

## Recommended target artifact & workflow

**Artifact:** one hand-authored `baseline.sql` = Tier-A + Tier-B + all active domain-schema objects, dependency-ordered (extensions → schemas → types → tables → sequences → constraints → functions → triggers → views → policies → grants). This becomes `supabase/migrations/0000_baseline.sql` in the new repo. Every later change is a normal timestamped Supabase migration. The raw dump stays archived read-only as the historical reference.

**Why not the alternatives:**
- *Raw schema-only dump as baseline* — carries Tier-C/D cruft and platform schemas.
- *Existing `migration/01–14` + `funciones/*` chain* — the accumulated-patch history you're leaving behind.
- *`legacy` schema inside the new project* — valid fallback if you need the objects physically present for audit, but it re-imports the cruft; the archived dump serves the same purpose without polluting the new schema.

## Deliverables (build pass complete)

- **`migration/_legacy_analysis/baseline.sql`** — the active-object-only baseline (schemas, extensions, collation, types, tables, sequences, defaults, constraints, functions, FK constraints, triggers, views, indexes, RLS, policies, grants), dependency-ordered. Copy this into the new project as `supabase/migrations/0000_baseline.sql`.
- **`migration/_legacy_analysis/archive_legacy.sql`** — reference-only dump of the excluded tables/views/functions/types (Tier C/D + junk + `migration.legacy_executions`). Not meant to be executed; kept for historical lookup if a question comes up later about what an old object used to do.
- **`migration/_legacy_analysis/validation.sql`** — run this against the new project *after* loading `baseline.sql`, to confirm object counts match expectations, no legacy table leaked in, the vestigial-FK drop landed as intended, and RLS/extensions/collation are present.
- **`migration/_legacy_analysis/prod_stats_queries.sql`** — the original production-stats probes used to harden this classification (kept for provenance).

**Not yet done:** no live execution test of `baseline.sql` against a real Postgres instance (out of scope for this pass — this is reference material for a not-yet-created project, not something being deployed now). The first real syntax/dependency check will happen naturally the first time it's loaded into an actual empty database; `validation.sql` is written for exactly that moment.

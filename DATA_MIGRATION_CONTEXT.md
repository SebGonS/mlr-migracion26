# Data Migration Context — mlr-migracion26
_Last updated: 2026-03-19. Continue from this file on a new workstation._

---

## Current DB State

| Section | Status |
|---------|--------|
| Schemas, enums, tables (01–10) | ✅ Done |
| `mes.operacion` incl. COMPACTADO | ✅ Done (or run standalone INSERT below) |
| `tipo_receta.orden_produccion_tipo` column | ✅ Done |
| `doc.partida` INSERT | ✅ Done |
| `doc.guia_remision` + `_detalle` | ✅ Done |
| `inventario.lote` PARTIDA rows (raw rolls) | ✅ Done — **old logic** (Steps 1+4 only) |
| `inventario.item_movimientos` SERV_ING | ✅ Done |
| `mes.orden_produccion` (pxr-derived) | ✅ Done |
| `mes.orden_produccion_paso` (pxr-derived) | ✅ Done |
| `mes.orden_produccion_item` (opi) | ❌ Needs redo — old LATERAL LIMIT 1 logic |
| `mes.orden_produccion_paso_item` (oppi) | ❌ Needs redo |
| Insumo ingress/egress movements | ✅ Done |
| Roll Steps 5–8 (PROD_CONSUMO, ghost, dyed lotes) | ❌ Not run |
| `produccion_tenido` enrich + backfill | ❌ Not run |
| `inventario.pesaje` backfill | ❌ Not run |
| `inventario.item_valoracion` seed | ❌ Not run |
| Finishing tables (termofijado, compactado, perchado, observado, perchado) | ❌ Not designed yet |

---

## Immediate Next Steps (in order)

### 1. Fix opi/oppi — cleanup first
```sql
DELETE FROM mes.orden_produccion_paso_item
WHERE orden_produccion_item_id IN (
    SELECT id FROM mes.orden_produccion_item
    WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo = 'PARTIDA')
);
DELETE FROM mes.orden_produccion_item
WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo = 'PARTIDA');
```

### 2. Run opi/oppi rerun snippet
File: [migration/11_data_migration.sql](migration/11_data_migration.sql)
Search for `RERUN SNIPPET` (~line 2349). Uncomment and run the block.
This reads existing lotes from `inventario.lote` and assigns them to the correct
pxr paso using `pxr_ranges` (NORMAL cumulative, REPROCESO offset=0).
SERV_ING movements already exist — do NOT re-run Step 4.

### 3. Run Steps 5–8
After opi/oppi are correct, run sequentially from the file:
- **Step 5** — `PROD_CONSUMO` (NORMAL pasos only, ~line 2415)
- **Step 6** — Ghost `SERV_EGR` for rolls with opi but no oppi (~line 2460)
- **Steps 7–8** — Dyed lote `PROD_ING` + `SERV_EGR` from last paso (~line 2510)

### 4. Run produccion_tenido enrichment
Search for `ENRICH / BACKFILL DYEING ORDENES FROM produccion_tenido` (~line 1480).
- Part A: UPDATEs fyh_inicio/fyh_fin on 5277 existing pxr-derived ordenes
- Part B: INSERTs 357 new ordenes+pasos for older history not in pxr
Run the two `setval` resets immediately after.

### 5. Run pesaje backfill
Search for `BACKFILL PESAJE` (~line 2540).
One pesaje row per raw roll lote using lote.cantidad as peso_real.

### 6. Run item_valoracion seed
Search for `SEED ITEM_VALORACION` (~line 2560).

---

## Pending Design — Finishing Tables

These legacy tables need migration. Schema is clear, SQL not yet written.
Run **after** Steps 7–8 (finishing steps consume dyed lotes from Step 7).

| Legacy table | Rows | Target | operacion |
|---|---|---|---|
| `termofijado` | 360 | `orden_produccion` + `paso` | TERMOFIJADO |
| `produccion_tenido` | 5634 | handled above (step 4) | TENIDO |
| `compactado` | 4984 | `orden_produccion` + `paso` | COMPACTADO |
| `perchado` | 702 | `orden_produccion` + `paso` | PERCHADO |
| `observado` | 638 | `calidad.inspeccion` | — |

**termofijado columns:** `id, partida_id, fecha, turno_id, hora_inicio, hora_fin, duracion, rollos`
**compactado columns:** `id, partida_id, fecha, rollos, hora_inicio, hora_fin, duracion, maquina_id, turno_id, tipo_proceso, estado, rib`
**perchado columns:** `id, partida_id, fecha, turno_id, hora_inicio, hora_fin, duracion, rollos, pases`
**observado columns:** `id, partida_id, fecha, rollos, motivo_observado_id, flg_elm, detalle, fyh_cre, fyh_cre_tz, rib`

For termofijado/compactado/perchado the pattern is the same as produccion_tenido Part B:
one `orden_produccion` + one `orden_produccion_paso` per row, rolls linked via opi/oppi
to the dyed lotes already in `inventario.lote` (documento_tipo = 'ORDEN_PRODUCCION_PASO').

Still need to confirm `calidad.inspeccion` column structure before writing `observado` migration.

---

## Key Architecture Decisions

- **1:1:1 model**: each `partida_x_recetas` row → 1 `orden_produccion` → 1 `orden_produccion_paso`, all using `pxr.id` via `OVERRIDING SYSTEM VALUE`.
- **REPROCESO roll assignment**: offset always 0 — REPROCESO pasos re-process rolls 1..pxr.rollos from the same partida (overlinking), no phantom inventory movements recorded for REPROCESO pasos.
- **Dyed lote creation**: only from the LAST paso per partida (`DISTINCT ON partida_id ORDER BY pxr.fecha DESC`).
- **PROD_CONSUMO guard**: `AND op.tipo = 'NORMAL'` — REPROCESO pasos carry opi/oppi for roll-count traceability but produce no inventory debit.
- **Ghost Step 6**: SERV_EGR on raw lotes that have opi but no oppi (linked to paso secuencia=1 of their orden).
- **produccion_tenido as ground truth**: covers ~2 months more history than pxr. For matched rows updates fyh_inicio/fyh_fin. For unmatched inserts new ordenes.
- **Bridge columns** `tercero.cliente_id`, `cliente_id2`, `proveedor_id`: kept (commented-out DROP at end of file). Remove after go-live stabilizes.
- **UTC-5 correction**: all DATE→TIMESTAMPTZ coercions use `::TIMESTAMP + INTERVAL '5 hours'`.

---

## Standalone Fixes Needed on Live DB (if migrations already ran)

```sql
-- Add COMPACTADO operacion if 07 already ran
INSERT INTO mes.operacion (codigo, nombre, requiere_receta)
VALUES ('COMPACTADO', 'Compactado', false)
ON CONFLICT (codigo) DO NOTHING;

-- Fix MLR client bridge
UPDATE tercero SET cliente_id = 13 WHERE id = 1;
```

---

## Files of Interest

| File | Purpose |
|------|---------|
| `migration/11_data_migration.sql` | Main migration — all data inserts |
| `migration/07_new_tables_mes_doc_calidad.sql` | operacion seed (COMPACTADO added) |
| `SCHEMA_MANUAL.md` | Full schema reference |
| `FRONTEND_BACKEND_MAP.md` | Frontend→backend mapping |

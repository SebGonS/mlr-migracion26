# Frontend Spec — Admin Reversal Actions

All functions live in `funciones/reversiones.sql` and require:
- A **Motivo** text field (non-empty, mandatory on every call — backend raises if blank)
- A **confirmation dialog** before executing (these are destructive admin operations)
- Display of the returned message on success, and the exception message verbatim on error

Prerequisite migration: `migration/23_reversal_movement_types.sql` must be applied first.

---

## 1. `inventario.anular_pesaje`

```
Signature:  inventario.anular_pesaje(p_lote_id BIGINT, p_motivo TEXT) → TEXT
Permission: inventario.editar
```

**Where:** Lote detail view → admin action menu, or in the partida components table as a per-row action.

**Show button when:**
- `inventario.pesaje` row exists for lote (`tipo IN ('INGRESO','CORRECCION')`)
- Lote has no movements of type outside `PESAJE_POS`, `PESAJE_NEG` (i.e., no `PROD_CONSUMO` — roll not yet in production)
- Lote `fyh_elm IS NULL`

A simple proxy: if the lote has a `pesaje` record AND `estado_produccion` of its parent partida is not yet `EN_PRODUCCION`/`TECO`/`CERRADA`.

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_lote_id` | BIGINT | from context (not user-entered) |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Show returned TEXT. Refresh `lote.cantidad` display (now shows guía declared weight).

**Key errors to handle:**
- `"Lote % no tiene registro de pesaje activo."` — button should already be hidden; hide and show generic "ya no disponible"
- `"Lote % ya tiene movimientos de producción u otros."` — same as above
- `"Lote % no encontrado, ya anulado, o sin guía de ingreso asociada."` — show verbatim

---

## 2. `inventario.revertir_cuadre_preparado`

```
Signature:  inventario.revertir_cuadre_preparado(p_cuadre_id BIGINT, p_motivo TEXT) → VOID
Permission: inventario.editar
```

**Where:** Cuadre list or detail page → action button visible only when `cuadre.estado = 'preparado'`.

**Show button when:** `cuadre.estado = 'preparado'`

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_cuadre_id` | BIGINT | from context |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Returns VOID. Show generic "Cuadre revertido a borrador." and refresh cuadre estado chip.

**Key errors:**
- `"Cuadre % no existe o no está en estado preparado."` — stale UI; refresh and re-check.

---

## 3. `inventario.anular_cuadre_ejecutado`

```
Signature:  inventario.anular_cuadre_ejecutado(p_cuadre_id BIGINT, p_motivo TEXT) → TEXT
Permission: inventario.editar
```

**Where:** Cuadre detail page → destructive action (separate from normal cuadre workflow). Only visible to users with `inventario.editar`. Show with a warning banner ("Esta acción revierte todos los ajustes de inventario").

**Show button when:** `cuadre.estado = 'ejecutado'`

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_cuadre_id` | BIGINT | from context |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Show returned TEXT (includes count of reversed adjustments). Navigate back to cuadre list or reload — cuadre is now in `borrador`.

**Key errors:**
- `"los lotes de sobrante ya tienen movimientos posteriores"` — show verbatim. Admin must trace and reverse those downstream documents first (guías, ajustes).

**UX note:** This is the most destructive action in the set. Consider requiring the cuadre ID to be typed into a confirmation field.

---

## 4. `mes.anular_omision_paso`

```
Signature:  mes.anular_omision_paso(p_paso_id BIGINT, p_motivo TEXT) → TEXT
Permission: produccion.administrar
```

**Where:** Partida detail → pasos timeline → per-paso action menu when paso estado is `OMITIDO`.

**Show button when:** `partida_paso.estado = 'OMITIDO'` AND partida `estado_produccion NOT IN ('CERRADA','CANCELADA')`

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_paso_id` | BIGINT | from context |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Show returned TEXT. Refresh paso estado chip to `PENDIENTE`. Partida state may also change (actualizar_estado_partida is called internally).

**Key errors:**
- `"hay pasos posteriores ya completados"` — show verbatim. Admin must anular those downstream pasos first (via `mes.anular_produccion`).
- `"La partida #% está en estado % y no permite modificaciones."` — show verbatim.

---

## 5. `mes.anular_transferencia_rollo`

```
Signature:  mes.anular_transferencia_rollo(
              p_lote_id          INT,
              p_partida_actual   BIGINT,
              p_partida_original BIGINT,
              p_motivo           TEXT
            ) → TEXT
Permission: produccion.administrar
```

**Where:** Partida detail → components list → per-roll action menu → "Revertir transferencia".

**Show button when:** Roll's current `partida_componente.partida_id` differs from the roll's ingress partida (i.e., it was transferred). Proxy: check `logs_api` for a `transferir_rollo_partida` entry for this lote.

**How to populate `p_partida_original`:**

`p_partida_original` is NOT derivable from current schema state — it must come from `logs_api`. Query:

```sql
SELECT (params->>'partida_origen')::BIGINT AS partida_original
FROM logs_api
WHERE function_name = 'transferir_rollo_partida'
  AND (params->>'lote_id')::INT = :lote_id
ORDER BY fyh_cre DESC
LIMIT 1;
```

If no log entry exists (data predates logs or was manually moved), the admin must enter the original partida ID manually. Expose a search/select field for partida.

**Inputs:**
| Field | Type | Source |
|---|---|---|
| `p_lote_id` | INT | from context |
| `p_partida_actual` | BIGINT | from context (current partida) |
| `p_partida_original` | BIGINT | from logs_api query above; fallback: manual input |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Show returned TEXT. Remove roll from current partida's component list; it now appears on the original partida.

**Key errors:**
- `"El rollo (lote #%) ya fue consumido en producción."` — button should already be hidden; show "ya no disponible"
- `"La partida original #% está en estado % y no puede recibir rollos."` — show verbatim (CERRADA/CANCELADA)
- `"El rollo (lote #%) ya está asignado a la partida original #%."` — stale UI; refresh

---

## 6. `calidad.anular_inspeccion`

```
Signature:  calidad.anular_inspeccion(p_inspeccion_id BIGINT, p_motivo TEXT) → TEXT
Permission: calidad.crear
```

**Where:** Lote QC history panel → per-inspection action menu → "Anular inspección". Also accessible from the inspection detail view.

**Show button when:**
- Inspection exists (not already deleted)
- Lote `fyh_elm IS NULL` (not scrapped)
- Lote has no `VENTA_EGR`, `SERV_EGR`, or `PROD_SCRAP` movements

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_inspeccion_id` | BIGINT | from context |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Show returned TEXT. Remove inspection from QC history list. Refresh `lote.estado_calidad` badge — may revert to a prior inspection's result or `PENDIENTE`.

**Key errors:**
- `"El lote #% ya fue dado de baja."` — show with hint "Use Revertir Baja primero"
- `"El lote #% ya fue despachado o dado de baja."` — show verbatim

**Note:** This is a hard delete — the inspection cannot be recovered. Make this clear in the confirmation dialog.

---

## 7. `calidad.revertir_baja_lote`

```
Signature:  calidad.revertir_baja_lote(p_lote_id INT, p_motivo TEXT) → TEXT
Permission: calidad.crear
```

**Where:** This lote is soft-deleted (`fyh_elm IS NOT NULL`), so it will NOT appear in normal lote lists. Requires a dedicated "Lotes dados de baja" admin view that queries `inventario.lote WHERE fyh_elm IS NOT NULL`.

**Show button when:**
- `lote.fyh_elm IS NOT NULL`
- `PROD_SCRAP` movement exists for lote
- No movements beyond `PROD_ING`, `PROD_ING_REV`, `PROD_SCRAP`

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_lote_id` | INT | from context |
| `p_motivo` | TEXT | required, non-empty |

**On success:** Show returned TEXT. Lote reappears in normal inventory. `estado_calidad` will be `BAJA` — admin should follow up with `anular_inspeccion` if they also want to remove the QC verdict.

**Key errors:**
- `"Lote % no encontrado o no está dado de baja."` — stale UI; refresh list
- `"Lote % tiene movimientos posteriores a la baja."` — show verbatim; admin must trace those first
- `"Tipo PROD_SCRAP_REV no encontrado."` — migration not applied; show "Contacte al administrador del sistema"

**UX flow:** revertir_baja_lote restores the lote to estado_calidad=BAJA. If the goal is to fully clear the QC verdict, the admin should then call `anular_inspeccion` on the lote's inspection. Consider offering this as a two-step confirmation: "¿También desea anular la inspección de calidad que originó la baja?"

---

## 8. `calidad.bulk_anular_decision_calidad`

```
Signature:  calidad.bulk_anular_decision_calidad(p_lote_ids INT[], p_motivo TEXT) → JSONB
Permission: calidad.crear
```

**Where:** Partida QC view → multi-select lotes → bulk action toolbar → "Anular decisión de calidad".

**Show bulk action when:** One or more lotes selected that have an inspection record.

**Inputs:**
| Field | Type | Validation |
|---|---|---|
| `p_lote_ids` | INT[] | from multi-select; at least 1 |
| `p_motivo` | TEXT | required, non-empty; applies to all |

**Return shape:**
```jsonb
{
  "anulados": 3,
  "fallidos": 1,
  "total":    4,
  "success": [
    { "lote_id": 101, "inspeccion_id": 55, "message": "Inspección #55 ... anulada." },
    ...
  ],
  "failed": [
    { "lote_id": 104, "inspeccion_id": 58, "error": "El lote #104 ya fue despachado..." },
    ...
  ]
}
```

**On success:** Show summary banner: "X decisiones anuladas, Y fallidas." If any failed, show a collapsible list of failures with lote_id + error message. Refresh lote `estado_calidad` badges for all successfully processed lotes.

**Partial failure:** This is expected behavior — the function does not abort on per-lote errors. A lote that fails does not block the others. Show the partial result clearly rather than treating it as a full error.

**Key per-lote errors (in `failed[].error`):**
- `"Sin inspección activa para este lote"` — lote had no inspection; selection was valid UI state but stale data
- `"El lote #% ya fue despachado o dado de baja."` — show with guidance to resolve that first

---

## General UX Patterns

**Confirmation dialog — required on all 8 functions:**
```
Title:   "Confirmar anulación"
Body:    [Function-specific description of what will change]
Fields:  Motivo (text input, required)
Actions: [Cancelar] [Confirmar y anular]  ← destructive button styled in red/warning
```

**Permission gating:**
| Permission | Functions |
|---|---|
| `inventario.editar` | anular_pesaje, revertir_cuadre_preparado, anular_cuadre_ejecutado |
| `produccion.administrar` | anular_omision_paso, anular_transferencia_rollo |
| `calidad.crear` | anular_inspeccion, revertir_baja_lote, bulk_anular_decision_calidad |

Hide action buttons entirely for users lacking the required permission — don't just disable them.

**Error display:** All backend errors are raised as PostgreSQL exceptions with descriptive Spanish messages. Show them verbatim in a toast or inline error — they are already user-readable.

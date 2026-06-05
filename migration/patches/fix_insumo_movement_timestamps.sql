-- ─────────────────────────────────────────────────────────────────────────────
-- FIX: Insumo egress movements (PROD_CONSUMO / AJUSTE_NEG / MUESTRA_EGR)
--   where fecha_hora is stuck at a migration-run timestamp.
--
-- Correct source: salida_inventario_detalle_x_stock.fecha
--
-- Guards:
--   - Excludes cuadre-linked movements (documento_tipo = 'cuadre') — those
--     correctly carry the cuadre execution timestamp, not the sdxs.fecha.
--   - Excludes live-system movements (fyh_cre >= go-live cutoff) — their
--     fecha_hora is already correct (set at transaction time by the live system).
--   - Guards against fan-out: uses DISTINCT ON (im.id) to ensure one sdxs
--     row per movement even if the same lote/cantidad matches multiple salidas.
--   - Rolls are excluded automatically: sdxs only covers insumo lotes.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────

-- Candidate movements: migrated egress where fecha_hora != sdxs.fecha,
-- excluding cuadres and live-system rows.
-- If fan-out exists the count here may exceed the UPDATE row count — that's OK,
-- the UPDATE resolves it via DISTINCT ON.
SELECT
    i.codigo                        AS item,
    imt.codigo                      AS tipo,
    COUNT(DISTINCT im.id)           AS movements_to_fix,
    MIN(sdxs.fecha)                 AS earliest_correct_ts,
    MAX(sdxs.fecha)                 AS latest_correct_ts,
    MIN(im.fecha_hora)              AS wrong_ts_min,
    MAX(im.fecha_hora)              AS wrong_ts_max
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt
    ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
JOIN item i ON i.id = im.item_id
JOIN public.salida_inventario_detalle_x_stock sdxs
    ON sdxs.inventario_id           = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si
    ON si.id  = sid.salida_inventario_id
    AND si.estado = 'aprobado'
WHERE im.fecha_hora               != sdxs.fecha
  AND im.documento_tipo            IS DISTINCT FROM 'cuadre'
  AND im.fyh_cre                   < '2025-09-25 00:00:00+00'   -- migrated only
GROUP BY i.codigo, imt.codigo
ORDER BY i.codigo, imt.codigo;

-- Fan-out check: any (lote_id, cantidad) that maps to more than one sdxs.fecha?
-- These will be resolved by MIN(sdxs.fecha) in the UPDATE below — verify that
-- the earliest date is the correct one for any items flagged here.
SELECT
    im.id           AS mov_id,
    i.codigo        AS item,
    im.lote_id,
    im.cantidad,
    im.fecha_hora   AS current_ts,
    COUNT(DISTINCT sdxs.fecha) AS distinct_sdxs_dates,
    MIN(sdxs.fecha) AS will_use_ts
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt
    ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
JOIN item i ON i.id = im.item_id
JOIN public.salida_inventario_detalle_x_stock sdxs
    ON sdxs.inventario_id           = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si ON si.id = sid.salida_inventario_id AND si.estado = 'aprobado'
WHERE im.fecha_hora               != sdxs.fecha
  AND im.documento_tipo            IS DISTINCT FROM 'cuadre'
  AND im.fyh_cre                   < '2025-09-25 00:00:00+00'
GROUP BY im.id, i.codigo, im.lote_id, im.cantidad, im.fecha_hora
HAVING COUNT(DISTINCT sdxs.fecha) > 1;


-- ── EXECUTE ──────────────────────────────────────────────────────────────────

ALTER TABLE inventario.item_movimientos
    DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

BEGIN;

WITH correct_ts AS (
    -- One row per movement: resolve fan-out by taking the earliest sdxs.fecha.
    -- The earliest date is the first time this lote/qty was debited in legacy,
    -- which is the most conservative/correct anchor.
    SELECT DISTINCT ON (im.id)
        im.id    AS mov_id,
        sdxs.fecha AS correct_fecha_hora
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt
        ON imt.id = im.item_movimiento_tipo_id
        AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
    JOIN public.salida_inventario_detalle_x_stock sdxs
        ON sdxs.inventario_id           = im.lote_id
        AND sdxs.cantidad::numeric(12,4) = im.cantidad
    JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
    JOIN public.salida_inventario si ON si.id = sid.salida_inventario_id AND si.estado = 'aprobado'
    WHERE im.fecha_hora               != sdxs.fecha
      AND im.documento_tipo            IS DISTINCT FROM 'cuadre'
      AND im.fyh_cre                   < '2025-09-25 00:00:00+00'
    ORDER BY im.id, sdxs.fecha ASC  -- earliest sdxs.fecha wins on fan-out
)
UPDATE inventario.item_movimientos im
SET    fecha_hora = ct.correct_fecha_hora
FROM   correct_ts ct
WHERE  im.id = ct.mov_id;

-- Verify: should return 0 rows (cuadre and live rows excluded from check)
SELECT imt.codigo, COUNT(DISTINCT im.id) AS remaining
FROM   inventario.item_movimientos im
JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
JOIN   public.salida_inventario_detalle_x_stock sdxs
    ON sdxs.inventario_id = im.lote_id AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN   public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
JOIN   public.salida_inventario si ON si.id = sid.salida_inventario_id AND si.estado = 'aprobado'
WHERE  im.fecha_hora != sdxs.fecha
  AND  im.documento_tipo IS DISTINCT FROM 'cuadre'
  AND  im.fyh_cre < '2025-09-25 00:00:00+00'
GROUP BY 1;

-- ROLLBACK;
COMMIT;

ALTER TABLE inventario.item_movimientos
    ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

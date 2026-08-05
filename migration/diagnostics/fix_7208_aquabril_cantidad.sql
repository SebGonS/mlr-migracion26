-- ============================================================================
-- FIX: receta.tenido id=7208 has an aquabril insumo line entered as 0.186
-- instead of the intended 1.86. Correcting the cantidad on
-- receta.tenido_paso_insumo (via its parent receta.tenido_paso rows for
-- receta_id=7208). The immutability trigger
-- (trg_bud_tenido_paso_insumo_immutable, migration/06_receta_tables.sql:223)
-- will itself RAISE EXCEPTION and roll this back if the recipe already has a
-- COMPLETADO mes.partida_paso_ejecucion row, so the UPDATE is self-guarding --
-- the SELECT below is just to eyeball state before/after.
-- ============================================================================

-- ── Before: locate the row and confirm no completed executions exist ───────
SELECT
    tpi.id,
    tpi.paso_id,
    tpi.item_id,
    i.nombre AS item_nombre,
    tpi.cantidad,
    tpi.medida,
    EXISTS (
        SELECT 1
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
        WHERE pp.receta_id = tp.receta_id
          AND pe.estado = 'COMPLETADO'
    ) AS tiene_ejecucion_completada
FROM receta.tenido_paso_insumo tpi
JOIN receta.tenido_paso tp ON tp.id = tpi.paso_id
JOIN item i ON i.id = tpi.item_id
WHERE tp.receta_id = 7208
  AND tpi.cantidad = 0.186;

-- ── Fix: 0.186 -> 1.86 ───────────────────────────────────────────────────
UPDATE receta.tenido_paso_insumo tpi
SET cantidad = 1.86
FROM receta.tenido_paso tp
WHERE tpi.paso_id = tp.id
  AND tp.receta_id = 7208
  AND tpi.cantidad = 0.186;

-- ── After: verify ────────────────────────────────────────────────────────
SELECT tpi.id, tpi.paso_id, tpi.item_id, i.nombre AS item_nombre, tpi.cantidad
FROM receta.tenido_paso_insumo tpi
JOIN receta.tenido_paso tp ON tp.id = tpi.paso_id
JOIN item i ON i.id = tpi.item_id
WHERE tp.receta_id = 7208;

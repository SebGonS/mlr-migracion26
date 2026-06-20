-- Rename partida_paso_ejecucion.cantidad → cantidad_rollos.
-- `cantidad` was ambiguous: everywhere else in the schema it means kg (lote.cantidad,
-- guia_remision_detalle.cantidad, etc.). Roll count is the non-SKU unit here, so the
-- explicit name prevents confusion now that peso_kg occupies the weight slot.
-- JSON input keys (p_datos->>'cantidad') are intentionally left unchanged for API compat —
-- the rename is DB-layer only. JSON output keys in get_partida / get_reporte are updated.

ALTER TABLE mes.partida_paso_ejecucion
    RENAME COLUMN cantidad TO cantidad_rollos;

-- Add peso_kg to partida_paso_ejecucion.
-- Stores the snapshotted weight processed in each execution run, immune to
-- subsequent reproceso splits that would shift partida_componente lote weights.
--
-- Population logic (mirrored in finalizar_paso / registrar_ejecucion_partida):
--   1. If the step registered produccion output: SUM of output lote weights
--      (document_tipo='partida_paso_ejecucion', documento_id=this row's id)
--   2. Otherwise (non-final step): prorate total partida input roll weight
--      by (run cantidad / total assigned rolls). When cantidad is NULL (all rolls),
--      the fraction is 1.0 and the full input weight is used.

ALTER TABLE mes.partida_paso_ejecucion
    ADD COLUMN IF NOT EXISTS peso_kg NUMERIC(12,4);

-- ── Backfill existing COMPLETADO rows ────────────────────────────────────────
UPDATE mes.partida_paso_ejecucion ppe
SET peso_kg = COALESCE(
    -- Output lotes (final step with registered produccion)
    (SELECT SUM(l.cantidad)
     FROM inventario.lote l
     WHERE l.documento_tipo = 'partida_paso_ejecucion'
       AND l.documento_id   = ppe.id
       AND l.fyh_elm IS NULL),
    -- Prorated input roll weights (non-final step)
    (SELECT ROUND(
         SUM(l.cantidad)
         * COALESCE(ppe.cantidad, MAX(totals.cnt))
         / NULLIF(MAX(totals.cnt), 0),
         4)
     FROM mes.partida_componente pc
     JOIN mes.partida_paso pp2  ON pp2.id = ppe.partida_paso_id
     JOIN inventario.lote l     ON l.id   = pc.lote_id
     CROSS JOIN LATERAL (
         SELECT COUNT(*)::numeric AS cnt
         FROM mes.partida_componente pc2
         WHERE pc2.partida_id  = pp2.partida_id
           AND pc2.lote_id IS NOT NULL
     ) totals
     WHERE pc.partida_id = pp2.partida_id
       AND pc.lote_id IS NOT NULL)
)
WHERE ppe.estado = 'COMPLETADO';

-- Bulk-reverts every remaining QC inspection tied to a partida_paso_ejecucion,
-- so revertir_inicio_paso (which requires zero calidad.inspeccion rows referencing
-- the run — see inspeccion_partida_paso_ejecucion_id_fkey) can proceed afterward.
--
-- Plain-SQL version (no psql \set / \gset — run each numbered block manually
-- in VS Code / any client). Fill in EJECUCION_ID first.

-- 0. If you only know the paso_id, resolve the EN_PROCESO ejecucion_id:
-- SELECT id FROM mes.partida_paso_ejecucion
-- WHERE partida_paso_id = <PASO_ID> AND estado = 'EN_PROCESO';

-- 1. Preview: lotes still holding a live inspection for this run
--    (already-reverted ones won't show up — anular_inspeccion hard-deletes the row)
SELECT ci.id AS inspeccion_id, ci.lote_id, ci.resultado, ci.fyh_inspeccion
FROM   calidad.inspeccion ci
WHERE  ci.partida_paso_ejecucion_id = 31105
ORDER  BY ci.lote_id;

-- 2. Build the payload and run the batch reversal
SELECT calidad.bulk_anular_decision_calidad(
    (SELECT array_agg(DISTINCT lote_id)
     FROM   calidad.inspeccion
     WHERE  partida_paso_ejecucion_id = 31105),
    'Reversión de paso - corrección operativa'
) AS resultado;

-- 3. Confirm zero remain before retrying mes.revertir_inicio_paso(<PASO_ID>)
SELECT count(*) AS inspecciones_restantes
FROM   calidad.inspeccion
WHERE  partida_paso_ejecucion_id = 31105;



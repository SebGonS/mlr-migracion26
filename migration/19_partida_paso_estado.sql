-- ═══════════════════════════════════════════════════════════════
-- 19. PARTIDA_PASO ESTADO — stored estado column (JEST equivalent)
--     Adds estado to partida_paso so the scheduling board and list
--     views can read it directly instead of deriving it from
--     partida_paso_ejecucion at query time.
--     Reuses partida_paso_estado_enum (PENDIENTE/EN_PROCESO/COMPLETADO/OMITIDO)
--     already defined in 02_enums.sql and used by lavado_maquina.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE mes.partida_paso
    ADD COLUMN estado partida_paso_estado_enum NOT NULL DEFAULT 'PENDIENTE';

-- Backfill from existing ejecuciones, using the same quantity-vs-assigned-rolls
-- logic as finalizar_paso: COMPLETADO only when all assigned rolls are covered.
UPDATE mes.partida_paso pp
SET estado = CASE
    WHEN EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
    ) THEN 'EN_PROCESO'::partida_paso_estado_enum
    WHEN EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id AND pe.estado = 'OMITIDO'
        AND NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe2
            WHERE pe2.partida_paso_id = pp.id AND pe2.estado IN ('EN_PROCESO','COMPLETADO')
        )
    ) THEN 'OMITIDO'::partida_paso_estado_enum
    WHEN (
        SELECT COALESCE(SUM(pe.cantidad) FILTER (WHERE pe.estado = 'COMPLETADO'), 0)
        FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id
    ) >= (
        SELECT COUNT(*)
        FROM mes.partida_componente pc
        WHERE pc.partida_id = pp.partida_id
          AND pc.lote_id IS NOT NULL
    ) AND EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    ) THEN 'COMPLETADO'::partida_paso_estado_enum
    WHEN EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    ) THEN 'EN_PROCESO'::partida_paso_estado_enum
    ELSE 'PENDIENTE'::partida_paso_estado_enum
END;



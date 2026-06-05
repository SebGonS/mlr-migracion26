-- ─────────────────────────────────────────────────────────────────────────────
-- ONE-TIME BACKFILL: correct estado_produccion for existing partidas
--
-- Run once after deploying the updated funciones/mes.sql and funciones/core.sql.
-- Uses the extended actualizar_estado_partida which now owns the full lifecycle:
--   CREADA → PLANIFICADA  (steps exist)
--   PLANIFICADA → PROGRAMADA  (on the board)
--   PROGRAMADA → PLANIFICADA  (removed from board)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_id BIGINT;
BEGIN
    FOR v_id IN
        SELECT id FROM mes.partida
        WHERE estado_produccion NOT IN ('CERRADA','CANCELADA','TECO','EN_PRODUCCION') AND id>4000
        ORDER BY id
    LOOP
        PERFORM mes.actualizar_estado_partida(v_id);
    END LOOP;
END;
$$;

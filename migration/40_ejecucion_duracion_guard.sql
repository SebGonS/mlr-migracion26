-- ═══════════════════════════════════════════════════════════════
-- Step 40: DB-level guards on closing a partida_paso_ejecucion run.
--
-- Consolidates into ONE trigger (same row, same "closing this run"
-- event as the roll-count guard from migration 39) instead of a
-- second trigger, since both checks fire on the identical condition
-- (estado -> COMPLETADO) and read overlapping row/parent data:
--   1. Roll count can never exceed rolls assigned to the partida
--      (moved here unchanged from 39_ejecucion_cantidad_guard.sql).
--   2. fyh_fin can never precede fyh_inicio (any operación — plain
--      data-sanity check, not operación-specific).
--   3. COMPACTADO runs can't exceed 4 hours. Hardcoded to COMPACTADO
--      / 4h for now. Long-term this should become a per-operacion
--      column (e.g. mes.operacion.duracion_max_min, or a
--      rolls-processed ratio) instead of a single hardcoded operation
--      and threshold — revisit when a second operation needs a cap.
--
-- Kept as trigger logic (not a CHECK constraint) for both new checks: a
-- trigger is the only enforcement point that catches every write path
-- regardless of origin (finalizar_paso with a caller-supplied historical
-- fyh_fin, the historical-backfill loader, or a future direct UPDATE) —
-- which is exactly how the existing corrupt rows (negative durations,
-- roll overflow) got in to begin with. A CHECK constraint would also fail
-- immediately on ADD CONSTRAINT since known corrupt historical rows
-- already violate fyh_fin >= fyh_inicio.
-- ═══════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_biu_ejecucion_cantidad_rollos ON mes.partida_paso_ejecucion;

CREATE OR REPLACE FUNCTION mes.fn_trg_check_paso_ejecucion_completado()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'mes', 'public'
AS $$
DECLARE
    v_partida_id       BIGINT;
    v_operacion_codigo text;
    v_asignados        NUMERIC;
    v_confirmados       NUMERIC;
BEGIN
    -- Non-negative duration: always enforced, independent of estado/operación.
    IF NEW.fyh_fin IS NOT NULL AND NEW.fyh_fin < NEW.fyh_inicio THEN
        RAISE EXCEPTION
            'La ejecución % tiene fyh_fin (%) anterior a fyh_inicio (%).',
            NEW.partida_paso_id, NEW.fyh_fin, NEW.fyh_inicio
            USING ERRCODE = 'check_violation';
    END IF;

    -- Everything below only applies when the run is being confirmed COMPLETADO.
    IF NEW.estado <> 'COMPLETADO' THEN
        RETURN NEW;
    END IF;

    SELECT pp.partida_id, o.codigo
    INTO v_partida_id, v_operacion_codigo
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    WHERE pp.id = NEW.partida_paso_id;

    -- Roll count can never sum, across a paso's COMPLETADO runs, past the
    -- roll count actually assigned to the partida (mes.partida_componente).
    IF NEW.cantidad_rollos IS NOT NULL THEN
        SELECT COUNT(*) INTO v_asignados
        FROM mes.partida_componente
        WHERE partida_id = v_partida_id AND lote_id IS NOT NULL;

        -- id IS DISTINCT FROM NEW.id excludes this row on UPDATE; on INSERT
        -- (BEFORE trigger, identity not yet assigned) NEW.id is NULL so
        -- nothing is excluded.
        SELECT COALESCE(SUM(cantidad_rollos), 0) INTO v_confirmados
        FROM mes.partida_paso_ejecucion
        WHERE partida_paso_id = NEW.partida_paso_id
          AND estado = 'COMPLETADO'
          AND id IS DISTINCT FROM NEW.id;

        IF v_confirmados + NEW.cantidad_rollos > v_asignados THEN
            RAISE EXCEPTION
                'La cantidad de rollos (%) del paso % excede los % rollos asignados a la partida.',
                NEW.cantidad_rollos, NEW.partida_paso_id, v_asignados
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- COMPACTADO duration cap.
    IF v_operacion_codigo = 'COMPACTADO'
       AND NEW.fyh_fin IS NOT NULL
       AND NEW.fyh_fin - NEW.fyh_inicio > INTERVAL '4 hours'
    THEN
        RAISE EXCEPTION
            'La duración del paso % (% - %) excede el máximo de 4 horas para COMPACTADO.',
            NEW.partida_paso_id, NEW.fyh_inicio, NEW.fyh_fin
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_biu_ejecucion_completado_guard ON mes.partida_paso_ejecucion;
CREATE TRIGGER trg_biu_ejecucion_completado_guard
BEFORE INSERT OR UPDATE OF cantidad_rollos, fyh_inicio, fyh_fin, estado ON mes.partida_paso_ejecucion
FOR EACH ROW EXECUTE FUNCTION mes.fn_trg_check_paso_ejecucion_completado();

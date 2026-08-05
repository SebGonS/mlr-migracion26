-- ═══════════════════════════════════════════════════════════════
-- Step 39: DB-level guard — partida_paso_ejecucion.cantidad_rollos
-- can never sum, across a paso's COMPLETADO runs, past the roll count
-- actually assigned to the partida (mes.partida_componente).
--
-- This rule already exists at the application layer, duplicated in
-- mes.finalizar_paso and the historical-backfill loader
-- (funciones/mes.sql), both raising 'excede los % rollos asignados'.
-- Both call sites can drift or be bypassed (a new RPC, a direct
-- UPDATE, a future backfill script), so this trigger makes the
-- invariant hold regardless of write path. It mirrors the same
-- exclude-self-then-sum-COMPLETADO logic those functions use.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION mes.fn_trg_check_cantidad_rollos_asignados()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'mes', 'public'
AS $$
DECLARE
    v_partida_id  BIGINT;
    v_asignados   NUMERIC;
    v_confirmados NUMERIC;
BEGIN
    -- Only the confirmed (COMPLETADO) quantity counts against the roll pool;
    -- EN_PROCESO runs are in-flight and not yet a committed consumption.
    IF NEW.estado <> 'COMPLETADO' OR NEW.cantidad_rollos IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT partida_id INTO v_partida_id
    FROM mes.partida_paso
    WHERE id = NEW.partida_paso_id;

    SELECT COUNT(*) INTO v_asignados
    FROM mes.partida_componente
    WHERE partida_id = v_partida_id AND lote_id IS NOT NULL;

    -- id IS DISTINCT FROM NEW.id excludes this row on UPDATE; on INSERT (BEFORE
    -- trigger, identity not yet assigned) NEW.id is NULL so nothing is excluded.
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

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_biu_ejecucion_cantidad_rollos ON mes.partida_paso_ejecucion;
CREATE TRIGGER trg_biu_ejecucion_cantidad_rollos
BEFORE INSERT OR UPDATE OF cantidad_rollos, estado ON mes.partida_paso_ejecucion
FOR EACH ROW EXECUTE FUNCTION mes.fn_trg_check_cantidad_rollos_asignados();
3
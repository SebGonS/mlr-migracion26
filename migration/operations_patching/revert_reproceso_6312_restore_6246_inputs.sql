-- ============================================================================
-- REVERT the mistaken fix on partida 6246 / reproceso 6312 — FINAL, matches the
-- actual committed state (verified via truth_6246_6312_now.sql):
--     6246 holds 21 of the incident rolls, 6312 holds 1 (lote 136293),
--     6312 is PROGRAMADA (untouched: no ejecuciones, no movements),
--     1 REPROCESO inspection remains (on 136293).
--
-- Why revert: 6246 never registered production output (0 output lotes, inputs
-- never consumed). The reproceso was branched off INPUT rolls, which is wrong.
-- Target clean state so the frontend can redo it correctly:
--     • all 22 incident rolls (136293..136314) are components of 6246
--     • 6312 soft-deleted (CANCELADA), its partida_detalle removed
--     • no QC inspections on the input rolls
--     • all 22 input rolls estado_calidad = PENDIENTE
--
-- Idempotent-ish: written against the CURRENT split (21/1), but the mutations
-- target the whole incident range so a re-run stays correct.
-- Wrapped in ONE transaction; ends in ROLLBACK. Verify, then flip to COMMIT.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_root_id  BIGINT := 6246;
    v_child_id BIGINT := 6312;
    v_usr_id   INT    := get_user_id();
    v_child_state text;
BEGIN
    -- Guard: 6312 must be unproduced.
    SELECT estado_produccion INTO v_child_state
    FROM mes.partida WHERE id = v_child_id AND fyh_elm IS NULL;
    IF v_child_state IS NULL THEN
        RAISE EXCEPTION 'Aborta: 6312 no existe o ya está anulada (nada que revertir).';
    END IF;
    IF v_child_state NOT IN ('CREADA','PROGRAMADA','PLANIFICADA') THEN
        RAISE EXCEPTION 'Aborta: 6312 estado=% (esperaba sin producción).', v_child_state;
    END IF;
    IF EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
        WHERE pp.partida_id = v_child_id
    ) THEN
        RAISE EXCEPTION 'Aborta: 6312 tiene ejecuciones de paso.';
    END IF;

    -- 1) Sweep any remaining incident roll off 6312 back to 6246.
    UPDATE mes.partida_componente
    SET partida_id = v_root_id, usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE partida_id = v_child_id
      AND lote_id BETWEEN 136293 AND 136314;

    -- 2) Delete ALL QC inspections on the 22 input rolls (wrong target: input QC).
    DELETE FROM calidad.inspeccion WHERE lote_id BETWEEN 136293 AND 136314;

    -- 3) Reset the 22 inputs to PENDIENTE (un-produced inputs; QC belongs on outputs).
    UPDATE inventario.lote
    SET estado_calidad = 'PENDIENTE', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id BETWEEN 136293 AND 136314;

    -- 4) Remove 6312's partida_detalle and soft-delete 6312.
    DELETE FROM mes.partida_detalle WHERE partida_id = v_child_id;
    UPDATE mes.partida
    SET estado_produccion = 'CANCELADA', fyh_elm = NOW(), usr_elm = v_usr_id
    WHERE id = v_child_id;

    -- End-state assertions (evaluated within this same tx).
    IF (SELECT COUNT(*) FROM mes.partida_componente
        WHERE partida_id = v_root_id AND lote_id BETWEEN 136293 AND 136314) <> 22 THEN
        RAISE EXCEPTION 'Aborta: 6246 no quedó con los 22 rollos.';
    END IF;
    IF (SELECT COUNT(*) FROM mes.partida_componente
        WHERE partida_id = v_child_id AND lote_id IS NOT NULL) <> 0 THEN
        RAISE EXCEPTION 'Aborta: 6312 aún tiene rollos.';
    END IF;

    RAISE NOTICE 'OK: 22 rollos en 6246; 6312 anulada; QC de inputs limpiada.';
END $$;

-- ---------------------------------------------------------------------------
-- VERIFY inside the SAME tx (these reflect post-mutation, pre-COMMIT state).
-- ---------------------------------------------------------------------------
SELECT pc.partida_id AS lives_on, COUNT(*) n
FROM mes.partida_componente pc
WHERE pc.lote_id BETWEEN 136293 AND 136314
GROUP BY pc.partida_id;                              -- expect: 6246 -> 22 only

SELECT id, estado_produccion, fyh_elm FROM mes.partida WHERE id IN (6246,6312) ORDER BY id;
                                                     -- 6312 CANCELADA + fyh_elm set
SELECT COUNT(*) inspecciones_en_inputs
FROM calidad.inspeccion WHERE lote_id BETWEEN 136293 AND 136314;   -- expect 0

SELECT estado_calidad, COUNT(*) FROM inventario.lote
WHERE id BETWEEN 136293 AND 136314 GROUP BY estado_calidad;        -- expect PENDIENTE 22

-- Verified on dry-run 2026-07-09: 6246->22, 6312 CANCELADA, 0 inspecciones,
-- 22 PENDIENTE. Committing.
COMMIT;

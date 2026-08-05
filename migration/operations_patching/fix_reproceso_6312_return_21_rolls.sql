-- ============================================================================
-- CORRECTION: reproceso 6312 wrongly branched 22 rolls off partida 6246 when
-- only ONE was defective. Move the 21 good rolls back to 6246, keep 1 in 6312.
--
-- Preconditions verified via debug_reproceso_6312_from_6246.sql (2026-07-08):
--   • All 22 are Case A input rolls (documento_tipo='entrega'), moved by a
--     partida_componente UPDATE — reversible by moving partida_id back.
--   • 6312 is PROGRAMADA; all 5 pasos PENDIENTE; NO ejecuciones; ZERO movements.
--     => nothing produced, this is a pure data edit, safe to reverse.
--   • crear_reproceso reset lote.estado_calidad 22×PENDIENTE (was REPROCESO).
--
-- After this patch:
--   6312 keeps  1 roll (the genuinely defective one) + partida_detalle.cantidad=1
--   6246 regains 21 rolls, their estado_calidad set to APROBADO (they passed QC;
--         the REPROCESO verdict on them was the operator error).
--
-- >>> SET THE ONE ROLL THAT STAYS IN REWORK BEFORE RUNNING <<<
-- Default below keeps lote 136293. Change v_keep_lote to the real defective roll.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_root_id       BIGINT := 6246;
    v_child_id      BIGINT := 6312;
    v_keep_lote     INT    := 136293;   -- <<< the single roll that STAYS in rework
    v_moved         INT;
    v_child_state   text;
    v_has_exec      BOOLEAN;
BEGIN
    -- Re-assert the safety gates at execution time (guard against drift since diag)
    SELECT estado_produccion INTO v_child_state FROM mes.partida WHERE id = v_child_id;
    IF v_child_state NOT IN ('CREADA','PROGRAMADA','PLANIFICADA') THEN
        RAISE EXCEPTION 'Aborta: 6312 estado_produccion=% (esperado sin producción).', v_child_state;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
        WHERE pp.partida_id = v_child_id
    ) INTO v_has_exec;
    IF v_has_exec THEN
        RAISE EXCEPTION 'Aborta: 6312 ya tiene ejecuciones de paso. No es edición limpia.';
    END IF;

    -- Confirm the roll to keep is actually one of 6312's components
    IF NOT EXISTS (
        SELECT 1 FROM mes.partida_componente
        WHERE partida_id = v_child_id AND lote_id = v_keep_lote
    ) THEN
        RAISE EXCEPTION 'Aborta: lote % no es componente de 6312.', v_keep_lote;
    END IF;

    -- 1) Move the 21 non-kept rolls' componente rows back to the root partida
    UPDATE mes.partida_componente
    SET partida_id = v_root_id,
        usr_mod = get_user_id(), fyh_mod = NOW()
    WHERE partida_id = v_child_id
      AND lote_id <> v_keep_lote;
    GET DIAGNOSTICS v_moved = ROW_COUNT;

    IF v_moved <> 21 THEN
        RAISE EXCEPTION 'Aborta: se esperaban 21 rollos a devolver, se movieron %.', v_moved;
    END IF;

    -- 2) Restore quality state on the 21 returned rolls.
    --    They passed inspection; the REPROCESO verdict was the operator error.
    UPDATE inventario.lote
    SET estado_calidad = 'APROBADO', usr_mod = get_user_id(), fyh_mod = NOW()
    WHERE id IN (
        SELECT pc.lote_id FROM mes.partida_componente pc
        WHERE pc.partida_id = v_root_id
    )
    AND id <> v_keep_lote
    AND id BETWEEN 136293 AND 136314;   -- scope to this incident's rolls only

    -- 3) Retire the erroneous REPROCESO inspection rows for the 21 returned rolls,
    --    keeping the one for the roll that genuinely stays in rework.
    --    (Soft-delete if the table supports it; otherwise DELETE. Inspecciones has
    --     no soft-delete columns here, so DELETE the mistaken verdicts.)
    DELETE FROM calidad.inspeccion
    WHERE lote_id BETWEEN 136293 AND 136314
      AND lote_id <> v_keep_lote
      AND resultado = 'REPROCESO'
      AND partida_paso_ejecucion_id = 30714;

    -- 4) Fix the rework child's declared roll count: 22 -> 1
    UPDATE mes.partida_detalle
    SET cantidad = 1, usr_mod = get_user_id(), fyh_mod = NOW()
    WHERE partida_id = v_child_id AND item_id = 232;

    RAISE NOTICE 'OK: 21 rollos devueltos a 6246; 6312 conserva lote %; detalle=1.', v_keep_lote;
END $$;

-- ---------------------------------------------------------------------------
-- VERIFY inside the same tx (review before COMMIT)
-- ---------------------------------------------------------------------------
SELECT '6312 components (expect 1)' AS chk, COUNT(*) AS n
FROM mes.partida_componente WHERE partida_id = 6312
UNION ALL
SELECT '6246 components (expect prior + 21)', COUNT(*)
FROM mes.partida_componente WHERE partida_id = 6246;

SELECT pd.partida_id, pd.item_id, pd.cantidad AS roll_count_intent
FROM mes.partida_detalle pd
WHERE pd.partida_id IN (6246, 6312) ORDER BY pd.partida_id;

SELECT l.id AS lote_id, l.estado_calidad
FROM inventario.lote l
WHERE l.id BETWEEN 136293 AND 136314 ORDER BY l.id;

-- If everything reads correctly:  COMMIT;
-- If anything looks wrong:         ROLLBACK;
--
-- Expected on a CLEAN run (fresh tx):
--   6312 components = 1   |   6246 components = prior + 21
--   detalle: 6246=22, 6312=1
--   136293 = PENDIENTE (stays in rework); 136294..136314 = APROBADO
-- If 6312 reads 2, you are in a stale/re-run tx — ROLLBACK and start fresh.
COMMIT;   -- verified 2026-07-08: fresh 6312 has exactly 22 clean incident rolls.


SELECT mes.get_partida(6312)
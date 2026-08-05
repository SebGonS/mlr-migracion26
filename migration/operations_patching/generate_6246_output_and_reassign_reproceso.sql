-- ============================================================================
-- 6246 REDO: register the production output that was never recorded, then put
-- the reproceso 6312 back with ONE genuinely-defective OUTPUT roll.
--
-- Context (verified via prep_6246_redo.sql, 2026-07-09):
--   • 6246 finished all pasos (TECO) but never registered output: 0 output
--     lotes, 22 input rolls (136293..136314, 21.3091 kg each, item 232) still
--     un-consumed on 6246, all PENDIENTE.
--   • 6312 was soft-deleted by the earlier revert (CANCELADA), but its pasos and
--     its schedule (mes.programacion #17976 -> paso 35987) are INTACT — restoring
--     it is just clearing fyh_elm.
--   • Output paso = COMPACTADO, ejecucion 30781 (COMPLETADO). ubicacion_id = 8.
--
-- This script (ONE transaction):
--   1. Re-open COMPACTADO ejecucion 30781  -> EN_PROCESO (anular_produccion;
--      no outputs exist yet so it only resets state).
--   2. registrar_produccion(30781, 22 rolls @ 21.3091) -> mint 22 OUTPUT lotes,
--      PROD_CONSUMO the 22 inputs, PROD_ING the 22 outputs, cantidad_producida=22.
--   3. QC the OUTPUT rolls: 21 APROBADO, 1 REPROCESO (the arbitrary defective one
--      = the output minted from input 136293; rolls are identical).
--   4. Restore 6312 (uncancel + recreate its partida_detalle) and reassign the 1
--      REPROCESO output roll to it as its component.
--
-- Wrapped in a tx; ends in ROLLBACK. Verify, then flip to COMMIT.
-- ============================================================================

BEGIN;

-- 1) Re-open COMPACTADO so registrar_produccion (requires EN_PROCESO) can run.
SELECT mes.anular_produccion(30781);

-- 2) Generate the 22 output rolls from the 22 inputs (weights carried through).
SELECT mes.registrar_produccion(
    30781,
    jsonb_build_object(
        'ubicacion_id', 8,
        'output', (
            SELECT jsonb_agg(jsonb_build_object(
                        'input_lote_id', pc.lote_id,
                        'peso_salida',   l.cantidad))
            FROM mes.partida_componente pc
            JOIN inventario.lote l ON l.id = pc.lote_id
            WHERE pc.partida_id = 6246
              AND pc.lote_id BETWEEN 136293 AND 136314
        )
    )
);

-- ----------------------------------------------------------------------------
-- 3) + 4): QC the outputs and rebuild the reproceso around the one bad output.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_usr_id       INT := get_user_id();
    v_bad_output   INT;      -- the output lote to send to rework
    v_reproc_ejec  BIGINT;   -- COMPACTADO ejecucion id (for the inspeccion link)
    v_out_count    INT;
BEGIN
    -- All output lotes just minted under ejecucion 30781.
    SELECT COUNT(*) INTO v_out_count
    FROM inventario.lote
    WHERE documento_tipo = 'partida_paso_ejecucion' AND documento_id = 30781
      AND fyh_elm IS NULL;

    IF v_out_count <> 22 THEN
        RAISE EXCEPTION 'Aborta: se esperaban 22 outputs, hay %.', v_out_count;
    END IF;

    -- Pick the defective output = the one whose input genealogy is 136293.
    SELECT l.id INTO v_bad_output
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    WHERE l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id   = 30781
      AND lrd.origen_lote_id = 136293
      AND l.fyh_elm IS NULL;

    IF v_bad_output IS NULL THEN
        RAISE EXCEPTION 'Aborta: no se encontró el output derivado del input 136293.';
    END IF;

    v_reproc_ejec := 30781;

    -- 3a) Approve the 21 good outputs.
    UPDATE inventario.lote
    SET estado_calidad = 'APROBADO', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE documento_tipo = 'partida_paso_ejecucion' AND documento_id = 30781
      AND id <> v_bad_output AND fyh_elm IS NULL;

    -- 3b) Reject the 1 defective output.
    UPDATE inventario.lote
    SET estado_calidad = 'REPROCESO', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = v_bad_output;

    -- 3c) Record the QC inspections (verdict history) on the OUTPUT rolls.
    INSERT INTO calidad.inspeccion (lote_id, partida_paso_ejecucion_id, resultado, observacion)
    SELECT l.id, v_reproc_ejec,
           CASE WHEN l.id = v_bad_output THEN 'REPROCESO'::calidad_estado_enum
                ELSE 'APROBADO'::calidad_estado_enum END,
           CASE WHEN l.id = v_bad_output THEN 'Reproceso: lavar' ELSE NULL END
    FROM inventario.lote l
    WHERE l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = 30781
      AND l.fyh_elm IS NULL;

    -- 4a) Restore 6312 (undo the earlier cancellation). Schedule row is intact.
    UPDATE mes.partida
    SET estado_produccion = 'PROGRAMADA', fyh_elm = NULL, usr_elm = NULL,
        usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = 6312;

    -- 4b) Recreate 6312's partida_detalle (1 roll of item 232).
    INSERT INTO mes.partida_detalle (partida_id, item_id, cantidad, unidad_id, usr_cre)
    SELECT 6312, 232, 1, pd.unidad_id, v_usr_id
    FROM mes.partida_detalle pd
    WHERE pd.partida_id = 6246 AND pd.item_id = 232
    LIMIT 1
    ON CONFLICT (partida_id, item_id) DO UPDATE
        SET cantidad = 1, usr_mod = v_usr_id, fyh_mod = NOW();

    -- 4c) Reassign the defective OUTPUT roll to 6312 as its component.
    --     (It was minted under 6246; give 6312 a component row for the rework.)
    INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada, usr_cre)
    VALUES (6312, v_bad_output, (SELECT cantidad FROM inventario.lote WHERE id = v_bad_output), v_usr_id)
    ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

    RAISE NOTICE 'OK: 22 outputs generados; output % -> REPROCESO en 6312; 21 APROBADO; 6312 restaurada.', v_bad_output;
END $$;

-- ---------------------------------------------------------------------------
-- VERIFY (same tx)
-- ---------------------------------------------------------------------------
SELECT pd.partida_id, pd.item_id, pd.cantidad AS target, pd.cantidad_producida
FROM mes.partida_detalle pd WHERE pd.partida_id IN (6246,6312) ORDER BY pd.partida_id;

SELECT estado_calidad, COUNT(*) AS n_output_rolls
FROM inventario.lote
WHERE documento_tipo='partida_paso_ejecucion' AND documento_id=30781 AND fyh_elm IS NULL
GROUP BY estado_calidad;                         -- expect APROBADO 21, REPROCESO 1

SELECT id, estado_produccion, fyh_elm FROM mes.partida WHERE id IN (6246,6312) ORDER BY id;
                                                 -- 6312 back to PROGRAMADA, fyh_elm NULL

SELECT pc.partida_id, pc.lote_id, l.estado_calidad
FROM mes.partida_componente pc JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6312;                       -- the 1 REPROCESO output roll

-- inputs should now be consumed (PROD_CONSUMO exists) — spot check count
SELECT COUNT(*) AS inputs_consumidos
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE imt.codigo = 'PROD_CONSUMO' AND im.documento_id = 30781
  AND im.lote_id BETWEEN 136293 AND 136314;       -- expect 22

-- Dry-run verified 2026-07-09: 6246 producida=22, outputs 21 APROBADO + 1
-- REPROCESO, 6312 restaurada con output 170045, 22 inputs consumidos. Committing.
-- NOTE: 6246 is now EN_PRODUCCION with COMPACTADO ejecucion 30781 EN_PROCESO —
-- finalize/close that paso through the normal flow afterwards to return 6246 to TECO.
COMMIT;

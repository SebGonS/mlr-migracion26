-- Patch 43: repair cuadre #34 double-reversal artifact
--
-- inventario.anular_cuadre_ejecutado had a scoping bug (fixed in
-- funciones/reversiones.sql): its second INSERT, which reverses AJUSTE_POS
-- (sobrantes), matched on documento_tipo='cuadre' + documento_id=p_cuadre_id
-- only -- so it also picked up the AJUSTE_POS counter-movements the first
-- INSERT (reversing AJUSTE_NEG faltantes) had just committed moments earlier
-- in the same call, since both share the same documento_id tag. The 75
-- restored faltante lotes were immediately re-deducted by a bogus duplicate
-- AJUSTE_NEG batch, net effect: the faltante reversal silently did nothing.
--
-- doc_movimiento_id 14988 (2026-07-07 23:37:04.913844+00), item_movimientos
-- ids 261659-261733, is that erroneous duplicate AJUSTE_NEG block. This
-- patch posts the missing AJUSTE_POS counter-movements to cancel it out,
-- restoring the 75 lotes to the balance the reversal already claimed
-- ("faltantes_revertidos": 75 in logs_api id 39126).
--
-- Verified: rows 261659-261733 exactly mirror rows 261550-261624
-- (same lote_id/item_id/cantidad, same ubicacion 7), confirming they are
-- a duplicate reversal of the legitimate AJUSTE_POS restoration, not a
-- distinct/intentional movement.

DO $$
DECLARE
    v_doc_mov_id      bigint;
    v_tipo_ajuste_pos smallint;
    v_count           int;
BEGIN
    SELECT id INTO v_tipo_ajuste_pos
    FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS';

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, precio_unitario, documento_tipo, documento_id
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id, v_tipo_ajuste_pos,
        im.origen_ubicacion_id,
        im.cantidad,
        im.precio_unitario,
        'cuadre', im.documento_id
    FROM inventario.item_movimientos im
    WHERE im.id BETWEEN 261659 AND 261733
      AND im.doc_movimiento_id = 14988
      AND im.documento_tipo = 'cuadre'
      AND im.documento_id = 34;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count <> 75 THEN
        RAISE EXCEPTION 'Expected to repair 75 rows, got %. Aborting.', v_count;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('patch_43_fix_cuadre34_double_reversal', get_user_id(),
            jsonb_build_object('cuadre_id', 34, 'rows_repaired', v_count,
                                'doc_movimiento_id', v_doc_mov_id,
                                'source_bug_doc_movimiento_id', 14988));
END $$;

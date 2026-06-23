-- ============================================================
-- REVERSE: undo ingreso_rollos_entrega.sql for a specific (entrega, partida)
--
-- Identifies lotes created by that script as:
--   lote.documento_tipo = 'entrega'
--   lote.documento_id   = v_entrega_id
--   AND assigned to v_partida_id via partida_componente
--
-- Deletion order respects FK dependencies:
--   item_movimientos → entrega_detalle → partida_componente
--   → lote_rollo_detalle → lote
--   → entrega header (only if it has no remaining lotes)
--
-- Parameters:
--   v_entrega_id    : doc.entrega.id to reverse
--   v_partida_id : mes.partida.id whose roll assignments to remove
--                  if a entrega spans multiple partidas, run once per partida
--   v_drop_entrega  : true  = also delete the entrega header if it becomes empty
--                  false = leave the header (use when other partidas share it)
-- ============================================================

-- -- DRY RUN ------------------------------------------------
/*
SELECT l.id AS lote_id, l.item_id, l.cantidad, pc.partida_id
FROM inventario.lote l
JOIN mes.partida_componente pc ON pc.lote_id = l.id
WHERE l.documento_tipo = 'entrega'
  AND l.documento_id   = 681          -- <- v_entrega_id
  AND pc.partida_id    = 5190;        -- <- v_partida_id
*/
SELECT * FROm doc.entrega WHERE correlativo='394'
-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_entrega_id    BIGINT := 700;   -- <- CHANGE
    v_partida_id INT    := 5194;   -- <- CHANGE
    v_drop_entrega  BOOLEAN := false; -- <- CHANGE: true only if entrega should be removed entirely

    v_lote_ids        INT[];
    v_movs_deleted    INT;
    v_grd_deleted     INT;
    v_pc_deleted      INT;
    v_lrd_deleted     INT;
    v_lote_deleted    INT;
    v_remaining_lotes INT;
BEGIN
    -- Collect lotes created by ingreso_rollos_entrega for this (entrega, partida)
    SELECT ARRAY_AGG(l.id) INTO v_lote_ids
    FROM inventario.lote l
    JOIN mes.partida_componente pc ON pc.lote_id = l.id
    WHERE l.documento_tipo = 'entrega'
      AND l.documento_id   = v_entrega_id
      AND pc.partida_id    = v_partida_id;

    IF v_lote_ids IS NULL THEN
        RAISE EXCEPTION 'No lotes found for entrega_id=% partida_id=% — nothing to reverse',
            v_entrega_id, v_partida_id;
    END IF;

    RAISE NOTICE 'Reversing % lotes for entrega_id=% partida_id=%',
        cardinality(v_lote_ids), v_entrega_id, v_partida_id;

    -- 1. item_movimientos
    DELETE FROM inventario.item_movimientos
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_movs_deleted = ROW_COUNT;

    -- 2. entrega_detalle
    DELETE FROM doc.entrega_detalle
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_grd_deleted = ROW_COUNT;

    -- 3. partida_componente
    DELETE FROM mes.partida_componente
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_pc_deleted = ROW_COUNT;

    -- 4. lote_rollo_detalle (1:1 with lote, delete before lote)
    DELETE FROM inventario.lote_rollo_detalle
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_lrd_deleted = ROW_COUNT;

    -- 5. lote — soft-delete only (hard delete blocked by trg_bd_prevent_hard_delete)
    UPDATE inventario.lote SET fyh_elm = NOW()
    WHERE id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_lote_deleted = ROW_COUNT;

    RAISE NOTICE '  movimientos: %, grd: %, partida_componente: %, lrd: %, lotes anulados: %',
        v_movs_deleted, v_grd_deleted, v_pc_deleted, v_lrd_deleted, v_lote_deleted;

    -- 6. Optionally soft-delete entrega header if it has no remaining active lotes
    IF v_drop_entrega THEN
        SELECT COUNT(*) INTO v_remaining_lotes
        FROM inventario.lote
        WHERE documento_tipo = 'entrega'
          AND documento_id   = v_entrega_id
          AND fyh_elm IS NULL;

        IF v_remaining_lotes = 0 THEN
            UPDATE doc.entrega SET fyh_elm = NOW() WHERE id = v_entrega_id;
            RAISE NOTICE '  entrega % anulada (no remaining active lotes)', v_entrega_id;
        ELSE
            RAISE NOTICE '  entrega % kept (% active lotes still reference it)',
                v_entrega_id, v_remaining_lotes;
        END IF;
    END IF;

    RAISE NOTICE 'Done.';
END;
$$;
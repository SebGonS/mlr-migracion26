-- ============================================================
-- REVERSE: undo ingreso_rollos_guia.sql for a specific (guia, partida)
--
-- Identifies lotes created by that script as:
--   lote.documento_tipo = 'GUIA_REMISION'
--   lote.documento_id   = v_guia_id
--   AND assigned to v_partida_id via partida_componente
--
-- Deletion order respects FK dependencies:
--   item_movimientos → guia_remision_detalle → partida_componente
--   → lote_rollo_detalle → lote
--   → guia_remision header (only if it has no remaining lotes)
--
-- Parameters:
--   v_guia_id    : doc.guia_remision.id to reverse
--   v_partida_id : mes.partida.id whose roll assignments to remove
--                  if a guia spans multiple partidas, run once per partida
--   v_drop_guia  : true  = also delete the guia header if it becomes empty
--                  false = leave the header (use when other partidas share it)
-- ============================================================

-- -- DRY RUN ------------------------------------------------
/*
SELECT l.id AS lote_id, l.item_id, l.cantidad, pc.partida_id
FROM inventario.lote l
JOIN mes.partida_componente pc ON pc.lote_id = l.id
WHERE l.documento_tipo = 'GUIA_REMISION'
  AND l.documento_id   = 681          -- <- v_guia_id
  AND pc.partida_id    = 5190;        -- <- v_partida_id
*/
SELECT * FROm doc.guia_remision WHERE correlativo='394'
-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_guia_id    BIGINT := 700;   -- <- CHANGE
    v_partida_id INT    := 5194;   -- <- CHANGE
    v_drop_guia  BOOLEAN := false; -- <- CHANGE: true only if guia should be removed entirely

    v_lote_ids        INT[];
    v_movs_deleted    INT;
    v_grd_deleted     INT;
    v_pc_deleted      INT;
    v_lrd_deleted     INT;
    v_lote_deleted    INT;
    v_remaining_lotes INT;
BEGIN
    -- Collect lotes created by ingreso_rollos_guia for this (guia, partida)
    SELECT ARRAY_AGG(l.id) INTO v_lote_ids
    FROM inventario.lote l
    JOIN mes.partida_componente pc ON pc.lote_id = l.id
    WHERE l.documento_tipo = 'GUIA_REMISION'
      AND l.documento_id   = v_guia_id
      AND pc.partida_id    = v_partida_id;

    IF v_lote_ids IS NULL THEN
        RAISE EXCEPTION 'No lotes found for guia_id=% partida_id=% — nothing to reverse',
            v_guia_id, v_partida_id;
    END IF;

    RAISE NOTICE 'Reversing % lotes for guia_id=% partida_id=%',
        cardinality(v_lote_ids), v_guia_id, v_partida_id;

    -- 1. item_movimientos
    DELETE FROM inventario.item_movimientos
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_movs_deleted = ROW_COUNT;

    -- 2. guia_remision_detalle
    DELETE FROM doc.guia_remision_detalle
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

    -- 6. Optionally soft-delete guia header if it has no remaining active lotes
    IF v_drop_guia THEN
        SELECT COUNT(*) INTO v_remaining_lotes
        FROM inventario.lote
        WHERE documento_tipo = 'GUIA_REMISION'
          AND documento_id   = v_guia_id
          AND fyh_elm IS NULL;

        IF v_remaining_lotes = 0 THEN
            UPDATE doc.guia_remision SET fyh_elm = NOW() WHERE id = v_guia_id;
            RAISE NOTICE '  guia_remision % anulada (no remaining active lotes)', v_guia_id;
        ELSE
            RAISE NOTICE '  guia_remision % kept (% active lotes still reference it)',
                v_guia_id, v_remaining_lotes;
        END IF;
    END IF;

    RAISE NOTICE 'Done.';
END;
$$;
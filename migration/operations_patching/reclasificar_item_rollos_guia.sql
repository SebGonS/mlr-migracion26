-- ============================================================
-- RECLASIFICAR: change item_id of UNASSIGNED rolls on a guia
--
-- Use case: rolls were ingressed under the wrong item. Move the
-- ones that have NOT yet been assigned to a partida onto a
-- different (separate) item.
--
-- "Unassigned" = the lote has NO row in mes.partida_componente.
-- Rolls already assigned to a partida are left untouched.
--
-- Because every layer is keyed per-lote, this is a pure UPDATE —
-- no new line item to insert. Changing lote.item_id automatically
-- moves the roll onto the new item's guia_remision_detalle "line"
-- (the unique key is (guia, item, lote, ubicacion); lote_id is
-- unique per roll, so there is no collision).
--
-- Touched layers (all item-bearing rows for the target lotes):
--   inventario.lote                 .item_id
--   inventario.item_movimientos     .item_id
--   doc.guia_remision_detalle       .item_id
--
-- NOT touched:
--   lote.cantidad / movimientos.cantidad / grd.cantidad
--       -> weights are kept as-is. If the wrong item also had the
--          wrong weight (e.g. rib prorated as regular), fix that
--          separately or extend this script.
--   lote_rollo_detalle, partida_componente, partida_detalle
--       -> item-agnostic or only for assigned rolls.
--
-- Parameters:
--   v_guia_id     : doc.guia_remision.id to correct
--   v_old_item_id : item the rolls were WRONGLY ingressed under
--   v_new_item_id : item they should be
-- ============================================================

-- -- DRY RUN ------------------------------------------------
-- Which rolls would be reclassified (unassigned only):
/*
SELECT l.id AS lote_id, l.item_id, l.cantidad,
       (pc.lote_id IS NOT NULL) AS asignada
FROM inventario.lote l
LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
WHERE l.documento_tipo = 'guia_remision'
  AND l.documento_id   = 700          -- <- v_guia_id
  AND l.item_id        = 254          -- <- v_old_item_id
  AND l.fyh_elm IS NULL
ORDER BY asignada, l.id;
-- rows with asignada=false are the ones this script will change
*/

-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_guia_id     BIGINT := 700;   -- <- CHANGE
    v_old_item_id INT    := 254;   -- <- CHANGE  wrong item
    v_new_item_id INT    := 278;   -- <- CHANGE  correct item

    v_lote_ids     INT[];
    v_lote_upd     INT;
    v_mov_upd      INT;
    v_grd_upd      INT;
BEGIN
    IF v_old_item_id = v_new_item_id THEN
        RAISE EXCEPTION 'old and new item are the same (%); nothing to do', v_new_item_id;
    END IF;

    -- Target = rolls on this guia, under the wrong item, NOT assigned to any partida
    SELECT ARRAY_AGG(l.id) INTO v_lote_ids
    FROM inventario.lote l
    WHERE l.documento_tipo = 'guia_remision'
      AND l.documento_id   = v_guia_id
      AND l.item_id        = v_old_item_id
      AND l.fyh_elm IS NULL
      AND NOT EXISTS (
            SELECT 1 FROM mes.partida_componente pc
            WHERE pc.lote_id = l.id
      );

    IF v_lote_ids IS NULL THEN
        RAISE EXCEPTION 'No unassigned lotes found for guia_id=% item_id=% — nothing to reclassify',
            v_guia_id, v_old_item_id;
    END IF;

    RAISE NOTICE 'Reclassifying % unassigned rolls on guia_id=% from item % -> %',
        cardinality(v_lote_ids), v_guia_id, v_old_item_id, v_new_item_id;

    -- 1. Lote
    UPDATE inventario.lote
    SET item_id = v_new_item_id, fyh_mod = NOW()
    WHERE id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_lote_upd = ROW_COUNT;

    -- 2. Ledger movements (all movements for these lotes still on the old item)
    UPDATE inventario.item_movimientos
    SET item_id = v_new_item_id
    WHERE lote_id = ANY(v_lote_ids)
      AND item_id = v_old_item_id;
    GET DIAGNOSTICS v_mov_upd = ROW_COUNT;

    -- 3. Guia detail line (per-roll row -> just retag the item)
    UPDATE doc.guia_remision_detalle
    SET item_id = v_new_item_id
    WHERE lote_id = ANY(v_lote_ids)
      AND item_id = v_old_item_id;
    GET DIAGNOSTICS v_grd_upd = ROW_COUNT;

    RAISE NOTICE '  lote: %, movimientos: %, guia_remision_detalle: %',
        v_lote_upd, v_mov_upd, v_grd_upd;
    RAISE NOTICE 'Done. lotes=%', v_lote_ids;
END;
$$;

-- -- VERIFY -------------------------------------------------
/*
SELECT l.id AS lote_id, l.item_id, i.nombre, l.cantidad,
       grd.item_id AS grd_item, m.item_id AS mov_item
FROM inventario.lote l
JOIN item i                          ON i.id = l.item_id
LEFT JOIN doc.guia_remision_detalle grd ON grd.lote_id = l.id
LEFT JOIN inventario.item_movimientos m ON m.lote_id  = l.id
WHERE l.documento_tipo = 'guia_remision'
  AND l.documento_id   = 700          -- <- v_guia_id
ORDER BY l.item_id, l.id;
*/

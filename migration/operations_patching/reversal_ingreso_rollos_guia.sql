-- ============================================================
-- Reversal of the most recent roll ingress batch for a partida
--
-- Identifies the newest entrega linked to this partida's lotes,
-- then flushes only those lotes in cascade order:
--   item_movimientos → partida_componente → entrega_detalle
--   → lote_rollo_detalle → lote → entrega (if fully owned)
--
-- Guards abort the whole block if any lote in the target batch
-- has downstream work (pesaje, orden_produccion_item, child lotes).
--
-- Parameters (edit before running):
--   v_partida_id : mes.partida.id whose latest ingress to undo
-- ============================================================

-- -- DRY RUN ------------------------------------------------
/*
SELECT gr.id AS entrega_id, gr.serie, gr.correlativo,
       MAX(pc.fyh_cre) AS ultimo_componente_cre,
       COUNT(pc.lote_id) AS n_rollos
FROM mes.partida_componente        pc
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id          = pc.lote_id
JOIN doc.entrega             gr  ON gr.id                = lrd.entrega_id
WHERE pc.partida_id = 0   -- <- v_partida_id
GROUP BY 1,2,3
ORDER BY MAX(pc.fyh_cre) DESC;  -- top row = what the reversal will target
*/

-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_partida_id  INT    := 5223;  -- <- CHANGE

    v_entrega_id     BIGINT;
    v_lote_ids    INT[];
    v_count       INT;
BEGIN
    -- 1. entrega linked to the most recently assigned partida_componente row
    SELECT gr.id
    INTO v_entrega_id
    FROM mes.partida_componente        pc
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id        = pc.lote_id
    JOIN doc.entrega             gr  ON gr.id              = lrd.entrega_id
    WHERE pc.partida_id = v_partida_id
      AND pc.lote_id IS NOT NULL
    ORDER BY pc.fyh_cre DESC
    LIMIT 1;

    IF v_entrega_id IS NULL THEN
        RAISE EXCEPTION 'No entrega found for partida_id=%. Nothing to reverse.', v_partida_id;
    END IF;

    RAISE NOTICE 'partida_id=% — targeting newest entrega_id=%', v_partida_id, v_entrega_id;

    -- 2. Lotes for this partida that belong to the selected entrega
    SELECT ARRAY_AGG(pc.lote_id)
    INTO v_lote_ids
    FROM mes.partida_componente        pc
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id        = pc.lote_id
    WHERE pc.partida_id        = v_partida_id
      AND lrd.entrega_id = v_entrega_id;

    RAISE NOTICE '% lote(s) in batch: %', array_length(v_lote_ids, 1), v_lote_ids;

    -- ---- Safety guards -------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM inventario.pesaje
    WHERE lote_id = ANY(v_lote_ids);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Cannot reverse: % pesaje record(s) exist. Undo weighing first.', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.lote_id = ANY(v_lote_ids)
      AND imt.codigo = 'PROD_CONSUMO';
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Cannot reverse: % PROD_CONSUMO movement(s) exist — lotes already consumed in production.', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM inventario.lote
    WHERE documento_tipo = 'LOTE'
      AND documento_id   = ANY(v_lote_ids);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Cannot reverse: % child lote(s) derived from these lotes.', v_count;
    END IF;

    -- ---- Cascade delete ------------------------------------

    -- Disable user triggers for this transaction (allows hard-delete on lote)
    SET LOCAL session_replication_role = replica;

    -- a. Stock ingress movements
    DELETE FROM inventario.item_movimientos
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % item_movimientos row(s)', v_count;

    -- b. Partida component assignments
    DELETE FROM mes.partida_componente
    WHERE partida_id = v_partida_id
      AND lote_id    = ANY(v_lote_ids);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % partida_componente row(s)', v_count;

    -- c. entrega detail lines for these lotes
    DELETE FROM doc.entrega_detalle
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % entrega_detalle row(s)', v_count;

    -- d. Billing anchors
    DELETE FROM inventario.lote_rollo_detalle
    WHERE lote_id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % lote_rollo_detalle row(s)', v_count;

    -- e. Lotes
    DELETE FROM inventario.lote
    WHERE id = ANY(v_lote_ids);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % lote row(s)', v_count;

    -- f. entrega header — only if no detail rows remain
    --    (safe when entrega spans multiple partidas)
    DELETE FROM doc.entrega
    WHERE id = v_entrega_id
      AND NOT EXISTS (
          SELECT 1 FROM doc.entrega_detalle
          WHERE entrega_id = v_entrega_id
      );
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % entrega header(s)', v_count;

    RAISE NOTICE 'Reversal complete — partida_id=%, entrega_id=%', v_partida_id, v_entrega_id;
END;
$$;

-- -- VERIFY -------------------------------------------------
/*
SELECT COUNT(*) FROM mes.partida_componente
WHERE partida_id = 0;  -- <- expect only demand rows (lote_id IS NULL)

SELECT COUNT(*) FROM doc.entrega WHERE id = 0;  -- <- entrega_id, expect 0
*/

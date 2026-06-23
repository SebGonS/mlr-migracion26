-- ============================================================
-- Partial dispatch reversal -- remove N rolls from an egress
-- entrega without cancelling the whole document.
--
-- Use case: dispatch registered for X rolls but only (X-N) were
-- physically sent. Picks the last N lote IDs (by id DESC) from
-- the partida's egress entrega -- arbitrary but deterministic.
--
-- Movement reversal mapping:
--   DESPACHO_CLIENTE -> SERV_EGR  -> SERV_DEV_ING
--   VENTA_EGRESO     -> VENTA_EGR -> DEV_CLI_ING
-- ============================================================

-- ── DRY RUN -- what SERV_EGR/VENTA_EGR movements actually exist for these lotes?
-- What lotes exist for partida 4588 and what movements do they have?
SELECT
    l.id          AS lote_id,
    l.documento_tipo,
    imt.codigo    AS mov_tipo,
    im.documento_tipo AS mov_doc_tipo,
    im.documento_id   AS mov_doc_id
FROM inventario.lote                 l
JOIN inventario.item_movimientos     im  ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                       AND imt.codigo IN ('SERV_EGR', 'VENTA_EGR')
WHERE l.documento_id = 4588
ORDER BY l.id;
-- All lotes associated with partida 4588 and ALL their movements
SELECT
    l.id              AS lote_id,
    l.documento_tipo  AS lote_doc_tipo,
    l.documento_id    AS lote_doc_id,
    imt.codigo        AS mov_tipo,
    im.documento_tipo AS mov_doc_tipo,
    im.documento_id   AS mov_doc_id,
    im.fecha_hora
FROM inventario.lote                 l
JOIN inventario.item_movimientos     im  ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE l.documento_tipo = 'PARTIDA'
  AND l.documento_id   = 4588
ORDER BY l.id, im.fecha_hora;


UPDATE mes.partida
SET estado_produccion = 'TECO',
    usr_mod = 1,
    fyh_mod = NOW()
WHERE id = 4588
  AND estado_produccion = 'CERRADA';


select column_name from information_schema.columns
where table_schema = 'inventario' and table_name = 'vw_lotes_rollos_stock'
order by 1;

-- ── DRY RUN 2 -- if there is a entrega, check its status
/*
SELECT
    gr.id, gr.serie, gr.correlativo, gr.fyh_elm AS anulada,
    grt.codigo AS entrega_tipo,
    COUNT(grd.id) AS n_lineas
FROM inventario.lote                 l
JOIN inventario.item_movimientos     im  ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                       AND imt.codigo IN ('SERV_EGR', 'VENTA_EGR')
JOIN doc.entrega               gr  ON gr.id = im.documento_id   -- no fyh_elm filter
JOIN doc.entrega_tipo          grt ON grt.id = gr.entrega_tipo_id
LEFT JOIN doc.entrega_detalle  grd ON grd.entrega_id = gr.id AND grd.fyh_elm IS NULL
WHERE l.documento_tipo = 'PARTIDA'
  AND l.documento_id   = 4595
GROUP BY gr.id, gr.serie, gr.correlativo, gr.fyh_elm, grt.codigo;
*/

-- ── EXECUTE ───────────────────────────────────────────────────────────────
-- NOTE: SERV_EGR movements for these partidas were posted directly with
-- documento_tipo='PARTIDA' (not via a entrega). Reversal mirrors that.
DO $$
DECLARE
    v_partida_id  BIGINT := 4588;   -- <- partida
    v_n_rollos    INT    := 2;      -- <- how many to revert

    v_lote_ids          BIGINT[];
    v_reversal_tipo_id  INT;
    v_doc_mov_id        BIGINT;
    v_count             INT;
BEGIN
    -- Pick last N lotes by id that have a SERV_EGR posted against the partida
    SELECT ARRAY_AGG(sub.lote_id) INTO v_lote_ids
    FROM (
        SELECT l.id AS lote_id
        FROM inventario.lote                 l
        JOIN inventario.item_movimientos     im  ON im.lote_id = l.id
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                               AND imt.codigo IN ('SERV_EGR', 'VENTA_EGR')
        WHERE l.documento_tipo  = 'PARTIDA'
          AND l.documento_id    = v_partida_id
          AND im.documento_tipo = 'PARTIDA'
          AND im.documento_id   = v_partida_id
        ORDER BY l.id DESC
        LIMIT v_n_rollos
    ) sub;

    IF v_lote_ids IS NULL THEN
        RAISE EXCEPTION 'No SERV_EGR movements found for partida %.', v_partida_id;
    END IF;

    RAISE NOTICE 'partida=% -- will revert lotes: %', v_partida_id, v_lote_ids;

    -- Guard: no unexpected downstream movements on these lotes
    SELECT COUNT(*) INTO v_count
    FROM inventario.item_movimientos     im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.lote_id = ANY(v_lote_ids)
      AND imt.codigo NOT IN ('PROD_ING', 'SERV_ING', 'SERV_EGR', 'VENTA_EGR');
    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Lotes % have % unexpected downstream movement(s). Inspect before reversing.',
            v_lote_ids, v_count;
    END IF;

    -- Resolve SERV_DEV_ING tipo id
    SELECT id INTO v_reversal_tipo_id
    FROM inventario.item_movimiento_tipo
    WHERE codigo = 'SERV_DEV_ING';

    IF v_reversal_tipo_id IS NULL THEN
        RAISE EXCEPTION 'Movement tipo SERV_DEV_ING not found.';
    END IF;

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- Post counter-movements mirroring the original (same doc ref: PARTIDA/partida_id)
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id, item_id, lote_id,
        item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora,
        documento_tipo, documento_id,
        observacion
    )
    SELECT
        v_doc_mov_id, im.item_id, im.lote_id,
        v_reversal_tipo_id,
        im.destino_ubicacion_id, im.origen_ubicacion_id,
        im.cantidad, NOW(),
        'PARTIDA', v_partida_id,
        format('REVERSAL PARCIAL %s rollos -- ghost SERV_EGR, partida %s',
               v_n_rollos, v_partida_id)
    FROM inventario.item_movimientos     im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.lote_id       = ANY(v_lote_ids)
      AND im.documento_tipo = 'PARTIDA'
      AND im.documento_id   = v_partida_id
      AND imt.codigo        IN ('SERV_EGR', 'VENTA_EGR');

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Posted % counter-movement(s)', v_count;

    IF v_count <> v_n_rollos THEN
        RAISE EXCEPTION 'Expected % movements, got %. Aborting.', v_n_rollos, v_count;
    END IF;

    RAISE NOTICE 'Done -- % roll(s) back in stock. partida=%', v_n_rollos, v_partida_id;

    ROLLBACK;
    -- COMMIT;
END;
$$;


-- ── VERIFY ────────────────────────────────────────────────────────────────
/*
SELECT l.id, l.codigo, imt.codigo AS mov, im.fecha_hora
FROM inventario.lote                 l
JOIN inventario.item_movimientos     im  ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE l.documento_tipo = 'PARTIDA'
  AND l.documento_id   = 4595   -- <- partida_id
ORDER BY l.id, im.fecha_hora;
*/

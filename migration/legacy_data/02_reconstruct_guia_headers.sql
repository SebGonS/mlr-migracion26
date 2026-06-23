-- ============================================================
-- Fix: link legacy PARTIDA-migrated rolls to their real entrega
--
-- Context: rolls that physically arrived via entrega were
-- pragmatically imported as documento_tipo='PARTIDA' during data
-- migration (insufficient legacy data to reconstruct entrega header+detail).
-- These lotes are still in-flight and need entrega linkage for display
-- and grouping (pesaje view, billing anchor, etc.).
--
-- What this script does:
--   1. INSERT doc.entrega        (header -- the real document)
--   2. UPDATE lote_rollo_detalle       (billing anchor per roll)
--   3. INSERT doc.entrega_detalle (optional -- only if compra
--      reconciliation on this entrega is still open/needed)
--
-- What this script does NOT do:
--   * Does NOT change lote.documento_tipo / documento_id
--   * Does NOT change item_movimientos.documento_tipo / documento_id
--   These remain 'PARTIDA' -- the AJUSTE_POS movements that created
--   them are factually accurate and should not be retropatched.
--   (contrast: fix_lote_documento_linkage.sql is for rolls that had
--    a real entrega ingress movement but were miscoded as PARTIDA)
--
-- Parameters (edit before running):
--   v_tipo_codigo   : entrega_tipo.codigo
--                       'COMPRA_INGRESO'        purchased rolls from supplier
--                       'CLIENTE_ENVIO_PROCESO' client-owned fabric sent to MLR
--   v_tercero_id    : tercero.id of the supplier or client
--   v_serie         : serie from the physical entrega document
--   v_correlativo   : correlativo from the physical entrega document
--   v_fecha_emision : date printed on the physical entrega
--   v_partida_ids   : partida.id(s) -- selects ALL rolls in those partidas
--                     use when every roll in the partida belongs to this entrega
--   v_lote_ids      : explicit lote.id list -- overrides v_partida_ids when non-empty
--                     use when a single partida has rolls from multiple entregas:
--                     run the block once per entrega supplying only its rolls
--   v_crear_detalle : true  = also insert entrega_detalle rows
--                     false = skip (use when compra is already settled)
-- ============================================================

-- -- DRY RUN ------------------------------------------------
-- Run before the DO block to confirm scope and note lote_ids.
-- -----------------------------------------------------------
/*
SELECT
    pc.partida_id,
    l.id            AS lote_id,
    l.item_id,
    i.codigo        AS item_codigo,
    ird.flg_rib,
    l.cantidad,
    lrd.entrega_id  AS current_entrega_id   -- expect NULL for unlinked legacy rolls
FROM mes.partida_componente              pc
JOIN inventario.lote                     l   ON l.id = pc.lote_id AND l.fyh_elm IS NULL
JOIN item                                i   ON i.id = l.item_id
JOIN item_rollo_detalle                  ird ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle  lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = ANY(ARRAY[5229])          -- <- v_partida_ids
  AND pc.lote_id IS NOT NULL
ORDER BY ird.flg_rib, l.id;
*/
SELECT * FROM mes.partida_componente WHERE partida_id=5187
-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_tipo_codigo   TEXT        := 'CLIENTE_ENVIO_PROCESO';  -- <- CHANGE
    v_tercero_id    INT         := NULL;                      -- <- CHANGE  tercero.id
    v_serie         TEXT        := NULL;                      -- <- CHANGE  e.g. 'T001'
    v_correlativo   TEXT        := NULL;                      -- <- CHANGE  e.g. '00123'
    v_fecha_emision TIMESTAMPTZ := NULL;                      -- <- CHANGE  e.g. '2024-03-15'
    v_partida_ids   INT[]       := ARRAY[5187];               -- <- CHANGE
    v_lote_ids      INT[]       := ARRAY[]::INT[];            -- <- CHANGE or leave empty to use v_partida_ids
    v_crear_detalle BOOLEAN     := false;                     -- <- CHANGE

    v_entrega_id       BIGINT;
    v_tipo_id       SMALLINT;
    v_lrd_updated   INT;
    v_grd_inserted  INT := 0;
BEGIN
    -- Resolve tipo id once
    SELECT id INTO STRICT v_tipo_id
    FROM doc.entrega_tipo
    WHERE codigo = v_tipo_codigo;

    -- 1. Create entrega header
    INSERT INTO doc.entrega (
        entrega_tipo_id,
        tercero_id,
        serie,
        correlativo,
        fecha_emision
    )
    VALUES (
        v_tipo_id,
        v_tercero_id,
        v_serie,
        v_correlativo,
        v_fecha_emision
    )
    RETURNING id INTO v_entrega_id;

    RAISE NOTICE 'Created entrega id=% (% % tipo=%)',
        v_entrega_id, v_serie, v_correlativo, v_tipo_codigo;

    -- 2. Set billing anchor.
    --    v_lote_ids non-empty -> explicit list (split-entrega case within one partida).
    --    v_lote_ids empty     -> all rolls across v_partida_ids.
    IF cardinality(v_lote_ids) > 0 THEN

        UPDATE inventario.lote_rollo_detalle
        SET    entrega_id = v_entrega_id
        WHERE  lote_id = ANY(v_lote_ids);

    ELSE

        UPDATE inventario.lote_rollo_detalle lrd
        SET    entrega_id = v_entrega_id
        FROM   mes.partida_componente pc
        JOIN   inventario.lote l ON l.id = pc.lote_id AND l.fyh_elm IS NULL
        WHERE  lrd.lote_id   = pc.lote_id
          AND  pc.partida_id = ANY(v_partida_ids)
          AND  pc.lote_id IS NOT NULL;

    END IF;

    GET DIAGNOSTICS v_lrd_updated = ROW_COUNT;
    RAISE NOTICE '  lote_rollo_detalle rows updated: %', v_lrd_updated;

    -- 3. (Optional) entrega_detalle
    --    Only needed when the corresponding compra still requires receipt
    --    reconciliation. Skip for fully settled legacy compras.
    IF v_crear_detalle THEN

        IF cardinality(v_lote_ids) > 0 THEN
            INSERT INTO doc.entrega_detalle (
                entrega_id, item_id, lote_id, cantidad
            )
            SELECT v_entrega_id, l.item_id, l.id, l.cantidad
            FROM   inventario.lote l
            WHERE  l.id = ANY(v_lote_ids)
              AND  l.fyh_elm IS NULL;
        ELSE
            INSERT INTO doc.entrega_detalle (
                entrega_id, item_id, lote_id, cantidad
            )
            SELECT v_entrega_id, l.item_id, l.id, l.cantidad
            FROM   mes.partida_componente pc
            JOIN   inventario.lote l ON l.id = pc.lote_id AND l.fyh_elm IS NULL
            WHERE  pc.partida_id = ANY(v_partida_ids)
              AND  pc.lote_id IS NOT NULL;
        END IF;

        GET DIAGNOSTICS v_grd_inserted = ROW_COUNT;
        RAISE NOTICE '  entrega_detalle rows inserted: %', v_grd_inserted;
    END IF;

    RAISE NOTICE 'Done. entrega_id=%, lrd_updated=%, grd_inserted=%',
        v_entrega_id, v_lrd_updated, v_grd_inserted;
END;
$$;

-- -- VERIFY -------------------------------------------------
/*
-- Header created:
SELECT gr.id, gr.serie, gr.correlativo, gr.fecha_emision,
       grt.codigo AS tipo, t.nombre AS tercero
FROM   doc.entrega gr
JOIN   doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
JOIN   tercero t ON t.id = gr.tercero_id
WHERE  gr.serie = 'XXX' AND gr.correlativo = 'YYYY';   -- <- fill

-- Billing anchor set:
SELECT pc.partida_id, l.id AS lote_id, l.item_id,
       ird.flg_rib, l.cantidad, lrd.entrega_id
FROM   mes.partida_componente              pc
JOIN   inventario.lote                     l   ON l.id = pc.lote_id
JOIN   item_rollo_detalle                  ird ON ird.item_id = l.item_id
JOIN   inventario.lote_rollo_detalle       lrd ON lrd.lote_id = l.id
WHERE  pc.partida_id = ANY(ARRAY[5229])         -- <- v_partida_ids
  AND  pc.lote_id IS NOT NULL
ORDER BY ird.flg_rib, l.id;

-- Detail rows (if v_crear_detalle = true):
SELECT grd.id, grd.item_id, grd.lote_id, grd.cantidad
FROM   doc.entrega_detalle grd
WHERE  grd.entrega_id = <id_from_above>;
*/
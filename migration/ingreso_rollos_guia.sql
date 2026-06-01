-- ============================================================
-- Ingresar rollos via guia_remision y asignar a partida
--
-- Use case: rolls arriving from a supplier (COMPRA_INGRESO) or
-- from a client sending fabric for processing (CLIENTE_ENVIO_PROCESO).
-- Creates the guia header, one lote per roll, lote_rollo_detalle
-- (billing anchor), partida_componente assignment, and the
-- appropriate ingress movement derived from guia_remision_tipo.
--
-- Assumes the partida has no pre-existing roll components for
-- the items being ingressed (no ON CONFLICT guard needed, but
-- the partida_componente insert includes one for safety).
--
-- Parameters (edit before running):
--   v_tipo_codigo   : 'COMPRA_INGRESO' or 'CLIENTE_ENVIO_PROCESO'
--   v_tercero_id    : NULL for CLIENTE_ENVIO_PROCESO (derived from partida.tercero_id)
--                     set explicitly for COMPRA_INGRESO (supplier, not on the partida)
--   v_serie         : serie from the physical guia
--   v_correlativo   : correlativo from the physical guia
--   v_fecha_emision : date on the physical guia
--   v_partida_id    : partida.id these rolls are assigned to
--   v_peso_kg_por_rollo : nominal kg weight per roll
--   v_rollos        : array of (item_id, n_rollos) pairs
--                     one entry per item type (rollo + rib if both present)
-- ============================================================

-- -- DRY RUN ------------------------------------------------
-- Verify partida exists and has no existing roll components:
/*
SELECT id, estado_produccion FROM mes.partida WHERE id = 5229;   -- <- v_partida_id

SELECT COUNT(*) FROM mes.partida_componente
WHERE partida_id = 5229 AND lote_id IS NOT NULL;                 -- expect 0
*/
-- ---5252 guia 2186
-- SELECT i.id,i.nombre,pd.cantidad,COUNT(*) FROM mes.partida_detalle pd
-- JOIN item i ON i.id = pd.item_id 
-- LEFT JOIN mes.partida_componente pc ON pc.partida_id = pd.partida_id
-- JOIN inventario.lote ON pc.lote_id = lote.id AND lote.item_id = i.id 
-- WHERE pd.partida_id=5252
-- GROUP BY 1,2,3
-- ;
-- SELECT * FROM mes.partida_detalle WHERE partida_id=5252
-- SELECT i.id,i.nombre,pd.cantidad,COUNT(*) FROM mes.partida_detalle pd
-- JOIN item i ON i.id = pd.item_id 
-- LEFT JOIN mes.partida_detalle pc ON pc.partida_id = pd.partida_id
-- WHERE pd.partida_id=5252
-- GROUP BY 1,2,3
;
SELECT * FROM mes.partida WHERE id=5253
SELECT * FROM partida WHERE id=5253
-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_tipo_codigo       TEXT        := 'CLIENTE_ENVIO_PROCESO';  -- <- CHANGE
    v_tercero_id        INT         := 214;                      -- <- leave NULL for CLIENTE_ENVIO_PROCESO; set for COMPRA_INGRESO (supplier)
    v_serie             TEXT        := '00';                      -- <- CHANGE
    v_correlativo       TEXT        := '2186';                      -- <- CHANGE
    v_fecha_emision     TIMESTAMPTZ := '2026-05-22 00:00:00-5';                      -- <- CHANGE
    v_partida_id        INT         := 5253;                      -- <- CHANGE
    v_peso_kg_por_rollo NUMERIC     := 20.0;                      -- <- CHANGE  nominal kg/roll

    -- List every (item_id, n_rollos) pair for this guia.
    -- Example: ARRAY[(101, 18), (102, 4)]  where 102 is the rib item.
    v_rollos            INT[][]     := ARRAY[
                                            
                                           ARRAY[254::INT, 19::INT]  ,ARRAY[278::INT, 1::INT]--, --<- CHANGE  [item_id, n_rollos]
                                       ];

    v_guia_id           BIGINT;
    v_tipo_id           SMALLINT;
    v_mov_tipo_id       SMALLINT;
    v_propietario_id    INT;
    v_doc_mov_id        BIGINT;
    v_ubicacion_id      INT;
    v_lote_id           INT;
    v_item_id           INT;
    v_n_rollos          INT;
    i                   INT;
    pair                INT[];
BEGIN
    -- Resolve guia tipo and its movement type in one shot
    SELECT grt.id, grt.item_movimiento_tipo_id
    INTO STRICT v_tipo_id, v_mov_tipo_id
    FROM doc.guia_remision_tipo grt
    WHERE grt.codigo = v_tipo_codigo;

    -- Derive tercero + propietario from partida when not supplied explicitly.
    -- CLIENTE_ENVIO_PROCESO: partida.tercero_id = the client whose fabric this is.
    -- COMPRA_INGRESO: MLR bought the rolls; v_tercero_id must be set to the supplier above.
    IF v_tercero_id IS NULL THEN
        SELECT tercero_id INTO STRICT v_tercero_id
        FROM mes.partida
        WHERE id = v_partida_id;
    END IF;

    -- client-owned fabric -> propietario = tercero; MLR-purchased -> NULL
    v_propietario_id := CASE v_tipo_codigo
        WHEN 'CLIENTE_ENVIO_PROCESO' THEN v_tercero_id
        ELSE NULL
    END;

    -- Destination warehouse: ALM_CRU (adjust if rolls land elsewhere)
    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1;

    -- 1. Create guia header (idempotent: skip insert if already exists)
    INSERT INTO doc.guia_remision (
        guia_remision_tipo_id, tercero_id, serie, correlativo, fecha_emision
    )
    VALUES (v_tipo_id, v_tercero_id, v_serie, v_correlativo, v_fecha_emision)
    ON CONFLICT (tercero_id, serie, correlativo, guia_remision_tipo_id) DO NOTHING
    RETURNING id INTO v_guia_id;

    IF v_guia_id IS NULL THEN
        SELECT id INTO STRICT v_guia_id
        FROM doc.guia_remision
        WHERE tercero_id             = v_tercero_id
          AND serie                  = v_serie
          AND correlativo            = v_correlativo
          AND guia_remision_tipo_id  = v_tipo_id;
        RAISE NOTICE 'Reusing existing guia_remision id=% (%-% tipo=%)',
            v_guia_id, v_serie, v_correlativo, v_tipo_codigo;
    ELSE
    RAISE NOTICE 'Created guia_remision id=% (%-% tipo=%)',
        v_guia_id, v_serie, v_correlativo, v_tipo_codigo;
    END IF;

    -- 2. One doc_movimiento_id groups all roll movements for this guia
    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    -- 3. Per item, per roll
    FOREACH pair SLICE 1 IN ARRAY v_rollos LOOP
        v_item_id  := pair[1];
        v_n_rollos := pair[2];

        FOR i IN 1 .. v_n_rollos LOOP

            -- a. Lote — tagged to the guia (correct origin, not PARTIDA)
            INSERT INTO inventario.lote (
                item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre
            )
            VALUES (
                v_item_id,
                'GUIA_REMISION',
                v_guia_id,
                v_peso_kg_por_rollo,
                v_propietario_id,
                NULL
            )
            RETURNING id INTO v_lote_id;

            -- b. Billing anchor
            INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id)
            VALUES (v_lote_id, v_guia_id);

            -- c. Assign to partida
            INSERT INTO mes.partida_componente (
                partida_id, lote_id, item_id, partida_paso_id,
                cantidad_reservada, usr_cre
            )
            VALUES (
                v_partida_id, v_lote_id, NULL, NULL,
                v_peso_kg_por_rollo, NULL
            )
            ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

            -- d. Ingress movement (COMPRA_ING or SERV_ING per tipo)
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id,
                item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id,
                cantidad, documento_tipo, documento_id,
                observacion, usr_cre
            )
            VALUES (
                v_doc_mov_id,
                v_item_id,
                v_lote_id,
                v_mov_tipo_id,
                NULL,             -- external origin, no internal source bin
                v_ubicacion_id,
                v_peso_kg_por_rollo,
                'GUIA_REMISION',
                v_guia_id,
                'Ingreso via guia ' || v_serie || '-' || v_correlativo
                    || ' para partida ' || v_partida_id,
                NULL
            );

            -- e. One detail row per roll; cantidad = weight of this lote (mirrors crear_guia)
            INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
            VALUES (v_guia_id, v_item_id, v_lote_id, v_peso_kg_por_rollo)
            ON CONFLICT (guia_remision_id, item_id, lote_id, ubicacion_id) DO NOTHING;

        END LOOP;

    END LOOP;

    RAISE NOTICE 'Done. guia_id=%, partida_id=%, doc_mov_id=%',
        v_guia_id, v_partida_id, v_doc_mov_id;
END;
$$;

-- -- VERIFY -------------------------------------------------
/*
-- Rolls created and linked:
SELECT
    l.id          AS lote_id,
    l.item_id,
    ird.flg_rib,
    l.cantidad,
    lrd.guia_remision_id,
    pc.partida_id
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle  lrd ON lrd.lote_id = l.id
JOIN item_rollo_detalle             ird ON ird.item_id = l.item_id
JOIN mes.partida_componente         pc  ON pc.lote_id  = l.id
WHERE l.documento_tipo = 'GUIA_REMISION'
  AND l.documento_id   = <guia_id_from_above>
ORDER BY ird.flg_rib, l.id;

-- Movements posted:
SELECT m.item_id, m.lote_id, imt.codigo AS mov_tipo, m.cantidad
FROM inventario.item_movimientos m
JOIN inventario.item_movimiento_tipo imt ON imt.id = m.item_movimiento_tipo_id
WHERE m.documento_tipo = 'GUIA_REMISION'
  AND m.documento_id   = <guia_id_from_above>;

-- guia_remision_detalle:
SELECT item_id, cantidad FROM doc.guia_remision_detalle
WHERE guia_remision_id = <guia_id_from_above>;
*/


----ROLLOS LA REAL
DO $$
DECLARE
    v_peso_kg_por_rollo  NUMERIC := 20.0;   -- ← change nominal kg/roll here

    v_doc_mov_id         BIGINT;
    v_lote_id            INT;
    v_ajuste_pos_id      SMALLINT;
    rec                  RECORD;
    i                    INT;
BEGIN
    -- Resolve AJUSTE_POS type id once
    SELECT id INTO STRICT v_ajuste_pos_id
    FROM inventario.item_movimiento_tipo
    WHERE codigo = 'AJUSTE_POS';

    -- One doc_movimiento_id per partida (groups all roll inserts per partida)
    -- We'll generate two: one for 5237, one for 5238.

    FOR rec IN
        SELECT
            pd.partida_id,
            pd.item_id,
            pd.cantidad::INT AS n_rollos   -- cantidad = roll count in partida_detalle
        FROM mes.partida_detalle pd
        WHERE pd.partida_id IN (5244)
        ORDER BY pd.partida_id, pd.item_id
    LOOP
        -- New doc_movimiento_id groups all rolls of this (partida, item) together
        v_doc_mov_id := nextval('inventario.mov_doc_seq');

        FOR i IN 1 .. rec.n_rollos LOOP

            -- 1. Create the lote (secuencia auto-assigned by trigger)
            INSERT INTO inventario.lote (
                item_id,
                documento_tipo,   -- 'ajuste' marks manual injection (no real cuadre doc)
                documento_id,
                cantidad,
                propietario_id,   -- NULL = MLR-owned
                usr_cre
            )
            VALUES (
                rec.item_id,
                'PARTIDA',
                rec.partida_id,
                v_peso_kg_por_rollo,
                NULL,
                NULL              -- no user context in batch script
            )
            RETURNING id INTO v_lote_id;

            -- 2. Reserve roll in partida (roll row: item_id NULL, partida_paso_id NULL)
            INSERT INTO mes.partida_componente (
                partida_id,
                lote_id,
                item_id,
                partida_paso_id,
                cantidad_reservada,
                usr_cre
            )
            VALUES (
                rec.partida_id,
                v_lote_id,
                NULL,
                NULL,
                v_peso_kg_por_rollo,
                NULL
            )
ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

            -- 3. Post inventory movement (AJUSTE_POS → stock enters MLR warehouse)
            --    destino_ubicacion_id NULL = no specific bin (adjust if needed)
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id,
                item_id,
                lote_id,
                item_movimiento_tipo_id,
                origen_ubicacion_id,
                destino_ubicacion_id,
                cantidad,
                documento_tipo,
                documento_id,
                observacion,
                usr_cre
            )
            VALUES (
                v_doc_mov_id,
                rec.item_id,
                v_lote_id,
                v_ajuste_pos_id,
                NULL,
                (SELECT id FROM inventario.ubicacion WHERE almacen_id = (SELECT id FROM inventario.almacen WHERE codigo = 'ALM_CRU') LIMIT 1),               -- ← set to your bodega's ubicacion_id if needed
                v_peso_kg_por_rollo,
                'PARTIDA',
                rec.partida_id,
                'Ingreso artificial de rollo MLR propio para partida ' || rec.partida_id,
                NULL
            );

        END LOOP;
    END LOOP;
END;
$$;


-- ============================================================
-- Patch roll ingress — appends missing items to existing guia
--
-- Use when a partida already has lotes ingressed but partida_detalle
-- has item types not yet covered by any partida_componente lote.
-- New lotes are created under the partida's newest guia (no new
-- guia header), and guia_remision_detalle is extended accordingly.
--
-- Parameters (edit before running):
--   v_partida_id        : partida to patch
--   v_peso_kg_por_rollo : nominal kg per roll for the new lotes
-- ============================================================

-- -- DRY RUN ------------------------------------------------
/*
-- Items in detalle with no lote in componente yet:
SELECT pd.item_id, i.nombre, pd.cantidad AS n_rollos_needed
FROM mes.partida_detalle pd
JOIN item i ON i.id = pd.item_id
WHERE pd.partida_id = 5195   -- <- v_partida_id
  AND NOT EXISTS (
      SELECT 1
      FROM mes.partida_componente pc
      JOIN inventario.lote l ON l.id = pc.lote_id
      WHERE pc.partida_id = pd.partida_id
        AND l.item_id     = pd.item_id
  );

-- Existing guia that new lotes will be appended to:
SELECT gr.id, gr.serie, gr.correlativo, COUNT(pc.lote_id) AS existing_lotes
FROM mes.partida_componente        pc
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id
JOIN doc.guia_remision             gr  ON gr.id       = lrd.guia_remision_id
WHERE pc.partida_id = 0   -- <- v_partida_id
GROUP BY 1,2,3
ORDER BY gr.id DESC
LIMIT 1;
*/

-- -- EXECUTE BLOCK ------------------------------------------
DO $$
DECLARE
    v_partida_id        INT     := 5195;     -- <- CHANGE
    v_peso_kg_por_rollo NUMERIC := 20.0;  -- <- CHANGE

    v_guia_id        BIGINT;
    v_mov_tipo_id    SMALLINT;
    v_propietario_id INT;
    v_ubicacion_id   INT;
    v_doc_mov_id     BIGINT;
    v_lote_id        INT;
    v_count          INT;
    r                RECORD;
    i                INT;
BEGIN
    -- 1. Newest guia already linked to this partida
    SELECT gr.id
    INTO v_guia_id
    FROM mes.partida_componente        pc
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id
    JOIN doc.guia_remision             gr  ON gr.id       = lrd.guia_remision_id
    WHERE pc.partida_id = v_partida_id
      AND pc.lote_id IS NOT NULL
    ORDER BY pc.fyh_cre DESC
    LIMIT 1;

    IF v_guia_id IS NULL THEN
        RAISE EXCEPTION 'No existing guia for partida_id=%. Run the full bulk ingress first.', v_partida_id;
    END IF;

    RAISE NOTICE 'Patching into guia_id=% for partida_id=%', v_guia_id, v_partida_id;

    -- 2. Movement tipo and propietario from the guia
    SELECT grt.item_movimiento_tipo_id, gr.tercero_id
    INTO v_mov_tipo_id, v_propietario_id
    FROM doc.guia_remision gr
    JOIN doc.guia_remision_tipo grt ON grt.id = gr.guia_remision_tipo_id
    WHERE gr.id = v_guia_id;

    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1;

    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    -- 3. Only items in partida_detalle with no lote in partida_componente yet
    FOR r IN
        SELECT pd.item_id, pd.cantidad AS n_rollos
        FROM mes.partida_detalle pd
        WHERE pd.partida_id = v_partida_id
          AND NOT EXISTS (
              SELECT 1
              FROM mes.partida_componente pc
              JOIN inventario.lote l ON l.id = pc.lote_id
              WHERE pc.partida_id = pd.partida_id
                AND l.item_id     = pd.item_id
          )
        ORDER BY pd.item_id
    LOOP
        RAISE NOTICE '  Adding item_id=% — % roll(s)', r.item_id, r.n_rollos;

        FOR i IN 1 .. r.n_rollos LOOP

            INSERT INTO inventario.lote (
                item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre
            )
            VALUES (r.item_id, 'guia_remision', v_guia_id,
                    v_peso_kg_por_rollo, v_propietario_id, NULL)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id)
            VALUES (v_lote_id, v_guia_id);

            INSERT INTO mes.partida_componente (
                partida_id, lote_id, item_id, partida_paso_id,
                cantidad_reservada, usr_cre
            )
            VALUES (v_partida_id, v_lote_id, NULL, NULL, v_peso_kg_por_rollo, NULL)
            ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id,
                item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id,
                cantidad, documento_tipo, documento_id,
                observacion, usr_cre
            )
            VALUES (
                v_doc_mov_id, r.item_id, v_lote_id, v_mov_tipo_id,
                NULL, v_ubicacion_id, v_peso_kg_por_rollo,
                'guia_remision', v_guia_id,
                'Patch ingreso guia_id=' || v_guia_id || ' partida=' || v_partida_id,
                NULL
            );

            INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
            VALUES (v_guia_id, r.item_id, v_lote_id, v_peso_kg_por_rollo)
            ON CONFLICT (guia_remision_id, item_id, lote_id, ubicacion_id) DO NOTHING;

        END LOOP;
    END LOOP;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RAISE NOTICE 'Patch complete — guia_id=%, partida_id=%, doc_mov_id=%',
        v_guia_id, v_partida_id, v_doc_mov_id;
END;
$$;

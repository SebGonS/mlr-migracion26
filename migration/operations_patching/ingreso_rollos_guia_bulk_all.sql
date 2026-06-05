-- ============================================================
-- Bulk roll ingress — loops over all pending partidas from
-- vw_partidas_resumen (non-MLR clients, guia without dash).
--
-- Derives per-iteration:
--   partida_id    ← vw.partida
--   correlativo   ← vw.guia
--   fecha_emision ← vw.fecha_registro
--
-- Fixed params (edit before running):
--   v_tipo_codigo       : always CLIENTE_ENVIO_PROCESO for this query
--   v_serie             : serie prefix for all guias
--   v_peso_kg_por_rollo : used only when Mode A creates new lotes
--
-- Per-partida logic mirrors ingreso_rollos_guia_bulk.sql:
--   A. New items → lote + lote_rollo_detalle + partida_componente +
--                  item_movimientos + guia_remision_detalle
--   B. Existing lotes missing lrd → lote_rollo_detalle +
--                                   guia_remision_detalle only
-- ============================================================

-- -- DRY RUN: partidas that will be processed ------------------
/*
SELECT partida, guia, fecha_registro, cliente
FROM vw_partidas_resumen
WHERE estado IN ('Pendiente Receta', 'Pendiente Termofijar', 'Para Programar')
  AND cliente NOT IN ('Fredy Gaytan','MLR/Rudy','Oswaldo','Montes','MLR/Oswaldo','Jimmy','Boston','A&R TEXTILES')
  AND guia NOT LIKE '%-%'
ORDER BY partida;
*/

DO $$
DECLARE
    -- Fixed params
    v_tipo_codigo       TEXT    := 'CLIENTE_ENVIO_PROCESO';
    v_serie             TEXT    := '00';
    v_peso_kg_por_rollo NUMERIC := 20.0;  -- <- CHANGE (new lotes only)

    -- Resolved once
    v_tipo_id        SMALLINT;
    v_mov_tipo_id    SMALLINT;
    v_ubicacion_id   INT;

    -- Per-partida
    p                RECORD;
    v_partida_id     INT;
    v_correlativo    TEXT;
    v_fecha_emision  TIMESTAMPTZ;
    v_tercero_id     INT;
    v_propietario_id INT;
    v_guia_id        BIGINT;
    v_doc_mov_id     BIGINT;
    v_lote_id        INT;
    v_count_new      INT;
    v_count_patched  INT;
    r                RECORD;
    i                INT;
BEGIN
    -- Resolve tipo and ubicacion once for the whole batch
    SELECT grt.id, grt.item_movimiento_tipo_id
    INTO STRICT v_tipo_id, v_mov_tipo_id
    FROM doc.guia_remision_tipo grt
    WHERE grt.codigo = v_tipo_codigo;

    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1;

    FOR p IN
        SELECT partida::INT      AS partida_id,
               guia              AS correlativo,
               fecha_registro    AS fecha_emision
        FROM vw_partidas_resumen
        WHERE estado IN ('Pendiente Receta', 'Pendiente Termofijar', 'Para Programar')
          AND cliente NOT IN ('Fredy Gaytan','MLR/Rudy','Oswaldo','Montes','MLR/Oswaldo','Jimmy','Boston','A&R TEXTILES')
          AND guia NOT LIKE '%-%'
        ORDER BY partida::INT
    LOOP
        v_partida_id    := p.partida_id;
        v_correlativo   := p.correlativo;
        v_fecha_emision := p.fecha_emision;
        v_count_new     := 0;
        v_count_patched := 0;

        IF NOT EXISTS (SELECT 1 FROM mes.partida_detalle WHERE partida_id = v_partida_id) THEN
            RAISE NOTICE 'SKIP partida_id=% — no partida_detalle rows', v_partida_id;
            CONTINUE;
        END IF;

        SELECT tercero_id INTO STRICT v_tercero_id
        FROM mes.partida WHERE id = v_partida_id;

        v_propietario_id := v_tercero_id;  -- always CLIENTE_ENVIO_PROCESO

        -- Guia header — create or reuse
        INSERT INTO doc.guia_remision (
            guia_remision_tipo_id, tercero_id, serie, correlativo, fecha_emision
        )
        VALUES (v_tipo_id, v_tercero_id, v_serie, v_correlativo, v_fecha_emision)
        ON CONFLICT (tercero_id, serie, correlativo, guia_remision_tipo_id) DO NOTHING
        RETURNING id INTO v_guia_id;

        IF v_guia_id IS NULL THEN
            SELECT id INTO STRICT v_guia_id
            FROM doc.guia_remision
            WHERE tercero_id            = v_tercero_id
              AND serie                 = v_serie
              AND correlativo           = v_correlativo
              AND guia_remision_tipo_id = v_tipo_id;
            RAISE NOTICE '  [guia] Reusing id=% (%-%) partida=%',
                v_guia_id, v_serie, v_correlativo, v_partida_id;
        ELSE
            RAISE NOTICE '  [guia] Created id=% (%-%) partida=%',
                v_guia_id, v_serie, v_correlativo, v_partida_id;
        END IF;

        v_doc_mov_id := nextval('inventario.mov_doc_seq');

        -- ---- A. New lotes for items not yet in partida_componente ----
        FOR r IN
            SELECT pd.item_id, pd.cantidad AS n_rollos
            FROM mes.partida_detalle pd
            WHERE pd.partida_id = v_partida_id
              AND NOT EXISTS (
                  SELECT 1 FROM mes.partida_componente pc
                  JOIN inventario.lote l ON l.id = pc.lote_id
                  WHERE pc.partida_id = pd.partida_id AND l.item_id = pd.item_id
              )
            ORDER BY pd.item_id
        LOOP
            RAISE NOTICE '  [NEW] partida=% item_id=% — % roll(s)',
                v_partida_id, r.item_id, r.n_rollos;

            FOR i IN 1..r.n_rollos LOOP
                INSERT INTO inventario.lote (
                    item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre
                )
                VALUES (r.item_id, 'guia_remision', v_guia_id,
                        v_peso_kg_por_rollo, v_propietario_id, NULL)
                RETURNING id INTO v_lote_id;

                INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id)
                VALUES (v_lote_id, v_guia_id);

                INSERT INTO mes.partida_componente (
                    partida_id, lote_id, item_id, partida_paso_id, cantidad_reservada, usr_cre
                )
                VALUES (v_partida_id, v_lote_id, NULL, NULL, v_peso_kg_por_rollo, NULL)
                ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

                INSERT INTO inventario.item_movimientos (
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, destino_ubicacion_id,
                    cantidad, documento_tipo, documento_id, observacion, usr_cre
                )
                VALUES (
                    v_doc_mov_id, r.item_id, v_lote_id, v_mov_tipo_id,
                    NULL, v_ubicacion_id, v_peso_kg_por_rollo,
                    'guia_remision', v_guia_id,
                    'Ingreso via guia ' || v_serie || '-' || v_correlativo
                        || ' para partida ' || v_partida_id,
                    NULL
                );

                INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
                VALUES (v_guia_id, r.item_id, v_lote_id, v_peso_kg_por_rollo)
                ON CONFLICT (guia_remision_id, item_id, lote_id, ubicacion_id) DO NOTHING;

                v_count_new := v_count_new + 1;
            END LOOP;
        END LOOP;

        -- ---- B. Existing lotes missing their billing anchor ----------
        FOR r IN
            SELECT pc.lote_id, l.item_id, l.cantidad
            FROM mes.partida_componente pc
            JOIN inventario.lote l ON l.id = pc.lote_id
            WHERE pc.partida_id = v_partida_id
              AND pc.lote_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM inventario.lote_rollo_detalle lrd WHERE lrd.lote_id = pc.lote_id
              )
            ORDER BY pc.lote_id
        LOOP
            RAISE NOTICE '  [PATCH] partida=% lote_id=%', v_partida_id, r.lote_id;

            INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id)
            VALUES (r.lote_id, v_guia_id)
            ON CONFLICT DO NOTHING;

            INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
            VALUES (v_guia_id, r.item_id, r.lote_id, r.cantidad)
            ON CONFLICT (guia_remision_id, item_id, lote_id, ubicacion_id) DO NOTHING;

            v_count_patched := v_count_patched + 1;
        END LOOP;

        RAISE NOTICE 'Done partida_id=% guia=%-% — % new lote(s), % patched anchor(s)',
            v_partida_id, v_serie, v_correlativo, v_count_new, v_count_patched;
    END LOOP;

    RAISE NOTICE '=== Batch complete ===';
END;
$$;

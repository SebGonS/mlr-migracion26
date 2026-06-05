-- ============================================================
-- Bulk roll ingress — derives item/roll counts from partida_detalle
-- SELECT * FROM mes.partida_detalle WHERE partida_id = 4328;
-- SELECT * FROM mes.partida_detalle WHERE partida_id = 5358;

-- INSERT INTO mes.partida_detalle (partida_id, item_id, cantidad,unidad_id)
-- SELECT 5358, item_id, cantidad, unidad_id FROM mes.partida_detalle WHERE partida_id = 4328
-- ON CONFLICT (partida_id, item_id) DO NOTHING
-- INSERT INTO mes.partida_detalle (partida_id, item_id, cantidad,unidad_id)
-- SELECT 5862, item_id, cantidad, unidad_id FROM mes.partida_detalle WHERE partida_id = 4699
-- ON CONFLICT (partida_id, item_id) DO NOTHING
;
-- Two modes in one pass:
--   A. New items (in partida_detalle, no lotes in partida_componente yet)
--      → creates lote + lote_rollo_detalle + partida_componente +
--        item_movimientos + guia_remision_detalle
--   B. Existing lotes (in partida_componente, missing lote_rollo_detalle)
--      → adds only lote_rollo_detalle + guia_remision_detalle
--        (movements untouched — reverse+redo if audit trail needs fixing)
--
-- Guia header is created if it doesn't exist yet; reused if it does.
--
-- Parameters (edit before running):
--   v_tipo_codigo       : 'CLIENTE_ENVIO_PROCESO' or 'COMPRA_INGRESO'
--   v_tercero_id        : NULL for CLIENTE_ENVIO_PROCESO (derived from partida)
--                         set explicitly for COMPRA_INGRESO (supplier)
--   v_serie             : serie from the physical guia
--   v_correlativo       : correlativo from the physical guia
--   v_fecha_emision     : date on the physical guia
--   v_partida_id         : partida whose partida_detalle drives the ingress (roll counts + weights)
--   v_asignar_partida_id : partida to assign rolls to in partida_componente
--                          NULL = same as v_partida_id (normal case)
--                          set explicitly for rework ingress (don't touch the original partida)
--   v_prorate       : TRUE  → weights are TOTALS prorated per roll (read from public.partida)
--                     FALSE → weights are PER-ROLL (uniform; must set v_peso_regular/v_peso_rib manually)
--   v_peso_regular  : override — leave NULL to auto-read from public.partida.peso_rollos
--   v_peso_rib      : override — leave NULL to auto-read from public.partida.peso_rib
-- ============================================================

-- -- DRY RUN ------------------------------------------------
/*
-- A. Items that will get new lotes:
SELECT pd.item_id, i.nombre, pd.cantidad AS n_rollos
FROM mes.partida_detalle pd
JOIN item i ON i.id = pd.item_id
WHERE pd.partida_id = 0   -- <- v_partida_id
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc
      JOIN inventario.lote l ON l.id = pc.lote_id
      WHERE pc.partida_id = pd.partida_id AND l.item_id = pd.item_id
  );

-- B. Existing lotes missing their billing anchor:
SELECT pc.lote_id, l.item_id, l.cantidad
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 0   -- <- v_partida_id
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM inventario.lote_rollo_detalle lrd WHERE lrd.lote_id = pc.lote_id
  );
*/
-- Select * from vw_partidas_resumen 
-- where estado in ('Pendiente Receta', 'Pendiente Termofijar','Para Programar') 
-- and cliente NOT IN ('Fredy Gaytan','MLR/Rudy', 'Oswaldo','Montes','MLR/Oswaldo','Jimmy','Boston','A&R TEXTILES') --mlr oswarlo incluirlo en ingreso de mlr
-- AND guia NOT LIKE '%-%'

-- Select partida,guia,fecha_registro, from vw_partidas_resumen 
-- where estado in ('Pendiente Receta', 'Pendiente Termofijar','Para Programar') 
-- and cliente NOT IN ('Fredy Gaytan','MLR/Rudy', 'Oswaldo','Montes','MLR/Oswaldo','Jimmy','Boston','A&R TEXTILES') --mlr oswarlo incluirlo en ingreso de mlr
-- AND guia NOT LIKE '%-%'
-- SELECT * FROM partida WHERE id=4699   -- <- v_partida_id
-- -- EXECUTE BLOCK ------------------------------------------
  -- <- v_partida_id
DO $$
DECLARE
    v_tipo_codigo       TEXT        := 'CLIENTE_ENVIO_PROCESO';  -- <- CHANGE
    v_tercero_id        INT         := NULL;                      -- <- NULL for CLIENTE_ENVIO_PROCESO
    v_serie             TEXT        := '00';                      -- <- CHANGE
    v_correlativo       TEXT        := '1155';                    -- <- CHANGE
    v_fecha_emision     TIMESTAMPTZ := '2026-04-01 00:00:00-5';  -- <- CHANGE
    v_partida_id         INT         := 4328;                       -- <- CHANGE  drives roll counts + weight lookup
    v_asignar_partida_id INT         := 5358;                       -- <- set for rework; NULL = use v_partida_id
    v_prorate       BOOLEAN     := TRUE;                            -- <- TRUE = totals prorated; FALSE = per-roll
    v_peso_regular  NUMERIC     := NULL;                           -- <- NULL = read from public.partida.peso_rollos; set to override
    v_peso_rib      NUMERIC     := NULL;                           -- <- NULL = read from public.partida.peso_rib;    set to override

    v_guia_id        BIGINT;
    v_tipo_id        SMALLINT;
    v_mov_tipo_id    SMALLINT;
    v_propietario_id INT;
    v_doc_mov_id     BIGINT;
    v_ubicacion_id   INT;
    v_lote_id        INT;
    v_peso_por_rollo NUMERIC;
    v_flg_rib        BOOLEAN;
    v_count_new      INT := 0;
    v_count_patched  INT := 0;
    r                RECORD;
    i                INT;
BEGIN
    v_asignar_partida_id := COALESCE(v_asignar_partida_id, v_partida_id);

    -- Resolve guia tipo
    SELECT grt.id, grt.item_movimiento_tipo_id
    INTO STRICT v_tipo_id, v_mov_tipo_id
    FROM doc.guia_remision_tipo grt
    WHERE grt.codigo = v_tipo_codigo;

    -- Derive tercero from partida for CLIENTE_ENVIO_PROCESO
    IF v_tercero_id IS NULL THEN
        SELECT tercero_id INTO STRICT v_tercero_id
        FROM mes.partida WHERE id = v_partida_id;
    END IF;

    -- Auto-read weights from public.partida when not overridden
    IF v_peso_regular IS NULL OR v_peso_rib IS NULL THEN
        SELECT COALESCE(v_peso_regular, p.peso_rollos),
               COALESCE(v_peso_rib,     p.peso_rib)
        INTO   v_peso_regular, v_peso_rib
        FROM   public.partida p
        WHERE  p.id = v_partida_id;
    END IF;

    IF v_peso_regular IS NULL THEN
        RAISE EXCEPTION 'partida % has no peso_rollos — set it in public.partida or pass v_peso_regular manually', v_partida_id;
    END IF;
    v_peso_rib := COALESCE(v_peso_rib, 0);

    RAISE NOTICE 'Weights — regular: % kg  rib: % kg  (prorate=%)', v_peso_regular, v_peso_rib, v_prorate;

    v_propietario_id := CASE v_tipo_codigo
        WHEN 'CLIENTE_ENVIO_PROCESO' THEN v_tercero_id
        ELSE NULL
    END;

    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1;

    IF NOT EXISTS (SELECT 1 FROM mes.partida_detalle WHERE partida_id = v_partida_id) THEN
        RAISE EXCEPTION 'No partida_detalle rows for partida_id=%. Wrong id?', v_partida_id;
    END IF;

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
        RAISE NOTICE 'Reusing guia_remision id=% (%-% tipo=%)',
            v_guia_id, v_serie, v_correlativo, v_tipo_codigo;
    ELSE
        RAISE NOTICE 'Created guia_remision id=% (%-% tipo=%)',
            v_guia_id, v_serie, v_correlativo, v_tipo_codigo;
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
              WHERE pc.partida_id = v_asignar_partida_id AND l.item_id = pd.item_id
          )
        ORDER BY pd.item_id
    LOOP
        SELECT COALESCE(ird.flg_rib, FALSE)
        INTO v_flg_rib
        FROM item_rollo_detalle ird
        WHERE ird.item_id = r.item_id;

        v_peso_por_rollo := CASE
            WHEN v_flg_rib AND     v_prorate THEN v_peso_rib     / r.n_rollos
            WHEN v_flg_rib AND NOT v_prorate THEN v_peso_rib
            WHEN                   v_prorate THEN v_peso_regular / r.n_rollos
            ELSE                                  v_peso_regular
        END;

        RAISE NOTICE '  [NEW] item_id=% flg_rib=% n_rollos=% peso_por_rollo=% (prorate=%)',
            r.item_id, v_flg_rib, r.n_rollos, v_peso_por_rollo, v_prorate;

        FOR i IN 1 .. r.n_rollos LOOP
            INSERT INTO inventario.lote (
                item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre
            )
            VALUES (r.item_id, 'guia_remision', v_guia_id,
                    v_peso_por_rollo, v_propietario_id, NULL)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id)
            VALUES (v_lote_id, v_guia_id);

            INSERT INTO mes.partida_componente (
                partida_id, lote_id, item_id, partida_paso_id, cantidad_reservada, usr_cre
            )
            VALUES (v_asignar_partida_id, v_lote_id, NULL, NULL, v_peso_por_rollo, NULL)
            ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id,
                cantidad, documento_tipo, documento_id, observacion, usr_cre
            )
            VALUES (
                v_doc_mov_id, r.item_id, v_lote_id, v_mov_tipo_id,
                NULL, v_ubicacion_id, v_peso_por_rollo,
                'guia_remision', v_guia_id,
                'Ingreso via guia ' || v_serie || '-' || v_correlativo
                    || ' para partida ' || v_asignar_partida_id,
                NULL
            );

            INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
            VALUES (v_guia_id, r.item_id, v_lote_id, v_peso_por_rollo)
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
        RAISE NOTICE '  [PATCH] lote_id=% item_id=%', r.lote_id, r.item_id;

        INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id)
        VALUES (r.lote_id, v_guia_id)
        ON CONFLICT DO NOTHING;

        INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
        VALUES (v_guia_id, r.item_id, r.lote_id, r.cantidad)
        ON CONFLICT (guia_remision_id, item_id, lote_id, ubicacion_id) DO NOTHING;

        v_count_patched := v_count_patched + 1;
    END LOOP;

    RAISE NOTICE 'Done. guia_id=%, partida_id=% — % new lote(s), % patched anchor(s)',
        v_guia_id, v_partida_id, v_count_new, v_count_patched;
END;
$$;

-- -- VERIFY -------------------------------------------------
/*
SELECT l.id AS lote_id, l.item_id, l.cantidad,
       lrd.guia_remision_id, pc.partida_id
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle  lrd ON lrd.lote_id = l.id
JOIN mes.partida_componente         pc  ON pc.lote_id  = l.id
WHERE pc.partida_id = 0   -- <- v_partida_id
ORDER BY l.item_id, l.id;
*/

-- DO $$
-- DECLARE
--     v_lote_ids INT[]  := ARRAY[125187,125188,125189,125190,125191,125192,
--                                 125193,125194,125195,125196,125197,125198,
--                                 125199,125200,125201,125202];
--     v_count INT;
-- BEGIN
--     SET LOCAL session_replication_role = replica;

--     DELETE FROM inventario.item_movimientos WHERE lote_id = ANY(v_lote_ids);
--     GET DIAGNOSTICS v_count = ROW_COUNT; RAISE NOTICE 'Deleted % movements', v_count;

--     DELETE FROM inventario.lote_rollo_detalle WHERE lote_id = ANY(v_lote_ids);
--     GET DIAGNOSTICS v_count = ROW_COUNT; RAISE NOTICE 'Deleted % lote_rollo_detalle', v_count;

--     DELETE FROM inventario.lote WHERE id = ANY(v_lote_ids);
--     GET DIAGNOSTICS v_count = ROW_COUNT; RAISE NOTICE 'Deleted % lotes', v_count;

--     -- Guia 716 has no detail rows left, safe to drop
--     DELETE FROM doc.guia_remision WHERE id = 716
--       AND NOT EXISTS (SELECT 1 FROM doc.guia_remision_detalle WHERE guia_remision_id = 716);
--     RAISE NOTICE 'Guia deleted';
-- END;
-- $$;

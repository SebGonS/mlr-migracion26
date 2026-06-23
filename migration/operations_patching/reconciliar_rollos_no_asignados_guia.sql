-- ============================================================
-- RECONCILIAR: dejar los rollos NO ASIGNADOS de una entrega igual
--              a una lista objetivo (item_id, n_rollos, peso_total)
--
-- Caso: la entrega tiene rollos pendientes (sin asignar a partida)
-- que estan mal. Se "anulan" TODOS los no asignados y se vuelven
-- a crear exactamente los del target. Borrar-y-recrear deja el
-- estado final exacto sin importar que habia antes.
--
-- "No asignado" = el lote NO tiene fila en mes.partida_componente.
-- Los rollos ya asignados a una partida NO se tocan.
--
-- Anula (solo no asignados):  item_movimientos, entrega_detalle,
--                             lote_rollo_detalle, lote (soft-delete)
-- Crea (target):              lote, lote_rollo_detalle, movimiento
--                             de ingreso, entrega_detalle
--   -> NO crea partida_componente (estos rollos quedan sin asignar,
--      tal como estaban; recien despues se asignan/programan).
--
-- El peso por rollo de cada item del target se prorratea de su
-- peso_total. Leonardo no dio pesos -> hay que ponerlos (o ver el
-- peso que se anula con el DRY RUN y redistribuir).
--
-- Cada bloque es UNA entrega. Hay dos: 1889 y 1881.
-- ============================================================

-- -- DRY RUN: que rollos no asignados se anularian y cuanto peso ----
/*
SELECT l.id AS lote_id, i.nombre, l.item_id, l.cantidad
FROM inventario.lote l
JOIN item i ON i.id = l.item_id
WHERE l.documento_tipo = 'entrega'
  AND l.documento_id   = (SELECT id FROM doc.entrega WHERE correlativo = '1889')
  AND l.fyh_elm IS NULL
  AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc WHERE pc.lote_id = l.id)
ORDER BY l.item_id, l.id;

-- Mapear nombres -> item_id (ajusta el ILIKE a tu catalogo):
SELECT id, nombre FROM item
WHERE nombre ILIKE '%20/1%'
ORDER BY nombre;
*/
-- SELECT * FROM item WHERE nombre ILIKE '%20/1%' 
-- ============================================================
-- BLOQUE A — entrega 1889 -> debe quedar: 16 rib J 20/1
-- ============================================================
DO $$
DECLARE
    v_correlativo TEXT := '1889';   -- <- entrega
    v_serie       TEXT := NULL;     -- <- si tu entrega identifica por serie, ponla; si no, se ignora

    -- TARGET: una fila por tipo de item -> ARRAY[item_id, n_rollos, peso_total_kg]
    -- 16 rib J 20/1  ->  item 299 = "Rollo Rib J 20/1 1 fibra(s)"
    v_target INT[][] := ARRAY[
        ARRAY[ 299::INT, 16::INT, /*peso_total*/ 0::INT ]
        -- , ARRAY[ ..., ..., ... ]   -- agrega mas lineas si hace falta
    ];

    -- ---- internos ----
    v_entrega_id        BIGINT;
    v_tipo_id        SMALLINT;
    v_mov_tipo_id    SMALLINT;
    v_propietario_id INT;
    v_tercero_id     INT;
    v_ubicacion_id   INT;
    v_doc_mov_id     BIGINT;
    v_lote_ids       INT[];
    v_anulados       INT;
    v_lote_id        INT;
    v_item_id        INT;
    v_n_rollos       INT;
    v_peso_total     NUMERIC;
    v_peso_rollo     NUMERIC;
    i                INT;
    fila             INT[];
BEGIN
    -- Resolver entrega
    SELECT id INTO STRICT v_entrega_id
    FROM doc.entrega
    WHERE correlativo = v_correlativo
      AND (v_serie IS NULL OR serie = v_serie)
      AND fyh_elm IS NULL;

    -- tipo + mov_tipo + tercero/propietario desde la entrega existente
    SELECT gr.entrega_tipo_id, grt.item_movimiento_tipo_id, gr.tercero_id
    INTO STRICT v_tipo_id, v_mov_tipo_id, v_tercero_id
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = v_entrega_id;

    -- propietario: si es CLIENTE_ENVIO_PROCESO la tela es del cliente (= tercero)
    SELECT CASE WHEN grt.codigo = 'CLIENTE_ENVIO_PROCESO' THEN v_tercero_id ELSE NULL END
    INTO v_propietario_id
    FROM doc.entrega_tipo grt WHERE grt.id = v_tipo_id;

    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU' LIMIT 1;

    -- ---- 1) ANULAR rollos no asignados de esta entrega ----
    SELECT ARRAY_AGG(l.id) INTO v_lote_ids
    FROM inventario.lote l
    WHERE l.documento_tipo = 'entrega'
      AND l.documento_id   = v_entrega_id
      AND l.fyh_elm IS NULL
      AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc WHERE pc.lote_id = l.id);

    IF v_lote_ids IS NOT NULL THEN
        DELETE FROM inventario.item_movimientos   WHERE lote_id = ANY(v_lote_ids);
        DELETE FROM doc.entrega_detalle      WHERE lote_id = ANY(v_lote_ids);
        DELETE FROM inventario.lote_rollo_detalle  WHERE lote_id = ANY(v_lote_ids);
        UPDATE inventario.lote SET fyh_elm = NOW() WHERE id = ANY(v_lote_ids);
        GET DIAGNOSTICS v_anulados = ROW_COUNT;
        RAISE NOTICE 'entrega % : anulados % rollos no asignados', v_correlativo, v_anulados;
    ELSE
        RAISE NOTICE 'entrega % : no habia rollos no asignados que anular', v_correlativo;
    END IF;

    -- ---- 2) CREAR el target ----
    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    FOREACH fila SLICE 1 IN ARRAY v_target LOOP
        v_item_id    := fila[1];
        v_n_rollos   := fila[2];
        v_peso_total := fila[3];

        IF v_item_id = 0 THEN
            RAISE EXCEPTION 'Falta poner el item_id real en el target de la entrega %', v_correlativo;
        END IF;
        -- pendiente de pesaje -> placeholder 0.1 kg por rollo (se corrige al pesar)
        v_peso_rollo := 0.1;

        FOR i IN 1 .. v_n_rollos LOOP
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
            VALUES (v_item_id, 'entrega', v_entrega_id, v_peso_rollo, v_propietario_id, NULL)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id)
            VALUES (v_lote_id, v_entrega_id);

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id, cantidad,
                documento_tipo, documento_id, observacion, usr_cre
            )
            VALUES (
                v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                NULL, v_ubicacion_id, v_peso_rollo,
                'entrega', v_entrega_id,
                'Reconciliacion no-asignados entrega ' || v_correlativo, NULL
            );

            INSERT INTO doc.entrega_detalle (entrega_id, item_id, lote_id, cantidad)
            VALUES (v_entrega_id, v_item_id, v_lote_id, v_peso_rollo)
            ON CONFLICT (entrega_id, item_id, lote_id, ubicacion_id) DO NOTHING;
        END LOOP;

        RAISE NOTICE '  + item % : % rollos x % kg', v_item_id, v_n_rollos, v_peso_rollo;
    END LOOP;

    RAISE NOTICE 'entrega % reconciliada. entrega_id=%, doc_mov=%', v_correlativo, v_entrega_id, v_doc_mov_id;
END;
$$;

-- ============================================================
-- BLOQUE B — entrega 1881 -> debe quedar: 16 J 20/1 + 3 pqte cuellos J 20/1
--   (mismo cuerpo; solo cambian v_correlativo y v_target)
-- ============================================================
DO $$
DECLARE
    v_correlativo TEXT := '1881';
    v_serie       TEXT := NULL;

    -- 16 J 20/1 (liso -> item 240) + 3 paquetes cuellos J 20/1 (item 324)
    v_target INT[][] := ARRAY[
        ARRAY[ 240::INT, 16::INT, /*peso_total*/ 0::INT ],
        ARRAY[ 324::INT,  3::INT, /*peso_total*/ 0::INT ]
    ];

    v_entrega_id        BIGINT;
    v_tipo_id        SMALLINT;
    v_mov_tipo_id    SMALLINT;
    v_propietario_id INT;
    v_tercero_id     INT;
    v_ubicacion_id   INT;
    v_doc_mov_id     BIGINT;
    v_lote_ids       INT[];
    v_anulados       INT;
    v_lote_id        INT;
    v_item_id        INT;
    v_n_rollos       INT;
    v_peso_total     NUMERIC;
    v_peso_rollo     NUMERIC;
    i                INT;
    fila             INT[];
BEGIN
    SELECT id INTO STRICT v_entrega_id
    FROM doc.entrega
    WHERE correlativo = v_correlativo
      AND (v_serie IS NULL OR serie = v_serie)
      AND fyh_elm IS NULL;

    SELECT gr.entrega_tipo_id, grt.item_movimiento_tipo_id, gr.tercero_id
    INTO STRICT v_tipo_id, v_mov_tipo_id, v_tercero_id
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = v_entrega_id;

    SELECT CASE WHEN grt.codigo = 'CLIENTE_ENVIO_PROCESO' THEN v_tercero_id ELSE NULL END
    INTO v_propietario_id
    FROM doc.entrega_tipo grt WHERE grt.id = v_tipo_id;

    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU' LIMIT 1;

    SELECT ARRAY_AGG(l.id) INTO v_lote_ids
    FROM inventario.lote l
    WHERE l.documento_tipo = 'entrega'
      AND l.documento_id   = v_entrega_id
      AND l.fyh_elm IS NULL
      AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc WHERE pc.lote_id = l.id);

    IF v_lote_ids IS NOT NULL THEN
        DELETE FROM inventario.item_movimientos   WHERE lote_id = ANY(v_lote_ids);
        DELETE FROM doc.entrega_detalle      WHERE lote_id = ANY(v_lote_ids);
        DELETE FROM inventario.lote_rollo_detalle  WHERE lote_id = ANY(v_lote_ids);
        UPDATE inventario.lote SET fyh_elm = NOW() WHERE id = ANY(v_lote_ids);
        GET DIAGNOSTICS v_anulados = ROW_COUNT;
        RAISE NOTICE 'entrega % : anulados % rollos no asignados', v_correlativo, v_anulados;
    ELSE
        RAISE NOTICE 'entrega % : no habia rollos no asignados que anular', v_correlativo;
    END IF;

    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    FOREACH fila SLICE 1 IN ARRAY v_target LOOP
        v_item_id    := fila[1];
        v_n_rollos   := fila[2];
        v_peso_total := fila[3];

        IF v_item_id = 0 THEN
            RAISE EXCEPTION 'Falta poner el item_id real en el target de la entrega %', v_correlativo;
        END IF;
        -- pendiente de pesaje -> placeholder 0.1 kg por rollo (se corrige al pesar)
        v_peso_rollo := 0.1;

        FOR i IN 1 .. v_n_rollos LOOP
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
            VALUES (v_item_id, 'entrega', v_entrega_id, v_peso_rollo, v_propietario_id, NULL)
            RETURNING id INTO v_lote_id;

            INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id)
            VALUES (v_lote_id, v_entrega_id);

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id, cantidad,
                documento_tipo, documento_id, observacion, usr_cre
            )
            VALUES (
                v_doc_mov_id, v_item_id, v_lote_id, v_mov_tipo_id,
                NULL, v_ubicacion_id, v_peso_rollo,
                'entrega', v_entrega_id,
                'Reconciliacion no-asignados entrega ' || v_correlativo, NULL
            );

            INSERT INTO doc.entrega_detalle (entrega_id, item_id, lote_id, cantidad)
            VALUES (v_entrega_id, v_item_id, v_lote_id, v_peso_rollo)
            ON CONFLICT (entrega_id, item_id, lote_id, ubicacion_id) DO NOTHING;
        END LOOP;

        RAISE NOTICE '  + item % : % rollos x % kg', v_item_id, v_n_rollos, v_peso_rollo;
    END LOOP;

    RAISE NOTICE 'entrega % reconciliada. entrega_id=%, doc_mov=%', v_correlativo, v_entrega_id, v_doc_mov_id;
END;
$$;

-- -- VERIFY -------------------------------------------------
/*
SELECT gr.correlativo, i.nombre, l.item_id, COUNT(*) AS rollos, SUM(l.cantidad) AS peso
FROM inventario.lote l
JOIN doc.entrega gr ON gr.id = l.documento_id
JOIN item i ON i.id = l.item_id
WHERE l.documento_tipo = 'entrega'
  AND gr.correlativo IN ('1881','1889')
  AND l.fyh_elm IS NULL
GROUP BY gr.correlativo, i.nombre, l.item_id
ORDER BY gr.correlativo, l.item_id;
*/

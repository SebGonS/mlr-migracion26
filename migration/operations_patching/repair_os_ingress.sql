-- ═══════════════════════════════════════════════════════════════
-- Repair: backfill lotes + movements for an orden_servicio that
-- was inserted directly (bypassing crear_orden_servicio).
--
-- Prerequisites:
--   1. Run patch 22b (item_id on orden_servicio_detalle)
--   2. Fill in item_id on each detalle row for this OS:
--        UPDATE doc.orden_servicio_detalle SET item_id = <X> WHERE id = <Y>;
--   3. Set variables below and run.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_os_id                 BIGINT  := 1;                                                     -- ← FILL IN
    v_destino_ubicacion_id  INT     := 8;  -- ← FILL IN
    v_usr_id                INT     := 4;                                                     -- ← FILL IN

    v_doc_movimiento_id     BIGINT;
    v_serv_ing_tipo_id      SMALLINT;
    v_detalle               RECORD;
    v_os                    RECORD;
    v_new_lote_id           INT;
    v_existing_count        INT;
    v_needed                INT;
    v_null_item_count       INT;
    i                       INT;
BEGIN
    -- ── Integrity checks ─────────────────────────────────────────

    -- OS exists and is not deleted
    SELECT os.* INTO v_os
    FROM doc.orden_servicio os
    WHERE os.id = v_os_id AND os.flg_elm = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'orden_servicio % does not exist or is deleted.', v_os_id;
    END IF;

    -- All detalle rows have item_id set
    SELECT COUNT(*) INTO v_null_item_count
    FROM doc.orden_servicio_detalle
    WHERE orden_servicio_id = v_os_id AND item_id IS NULL;

    IF v_null_item_count > 0 THEN
        RAISE EXCEPTION '% detalle row(s) still have NULL item_id. Run the UPDATE first.', v_null_item_count;
    END IF;

    -- All item_ids are ROLLO type
    IF EXISTS (
        SELECT 1
        FROM doc.orden_servicio_detalle osd
        JOIN item i      ON i.id = osd.item_id
        JOIN item_tipo it ON it.id = i.item_tipo_id
        WHERE osd.orden_servicio_id = v_os_id
          AND it.codigo <> 'ROLLO'
    ) THEN
        RAISE EXCEPTION 'One or more item_ids on detalle are not ROLLO type.';
    END IF;

    -- SERV_ING movement tipo exists
    SELECT id INTO v_serv_ing_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING';

    IF v_serv_ing_tipo_id IS NULL THEN
        RAISE EXCEPTION 'Movement tipo SERV_ING not found.';
    END IF;

    -- Destination ubicacion exists
    IF NOT EXISTS (SELECT 1 FROM inventario.ubicacion WHERE id = v_destino_ubicacion_id) THEN
        RAISE EXCEPTION 'ubicacion_id % does not exist.', v_destino_ubicacion_id;
    END IF;

    -- ── Repair ───────────────────────────────────────────────────

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    FOR v_detalle IN
        SELECT osd.id, osd.item_id, osd.cantidad, osd.malla
        FROM doc.orden_servicio_detalle osd
        WHERE osd.orden_servicio_id = v_os_id
    LOOP
        SELECT COUNT(*) INTO v_existing_count
        FROM inventario.lote l
        JOIN inventario.item_movimientos im ON im.lote_id = l.id
        WHERE im.documento_tipo    = 'orden_servicio'
          AND im.documento_id      = v_os_id
          AND im.documento_linea_id = v_detalle.id
          AND l.fyh_elm IS NULL;

        v_needed := v_detalle.cantidad - v_existing_count;

        IF v_needed <= 0 THEN
            RAISE NOTICE 'Detalle %: already has % lotes, skipping.', v_detalle.id, v_existing_count;
            CONTINUE;
        END IF;

        RAISE NOTICE 'Detalle %: creating % lotes for item %.', v_detalle.id, v_needed, v_detalle.item_id;

        FOR i IN 1 .. v_needed
        LOOP
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id)
            VALUES (v_detalle.item_id, 'orden_servicio', v_os_id, 0.1, NULL)
            RETURNING id INTO v_new_lote_id;

            INSERT INTO inventario.lote_rollo_detalle (
                lote_id, orden_servicio_id,
                ancho, malla, rendimiento,
                flg_tenido, flg_antipilling
            ) VALUES (
                v_new_lote_id, v_os_id,
                v_os.ancho, v_detalle.malla, v_os.rendimiento,
                false, COALESCE(v_os.flg_antipilling, false)
            );

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                destino_ubicacion_id, cantidad, fecha_hora,
                documento_tipo, documento_id, documento_linea_id
            ) VALUES (
                v_doc_movimiento_id,
                v_detalle.item_id,
                v_new_lote_id,
                v_serv_ing_tipo_id,
                v_destino_ubicacion_id,
                0.1,
                now(),
                'orden_servicio', v_os_id, v_detalle.id
            );
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Repair complete for orden_servicio %. Doc movimiento id: %.', v_os_id, v_doc_movimiento_id;
END;
$$;


-- Step A: see which detalle rows still need item_id (replace OS id as needed)
SELECT osd.id, osd.articulo_id, a.nombre AS articulo, osd.malla, osd.cantidad
FROM doc.orden_servicio_detalle osd
JOIN articulo a ON a.id = osd.articulo_id
WHERE osd.orden_servicio_id =2
  AND osd.item_id IS NULL;

-- Step B: find the ROLLO item_id for a given articulo_id
SELECT i.id, i.codigo, i.nombre, a.nombre AS articulo
FROM item i
JOIN item_rollo_detalle ird ON ird.item_id = i.id
JOIN articulo a              ON a.id = ird.articulo_id
JOIN item_tipo it            ON it.id = i.item_tipo_id
WHERE it.codigo = 'ROLLO'
  AND ird.articulo_id IN (18);

-- Step C: backfill (one UPDATE per detalle row)
-- UPDATE doc.orden_servicio_detalle SET item_id = <item_id> WHERE id = <detalle_id>;
UPDATE doc.orden_servicio_detalle
SET item_id = 253
WHERE orden_servicio_id = 2
  AND item_id IS NULL;


  SELECT
    osd.id          AS detalle_id,
    osd.linea,
    osd.cantidad    AS rollos_esperados,
    osd.item_id,
    i.nombre        AS item,
    COUNT(DISTINCT l.id) AS lotes_existentes
FROM doc.orden_servicio_detalle osd
JOIN item i ON i.id = osd.item_id
LEFT JOIN inventario.item_movimientos im
    ON im.documento_tipo     = 'orden_servicio'
   AND im.documento_id       = osd.orden_servicio_id
   AND im.documento_linea_id = osd.id
LEFT JOIN inventario.lote l
    ON l.id = im.lote_id
   AND l.fyh_elm IS NULL
WHERE osd.orden_servicio_id = 2  -- ← change as needed
GROUP BY osd.id, osd.linea, osd.cantidad, osd.item_id, i.nombre
ORDER BY osd.linea;


SELECT
    osd.id          AS detalle_id,
    osd.linea,
    osd.cantidad    AS rollos_esperados,
    osd.item_id,
    i.nombre        AS item,
    COUNT(DISTINCT l.id) AS lotes_existentes
FROM doc.orden_servicio_detalle osd
JOIN item i ON i.id = osd.item_id
LEFT JOIN inventario.item_movimientos im
    ON im.documento_tipo     = 'orden_servicio'
   AND im.documento_id       = osd.orden_servicio_id
   AND im.documento_linea_id = osd.id
LEFT JOIN inventario.lote l
    ON l.id = im.lote_id
   AND l.fyh_elm IS NULL
WHERE osd.orden_servicio_id = 2
GROUP BY osd.id, osd.linea, osd.cantidad, osd.item_id, i.nombre
ORDER BY osd.linea;

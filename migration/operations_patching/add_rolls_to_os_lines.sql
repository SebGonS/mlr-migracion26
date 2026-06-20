-- ═══════════════════════════════════════════════════════════════
-- Add MORE rolls to existing orden_servicio lines, then attach them
-- to the partida already created from those lines.
--
-- Run as TWO steps:
--   BLOCK 1  ingress the extra rolls           → WRITES THE LEDGER (SERV_ING)
--   BLOCK 2  reserve them onto the partida      → reservation only, NOT the ledger
--
-- BLOCK 2 replicates mes.actualizar_componentes_partida for the additive
-- case (the function itself is SECURITY DEFINER + jwt-gated, so it won't run
-- from a plain SQL session). It honors the same guards:
--   • partida not TECO/CERRADA/CANCELADA
--   • no paso started (recipe was scaled to the original weight — adding rolls
--     mid-execution is a different, manual problem)
--   • bumps partida_detalle.cantidad so the planned roll count stays in step
--   • clears chemical reservations so recipes re-scale to the new weight
--     → you must re-run generar_receta per paso afterwards
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- BLOCK 1 — ingress extra rolls (LEDGER WRITE)
--
-- v_adds: one object per line to grow
--   detalle_id    orden_servicio_detalle.id of the line
--   extra_rollos  how many MORE rolls to add
--   factura_hilo  null = inherit the line's existing thread invoice
--   peso_total    null = 0.1 kg/roll sentinel; a number = split evenly
-- ═══════════════════════════════════════════════════════════════

-- SELECT * FROM doc.orden_servicio_detalle OrdER BY orden_servicio_id desc

DO $$
DECLARE
    v_os_id                 BIGINT := 6;                                                  -- ← FILL IN
    v_destino_ubicacion_id  INT    := (SELECT id FROM inventario.ubicacion WHERE almacen_id = (SELECT id FROM inventario.almacen WHERE codigo='ALM_CRU'));  -- ← FILL IN

    v_adds JSONB := '[
        {"detalle_id": 19, "extra_rollos": 2,  "peso_total": 0.1},
         {"detalle_id": 18, "extra_rollos": 1,  "peso_total": 0.1}
    ]'::jsonb;                                                                                   -- ← FILL IN

    v_os                    RECORD;
    v_add                   JSONB;
    v_detalle_id            BIGINT;
    v_extra                 INT;
    v_item_id               INT;
    v_malla                 TEXT;
    v_peso_por_rollo        NUMERIC;
    v_doc_movimiento_id     BIGINT;
    v_serv_ing_tipo_id      SMALLINT;
    v_new_lote_id           INT;
    i                       INT;
BEGIN
    SELECT os.* INTO v_os
    FROM doc.orden_servicio os
    WHERE os.id = v_os_id AND os.flg_elm = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'orden_servicio % does not exist or is deleted.', v_os_id;
    END IF;

    SELECT id INTO v_serv_ing_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING';
    IF v_serv_ing_tipo_id IS NULL THEN
        RAISE EXCEPTION 'Movement tipo SERV_ING not found.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventario.ubicacion WHERE id = v_destino_ubicacion_id) THEN
        RAISE EXCEPTION 'ubicacion_id % does not exist.', v_destino_ubicacion_id;
    END IF;

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    FOR v_add IN SELECT * FROM jsonb_array_elements(v_adds)
    LOOP
        v_detalle_id := (v_add->>'detalle_id')::BIGINT;
        v_extra      := (v_add->>'extra_rollos')::INT;

        IF v_extra IS NULL OR v_extra <= 0 THEN
            RAISE EXCEPTION 'Line %: extra_rollos must be > 0.', v_detalle_id;
        END IF;

        SELECT osd.item_id, osd.malla
        INTO v_item_id, v_malla
        FROM doc.orden_servicio_detalle osd
        JOIN item it_       ON it_.id = osd.item_id
        JOIN item_tipo itp  ON itp.id = it_.item_tipo_id
        WHERE osd.id = v_detalle_id
          AND osd.orden_servicio_id = v_os_id
          AND itp.codigo = 'ROLLO';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'detalle % is not a ROLLO line of orden_servicio %.', v_detalle_id, v_os_id;
        END IF;

        v_peso_por_rollo := COALESCE(
            (v_add->>'peso_total')::NUMERIC / NULLIF(v_extra, 0),
            0.1
        );

        RAISE NOTICE 'Line %: adding % rolls (item %).', v_detalle_id, v_extra, v_item_id;

        FOR i IN 1 .. v_extra
        LOOP
            INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id)
            VALUES (v_item_id, 'orden_servicio', v_os_id, v_peso_por_rollo, NULL)
            RETURNING id INTO v_new_lote_id;

            INSERT INTO inventario.lote_rollo_detalle (
                lote_id, orden_servicio_id,
                ancho, malla, rendimiento,
                flg_tenido, flg_antipilling
            ) VALUES (
                v_new_lote_id, v_os_id,
                v_os.ancho, v_malla, v_os.rendimiento,
                false, COALESCE(v_os.flg_antipilling, false)
            );

            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                destino_ubicacion_id, cantidad, fecha_hora,
                documento_tipo, documento_id, documento_linea_id
            ) VALUES (
                v_doc_movimiento_id, v_item_id, v_new_lote_id, v_serv_ing_tipo_id,
                v_destino_ubicacion_id, v_peso_por_rollo, now(),
                'orden_servicio', v_os_id, v_detalle_id
            );
        END LOOP;

        -- keep OS doc intent in step with stock
        UPDATE doc.orden_servicio_detalle
        SET cantidad = cantidad + v_extra
        WHERE id = v_detalle_id;
    END LOOP;

    RAISE NOTICE 'BLOCK 1 done. orden_servicio %. Doc movimiento id: %.', v_os_id, v_doc_movimiento_id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- BLOCK 2 — reserve the new rolls onto the existing partida
--           (reservation only — does NOT touch the ledger)
--
-- The partida is DERIVED, not supplied: each new roll → its OS line
-- (via the SERV_ING movement's documento_linea_id) → the partida that
-- already holds the other rolls of that line. Raises if a line has no
-- existing partida, maps to several, or the partida has already started.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_os_id    BIGINT := 6;   -- ← FILL IN (same as BLOCK 1)
    v_usr_id   INT    := 4;         -- ← FILL IN if not 4

    v_bad      TEXT;
    v_attached INT;
BEGIN
    -- new (unreserved) OS rolls → their line → the partida already holding that line
    CREATE TEMP TABLE _attach ON COMMIT DROP AS
    WITH detalle_partida AS (
        -- which partida currently holds each OS line's rolls
        SELECT DISTINCT im.documento_linea_id AS detalle_id, pc.partida_id
        FROM mes.partida_componente pc
        JOIN inventario.item_movimientos im
          ON im.lote_id        = pc.lote_id
         AND im.documento_tipo  = 'orden_servicio'
         AND im.documento_id    = v_os_id
        WHERE pc.lote_id IS NOT NULL
    ),
    new_rolls AS (
        SELECT l.id AS lote_id, l.item_id, l.cantidad,
               im.documento_linea_id AS detalle_id
        FROM inventario.lote l
        JOIN inventario.item_movimientos im
          ON im.lote_id        = l.id
         AND im.documento_tipo  = 'orden_servicio'
         AND im.documento_id    = v_os_id
        WHERE l.documento_tipo = 'orden_servicio'
          AND l.documento_id   = v_os_id
          AND l.fyh_elm IS NULL
          AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc WHERE pc.lote_id = l.id)
    )
    SELECT nr.lote_id, nr.item_id, nr.cantidad, nr.detalle_id, dp.partida_id
    FROM new_rolls nr
    LEFT JOIN detalle_partida dp ON dp.detalle_id = nr.detalle_id;

    IF NOT EXISTS (SELECT 1 FROM _attach) THEN
        RAISE NOTICE 'No unreserved orden_servicio rolls for OS %. Nothing to attach.', v_os_id;
        RETURN;
    END IF;

    -- line(s) with new rolls but no existing partida → cannot derive
    SELECT string_agg(DISTINCT detalle_id::text, ', ') INTO v_bad
    FROM _attach WHERE partida_id IS NULL;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Line(s) % have new rolls but no existing partida to derive from.', v_bad;
    END IF;

    -- line(s) whose existing rolls span >1 partida → ambiguous
    SELECT string_agg(detalle_id::text, ', ') INTO v_bad
    FROM (SELECT detalle_id FROM _attach GROUP BY detalle_id HAVING COUNT(DISTINCT partida_id) > 1) q;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Line(s) % map to multiple partidas; cannot auto-derive.', v_bad;
    END IF;

    -- target partida(s) must be pre-execution
    SELECT string_agg(DISTINCT p.id::text, ', ') INTO v_bad
    FROM _attach a JOIN mes.partida p ON p.id = a.partida_id
    WHERE p.estado_produccion IN ('TECO','CERRADA','CANCELADA')
       OR EXISTS (
           SELECT 1 FROM mes.partida_paso pp
           JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
           WHERE pp.partida_id = p.id AND ppe.estado IN ('EN_PROCESO','COMPLETADO','OMITIDO')
       );
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Partida(s) % are terminal or have started pasos; cannot add rolls automatically.', v_bad;
    END IF;

    -- every (partida,item) must already have a planned-item row to grow
    SELECT string_agg(DISTINCT a.partida_id || '/' || a.item_id, ', ') INTO v_bad
    FROM _attach a
    WHERE NOT EXISTS (
        SELECT 1 FROM mes.partida_detalle pd
        WHERE pd.partida_id = a.partida_id AND pd.item_id = a.item_id
    );
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Partida/item % has no partida_detalle row to grow.', v_bad;
    END IF;

    -- bump planned roll count per (partida,item)
    UPDATE mes.partida_detalle pd
    SET cantidad = pd.cantidad + sub.n, fyh_mod = now()
    FROM (SELECT partida_id, item_id, COUNT(*) AS n FROM _attach GROUP BY partida_id, item_id) sub
    WHERE pd.partida_id = sub.partida_id AND pd.item_id = sub.item_id;

    -- reserve the new rolls (RESB rows)
    INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada, usr_cre)
    SELECT a.partida_id, a.lote_id, a.cantidad, v_usr_id
    FROM _attach a
    ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;
    GET DIAGNOSTICS v_attached = ROW_COUNT;

    -- batch weight changed → chemical reservations are stale; force re-generation
    DELETE FROM mes.partida_componente
    WHERE item_id IS NOT NULL
      AND partida_paso_id IN (
          SELECT pp.id FROM mes.partida_paso pp
          WHERE pp.partida_id IN (SELECT DISTINCT partida_id FROM _attach)
      );

    RAISE NOTICE 'BLOCK 2 done. Reserved % new rolls onto partida(s) %. '
                 'Chemical reservations cleared — re-run generar_receta per paso to re-scale.',
                 v_attached, (SELECT string_agg(DISTINCT partida_id::text, ', ') FROM _attach);
END;
$$;

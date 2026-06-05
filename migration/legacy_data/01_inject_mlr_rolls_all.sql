-- ============================================================
-- Bulk MLR-owned roll injection — loops over pending partidas
-- from vw_partidas_resumen (includes MLR/Oswaldo, excludes
-- pure-client senders).
--
-- No guia involved: lotes are stamped documento_tipo='PARTIDA',
-- propietario_id=NULL (MLR stock), movement type AJUSTE_POS.
--
-- Fixed params (edit before running):
--   v_peso_kg_por_rollo : nominal kg/roll for all new lotes
--
-- Idempotent: skips items already present in partida_componente.
-- ============================================================

-- -- DRY RUN: partidas that will be processed ------------------
/*
SELECT partida, cliente, estado, fecha_registro
FROM vw_partidas_resumen
WHERE estado IN ('Pendiente Receta', 'Pendiente Termofijar', 'Para Programar')
  AND cliente = 'MLR/Oswaldo'
ORDER BY partida::INT;
*/

DO $$
DECLARE
    v_peso_kg_por_rollo  NUMERIC := 20.0;  -- <- CHANGE

    -- Resolved once
    v_ajuste_pos_id  SMALLINT;
    v_ubicacion_id   INT;

    -- Per-partida
    p            RECORD;
    rec          RECORD;
    v_doc_mov_id BIGINT;
    v_lote_id    INT;
    v_count      INT;
    i            INT;
BEGIN
    SELECT id INTO STRICT v_ajuste_pos_id
    FROM inventario.item_movimiento_tipo
    WHERE codigo = 'AJUSTE_POS';

    SELECT ub.id INTO STRICT v_ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1;

    FOR p IN
        SELECT partida::INT AS partida_id
        FROM vw_partidas_resumen
        WHERE estado IN ('Pendiente Receta', 'Pendiente Termofijar', 'Para Programar')
          AND cliente = 'MLR/Oswaldo'
        ORDER BY partida::INT
    LOOP
        v_count := 0;

        IF NOT EXISTS (SELECT 1 FROM mes.partida_detalle WHERE partida_id = p.partida_id) THEN
            RAISE NOTICE 'SKIP partida_id=% — no partida_detalle rows', p.partida_id;
            CONTINUE;
        END IF;

        FOR rec IN
            SELECT pd.item_id, pd.cantidad::INT AS n_rollos
            FROM mes.partida_detalle pd
            WHERE pd.partida_id = p.partida_id
              AND NOT EXISTS (
                  SELECT 1 FROM mes.partida_componente pc
                  JOIN inventario.lote l ON l.id = pc.lote_id
                  WHERE pc.partida_id = pd.partida_id AND l.item_id = pd.item_id
              )
            ORDER BY pd.item_id
        LOOP
            RAISE NOTICE '  [NEW] partida=% item_id=% — % roll(s)',
                p.partida_id, rec.item_id, rec.n_rollos;

            v_doc_mov_id := nextval('inventario.mov_doc_seq');

            FOR i IN 1..rec.n_rollos LOOP
                INSERT INTO inventario.lote (
                    item_id, documento_tipo, documento_id,
                    cantidad, propietario_id, usr_cre
                )
                VALUES (
                    rec.item_id, 'PARTIDA', p.partida_id,
                    v_peso_kg_por_rollo, NULL, NULL
                )
                RETURNING id INTO v_lote_id;

                INSERT INTO mes.partida_componente (
                    partida_id, lote_id, item_id, partida_paso_id,
                    cantidad_reservada, usr_cre
                )
                VALUES (
                    p.partida_id, v_lote_id, NULL, NULL,
                    v_peso_kg_por_rollo, NULL
                )
                ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

                INSERT INTO inventario.item_movimientos (
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, destino_ubicacion_id,
                    cantidad, documento_tipo, documento_id, observacion, usr_cre
                )
                VALUES (
                    v_doc_mov_id, rec.item_id, v_lote_id, v_ajuste_pos_id,
                    NULL, v_ubicacion_id,
                    v_peso_kg_por_rollo, 'PARTIDA', p.partida_id,
                    'Ingreso artificial de rollo MLR propio para partida ' || p.partida_id,
                    NULL
                );

                v_count := v_count + 1;
            END LOOP;
        END LOOP;

        RAISE NOTICE 'Done partida_id=% — % new lote(s)', p.partida_id, v_count;
    END LOOP;

    RAISE NOTICE '=== Batch complete ===';
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY MIGRATION: public.partida → client roll ingress
-- Sources  : public.partida  (guia, rollos, rib, peso_rollos, peso_rib)
-- Targets  : doc.guia_remision          (CLIENTE_ENVIO_PROCESO)
--            doc.guia_remision_detalle  (one line per lote)
--            inventario.lote            (one per physical roll, prorated weight)
--            inventario.lote_rollo_detalle
--            mes.partida_componente     (roll reservation)
--            inventario.item_movimientos (SERV_ING)
--            inventario.pesaje          (INGRESO, one per lote)
--
-- Scope    : Client-owned partidas (tercero.procedencia != 'MLR') where:
--              partida.guia IS NOT NULL  (has a real incoming transport document)
--              partida.rollos > 0 AND partida.peso_rollos > 0
--              mes.partida.estado_produccion != 'CANCELADA'
--              no rolls yet in mes.partida_componente
--
-- Weights  : peso_rollos / rollos  kg per regular roll  (prorated)
--            peso_rib    / rib     kg per rib roll       (prorated)
--
-- Guia parsing  : 'SERIE-CORRELATIVO' → split at first '-'
--                 no dash             → headless (NULL, NULL) per partida
--                 same client + guia  → reuse existing guia row (ON CONFLICT)
--
-- Idempotency   : skips partidas already present in mes.partida_componente
--
-- REVERSAL (undo this file):
--   DELETE FROM inventario.pesaje            WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo='guia_remision' AND documento_id IN (SELECT id FROM doc.guia_remision WHERE guia_remision_tipo_id=(SELECT id FROM doc.guia_remision_tipo WHERE codigo='CLIENTE_ENVIO_PROCESO') AND fyh_cre >= '<migration_date>'));
--   DELETE FROM doc.guia_remision_detalle    WHERE guia_remision_id IN (...same filter...);
--   DELETE FROM inventario.item_movimientos  WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo='guia_remision' AND documento_id IN (...));
--   DELETE FROM mes.partida_componente       WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo='guia_remision' AND documento_id IN (...));
--   DELETE FROM inventario.lote_rollo_detalle WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo='guia_remision' AND documento_id IN (...));
--   DELETE FROM inventario.lote              WHERE documento_tipo='guia_remision' AND documento_id IN (...);
--   DELETE FROM doc.guia_remision            WHERE guia_remision_tipo_id=... AND fyh_cre >= '<migration_date>';
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT DRY RUN
-- ═══════════════════════════════════════════════════════════════════════════════

-- Eligible partidas overview
SELECT
    COUNT(DISTINCT p.id)                                                        AS partidas_elegibles,
    COUNT(DISTINCT p.id) FILTER (WHERE p.guia IS NULL)                          AS sin_guia,
    COUNT(DISTINCT p.id) FILTER (WHERE POSITION('-' IN COALESCE(p.guia,''))=0
                                   AND p.guia IS NOT NULL)                      AS guia_sin_guion,
    COUNT(DISTINCT p.id) FILTER (WHERE POSITION('-' IN COALESCE(p.guia,''))>0)  AS guia_con_guion,
    SUM(p.rollos)                                                                AS total_rollos_regular,
    SUM(COALESCE(p.rib,0))                                                       AS total_rollos_rib,
    ROUND(SUM(COALESCE(p.peso_rollos,0))::NUMERIC,1)                            AS kg_regular,
    ROUND(SUM(COALESCE(p.peso_rib,0))::NUMERIC,1)                               AS kg_rib
FROM public.partida p
JOIN mes.partida mp ON mp.id = p.id
JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
WHERE p.rollos > 0
  AND p.peso_rollos > 0
  AND p.guia IS NOT NULL
  AND mp.estado_produccion != 'CANCELADA'
  AND t.procedencia IS DISTINCT FROM 'MLR'
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL
  );

-- Sample of what will be created (first 20)
SELECT
    p.id                                                    AS partida_id,
    p.guia,
    t.nombre                                                AS cliente,
    t.procedencia,
    p.rollos,
    COALESCE(p.rib,0)                                       AS rib,
    ROUND(p.peso_rollos::NUMERIC,2)                         AS peso_rollos_kg,
    ROUND(COALESCE(p.peso_rib,0)::NUMERIC,2)                AS peso_rib_kg,
    ROUND((p.peso_rollos/NULLIF(p.rollos,0))::NUMERIC,3)    AS kg_x_rollo,
    ROUND((COALESCE(p.peso_rib,0)/NULLIF(p.rib,0))::NUMERIC,3) AS kg_x_rib,
    mp.estado_produccion
FROM public.partida p
JOIN mes.partida mp ON mp.id = p.id
JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
WHERE p.rollos > 0
  AND p.peso_rollos > 0
  AND p.guia IS NOT NULL
  AND mp.estado_produccion != 'CANCELADA'
  AND t.procedencia IS DISTINCT FROM 'MLR'
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL
  )
ORDER BY p.id
LIMIT 20;

-- Guias that would be reused (same client + guia text across multiple partidas)
SELECT
    t.id                                                    AS tercero_id,
    t.nombre                                                AS cliente,
    p.guia,
    COUNT(*)                                                AS partidas_con_esta_guia
FROM public.partida p
JOIN mes.partida mp ON mp.id = p.id
JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
WHERE p.guia IS NOT NULL
  AND p.rollos > 0
  AND p.peso_rollos > 0
  AND mp.estado_produccion != 'CANCELADA'
  AND t.procedencia IS DISTINCT FROM 'MLR'
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL
  )
GROUP BY t.id, t.nombre, p.guia
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC
LIMIT 10;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — EXECUTE
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_serv_ing_imt_id   SMALLINT;
    v_guia_tipo_id      SMALLINT;
    v_alm_cru_ubi_id    INT;

    p                   RECORD;
    v_guia_id           BIGINT;
    v_serie             TEXT;
    v_corr              TEXT;

    rec                 RECORD;
    v_peso_por_rollo    NUMERIC;
    v_doc_mov_id        BIGINT;
    v_lote_id           INT;
    v_linea             SMALLINT;

    i                   INT;
    v_lotes_total       INT := 0;
    v_partidas_total    INT := 0;
BEGIN
    SELECT id INTO STRICT v_serv_ing_imt_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING';

    SELECT id INTO STRICT v_guia_tipo_id
    FROM doc.guia_remision_tipo WHERE codigo = 'CLIENTE_ENVIO_PROCESO';

    SELECT ub.id INTO STRICT v_alm_cru_ubi_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1;

    FOR p IN
        SELECT
            p.id            AS partida_id,
            p.guia,
            p.rollos,
            p.rib,
            p.peso_rollos,
            p.peso_rib,
            p.malla,
            p.ancho,
            p.rendimiento,
            p.articulo_id,
            COALESCE(p.fyh_cre_tz, p.fyh_cre::TIMESTAMPTZ) AS fyh_cre,
            t.id            AS tercero_id
        FROM public.partida p
        JOIN mes.partida mp ON mp.id = p.id
        JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
        WHERE p.rollos > 0
          AND p.peso_rollos > 0
          AND p.guia IS NOT NULL
          AND mp.estado_produccion != 'CANCELADA'
          AND t.procedencia IS DISTINCT FROM 'MLR'
          AND NOT EXISTS (
              SELECT 1 FROM mes.partida_componente pc
              WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL
          )
        ORDER BY p.id
    LOOP
        -- ── Parse guia serie/correlativo ─────────────────────────────────────
        IF POSITION('-' IN p.guia) > 0 THEN
            v_serie := SPLIT_PART(p.guia, '-', 1);
            v_corr  := SUBSTRING(p.guia FROM POSITION('-' IN p.guia) + 1);
        ELSE
            v_serie := NULL;
            v_corr  := NULL;
        END IF;

        -- ── Create or find guia header ────────────────────────────────────────
        v_guia_id := NULL;

        IF v_serie IS NOT NULL THEN
            INSERT INTO doc.guia_remision (
                guia_remision_tipo_id, tercero_id, serie, correlativo,
                fecha_emision, fyh_cre
            )
            VALUES (v_guia_tipo_id, p.tercero_id, v_serie, v_corr, p.fyh_cre, p.fyh_cre)
            ON CONFLICT (tercero_id, serie, correlativo, guia_remision_tipo_id) DO NOTHING
            RETURNING id INTO v_guia_id;

            IF v_guia_id IS NULL THEN
                SELECT id INTO v_guia_id
                FROM doc.guia_remision
                WHERE guia_remision_tipo_id = v_guia_tipo_id
                  AND tercero_id            = p.tercero_id
                  AND serie                 = v_serie
                  AND correlativo           = v_corr;
            END IF;
        ELSE
            -- Headless: always a new guia (NULLs never match UNIQUE)
            INSERT INTO doc.guia_remision (
                guia_remision_tipo_id, tercero_id, serie, correlativo,
                fecha_emision, fyh_cre
            )
            VALUES (v_guia_tipo_id, p.tercero_id, NULL, NULL, p.fyh_cre, p.fyh_cre)
            RETURNING id INTO v_guia_id;
        END IF;

        -- Get current max linea for this guia (for sequencing detalle lines)
        SELECT COALESCE(MAX(linea), 0)
        INTO v_linea
        FROM doc.guia_remision_detalle
        WHERE guia_remision_id = v_guia_id;

        -- ── Create one lote per roll, per item type (regular + rib) ──────────
        FOR rec IN
            SELECT
                ird.item_id,
                CASE WHEN ird.flg_rib THEN COALESCE(p.rib, 0)
                                      ELSE p.rollos END              AS n_rollos,
                CASE WHEN ird.flg_rib
                     THEN COALESCE(p.peso_rib, 0) / NULLIF(p.rib, 0)
                     ELSE p.peso_rollos            / NULLIF(p.rollos, 0)
                END                                                  AS peso_por_rollo,
                ird.flg_rib
            FROM item_rollo_detalle ird
            WHERE ird.articulo_id = p.articulo_id
              AND (ird.flg_rib = false
                   OR (ird.flg_rib = true AND COALESCE(p.rib, 0) > 0))
        LOOP
            IF rec.peso_por_rollo IS NULL OR rec.n_rollos = 0 THEN
                CONTINUE;
            END IF;

            v_doc_mov_id := nextval('inventario.mov_doc_seq');

            FOR i IN 1 .. rec.n_rollos LOOP

                -- 1. lote
                INSERT INTO inventario.lote (
                    item_id, cantidad, propietario_id,
                    documento_tipo, documento_id,
                    usr_cre, fyh_cre
                )
                VALUES (
                    rec.item_id,
                    ROUND(rec.peso_por_rollo::NUMERIC, 4),
                    p.tercero_id,
                    'guia_remision',
                    v_guia_id,
                    NULL,
                    p.fyh_cre
                )
                RETURNING id INTO v_lote_id;

                -- 2. lote_rollo_detalle
                INSERT INTO inventario.lote_rollo_detalle (
                    lote_id, guia_remision_id, origen_lote_id,
                    ancho, malla, rendimiento,
                    flg_tenido, flg_antipilling
                )
                VALUES (
                    v_lote_id, v_guia_id, NULL,
                    p.ancho, p.malla, p.rendimiento,
                    false, false
                );

                -- 3. partida_componente reservation
                INSERT INTO mes.partida_componente (
                    partida_id, lote_id, item_id, partida_paso_id,
                    cantidad_reservada, usr_cre
                )
                VALUES (
                    p.partida_id, v_lote_id, NULL, NULL,
                    ROUND(rec.peso_por_rollo::NUMERIC, 4), NULL
                )
                ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

                -- 4. SERV_ING movement
                INSERT INTO inventario.item_movimientos (
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    destino_ubicacion_id, cantidad,
                    documento_tipo, documento_id,
                    observacion, usr_cre, fyh_cre, fecha_hora
                )
                VALUES (
                    v_doc_mov_id,
                    rec.item_id, v_lote_id, v_serv_ing_imt_id,
                    v_alm_cru_ubi_id,
                    ROUND(rec.peso_por_rollo::NUMERIC, 4),
                    'guia_remision', v_guia_id,
                    'Migración: ingreso rollo cliente partida ' || p.partida_id,
                    NULL, p.fyh_cre, p.fyh_cre
                );

                -- 5. guia_remision_detalle (one line per physical roll)
                v_linea := v_linea + 1;
                INSERT INTO doc.guia_remision_detalle (
                    guia_remision_id, linea, item_id, lote_id, cantidad, n_rollos
                )
                VALUES (v_guia_id, v_linea, rec.item_id, v_lote_id,
                        ROUND(rec.peso_por_rollo::NUMERIC, 4), 1);

                -- 6. pesaje INGRESO (weighing gate — each roll treated as weighed)
                INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, observacion, usr_cre, fyh_cre)
                VALUES (
                    v_lote_id, 'INGRESO',
                    ROUND(rec.peso_por_rollo::NUMERIC, 4),
                    'Migración: peso prorrateado de partida ' || p.partida_id,
                    NULL, p.fyh_cre
                )
                ON CONFLICT (lote_id) DO NOTHING;

                v_lotes_total := v_lotes_total + 1;
            END LOOP;
        END LOOP;

        v_partidas_total := v_partidas_total + 1;

        IF v_partidas_total % 100 = 0 THEN
            RAISE NOTICE '  % partidas procesadas, % lotes creados hasta ahora',
                v_partidas_total, v_lotes_total;
        END IF;

    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE 'RESUMEN: % partidas procesadas, % lotes creados',
        v_partidas_total, v_lotes_total;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — POST-MIGRATION VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Counts by type
SELECT
    'lotes_creados'       AS metrica,
    COUNT(*)              AS valor
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN doc.guia_remision gr ON gr.id = lrd.guia_remision_id
WHERE gr.guia_remision_tipo_id = (SELECT id FROM doc.guia_remision_tipo WHERE codigo='CLIENTE_ENVIO_PROCESO')
UNION ALL
SELECT 'guias_creadas', COUNT(DISTINCT gr.id)
FROM doc.guia_remision gr
WHERE gr.guia_remision_tipo_id = (SELECT id FROM doc.guia_remision_tipo WHERE codigo='CLIENTE_ENVIO_PROCESO')
  AND NOT EXISTS (SELECT 1 FROM doc.guia_remision_detalle grd WHERE grd.guia_remision_id = gr.id AND grd.fyh_cre < '2026-01-01')
UNION ALL
SELECT 'partidas_sin_componente', COUNT(DISTINCT p.id)
FROM public.partida p
JOIN mes.partida mp ON mp.id = p.id
JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
WHERE p.rollos > 0 AND p.peso_rollos > 0 AND p.guia IS NOT NULL
  AND mp.estado_produccion != 'CANCELADA'
  AND t.procedencia IS DISTINCT FROM 'MLR'
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL
  );

-- Rolls with missing pesaje (should be zero)
SELECT COUNT(*) AS lotes_sin_pesaje
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE l.documento_tipo = 'guia_remision'
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje ps WHERE ps.lote_id = l.id);

-- Sample of created guias + roll counts
SELECT
    gr.id   AS guia_id,
    t.nombre AS cliente,
    gr.serie,
    gr.correlativo,
    gr.fecha_emision::date,
    COUNT(DISTINCT grd.lote_id) AS rollos,
    ROUND(SUM(grd.cantidad),2)  AS kg_total
FROM doc.guia_remision gr
JOIN tercero t ON t.id = gr.tercero_id
JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
WHERE gr.guia_remision_tipo_id = (SELECT id FROM doc.guia_remision_tipo WHERE codigo='CLIENTE_ENVIO_PROCESO')
GROUP BY gr.id, t.nombre, gr.serie, gr.correlativo, gr.fecha_emision
ORDER BY gr.id DESC
LIMIT 20;

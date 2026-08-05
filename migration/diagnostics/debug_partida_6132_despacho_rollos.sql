-- Partida 6132: dispatch UI shows more rolls pending than expected.
--
-- Working hypothesis: get_despacho_partida (funciones/despacho.sql:105) builds
-- its items[] by joining inventario.vw_stock_lotes_ubicacion, which is keyed
-- per (lote_id, ubicacion_id) — NOT per lote. inventario.lote_saldo allows a
-- lote to have balances in more than one ubicacion at once (UNIQUE NULLS NOT
-- DISTINCT (lote_id, ubicacion_id), migration/05_new_tables_foundation.sql:425).
-- If any dyed roll's stock for this partida is split across 2+ locations,
-- roll_count (COUNT(*)) and items (jsonb_agg) both duplicate that roll — one
-- row per ubicacion — even though vw_despacho_pendiente's own listing count
-- (COUNT(DISTINCT l.id)) is correct. That would explain a mismatch between
-- the listing count and what the detail screen actually shows.
--
-- Step 1 — reproduce the listing view's count for this partida (ground truth).
SELECT
    p.id AS partida_id,
    COUNT(DISTINCT l.id)                            AS rolls_pendientes_distinct,
    ROUND(SUM(sa.cantidad_disponible)::NUMERIC, 2)  AS kg_pendientes
FROM mes.partida p
JOIN mes.partida_paso pp            ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                    AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
JOIN inventario.lote_rollo_detalle lrd
    ON  lrd.lote_id    = l.id
    AND lrd.flg_tenido  = true
JOIN inventario.vw_stock_lotes sa   ON sa.lote_id = l.id
WHERE p.id = 6132
  AND l.estado_calidad = 'APROBADO'
GROUP BY p.id;

-- Step 2 — reproduce get_despacho_partida's row count (per lote+ubicacion,
-- what the dispatch detail screen actually renders as "items"/rolls).
SELECT
    COUNT(*)                                        AS rows_lote_x_ubicacion,
    COUNT(DISTINCT l.id)                             AS distinct_lotes,
    ROUND(SUM(sa.cantidad_disponible)::NUMERIC, 2)  AS kg_total
FROM mes.partida_paso pp
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                    AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
JOIN inventario.lote_rollo_detalle lrd
    ON  lrd.lote_id    = l.id
    AND lrd.flg_tenido  = true
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE pp.partida_id = 6132
  AND l.estado_calidad = 'APROBADO';

-- Step 3 — if rows_lote_x_ubicacion > distinct_lotes above, this lists exactly
-- which lotes are split across locations (the duplicated rows).
SELECT
    l.id AS lote_id,
    l.item_id,
    sa.ubicacion_id,
    sa.cantidad_disponible,
    lrd.color_x_cliente_id,
    lrd.ancho
FROM mes.partida_paso pp
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                    AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
JOIN inventario.lote_rollo_detalle lrd
    ON  lrd.lote_id    = l.id
    AND lrd.flg_tenido  = true
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE pp.partida_id = 6132
  AND l.estado_calidad = 'APROBADO'
  AND l.id IN (
    SELECT l2.id
    FROM mes.partida_paso pp2
    JOIN mes.partida_paso_ejecucion pe2 ON pe2.partida_paso_id = pp2.id
                                         AND pe2.estado = 'COMPLETADO'
    JOIN inventario.lote l2
        ON  l2.documento_tipo = 'partida_paso_ejecucion'
        AND l2.documento_id   = pe2.id
    JOIN inventario.vw_stock_lotes_ubicacion sa2 ON sa2.lote_id = l2.id
    WHERE pp2.partida_id = 6132
    GROUP BY l2.id
    HAVING COUNT(*) > 1
)
ORDER BY l.id, sa.ubicacion_id;

-- Step 4 — sanity check: does this partida include rework/reproceso children
-- (a second producing partida whose output also routes here) — another way
-- "more rolls than expected" can show up, distinct from the split-location bug.
SELECT
    p.id AS partida_id, p.numero, p.tercero_id, p.color_x_cliente_id,
    pp.id AS partida_paso_id, pp.partida_id AS root_partida_id
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.partida_id = p.id
WHERE p.id = 6132 OR pp.partida_id = 6132;

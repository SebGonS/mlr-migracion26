-- ============================================================================
-- DIAGNOSTIC: do partidas 4577, 4918, 5090, 4388 have production output and a
-- dispatch (entrega) record? Context: they are being returned and must be
-- re-ingressed for rework under the appropriate entrega.
-- Read-only. Run each block independently (or all at once).
-- ============================================================================

-- ── 1. Partida header + state ───────────────────────────────────────────────
SELECT
    p.id                                                        AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                  AS codigo,
    p.estado_produccion,
    p.tercero_id,
    t.nombre                                                    AS cliente,
    p.fecha_acordada
FROM mes.partida p
JOIN tercero t ON t.id = p.tercero_id
WHERE p.id IN (4577, 4918, 5090, 4388)
ORDER BY p.id;


-- ── 2. Production output — completed ejecuciones and the output lotes they made
SELECT
    p.id                                            AS partida_id,
    pp.id                                           AS partida_paso_id,
    pp.secuencia                                    AS paso_orden,
    pe.id                                           AS ejecucion_id,
    pe.estado                                       AS ejecucion_estado,
    pe.peso_kg,
    pe.cantidad_rollos,
    COUNT(DISTINCT l.id)                            AS lotes_salida,
    COUNT(DISTINCT l.id) FILTER (WHERE lrd.flg_tenido) AS lotes_tenidos,
    ROUND(SUM(l.cantidad)::NUMERIC, 2)              AS kg_salida
FROM mes.partida p
JOIN mes.partida_paso pp           ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
LEFT JOIN inventario.lote l
       ON l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id   = pe.id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE p.id IN (4577, 4918, 5090, 4388)
GROUP BY p.id, pp.id, pp.secuencia, pe.id, pe.estado, pe.peso_kg, pe.cantidad_rollos
ORDER BY p.id, pp.secuencia, pe.id;


-- ── 3. Current stock of those output lotes (what is still available vs gone) ──
SELECT
    p.id                                   AS partida_id,
    l.id                                   AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100
        || '-' || LPAD(l.secuencia::text, 5, '0')              AS lote_codigo,
    l.propietario_id,
    lrd.flg_tenido,
    ROUND(l.cantidad::NUMERIC, 2)          AS kg_lote,
    ROUND(sa.cantidad_disponible::NUMERIC, 2) AS kg_disponible
FROM mes.partida p
JOIN mes.partida_paso pp           ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN inventario.lote l
       ON l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id   = pe.id
LEFT JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id
LEFT JOIN inventario.vw_stock_lotes sa       ON sa.lote_id  = l.id
WHERE p.id IN (4577, 4918, 5090, 4388)
ORDER BY p.id, l.id;


-- ── 3b. Raw lote_saldo + item_movimientos for 5090 lotes (diagnose NULL disponible) ──
SELECT
    ls.lote_id,
    ls.ubicacion_id,
    ls.cantidad_actual,
    im.documento_tipo,
    im.documento_id,
    im.cantidad,
    im.origen_ubicacion_id,
    im.destino_ubicacion_id,
    im.fyh_cre
FROM inventario.lote_saldo ls
RIGHT JOIN (
    SELECT id FROM inventario.lote
    WHERE documento_tipo = 'partida_paso_ejecucion'
      AND documento_id   = 1851  -- ejecucion_id for 5090 paso 1
) l ON l.id = ls.lote_id
LEFT JOIN inventario.item_movimientos im ON im.lote_id = l.id
ORDER BY l.id, im.fyh_cre;


-- ── 4. Dispatch (entrega) records — entregas whose lines reference those output lotes
SELECT
    p.id                                   AS partida_id,
    gr.id                                  AS entrega_id,
    grt.codigo                             AS entrega_tipo,
    gr.serie,
    gr.correlativo,
    gr.fecha_emision,
    gr.tercero_id,
    gr.fyh_elm,
    (gr.fyh_elm IS NOT NULL)               AS entrega_anulada,
    COUNT(grd.id)                          AS lineas,
    SUM(grd.n_rollos)                      AS rollos_declarados,
    ROUND(SUM(grd.cantidad)::NUMERIC, 2)   AS kg_despachados
FROM mes.partida p
JOIN mes.partida_paso pp           ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN inventario.lote l
       ON l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id   = pe.id
JOIN doc.entrega_detalle grd ON grd.lote_id = l.id
JOIN doc.entrega gr          ON gr.id = grd.entrega_id
JOIN doc.entrega_tipo grt    ON grt.id = gr.entrega_tipo_id
WHERE p.id IN (4577, 4918, 5090, 4388)
GROUP BY p.id, gr.id, grt.codigo, gr.serie, gr.correlativo,
         gr.fecha_emision, gr.tercero_id, gr.fyh_elm
ORDER BY p.id, gr.fecha_emision;

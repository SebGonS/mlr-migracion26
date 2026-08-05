-- Diagnostic: why doesn't partida/roll X show up in doc.vw_despacho_pendiente
-- ("pending to dispatch" list, funciones/despacho.sql)?
--
-- doc.vw_despacho_pendiente requires ALL of the following per lote to count
-- toward a partida's pending kg, and the partida itself only appears if the
-- sum across its dyed lotes is > 0:
--   1. pe.estado = 'COMPLETADO'            (partida_paso_ejecucion that produced the lote)
--   2. lrd.flg_tenido = true               (dyed rolls only — raw/crudo never shows here)
--   3. l.estado_calidad = 'APROBADO'       (PENDIENTE/REPROCESO/BAJA excluded)
--   4. inventario.vw_stock_lotes has a row with cantidad_disponible > 0 for the lote
--   5. lote must be reachable via partida_paso -> partida_paso_ejecucion -> lote
--      (documento_tipo='partida_paso_ejecucion') and lote_rollo_detalle must exist
--
-- EDIT THE TWO NUMBERS BELOW then run each query (no psql, plain literals):
--   partida_id : the partida you're investigating (0 if you only have a lote_id)
--   lote_id    : a specific roll id (0 if you only have a partida_id)

-- ==> SET THESE <==
--   partida_id = 6223
--   lote_id    = 5678

-- 1. Does the partida even show up in the view? (should be empty if the bug is real)
SELECT * FROM doc.vw_despacho_pendiente WHERE partida_id = 6223;

-- 2. All dyed-output lotes for the partida, with every gating condition evaluated
--    side-by-side so you can see exactly which one fails.
SELECT
    l.id                    AS lote_id,
    l.estado_calidad,
    l.documento_tipo,
    l.documento_id,
    pp.id                   AS partida_paso_id,
    pp.partida_id,
    pe.id                   AS ejecucion_id,
    pe.estado               AS ejecucion_estado,
    (pe.estado = 'COMPLETADO')                         AS ok_ejecucion_completado,
    lrd.flg_tenido,
    (lrd.flg_tenido IS TRUE)                            AS ok_tenido,
    (l.estado_calidad = 'APROBADO')                     AS ok_calidad_aprobado,
    sa.cantidad_disponible,
    (COALESCE(sa.cantidad_disponible, 0) > 0)           AS ok_stock_disponible
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion pe
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
JOIN mes.partida_paso pp            ON pp.id = pe.partida_paso_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
LEFT JOIN inventario.vw_stock_lotes sa      ON sa.lote_id  = l.id
WHERE pp.partida_id = 6223
ORDER BY l.id;

-- 3. If a specific lote_id was given: same breakdown for just that roll,
--    plus raw lote/lrd/saldo so you can see actual stock numbers.
SELECT
    l.id AS lote_id, l.cantidad AS lote_cantidad, l.estado_calidad,
    l.documento_tipo, l.documento_id,
    lrd.flg_tenido, lrd.entrega_id,
    ls.cantidad_actual,
    sa.cantidad_disponible
FROM inventario.lote l
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
LEFT JOIN inventario.lote_saldo ls          ON ls.lote_id  = l.id
LEFT JOIN inventario.vw_stock_lotes sa      ON sa.lote_id  = l.id
WHERE l.id = 5678;

-- 4. Sanity check: does the partida exist / soft-deleted / what estado_produccion?
SELECT id, numero, estado_produccion, partida_origen_id, fyh_elm
FROM mes.partida
WHERE id = 6223;

-- 5. Cross-check against the commercial/billing view (different logic, uses
--    item_movimientos SERV_EGR/VENTA_EGR instead of vw_stock_lotes) — if this
--    disagrees with vw_despacho_pendiente, see mes.vw_partida_comercial comment
--    in migration/08_views.sql for which one is authoritative for what.
SELECT * FROM mes.vw_partida_comercial WHERE partida_id = 6223;

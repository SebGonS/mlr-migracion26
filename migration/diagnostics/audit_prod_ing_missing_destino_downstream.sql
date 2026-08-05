-- Follow-up to audit_prod_ing_missing_destino.sql.
-- Before blanket-crediting all 3521 affected dyed lotes into ALM_CRU, check
-- whether any of them ALREADY have a later movement (egress/dispatch/reproceso)
-- that assumed stock existed at some location. If so, blindly backfilling
-- ALM_CRU now could double-count or misrepresent rolls that are already gone
-- — those need manual review, not the blanket credit.

-- 1. Split affected dyed PROD_ING lotes into "clean" (no other movement at all
--    besides the broken PROD_ING) vs "has downstream activity" (needs review).
WITH affected AS (
    SELECT im.lote_id, im.id AS prod_ing_movimiento_id, im.fyh_cre AS prod_ing_fecha
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
    WHERE imt.codigo = 'PROD_ING'
      AND im.origen_ubicacion_id IS NULL
      AND im.destino_ubicacion_id IS NULL
)
SELECT
    a.lote_id,
    COUNT(im2.id)                                      AS otros_movimientos,
    BOOL_OR(im2.origen_ubicacion_id IS NOT NULL
            OR im2.destino_ubicacion_id IS NOT NULL)    AS tiene_movimiento_con_ubicacion,
    STRING_AGG(DISTINCT imt2.codigo, ', ')              AS tipos_movimiento
FROM affected a
LEFT JOIN inventario.item_movimientos im2
    ON  im2.lote_id = a.lote_id
    AND im2.id <> a.prod_ing_movimiento_id
LEFT JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
GROUP BY a.lote_id
ORDER BY otros_movimientos DESC;

-- 2. Summary: how many are clean vs need review.
WITH affected AS (
    SELECT im.lote_id, im.id AS prod_ing_movimiento_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
    WHERE imt.codigo = 'PROD_ING'
      AND im.origen_ubicacion_id IS NULL
      AND im.destino_ubicacion_id IS NULL
),
per_lote AS (
    SELECT
        a.lote_id,
        COUNT(im2.id) AS otros_movimientos
    FROM affected a
    LEFT JOIN inventario.item_movimientos im2
        ON  im2.lote_id = a.lote_id
        AND im2.id <> a.prod_ing_movimiento_id
    GROUP BY a.lote_id
)
SELECT
    COUNT(*) FILTER (WHERE otros_movimientos = 0)  AS lotes_limpios_solo_prod_ing,
    COUNT(*) FILTER (WHERE otros_movimientos > 0)  AS lotes_con_actividad_posterior,
    COUNT(*)                                        AS total
FROM per_lote;

-- 3. Also: current estado_calidad + partida estado for the affected lotes,
--    grouped, to see if any belong to partidas that are already TECO/CERRADA
--    (a roll from a closed partida getting a fresh stock credit today is a
--    stronger signal something is off vs. one still EN_PRODUCCION).
WITH affected AS (
    SELECT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
    WHERE imt.codigo = 'PROD_ING'
      AND im.origen_ubicacion_id IS NULL
      AND im.destino_ubicacion_id IS NULL
)
SELECT
    p.estado_produccion,
    l.estado_calidad,
    COUNT(*) AS lotes
FROM affected a
JOIN inventario.lote l ON l.id = a.lote_id
JOIN mes.partida_paso_ejecucion pe ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
GROUP BY p.estado_produccion, l.estado_calidad
ORDER BY lotes DESC;

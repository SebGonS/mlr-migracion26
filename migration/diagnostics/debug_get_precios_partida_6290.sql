-- ═══════════════════════════════════════════════════════════════
-- Why does doc.get_precios_partida(ARRAY[6290]) return zero rows?
-- Checks both required conditions independently.
-- ═══════════════════════════════════════════════════════════════

-- 1) Does the partida have any assigned rolls? (partidas CTE requirement)
--    Zero rows here = get_precios_partida excludes the partida entirely.
SELECT opi.id, opi.lote_id, opi_l.id AS lote_ok, ird.item_id, ar.id AS articulo_id, ar.fibra
FROM mes.partida_componente opi
LEFT JOIN inventario.lote opi_l      ON opi_l.id = opi.lote_id
LEFT JOIN item_rollo_detalle ird     ON ird.item_id = opi_l.item_id
LEFT JOIN articulo ar                ON ar.id = ird.articulo_id
WHERE opi.partida_id = 6290
  AND opi.lote_id IS NOT NULL;

-- 2) Does the partida have any COMPLETADO paso ejecucion? (lineas CTE requirement)
--    Zero rows here = operacion_ids is an empty array, no price lines generated.
SELECT pp.id AS partida_paso_id, pp.operacion_id, op.nombre AS operacion,
       pe.id AS ejecucion_id, pe.estado
FROM mes.partida_paso pp
JOIN mes.operacion op ON op.id = pp.operacion_id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE pp.partida_id = 6290
ORDER BY pp.id, pe.id;

-- 3) Direct call to the RPC itself for comparison
SELECT * FROM doc.get_precios_partida(ARRAY[6290]::BIGINT[]);



SELECT CASE WHEN COALESCE(saldo,0) > 0 THEN 'en stock' ELSE 'consumido' END AS estado,
       COUNT(*) AS n_rollos
FROM (
    SELECT l.id, SUM(ls.cantidad_actual) AS saldo
    FROM inventario.lote l
    JOIN item_rollo_detalle ird       ON ird.item_id = l.item_id
    LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
    WHERE ird.articulo_id = 28
    GROUP BY l.id
) x
GROUP BY 1;

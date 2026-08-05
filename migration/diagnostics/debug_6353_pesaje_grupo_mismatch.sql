-- Why does registrar_pesaje_grupo (called from frontend) not clear the
-- pesaje guard on partida 6353's 14 output rolls (169325-169338)?
--
-- registrar_pesaje_grupo groups strictly by (partida_id, item_id, flg_rib,
-- entrega_id) via lote_rollo_detalle.entrega_id. If the frontend sends an
-- entrega_id/item_id combo that doesn't exactly match what these rolls
-- carry, the function matches 0 rows and RAISEs *before* it reaches the
-- logs_api insert -- so a failed call leaves no log trail.
--
-- READ ONLY. Run on a fresh connection.

-- 1) What (item_id, flg_rib, entrega_id) groups actually exist among
--    6353's 14 components -- these are the exact params a successful
--    registrar_pesaje_grupo call needs.
SELECT
    pc.lote_id, l.item_id, ird.flg_rib,
    lrd.entrega_id, lrd.origen_lote_id,
    l.cantidad
FROM mes.partida_componente pc
JOIN inventario.lote l               ON l.id = pc.lote_id
JOIN item_rollo_detalle ird          ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = 6353
ORDER BY l.item_id, ird.flg_rib, pc.lote_id;

-- 2) Distinct groups summary -- how many registrar_pesaje_grupo calls
--    you actually need (one per row here) and the exact params for each.
SELECT
    l.item_id, ird.flg_rib, lrd.entrega_id,
    COUNT(*) AS n_rollos, SUM(l.cantidad) AS peso_actual_total
FROM mes.partida_componente pc
JOIN inventario.lote l               ON l.id = pc.lote_id
JOIN item_rollo_detalle ird          ON ird.item_id = l.item_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = 6353
GROUP BY l.item_id, ird.flg_rib, lrd.entrega_id
ORDER BY 1,2,3;

-- 3) Any recent registrar_pesaje_grupo calls logged for partida 6353
--    (only appears if the call got PAST the "no rolls found" guard --
--    i.e. it matched something. If this is empty, every attempt so far
--    raised before logging, meaning 0 rows matched every time.)
SELECT id, called_at, user_id, params
FROM logs_api
WHERE function_name = 'registrar_pesaje_grupo'
  AND params->>'partida_id' = '6353'
ORDER BY called_at DESC
LIMIT 20;

-- 4) PROD_CONSUMO guard check -- would any of these 14 rolls make
--    registrar_pesaje_grupo raise "ya tienen movimientos de producción"?
SELECT pc.lote_id, im.id AS mov_id, imt.codigo
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
JOIN inventario.item_movimientos im ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE pc.partida_id = 6353 AND imt.codigo = 'PROD_CONSUMO';

-- 5) Fresh guard re-check (same as before) -- has anything changed?
SELECT pc.lote_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6353
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);

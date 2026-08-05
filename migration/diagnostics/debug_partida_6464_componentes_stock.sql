-- Check item 301's flg_rib -- registrar_pesaje_grupo joins on
-- item_rollo_detalle.flg_rib = p_flg_rib, so if item 301 is actually rib,
-- passing false finds zero rows ("No se encontraron rollos para el grupo").
SELECT item_id, flg_rib
FROM item_rollo_detalle
WHERE item_id = 301;

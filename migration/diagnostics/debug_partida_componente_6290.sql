-- Why does mes.partida_componente have no lote_id row for partida 6290,
-- despite the partida having completed 5 production steps?

-- 1) Any partida_componente rows at all (even with lote_id NULL)?
SELECT * FROM mes.partida_componente WHERE partida_id = 6290;

-- 2) Where did the input rolls actually come from? Check item_movimientos
--    for PROD_ING / PARTIDA-scoped movements tied to this partida.
SELECT im.id, im.documento_tipo, im.documento_id, im.tipo_id,
       im.lote_id, im.fyh_cre
FROM inventario.item_movimientos im
WHERE im.documento_tipo = 'PARTIDA' AND im.documento_id = 6290
ORDER BY im.fyh_cre;

-- 3) Was pesaje ever registered for this partida's rolls?
SELECT pz.*
FROM inventario.pesaje pz
JOIN inventario.item_movimientos im
  ON im.lote_id = pz.lote_id AND im.documento_tipo = 'PARTIDA' AND im.documento_id = 6290;

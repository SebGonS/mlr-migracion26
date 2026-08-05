-- corregir_pesaje_produccion self-reported "0 pesos corregidos" (its
-- return message uses the REAL final UPDATE row count, so this is
-- trustworthy: its `rolls` CTE matched 0 rows). registrar_pesaje_grupo's
-- "success" message is NOT trustworthy the same way -- it always prints
-- the pre-computed candidate count, not the actual rows written -- so a
-- prior "success" there could equally have written nothing.
--
-- Both functions (and actualizar_pesos_individuales_partida) INNER JOIN
-- inventario.vw_stock_lotes_ubicacion, which is built off
-- inventario.lote_saldo WHERE cantidad_actual > 0. If these 14 rolls
-- have no positive balance row there, every weighing path silently
-- matches zero rolls no matter which function you call.
--
-- READ ONLY. Run on a fresh connection.

-- 1) Raw lote_saldo rows for these 14 lots (bypasses the view's
--    cantidad_actual > 0 filter, so we can see 0/negative/missing).
SELECT ls.lote_id, ls.ubicacion_id, ls.cantidad_actual
FROM mes.partida_componente pc
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = pc.lote_id
WHERE pc.partida_id = 6353
ORDER BY pc.lote_id, ls.ubicacion_id;

-- 2) Full movement ledger per lot, chronological -- shows every
--    ingreso/egreso and running balance so we can see what zeroed
--    (or never established) their stock position.
SELECT pc.lote_id, im.id AS mov_id, imt.codigo AS mov_tipo,
       im.origen_ubicacion_id, im.destino_ubicacion_id,
       im.cantidad, im.documento_tipo, im.documento_id, im.fyh_cre
FROM mes.partida_componente pc
JOIN inventario.item_movimientos im ON im.lote_id = pc.lote_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE pc.partida_id = 6353
ORDER BY pc.lote_id, im.fyh_cre, im.id;

-- 3) Does the view see them at all?
SELECT sa.*
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN mes.partida_componente pc ON pc.lote_id = sa.lote_id
WHERE pc.partida_id = 6353;
-- Empty result set = confirmed: these rolls are invisible to every
-- pesaje-writing function because of the stock view join.

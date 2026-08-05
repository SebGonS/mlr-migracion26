-- ============================================================================
-- Safety check before repointing the 20 rolls from 6168 (root, wrong landing
-- spot after anular_reproceso) back to 6430 (their true immediate source,
-- per logs_api id 41531: crear_reproceso partida_id=6430 -> reproceso 6470).
--
-- Confirms no committed componente row already exists on 6430 for these
-- lotes (would collide), and no movements/production happened on 6168's
-- pasos for these lotes since the wrong repoint (2026-07-24 15:09:02) that
-- would make a plain UPDATE unsafe.
-- ============================================================================

-- 1) Any existing componente rows on 6430 for these lotes already? (expect 0)
SELECT * FROM mes.partida_componente
WHERE partida_id = 6430
  AND lote_id IN (132920,132921,132922,132923,132924,132925,132926,132927,132928,132929,
                  132930,132931,132932,132933,132934,132935,132936,132937,132938,133016);

-- 2) Any movements against these lotes since the wrong repoint? (expect 0,
--    or only pre-existing PROD_CONSUMO history from before 6470 was created)
SELECT im.id, im.lote_id, imt.codigo AS mov_tipo, im.cantidad,
       im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (132920,132921,132922,132923,132924,132925,132926,132927,132928,132929,
                      132930,132931,132932,132933,132934,132935,132936,132937,132938,133016)
  AND im.fyh_cre > '2026-07-24 15:09:02.39939+00'
ORDER BY im.fyh_cre;

-- 3) 6430's own paso state — make sure nothing started production on these
--    rolls between the repoint and now that would conflict with moving the
--    reservation.
SELECT pp.id, pp.secuencia, pp.operacion_id, pp.estado,
       ppe.id AS ejecucion_id, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 6430
ORDER BY pp.secuencia, ppe.id;

-- READ ONLY · Test the claim: partida 4320's 12 rolls were DISPATCHED, RETURNED
-- (devolución), then RE-INGRESSED as new child lotes + production recorded.
-- A real return should show: SERV_DEV_ING on the raw rolls (or a devolución doc),
-- children created AFTER the return, and the children having onward life.

-- §1 · Full movement ledger of the 12 raw rolls — is there a SERV_DEV_ING / return?
SELECT im.lote_id, im.id AS mov_id, imt.codigo AS mov, imt.factor,
       im.cantidad, im.documento_tipo, im.documento_id, im.fecha_hora
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
WHERE im.lote_id BETWEEN 84802 AND 84813
ORDER BY im.lote_id, im.fecha_hora, im.id;

-- §2 · Full movement ledger of the 12 CHILD lotes — onward life? created when?
SELECT im.lote_id, im.id AS mov_id, imt.codigo AS mov, imt.factor,
       im.cantidad, im.documento_tipo, im.documento_id, im.fecha_hora,
       l.fyh_cre AS child_lote_created
FROM inventario.lote l
JOIN inventario.item_movimientos im ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
WHERE l.id BETWEEN 131340 AND 131351
ORDER BY im.lote_id, im.fecha_hora, im.id;

-- §3 · Is 4320 a rework/child partida, and does any partida reference it as origen?
SELECT p.id, p.partida_origen_id, p.estado_produccion, p.fyh_cre,
       (SELECT COUNT(*) FROM mes.partida ch WHERE ch.partida_origen_id = p.id) AS n_child_partidas
FROM mes.partida p WHERE p.id = 4320;

-- §4 · Chronology summary: does every child's creation post-date its parent's SERV_EGR?
SELECT
    COUNT(*) AS pairs,
    COUNT(*) FILTER (WHERE child.fyh_cre > egr.fecha_hora) AS child_after_dispatch,
    COUNT(*) FILTER (WHERE child.fyh_cre <= egr.fecha_hora) AS child_before_or_at_dispatch
FROM inventario.lote_rollo_detalle clrd
JOIN inventario.lote child ON child.id = clrd.lote_id
JOIN LATERAL (SELECT MIN(im.fecha_hora) AS fecha_hora FROM inventario.item_movimientos im
             JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
             WHERE im.lote_id = clrd.origen_lote_id) egr ON true
WHERE clrd.origen_lote_id BETWEEN 84802 AND 84813;

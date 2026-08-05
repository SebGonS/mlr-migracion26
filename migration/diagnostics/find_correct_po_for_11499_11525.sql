-- ============================================================================
-- Find the correct PO for entregas 11499 (120kg SILICONA, item 198) and
-- 11525 (625kg TRITON, item 6) — likely one of the compras created in the
-- same rapid-fire session as the (mistaken) reconciliation to compra 1014.
-- ============================================================================

-- 0) Companion reconciliar_entrega_compra call (40171) — what did it link? ----
SELECT id, function_name, called_at, params FROM logs_api WHERE id = 40171;

-- 1) entrega 11500 (EG07-918) — same-day sibling of 11499. What item/qty,
--    and is it linked to any compra?
SELECT ed.entrega_id, ed.id AS detalle_id, ed.item_id, i.nombre, ed.cantidad, ed.compra_detalle_id
FROM doc.entrega_detalle ed JOIN item i ON i.id = ed.item_id
WHERE ed.entrega_id = 11500;

SELECT * FROM doc.compra_entrega WHERE entrega_id = 11500;

-- 2) All compras created by user 18 on 2026-07-13 in that batch window
--    (22:05–22:18), with their item lines and pending balance
SELECT c.id AS compra_id, c.fyh_cre,
       cd.id AS compra_detalle_id, cd.item_id, i.nombre,
       cd.cantidad AS ordenada, cd.cantidad_recibida,
       (cd.cantidad - cd.cantidad_recibida) AS pendiente
FROM doc.compra c
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i ON i.id = cd.item_id
WHERE c.usr_cre = 18
  AND c.fyh_cre BETWEEN '2026-07-13 22:00:00' AND '2026-07-13 22:20:00'
ORDER BY c.fyh_cre, cd.id;

-- 3) All compras created by user 18 on 2026-07-14/15/16 in the batch windows
--    around the second reconciliation (11525, item 6 TRITON, 625kg)
SELECT c.id AS compra_id, c.fyh_cre,
       cd.id AS compra_detalle_id, cd.item_id, i.nombre,
       cd.cantidad AS ordenada, cd.cantidad_recibida,
       (cd.cantidad - cd.cantidad_recibida) AS pendiente
FROM doc.compra c
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i ON i.id = cd.item_id
WHERE c.usr_cre = 18
  AND c.fyh_cre BETWEEN '2026-07-14 22:00:00' AND '2026-07-16 15:00:00'
ORDER BY c.fyh_cre, cd.id;

-- 4) Broader net: ANY compra for tercero 184 (any date, not anulada) with a
--    still-pending line for item 198 (SILICONA) or item 6 (TRITON) — in case
--    the correct target predates the 07-13 batch entirely
SELECT c.id AS compra_id, c.fyh_cre, c.fyh_elm,
       cd.id AS compra_detalle_id, cd.item_id, i.nombre,
       cd.cantidad AS ordenada, cd.cantidad_recibida,
       (cd.cantidad - cd.cantidad_recibida) AS pendiente
FROM doc.compra c
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i ON i.id = cd.item_id
WHERE c.tercero_id = 184
  AND c.fyh_elm IS NULL
  AND cd.item_id IN (6, 198)
  AND cd.cantidad_recibida < cd.cantidad
ORDER BY c.fyh_cre;

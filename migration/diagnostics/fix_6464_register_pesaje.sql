-- ============================================================================
-- FIX: register pesaje for 6464's 4 componente rolls (122749-122752). These
-- are dyed output rolls (PROD_ING from root 5090's paso 3) reused as rework
-- input -- they never went through a raw-material weighing flow, so
-- generar_receta's pesaje gate blocks them. Weight unchanged: total = sum of
-- existing lote.cantidad (4 x 22.65 = 90.6kg), regular rolls (flg_rib=false).
-- ============================================================================

-- 0) Sanity check: confirm these are the only 4 componentes of 6464 and see
--    their origin entrega (expected NULL -- MLR-produced dyed output, not an
--    ingress guía).
SELECT l.id AS lote_id, l.item_id, l.cantidad, lrd.entrega_id AS origen_lote_entrega_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = 6464;

-- 1) Register the weigh (total unchanged from current sum).
SELECT inventario.registrar_pesaje_grupo(
    6464,
    (SELECT DISTINCT lrd.entrega_id
     FROM mes.partida_componente pc
     JOIN inventario.lote l ON l.id = pc.lote_id
     LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
     WHERE pc.partida_id = 6464),
    (SELECT DISTINCT l.item_id
     FROM mes.partida_componente pc
     JOIN inventario.lote l ON l.id = pc.lote_id
     WHERE pc.partida_id = 6464),
    true,
    90.6
);

-- 2) Confirm the pesaje guard clears.
SELECT pc.lote_id
FROM mes.partida_componente pc
WHERE pc.partida_id = 6464
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows.

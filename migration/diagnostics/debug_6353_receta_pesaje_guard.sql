-- Why does generar_receta for partida 6353 still say
-- "Todos los rollos deben estar pesados antes de generar la receta"
-- despite weights already being registered?
--
-- Hypothesis: mes.partida_componente for 6353 still references a lote_id
-- that was later soft-deleted (split/replaced/double-spent) and therefore
-- can never receive an inventario.pesaje row. The guard in generar_receta
-- (funciones/mes.sql:486-498) checks ALL pc.lote_id without filtering
-- l.fyh_elm IS NULL, unlike registrar_pesaje_produccion which does filter
-- it. A stale soft-deleted component would block the guard forever.
--
-- READ ONLY. Run on a fresh connection.

-- 1) All components currently attached to partida 6353, with lot status
--    and whether each has a pesaje row.
SELECT
    pc.lote_id,
    l.fyh_elm            AS lote_soft_deleted_at,
    l.cantidad            AS lote_cantidad,
    l.estado_calidad,
    l.documento_tipo      AS lote_origen_doc_tipo,
    l.documento_id        AS lote_origen_doc_id,
    p.id                  AS pesaje_id,
    p.tipo                AS pesaje_tipo,
    p.peso_real
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.pesaje p ON p.lote_id = pc.lote_id
WHERE pc.partida_id = 6353
ORDER BY l.fyh_elm NULLS FIRST, pc.lote_id;

-- 2) Isolate exactly which component(s) trip the generar_receta guard
--    (mirrors the guard's own query, no fyh_elm filter).
SELECT pc.lote_id, l.fyh_elm AS lote_soft_deleted_at
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6353
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id
  );

-- 3) If any offending lote_id is soft-deleted, trace what replaced it
--    (movements that consumed it, and any lot(s) it produced/became).
SELECT im.id AS mov_id, imt.codigo AS mov_tipo, im.lote_id,
       im.documento_tipo, im.documento_id, im.cantidad, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (
    SELECT pc.lote_id
    FROM mes.partida_componente pc
    JOIN inventario.lote l ON l.id = pc.lote_id
    WHERE pc.partida_id = 6353 AND l.fyh_elm IS NOT NULL
)
ORDER BY im.fyh_cre;

-- 4) Sanity check: what registrar_pesaje_produccion itself would count
--    as "assigned rolls" (its own fyh_elm-filtered view). If this returns
--    rows for 6353 but query #2 above also returns rows, that confirms
--    the guard and the weighing function disagree on live components.
SELECT
    COUNT(*) FILTER (WHERE ird.flg_rib = false) AS regular_activos,
    COUNT(*) FILTER (WHERE ird.flg_rib = true)  AS rib_activos
FROM mes.partida_componente pc
JOIN inventario.lote l      ON l.id = pc.lote_id AND l.fyh_elm IS NULL
JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
WHERE pc.partida_id = 6353;

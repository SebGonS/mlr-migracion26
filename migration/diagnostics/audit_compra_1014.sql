-- ============================================================================
-- Damage assessment: compra 1014 — negative pending + over-received (header).
-- Goal: extent of ledger damage, root cause, which RPC calls / manual scripts
-- touched it.
-- ============================================================================

-- 1) Header --------------------------------------------------------------------
SELECT c.id AS compra_id, c.tercero_id, c.fyh_cre, c.fyh_elm, c.usr_cre, c.usr_mod, c.fyh_mod
FROM doc.compra c WHERE c.id = 1014;

-- 2) Lines: ordenada vs cantidad_recibida vs pendiente (computed) --------------
SELECT cd.id AS compra_detalle_id, cd.item_id, i.nombre,
       cd.cantidad AS ordenada, cd.cantidad_recibida,
       (cd.cantidad - cd.cantidad_recibida) AS pendiente,
       cd.precio_unitario
FROM doc.compra_detalle cd
JOIN item i ON i.id = cd.item_id
WHERE cd.compra_id = 1014
ORDER BY cd.id;

-- 3) All entregas linked to this compra -----------------------------------------
SELECT ce.entrega_id, e.serie, e.correlativo, et.codigo AS tipo,
       e.fecha_recepcion, e.fyh_elm, e.usr_mod, e.fyh_mod
FROM doc.compra_entrega ce
JOIN doc.entrega e ON e.id = ce.entrega_id
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE ce.compra_id = 1014
ORDER BY e.fecha_recepcion;

-- 4) All entrega_detalle lines for those entregas --------------------------------
SELECT ed.entrega_id, ed.id AS detalle_id, ed.linea, ed.item_id, i.nombre,
       ed.cantidad AS detalle_cantidad, ed.n_rollos, ed.compra_detalle_id
FROM doc.entrega_detalle ed
JOIN item i ON i.id = ed.item_id
WHERE ed.entrega_id IN (SELECT entrega_id FROM doc.compra_entrega WHERE compra_id = 1014)
ORDER BY ed.entrega_id, ed.linea;

-- 5) Full ledger for this compra's entregas — chronological, every movement ----
SELECT im.id AS mov_id, im.item_id, im.lote_id, imt.codigo AS mov_tipo,
       im.cantidad, im.precio_unitario, im.monto,
       im.origen_ubicacion_id, im.destino_ubicacion_id,
       im.documento_tipo, im.documento_id, im.documento_linea_id,
       im.fecha_hora, im.usr_cre, im.observacion
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'entrega'
  AND im.documento_id IN (SELECT entrega_id FROM doc.compra_entrega WHERE compra_id = 1014)
ORDER BY im.fecha_hora, im.id;

-- 6) Net ledger per item (factoring reversal types) vs cantidad_recibida -------
WITH ledger_neto AS (
    SELECT im.item_id,
        SUM(CASE imt.codigo
            WHEN 'COMPRA_ING'       THEN  im.cantidad
            WHEN 'DEV_PROV_EGR'     THEN -im.cantidad
            WHEN 'DEV_PROV_EGR_REV' THEN  im.cantidad
            ELSE 0
        END) AS cantidad_neta_ledger
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE im.documento_tipo = 'entrega'
      AND im.documento_id IN (SELECT entrega_id FROM doc.compra_entrega WHERE compra_id = 1014)
    GROUP BY im.item_id
)
SELECT cd.item_id, i.nombre, cd.cantidad AS ordenada, cd.cantidad_recibida AS registrado,
       COALESCE(ln.cantidad_neta_ledger, 0) AS ledger_neto,
       cd.cantidad_recibida - COALESCE(ln.cantidad_neta_ledger, 0) AS diferencia
FROM doc.compra_detalle cd
JOIN item i ON i.id = cd.item_id
LEFT JOIN ledger_neto ln ON ln.item_id = cd.item_id
WHERE cd.compra_id = 1014;

-- 7) logs_api — every RPC call touching this compra or its entregas -----------
--    (params is jsonb; search for compra_id=1014 or any linked entrega_id)
SELECT la.id, la.function_name, la.user_id, u.nombre, u.apellido, la.called_at, la.params
FROM logs_api la
LEFT JOIN usuario u ON u.id = la.user_id
WHERE la.params::text LIKE '%1014%'
   OR EXISTS (
       SELECT 1 FROM doc.compra_entrega ce
       WHERE ce.compra_id = 1014
         AND la.params::text LIKE '%"entrega_id": ' || ce.entrega_id::text || '%'
   )
ORDER BY la.called_at ;

-- 8) Broader logs_api sweep: anything referencing this compra's item_ids ------
--    (catches calls where compra_id wasn't in params but item was touched
--     directly, e.g. registrar_ajuste)
SELECT la.id, la.function_name, la.user_id, la.called_at, la.params
FROM logs_api la
WHERE la.function_name IN ('registrar_ajuste','registrar_ajuste_a_total','actualizar_entrega',
                            'anular_entrega','registrar_entrega_compra','crear_entrega',
                            'registrar_devolucion_proveedor','anular_devolucion_proveedor')
  AND la.called_at BETWEEN (SELECT fyh_cre FROM doc.compra WHERE id = 1014) - interval '1 day'
                      AND now()
  AND EXISTS (
      SELECT 1 FROM doc.compra_detalle cd
      WHERE cd.compra_id = 1014
        AND la.params::text LIKE '%' || cd.item_id::text || '%'
  )
ORDER BY la.called_at ;

-- 9) Did any of the manual diagnostic/patch scripts from this session touch
--    compra 1014 or its items? (item ids 7,135,71,69,104,210,212 were the ones
--    we manually fixed earlier — confirm 1014's items don't overlap by
--    coincidence, and check compra id itself never appeared)
SELECT cd.item_id, i.nombre FROM doc.compra_detalle cd JOIN item i ON i.id=cd.item_id
WHERE cd.compra_id = 1014;

-- ============================================================================
-- Full timeline reconstruction: compra 1014 (items 6 TRITON, 198 SILICONA)
-- and its three entregas (11463, 11499, 11525).
-- Uses jsonb key match (->>'compra_id' / ->>'entrega_id') instead of ILIKE
-- substring, to avoid false positives from small integers colliding with
-- unrelated JSON fields (e.g. color_x_cliente_id, receta_id) — that's what
-- broke the earlier broad-substring search.
-- ============================================================================

-- 1) logs_api: exact match on compra_id = 1014 in the call params ------------
SELECT la.id, la.function_name, la.user_id, u.nombre, u.apellido, la.called_at,
       la.params->>'compra_id' AS compra_id_param
FROM logs_api la
LEFT JOIN usuario u ON u.id = la.user_id
WHERE (la.params->>'compra_id')::text = '1014'
   OR (la.params->'datos'->>'compra_id')::text = '1014'
ORDER BY la.called_at;

-- 2) logs_api: exact match on entrega_id in (11463, 11499, 11525) -------------
SELECT la.id, la.function_name, la.user_id, u.nombre, u.apellido, la.called_at,
       COALESCE(la.params->>'entrega_id', la.params->>'p_entrega_id') AS entrega_id_param
FROM logs_api la
LEFT JOIN usuario u ON u.id = la.user_id
WHERE COALESCE(la.params->>'entrega_id', la.params->>'p_entrega_id') IN ('11463','11499','11525')
ORDER BY la.called_at;

-- 3) logs_api: registrar_entrega_compra / crear_entrega / actualizar_entrega /
--    anular_entrega calls whose 'items' payload mentions item_id 6 or 198,
--    in the relevant date window (2026-07-08 to 2026-07-16)
SELECT la.id, la.function_name, la.user_id, u.nombre, u.apellido, la.called_at, la.params
FROM logs_api la
LEFT JOIN usuario u ON u.id = la.user_id
WHERE la.function_name IN ('registrar_entrega_compra','crear_entrega','actualizar_entrega',
                            'anular_entrega','registrar_ajuste','registrar_ajuste_a_total',
                            'fn_refresh_compra_detalle_qtys','conciliar_compra')
  AND la.called_at BETWEEN '2026-07-08' AND '2026-07-16'
  AND (la.params::text LIKE '%"item_id": 6,%' OR la.params::text LIKE '%"item_id": 198,%'
       OR la.params::text LIKE '%"item_id":6,%'  OR la.params::text LIKE '%"item_id":198,%')
ORDER BY la.called_at;

-- 4) Full chronological event stream: compra header, all 3 entregas, all
--    movements, and cantidad_recibida snapshots — merged into one timeline.
--    (No single "as-of" history table for compra_detalle exists, so this is
--    the closest reconstruction from immutable/append-only sources.)
SELECT 'compra creada' AS evento, c.fyh_cre AS momento, NULL::text AS detalle
FROM doc.compra c WHERE c.id = 1014
UNION ALL
SELECT 'entrega creada: ' || e.id || ' (' || COALESCE(e.serie,'headless') || '-' || COALESCE(e.correlativo,'') || ')',
       e.fecha_recepcion, et.codigo
FROM doc.entrega e JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE e.id IN (11463, 11499, 11525)
UNION ALL
SELECT 'movimiento: ' || imt.codigo || ' item ' || im.item_id || ' qty ' || im.cantidad,
       im.fecha_hora, 'entrega ' || im.documento_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'entrega' AND im.documento_id IN (11463, 11499, 11525)
ORDER BY momento;

-- 5) Was compra 1014 (or its entregas) touched by fn_refresh_compra_detalle_qtys
--    manually at any point (vs only the inline call inside registrar_entrega_compra)?
SELECT la.id, la.function_name, la.called_at, la.params
FROM logs_api la
WHERE la.function_name = 'fn_refresh_compra_detalle_qtys'
  AND (la.params->>'p_compra_id' = '1014' OR la.params::text LIKE '%1014%')
ORDER BY la.called_at;

-- 6) Other open/recent compras for the same supplier (tercero 184) around
--    this window — to check if 11499/11525 might have belonged to a
--    DIFFERENT PO instead
SELECT c.id, c.fyh_cre, c.fyh_elm
FROM doc.compra c
WHERE c.tercero_id = 184
  AND c.fyh_cre BETWEEN '2026-07-01' AND '2026-07-16'
ORDER BY c.fyh_cre;

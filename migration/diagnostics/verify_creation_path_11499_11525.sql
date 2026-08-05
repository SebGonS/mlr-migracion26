-- ============================================================================
-- Critical question: were 11499/11525 created via the normal RPC path at all?
-- Prior sweep of ALL of user 18's logs_api activity on 2026-07-13 and
-- 2026-07-14→16 showed ONLY: registrar_compra_completa, registrar_entrega_compra,
-- registrar_factura_proveedor, registrar_letra, reconciliar_entrega_compra.
-- No crear_entrega call appears anywhere in that window for user 18.
-- So either (a) a different user created them, (b) they were created on a
-- different date than fecha_recepcion implies, or (c) they bypassed the RPC
-- layer entirely (same failure mode as entregas 855/856 earlier this session).
-- ============================================================================

-- 1) Does doc.entrega even have a creation-audit column (usr_cre/fyh_cre)?
--    Earlier query only selected usr_mod/fyh_mod — check full column set.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'doc' AND table_name = 'entrega'
ORDER BY ordinal_position;

-- 2) Full row for 11499/11525 with every column, whatever exists
SELECT * FROM doc.entrega WHERE id IN (11499, 11525);

-- 3) crear_entrega calls by ANY user mentioning these guía numbers
SELECT la.id, la.function_name, la.user_id, u.nombre, u.apellido, la.called_at, la.params
FROM logs_api la
LEFT JOIN usuario u ON u.id = la.user_id
WHERE la.function_name = 'crear_entrega'
  AND (la.params::text LIKE '%EG07%' OR la.params::text LIKE '%"917"%' OR la.params::text LIKE '%"919"%')
ORDER BY la.called_at;

-- 4) ANY logs_api call by ANY user (not just 18) whose params mention EG07
--    at all, any function, any date — widest possible net
SELECT la.id, la.function_name, la.user_id, u.nombre, u.apellido, la.called_at
FROM logs_api la
LEFT JOIN usuario u ON u.id = la.user_id
WHERE la.params::text LIKE '%EG07%'
ORDER BY la.called_at;

-- 5) The item_movimientos usr_cre for these entregas' postings — who's
--    actually recorded as posting the ledger entries (separate from logs_api)
SELECT im.id, im.item_id, im.usr_cre, u.nombre, u.apellido, im.fecha_hora, im.documento_id
FROM inventario.item_movimientos im
LEFT JOIN usuario u ON u.id = im.usr_cre
WHERE im.documento_tipo = 'entrega' AND im.documento_id IN (11499, 11525);

-- 6) The inventario.lote usr_cre for these lotes
SELECT l.id, l.item_id, l.usr_cre, u.nombre, u.apellido, l.fyh_cre, l.documento_id
FROM inventario.lote l
LEFT JOIN usuario u ON u.id = l.usr_cre
WHERE l.documento_tipo = 'entrega' AND l.documento_id IN (11499, 11525);

-- ============================================================================
-- Find the actual creation call for entregas 11499 and 11525 (earlier
-- item_id-substring search came back empty — broadening now).
-- ============================================================================

-- 1) entrega table's own audit columns — who/when created, if tracked --------
SELECT id, serie, correlativo, fecha_recepcion, fyh_elm,
       usr_mod, fyh_mod
FROM doc.entrega
WHERE id IN (11463, 11499, 11525);

-- 2) ALL logs_api calls by user 18 in the relevant windows, regardless of
--    function name, so we can eyeball what ran right around entrega creation.
--    11499: fecha_recepcion 2026-07-13, reconciled 2026-07-13 22:13:10
--    11525: fecha_recepcion 2026-07-15, reconciled 2026-07-16 14:56:21
SELECT la.id, la.function_name, la.user_id, la.called_at
FROM logs_api la
WHERE la.user_id = 18
  AND la.called_at BETWEEN '2026-07-13 00:00:00' AND '2026-07-13 23:59:59'
ORDER BY la.called_at;

SELECT la.id, la.function_name, la.user_id, la.called_at
FROM logs_api la
WHERE la.user_id = 18
  AND la.called_at BETWEEN '2026-07-14 12:00:00' AND '2026-07-16 15:00:00'
ORDER BY la.called_at;

-- 3) Any entrega-creation-shaped function call whose params mention serie
--    'EG07' or correlativo '917' / '919' directly (more reliable than item_id
--    substring matching, since these are the actual guía document numbers)
SELECT la.id, la.function_name, la.user_id, la.called_at, la.params
FROM logs_api la
WHERE la.params::text LIKE '%EG07%'
  AND la.called_at BETWEEN '2026-07-12' AND '2026-07-17'
ORDER BY la.called_at;

-- 4) Full params for the reconciliar_entrega_compra calls themselves —
--    confirm they only carry entrega_id+compra_id (i.e. entrega already
--    existed at that point) rather than embedding item lines (which would
--    imply reconciliar_entrega_compra ALSO creates the entrega, not just links it)
SELECT id, function_name, called_at, params
FROM logs_api
WHERE id IN (40173, 40536);

-- 5) Sanity: how many OTHER entregas were created same-day, same-tercero,
--    to see if this is a batch/bulk import process rather than one-by-one UI use
SELECT e.id, e.serie, e.correlativo, e.fecha_recepcion, e.tercero_id
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE et.codigo = 'COMPRA_INGRESO'
  AND e.tercero_id = 184
  AND e.fecha_recepcion BETWEEN '2026-07-12' AND '2026-07-16'
ORDER BY e.fecha_recepcion;

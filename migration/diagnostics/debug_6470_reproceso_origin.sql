-- ============================================================================
-- CONTEXT: partida 6470 was a reproceso (rework) child, created from another
-- reproceso partida (a sibling), NOT directly from the family root. It was
-- reversed via mes.anular_reproceso -> mes.mover_lotes_reproceso.
--
-- BUG: mover_lotes_reproceso always sends the rolls back to
-- v_child.partida_origen_id, which crear_reproceso always sets to the FLAT
-- ROOT of the family (funciones/mes.sql:3658 -
-- "v_root_id := COALESCE(v_origen.partida_origen_id, v_origen.id)"), never to
-- the immediate sibling partida the rolls actually came from. So the rolls
-- from 6470 landed back on the root instead of the sibling rework partida
-- they were pulled from when 6470 was created.
--
-- READ ONLY. Nothing here mutates. Run each block, paste the output back.
-- ============================================================================

-- 0) Headers: family link + current states.
SELECT p.id,
       EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text,4,'0') AS codigo,
       p.partida_origen_id,
       p.estado_produccion,
       p.estado_comercial,
       p.fyh_cre, p.fyh_elm
FROM mes.partida p
WHERE p.id = 6470
   OR p.id = (SELECT partida_origen_id FROM mes.partida WHERE id = 6470)
   OR p.partida_origen_id = (SELECT COALESCE(partida_origen_id, id) FROM mes.partida WHERE id = 6470)
ORDER BY p.id;

-- 1) discover logs_api columns (its timestamp col is not necessarily fyh_cre) --
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'logs_api'
ORDER BY ordinal_position;

-- 2) The crear_reproceso call that created 6470 — params->>'partida_id' is the
--    TRUE immediate source partida (sibling rework or root) at creation time.
--    reproceso_partida_id isn't in the input params, so match by result message
--    or by timing; try the direct id match first in case it's logged.
SELECT id, function_name, user_id, params
FROM logs_api
WHERE function_name = 'crear_reproceso'
  AND (
        params->>'reproceso_partida_id' = '6470'
        OR params::text LIKE '%"6470"%'
      )
ORDER BY id DESC
LIMIT 10;

-- 3) The anular_reproceso / mover_lotes_reproceso call(s) that reversed 6470.
SELECT id, function_name, user_id, params
FROM logs_api
WHERE function_name IN ('anular_reproceso','mover_lotes_reproceso')
  AND (params->>'reproceso_id')::bigint = 6470
ORDER BY id DESC;

-- 4) Rolls historically tied to 6470 (via its own pasos/inspecciones) and
--    where they sit RIGHT NOW in partida_componente.
SELECT DISTINCT ci.lote_id
FROM calidad.inspeccion ci
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE pp.partida_id = 6470;

-- 5) Current componente rows for those lotes: shows where they landed after
--    the reversal (expected: the root, per the bug above).
SELECT pc.partida_id, pc.lote_id, p.estado_produccion, p.partida_origen_id
FROM mes.partida_componente pc
JOIN mes.partida p ON p.id = pc.partida_id
WHERE pc.lote_id IN (
    SELECT DISTINCT ci.lote_id
    FROM calidad.inspeccion ci
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    WHERE pp.partida_id = 6470
)
ORDER BY pc.partida_id, pc.lote_id;

-- 6) SAFETY GATE: has 6470 (or the target sibling) had any production/movements
--    on these rolls that would make a plain componente-repoint unsafe?
SELECT im.id, im.lote_id, imt.codigo AS mov_tipo, im.cantidad,
       im.documento_tipo, im.documento_id, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (
    SELECT DISTINCT ci.lote_id
    FROM calidad.inspeccion ci
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = ci.partida_paso_ejecucion_id
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    WHERE pp.partida_id = 6470
)
ORDER BY im.fyh_cre;

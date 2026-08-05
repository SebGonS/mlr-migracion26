-- Debug: partidas 6373, 6374, 6176, 6377, 6348, 6346 not appearing in
-- calidad.vw_partidas_pendientes_calidad.
--
-- Walks through every filter in calidad.vw_lotes_pendientes_inspeccion
-- (migration/08_views.sql:1245) for each target partida to see exactly
-- where each candidate lote drops out. Run each section in order; the
-- first one that shows "EXCLUDED" for a given lote explains why it's
-- missing from the QC queue.

-- ═══════════════════════════════════════════════════════════════
-- 0) Target list
-- ═══════════════════════════════════════════════════════════════
WITH targets AS (
    SELECT unnest(ARRAY[6373, 6374, 6176, 6377, 6348, 6346]) AS partida_id
)
SELECT * FROM targets;

-- ═══════════════════════════════════════════════════════════════
-- 1) Partida state gate:
--    COALESCE(p.estado_produccion, 'CREADA') NOT IN ('CERRADA','CANCELADA')
-- ═══════════════════════════════════════════════════════════════
SELECT
    p.id AS partida_id,
    p.estado_produccion,
    p.partida_origen_id,
    CASE WHEN COALESCE(p.estado_produccion, 'CREADA') IN ('CERRADA', 'CANCELADA')
         THEN 'EXCLUDED: closed/cancelled'
         ELSE 'ok: state allows QC'
    END AS verdict
FROM mes.partida p
WHERE p.id IN (6373, 6374, 6176, 6377, 6348, 6346)
ORDER BY p.id;

-- ═══════════════════════════════════════════════════════════════
-- 2) Candidate rolls per partida — both paths:
--    Path A: output rolls (lote.documento_tipo='partida_paso_ejecucion',
--             not in partida_componente)
--    Path B/C: input/rework rolls (lote_id present in mes.partida_componente)
-- ═══════════════════════════════════════════════════════════════

-- 2a) Path A candidates: output rolls created by this partida's ejecuciones
SELECT
    'path_A_output' AS path,
    p.id AS partida_id,
    l.id AS lote_id,
    l.fyh_cre,
    pe.id AS ejecucion_id,
    pe.estado AS ejecucion_estado,
    pp.secuencia,
    EXISTS (
        SELECT 1 FROM calidad.inspeccion ci
        WHERE ci.lote_id = l.id AND ci.partida_paso_ejecucion_id = pe.id
    ) AS ya_inspeccionado,
    CASE
        WHEN pe.id IS NULL THEN 'no matching ejecucion (lote not linked as output)'
        WHEN EXISTS (SELECT 1 FROM calidad.inspeccion ci
                     WHERE ci.lote_id = l.id AND ci.partida_paso_ejecucion_id = pe.id)
            THEN 'EXCLUDED: already inspected'
        ELSE 'PENDING (should appear)'
    END AS verdict
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN inventario.lote l ON l.documento_id = pe.id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
WHERE p.id IN (6373, 6374, 6176, 6377, 6348, 6346)
  AND pc.lote_id IS NULL   -- Path A requires NOT in partida_componente
ORDER BY p.id, l.fyh_cre;

-- 2b) Path B/C candidates: input/rework rolls in mes.partida_componente
SELECT
    'path_BC_input' AS path,
    pc.partida_id,
    pc.lote_id,
    -- does an active (EN_PROCESO or COMPLETADO) ejecucion exist for this partida at all?
    active_ppe.ejecucion_id,
    active_ppe.paso_id,
    active_ppe.estado AS active_ejecucion_estado,
    -- already inspected under this paso?
    EXISTS (
        SELECT 1 FROM calidad.inspeccion ci
        JOIN mes.partida_paso_ejecucion ppe_chk ON ppe_chk.id = ci.partida_paso_ejecucion_id
        WHERE ci.lote_id = pc.lote_id
          AND ppe_chk.partida_paso_id = active_ppe.paso_id
    ) AS ya_inspeccionado,
    -- roll balance still > 0 (not yet consumed by PROD_CONSUMO)?
    (SELECT ls.cantidad_actual FROM inventario.lote_saldo ls WHERE ls.lote_id = pc.lote_id) AS saldo_actual,
    CASE
        WHEN active_ppe.ejecucion_id IS NULL
            THEN 'EXCLUDED: no EN_PROCESO/COMPLETADO ejecucion found for this partida (paso not started or already advanced past)'
        WHEN EXISTS (
                SELECT 1 FROM calidad.inspeccion ci
                JOIN mes.partida_paso_ejecucion ppe_chk ON ppe_chk.id = ci.partida_paso_ejecucion_id
                WHERE ci.lote_id = pc.lote_id AND ppe_chk.partida_paso_id = active_ppe.paso_id)
            THEN 'EXCLUDED: already inspected'
        WHEN COALESCE((SELECT ls.cantidad_actual FROM inventario.lote_saldo ls WHERE ls.lote_id = pc.lote_id), 0) <= 0
            THEN 'EXCLUDED: lote_saldo <= 0 (already consumed / no stock)'
        ELSE 'PENDING (should appear)'
    END AS verdict
FROM mes.partida_componente pc
LEFT JOIN LATERAL (
    SELECT ppe.id AS ejecucion_id, ppe.estado, pp2.id AS paso_id
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp2 ON pp2.id = ppe.partida_paso_id
    WHERE pp2.partida_id = pc.partida_id
      AND ppe.estado IN ('EN_PROCESO', 'COMPLETADO')
    ORDER BY
        CASE WHEN ppe.estado = 'EN_PROCESO' THEN 0 ELSE 1 END,
        pp2.secuencia DESC,
        ppe.fyh_inicio DESC
    LIMIT 1
) active_ppe ON true
WHERE pc.partida_id IN (6373, 6374, 6176, 6377, 6348, 6346)
  AND pc.lote_id IS NOT NULL
ORDER BY pc.partida_id, pc.lote_id;

-- ═══════════════════════════════════════════════════════════════
-- 3) Sanity check: do these partidas have ANY rows in partida_componente
--    or ANY output lote at all? (If neither, there's simply nothing to
--    inspect yet — e.g. no paso has run/produced output.)
-- ═══════════════════════════════════════════════════════════════
SELECT
    p.id AS partida_id,
    p.estado_produccion,
    (SELECT COUNT(*) FROM mes.partida_componente pc WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL) AS n_componentes,
    (SELECT COUNT(*) FROM mes.partida_paso pp WHERE pp.partida_id = p.id) AS n_pasos,
    (SELECT COUNT(*) FROM mes.partida_paso pp
       JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
       WHERE pp.partida_id = p.id) AS n_ejecuciones,
    (SELECT COUNT(*) FROM mes.partida_paso pp
       JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
       WHERE pp.partida_id = p.id AND ppe.estado IN ('EN_PROCESO','COMPLETADO')) AS n_ejecuciones_activas,
    (SELECT COUNT(*) FROM inventario.lote l
       JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
       JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
       WHERE pp.partida_id = p.id) AS n_lotes_output
FROM mes.partida p
WHERE p.id IN (6373, 6374, 6176, 6377, 6348, 6346)
ORDER BY p.id;

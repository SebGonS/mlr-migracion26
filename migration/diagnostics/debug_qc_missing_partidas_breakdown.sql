-- Follow-up on debug_qc_missing_partidas_6373_etc.sql:
-- All 6 partidas (6373, 6374, 6176, 6377, 6348, 6346) have zero pending QC
-- because every output lote already has an inspeccion row and every input
-- lote has lote_saldo = 0. This script answers, grouped per partida
-- (no per-roll rows unless a partida's rolls disagree with each other):
--   1) WHEN were the output lotes inspected, and by whom (real review vs. backfill)?
--   2) WHERE did the consumed input rolls go — folded into the very output
--      that was inspected (normal close-out), or peeled off into a rework
--      partida (Path C)?

-- ═══════════════════════════════════════════════════════════════
-- 1) Inspection timestamp summary per partida (Path A output lotes),
--    with the approving user's email (usuario.auth_id -> auth.users.email).
--    Tight spread + single usr_cre = likely one bulk action, not 20
--    individual manual inspections.
-- ═══════════════════════════════════════════════════════════════
SELECT
    p.id AS partida_id,
    COUNT(*) AS n_lotes_inspeccionados,
    COUNT(DISTINCT ci.usr_cre) AS n_usuarios_distintos,
    MIN(u.nombre || ' ' || u.apellido) AS aprobado_por_nombre,
    MIN(au.email) AS aprobado_por_email,
    COUNT(DISTINCT ci.resultado) AS n_resultados_distintos,
    MIN(ci.resultado::text) AS resultado_si_uniforme,  -- meaningful only when n_resultados_distintos=1
    MIN(ci.fyh_inspeccion) AS primera_inspeccion,
    MAX(ci.fyh_inspeccion) AS ultima_inspeccion,
    MAX(ci.fyh_inspeccion) - MIN(ci.fyh_inspeccion) AS spread
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
JOIN inventario.lote l ON l.documento_id = pe.id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
JOIN calidad.inspeccion ci ON ci.lote_id = l.id AND ci.partida_paso_ejecucion_id = pe.id
LEFT JOIN public.usuario u ON u.id = ci.usr_cre
LEFT JOIN auth.users au ON au.id = u.auth_id
WHERE p.id IN (6373, 6374, 6176, 6377, 6348, 6346)
  AND pc.lote_id IS NULL
GROUP BY p.id
ORDER BY p.id;

-- ═══════════════════════════════════════════════════════════════
-- 2) Consumed input rolls (saldo=0): where the PROD_CONSUMO leg
--    points, grouped by partida + verdict. If a partida shows only
--    one verdict row with count=20, all its rolls behaved the same way.
-- ═══════════════════════════════════════════════════════════════
WITH consumed_inputs AS (
    SELECT pc.partida_id, pc.lote_id
    FROM mes.partida_componente pc
    JOIN inventario.lote_saldo ls ON ls.lote_id = pc.lote_id
    WHERE pc.partida_id IN (6373, 6374, 6176, 6377, 6348, 6346)
      AND ls.cantidad_actual <= 0
),
closing_ejecucion AS (
    SELECT p.id AS partida_id, MAX(pe.id) AS ejecucion_id  -- last/highest-secuencia ejecucion
    FROM mes.partida p
    JOIN mes.partida_paso pp ON pp.partida_id = p.id
    JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
    WHERE p.id IN (6373, 6374, 6176, 6377, 6348, 6346)
      AND pe.estado = 'COMPLETADO'
    GROUP BY p.id
),
per_lote AS (
    SELECT
        ci.partida_id,
        ci.lote_id,
        im.documento_tipo,
        im.documento_id,
        CASE WHEN im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = ce.ejecucion_id
             THEN 'folded into inspected output (normal close-out)'
             WHEN im.documento_id IS NULL
             THEN 'no PROD_CONSUMO movement found'
             ELSE 'went elsewhere (documento_tipo/id differs from closing ejecucion)'
        END AS verdict
    FROM consumed_inputs ci
    JOIN closing_ejecucion ce ON ce.partida_id = ci.partida_id
    LEFT JOIN LATERAL (
        SELECT im.documento_tipo, im.documento_id
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = ci.lote_id AND imt.codigo = 'PROD_CONSUMO'
        ORDER BY im.fecha_hora DESC
        LIMIT 1
    ) im ON true
)
SELECT
    partida_id,
    verdict,
    documento_tipo,
    documento_id,
    COUNT(*) AS n_lotes
    -- , array_agg(lote_id ORDER BY lote_id) AS lote_ids  -- uncomment if a verdict group needs drilling into
FROM per_lote
GROUP BY partida_id, verdict, documento_tipo, documento_id
ORDER BY partida_id, n_lotes DESC;

-- ═══════════════════════════════════════════════════════════════
-- 3) Rework check: any child partida spun off from these six?
-- ═══════════════════════════════════════════════════════════════
SELECT
    rw.partida_origen_id,
    COUNT(*) AS n_rework_partidas,
    array_agg(rw.id ORDER BY rw.id) AS rework_partida_ids,
    array_agg(DISTINCT rw.estado_produccion) AS estados
FROM mes.partida rw
WHERE rw.partida_origen_id IN (6373, 6374, 6176, 6377, 6348, 6346)
GROUP BY rw.partida_origen_id
ORDER BY rw.partida_origen_id;

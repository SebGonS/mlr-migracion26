-- ─────────────────────────────────────────────────────────────────────────────
-- DEBUG: why is a partida NOT showing in vw_partidas_pendientes_calidad?
--
-- Gates checked (mirrors vw_lotes_pendientes_inspeccion logic exactly):
--   G1  partida exists, not soft-deleted, not CERRADA/CANCELADA
--   G2  has at least one ROLLO lote reachable via Path A or B/C
--   G3  Path B/C: active paso (EN_PROCESO or latest COMPLETADO) exists
--   G4  no inspection already recorded for that roll+ejecucion pair
--   G5  Path B/C: lote_saldo.cantidad_actual > 0  (roll not consumed)
--
-- USAGE: add the partida IDs you want to investigate in the ids CTE below.
-- ─────────────────────────────────────────────────────────────────────────────

WITH ids AS (
    SELECT unnest(ARRAY[ 2937]) AS partida_id
)

-- ── G1: partida estado & soft-delete ─────────────────────────────────────────
, g1 AS (
    SELECT
        i.partida_id,
        p.id                  AS found_id,
        p.estado_produccion,
        p.fyh_elm,
        CASE
            WHEN p.id IS NULL
                THEN 'FAIL – not found'
            WHEN p.fyh_elm IS NOT NULL
                THEN 'FAIL – soft-deleted'
            WHEN COALESCE(p.estado_produccion, 'CREADA') IN ('CERRADA', 'CANCELADA')
                THEN 'FAIL – estado=' || p.estado_produccion || ' (excluded by view)'
            ELSE 'OK   – estado=' || COALESCE(p.estado_produccion, 'CREADA')
        END AS result
    FROM ids i
    LEFT JOIN mes.partida p ON p.id = i.partida_id
)

-- ── G2A: Path A — output rolls created by a partida_paso_ejecucion ───────────
-- lote.documento_tipo = 'partida_paso_ejecucion' AND linked ppe belongs to this partida
, g2a AS (
    SELECT
        i.partida_id,
        COUNT(l.id) AS path_a_rolls,
        CASE
            WHEN COUNT(l.id) = 0 THEN 'NONE – no output rolls (Path A)'
            ELSE 'OK   – ' || COUNT(l.id) || ' output roll(s) exist'
        END AS result
    FROM ids i
    LEFT JOIN mes.partida_paso        pp  ON pp.partida_id = i.partida_id
    LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
    LEFT JOIN inventario.lote l
          ON  l.documento_tipo = 'partida_paso_ejecucion'
          AND l.documento_id   = ppe.id
          AND l.fyh_elm IS NULL
    LEFT JOIN item_tipo it ON it.id = (
        SELECT it2.id FROM item i2
        JOIN item_tipo it2 ON it2.id = i2.item_tipo_id
        WHERE i2.id = l.item_id LIMIT 1
    )
    GROUP BY i.partida_id
)

-- ── G2B: Path B/C — input rolls assigned via partida_componente ──────────────
, g2b AS (
    SELECT
        i.partida_id,
        COUNT(pc.lote_id) AS path_bc_rolls,
        CASE
            WHEN COUNT(pc.lote_id) = 0 THEN 'NONE – no rolls in partida_componente (Paths B/C)'
            ELSE 'OK   – ' || COUNT(pc.lote_id) || ' roll(s) in partida_componente'
        END AS result
    FROM ids i
    LEFT JOIN mes.partida_componente pc
          ON  pc.partida_id = i.partida_id
          AND pc.lote_id IS NOT NULL
    GROUP BY i.partida_id
)

-- ── G3: active paso for B/C paths ────────────────────────────────────────────
-- Mirrors the LATERAL: EN_PROCESO first, then latest COMPLETADO
, g3 AS (
    SELECT DISTINCT ON (i.partida_id)
        i.partida_id,
        ppe.id          AS active_ejecucion_id,
        ppe.estado      AS active_estado,
        pp.id           AS active_paso_id,
        pp.secuencia    AS active_secuencia,
        CASE
            WHEN ppe.id IS NULL THEN 'FAIL – no EN_PROCESO or COMPLETADO ejecucion found'
            ELSE 'OK   – ejecucion ' || ppe.id || ' estado=' || ppe.estado
        END AS result
    FROM ids i
    LEFT JOIN mes.partida_paso           pp  ON pp.partida_id = i.partida_id
    LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
                                            AND ppe.estado IN ('EN_PROCESO', 'COMPLETADO')
    ORDER BY
        i.partida_id,
        CASE WHEN ppe.estado = 'EN_PROCESO' THEN 0 ELSE 1 END,
        pp.secuencia DESC,
        ppe.fyh_inicio DESC
)

-- ── G4: inspections already recorded (per roll+ejecucion) ────────────────────
, g4 AS (
    SELECT
        i.partida_id,
        COUNT(ci.id)                                       AS inspecciones_existentes,
        COUNT(pc.lote_id)                                  AS total_rolls_bc,
        COUNT(pc.lote_id) - COUNT(ci.id)                  AS rolls_sin_inspeccion,
        CASE
            WHEN COUNT(pc.lote_id) = 0 THEN 'N/A  – no B/C rolls'
            WHEN COUNT(ci.id) >= COUNT(pc.lote_id)
                THEN 'FAIL – all B/C rolls already inspected (' || COUNT(ci.id) || '/' || COUNT(pc.lote_id) || ')'
            ELSE 'OK   – ' || (COUNT(pc.lote_id) - COUNT(ci.id)) || ' roll(s) not yet inspected'
        END AS result
    FROM ids i
    LEFT JOIN mes.partida_componente     pc  ON pc.partida_id = i.partida_id
                                            AND pc.lote_id IS NOT NULL
    LEFT JOIN g3                             ON g3.partida_id = i.partida_id
    LEFT JOIN calidad.inspeccion         ci  ON ci.lote_id = pc.lote_id
                                            AND ci.partida_paso_ejecucion_id = g3.active_ejecucion_id
    GROUP BY i.partida_id
)

-- ── G5: lote_saldo guard (B/C rolls must have cantidad_actual > 0) ────────────
, g5 AS (
    SELECT
        i.partida_id,
        COUNT(pc.lote_id)                                                    AS total_rolls,
        COUNT(pc.lote_id) FILTER (WHERE ls.cantidad_actual > 0)              AS rolls_con_saldo,
        COUNT(pc.lote_id) FILTER (WHERE COALESCE(ls.cantidad_actual, 0) = 0) AS rolls_sin_saldo,
        CASE
            WHEN COUNT(pc.lote_id) = 0 THEN 'N/A  – no B/C rolls'
            WHEN COUNT(pc.lote_id) FILTER (WHERE ls.cantidad_actual > 0) = 0
                THEN 'FAIL – all B/C rolls have cantidad_actual = 0 (consumed)'
            ELSE 'OK   – ' || COUNT(pc.lote_id) FILTER (WHERE ls.cantidad_actual > 0)
                          || '/' || COUNT(pc.lote_id) || ' rolls have saldo > 0'
        END AS result
    FROM ids i
    LEFT JOIN mes.partida_componente pc ON pc.partida_id = i.partida_id
                                       AND pc.lote_id IS NOT NULL
    LEFT JOIN inventario.lote_saldo  ls ON ls.lote_id = pc.lote_id
    GROUP BY i.partida_id
)

-- ── Roll-level detail: one row per roll, all gate flags ──────────────────────
-- Useful once you know which gate is failing to pinpoint the exact rolls.
, roll_detail AS (
    SELECT
        i.partida_id,
        pc.lote_id,
        EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0')
                                                                  AS lote_codigo,
        g3.active_ejecucion_id,
        g3.active_estado,
        ci.id IS NOT NULL                                         AS inspeccion_existe,
        COALESCE(ls.cantidad_actual, 0)                           AS saldo_actual,
        -- which path does this roll land on?
        CASE
            WHEN l.documento_tipo = 'partida_paso_ejecucion' THEN 'A (output)'
            WHEN pc.lote_id IS NOT NULL                       THEN 'B/C (input)'
            ELSE '?'
        END                                                       AS path,
        CASE
            WHEN g3.active_ejecucion_id IS NULL          THEN 'FAIL G3 – no active ejecucion'
            WHEN ci.id IS NOT NULL                        THEN 'FAIL G4 – already inspected'
            WHEN COALESCE(ls.cantidad_actual, 0) = 0      THEN 'FAIL G5 – consumed (saldo=0)'
            ELSE                                               'OK   – eligible'
        END                                                       AS verdict
    FROM ids i
    JOIN mes.partida_componente     pc  ON pc.partida_id = i.partida_id
                                       AND pc.lote_id IS NOT NULL
    JOIN inventario.lote            l   ON l.id = pc.lote_id AND l.fyh_elm IS NULL
    LEFT JOIN g3                        ON g3.partida_id = i.partida_id
    LEFT JOIN calidad.inspeccion    ci  ON ci.lote_id = pc.lote_id
                                       AND ci.partida_paso_ejecucion_id = g3.active_ejecucion_id
    LEFT JOIN inventario.lote_saldo ls  ON ls.lote_id = pc.lote_id
    ORDER BY i.partida_id, pc.lote_id
)

-- ── FINAL VERDICT ─────────────────────────────────────────────────────────────
SELECT
    g1.partida_id,
    g1.result  AS "G1 partida estado",
    g2b.result AS "G2 rolls asignados (B/C)",
    g2a.result AS "G2 output rolls (A)",
    g3.result  AS "G3 active ejecucion",
    g4.result  AS "G4 inspecciones pendientes",
    g5.result  AS "G5 saldo rolls"
FROM g1
LEFT JOIN g2a ON g2a.partida_id = g1.partida_id
LEFT JOIN g2b ON g2b.partida_id = g1.partida_id
LEFT JOIN g3  ON g3.partida_id  = g1.partida_id
LEFT JOIN g4  ON g4.partida_id  = g1.partida_id
LEFT JOIN g5  ON g5.partida_id  = g1.partida_id
ORDER BY g1.partida_id;

-- ── Uncomment to see per-roll breakdown after identifying which gate fails ────
-- SELECT * FROM roll_detail ORDER BY partida_id, lote_id;


-- ═════════════════════════════════════════════════════════════════════════════
-- DEEP DIVE: partida 4230 — input consumed but zero output rolls
-- Answers: what happened to the ejecucion, where did the movements go,
--          and did any output lotes land outside the expected documento link?
-- ═════════════════════════════════════════════════════════════════════════════

-- 1. Ejecucion 7863 detail + paso context
SELECT
    ppe.id              AS ejecucion_id,
    ppe.estado,
    ppe.fyh_inicio,
    ppe.fyh_fin,
    pp.id               AS paso_id,
    pp.secuencia,
    op.codigo           AS operacion,
    m.codigo            AS maquina
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso  pp ON pp.id  = ppe.partida_paso_id
JOIN mes.operacion     op ON op.id  = pp.operacion_id
LEFT JOIN mes.maquina  m  ON m.id   = ppe.maquina_id
WHERE ppe.id = 7863;

-- 2. All movements touching the 12 consumed input rolls
--    (shows PROD_CONSUMO, any EGRESO, anything unexpected)
SELECT
    im.id,
    im.lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0')
                        AS lote_codigo,
    imt.codigo          AS tipo_movimiento,
    im.documento_tipo,
    im.documento_id,
    im.cantidad,
    im.fecha_hora
FROM mes.partida_componente pc
JOIN inventario.item_movimientos    im  ON im.lote_id = pc.lote_id
JOIN inventario.lote                l   ON l.id = pc.lote_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE pc.partida_id = 4230
  AND pc.lote_id IS NOT NULL
ORDER BY pc.lote_id, im.fecha_hora;

-- 3. Any lotes whose documento_id = 7863 (should be the output rolls if they exist)
SELECT
    l.id            AS lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0')
                    AS lote_codigo,
    l.documento_tipo,
    l.documento_id,
    l.fyh_cre,
    ls.cantidad_actual
FROM inventario.lote l
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = l.id
WHERE l.documento_tipo = 'partida_paso_ejecucion'
  AND l.documento_id   = 7863
  AND l.fyh_elm IS NULL;

-- 4. lote_saldo snapshot for input rolls (confirms all are zero and why)
SELECT
    pc.lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0')
                            AS lote_codigo,
    ls.cantidad_actual
FROM mes.partida_componente  pc
JOIN inventario.lote          l  ON l.id  = pc.lote_id
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = pc.lote_id
WHERE pc.partida_id = 4230
  AND pc.lote_id IS NOT NULL
ORDER BY pc.lote_id;

SELECT ppe.id AS ejecucion_id, ppe.estado, pp.id AS paso_id, op.codigo AS operacion
FROM mes.partida_paso pp
JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
JOIN mes.operacion op ON op.id = pp.operacion_id
WHERE pp.partida_id = 4230
ORDER BY pp.secuencia, ppe.id;



SELECT 
    l.id                                                    AS lote_id,
    pc.lote_id                                              AS pc_lote_id,
    pc.partida_id,
    active_ppe.ejecucion_id,
    active_ppe.estado                                       AS ppe_estado,
    p.id                                                    AS p_id,
    p.estado_produccion,
    EXISTS(
        SELECT 1 FROM inventario.lote_saldo ls
        WHERE ls.lote_id = l.id AND ls.cantidad_actual > 0
    )                                                       AS has_saldo,
    EXISTS(
        SELECT 1 FROM calidad.inspeccion ci
        WHERE ci.lote_id = l.id 
          AND ci.partida_paso_ejecucion_id = active_ppe.ejecucion_id
    )                                                       AS has_inspeccion
FROM inventario.lote l
JOIN vw_items vi ON vi.item_id = l.item_id AND vi.item_tipo_codigo = 'ROLLO'
LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
LEFT JOIN LATERAL (
    SELECT ppe.id AS ejecucion_id, ppe.estado
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp2 ON pp2.id = ppe.partida_paso_id
    WHERE pp2.partida_id = pc.partida_id
      AND ppe.estado IN ('EN_PROCESO', 'COMPLETADO')
    ORDER BY CASE WHEN ppe.estado = 'EN_PROCESO' THEN 0 ELSE 1 END,
             pp2.secuencia DESC, ppe.fyh_inicio DESC
    LIMIT 1
) active_ppe ON pc.lote_id IS NOT NULL
LEFT JOIN mes.partida p ON p.id = CASE
    WHEN pc.lote_id IS NOT NULL THEN pc.partida_id
    ELSE NULL
END
WHERE l.id = 58374;



SELECT COUNT(*), COUNT(DISTINCT lote_id)
FROM calidad.inspeccion
WHERE partida_paso_ejecucion_id = 6139;


SELECT 
    ci.id,
    ci.lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    ci.resultado,
    ci.fyh_inspeccion,
    ci.empleado_id,
    e.nombre || ' ' || e.apellido AS empleado,
    ci.observacion
FROM calidad.inspeccion ci
JOIN inventario.lote l ON l.id = ci.lote_id
LEFT JOIN mes.empleado e ON e.id = ci.empleado_id
WHERE ci.partida_paso_ejecucion_id = 6139
ORDER BY ci.fyh_inspeccion, ci.lote_id;

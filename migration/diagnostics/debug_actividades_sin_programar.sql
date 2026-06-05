-- ─────────────────────────────────────────────────────────────────────────────
-- DEBUG: why is a partida NOT showing / wrongly showing in get_actividades_sin_programar()?
--
-- Two modes:
--   NOT SHOWING  → all gates return OK but partida is absent → check gates 1–5
--   WRONGLY SHOWING → paso appears in list but shouldn't → look for "BUG" rows
--                     in the VERDICT section (paso.estado vs ejecucion counts mismatch)
--
-- USAGE: replace v_partida_id below with the partida you're investigating.
-- ─────────────────────────────────────────────────────────────────────────────

WITH v AS (
    SELECT 5177 AS v_partida_id  -- ← EDIT THIS
)

-- ── Gate 1: partida estado_produccion & soft-delete
, g1_partida AS (
    SELECT
        p.id,
        EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo,
        p.estado_produccion,
        p.fyh_elm,
        CASE
            WHEN p.id IS NULL                                                    THEN 'FAIL – partida not found'
            WHEN p.fyh_elm IS NOT NULL                                           THEN 'FAIL – soft-deleted (fyh_elm = ' || p.fyh_elm::text || ')'
            WHEN p.estado_produccion IN ('CERRADA','CANCELADA','TECO','CREADA')  THEN 'FAIL – estado_produccion = ' || p.estado_produccion || ' (excluded)'
            ELSE                                                                      'OK   – estado_produccion = ' || p.estado_produccion
        END AS gate_result
    FROM mes.partida p, v
    WHERE p.id = v.v_partida_id
)

-- ── Gate 2: partida_paso rows exist?
, g2_pasos AS (
    SELECT
        pp.id          AS paso_id,
        o.nombre       AS operacion,
        o.codigo       AS operacion_codigo,
        pp.estado
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id, v
    WHERE pp.partida_id = v.v_partida_id
)

-- ── Gate 3: lotes assigned via partida_componente (denominator for gate 4)
, g3_lotes AS (
    SELECT COUNT(*) AS lotes_asignados
    FROM mes.partida_componente pc, v
    WHERE pc.partida_id = v.v_partida_id
      AND pc.lote_id IS NOT NULL
)

-- ── Gate 4: per paso — completed executions vs. lotes; EN_PROCESO check
, g4_ejecuciones AS (
    SELECT
        pp.id                                                              AS paso_id,
        o.nombre                                                           AS operacion,
        pp.estado                                                          AS paso_estado,
        (SELECT COUNT(*) FROM mes.partida_paso_ejecucion pe
         WHERE pe.partida_paso_id = pp.id
           AND pe.estado IN ('COMPLETADO','OMITIDO'))                      AS exec_completadas,
        (SELECT COUNT(*) FROM mes.partida_componente pc
         WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL)  AS lotes_asignados,
        (SELECT COUNT(*) FROM mes.partida_paso_ejecucion pe
         WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO')   AS en_proceso_count,
        CASE
            WHEN (SELECT COUNT(*) FROM mes.partida_paso_ejecucion pe
                  WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO') > 0
                THEN 'FAIL – paso has EN_PROCESO ejecucion (excluded while in progress)'
            WHEN (SELECT COUNT(*) FROM mes.partida_componente pc
                  WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL) = 0
                THEN 'FAIL – no lotes assigned (denominator = 0)'
            WHEN (SELECT COUNT(*) FROM mes.partida_paso_ejecucion pe
                  WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('COMPLETADO','OMITIDO'))
                 >=
                 (SELECT COUNT(*) FROM mes.partida_componente pc
                  WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL)
                THEN 'FAIL – completadas (' ||
                     (SELECT COUNT(*) FROM mes.partida_paso_ejecucion pe
                      WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('COMPLETADO','OMITIDO'))::text
                     || ') >= lotes (' ||
                     (SELECT COUNT(*) FROM mes.partida_componente pc
                      WHERE pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL)::text
                     || ') – paso already done'
            ELSE 'OK   – execution gate passes'
        END AS gate_result
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id, v
    WHERE pp.partida_id = v.v_partida_id
)

-- ── Gate 5: per paso — already in mes.programacion for a future/today date?
, g5_programacion AS (
    SELECT
        pp.id        AS paso_id,
        o.nombre     AS operacion,
        prog.id      AS prog_id,
        prog.fecha   AS prog_fecha,
        prog.maquina_id,
        CASE
            WHEN prog.id IS NULL THEN 'OK   – not yet scheduled (will appear in list)'
            ELSE 'FAIL – already scheduled on ' || prog.fecha::text || ' (excluded from pending list)'
        END AS gate_result
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    LEFT JOIN mes.programacion prog
           ON prog.actividad_tipo = 'partida_paso'
          AND prog.actividad_id   = pp.id
          AND prog.fecha         >= CURRENT_DATE, v
    WHERE pp.partida_id = v.v_partida_id
)

-- ── VERDICT: per paso — is it showing, should it be, and is there a mismatch?
--
--  get_actividades_sin_programar() does NOT filter by pp.estado.
--  A paso with estado=COMPLETADO but exec_completadas < lotes_asignados will
--  still pass all 5 gates and appear in the pending list — this is the bug.
, verdict AS (
    SELECT
        e.paso_id,
        e.operacion,
        e.paso_estado,
        e.exec_completadas,
        e.lotes_asignados,
        -- Would the function include this paso?
        CASE
            WHEN e.gate_result LIKE 'FAIL%'                      THEN false
            WHEN p5.gate_result LIKE 'FAIL%'                     THEN false
            ELSE true
        END AS function_includes,
        -- Should it logically be included?
        CASE
            WHEN e.paso_estado IN ('COMPLETADO','OMITIDO')       THEN false
            ELSE true
        END AS should_include,
        -- Diagnosis
        CASE
            -- Showing correctly
            WHEN e.gate_result NOT LIKE 'FAIL%'
             AND p5.gate_result NOT LIKE 'FAIL%'
             AND e.paso_estado NOT IN ('COMPLETADO','OMITIDO')
                THEN 'SHOWING (correct)'
            -- Not showing (expected)
            WHEN (e.gate_result LIKE 'FAIL%' OR p5.gate_result LIKE 'FAIL%')
             AND e.paso_estado IN ('COMPLETADO','OMITIDO')
                THEN 'HIDDEN (correct – paso done and blocked by gate)'
            -- Not showing correctly
            WHEN e.gate_result LIKE 'FAIL%' OR p5.gate_result LIKE 'FAIL%'
                THEN 'HIDDEN – gate blocks it: ' || COALESCE(NULLIF(e.gate_result,''), p5.gate_result)
            -- BUG: showing but paso.estado says it's done
            WHEN e.paso_estado IN ('COMPLETADO','OMITIDO')
                THEN 'BUG – SHOWING but paso.estado=' || e.paso_estado
                     || ' | exec_completadas=' || e.exec_completadas::text
                     || ' / lotes=' || e.lotes_asignados::text
                     || ' | function does not filter by pp.estado'
            ELSE 'SHOWING (correct)'
        END AS verdict
    FROM g4_ejecuciones e
    JOIN g5_programacion p5 ON p5.paso_id = e.paso_id
)

-- ── Output ────────────────────────────────────────────────────────────────────
SELECT '1_PARTIDA'   AS gate, NULL::text AS paso_id, NULL::text AS operacion, gate_result FROM g1_partida
UNION ALL
SELECT '2_PASOS'     AS gate, paso_id::text, operacion, 'estado=' || estado FROM g2_pasos
UNION ALL
SELECT '3_LOTES'     AS gate, NULL, NULL,
    CASE WHEN lotes_asignados = 0
         THEN 'FAIL – 0 lotes assigned (blocks all pasos)'
         ELSE 'OK   – ' || lotes_asignados::text || ' lotes assigned'
    END
FROM g3_lotes
UNION ALL
SELECT '4_EJECUCIONES' AS gate, paso_id::text, operacion,
    gate_result
    || ' | completadas=' || exec_completadas::text
    || ' / lotes=' || lotes_asignados::text
    || ' | en_proceso=' || en_proceso_count::text
    || ' | paso.estado=' || paso_estado
FROM g4_ejecuciones
UNION ALL
SELECT '5_PROGRAMACION' AS gate, paso_id::text, operacion,
    gate_result || COALESCE(' (prog_id=' || prog_id::text || ', maquina=' || maquina_id::text || ')', '')
FROM g5_programacion
UNION ALL
SELECT '6_VERDICT' AS gate, paso_id::text, operacion, verdict
FROM verdict

ORDER BY gate, paso_id;


-- SELEcT * FROM mes.partida_paso_ejecucion WHERE partida_paso_id IN (7783)

--SELECT mes.get_partida(5194)


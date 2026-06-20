-- ═══════════════════════════════════════════════════════════════════════════════
-- PRECHECK: compactado partidas — inventory state + rework timeline analysis
-- Run this BEFORE insert_compactado_perchado_may2026.sql
--
-- RESULT SET 1 — per-partida inventory state
--   lotes_asignados   — rolls in partida_componente (required > 0)
--   lotes_en_stock    — rolls still in stock (not yet consumed)
--   lotes_consumidos  — rolls already hit by PROD_CONSUMO (script will skip these)
--   prod_ing_exists   — output lotes already created by a prior registrar_produccion
--   tiene_reprocesos  — script skips the parent; see Result Set 2 for rework routing
--
-- Expected "green" state:
--   lotes_asignados > 0, lotes_en_stock = lotes_asignados,
--   lotes_consumidos = 0, prod_ing_exists = false, tiene_reprocesos = false
--
-- RESULT SET 2 — rework routing (only for partidas flagged tiene_reprocesos = true)
--   For each rework child, shows whether the compactado run date falls inside
--   the rework's production window (fyh_inicio..fyh_fin).
--   alineado = true  → compactado run likely belongs to this rework child
--   alineado = false → run falls outside this rework's window; check manually
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── RESULT SET 1: inventory state ─────────────────────────────────────────────
WITH partidas AS (
    SELECT partida::bigint AS partida_id, TO_DATE(fecha, 'DD/MM/YYYY') AS run_fecha, 'mersan'::text AS fuente
    FROM public.mersan WHERE partida::text ~ '^\d+$'
    UNION ALL
    SELECT partida::bigint, TO_DATE(fecha, 'DD/MM/YYYY'), 'sertks1'
    FROM public.sertks1 WHERE partida::text ~ '^\d+$'
    UNION ALL
    SELECT partida::bigint, TO_DATE(fecha, 'DD/MM/YYYY'), 'sertks2'
    FROM public.sertks2 WHERE partida::text ~ '^\d+$'
),
lote_state AS (
    SELECT
        pc.partida_id,
        COUNT(pc.lote_id)                                                  AS lotes_asignados,
        COUNT(pc.lote_id) FILTER (WHERE stk.lote_id IS NOT NULL)           AS lotes_en_stock,
        COUNT(pc.lote_id) FILTER (WHERE consumo.lote_id IS NOT NULL)       AS lotes_consumidos,
        BOOL_OR(prod_ing.lote_id IS NOT NULL)                              AS prod_ing_exists
    FROM mes.partida_componente pc
    LEFT JOIN LATERAL (
        SELECT lote_id FROM inventario.vw_stock_lotes_ubicacion
        WHERE lote_id = pc.lote_id LIMIT 1
    ) stk ON true
    LEFT JOIN LATERAL (
        SELECT im.lote_id
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.lote_id = pc.lote_id AND imt.codigo = 'PROD_CONSUMO'
        LIMIT 1
    ) consumo ON true
    LEFT JOIN LATERAL (
        SELECT l.id AS lote_id
        FROM inventario.lote l
        JOIN inventario.item_movimientos im      ON im.lote_id = l.id
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        JOIN mes.partida_paso_ejecucion pe       ON pe.id = im.documento_id::bigint
                                                AND im.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp                 ON pp.id = pe.partida_paso_id
        WHERE pp.partida_id = pc.partida_id AND imt.codigo = 'PROD_ING'
        LIMIT 1
    ) prod_ing ON true
    WHERE pc.partida_id IN (SELECT partida_id FROM partidas)
    GROUP BY pc.partida_id
)
SELECT
    p.fuente,
    p.partida_id,
    p.run_fecha,
    pt.estado_produccion,
    COALESCE(ls.lotes_asignados,  0)     AS lotes_asignados,
    COALESCE(ls.lotes_en_stock,   0)     AS lotes_en_stock,
    COALESCE(ls.lotes_consumidos, 0)     AS lotes_consumidos,
    COALESCE(ls.prod_ing_exists,  false) AS prod_ing_exists,
    EXISTS (
        SELECT 1 FROM mes.partida WHERE partida_origen_id = p.partida_id
    )                                    AS tiene_reprocesos,
    CASE
        WHEN EXISTS (SELECT 1 FROM mes.partida WHERE partida_origen_id = p.partida_id)
            THEN '⚠ SALTADO — ver Resultado 2 para routing de reprocesos'
        WHEN COALESCE(ls.lotes_asignados, 0) = 0
            THEN '✗ SIN LOTES — registrar_produccion no hará nada'
        WHEN COALESCE(ls.lotes_consumidos, 0) > 0 OR COALESCE(ls.prod_ing_exists, false)
            THEN '⚠ PRODUCCION YA REGISTRADA (parcial o total)'
        WHEN COALESCE(ls.lotes_en_stock, 0) < COALESCE(ls.lotes_asignados, 0)
            THEN '⚠ LOTES FUERA DE STOCK — verificar movimientos'
        ELSE '✓ OK'
    END AS estado_precheck
FROM partidas p
LEFT JOIN lote_state ls  ON ls.partida_id = p.partida_id
LEFT JOIN mes.partida pt ON pt.id = p.partida_id
ORDER BY p.fuente, p.partida_id;


-- ── RESULT SET 2: rework routing ───────────────────────────────────────────────
-- Only shows rows for partidas that have rework children.
--
-- Overlap is determined by partida_paso_ejecucion.fyh_inicio/fyh_fin —
-- operator-recorded execution timestamps, which are the most reliable indicator
-- of when the rework actually ran (fyh_cre on partida is just system insert time).
--
-- exec_min / exec_max: earliest and latest ejecucion timestamps across all pasos
--   of the rework (converted to Lima local date). NULL = no ejecuciones yet.
-- alineado: run_fecha falls on or between exec_min and exec_max.
--   When exec_max is NULL (rework still running), upper bound = CURRENT_DATE.
--   When exec_min is NULL (no executions), alineado = NULL (unknown).
WITH partidas AS (
    SELECT partida::bigint AS partida_id, TO_DATE(fecha, 'DD/MM/YYYY') AS run_fecha, 'mersan'::text AS fuente
    FROM public.mersan WHERE partida::text ~ '^\d+$'
    UNION ALL
    SELECT partida::bigint, TO_DATE(fecha, 'DD/MM/YYYY'), 'sertks1'
    FROM public.sertks1 WHERE partida::text ~ '^\d+$'
    UNION ALL
    SELECT partida::bigint, TO_DATE(fecha, 'DD/MM/YYYY'), 'sertks2'
    FROM public.sertks2 WHERE partida::text ~ '^\d+$'
),
rework_exec AS (
    -- Earliest and latest ejecucion timestamps per rework partida
    SELECT
        pp.partida_id,
        MIN(pe.fyh_inicio AT TIME ZONE 'America/Lima')::date AS exec_min,
        MAX(COALESCE(pe.fyh_fin, pe.fyh_inicio) AT TIME ZONE 'America/Lima')::date AS exec_max
    FROM mes.partida_paso pp
    JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
    GROUP BY pp.partida_id
)
SELECT
    p.fuente,
    p.partida_id                                                AS partida_padre,
    p.run_fecha,
    rw.id                                                       AS reproceso_id,
    rw.estado_produccion                                        AS reproceso_estado,
    re.exec_min                                                 AS exec_primera_ejecucion,
    re.exec_max                                                 AS exec_ultima_ejecucion,
    CASE
        WHEN re.exec_min IS NULL THEN NULL
        ELSE p.run_fecha BETWEEN re.exec_min AND COALESCE(re.exec_max, CURRENT_DATE)
    END                                                         AS alineado,
    EXISTS (
        SELECT 1 FROM mes.partida_paso pp2
        JOIN mes.operacion o ON o.id = pp2.operacion_id
        WHERE pp2.partida_id = rw.id AND o.codigo = 'COMPACTADO'
    )                                                           AS ya_tiene_compactado,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM mes.partida_paso pp2
            JOIN mes.operacion o ON o.id = pp2.operacion_id
            WHERE pp2.partida_id = rw.id AND o.codigo = 'COMPACTADO'
        ) THEN '⚠ reproceso ya tiene COMPACTADO'
        WHEN re.exec_min IS NULL
            THEN '? sin ejecuciones — no se puede determinar ventana'
        WHEN p.run_fecha BETWEEN re.exec_min AND COALESCE(re.exec_max, CURRENT_DATE)
            THEN '→ registrar en reproceso ' || rw.id::text
        WHEN p.run_fecha < re.exec_min
            THEN '← run antes del reproceso — pertenece al padre ' || p.partida_id::text
        ELSE '? fuera de ventana — revisar manualmente'
    END                                                         AS accion_sugerida
FROM partidas p
JOIN mes.partida rw    ON rw.partida_origen_id = p.partida_id
LEFT JOIN rework_exec re ON re.partida_id = rw.id
ORDER BY p.fuente, p.partida_id, rw.id;

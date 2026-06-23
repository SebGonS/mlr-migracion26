-- validate_pasos_migration.sql
-- Validates migration of legacy execution events (produccion_tenido + perchado
-- + compactado + termofijado) into mes.partida_paso + mes.partida_paso_ejecucion.
--
-- For the deep pxr ↔ produccion_tenido join investigation that backs the join
-- choices below, see diagnostics/debug_pxr_produccion_tenido_join.sql.
--
-- STATUS values (§2):
--   MATCHED            → paso + ejecucion found, weight/rolls within tolerance
--   MISSING_PASO       → no mes.partida_paso row for this partida + operacion
--   MISSING_EJECUCION  → paso exists but no ejecucion on the legacy fecha
--   WEIGHT_DRIFT       → found but |new_peso_kg - legacy_kilos| > 1 (tenido only)
--   ROLL_DRIFT         → found but roll count differs
--
-- §1 — totals comparison (legacy vs new schema per root partida)
-- §2 — row-level detail with status per execution event
-- §3 — summary by operation + status


-- ── §1 Totals: legacy vs new per root partida (reworks rolled up) ─────────────
-- new_counts groups by COALESCE(partida_origen_id, id) so rework partidas
-- created by mes.crear_reproceso count against their original legacy partida_id.
WITH legacy_counts AS (
    SELECT partida_id, COUNT(*) AS n
    FROM (
        SELECT partida_id FROM produccion_tenido
        UNION ALL
        SELECT partida_id FROM perchado
        UNION ALL
        SELECT partida_id FROM compactado
        UNION ALL
        SELECT partida_id FROM termofijado
    ) t
    GROUP BY partida_id
),
new_counts AS (
    SELECT COALESCE(p.partida_origen_id, p.id) AS partida_id, COUNT(*) AS n
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    GROUP BY 1
)
SELECT
    COALESCE(l.partida_id, n.partida_id)    AS partida_id,
    COALESCE(l.n, 0)                        AS legacy_n,
    COALESCE(n.n, 0)                        AS new_n,
    COALESCE(l.n, 0) - COALESCE(n.n, 0)    AS diff
FROM legacy_counts l
FULL OUTER JOIN new_counts n USING (partida_id)
WHERE COALESCE(l.n, 0) != COALESCE(n.n, 0)
ORDER BY diff DESC;


-- ── §2 Row-level detail: one row per legacy execution event, with status ─────
WITH legacy AS (

    -- ── produccion_tenido: routes through pxr → tipo_receta for operacion_id ──
    SELECT
        'produccion_tenido'::text       AS source_table,
        pt.id                           AS legacy_id,
        pt.partida_id,
        tr.operacion_id,
        op.codigo                       AS operacion_codigo,
        pt.fecha,
        pt.maquina                      AS legacy_maquina,
        pt.rollos::int                  AS legacy_rollos,
        pt.kilos                        AS legacy_kilos,
        pt.hora_inicio,
        pt.hora_fin
    FROM produccion_tenido pt
    JOIN partida_x_recetas pxr
        ON  pxr.partida_id     = pt.partida_id
        AND pxr.fecha          = pt.fecha
        AND pxr.flg_elm        = false
        AND pxr.tipo_receta_id IS NOT NULL
    JOIN tipo_receta tr
        ON  tr.id              = pxr.tipo_receta_id
        AND tr.tipo_receta     = pt.tipo
    JOIN mes.operacion op ON op.id = tr.operacion_id
    WHERE pt.maquina = pxr.maquina_id   -- 1:1 pin: same machine on same date

    UNION ALL

    -- ── perchado ─────────────────────────────────────────────────────────────
    SELECT
        'perchado', pe.id, pe.partida_id, op.id, op.codigo,
        pe.fecha, NULL, pe.rollos, NULL, pe.hora_inicio, pe.hora_fin
    FROM perchado pe
    CROSS JOIN (SELECT id, codigo FROM mes.operacion WHERE codigo = 'PERCHADO') op

    UNION ALL

    -- ── compactado ───────────────────────────────────────────────────────────
    SELECT
        'compactado', c.id, c.partida_id, op.id, op.codigo,
        c.fecha, c.maquina_id, c.rollos, NULL, c.hora_inicio, c.hora_fin
    FROM compactado c
    CROSS JOIN (SELECT id, codigo FROM mes.operacion WHERE codigo = 'COMPACTADO') op

    UNION ALL

    -- ── termofijado ──────────────────────────────────────────────────────────
    SELECT
        'termofijado', t.id, t.partida_id, op.id, op.codigo,
        t.fecha, NULL, t.rollos, NULL, t.hora_inicio, t.hora_fin
    FROM termofijado t
    CROSS JOIN (SELECT id, codigo FROM mes.operacion WHERE codigo = 'TERMOFIJADO') op

),
joined AS (
    SELECT
        l.*,
        pp.id                           AS new_paso_id,
        pp.secuencia                    AS new_secuencia,
        ppe.id                          AS new_ejecucion_id,
        ppe.estado                      AS new_estado,
        ppe.fyh_inicio                  AS new_fyh_inicio,
        ppe.fyh_fin                     AS new_fyh_fin,
        ppe.peso_kg                     AS new_peso_kg,
        ppe.cantidad_rollos             AS new_rollos
    FROM legacy l
    LEFT JOIN mes.partida_paso pp
        ON  pp.partida_id   = l.partida_id
        AND pp.operacion_id = l.operacion_id
    LEFT JOIN mes.partida_paso_ejecucion ppe
        ON  ppe.partida_paso_id  = pp.id
        AND ppe.fyh_inicio::date = l.fecha
)
SELECT
    source_table,
    legacy_id,
    partida_id,
    operacion_codigo,
    fecha,
    legacy_maquina,
    legacy_rollos,
    legacy_kilos,
    hora_inicio,
    hora_fin,

    new_paso_id,
    new_secuencia,
    new_ejecucion_id,
    new_estado,
    new_fyh_inicio,
    new_fyh_fin,
    new_peso_kg,
    new_rollos,

    CASE
        WHEN new_paso_id      IS NULL THEN 'MISSING_PASO'
        WHEN new_ejecucion_id IS NULL THEN 'MISSING_EJECUCION'
        WHEN legacy_kilos     IS NOT NULL
         AND ABS(COALESCE(new_peso_kg, 0) - legacy_kilos) > 1
                                      THEN 'WEIGHT_DRIFT'
        WHEN legacy_rollos    IS NOT NULL
         AND new_rollos        IS NOT NULL
         AND new_rollos::int  != legacy_rollos
                                      THEN 'ROLL_DRIFT'
        ELSE 'MATCHED'
    END                               AS status

FROM joined
ORDER BY partida_id, operacion_codigo, fecha;


-- ── §3 Summary by operation + status ─────────────────────────────────────────
-- Wrap §2 (the legacy + joined CTEs and final SELECT) as a subquery `v` and:
-- SELECT source_table, operacion_codigo, status, COUNT(*) AS n
-- FROM v
-- GROUP BY 1, 2, 3
-- ORDER BY 1, 2, 3;

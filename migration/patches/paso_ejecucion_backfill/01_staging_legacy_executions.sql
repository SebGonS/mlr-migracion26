-- ============================================================================
-- 01 · Staging table: migration.legacy_executions            (paso-backfill step 01)
-- ============================================================================
-- Materializes the legacy execution base (produccion_tenido + perchado +
-- compactado + termofijado) into a workbench table for paso/ejecucion insertion.
--
-- WHY A STAGING TABLE:
--   · INSERT into partida_paso must precede INSERT into partida_paso_ejecucion
--     (need generated paso IDs). Cannot chain in a single CTE.
--   · Ordering (fecha ASC, then operacion priority) applied at INSERT time
--     over this table — not stored as a column.
--   · status column enables idempotent, resumable processing.
--
-- OPERACION PRIORITY (ORDER BY at INSERT time, not stored):
--   PREPARADO(1) → TERMOFIJADO(2) → TENIDO(3) → LAVADO_HIDRO(4) →
--   SECADO(5) → VOLTEADO(6) → PERCHADO(7) → COMPACTADO(8)
--
-- TIMESTAMP FORMULA (Peru → UTC, from migration-11 line ~1435):
--   (fecha + COALESCE(hora_inicio, '06:00'))::timestamp + interval '5 hours'
--
-- usr_cre: NULL for all rows — legacy tables do not carry operator tracking
--   (migration-11 also set usr_cre = NULL for migrated pasos).
--
-- produccion_tenido OPERACION:
--   EVERY produccion_tenido row IS a teñido-machine run → operacion = TENIDO,
--   unconditionally. The legacy `tipo` only selects the RECIPE, never the
--   operation (client-confirmed; see migration/patches/30_fix_lavado_hidro_to_tenido.sql).
--   The migration-11 tipo→LAVADO_HIDRO split (11_data_migration.sql:894) was the
--   bug patch 30 diagnosed; we do NOT reproduce it here. Recipe identity is not
--   carried in staging — it lives on the paso's receta_id — so the pxr/tipo_receta
--   join is gone. (Real LAVADO_HIDRO is the separate HIDRO-machine operation,
--   sourced post-go-live by the app, not from produccion_tenido.)
--
-- PREREQUISITES: step 00 applied (Reproceso Matizado operacion_id fixed).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS migration;

DROP TABLE IF EXISTS migration.legacy_executions;

CREATE TABLE migration.legacy_executions (
    id               SERIAL PRIMARY KEY,
    source_table     TEXT        NOT NULL,
    legacy_id        INT         NOT NULL,
    partida_id       INT         NOT NULL,
    operacion_id     INT         NOT NULL,
    operacion_codigo TEXT        NOT NULL,
    fecha            DATE,
    fyh_inicio       TIMESTAMPTZ,
    fyh_fin          TIMESTAMPTZ,
    legacy_maquina   INT,
    legacy_rollos    INT,
    legacy_kilos     NUMERIC,
    legacy_estado    TEXT,                   -- produccion_tenido split marker: 'En Proceso Teñido' (lead) vs 'Teñido' (completion). NULL for finishing sources (they don't stunt-split). Consumed by the patch-37 chain-merge.
    usr_cre          INT,                    -- NULL: no operator tracking in legacy
    -- filled after insertion (BIGINT to match the bigint IDENTITY PKs they reference):
    new_paso_id      BIGINT,
    new_ejecucion_id BIGINT,
    status           TEXT        NOT NULL DEFAULT 'PENDING',
    UNIQUE (source_table, legacy_id)
);

-- ── Populate ──────────────────────────────────────────────────────────────────
INSERT INTO migration.legacy_executions (
    source_table, legacy_id, partida_id, operacion_id, operacion_codigo,
    fecha, fyh_inicio, fyh_fin,
    legacy_maquina, legacy_rollos, legacy_kilos, legacy_estado, usr_cre
)

-- produccion_tenido: every row → operacion = TENIDO (see header). No pxr join,
-- so one staging row per pt row — no DISTINCT ON needed.
SELECT
    'produccion_tenido'::text,
    pt.id,
    pt.partida_id,
    op_tenido.id,
    'TENIDO'::text,
    pt.fecha,
    ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::timestamp
        + interval '5 hours')::timestamptz,
    CASE WHEN pt.hora_fin IS NOT NULL
         THEN ((pt.fecha + pt.hora_fin)::timestamp
               + interval '5 hours')::timestamptz
    END,
    pt.maquina,
    ROUND(pt.rollos)::int,
    pt.kilos,
    pt.estado,          -- lead/completion marker for the chain-merge
    NULL::int
FROM produccion_tenido pt
CROSS JOIN (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO') op_tenido

UNION ALL

-- perchado
SELECT
    'perchado', pe.id, pe.partida_id, op.id, op.codigo,
    pe.fecha,
    ((pe.fecha + COALESCE(pe.hora_inicio, '06:00'::time))::timestamp
        + interval '5 hours')::timestamptz,
    CASE WHEN pe.hora_fin IS NOT NULL
         THEN ((pe.fecha + pe.hora_fin)::timestamp + interval '5 hours')::timestamptz
    END,
    NULL, pe.rollos, NULL, NULL, NULL
FROM perchado pe
CROSS JOIN (SELECT id, codigo FROM mes.operacion WHERE codigo = 'PERCHADO') op

UNION ALL

-- compactado
SELECT
    'compactado', c.id, c.partida_id, op.id, op.codigo,
    c.fecha,
    ((c.fecha + COALESCE(c.hora_inicio, '06:00'::time))::timestamp
        + interval '5 hours')::timestamptz,
    CASE WHEN c.hora_fin IS NOT NULL
         THEN ((c.fecha + c.hora_fin)::timestamp + interval '5 hours')::timestamptz
    END,
    c.maquina_id, c.rollos, NULL, NULL, NULL
FROM compactado c
CROSS JOIN (SELECT id, codigo FROM mes.operacion WHERE codigo = 'COMPACTADO') op

UNION ALL

-- termofijado
SELECT
    'termofijado', t.id, t.partida_id, op.id, op.codigo,
    t.fecha,
    ((t.fecha + COALESCE(t.hora_inicio, '06:00'::time))::timestamp
        + interval '5 hours')::timestamptz,
    CASE WHEN t.hora_fin IS NOT NULL
         THEN ((t.fecha + t.hora_fin)::timestamp + interval '5 hours')::timestamptz
    END,
    NULL, t.rollos, NULL, NULL, NULL
FROM termofijado t
CROSS JOIN (SELECT id, codigo FROM mes.operacion WHERE codigo = 'TERMOFIJADO') op;

-- ── Verify ────────────────────────────────────────────────────────────────────
SELECT
    source_table,
    operacion_codigo,
    COUNT(*)                                        AS n,
    COUNT(*) FILTER (WHERE fyh_inicio IS NULL)      AS null_fyh_inicio,
    COUNT(*) FILTER (WHERE fyh_fin IS NULL)         AS null_fyh_fin,
    COUNT(*) FILTER (WHERE fecha IS NULL)           AS null_fecha
FROM migration.legacy_executions
GROUP BY 1, 2
ORDER BY 1, n DESC;




SELECT le.source_table, COUNT(*) AS candidate_split_pairs
FROM migration.legacy_executions a
JOIN migration.legacy_executions le
  ON le.source_table = a.source_table
 AND le.partida_id   = a.partida_id
 AND le.operacion_id = a.operacion_id
 AND le.fyh_inicio   = a.fyh_fin           -- row B starts exactly when row A ends
 AND a.fyh_fin::time = '00:00:00'           -- at a midnight boundary
GROUP BY 1;







-- 1. estado landscape
SELECT estado, COUNT(*) FROM produccion_tenido GROUP BY 1 ORDER BY 2 DESC;

-- 2. how many block-merge pairs exist (En partida Teñido → Teñido)
WITH m AS (
  SELECT partida_id, fecha, estado,
         LAG(estado) OVER (PARTITION BY partida_id ORDER BY fecha) AS prev
  FROM produccion_tenido WHERE estado IN ('En partida Teñido','Teñido'))
SELECT COUNT(*) AS merge_pairs FROM m
WHERE estado='Teñido' AND prev='En partida Teñido';

-- 3. did we migrate rows the legacy display EXCLUDES? (estado not in the two)
SELECT pt.estado, COUNT(*)
FROM migration.legacy_executions le
JOIN produccion_tenido pt ON pt.id = le.legacy_id
WHERE le.source_table='produccion_tenido'
  AND pt.estado NOT IN ('En partida Teñido','Teñido')
GROUP BY 1 ORDER BY 2 DESC;

-- 4. the quantity question: do paired rows duplicate or add up?
WITH m AS (
  SELECT partida_id, fecha, estado, rollos, kilos,
         LAG(estado) OVER w AS prev, LAG(rollos) OVER w AS rollos_prev,
         LAG(kilos)  OVER w AS kilos_prev
  FROM produccion_tenido WHERE estado IN ('En partida Teñido','Teñido')
  WINDOW w AS (PARTITION BY partida_id ORDER BY fecha))
SELECT rollos_prev, rollos, kilos_prev, kilos FROM m
WHERE estado='Teñido' AND prev='En partida Teñido' LIMIT 50;






WITH ordered AS (
  SELECT
    source_table, partida_id, operacion_id, legacy_maquina, legacy_rollos,
    fecha, fyh_inicio, fyh_fin,
    LEAD(fecha)          OVER w AS next_fecha,
    LEAD(fyh_inicio)     OVER w AS next_inicio,
    LEAD(legacy_maquina) OVER w AS next_maquina
  FROM migration.legacy_executions
  WINDOW w AS (PARTITION BY source_table, partida_id, operacion_id ORDER BY fyh_inicio)
)
SELECT
  source_table, partida_id, legacy_maquina,
  fecha AS fecha_a, next_fecha AS fecha_b,
  fyh_fin AS a_ends, next_inicio AS b_starts,
  next_inicio - fyh_fin                              AS gap,
  (next_fecha = fecha + 1)                           AS crosses_one_day,
  (legacy_maquina IS NOT DISTINCT FROM next_maquina) AS same_machine
FROM ordered
WHERE next_inicio IS NOT NULL AND fyh_fin IS NOT NULL
  AND next_inicio - fyh_fin BETWEEN interval '-1 hour' AND interval '6 hours'
ORDER BY source_table, partida_id, fyh_inicio;




WITH m AS (
  SELECT partida_id, maquina, fecha, estado, rollos,
         LAG(estado)  OVER w AS prev_estado,
         LAG(maquina) OVER w AS prev_maq,
         LAG(rollos)  OVER w AS prev_rollos
  FROM produccion_tenido
  WINDOW w AS (PARTITION BY partida_id ORDER BY fecha, id))
SELECT
  COUNT(*) FILTER (WHERE estado='Teñido' AND prev_estado='En Proceso Teñido')                          AS enproc_then_tenido,
  COUNT(*) FILTER (WHERE estado='Teñido' AND prev_estado='En Proceso Teñido' AND prev_maq=maquina
                                                                          AND prev_rollos=rollos)       AS looks_like_same_run
FROM m;



WITH t AS (
  SELECT partida_id, maquina, fecha, hora_inicio, hora_fin,
         LEAD(hora_fin)  OVER w AS next_end,
         LEAD(fecha)     OVER w AS next_row   -- NULL => last row in this partida+maquina group
  FROM produccion_tenido
  WINDOW w AS (PARTITION BY partida_id, maquina ORDER BY fecha, hora_inicio, id))
SELECT
  COUNT(*) FILTER (WHERE hora_fin IS NULL)                                  AS lead_rows,
  COUNT(*) FILTER (WHERE hora_fin IS NULL AND next_row IS NULL)             AS lead_no_successor,   -- open, never completed
  COUNT(*) FILTER (WHERE hora_fin IS NULL AND next_end IS NULL
                                          AND next_row IS NOT NULL)         AS multi_window_chain   -- 3+ row runs
FROM t;



-- Per partida: declared total vs NORMAL dyed total (reworks excluded — they re-dye the same rolls)
SELECT
  p.id AS partida_id,
  p.rollos                                              AS declared_rollos,
  ROUND((p.peso_rollos + COALESCE(p.peso_rib,0))::numeric, 2) AS declared_kg,
  SUM(pt.rollos)                                        AS dyed_rollos,
  ROUND(SUM(pt.kilos)::numeric, 2)                      AS dyed_kg
FROM partida p
JOIN produccion_tenido pt ON pt.partida_id = p.id
WHERE pt.tipo = 'Teñido'                       -- normal only
GROUP BY p.id, p.rollos, p.peso_rollos, p.peso_rib
HAVING SUM(pt.rollos) <> p.rollos
    OR ABS(SUM(pt.kilos) - (p.peso_rollos + COALESCE(p.peso_rib,0))) > 1
ORDER BY p.id;



SELECT 'produccion_tenido' src, COUNT(*) FILTER (WHERE hora_fin IS NULL) leads, COUNT(*) total FROM produccion_tenido
UNION ALL SELECT 'compactado',  COUNT(*) FILTER (WHERE hora_fin IS NULL), COUNT(*) FROM compactado
UNION ALL SELECT 'perchado',    COUNT(*) FILTER (WHERE hora_fin IS NULL), COUNT(*) FROM perchado
UNION ALL SELECT 'termofijado', COUNT(*) FILTER (WHERE hora_fin IS NULL), COUNT(*) FROM termofijado;



SELECT id, partida_id, fecha, hora_inicio, hora_fin, tipo, estado, maquina, rollos, kilos
FROM produccion_tenido
WHERE partida_id IN (294, 3045, 529, 4939, 5199, 3476)
ORDER BY partida_id, fecha, hora_inicio, id;



SELECT id, partida_id, fecha, hora_inicio, hora_fin, tipo, estado, maquina, rollos, kilos
FROM produccion_tenido
WHERE partida_id IN (294, 3045, 529, 4939, 5199, 3476)
ORDER BY partida_id, fecha, hora_inicio, id;




SELECT estado,
       COUNT(*)                                                              AS n,
       COUNT(*) FILTER (WHERE hora_fin IS NULL)                              AS end_null,
       COUNT(*) FILTER (WHERE hora_fin = '00:00:00')                         AS end_midnight,
       COUNT(*) FILTER (WHERE hora_fin IS NOT NULL AND hora_fin <> '00:00:00') AS end_real
FROM produccion_tenido
GROUP BY estado ORDER BY n DESC;


WITH open_runs AS (
  SELECT pt.partida_id, pt.maquina, pt.fecha, pt.hora_inicio, pt.rollos, pt.kilos
  FROM produccion_tenido pt
  WHERE pt.estado = 'En Proceso Teñido'
    AND NOT EXISTS (                     -- no later completion, same partida+machine
      SELECT 1 FROM produccion_tenido c
      WHERE c.partida_id = pt.partida_id
        AND c.maquina    = pt.maquina
        AND c.estado     = 'Teñido'
        AND (c.fecha, COALESCE(c.hora_inicio,'00:00'::time))
          > (pt.fecha, COALESCE(pt.hora_inicio,'00:00'::time))
    )
)
SELECT
  o.partida_id, o.fecha, o.rollos, o.kilos,
  COUNT(ppe.id) AS app_ejecuciones_post_golive
FROM open_runs o
LEFT JOIN mes.partida_paso pp  ON pp.partida_id = o.partida_id
LEFT JOIN mes.partida_paso_ejecucion ppe
       ON ppe.partida_paso_id = pp.id
      AND ppe.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz
GROUP BY o.partida_id, o.fecha, o.rollos, o.kilos
ORDER BY o.partida_id;




SELECT estado,
       COUNT(*)                                                              AS n,
       COUNT(*) FILTER (WHERE hora_fin IS NULL)                              AS end_null,
       COUNT(*) FILTER (WHERE hora_fin = '00:00:00')                         AS end_midnight,
       COUNT(*) FILTER (WHERE hora_fin IS NOT NULL AND hora_fin <> '00:00:00') AS end_real
FROM produccion_tenido
GROUP BY estado ORDER BY n DESC;




WITH open_runs AS (
  SELECT pt.partida_id, pt.maquina, pt.fecha, pt.hora_inicio, pt.rollos, pt.kilos
  FROM produccion_tenido pt
  WHERE pt.estado = 'En Proceso Teñido'
    AND NOT EXISTS (                     -- no later completion, same partida+machine
      SELECT 1 FROM produccion_tenido c
      WHERE c.partida_id = pt.partida_id
        AND c.maquina    = pt.maquina
        AND c.estado     = 'Teñido'
        AND (c.fecha, COALESCE(c.hora_inicio,'00:00'::time))
          > (pt.fecha, COALESCE(pt.hora_inicio,'00:00'::time))
    )
)
SELECT
  o.partida_id, o.fecha, o.rollos, o.kilos,
  COUNT(ppe.id) AS app_ejecuciones_post_golive
FROM open_runs o
LEFT JOIN mes.partida_paso pp  ON pp.partida_id = o.partida_id
LEFT JOIN mes.partida_paso_ejecucion ppe
       ON ppe.partida_paso_id = pp.id
      AND ppe.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz
GROUP BY o.partida_id, o.fecha, o.rollos, o.kilos
ORDER BY o.partida_id;

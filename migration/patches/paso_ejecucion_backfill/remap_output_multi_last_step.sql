-- ============================================================================
-- REMAP · Distribute tenido output across multi-last-step ejecuciones (207 partidas)
-- ============================================================================
-- WHAT: remap_output_to_last_step.sql skipped 207 partidas whose last finishing
--   step has MULTIPLE ejecuciones. Each ejecucion is an independent production
--   run with its own output batch. This script distributes the synthetic lote
--   pool across those runs arbitrarily:
--     · Lotes are ordered by lote.id (stable); ejecuciones by fyh_inicio, id.
--     · Each ejec claims a bucket sized by its cantidad_rollos.
--     · Overflow (pool > sum of ejec counts) goes to the last ejec chronologically.
--     · NULL/zero cantidad_rollos ejecuciones act as empty buckets; overflow
--       falls through to the last ejec regardless.
--   Rib/regular: same-timestamp rib/regular pairs were scrapped (merge_rib_regular
--   rolled back). Chronologically distinct runs are treated as separate batches;
--   any rib lotes present are distributed into whatever bucket covers their rank.
--   If the pool clearly splits rib vs regular by count matching an ejec's
--   cantidad_rollos, that emerges naturally from the ordered assignment.
--
-- RE-POINTS (same as remap_output_to_last_step.sql):
--   · inventario.lote.documento_id  (produced-by marker output views read)
--   · production INGRESO in item_movimientos (origen NULL, destino set)
--   Egresos are LEFT on the tenido ejecucion (step that consumed input rolls).
--
-- Covers all 207 multi-last-step cases including:
--   · 205 COMPACTADO-last partidas
--   · 1 PERCHADO-last (5862)
--   · 1 TENIDO-last with 2 runs (5358) — distributes across the 2 tenido ejecs
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- ── Section 0 · DRY RUN — scope ───────────────────────────────────────────────
WITH lote_pool AS (
    SELECT l.id AS lote_id, pp.partida_id, tppe.id AS tenido_ejec_id,
           ROW_NUMBER() OVER (PARTITION BY pp.partida_id ORDER BY l.id) AS lote_rank
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion tppe ON tppe.id = l.documento_id
                                        AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = tppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
),
step_ejec AS (
    SELECT lp.partida_id, op.codigo,
           CASE op.codigo WHEN 'COMPACTADO' THEN 8 WHEN 'PERCHADO' THEN 7
                          WHEN 'VOLTEADO'   THEN 6 WHEN 'SECADO'   THEN 5
                          WHEN 'LAVADO_HIDRO' THEN 4 WHEN 'TENIDO' THEN 3
                          WHEN 'TERMOFIJADO' THEN 2 WHEN 'PREPARADO' THEN 1 ELSE 0 END AS prio,
           COUNT(DISTINCT ppe.id) AS n_ejec  -- DISTINCT: lote_pool has N rows/partida; avoid lote×ejec inflation
    FROM lote_pool lp
    JOIN mes.partida_paso pp            ON pp.partida_id = lp.partida_id
    JOIN mes.operacion op               ON op.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
    GROUP BY lp.partida_id, op.codigo
),
last_step AS (
    SELECT DISTINCT ON (partida_id) partida_id, codigo AS last_op, n_ejec
    FROM step_ejec ORDER BY partida_id, prio DESC
),
multi_last AS (SELECT partida_id, last_op FROM last_step WHERE n_ejec > 1)
SELECT
    ml.last_op,
    COUNT(DISTINCT ml.partida_id)                                             AS partidas,
    (SELECT COUNT(*) FROM lote_pool lp2 WHERE lp2.partida_id IN (SELECT partida_id FROM multi_last)) AS lotes_to_distribute,
    AVG(ls2.n_ejec)::numeric(5,1)                                             AS avg_ejec_per_partida
FROM multi_last ml
JOIN last_step ls2 ON ls2.partida_id = ml.partida_id
GROUP BY ml.last_op ORDER BY 2 DESC;


-- ── Section 1 · Build assignment + remap ──────────────────────────────────────
BEGIN;

CREATE TEMP TABLE _assign AS
WITH lote_pool AS (
    SELECT l.id AS lote_id, pp.partida_id, tppe.id AS tenido_ejec_id,
           ROW_NUMBER() OVER (PARTITION BY pp.partida_id ORDER BY l.id) AS lote_rank
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion tppe ON tppe.id = l.documento_id
                                        AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = tppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
),
step_ejec AS (
    SELECT lp.partida_id, op.codigo,
           CASE op.codigo WHEN 'COMPACTADO' THEN 8 WHEN 'PERCHADO' THEN 7
                          WHEN 'VOLTEADO'   THEN 6 WHEN 'SECADO'   THEN 5
                          WHEN 'LAVADO_HIDRO' THEN 4 WHEN 'TENIDO' THEN 3
                          WHEN 'TERMOFIJADO' THEN 2 WHEN 'PREPARADO' THEN 1 ELSE 0 END AS prio,
           COUNT(DISTINCT ppe.id) AS n_ejec  -- DISTINCT: avoids lote×ejec inflation
    FROM lote_pool lp
    JOIN mes.partida_paso pp            ON pp.partida_id = lp.partida_id
    JOIN mes.operacion op               ON op.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
    GROUP BY lp.partida_id, op.codigo
),
last_step AS (
    SELECT DISTINCT ON (partida_id) partida_id, codigo AS last_op, n_ejec
    FROM step_ejec ORDER BY partida_id, prio DESC
),
multi_last AS (SELECT partida_id, last_op FROM last_step WHERE n_ejec > 1),
ejec_list AS (
    SELECT ml.partida_id, ppe.id AS ejec_id,
           COALESCE(ppe.cantidad_rollos, 0) AS ejec_rollos,
           ROW_NUMBER() OVER (PARTITION BY ml.partida_id ORDER BY ppe.fyh_inicio, ppe.id) AS ejec_rank,
           COUNT(*)    OVER (PARTITION BY ml.partida_id)                                   AS n_ejec
    FROM multi_last ml
    JOIN mes.partida_paso pp            ON pp.partida_id = ml.partida_id
    JOIN mes.operacion op               ON op.id = pp.operacion_id AND op.codigo = ml.last_op
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
),
ejec_cumulative AS (
    SELECT *,
           COALESCE(SUM(ejec_rollos) OVER (PARTITION BY partida_id ORDER BY ejec_rank
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) + 1 AS range_start,
           SUM(ejec_rollos) OVER (PARTITION BY partida_id ORDER BY ejec_rank
                        ROWS UNBOUNDED PRECEDING)                                   AS range_end
    FROM ejec_list
),
assignment AS (
    SELECT lp.lote_id, lp.tenido_ejec_id,
           -- Pick first ejec whose range covers this rank; last ejec has no upper bound (absorbs overflow)
           (SELECT ec.ejec_id FROM ejec_cumulative ec
            WHERE ec.partida_id = lp.partida_id
              AND lp.lote_rank >= ec.range_start
              AND (lp.lote_rank <= ec.range_end OR ec.ejec_rank = ec.n_ejec)
            ORDER BY ec.ejec_rank LIMIT 1) AS target_ejec_id
    FROM lote_pool lp
    WHERE lp.partida_id IN (SELECT partida_id FROM multi_last)
)
SELECT * FROM assignment;

-- 1a. re-point the output lote's produced-by marker
UPDATE inventario.lote l
SET documento_id = a.target_ejec_id
FROM _assign a
WHERE l.id = a.lote_id AND l.documento_tipo = 'partida_paso_ejecucion';

-- 1b. re-point the production INGRESO (origen NULL, destino set). Leave egresos.
UPDATE inventario.item_movimientos im
SET documento_id = a.target_ejec_id
FROM _assign a
WHERE im.lote_id            = a.lote_id
  AND im.documento_tipo     = 'partida_paso_ejecucion'
  AND im.documento_id       = a.tenido_ejec_id
  AND im.origen_ubicacion_id  IS NULL
  AND im.destino_ubicacion_id IS NOT NULL;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) every assigned lote now points at its target — expect 0
SELECT COUNT(*) AS lotes_not_on_target
FROM _assign a
JOIN inventario.lote l ON l.id = a.lote_id
WHERE l.documento_id <> a.target_ejec_id;

-- (b) every ingreso now on target — expect 0 for COMPACTADO/PERCHADO partidas.
--   For TENIDO-last partidas (last_op=TENIDO), tenido IS the target, so they
--   appear here but are correct. After COUNT(DISTINCT) fix in step_ejec, only
--   genuine multi-tenido-run partidas (e.g. 5358) appear in scope.
SELECT COUNT(*) AS ingresos_still_on_tenido
FROM _assign a
JOIN inventario.item_movimientos im ON im.lote_id       = a.lote_id
                                    AND im.documento_tipo = 'partida_paso_ejecucion'
                                    AND im.origen_ubicacion_id  IS NULL
                                    AND im.destino_ubicacion_id IS NOT NULL
WHERE im.documento_id = a.tenido_ejec_id;

-- (c) egresos left on tenido — informational, should be > 0
SELECT COUNT(*) AS egresos_left_on_tenido
FROM _assign a
JOIN inventario.item_movimientos im ON im.lote_id       = a.lote_id
                                    AND im.documento_tipo = 'partida_paso_ejecucion'
                                    AND im.origen_ubicacion_id IS NOT NULL
WHERE im.documento_id = a.tenido_ejec_id;

-- (d) distribution summary — lotes per ejec per partida (spot-check a few)
SELECT a.target_ejec_id, COUNT(*) AS lotes_assigned
FROM _assign a
GROUP BY a.target_ejec_id
ORDER BY lotes_assigned DESC LIMIT 20;

-- (e) any lote with NULL target (shouldn't happen) — expect 0
SELECT COUNT(*) AS null_target FROM _assign WHERE target_ejec_id IS NULL;

DROP TABLE _assign;

-- COMMIT;   -- ← after §2 all zeros + sensible distribution
-- ROLLBACK; -- ← if anything is off


SELECT distinct guia FROM public.partida

SELECT
    CASE
        WHEN guia IS NULL THEN 'NULL'
        WHEN btrim(guia) = '' THEN 'Empty'

        -- only digits
        WHEN guia ~ '^[0-9]+$' THEN 'Numeric'

        -- numeric with leading zeros
        WHEN guia ~ '^0+[0-9]+$' THEN 'Numeric (leading zeros)'

        -- dash-separated numbers
        WHEN guia ~ '^[0-9]+(-[0-9]+)+$' THEN 'Numeric list (-)'

        -- slash-separated
        WHEN guia ~ '^[0-9]+(/[0-9]+)+$' THEN 'Numeric list (/)'

        -- comma-separated
        WHEN guia ~ '^[0-9]+(,[0-9]+)+$' THEN 'Numeric list (,)'

        -- starts with letters
        WHEN guia ~ '^[A-Za-z]' THEN 'Starts with letters'

        -- contains letters somewhere
        WHEN guia ~ '[A-Za-z]' THEN 'Contains letters'

        -- whitespace
        WHEN guia <> btrim(guia) THEN 'Leading/trailing spaces'

        ELSE 'Other'
    END AS pattern,
    COUNT(*) AS cantidad
FROM public.partida
GROUP BY pattern
ORDER BY cantidad DESC;
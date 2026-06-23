-- debug_pxr_produccion_tenido_join.sql
-- One-time investigation of the legacy join produccion_tenido ↔ partida_x_recetas
-- ↔ tipo_receta, used to validate the migration of dyeing runs into mes.partida_paso.
-- Ground truth = produccion_tenido (the dyeing-machine production log).
--
-- KEY DOMAIN FACT (confirmed with client):
--   Every produccion_tenido row IS a TEÑIDO operation. `tipo` only selects the
--   recipe (re-dye, strip, wash-on-dye-machine…), never a different operation.
--   → tipo maps to receta_id, NOT operacion_id. The migration-11 split of some
--     tipos to LAVADO_HIDRO is a bug (fixed in migration/patches/30_*).
--
-- Findings summary (run date 2026-06-21, ~6688 produccion_tenido rows):
--   4346 matched · 1494 fecha-only · 490 maquina-only · 249 tipo · 109 no-partida
--   Vocabularies are the same domain (§0d): 15 shared labels, 4 PT_ONLY
--   (Lavado, Reproceso Antiguo/Desmontado/Otros), zero whitespace/case drift.
--   Real client-discussion edge cases ≈ 39 (recipe-less reprocesos + 1 lost partida).

-- ── §0a: pt rows with NO matching pxr (orphaned executions) ──────────────────
SELECT pt.id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina, pt.kilos, pt.rollos
FROM produccion_tenido pt
WHERE NOT EXISTS (
    SELECT 1
    FROM partida_x_recetas pxr
    JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
    WHERE pxr.partida_id  = pt.partida_id
      AND pxr.fecha       = pt.fecha
      AND tr.tipo_receta  = pt.tipo
      AND pxr.maquina_id  = pt.maquina
      AND pxr.flg_elm     = false
)
ORDER BY pt.partida_id, pt.fecha;

-- ── §0a': classify EACH orphaned pt row by which condition blocks the match ──
-- Probes progressively looser keys. The first level that finds a pxr tells you
-- which column is the culprit. GROUP BY block_reason for a tally.
WITH probe AS (
    SELECT
        pt.id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina,
        EXISTS (SELECT 1 FROM partida_x_recetas pxr
                WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false)
                                                                AS has_partida,
        EXISTS (SELECT 1 FROM partida_x_recetas pxr
                JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
                WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false
                  AND tr.tipo_receta = pt.tipo)                 AS has_partida_tipo,
        EXISTS (SELECT 1 FROM partida_x_recetas pxr
                JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
                WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false
                  AND tr.tipo_receta = pt.tipo
                  AND pxr.maquina_id = pt.maquina)              AS has_partida_tipo_maq,
        EXISTS (SELECT 1 FROM partida_x_recetas pxr
                JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
                WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false
                  AND tr.tipo_receta = pt.tipo
                  AND pxr.maquina_id = pt.maquina
                  AND pxr.fecha      = pt.fecha)                AS has_all
    FROM produccion_tenido pt
)
SELECT
    CASE
        WHEN has_all              THEN 'MATCHES (not orphaned)'
        WHEN NOT has_partida      THEN '1_NO_PARTIDA_IN_PXR'
        WHEN NOT has_partida_tipo THEN '2_TIPO_MISMATCH'
        WHEN NOT has_partida_tipo_maq THEN '3_MAQUINA_MISMATCH'
        ELSE                           '4_FECHA_MISMATCH'
    END                          AS block_reason,
    COUNT(*)                     AS n
FROM probe
GROUP BY 1
ORDER BY 1;

-- ── §0b: pt.tipo values that map to nothing in tipo_receta ───────────────────
SELECT DISTINCT pt.tipo, COUNT(*) AS n
FROM produccion_tenido pt
WHERE NOT EXISTS (
    SELECT 1 FROM tipo_receta tr WHERE tr.tipo_receta = pt.tipo
)
GROUP BY pt.tipo
ORDER BY n DESC;

-- ── §0d: are the two vocabularies the same domain? Full side-by-side ──────────
-- side = BOTH / PT_ONLY / RECETA_ONLY. pt_len vs receta_len exposes case/accent/
-- whitespace near-duplicates.
WITH pt_vocab AS (
    SELECT DISTINCT lower(trim(tipo)) AS norm, tipo AS raw FROM produccion_tenido
),
tr_vocab AS (
    SELECT DISTINCT lower(trim(tipo_receta)) AS norm, tipo_receta AS raw FROM tipo_receta
)
SELECT
    COALESCE(p.norm, t.norm)            AS norm_label,
    p.raw                               AS pt_raw,
    length(p.raw)                       AS pt_len,
    t.raw                               AS receta_raw,
    length(t.raw)                       AS receta_len,
    CASE
        WHEN p.norm IS NOT NULL AND t.norm IS NOT NULL THEN 'BOTH'
        WHEN p.norm IS NOT NULL                        THEN 'PT_ONLY'
        ELSE                                                'RECETA_ONLY'
    END                                 AS side
FROM pt_vocab p
FULL OUTER JOIN tr_vocab t USING (norm)
ORDER BY side, norm_label;

-- ── §0c: pt rows that match MORE than one pxr (would fan out) ─────────────────
SELECT pt.id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina, COUNT(*) AS pxr_matches
FROM produccion_tenido pt
JOIN partida_x_recetas pxr
    ON  pxr.partida_id  = pt.partida_id
    AND pxr.fecha       = pt.fecha
    AND pxr.flg_elm     = false
    AND pxr.maquina_id  = pt.maquina
JOIN tipo_receta tr
    ON  tr.id           = pxr.tipo_receta_id
    AND tr.tipo_receta  = pt.tipo
GROUP BY pt.id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina
HAVING COUNT(*) > 1
ORDER BY pxr_matches DESC;

-- ── §0c2: lay the colliding pxr rows side by side — what actually differs? ────
--   distinct_recetas = 1 → exact dupes (safe to dedup, keep MAX(rollos)/MIN(id))
--   distinct_recetas > 1 → different recipes sharing a tipo (compound op, not a dupe)
SELECT
    pxr.partida_id,
    pxr.fecha,
    pxr.maquina_id,
    tr.tipo_receta,
    COUNT(*)                              AS pxr_rows,
    COUNT(DISTINCT pxr.receta_id)         AS distinct_recetas,
    array_agg(pxr.id        ORDER BY pxr.id) AS pxr_ids,
    array_agg(pxr.receta_id ORDER BY pxr.id) AS receta_ids,
    array_agg(pxr.rollos    ORDER BY pxr.id) AS rollos_each
FROM partida_x_recetas pxr
JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
WHERE pxr.flg_elm = false
GROUP BY pxr.partida_id, pxr.fecha, pxr.maquina_id, tr.tipo_receta
HAVING COUNT(*) > 1
ORDER BY distinct_recetas DESC, pxr_rows DESC;

-- ── §0c3: pt-side fan-out — does ONE pxr map to multiple pt executions? ───────
-- Legit re-runs/continuations (1 paso → N ejecuciones), not an error.
SELECT pxr_id, COUNT(*) AS pt_executions
FROM (
    SELECT pxr.id AS pxr_id, pt.id AS pt_id
    FROM partida_x_recetas pxr
    JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
    JOIN produccion_tenido pt
        ON  pt.partida_id = pxr.partida_id
        AND pt.fecha      = pxr.fecha
        AND pt.maquina    = pxr.maquina_id
        AND pt.tipo       = tr.tipo_receta
    WHERE pxr.flg_elm = false
) m
GROUP BY pxr_id
HAVING COUNT(*) > 1
ORDER BY pt_executions DESC;

-- ── §0e: break the 2_TIPO_MISMATCH bucket down by label ──────────────────────
SELECT pt.tipo, COUNT(*) AS n,
       EXISTS (SELECT 1 FROM tipo_receta tr WHERE tr.tipo_receta = pt.tipo) AS tipo_exists_in_receta,
       (SELECT tr.operacion_id FROM tipo_receta tr WHERE tr.tipo_receta = pt.tipo LIMIT 1) AS mapped_op
FROM produccion_tenido pt
WHERE EXISTS (SELECT 1 FROM partida_x_recetas pxr
              WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false)
  AND NOT EXISTS (SELECT 1 FROM partida_x_recetas pxr
                  JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
                  WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false
                    AND tr.tipo_receta = pt.tipo)
GROUP BY pt.tipo
ORDER BY n DESC;

-- ── §0f: characterize the 1_NO_PARTIDA_IN_PXR bucket ─────────────────────────
SELECT pt.tipo,
       COUNT(*) AS n,
       COUNT(*) FILTER (WHERE p.partida_origen_id IS NOT NULL) AS landed_as_rework,
       COUNT(*) FILTER (WHERE p.id IS NULL)                    AS no_new_partida_at_all
FROM produccion_tenido pt
LEFT JOIN mes.partida p ON p.id = pt.partida_id
WHERE NOT EXISTS (SELECT 1 FROM partida_x_recetas pxr
                  WHERE pxr.partida_id = pt.partida_id AND pxr.flg_elm = false)
GROUP BY pt.tipo
ORDER BY n DESC;

-- ── §0g: prove FECHA/MAQUINA are SAFE to relax (no ambiguity) ────────────────
-- Relaxing the join to (partida, tipo) should resolve to exactly ONE pxr.
-- Any pxr_matches>1 needs fecha as a tiebreaker.
SELECT pxr_matches, COUNT(*) AS pt_rows
FROM (
    SELECT pt.id, COUNT(*) AS pxr_matches
    FROM produccion_tenido pt
    JOIN partida_x_recetas pxr
        ON pxr.partida_id = pt.partida_id AND pxr.flg_elm = false
    JOIN tipo_receta tr
        ON tr.id = pxr.tipo_receta_id AND tr.tipo_receta = pt.tipo
    GROUP BY pt.id
) m
GROUP BY pxr_matches
ORDER BY pxr_matches;

-- ── §0y: DOMAIN CHECK — is every dyeing run migrated as TENIDO? ──────────────
-- Any non-TENIDO operacion here (esp. LAVADO_HIDRO) is the migration-11 mis-split.
-- Fix lives in migration/patches/30_fix_lavado_hidro_to_tenido.sql.
SELECT op.codigo AS paso_operacion, COUNT(*) AS pasos
FROM mes.partida_paso pp
JOIN mes.operacion op ON op.id = pp.operacion_id
JOIN mes.partida p    ON p.id = pp.partida_id
WHERE EXISTS (
    SELECT 1 FROM produccion_tenido pt
    WHERE pt.partida_id = COALESCE(p.partida_origen_id, p.id)
)
GROUP BY op.codigo
ORDER BY pasos DESC;

-- ── §0z: CLIENT-DISCUSSION EXTRACT — the rows that don't map cleanly ─────────
--   REPROCESO_SIN_RECETA   → rework run with no recipe type recorded
--   COMPUESTO_MULTI_RECETA  → one execution used >1 distinct recipe
--   PARTIDA_INEXISTENTE     → legacy partida absent from new schema entirely
SELECT pt.id AS pt_id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina, pt.kilos, pt.rollos,
       'REPROCESO_SIN_RECETA' AS reason
FROM produccion_tenido pt
WHERE pt.tipo IN ('Reproceso Otros', 'Reproceso Desmontado', 'Reproceso Antiguo')

UNION ALL

SELECT pt.id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina, pt.kilos, pt.rollos,
       'COMPUESTO_MULTI_RECETA'
FROM produccion_tenido pt
WHERE EXISTS (
    SELECT 1
    FROM partida_x_recetas pxr
    JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
    WHERE pxr.partida_id = pt.partida_id
      AND pxr.fecha      = pt.fecha
      AND pxr.maquina_id = pt.maquina
      AND tr.tipo_receta = pt.tipo
      AND pxr.flg_elm    = false
    GROUP BY pxr.partida_id, pxr.fecha, pxr.maquina_id, tr.tipo_receta
    HAVING COUNT(DISTINCT pxr.receta_id) > 1
)

UNION ALL

SELECT pt.id, pt.partida_id, pt.fecha, pt.tipo, pt.maquina, pt.kilos, pt.rollos,
       'PARTIDA_INEXISTENTE'
FROM produccion_tenido pt
LEFT JOIN mes.partida p ON p.id = pt.partida_id
WHERE p.id IS NULL

ORDER BY reason, partida_id, fecha;

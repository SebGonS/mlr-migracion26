-- ============================================================================
-- 02 · LINK staging rows to existing mes.partida_paso rows    (paso-backfill step 02)
-- ============================================================================
-- Writes new_paso_id into migration.legacy_executions for every staging row
-- that already has a matching paso in the new schema.
--
-- TWO LINK STRATEGIES (run in order):
--
--   STEP A — REWORK teñido runs, linked by legacy_id (pp.id = pt.id).
--     produccion_tenido rows with tipo != 'Teñido' are REPROCESO runs. migration-11
--     (11_data_migration.sql:1443-1528) turned each into its OWN child mes.partida
--     (partida_origen_id → original) plus a paso with pp.id = pt.id under that CHILD
--     partida. Staging carries partida_id = the ORIGINAL partida, so the (partida,
--     operacion) key in Step B would mislink these onto the parent's normal teñido
--     paso (or leave them unlinked → a duplicate paso in step 03). Instead we link
--     them DIRECTLY: new_paso_id = pp.id where pp.id = legacy_id. Each rework is its
--     own partida with a single paso, so there is nothing to canonicalize.
--
--   STEP B — everything else, by (partida_id, operacion_id) → MIN(pp.id).
--     · NORMAL teñido (tipo='Teñido'): migration-11 used OVERRIDING SYSTEM VALUE
--       so pp.id = pt.id, but the new model is ONE paso per (partida, operacion)
--       with multiple ejecuciones — a partida with 3 normal runs has pp.ids
--       {100,200,300}, canonicalized to MIN(pp.id)=100; extras removed later.
--     · perchado/compactado/termofijado: 06b used auto-generated ids, so legacy_id
--       carries no stable pp.id mapping — (partida, operacion) is the only key.
--     Step B EXCLUDES rework teñido rows so they can never attach to the parent.
--     NOTE: finishing ops (perchado/compactado/termofijado) performed on REWORKED
--     rolls still carry the ORIGINAL partida_id here and are NOT yet redirected to
--     the rework child partida — that remap is a separate, later step (pending the
--     roll-quantity matching rule).
--
--   WHY NOT date matching (Step B):
--     · Some pasos were inserted by the pre-06b script (06_migrar_despachos_y_produccion)
--       which used now() as fyh_cre (migration run time, not production date).
--       06b deleted and rebuilt most of them, but any survivors would break a
--       date filter. (partida_id, operacion_id) is unambiguous without dates.
--     · now()-stamped survivors ARE found by the link (join doesn't use date).
--       Verify #4 below surfaces them so their fyh_cre can be fixed.
--
-- CANONICALIZATION: when multiple pasos exist per (partida, operacion) —
--   MIN(pp.id) is chosen (the oldest). All staging rows for that group get the
--   same new_paso_id. Extra pasos are cleaned up before ejecucion insertion.
--
-- MIDNIGHT-SPLIT RUNS: the LINK is invariant to them. A continuous run that the
--   legacy system split across 00:00 produces two staging rows with the same
--   (partida_id, operacion_id), so both link to the same canonical paso anyway.
--   Whether those halves stay separate or merge into one ejecucion is decided at
--   ejecucion-insertion time (step 05), not here.
--
-- STATUS: sets status = 'LINKED' on every row it links, so the LINK step is
--   observable independently of new_paso_id and the staging state machine
--   introduced in step 01 is actually honored.
--
-- PREREQUISITES: step 01 applied (migration.legacy_executions populated).
-- ============================================================================


-- ── DRY RUN ──────────────────────────────────────────────────────────────────
-- Shows what would be linked. Check:
--   · linked_paso_id = MIN paso id per (partida, operacion)
--   · n_existing_pasos > 1 = consolidation case (extra pasos to merge later)
--   · n_staging_rows > 1 = multiple executions pointing to the same paso (good)
SELECT
    le.source_table,
    le.operacion_codigo,
    le.partida_id,
    canonical.paso_id            AS linked_paso_id,
    canonical.n_existing_pasos,
    COUNT(le.id)                 AS n_staging_rows
FROM migration.legacy_executions le
JOIN (
    SELECT
        pp.partida_id,
        pp.operacion_id,
        MIN(pp.id)   AS paso_id,
        COUNT(pp.id) AS n_existing_pasos
    FROM mes.partida_paso pp
    GROUP BY pp.partida_id, pp.operacion_id
) canonical
    ON  canonical.partida_id   = le.partida_id
    AND canonical.operacion_id = le.operacion_id
GROUP BY le.source_table, le.operacion_codigo, le.partida_id,
         canonical.paso_id, canonical.n_existing_pasos
ORDER BY canonical.n_existing_pasos DESC, le.partida_id
LIMIT 100;


-- ── Summary before LINK ───────────────────────────────────────────────────────
SELECT
    source_table,
    operacion_codigo,
    COUNT(*)                                        AS total,
    COUNT(*) FILTER (WHERE new_paso_id IS NOT NULL) AS already_linked,
    COUNT(*) FILTER (WHERE new_paso_id IS NULL)     AS unlinked
FROM migration.legacy_executions
GROUP BY 1, 2
ORDER BY 1, 2;


-- 1. Staging rows with NO matching paso (need INSERT in step 03)
SELECT
    le.source_table,
    le.operacion_codigo,
    COUNT(*) AS n_unmatched
FROM migration.legacy_executions le
LEFT JOIN (
    SELECT partida_id, operacion_id, MIN(id) AS paso_id
    FROM mes.partida_paso
    GROUP BY partida_id, operacion_id
) canonical
    ON  canonical.partida_id   = le.partida_id
    AND canonical.operacion_id = le.operacion_id
WHERE canonical.paso_id IS NULL
GROUP BY 1, 2
ORDER BY 1, 2;

-- 2. Existing pasos with NO matching staging row (orphans / now()-dated ghosts)
SELECT
    op.codigo               AS operacion_codigo,
    COUNT(pp.id)            AS n_orphan_pasos,
    MIN(pp.fyh_cre)         AS earliest_fyh_cre,
    MAX(pp.fyh_cre)         AS latest_fyh_cre,
    COUNT(*) FILTER (
        WHERE pp.fyh_cre::date
              BETWEEN '2026-05-25' AND '2026-05-26'
    )                       AS n_migration_timestamp   -- now()-stamped ones
FROM mes.partida_paso pp
JOIN mes.operacion op ON op.id = pp.operacion_id
WHERE op.codigo IN ('TENIDO','PERCHADO','COMPACTADO','TERMOFIJADO','LAVADO_HIDRO')
  AND NOT EXISTS (
        SELECT 1 FROM migration.legacy_executions le
        WHERE le.partida_id   = pp.partida_id
          AND le.operacion_id = pp.operacion_id
  )
GROUP BY op.codigo
ORDER BY n_orphan_pasos DESC;


SELECT
  (pt.tipo = 'Teñido')                              AS is_normal,
  COUNT(*)                                          AS n_rows,
  COUNT(pp.id)                                      AS has_paso_by_legacy_id,
  COUNT(*) FILTER (WHERE pp.partida_id <> pt.partida_id) AS paso_under_child_partida
FROM produccion_tenido pt
LEFT JOIN mes.partida_paso pp ON pp.id = pt.id
GROUP BY 1;


WITH rework AS (
  SELECT partida_id, rollos FROM produccion_tenido WHERE tipo <> 'Teñido'
)
SELECT
  f.source_table,
  COUNT(*)                                    AS finishing_on_rework_partidas,
  COUNT(*) FILTER (WHERE m.n = 1)             AS unambiguous_by_rollqty,
  COUNT(*) FILTER (WHERE m.n > 1)             AS ambiguous_by_rollqty,
  COUNT(*) FILTER (WHERE m.n = 0)             AS no_rollqty_match
FROM (
  SELECT 'perchado'    src, partida_id, rollos FROM perchado
  UNION ALL SELECT 'compactado',  partida_id, rollos FROM compactado
  UNION ALL SELECT 'termofijado', partida_id, rollos FROM termofijado
) f(source_table, partida_id, rollos)
JOIN LATERAL (
  SELECT COUNT(*) AS n FROM rework r
  WHERE r.partida_id = f.partida_id AND r.rollos = f.rollos
) m ON true
WHERE EXISTS (SELECT 1 FROM rework r WHERE r.partida_id = f.partida_id)
GROUP BY f.source_table;


-- ── LINK UPDATE ───────────────────────────────────────────────────────────────
BEGIN;

-- STEP A — REWORK teñido runs → their own child-partida paso (pp.id = pt.id).
--   Direct legacy_id link; never canonicalized into the parent partida.
UPDATE migration.legacy_executions le
SET new_paso_id = pp.id,
    status      = 'LINKED'
FROM produccion_tenido pt
JOIN mes.partida_paso pp ON pp.id = pt.id
WHERE le.source_table = 'produccion_tenido'
  AND le.legacy_id    = pt.id
  AND pt.tipo        <> 'Teñido'        -- REPROCESO run
  AND le.new_paso_id IS NULL;           -- idempotent: skip already-linked rows

-- STEP B — NORMAL teñido + perchado/compactado/termofijado → MIN(pp.id) per
--   (partida, operacion). Excludes rework teñido rows (handled in Step A) so they
--   can never bind to the parent partida's normal paso.
UPDATE migration.legacy_executions le
SET new_paso_id = canonical.paso_id,
    status      = 'LINKED'
FROM (
    SELECT
        pp.partida_id,
        pp.operacion_id,
        MIN(pp.id) AS paso_id
    FROM mes.partida_paso pp
    GROUP BY pp.partida_id, pp.operacion_id
) canonical
WHERE canonical.partida_id   = le.partida_id
  AND canonical.operacion_id = le.operacion_id
  AND le.new_paso_id IS NULL              -- idempotent + skips Step-A reworks
  AND NOT (
        le.source_table = 'produccion_tenido'
        AND EXISTS (
            SELECT 1 FROM produccion_tenido pt
            WHERE pt.id = le.legacy_id
              AND pt.tipo <> 'Teñido'      -- a rework with no surviving paso stays
        )                                  -- unlinked, never bound to the parent
  );

COMMIT;


-- ── Verify after LINK ─────────────────────────────────────────────────────────

-- 1. Linked vs unlinked by source + operacion.
--    unlinked > 0 → those need INSERT in the next patch.
SELECT
    source_table,
    operacion_codigo,
    COUNT(*)                                        AS total,
    COUNT(*) FILTER (WHERE new_paso_id IS NOT NULL) AS linked,
    COUNT(*) FILTER (WHERE new_paso_id IS NULL)     AS unlinked
FROM migration.legacy_executions
GROUP BY 1, 2
ORDER BY 1, 2;

-- 2. Consolidation cases: (partida, operacion) groups with multiple existing
--    pasos. The extra pasos (all except MIN id) must be deleted before
--    ejecucion insertion so FK constraints stay clean.
SELECT
    op.codigo    AS operacion_codigo,
    pp.partida_id,
    COUNT(pp.id) AS n_pasos,
    MIN(pp.id)   AS canonical_paso_id,
    ARRAY_AGG(pp.id ORDER BY pp.id) AS all_paso_ids
FROM mes.partida_paso pp
JOIN mes.operacion op ON op.id = pp.operacion_id
GROUP BY op.codigo, pp.partida_id
HAVING COUNT(pp.id) > 1
ORDER BY n_pasos DESC, pp.partida_id;

-- 3. Unlinked staging rows — need new pasos in step 03.
SELECT
    source_table,
    operacion_codigo,
    partida_id,
    fecha,
    legacy_id
FROM migration.legacy_executions
WHERE new_paso_id IS NULL
ORDER BY source_table, partida_id, fecha
LIMIT 200;

-- 4. now()-stamped EXISTING ejecuciones — the real patch-36 target.
--    fyh_inicio/fyh_fin written as now() by pre-06b scripts land on the migration
--    day (2026-05-25) instead of the real production timestamp. (paso fyh_cre is
--    cosmetic and deliberately NOT targeted.)
--    Deduped to one row per ejecucion (the paso↔staging join is many-to-many).
--    candidate_* lists every legacy timestamp on the paso, since the correct value
--    per ejecucion is not 1:1 here — step 04 picks the match and rewrites ONLY
--    where it actually differs (that predicate also skips genuine go-live-day runs
--    and hand-run-patch values, which already equal the legacy timestamp).
SELECT
    le.source_table,
    le.operacion_codigo,
    pp.partida_id,
    ppe.id                                                   AS ejecucion_id,
    ppe.fyh_inicio                                           AS wrong_fyh_inicio,
    ppe.fyh_fin                                              AS wrong_fyh_fin,
    ARRAY_AGG(DISTINCT le.fyh_inicio ORDER BY le.fyh_inicio) AS candidate_fyh_inicio,
    ARRAY_AGG(DISTINCT le.fyh_fin    ORDER BY le.fyh_fin)    AS candidate_fyh_fin
FROM migration.legacy_executions le
JOIN mes.partida_paso pp            ON pp.id  = le.new_paso_id
JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE le.new_paso_id IS NOT NULL
  AND (
      ppe.fyh_inicio BETWEEN '2026-05-25 11:00:00+00'::timestamptz
                         AND '2026-05-25 16:00:00+00'::timestamptz
   OR ppe.fyh_fin    BETWEEN '2026-05-25 11:00:00+00'::timestamptz
                         AND '2026-05-25 16:00:00+00'::timestamptz
  )
GROUP BY le.source_table, le.operacion_codigo, pp.partida_id,
         ppe.id, ppe.fyh_inicio, ppe.fyh_fin
ORDER BY le.source_table, pp.partida_id, ppe.id;
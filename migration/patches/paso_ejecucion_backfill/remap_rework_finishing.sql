-- ============================================================================
-- REMAP · Move rework-subset finishing runs to their rework child partida
-- ============================================================================
-- WHAT: finishing runs (compactado/perchado/termofijado) done on the REWORKED
--   rolls are recorded in legacy under the ORIGINAL partida. They belong to the
--   rework CHILD partida (partida_origen_id → original). We identify them by
--   ROLL QUANTITY + CHRONOLOGY and move their ejecucion under the child.
--
-- MATCH RULE: a finishing ejecucion F (under original O) belongs to rework R
--   (child of O) when R.rework_rolls = F.cantidad_rollos AND R happened on/before F
--   (R.rework_date <= F.fyh_inicio). Ambiguous (several qualifying reworks) → the
--   NEAREST PRECEDING rework wins (latest rework_date <= F). No match → F stays on
--   the original (it was finished as part of the whole batch — correct).
--   Rework rolls come from partida_detalle.cantidad (the ejecucion's cantidad_rollos
--   is NULL on migration-11 reworks); finishing rolls from the ejecucion.
--
-- WHY SAFE ON REFS: we move the EJECUCION (change partida_paso_id) — its id is
--   unchanged, so lote/movimiento documento_id refs stay valid. No re-pointing.
--
-- LIMITATION: roll-qty can false-positive when a full-batch finishing coincidentally
--   equals a rework's roll count and postdates it. That is the irreducible limit of
--   the chosen signal (roll quantity), accepted per decision.
--
-- Standalone deferred item (not part of the 00–06 sequence). Run after 06.
-- ⚠ DRY-RUN §0, run §1 in the open transaction, read §2, then COMMIT.
-- ============================================================================


-- ── reusable match CTEs (used in §0 and §1) ──────────────────────────────────
-- (kept as a comment template; both sections inline it)

-- ── Section 0 · DRY RUN — the remap set ───────────────────────────────────────
WITH rework AS (
    SELECT child.id AS rework_partida_id, child.partida_origen_id AS original_id,
           pd.cantidad AS rework_rolls, MIN(rppe.fyh_inicio) AS rework_date
    FROM mes.partida child
    JOIN mes.partida_detalle pd          ON pd.partida_id = child.id
    JOIN mes.partida_paso rpp            ON rpp.partida_id = child.id
    JOIN mes.operacion rop               ON rop.id = rpp.operacion_id AND rop.codigo = 'TENIDO'
    JOIN mes.partida_paso_ejecucion rppe ON rppe.partida_paso_id = rpp.id
    WHERE child.partida_origen_id IS NOT NULL AND child.fyh_elm IS NULL
    GROUP BY child.id, child.partida_origen_id, pd.cantidad
),
finishing AS (
    SELECT ppe.id AS ejec_id, pp.partida_id AS original_id, pp.operacion_id, op.codigo AS op,
           ppe.cantidad_rollos AS fin_rolls, ppe.fyh_inicio AS fin_date
    FROM mes.partida_paso pp
    JOIN mes.operacion op                ON op.id = pp.operacion_id
                                        AND op.codigo IN ('COMPACTADO','PERCHADO','TERMOFIJADO')
    JOIN mes.partida_paso_ejecucion ppe  ON ppe.partida_paso_id = pp.id
    WHERE pp.partida_id IN (SELECT DISTINCT original_id FROM rework)
),
match AS (
    SELECT DISTINCT ON (f.ejec_id)
           f.ejec_id, f.operacion_id, f.op, r.rework_partida_id
    FROM finishing f
    JOIN rework r ON r.original_id = f.original_id
                 AND r.rework_rolls = f.fin_rolls
                 AND r.rework_date <= f.fin_date
    ORDER BY f.ejec_id, r.rework_date DESC          -- nearest preceding rework wins
)
SELECT op,
       COUNT(*)                                      AS ejecuciones_to_move,
       COUNT(DISTINCT rework_partida_id)             AS target_child_partidas,
       COUNT(DISTINCT (rework_partida_id, operacion_id)) AS finishing_pasos_to_create
FROM match GROUP BY op ORDER BY op;


-- ── Section 1 · Remap ─────────────────────────────────────────────────────────
BEGIN;

CREATE TEMP TABLE _remap AS
WITH rework AS (
    SELECT child.id AS rework_partida_id, child.partida_origen_id AS original_id,
           pd.cantidad AS rework_rolls, MIN(rppe.fyh_inicio) AS rework_date
    FROM mes.partida child
    JOIN mes.partida_detalle pd          ON pd.partida_id = child.id
    JOIN mes.partida_paso rpp            ON rpp.partida_id = child.id
    JOIN mes.operacion rop               ON rop.id = rpp.operacion_id AND rop.codigo = 'TENIDO'
    JOIN mes.partida_paso_ejecucion rppe ON rppe.partida_paso_id = rpp.id
    WHERE child.partida_origen_id IS NOT NULL AND child.fyh_elm IS NULL
    GROUP BY child.id, child.partida_origen_id, pd.cantidad
),
finishing AS (
    SELECT ppe.id AS ejec_id, pp.partida_id AS original_id, pp.operacion_id,
           ppe.cantidad_rollos AS fin_rolls, ppe.fyh_inicio AS fin_date, ppe.fyh_cre
    FROM mes.partida_paso pp
    JOIN mes.operacion op                ON op.id = pp.operacion_id
                                        AND op.codigo IN ('COMPACTADO','PERCHADO','TERMOFIJADO')
    JOIN mes.partida_paso_ejecucion ppe  ON ppe.partida_paso_id = pp.id
    WHERE pp.partida_id IN (SELECT DISTINCT original_id FROM rework)
)
SELECT DISTINCT ON (f.ejec_id)
       f.ejec_id, f.operacion_id, r.rework_partida_id, f.fin_date AS fyh_cre
FROM finishing f
JOIN rework r ON r.original_id = f.original_id
             AND r.rework_rolls = f.fin_rolls
             AND r.rework_date <= f.fin_date
ORDER BY f.ejec_id, r.rework_date DESC;

-- 1a. create ONE finishing paso per (rework child, operacion) that receives runs,
--     unless the child already has one. Capture (child, operacion) → new paso id.
CREATE TEMP TABLE _child_paso AS
WITH need AS (
    SELECT DISTINCT rework_partida_id, operacion_id, MIN(fyh_cre) AS fyh_cre
    FROM _remap GROUP BY rework_partida_id, operacion_id
),
ins AS (
    INSERT INTO mes.partida_paso (partida_id, secuencia, operacion_id, usr_cre, fyh_cre)
    SELECT n.rework_partida_id,
           (900 + ROW_NUMBER() OVER (PARTITION BY n.rework_partida_id ORDER BY n.operacion_id))::smallint,
           n.operacion_id, 4, n.fyh_cre
    FROM need n
    WHERE NOT EXISTS (SELECT 1 FROM mes.partida_paso pp
                      WHERE pp.partida_id = n.rework_partida_id AND pp.operacion_id = n.operacion_id)
    RETURNING id, partida_id, operacion_id
)
SELECT id AS paso_id, partida_id AS rework_partida_id, operacion_id FROM ins;

-- 1b. move each matched ejecucion onto the child's finishing paso (new one, or an
--     existing child paso for that operacion if one already existed)
UPDATE mes.partida_paso_ejecucion ppe
SET partida_paso_id = COALESCE(cp.paso_id, existing.id),
    usr_mod = 4, fyh_mod = now()
FROM _remap rm
LEFT JOIN _child_paso cp
       ON cp.rework_partida_id = rm.rework_partida_id AND cp.operacion_id = rm.operacion_id
LEFT JOIN LATERAL (
       SELECT pp.id FROM mes.partida_paso pp
       WHERE pp.partida_id = rm.rework_partida_id AND pp.operacion_id = rm.operacion_id
       LIMIT 1) existing ON true
WHERE ppe.id = rm.ejec_id;

-- 1c. renumber secuencia 1..N by operation priority for the affected child partidas
UPDATE mes.partida_paso pp
SET secuencia = -ranked.new_seq
FROM (
    SELECT pp2.id,
           ROW_NUMBER() OVER (
               PARTITION BY pp2.partida_id
               ORDER BY CASE op.codigo
                   WHEN 'PREPARADO'   THEN 1 WHEN 'TERMOFIJADO' THEN 2
                   WHEN 'TENIDO'      THEN 3 WHEN 'LAVADO_HIDRO' THEN 4
                   WHEN 'SECADO'      THEN 5 WHEN 'VOLTEADO'    THEN 6
                   WHEN 'PERCHADO'    THEN 7 WHEN 'COMPACTADO'  THEN 8
                   ELSE 99 END, pp2.fyh_cre, pp2.id) AS new_seq
    FROM mes.partida_paso pp2
    JOIN mes.operacion op ON op.id = pp2.operacion_id
    WHERE pp2.partida_id IN (SELECT DISTINCT rework_partida_id FROM _remap)
) ranked
WHERE pp.id = ranked.id;

UPDATE mes.partida_paso pp
SET secuencia = -pp.secuencia
WHERE pp.partida_id IN (SELECT DISTINCT rework_partida_id FROM _remap)
  AND pp.secuencia < 0;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) every matched ejecucion now lives under its rework child partida — expect 0 wrong
SELECT COUNT(*) AS ejecuciones_not_under_child
FROM _remap rm
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = rm.ejec_id
JOIN mes.partida_paso pp            ON pp.id = ppe.partida_paso_id
WHERE pp.partida_id <> rm.rework_partida_id;

-- (b) no ejecucion orphaned
SELECT COUNT(*) AS orphaned_ejecuciones
FROM mes.partida_paso_ejecucion ppe
WHERE NOT EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.id = ppe.partida_paso_id);

-- (c) affected child partidas have clean 1..N secuencia — expect 0 bad
SELECT COUNT(*) AS children_with_bad_secuencia
FROM (
    SELECT partida_id FROM mes.partida_paso
    WHERE partida_id IN (SELECT DISTINCT rework_partida_id FROM _remap)
    GROUP BY partida_id
    HAVING COUNT(*) <> COUNT(DISTINCT secuencia)
        OR MIN(secuencia) <> 1 OR MAX(secuencia) <> COUNT(*)
) bad;

-- (d) roll-count integrity: every moved ejecucion's cantidad_rollos equals its
--     target child's rework roll count (partida_detalle.cantidad). This is the
--     match criterion, re-checked post-move — moved_matching must equal total_moved.
--     (It confirms the mechanics; roll-qty can't prove semantic correctness — a
--     coincidental full-batch match that postdates a rework is the accepted limit.)
SELECT (SELECT COUNT(*) FROM _remap)                       AS total_moved,
       COUNT(*)                                            AS moved_matching_rolls
FROM _remap rm
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = rm.ejec_id
JOIN mes.partida_detalle pd         ON pd.partida_id = rm.rework_partida_id
WHERE ppe.cantidad_rollos = pd.cantidad;

DROP TABLE _remap;
DROP TABLE _child_paso;

-- COMMIT;    -- ← after §2 all 0
-- ROLLBACK;  -- ← if anything is off


-- (a) how many output lotes hang off TENIDO ejecuciones, and for how many partidas
SELECT COUNT(*) AS tenido_output_lotes, COUNT(DISTINCT pp.partida_id) AS partidas
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                   AND l.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO';

-- (b) per such partida: what's the last step (by priority) that has ejecuciones,
--     and how many ejecuciones does that last step have (1 = easy, >1 = ambiguous)?
WITH parts AS (
    SELECT DISTINCT pp.partida_id
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                       AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
),
step_prio AS (
    SELECT p.partida_id, op.codigo,
           CASE op.codigo WHEN 'COMPACTADO' THEN 8 WHEN 'PERCHADO' THEN 7 WHEN 'VOLTEADO' THEN 6
                          WHEN 'SECADO' THEN 5 WHEN 'LAVADO_HIDRO' THEN 4 WHEN 'TENIDO' THEN 3
                          WHEN 'TERMOFIJADO' THEN 2 WHEN 'PREPARADO' THEN 1 ELSE 0 END AS prio,
           COUNT(ppe.id) AS n_ejec
    FROM parts p
    JOIN mes.partida_paso pp            ON pp.partida_id = p.partida_id
    JOIN mes.operacion op               ON op.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
    GROUP BY p.partida_id, op.codigo
),
last_step AS (
    SELECT DISTINCT ON (partida_id) partida_id, codigo AS last_op, n_ejec
    FROM step_prio ORDER BY partida_id, prio DESC
)
SELECT last_op,
       COUNT(*)                          AS partidas,
       COUNT(*) FILTER (WHERE n_ejec = 1) AS single_ejec_easy,
       COUNT(*) FILTER (WHERE n_ejec > 1) AS multi_ejec_ambiguous
FROM last_step GROUP BY last_op ORDER BY 2 DESC;
-- across the 20,567 tenido output lotes, which operaciones appear in each lote's
-- item_movimientos genealogy? If COMPACTADO/PERCHADO show up widely, genealogy can
-- read the real last step per roll; if it's basically only TENIDO, there's no trail.
WITH output_lote AS (
    SELECT l.id AS lote_id
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                       AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
)
SELECT op.codigo,
       COUNT(DISTINCT ol.lote_id) AS output_lotes_touching_this_op
FROM output_lote ol
JOIN inventario.item_movimientos im  ON im.lote_id = ol.lote_id
                                    AND im.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso_ejecucion ppe  ON ppe.id = im.documento_id
JOIN mes.partida_paso pp             ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op                ON op.id = pp.operacion_id
GROUP BY op.codigo
ORDER BY 2 DESC;

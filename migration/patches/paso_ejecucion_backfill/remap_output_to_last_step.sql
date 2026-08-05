-- ============================================================================
-- REMAP · Move tenido output to the real last step (single-last-step partidas)
-- ============================================================================
-- WHAT: migration-11 bolted production output lotes onto the TENIDO ejecucion as a
--   bootstrap. Physically the finished-goods output is produced at the last step
--   (usually compactado). This moves the output attribution to that last step.
--
-- SCOPE: ONLY partidas whose last step (highest operation priority that has an
--   ejecucion) is NON-tenido AND has EXACTLY ONE ejecucion. Then that single
--   finishing run is the unambiguous owner of the partida's output.
--   CONTEXT: these tenido output lotes are SYNTHETIC "expected output" — the
--   migration deliberately imported only the DYEING (produccion_tenido) and
--   assigned the expected output rolls to those tenido runs (the client did not
--   need full legacy finishing history). So there is NO real per-roll genealogy
--   from a dyed roll to the finishing run that processed it — nothing to follow.
--   NOT moved (left on tenido, by decision):
--     · last step = TENIDO (no finishing) — already correct.
--     · last step has MULTIPLE ejecuciones — the bulk-assigned expected output can't
--       be meaningfully SPLIT across several finishing runs (no genealogy; roll-qty
--       misses ~53%). Forcing a split would fabricate detail → left as-is.
--
-- RE-POINTS (per moved output lote), tenido ejec → last-step ejec:
--   · inventario.lote.documento_id  (the "produced-by" marker the output views read)
--   · the production INGRESO in item_movimientos (destino set, origen NULL)
--   LEAVES the EGRESO (origen set) on tenido — that is the step CONSUMING the roll
--   before its transformation, which belongs to tenido.
--
-- Standalone deferred item. ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- op priority helper is inlined as a CASE in each block.

-- ── Section 0 · DRY RUN — scope ───────────────────────────────────────────────
WITH parts AS (
    SELECT DISTINCT pp.partida_id
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                       AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
),
step_ejec AS (
    SELECT p.partida_id, op.codigo,
           CASE op.codigo WHEN 'COMPACTADO' THEN 8 WHEN 'PERCHADO' THEN 7 WHEN 'VOLTEADO' THEN 6
                          WHEN 'SECADO' THEN 5 WHEN 'LAVADO_HIDRO' THEN 4 WHEN 'TENIDO' THEN 3
                          WHEN 'TERMOFIJADO' THEN 2 WHEN 'PREPARADO' THEN 1 ELSE 0 END AS prio,
           COUNT(ppe.id) AS n_ejec, MIN(ppe.id) AS the_ejec
    FROM parts p
    JOIN mes.partida_paso pp            ON pp.partida_id = p.partida_id
    JOIN mes.operacion op               ON op.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
    GROUP BY p.partida_id, op.codigo
),
last_step AS (
    SELECT DISTINCT ON (partida_id) partida_id, codigo AS last_op, n_ejec, the_ejec
    FROM step_ejec ORDER BY partida_id, prio DESC
)
SELECT last_op,
       COUNT(*) FILTER (WHERE n_ejec = 1) AS single_partidas_MOVE,
       COUNT(*) FILTER (WHERE n_ejec > 1) AS multi_partidas_SKIP
FROM last_step
WHERE last_op <> 'TENIDO'
GROUP BY last_op ORDER BY 2 DESC;


-- ── Section 1 · Re-point output ───────────────────────────────────────────────
BEGIN;

-- target = single non-tenido last-step ejecucion per in-scope partida
CREATE TEMP TABLE _target AS
WITH parts AS (
    SELECT DISTINCT pp.partida_id
    FROM inventario.lote l
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                       AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
),
step_ejec AS (
    SELECT p.partida_id, op.codigo,
           CASE op.codigo WHEN 'COMPACTADO' THEN 8 WHEN 'PERCHADO' THEN 7 WHEN 'VOLTEADO' THEN 6
                          WHEN 'SECADO' THEN 5 WHEN 'LAVADO_HIDRO' THEN 4 WHEN 'TENIDO' THEN 3
                          WHEN 'TERMOFIJADO' THEN 2 WHEN 'PREPARADO' THEN 1 ELSE 0 END AS prio,
           COUNT(ppe.id) AS n_ejec, MIN(ppe.id) AS the_ejec
    FROM parts p
    JOIN mes.partida_paso pp            ON pp.partida_id = p.partida_id
    JOIN mes.operacion op               ON op.id = pp.operacion_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
    GROUP BY p.partida_id, op.codigo
),
last_step AS (
    SELECT DISTINCT ON (partida_id) partida_id, codigo AS last_op, n_ejec, the_ejec
    FROM step_ejec ORDER BY partida_id, prio DESC
)
SELECT partida_id, the_ejec AS target_ejec
FROM last_step
WHERE last_op <> 'TENIDO' AND n_ejec = 1;

-- output lotes to move + their current tenido ejec + target
CREATE TEMP TABLE _move AS
SELECT l.id AS lote_id, l.documento_id AS tenido_ejec_id, t.target_ejec
FROM _target t
JOIN mes.partida_paso pp             ON pp.partida_id = t.partida_id
JOIN mes.operacion op                ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
JOIN mes.partida_paso_ejecucion tppe ON tppe.partida_paso_id = pp.id
JOIN inventario.lote l               ON l.documento_id = tppe.id
                                    AND l.documento_tipo = 'partida_paso_ejecucion';

-- 1a. re-point the output lote's "produced-by" marker
UPDATE inventario.lote l
SET documento_id = m.target_ejec
FROM _move m
WHERE l.id = m.lote_id AND l.documento_tipo = 'partida_paso_ejecucion';

-- 1b. re-point the production INGRESO (destino set, origen NULL). Leave egresos.
UPDATE inventario.item_movimientos im
SET documento_id = m.target_ejec
FROM _move m
WHERE im.lote_id       = m.lote_id
  AND im.documento_tipo = 'partida_paso_ejecucion'
  AND im.documento_id   = m.tenido_ejec_id
  AND im.origen_ubicacion_id  IS NULL
  AND im.destino_ubicacion_id IS NOT NULL;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) all moved output lotes now point at their target last-step ejec — expect 0 wrong
SELECT COUNT(*) AS lotes_not_on_target
FROM _move m
JOIN inventario.lote l ON l.id = m.lote_id
WHERE l.documento_id <> m.target_ejec;

-- (b) each moved lote's production ingreso now on target — expect 0 left on tenido
SELECT COUNT(*) AS ingresos_still_on_tenido
FROM _move m
JOIN inventario.item_movimientos im ON im.lote_id = m.lote_id
                                   AND im.documento_tipo = 'partida_paso_ejecucion'
                                   AND im.origen_ubicacion_id IS NULL
                                   AND im.destino_ubicacion_id IS NOT NULL
WHERE im.documento_id = m.tenido_ejec_id;

-- (c) egresos deliberately LEFT on tenido — informational (should be > 0, unchanged)
SELECT COUNT(*) AS egresos_left_on_tenido
FROM _move m
JOIN inventario.item_movimientos im ON im.lote_id = m.lote_id
                                   AND im.documento_tipo = 'partida_paso_ejecucion'
                                   AND im.origen_ubicacion_id IS NOT NULL
WHERE im.documento_id = m.tenido_ejec_id;

-- (d) counts
SELECT COUNT(DISTINCT partida_id) AS partidas_moved,
       (SELECT COUNT(*) FROM _move) AS lotes_moved
FROM _target;

DROP TABLE _move;
DROP TABLE _target;

-- COMMIT;    -- ← after §2: lotes_not_on_target = 0, ingresos_still_on_tenido = 0
-- ROLLBACK;  -- ← if anything is off

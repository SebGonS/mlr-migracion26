-- ═══════════════════════════════════════════════════════════════════════════════
-- DATA FIX: chemical consumption posted in GRAMS → KG  (live go-live data)
--
-- CONTEXT
--   Before the generar_receta unit fix, the frontend sent the recipe field
--   "cantidad_requerida_kg" (actually grams) verbatim to finalizar_paso →
--   registrar_consumo_paso, which stored it as-is. Stock items are kg, so every
--   chemical PROD_CONSUMO that operators registered live is 1000× too large, and
--   that error already cascaded into item_saldo / lote_saldo / item_valoracion.
--
--   This script corrects the already-posted rows. The complementary script
--   11_backfill_egresos_no_registrados.sql handles runs whose chemicals were NEVER
--   posted (it now writes kg). 08_migrar_ejecuciones_batch.sql is unaffected
--   (roll weights, always kg). LAVADO consumption is unaffected (always kg).
--
-- SCOPE (what gets divided by 1000)
--   item_movimientos where:
--     • item_movimiento_tipo = PROD_CONSUMO
--     • documento_tipo = 'partida_paso_ejecucion'        (tenido step consumption)
--     • item ∈ item_insumo_detalle with medida IN ('g/L','%')  (recipe chemicals;
--       this EXCLUDES roll PROD_CONSUMO, which is kg, and any kg-medida insumo)
--     • motivo_id IS NULL  → normal recipe consumption ONLY. MATIZADO rows are
--       operator-entered in kg (verified: avg ~0.6, max ~5.8), so they are EXCLUDED;
--       dividing them would corrupt them.
--   Rows already in the fix log are skipped (idempotent).
--
-- ── FILTERING OUT LEGACY / NON-GRAMS ROWS ───────────────────────────────────────
--   The structural filter above is not enough: legacy-migrated and post-fix rows
--   also live in partida_paso_ejecucion. We isolate ONLY the live grams rows using
--   the two timestamps every movement carries:
--     • fecha_hora = event time  (migrations BACKDATE this to the historical run)
--     • fyh_cre    = real INSERT time (DEFAULT now(); = migration run date for
--                    migrated rows, = the real-time moment for live app posts)
--   The live grams bug existed only in registrar_consumo_paso (new system), bounded
--   by two timestamps on fyh_cre (the real INSERT time). A row is a live grams row iff:
--     (a) fyh_cre > :p_migration_ts          → LOWER bound: inserted AFTER the data
--                                              migration → a live post, not legacy/migrated.
--                                              = the migration run time (+buffer).
--     (b) fyh_cre < :p_fix_cutoff            → UPPER bound: inserted BEFORE the kg-fix
--                                              deploy → still grams (post-fix posts are kg).
--     (c) observacion <> 'BACKFILL_EGRESO_NO_REGISTRADO'  → exclude script 11.
--
--   IMPORTANT — the two boundaries are DIFFERENT facts:
--     • p_migration_ts is known (the migration run): set in PARAMS below.
--     • p_fix_cutoff = the generar_receta kg-fix DEPLOY timestamp. The fix IS already
--       deployed, so genuine kg rows exist after it — this bound is REQUIRED to avoid
--       dividing them. Magnitude cannot tell a small grams row from a kg row (a 0.4 kg
--       dye was stored 400 pre-fix, 0.4 after; a real 400 kg row is also 400), so the
--       cutoff MUST be the actual deploy time from your deploy log — it is NOT derivable
--       from the data. PROVISIONAL value below = just after the last observed grams row;
--       replace it with the exact deploy timestamp.
--   ⇒ SECTION 0d classifies every chemical-consumption row (included / why-excluded)
--     so you can confirm the window before running.
--
-- ASSUMPTIONS
--   • Every matching row came through the grams-scaled recipe path. If any operator
--     ever typed a real kg amount for a g/L/% insumo, that row would be wrongly
--     divided — SECTION 0 lists the rows so you can eyeball before running.
--   • If the OLD (grams) script 11 ever ran, its rows are stamped BACKFILL and would
--     be EXCLUDED by (c) yet still be in grams — handle separately. (Per current
--     understanding 11 never ran; SECTION 0d will surface any such rows.)
--   • factor_stock is NOT touched here (deferred). The /1000 is a pure unit fix.
--   • Run AFTER patch 28 (columns widened to 15,7) and the generar_receta deploy.
--
-- HOW BALANCES ARE REBUILT (not delta-patched)
--   item_saldo / lote_saldo sync is purely additive (no clamp), so they are rebuilt
--   exactly by re-aggregating signed movements for affected items/lotes.
--   item_valoracion (MAP) clamps with GREATEST(0,…) and resets valorado at qty=0,
--   so it is rebuilt by a chronological REPLAY of fn_trg_actualizar_map per item.
--
--   DECISION — replay order: (fecha_hora, id) = economic chronological order. The
--   live triggers accumulated in insert (id) order, which differs only for backdated
--   rows. Chronological is the correct moving-average basis; switch the ORDER BY in
--   SECTION 2c to (id) if you'd rather reproduce the original insert-order figures.
--
-- WORKFLOW: SECTION 0 (read-only) → 1 → 2 → 3, in order. Whole thing is reversible
--   (see REVERSAL at the bottom).
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── PARAMS — p_migration_ts = data-migration run time (+buffer, known);
--            p_fix_cutoff   = generar_receta kg-fix DEPLOY moment (set this).
--    (Repeated in 0a/0b/0c/0d and SECTION 1; keep all copies identical.)

-- Idempotency log — created up front so the SECTION 0 previews can reference it
-- (SECTION 1 re-issues this CREATE harmlessly via IF NOT EXISTS).
CREATE TABLE IF NOT EXISTS inventario.consumo_kg_fix_log (
    item_movimiento_id BIGINT PRIMARY KEY REFERENCES inventario.item_movimientos(id),
    item_id            INT           NOT NULL,
    old_cantidad       NUMERIC(15,7) NOT NULL,
    new_cantidad       NUMERIC(15,7) NOT NULL,
    fyh_cre            TIMESTAMPTZ DEFAULT now()
);

-- 0a. Summary: how many rows / how much grams will be corrected
WITH params AS (SELECT '2026-05-25 18:30:00+00'::timestamptz AS p_migration_ts,   -- data migration 15:27:52 + buffer
                       '2026-06-18 22:00:00+00'::timestamptz  AS p_fix_cutoff)    -- ⇦ PROVISIONAL. Fix IS deployed → must bound. SET to the exact generar_receta deploy timestamp (post-fix rows are kg).
SELECT
    im.documento_tipo,
    COUNT(*)                          AS movimientos,
    COUNT(DISTINCT im.item_id)        AS insumos,
    ROUND(SUM(im.cantidad), 4)        AS total_actual_grams,
    ROUND(SUM(im.cantidad) / 1000, 7) AS total_corregido_kg
FROM inventario.item_movimientos im
CROSS JOIN params pr
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.fyh_cre > pr.p_migration_ts                                 -- (a) live row, after the data migration
  AND im.fyh_cre < pr.p_fix_cutoff                                   -- (b) before the kg fix → grams
  AND COALESCE(im.observacion,'') <> 'BACKFILL_EGRESO_NO_REGISTRADO' -- (c) exclude script 11
  AND im.motivo_id IS NULL                                           -- (d) normal consumption only; matizado is operator-entered kg
  AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
GROUP BY im.documento_tipo;

-- 0b. Per-row detail (eyeball for any suspiciously small / already-kg values)
WITH params AS (SELECT '2026-05-25 18:30:00+00'::timestamptz AS p_migration_ts,   -- data migration 15:27:52 + buffer
                       '2026-06-18 22:00:00+00'::timestamptz  AS p_fix_cutoff)    -- ⇦ PROVISIONAL. Fix IS deployed → must bound. SET to the exact generar_receta deploy timestamp (post-fix rows are kg).
SELECT im.id AS mov_id, im.fecha_hora, im.fyh_cre, im.item_id, it.nombre AS insumo, iid.medida,
       im.lote_id, im.origen_ubicacion_id,
       im.cantidad AS cantidad_grams, ROUND(im.cantidad / 1000, 7) AS cantidad_kg,
       im.observacion
FROM inventario.item_movimientos im
CROSS JOIN params pr
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item it             ON it.id  = im.item_id
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.fyh_cre > pr.p_migration_ts
  AND im.fyh_cre < pr.p_fix_cutoff
  AND COALESCE(im.observacion,'') <> 'BACKFILL_EGRESO_NO_REGISTRADO'
  AND im.motivo_id IS NULL                                           -- normal consumption only (matizado is kg)
  AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
ORDER BY im.fecha_hora, im.id;

-- 0d. Rows EXCLUDED by the legacy filter (sanity-check before running): chemical
--     PROD_CONSUMO on partida_paso_ejecucion that this script will NOT touch, and why.
WITH params AS (SELECT '2026-05-25 18:30:00+00'::timestamptz AS p_migration_ts,   -- data migration 15:27:52 + buffer
                       '2026-06-18 22:00:00+00'::timestamptz  AS p_fix_cutoff)    -- ⇦ PROVISIONAL. Fix IS deployed → must bound. SET to the exact generar_receta deploy timestamp (post-fix rows are kg).
SELECT
    CASE
        WHEN im.observacion = 'BACKFILL_EGRESO_NO_REGISTRADO'  THEN 'excluida: backfill (script 11)'
        WHEN im.motivo_id IS NOT NULL                          THEN 'excluida: matizado (kg manual)'
        WHEN im.fyh_cre <= pr.p_migration_ts                   THEN 'excluida: legacy/migración'
        WHEN im.fyh_cre >= pr.p_fix_cutoff                     THEN 'excluida: post-fix (ya en kg)'
        ELSE 'incluida'
    END                              AS clasificacion,
    COUNT(*)                         AS movimientos,
    ROUND(SUM(im.cantidad), 4)       AS cantidad_total
FROM inventario.item_movimientos im
CROSS JOIN params pr
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
WHERE im.documento_tipo = 'partida_paso_ejecucion'
GROUP BY 1
ORDER BY 1;

-- 0c. Affected items' current valoración (compare against SECTION 3 after the fix)
WITH params AS (SELECT '2026-05-25 18:30:00+00'::timestamptz AS p_migration_ts,   -- data migration 15:27:52 + buffer
                       '2026-06-18 22:00:00+00'::timestamptz  AS p_fix_cutoff)    -- ⇦ PROVISIONAL. Fix IS deployed → must bound. SET to the exact generar_receta deploy timestamp (post-fix rows are kg).
SELECT iv.item_id, it.nombre, iv.precio_promedio, iv.stock_qty, iv.stock_valorado
FROM inventario.item_valoracion iv
JOIN item it ON it.id = iv.item_id
WHERE iv.item_id IN (
    SELECT DISTINCT im.item_id
    FROM inventario.item_movimientos im
    CROSS JOIN params pr
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo = 'PROD_CONSUMO'
    JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND im.fyh_cre > pr.p_migration_ts
      AND im.fyh_cre < pr.p_fix_cutoff
      AND COALESCE(im.observacion,'') <> 'BACKFILL_EGRESO_NO_REGISTRADO'
      AND im.motivo_id IS NULL
)
ORDER BY iv.item_id;
WITH params AS (SELECT '2026-05-25 18:30:00+00'::timestamptz AS p_migration_ts,
                       '2026-06-18 22:00:00+00'::timestamptz  AS p_fix_cutoff)
SELECT COALESCE(mm.codigo, '(NULL = consumo normal)') AS motivo,
       COUNT(*)                                   AS movimientos,
       MIN(im.cantidad)                           AS min_cant,
       ROUND(AVG(im.cantidad), 4)                 AS avg_cant,
       MAX(im.cantidad)                           AS max_cant,
       COUNT(*) FILTER (WHERE im.cantidad < 1)    AS menores_a_1
FROM inventario.item_movimientos im
CROSS JOIN params pr
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
LEFT JOIN inventario.item_movimiento_motivo mm ON mm.id = im.motivo_id
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.fyh_cre > pr.p_migration_ts
  AND im.fyh_cre < pr.p_fix_cutoff
  AND COALESCE(im.observacion,'') <> 'BACKFILL_EGRESO_NO_REGISTRADO'
GROUP BY 1
ORDER BY 1;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — CORRECT THE MOVEMENTS  (÷1000, logged)
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS inventario.consumo_kg_fix_log (
    item_movimiento_id BIGINT PRIMARY KEY REFERENCES inventario.item_movimientos(id),
    item_id            INT           NOT NULL,
    old_cantidad       NUMERIC(15,7) NOT NULL,
    new_cantidad       NUMERIC(15,7) NOT NULL,
    fyh_cre            TIMESTAMPTZ DEFAULT now()
);

-- These rows are dated in the go-live window, possibly before a cuadre cutoff; the
-- corte guard only blocks UPDATE, so lift it for this transaction. The stock + MAP
-- triggers are AFTER INSERT only and do NOT fire on UPDATE, so balances are rebuilt
-- explicitly in SECTION 2 (do not rely on cascade here).
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

WITH params AS (SELECT '2026-05-25 18:30:00+00'::timestamptz AS p_migration_ts,
                       '2026-06-18 22:00:00+00'::timestamptz  AS p_fix_cutoff),   -- keep identical to SECTION 0 (set to real deploy ts)
afectados AS (
    SELECT im.id, im.item_id, im.cantidad AS old_cantidad
    FROM inventario.item_movimientos im
    CROSS JOIN params pr
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo = 'PROD_CONSUMO'
    JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND im.fyh_cre > pr.p_migration_ts                                 -- (a) live row, after the data migration
      AND im.fyh_cre < pr.p_fix_cutoff                                   -- (b) before the kg fix → grams
      AND COALESCE(im.observacion,'') <> 'BACKFILL_EGRESO_NO_REGISTRADO' -- (c) exclude script 11
      AND im.motivo_id IS NULL                                           -- (d) normal consumption only; matizado is operator-entered kg
      AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
),
upd AS (
    UPDATE inventario.item_movimientos im
    SET cantidad = ROUND(a.old_cantidad / 1000, 7)   -- monto (generated) recomputes automatically
    FROM afectados a
    WHERE im.id = a.id
    RETURNING im.id, im.item_id, a.old_cantidad, im.cantidad AS new_cantidad
)
INSERT INTO inventario.consumo_kg_fix_log (item_movimiento_id, item_id, old_cantidad, new_cantidad)
SELECT id, item_id, old_cantidad, new_cantidad FROM upd;

-- 1b. Extend the correction to consumption REVERSALS (PROD_CONSUMO_REV).
--     A reversal inherits the unit of the consumption it reverses, so we /1000 exactly
--     those reversals that reverse an ejecución+item corrected above — matched by
--     documento_id + item_id to the fix-log (NOT by the reversal's own timestamp; a
--     reversal of a grams consumption is grams whenever it was posted). Otherwise the
--     grams reversal over-credits stock (e.g. SAL saldo was inflated by ~1.4M).
WITH fixed_ejec AS (
    SELECT DISTINCT c.documento_id, c.item_id
    FROM inventario.item_movimientos c
    JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = c.id
    WHERE c.documento_tipo = 'partida_paso_ejecucion'
),
rev AS (
    SELECT im.id, im.item_id, im.cantidad AS old_cantidad
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo = 'PROD_CONSUMO_REV'
    JOIN fixed_ejec fe ON fe.documento_id = im.documento_id AND fe.item_id = im.item_id
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
),
upd_rev AS (
    UPDATE inventario.item_movimientos im
    SET cantidad = ROUND(r.old_cantidad / 1000, 7)
    FROM rev r
    WHERE im.id = r.id
    RETURNING im.id, im.item_id, r.old_cantidad, im.cantidad AS new_cantidad
)
INSERT INTO inventario.consumo_kg_fix_log (item_movimiento_id, item_id, old_cantidad, new_cantidad)
SELECT id, item_id, old_cantidad, new_cantidad FROM upd_rev;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — REBUILD BALANCES for affected items  (same transaction)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. item_saldo: re-aggregate signed movements per (item, ubicacion).
--     Matches fn_trg_sync_cantidad_actual (credit destino, debit origen, no clamp).
--     DELETE then INSERT as separate statements (a combined data-modifying CTE
--     would not see its own DELETE and could hit a unique violation).
DELETE FROM inventario.item_saldo
WHERE item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log);

INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
SELECT item_id, ubicacion_id, SUM(qty)
FROM (
    SELECT im.item_id, im.destino_ubicacion_id AS ubicacion_id,  im.cantidad AS qty
    FROM inventario.item_movimientos im
    WHERE im.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
      AND im.destino_ubicacion_id IS NOT NULL
    UNION ALL
    SELECT im.item_id, im.origen_ubicacion_id, -im.cantidad
    FROM inventario.item_movimientos im
    WHERE im.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
      AND im.origen_ubicacion_id IS NOT NULL
) s
GROUP BY item_id, ubicacion_id;

-- 2b. lote_saldo: same rebuild, for lotes touched by any corrected movement.
DELETE FROM inventario.lote_saldo
WHERE lote_id IN (
    SELECT DISTINCT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im.id
    WHERE im.lote_id IS NOT NULL
);

INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT lote_id, ubicacion_id, SUM(qty)
FROM (
    SELECT im.lote_id, im.destino_ubicacion_id AS ubicacion_id,  im.cantidad AS qty
    FROM inventario.item_movimientos im
    WHERE im.destino_ubicacion_id IS NOT NULL
      AND im.lote_id IN (
          SELECT DISTINCT im2.lote_id FROM inventario.item_movimientos im2
          JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im2.id
          WHERE im2.lote_id IS NOT NULL)
    UNION ALL
    SELECT im.lote_id, im.origen_ubicacion_id, -im.cantidad
    FROM inventario.item_movimientos im
    WHERE im.origen_ubicacion_id IS NOT NULL
      AND im.lote_id IN (
          SELECT DISTINCT im2.lote_id FROM inventario.item_movimientos im2
          JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im2.id
          WHERE im2.lote_id IS NOT NULL)
) s
GROUP BY lote_id, ubicacion_id;

-- 2c. item_valoracion: PRESERVE precio_promedio, only recompute qty + valuation.
--     The grams bug affected QUANTITIES only, never the unit price. precio_promedio
--     (MAP) is seeded outside the replayable movement set (migration / purchase docs),
--     so a from-scratch movement replay would wrongly zero it — DO NOT replay.
--     Recompute stock_qty from the corrected item_saldo and revalue at the existing MAP.
--     (Egress quantity never changes MAP in fn_trg_actualizar_map, so this is faithful.)
UPDATE inventario.item_valoracion iv
SET stock_qty      = COALESCE(s.qty, 0),
    stock_valorado = ROUND(GREATEST(0, COALESCE(s.qty, 0)) * iv.precio_promedio, 4),
    fyh_mod        = now()
FROM (
    SELECT item_id, SUM(cantidad_actual) AS qty
    FROM inventario.item_saldo
    WHERE item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
    GROUP BY item_id
) s
WHERE iv.item_id = s.item_id;

COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — VERIFY  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 3a. What was corrected
SELECT COUNT(*) AS movimientos_corregidos,
       COUNT(DISTINCT item_id) AS insumos,
       ROUND(SUM(old_cantidad), 4) AS total_old_grams,
       ROUND(SUM(new_cantidad), 7) AS total_new_kg
FROM inventario.consumo_kg_fix_log;

-- 3b. item_saldo vs independent re-aggregation (should be 0 rows out of sync)
WITH itms AS (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log),
expected AS (
    SELECT item_id, ubicacion_id, SUM(qty) AS cantidad
    FROM (
        SELECT im.item_id, im.destino_ubicacion_id AS ubicacion_id,  im.cantidad AS qty
        FROM inventario.item_movimientos im JOIN itms USING (item_id)
        WHERE im.destino_ubicacion_id IS NOT NULL
        UNION ALL
        SELECT im.item_id, im.origen_ubicacion_id, -im.cantidad
        FROM inventario.item_movimientos im JOIN itms USING (item_id)
        WHERE im.origen_ubicacion_id IS NOT NULL
    ) s GROUP BY item_id, ubicacion_id
)
SELECT e.item_id, e.ubicacion_id, e.cantidad AS esperado, s.cantidad_actual AS real
FROM expected e
LEFT JOIN inventario.item_saldo s
       ON s.item_id = e.item_id AND s.ubicacion_id IS NOT DISTINCT FROM e.ubicacion_id
WHERE ROUND(e.cantidad, 7) <> ROUND(COALESCE(s.cantidad_actual, 0), 7);

-- 3c. Affected items' valoración after the fix (compare to SECTION 0c)
SELECT iv.item_id, it.nombre, iv.precio_promedio, iv.stock_qty, iv.stock_valorado
FROM inventario.item_valoracion iv
JOIN item it ON it.id = iv.item_id
WHERE iv.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
ORDER BY iv.item_id;

-- 3d. Insumos still negative after the fix (investigate — may be genuine shortfalls)
SELECT i.id AS item_id, i.codigo, i.nombre, ROUND(SUM(si.cantidad_actual), 7) AS stock_actual
FROM inventario.item_saldo si
JOIN item i ON i.id = si.item_id
WHERE i.id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log)
GROUP BY i.id, i.codigo, i.nombre
HAVING SUM(si.cantidad_actual) < 0
ORDER BY SUM(si.cantidad_actual);


-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL (undo this fix)
--   BEGIN;
--   ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;
--   UPDATE inventario.item_movimientos im
--   SET cantidad = f.old_cantidad
--   FROM inventario.consumo_kg_fix_log f
--   WHERE im.id = f.item_movimiento_id;
--   ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;
--   -- then re-run SECTION 2 (2a/2b/2c) to rebuild balances from the restored quantities,
--   -- and finally:  TRUNCATE inventario.consumo_kg_fix_log;  (or DELETE the reverted ids)
--   COMMIT;
--
-- NOTE on open cuadres: if a cuadre (borrador/preparado) was frozen during the
-- go-live window, its cantidad_sistema snapshot captured the inflated stock. This
-- script does NOT touch cuadre snapshots. If SECTION 0b shows rows dated before an
-- open cuadre's fecha_cuadre, re-sync that snapshot the same way 11 SECTION 2 does
-- (add the corrected delta back to cuadre_detalle.cantidad_sistema). Check first:
--   SELECT id, estado, fecha_cuadre FROM inventario.cuadre WHERE estado IN ('borrador','preparado');
-- ═══════════════════════════════════════════════════════════════════════════════


SELECT im.id                          AS mov_id,
       im.fecha_hora,                            -- event time
       im.fyh_cre,                               -- insert time (the boundary axis)
       im.documento_id                AS ejecucion_id,
       im.item_id,
       it.nombre                      AS insumo,
       iid.medida,
       im.cantidad                    AS cantidad_actual_kg,      -- the inflated value
       ROUND(im.cantidad / 1000, 5)   AS cantidad_corregida_kg,   -- what 12 would write
       im.observacion
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO'
JOIN item it                 ON it.id = im.item_id
JOIN item_insumo_detalle iid ON iid.item_id = im.item_id AND iid.medida IN ('g/L','%')
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.cantidad >= 1000
ORDER BY im.fyh_cre DESC, im.id DESC
LIMIT 50;



SELECT im.item_id,
       imt.codigo AS tipo,
       CASE WHEN im.destino_ubicacion_id IS NOT NULL THEN 'INGRESS' ELSE 'EGRESS' END AS dir,
       COUNT(*)                       AS movs,
       ROUND(SUM(im.cantidad), 2)     AS total_cantidad,
       MIN(im.fyh_cre)                AS primer,
       MAX(im.fyh_cre)                AS ultimo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id IN (92, 202, 5)        -- SAL PDV, KIRAZOL BLACK, ANTIQUIEBRE
GROUP BY im.item_id, imt.codigo, dir
ORDER BY im.item_id, dir, total_cantidad DESC;



SELECT im.id, im.documento_tipo, im.documento_id, im.motivo_id, mm.codigo AS motivo,
       im.fecha_hora, im.fyh_cre, im.cantidad, im.observacion
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                        AND imt.codigo = 'PROD_CONSUMO_REV'
LEFT JOIN inventario.item_movimiento_motivo mm ON mm.id = im.motivo_id
WHERE im.item_id = 92
ORDER BY im.fyh_cre;



BEGIN;
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

WITH fixed_ejec AS (
    SELECT DISTINCT c.documento_id, c.item_id
    FROM inventario.item_movimientos c
    JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = c.id
    WHERE c.documento_tipo = 'partida_paso_ejecucion'
),
rev AS (
    SELECT im.id, im.item_id, im.cantidad AS old_cantidad
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo = 'PROD_CONSUMO_REV'
    JOIN fixed_ejec fe ON fe.documento_id = im.documento_id AND fe.item_id = im.item_id
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id = im.id)
),
upd_rev AS (
    UPDATE inventario.item_movimientos im
    SET cantidad = ROUND(r.old_cantidad / 1000, 7)
    FROM rev r WHERE im.id = r.id
    RETURNING im.id, im.item_id, r.old_cantidad, im.cantidad AS new_cantidad
)
INSERT INTO inventario.consumo_kg_fix_log (item_movimiento_id, item_id, old_cantidad, new_cantidad)
SELECT id, item_id, old_cantidad, new_cantidad FROM upd_rev;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

-- rebuild item_saldo
DELETE FROM inventario.item_saldo WHERE item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log);
INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
SELECT item_id, ubicacion_id, SUM(qty) FROM (
    SELECT im.item_id, im.destino_ubicacion_id AS ubicacion_id, im.cantidad AS qty
    FROM inventario.item_movimientos im
    WHERE im.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log) AND im.destino_ubicacion_id IS NOT NULL
    UNION ALL
    SELECT im.item_id, im.origen_ubicacion_id, -im.cantidad
    FROM inventario.item_movimientos im
    WHERE im.item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log) AND im.origen_ubicacion_id IS NOT NULL
) s GROUP BY item_id, ubicacion_id;

-- rebuild lote_saldo
DELETE FROM inventario.lote_saldo WHERE lote_id IN (
    SELECT DISTINCT im.lote_id FROM inventario.item_movimientos im
    JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im.id WHERE im.lote_id IS NOT NULL);
INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT lote_id, ubicacion_id, SUM(qty) FROM (
    SELECT im.lote_id, im.destino_ubicacion_id AS ubicacion_id, im.cantidad AS qty
    FROM inventario.item_movimientos im
    WHERE im.destino_ubicacion_id IS NOT NULL AND im.lote_id IN (
        SELECT DISTINCT im2.lote_id FROM inventario.item_movimientos im2
        JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im2.id WHERE im2.lote_id IS NOT NULL)
    UNION ALL
    SELECT im.lote_id, im.origen_ubicacion_id, -im.cantidad
    FROM inventario.item_movimientos im
    WHERE im.origen_ubicacion_id IS NOT NULL AND im.lote_id IN (
        SELECT DISTINCT im2.lote_id FROM inventario.item_movimientos im2
        JOIN inventario.consumo_kg_fix_log f ON f.item_movimiento_id = im2.id WHERE im2.lote_id IS NOT NULL)
) s GROUP BY lote_id, ubicacion_id;

-- revalue (precio_promedio already restored; preserve it)
UPDATE inventario.item_valoracion iv
SET stock_qty = COALESCE(s.qty,0),
    stock_valorado = ROUND(GREATEST(0,COALESCE(s.qty,0)) * iv.precio_promedio, 4),
    fyh_mod = now()
FROM (SELECT item_id, SUM(cantidad_actual) AS qty FROM inventario.item_saldo
      WHERE item_id IN (SELECT DISTINCT item_id FROM inventario.consumo_kg_fix_log) GROUP BY item_id) s
WHERE iv.item_id = s.item_id;

COMMIT;



SELECT COUNT(*), ROUND(SUM(cantidad),2)
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='PROD_CONSUMO_REV'
WHERE im.documento_tipo='partida_paso_ejecucion'
  AND im.cantidad >= 100   -- still grams-scale after the fix = missed
  AND NOT EXISTS (SELECT 1 FROM inventario.consumo_kg_fix_log f WHERE f.item_movimiento_id=im.id);

SELECT date_trunc('week', pe.fyh_inicio) AS semana, COUNT(*) AS runs_sin_consumo
FROM mes.partida_paso_ejecucion pe
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p       ON p.id  = pp.partida_id
WHERE pe.estado = 'COMPLETADO' AND pp.receta_id IS NOT NULL
  AND p.estado_produccion <> 'CANCELADA'
  AND pe.fyh_inicio >= '2026-05-25 00:00+00'
  AND NOT EXISTS (
      SELECT 1 FROM inventario.item_movimientos im
      JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo='PROD_CONSUMO'
      JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
      WHERE im.documento_tipo='partida_paso_ejecucion' AND im.documento_id = pe.id)
GROUP BY 1 ORDER BY 1;

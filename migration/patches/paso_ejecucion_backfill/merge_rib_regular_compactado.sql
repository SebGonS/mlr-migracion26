-- ============================================================================
-- MERGE · Rib/regular compactado pairs → one summed ejecucion
-- ============================================================================
-- WHAT: ~19 compactado partidas recorded rib and regular rolls as TWO legacy rows
--   with IDENTICAL (fyh_inicio, fyh_fin) — one physical compactado run split into a
--   rib pass and a regular pass. Step 06 already collapsed them to ONE paso with
--   TWO ejecuciones sharing the timespan. This merges those two into ONE ejecucion
--   with summed quantities.
--
-- SCOPE: compactado ejecuciones sharing (partida_paso_id, fyh_inicio, fyh_fin), >1
--   per group. Canonical = MIN(id); the rest are partners folded in and deleted.
--   (Genuinely separate compactado runs have DIFFERENT timespans — 1334 of them —
--   and are NOT touched; they legitimately stay as N ejecuciones under one paso.)
--
-- ORDER (reassign refs BEFORE delete — never orphan a chain):
--   1. sum partners' cantidad_rollos + peso_kg into the canonical,
--   2. re-point every partner ref (lote / item_movimientos / inspeccion) → canonical,
--   3. delete the partner ejecuciones.
--
-- Standalone deferred item. ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- ── Section 0 · DRY RUN — the pairs + what needs reassigning ──────────────────
WITH grp AS (
    SELECT ppe.id, ppe.partida_paso_id, ppe.fyh_inicio, ppe.fyh_fin,
           MIN(ppe.id) OVER w AS canonical_id, COUNT(*) OVER w AS n
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'COMPACTADO'
    WINDOW w AS (PARTITION BY ppe.partida_paso_id, ppe.fyh_inicio, ppe.fyh_fin)
),
partners AS (SELECT id AS partner_id, canonical_id FROM grp WHERE n > 1 AND id <> canonical_id)
SELECT
    (SELECT COUNT(DISTINCT canonical_id) FROM partners)                          AS groups,
    (SELECT COUNT(*) FROM partners)                                              AS partners_to_delete,
    (SELECT COUNT(*) FROM inventario.lote l
        WHERE l.documento_tipo='partida_paso_ejecucion'
          AND l.documento_id IN (SELECT partner_id FROM partners))               AS partner_lote_refs,
    (SELECT COUNT(*) FROM inventario.item_movimientos im
        WHERE im.documento_tipo='partida_paso_ejecucion'
          AND im.documento_id IN (SELECT partner_id FROM partners))              AS partner_movim_refs,
    (SELECT COUNT(*) FROM calidad.inspeccion i
        WHERE i.partida_paso_ejecucion_id IN (SELECT partner_id FROM partners))  AS partner_inspeccion_refs;


-- ── Section 1 · Merge ─────────────────────────────────────────────────────────
BEGIN;

CREATE TEMP TABLE _rib AS
SELECT ppe.id AS ejec_id, ppe.partida_paso_id,
       MIN(ppe.id) OVER w                 AS canonical_id,
       SUM(ppe.cantidad_rollos) OVER w    AS grp_rollos,
       SUM(ppe.peso_kg) OVER w            AS grp_kg,
       COUNT(*) OVER w                    AS n
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'COMPACTADO'
WINDOW w AS (PARTITION BY ppe.partida_paso_id, ppe.fyh_inicio, ppe.fyh_fin);

DELETE FROM _rib WHERE n = 1;   -- keep only rib/regular groups (>1 per timespan)

-- 1a. fold the summed quantities into the canonical ejecucion
UPDATE mes.partida_paso_ejecucion ppe
SET cantidad_rollos = r.grp_rollos, peso_kg = r.grp_kg, usr_mod = 4, fyh_mod = now()
FROM (SELECT DISTINCT canonical_id, grp_rollos, grp_kg FROM _rib) r
WHERE ppe.id = r.canonical_id;

-- 1b. re-point partner refs onto the canonical (BEFORE any delete)
UPDATE inventario.lote l
SET documento_id = r.canonical_id
FROM _rib r
WHERE r.ejec_id <> r.canonical_id
  AND l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = r.ejec_id;

UPDATE inventario.item_movimientos im
SET documento_id = r.canonical_id
FROM _rib r
WHERE r.ejec_id <> r.canonical_id
  AND im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = r.ejec_id;

-- inspeccion has UNIQUE(lote_id, partida_paso_ejecucion_id): move non-conflicting;
-- a conflicting one (canonical already inspected that lote) is dropped (no info lost
-- — the canonical already carries an inspeccion for that lote).
UPDATE calidad.inspeccion i
SET partida_paso_ejecucion_id = r.canonical_id
FROM _rib r
WHERE r.ejec_id <> r.canonical_id
  AND i.partida_paso_ejecucion_id = r.ejec_id
  AND NOT EXISTS (SELECT 1 FROM calidad.inspeccion i2
                  WHERE i2.partida_paso_ejecucion_id = r.canonical_id AND i2.lote_id = i.lote_id);
DELETE FROM calidad.inspeccion i
USING _rib r
WHERE r.ejec_id <> r.canonical_id AND i.partida_paso_ejecucion_id = r.ejec_id;

-- 1c. delete the folded partner ejecuciones (refs now moved)
DELETE FROM mes.partida_paso_ejecucion ppe
USING _rib r
WHERE r.ejec_id <> r.canonical_id AND ppe.id = r.ejec_id;


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) no partner ejecucion survives — expect 0
SELECT COUNT(*) AS partners_surviving
FROM mes.partida_paso_ejecucion ppe
WHERE ppe.id IN (SELECT ejec_id FROM _rib WHERE ejec_id <> canonical_id);

-- (b) no dangling refs to a deleted partner — all expect 0
SELECT
  (SELECT COUNT(*) FROM inventario.lote l WHERE l.documento_tipo='partida_paso_ejecucion'
      AND l.documento_id IN (SELECT ejec_id FROM _rib WHERE ejec_id<>canonical_id))          AS dangling_lote,
  (SELECT COUNT(*) FROM inventario.item_movimientos im WHERE im.documento_tipo='partida_paso_ejecucion'
      AND im.documento_id IN (SELECT ejec_id FROM _rib WHERE ejec_id<>canonical_id))         AS dangling_movim,
  (SELECT COUNT(*) FROM calidad.inspeccion i
      WHERE i.partida_paso_ejecucion_id IN (SELECT ejec_id FROM _rib WHERE ejec_id<>canonical_id)) AS dangling_inspeccion;

-- (c) no compactado paso still has same-timespan duplicate ejecuciones — expect 0
SELECT COUNT(*) AS remaining_rib_regular_groups
FROM (
    SELECT ppe.partida_paso_id, ppe.fyh_inicio, ppe.fyh_fin
    FROM mes.partida_paso_ejecucion ppe
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'COMPACTADO'
    GROUP BY ppe.partida_paso_id, ppe.fyh_inicio, ppe.fyh_fin
    HAVING COUNT(*) > 1
) x;

DROP TABLE _rib;

-- COMMIT;    -- ← after §2 all 0
-- ROLLBACK;  -- ← if anything is off


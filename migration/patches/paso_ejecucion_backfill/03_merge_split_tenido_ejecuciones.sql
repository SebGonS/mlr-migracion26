-- ============================================================================
-- 03 · Merge legacy shift-split TENIDO runs into one ejecucion (in place)   (paso-backfill step 03)
-- ============================================================================
-- WHAT: the legacy system split a dyeing run that crossed the 07:00 shift cutoff
--   into TWO produccion_tenido rows — a LEAD (estado='En Proceso Teñido', real
--   start, stunted end: null or midnight) and a COMPLETION (estado='Teñido',
--   placeholder 07:00 start, real end). The rolls never leave the machine: it is
--   ONE physical run and the per-row quantities are a reporting allocation that
--   SUMS to the run total. migration-11 (11_data_migration.sql:3040) recorded each
--   row as its own paso + ejecucion, so a split run currently exists as TWO
--   ejecuciones. This patch collapses each split run into ONE ejecucion.
--
-- CANONICAL = THE COMPLETION. The output lotes + real end live on the COMPLETION
--   half (161/190). The LEAD half carries only INPUT-CONSUMPTION movements
--   (item_movimientos — chemicals consumed in the first shift) — 0 output lote,
--   0 inspeccion, 0 termofijado. So we KEEP the completion ejecucion (it owns the
--   output + real end), fold the lead into it (add rolls/kg, set fyh_inicio = the
--   lead's real start), RE-POINT the lead's consumption movements onto the
--   completion, then DELETE the lead. Direct FKs (inspeccion/termofijado) are 0 on
--   leads (verified), so none are re-pointed — §1b asserts that and aborts if not.
--
-- REWORK SPLITS: migration-11 turned each rework row into its own CHILD partida
--   (partida_origen_id → original) + paso + ejecucion. A split rework is therefore
--   TWO child partidas for ONE physical rework. We keep the COMPLETION's child
--   partida (it has the output); the LEAD's child partida + paso is the phantom
--   → guarded delete (§2).
--
-- RUN IDENTITY: within (partida_id, legacy_maquina) ordered by time, a new run
--   starts at any row whose PREVIOUS row is NOT a lead ('En Proceso Teñido').
--   Consecutive leads + the terminating completion = one run (handles multi-window
--   chains). Exactly one 'Teñido' row per run = the completion = canonical.
--   Single-row runs (standalone completions, open leads) are left untouched.
--
-- MERGED VALUES (written onto the completion): fyh_inicio = the lead's real start
--   [MIN(fyh_inicio) over the run]; fyh_fin unchanged (completion's real end);
--   cantidad_rollos/peso_kg = SUM over the run; estado = COMPLETADO.
--
-- SCOPE: produccion_tenido only. Finishing ops (compactado/perchado/termofijado)
--   have zero stunted leads — they do not shift-split — so they are excluded.
--
-- NOT IN SCOPE (separate later step): re-pointing tenido output lotes to the real
--   last step (usually compactado). migration-11 bolted output onto tenido as a
--   bootstrap; correcting that genealogy is its own effort. Output stays on the
--   canonical tenido ejecucion here.
--
-- PREREQUISITES:
--   · step 01 re-run WITH legacy_estado populated.
--   · step 02 applied (Step A rework linking).
--   · migration-11 ejecucion layer present (pp.id = pt.id for produccion_tenido).
-- SEQUENCE: run AFTER step 02, BEFORE step 06 — relies on pp.id = pt.id (step 06's
--   re-parenting/deletion of extra pasos destroys that mapping). Independent of
--   step 04 (insert missing pasos) — either order is fine; this touches only the
--   already-migrated ejecuciones.
--
-- STATUS: APPLIED (committed after §3 verified 0/0/0/0). Dry-run §0 to re-inspect.
-- ============================================================================


-- ── Section 0 · DRY RUN — what will merge ─────────────────────────────────────
-- One row per split run. Check:
--   · n_rows = 2 (normal shift split) or >2 (multi-window chain)
--   · run_ejec = n_rows → both halves already migrated (handled here). run_ejec <
--     n_rows = partially migrated → excluded here, review separately.
WITH marked AS (
    SELECT le.legacy_id, le.partida_id, le.legacy_maquina, le.legacy_estado,
           le.fyh_inicio, le.fyh_fin, le.legacy_rollos, le.legacy_kilos,
           CASE WHEN LAG(le.legacy_estado)
                       OVER (PARTITION BY le.partida_id, le.legacy_maquina
                             ORDER BY le.fyh_inicio, le.legacy_id)
                     IS DISTINCT FROM 'En Proceso Teñido'
                THEN 1 ELSE 0 END AS is_new_run
    FROM migration.legacy_executions le
    WHERE le.source_table = 'produccion_tenido'
),
runs AS (
    SELECT m.*,
           SUM(m.is_new_run) OVER (PARTITION BY m.partida_id, m.legacy_maquina
                                   ORDER BY m.fyh_inicio, m.legacy_id) AS run_seq
    FROM marked m
),
enriched AS (
    SELECT r.partida_id, r.legacy_maquina, r.run_seq, r.legacy_id, r.legacy_estado,
           r.fyh_inicio, r.legacy_rollos, r.legacy_kilos,
           ppe.id AS ejec_id,
           COUNT(*)      OVER w AS run_size,
           COUNT(ppe.id) OVER w AS run_ejec,
           SUM(r.legacy_rollos) OVER w AS run_rollos,
           SUM(r.legacy_kilos)  OVER w AS run_kilos
    FROM runs r
    LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = r.legacy_id
    WINDOW w AS (PARTITION BY r.partida_id, r.legacy_maquina, r.run_seq)
)
SELECT partida_id, legacy_maquina, run_seq,
       MIN(run_size) AS n_rows, MIN(run_ejec) AS run_ejec,
       MIN(run_rollos) AS run_rollos, MIN(run_kilos) AS run_kilos,
       ARRAY_AGG(legacy_id ORDER BY fyh_inicio, legacy_id) AS legacy_ids,
       ARRAY_AGG(legacy_estado ORDER BY fyh_inicio, legacy_id) AS estados
FROM enriched
GROUP BY partida_id, legacy_maquina, run_seq
HAVING COUNT(*) > 1
ORDER BY n_rows DESC, partida_id
LIMIT 100;


-- ── Section 1 · Build the merge map + collapse ───────────────────────────────
BEGIN;

CREATE TEMP TABLE _split_map AS
WITH marked AS (
    SELECT le.legacy_id, le.partida_id, le.legacy_maquina, le.legacy_estado,
           le.fyh_inicio, le.fyh_fin, le.legacy_rollos, le.legacy_kilos,
           CASE WHEN LAG(le.legacy_estado)
                       OVER (PARTITION BY le.partida_id, le.legacy_maquina
                             ORDER BY le.fyh_inicio, le.legacy_id)
                     IS DISTINCT FROM 'En Proceso Teñido'
                THEN 1 ELSE 0 END AS is_new_run
    FROM migration.legacy_executions le
    WHERE le.source_table = 'produccion_tenido'
),
runs AS (
    SELECT m.*,
           SUM(m.is_new_run) OVER (PARTITION BY m.partida_id, m.legacy_maquina
                                   ORDER BY m.fyh_inicio, m.legacy_id) AS run_seq
    FROM marked m
),
enriched AS (
    SELECT r.legacy_id, r.partida_id, r.legacy_maquina, r.run_seq, r.legacy_estado,
           (r.legacy_estado = 'En Proceso Teñido') AS is_lead,
           ppe.id              AS ejec_id,
           ppe.partida_paso_id AS paso_id,
           COUNT(*)      OVER w AS run_size,
           COUNT(ppe.id) OVER w AS run_ejec,
           SUM(r.legacy_rollos) OVER w AS run_rollos,
           SUM(r.legacy_kilos)  OVER w AS run_kilos,
           MIN(r.fyh_inicio)    OVER w AS run_inicio,   -- lead's real start
           MAX(r.fyh_fin) FILTER (WHERE r.legacy_estado = 'Teñido') OVER w AS run_fin,
           -- canonical = the single 'Teñido' (completion) row of the run
           MAX(CASE WHEN r.legacy_estado = 'Teñido' THEN ppe.id END)              OVER w AS canonical_ejec_id,
           MAX(CASE WHEN r.legacy_estado = 'Teñido' THEN ppe.partida_paso_id END) OVER w AS canonical_paso_id
    FROM runs r
    LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = r.legacy_id
    WINDOW w AS (PARTITION BY r.partida_id, r.legacy_maquina, r.run_seq)
)
SELECT * FROM enriched
WHERE run_size > 1          -- split runs only
  AND run_ejec = run_size;  -- both halves already migrated
                            -- (run_ejec < run_size = partial migration → excluded;
                            --  section-0 dry run surfaces any such case)

-- 1a. fold run totals + the lead's real start into the COMPLETION (canonical)
UPDATE mes.partida_paso_ejecucion ppe
SET cantidad_rollos = sm.run_rollos,
    peso_kg         = sm.run_kilos,
    fyh_inicio      = sm.run_inicio,     -- ← lead's real start (was 07:00 placeholder)
    fyh_fin         = sm.run_fin,        -- completion's own real end (unchanged)
    estado          = 'COMPLETADO'::paso_ejecucion_estado_enum,
    usr_mod = 4, fyh_mod = now()
FROM (SELECT DISTINCT canonical_ejec_id, run_rollos, run_kilos, run_inicio, run_fin
      FROM _split_map) sm
WHERE ppe.id = sm.canonical_ejec_id;

-- 1b. re-point the leads' polymorphic refs (consumption movements; lote
--     defensively — 0 expected) onto the canonical completion.
UPDATE inventario.item_movimientos im
SET documento_id = sm.canonical_ejec_id
FROM _split_map sm
WHERE sm.is_lead
  AND im.documento_tipo = 'partida_paso_ejecucion'
  AND im.documento_id   = sm.ejec_id;

UPDATE inventario.lote l
SET documento_id = sm.canonical_ejec_id
FROM _split_map sm
WHERE sm.is_lead
  AND l.documento_tipo = 'partida_paso_ejecucion'
  AND l.documento_id   = sm.ejec_id;

-- SAFETY: leads carry no DIRECT FK (inspeccion/termofijado) — those aren't
-- re-pointed here, so abort if the data has drifted rather than orphan one.
DO $$
DECLARE v_refs int;
BEGIN
    SELECT
        (SELECT count(*) FROM calidad.inspeccion i
             WHERE i.partida_paso_ejecucion_id IN (SELECT ejec_id FROM _split_map WHERE is_lead))
      + (SELECT count(*) FROM mes.partida_paso_ejecucion_termofijado t
             WHERE t.ejecucion_id IN (SELECT ejec_id FROM _split_map WHERE is_lead))
      INTO v_refs;
    IF v_refs > 0 THEN
        RAISE EXCEPTION
          'ABORT: % lead ejecucion(es) carry a direct FK (inspeccion/termofijado) — '
          'expected 0; those are not re-pointed here. Investigate.', v_refs;
    END IF;
END $$;

-- 1c. delete the now-folded lead ejecuciones (refs moved to the completion)
DELETE FROM mes.partida_paso_ejecucion ppe
USING _split_map sm
WHERE sm.is_lead
  AND ppe.id = sm.ejec_id;


-- ── Section 2 · Guarded phantom rework child-partida cleanup ──────────────────
-- The LEAD's child partida (rework only) is now empty → phantom. NORMAL lead pasos
-- are empty extra pasos under the original partida — left for step 06 to drop.
-- Each phantom is deleted ONLY if it is a migration-11 artifact AND unreferenced;
-- otherwise RAISE (stop) so it can be debugged out-of-band. FK constraints are a
-- second safety net.
DO $$
DECLARE
    r      RECORD;
    v_refs int;
BEGIN
    FOR r IN
        SELECT DISTINCT sm.paso_id AS lead_paso_id, pp.partida_id AS child_partida_id
        FROM _split_map sm
        JOIN mes.partida_paso pp ON pp.id = sm.paso_id
        JOIN mes.partida      p  ON p.id  = pp.partida_id
        WHERE sm.is_lead
          AND p.partida_origen_id IS NOT NULL          -- rework child partida
    LOOP
        -- guard 1: migration-11 origin — paso.id is a legacy pt.id AND the child
        --          partida predates go-live. Post-go-live app reworks fail this.
        IF NOT EXISTS (SELECT 1 FROM produccion_tenido pt WHERE pt.id = r.lead_paso_id)
           OR (SELECT p.fyh_cre FROM mes.partida p WHERE p.id = r.child_partida_id)
                 > '2026-05-25 15:27:52+00'::timestamptz
        THEN
            RAISE EXCEPTION
              'ABORT: phantom paso % (child partida %) is NOT a migration-11 artifact '
              '(post-go-live or non-legacy). A rework may have been registered in the new '
              'system — investigate; not deleting.', r.lead_paso_id, r.child_partida_id;
        END IF;

        -- guard 2: nothing references the phantom (its ejecucion was deleted in §1c,
        --          no schedule, no other paso under the child partida)
        SELECT
            (SELECT count(*) FROM mes.partida_paso_ejecucion e WHERE e.partida_paso_id = r.lead_paso_id)
          + (SELECT count(*) FROM mes.programacion pr
                 WHERE pr.actividad_tipo='partida_paso' AND pr.actividad_id = r.lead_paso_id)
          + (SELECT count(*) FROM mes.partida_paso pp2
                 WHERE pp2.partida_id = r.child_partida_id AND pp2.id <> r.lead_paso_id)
          INTO v_refs;

        IF v_refs > 0 THEN
            RAISE EXCEPTION
              'ABORT: phantom child partida % / paso % still has % reference(s) — investigate; not deleting.',
              r.child_partida_id, r.lead_paso_id, v_refs;
        END IF;

        -- safe: hard-delete paso (cascades partida_componente) + detalle (no guard),
        -- then SOFT-delete the child partida. mes.partida forbids hard delete
        -- (fn_trg_prevent_hard_delete) — annul via fyh_elm per system policy. The
        -- §2 guards already restrict this to pre-go-live migration-11 phantoms.
        DELETE FROM mes.partida_paso    WHERE id         = r.lead_paso_id;
        DELETE FROM mes.partida_detalle WHERE partida_id = r.child_partida_id;
        UPDATE mes.partida
           SET fyh_elm = now(), usr_elm = 4
         WHERE id = r.child_partida_id;
    END LOOP;
END $$;


-- ── Section 3 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- Merged canonical ejecuciones + their folded totals:
SELECT COUNT(*) AS ejecuciones_merged,
       SUM(cantidad_rollos) AS total_rollos_on_merged
FROM mes.partida_paso_ejecucion ppe
WHERE ppe.id IN (SELECT canonical_ejec_id FROM _split_map);

-- Deleted leads must leave nothing behind (all four should be 0):
SELECT
  (SELECT count(*) FROM mes.partida_paso_ejecucion e
       WHERE e.id IN (SELECT ejec_id FROM _split_map WHERE is_lead))                       AS surviving_lead_ejec,
  (SELECT count(*) FROM inventario.lote l WHERE l.documento_tipo='partida_paso_ejecucion'
       AND l.documento_id IN (SELECT ejec_id FROM _split_map WHERE is_lead))               AS dangling_lote_refs,
  (SELECT count(*) FROM inventario.item_movimientos im WHERE im.documento_tipo='partida_paso_ejecucion'
       AND im.documento_id IN (SELECT ejec_id FROM _split_map WHERE is_lead))              AS dangling_movim_refs,
  (SELECT count(*) FROM calidad.inspeccion i
       WHERE i.partida_paso_ejecucion_id IN (SELECT ejec_id FROM _split_map WHERE is_lead)) AS dangling_inspeccion;

DROP TABLE _split_map;

-- COMMIT;    -- ← uncomment after §3 looks right (all 0s except the merged counts)
-- ROLLBACK;  -- ← if anything is off

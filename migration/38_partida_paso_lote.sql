-- ═══════════════════════════════════════════════════════════════
-- Step 38: per-roll production tracking — participation events + scope
--
-- DEPENDS ON: 35-37 (rib is a fabric; construccion exists for future routing).
--
-- ⚠ THIS FILE REPLACES an earlier draft that stored a per-roll SCOPE table
-- (mes.partida_paso_lote) with a mutable `estado` and a
-- sincronizar_alcance_pasos() sync function. Design review 2026-07-20 found
-- that draft conflated three concerns in one mutable row. The bare table + sync
-- function created live to unblock a core.sql deploy are DROPPED in §0, and the
-- sync calls in funciones/core.sql are reverted alongside this file. Nothing
-- was populated — no data to migrate.
--
-- THE VOCABULARY (so the model stays honest) ──────────────────────
--   partida  = production order AND dye batch (one bath = one order = one
--              homogeneous dye lot). The BATCH grain.
--   lote     = one physical roll. Despite the name (ERP "lote/lot" normally
--              means a homogeneous quantity), here 1 lote = 1 roll, so it is a
--              SERIALIZED UNIT, not a batch. The UNIT grain.
--   This migration formalizes the ROLLO (lote) as the unit of process
--   traceability. It does NOT make the rollo a "batch" — it adds serial-level
--   tracking BELOW the batch, which never existed.
--
-- THE THREE CONCERNS, KEPT SEPARATE ───────────────────────────────
--   PLANNING   — which rolls SHOULD pass an operation.   → vw_paso_lote_alcance
--                (DERIVED. today = all rolls; routing refines it. §2)
--   EXECUTION  — which rolls DID, in which run, outcome.  → mes.ejecucion_lote
--                (STORED, append-only event log. §1)
--   PROGRESS   — did / should.                            → vw_paso_progreso (§3)
--
--   There is deliberately NO stored per-roll `estado`. "In process / done" is a
--   fact about the RUN (partida_paso_ejecucion.estado); storing it again per
--   roll is the flg_rib mistake (two homes, free to disagree). "Not expected
--   here" is absence from the scope view. "Pulled mid-op" is a RETIRADO event.
--   Every question the old `estado` answered is derived from a run link or from
--   scope membership — which is also why an `omitido` flag alongside a derived
--   state was itself a planning/execution merge, and is gone.
--
-- WHY PARTICIPATION HANGS OFF THE RUN, NOT THE PASO ───────────────
-- The event is "this roll was in this run". ejecucion_id already implies the
-- paso (partida_paso_ejecucion.partida_paso_id), so the row is (ejecucion_id,
-- lote_id) — the paso is reachable, not stored twice. mes.ejecucion_lote is the
-- per-roll line items of a run, parallel to how partida_paso_ejecucion_termofijado
-- extends a run (migration 18).
--
-- WHY LOTE, NOT THE RESERVATION ROW ───────────────────────────────
-- Links to inventario.lote (the roll's stable identity), never to
-- partida_componente (a planning artifact actualizar_componentes_partida
-- deletes and re-inserts). Execution/audit anchors to the durable entity.
-- Confirmed 2026-07-20: no intermediate step mints new lotes — the input
-- lote_id is stable across every paso.
--
-- RECORD EVERYTHING, UNIFORMLY ────────────────────────────────────
-- One rule: when a run processes a roll, it emits one event — teñido included
-- (one run → N events), not just finishing. The earlier "store only divergence"
-- idea was rejected as operation-type conditional logic (the flg_rib smell),
-- and because "did" is never derivable from "should" even when they match: a
-- confirmation that the plan was followed is the whole job of an execution
-- layer (≈ SAP AFRU, one confirmation per operation). Storage is a non-issue.
-- ═══════════════════════════════════════════════════════════════


-- ── §0. Tear down the pulled draft ───────────────────────────────
-- Both created bare/empty to unblock a core.sql deploy; neither populated.
-- The core.sql sync calls are reverted in the same change set.
DROP FUNCTION IF EXISTS mes.sincronizar_alcance_pasos(BIGINT);
DROP TABLE    IF EXISTS mes.partida_paso_lote;


-- ── §1. mes.ejecucion_lote — participation (EXECUTION / AUDIT) ────
-- Append-only event log. A row = "roll L took part in run E, with outcome R".
DO $$ BEGIN
    CREATE TYPE paso_lote_resultado_enum AS ENUM (
        'PROCESADO',   -- completed the operation normally
        'SCRAP',       -- condemned during this operation (≈ AFRU.AFRUASC)
        'RETIRADO'     -- pulled out to go elsewhere (reproceso/re-route), not destroyed
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS mes.ejecucion_lote (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ejecucion_id BIGINT NOT NULL REFERENCES mes.partida_paso_ejecucion(id) ON DELETE CASCADE,
    lote_id      BIGINT NOT NULL REFERENCES inventario.lote(id),
    resultado    paso_lote_resultado_enum NOT NULL DEFAULT 'PROCESADO',
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW()
    -- Surrogate PK + NO unique(ejecucion_id, lote_id): a roll can legitimately
    -- reappear (rework, a re-run of the same paso). Event log, not state table —
    -- repeats across runs are the data, not a violation.
);

CREATE INDEX IF NOT EXISTS idx_ejecucion_lote_lote      ON mes.ejecucion_lote (lote_id);
CREATE INDEX IF NOT EXISTS idx_ejecucion_lote_ejecucion ON mes.ejecucion_lote (ejecucion_id);

ALTER TABLE mes.ejecucion_lote ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "produccion_ver" ON mes.ejecucion_lote;
CREATE POLICY "produccion_ver" ON mes.ejecucion_lote
    FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));

DROP TRIGGER IF EXISTS trg_bi_ejecucion_lote_audit ON mes.ejecucion_lote;
CREATE TRIGGER trg_bi_ejecucion_lote_audit
    BEFORE INSERT ON mes.ejecucion_lote
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

GRANT SELECT ON mes.ejecucion_lote TO authenticated;

-- Starts EMPTY, NOT backfilled. Historical runs never recorded which roll they
-- processed — genuinely unrecoverable, and inventing it would fabricate
-- traceability in the one table meant to be trustworthy (decision 9's rule).
-- Fills going forward once the emit is wired into the paso-completion path (§4a).


-- ── §2. vw_paso_lote_alcance — scope (PLANNING, derived) ──────────
-- Which rolls SHOULD pass each paso. DERIVED, never stored — no sync, no
-- trigger, nothing to drift. (The sync-function pattern was the tell that scope
-- was being wrongly materialized.)
--
-- ⚠ TODAY: ALL ROLLS × ALL PASOS — the current implicit assumption, now written
-- in exactly ONE place. Still WRONG for rib (rib rolls appear in perchado scope
-- → 20/22 persists), and that is deliberate and honest: the denominator cannot
-- be correct until routing exists to say rib∉perchado. When routing lands, ONLY
-- this view's WHERE clause changes and every consumer becomes correct with no
-- further edit. That single point of change is the whole reason scope is a view.
CREATE OR REPLACE VIEW mes.vw_paso_lote_alcance AS
SELECT
    pp.id          AS partida_paso_id,
    pp.partida_id,
    pp.operacion_id,
    pc.lote_id
FROM mes.partida_paso pp
JOIN mes.partida_componente pc ON pc.partida_id = pp.partida_id
WHERE pc.lote_id IS NOT NULL          -- chemical rows carry item_id, not lote_id
-- ROUTING FILTER GOES HERE (migration 39+):
--   AND <the roll's fabric route includes pp.operacion_id>
-- resolved lote → item_rollo_detalle → articulo → construccion_id → route.
;

GRANT SELECT ON mes.vw_paso_lote_alcance TO authenticated;


-- ── §3. vw_paso_progreso — progress (did / should) ───────────────
-- Denominator = scope (§2); numerator = distinct rolls with a PROCESADO event
-- on any run of the paso. Replaces the frontend "20/22", and becomes correct
-- automatically when §2 gains its routing filter — no change here.
CREATE OR REPLACE VIEW mes.vw_paso_progreso AS
SELECT
    pp.id            AS partida_paso_id,
    pp.partida_id,
    pp.operacion_id,
    (SELECT COUNT(*) FROM mes.vw_paso_lote_alcance a
      WHERE a.partida_paso_id = pp.id)                       AS rollos_alcance,     -- should
    (SELECT COUNT(DISTINCT el.lote_id)
       FROM mes.partida_paso_ejecucion pe
       JOIN mes.ejecucion_lote el ON el.ejecucion_id = pe.id
      WHERE pe.partida_paso_id = pp.id
        AND el.resultado = 'PROCESADO')                       AS rollos_procesados  -- did
FROM mes.partida_paso pp;

GRANT SELECT ON mes.vw_paso_progreso TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- §4. NOT DONE HERE — the remaining wiring
-- ═══════════════════════════════════════════════════════════════
-- This file establishes STRUCTURE only. It changes no live behaviour:
-- ejecucion_lote is empty, and vw_paso_progreso reads the all-rolls scope until
-- routing refines it.
--
--   a) EMIT PARTICIPATION. The paso-completion path (registrar_produccion /
--      finalizar_paso, funciones/mes.sql) inserts one mes.ejecucion_lote row per
--      roll the run processed. Until then, rollos_procesados is 0.
--
--   b) MOVE THE DENOMINATOR. Whatever renders "rollos procesados" reads
--      mes.vw_paso_progreso (rollos_procesados / rollos_alcance).
--      ejecucion.cantidad_rollos stays — per-RUN yield snapshot (≈ AFRU), a
--      different fact from per-paso progress.
--
--   c) ROUTING (migration 39+) — the OPEN design fork. A route is per-FABRIC
--      (finishing differs by fabric: rib is not brushed, polyester must be
--      heat-set), realized as the §2 filter. partida_paso stays the order's
--      operation list (the UNION of member fabrics' routes); scope picks each
--      roll's subset. UNSETTLED: does the route key on construccion_id alone, or
--      construccion_id + fibra + composition? That decides ruta_plantilla's
--      applicability key — the one thing not to guess. The partida grain is NOT
--      wrong: dyeing is inherently batch-grain (shared bath); routing adds a
--      grain BELOW it (per-roll scope) and a master ABOVE it (per-fabric route
--      that partida_paso is copied from instead of hand-entered).
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════
-- PATCH: Rollback the last paso execution for targeted partidas
--
-- PURPOSE:
--   Before re-running ejecucion backfill (08_migrar_ejecuciones_batch), remove
--   or reset any ejecucion that was incorrectly created by a previous migration
--   attempt.
--
-- DECISION RULE (per ejecucion):
--   ejecucion.fyh_cre > v_migration_cutoff  →  DELETE cascade
--     (migration artifact: output lotes, PROD_ING/PROD_CONSUMO movements, ejecucion)
--   ejecucion.fyh_cre <= v_migration_cutoff →  UPDATE estado = 'PENDIENTE'
--     (real historical record: inventory already committed, only status is reset)
--
-- SCOPE:
--   Targets only the LAST ejecucion of the LAST paso (highest secuencia) for
--   each partida in v_partida_ids.  Earlier pasos / earlier ejecuciones are
--   not touched.
--
-- WORKFLOW:
--   1. Edit v_partida_ids and v_migration_cutoff below.
--   2. Run SECTION 1 (DRY RUN) — review what will be touched.
--   3. Run SECTION 2 (EXECUTE) — commits the rollback.
--   4. Run SECTION 3 (VERIFY) — confirm post-rollback state.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────────
-- SECTION 1 — DRY RUN  (read-only)
-- ───────────────────────────────────────────────────────────────────────────────

WITH params AS (
    SELECT
        ARRAY[0]::BIGINT[]                         AS partida_ids,   -- ← EDIT
        TIMESTAMPTZ '2026-06-01 00:00:00-05'       AS migration_cutoff
),
last_paso AS (
    SELECT DISTINCT ON (pp.partida_id)
        pp.partida_id,
        pp.id          AS paso_id,
        pp.secuencia,
        o.codigo       AS operacion_codigo
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id = pp.operacion_id
    WHERE pp.partida_id = ANY((SELECT partida_ids FROM params))
    ORDER BY pp.partida_id, pp.secuencia DESC
),
last_ejecucion AS (
    SELECT DISTINCT ON (pe.partida_paso_id)
        lp.partida_id,
        lp.paso_id,
        lp.secuencia,
        lp.operacion_codigo,
        pe.id              AS ejecucion_id,
        pe.estado          AS ejecucion_estado,
        pe.fyh_cre         AS ejecucion_fyh_cre,
        pe.fyh_inicio,
        pe.fyh_fin
    FROM last_paso lp
    JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = lp.paso_id
    ORDER BY pe.partida_paso_id, pe.id DESC
)
SELECT
    le.partida_id,
    le.operacion_codigo,
    le.secuencia,
    le.paso_id,
    le.ejecucion_id,
    le.ejecucion_estado,
    le.ejecucion_fyh_cre,
    le.fyh_inicio,
    le.fyh_fin,
    CASE
        WHEN le.ejecucion_fyh_cre > p.migration_cutoff THEN 'DELETE cascade'
        ELSE 'UPDATE → PENDIENTE'
    END                                            AS accion,
    (
        SELECT COUNT(*)
        FROM inventario.lote l
        WHERE l.documento_tipo = 'partida_paso_ejecucion'
          AND l.documento_id   = le.ejecucion_id
    )                                              AS output_lotes,
    (
        SELECT COUNT(*)
        FROM inventario.item_movimientos im
        WHERE im.documento_tipo = 'partida_paso_ejecucion'
          AND im.documento_id   = le.ejecucion_id
    )                                              AS movimientos_ligados
FROM last_ejecucion le, params p
ORDER BY le.partida_id;


-- Partidas in the list that have NO ejecucion on their last paso
-- (good: they can receive script 08 without any rollback needed)
WITH params AS (
    SELECT ARRAY[0]::BIGINT[] AS partida_ids
),
last_paso AS (
    SELECT DISTINCT ON (pp.partida_id)
        pp.partida_id,
        pp.id AS paso_id,
        pp.secuencia
    FROM mes.partida_paso pp
    WHERE pp.partida_id = ANY((SELECT partida_ids FROM params))
    ORDER BY pp.partida_id, pp.secuencia DESC
)
SELECT lp.partida_id, lp.paso_id, lp.secuencia, 'NO EJECUCION — ready for 08' AS estado
FROM last_paso lp
WHERE NOT EXISTS (
    SELECT 1 FROM mes.partida_paso_ejecucion pe
    WHERE pe.partida_paso_id = lp.paso_id
);


-- ───────────────────────────────────────────────────────────────────────────────
-- SECTION 2 — EXECUTE
-- ───────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    -- ── CONFIGURE THESE ─────────────────────────────────────────────────────
    v_partida_ids       BIGINT[]    := ARRAY[0];                          -- ← EDIT
    v_migration_cutoff  TIMESTAMPTZ := TIMESTAMPTZ '2026-06-01 00:00:00-05'; -- ← EDIT
    v_usr_admin         INT         := 1;
    -- ────────────────────────────────────────────────────────────────────────

    v_partida_id        BIGINT;
    v_paso_id           BIGINT;
    v_ejecucion_id      BIGINT;
    v_ejecucion_fyh_cre TIMESTAMPTZ;
    v_output_lote_ids   BIGINT[];
    v_del_movs          INT;
    v_del_lotes         INT;
BEGIN
    FOREACH v_partida_id IN ARRAY v_partida_ids LOOP

        -- ── 1. Find the last paso ────────────────────────────────────────────
        SELECT pp.id
        INTO v_paso_id
        FROM mes.partida_paso pp
        WHERE pp.partida_id = v_partida_id
        ORDER BY pp.secuencia DESC
        LIMIT 1;

        IF v_paso_id IS NULL THEN
            RAISE NOTICE 'Partida #%: sin pasos — saltando.', v_partida_id;
            CONTINUE;
        END IF;

        -- ── 2. Find the last ejecucion on that paso ──────────────────────────
        SELECT pe.id, pe.fyh_cre
        INTO v_ejecucion_id, v_ejecucion_fyh_cre
        FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = v_paso_id
        ORDER BY pe.id DESC
        LIMIT 1;

        IF v_ejecucion_id IS NULL THEN
            RAISE NOTICE 'Partida #%: paso % sin ejecucion — saltando.',
                v_partida_id, v_paso_id;
            CONTINUE;
        END IF;

        -- ── 3. Branch on creation date ───────────────────────────────────────
        IF v_ejecucion_fyh_cre > v_migration_cutoff THEN
            -- ── 3a. POST-CUTOFF: full DELETE cascade ─────────────────────────

            -- Collect output lotes (PROD_ING ingress produced by this ejecucion)
            SELECT ARRAY(
                SELECT l.id
                FROM inventario.lote l
                WHERE l.documento_tipo = 'partida_paso_ejecucion'
                  AND l.documento_id   = v_ejecucion_id
            ) INTO v_output_lote_ids;

            -- Delete all movements for the output lotes
            DELETE FROM inventario.item_movimientos
            WHERE lote_id = ANY(v_output_lote_ids);

            GET DIAGNOSTICS v_del_movs = ROW_COUNT;
            RAISE NOTICE 'Partida #%: eliminados % movimientos de lotes PROD_ING.',
                v_partida_id, v_del_movs;

            -- Delete PROD_CONSUMO (input roll egress) tied to this ejecucion
            DELETE FROM inventario.item_movimientos
            WHERE documento_tipo = 'partida_paso_ejecucion'
              AND documento_id   = v_ejecucion_id;

            GET DIAGNOSTICS v_del_movs = ROW_COUNT;
            RAISE NOTICE 'Partida #%: eliminados % movimientos PROD_CONSUMO.',
                v_partida_id, v_del_movs;

            -- Delete lote_rollo_detalle before lote (no CASCADE on FK)
            DELETE FROM inventario.lote_rollo_detalle
            WHERE lote_id = ANY(v_output_lote_ids);

            -- Delete the output lotes themselves
            DELETE FROM inventario.lote
            WHERE id = ANY(v_output_lote_ids);

            GET DIAGNOSTICS v_del_lotes = ROW_COUNT;
            RAISE NOTICE 'Partida #%: eliminados % lotes PROD_ING.',
                v_partida_id, v_del_lotes;

            -- Delete the ejecucion
            DELETE FROM mes.partida_paso_ejecucion
            WHERE id = v_ejecucion_id;

            RAISE NOTICE 'Partida #%: ejecucion % eliminada (fyh_cre=% > cutoff).',
                v_partida_id, v_ejecucion_id, v_ejecucion_fyh_cre;

            -- Reset the paso estado to PENDIENTE only if it was also created post-cutoff
            -- (pre-cutoff pasos have historical state that should not be disturbed)
            UPDATE mes.partida_paso
            SET estado   = 'PENDIENTE',
                usr_mod  = v_usr_admin,
                fyh_mod  = NOW()
            WHERE id     = v_paso_id
              AND fyh_cre > v_migration_cutoff;

            IF FOUND THEN
                RAISE NOTICE 'Partida #%: paso % → PENDIENTE (también post-cutoff).',
                    v_partida_id, v_paso_id;
            END IF;

        ELSE
            -- ── 3b. PRE-CUTOFF: soft reset only ──────────────────────────────
            -- WARNING: only safe when the ejecucion has no committed inventory
            -- (no PROD_CONSUMO movements). The DRY RUN shows movimientos_ligados;
            -- if that value is > 0 this reset will leave inventory in an
            -- inconsistent state — consider DELETE cascade instead.
            UPDATE mes.partida_paso_ejecucion
            SET estado   = 'PENDIENTE',
                fyh_fin  = NULL,
                usr_mod  = v_usr_admin,
                fyh_mod  = NOW()
            WHERE id = v_ejecucion_id;

            RAISE NOTICE 'Partida #%: ejecucion % → PENDIENTE (fyh_cre=% ≤ cutoff, inventario intacto).',
                v_partida_id, v_ejecucion_id, v_ejecucion_fyh_cre;
        END IF;

        -- ── 4. Recalculate partida state ─────────────────────────────────────
        PERFORM mes.actualizar_estado_partida(v_partida_id);
        RAISE NOTICE 'Partida #%: estado recalculado → %',
            v_partida_id,
            (SELECT estado_produccion FROM mes.partida WHERE id = v_partida_id);

    END LOOP;
END;
$$;


-- ───────────────────────────────────────────────────────────────────────────────
-- SECTION 3 — VERIFY
-- ───────────────────────────────────────────────────────────────────────────────

WITH params AS (SELECT ARRAY[0]::BIGINT[] AS partida_ids)
SELECT
    p.id                                            AS partida_id,
    p.estado_produccion,
    pp.id                                           AS paso_id,
    pp.secuencia,
    o.codigo                                        AS operacion,
    pp.estado                                       AS paso_estado,
    pe.id                                           AS ejecucion_id,
    pe.estado                                       AS ejecucion_estado,
    pe.fyh_cre,
    (
        SELECT COUNT(*)
        FROM inventario.lote l
        WHERE l.documento_tipo = 'partida_paso_ejecucion'
          AND l.documento_id   = pe.id
    )                                               AS output_lotes_restantes
FROM params
JOIN mes.partida p       ON p.id = ANY(params.partida_ids)
LEFT JOIN mes.partida_paso pp     ON pp.partida_id = p.id
LEFT JOIN mes.operacion o         ON o.id = pp.operacion_id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
ORDER BY p.id, pp.secuencia, pe.id;

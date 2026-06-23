-- ============================================================================
-- NUKE PARTIDAS: A&R TEXTILES / entrega 505 (ran 2026-05-26)
-- ============================================================================
-- Removes partidas that were incorrectly imported into the new system.
-- Target: SELECT partida FROM vw_partidas_resumen WHERE entrega ILIKE '%505%'
--         AND cliente = 'A&R TEXTILES'
--
-- Approach:
--   1. Hard-delete all item_movimientos for target lotes — the movements are
--      equally garbage data from the bad import, no compensating entries needed.
--   2. Hard-delete lotes (pesaje, lote_rollo_detalle, then lote) using
--      SET LOCAL session_replication_role = replica to bypass FK checks.
--   3. Hard-delete partida child tables in FK order.
--   4. Hard-delete mes.partida (same replica bypass).
--
-- SAFE TO RE-RUN: array_length / NOT EXISTS guards prevent double-execution.
-- ============================================================================

-- ─── DRY RUN ─────────────────────────────────────────────────────────────────
-- Run this SELECT block first to preview scope before executing the DO block.
-- ─────────────────────────────────────────────────────────────────────────────
/*
WITH target_ids AS (
    SELECT partida AS id FROM vw_partidas_resumen
    WHERE entrega ILIKE '%505%' AND cliente = 'A&R TEXTILES'
),
target_lotes AS (
    SELECT
        l.id            AS lote_id,
        l.item_id,
        l.documento_tipo,
        l.documento_id  AS partida_id,
        l.cantidad,
        -- direction: credit when destino only (ingress), debit when origen set (egress)
        COALESCE(
            SUM(CASE WHEN im.origen_ubicacion_id IS NOT NULL THEN -im.cantidad
                     ELSE im.cantidad END),
            0
        )               AS saldo_actual
    FROM inventario.lote l
    LEFT JOIN inventario.item_movimientos im ON im.lote_id = l.id
    WHERE l.documento_tipo = 'PARTIDA'
      AND l.documento_id IN (SELECT id FROM target_ids)
    GROUP BY l.id, l.item_id, l.documento_tipo, l.documento_id, l.cantidad
)
SELECT
    p.id            AS partida_id,
    p.estado_produccion,
    p.estado_comercial,
    COUNT(DISTINCT tl.lote_id)              AS lotes_count,
    COUNT(DISTINCT pp.id)                   AS pasos_count,
    COUNT(DISTINCT ppe.id)                  AS ejecuciones_count,
    COUNT(DISTINCT pc.id)                   AS componentes_count,
    SUM(CASE WHEN tl.saldo_actual > 0 THEN 1 ELSE 0 END) AS lotes_con_saldo,
    SUM(tl.saldo_actual)                    AS saldo_total_kg
FROM target_ids ti
JOIN mes.partida p                ON p.id = ti.id
LEFT JOIN target_lotes tl         ON tl.partida_id = ti.id
LEFT JOIN mes.partida_paso pp     ON pp.partida_id = ti.id
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
LEFT JOIN mes.partida_componente pc ON pc.partida_id = ti.id
GROUP BY p.id, p.estado_produccion, p.estado_comercial
ORDER BY p.id;
*/

-- ─── DESTRUCTIVE BLOCK ───────────────────────────────────────────────────────
-- Wrap in BEGIN/ROLLBACK for a rehearsal run; swap to COMMIT when ready.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_target_ids     BIGINT[];
    v_lote_ids       INT[];
    v_nuked_partidas INT;
    v_nuked_lotes    INT;
    v_nuked_movs     INT;
BEGIN
    -- ── 0. Resolve targets ────────────────────────────────────────────────────
    SELECT array_agg(partida)
    INTO v_target_ids
    FROM vw_partidas_resumen
    WHERE entrega ILIKE '%505%' AND cliente = 'A&R TEXTILES';

    IF v_target_ids IS NULL OR array_length(v_target_ids, 1) = 0 THEN
        RAISE NOTICE 'No target partidas found — nothing to do.';
        RETURN;
    END IF;
    RAISE NOTICE 'Target partidas (%): %', array_length(v_target_ids, 1), v_target_ids;

    SELECT array_agg(l.id)
    INTO v_lote_ids
    FROM inventario.lote l
    WHERE l.documento_tipo = 'PARTIDA'
      AND l.documento_id = ANY(v_target_ids);

    RAISE NOTICE 'Roll lotes to nuke: %', COALESCE(array_length(v_lote_ids, 1), 0);

    -- From here on everything runs under replica mode to bypass FK triggers.
    SET LOCAL session_replication_role = replica;

    -- ── 1. Nuke inventory movements for target lotes ──────────────────────────
    IF v_lote_ids IS NOT NULL AND array_length(v_lote_ids, 1) > 0 THEN
        DELETE FROM inventario.item_movimientos WHERE lote_id = ANY(v_lote_ids);
        GET DIAGNOSTICS v_nuked_movs = ROW_COUNT;
        RAISE NOTICE 'item_movimientos deleted: %', v_nuked_movs;

        DELETE FROM inventario.pesaje           WHERE lote_id = ANY(v_lote_ids);
        DELETE FROM inventario.lote_rollo_detalle WHERE lote_id = ANY(v_lote_ids);

        DELETE FROM inventario.lote WHERE id = ANY(v_lote_ids);
        GET DIAGNOSTICS v_nuked_lotes = ROW_COUNT;
        RAISE NOTICE 'Lotes deleted: %', v_nuked_lotes;
    END IF;

    -- ── 2. Delete partida child tables (FK order) ─────────────────────────────
    DELETE FROM calidad.inspeccion
    WHERE partida_paso_ejecucion_id IN (
        SELECT ppe.id
        FROM mes.partida_paso_ejecucion ppe
        JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
        WHERE pp.partida_id = ANY(v_target_ids)
    );

    DELETE FROM mes.programacion
    WHERE actividad_id IN (
        SELECT id FROM mes.partida_paso WHERE partida_id = ANY(v_target_ids)
    );

    DELETE FROM mes.partida_componente        WHERE partida_id = ANY(v_target_ids);

    DELETE FROM mes.partida_paso_ejecucion
    WHERE partida_paso_id IN (
        SELECT id FROM mes.partida_paso WHERE partida_id = ANY(v_target_ids)
    );

    DELETE FROM mes.partida_paso              WHERE partida_id = ANY(v_target_ids);
    DELETE FROM mes.partida_detalle           WHERE partida_id = ANY(v_target_ids);

    -- NULL nullable FK on invoice lines rather than deleting them
    UPDATE doc.factura_detalle SET partida_id = NULL WHERE partida_id = ANY(v_target_ids);
    -- NULL rework back-references
    UPDATE mes.partida SET partida_origen_id = NULL   WHERE partida_origen_id = ANY(v_target_ids);

    -- ── 3. Nuke the partidas themselves ───────────────────────────────────────
    DELETE FROM mes.partida WHERE id = ANY(v_target_ids);
    GET DIAGNOSTICS v_nuked_partidas = ROW_COUNT;

    SET LOCAL session_replication_role = DEFAULT;

    RAISE NOTICE '=== DONE: % partidas, % lotes, % movements deleted ===',
        v_nuked_partidas, COALESCE(v_nuked_lotes, 0), COALESCE(v_nuked_movs, 0);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- BACKFILL (re-run): recompute estado_produccion for ALL non-terminal partidas
--
-- WHY
--   05_recalc_estado_produccion.sql only processed id > 4000 and skipped
--   EN_PRODUCCION/TECO, so thousands of partidas (e.g. 2001-2119) stayed at the
--   CREADA default even though the migration gave them completed pasos+ejecuciones.
--   Direct inserts never call iniciar_paso/finalizar_paso, which are what normally
--   trigger mes.actualizar_estado_partida — so the state machine never ran for them.
--   Result: they linger in calidad.vw_partidas_pendientes_calidad (only CERRADA/
--   CANCELADA are excluded there) and 10_cerrar_partidas_despachadas.sql can't see
--   them (it acts only on TECO).
--
-- WHAT THIS DOES
--   Calls mes.actualizar_estado_partida for every partida that has pasos and is not
--   already terminal. The function derives the correct state from current paso
--   states (never touches CERRADA/CANCELADA):
--     all pasos have a COMPLETADO/OMITIDO ejecucion  → TECO
--     any paso EN_PROCESO                            → EN_PRODUCCION
--     pasos exist but no ejecucion yet               → PLANIFICADA / PROGRAMADA
--   No id filter, includes EN_PRODUCCION (so ones whose EN_PROCESO ejecuciones were
--   since completed advance to TECO).
--
-- SAFE & IDEMPOTENT: pure recompute from live paso/ejecucion state; re-running is a
--   no-op once states are correct. TECO requires EVERY paso terminal, so genuinely
--   in-progress partidas are NOT wrongly closed.
--
-- AFTER THIS: re-run 10_cerrar_partidas_despachadas.sql to close the now-TECO
--   dispatched partidas (TECO → CERRADA) so they leave the pending-QC view.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — BEFORE  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════
SELECT p.estado_produccion, COUNT(*) AS partidas
FROM mes.partida p
WHERE p.estado_produccion NOT IN ('CERRADA','CANCELADA')
  AND EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id = p.id)
GROUP BY p.estado_produccion
ORDER BY partidas DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — RECOMPUTE
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_id BIGINT;
    v_n  INT := 0;
BEGIN
    FOR v_id IN
        SELECT p.id
        FROM mes.partida p
        WHERE p.estado_produccion NOT IN ('CERRADA','CANCELADA')
          AND EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id = p.id)
        ORDER BY p.id
    LOOP
        PERFORM mes.actualizar_estado_partida(v_id);
        v_n := v_n + 1;
    END LOOP;

    RAISE NOTICE '═══════════ RECALC ESTADO PARTIDA ═══════════';
    RAISE NOTICE '  partidas recomputadas : %', v_n;
    RAISE NOTICE '═════════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — AFTER
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. New state distribution.
SELECT p.estado_produccion, COUNT(*) AS partidas
FROM mes.partida p
WHERE p.estado_produccion NOT IN ('CERRADA','CANCELADA')
  AND EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id = p.id)
GROUP BY p.estado_produccion
ORDER BY partidas DESC;

-- 2b. Now-TECO partidas dispatched in legacy — these will close on the next
--     10_cerrar_partidas_despachadas.sql run.
SELECT COUNT(*) AS teco_con_despacho_listas_para_cerrar
FROM mes.partida p
WHERE p.estado_produccion = 'TECO'
  AND EXISTS (
      SELECT 1 FROM public.despacho d
      WHERE d.flg_elm = false AND d.partida_id = COALESCE(p.partida_origen_id, p.id)
  );

-- 2c. Still NOT TECO after recompute (stuck) — investigate separately. A paso with
--     an EN_PROCESO ejecucion or with NO ejecucion at all keeps a partida off TECO.
SELECT
    p.estado_produccion,
    COUNT(DISTINCT p.id) AS partidas,
    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe WHERE pe.partida_paso_id = pp.id
    ))                                   AS pasos_sin_ejecucion,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion pe
        WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
    ))                                   AS pasos_en_proceso
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.partida_id = p.id
WHERE p.estado_produccion NOT IN ('CERRADA','CANCELADA','TECO')
  AND EXISTS (
      SELECT 1 FROM mes.partida_paso_ejecucion pe2
      JOIN mes.partida_paso pp2 ON pp2.id = pe2.partida_paso_id
      WHERE pp2.partida_id = p.id
  )
GROUP BY p.estado_produccion
ORDER BY partidas DESC;

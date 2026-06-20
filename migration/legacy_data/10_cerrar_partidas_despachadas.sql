-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX: close legacy dispatched partidas so they leave the pending-QC view
--
-- SYMPTOM
--   Many old partidas still appear in calidad.vw_partidas_pendientes_calidad even
--   after their output was egressed by 09_despacho_egreso_legacy.sql.
--
-- ROOT CAUSE
--   That view's Path A (pure output rolls) has NO lote_saldo guard — egressing a
--   roll does NOT drop it from pending QC. The view's only exit for dispatched
--   output is the partida being CERRADA/CANCELADA (see 08_views.sql line ~1326):
--       AND COALESCE(p.estado_produccion,'CREADA') NOT IN ('CERRADA','CANCELADA')
--   These partidas are stuck at TECO (production complete) because the despacho
--   migration posted guias/movements directly and never advanced estado_comercial
--   / estado_facturacion — so mes.cerrar_partida's three-axis gate can't close them.
--
-- FIX (legacy backfill — same precedent as 11_data_migration closing 'Despachado'
--   partidas directly). Two cases, told apart by whether dyed output still remains
--   in stock after 09 egressed everything that was shipped:
--     • FULLY delivered (no dyed output left in stock):
--         estado_produccion = 'CERRADA', estado_comercial = 'ENTREGADA'
--         → drops out of the pending-QC view.
--     • PARTIALLY delivered (despacho exists but dyed output still in stock):
--         estado_produccion stays 'TECO', estado_comercial = 'ENTREGA_PARCIAL'
--         → undelivered rolls stay QC-able and dispatchable (CERRADA would block
--           their future despacho); only the commercial state is corrected. Their
--           already-shipped rolls keep showing in pending-QC until the partida is
--           fully delivered and closed — the Path-A no-saldo-guard behavior, by design.
--
-- SCOPE (covers originals AND rework children via COALESCE(partida_origen_id, id)):
--   p.estado_produccion = 'TECO' ∧ EXISTS active public.despacho.
--   Reworks are TECO-terminal in the live flow, but closing fully-dispatched
--   historical reworks is correct; cerrar_partida's parent gate accepts CERRADA
--   reworks, so nothing breaks.
--
-- NOT TOUCHED: PENDIENTE / EN_PRODUCCION partidas, and partidas with no legacy
--   despacho (genuinely pending). estado_facturacion is left as-is (billing not
--   migrated; this is a production/QC settlement, not a commercial one).
--
-- Idempotent: only flips rows still at TECO.
-- ═══════════════════════════════════════════════════════════════════════════════
-- SELECT * FROM mes.partida WHERE id=4320
-- --  UPDATE mes.partida set estado_produccion='TECO', estado_comercial='ENTREGA_PARCIAL'  WHERE id=4320
-- SELECT * FROM partida WHERE id=4320
-- SELECT * FROM despacho WHERE partida_id=4320

-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PREVIEW  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0a. Breakdown of TECO partidas dispatched in legacy: fully vs partially delivered.
--     COMPLETA → SECTION 1a (CERRADA). PARCIAL → SECTION 1b (ENTREGA_PARCIAL, stays TECO).
SELECT
    CASE WHEN EXISTS (
        SELECT 1
        FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
        JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
        JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
        WHERE pp.partida_id = p.id
    ) THEN 'PARCIAL (queda stock)' ELSE 'COMPLETA' END AS entrega,
    (p.partida_origen_id IS NOT NULL)        AS es_reproceso,
    COUNT(*)                                 AS partidas,
    COUNT(*) FILTER (
        WHERE p.id IN (SELECT partida_id FROM calidad.vw_partidas_pendientes_calidad)
    )                                        AS de_ellas_en_pending_qc
FROM mes.partida p
WHERE p.estado_produccion = 'TECO'
  AND EXISTS (
      SELECT 1 FROM public.despacho d
      WHERE d.flg_elm = false
        AND d.partida_id = COALESCE(p.partida_origen_id, p.id)
  )
GROUP BY 1, 2
ORDER BY 1, 2;

-- 0b. The PARTIAL deliveries (still have dyed output in stock). These are NOT closed
--     — only marked ENTREGA_PARCIAL. The kg/rolls shown stay in stock & dispatchable.
SELECT
    p.id AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::text || '-' || LPAD(p.numero::text,4,'0') AS codigo,
    COUNT(DISTINCT l.id) AS rolls_dyed_en_stock,
    ROUND(SUM(sa.cantidad_disponible)::numeric, 2) AS kg
FROM mes.partida p
JOIN mes.partida_paso pp            ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l              ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE p.estado_produccion = 'TECO'
  AND EXISTS (
      SELECT 1 FROM public.despacho d
      WHERE d.flg_elm = false AND d.partida_id = COALESCE(p.partida_origen_id, p.id)
  )
GROUP BY p.id, p.numero, p.fyh_cre
ORDER BY p.id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — CLOSE  (idempotent)
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_full    INT;
    v_partial INT;
BEGIN
    -- 1a. FULLY delivered → close (TECO → CERRADA). estado_comercial = ENTREGADA only
    --     for originals; rework children must stay PENDIENTE (chk_rework_comercial_locked),
    --     so their commercial settlement remains on the parent.
    UPDATE mes.partida p
    SET estado_produccion = 'CERRADA',
        estado_comercial  = CASE WHEN p.partida_origen_id IS NULL
                                 THEN 'ENTREGADA'::partida_estado_comercial_enum
                                 ELSE p.estado_comercial END,
        fyh_mod           = NOW()
    WHERE p.estado_produccion = 'TECO'
      AND EXISTS (
          SELECT 1 FROM public.despacho d
          WHERE d.flg_elm = false
            AND d.partida_id = COALESCE(p.partida_origen_id, p.id)
      )
      AND NOT EXISTS (   -- no dyed output left in stock = fully delivered
          SELECT 1
          FROM mes.partida_paso pp
          JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
          JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
          JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
          JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
          WHERE pp.partida_id = p.id
      );
    GET DIAGNOSTICS v_full = ROW_COUNT;

    -- 1b. PARTIAL → keep TECO, correct commercial state only (ENTREGA_PARCIAL).
    --     Originals only: rework children are locked to PENDIENTE
    --     (chk_rework_comercial_locked), so partial reworks are left untouched.
    UPDATE mes.partida p
    SET estado_comercial = 'ENTREGA_PARCIAL',
        fyh_mod          = NOW()
    WHERE p.estado_produccion = 'TECO'
      AND p.partida_origen_id IS NULL
      AND p.estado_comercial IS DISTINCT FROM 'ENTREGA_PARCIAL'
      AND EXISTS (
          SELECT 1 FROM public.despacho d
          WHERE d.flg_elm = false
            AND d.partida_id = COALESCE(p.partida_origen_id, p.id)
      )
      AND EXISTS (   -- dyed output still in stock = partially delivered
          SELECT 1
          FROM mes.partida_paso pp
          JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
          JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
          JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
          JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
          WHERE pp.partida_id = p.id
      );
    GET DIAGNOSTICS v_partial = ROW_COUNT;

    RAISE NOTICE '═══════════ CIERRE PARTIDAS DESPACHADAS ═══════════';
    RAISE NOTICE '  cerradas completas (TECO → CERRADA)   : %', v_full;
    RAISE NOTICE '  parciales marcadas (ENTREGA_PARCIAL)  : %', v_partial;
    RAISE NOTICE '═══════════════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. Pending-QC rows remaining (should drop sharply).
SELECT COUNT(*) AS partidas_en_pending_qc
FROM calidad.vw_partidas_pendientes_calidad;

-- 2b. Anything still pending QC that was dispatched in legacy (should be 0 — these
--     would be still-TECO leftovers; if any, inspect why they weren't in scope).
SELECT vpc.partida_id, vpc.partida_codigo, vpc.lotes_pendientes_qc, vpc.operaciones_pendientes
FROM calidad.vw_partidas_pendientes_calidad vpc
JOIN mes.partida p ON p.id = vpc.partida_id
WHERE EXISTS (
    SELECT 1 FROM public.despacho d
    WHERE d.flg_elm = false AND d.partida_id = COALESCE(p.partida_origen_id, p.id)
)
ORDER BY vpc.partida_id
LIMIT 100;

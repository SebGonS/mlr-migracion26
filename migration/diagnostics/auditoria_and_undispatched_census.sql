-- ============================================================================
-- DIAGNOSTIC · Legacy auditoría coverage + already-dyed-undispatched set — READ ONLY
-- ============================================================================
-- Goal: size two coupled bodies of work before building.
--   (A) AUDITORÍA migration: legacy public.auditoria is PARTIDA-level
--       (partida_id, fecha_auditoria, estado); new calidad.inspeccion is per
--       (lote_id, partida_paso_ejecucion_id). Migrating = fan partida verdict → per
--       dyed-roll inspeccion rows. Legacy rule: estado='OK' + fecha → "Para Despachar".
--   (B) ALREADY-DYED, UNDISPATCHED partidas: dyed output exists (flg_tenido=true on a
--       pp_ejec) but the dyed rolls were never dispatched (no SERV_EGR/VENTA_EGR on an
--       outbound entrega). These need auditoría FIRST, then dispatch.
-- go-live cutoff '2026-05-25 15:27:52+00'::timestamptz. Nothing writes.
-- ============================================================================


-- ── §1 · Legacy auditoria table: volume + estado distribution ─────────────────
SELECT estado, COUNT(*) AS rows,
       COUNT(DISTINCT partida_id) AS partidas,
       COUNT(*) FILTER (WHERE fecha_auditoria IS NULL) AS null_fecha
FROM public.auditoria
GROUP BY estado ORDER BY rows DESC;


-- ── §2 · Current calidad.inspeccion coverage (how much QC already migrated?) ──
SELECT
    COUNT(*)                                           AS inspeccion_rows,
    COUNT(DISTINCT lote_id)                            AS distinct_lotes,
    COUNT(DISTINCT partida_paso_ejecucion_id)          AS distinct_ejecs,
    COUNT(*) FILTER (WHERE fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz) AS legacy_era,
    COUNT(*) FILTER (WHERE fyh_cre >  '2026-05-25 15:27:52+00'::timestamptz) AS app_era
FROM calidad.inspeccion;


-- ── §3 · Dyed output rolls: dispatched vs NOT (the undispatched set) ──────────
-- A dyed roll = flg_tenido=true lote on a partida_paso_ejecucion. "Dispatched" =
-- has a SERV_EGR|VENTA_EGR movement on documento_tipo='entrega'.
WITH dyed AS (
    SELECT l.id AS lote_id, pp.partida_id
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida p ON p.id=pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
dispatched AS (
    SELECT DISTINCT im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
    WHERE im.documento_tipo='entrega'
)
SELECT
    (d.lote_id IN (SELECT lote_id FROM dispatched)) AS is_dispatched,
    COUNT(*)                       AS dyed_rolls,
    COUNT(DISTINCT d.partida_id)   AS partidas
FROM dyed d
GROUP BY 1;


-- ── §4 · Undispatched dyed partidas: do they have legacy auditoria + is it OK? ─
-- For partidas with ANY undispatched dyed roll, cross with legacy auditoria estado.
WITH dyed AS (
    SELECT l.id AS lote_id, pp.partida_id
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida p ON p.id=pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
dispatched AS (
    SELECT DISTINCT im.lote_id FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
    WHERE im.documento_tipo='entrega'
),
undispatched_partida AS (
    SELECT DISTINCT partida_id FROM dyed d
    WHERE d.lote_id NOT IN (SELECT lote_id FROM dispatched)
),
-- pool auditoria on original partida (original+reworks), latest OK verdict
aud AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id,
           bool_or(a.estado = 'OK') AS has_ok,
           MAX(a.fecha_auditoria) FILTER (WHERE a.estado='OK') AS ok_fecha,
           COUNT(*) AS aud_rows
    FROM public.auditoria a
    JOIN mes.partida mp ON mp.id = a.partida_id
    GROUP BY COALESCE(mp.partida_origen_id, mp.id)
)
SELECT
    (aud.pool_id IS NOT NULL)        AS has_legacy_auditoria,
    COALESCE(aud.has_ok, false)      AS auditoria_ok,
    COUNT(*)                         AS undispatched_partidas
FROM undispatched_partida up
LEFT JOIN mes.partida mp ON mp.id = up.partida_id
LEFT JOIN aud ON aud.pool_id = COALESCE(mp.partida_origen_id, up.partida_id)
GROUP BY 1, 2
ORDER BY undispatched_partidas DESC;


-- ── §5 · Do the already-dispatched dyed rolls even HAVE inspeccion? (did prior ─
--         dispatch migration require QC, or was it skipped?) Sizes retro-QC need.
WITH dyed_dispatched AS (
    SELECT DISTINCT l.id AS lote_id
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN inventario.item_movimientos im ON im.lote_id=l.id AND im.documento_tipo='entrega'
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
)
SELECT
    COUNT(*)                                                                        AS dyed_dispatched_rolls,
    COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM calidad.inspeccion ci WHERE ci.lote_id = dd.lote_id)) AS with_inspeccion,
    COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM calidad.inspeccion ci WHERE ci.lote_id = dd.lote_id)) AS without_inspeccion
FROM dyed_dispatched dd;

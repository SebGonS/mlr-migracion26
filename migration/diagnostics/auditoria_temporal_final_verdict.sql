-- ============================================================================
-- DIAGNOSTIC · Auditoría temporal ordering → final verdict per partida — READ ONLY
-- ============================================================================
-- Design rests on: the LATEST auditoria row (by fecha_auditoria) is the true
-- disposition. For Observado→OK partidas the OK must be the LATER date (rework was
-- re-audited). This verifies that, and buckets partidas by FINAL verdict.
-- Rule to build: final OK → all dyed approved; final non-OK → all dyed observado;
-- no verdict/absent → no inspeccion. Nothing writes.
-- ============================================================================


-- ── §1 · For partidas with BOTH OK and Observado, is OK the later date? ────────
WITH per_partida AS (
    SELECT partida_id,
           MAX(fecha_auditoria) FILTER (WHERE estado='OK')        AS last_ok,
           MAX(fecha_auditoria) FILTER (WHERE estado='Observado') AS last_obs,
           COUNT(*) FILTER (WHERE estado='OK')        AS ok_rows,
           COUNT(*) FILTER (WHERE estado='Observado') AS obs_rows
    FROM public.auditoria
    GROUP BY partida_id
)
SELECT
    COUNT(*) FILTER (WHERE ok_rows>0 AND obs_rows>0)                       AS both_ok_and_obs,
    COUNT(*) FILTER (WHERE ok_rows>0 AND obs_rows>0 AND last_ok >  last_obs) AS ok_is_later_GOOD,
    COUNT(*) FILTER (WHERE ok_rows>0 AND obs_rows>0 AND last_ok =  last_obs) AS same_date_TIE,
    COUNT(*) FILTER (WHERE ok_rows>0 AND obs_rows>0 AND last_ok <  last_obs) AS obs_is_later_HELD
FROM per_partida;
-- want: both = ok_is_later + ties; obs_is_later_HELD ideally 0 (else those ended non-OK).


-- ── §2 · Final verdict bucket per partida (latest row wins; ties: OK>Observado) ─
-- Also cross with whether the partida has dyed output + whether already dispatched,
-- to size each bucket's real work.
WITH latest AS (
    SELECT DISTINCT ON (partida_id) partida_id, estado AS final_estado, fecha_auditoria AS final_fecha
    FROM public.auditoria
    ORDER BY partida_id,
             fecha_auditoria DESC NULLS LAST,
             CASE estado WHEN 'OK' THEN 0 WHEN 'Observado' THEN 1 ELSE 2 END  -- tie-break OK first
),
dyed AS (
    SELECT pp.partida_id, COUNT(*) AS dyed_rolls,
           COUNT(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM inventario.item_movimientos im
               JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
               WHERE im.lote_id=l.id AND im.documento_tipo='entrega')) AS dispatched_rolls
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida p ON p.id=pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
    GROUP BY pp.partida_id
)
SELECT
    COALESCE(l.final_estado, 'NO_AUDITORIA')  AS final_verdict,
    COUNT(DISTINCT d.partida_id)              AS partidas_with_dyed,
    SUM(d.dyed_rolls)                         AS dyed_rolls,
    SUM(d.dispatched_rolls)                   AS already_dispatched,
    SUM(d.dyed_rolls - d.dispatched_rolls)    AS undispatched
FROM dyed d
LEFT JOIN latest l ON l.partida_id = d.partida_id
GROUP BY 1
ORDER BY dyed_rolls DESC NULLS LAST;


-- ── §3 · Sanity: any roll already DISPATCHED whose partida final verdict is NON-OK?
-- (would mean legacy shipped a held/rejected batch — a conflict to surface.)
WITH latest AS (
    SELECT DISTINCT ON (partida_id) partida_id, estado AS final_estado
    FROM public.auditoria
    ORDER BY partida_id, fecha_auditoria DESC NULLS LAST,
             CASE estado WHEN 'OK' THEN 0 WHEN 'Observado' THEN 1 ELSE 2 END
)
SELECT COALESCE(l.final_estado,'NO_AUDITORIA') AS final_verdict,
       COUNT(*) AS dispatched_dyed_rolls
FROM inventario.lote lo
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=lo.id AND lrd.flg_tenido=true
JOIN mes.partida_paso_ejecucion ppe ON ppe.id=lo.documento_id AND lo.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
JOIN inventario.item_movimientos im ON im.lote_id=lo.id AND im.documento_tipo='entrega'
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
LEFT JOIN latest l ON l.partida_id = pp.partida_id
GROUP BY 1 ORDER BY dispatched_dyed_rolls DESC;

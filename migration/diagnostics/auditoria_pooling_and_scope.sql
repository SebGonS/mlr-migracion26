-- READ ONLY · Resolve rework-pooling for the auditoría fan-out + final build scope.
-- Legacy auditoria.partida_id = ORIGINAL partida. New reworks are CHILD partidas
-- (partida_origen_id set) that may lack a direct auditoria row but were audited under
-- the original. Decide whether to POOL the verdict via COALESCE(partida_origen_id,id).
-- go-live '2026-05-25 15:27:52+00'. Nothing writes.
SELECT * FROm mes.partida_paso_ejecucion WHERE receta_id=7075
SELECT* FROM mes.partida WHERE id=6352
UPDATE receta.tenido SET color_x_cliente_id=1353 WHERE id=7075
-- ── §1 · The 55 NO_AUDITORIA (direct-join) partidas: are they rework children whose
--         POOL (original) actually HAS an OK verdict? If so, pooling rescues them.
WITH dyed AS (
    SELECT DISTINCT pp.partida_id
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida p ON p.id=pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
direct AS (  -- partidas with NO direct auditoria row
    SELECT d.partida_id FROM dyed d
    WHERE NOT EXISTS (SELECT 1 FROM public.auditoria a WHERE a.partida_id = d.partida_id)
),
pool_ok AS (  -- does the POOL (original) have an OK verdict?
    SELECT dr.partida_id,
           mp.partida_origen_id,
           EXISTS (SELECT 1 FROM public.auditoria a
                   WHERE a.partida_id = COALESCE(mp.partida_origen_id, dr.partida_id)
                     AND a.estado='OK') AS pool_has_ok
    FROM direct dr JOIN mes.partida mp ON mp.id = dr.partida_id
)
SELECT
    (partida_origen_id IS NOT NULL) AS is_rework_child,
    pool_has_ok,
    COUNT(*) AS partidas
FROM pool_ok
GROUP BY 1,2 ORDER BY 1,2;


-- ── §2 · Build scope under POOLED final verdict (COALESCE(origen,id)) ──────────
-- Recompute the final-verdict buckets pooling auditoria on the original partida.
WITH latest AS (   -- latest verdict per POOL id
    SELECT DISTINCT ON (pool_id) pool_id, estado AS final_estado, fecha_auditoria AS final_fecha
    FROM (
        SELECT COALESCE(mp.partida_origen_id, a.partida_id) AS pool_id, a.estado, a.fecha_auditoria
        FROM public.auditoria a JOIN mes.partida mp ON mp.id = a.partida_id
    ) z
    ORDER BY pool_id, fecha_auditoria DESC NULLS LAST,
             CASE estado WHEN 'OK' THEN 0 WHEN 'Observado' THEN 1 ELSE 2 END
),
dyed AS (
    SELECT l.id AS lote_id, l.documento_id AS ejec_id, pp.partida_id,
           COALESCE(mp.partida_origen_id, pp.partida_id) AS pool_id,
           EXISTS (SELECT 1 FROM inventario.item_movimientos im
                   JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
                   WHERE im.lote_id=l.id AND im.documento_tipo='entrega') AS dispatched,
           EXISTS (SELECT 1 FROM calidad.inspeccion ci WHERE ci.lote_id=l.id AND ci.partida_paso_ejecucion_id=l.documento_id) AS has_insp
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id AND mp.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
)
SELECT
    COALESCE(l.final_estado,'NO_AUDITORIA')  AS pooled_final_verdict,
    COUNT(*)                                 AS dyed_rolls,
    COUNT(*) FILTER (WHERE d.has_insp)        AS already_has_inspeccion,
    COUNT(*) FILTER (WHERE d.dispatched)      AS dispatched,
    COUNT(*) FILTER (WHERE NOT d.dispatched)  AS undispatched
FROM dyed d
LEFT JOIN latest l ON l.pool_id = d.pool_id
GROUP BY 1 ORDER BY dyed_rolls DESC;

-- ============================================================================
-- DIAGNOSTIC · Source cantidad_kg + precio_kg for the venta migration — READ ONLY
-- ============================================================================
-- venta_detalle needs cantidad_kg (NOT NULL, >0) and precio_kg. Legacy public.despacho
-- has ONLY roll counts (rollos/rib) + precio_unit — no kg. Find the reliable kg source:
--   candidate A: produccion_tenido.kilos  (per partida; covers ALL partidas incl. the
--                68k lote-less ones — the universal source)
--   candidate B: SUM(dispatched dyed lote.cantidad)  (accurate but only ~30k w/ lotes)
-- And determine whether despacho.precio_unit is per-KG or per-ROLL.
-- Pool = COALESCE(partida_origen_id,id). go-live '2026-05-25 15:27:52+00'. No writes.
-- ============================================================================

-- ── §1 · kg source coverage + sanity (kg/roll should look like ~14–25) ────────
WITH desp AS (
    SELECT partida_id AS pool_id, SUM(rollos_total) AS desp_rollos, SUM(rollos_total*precio_unit) AS desp_precio_x_rollos,
           AVG(precio_unit) AS avg_precio_unit
    FROM public.despacho WHERE COALESCE(flg_elm,false)=false GROUP BY partida_id
),
pt AS (   -- legacy produccion_tenido, tenido rows only, pooled on original
    SELECT partida_id AS pool_id, SUM(rollos) AS pt_rollos, SUM(kilos) AS pt_kilos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
lotew AS (  -- dispatched dyed lote weight, pooled
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, SUM(l.cantidad) AS lote_kg, COUNT(*) AS lote_rolls
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id
    JOIN inventario.item_movimientos im ON im.lote_id=l.id AND im.documento_tipo='entrega'
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
    GROUP BY 1
)
SELECT
    COUNT(*)                                                          AS despacho_pools,
    COUNT(*) FILTER (WHERE pt.pt_kilos > 0)                           AS have_pt_kilos,
    COUNT(*) FILTER (WHERE pt.pt_kilos IS NULL)                       AS missing_pt_kilos,
    COUNT(*) FILTER (WHERE lw.lote_kg > 0)                            AS have_lote_kg,
    round(AVG(pt.pt_kilos / NULLIF(pt.pt_rollos,0))::numeric, 2)      AS avg_kg_per_roll_pt,
    round(AVG(lw.lote_kg / NULLIF(lw.lote_rolls,0))::numeric, 2)      AS avg_kg_per_roll_lote
FROM desp d
LEFT JOIN pt      ON pt.pool_id = d.pool_id
LEFT JOIN lotew lw ON lw.pool_id = d.pool_id;


-- ── §2 · Do pt_kilos and dispatched-lote_kg AGREE where both exist? ───────────
-- If they track closely, produccion_tenido.kilos is a trustworthy universal source.
WITH pt AS (
    SELECT partida_id AS pool_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
lotew AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, SUM(l.cantidad) AS lote_kg
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id
    GROUP BY 1
)
SELECT
    COUNT(*)                                                                  AS pools_with_both,
    round(AVG(lote_kg / NULLIF(pt_kilos,0))::numeric, 3)                       AS avg_ratio_lote_over_pt,
    COUNT(*) FILTER (WHERE abs(lote_kg - pt_kilos) / NULLIF(pt_kilos,0) < 0.05) AS within_5pct,
    COUNT(*) FILTER (WHERE abs(lote_kg - pt_kilos) / NULLIF(pt_kilos,0) >= 0.20) AS off_by_20pct_plus
FROM pt JOIN lotew lw USING (pool_id)
WHERE pt_kilos > 0;


-- ── §3 · precio_unit basis: per-KG or per-ROLL? (compare magnitude vs kg/roll) ─
-- If precio_unit ≈ 2–6, it's per-kg (MLR bills USD/kg). If ≈ 40–120, per-roll.
SELECT
    round(MIN(precio_unit)::numeric,2)  AS min_precio,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY precio_unit)::numeric,2) AS median_precio,
    round(AVG(precio_unit)::numeric,2)  AS avg_precio,
    round(MAX(precio_unit)::numeric,2)  AS max_precio,
    COUNT(*) FILTER (WHERE precio_unit BETWEEN 0.5 AND 8)   AS looks_per_kg,
    COUNT(*) FILTER (WHERE precio_unit > 20)                AS looks_per_roll,
    COUNT(*) FILTER (WHERE precio_unit = 0 OR precio_unit IS NULL) AS zero_or_null
FROM public.despacho
WHERE COALESCE(flg_elm,false)=false;


SELECT * FROM despacho

SELECT DISTINCT cliente FROM partida 
JOIN cliente ON cliente.id = partida.cliente_id
WHERE partida.id IN
(SELECT partida_id FROM despacho WHERE precio_unit>10)


SELECT despacho.* FROM partida 
JOIN cliente ON cliente.id = partida.cliente_id
JOIN despacho ON despacho.partida_id = partida.id
WHERE precio_unit10
AND NOT (cliente.procedencia='MLR'or cliente.cliente ILIKE '%MLR%'or cliente.cliente ILIKE '%oswaldo%')



SELECT * FROM vw_partidas_resumen WHERE partida=3620
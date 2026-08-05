-- READ ONLY · Characterize the ~3,976 despacho-shortfall pools (no dyed output) +
-- verify rework modeling + devolucion overlap. Decides: huge backfill vs out-of-scope
-- history vs devolucion-aware reconciliation. go-live '2026-05-25 15:27:52+00'.

-- ── §1 · Age of shortfall pools: fecha_despacho + partida.fyh_cre year distribution
WITH desp AS (
    SELECT partida_id AS pool_id, SUM(rollos_total) AS despacho_total,
           MIN(fecha_despacho) AS first_desp, MAX(fecha_despacho) AS last_desp
    FROM public.despacho WHERE COALESCE(flg_elm,false)=false GROUP BY partida_id
),
dyed_pool AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, COUNT(*) AS dyed
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id
    GROUP BY 1
),
shortfall AS (
    SELECT d.pool_id, d.despacho_total, d.last_desp
    FROM desp d LEFT JOIN dyed_pool y ON y.pool_id=d.pool_id
    WHERE COALESCE(y.dyed,0) = 0            -- pools with NO dyed output at all
)
SELECT
    EXTRACT(YEAR FROM s.last_desp)::int              AS despacho_year,
    COUNT(*)                                         AS pools,
    SUM(s.despacho_total)                            AS rolls,
    COUNT(*) FILTER (WHERE p.id IS NULL)             AS pool_not_in_mes_partida,
    COUNT(*) FILTER (WHERE p.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) AS post_golive_partida
FROM shortfall s
LEFT JOIN mes.partida p ON p.id = s.pool_id
GROUP BY 1 ORDER BY despacho_year;


-- ── §2 · Do these shortfall pools have ANY migrated lotes (raw ingress) at all? ─
-- If raw rolls exist but no dyed output → real production gap. If NO lotes at all →
-- the partida's roll detail was never migrated (out of scope historical).
WITH desp AS (
    SELECT partida_id AS pool_id, SUM(rollos_total) AS despacho_total
    FROM public.despacho WHERE COALESCE(flg_elm,false)=false GROUP BY partida_id
),
dyed_pool AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS pool_id, COUNT(*) AS dyed
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN mes.partida mp ON mp.id=pp.partida_id GROUP BY 1
),
shortfall AS (
    SELECT d.pool_id FROM desp d LEFT JOIN dyed_pool y ON y.pool_id=d.pool_id
    WHERE COALESCE(y.dyed,0)=0
)
SELECT
    EXISTS (SELECT 1 FROM public.produccion_tenido pt WHERE pt.partida_id=s.pool_id)            AS has_legacy_prodtenido,
    (SELECT COUNT(*) > 0 FROM mes.partida_componente pc WHERE pc.partida_id=s.pool_id)          AS has_componente,
    (SELECT COUNT(*) > 0 FROM mes.partida_paso pp WHERE pp.partida_id=s.pool_id)                AS has_paso,
    EXISTS (SELECT 1 FROM inventario.lote l JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id
            WHERE l.documento_tipo='PARTIDA' AND l.documento_id=s.pool_id)                      AS has_raw_lotes_on_partida,
    COUNT(*) AS pools
FROM shortfall s
GROUP BY 1,2,3,4 ORDER BY pools DESC;


-- ── §3 · Rework modeling check: do rework CHILD partidas consume PARENT dyed ───
-- output, or produce fresh? Count rework children and whether their inputs
-- (partida_componente / PROD_CONSUMO) reference the parent's output lotes.
SELECT
    COUNT(*) AS rework_child_partidas,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM mes.partida_componente pc
        JOIN inventario.lote pl ON pl.id = pc.lote_id
        WHERE pc.partida_id = ch.id
          AND pl.documento_tipo='partida_paso_ejecucion'   -- input is a produced (dyed) lote
    )) AS consume_a_produced_lote,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM mes.partida_componente pc
        JOIN mes.partida_paso pp ON pp.partida_id = ch.partida_origen_id
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
        JOIN inventario.lote pl ON pl.documento_id=ppe.id AND pl.documento_tipo='partida_paso_ejecucion'
        WHERE pc.partida_id=ch.id AND pc.lote_id = pl.id   -- input IS a parent-output lote
    )) AS consume_PARENT_output
FROM mes.partida ch
WHERE ch.partida_origen_id IS NOT NULL
  AND ch.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;


-- ── §4 · Devolucion table: volume + overlap with dispatched partidas ──────────
SELECT
    COUNT(*)                                                        AS devolucion_rows,
    COUNT(DISTINCT partida_id)                                      AS partidas,
    SUM(rollos + rib)                                               AS total_rolls_returned,
    COUNT(*) FILTER (WHERE COALESCE(flg_elm,false)=false)           AS active_rows,
    MIN(fecha_devolucion) AS first_dev, MAX(fecha_devolucion) AS last_dev
FROM public.devolucion;

-- ============================================================================
-- DIAGNOSTIC · Track B legacy-gate + gap-partida shape — READ ONLY
-- ============================================================================
-- Two safety questions before the build:
--   (A) Are the "problem" Track-B partidas (no compactado paso / paso-but-no-ejec /
--       supply<demand) all LEGACY (fyh_cre <= go-live)? Any post-go-live partida is
--       LIVE APP DATA and must be excluded from the backfill entirely.
--   (B) For the 35 no-ejec + 16 paso-no-ejec gaps, what do they look like — do they
--       have OTHER pasos/ejecs (perchado/tenido), a legacy produccion_tenido row, so
--       a synthetic compactado ejec is justified?
--
-- go-live cutoff: '2026-05-25 15:27:52+00'::timestamptz. Nothing writes.
-- ============================================================================


-- ── §1 · Legacy-gate every Track-B partida, split by compactado-coverage class ─
WITH tb AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_shipped
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
comp_paso AS (
    SELECT DISTINCT pp.partida_id
    FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
),
comp_ejec AS (
    SELECT DISTINCT pp.partida_id
    FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
)
SELECT
    CASE WHEN ce.partida_id IS NOT NULL THEN 'has_paso+ejec'
         WHEN cp.partida_id IS NOT NULL THEN 'paso_no_ejec'
         ELSE 'no_paso' END                                         AS coverage_class,
    (p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz)            AS is_legacy,
    COUNT(*)                                                        AS partidas,
    SUM(tb.raw_shipped)                                             AS raw_rolls,
    MIN(p.fyh_cre)                                                  AS earliest_fyh,
    MAX(p.fyh_cre)                                                  AS latest_fyh
FROM tb
JOIN mes.partida p ON p.id = tb.partida_id
LEFT JOIN comp_paso cp ON cp.partida_id = tb.partida_id
LEFT JOIN comp_ejec ce ON ce.partida_id = tb.partida_id
GROUP BY 1, 2
ORDER BY coverage_class, is_legacy;
-- watch for is_legacy=false in ANY class → that partida is app data, exclude it.


-- ── §2 · The 35 no-ejec + 16 paso-no-ejec gaps: what other structure exists? ──
-- Do these gap partidas at least have a legacy produccion_tenido row + some other
-- paso, so synthesizing a compactado ejec is grounded (not inventing production)?
WITH tb AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_shipped
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
comp_ejec AS (
    SELECT DISTINCT pp.partida_id
    FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
),
gaps AS (
    SELECT tb.partida_id, tb.raw_shipped
    FROM tb LEFT JOIN comp_ejec ce ON ce.partida_id = tb.partida_id
    WHERE ce.partida_id IS NULL
)
SELECT
    EXISTS (SELECT 1 FROM public.produccion_tenido pt WHERE pt.partida_id = g.partida_id) AS has_legacy_prodtenido,
    EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id = g.partida_id)         AS has_any_paso,
    EXISTS (SELECT 1 FROM mes.partida_paso pp
            JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
            WHERE pp.partida_id = g.partida_id)                                           AS has_any_ejec,
    (p.partida_origen_id IS NOT NULL)                                                     AS is_rework,
    COUNT(*)                                                                              AS partidas,
    SUM(g.raw_shipped)                                                                    AS raw_rolls
FROM gaps g
JOIN mes.partida p ON p.id = g.partida_id
GROUP BY 1,2,3,4
ORDER BY partidas DESC;


-- ── §3 · Per-partida dump of the 35 gap partidas (small enough to eyeball) ────
WITH tb AS (
    SELECT im.documento_id AS partida_id, COUNT(DISTINCT im.lote_id) AS raw_shipped
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
    GROUP BY im.documento_id
),
comp_ejec AS (
    SELECT DISTINCT pp.partida_id
    FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
)
SELECT tb.partida_id, tb.raw_shipped,
       p.partida_origen_id, p.estado_produccion, p.fyh_cre,
       (SELECT string_agg(DISTINCT o.codigo, ',' ORDER BY o.codigo)
        FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id
        WHERE pp.partida_id = tb.partida_id)                        AS pasos_present,
       (SELECT COUNT(*) FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
        WHERE pp.partida_id = tb.partida_id)                        AS total_ejecs,
       (SELECT SUM(pt.rollos) FROM public.produccion_tenido pt WHERE pt.partida_id = tb.partida_id) AS legacy_rollos_direct
FROM tb
LEFT JOIN comp_ejec ce ON ce.partida_id = tb.partida_id
JOIN mes.partida p ON p.id = tb.partida_id
WHERE ce.partida_id IS NULL
ORDER BY tb.raw_shipped DESC, tb.partida_id;


-- ── §4 · The single in_stock=TRUE roll — what is it? (odd one out from §4 prior)
SELECT im.lote_id, im.documento_id AS egr_partida_id,
       (SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=im.lote_id) AS saldo,
       string_agg(DISTINCT imt2.codigo, '+' ORDER BY imt2.codigo) AS all_movs
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
JOIN inventario.item_movimientos im2 ON im2.lote_id=im.lote_id
JOIN inventario.item_movimiento_tipo imt2 ON imt2.id=im2.item_movimiento_tipo_id
WHERE im.documento_tipo='PARTIDA'
  AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=im.lote_id),0) > 0
GROUP BY im.lote_id, im.documento_id;

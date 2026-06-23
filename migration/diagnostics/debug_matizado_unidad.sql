-- ═══════════════════════════════════════════════════════════════════════════════
-- DIAGNOSTIC (read-only): ¿los MATIZADO registrados están en gramos o kg?
--
-- CONTEXT
--   Pre patch-28, generar_receta returned chemical amounts in GRAMS mislabeled as kg,
--   and the frontend round-tripped them into the consumption payload AS kg (no ÷1000).
--   registrar_matizado → registrar_consumo_paso shares that payload path, so MATIZADO
--   consumos registered in that era are likely 1000× too large too. (Lavado is server-
--   side and unaffected.) Matizado has NO recipe baseline, so unlike tenido we cannot
--   recompute the "expected kg" — we judge by RECORD TIME (fyh_cre) and by MAGNITUDE
--   plausibility (a color top-up of "250 kg" of a dye you stock 8 kg of is obviously g).
--
--   fecha_hora = business event time (back-datable). fyh_cre = real insert time, never
--   backdated → the reliable era signal. Set fix_deploy below to split the eras.
--
-- HOW TO READ
--   • SECTION 1 (per item): look at max/avg cantidad vs stock_actual & precio. Values
--     orders of magnitude above what you'd ever dose by hand ⇒ grams.
--   • SECTION 2 (timeline): when matizado was actually recorded (fyh_cre) vs fix_deploy.
--   • SECTION 3 (per movement): the raw rows, with the era guess, to eyeball/spot-check.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Set the moment the patched generar_receta went live. Rows recorded before this
--    are the grams-era candidates. Leave as a far-future ts to tag everything "grams?".
-- ───────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — Per-insumo magnitude profile (the main "grams or kg?" tell)
-- ═══════════════════════════════════════════════════════════════════════════════
WITH params AS (SELECT '2026-06-20 00:00'::timestamptz AS fix_deploy),
mov AS (
    SELECT im.id, im.item_id, im.cantidad, im.fyh_cre, im.fecha_hora, im.monto
    FROM inventario.item_movimientos im
    WHERE im.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo   WHERE codigo='PROD_CONSUMO')
      AND im.motivo_id               = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo='MATIZADO')
)
SELECT
    m.item_id,
    it.codigo                          AS insumo_codigo,
    it.nombre                          AS insumo,
    iid.medida,
    it.flg_fungible,
    COUNT(*)                           AS n_movimientos,
    ROUND(MIN(m.cantidad),4)           AS min_cantidad,
    ROUND(AVG(m.cantidad),4)           AS avg_cantidad,
    ROUND(MAX(m.cantidad),4)           AS max_cantidad,
    ROUND(SUM(m.cantidad),4)           AS total_cantidad,
    ROUND(COALESCE(sg.cantidad_total,0),4) AS stock_actual,
    iv.precio_promedio,
    -- crude plausibility: how many times the current stock the single biggest matizado is.
    -- ≫1 strongly suggests grams (you cannot hand-dose more than you stock).
    ROUND(MAX(m.cantidad) / NULLIF(sg.cantidad_total,0), 1) AS max_sobre_stock
FROM mov m
JOIN item it ON it.id = m.item_id
LEFT JOIN item_insumo_detalle iid       ON iid.item_id = m.item_id
LEFT JOIN inventario.vw_stock_items sg  ON sg.item_id  = m.item_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id  = m.item_id
GROUP BY m.item_id, it.codigo, it.nombre, iid.medida, it.flg_fungible,
         sg.cantidad_total, iv.precio_promedio
ORDER BY max_sobre_stock DESC NULLS LAST, total_cantidad DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — Timeline: when matizado was recorded, split by era (fyh_cre)
-- ═══════════════════════════════════════════════════════════════════════════════
WITH params AS (SELECT '2026-06-20 00:00'::timestamptz AS fix_deploy)
SELECT
    im.fyh_cre::date                       AS dia_registro,
    CASE WHEN im.fyh_cre < (SELECT fix_deploy FROM params)
         THEN 'grams?' ELSE 'kg' END        AS era,
    COUNT(*)                                AS movimientos,
    COUNT(DISTINCT im.documento_id)         AS ejecuciones,
    ROUND(SUM(im.cantidad),4)               AS cantidad_total,
    ROUND(SUM(im.monto),2)                  AS valor_total
FROM inventario.item_movimientos im
WHERE im.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo   WHERE codigo='PROD_CONSUMO')
  AND im.motivo_id               = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo='MATIZADO')
GROUP BY im.fyh_cre::date, era
ORDER BY dia_registro;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — Per-movement detail (spot-check the actual rows)
-- ═══════════════════════════════════════════════════════════════════════════════
WITH params AS (SELECT '2026-06-20 00:00'::timestamptz AS fix_deploy)
SELECT
    im.id                                   AS mov_id,
    im.documento_id                         AS ejecucion_id,
    pp.partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    it.codigo                               AS insumo_codigo,
    it.nombre                               AS insumo,
    ROUND(im.cantidad,4)                    AS cantidad,
    im.precio_unitario,
    ROUND(im.monto,2)                       AS monto,
    im.fecha_hora,
    im.fyh_cre,
    CASE WHEN im.fyh_cre < (SELECT fix_deploy FROM params)
         THEN 'grams?' ELSE 'kg' END         AS era
FROM inventario.item_movimientos im
JOIN item it                       ON it.id = im.item_id
LEFT JOIN mes.partida_paso_ejecucion pe ON pe.id = im.documento_id
                                       AND im.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_paso pp      ON pp.id = pe.partida_paso_id
LEFT JOIN mes.partida p            ON p.id  = pp.partida_id
WHERE im.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo   WHERE codigo='PROD_CONSUMO')
  AND im.motivo_id               = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo='MATIZADO')
ORDER BY im.fyh_cre, im.id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 4 — Cross-check vs the same run's recipe consumption
-- For each matizado, the ratio to that item's RECIPE consumption (motivo NULL) in the
-- SAME ejecucion. If both are same-era they cancel (ratio sane); a matizado that is
-- ~1000× its recipe sibling (or vice-versa) means the two were recorded in different
-- eras — a strong, recipe-free tell for matizado rows whose era is otherwise unclear.
-- ═══════════════════════════════════════════════════════════════════════════════
WITH base AS (
    SELECT im.documento_id AS ejecucion_id, im.item_id, im.cantidad, im.motivo_id, im.fyh_cre
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND im.item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO')
      AND EXISTS (SELECT 1 FROM item_insumo_detalle iid WHERE iid.item_id = im.item_id)
),
mat AS (
    SELECT ejecucion_id, item_id, SUM(cantidad) AS cant_matizado, MIN(fyh_cre) AS mat_fyh_cre
    FROM base WHERE motivo_id = (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo='MATIZADO')
    GROUP BY ejecucion_id, item_id
),
rec AS (
    SELECT ejecucion_id, item_id, SUM(cantidad) AS cant_receta
    FROM base WHERE motivo_id IS DISTINCT FROM (SELECT id FROM inventario.item_movimiento_motivo WHERE codigo='MATIZADO')
    GROUP BY ejecucion_id, item_id
)
SELECT
    mat.ejecucion_id,
    it.codigo                          AS insumo_codigo,
    it.nombre                          AS insumo,
    ROUND(mat.cant_matizado,4)         AS cant_matizado,
    ROUND(rec.cant_receta,4)           AS cant_receta_mismo_item,
    ROUND(mat.cant_matizado / NULLIF(rec.cant_receta,0), 1) AS ratio_matizado_receta,
    mat.mat_fyh_cre
FROM mat
LEFT JOIN rec ON rec.ejecucion_id = mat.ejecucion_id AND rec.item_id = mat.item_id
JOIN item it ON it.id = mat.item_id
ORDER BY ratio_matizado_receta DESC NULLS LAST;

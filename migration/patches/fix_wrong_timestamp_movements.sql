

-- Temporarily lift the cutoff guard — migration correction only
ALTER TABLE inventario.item_movimientos
    DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;
BEGIN;

WITH affected_docs AS (
    SELECT DISTINCT im.doc_movimiento_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
    WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
),
-- Egress lote fingerprint per doc group
im_fp_raw AS (
    SELECT
        im.doc_movimiento_id,
        array_agg(DISTINCT im.lote_id ORDER BY im.lote_id) AS lote_set
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
    WHERE im.doc_movimiento_id IN (SELECT doc_movimiento_id FROM affected_docs)
    GROUP BY im.doc_movimiento_id
),
im_fp AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY lote_set ORDER BY doc_movimiento_id) AS rn
    FROM im_fp_raw
),
-- Same fingerprint on the legacy side — restrict to bulk-migrated salidas only
-- so rn counts stay aligned
si_fp_raw AS (
    SELECT
        si.id AS si_id,
        array_agg(DISTINCT sdxs.inventario_id ORDER BY sdxs.inventario_id) AS lote_set
    FROM public.salida_inventario si
    JOIN public.salida_inventario_detalle sid ON sid.salida_inventario_id = si.id
    JOIN public.salida_inventario_detalle_x_stock sdxs ON sdxs.salida_inventario_detalle_id = sid.id
    WHERE si.estado = 'aprobado'
      AND si.fyh_solicitud_tz = '2025-09-11 22:53:28.212517+00'  -- only bulk-migrated
    GROUP BY si.id
),
si_fp AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY lote_set ORDER BY si_id) AS rn
    FROM si_fp_raw
),
-- 1:1 mapping: same fingerprint + same chronological position
doc_to_si AS (
    SELECT imf.doc_movimiento_id, sif.si_id
    FROM im_fp imf
    JOIN si_fp sif ON sif.lote_set = imf.lote_set AND sif.rn = imf.rn
)

-- Pre-flight: every doc should map to exactly one si — if any row returns here, stop
--  SELECT doc_movimiento_id, COUNT(*) FROM doc_to_si GROUP BY 1 HAVING COUNT(*) > 1;

UPDATE inventario.item_movimientos im
SET    fecha_hora = sdxs.fecha
FROM   doc_to_si d,
       public.salida_inventario_detalle sid,
       public.salida_inventario_detalle_x_stock sdxs,
       inventario.item_movimiento_tipo imt
WHERE  im.doc_movimiento_id              = d.doc_movimiento_id
  AND  sid.salida_inventario_id          = d.si_id
  AND  sdxs.salida_inventario_detalle_id = sid.id
  AND  sdxs.inventario_id               = im.lote_id
  AND  sdxs.cantidad::numeric(12,4)     = im.cantidad
  AND  imt.id                           = im.item_movimiento_tipo_id
  AND  imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
  AND  im.fecha_hora = '2025-09-11 22:53:28.212517+00';

-- How many rows remain at the migration timestamp?
SELECT COUNT(*), imt.codigo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
GROUP BY imt.codigo;

-- Spot-check item 27 timeline looks clean
SELECT fecha_hora, imt.codigo, im.cantidad * imt.factor AS neta,
       SUM(im.cantidad * imt.factor) OVER (ORDER BY fecha_hora, im.id) AS saldo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 27
ORDER BY fecha_hora, im.id;

-- ROLLBACK;
COMMIT;
-- Restore the guard immediately after
ALTER TABLE inventario.item_movimientos
    ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;




SELECT
    im.fecha_hora,
    imt.codigo,
    im.cantidad * imt.factor AS neta,
    SUM(im.cantidad * imt.factor) OVER (ORDER BY im.fecha_hora, im.id) AS saldo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 24
ORDER BY im.fecha_hora, im.id;

SELECT get_insumo_movimientos_rango(24, '2024-01-01', '2027-01-01');



SELECT im.id, im.doc_movimiento_id, im.lote_id, im.cantidad * imt.factor AS neta
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 24
  AND im.fecha_hora = '2025-11-19 01:55:32.250751+00'
ORDER BY im.id;



-- ══════════════════════════════════════════════════════════════════
-- PRE-FLIGHT — confirmed duplicates only (new count > legacy count)
-- ══════════════════════════════════════════════════════════════════
WITH legacy_counts AS (
    -- How many sdxs rows exist per (lote, cantidad, fecha) in the source
    SELECT
        sdxs.inventario_id          AS lote_id,
        sdxs.cantidad::numeric(12,4) AS cantidad,
        sdxs.fecha,
        COUNT(*)                    AS sdxs_count
    FROM public.salida_inventario_detalle_x_stock sdxs
    JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
    JOIN public.salida_inventario si          ON si.id  = sid.salida_inventario_id
    WHERE si.estado = 'aprobado'
    GROUP BY sdxs.inventario_id, sdxs.cantidad::numeric(12,4), sdxs.fecha
),
im_counts AS (
    SELECT
        im.lote_id, im.cantidad, im.fecha_hora,
        im.item_id, im.item_movimiento_tipo_id, im.origen_ubicacion_id,
        COUNT(*)               AS im_count,
        MIN(doc_movimiento_id) AS keep_doc
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
    GROUP BY im.lote_id, im.cantidad, im.fecha_hora,
             im.item_id, im.item_movimiento_tipo_id, im.origen_ubicacion_id
    HAVING COUNT(*) > 1
),
confirmed AS (
    SELECT
        ic.*,
        lc.sdxs_count,
        ic.im_count - lc.sdxs_count AS excess
    FROM im_counts ic
    JOIN legacy_counts lc            -- must have a legacy source (migrated row)
        ON  lc.lote_id  = ic.lote_id
        AND lc.cantidad = ic.cantidad
        AND lc.fecha    = ic.fecha_hora
    WHERE ic.im_count > lc.sdxs_count  -- only confirmed excess
)
SELECT
    i.codigo AS item, imt.codigo AS tipo,
    c.lote_id, c.cantidad, c.fecha_hora,
    c.sdxs_count AS legacy_rows,
    c.im_count   AS new_rows,
    c.excess     AS rows_to_delete
FROM confirmed c
JOIN item i ON i.id = c.item_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = c.item_movimiento_tipo_id
ORDER BY c.item_id, c.fecha_hora;


-- ══════════════════════════════════════════════════════════════════
-- FIX — same logic, delete only confirmed excess rows
-- ══════════════════════════════════════════════════════════════════
BEGIN;

WITH legacy_counts AS (
    SELECT
        sdxs.inventario_id          AS lote_id,
        sdxs.cantidad::numeric(12,4) AS cantidad,
        sdxs.fecha,
        COUNT(*) AS sdxs_count
    FROM public.salida_inventario_detalle_x_stock sdxs
    JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
    JOIN public.salida_inventario si          ON si.id  = sid.salida_inventario_id
    WHERE si.estado = 'aprobado'
    GROUP BY sdxs.inventario_id, sdxs.cantidad::numeric(12,4), sdxs.fecha
),
im_counts AS (
    SELECT
        im.lote_id, im.cantidad, im.fecha_hora,
        im.item_id, im.item_movimiento_tipo_id, im.origen_ubicacion_id,
        COUNT(*) AS im_count, MIN(doc_movimiento_id) AS keep_doc
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
    GROUP BY im.lote_id, im.cantidad, im.fecha_hora,
             im.item_id, im.item_movimiento_tipo_id, im.origen_ubicacion_id
    HAVING COUNT(*) > 1
),
confirmed AS (
    SELECT ic.*, lc.sdxs_count
    FROM im_counts ic
    JOIN legacy_counts lc
        ON  lc.lote_id  = ic.lote_id
        AND lc.cantidad = ic.cantidad
        AND lc.fecha    = ic.fecha_hora
    WHERE ic.im_count > lc.sdxs_count
),
deleted AS (
    DELETE FROM inventario.item_movimientos im
    USING confirmed dg
    WHERE  im.item_id                 = dg.item_id
      AND  im.lote_id                 = dg.lote_id
      AND  im.cantidad                = dg.cantidad
      AND  im.fecha_hora              = dg.fecha_hora
      AND  im.item_movimiento_tipo_id = dg.item_movimiento_tipo_id
      AND  im.origen_ubicacion_id IS NOT DISTINCT FROM dg.origen_ubicacion_id
      AND  im.doc_movimiento_id      <> dg.keep_doc
    RETURNING im.lote_id, im.item_id, im.cantidad, im.origen_ubicacion_id
),
lote_credit AS (
    UPDATE inventario.lote_saldo ls
    SET    cantidad_actual = ls.cantidad_actual + d.credit
    FROM  (SELECT lote_id, origen_ubicacion_id, SUM(cantidad) AS credit
           FROM deleted GROUP BY lote_id, origen_ubicacion_id) d
    WHERE  ls.lote_id      = d.lote_id
      AND  ls.ubicacion_id IS NOT DISTINCT FROM d.origen_ubicacion_id
    RETURNING ls.lote_id, ls.cantidad_actual AS post_fix
),
item_credit AS (
    UPDATE inventario.item_saldo is2
    SET    cantidad_actual = is2.cantidad_actual + d.credit
    FROM  (SELECT item_id, origen_ubicacion_id, SUM(cantidad) AS credit
           FROM deleted GROUP BY item_id, origen_ubicacion_id) d
    WHERE  is2.item_id     = d.item_id
      AND  is2.ubicacion_id IS NOT DISTINCT FROM d.origen_ubicacion_id
    RETURNING is2.item_id, is2.cantidad_actual AS post_fix
)
SELECT 'lote' AS nivel, lote_id AS id, post_fix FROM lote_credit
UNION ALL
SELECT 'item',           item_id,       post_fix FROM item_credit;

-- ROLLBACK;
COMMIT;


-- Orphaned sdxs rows: legacy source exists, new movement was deleted
SELECT
    sdxs.inventario_id  AS lote_id,
    l.item_id,
    sdxs.cantidad::numeric(12,4) AS cantidad,
    sdxs.fecha          AS fecha_hora,
    sid.salida_inventario_id,
    si.motivo
FROM public.salida_inventario_detalle_x_stock sdxs
JOIN public.salida_inventario_detalle sid ON sid.id  = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si           ON si.id  = sid.salida_inventario_id
JOIN inventario.lote l                     ON l.id   = sdxs.inventario_id
WHERE si.estado = 'aprobado'
  AND NOT EXISTS (
      SELECT 1 FROM inventario.item_movimientos im
      WHERE im.lote_id    = sdxs.inventario_id
        AND im.cantidad   = sdxs.cantidad::numeric(12,4)
        AND im.fecha_hora = sdxs.fecha
        AND im.item_id    = l.item_id
  )
ORDER BY sdxs.fecha, l.item_id;

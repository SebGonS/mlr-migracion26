-- ═══════════════════════════════════════════════════════════════════════════════
-- COMPRAS INTEGRITY DIAGNOSTIC  (live data · last 3 weeks)
-- ───────────────────────────────────────────────────────────────────────────────
-- §1   Compras sin líneas de detalle
-- §2   Compras sin entrega vinculada (PO sin guía)
-- §3   Compras con entrega pero sin movimientos COMPRA_ING (stock no postado)
-- §4   Entregas COMPRA_INGRESO huérfanas (sin compra vinculada)
-- §5   entrega_detalle sin compra_detalle_id (no reconciliadas)
-- §6   Drift en cantidad_recibida vs ledger
-- §7   Movimientos COMPRA_ING sin lote
-- §8   lrd.entrega_id nulo o de tipo incorrecto
-- §9   Movimientos COMPRA_ING desde entrega sin PO vinculada
-- §10  Scorecard
-- ───────────────────────────────────────────────────────────────────────────────
-- Cutoff: ajustar el INTERVAL en la línea siguiente para cambiar la ventana.
-- ═══════════════════════════════════════════════════════════════════════════════

SET search_path TO doc, inventario, public;

-- Cutoff compartido — cambiar aquí para ajustar la ventana.
CREATE TEMP TABLE IF NOT EXISTS _cfg AS
SELECT (NOW() - INTERVAL '21 days') AS desde;


-- ── §1  Compras de insumos sin ninguna línea de detalle ──────────────────────
-- Compras creadas en el período que tienen al menos una línea pero ninguna es
-- de tipo INSUMO — o directamente no tienen ninguna línea.
-- Expect: 0 rows.
SELECT
    c.id                AS compra_id,
    t.nombre            AS proveedor,
    c.fecha,
    c.fyh_cre::date     AS creado
FROM doc.compra c
JOIN tercero t ON t.id = c.tercero_id
WHERE c.fyh_elm IS NULL
  AND c.fyh_cre >= (SELECT desde FROM _cfg)
  AND NOT EXISTS (
      SELECT 1
      FROM doc.compra_detalle cd
      JOIN item i       ON i.id  = cd.item_id
      JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
      WHERE cd.compra_id = c.id
  )
ORDER BY c.fecha DESC;


-- ── §2  Compras sin entrega vinculada (PO sin guía) ──────────────────────────
SELECT
    c.id                                            AS compra_id,
    t.nombre                                        AS proveedor,
    c.fecha,
    COUNT(cd.id)                                    AS n_lineas,
    ROUND(SUM(cd.cantidad * cd.precio_unitario), 2) AS valor_estimado
FROM doc.compra c
JOIN tercero t             ON t.id = c.tercero_id
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i                ON i.id  = cd.item_id
JOIN item_tipo it          ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
WHERE c.fyh_elm IS NULL
  AND c.fyh_cre >= (SELECT desde FROM _cfg)
  AND NOT EXISTS (SELECT 1 FROM doc.compra_entrega ce WHERE ce.compra_id = c.id)
GROUP BY c.id, t.nombre, c.fecha
ORDER BY c.fecha DESC;


-- ── §3  Compras con entrega pero sin movimientos COMPRA_ING ──────────────────
-- Expect: 0 rows.
SELECT
    c.id                                                            AS compra_id,
    t.nombre                                                        AS proveedor,
    c.fecha,
    e.id                                                            AS entrega_id,
    COALESCE(e.serie || '-' || e.correlativo, '(sin referencia)')   AS guia,
    e.fecha_emision                                                  AS guia_fecha,
    COUNT(DISTINCT ed.id)                                           AS lineas_entrega
FROM doc.compra c
JOIN tercero t              ON t.id = c.tercero_id
JOIN doc.compra_entrega ce  ON ce.compra_id = c.id
JOIN doc.entrega e          ON e.id = ce.entrega_id
LEFT JOIN doc.entrega_detalle ed ON ed.entrega_id = e.id
WHERE c.fyh_elm IS NULL
  AND c.fyh_cre >= (SELECT desde FROM _cfg)
  -- Only compras that have insumo lines
  AND EXISTS (
      SELECT 1 FROM doc.compra_detalle cd
      JOIN item i       ON i.id  = cd.item_id
      JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
      WHERE cd.compra_id = c.id
  )
  AND NOT EXISTS (
      SELECT 1
      FROM inventario.item_movimientos im
      JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
      WHERE imt.codigo        = 'COMPRA_ING'
        AND im.documento_tipo = 'entrega'
        AND im.documento_id   = e.id
  )
GROUP BY c.id, t.nombre, c.fecha, e.id, e.serie, e.correlativo, e.fecha_emision
ORDER BY c.fecha DESC, c.id;


-- ── §4  Entregas COMPRA_INGRESO huérfanas (sin compra vinculada) ─────────────
-- Normal para flujo orderless antes de reconciliar.
SELECT
    e.id                                                            AS entrega_id,
    COALESCE(e.serie || '-' || e.correlativo, '(sin referencia)')   AS guia,
    e.fecha_emision,
    t.nombre                                                        AS proveedor,
    COUNT(ed.id)                                                    AS n_lineas,
    ROUND(SUM(ed.cantidad), 2)                                      AS kg_total
FROM doc.entrega e
JOIN doc.entrega_tipo et         ON et.id = e.entrega_tipo_id AND et.codigo = 'COMPRA_INGRESO'
LEFT JOIN tercero t              ON t.id  = e.tercero_id
LEFT JOIN doc.entrega_detalle ed ON ed.entrega_id = e.id
LEFT JOIN item i                 ON i.id  = ed.item_id
LEFT JOIN item_tipo it           ON it.id = i.item_tipo_id
WHERE e.fyh_elm IS NULL
  AND e.fyh_cre >= (SELECT desde FROM _cfg)
  AND NOT EXISTS (SELECT 1 FROM doc.compra_entrega ce WHERE ce.entrega_id = e.id)
  -- Only entregas that carry insumo lines
  AND EXISTS (
      SELECT 1 FROM doc.entrega_detalle ed2
      JOIN item i2       ON i2.id  = ed2.item_id
      JOIN item_tipo it2 ON it2.id = i2.item_tipo_id AND it2.codigo = 'INSUMO'
      WHERE ed2.entrega_id = e.id
  )
GROUP BY e.id, e.serie, e.correlativo, e.fecha_emision, t.nombre
ORDER BY e.fecha_emision DESC;


-- ── §5  entrega_detalle sin compra_detalle_id (sin reconciliar) ──────────────
SELECT
    ce.compra_id,
    e.id                                                            AS entrega_id,
    COALESCE(e.serie || '-' || e.correlativo, '(sin referencia)')   AS guia,
    ed.id                                                           AS entrega_detalle_id,
    ed.linea,
    i.codigo                                                        AS item_codigo,
    i.nombre                                                        AS item_nombre,
    ed.cantidad
FROM doc.compra_entrega ce
JOIN doc.entrega e              ON e.id  = ce.entrega_id
JOIN doc.entrega_detalle ed     ON ed.entrega_id = e.id
JOIN item i                     ON i.id  = ed.item_id
JOIN item_tipo it               ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
JOIN doc.compra c               ON c.id  = ce.compra_id
WHERE ed.compra_detalle_id IS NULL
  AND e.fyh_cre >= (SELECT desde FROM _cfg)
  AND c.fyh_elm IS NULL
ORDER BY ce.compra_id, e.id, ed.linea;


-- ── §6  Drift en cantidad_recibida ───────────────────────────────────────────
-- Fix: SELECT doc.fn_refresh_compra_detalle_qtys(<compra_id>);
-- Expect: 0 rows.
WITH ledger AS (
    SELECT
        cd.id                         AS compra_detalle_id,
        COALESCE(SUM(im.cantidad), 0) AS qty_ledger
    FROM doc.compra_detalle cd
    JOIN doc.compra c               ON c.id  = cd.compra_id
    JOIN item i_cd                  ON i_cd.id  = cd.item_id
    JOIN item_tipo it_cd            ON it_cd.id = i_cd.item_tipo_id AND it_cd.codigo = 'INSUMO'
    JOIN doc.compra_entrega cex     ON cex.compra_id = cd.compra_id
    JOIN doc.entrega_detalle ed     ON ed.entrega_id = cex.entrega_id
                                   AND (ed.compra_detalle_id = cd.id
                                        OR (ed.compra_detalle_id IS NULL AND ed.item_id = cd.item_id))
    JOIN inventario.item_movimientos im
                                    ON im.documento_tipo = 'entrega'
                                   AND im.documento_id   = ed.entrega_id
                                   AND im.item_id        = cd.item_id
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                           AND imt.codigo = 'COMPRA_ING'
    WHERE c.fyh_elm IS NULL
      AND c.fyh_cre >= (SELECT desde FROM _cfg)
    GROUP BY cd.id
)
SELECT
    cd.compra_id,
    cd.id                        AS compra_detalle_id,
    i.codigo                     AS item_codigo,
    cd.cantidad                  AS qty_ordenada,
    cd.cantidad_recibida         AS qty_stored,
    COALESCE(lg.qty_ledger, 0)   AS qty_ledger,
    ROUND(cd.cantidad_recibida - COALESCE(lg.qty_ledger, 0), 4) AS delta
FROM doc.compra_detalle cd
JOIN doc.compra c   ON c.id  = cd.compra_id
JOIN item i         ON i.id  = cd.item_id
JOIN item_tipo it   ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
LEFT JOIN ledger lg ON lg.compra_detalle_id = cd.id
WHERE c.fyh_elm IS NULL
  AND c.fyh_cre >= (SELECT desde FROM _cfg)
  AND cd.cantidad_recibida <> COALESCE(lg.qty_ledger, 0)
ORDER BY cd.compra_id, cd.id;


-- ── §7  Movimientos COMPRA_ING sin lote ──────────────────────────────────────
-- Expect: 0 rows.
SELECT
    im.id                AS movimiento_id,
    im.documento_tipo,
    im.documento_id,
    im.item_id,
    i.codigo             AS item_codigo,
    im.cantidad,
    im.fecha_hora::date  AS fecha
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                       AND imt.codigo = 'COMPRA_ING'
JOIN item i       ON i.id  = im.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
WHERE im.lote_id IS NULL
  AND im.fecha_hora >= (SELECT desde FROM _cfg)
ORDER BY im.fecha_hora DESC;


-- ── §8  (omitido — lrd.entrega_id sólo aplica a ROLLO; no relevante para insumos) ──

-- ── §9  Movimientos COMPRA_ING de entrega sin PO vinculada ───────────────────
-- Stock correcto en ledger pero sin cobertura de PO.
SELECT
    im.id                AS movimiento_id,
    im.documento_id      AS entrega_id,
    COALESCE(e.serie || '-' || e.correlativo, '(sin referencia)') AS guia,
    im.item_id,
    i.codigo             AS item_codigo,
    im.cantidad,
    im.fecha_hora::date  AS fecha
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                       AND imt.codigo = 'COMPRA_ING'
JOIN item i       ON i.id  = im.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
LEFT JOIN doc.entrega e  ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
WHERE im.documento_tipo = 'entrega'
  AND im.fecha_hora >= (SELECT desde FROM _cfg)
  AND NOT EXISTS (
      SELECT 1 FROM doc.compra_entrega ce WHERE ce.entrega_id = im.documento_id
  )
ORDER BY im.fecha_hora DESC;


-- ── §10  Scorecard ───────────────────────────────────────────────────────────
-- s2 y s4 pueden ser >0 legítimamente (POs recientes sin guía / orderless).
-- El resto debe ser 0.
SELECT

    -- §1: compras with no insumo detail lines
    (SELECT COUNT(*) FROM doc.compra c
     WHERE c.fyh_elm IS NULL
       AND c.fyh_cre >= (SELECT desde FROM _cfg)
       AND NOT EXISTS (
           SELECT 1 FROM doc.compra_detalle cd
           JOIN item i       ON i.id  = cd.item_id
           JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
           WHERE cd.compra_id = c.id
       )
    )                                                               AS s1_compras_sin_lineas_insumo,

    -- §2: insumo compras with no linked entrega
    (SELECT COUNT(*) FROM doc.compra c
     WHERE c.fyh_elm IS NULL
       AND c.fyh_cre >= (SELECT desde FROM _cfg)
       AND NOT EXISTS (SELECT 1 FROM doc.compra_entrega ce WHERE ce.compra_id = c.id)
       AND EXISTS (
           SELECT 1 FROM doc.compra_detalle cd
           JOIN item i       ON i.id  = cd.item_id
           JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
           WHERE cd.compra_id = c.id
       )
    )                                                               AS s2_compras_sin_entrega,

    -- §3: insumo compras with entrega but no stock posted
    (SELECT COUNT(DISTINCT c.id)
     FROM doc.compra c
     JOIN doc.compra_entrega ce ON ce.compra_id = c.id
     JOIN doc.entrega e         ON e.id = ce.entrega_id
     WHERE c.fyh_elm IS NULL
       AND c.fyh_cre >= (SELECT desde FROM _cfg)
       AND EXISTS (
           SELECT 1 FROM doc.compra_detalle cd
           JOIN item i       ON i.id  = cd.item_id
           JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
           WHERE cd.compra_id = c.id
       )
       AND NOT EXISTS (
           SELECT 1
           FROM inventario.item_movimientos im
           JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
           WHERE imt.codigo = 'COMPRA_ING'
             AND im.documento_tipo = 'entrega'
             AND im.documento_id   = e.id
       )
    )                                                               AS s3_compras_sin_stock,

    -- §4: COMPRA_INGRESO entregas with insumo lines but no compra link
    (SELECT COUNT(*)
     FROM doc.entrega e
     JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id AND et.codigo = 'COMPRA_INGRESO'
     WHERE e.fyh_elm IS NULL
       AND e.fyh_cre >= (SELECT desde FROM _cfg)
       AND NOT EXISTS (SELECT 1 FROM doc.compra_entrega ce WHERE ce.entrega_id = e.id)
       AND EXISTS (
           SELECT 1 FROM doc.entrega_detalle ed
           JOIN item i       ON i.id  = ed.item_id
           JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
           WHERE ed.entrega_id = e.id
       )
    )                                                               AS s4_entregas_huerfanas,

    -- §5: entrega_detalle insumo lines not pinned to a compra_detalle
    (SELECT COUNT(*)
     FROM doc.compra_entrega ce
     JOIN doc.entrega e          ON e.id  = ce.entrega_id
     JOIN doc.compra c           ON c.id  = ce.compra_id
     JOIN doc.entrega_detalle ed ON ed.entrega_id = e.id
     JOIN item i                 ON i.id  = ed.item_id
     JOIN item_tipo it           ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
     WHERE ed.compra_detalle_id IS NULL
       AND e.fyh_cre >= (SELECT desde FROM _cfg)
       AND c.fyh_elm IS NULL
    )                                                               AS s5_lineas_sin_reconciliar,

    -- §6: cantidad_recibida drift on insumo lines
    (SELECT COUNT(*)
     FROM (
         SELECT cd.id
         FROM doc.compra_detalle cd
         JOIN doc.compra c   ON c.id  = cd.compra_id
         JOIN item i         ON i.id  = cd.item_id
         JOIN item_tipo it   ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
         LEFT JOIN (
             SELECT cd2.id AS compra_detalle_id, COALESCE(SUM(im.cantidad), 0) AS qty_ledger
             FROM doc.compra_detalle cd2
             JOIN doc.compra c2          ON c2.id  = cd2.compra_id
             JOIN item i2                ON i2.id  = cd2.item_id
             JOIN item_tipo it2          ON it2.id = i2.item_tipo_id AND it2.codigo = 'INSUMO'
             JOIN doc.compra_entrega cex ON cex.compra_id = cd2.compra_id
             JOIN doc.entrega_detalle ed ON ed.entrega_id = cex.entrega_id
                                        AND (ed.compra_detalle_id = cd2.id
                                             OR (ed.compra_detalle_id IS NULL AND ed.item_id = cd2.item_id))
             JOIN inventario.item_movimientos im
                                         ON im.documento_tipo = 'entrega'
                                        AND im.documento_id   = ed.entrega_id
                                        AND im.item_id        = cd2.item_id
             JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                                     AND imt.codigo = 'COMPRA_ING'
             WHERE c2.fyh_elm IS NULL
               AND c2.fyh_cre >= (SELECT desde FROM _cfg)
             GROUP BY cd2.id
         ) lg ON lg.compra_detalle_id = cd.id
         WHERE c.fyh_elm IS NULL
           AND c.fyh_cre >= (SELECT desde FROM _cfg)
           AND cd.cantidad_recibida <> COALESCE(lg.qty_ledger, 0)
     ) x
    )                                                               AS s6_qty_recibida_drift,

    -- §7: COMPRA_ING insumo movements with no lote
    (SELECT COUNT(*)
     FROM inventario.item_movimientos im
     JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                             AND imt.codigo = 'COMPRA_ING'
     JOIN item i       ON i.id  = im.item_id
     JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
     WHERE im.lote_id IS NULL
       AND im.fecha_hora >= (SELECT desde FROM _cfg)
    )                                                               AS s7_movimientos_sin_lote,

    -- §8: omitido (lrd sólo aplica a ROLLO)

    -- §9: COMPRA_ING insumo movements from unlinked entrega
    (SELECT COUNT(*)
     FROM inventario.item_movimientos im
     JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                             AND imt.codigo = 'COMPRA_ING'
     JOIN item i       ON i.id  = im.item_id
     JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
     WHERE im.documento_tipo = 'entrega'
       AND im.fecha_hora >= (SELECT desde FROM _cfg)
       AND NOT EXISTS (
           SELECT 1 FROM doc.compra_entrega ce WHERE ce.entrega_id = im.documento_id
       )
    )                                                               AS s9_stock_sin_po;

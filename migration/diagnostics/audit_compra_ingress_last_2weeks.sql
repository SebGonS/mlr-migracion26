-- ============================================================================
-- Audit: purchase ingresos in the last 2 weeks for the two failure modes
-- found on compra 1008 and compra 991:
--   A) cantidad_recibida doesn't match the NET ledger (COMPRA_ING/DEV_PROV_EGR/
--      DEV_PROV_EGR_REV) — e.g. a correction via actualizar_entrega/anular_entrega
--      that never resynced the counter.
--   B) entrega_detalle line has a quantity but ZERO matching item_movimientos
--      (or the movement sum doesn't match the detalle quantity at all) — e.g. a
--      guía created manually/separately from the compra, skipping the ledger
--      entirely.
-- Window: compra.fyh_cre >= now() - interval '14 days'
-- ============================================================================

-- A) cantidad_recibida vs net ledger mismatch ----------------------------------
WITH ledger_neto AS (
    SELECT
        ce.compra_id,
        im.item_id,
        SUM(CASE imt.codigo
            WHEN 'COMPRA_ING'       THEN  im.cantidad
            WHEN 'DEV_PROV_EGR'     THEN -im.cantidad
            WHEN 'DEV_PROV_EGR_REV' THEN  im.cantidad
            ELSE 0
        END) AS cantidad_neta_ledger
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN doc.compra_entrega ce ON ce.entrega_id = im.documento_id AND im.documento_tipo = 'entrega'
    GROUP BY ce.compra_id, im.item_id
)
SELECT
    'A: cantidad_recibida MISMATCH' AS problema,
    c.id AS compra_id, c.fyh_cre AS compra_fecha,
    cd.id AS compra_detalle_id, cd.item_id, i.nombre,
    cd.cantidad AS ordenada, cd.cantidad_recibida AS recibida_registrada,
    COALESCE(ln.cantidad_neta_ledger, 0) AS recibida_segun_ledger
FROM doc.compra c
JOIN doc.compra_detalle cd ON cd.compra_id = c.id
JOIN item i ON i.id = cd.item_id
LEFT JOIN ledger_neto ln ON ln.compra_id = c.id AND ln.item_id = cd.item_id
WHERE c.fyh_cre >= now() - interval '14 days'
  AND c.fyh_elm IS NULL
  AND ROUND(cd.cantidad_recibida, 4) <> ROUND(COALESCE(ln.cantidad_neta_ledger, 0), 4)
ORDER BY c.fyh_cre DESC;

-- B) entrega_detalle lines with no (or mismatched) movement coverage ----------
WITH detalle_vs_mov AS (
    SELECT
        ed.entrega_id, ed.id AS detalle_id, ed.item_id, ed.cantidad AS detalle_cantidad,
        COALESCE((
            SELECT SUM(im.cantidad)
            FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE im.documento_tipo = 'entrega'
              AND im.documento_id = ed.entrega_id
              AND im.documento_linea_id = ed.id
              AND imt.codigo = 'COMPRA_ING'
        ), 0) AS movimiento_cantidad
    FROM doc.entrega_detalle ed
    JOIN doc.entrega e ON e.id = ed.entrega_id
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
    WHERE et.codigo = 'COMPRA_INGRESO'
      AND e.fyh_elm IS NULL
)
SELECT
    'B: entrega_detalle vs movimientos MISMATCH' AS problema,
    ce.compra_id, e.fecha_recepcion, e.id AS entrega_id, e.serie, e.correlativo,
    dvm.detalle_id, dvm.item_id, i.nombre,
    dvm.detalle_cantidad, dvm.movimiento_cantidad,
    CASE WHEN dvm.movimiento_cantidad = 0 THEN 'SIN MOVIMIENTO (guía sin postear)'
         ELSE 'CANTIDAD NO COINCIDE' END AS tipo_falla
FROM detalle_vs_mov dvm
JOIN doc.entrega e ON e.id = dvm.entrega_id
JOIN item i ON i.id = dvm.item_id
LEFT JOIN doc.compra_entrega ce ON ce.entrega_id = dvm.entrega_id
WHERE e.fecha_recepcion >= now() - interval '14 days'
  AND ROUND(dvm.detalle_cantidad, 4) <> ROUND(dvm.movimiento_cantidad, 4)
ORDER BY e.fecha_recepcion DESC;

-- C) Sanity: any COMPRA_INGRESO entrega in the window not linked to a compra? -
--    (not itself a bug, but useful context if B) shows unexpected rows)
SELECT e.id AS entrega_id, e.serie, e.correlativo, e.fecha_recepcion
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
LEFT JOIN doc.compra_entrega ce ON ce.entrega_id = e.id
WHERE et.codigo = 'COMPRA_INGRESO'
  AND e.fyh_elm IS NULL
  AND e.fecha_recepcion >= now() - interval '14 days'
  AND ce.entrega_id IS NULL
ORDER BY e.fecha_recepcion DESC;


SELECT * FROM tenido
UPDATE mes.partida set tenido_id =2 WHERE id=6328



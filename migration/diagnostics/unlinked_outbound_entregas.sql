-- READ ONLY · What are the 41 outbound entregas that got NO venta_id after the
-- despacho→venta migration? The link step (§5 of migrate_despacho_to_venta.sql)
-- matches an outbound entrega to a venta via (tercero_id, root partida). An entrega
-- fails to link if either: (a) its partida has no despacho row at all (never
-- migrated as a venta), or (b) the tercero on the entrega differs from the tercero
-- the venta was created under. Nothing writes.

WITH unlinked AS (
    SELECT DISTINCT e.id AS entrega_id, e.tercero_id AS entrega_tercero_id,
           e.fyh_cre, et.codigo AS entrega_tipo, pp.partida_id
    FROM doc.entrega e
    JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
                            AND et.codigo IN ('DESPACHO_CLIENTE','VENTA_EGRESO')
    JOIN doc.entrega_detalle ed ON ed.entrega_id = e.id
    JOIN inventario.lote l      ON l.id = ed.lote_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                       AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp    ON pp.id = ppe.partida_paso_id
    WHERE e.venta_id IS NULL
)
SELECT u.entrega_id, u.entrega_tipo, u.entrega_tercero_id, t.nombre AS entrega_cliente,
       u.partida_id,
       COALESCE(mp.partida_origen_id, mp.id) AS root_partida_id,
       mp.tercero_id AS partida_tercero_id,
       u.fyh_cre,
       EXISTS (SELECT 1 FROM public.despacho d WHERE d.partida_id = u.partida_id
                                                   OR d.partida_id = COALESCE(mp.partida_origen_id, mp.id))
                                                 AS partida_has_despacho_row,
       (u.entrega_tercero_id = mp.tercero_id)   AS tercero_matches
FROM unlinked u
LEFT JOIN mes.partida mp ON mp.id = u.partida_id
LEFT JOIN tercero t      ON t.id = u.entrega_tercero_id
ORDER BY u.fyh_cre;

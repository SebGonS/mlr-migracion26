-- Follow-up to debug_partida_6132_despacho_rollos.sql.
-- Split-location duplication ruled out: rows_lote_x_ubicacion = distinct_lotes = 8,
-- kg_total = 112.78. Only one producing partida_paso set (21802-21806), no
-- rework/reproceso child feeding in. So the 8 lotes are genuinely 8 distinct
-- dyed output lotes with stock — need to check whether "more than expected"
-- means (a) more physical rolls than the client/partida intent, or (b) some
-- of these 8 are stale — already dispatched but stock never decremented.

-- Step 1 — the 8 lotes in question: genealogy, quality-split lineage, entrega linkage.
SELECT
    l.id AS lote_id,
    l.item_id,
    l.propietario_id,
    l.estado_calidad,
    l.documento_tipo,
    l.documento_id,
    lrd.flg_tenido,
    lrd.entrega_id,
    lrd.ancho,
    sa.cantidad_disponible,
    l.fyh_cre
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE l.documento_tipo = 'partida_paso_ejecucion'
  AND l.documento_id IN (21802, 21803, 21804, 21805, 21806)
ORDER BY l.id;

-- Step 2 — were any of these lotes born from a QC split (egress of a parent
-- lot, ingress of N children under the same document)? That would mean fewer
-- "real" rolls arrived from production than now appear as separate lotes.
SELECT
    im.lote_id,
    im.id AS movimiento_id,
    imt.codigo AS tipo,
    im.documento_tipo,
    im.documento_id,
    im.origen_ubicacion_id,
    im.destino_ubicacion_id,
    im.cantidad,
    im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (
    SELECT l.id FROM inventario.lote l
    WHERE l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id IN (21802, 21803, 21804, 21805, 21806)
)
ORDER BY im.lote_id, im.fyh_cre;

-- Step 3 — has any of these 8 already been dispatched via doc.entrega
-- (entrega_id set on lote_rollo_detalle, or an entrega_detalle row exists)
-- while still showing available stock? That's the "manual entrega without
-- movements" bug pattern (bug_manual_entrega_without_movements memory).
SELECT
    lrd.lote_id,
    lrd.entrega_id,
    ent.serie, ent.correlativo, ent.fyh_cre AS entrega_fecha,
    ed.id AS entrega_detalle_id
FROM inventario.lote_rollo_detalle lrd
LEFT JOIN doc.entrega ent ON ent.id = lrd.entrega_id
LEFT JOIN doc.entrega_detalle ed ON ed.lote_id = lrd.lote_id
WHERE lrd.lote_id IN (
    SELECT l.id FROM inventario.lote l
    WHERE l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id IN (21802, 21803, 21804, 21805, 21806)
);

-- Step 4 — what did the partida actually order/intend (roll count), to compare
-- against the 8 physical output rolls.
SELECT
    pd.id, pd.item_id, pd.cantidad AS rollos_intencion
FROM mes.partida_detalle pd
WHERE pd.partida_id = 6132;

-- Step 5 — the 5 partida_paso rows (21802-21806): which pasos, and are any of
-- them duplicates of the same operacion (e.g. a correction/re-run that created
-- a second ejecucion + second output lote for what should be the same rolls)?
SELECT
    pp.id AS partida_paso_id,
    pp.operacion_id,
    o.nombre AS operacion,
    pp.secuencia,
    pp.estado,
    pe.id AS ejecucion_id,
    pe.estado AS ejecucion_estado,
    pe.fyh_cre AS ejecucion_fecha
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE pp.partida_id = 6132
ORDER BY pp.secuencia, pe.fyh_cre;

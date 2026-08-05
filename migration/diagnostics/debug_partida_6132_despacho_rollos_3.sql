-- Follow-up #2 to debug_partida_6132_despacho_rollos_2.sql.
-- Bug in my own script: queried l.documento_id IN (21802..21806), but those
-- are mes.partida_paso.id values, not mes.partida_paso_ejecucion.id — hence
-- the three EMPTY results. l.documento_id must reference pe.id. The real
-- ejecucion ids (from step 5's output) are: 9677, 9759, 9838, 9856, 30939.
--
-- Also notable from step 5: partida_paso 21806 (Compactado, secuencia 5, the
-- FINAL step) has estado = 'EN_PROCESO', but its ejecucion 30939 already has
-- estado = 'COMPLETADO' and is dated 2026-07-08 — three weeks after the prior
-- step (Secado, 2026-06-17). That gap + paso/ejecucion estado mismatch is the
-- likely lead: dispatch only requires pe.estado = 'COMPLETADO', not the paso's
-- own estado, so if compactado has more than one ejecucion (e.g. a partial run
-- plus a pending remainder still to come) the already-completed one's output
-- rolls are dispatchable now even though the step isn't fully closed.

-- Step A — re-run with the correct ejecucion ids: the actual 8 output lotes,
-- their genealogy anchor, and entrega linkage.
SELECT
    l.id AS lote_id,
    l.item_id,
    l.propietario_id,
    l.estado_calidad,
    l.documento_id AS ejecucion_id,
    lrd.flg_tenido,
    lrd.entrega_id,
    lrd.ancho,
    sa.cantidad_disponible,
    l.fyh_cre
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE l.documento_tipo = 'partida_paso_ejecucion'
  AND l.documento_id IN (9677, 9759, 9838, 9856, 30939)
ORDER BY l.documento_id, l.id;

-- Step B — does the Compactado paso (21806) have more than one ejecucion row?
-- If so, is 30939 the only COMPLETADO one, with another still pending/EN_PROCESO
-- (which would explain why the paso itself isn't COMPLETADO yet, while these
-- rolls are already dispatchable)?
SELECT
    pe.id AS ejecucion_id, pe.estado, pe.fyh_cre, pe.peso_kg, pe.cantidad_rollos
FROM mes.partida_paso_ejecucion pe
WHERE pe.partida_paso_id = 21806
ORDER BY pe.fyh_cre;

-- Step C — item_movimientos for the 8 lotes: confirms production ingress and
-- checks for any egress (dispatch) already recorded against them.
SELECT
    im.lote_id, im.id AS movimiento_id, imt.codigo AS tipo,
    im.documento_tipo, im.documento_id,
    im.origen_ubicacion_id, im.destino_ubicacion_id,
    im.cantidad, im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (
    SELECT l.id FROM inventario.lote l
    WHERE l.documento_tipo = 'partida_paso_ejecucion'
      AND l.documento_id IN (9677, 9759, 9838, 9856, 30939)
)
ORDER BY im.lote_id, im.fyh_cre;

-- Step D — is 262 (the item on partida_detalle, 23 rollos intención) the raw
-- input item, or the dyed output item? Compare against the 8 output lotes'
-- item_id from Step A to see if intención (23) and actual output count (8)
-- are even comparable, or if "more than expected" means something else
-- (e.g. user expected 0 dispatchable because compactado isn't finished yet).
SELECT DISTINCT i.id, i.codigo, i.item_tipo_id
FROM inventario.lote l
JOIN item i ON i.id = l.item_id
WHERE l.documento_tipo = 'partida_paso_ejecucion'
  AND l.documento_id IN (9677, 9759, 9838, 9856, 30939)
UNION
SELECT id, codigo, item_tipo_id FROM item WHERE id = 262;

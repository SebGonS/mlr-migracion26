-- Partida 6132 confirmed as the ROOT of its own 5 pasos (21802-21806), all
-- COMPLETADO/EN_PROCESO as shown earlier — so the "wrong registration" isn't
-- pasos owned by 6132 itself. User says: 6132 is a rework (reproceso), and
-- the Compactado for its reworked rolls was wrongly registered on the
-- ORIGINAL partida instead. Need to find:
--   1. 6132's partida_origen_id (the partida it reworks).
--   2. The original partida's own Compactado paso/ejecucion, to see if it
--      has extra output that actually belongs to 6132's rework material
--      (e.g. output lotes whose genealogy traces back to 6132's rework
--      input rolls, i.e. lrd.origen_lote_id points at a 6132 REPROCESO lote).

-- Step 1 — 6132 itself: is it a rework, and of what?
SELECT id, numero, partida_origen_id, estado_produccion, estado_comercial,
       tercero_id, color_x_cliente_id, fyh_cre
FROM mes.partida
WHERE id = 6132;

-- Step 2 — the original partida's pasos/ejecuciones (once we have the id from
-- step 1). Placeholder :orig — replace after running step 1.
-- SELECT pp.id AS partida_paso_id, pp.operacion_id, o.nombre, pp.secuencia,
--        pp.estado, pe.id AS ejecucion_id, pe.estado AS ejecucion_estado,
--        pe.fyh_cre, pe.cantidad_rollos, pe.peso_kg
-- FROM mes.partida_paso pp
-- JOIN mes.operacion o ON o.id = pp.operacion_id
-- JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
-- WHERE pp.partida_id = :orig
-- ORDER BY pp.secuencia, pe.fyh_cre;

-- Step 3 — how did 6132 receive its rework input material? Look at
-- mes.partida_componente for 6132 (the rework roll(s) it started from) and
-- trace their lote lineage.
SELECT pc.partida_id, pc.lote_id, l.estado_calidad, l.documento_tipo, l.documento_id,
       lrd.origen_lote_id, l.cantidad
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE pc.partida_id = 6132;

-- Step 4 — 6132's own Preparado ejecucion (9677, the FIRST step) — what were
-- its declared input rolls (cantidad_rollos) vs what actually got dyed
-- through to Compactado (8, per the earlier count)? A mismatch here (e.g.
-- Preparado says more rolls than 8) plus the note about a compactado
-- "missing" points at some of 6132's rework rolls having their final step
-- registered elsewhere.
SELECT pe.id, pe.estado, pe.cantidad_rollos, pe.peso_kg, pe.fyh_cre
FROM mes.partida_paso_ejecucion pe
WHERE pe.id IN (9677, 9759, 9838, 9856, 30939)
ORDER BY pe.fyh_cre;

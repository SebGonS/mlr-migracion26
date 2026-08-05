-- ============================================================================
-- CORRECTION: the prior fix (fix_6464_remove_stale_componentes.sql) deleted
-- 6464's partida_componente rows for lotes 122749-122752, on the assumption
-- 5947 already had its own reservation row for them. It did not -- verify
-- confirmed mes.partida_componente now has ZERO rows for these lotes.
--
-- These rolls WERE physically consumed (PROD_CONSUMO) by 5947's TENIDO step
-- (ejecucion 1860, COMPLETADO, cantidad_rollos=4/peso_kg=90.6 -- exact match).
-- That consumption is real and stays. What's missing is the componente
-- (reservation) row itself, which every partida_componente-driven function
-- (materiales_reservados, generar_receta weight sums, etc.) expects to exist
-- for partida 5947. Re-add it there, mirroring crear_reproceso's Case B
-- insert (funciones/mes.sql:3763-3771).
-- ============================================================================

INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada)
SELECT 5947, l.id, l.cantidad
FROM inventario.lote l
WHERE l.id IN (122749,122750,122751,122752)
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_componente pc
      WHERE pc.lote_id = l.id AND pc.partida_id = 5947
  );

-- ── Verify ───────────────────────────────────────────────────────────────
SELECT lote_id, partida_id, cantidad_reservada
FROM mes.partida_componente
WHERE lote_id IN (122749,122750,122751,122752);
-- Expect: 4 rows, all partida_id = 5947.

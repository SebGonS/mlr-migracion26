-- ============================================================================
-- FIX: registrar_pesaje_grupo's guard checks EXISTS(... codigo='PROD_CONSUMO'
-- ...) -- a raw historical existence check that a PROD_CONSUMO_REV can never
-- satisfy, since history is never deleted. These 4 rolls (122749-122752)
-- have already been manually validated (reversed consumption confirmed net
-- zero, correctly reassigned to 6464, weight unchanged at 22.65kg each), so
-- insert the pesaje row directly -- mirrors exactly what registrar_pesaje_
-- grupo would do (inventario.sql ~1230-1238), skipped only because its
-- guard can't be satisfied here. Weight is unchanged, so no PESAJE_POS/NEG
-- movement or lote.cantidad update is needed (peso_nuevo = peso_anterior).
-- ============================================================================

INSERT INTO inventario.pesaje (lote_id, tipo, peso_real)
SELECT id, 'INGRESO', cantidad
FROM inventario.lote
WHERE id IN (122749,122750,122751,122752)
ON CONFLICT (lote_id) DO UPDATE
    SET peso_real = EXCLUDED.peso_real,
        tipo      = EXCLUDED.tipo;

-- ── Verify: generar_receta's pesaje guard clears for 6464 ──────────────────
SELECT pc.lote_id
FROM mes.partida_componente pc
WHERE pc.partida_id = 6464
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows.

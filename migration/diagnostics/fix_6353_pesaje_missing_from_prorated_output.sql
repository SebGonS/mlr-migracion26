-- partida 6353: generar_receta blocked because its 14 components are
-- output rolls of partida_paso_ejecucion 8772 that were prorated (all
-- identical 22.4850 kg) and therefore never got an inventario.pesaje row.
-- registrar_produccion only writes pesaje when peso_salida is physically
-- measured per roll; prorated totals skip it by design.
--
-- Not a bug: the weighing gate is correctly saying these specific rolls
-- were never actually put on a scale. Resolve by recording real weights.

-- 1) opi_id (mes.partida_componente.id) + lote_id + type, to fill in
--    actual measured weights per roll.
SELECT pc.id AS opi_id, pc.lote_id, l.cantidad AS peso_actual_prorateado,
       ird.flg_rib
FROM mes.partida_componente pc
JOIN inventario.lote l      ON l.id = pc.lote_id
JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
WHERE pc.partida_id = 6353
ORDER BY pc.id;

-- 2a) OPTION A — individual per-roll weights (recommended: these are
--     WIP rolls, real weights likely differ from each other).
--     Fill in real peso_kg per opi_id from query #1, then run:
--
-- SELECT mes.actualizar_pesos_individuales_partida(
--     6353,
--     '[
--        {"id": <opi_id_1>, "peso_kg": <real_weight_1>},
--        {"id": <opi_id_2>, "peso_kg": <real_weight_2>}
--        -- ... one entry per row from query #1
--     ]'::jsonb
-- );

-- 2b) OPTION B — bulk correction, evenly re-prorates by roll type
--     (same limitation as before: all regular rolls get one weight,
--     all rib rolls get another). Only use if you don't have per-roll
--     scale readings.
--
SELECT inventario.corregir_pesaje_produccion(
    6353,
   314.8,
    NULL
);

-- 3) After running 2a or 2b, verify the guard clears:
SELECT pc.lote_id
FROM mes.partida_componente pc
JOIN inventario.lote l ON l.id = pc.lote_id
WHERE pc.partida_id = 6353
  AND pc.lote_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM inventario.pesaje p WHERE p.lote_id = pc.lote_id);
-- Expect 0 rows.

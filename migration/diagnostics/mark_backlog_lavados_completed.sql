-- ═══════════════════════════════════════════════════════════════
-- One-off backfill: mark the pre-cuadre lavado backlog COMPLETADO
-- WITHOUT posting insumo consumption.
--
-- Context
-- ───────
-- 20 machine washes (18 PENDIENTE + 2 EN_PROCESO) were created between
-- cuadre 33 (2026-06-23) and cuadre 35's count (2026-08-03 13:28) and never
-- executed. Evidence (scheduling board + real production flanking each wash
-- on its machine) shows they physically happened, so they must NOT be
-- cancelled — they are marked COMPLETADO for traceability.
--
-- Their theoretical recipe consumption is deliberately NOT posted:
--   • cuadre 35's physical count already reconciled real stock as of the
--     count date, so the drawdown is already reflected;
--   • the recipes are theoretical and routinely need manual adjustment, so
--     posting recipe totals would fabricate/duplicate deductions (proven by
--     the surpluses on HIDROSULFITO/DESENGRASANTE/ISOPON ERC at the count).
--
-- Scope: only lavados created BEFORE the count (fyh_cre < 2026-08-03 13:28).
-- Lavados 61 & 62 (post-count) are intentionally excluded — they are not in
-- the cuadre and should be run through the normal finalize flow WITH
-- (adjusted) consumption once the insumos-override UI is live.
-- ═══════════════════════════════════════════════════════════════

-- Preview what will change (run first, expect 20 rows):
-- SELECT id, estado, maquina_id, fyh_cre
-- FROM mes.lavado_maquina
-- WHERE estado IN ('PENDIENTE','EN_PROCESO')
--   AND fyh_cre < '2026-08-03 13:28:00+00'
-- ORDER BY fyh_cre;

UPDATE mes.lavado_maquina
SET estado     = 'COMPLETADO',
    fyh_inicio = COALESCE(fyh_inicio, fyh_cre),
    fyh_fin    = COALESCE(fyh_fin, fyh_cre),
    nota       = COALESCE(nota || ' | ', '')
                 || 'Backfill 2026-08-04: COMPLETADO sin consumo. Recetas requieren '
                 || 'ajuste manual; drawdown fisico ya reconciliado en cuadre 35.',
    usr_mod    = 8,          -- TODO: set to the user id running this
    fyh_mod    = now()
WHERE estado IN ('PENDIENTE','EN_PROCESO')
  AND fyh_cre < '2026-08-03 13:28:00+00';

-- Expected: UPDATE 20. No inventario.item_movimientos are written.

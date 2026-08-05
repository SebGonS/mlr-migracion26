-- ============================================================================
-- DIAGNOSTIC: full movement ledger + lote_saldo for the 10 zero-stock,
-- no-pesaje componente rolls of partida 6465. Grouped to keep output small.
-- Read-only.
-- ============================================================================

-- ── 1. Full movement ledger for these lotes (chronological, per lote) ────────
SELECT
    im.lote_id,
    imt.codigo          AS movimiento,
    im.documento_tipo,
    im.documento_id,
    im.cantidad,
    im.origen_ubicacion_id,
    im.destino_ubicacion_id,
    im.fyh_cre
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.lote_id IN (167200,167201,167202,167203,167204,167205,167206,167207,167208,167209)
ORDER BY im.lote_id, im.fyh_cre;

-- ── 2. Raw lote_saldo rows (does the balance table even have a row?) ─────────
SELECT
    ls.lote_id,
    ls.ubicacion_id,
    ls.cantidad_actual
FROM inventario.lote_saldo ls
WHERE ls.lote_id IN (167200,167201,167202,167203,167204,167205,167206,167207,167208,167209)
ORDER BY ls.lote_id, ls.ubicacion_id;

-- ── 3. Lote header — cantidad, propietario, documento origin ─────────────────
SELECT
    l.id AS lote_id,
    l.item_id,
    l.documento_tipo,
    l.documento_id,
    l.propietario_id,
    ROUND(l.cantidad::NUMERIC,2) AS kg_lote,
    l.estado_calidad
FROM inventario.lote l
WHERE l.id IN (167200,167201,167202,167203,167204,167205,167206,167207,167208,167209)
ORDER BY l.id;

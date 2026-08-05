-- Audit: find every occurrence of the same bug that hit partida 6223 —
-- an ingress movement (PROD_ING, and any other *_ING/*_ENTRADA style type
-- that should always carry a destino) posted with destino_ubicacion_id NULL,
-- meaning the lote has a movement row but no lote_saldo/item_saldo credit
-- and is invisible to every stock view (vw_stock_lotes, vw_despacho_pendiente, etc).
-- See migration/operations_patching/fix_6223_missing_destino_ubicacion.sql for
-- the single-partida repair and root cause (registrar_produccion read
-- p_datos->>'ubicacion_id' with no NOT NULL guard — now fixed, funciones/mes.sql:1610).

-- 1. Overview: how many affected rows per movement type, split dyed vs undyed.
SELECT
    imt.codigo                         AS tipo,
    lrd.flg_tenido,
    COUNT(*)                           AS movimientos_afectados,
    COUNT(DISTINCT im.lote_id)         AS lotes_afectados,
    COUNT(DISTINCT pp.partida_id)      AS partidas_afectadas,
    MIN(im.fyh_cre)                    AS primera_fecha,
    MAX(im.fyh_cre)                    AS ultima_fecha
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id
LEFT JOIN inventario.lote l ON l.id = im.lote_id
LEFT JOIN mes.partida_paso_ejecucion pe
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
LEFT JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
WHERE imt.codigo LIKE '%ING%'          -- all ingress-style movement types
  AND im.origen_ubicacion_id IS NULL   -- true ingress (not a transfer, which sets both)
  AND im.destino_ubicacion_id IS NULL  -- the bug: no destination recorded
GROUP BY imt.codigo, lrd.flg_tenido
ORDER BY imt.codigo, lrd.flg_tenido;

-- 2. Row-level detail for PROD_ING specifically (the type that bit partida 6223) —
--    one row per affected lote, with the partida it belongs to and its dyed flag.
SELECT
    im.id                   AS movimiento_id,
    im.lote_id,
    im.cantidad,
    im.fyh_cre,
    l.documento_id           AS ejecucion_id,
    pp.partida_id,
    lrd.flg_tenido,
    lrd.entrega_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
JOIN inventario.lote l ON l.id = im.lote_id
LEFT JOIN mes.partida_paso_ejecucion pe
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
LEFT JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id
WHERE imt.codigo = 'PROD_ING'
  AND im.origen_ubicacion_id IS NULL
  AND im.destino_ubicacion_id IS NULL
ORDER BY im.fyh_cre, im.lote_id;

-- 3. Sanity check: confirm none of these lotes already got a lote_saldo row
--    some other way (e.g. a later correction) — if cantidad_actual already
--    exists, don't double-credit them in the patch.
SELECT im.lote_id, ls.ubicacion_id, ls.cantidad_actual
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
LEFT JOIN inventario.lote_saldo ls ON ls.lote_id = im.lote_id
WHERE imt.codigo = 'PROD_ING'
  AND im.origen_ubicacion_id IS NULL
  AND im.destino_ubicacion_id IS NULL;

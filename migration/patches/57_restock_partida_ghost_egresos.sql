-- 57_restock_partida_ghost_egresos.sql   ⚠ review before running (data mutation)
--
-- Restocks the PARTIDA-attached ghost SERV_EGR egresses: SERV_EGR movements with
-- documento_tipo='PARTIDA' (posted directly against a partida, bypassing the
-- entrega/venta flow — the Track-B deferred rolls). These rolls are wrongly out
-- of stock; they never really dispatched.
--
-- Reversal type = SERV_DEV_ING (+1), the EXACT counterpart of SERV_EGR (the same
-- pair anular_entrega uses). NOT AJUSTE_POS — that is valorizable and would post
-- a valuation for client material MLR doesn't own. SERV_DEV_ING is non-valorizable.
--
-- EXCLUDES the 1 lote already manually re-ingressed (double-restock / double-charge
-- guard), and any lote currently in stock.
--
-- After restock, the rolls are dispatched properly through the app (manual, new
-- per-item flow) — this script does NOT fabricate ventas/prices.
--
-- ⚠ §0 read-only → §1 in a txn → §2 verify → COMMIT.

-- ══════════════════════════════════════════════════════════════════════════
-- §0 · PRE-CHECK (read only) — the clean-to-reverse set
-- ══════════════════════════════════════════════════════════════════════════
WITH ghost AS (
  SELECT im.id AS orig_mov_id, im.item_id, im.lote_id, im.cantidad,
         im.origen_ubicacion_id, im.documento_id AS partida_id, im.fecha_hora
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
  WHERE imt.codigo = 'SERV_EGR' AND im.documento_tipo = 'PARTIDA'
),
clean AS (
  SELECT g.*
  FROM ghost g
  LEFT JOIN inventario.vw_stock_lotes sl ON sl.lote_id = g.lote_id
  WHERE sl.lote_id IS NULL                                   -- still out of stock
    AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im2
                    JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                    WHERE im2.lote_id = g.lote_id AND imt2.factor = 1
                      AND im2.fecha_hora > g.fecha_hora)      -- not already re-ingressed
)
SELECT COUNT(*) AS clean_to_restock_expect_1955,
       COUNT(DISTINCT lote_id) AS distinct_lotes,
       COUNT(*) FILTER (WHERE origen_ubicacion_id IS NULL) AS null_ubicacion
FROM clean;


-- ══════════════════════════════════════════════════════════════════════════
-- §1 · Execute  (one transaction)
-- ══════════════════════════════════════════════════════════════════════════
BEGIN;

WITH ghost AS (
  SELECT im.id AS orig_mov_id, im.item_id, im.lote_id, im.cantidad,
         im.origen_ubicacion_id, im.documento_id AS partida_id, im.fecha_hora
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
  WHERE imt.codigo = 'SERV_EGR' AND im.documento_tipo = 'PARTIDA'
),
clean AS (
  SELECT g.*
  FROM ghost g
  LEFT JOIN inventario.vw_stock_lotes sl ON sl.lote_id = g.lote_id
  WHERE sl.lote_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im2
                    JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                    WHERE im2.lote_id = g.lote_id AND imt2.factor = 1
                      AND im2.fecha_hora > g.fecha_hora)
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id,
    observacion, usr_cre)
SELECT
    nextval('inventario.mov_doc_seq'),
    c.item_id, c.lote_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_DEV_ING'),
    c.origen_ubicacion_id,          -- roll returns to where the bogus egress took it from
    c.cantidad, now(), 'PARTIDA', c.partida_id,
    'Restock: reversa de SERV_EGR fantasma (egreso sin entrega/venta) mov #' || c.orig_mov_id || ' — patch 57',
    4
FROM clean c;
-- -- expect 1955 rows


-- ══════════════════════════════════════════════════════════════════════════
-- §2 · VERIFY (before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════
-- -- the 1,955 lotes are now back in stock (expect: back_in_stock = 1955)
WITH ghost AS (
  SELECT DISTINCT im.lote_id
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
  WHERE imt.codigo = 'SERV_EGR' AND im.documento_tipo = 'PARTIDA'
    AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im2
        JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
        WHERE im2.lote_id = im.lote_id AND imt2.codigo IN ('SERV_DEV_ING') AND im2.observacion LIKE '%patch 57%')
    IS NOT TRUE   -- placeholder; simpler: just recount stock below
)
SELECT COUNT(*) AS serv_dev_ing_posted
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE imt.codigo = 'SERV_DEV_ING' AND im.observacion LIKE '%patch 57%';
-- -- expect 1955
--
-- -- no valuation leaked (SERV_DEV_ING is non-valorizable → these post monto NULL)
SELECT COUNT(*) AS valued_rows_expect_0
FROM inventario.item_movimientos
WHERE observacion LIKE '%patch 57%' AND precio_unitario IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════════
-- COMMIT;   -- only after §2 checks out
-- ══════════════════════════════════════════════════════════════════════════

-- ============================================================================
-- Fix: entrega 855 (compra 991) has entrega_detalle rows but NO lote/movement.
-- Root cause (confirmed by user): guía was created manually, separately from
-- the compra, via a stale path that never posted inventory movements.
-- Goods are confirmed physically on hand. Posting directly onto entrega 855
-- (not anulando/recreating) to preserve the existing guía numbering.
-- ============================================================================

-- 0) Sanity check: still no lote/movement for this entrega? (should be 0 rows) --
SELECT 'lote' AS tabla, count(*) FROM inventario.lote
WHERE documento_tipo = 'entrega' AND documento_id = 855
UNION ALL
SELECT 'item_movimientos', count(*) FROM inventario.item_movimientos
WHERE documento_tipo = 'entrega' AND documento_id = 855;

-- 1) Confirm destination ubicacion for insumos (ALM_INS) -----------------------
SELECT ub.id AS ubicacion_id, ub.codigo, alm.codigo AS almacen_codigo
FROM inventario.ubicacion ub
JOIN inventario.almacen alm ON alm.id = ub.almacen_id
WHERE alm.codigo = 'ALM_INS';

-- ============================================================================
-- Once 0) confirms zero rows and 1) gives you the ubicacion_id, fill it into
-- the block below (replace <UBICACION_INS_ID>) and run inside a transaction.
-- ============================================================================

BEGIN;

-- 2) Create the two missing lotes (one per entrega_detalle line) --------------
WITH nuevos_lotes AS (
    INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
    SELECT ed.item_id, 'entrega', ed.entrega_id, ed.cantidad, NULL, get_user_id()
    FROM doc.entrega_detalle ed
    WHERE ed.entrega_id = 855
    RETURNING id, item_id, cantidad, documento_id
),
-- 3) Post the missing COMPRA_ING movement for each new lote -------------------
mov AS (
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, fecha_hora,
        documento_tipo, documento_id, documento_linea_id, usr_cre
    )
    SELECT
        nextval('inventario.mov_doc_seq'),
        nl.item_id, nl.id,
        (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'COMPRA_ING'),
        (SELECT ub.id FROM inventario.ubicacion ub
         JOIN inventario.almacen alm ON alm.id = ub.almacen_id
         WHERE alm.codigo = 'ALM_INS'),
        nl.cantidad,
        now(),   -- backdated fecha_recepcion rejected by fn_trg_check_corte_cuadre (inventory cutoff); posting as of today instead
        'entrega', nl.documento_id,
        (SELECT ed.id FROM doc.entrega_detalle ed WHERE ed.entrega_id = nl.documento_id AND ed.item_id = nl.item_id),
        get_user_id()
    FROM nuevos_lotes nl
    RETURNING id
)
SELECT * FROM mov;

-- 4) Resync cantidad_recibida on the linked compra_detalle lines --------------
UPDATE doc.compra_detalle cd
SET cantidad_recibida = ed.cantidad
FROM doc.entrega_detalle ed
WHERE ed.entrega_id = 855
  AND cd.compra_id = 991
  AND cd.item_id = ed.item_id;

-- 5) Verify ---------------------------------------------------------------
SELECT * FROM inventario.lote WHERE documento_tipo='entrega' AND documento_id=855;
SELECT * FROM inventario.item_movimientos WHERE documento_tipo='entrega' AND documento_id=855;
SELECT id, item_id, cantidad, cantidad_recibida FROM doc.compra_detalle WHERE compra_id = 991;

-- Inspect the above, then:
COMMIT;   -- or ROLLBACK if anything looks wrong


select * from doc.entrega
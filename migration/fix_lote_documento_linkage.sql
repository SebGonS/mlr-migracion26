-- ============================================================
-- Fix documento linkage: reassign lotes & movements from
--   documento_tipo = 'PARTIDA'  →  'GUIA_REMISION'
--
-- Use case: rows in lote and item_movimientos are currently
-- tagged as PARTIDA but should point back to the guia_remision
-- that originated them.
--
-- Source of new values  : inventario.lote WHERE documento_tipo='GUIA_REMISION' AND documento_id=v_guia_remision_id
-- Targets to UPDATE     :
--   inventario.lote              WHERE documento_tipo='PARTIDA' AND documento_id=v_partida_id
--   inventario.item_movimientos  WHERE documento_tipo='PARTIDA' AND documento_id=v_partida_id
--
-- Parameters (edit before running):
--   v_guia_remision_id  : the guia_remision.id to set AS the new documento_id
--   v_partida_id        : the partida.id currently on the rows to fix
--
-- Steps (in order):
--   1. INSERT into doc.guia_remision_detalle (item_id, lote_id, cantidad) from the target lotes
--   2. UPDATE inventario.lote              PARTIDA → GUIA_REMISION
--   3. UPDATE inventario.item_movimientos  PARTIDA → GUIA_REMISION
-- ============================================================

-- ── DRY RUN ──────────────────────────────────────────────────
-- Run these SELECTs first to verify scope before executing the DO block.
-- -------------------------------------------------------------
/*
-- Rows that will be updated:
SELECT id, item_id, cantidad, documento_tipo, documento_id
FROM   inventario.lote
WHERE  documento_tipo = 'PARTIDA'
AND    documento_id   = 5190;   -- ← v_partida_id

SELECT id, lote_id, cantidad, documento_tipo, documento_id
FROM   inventario.item_movimientos
WHERE  documento_tipo = 'PARTIDA'
AND    documento_id   = 5190;   -- ← v_partida_id

-- New values they will be set to (confirm these exist):
SELECT documento_tipo, documento_id
FROM   inventario.lote
WHERE  documento_tipo = 'GUIA_REMISION'
AND    documento_id   = 681;    -- ← v_guia_remision_id
*/

-- ── EXECUTE BLOCK ─────────────────────────────────────────────
-- Wrap the DO body in BEGIN / ROLLBACK for a rehearsal run;
-- swap to COMMIT (or remove the savepoint wrapper) when ready.
-- -------------------------------------------------------------
DO $$
DECLARE
    v_guia_remision_id  INT := 681;   -- ← CHANGE THIS  (new documento_id to set)
    v_partida_id        INT := 5190;  -- ← CHANGE THIS  (current documento_id to match)

    v_grd_inserted      INT;
    v_lotes_updated     INT;
    v_movs_updated      INT;
BEGIN
    RAISE NOTICE 'Reassigning PARTIDA % → GUIA_REMISION % ...', v_partida_id, v_guia_remision_id;

    -- 1. Insert guia_remision_detalle rows from the target lotes
    --    (reads lote before the update so item_id / lote_id / cantidad are still queryable)
    INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
    SELECT v_guia_remision_id,
           l.item_id,
           l.id,  
           l.cantidad
    FROM   inventario.lote l
    WHERE  l.documento_tipo = 'PARTIDA'
      AND  l.documento_id   = v_partida_id;

    GET DIAGNOSTICS v_grd_inserted = ROW_COUNT;
    RAISE NOTICE '  doc.guia_remision_detalle rows inserted: %', v_grd_inserted;

    -- 2. Update inventario.lote
    UPDATE inventario.lote
    SET    documento_tipo = 'GUIA_REMISION',
           documento_id   = v_guia_remision_id
    WHERE  documento_tipo = 'PARTIDA'
      AND  documento_id   = v_partida_id;

    GET DIAGNOSTICS v_lotes_updated = ROW_COUNT;
    RAISE NOTICE '  inventario.lote rows updated: %', v_lotes_updated;

    -- 3. Update inventario.item_movimientos
    UPDATE inventario.item_movimientos
    SET    documento_tipo = 'GUIA_REMISION',
           documento_id   = v_guia_remision_id
    WHERE  documento_tipo = 'PARTIDA'
      AND  documento_id   = v_partida_id;

    GET DIAGNOSTICS v_movs_updated = ROW_COUNT;
    RAISE NOTICE '  inventario.item_movimientos rows updated: %', v_movs_updated;

    RAISE NOTICE 'Done. grd inserted: %, lotes updated: %, movs updated: %',
        v_grd_inserted, v_lotes_updated, v_movs_updated;
END;
$$;

-- ── VERIFY ───────────────────────────────────────────────────
-- After running, confirm the rows now point to the guia_remision:
-- -------------------------------------------------------------
/*
SELECT id, numero, item_id, cantidad, documento_tipo, documento_id
FROM   inventario.lote
WHERE  documento_tipo = 'GUIA_REMISION'
AND    documento_id   = 681;    -- ← v_guia_remision_id

SELECT id, lote_id, tipo, cantidad, documento_tipo, documento_id
FROM   inventario.item_movimientos
WHERE  documento_tipo = 'GUIA_REMISION'
AND    documento_id   = 681;    -- ← v_guia_remision_id

SELECT id, guia_remision_id, item_id, lote_id, ubicacion_id, cantidad
FROM   doc.guia_remision_detalle
WHERE  guia_remision_id = 681;  -- ← v_guia_remision_id
*/

INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, lote_id, cantidad)
    SELECT 681,
           l.item_id,
           l.id,  
           l.cantidad
    FROM   inventario.lote l
    WHERE id IN 
    (
        SELECT lote_id FROM mes.partida_componente WHERE partida_id=5190
    );
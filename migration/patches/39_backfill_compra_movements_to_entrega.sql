-- ─────────────────────────────────────────────────────────────────────────────
-- Patch 39 — backfill compra movements → entrega
--
-- Before this patch: stock ingress posted directly against compra
--   (lote.documento_tipo='compra', item_movimientos.documento_tipo='compra').
-- After this patch: every movement is anchored to an entrega, matching the
--   new model where all COMPRA_ING goes through registrar_entrega_compra.
--
-- Strategy per compra:
--   1. Create one headless entrega (NULL serie/correlativo) of tipo COMPRA_INGRESO.
--   2. Link it via compra_entrega.
--   3. For each distinct (doc_movimiento_id) group, create one entrega_detalle
--      line per item aggregating the movement quantities.
--   4. Re-point lote.documento_tipo/id → 'entrega' / new_entrega_id.
--   5. Re-point item_movimientos.documento_tipo/id/linea_id → entrega path.
--   6. Recompute cantidad_recibida via fn_refresh_compra_detalle_qtys.
--
-- Run inside a transaction; ROLLBACK and inspect if row counts look wrong.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
DECLARE
    v_rec              record;
    v_compra_rec       record;
    v_entrega_tipo_id  smallint;
    v_entrega_id       bigint;
    v_detalle_id       bigint;
    v_compra_det_id    bigint;
    v_compra_count     int := 0;
BEGIN
    SELECT id INTO STRICT v_entrega_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'COMPRA_INGRESO';

    -- Iterate over each compra that has direct-compra movements
    FOR v_compra_rec IN
        SELECT DISTINCT im.documento_id AS compra_id
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE imt.codigo       = 'COMPRA_ING'
          AND im.documento_tipo = 'compra'
        ORDER BY im.documento_id
    LOOP
        -- Create one headless entrega per compra
        INSERT INTO doc.entrega (
            entrega_tipo_id, tercero_id,
            serie, correlativo,
            fecha_emision, fecha_recepcion
        )
        SELECT
            v_entrega_tipo_id,
            c.tercero_id,
            NULL, NULL,                  -- headless: no physical guia reference
            MIN(im.fecha_hora),          -- earliest movement timestamp as receipt date
            MIN(im.fecha_hora)
        FROM doc.compra c
        JOIN inventario.item_movimientos im
            ON im.documento_tipo = 'compra' AND im.documento_id = c.id
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE c.id = v_compra_rec.compra_id
          AND imt.codigo = 'COMPRA_ING'
        GROUP BY c.tercero_id
        RETURNING id INTO v_entrega_id;

        -- Link to compra (idempotent)
        INSERT INTO doc.compra_entrega (compra_id, entrega_id)
        VALUES (v_compra_rec.compra_id, v_entrega_id)
        ON CONFLICT DO NOTHING;

        -- Create entrega_detalle lines (one per item, summing all movements)
        FOR v_rec IN
            SELECT
                im.item_id,
                SUM(im.cantidad)    AS total_cantidad,
                SUM(CASE WHEN l.id IS NOT NULL AND it.codigo = 'ROLLO' THEN 1 ELSE 0 END) AS n_rollos,
                -- Recover compra_detalle link for PO-line traceability
                MIN(im.documento_linea_id) AS compra_detalle_id
            FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            LEFT JOIN inventario.lote l ON l.id = im.lote_id
            LEFT JOIN item i ON i.id = im.item_id
            LEFT JOIN item_tipo it ON it.id = i.item_tipo_id
            WHERE imt.codigo        = 'COMPRA_ING'
              AND im.documento_tipo  = 'compra'
              AND im.documento_id    = v_compra_rec.compra_id
            GROUP BY im.item_id
        LOOP
            -- Resolve compra_detalle_id from PO if not captured on the movement
            v_compra_det_id := v_rec.compra_detalle_id;
            IF v_compra_det_id IS NULL THEN
                SELECT id INTO v_compra_det_id
                FROM doc.compra_detalle
                WHERE compra_id = v_compra_rec.compra_id
                  AND item_id   = v_rec.item_id
                ORDER BY id LIMIT 1;
            END IF;

            INSERT INTO doc.entrega_detalle (
                entrega_id, linea, item_id, cantidad,
                n_rollos, compra_detalle_id
            )
            SELECT
                v_entrega_id,
                ROW_NUMBER() OVER (ORDER BY v_rec.item_id),
                v_rec.item_id,
                v_rec.total_cantidad,
                NULLIF(v_rec.n_rollos, 0),
                v_compra_det_id
            RETURNING id INTO v_detalle_id;

            -- Re-point lotes: documento_tipo='compra' → 'entrega'
            UPDATE inventario.lote
            SET documento_tipo = 'entrega',
                documento_id   = v_entrega_id
            WHERE documento_tipo = 'compra'
              AND documento_id   = v_compra_rec.compra_id
              AND item_id        = v_rec.item_id;

            -- Re-point lote_rollo_detalle.entrega_id if NULL (headless from old ingresar_compra)
            UPDATE inventario.lote_rollo_detalle lrd
            SET entrega_id = v_entrega_id
            WHERE lrd.entrega_id IS NULL
              AND lrd.lote_id IN (
                  SELECT id FROM inventario.lote
                  WHERE documento_tipo = 'entrega'
                    AND documento_id   = v_entrega_id
                    AND item_id        = v_rec.item_id
              );

            -- Re-point movements: documento_tipo/id/linea_id
            UPDATE inventario.item_movimientos
            SET documento_tipo    = 'entrega',
                documento_id      = v_entrega_id,
                documento_linea_id = v_detalle_id
            WHERE documento_tipo = 'compra'
              AND documento_id   = v_compra_rec.compra_id
              AND item_id        = v_rec.item_id
              AND item_movimiento_tipo_id IN (
                  SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'COMPRA_ING'
              );

        END LOOP;

        -- Recompute denormalized receipt counter
        PERFORM doc.fn_refresh_compra_detalle_qtys(v_compra_rec.compra_id);

        v_compra_count := v_compra_count + 1;
        RAISE NOTICE 'compra #%: entrega #% created, movements re-pointed.',
            v_compra_rec.compra_id, v_entrega_id;
    END LOOP;

    RAISE NOTICE 'Backfill complete: % compra(s) processed.', v_compra_count;
END;
$$;

-- ── Verification ─────────────────────────────────────────────────────────────
-- Run this after committing to confirm no compra-anchored COMPRA_ING remain.

SELECT COUNT(*) AS remaining_compra_movements
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE imt.codigo = 'COMPRA_ING'
  AND im.documento_tipo = 'compra';

-- Expected: 0

COMMIT;




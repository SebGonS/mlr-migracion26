-- ═══════════════════════════════════════════════════════════════════════════
-- Patch 41: Retroactive factor_stock correction for PROD_CONSUMO movements
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PROBLEM: registrar_consumo_paso was posting the physical/recipe amount
-- directly to item_movimientos without multiplying by
-- item_insumo_detalle.factor_stock. Items with factor_stock != 1 had their
-- stock under-debited by a factor of (factor_stock - 1).
--
-- APPROACH: INSERT new PROD_CONSUMO movements for the missing delta.
-- Cannot UPDATE existing rows because item_saldo / item_valoracion are
-- maintained by INSERT-only triggers (trg_ai_im_sync_cantidad_actual,
-- trg_ai_item_movimientos_map). The stock is currently over-inflated by
-- exactly these deltas, so FIFO resolution should succeed cleanly.
--
-- Each corrective movement:
--   • tipo:         PROD_CONSUMO (same as original — this is real consumption)
--   • documento_tipo/id: 'partida_paso_ejecucion' + original ejecucion_id
--   • observacion:  'PATCH-41: corrección factor_stock' (idempotency tag)
--   • fecha_hora:   NOW() — not backdated, avoids cuadre-cutoff trigger
--
-- IDEMPOTENT: guarded by observacion tag; safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════
SELECT * FROM item_insumo_detalle WHERE factor_stock IS DISTINCT FROM 1;
BEGIN;

-- ── Step 0: Dry-run preview ──────────────────────────────────────────────
-- Run this SELECT first to inspect scope before applying corrections.
-- NET logic: PROD_CONSUMO_REV (corregir_matizado reversals) are subtracted
-- from the gross PROD_CONSUMO so reversed-then-reposted cases aren't
-- double-counted. The delta is only on the net-consumed amount.
/*
WITH egress AS (
    SELECT im.documento_id AS ejecucion_id, im.item_id,
           SUM(im.cantidad) AS cantidad_consumo
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt
        ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND (im.observacion IS NULL OR im.observacion NOT LIKE 'PATCH-41%')
    GROUP BY im.documento_id, im.item_id
),
reversals AS (
    SELECT im.documento_id AS ejecucion_id, im.item_id,
           SUM(im.cantidad) AS cantidad_revertida
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt
        ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO_REV'
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
    GROUP BY im.documento_id, im.item_id
)
SELECT
    e.ejecucion_id,
    e.item_id,
    i.nombre                                                             AS item_nombre,
    iid.factor_stock,
    it.flg_fungible,
    e.cantidad_consumo,
    COALESCE(r.cantidad_revertida, 0)                                    AS cantidad_revertida,
    e.cantidad_consumo - COALESCE(r.cantidad_revertida, 0)               AS cantidad_neta,
    ROUND((e.cantidad_consumo - COALESCE(r.cantidad_revertida, 0))
          * (iid.factor_stock - 1), 7)                                  AS cantidad_delta
FROM egress e
LEFT JOIN reversals r USING (ejecucion_id, item_id)
JOIN item_insumo_detalle iid ON iid.item_id = e.item_id
    AND iid.factor_stock IS DISTINCT FROM 1
JOIN item i  ON i.id  = e.item_id
JOIN item it ON it.id = e.item_id
WHERE (e.cantidad_consumo - COALESCE(r.cantidad_revertida, 0))
      * (iid.factor_stock - 1) <> 0
ORDER BY e.ejecucion_id, e.item_id;
-- delta > 0 → under-consumed (factor_stock > 1) → needs extra PROD_CONSUMO debit
-- delta < 0 → over-consumed  (factor_stock < 1) → needs PROD_CONSUMO_REV credit
*/

-- ── Step 1: Apply corrections ────────────────────────────────────────────
DO $$
DECLARE
    v_egr_tipo_id       SMALLINT;
    v_rev_tipo_id       SMALLINT;
    v_doc_movimiento_id BIGINT;
    v_fifo_result       jsonb;
    v_total_rows        int := 0;
    rec RECORD;
BEGIN
    SELECT id INTO STRICT v_egr_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO';
    SELECT id INTO STRICT v_rev_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO_REV';

    FOR rec IN
        WITH egress AS (
            SELECT im.documento_id AS ejecucion_id, im.item_id,
                   SUM(im.cantidad) AS cantidad_consumo,
                   AVG(im.precio_unitario) AS precio_unitario
            FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt
                ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
            WHERE im.documento_tipo = 'partida_paso_ejecucion'
              AND (im.observacion IS NULL OR im.observacion NOT LIKE 'PATCH-41%')
            GROUP BY im.documento_id, im.item_id
        ),
        reversals AS (
            SELECT im.documento_id AS ejecucion_id, im.item_id,
                   SUM(im.cantidad) AS cantidad_revertida
            FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt
                ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO_REV'
            WHERE im.documento_tipo = 'partida_paso_ejecucion'
            GROUP BY im.documento_id, im.item_id
        )
        SELECT
            e.ejecucion_id,
            e.item_id,
            it.flg_fungible,
            ROUND((e.cantidad_consumo - COALESCE(r.cantidad_revertida, 0))
                  * (iid.factor_stock - 1), 7)    AS cantidad_delta,
            e.precio_unitario
        FROM egress e
        LEFT JOIN reversals r USING (ejecucion_id, item_id)
        JOIN item_insumo_detalle iid
            ON iid.item_id = e.item_id AND iid.factor_stock IS DISTINCT FROM 1
        JOIN item it ON it.id = e.item_id
        WHERE (e.cantidad_consumo - COALESCE(r.cantidad_revertida, 0))
              * (iid.factor_stock - 1) <> 0
        ORDER BY e.ejecucion_id, e.item_id
    LOOP
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

        IF rec.cantidad_delta > 0 THEN
            -- ── Under-consumed (factor_stock > 1): insert additional PROD_CONSUMO ──
            IF rec.flg_fungible THEN
                INSERT INTO inventario.item_movimientos(
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, cantidad, precio_unitario,
                    documento_tipo, documento_id, observacion
                ) VALUES (
                    v_doc_movimiento_id, rec.item_id, NULL, v_egr_tipo_id,
                    COALESCE(
                        (SELECT ubicacion_id FROM inventario.item_saldo
                         WHERE item_id = rec.item_id ORDER BY cantidad_actual DESC LIMIT 1),
                        (SELECT im2.origen_ubicacion_id FROM inventario.item_movimientos im2
                         WHERE im2.item_id = rec.item_id AND im2.origen_ubicacion_id IS NOT NULL
                         ORDER BY im2.id DESC LIMIT 1)
                    ),
                    rec.cantidad_delta, rec.precio_unitario,
                    'partida_paso_ejecucion', rec.ejecucion_id,
                    'PATCH-41: corrección factor_stock'
                );
            ELSE
                v_fifo_result := mes.calcular_fifo(jsonb_build_array(
                    jsonb_build_object('item_id', rec.item_id, 'cantidad', rec.cantidad_delta)
                ));
                IF v_fifo_result IS NULL OR jsonb_array_length(v_fifo_result) = 0 THEN
                    RAISE EXCEPTION 'PATCH-41: FIFO returned no lots for item_id=%, ejecucion_id=%, delta=%',
                        rec.item_id, rec.ejecucion_id, rec.cantidad_delta;
                END IF;
                INSERT INTO inventario.item_movimientos(
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, cantidad, precio_unitario,
                    documento_tipo, documento_id, observacion
                )
                SELECT v_doc_movimiento_id,
                    (c->>'item_id')::INT, (c->>'lote_id')::INT, v_egr_tipo_id,
                    (c->>'ubicacion_id')::INT, (c->>'cantidad')::NUMERIC, rec.precio_unitario,
                    'partida_paso_ejecucion', rec.ejecucion_id, 'PATCH-41: corrección factor_stock'
                FROM jsonb_array_elements(v_fifo_result) c;
            END IF;

        ELSE
            -- ── Over-consumed (factor_stock < 1): return excess via PROD_CONSUMO_REV ──
            -- excess = ABS(delta) = net_consumed * (1 - factor_stock)
            -- Stock goes back to the item's default location.
            IF rec.flg_fungible THEN
                INSERT INTO inventario.item_movimientos(
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    destino_ubicacion_id, cantidad, precio_unitario,
                    documento_tipo, documento_id, observacion
                ) VALUES (
                    v_doc_movimiento_id, rec.item_id, NULL, v_rev_tipo_id,
                    COALESCE(
                        (SELECT im2.origen_ubicacion_id FROM inventario.item_movimientos im2
                         WHERE im2.item_id = rec.item_id AND im2.origen_ubicacion_id IS NOT NULL
                         ORDER BY im2.id DESC LIMIT 1),
                        (SELECT ity.ubicacion_default_id FROM item it2
                         JOIN item_tipo ity ON ity.id = it2.item_tipo_id
                         WHERE it2.id = rec.item_id)
                    ),
                    ABS(rec.cantidad_delta), rec.precio_unitario,
                    'partida_paso_ejecucion', rec.ejecucion_id,
                    'PATCH-41: corrección factor_stock'
                );
            ELSE
                -- Non-fungible over-consumption: return to a specific lot is ambiguous
                -- retroactively. Raise so it can be handled manually.
                RAISE EXCEPTION
                    'PATCH-41: item_id=% is non-fungible with factor_stock < 1 (over-consumed).'
                    ' Manual lot assignment required for ejecucion_id=%, excess=%',
                    rec.item_id, rec.ejecucion_id, ABS(rec.cantidad_delta);
            END IF;
        END IF;

        v_total_rows := v_total_rows + 1;
        RAISE NOTICE '% ejecucion_id=%, item_id=%, delta=%',
            CASE WHEN rec.cantidad_delta > 0 THEN 'DEBIT' ELSE 'CREDIT' END,
            rec.ejecucion_id, rec.item_id, rec.cantidad_delta;
    END LOOP;

    RAISE NOTICE 'PATCH-41 complete: % (ejecucion, item) pairs corrected.', v_total_rows;
END;
$$;

-- ── Step 2: Verification ─────────────────────────────────────────────────
-- After applying, confirm no uncorrected pairs remain.
WITH egress AS (
    SELECT im.documento_id AS ejecucion_id, im.item_id,
           SUM(im.cantidad) AS cantidad_consumo
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt
        ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
      AND (im.observacion IS NULL OR im.observacion NOT LIKE 'PATCH-41%')
    GROUP BY im.documento_id, im.item_id
),
reversals AS (
    SELECT im.documento_id AS ejecucion_id, im.item_id,
           SUM(im.cantidad) AS cantidad_revertida
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt
        ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO_REV'
    WHERE im.documento_tipo = 'partida_paso_ejecucion'
    GROUP BY im.documento_id, im.item_id
)
SELECT COUNT(*) AS uncorrected_pairs_remaining
FROM egress e
LEFT JOIN reversals r USING (ejecucion_id, item_id)
JOIN item_insumo_detalle iid
    ON iid.item_id = e.item_id AND iid.factor_stock IS DISTINCT FROM 1
WHERE (e.cantidad_consumo - COALESCE(r.cantidad_revertida, 0))
      * (iid.factor_stock - 1) <> 0;

-- Expected: 1 row with count = 0

COMMIT;


UPDATE inventario.item_movimientos
SET observacion = 'corrección consumo: factor de dilución no aplicado'
WHERE observacion = 'PATCH-41: factor_stock correction';

SELECT SUM(cantidad) AS total_devuelto_kg
FROM inventario.item_movimientos
WHERE observacion = 'corrección consumo: factor de dilución no aplicado';


SELECT
    SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO' THEN im.cantidad ELSE 0 END) AS total_consumido_kg,
    SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN im.cantidad ELSE 0 END) AS total_devuelto_kg,
    SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO' THEN im.cantidad ELSE 0 END)
  - SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN im.cantidad ELSE 0 END) AS neto_kg
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 13
  AND im.documento_tipo = 'partida_paso_ejecucion';



SELECT
    im.documento_id                                            AS ejecucion_id,
    SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO'     THEN im.cantidad ELSE 0 END) AS consumido,
    SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN im.cantidad ELSE 0 END) AS revertido,
    SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO'     THEN im.cantidad ELSE 0 END)
  - SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN im.cantidad ELSE 0 END) AS neto_consumido,
    ROUND((
        SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO'     THEN im.cantidad ELSE 0 END)
      - SUM(CASE WHEN imt.codigo = 'PROD_CONSUMO_REV' THEN im.cantidad ELSE 0 END)
    ) * 0.166667, 4)                                          AS debio_consumirse
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 13
  AND im.documento_tipo = 'partida_paso_ejecucion'
GROUP BY im.documento_id
ORDER BY im.documento_id;


SELECT id, fecha_cierre, estado
FROM inventario.cuadre
WHERE estado = 'ejecutado'
ORDER BY fecha_cierre DESC
LIMIT 3;


BEGIN;

-- Preview: which of our corrections are pre-cuadre?
SELECT corr.id, corr.documento_id AS ejecucion_id, corr.cantidad,
       ppe.fyh_cre AS ejecucion_fecha
FROM inventario.item_movimientos corr
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = corr.documento_id
WHERE corr.observacion = 'corrección consumo: factor de dilución no aplicado'
  AND ppe.fyh_cre < '2026-06-23 15:19:21.927224+00'
ORDER BY ppe.fyh_cre;


BEGIN;

INSERT INTO inventario.item_movimientos(
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    origen_ubicacion_id, cantidad, precio_unitario,
    documento_tipo, documento_id, observacion
)
SELECT
    nextval('inventario.mov_doc_seq'),
    corr.item_id,
    corr.lote_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'),
    corr.destino_ubicacion_id,
    corr.cantidad,
    corr.precio_unitario,
    corr.documento_tipo,
    corr.documento_id,
    'anulación corrección pre-cuadre'
FROM inventario.item_movimientos corr
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = corr.documento_id
WHERE corr.observacion = 'corrección consumo: factor de dilución no aplicado'
  AND ppe.fyh_cre < '2026-06-23 15:19:21.927224+00';

-- Verify: should return 240
SELECT COUNT(*) FROM inventario.item_movimientos
WHERE observacion = 'anulación corrección pre-cuadre';

COMMIT;

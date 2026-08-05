-- ═══════════════════════════════════════════════════════════════════════════════
-- 35 · Collapse doc.orden_servicio → doc.entrega (INGRESO_INTERNO)
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY: orden_servicio was a compra-style order/receipt split for MLR-confected
-- rolls. In practice it was always filled out and received in one sitting — the
-- order/receipt distinction provided zero value. All its mechanics (ledger,
-- reversal, roll creation) are already handled by the entrega layer. The one
-- genuine value (partida spec per line) now flows directly through
-- crear_ingreso_interno into lrd/partida without an intermediate document.
--
-- What changes:
--   • New entrega_tipo: INGRESO_INTERNO (flg_emitida=false, moves=SERV_ING).
--   • One synthetic entrega per existing OS; serie='OS-<os.id>', correlativo=os.factura.
--   • All lrd.orden_servicio_id rows repointed → lrd.entrega_id.
--   • lote.documento_tipo/id repointed 'orden_servicio' → 'entrega'.
--   • item_movimientos repointed likewise; entrega_detalle lines created.
--   • Columns lrd.orden_servicio_id, lrd.factura_hilo dropped.
--   • entrega_id promoted to NOT NULL on lrd.
--   • Tables orden_servicio_detalle, orden_servicio dropped.
--
-- Sequence:
--   1. New entrega_tipo row.
--   2. Backfill loop (synthetic entrega + entrega_detalle + repoint).
--   3. Verification guard.
--   4. Schema cleanup.
--
-- After running: redeploy funciones/core.sql (drops old OS functions, adds
--   crear_ingreso_interno). Redeploy funciones/core.sql ONLY AFTER this patch.
-- ═══════════════════════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════════
-- DRY RUN · patch 35_collapse_orden_servicio
-- ══════════════════════════════════════════════════════════════════

-- ── §1 · entrega_tipo to be inserted ────────────────────────────
-- Should return 1 row if INGRESO_INTERNO doesn't exist yet,
-- 0 if it was already inserted (ON CONFLICT DO NOTHING would skip).
SELECT
    'INGRESO_INTERNO'                   AS codigo,
    'Ingreso Interno MLR'               AS nombre,
    false                               AS flg_emitida,
    false                               AS flg_cliente,
    imt.id                              AS item_movimiento_tipo_id,
    NOT EXISTS (
        SELECT 1 FROM doc.entrega_tipo WHERE codigo = 'INGRESO_INTERNO'
    )                                   AS would_insert
FROM inventario.item_movimiento_tipo imt
WHERE imt.codigo = 'SERV_ING';


-- ── §2a · Synthetic entrega to be created — one row per OS ──────
SELECT
    os.id                                                           AS os_id,
    os.tercero_id,
    os.factura,
    os.fecha_emision,
    CASE WHEN os.factura IS NOT NULL
         THEN 'OS-' || os.id::TEXT ELSE NULL END                   AS serie_new,
    os.factura                                                      AS correlativo_new,
    COUNT(lrd.lote_id)
        FILTER (WHERE l.fyh_elm IS NULL)                           AS rollos_vivos,
    COUNT(lrd.lote_id)
        FILTER (WHERE l.fyh_elm IS NOT NULL)                       AS rollos_revertidos,
    COUNT(lrd.lote_id)                                             AS rollos_total
FROM doc.orden_servicio os
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.orden_servicio_id = os.id
LEFT JOIN inventario.lote               l   ON l.id = lrd.lote_id
GROUP BY os.id, os.tercero_id, os.factura, os.fecha_emision
ORDER BY os.id;


-- ── §2b · lrd rows to be repointed (entrega_id) ─────────────────
SELECT
    lrd.lote_id,
    l.id                    AS lote_id_check,
    lrd.orden_servicio_id   AS os_id,
    lrd.entrega_id          AS entrega_id_current,     -- expect NULL or old value
    l.fyh_elm IS NOT NULL   AS is_reversed,
    im.documento_tipo       AS im_doc_tipo_current,
    im.documento_id         AS im_doc_id_current
FROM inventario.lote_rollo_detalle lrd
JOIN inventario.lote              l  ON l.id  = lrd.lote_id
LEFT JOIN inventario.item_movimientos im
       ON im.lote_id        = l.id
      AND im.documento_tipo = 'orden_servicio'
      AND im.documento_id   = lrd.orden_servicio_id
WHERE lrd.orden_servicio_id IS NOT NULL
ORDER BY lrd.orden_servicio_id, l.id;


-- ── §2c · item_movimientos to be repointed ───────────────────────
SELECT
    im.id,
    im.lote_id,
    im.documento_tipo,
    im.documento_id,
    im.documento_linea_id,
    imt.codigo              AS movimiento_tipo,
    os.id                   AS os_id,
    os.factura
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
JOIN doc.orden_servicio             os  ON os.id   = im.documento_id
WHERE im.documento_tipo = 'orden_servicio'
ORDER BY os.id, im.lote_id, im.id;


-- ── §2d · lote rows to be repointed (documento_tipo/id) ─────────
SELECT
    l.id            AS lote_id,
    l.documento_tipo,
    l.documento_id,
    lrd.orden_servicio_id
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE l.documento_tipo = 'orden_servicio'
ORDER BY lrd.orden_servicio_id, l.id;


-- ── §3 · Verification preview (should both be 0) ────────────────
SELECT
    (SELECT COUNT(*)
     FROM inventario.lote_rollo_detalle
     WHERE orden_servicio_id IS NOT NULL
       AND entrega_id IS NULL)          AS orphan_lrd_after_backfill,   -- expect 0

    (SELECT COUNT(*)
     FROM inventario.item_movimientos
     WHERE documento_tipo = 'orden_servicio')  AS stale_movements_after_backfill; -- expect 0
-- (Both will still show non-zero NOW since backfill hasn't run yet;
--  use these to see the current count, not the post-migration count.)


-- ── Summary ──────────────────────────────────────────────────────
SELECT
    (SELECT COUNT(*) FROM doc.orden_servicio)                       AS os_count,
    (SELECT COUNT(*) FROM inventario.lote_rollo_detalle
     WHERE orden_servicio_id IS NOT NULL)                           AS lrd_to_repoint,
    (SELECT COUNT(*) FROM inventario.item_movimientos
     WHERE documento_tipo = 'orden_servicio')                       AS movements_to_repoint,
    (SELECT COUNT(*) FROM inventario.lote
     WHERE documento_tipo = 'orden_servicio')                       AS lotes_to_repoint;


ROLLBACK;

BEGIN;

-- ── §0 · Data fix: normalize free-text factura → clean invoice reference ─────
-- One OS row has a long free-text value ("20/1 PC 6535=201 10/1 PC 6535=2024").
-- Parse out the two invoice numbers so the backfill stores a clean correlativo.
UPDATE doc.orden_servicio
SET    factura = '201/2024'
WHERE  factura ILIKE '%20/1%PC%6535%';

-- ── §1 · entrega_tipo: INGRESO_INTERNO ──────────────────────────────────────
INSERT INTO doc.entrega_tipo (codigo, nombre, flg_emitida, flg_cliente, item_movimiento_tipo_id)
SELECT 'INGRESO_INTERNO',
       'Ingreso Interno MLR',
       false,
       false,  -- internal document; no client counterparty
       imt.id
FROM   inventario.item_movimiento_tipo imt
WHERE  imt.codigo = 'SERV_ING'
ON CONFLICT (codigo) DO NOTHING;

-- ── §2 · Backfill: set-based ────────────────────────────────────────────────
DO $$
DECLARE v_ent_tipo_id SMALLINT;
BEGIN
    SELECT id INTO STRICT v_ent_tipo_id FROM doc.entrega_tipo WHERE codigo = 'INGRESO_INTERNO';

    -- 2a · One entrega per OS; serie='OS-<os.id>' is the durable mapping key
    INSERT INTO doc.entrega (entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, usr_cre, fyh_cre)
    SELECT v_ent_tipo_id, 1,
           CASE WHEN factura IS NOT NULL THEN 'OS-' || id::TEXT ELSE NULL END,
           factura, fecha_emision, usr_cre, fyh_cre
    FROM   doc.orden_servicio
    ORDER  BY id;

    -- 2b · entrega_detalle — one line per live roll, linea numbered per entrega
    INSERT INTO doc.entrega_detalle (entrega_id, linea, lote_id, item_id, cantidad, ubicacion_id)
    SELECT e.id,
           ROW_NUMBER() OVER (PARTITION BY e.id ORDER BY l.id)::SMALLINT,
           l.id, l.item_id, l.cantidad,
           (SELECT COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id)
            FROM   inventario.item_movimientos im
            WHERE  im.lote_id        = l.id
              AND  im.documento_tipo = 'orden_servicio'
            LIMIT  1)
    FROM   doc.entrega e
    JOIN   inventario.lote_rollo_detalle lrd ON e.serie = 'OS-' || lrd.orden_servicio_id::TEXT
    JOIN   inventario.lote l ON l.id = lrd.lote_id
    WHERE  e.entrega_tipo_id = v_ent_tipo_id
      AND  l.fyh_elm IS NULL;

    -- 2c · Repoint lrd.entrega_id
    UPDATE inventario.lote_rollo_detalle lrd
    SET    entrega_id = e.id
    FROM   doc.entrega e
    WHERE  e.entrega_tipo_id = v_ent_tipo_id
      AND  e.serie           = 'OS-' || lrd.orden_servicio_id::TEXT;

    -- 2d · Repoint lote (propietario_id NULL = MLR-owned)
    UPDATE inventario.lote l
    SET    documento_tipo = 'entrega',
           documento_id   = e.id,
           propietario_id = NULL
    FROM   inventario.lote_rollo_detalle lrd
    JOIN   doc.entrega e ON e.entrega_tipo_id = v_ent_tipo_id
                        AND e.serie = 'OS-' || lrd.orden_servicio_id::TEXT
    WHERE  lrd.lote_id = l.id;

    -- 2e · Repoint item_movimientos with documento_tipo='orden_servicio'
    UPDATE inventario.item_movimientos im
    SET    documento_tipo     = 'entrega',
           documento_id       = e.id,
           documento_linea_id = (SELECT ed.id FROM doc.entrega_detalle ed
                                 WHERE ed.entrega_id = e.id AND ed.lote_id = im.lote_id)
    FROM   doc.entrega e
    WHERE  e.entrega_tipo_id = v_ent_tipo_id
      AND  im.documento_tipo = 'orden_servicio'
      AND  e.serie           = 'OS-' || im.documento_id::TEXT;
END;
$$;

-- ── §3 · Verification: no OS roll left without entrega_id ───────────────────
DO $$
DECLARE v_orphans INT;
BEGIN
    SELECT COUNT(*) INTO v_orphans
    FROM   inventario.lote_rollo_detalle
    WHERE  orden_servicio_id IS NOT NULL
      AND  entrega_id        IS NULL;

    IF v_orphans > 0 THEN
        RAISE EXCEPTION
            'Migration aborted: % lrd row(s) have orden_servicio_id but no entrega_id. '
            'Check for lotes missing item_movimientos.',
            v_orphans;
    END IF;
END;
$$;

-- Also verify no 'orden_servicio' movements remain
DO $$
DECLARE v_stale INT;
BEGIN
    SELECT COUNT(*) INTO v_stale
    FROM   inventario.item_movimientos
    WHERE  documento_tipo = 'orden_servicio';

    IF v_stale > 0 THEN
        RAISE EXCEPTION
            'Migration aborted: % item_movimientos row(s) still reference documento_tipo=''orden_servicio''.',
            v_stale;
    END IF;
END;
$$;

-- ── §4 · Schema cleanup ──────────────────────────────────────────────────────

-- Drop views that reference orden_servicio_id / factura_hilo before column removal
DROP VIEW IF EXISTS doc.vw_ordenes_servicio;                    -- retiring with OS table
DROP VIEW IF EXISTS doc.vw_pendientes_proceso;                  -- rewritten below
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_disponibles;     -- depends on stock view
DROP VIEW IF EXISTS inventario.vw_lotes_rollos_stock;           -- has OS join

-- Drop constraint referencing both columns before dropping either column
ALTER TABLE inventario.lote_rollo_detalle
    DROP CONSTRAINT IF EXISTS chk_lrd_doc_origen;

DROP INDEX IF EXISTS inventario.idx_lrd_orden_servicio_id;

-- Revoke that referenced the soon-dropped column (ignore if already gone)
REVOKE UPDATE (orden_servicio_id) ON inventario.lote_rollo_detalle FROM anon, authenticated;

ALTER TABLE inventario.lote_rollo_detalle
    DROP COLUMN IF EXISTS orden_servicio_id,
    DROP COLUMN IF EXISTS factura_hilo;

-- entrega_id NOT NULL skipped — some legacy lrd rows have no ingress document.
-- Enforce once orphans are identified and resolved in a follow-up patch.

-- Recreate views — lrd.entrega_id is now the unified origin for all roll types
CREATE OR REPLACE VIEW inventario.vw_lotes_rollos_stock AS
SELECT
    sa.lote_id,
    sa.item_id,
    i.codigo                        AS item_codigo,
    i.nombre                        AS item_nombre,
    sa.ubicacion_id,
    u.nombre                        AS ubicacion,
    a.nombre                        AS almacen,
    sa.cantidad_disponible,
    un.codigo                       AS unidad,
    l.estado_calidad::text,
    l.cantidad                      AS peso,
    ird.articulo_id,
    art.nombre                      AS articulo_nombre,
    art.articulo_tipo_id,
    ird.flg_rib,
    art.fibra,
    lrd.flg_tenido,
    lrd.flg_antipilling,
    lrd.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.cliente_id,
    vc.color_hex,
    vc.color_x_cliente_hex,
    lrd.tenido_id,
    tn.tenido,
    lrd.ancho,
    lrd.malla,
    lrd.rendimiento,
    l.propietario_id,
    t.nombre                        AS propietario,
    lrd.entrega_id,
    gr.serie                        AS entrega_serie,
    gr.correlativo                  AS entrega_correlativo
FROM inventario.vw_stock_lotes_ubicacion sa
JOIN inventario.lote l                      ON l.id = sa.lote_id
JOIN item i                                 ON i.id = sa.item_id
JOIN item_tipo it                           ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN item_rollo_detalle ird                 ON ird.item_id = i.id
JOIN articulo art                           ON art.id = ird.articulo_id
JOIN unidad un                              ON un.id = i.unidad_id
LEFT JOIN inventario.ubicacion u            ON u.id = sa.ubicacion_id
LEFT JOIN inventario.almacen a              ON a.id = u.almacen_id
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = sa.lote_id
LEFT JOIN doc.entrega gr                    ON gr.id = lrd.entrega_id
LEFT JOIN tercero t                         ON t.id = l.propietario_id
LEFT JOIN vw_colores vc                     ON vc.color_x_cliente_id = lrd.color_x_cliente_id
LEFT JOIN tenido tn                         ON tn.id = lrd.tenido_id;

CREATE OR REPLACE VIEW inventario.vw_lotes_rollos_disponibles AS
SELECT s.*
FROM inventario.vw_lotes_rollos_stock s
WHERE NOT EXISTS (
    SELECT 1 FROM mes.partida_componente pc
    JOIN mes.partida p ON p.id = pc.partida_id
    WHERE pc.lote_id = s.lote_id
      AND p.estado_produccion NOT IN ('CERRADA', 'CANCELADA')
      AND p.fyh_elm IS NULL
);

CREATE OR REPLACE VIEW doc.vw_pendientes_proceso AS
WITH rollos AS (
    SELECT
        lrd.entrega_id,
        gr.serie || '-' || COALESCE(gr.correlativo, gr.id::text) AS documento,
        gr.fecha_emision::date                                    AS fecha_emision,
        gr.tercero_id,
        tg.nombre                                                 AS cliente,
        ird.articulo_id,
        art.nombre                                                AS articulo,
        art.articulo_tipo_id,
        at.nombre                                                 AS articulo_tipo,
        art.fibra,
        l.cantidad                                                AS peso_kg,
        lrd.flg_tenido,
        lrd.origen_lote_id,
        EXISTS (
            SELECT 1
            FROM mes.partida_componente pc
            JOIN mes.partida p ON p.id = pc.partida_id
            WHERE pc.lote_id = l.id
              AND pc.item_id IS NULL
              AND p.estado_produccion NOT IN ('TECO', 'CERRADA', 'CANCELADA')
              AND p.fyh_elm IS NULL
        )                                                         AS asignado
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id
    JOIN inventario.vw_stock_lotes sl       ON sl.lote_id = l.id
    LEFT JOIN item_rollo_detalle ird        ON ird.item_id = l.item_id
    LEFT JOIN articulo art                  ON art.id = ird.articulo_id
    LEFT JOIN articulo_tipo at              ON at.id = art.articulo_tipo_id
    LEFT JOIN doc.entrega gr                ON gr.id = lrd.entrega_id
    LEFT JOIN tercero tg                    ON tg.id = gr.tercero_id
    WHERE l.fyh_elm IS NULL
      AND gr.fyh_elm IS NULL
      AND lrd.entrega_id IS NOT NULL
)
SELECT
    entrega_id,
    documento,
    fecha_emision,
    tercero_id,
    cliente,
    articulo_id,
    articulo,
    articulo_tipo_id,
    articulo_tipo,
    fibra,
    COUNT(*)                                 AS rollos_en_stock,
    COUNT(*) FILTER (WHERE NOT asignado)     AS rollos_sin_asignar,
    COUNT(*) FILTER (WHERE asignado)         AS rollos_asignados_pendientes,
    COUNT(*) FILTER (WHERE NOT flg_tenido)   AS rollos_sin_tenir,
    ROUND(SUM(peso_kg)::numeric, 2)          AS kg_en_stock
FROM rollos
WHERE origen_lote_id IS NULL
   OR asignado
GROUP BY
    entrega_id, documento, fecha_emision, tercero_id, cliente,
    articulo_id, articulo, articulo_tipo_id, articulo_tipo, fibra;

GRANT SELECT ON inventario.vw_lotes_rollos_stock      TO anon, authenticated;
GRANT SELECT ON inventario.vw_lotes_rollos_disponibles TO anon, authenticated;
GRANT SELECT ON doc.vw_pendientes_proceso              TO authenticated;

-- -- Drop OS tables (cascade drops their FKs and indexes)
-- DROP VIEW  IF EXISTS doc.vw_ordenes_servicio                 CASCADE;
-- DROP TABLE IF EXISTS doc.orden_servicio_detalle              CASCADE;
-- DROP TABLE IF EXISTS doc.orden_servicio                      CASCADE;

COMMIT;

-- ── §5 · Post-steps (after COMMIT) ──────────────────────────────────────────
-- 1. Redeploy funciones/core.sql  — drops old OS functions, adds crear_ingreso_interno.
-- 2. Drop stale function signatures from the live DB:
--      DROP FUNCTION IF EXISTS doc.crear_orden_servicio(jsonb);
--      DROP FUNCTION IF EXISTS doc.ingresar_orden_servicio(jsonb);
--      DROP FUNCTION IF EXISTS doc.revertir_recepcion_orden_servicio(jsonb);
--      DROP FUNCTION IF EXISTS doc.actualizar_orden_servicio(bigint, jsonb);
--      DROP FUNCTION IF EXISTS doc.get_orden_servicio(bigint);

-- ── §5a · Orphan lrd diagnostic (run after COMMIT to investigate) ───────────
-- These rolls have no ingress document — they need a follow-up cleanup patch
-- before entrega_id NOT NULL can be enforced.
SELECT
    lrd.lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.fyh_cre,
    l.fyh_elm,
    l.documento_tipo,
    l.documento_id,
    array_agg(DISTINCT im.documento_tipo) FILTER (WHERE im.id IS NOT NULL) AS movimiento_tipos
FROM inventario.lote_rollo_detalle lrd
JOIN inventario.lote l ON l.id = lrd.lote_id
LEFT JOIN inventario.item_movimientos im ON im.lote_id = l.id
WHERE lrd.entrega_id IS NULL
GROUP BY lrd.lote_id, l.fyh_cre, l.fyh_elm, l.secuencia, l.documento_tipo, l.documento_id
ORDER BY l.fyh_cre;



-- SELECT 
--     lrd.orden_servicio_id,
--     COUNT(*)                                                      AS total_lrd,
--     COUNT(im.id) FILTER (WHERE im.documento_tipo = 'orden_servicio') AS with_serv_mov,
--     COUNT(*) FILTER (WHERE im.id IS NULL OR 
--                      im.documento_tipo != 'orden_servicio')       AS missing_serv_mov,
--     array_agg(DISTINCT im.documento_tipo) FILTER (WHERE im.id IS NOT NULL) AS other_doc_tipos
-- FROM inventario.lote_rollo_detalle lrd
-- JOIN inventario.lote l ON l.id = lrd.lote_id
-- LEFT JOIN inventario.item_movimientos im ON im.lote_id = l.id
-- WHERE lrd.orden_servicio_id IS NOT NULL
-- GROUP BY lrd.orden_servicio_id
-- ORDER BY lrd.orden_servicio_id;



SELECT COUNT(*) FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE et.codigo = 'INGRESO_INTERNO';

SELECT COUNT(*) FROM inventario.lote_rollo_detalle WHERE entrega_id IS NULL;

SELECT column_name FROM information_schema.columns
WHERE table_schema = 'inventario' AND table_name = 'lote_rollo_detalle'
  AND column_name IN ('orden_servicio_id', 'factura_hilo');



SELECT * FROM inventario.vw_lotes_rollos_despachados WHERE entrega_id IS NOT NULL




SELECT * FROM doc.entrega_tipo
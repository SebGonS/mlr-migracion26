-- 59_bare_venta_ghost_entregas.sql   ⚠ review before running (data insert)
--
-- (b) of the ghost cleanup: the ~30 entregas with a real SERV_EGR dispatch but no
-- linked venta (entrega.venta_id NULL, rolls out of stock). Gives each a BARE venta
-- so it leaves the "ghost" set — item lines (what/how much/which articulo went out)
-- but NO cargo (price unrecorded; legacy had no rate for these — per user).
--
-- One venta per ghost entrega (the entrega IS the dispatch). referencia = the
-- entrega's guía serie/correlativo (may be NULL). tipo=SERVICIO (SERV_EGR = client
-- material). Item lines grouped by (articulo × tenido × color) from the dispatched
-- rolls; dims from the rolls' partida, articulo from item_rollo_detalle. No price.
--
-- ⚠ §0 read-only → §1 in a txn → §2 verify → COMMIT.

-- ══════════════════════════════════════════════════════════════════════════
-- §0 · PRE-CHECK (read only)
-- ══════════════════════════════════════════════════════════════════════════
WITH ghost AS (
  SELECT DISTINCT im.lote_id, im.documento_id AS entrega_id
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
  JOIN doc.entrega e ON e.id=im.documento_id AND im.documento_tipo='entrega'
  WHERE imt.codigo='SERV_EGR' AND e.venta_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM inventario.vw_stock_lotes sl WHERE sl.lote_id=im.lote_id)
)
SELECT COUNT(DISTINCT entrega_id) AS ghost_entregas_expect_30,
       COUNT(DISTINCT lote_id)    AS ghost_lotes
FROM ghost;


-- ══════════════════════════════════════════════════════════════════════════
-- §1 · Execute  (one transaction)
-- ══════════════════════════════════════════════════════════════════════════
BEGIN;
ALTER TABLE doc.venta         DISABLE TRIGGER trg_bi_venta_cre;
ALTER TABLE doc.venta         DISABLE TRIGGER trg_bu_venta_mod;
ALTER TABLE doc.venta         DISABLE TRIGGER trg_biud_venta_audit;
ALTER TABLE doc.venta_detalle DISABLE TRIGGER trg_biud_venta_detalle_audit;

DO $$
DECLARE r RECORD; v_venta_id bigint;
BEGIN
  FOR r IN
    SELECT e.id AS entrega_id, e.tercero_id, e.fecha_emision, e.serie, e.correlativo
    FROM doc.entrega e
    WHERE e.venta_id IS NULL
      AND EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
        WHERE im.documento_tipo='entrega' AND im.documento_id=e.id AND imt.codigo='SERV_EGR'
          AND NOT EXISTS (SELECT 1 FROM inventario.vw_stock_lotes sl WHERE sl.lote_id=im.lote_id))
  LOOP
    INSERT INTO doc.venta (tercero_id, fecha, referencia_serie, referencia_correlativo, observacion, usr_cre, fyh_cre)
    VALUES (r.tercero_id, COALESCE(r.fecha_emision::date, CURRENT_DATE), r.serie, r.correlativo,
            'Backfill bare venta — despacho físico sin venta comercial, sin tarifa (patch 59)', 4,
            COALESCE(r.fecha_emision, now()))
    RETURNING id INTO v_venta_id;

    UPDATE doc.entrega SET venta_id = v_venta_id WHERE id = r.entrega_id;

    -- item lines per (articulo × tenido × color); no cargo (no price)
    INSERT INTO doc.venta_detalle (venta_id, linea, tipo, articulo_id, color_x_cliente_id, tenido_id,
                                   grupo_articulo_id, partida_id, cantidad_kg, cantidad_rollos, usr_cre)
    SELECT v_venta_id,
           (row_number() OVER (ORDER BY ird.articulo_id, p.tenido_id, p.color_x_cliente_id))::smallint,
           'SERVICIO'::venta_linea_tipo_enum,
           ird.articulo_id, p.color_x_cliente_id, p.tenido_id, p.grupo_articulo_id,
           COALESCE(p.partida_origen_id, p.id),
           SUM(l.cantidad), COUNT(*), 4
    FROM doc.entrega_detalle ed
    JOIN inventario.lote l ON l.id = ed.lote_id
    LEFT JOIN public.item_rollo_detalle ird ON ird.item_id = l.item_id
    JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN mes.partida p ON p.id = pp.partida_id
    WHERE ed.entrega_id = r.entrega_id
    GROUP BY ird.articulo_id, p.color_x_cliente_id, p.tenido_id, p.grupo_articulo_id,
             COALESCE(p.partida_origen_id, p.id);
  END LOOP;
END $$;

ALTER TABLE doc.venta         ENABLE TRIGGER trg_bi_venta_cre;
ALTER TABLE doc.venta         ENABLE TRIGGER trg_bu_venta_mod;
ALTER TABLE doc.venta         ENABLE TRIGGER trg_biud_venta_audit;
ALTER TABLE doc.venta_detalle ENABLE TRIGGER trg_biud_venta_detalle_audit;


-- ══════════════════════════════════════════════════════════════════════════
-- §2 · VERIFY (before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════
-- -- the ghost entregas are now linked (expect 0 remaining)
SELECT COUNT(*) AS ghost_entregas_still_unlinked_expect_0
FROM doc.entrega e
WHERE e.venta_id IS NULL
  AND EXISTS (SELECT 1 FROM inventario.item_movimientos im
      JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
      WHERE im.documento_tipo='entrega' AND im.documento_id=e.id AND imt.codigo='SERV_EGR'
        AND NOT EXISTS (SELECT 1 FROM inventario.vw_stock_lotes sl WHERE sl.lote_id=im.lote_id));

-- new bare ventas + their lines (no cargo)
SELECT COUNT(*) AS bare_ventas FROM doc.venta WHERE observacion LIKE '%patch 59%';
SELECT COUNT(*) AS bare_lines,
       COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM doc.venta_detalle_cargo c WHERE c.venta_detalle_id=vd.id)) AS lines_with_cargo_expect_0
FROM doc.venta_detalle vd
JOIN doc.venta v ON v.id=vd.venta_id WHERE v.observacion LIKE '%patch 59%';

-- ══════════════════════════════════════════════════════════════════════════
-- COMMIT;   -- only after §2 checks out
-- ══════════════════════════════════════════════════════════════════════════

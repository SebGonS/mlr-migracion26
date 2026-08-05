-- 56_venta_detalle_item_grain.sql   ⚠ review before running
--
-- Reshapes doc.venta_detalle from charge-grain (one row per operación) to two
-- grains (VENTA_PER_ITEM_BILLING_SPEC.md):
--   • venta_detalle       = ITEM line, one per (articulo × tenido × color)
--   • venta_detalle_cargo  = CHARGE sub-line, one per (item × operación)  [NEW]
-- Weight/pieces on the item line; rate components in cargo (≈ SAP SD conditions).
-- entrega_detalle gets a nullable venta_detalle_id (traceability reference only).
--
-- ORDER MATTERS: fn_descripcion_linea + vw_venta + vw_partida_comercial depend on
-- the columns/function being changed, so §1 drops the two views FIRST, swaps the
-- function, recreates the views, THEN drops the columns. (The first run failed at
-- DROP FUNCTION because vw_venta still depended on it.)
--
-- NOT here (apply after; does not block the DDL): the reworked registrar_despacho
-- in funciones/despacho.sql — the OLD one inserts operacion_id/precio_kg and will
-- error once those columns drop, so re-apply despacho.sql before the app dispatches.
--
-- Kept vestigial (non-destructive): flg_antipilling, articulo_tipo_id on
-- venta_detalle. Antipilling is now operación 10 (a cargo).
--
-- ⚠ §0 read-only → §1 in a txn → uncomment §2 verify → COMMIT.

-- ══════════════════════════════════════════════════════════════════════════
-- §0 · PRE-CHECK (read only)
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  COUNT(*)                                         AS venta_detalle_rows,
  COUNT(*) FILTER (WHERE operacion_id IS NULL)     AS venta_lines_no_op,
  COUNT(*) FILTER (WHERE operacion_id IS NOT NULL) AS servicio_lines,
  COUNT(*) FILTER (WHERE precio_kg IS NULL)        AS null_precio_expect_0
FROM doc.venta_detalle;   -- each row → exactly one historical cargo (6716)


-- ══════════════════════════════════════════════════════════════════════════
-- §1 · Execute  (one transaction)
-- ══════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── 1a. New columns on the item line ────────────────────────────────────────
ALTER TABLE doc.venta_detalle
    ADD COLUMN IF NOT EXISTS articulo_id     INT REFERENCES public.articulo(id),
    ADD COLUMN IF NOT EXISTS cantidad_rollos INT;

-- ── 1b. New charge sub-line table ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS doc.venta_detalle_cargo (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venta_detalle_id BIGINT NOT NULL REFERENCES doc.venta_detalle(id) ON DELETE CASCADE,
    operacion_id     SMALLINT REFERENCES mes.operacion(id),   -- NULL = product/base price; else the charged op
    precio_kg        NUMERIC(12,4) NOT NULL CHECK (precio_kg >= 0),
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_venta_detalle_cargo_op UNIQUE NULLS NOT DISTINCT (venta_detalle_id, operacion_id)
);
CREATE INDEX IF NOT EXISTS idx_vdc_detalle ON doc.venta_detalle_cargo (venta_detalle_id);

-- ── 1c. Traceability reference on the physical line (many roll-lines → 1 charge) ─
ALTER TABLE doc.entrega_detalle
    ADD COLUMN IF NOT EXISTS venta_detalle_id BIGINT REFERENCES doc.venta_detalle(id);

-- ── 1d. History → one cargo per existing line (preserves the migrated price) ──
INSERT INTO doc.venta_detalle_cargo (venta_detalle_id, operacion_id, precio_kg, usr_cre, fyh_cre)
SELECT vd.id, vd.operacion_id, vd.precio_kg, 4, vd.fyh_cre
FROM doc.venta_detalle vd;
-- expect: cargo rows = venta_detalle rows (6716)

-- ── 1e. Drop the dependent views FIRST (they reference old fn + old columns) ──
DROP VIEW IF EXISTS doc.vw_venta;
DROP VIEW IF EXISTS mes.vw_partida_comercial;

-- ── 1f. Swap the description function ───────────────────────────────────────
DROP FUNCTION IF EXISTS doc.fn_descripcion_linea(venta_linea_tipo_enum, SMALLINT, INT, INT, INT, INT, BOOLEAN);
CREATE OR REPLACE FUNCTION doc.fn_descripcion_linea(
    p_tipo               venta_linea_tipo_enum,
    p_item_id            INT,
    p_articulo_id        INT,
    p_color_x_cliente_id INT,
    p_tenido_id          INT
) RETURNS TEXT LANGUAGE sql STABLE SET search_path TO 'public','mes','doc' AS $$
    SELECT CASE
        WHEN p_tipo = 'VENTA' THEN
            COALESCE((SELECT nombre FROM item WHERE id = p_item_id), 'Producto')
        ELSE
            TRIM(BOTH ' · ' FROM
                COALESCE((SELECT nombre FROM articulo WHERE id = p_articulo_id), '')
                || COALESCE(' · ' || (SELECT color FROM vw_colores WHERE color_x_cliente_id = p_color_x_cliente_id), '')
                || COALESCE(' · ' || (SELECT tenido FROM tenido WHERE id = p_tenido_id), '')
            )
    END;
$$;
GRANT EXECUTE ON FUNCTION doc.fn_descripcion_linea(venta_linea_tipo_enum, INT, INT, INT, INT) TO authenticated;

-- ── 1g. Recreate vw_venta (item line + cargo aggregate + breakdown) ─────────
CREATE VIEW doc.vw_venta AS
SELECT
    v.id AS venta_id, v.tercero_id, t.nombre AS cliente, v.fecha,
    v.referencia_serie, v.referencia_correlativo,
    vd.id AS detalle_id, vd.linea, vd.tipo,
    vd.item_id, it.nombre AS item_nombre,
    vd.articulo_id, art.nombre AS articulo,
    vd.partida_id, pcod.codigo AS partida_codigo,
    vd.color_x_cliente_id, vc.color, vd.tenido_id, ten.tenido,
    vd.grupo_articulo_id, ga.nombre AS grupo_articulo,
    vd.cantidad_kg, vd.cantidad_rollos,
    cg.precio_kg_total,
    ROUND(vd.cantidad_kg * COALESCE(cg.precio_kg_total,0), 2) AS importe,
    cg.cargos,
    COALESCE(vd.descripcion, doc.fn_descripcion_linea(
        vd.tipo, vd.item_id, vd.articulo_id, vd.color_x_cliente_id, vd.tenido_id)) AS descripcion
FROM doc.venta v
JOIN tercero t ON t.id = v.tercero_id
LEFT JOIN doc.venta_detalle vd ON vd.venta_id = v.id
LEFT JOIN LATERAL (
    SELECT SUM(c.precio_kg) AS precio_kg_total,
           jsonb_agg(jsonb_build_object(
               'operacion_id', c.operacion_id,
               'operacion',    (SELECT nombre FROM mes.operacion WHERE id = c.operacion_id),
               'precio_kg',    c.precio_kg) ORDER BY c.operacion_id NULLS FIRST) AS cargos
    FROM doc.venta_detalle_cargo c WHERE c.venta_detalle_id = vd.id
) cg ON true
LEFT JOIN public.articulo art ON art.id = vd.articulo_id
LEFT JOIN item it ON it.id = vd.item_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = vd.color_x_cliente_id
LEFT JOIN tenido ten ON ten.id = vd.tenido_id
LEFT JOIN grupo_articulo ga ON ga.id = vd.grupo_articulo_id
LEFT JOIN LATERAL (
    SELECT EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo
    FROM mes.partida p WHERE p.id = vd.partida_id
) pcod ON true
WHERE v.flg_elm = false;
GRANT SELECT ON doc.vw_venta TO authenticated;

-- ── 1h. Recreate vw_partida_comercial (importe now = kg × Σcargo) ───────────
CREATE VIEW mes.vw_partida_comercial AS
WITH terminal AS (
    SELECT root_id, lote_id FROM mes.vw_partida_familia_output WHERE estado_calidad = 'APROBADO'
),
fulfillment AS (
    SELECT t.root_id, COUNT(*) AS total_terminal,
        COUNT(*) FILTER (
            WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = t.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR'))
            AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im2
                JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                WHERE im2.lote_id = t.lote_id AND imt2.codigo IN ('SERV_DEV_ING','DEV_CLI_ING'))
        ) AS dispatched_ahora
    FROM terminal t GROUP BY t.root_id
)
SELECT
    p.id AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo,
    p.tercero_id, c.nombre AS cliente,
    p.estado_comercial AS estado_comercial_cache,
    COALESCE(f.total_terminal, 0) AS total_terminal,
    COALESCE(f.dispatched_ahora, 0) AS dispatched_ahora,
    GREATEST(0, COALESCE(f.total_terminal, 0) - COALESCE(f.dispatched_ahora, 0)) AS pendiente,
    v.venta_ids, v.referencia_refs, v.total_kg_facturado, v.total_importe
FROM mes.partida p
JOIN tercero c ON c.id = p.tercero_id
LEFT JOIN fulfillment f ON f.root_id = p.id
LEFT JOIN LATERAL (
    SELECT jsonb_agg(DISTINCT vd.venta_id) AS venta_ids,
        jsonb_agg(DISTINCT (ve.referencia_serie || '-' || ve.referencia_correlativo))
            FILTER (WHERE ve.referencia_serie IS NOT NULL) AS referencia_refs,
        SUM(vd.cantidad_kg) AS total_kg_facturado,
        SUM(vd.cantidad_kg * COALESCE(
            (SELECT SUM(c.precio_kg) FROM doc.venta_detalle_cargo c WHERE c.venta_detalle_id = vd.id), 0
        )) AS total_importe
    FROM doc.venta_detalle vd
    JOIN doc.venta ve ON ve.id = vd.venta_id AND ve.flg_elm = false
    WHERE vd.partida_id = p.id
) v ON true
WHERE p.partida_origen_id IS NULL AND p.fyh_elm IS NULL;
GRANT SELECT ON mes.vw_partida_comercial TO authenticated;

-- ── 1i. Drop the columns that moved to cargo / are now recomputed ───────────
ALTER TABLE doc.venta_detalle
    DROP COLUMN IF EXISTS importe,       -- was GENERATED (cantidad_kg*precio_kg)
    DROP COLUMN IF EXISTS precio_kg,     -- → venta_detalle_cargo.precio_kg
    DROP COLUMN IF EXISTS operacion_id;  -- → venta_detalle_cargo.operacion_id


-- ══════════════════════════════════════════════════════════════════════════
-- §2 · VERIFY (uncomment; run before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════
SELECT (SELECT COUNT(*) FROM doc.venta_detalle)       AS lineas,
       (SELECT COUNT(*) FROM doc.venta_detalle_cargo) AS cargos_expect_equal;
SELECT
  COUNT(*) FILTER (WHERE column_name IN ('operacion_id','precio_kg','importe')) AS old_expect_0,
  COUNT(*) FILTER (WHERE column_name IN ('articulo_id','cantidad_rollos'))       AS new_expect_2
FROM information_schema.columns WHERE table_schema='doc' AND table_name='venta_detalle';
SELECT venta_id, detalle_id, cantidad_kg, precio_kg_total, importe, cargos
FROM doc.vw_venta WHERE venta_id = 1 ORDER BY linea LIMIT 5;
SELECT COUNT(*) FROM mes.vw_partida_comercial;

-- ══════════════════════════════════════════════════════════════════════════
-- COMMIT;   -- only after §2 checks out
-- ══════════════════════════════════════════════════════════════════════════

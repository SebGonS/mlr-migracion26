-- 55_venta_drop_factura_estado.sql
--
-- Completes the venta reframe (outflow register, not AR). Removes the invoice
-- scaffolding now that `referencia_serie/correlativo` (patch 54) is the reference:
--   • factura_serie / factura_numero / factura_fecha_venc  (columns)
--   • estado + venta_estado_enum                            (no lifecycle; void = soft-delete)
--   • uq_venta_factura (global unique) + idx_venta_abierta  (indexes)
--   • chk_venta_factura_fields                              (constraint)
--   • facturar_venta(BIGINT,TEXT,INT,DATE)                  (old fn → asignar_referencia_venta)
--
-- DEPENDS ON PATCH 54 (referencia columns must already exist and be backfilled).
--
-- SELF-CONTAINED: §1 first redefines the two views that DEPEND on the columns
-- being dropped (Postgres blocks DROP COLUMN on view deps — this is what failed
-- when the drops were run alone). Views are the ONLY hard blocker; the 3 reworked
-- FUNCTIONS do not block the DDL (Postgres doesn't track function-body column
-- deps) so they apply independently — see the FUNCTIONS note at the end. The
-- view bodies below mirror migration/08_views.sql exactly.
--
-- ⚠ DRY-RUN §0 → run §1 in a txn → §2 verify → COMMIT.  Then apply functions.

-- ══════════════════════════════════════════════════════════════════════════
-- §0 · PRE-CHECK (read only) — referencia backfill from patch 54 is present
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  COUNT(*)                                              AS ventas,
  COUNT(*) FILTER (WHERE referencia_serie IS NOT NULL)  AS con_referencia,
  bool_or(referencia_serie IS NOT NULL)                 AS patch54_applied_expect_true
FROM doc.venta;   -- expect con_referencia >= 2115


-- ══════════════════════════════════════════════════════════════════════════
-- §1 · Execute  (one transaction)
-- ══════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── 1a. Redefine the dependent views OFF the doomed columns (unblocks drops) ──
DROP VIEW IF EXISTS mes.vw_partida_comercial;
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
        SUM(vd.importe) AS total_importe
    FROM doc.venta_detalle vd
    JOIN doc.venta ve ON ve.id = vd.venta_id AND ve.flg_elm = false
    WHERE vd.partida_id = p.id
) v ON true
WHERE p.partida_origen_id IS NULL AND p.fyh_elm IS NULL;
GRANT SELECT ON mes.vw_partida_comercial TO authenticated;

DROP VIEW IF EXISTS doc.vw_venta;
CREATE VIEW doc.vw_venta AS
SELECT
    v.id AS venta_id, v.tercero_id, t.nombre AS cliente, v.fecha,
    v.referencia_serie, v.referencia_correlativo,
    vd.id AS detalle_id, vd.linea, vd.tipo, vd.operacion_id, op.nombre AS operacion_nombre,
    vd.item_id, it.nombre AS item_nombre, vd.partida_id, pcod.codigo AS partida_codigo,
    vd.color_x_cliente_id, vc.color, vd.tenido_id, ten.tenido,
    vd.grupo_articulo_id, ga.nombre AS grupo_articulo, vd.flg_antipilling,
    COALESCE(vd.descripcion, doc.fn_descripcion_linea(
        vd.tipo, vd.operacion_id, vd.item_id, vd.grupo_articulo_id,
        vd.color_x_cliente_id, vd.tenido_id, vd.flg_antipilling)) AS descripcion,
    vd.cantidad_kg, vd.precio_kg, vd.importe
FROM doc.venta v
JOIN tercero t ON t.id = v.tercero_id
LEFT JOIN doc.venta_detalle vd ON vd.venta_id = v.id
LEFT JOIN mes.operacion op ON op.id = vd.operacion_id
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

-- ── 1b. Drop the invoice scaffolding ─────────────────────────────────────────
DROP FUNCTION IF EXISTS doc.facturar_venta(BIGINT, TEXT, INT, DATE);
DROP INDEX    IF EXISTS doc.uq_venta_factura;
DROP INDEX    IF EXISTS doc.idx_venta_abierta;
ALTER TABLE doc.venta DROP CONSTRAINT IF EXISTS chk_venta_factura_fields;
ALTER TABLE doc.venta
    DROP COLUMN IF EXISTS factura_serie,
    DROP COLUMN IF EXISTS factura_numero,
    DROP COLUMN IF EXISTS factura_fecha_venc,
    DROP COLUMN IF EXISTS estado;
DROP TYPE IF EXISTS venta_estado_enum;   -- unreferenced after the above


-- ══════════════════════════════════════════════════════════════════════════
-- §2 · VERIFY (before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  COUNT(*) FILTER (WHERE column_name IN ('factura_serie','factura_numero','factura_fecha_venc','estado')) AS old_cols_expect_0,
  COUNT(*) FILTER (WHERE column_name IN ('referencia_serie','referencia_correlativo'))                    AS new_cols_expect_2
FROM information_schema.columns WHERE table_schema='doc' AND table_name='venta';

SELECT to_regtype('venta_estado_enum') IS NOT NULL AS enum_still_exists_expect_false;
SELECT COUNT(*) FROM doc.vw_venta;               -- resolves
SELECT COUNT(*) FROM mes.vw_partida_comercial;   -- resolves

-- ══════════════════════════════════════════════════════════════════════════
-- COMMIT;   -- only after §2 checks out
-- ══════════════════════════════════════════════════════════════════════════

-- ── FUNCTIONS (apply separately; order-independent — they don't block the DDL) ─
-- Re-apply funciones/despacho.sql (idempotent CREATE OR REPLACE) to install the
-- 3 reworked functions before the app is brought back up:
--   • registrar_despacho        (one venta per dispatch; referencia from input)
--   • asignar_referencia_venta   (replaces facturar_venta; sets referencia)
--   • anular_venta               (void = soft-delete flg_elm)
-- They reference referencia_* (exists post-54) and no longer touch factura_*/estado.

-- ============================================================================
-- DISPATCH MODULE
-- ============================================================================
-- doc.vw_despacho_pendiente  — listing view: partidas with dyed stock pending dispatch
-- doc.get_despacho_partida   — detail function: pre-built payload for crear_guia
--
-- Flow:
--   1. Frontend queries vw_despacho_pendiente to list dispatchable partidas.
--   2. User selects a partida → frontend calls get_despacho_partida(partida_id).
--   3. Function returns pre-grouped guia payloads (one per propietario group).
--   4. Frontend lets user filter/adjust lotes, add serie/correlativo/fecha_emision.
--   5. Frontend calls doc.crear_guia once per guia payload.
--
-- propietario split:
--   • propietario_id = 1 (MLR-owned rolls — MLR/* or OSWALDO/* clients) → VENTA_EGRESO
--   • propietario_id ≠ 1 (client-owned rolls)                          → DESPACHO_CLIENTE
-- ============================================================================


-- ── doc.vw_despacho_pendiente ─────────────────────────────────────────────
-- Partidas that have dyed roll lotes with available stock not yet dispatched.
-- Query-driven: a partida appears iff SUM(cantidad_disponible) > 0 on its dyed lotes.
-- Partial dispatch is handled naturally — remaining lotes keep the partida in view.
-- tiene_mixto = true means two guias will be needed (MLR-owned + client-owned rolls).
-- ─────────────────────────────────────────────────────────────────────────


DROP VIEW IF EXISTS doc.vw_despacho_pendiente;
CREATE OR REPLACE VIEW doc.vw_despacho_pendiente AS
SELECT
    p.id                                                                            AS partida_id,
    p.numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                                     AS codigo,
    p.estado,
    p.tercero_id,
    t.nombre                                                                        AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.tono,
    p.fecha_acordada,
    COUNT(DISTINCT l.id)                                                            AS rolls_pendientes,
    ROUND(SUM(sa.cantidad_disponible)::NUMERIC, 2)                                  AS kg_pendientes,
    BOOL_OR(l.propietario_id = 1)                                                   AS tiene_rolls_mlr,
    BOOL_OR(l.propietario_id IS DISTINCT FROM 1)                                    AS tiene_rolls_cliente,
    (BOOL_OR(l.propietario_id = 1)
     AND BOOL_OR(l.propietario_id IS DISTINCT FROM 1))                              AS tiene_mixto
FROM mes.partida p
JOIN tercero t                      ON t.id                    = p.tercero_id
LEFT JOIN vw_colores vc             ON vc.color_x_cliente_id   = p.color_x_cliente_id
JOIN mes.partida op        ON op.partida_id           = p.id
JOIN mes.partida_paso opp  ON opp.partida_id = op.id
JOIN inventario.lote l
    ON  l.documento_tipo = 'partida_paso'
    AND l.documento_id   = opp.id
JOIN inventario.lote_rollo_detalle lrd
    ON  lrd.lote_id    = l.id
    AND lrd.flg_tenido = true           -- dyed rolls only
JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id  -- vw_stock_actual already excludes 0-balance lotes
GROUP BY
    p.id, p.numero, p.estado, p.tercero_id, t.nombre,
    p.color_x_cliente_id, vc.color, vc.tono, p.fecha_acordada
HAVING SUM(sa.cantidad_disponible) > 0;

GRANT SELECT ON doc.vw_despacho_pendiente TO authenticated;


-- ── doc.get_despacho_partida ──────────────────────────────────────────────
-- Returns a pre-built dispatch payload for a single partida.
--
-- Result shape:
-- {
--   "partida_id": 123,
--   "codigo": "2025-0042",
--   "tercero_id": 7,
--   "cliente": "Acme S.A.",
--   "guias": [
--     {
--       "guia_remision_tipo_id": 2,
--       "guia_remision_tipo_codigo": "DESPACHO_CLIENTE",
--       "guia_remision_tipo_nombre": "Servicio – Despacho de material procesado a cliente",
--       "tercero_id": 7,
--       "rolls": 12,
--       "kg_total": 245.60,
--       "items": [
--         { "item_id": 44, "lote_id": 901, "ubicacion_id": 3, "cantidad": 20.50, "propietario_id": 7 },
--         ...
--       ]
--     },
--     { ... }   -- second entry only present when tiene_mixto = true
--   ]
-- }
--
-- Frontend adds serie, correlativo, fecha_emision to each guia entry and
-- calls doc.crear_guia once per entry.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_despacho_partida(p_partida_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'partida_id', p.id,
        'codigo',     EXTRACT(YEAR FROM p.fyh_cre)::TEXT
                          || '-' || LPAD(p.numero::TEXT, 4, '0'),
        'tercero_id', p.tercero_id,
        'cliente',    t.nombre,
        'guias',      COALESCE(guias_agg.guias, '[]'::jsonb)
    )
    INTO v_result
    FROM mes.partida p
    JOIN tercero t ON t.id = p.tercero_id
    LEFT JOIN LATERAL (
        SELECT jsonb_agg(
            jsonb_build_object(
                'guia_remision_tipo_id',     grt.id,
                'guia_remision_tipo_codigo', grt.codigo,
                'guia_remision_tipo_nombre', grt.nombre,
                'tercero_id',                p.tercero_id,
                'rolls',                     lotes_agg.roll_count,
                'kg_total',                  ROUND(lotes_agg.kg_total::NUMERIC, 2),
                'items',                     lotes_agg.items
            )
            ORDER BY grt.codigo  -- deterministic: DESPACHO_CLIENTE before VENTA_EGRESO
        ) AS guias
        FROM (
            -- Group available dyed lotes by ownership
            SELECT
                CASE WHEN l.propietario_id = 1
                     THEN 'VENTA_EGRESO'
                     ELSE 'DESPACHO_CLIENTE'
                END                             AS tipo_codigo,
                COUNT(*)                        AS roll_count,
                SUM(sa.cantidad_disponible)     AS kg_total,
                jsonb_agg(
                    jsonb_build_object(
                        'item_id',        l.item_id,
                        'lote_id',        l.id,
                        'ubicacion_id',   sa.ubicacion_id,
                        'cantidad',       ROUND(sa.cantidad_disponible::NUMERIC, 2),
                        'propietario_id', l.propietario_id
                    )
                    ORDER BY l.id
                )                               AS items
            FROM mes.partida op
            JOIN mes.partida_paso opp
                ON  opp.partida_id = op.id
            JOIN inventario.lote l
                ON  l.documento_tipo = 'partida_paso'
                AND l.documento_id   = opp.id
            JOIN inventario.lote_rollo_detalle lrd
                ON  lrd.lote_id    = l.id
                AND lrd.flg_tenido = true
            JOIN inventario.vw_stock_actual sa ON sa.lote_id = l.id  -- 0-balance lotes already excluded
            WHERE op.partida_id = p.id
            GROUP BY
                CASE WHEN l.propietario_id = 1 THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END
        ) lotes_agg
        JOIN doc.guia_remision_tipo grt ON grt.codigo = lotes_agg.tipo_codigo
    ) guias_agg ON true
    WHERE p.id = p_partida_id;

    IF v_result IS NULL THEN
        RAISE EXCEPTION
            'Partida % no encontrada o sin stock de rollos teñidos pendiente de despacho',
            p_partida_id;
    END IF;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.get_despacho_partida(BIGINT) TO authenticated;

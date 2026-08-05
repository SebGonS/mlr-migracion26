-- ============================================================================
-- DIAGNOSTIC · Lock the exact in-scope set for the Track B clean run — READ ONLY
-- ============================================================================
-- In scope for the FIRST clean build:
--   • raw roll (flg_tenido=false) with SERV_EGR on documento_tipo='PARTIDA'
--   • partida (=im.documento_id) legacy (fyh_cre <= go-live)
--   • partida has compactado paso + >=1 ejecucion
--   • SUPPLY (sum compactado ejec cantidad_rollos) >= DEMAND (raw rolls shipped)
--   • roll is out of stock (exclude the 1 returned roll 90129 / in-stock)
-- Deferred: supply<demand (60), no-compactado-ejec gaps (35), returns.
--
-- Confirms the exact counts the build's §0/§2 will assert. Nothing writes.
-- ============================================================================

WITH tb AS (   -- raw rolls shipped, per partida
    SELECT im.documento_id AS partida_id, im.lote_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
      AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=im.lote_id),0) = 0
),
demand AS (
    SELECT partida_id, COUNT(DISTINCT lote_id) AS raw_shipped
    FROM tb GROUP BY partida_id
),
supply AS (
    SELECT pp.partida_id, SUM(ppe.cantidad_rollos) AS supply_rollos, COUNT(*) AS n_ejecs
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
    GROUP BY pp.partida_id
),
scope AS (
    SELECT d.partida_id, d.raw_shipped, s.supply_rollos, s.n_ejecs
    FROM demand d
    JOIN supply s ON s.partida_id = d.partida_id           -- has compactado ejec
    JOIN mes.partida p ON p.id = d.partida_id
    WHERE p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz  -- legacy
      AND s.supply_rollos IS NOT NULL
      AND s.supply_rollos >= d.raw_shipped                    -- supply >= demand
)
SELECT
    COUNT(*)                                   AS in_scope_partidas,
    SUM(raw_shipped)                           AS in_scope_rolls,
    COUNT(*) FILTER (WHERE n_ejecs = 1)        AS single_ejec_partidas,
    COUNT(*) FILTER (WHERE n_ejecs > 1)        AS multi_ejec_partidas,
    SUM(raw_shipped) FILTER (WHERE n_ejecs>1)  AS rolls_in_multi_ejec_partidas
FROM scope;
-- expect ~529 partidas / ~10,186 rolls (469 exact 9060 + 60 room 1126). Confirm live.

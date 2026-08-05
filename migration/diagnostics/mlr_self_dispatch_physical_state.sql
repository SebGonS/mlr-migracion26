-- ============================================================================
-- DIAGNOSTIC · Physical state of the MLR→MLR "self dispatch" partidas — READ ONLY
-- ============================================================================
-- 145 partidas with legacy cliente='MLR' (→ tercero 1 = Manufacturas la Real itself).
-- COMMERCIAL decision is settled: NO venta (a sale to self is not a sale; ownership
-- never transfers). Per 27_venta.sql, a non-commercial entrega simply has venta_id NULL.
--
-- OPEN question is STOCK: their rolls were "dispatched as regular rolls", so the ledger
-- likely holds real egresses → goods left stock with no sale. Two opposite fixes:
--   (a) goods physically left  → leave the egress (reversing = phantom inventory)
--   (b) despacho was bookkeeping only → egress is spurious (like the 193 phantom
--       SERV_EGRs) → reverse so rolls sit in finished-goods stock
-- This shows which. Nothing writes.
-- ============================================================================

-- ── §1 · Do their dyed rolls exist, and are they in stock or egressed? ────────
WITH selfp AS (
    SELECT DISTINCT mp.id AS partida_id, COALESCE(mp.partida_origen_id, mp.id) AS root_id
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN public.cliente c  ON c.id = lp.cliente_id AND c.cliente = 'MLR'
    JOIN mes.partida mp    ON mp.id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
),
dyed AS (
    SELECT l.id AS lote_id, pp.partida_id,
           COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=l.id),0) AS saldo,
           EXISTS (SELECT 1 FROM inventario.item_movimientos im
                   JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
                                                          AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
                   WHERE im.lote_id=l.id) AS has_egress,
           EXISTS (SELECT 1 FROM inventario.item_movimientos im
                   WHERE im.lote_id=l.id AND im.documento_tipo='entrega') AS egress_on_entrega
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    JOIN selfp s ON s.partida_id = pp.partida_id
)
SELECT
    has_egress,
    egress_on_entrega,
    (saldo > 0)          AS in_stock,
    COUNT(*)             AS dyed_rolls,
    round(SUM(saldo)::numeric,2) AS kg_en_stock
FROM dyed
GROUP BY 1,2,3 ORDER BY dyed_rolls DESC;
-- has_egress=true & in_stock=false ⇒ they really left (reading a)
-- has_egress=false & in_stock=true ⇒ still in stock, nothing to fix
-- has_egress=true & in_stock=true  ⇒ partial / odd, inspect


-- ── §2 · What movement types do those rolls carry? (is the egress a real dispatch?)
WITH selfp AS (
    SELECT DISTINCT mp.id AS partida_id
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN public.cliente c  ON c.id = lp.cliente_id AND c.cliente = 'MLR'
    JOIN mes.partida mp    ON mp.id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
)
SELECT imt.codigo AS movimiento, im.documento_tipo,
       COUNT(*) AS movimientos, COUNT(DISTINCT im.lote_id) AS rolls
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
JOIN selfp s ON s.partida_id = pp.partida_id
JOIN inventario.item_movimientos im ON im.lote_id = l.id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
GROUP BY 1,2 ORDER BY movimientos DESC;


-- ── §3 · Do these partidas appear in despacho under ANY other client too? ────
-- If a partida was dispatched both to 'MLR' and to a real client, the MLR row is the
-- internal step and the real one is the sale ⇒ strengthens "bookkeeping only".
WITH selfp AS (
    SELECT DISTINCT dsp.partida_id
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN public.cliente c  ON c.id = lp.cliente_id AND c.cliente = 'MLR'
    WHERE COALESCE(dsp.flg_elm,false)=false
)
SELECT
    COUNT(DISTINCT s.partida_id)                                          AS mlr_self_partidas,
    COUNT(DISTINCT s.partida_id) FILTER (WHERE otros.partida_id IS NOT NULL) AS tambien_despachadas_a_otro_cliente
FROM selfp s
LEFT JOIN (
    SELECT DISTINCT dsp.partida_id
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN public.cliente c  ON c.id = lp.cliente_id AND c.cliente <> 'MLR'
    WHERE COALESCE(dsp.flg_elm,false)=false
) otros ON otros.partida_id = s.partida_id;

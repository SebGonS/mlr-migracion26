-- READ ONLY · Will the GLOBAL uq_venta_factura (factura_serie, factura_numero) collide?
-- Live index is global (confirmed via pg_indexes). Grouping = one venta per
-- (tercero, nfactura). A collision happens iff a REAL factura (F###/B###) maps to more
-- than one mes.partida.tercero_id. Legacy "clientes" like MLR/Oswaldo, MLR/Victoria may
-- be sub-labels that merge into ONE tercero in the new schema — if so, no collision.
-- GI-*/G0x-* are internal refs, NOT facturas → excluded (they stay ABIERTA).

-- ── §1 · Per REAL factura: how many distinct new-schema terceros? ─────────────
WITH f AS (
    SELECT dsp.nfactura,
           split_part(dsp.nfactura,'-',1)                     AS serie,
           mp.tercero_id,
           lp.cliente_id
    FROM public.despacho dsp
    JOIN public.partida lp  ON lp.id = dsp.partida_id
    JOIN mes.partida    mp  ON mp.id = dsp.partida_id     -- new-schema tercero
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura ~ '^[A-Za-z0-9]+-[0-9]+$'
      AND upper(split_part(dsp.nfactura,'-',1)) ~ '^[FB][0-9]+$'   -- real facturas/boletas only
)
SELECT
    COUNT(*)                                        AS real_factura_docs,
    COUNT(*) FILTER (WHERE n_terceros = 1)          AS single_tercero_OK,
    COUNT(*) FILTER (WHERE n_terceros > 1)          AS MULTI_tercero_COLLISION,
    MAX(n_terceros)                                 AS worst_case,
    MAX(n_clientes)                                 AS worst_case_legacy_clientes
FROM (
    SELECT nfactura,
           COUNT(DISTINCT tercero_id) AS n_terceros,
           COUNT(DISTINCT cliente_id) AS n_clientes
    FROM f GROUP BY nfactura
) x;
-- MULTI_tercero_COLLISION = 0  ⇒ global index is safe, build as planned.
-- > 0 ⇒ those facturas need a rule (merge terceros, or per-tercero index).


-- ── §2 · The colliding facturas in detail (if any) ───────────────────────────
WITH f AS (
    SELECT dsp.nfactura, mp.tercero_id, t.nombre AS tercero, c.cliente AS legacy_cliente
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN public.cliente c  ON c.id = lp.cliente_id
    JOIN mes.partida mp    ON mp.id = dsp.partida_id
    JOIN tercero t         ON t.id = mp.tercero_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura ~ '^[A-Za-z0-9]+-[0-9]+$'
      AND upper(split_part(dsp.nfactura,'-',1)) ~ '^[FB][0-9]+$'
)
SELECT nfactura,
       COUNT(DISTINCT tercero_id)                 AS n_terceros,
       string_agg(DISTINCT tercero, ' | ')        AS terceros,
       string_agg(DISTINCT legacy_cliente, ' | ') AS legacy_clientes
FROM f
GROUP BY nfactura
HAVING COUNT(DISTINCT tercero_id) > 1
ORDER BY n_terceros DESC, nfactura
LIMIT 25;


-- ── §3 · Do the MLR sub-labels collapse to one tercero? (the key mapping) ────
SELECT c.cliente AS legacy_cliente, mp.tercero_id, t.nombre AS tercero, COUNT(*) AS partidas
FROM public.cliente c
JOIN public.partida lp ON lp.cliente_id = c.id
JOIN mes.partida mp    ON mp.id = lp.id
JOIN tercero t         ON t.id = mp.tercero_id
WHERE c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)'
GROUP BY c.cliente, mp.tercero_id, t.nombre
ORDER BY c.cliente;

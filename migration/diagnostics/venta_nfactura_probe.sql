-- ============================================================================
-- DIAGNOSTIC · legacy despacho.nfactura — format + uniqueness — READ ONLY
-- ============================================================================
-- Needed before the venta migration:
--   (1) FORMAT — doc.venta stores factura_serie TEXT + factura_numero INT separately,
--       with CHECK ((serie IS NULL) = (numero IS NULL)). Must parse nfactura into both.
--   (2) UNIQUENESS — grouping is "one venta per nfactura". If an nfactura spans MULTIPLE
--       terceros, that grouping breaks (venta.tercero_id is single NOT NULL) AND the
--       uq_venta_factura index collides. NOTE: VENTA_MODULE_CONSOLIDATED.sql has that
--       index on (factura_serie, factura_numero) GLOBALLY, while migration/27_venta.sql
--       declares (tercero_id, factura_serie, factura_numero) — confirm which is live.
-- Nothing writes.
-- ============================================================================

-- ── §1 · Shape census: what does nfactura look like? ─────────────────────────
SELECT
    CASE
        WHEN nfactura IS NULL OR btrim(nfactura) = ''        THEN 'null_or_blank'
        WHEN nfactura ~ '^[0-9]+$'                           THEN 'pure_numeric'
        WHEN nfactura ~ '^[A-Za-z0-9]+-[0-9]+$'              THEN 'serie-numero (dash)'
        WHEN nfactura ~ '^[A-Za-z]+[0-9]+$'                  THEN 'alpha+numeric (no sep)'
        ELSE                                                      'other'
    END                                           AS shape,
    COUNT(*)                                      AS rows,
    COUNT(DISTINCT nfactura)                      AS distinct_values,
    (array_agg(DISTINCT nfactura))[1:8]           AS samples
FROM public.despacho
WHERE COALESCE(flg_elm,false)=false
GROUP BY 1 ORDER BY rows DESC;


-- ── §2 · Does one nfactura span MULTIPLE terceros? (breaks the grouping) ─────
WITH d AS (
    SELECT dsp.nfactura, lp.cliente_id
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura IS NOT NULL AND btrim(dsp.nfactura) <> ''
)
SELECT
    COUNT(*)                                                   AS distinct_nfacturas,
    COUNT(*) FILTER (WHERE n_clientes = 1)                     AS single_cliente_OK,
    COUNT(*) FILTER (WHERE n_clientes > 1)                     AS MULTI_cliente_PROBLEM,
    MAX(n_clientes)                                            AS worst_case_clientes
FROM (
    SELECT nfactura, COUNT(DISTINCT cliente_id) AS n_clientes
    FROM d GROUP BY nfactura
) x;


-- ── §3 · The multi-tercero offenders (if any) — inspect before deciding ──────
WITH d AS (
    SELECT dsp.nfactura, lp.cliente_id, c.cliente, COUNT(*) AS rows
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN public.cliente c ON c.id = lp.cliente_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura IS NOT NULL AND btrim(dsp.nfactura) <> ''
    GROUP BY dsp.nfactura, lp.cliente_id, c.cliente
)
SELECT nfactura, COUNT(DISTINCT cliente_id) AS n_clientes,
       string_agg(DISTINCT cliente, ' | ') AS clientes, SUM(rows) AS despacho_rows
FROM d
GROUP BY nfactura
HAVING COUNT(DISTINCT cliente_id) > 1
ORDER BY n_clientes DESC, nfactura
LIMIT 25;


-- ── §4 · How many despacho rows would be ABIERTA (no factura ref)? ───────────
SELECT
    (nfactura IS NULL OR btrim(nfactura)='')  AS no_factura,
    COUNT(*)                                  AS despacho_rows,
    COUNT(DISTINCT partida_id)                AS partidas
FROM public.despacho
WHERE COALESCE(flg_elm,false)=false
GROUP BY 1;



SELECT indexdef FROM pg_indexes WHERE schemaname='doc' AND tablename='venta';

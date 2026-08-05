-- READ ONLY · nfactura serie-prefix breakdown: which are REAL facturas (F###/B###)
-- vs internal refs (GI-*) vs multi-factura strings? Decides what becomes a
-- venta.factura_serie/numero ref and what stays ABIERTA with the raw text preserved.

-- ── §1 · prefix census (dash-format only) + multi-client flag per prefix ──────
WITH d AS (
    SELECT dsp.nfactura,
           split_part(dsp.nfactura, '-', 1)                AS serie_raw,
           lp.cliente_id
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura ~ '^[A-Za-z0-9]+-[0-9]+$'
)
SELECT serie_raw,
       COUNT(*)                                            AS rows,
       COUNT(DISTINCT nfactura)                            AS distinct_docs,
       COUNT(DISTINCT cliente_id)                          AS distinct_clientes,
       -- a real factura should map to exactly ONE cliente
       (SELECT COUNT(*) FROM (
            SELECT nfactura FROM d d2 WHERE d2.serie_raw = d.serie_raw
            GROUP BY nfactura HAVING COUNT(DISTINCT cliente_id) > 1
        ) z)                                               AS docs_spanning_multi_cliente
FROM d
GROUP BY serie_raw
ORDER BY rows DESC;


-- ── §2 · the "other" bucket in detail — multi-factura + malformed shapes ─────
SELECT
    CASE
        WHEN nfactura ~ ','                       THEN 'multi_factura (comma)'
        WHEN nfactura ~ '/'                       THEN 'malformed_separator'
        WHEN nfactura ~ '^[0-9]+$'                THEN 'pure_numeric'
        ELSE                                           'other_unclassified'
    END                                  AS shape,
    COUNT(*)                             AS rows,
    COUNT(DISTINCT nfactura)             AS distinct_values,
    (array_agg(DISTINCT nfactura))[1:10] AS samples
FROM public.despacho
WHERE COALESCE(flg_elm,false)=false
  AND nfactura IS NOT NULL AND btrim(nfactura) <> ''
  AND nfactura !~ '^[A-Za-z0-9]+-[0-9]+$'
GROUP BY 1 ORDER BY rows DESC;


-- ── §3 · Would parsing overflow factura_numero (INT)? correlativos are long ──
-- e.g. F002-00009462 → 9462 fits; but check the max parsed value.
SELECT
    MAX(length(split_part(nfactura,'-',2)))                       AS max_correlativo_len,
    MAX(NULLIF(split_part(nfactura,'-',2),'')::bigint)            AS max_correlativo_value,
    COUNT(*) FILTER (WHERE NULLIF(split_part(nfactura,'-',2),'')::bigint > 2147483647) AS would_overflow_int
FROM public.despacho
WHERE COALESCE(flg_elm,false)=false
  AND nfactura ~ '^[A-Za-z0-9]+-[0-9]+$';

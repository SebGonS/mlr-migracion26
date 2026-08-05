-- READ ONLY · Break down WHY migrated ventas have NULL factura_serie/numero.
-- Distinguishes: (a) genuinely no nfactura, (b) not-a-single-factura (internal ref /
-- multi-factura — correctly null, raw preserved), (c) FIXABLE format issue we
-- should have parsed (slash typo, stray spaces, etc.) — the real gap, (d) lost the
-- 42-way conflict tiebreak (correctly null per client decision). Nothing writes.

WITH v AS (
    SELECT id, observacion,
           (observacion ~ 'Ref\. original: "') AS has_raw_ref,
           substring(observacion FROM 'Ref\. original: "([^"]*)"') AS raw_ref,
           (observacion ~ 'factura compartida entre varios clientes') AS lost_conflict
    FROM doc.venta
    WHERE factura_serie IS NULL
)
SELECT
    CASE
        WHEN NOT has_raw_ref                                        THEN 'sin_referencia_legacy (correcto)'
        WHEN lost_conflict                                          THEN 'perdio_empate_conflicto (correcto, decision cliente)'
        WHEN raw_ref ~ '^[A-Za-z0-9]+[/\s]*[0-9]+[-\s]*[0-9]+$'
             AND raw_ref !~ ','                                     THEN 'FORMATO_CORREGIBLE (gap real)'
        WHEN raw_ref ~ ','                                          THEN 'multi_factura (correcto, no es 1 sola factura)'
        WHEN upper(split_part(raw_ref,'-',1)) ~ '^GI|^G0'            THEN 'referencia_interna GI/G0x (correcto, no es factura)'
        ELSE                                                             'otro_no_clasificado'
    END AS categoria,
    COUNT(*)                              AS ventas,
    (array_agg(raw_ref))[1:8]              AS ejemplos
FROM v
GROUP BY 1 ORDER BY ventas DESC;

-- ============================================================================
-- DIAGNOSTIC v2 · The REAL fixable-format set (corrects the v1 regex bug) — READ ONLY
-- ============================================================================
-- v1 (null_factura_breakdown.sql) mis-flagged G0x-prefixed internal refs (G01-60,
-- G03-21, G06-12) as "correctable format" — they were never real facturas, same
-- family as GI-*, just a different letter. This re-derives the fixable set properly:
--   1. strip ONLY stray noise chars (/, ., space) — never touch commas (those mark
--      genuine multi-factura, must stay excluded)
--   2. require the cleaned value to match a REAL factura prefix: [FB][0-9]* (not G/GI)
--   3. require exactly ONE numero group after the dash (no embedded second number)
-- Also checks: would assigning it collide with an EXISTING factura_serie/numero
-- already on another venta (the global unique index)? Nothing writes.
-- ============================================================================

WITH v AS (
    SELECT id, tercero_id,
           substring(observacion FROM 'Ref\. original: "([^"]*)"') AS raw_ref
    FROM doc.venta
    WHERE factura_serie IS NULL
      AND observacion ~ 'Ref\. original: "'
      AND observacion !~ 'factura compartida entre varios clientes'  -- exclude the 55 conflict-losers (settled)
),
cleaned AS (
    SELECT id, tercero_id, raw_ref,
           regexp_replace(raw_ref, '[/\.\s]', '', 'g') AS stripped
    FROM v
    WHERE raw_ref !~ ','          -- exclude genuine multi-factura outright
),
candidate AS (
    SELECT id, tercero_id, raw_ref, stripped,
           (stripped ~ '^[FB][0-9]*-[0-9]+$')       AS looks_real_factura
    FROM cleaned
)
SELECT
    looks_real_factura,
    COUNT(*)                        AS ventas,
    (array_agg(DISTINCT raw_ref))[1:15] AS ejemplos
FROM candidate
GROUP BY 1 ORDER BY 1 DESC;


-- ── §2 · The actual fixable rows, with parsed serie/numero + collision check ──
WITH v AS (
    SELECT id, tercero_id,
           substring(observacion FROM 'Ref\. original: "([^"]*)"') AS raw_ref
    FROM doc.venta
    WHERE factura_serie IS NULL
      AND observacion ~ 'Ref\. original: "'
      AND observacion !~ 'factura compartida entre varios clientes'
),
cleaned AS (
    SELECT id, tercero_id, raw_ref,
           regexp_replace(raw_ref, '[/\.\s]', '', 'g') AS stripped
    FROM v
    WHERE raw_ref !~ ','
),
fixable AS (
    SELECT id, tercero_id, raw_ref,
           upper(split_part(stripped,'-',1)) AS f_serie,
           NULLIF(split_part(stripped,'-',2),'')::int AS f_numero
    FROM cleaned
    WHERE stripped ~ '^[FB][0-9]*-[0-9]+$'
)
SELECT f.id, f.tercero_id, f.raw_ref, f.f_serie, f.f_numero,
       EXISTS (SELECT 1 FROM doc.venta v2
               WHERE v2.factura_serie = f.f_serie AND v2.factura_numero = f.f_numero
                 AND v2.id <> f.id)                              AS collides_with_existing_venta,
       (SELECT COUNT(*) FROM fixable f2
        WHERE f2.f_serie = f.f_serie AND f2.f_numero = f.f_numero
          AND f2.id <> f.id)                                     AS collides_within_fixable_set
FROM fixable f
ORDER BY f.id;

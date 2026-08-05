-- 52_fix_venta_factura_typos.sql
--
-- Fixes: factura_format_fixable_v2.sql §1/§2 found 3 NULL-factura ventas whose
-- observacion ref "looks like" a real F/B factura (not an internal GI-/G0x- ref,
-- not a comma-separated multi-factura). Only 2 of the 3 are genuinely fixable:
--
--   venta 2090: raw_ref 'F/002-0010502'      -> stray slash    -> serie 'F002', numero 10502
--   venta 1350: raw_ref 'F-9460'              -> serie exactly as written, no branch digits to fabricate -> serie 'F', numero 9460
--
-- venta 1348 (raw_ref 'F002-0010805.10806') is EXCLUDED on purpose: the period
-- separates TWO facturas ('0010805' and '10806'), same family as the comma
-- multi-factura cases — v2's parser merged it into a fake single number
-- (1080510806), which would be wrong to write. Stays NULL.
--
-- Neither remaining row collides with an existing venta's (factura_serie,
-- factura_numero) or with each other (checked by v2 §2) — uq_venta_factura is
-- the GLOBAL unique index, so this was the load-bearing check.

-- ── §0. DRY RUN — confirm exact target rows before writing ──────────────────
SELECT id, tercero_id, factura_serie, factura_numero, estado,
       substring(observacion FROM 'Ref\. original: "([^"]*)"') AS raw_ref
FROM doc.venta
WHERE id IN (2090, 1350);
-- Expect: both rows, factura_serie/factura_numero NULL, estado != 'FACTURADA'


-- ── §1. UPDATE — run in a transaction, do NOT autocommit ────────────────────
BEGIN;

UPDATE doc.venta
SET factura_serie = 'F002', factura_numero = 10502, estado = 'FACTURADA'
WHERE id = 2090;

UPDATE doc.venta
SET factura_serie = 'F', factura_numero = 9460, estado = 'FACTURADA'
WHERE id = 1350;


-- ── §2. VERIFY — still inside the open transaction, before COMMIT ───────────
-- SELECT id, factura_serie, factura_numero, estado FROM doc.venta WHERE id IN (2090, 1350);
-- -- Expect: 2090 -> F002/10502/FACTURADA, 1350 -> F/9460/FACTURADA
--
-- -- Global uniqueness still holds (expect 0 rows):
SELECT factura_serie, factura_numero, COUNT(*)
FROM doc.venta
WHERE factura_serie IS NOT NULL
GROUP BY 1,2 HAVING COUNT(*) > 1;

-- ── COMMIT only after §2 checks out ──────────────────────────────────────────
-- COMMIT;

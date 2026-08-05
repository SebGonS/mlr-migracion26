-- 54_add_venta_referencia.sql
--
-- Adds doc.venta.referencia_serie / referencia_correlativo — the faithful,
-- NON-UNIQUE record of the reference document that backs each dispatch, split
-- verbatim into serie/correlativo tokens (the shape legacy always used).
--
-- WHY (settled over a long design thread — see below):
--   • The venta layer is an OUTFLOW REGISTER, not an AR/invoicing system. Its
--     job is only: what went out, at what price, and the reference document for
--     it. There is no sales order upstream; the dispatch IS the originating
--     event. So the reference is just a value on the venta, not a modeled
--     invoice with a lifecycle.
--   • Legacy public.despacho.nfactura was ONE free-text field mixing real
--     facturas (F/B), boletas, and internal guías (GI/G0x). The reference is
--     genuinely reused: 195 refs span multiple clients, 1,217 span multiple
--     rows, one GI can label 10 dispatches across 3 months. It is NOT a unique
--     per-shipment document number, so it must be NON-UNIQUE and it belongs on
--     venta (client/group level), NOT on entrega (whose serie/correlativo is
--     the per-shipment guía de remisión, UNIQUE per tercero+tipo — a different,
--     forward concept left untouched here).
--   • correlativo is TEXT (not INT): preserves leading zeros ('0010502'), holds
--     the messy GI tails ('A01-617') and multi-refs ('631,632') verbatim, never
--     overflows. Split is on the FIRST dash only; everything after is kept as-is.
--   • serie is NORMALIZED to alphanumerics (strips the one 'F/002' slash typo +
--     any stray spaces); correlativo stays fully verbatim.
--
-- SCOPE: purely ADDITIVE. Does NOT touch factura_serie/factura_numero,
--   uq_venta_factura, estado, doc.entrega, or the live registrar_despacho /
--   facturar_venta flow — those are the deferred "live-flow rework" follow-up
--   (the per-tercero ABIERTA tab-reuse + estado). This patch only records the
--   historical reference faithfully.
--
-- BACKFILL SOURCE (verbatim, preserves leading zeros):
--   raw_ref = COALESCE(
--       observacion 'Ref. original: "..."',        -- ABIERTA + typo-fixed rows
--       legacy despacho.nfactura via (tercero, serie, numero) join)  -- FACTURADA
--   Validated read-only: 2,115 / 2,116 ventas resolve; the 1 holdout (id 2116)
--   had no legacy reference at all → referencia stays NULL (correct).
--
-- Supersedes and discards 53_backfill_venta_internal_refs.sql (the abandoned
-- "cram GI into factura fields" approach). 52_fix_venta_factura_typos.sql stays
-- (already applied; its 2 rows are covered here verbatim via observacion).
--
-- ⚠ DRY-RUN §0 → run §1 in a txn → read §2 → COMMIT.

-- ══════════════════════════════════════════════════════════════════════════
-- §0 · DRY RUN — coverage (read only)
-- ══════════════════════════════════════════════════════════════════════════
WITH clean_desp AS (
  SELECT DISTINCT mp.tercero_id,
         upper(split_part(btrim(d.nfactura),'-',1)) AS s,
         split_part(btrim(d.nfactura),'-',2)::int   AS n,
         btrim(d.nfactura)                          AS nf
  FROM public.despacho d JOIN mes.partida mp ON mp.id = d.partida_id
  WHERE COALESCE(d.flg_elm,false)=false
    AND btrim(d.nfactura) ~ '^[A-Za-z0-9]+-[0-9]+$'
),
resolved AS (
  SELECT v.id,
    COALESCE(
      NULLIF(substring(v.observacion FROM 'Ref\. original: "([^"]*)"'), ''),
      (SELECT cd.nf FROM clean_desp cd
       WHERE cd.tercero_id=v.tercero_id AND cd.s=v.factura_serie AND cd.n=v.factura_numero
       LIMIT 1)
    ) AS raw_ref
  FROM doc.venta v
)
SELECT COUNT(*) AS total_ventas,
       COUNT(*) FILTER (WHERE raw_ref IS NOT NULL) AS resolved,
       COUNT(*) FILTER (WHERE raw_ref IS NULL)     AS unresolved_expect_1
FROM resolved;


-- ══════════════════════════════════════════════════════════════════════════
-- §1 · Execute
-- ══════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE doc.venta ADD COLUMN IF NOT EXISTS referencia_serie       TEXT;
ALTER TABLE doc.venta ADD COLUMN IF NOT EXISTS referencia_correlativo TEXT;

-- Non-unique lookup index (references are searched; sharing across ventas is expected).
CREATE INDEX IF NOT EXISTS idx_venta_referencia
    ON doc.venta (referencia_serie, referencia_correlativo)
    WHERE referencia_serie IS NOT NULL;

-- Audit/mod triggers need a JWT user context this patch session lacks
-- (same pattern as migrate_despacho_to_venta.sql §1).
ALTER TABLE doc.venta DISABLE TRIGGER trg_bu_venta_mod;
ALTER TABLE doc.venta DISABLE TRIGGER trg_biud_venta_audit;

WITH clean_desp AS (
  SELECT DISTINCT mp.tercero_id,
         upper(split_part(btrim(d.nfactura),'-',1)) AS s,
         split_part(btrim(d.nfactura),'-',2)::int   AS n,
         btrim(d.nfactura)                          AS nf
  FROM public.despacho d JOIN mes.partida mp ON mp.id = d.partida_id
  WHERE COALESCE(d.flg_elm,false)=false
    AND btrim(d.nfactura) ~ '^[A-Za-z0-9]+-[0-9]+$'
),
resolved AS (
  SELECT v.id,
    COALESCE(
      NULLIF(substring(v.observacion FROM 'Ref\. original: "([^"]*)"'), ''),
      (SELECT cd.nf FROM clean_desp cd
       WHERE cd.tercero_id=v.tercero_id AND cd.s=v.factura_serie AND cd.n=v.factura_numero
       LIMIT 1)
    ) AS raw_ref
  FROM doc.venta v
)
UPDATE doc.venta v
SET referencia_serie =                      -- serie normalized: strip non-alnum (F/002 -> F002, stray spaces)
      regexp_replace(
        CASE WHEN r.raw_ref ~ '-' THEN split_part(r.raw_ref,'-',1) ELSE r.raw_ref END,
        '[^A-Za-z0-9]', '', 'g'),
    referencia_correlativo =                -- correlativo VERBATIM (zeros, commas, messy tails kept)
      CASE WHEN r.raw_ref ~ '-'
           THEN substring(r.raw_ref FROM position('-' IN r.raw_ref)+1)
           ELSE NULL END
FROM resolved r
WHERE v.id = r.id AND r.raw_ref IS NOT NULL;
-- expect 2115 rows

ALTER TABLE doc.venta ENABLE TRIGGER trg_bu_venta_mod;
ALTER TABLE doc.venta ENABLE TRIGGER trg_biud_venta_audit;


-- ══════════════════════════════════════════════════════════════════════════
-- §2 · VERIFY (inside the open txn, before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════
-- -- Coverage: 2115 populated, 1 NULL (venta 2116, genuinely no legacy ref).
SELECT COUNT(*) FILTER (WHERE referencia_serie IS NOT NULL) AS con_ref,
       COUNT(*) FILTER (WHERE referencia_serie IS NULL)     AS sin_ref
FROM doc.venta;
--
-- -- Fidelity spot-checks (leading zeros + verbatim tails preserved):
SELECT id, estado, factura_serie, factura_numero,
       referencia_serie, referencia_correlativo
FROM doc.venta
WHERE id IN (
  2090,   -- typo row: slash normalized out -> serie 'F002', corr '0010502'
  1277,   -- GI group: expect serie 'GI', corr '43'
  2116    -- no ref: expect both NULL
) OR (estado='FACTURADA' AND factura_serie='F002')
ORDER BY id LIMIT 10;

-- -- Sanity: no row where a real factura lost its correlativo digits
SELECT COUNT(*) AS facturadas_sin_ref
FROM doc.venta WHERE estado='FACTURADA' AND referencia_serie IS NULL;
-- -- expect 0

-- ══════════════════════════════════════════════════════════════════════════
-- COMMIT;   -- only after §2 checks out
-- ══════════════════════════════════════════════════════════════════════════

-- venta_detalle_schema_check.sql
--
-- Context: migrate_despacho_to_venta.sql (committed, RUN) writes only
-- articulo_tipo_id on doc.venta_detalle (see its INSERT column list). But
-- migration/33_pricing_grupo_articulo.sql later added doc.venta_detalle.
-- grupo_articulo_id and doc.vw_venta (08_views.sql) now reads
-- vd.grupo_articulo_id, NOT vd.articulo_tipo_id.
--
-- Migration 33's own backfill:
--   UPDATE doc.venta_detalle vd SET grupo_articulo_id = g.id
--   FROM grupo_articulo g
--   WHERE g.origen_articulo_tipo_id = vd.articulo_tipo_id
--     AND vd.grupo_articulo_id IS NULL;
-- ...only ran ONCE, at whatever point migration 33 was applied. If the
-- despacho->venta migration's 6,704 rows were inserted AFTER 33 already ran,
-- they never got this backfill and are sitting with grupo_articulo_id NULL
-- right now -- meaning vw_venta shows them with no article classification.
--
-- This script is read-only. Run all of it and paste back the results.

-- ── §1. Do both columns exist, and which does vw_venta actually read? ───────
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'doc' AND table_name = 'venta_detalle'
  AND column_name IN ('articulo_tipo_id', 'grupo_articulo_id')
ORDER BY column_name;

-- ── §2. Global picture: any row with articulo_tipo_id set but no grupo? ─────
-- Migration 33's abort-guard checked this exact condition at its own run
-- time and required it to be 0 -- if it's >0 now, something was inserted
-- since without a matching backfill.
SELECT
    COUNT(*) FILTER (WHERE articulo_tipo_id IS NOT NULL AND grupo_articulo_id IS NULL) AS missing_grupo,
    COUNT(*) FILTER (WHERE articulo_tipo_id IS NOT NULL AND grupo_articulo_id IS NOT NULL) AS has_both,
    COUNT(*) FILTER (WHERE articulo_tipo_id IS NULL) AS no_articulo_tipo,
    COUNT(*) AS total
FROM doc.venta_detalle;

-- ── §3. Scoped to just the despacho->venta migration's rows ────────────────
-- Those rows are usr_cre=4 with fyh_cre = the legacy d.fecha_despacho (NOT
-- migration run time) -- usr_cre=4 alone is reused by other patches, so scope
-- via venta_id joined back to ventas that only this migration could have
-- created: doc.venta rows with usr_cre=4 whose observacion carries the
-- migration's marker text, or simply any venta_detalle row whose venta_id
-- is itself usr_cre=4 AND fyh_cre = venta.fecha (this migration set
-- venta.fyh_cre = r.fecha, matching venta_detalle.fyh_cre = d.fecha_despacho
-- for same-day dispatches -- looser but sufficient as a sanity cross-check).
SELECT
    COUNT(*) AS migrated_rows_total,
    COUNT(*) FILTER (WHERE vd.grupo_articulo_id IS NULL AND vd.articulo_tipo_id IS NOT NULL) AS migrated_rows_missing_grupo,
    COUNT(*) FILTER (WHERE vd.grupo_articulo_id IS NOT NULL) AS migrated_rows_has_grupo
FROM doc.venta_detalle vd
JOIN doc.venta v ON v.id = vd.venta_id
WHERE vd.usr_cre = 4 AND v.usr_cre = 4;

-- ── §4. Concrete sample of affected rows (if any), for eyeballing ───────────
SELECT vd.id, vd.venta_id, vd.partida_id, vd.articulo_tipo_id, vd.grupo_articulo_id,
       at.nombre AS articulo_tipo_nombre
FROM doc.venta_detalle vd
JOIN doc.venta v ON v.id = vd.venta_id
LEFT JOIN articulo_tipo at ON at.id = vd.articulo_tipo_id
WHERE vd.usr_cre = 4 AND v.usr_cre = 4
  AND vd.articulo_tipo_id IS NOT NULL
  AND vd.grupo_articulo_id IS NULL
ORDER BY vd.id
LIMIT 20;

-- ── §5. Does a grupo_articulo row actually exist for every articulo_tipo_id
--        used by the migrated rows? (rules out "no mapping exists yet" vs.
--        "mapping exists, just never applied") ─────────────────────────────
SELECT DISTINCT vd.articulo_tipo_id, at.nombre,
       g.id AS grupo_articulo_id_disponible
FROM doc.venta_detalle vd
JOIN doc.venta v ON v.id = vd.venta_id
LEFT JOIN articulo_tipo at ON at.id = vd.articulo_tipo_id
LEFT JOIN grupo_articulo g ON g.origen_articulo_tipo_id = vd.articulo_tipo_id
WHERE vd.usr_cre = 4 AND v.usr_cre = 4
  AND vd.articulo_tipo_id IS NOT NULL
ORDER BY vd.articulo_tipo_id;

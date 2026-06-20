-- ============================================================================
-- PATCH 25 — doc.articulo_tipo_familia: commercial pricing families
-- ----------------------------------------------------------------------------
-- Restores the legacy article-type pricing grouping that was dropped in the
-- migration (catalogo_precios kept BUCKET ids, partidas kept LITERAL ids, and
-- the new lookup matched literally → ~2000 TENIDO partidas resolved to no price).
--
-- The grouping is now DATA, not hardcoded SQL:
--   - tercero_id IS NULL → default family for every client
--   - tercero_id = <id>  → per-client override (flat-rate clients 1/11/22 → 20)
-- Lookup (doc.fn_familia_precio, in funciones/facturacion.sql) picks the
-- client-specific row over the default, else prices as the type itself.
--
-- Applies to TENIDO pricing only. Recipes still match the LITERAL articulo_tipo.
--
-- Order: this patch is self-contained (the data-fix reads the mapping table
-- directly, not fn_familia_precio), so it can run before or after facturacion.sql.
-- ============================================================================

-- ── Table ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS doc.articulo_tipo_familia (
    articulo_tipo_id SMALLINT NOT NULL REFERENCES articulo_tipo(id),
    tercero_id       INT               REFERENCES tercero(id),  -- NULL = default for all clients
    familia_id       SMALLINT NOT NULL REFERENCES articulo_tipo(id),
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ
);

-- One default per type (tercero_id NULL), one override per (type, client).
-- Partial unique indexes because a plain UNIQUE treats NULLs as distinct.
CREATE UNIQUE INDEX IF NOT EXISTS uq_articulo_tipo_familia_default
    ON doc.articulo_tipo_familia(articulo_tipo_id) WHERE tercero_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_articulo_tipo_familia_cliente
    ON doc.articulo_tipo_familia(articulo_tipo_id, tercero_id) WHERE tercero_id IS NOT NULL;

GRANT SELECT ON doc.articulo_tipo_familia TO authenticated;

-- ── Seed: default family map (client-independent) ─────────────
-- From the legacy price-lookup CASE: 4,9→18 · 8→12 · 10,17→14 · 22,23→16.
INSERT INTO doc.articulo_tipo_familia (articulo_tipo_id, tercero_id, familia_id)
SELECT v.tipo, NULL::INT, v.fam
FROM (VALUES (4,18),(9,18),(8,12),(10,14),(17,14),(22,16),(23,16)) AS v(tipo, fam)
WHERE EXISTS (SELECT 1 FROM articulo_tipo a WHERE a.id = v.tipo)
  AND EXISTS (SELECT 1 FROM articulo_tipo a WHERE a.id = v.fam)
  AND NOT EXISTS (
      SELECT 1 FROM doc.articulo_tipo_familia f
      WHERE f.articulo_tipo_id = v.tipo AND f.tercero_id IS NULL
  );

-- ── Seed: per-client override → flat family 20 ────────────────
-- Legacy: cliente_id IN (1,11,22) AND tipo IN (4,8,9,10,11,12,14,15,17,18,20) → 20.
-- Resolve the clients via tercero.cliente_id (bridge column still present).
INSERT INTO doc.articulo_tipo_familia (articulo_tipo_id, tercero_id, familia_id)
SELECT v.tipo, t.id, 20
FROM tercero t
CROSS JOIN (VALUES (4),(8),(9),(10),(11),(12),(14),(15),(17),(18),(20)) AS v(tipo)
WHERE t.cliente_id IN (1, 11, 22)
  AND EXISTS (SELECT 1 FROM articulo_tipo a WHERE a.id = v.tipo)
  AND EXISTS (SELECT 1 FROM articulo_tipo a WHERE a.id = 20)
  AND NOT EXISTS (
      SELECT 1 FROM doc.articulo_tipo_familia f
      WHERE f.articulo_tipo_id = v.tipo AND f.tercero_id = t.id
  );

-- Sanity check (run manually): the 3 flat-rate clients should appear here.
--   SELECT DISTINCT t.id, t.nombre
--   FROM doc.articulo_tipo_familia f JOIN tercero t ON t.id = f.tercero_id
--   WHERE f.familia_id = 20;

-- ============================================================================
-- FIX EXISTING DATA — re-point active TENIDO catalog rows onto their family
-- ----------------------------------------------------------------------------
-- Legacy migrated only bucket-keyed rows, but post-migration some prices were
-- entered under absorbed types (e.g. type 23). Once the lookup normalizes to
-- the bucket, those literal-keyed rows become unreachable — move them onto the
-- bucket so they still resolve. Idempotent (bucket types map to themselves).
--
-- Pre-check (review before running):
--   SELECT cp.id, cp.articulo_tipo_id, cp.color_x_cliente_id, cp.precio_kg
--   FROM doc.catalogo_precios cp
--   WHERE cp.operacion_id = (SELECT id FROM mes.operacion WHERE codigo='TENIDO')
--     AND cp.fyh_elm IS NULL
--     AND cp.articulo_tipo_id <> COALESCE((
--           SELECT f.familia_id FROM doc.articulo_tipo_familia f
--           WHERE f.articulo_tipo_id = cp.articulo_tipo_id
--             AND (f.tercero_id = COALESCE(cp.tercero_id,
--                    (SELECT tercero_id FROM color_x_cliente WHERE id = cp.color_x_cliente_id))
--                  OR f.tercero_id IS NULL)
--           ORDER BY f.tercero_id NULLS LAST LIMIT 1), cp.articulo_tipo_id);
-- ============================================================================
UPDATE doc.catalogo_precios cp
SET articulo_tipo_id = COALESCE((
        SELECT f.familia_id
        FROM doc.articulo_tipo_familia f
        WHERE f.articulo_tipo_id = cp.articulo_tipo_id
          AND (f.tercero_id = COALESCE(cp.tercero_id,
                 (SELECT cxc.tercero_id FROM color_x_cliente cxc WHERE cxc.id = cp.color_x_cliente_id))
               OR f.tercero_id IS NULL)
        ORDER BY f.tercero_id NULLS LAST
        LIMIT 1), cp.articulo_tipo_id)
WHERE cp.operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
  AND cp.fyh_elm IS NULL
  AND COALESCE((
        SELECT f.familia_id
        FROM doc.articulo_tipo_familia f
        WHERE f.articulo_tipo_id = cp.articulo_tipo_id
          AND (f.tercero_id = COALESCE(cp.tercero_id,
                 (SELECT cxc.tercero_id FROM color_x_cliente cxc WHERE cxc.id = cp.color_x_cliente_id))
               OR f.tercero_id IS NULL)
        ORDER BY f.tercero_id NULLS LAST
        LIMIT 1), cp.articulo_tipo_id) <> cp.articulo_tipo_id;

-- ── De-duplicate: re-pointing may collide an absorbed-type row with an
-- existing bucket row for the same key. Keep the most recent, close the rest.
-- (Review first if an older manually-entered price should win instead.)
WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY operacion_id, color_x_cliente_id, tercero_id,
                            articulo_tipo_id, tenido_id, fibra, flg_antipilling
               ORDER BY fyh_cre DESC, id DESC
           ) AS rn
    FROM doc.catalogo_precios
    WHERE fyh_elm IS NULL
      AND operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
)
UPDATE doc.catalogo_precios cp
SET fyh_elm = NOW()
FROM ranked r
WHERE r.id = cp.id AND r.rn > 1;

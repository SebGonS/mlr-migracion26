-- ═══════════════════════════════════════════════════════════════
-- Step 16: Add tercero_id dimension to doc.catalogo_precios
-- Depends on: migration/15_catalogo_precios.sql
--
-- Adds a client-level wildcard dimension so you can set a flat rate
-- for an entire client without enumerating every color_x_cliente row.
--
-- Specificity tiers (high → low):
--   color_x_cliente_id  — specific color for specific client
--   tercero_id          — any color for this client (new)
--   both NULL           — universal default
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE doc.catalogo_precios
    ADD COLUMN IF NOT EXISTS tercero_id INT REFERENCES tercero(id);

-- Rebuild unique index to include tercero_id
DROP INDEX IF EXISTS uq_catalogo_precios_activo;

CREATE UNIQUE INDEX uq_catalogo_precios_activo
    ON doc.catalogo_precios (
        operacion_id,
        COALESCE(color_x_cliente_id,    -1),
        COALESCE(tercero_id,            -1),
        COALESCE(articulo_tipo_id::int, -1),
        COALESCE(tenido_id,             -1),
        COALESCE(fibra::int,            -1)
    )
    WHERE fyh_elm IS NULL;

-- Constraint: color_x_cliente_id and tercero_id are mutually exclusive.
-- Setting both would be redundant (color_x_cliente already implies a tercero).
ALTER TABLE doc.catalogo_precios
    ADD CONSTRAINT chk_precio_client_dim
        CHECK (
            color_x_cliente_id IS NULL
            OR tercero_id IS NULL
        );

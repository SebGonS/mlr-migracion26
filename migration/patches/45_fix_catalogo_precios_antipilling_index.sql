-- ═══════════════════════════════════════════════════════════════════════════════
-- 45 · doc.catalogo_precios: include flg_antipilling in the active-row unique index
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY: uq_catalogo_precios_activo enforces one active row per
-- (operacion, color_x_cliente/tercero, articulo_tipo, tenido, fibra) — but did
-- NOT include flg_antipilling. Per the table's own design (doc.catalogo_precios
-- comment), a TENIDO base row (flg_antipilling=false) and its antipilling
-- variant (flg_antipilling=true) legitimately share every other dimension and
-- must coexist as two separate active rows (same precio_kg allowed, different
-- costo_kg). The old index collided them, so doc.upsert_catalogo_precio raised
-- "duplicate key value violates unique constraint uq_catalogo_precios_activo"
-- whenever a second variant was saved for a combination that already had the
-- other variant active.
--
-- Fix: rebuild the index with COALESCE(flg_antipilling::int, -1) added to the
-- key. This only loosens the constraint (fewer collisions), so no existing
-- active rows can violate it.
-- ═══════════════════════════════════════════════════════════════════════════════

DROP INDEX IF EXISTS doc.uq_catalogo_precios_activo;

CREATE UNIQUE INDEX uq_catalogo_precios_activo
    ON doc.catalogo_precios (
        operacion_id,
        COALESCE(color_x_cliente_id,    -1),
        COALESCE(tercero_id,            -1),
        COALESCE(articulo_tipo_id::int, -1),
        COALESCE(tenido_id,             -1),
        COALESCE(fibra::int,            -1),
        COALESCE(flg_antipilling::int,  -1)
    )
    WHERE fyh_elm IS NULL;

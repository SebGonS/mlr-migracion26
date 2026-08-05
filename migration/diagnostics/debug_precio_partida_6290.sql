-- ═══════════════════════════════════════════════════════════════
-- Debug: partida price not resolving in fn_get_precio
-- Plain SELECT statements (no DO block) so SQL editors that split
-- on ";" don't break it. Run each block separately, top to bottom.
-- Change the partida id (6290 below) to debug a different partida.
-- ═══════════════════════════════════════════════════════════════

-- 1) Partida's pricing dimensions
SELECT
    p.id, p.tercero_id, p.color_x_cliente_id, p.tenido_id,
    p.articulo_tipo_id, p.fibra, p.flg_antipilling,
    p.precio_kg AS precio_kg_override
FROM mes.partida p
WHERE p.id = 6290;

-- 2) TENIDO operacion_id
SELECT id AS operacion_id_tenido FROM mes.operacion WHERE codigo = 'TENIDO';

-- 3) Pricing family this partida's articulo_tipo_id maps to
--    (catalog is keyed on the FAMILY, not the literal articulo_tipo_id)
SELECT
    p.articulo_tipo_id,
    p.tercero_id,
    doc.fn_familia_precio(p.articulo_tipo_id, p.tercero_id) AS familia_id
FROM mes.partida p
WHERE p.id = 6290;

-- 4) Direct fn_get_precio call with the partida's real dimensions
SELECT doc.fn_get_precio(
    (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO'),
    p.color_x_cliente_id,
    p.tercero_id,
    doc.fn_familia_precio(p.articulo_tipo_id, p.tercero_id),
    p.tenido_id,
    p.fibra
) AS precio_kg_resuelto
FROM mes.partida p
WHERE p.id = 6290;

-- 5) Any catalogo_precios rows sharing at least one dimension (active or closed)
--    Shows per-dimension match flags so you can see exactly what's mismatched.
SELECT
    cp.id, cp.precio_kg, cp.fyh_cre, cp.fyh_elm,
    cp.tercero_id,          (cp.tercero_id         IS NOT DISTINCT FROM p.tercero_id)          AS match_tercero,
    cp.color_x_cliente_id,  (cp.color_x_cliente_id IS NOT DISTINCT FROM p.color_x_cliente_id)  AS match_color_cliente,
    cp.articulo_tipo_id,    (cp.articulo_tipo_id   IS NOT DISTINCT FROM doc.fn_familia_precio(p.articulo_tipo_id, p.tercero_id)) AS match_familia,
    cp.tenido_id,           (cp.tenido_id          IS NOT DISTINCT FROM p.tenido_id)           AS match_tenido,
    cp.fibra,               (cp.fibra              IS NOT DISTINCT FROM p.fibra)               AS match_fibra
FROM doc.catalogo_precios cp
CROSS JOIN (SELECT * FROM mes.partida WHERE id = 6290) p
WHERE cp.operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
  AND (
        cp.tercero_id = p.tercero_id                                              -- real client match
     OR cp.color_x_cliente_id = p.color_x_cliente_id                              -- real color match
     OR cp.articulo_tipo_id = doc.fn_familia_precio(p.articulo_tipo_id, p.tercero_id)  -- real family match
     OR cp.tenido_id = p.tenido_id                                                -- real tenido match
     OR (cp.tercero_id IS NULL AND cp.color_x_cliente_id IS NULL
         AND cp.articulo_tipo_id IS NULL AND cp.tenido_id IS NULL AND cp.fibra IS NULL)  -- universal wildcard row
      )
ORDER BY cp.fyh_elm NULLS FIRST, cp.fyh_cre DESC
LIMIT 50;

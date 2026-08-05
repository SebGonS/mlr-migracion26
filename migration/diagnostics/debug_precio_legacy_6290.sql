-- ═══════════════════════════════════════════════════════════════
-- Was there ever a legacy price for partida 6290's combination?
-- legacy public.catalogo_precios: color_x_cliente_id=138, tipo_articulo_id=45,
-- tenido_id=2, fibra=1 (raw, un-normalized dimensions — legacy never had
-- the family-bucket concept, that's new-schema only via fn_familia_precio)
-- ═══════════════════════════════════════════════════════════════

-- 1) Exact match on all four dimensions (any adicional_id/activo state)
SELECT id_precio, color_x_cliente_id, tipo_articulo_id, tenido_id, fibra,
       adicional_id, precio_tenido, fyh_cre, fyh_fin, activo
FROM public.catalogo_precios
WHERE color_x_cliente_id = 138
  AND tipo_articulo_id   = 45
  AND tenido_id          = 2
  AND fibra               = 1
ORDER BY fyh_cre DESC;

-- 2) Loosen it: same color_x_cliente_id (this exact client/color), any article/tenido/fibra
--    — shows whether this client ever had ANY legacy price row, and for what combos
SELECT id_precio, color_x_cliente_id, tipo_articulo_id, tenido_id, fibra,
       adicional_id, precio_tenido, fyh_cre, fyh_fin, activo
FROM public.catalogo_precios
WHERE color_x_cliente_id = 138
ORDER BY fyh_cre DESC;

-- 3) Loosen the other way: same tipo_articulo_id=45, any client
--    — shows whether article type 45 was ever priced for ANYONE in legacy
SELECT id_precio, color_x_cliente_id, tipo_articulo_id, tenido_id, fibra,
       adicional_id, precio_tenido, fyh_cre, fyh_fin, activo
FROM public.catalogo_precios
WHERE tipo_articulo_id = 45
ORDER BY fyh_cre DESC;

-- 4) Sanity check: confirm color_x_cliente_id=138 / tipo_articulo=45 refer to
--    the same client/article as the new-schema partida (ids preserved 1:1 across migration)
SELECT cxc.id, cxc.tercero_id, cxc.color_id
FROM color_x_cliente cxc
WHERE cxc.id = 138;

SELECT id, nombre FROM articulo_tipo WHERE id = 45;

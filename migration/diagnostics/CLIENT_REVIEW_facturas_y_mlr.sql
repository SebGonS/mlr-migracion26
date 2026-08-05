-- ============================================================================
-- PARA REVISIÓN DEL CLIENTE · dos hallazgos en los datos históricos — SOLO LECTURA
-- ============================================================================
-- Contexto: estamos migrando el histórico de despachos al nuevo módulo comercial
-- (doc.venta). Dos cosas requieren decisión del negocio antes de migrar.
--
--   §1/§2 — 42 facturas aparecen registradas contra VARIOS clientes distintos
--   §3/§4 — los despachos del cliente "MLR" apuntan a la propia empresa
--
-- Nada de esto modifica datos. Es para que el cliente lo revise y explique.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════════
-- §1 · RESUMEN: ¿cuántas facturas están compartidas entre clientes?
-- ══════════════════════════════════════════════════════════════════════════════
WITH f AS (
    SELECT dsp.nfactura, mp.tercero_id
    FROM public.despacho dsp
    JOIN mes.partida mp ON mp.id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura ~ '^[A-Za-z0-9]+-[0-9]+$'
      AND upper(split_part(dsp.nfactura,'-',1)) ~ '^[FB][0-9]+$'   -- solo facturas/boletas reales
)
SELECT
    COUNT(*)                                  AS facturas_totales,
    COUNT(*) FILTER (WHERE n_clientes = 1)    AS ok_un_solo_cliente,
    COUNT(*) FILTER (WHERE n_clientes > 1)    AS problema_varios_clientes,
    MAX(n_clientes)                           AS peor_caso_clientes
FROM (SELECT nfactura, COUNT(DISTINCT tercero_id) AS n_clientes FROM f GROUP BY nfactura) x;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · DETALLE: las 42 facturas compartidas — para que el cliente las explique
--      Una factura se emite a UN solo cliente. Aquí aparecen contra varios.
-- ══════════════════════════════════════════════════════════════════════════════
WITH f AS (
    SELECT dsp.nfactura, mp.tercero_id, t.nombre AS cliente,
           dsp.fecha_despacho, dsp.rollos_total, dsp.precio_unit
    FROM public.despacho dsp
    JOIN mes.partida mp ON mp.id = dsp.partida_id
    JOIN tercero t      ON t.id = mp.tercero_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      AND dsp.nfactura ~ '^[A-Za-z0-9]+-[0-9]+$'
      AND upper(split_part(dsp.nfactura,'-',1)) ~ '^[FB][0-9]+$'
),
conflictivas AS (
    SELECT nfactura FROM f GROUP BY nfactura HAVING COUNT(DISTINCT tercero_id) > 1
)
SELECT
    f.nfactura                                   AS factura,
    f.cliente,
    COUNT(*)                                     AS despachos,
    MIN(f.fecha_despacho)                        AS primera_fecha,
    MAX(f.fecha_despacho)                        AS ultima_fecha,
    SUM(f.rollos_total)                          AS rollos,
    round(AVG(f.precio_unit)::numeric,2)         AS precio_prom
FROM f JOIN conflictivas c ON c.nfactura = f.nfactura
GROUP BY f.nfactura, f.cliente
ORDER BY f.nfactura, f.cliente;
-- PREGUNTA AL CLIENTE: ¿por qué una misma factura figura en varios clientes?
--   (a) error de tipeo al registrar el N° de factura  → hay que corregirlo
--   (b) la factura realmente agrupa varios "clientes" que son la misma empresa
--   (c) el N° de factura se reutilizó / se registró de forma referencial


-- ══════════════════════════════════════════════════════════════════════════════
-- §3 · RESUMEN: despachos registrados al cliente "MLR" (= la propia empresa)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT
    COUNT(DISTINCT dsp.partida_id)          AS partidas,
    COUNT(*)                                AS despachos,
    SUM(dsp.rollos_total)                   AS rollos,
    MIN(dsp.fecha_despacho)                 AS primera_fecha,
    MAX(dsp.fecha_despacho)                 AS ultima_fecha,
    round(AVG(dsp.precio_unit)::numeric,2)  AS precio_prom,
    COUNT(*) FILTER (WHERE dsp.precio_unit >= 10) AS con_precio_venta_rollo,
    COUNT(*) FILTER (WHERE dsp.precio_unit <  10) AS con_precio_tenido
FROM public.despacho dsp
JOIN public.partida lp ON lp.id = dsp.partida_id
JOIN public.cliente c  ON c.id = lp.cliente_id
WHERE COALESCE(dsp.flg_elm,false)=false
  AND c.cliente = 'MLR';


-- ══════════════════════════════════════════════════════════════════════════════
-- §4 · DETALLE: los despachos al cliente "MLR" — ¿son ventas reales o
--      movimientos internos de stock propio?
-- ══════════════════════════════════════════════════════════════════════════════
SELECT
    EXTRACT(YEAR FROM mp.fyh_cre)::text || '-' || LPAD(mp.numero::text,4,'0') AS partida,
    dsp.fecha_despacho                       AS fecha,
    dsp.rollos_total                         AS rollos,
    dsp.precio_unit                          AS precio,
    dsp.nfactura                             AS factura,
    vc.color, vc.tono
FROM public.despacho dsp
JOIN public.partida lp ON lp.id = dsp.partida_id
JOIN public.cliente c  ON c.id = lp.cliente_id
JOIN mes.partida mp    ON mp.id = dsp.partida_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = mp.color_x_cliente_id
WHERE COALESCE(dsp.flg_elm,false)=false
  AND c.cliente = 'MLR'
ORDER BY dsp.fecha_despacho DESC
LIMIT 60;
-- PREGUNTA AL CLIENTE: los despachos registrados con cliente "MLR", ¿a quién iban?
--   (a) son ventas reales a un tercero que se registró como "MLR" por comodidad
--   (b) son movimientos internos / stock propio, NO ventas
--   (c) son ventas a las sub-cuentas (Oswaldo, Rudy, Victoria…) agrupadas bajo "MLR"

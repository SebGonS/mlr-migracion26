-- ═══════════════════════════════════════════════════════════════════════════════
-- DIAGNOSTIC (read-only): egresos de insumos NO registrados
--
-- PURPOSE
--   The first weeks the system was live, some production steps (TENIDO recipes)
--   and machine washes (LAVADO_MAQUINA) were marked COMPLETADO but the operator
--   never registered the chemical consumption — so the PROD_CONSUMO egress
--   movements for those insumos are missing from inventario.item_movimientos.
--
--   This script IDENTIFIES those runs and COMPUTES the egress that *should* have
--   been posted. It writes NOTHING. Review it, then run the companion backfill:
--       migration/legacy_data/11_backfill_egresos_no_registrados.sql
--
-- DEFINITION OF "unexecuted recipe / wash" (per decision):
--   The run record exists and is COMPLETADO, but there is ZERO insumo PROD_CONSUMO
--   egress attributable to it.
--
-- WHY item-type, not documento_tipo, distinguishes the egress:
--   registrar_produccion ALSO posts PROD_CONSUMO with documento_tipo
--   'partida_paso_ejecucion' — but on the input ROLL lotes (backflush), not on
--   chemicals. We therefore only count PROD_CONSUMO whose item is an INSUMO
--   (EXISTS item_insumo_detalle). Roll consumption is ignored.
--
-- EGRESS AMOUNT (mirrors mes.generar_receta exactly):
--   peso          = SUM(lote.cantidad) of the partida's rolls (real weighed kg)
--   rb            = COALESCE(partida_paso.relacion_bano_objetivo, maquina.relacion_bano)
--   peso_volumen  = GREATEST(peso, maquina.capacidad_min_kg)        -- floor to drum min
--   volumen       = peso_volumen * rb
--   per insumo:
--     medida 'g/L' →  receta_cantidad * volumen        [* factor_stock]
--     medida '%'   →  receta_cantidad * peso * 10       [* factor_stock]
--   The version WITH factor_stock equals partida_componente.cantidad_reservada
--   (what the system reserved). The version WITHOUT is generar_receta's display
--   value. The backfill posts the WITH-factor_stock value — verify below.
--
-- LAVADO_MAQUINA amount (mirrors finalizar_lavado_maquina):
--   Fixed: SUM(lavado_maquina_paso_insumo.cantidad) per item. No scaling, no factor.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- EDIT THE WINDOW HERE (the "first weeks live"). Used by every section below.
-- ─────────────────────────────────────────────────────────────────────────────
-- Convention used throughout: change these two literals only.
--   win_ini  inclusive  >=
--   win_fin  exclusive  <
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION A — TENIDO recipes COMPLETADO with no insumo egress
-- ═══════════════════════════════════════════════════════════════════════════════

-- A0. Summary counts
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO')
SELECT
    COUNT(*)                                              AS ejecuciones_tenido_sin_egreso,
    COUNT(DISTINCT pp.partida_id)                         AS partidas_afectadas,
    MIN(pe.fyh_inicio)                                    AS primera,
    MAX(pe.fyh_inicio)                                    AS ultima
FROM mes.partida_paso_ejecucion pe
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p       ON p.id  = pp.partida_id
CROSS JOIN params pr
WHERE pe.estado = 'COMPLETADO'
  AND pp.receta_id IS NOT NULL
  AND p.estado_produccion <> 'CANCELADA'
  AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
  AND NOT EXISTS (
      SELECT 1
      FROM inventario.item_movimientos im
      JOIN egr_tipo et             ON et.id  = im.item_movimiento_tipo_id
      JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
      WHERE im.documento_tipo = 'partida_paso_ejecucion'
        AND im.documento_id   = pe.id
  );


-- A1. One row per affected ejecucion (header view: weights + resolved volume)
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'),
pasos AS (
    SELECT pe.id AS ejecucion_id, pp.id AS paso_id, pp.partida_id, pp.receta_id,
           COALESCE(pe.maquina_id, pp.maquina_planificada_id) AS maquina_id,
           pp.relacion_bano_objetivo,
           pe.fyh_inicio, COALESCE(pe.fyh_fin, pe.fyh_inicio) AS fyh_evento
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    CROSS JOIN params pr
    WHERE pe.estado = 'COMPLETADO'
      AND pp.receta_id IS NOT NULL
      AND p.estado_produccion <> 'CANCELADA'
      AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
      AND NOT EXISTS (
          SELECT 1 FROM inventario.item_movimientos im
          JOIN egr_tipo et             ON et.id      = im.item_movimiento_tipo_id
          JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
          WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = pe.id
      )
),
pesos AS (
    SELECT s.ejecucion_id, SUM(l.cantidad) AS peso
    FROM pasos s
    JOIN mes.partida_componente pc ON pc.partida_id = s.partida_id AND pc.lote_id IS NOT NULL
    JOIN inventario.lote l         ON l.id = pc.lote_id
    GROUP BY s.ejecucion_id
)
SELECT
    s.ejecucion_id,
    s.paso_id,
    s.partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    s.fyh_inicio,
    s.maquina_id,
    m.codigo                                       AS maquina,
    pz.peso,
    m.capacidad_min_kg,
    COALESCE(s.relacion_bano_objetivo, m.relacion_bano) AS rb,
    CASE WHEN pz.peso < m.capacidad_min_kg THEN true ELSE false END AS aplica_cap_minima,
    ROUND(GREATEST(pz.peso, m.capacidad_min_kg)
          * COALESCE(s.relacion_bano_objetivo, m.relacion_bano), 2)     AS volumen,
    CASE WHEN COALESCE(s.relacion_bano_objetivo, m.relacion_bano) IS NULL
         THEN '⚠ sin relacion_bano (g/L no calculable)' END             AS advertencia
FROM pasos s
LEFT JOIN pesos pz       ON pz.ejecucion_id = s.ejecucion_id
LEFT JOIN mes.maquina m  ON m.id = s.maquina_id
JOIN mes.partida p       ON p.id = s.partida_id
ORDER BY s.fyh_inicio, s.ejecucion_id;


-- A2. Per-insumo computed egress (the numbers the backfill will post)
--     egreso_con_factor  → posted by backfill (stock units)
--     egreso_sin_factor  → generar_receta display value (recipe units)
--     reservada          → partida_componente.cantidad_reservada cross-check
--     flag_mismatch      → reservada present but differs from computed
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'),
pasos AS (
    SELECT pe.id AS ejecucion_id, pp.id AS paso_id, pp.partida_id, pp.receta_id,
           COALESCE(pe.maquina_id, pp.maquina_planificada_id) AS maquina_id,
           pp.relacion_bano_objetivo, pe.fyh_inicio
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    CROSS JOIN params pr
    WHERE pe.estado = 'COMPLETADO'
      AND pp.receta_id IS NOT NULL
      AND p.estado_produccion <> 'CANCELADA'
      AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
      AND NOT EXISTS (
          SELECT 1 FROM inventario.item_movimientos im
          JOIN egr_tipo et             ON et.id      = im.item_movimiento_tipo_id
          JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
          WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = pe.id
      )
),
ctx AS (
    SELECT s.*,
           pz.peso,
           m.capacidad_min_kg,
           COALESCE(s.relacion_bano_objetivo, m.relacion_bano) AS rb,
           GREATEST(pz.peso, m.capacidad_min_kg)
               * COALESCE(s.relacion_bano_objetivo, m.relacion_bano)    AS volumen
    FROM pasos s
    LEFT JOIN mes.maquina m ON m.id = s.maquina_id
    LEFT JOIN (
        SELECT s2.ejecucion_id, SUM(l.cantidad) AS peso
        FROM pasos s2
        JOIN mes.partida_componente pc ON pc.partida_id = s2.partida_id AND pc.lote_id IS NOT NULL
        JOIN inventario.lote l         ON l.id = pc.lote_id
        GROUP BY s2.ejecucion_id
    ) pz ON pz.ejecucion_id = s.ejecucion_id
),
insumos AS (
    SELECT c.ejecucion_id, c.paso_id, c.partida_id, c.fyh_inicio,
           rtpi.item_id, iid.medida, iid.factor_stock,
           c.peso, c.volumen,
           SUM(rtpi.cantidad) AS receta_cantidad,
           ROUND(CASE iid.medida
                     WHEN 'g/L' THEN SUM(rtpi.cantidad) * c.volumen
                     WHEN '%'   THEN SUM(rtpi.cantidad) * c.peso * 10
                 END, 4)                                   AS egreso_sin_factor,
           ROUND(CASE iid.medida
                     WHEN 'g/L' THEN SUM(rtpi.cantidad) * c.volumen * iid.factor_stock
                     WHEN '%'   THEN SUM(rtpi.cantidad) * c.peso * 10 * iid.factor_stock
                 END, 4)                                   AS egreso_con_factor
    FROM ctx c
    JOIN receta.tenido_paso        rtp  ON rtp.receta_id = c.receta_id
    JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id  = rtp.id
    JOIN item_insumo_detalle       iid  ON iid.item_id   = rtpi.item_id
    GROUP BY c.ejecucion_id, c.paso_id, c.partida_id, c.fyh_inicio,
             rtpi.item_id, iid.medida, iid.factor_stock, c.peso, c.volumen
)
SELECT
    i.ejecucion_id,
    i.paso_id,
    i.partida_id,
    i.fyh_inicio,
    i.item_id,
    it.codigo                          AS insumo_codigo,
    it.nombre                          AS insumo,
    i.medida,
    i.factor_stock,
    i.receta_cantidad,
    i.egreso_sin_factor,
    i.egreso_con_factor,
    pc.cantidad_reservada              AS reservada,
    CASE WHEN pc.cantidad_reservada IS NOT NULL
          AND ROUND(pc.cantidad_reservada,4) <> i.egreso_con_factor
         THEN '⚠' END                  AS flag_mismatch,
    iv.precio_promedio,
    ROUND(i.egreso_con_factor * COALESCE(iv.precio_promedio,0), 2) AS costo_estimado
FROM insumos i
JOIN item it ON it.id = i.item_id
LEFT JOIN mes.partida_componente pc
       ON pc.partida_paso_id = i.paso_id AND pc.item_id = i.item_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = i.item_id
ORDER BY i.fyh_inicio, i.ejecucion_id, it.nombre;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION B — LAVADO_MAQUINA COMPLETADO with no egress
-- ═══════════════════════════════════════════════════════════════════════════════

-- B0. Summary
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
)
SELECT COUNT(*) AS lavados_sin_egreso, MIN(lm.fyh_inicio) AS primera, MAX(lm.fyh_inicio) AS ultima
FROM mes.lavado_maquina lm
CROSS JOIN params pr
WHERE lm.estado = 'COMPLETADO'
  AND COALESCE(lm.fyh_inicio, lm.fyh_fin) >= pr.win_ini
  AND COALESCE(lm.fyh_inicio, lm.fyh_fin) <  pr.win_fin
  AND NOT EXISTS (
      SELECT 1 FROM inventario.item_movimientos im
      WHERE im.documento_tipo = 'lavado_maquina' AND im.documento_id = lm.id
  );


-- B1. Per-insumo fixed egress for each affected lavado
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
),
lavados AS (
    SELECT lm.id AS lavado_id, lm.receta_id, lm.maquina_id,
           COALESCE(lm.fyh_inicio, lm.fyh_fin) AS fyh_evento
    FROM mes.lavado_maquina lm
    CROSS JOIN params pr
    WHERE lm.estado = 'COMPLETADO'
      AND COALESCE(lm.fyh_inicio, lm.fyh_fin) >= pr.win_ini
      AND COALESCE(lm.fyh_inicio, lm.fyh_fin) <  pr.win_fin
      AND NOT EXISTS (
          SELECT 1 FROM inventario.item_movimientos im
          WHERE im.documento_tipo = 'lavado_maquina' AND im.documento_id = lm.id
      )
)
SELECT
    lv.lavado_id,
    lv.fyh_evento,
    lv.maquina_id,
    mq.codigo                AS maquina,
    lmpi.item_id,
    it.codigo                AS insumo_codigo,
    it.nombre                AS insumo,
    SUM(lmpi.cantidad)       AS egreso,
    iv.precio_promedio,
    ROUND(SUM(lmpi.cantidad) * COALESCE(iv.precio_promedio,0), 2) AS costo_estimado
FROM lavados lv
JOIN receta.lavado_maquina_paso        lmp  ON lmp.receta_id = lv.receta_id
JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id  = lmp.id
JOIN item it                ON it.id = lmpi.item_id
LEFT JOIN mes.maquina mq    ON mq.id = lv.maquina_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = lmpi.item_id
GROUP BY lv.lavado_id, lv.fyh_evento, lv.maquina_id, mq.codigo,
         lmpi.item_id, it.codigo, it.nombre, iv.precio_promedio
ORDER BY lv.fyh_evento, lv.lavado_id, it.nombre;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION C — total valorized impact + cuadre exposure
-- ═══════════════════════════════════════════════════════════════════════════════

-- C0. Open cuadre(s) whose snapshot will need adjusting (fecha_cuadre = the cutoff).
SELECT c.id AS cuadre_id, c.estado, c.almacen_id, c.fecha_cuadre, c.fecha_cierre,
       (SELECT COUNT(*) FROM inventario.cuadre_detalle cd WHERE cd.cuadre_id = c.id) AS items_en_snapshot
FROM inventario.cuadre c
WHERE c.estado <> 'cancelado'
ORDER BY c.fecha_cuadre DESC;

-- C1. How much of the backfill lands BEFORE the latest open cuadre's cutoff
--     (i.e. must be subtracted from cuadre_detalle.cantidad_sistema). Per item.
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
),
cutoff AS (
    SELECT MAX(fecha_cuadre) AS fecha_cuadre
    FROM inventario.cuadre
    WHERE estado IN ('borrador','preparado')
),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'),
-- tenido lines
pasos AS (
    SELECT pe.id AS ejecucion_id, pp.id AS paso_id, pp.partida_id, pp.receta_id,
           COALESCE(pe.maquina_id, pp.maquina_planificada_id) AS maquina_id,
           pp.relacion_bano_objetivo,
           COALESCE(pe.fyh_fin, pe.fyh_inicio) AS fyh_evento
    FROM mes.partida_paso_ejecucion pe
    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
    JOIN mes.partida p       ON p.id  = pp.partida_id
    CROSS JOIN params pr
    WHERE pe.estado = 'COMPLETADO' AND pp.receta_id IS NOT NULL
      AND p.estado_produccion <> 'CANCELADA'
      AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
      AND NOT EXISTS (
          SELECT 1 FROM inventario.item_movimientos im
          JOIN egr_tipo et             ON et.id      = im.item_movimiento_tipo_id
          JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
          WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = pe.id)
),
ctx AS (
    SELECT s.*, GREATEST(pz.peso, m.capacidad_min_kg)
                  * COALESCE(s.relacion_bano_objetivo, m.relacion_bano) AS volumen,
           pz.peso
    FROM pasos s
    LEFT JOIN mes.maquina m ON m.id = s.maquina_id
    LEFT JOIN (
        SELECT s2.ejecucion_id, SUM(l.cantidad) AS peso
        FROM pasos s2
        JOIN mes.partida_componente pc ON pc.partida_id = s2.partida_id AND pc.lote_id IS NOT NULL
        JOIN inventario.lote l         ON l.id = pc.lote_id
        GROUP BY s2.ejecucion_id) pz ON pz.ejecucion_id = s.ejecucion_id
),
tenido_lines AS (
    SELECT c.fyh_evento, rtpi.item_id,
           COALESCE(
             pc.cantidad_reservada,
             ROUND(CASE iid.medida
                       WHEN 'g/L' THEN SUM(rtpi.cantidad) * c.volumen * iid.factor_stock
                       WHEN '%'   THEN SUM(rtpi.cantidad) * c.peso * 10 * iid.factor_stock
                   END, 4)) AS cantidad
    FROM ctx c
    JOIN receta.tenido_paso        rtp  ON rtp.receta_id = c.receta_id
    JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id  = rtp.id
    JOIN item_insumo_detalle       iid  ON iid.item_id   = rtpi.item_id
    LEFT JOIN mes.partida_componente pc ON pc.partida_paso_id = c.paso_id AND pc.item_id = rtpi.item_id
    GROUP BY c.fyh_evento, rtpi.item_id, iid.medida, iid.factor_stock, c.volumen, c.peso, pc.cantidad_reservada
),
lavado_lines AS (
    SELECT COALESCE(lm.fyh_inicio, lm.fyh_fin) AS fyh_evento, lmpi.item_id,
           SUM(lmpi.cantidad) AS cantidad
    FROM mes.lavado_maquina lm
    CROSS JOIN params pr
    JOIN receta.lavado_maquina_paso        lmp  ON lmp.receta_id = lm.receta_id
    JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id  = lmp.id
    WHERE lm.estado = 'COMPLETADO'
      AND COALESCE(lm.fyh_inicio, lm.fyh_fin) >= pr.win_ini
      AND COALESCE(lm.fyh_inicio, lm.fyh_fin) <  pr.win_fin
      AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      WHERE im.documento_tipo = 'lavado_maquina' AND im.documento_id = lm.id)
    GROUP BY COALESCE(lm.fyh_inicio, lm.fyh_fin), lmpi.item_id
),
all_lines AS (
    SELECT * FROM tenido_lines
    UNION ALL
    SELECT * FROM lavado_lines
)
SELECT
    a.item_id,
    it.codigo                                  AS insumo_codigo,
    it.nombre                                  AS insumo,
    it.flg_fungible,
    ROUND(SUM(a.cantidad), 4)                                              AS egreso_total,
    ROUND(SUM(a.cantidad) FILTER (
        WHERE (SELECT fecha_cuadre FROM cutoff) IS NOT NULL
          AND a.fyh_evento < (SELECT fecha_cuadre FROM cutoff)), 4)        AS egreso_antes_de_cuadre,
    COALESCE(sg.cantidad_total, 0)             AS stock_actual,
    CASE WHEN COALESCE(sg.cantidad_total,0) < SUM(a.cantidad)
         THEN '⚠ stock actual < egreso (lot FIFO quedará corto / negativo)' END AS advertencia_stock,
    ROUND(SUM(a.cantidad) * COALESCE(iv.precio_promedio,0), 2) AS costo_total
FROM all_lines a
JOIN item it ON it.id = a.item_id
LEFT JOIN inventario.vw_stock_items sg ON sg.item_id = a.item_id
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = a.item_id
GROUP BY a.item_id, it.codigo, it.nombre, it.flg_fungible, sg.cantidad_total, iv.precio_promedio
ORDER BY costo_total DESC NULLS LAST;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION D — (optional) PARTIAL consumption detector
-- Runs that DID register some insumo egress but fewer distinct insumos than the
-- recipe defines. Not handled by the backfill (which targets zero-egress runs);
-- review these manually.
-- ═══════════════════════════════════════════════════════════════════════════════
WITH params AS (
    SELECT '2026-01-01'::timestamptz AS win_ini,
           '2026-04-01'::timestamptz AS win_fin
),
egr_tipo AS (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO')
SELECT
    pe.id AS ejecucion_id, pp.partida_id, pp.receta_id, pe.fyh_inicio,
    (SELECT COUNT(DISTINCT rtpi.item_id)
     FROM receta.tenido_paso rtp JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id = rtp.id
     WHERE rtp.receta_id = pp.receta_id)                       AS insumos_receta,
    (SELECT COUNT(DISTINCT im.item_id)
     FROM inventario.item_movimientos im
     JOIN egr_tipo et ON et.id = im.item_movimiento_tipo_id
     JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
     WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = pe.id) AS insumos_consumidos
FROM mes.partida_paso_ejecucion pe
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p       ON p.id  = pp.partida_id
CROSS JOIN params pr
WHERE pe.estado = 'COMPLETADO' AND pp.receta_id IS NOT NULL
  AND p.estado_produccion <> 'CANCELADA'
  AND pe.fyh_inicio >= pr.win_ini AND pe.fyh_inicio < pr.win_fin
  AND EXISTS (
      SELECT 1 FROM inventario.item_movimientos im
      JOIN egr_tipo et             ON et.id      = im.item_movimiento_tipo_id
      JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
      WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = pe.id)
  AND (SELECT COUNT(DISTINCT im.item_id)
       FROM inventario.item_movimientos im
       JOIN egr_tipo et ON et.id = im.item_movimiento_tipo_id
       JOIN item_insumo_detalle iid ON iid.item_id = im.item_id
       WHERE im.documento_tipo = 'partida_paso_ejecucion' AND im.documento_id = pe.id)
      < (SELECT COUNT(DISTINCT rtpi.item_id)
         FROM receta.tenido_paso rtp JOIN receta.tenido_paso_insumo rtpi ON rtpi.paso_id = rtp.id
         WHERE rtp.receta_id = pp.receta_id)
ORDER BY pe.fyh_inicio;

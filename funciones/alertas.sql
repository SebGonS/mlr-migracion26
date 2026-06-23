-- ═══════════════════════════════════════════════════════════════
-- ALERT FUNCTIONS
-- Called by pg_cron on a schedule. Each function:
--   1. OPEN  — inserts alert rows for active conditions (skips if
--              an unresolved alert already exists for that user+object).
--   2. CLOSE — stamps fyh_resuelta on alerts whose condition has cleared.
--
-- All functions are SECURITY DEFINER and run as the function owner.
-- Not exposed to authenticated — called by pg_cron only.
-- ═══════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────
-- alertas.check_partidas_vencidas
-- Fires daily at 8am.
-- Condition: fecha_acordada < now() AND estado not terminal.
-- Resolves: when partida reaches CERRADA / CANCELADA / FACTURADA
--           or fecha_acordada is extended past today.
-- Notifies: jefe_planta, compras
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION alertas.check_partidas_vencidas()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'doc', 'iam', 'notification'
AS $$
BEGIN
    -- OPEN: partidas past due and not yet closed
    INSERT INTO notification.notifications (
        user_id, title, body, tipo, categoria,
        objeto_tipo, objeto_id, payload
    )
    SELECT
        ur.user_id,
        'Partida vencida',
        'La partida #' || p.numero || ' (' || c.nombre || ') venció el '
            || TO_CHAR(p.fecha_acordada, 'DD/MM/YYYY') || ' sin ser despachada.',
        'alert',
        'partida_vencida',
        'partida',
        p.id,
        jsonb_build_object('partida_id', p.id, 'numero', p.numero, 'cliente', c.nombre, 'fecha_acordada', p.fecha_acordada)
    FROM mes.partida p
    JOIN tercero c ON c.id = p.tercero_id
    CROSS JOIN (
        SELECT ur.user_id
        FROM iam.user_rol ur
        JOIN iam.rol r ON r.id = ur.rol_id
        WHERE r.code = ANY(ARRAY['jefe_planta', 'compras'])
    ) ur
    WHERE p.fecha_acordada < now()
      AND p.estado_produccion NOT IN ('CERRADA', 'CANCELADA')
      AND p.fyh_elm IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM notification.notifications n
          WHERE n.user_id     = ur.user_id
            AND n.categoria   = 'partida_vencida'
            AND n.objeto_tipo = 'partida'
            AND n.objeto_id   = p.id
            AND n.fyh_resuelta IS NULL
      )
    ON CONFLICT DO NOTHING;

    -- CLOSE: partidas that are now terminal or no longer overdue
    UPDATE notification.notifications
    SET fyh_resuelta = now()
    WHERE categoria   = 'partida_vencida'
      AND objeto_tipo = 'partida'
      AND fyh_resuelta IS NULL
      AND objeto_id IN (
          SELECT id FROM mes.partida
          WHERE estado_produccion IN ('CERRADA', 'CANCELADA')
             OR fecha_acordada >= now()
      );
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- alertas.check_rollos_sin_programar
-- Fires daily.
-- Condition: CLIENTE_ENVIO_PROCESO entrega with fecha_emision > 5 days
--            ago that still has at least one in-stock roll with no
--            partida_componente assignment.
-- Resolves: when all in-stock rolls from the entrega are assigned to a partida.
-- Notifies: jefe_planta, supervisor_produccion
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION alertas.check_rollos_sin_programar()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'doc', 'mes', 'inventario', 'iam', 'notification'
AS $$
BEGIN
    -- OPEN: entregas older than 5 days with at least one in-stock unassigned roll
    INSERT INTO notification.notifications (
        user_id, title, body, tipo, categoria,
        objeto_tipo, objeto_id, payload
    )
    SELECT
        ur.user_id,
        'Rollos sin programar',
        'La guía ' || gr.serie || '-' || gr.correlativo || ' de ' || t.nombre
            || ' lleva ' || (CURRENT_DATE - gr.fecha_emision::DATE)
            || ' días con rollos sin asignar a una orden de producción.',
        'alert',
        'rollo_sin_programar',
        'entrega',
        gr.id,
        jsonb_build_object(
            'entrega_id',  gr.id,
            'entrega_numero',       gr.serie || '-' || gr.correlativo,
            'tercero',           t.nombre,
            'dias_espera',       (CURRENT_DATE - gr.fecha_emision::DATE),
            'fecha_emision',     gr.fecha_emision
        )
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    JOIN tercero t ON t.id = gr.tercero_id
    CROSS JOIN (
        SELECT ur.user_id
        FROM iam.user_rol ur
        JOIN iam.rol r ON r.id = ur.rol_id
        WHERE r.code = ANY(ARRAY['jefe_planta', 'supervisor_produccion'])
    ) ur
    WHERE grt.codigo = 'CLIENTE_ENVIO_PROCESO'
      AND gr.fecha_emision < CURRENT_DATE - 5
      AND EXISTS (
          -- at least one in-stock roll with no partida assigned
          SELECT 1
          FROM inventario.lote_rollo_detalle lrd
          JOIN inventario.lote l              ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
          JOIN inventario.vw_stock_lotes sl   ON sl.lote_id = l.id
          LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
          WHERE lrd.entrega_id = gr.id
            AND pc.lote_id IS NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM notification.notifications n
          WHERE n.user_id     = ur.user_id
            AND n.categoria   = 'rollo_sin_programar'
            AND n.objeto_tipo = 'entrega'
            AND n.objeto_id   = gr.id
            AND n.fyh_resuelta IS NULL
      )
    ON CONFLICT DO NOTHING;

    -- CLOSE: entregas that no longer have any in-stock unassigned rolls
    UPDATE notification.notifications n
    SET fyh_resuelta = now()
    WHERE n.categoria   = 'rollo_sin_programar'
      AND n.objeto_tipo = 'entrega'
      AND n.fyh_resuelta IS NULL
      AND NOT EXISTS (
          SELECT 1
          FROM inventario.lote_rollo_detalle lrd
          JOIN inventario.lote l              ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
          JOIN inventario.vw_stock_lotes sl   ON sl.lote_id = l.id
          LEFT JOIN mes.partida_componente pc ON pc.lote_id = l.id
          WHERE lrd.entrega_id = n.objeto_id
            AND pc.lote_id IS NULL
      );
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- alertas.check_stock_bajo
-- Fires every 6 hours.
-- Condition: current stock < COALESCE(stock_minimo, avg_daily_60d × 7).
--   Items with no movement in 90 days AND no stock_minimo are skipped
--   (inactive items — no point alerting on zero-consumption dead stock).
-- Resolves: when stock rises back above reorder point.
-- Notifies: inventario, compras
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION alertas.check_stock_bajo()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'inventario', 'iam', 'notification'
AS $$
BEGIN
    -- OPEN: items below their reorder point
    INSERT INTO notification.notifications (
        user_id, title, body, tipo, categoria,
        objeto_tipo, objeto_id, payload
    )
    WITH consumo_60d AS (
        SELECT
            im.item_id,
            SUM(im.cantidad) / 60.0 AS avg_daily
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        WHERE im.origen_ubicacion_id IS NOT NULL
          AND imt.categoria NOT IN ('PRODUCCION', 'TRANSFERENCIA')
          AND im.fecha_hora >= now() - interval '60 days'
        GROUP BY im.item_id
    ),
    actividad_90d AS (
        SELECT DISTINCT im.item_id
        FROM inventario.item_movimientos im
        WHERE im.fecha_hora >= now() - interval '90 days'
    ),
    stock_actual AS (
        SELECT item_id, COALESCE(cantidad_total, 0) AS cantidad
        FROM inventario.vw_stock_insumos
    ),
    items_bajo AS (
        SELECT
            i.id                                                        AS item_id,
            i.nombre                                                    AS item_nombre,
            COALESCE(sa.cantidad, 0)                                    AS stock_actual,
            COALESCE(i.stock_minimo, COALESCE(c.avg_daily, 0) * 7)     AS reorder_point,
            un.codigo                                                   AS unidad
        FROM item i
        JOIN item_tipo it  ON it.id = i.item_tipo_id AND it.codigo = 'INSUMO'
        JOIN unidad un     ON un.id = i.unidad_id
        LEFT JOIN stock_actual  sa ON sa.item_id = i.id
        LEFT JOIN consumo_60d   c  ON c.item_id  = i.id
        LEFT JOIN actividad_90d a  ON a.item_id  = i.id
        WHERE i.fyh_elm IS NULL
          AND (i.stock_minimo IS NOT NULL OR a.item_id IS NOT NULL)
          AND COALESCE(sa.cantidad, 0) < COALESCE(i.stock_minimo, COALESCE(c.avg_daily, 0) * 7)
          AND COALESCE(i.stock_minimo, COALESCE(c.avg_daily, 0) * 7) > 0
    )
    SELECT
        ur.user_id,
        'Stock bajo: ' || ib.item_nombre,
        'El stock de ' || ib.item_nombre || ' (' || ib.stock_actual || ' ' || ib.unidad
            || ') está por debajo del punto de reorden (' || ROUND(ib.reorder_point, 2) || ' ' || ib.unidad || ').',
        'alert',
        'stock_bajo',
        'item',
        ib.item_id,
        jsonb_build_object(
            'item_id',       ib.item_id,
            'item_nombre',   ib.item_nombre,
            'stock_actual',  ib.stock_actual,
            'reorder_point', ROUND(ib.reorder_point, 2),
            'unidad',        ib.unidad
        )
    FROM items_bajo ib
    CROSS JOIN (
        SELECT ur.user_id
        FROM iam.user_rol ur
        JOIN iam.rol r ON r.id = ur.rol_id
        WHERE r.code = ANY(ARRAY['inventario', 'compras'])
    ) ur
    WHERE NOT EXISTS (
        SELECT 1 FROM notification.notifications n
        WHERE n.user_id     = ur.user_id
          AND n.categoria   = 'stock_bajo'
          AND n.objeto_tipo = 'item'
          AND n.objeto_id   = ib.item_id
          AND n.fyh_resuelta IS NULL
    )
    ON CONFLICT DO NOTHING;

    -- CLOSE: items that have recovered above their reorder point
    UPDATE notification.notifications n
    SET fyh_resuelta = now()
    WHERE n.categoria   = 'stock_bajo'
      AND n.objeto_tipo = 'item'
      AND n.fyh_resuelta IS NULL
      AND NOT EXISTS (
          WITH consumo_60d AS (
              SELECT im.item_id, SUM(im.cantidad) / 60.0 AS avg_daily
              FROM inventario.item_movimientos im
              JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
              WHERE im.origen_ubicacion_id IS NOT NULL
          AND imt.categoria NOT IN ('PRODUCCION', 'TRANSFERENCIA')
                AND im.fecha_hora >= now() - interval '60 days'
              GROUP BY im.item_id
          ),
          stock_actual AS (
              SELECT item_id, COALESCE(cantidad_total, 0) AS cantidad
              FROM inventario.vw_stock_insumos
          )
          SELECT 1
          FROM item i
          LEFT JOIN stock_actual sa ON sa.item_id = i.id
          LEFT JOIN consumo_60d  c  ON c.item_id  = i.id
          WHERE i.id = n.objeto_id
            AND COALESCE(sa.cantidad, 0) < COALESCE(i.stock_minimo, COALESCE(c.avg_daily, 0) * 7)
      );
END;
$$;


-- ───────────────────────────────────────────────────────────────
-- alertas.check_stock_pasos
-- Fires every 6 hours (aligned with check_stock_bajo).
-- Condition: a planned paso with requiere_receta=true has insufficient
--   insumo stock to cover its full chemical demand (recipe dose × roll kg).
--   Demand = SUM(tpi.cantidad × pc.cantidad_reservada / conversion_factor)
--   where conversion_factor = 1000 for g_kg (g per kg → kg), 100 for pct.
-- Resolves: when stock rises above demand, or the paso is completed.
-- Notifies: jefe_planta, supervisor_produccion, inventario, compras
-- ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION alertas.check_stock_pasos()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'inventario', 'mes', 'receta', 'iam', 'notification'
AS $$
BEGIN
    -- OPEN: pasos whose recipe insumo demand exceeds available stock
    INSERT INTO notification.notifications (
        user_id, title, body, tipo, categoria,
        objeto_tipo, objeto_id, payload
    )
    WITH paso_demanda AS (
        SELECT
            pp.id                                                           AS paso_id,
            tpi.item_id,
            SUM(
                tpi.cantidad * pc.cantidad_reservada
                / CASE WHEN tpi.medida = 'pct' THEN 100.0 ELSE 1000.0 END
            )                                                               AS kg_demandado
        FROM mes.partida_paso pp
        JOIN mes.operacion op          ON op.id = pp.operacion_id AND op.requiere_receta = true
        JOIN mes.partida_componente pc ON pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL
        JOIN receta.tenido rt          ON rt.id = pp.receta_id AND rt.flg_produccion = true
        JOIN receta.tenido_paso rtp    ON rtp.receta_id = rt.id
        JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = rtp.id
        WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
        )
        GROUP BY pp.id, tpi.item_id
    ),
    stock_disponible AS (
        SELECT item_id, COALESCE(cantidad_total, 0) AS cantidad
        FROM inventario.vw_stock_insumos
    ),
    deficit AS (
        SELECT
            pd.paso_id,
            pd.item_id,
            i.nombre                         AS item_nombre,
            pd.kg_demandado,
            COALESCE(sd.cantidad, 0)         AS stock_actual,
            un.codigo                        AS unidad
        FROM paso_demanda pd
        JOIN item i           ON i.id  = pd.item_id
        JOIN unidad un        ON un.id = i.unidad_id
        LEFT JOIN stock_disponible sd ON sd.item_id = pd.item_id
        WHERE COALESCE(sd.cantidad, 0) < pd.kg_demandado
    )
    SELECT
        ur.user_id,
        'Stock insuficiente para paso',
        'El paso #' || d.paso_id || ' requiere ' || ROUND(d.kg_demandado, 2)
            || ' ' || d.unidad || ' de ' || d.item_nombre
            || ' pero solo hay ' || ROUND(d.stock_actual, 2) || ' ' || d.unidad || ' disponibles.',
        'alert',
        'stock_paso',
        'partida_paso',
        d.paso_id,
        jsonb_build_object(
            'paso_id',      d.paso_id,
            'item_id',      d.item_id,
            'item_nombre',  d.item_nombre,
            'kg_demandado', ROUND(d.kg_demandado, 2),
            'stock_actual', ROUND(d.stock_actual, 2),
            'unidad',       d.unidad
        )
    FROM deficit d
    CROSS JOIN (
        SELECT ur.user_id
        FROM iam.user_rol ur
        JOIN iam.rol r ON r.id = ur.rol_id
        WHERE r.code = ANY(ARRAY['jefe_planta', 'supervisor_produccion', 'inventario', 'compras'])
    ) ur
    WHERE NOT EXISTS (
        SELECT 1 FROM notification.notifications n
        WHERE n.user_id     = ur.user_id
          AND n.categoria   = 'stock_paso'
          AND n.objeto_tipo = 'partida_paso'
          AND n.objeto_id   = d.paso_id
          AND n.fyh_resuelta IS NULL
    )
    ON CONFLICT DO NOTHING;

    -- CLOSE: deficit cleared (stock recovered or paso completed)
    UPDATE notification.notifications n
    SET fyh_resuelta = now()
    WHERE n.categoria   = 'stock_paso'
      AND n.objeto_tipo = 'partida_paso'
      AND n.fyh_resuelta IS NULL
      AND NOT EXISTS (
          WITH paso_demanda AS (
              SELECT
                  pp.id                                            AS paso_id,
                  tpi.item_id,
                  SUM(
                      tpi.cantidad * pc.cantidad_reservada
                      / CASE WHEN tpi.medida = 'pct' THEN 100.0 ELSE 1000.0 END
                  )                                                AS kg_demandado
              FROM mes.partida_paso pp
              JOIN mes.operacion op          ON op.id = pp.operacion_id AND op.requiere_receta = true
              JOIN mes.partida_componente pc ON pc.partida_id = pp.partida_id AND pc.lote_id IS NOT NULL
              JOIN receta.tenido rt          ON rt.id = pp.receta_id AND rt.flg_produccion = true
              JOIN receta.tenido_paso rtp    ON rtp.receta_id = rt.id
              JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = rtp.id
              WHERE pp.id = n.objeto_id
                AND NOT EXISTS (
                    SELECT 1 FROM mes.partida_paso_ejecucion pe
                    WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
                )
              GROUP BY pp.id, tpi.item_id
          ),
          stock_disponible AS (
              SELECT item_id, COALESCE(cantidad_total, 0) AS cantidad
              FROM inventario.vw_stock_insumos
          )
          SELECT 1
          FROM paso_demanda pd
          LEFT JOIN stock_disponible sd ON sd.item_id = pd.item_id
          WHERE COALESCE(sd.cantidad, 0) < pd.kg_demandado
      );
END;
$$;


-- ── Grants ───────────────────────────────────────────────────────
-- Called by pg_cron (runs as postgres). No authenticated access.
REVOKE EXECUTE ON FUNCTION alertas.check_partidas_vencidas()    FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION alertas.check_rollos_sin_programar() FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION alertas.check_stock_bajo()           FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION alertas.check_stock_pasos()          FROM PUBLIC, authenticated, anon;

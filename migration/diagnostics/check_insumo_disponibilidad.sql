-- check_insumo_disponibilidad.sql
-- Neutral "true available stock" check for an insumo: physical stock minus all
-- currently-open chemical reservations (mes.partida_componente), regardless of
-- which paso holds them. This is the same net figure generar_receta's stock gate
-- and registrar_consumo_paso's stock check compute (they additionally exclude the
-- one paso being acted on — irrelevant here since this is a general-purpose check).

WITH params AS (
    SELECT CAST(123 AS int) AS item_id   -- <-- edit: the insumo to check
),
reservado AS (
    SELECT pc.item_id, SUM(pc.cantidad_reservada) AS cantidad_reservada
    FROM params, mes.partida_componente pc
    JOIN mes.partida_paso pp ON pp.id = pc.partida_paso_id
    JOIN mes.partida p       ON p.id  = pc.partida_id
    WHERE pc.item_id = params.item_id
      AND p.estado_produccion NOT IN ('CERRADA', 'CANCELADA', 'TECO')
      AND p.fyh_elm IS NULL
      AND pp.estado NOT IN ('COMPLETADO', 'OMITIDO')
    GROUP BY pc.item_id
)
SELECT i.id AS item_id, i.codigo, i.nombre, i.flg_fungible,
       COALESCE(s.cantidad_total, 0)            AS stock_fisico,
       COALESCE(r.cantidad_reservada, 0)         AS reservado_total,
       COALESCE(s.cantidad_total, 0) - COALESCE(r.cantidad_reservada, 0) AS stock_neto_disponible
FROM params
JOIN item i ON i.id = params.item_id
LEFT JOIN inventario.vw_stock_items s ON s.item_id = params.item_id
LEFT JOIN reservado r ON r.item_id = params.item_id;

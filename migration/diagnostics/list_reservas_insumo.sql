-- list_reservas_insumo.sql
-- Lists every chemical reservation (mes.partida_componente, item_id NOT NULL) for
-- a given insumo, active or not, with enough context to see which ones would
-- count toward "reservado" in check_insumo_disponibilidad.sql and why.

WITH params AS (
    SELECT CAST(7 AS int) AS item_id   -- <-- edit: the insumo to check
)
SELECT pc.id AS partida_componente_id,
       pc.partida_id, pc.partida_paso_id,
       p.estado_produccion, pp.estado AS paso_estado,
       pp.operacion_id, o.nombre AS operacion,
       pc.cantidad_reservada,
       pc.fyh_cre AS reservado_desde,
       CASE
           WHEN p.estado_produccion IN ('CERRADA','CANCELADA','TECO')
                OR p.fyh_elm IS NOT NULL
                OR pp.estado IN ('COMPLETADO','OMITIDO')
           THEN 'INACTIVA (no cuenta)'
           ELSE 'ACTIVA (cuenta)'
       END AS clasificacion
FROM params, mes.partida_componente pc
JOIN mes.partida_paso pp ON pp.id = pc.partida_paso_id
JOIN mes.partida p       ON p.id  = pc.partida_id
LEFT JOIN mes.operacion o ON o.id = pp.operacion_id
WHERE pc.item_id = params.item_id
ORDER BY clasificacion, pc.fyh_cre DESC;

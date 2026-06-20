-- Drop articulo_id from orden_servicio_detalle.
-- Redundant: always derivable via item_rollo_detalle.articulo_id for a given item_id.
-- get_orden_servicio now JOINs item_rollo_detalle to supply articulo_id to the frontend.
ALTER TABLE doc.orden_servicio_detalle
    DROP COLUMN articulo_id;

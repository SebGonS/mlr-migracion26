-- Add item_id to orden_servicio_detalle — should have been there from the start,
-- mirrors entrega_detalle.item_id. Nullable to allow backfill before NOT NULL.
ALTER TABLE doc.orden_servicio_detalle
    ADD COLUMN item_id INT REFERENCES item(id);

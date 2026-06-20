-- Add factura_hilo to lote_rollo_detalle.
-- Thread (hilo) supplier invoice the roll was spun from. Free-text reference,
-- NOT an FK — bridges the unmapped confection process to dyeing. Entered once
-- per OS line, fanned to every roll on that line by crear_orden_servicio.
ALTER TABLE inventario.lote_rollo_detalle
    ADD COLUMN factura_hilo TEXT;

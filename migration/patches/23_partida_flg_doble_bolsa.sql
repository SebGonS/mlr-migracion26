-- Add flg_doble_bolsa to mes.partida.
-- Carries packing instruction from orden_servicio_detalle through the production lifecycle.
-- Displayed on print/scheduling board via get_programacion_diaria and get_partida.
-- Frontend composes display: appends "Doble bolsa" to observacion when true.
ALTER TABLE mes.partida
    ADD COLUMN flg_doble_bolsa BOOLEAN NOT NULL DEFAULT false;

-- Add operacion_id to mes.maquina_tipo to make the implicit machine↔operation
-- relationship explicit and queryable for frontend filtering.
ALTER TABLE mes.maquina_tipo
    ADD COLUMN operacion_id SMALLINT REFERENCES mes.operacion(id);

-- Populate from known type↔operation mappings
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')       WHERE codigo = 'TEN';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'LAVADO_HIDRO') WHERE codigo = 'HIDRO';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'SECADO')       WHERE codigo = 'SEC';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TERMOFIJADO')  WHERE codigo = 'TERMO';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'PERCHADO')     WHERE codigo = 'PERCH';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'COMPACTADO')   WHERE codigo = 'COMPACT';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'VOLTEADO')     WHERE codigo = 'VOLT';
UPDATE mes.maquina_tipo SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'PLANCHADO')    WHERE codigo = 'PLANCH';

SELECT * FROm mes.maquina_tipo
SELECT * FROm mes.operacion
SELECT * FROm mes.maquina
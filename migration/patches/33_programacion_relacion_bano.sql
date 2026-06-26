-- patch 33: move relacion_bano from paso to programacion
--
-- relacion_bano_objetivo on partida_paso is machine-coupled (default + min/max come
-- from the machine). A paso carries no machine after patch 32, so the column is an
-- unvalidatable orphan. Bath ratio belongs where the machine is known: programacion
-- (plan) and ejecucion (actual, already has relacion_bano_real).
--
-- NULL programacion.relacion_bano  = use machine standard (existing behaviour).
--
-- DEPLOY ORDER:
--   1. Redeploy funciones/mes.sql  (generar_receta, iniciar_paso)
--   2. Redeploy funciones/core.sql (crear_partida, actualizar_pasos_partida)
--   3. Redeploy migration/08_views.sql (vw_pasos — prog lateral gains relacion_bano)
--   4. Run this patch

ALTER TABLE mes.partida_paso
    DROP COLUMN IF EXISTS relacion_bano_objetivo;

ALTER TABLE mes.programacion
    ADD COLUMN IF NOT EXISTS relacion_bano NUMERIC(6,2);

COMMENT ON COLUMN mes.programacion.relacion_bano IS
    'Custom bath ratio for this scheduled run. NULL = use machine standard (maquina.relacion_bano).';


    SELECT mes.get_partida(6216)  
-- patch 32: clean up paso planning fields now that machine lives on programacion
--
-- partida_paso no longer carries machine or bath ratio. Both are machine-coupled
-- and belong where the machine is known:
--
--   Machine:      mes.programacion.maquina_id        (plan — the scheduling board)
--                 mes.partida_paso_ejecucion.maquina_id (actual — the run)
--
--   Bath ratio:   mes.programacion.relacion_bano      (nullable custom; NULL = machine standard)
--                 mes.partida_paso_ejecucion.relacion_bano_real (actual)
--
-- ph_objetivo and temperatura_objetivo stay on paso — they are machine-independent
-- chemistry targets.
--
-- DEPLOY ORDER:
--   1. Redeploy funciones/mes.sql  (generar_receta, iniciar_paso)
--   2. Redeploy funciones/core.sql (crear_partida, actualizar_pasos_partida)
--   3. Redeploy migration/08_views.sql (vw_pasos — prog lateral gains relacion_bano)
--   4. Run this patch

ALTER TABLE mes.partida_paso
    DROP COLUMN IF EXISTS maquina_planificada_id;

ALTER TABLE mes.partida_paso
    DROP COLUMN IF EXISTS relacion_bano_objetivo;

ALTER TABLE mes.programacion
    ADD COLUMN IF NOT EXISTS relacion_bano NUMERIC(6,2)
        CONSTRAINT chk_prog_relacion_bano CHECK (relacion_bano > 0);

COMMENT ON COLUMN mes.programacion.relacion_bano IS
    'Custom bath ratio for this scheduled run. NULL = use machine standard (maquina.relacion_bano).';

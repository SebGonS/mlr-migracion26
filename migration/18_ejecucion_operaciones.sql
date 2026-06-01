-- Extend partida_paso_ejecucion with operation-specific nullable columns.
-- Follows existing pattern of ph_real / temperatura_real / relacion_bano_real.
-- Only TERMOFIJADO retains an extension table (7 fields with no cross-operation meaning).
ALTER TABLE mes.partida_paso_ejecucion
    ADD COLUMN receta_id           int REFERENCES receta.tenido(id),  -- snapshot of paso.receta_id at iniciar time; immutable
    ADD COLUMN ancho_entrada       numeric(6,2),
    ADD COLUMN ancho_salida        numeric(6,2),
    ADD COLUMN velocidad           numeric(6,2),   -- HIDRO, SECADO, COMPACTADO
    ADD COLUMN entrada             numeric(6,2),   -- HIDRO
    ADD COLUMN salida              numeric(6,2),   -- HIDRO
    ADD COLUMN rendimiento         numeric(6,4),   -- COMPACTADO
    ADD COLUMN pases               smallint,       -- PERCHADO
    ADD COLUMN malla_alimentacion  numeric(5,2);   -- SECADO

-- Prevent retroactive changes to the recipe snapshot.
CREATE OR REPLACE FUNCTION mes.fn_trg_ejecucion_receta_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.receta_id IS NOT NULL AND OLD.receta_id IS DISTINCT FROM NEW.receta_id THEN
        RAISE EXCEPTION 'receta_id es inmutable en partida_paso_ejecucion (id=%). La receta se fija al iniciar el paso.', OLD.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bu_ejecucion_receta_immutable
BEFORE UPDATE OF receta_id ON mes.partida_paso_ejecucion
FOR EACH ROW EXECUTE FUNCTION mes.fn_trg_ejecucion_receta_immutable();

-- ── TERMOFIJADO extension ─────────────────────────────────────────
-- ancho_entrada / ancho_salida / temperatura_real handled by base columns above.
CREATE TABLE mes.partida_paso_ejecucion_termofijado (
    ejecucion_id        bigint PRIMARY KEY REFERENCES mes.partida_paso_ejecucion(id) ON DELETE CASCADE,
    ancho_marco         numeric(6,2)  NOT NULL,
    vel_maquina         numeric(6,2)  NOT NULL,
    vel_alimentacion    numeric(6,2)  NOT NULL,
    densidad_entrada    numeric(8,4)  NOT NULL,
    densidad_salida     numeric(8,4)  NOT NULL,
    lm                  numeric(10,2) NOT NULL,
    galga               numeric(5,2)  NOT NULL,
    usr_cre int,
    fyh_cre timestamptz DEFAULT now(),
    usr_mod int,
    fyh_mod timestamptz
);

ALTER TABLE mes.partida_paso_ejecucion_termofijado ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "produccion_ver" ON mes.partida_paso_ejecucion_termofijado;
CREATE POLICY "produccion_ver" ON mes.partida_paso_ejecucion_termofijado
    FOR SELECT TO authenticated USING (jwt_has_permission('produccion.ver'));

CREATE TRIGGER trg_bi_partida_paso_ejecucion_termofijado_audit
    BEFORE INSERT ON mes.partida_paso_ejecucion_termofijado
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_paso_ejecucion_termofijado_audit
    BEFORE UPDATE ON mes.partida_paso_ejecucion_termofijado
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();


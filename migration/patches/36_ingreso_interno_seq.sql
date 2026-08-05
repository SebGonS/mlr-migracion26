-- ═══════════════════════════════════════════════════════════════════════════════
-- 36 · INGRESO_INTERNO auto-sequence
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY: Multiple INGRESO_INTERNO entregas can share the same hilo supplier invoice
-- (same factura, different ingress dates). Storing the invoice in serie/correlativo
-- collides on the UNIQUE(tercero_id, serie, correlativo, entrega_tipo_id) constraint.
--
-- Fix: auto-generate serie='II' + correlativo=nextval(seq) as the stable internal
-- reference. The hilo invoice reference moves to entrega.observacion via the
-- `referencia_hilo` input key.
--
-- After running: redeploy funciones/core.sql (crear_ingreso_interno updated).
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SEQUENCE IF NOT EXISTS doc.ingreso_interno_seq START 1;

-- Backfill existing INGRESO_INTERNO entregas so they conform to the new scheme.
-- serie was 'OS-<id>' (migration discriminator) — replace with 'II' + seq value.
-- correlativo was the hilo invoice — move to observacion.
DO $$
DECLARE
    v_ent_tipo_id SMALLINT;
    v_rec         RECORD;
    v_seq         BIGINT;
BEGIN
    SELECT id INTO STRICT v_ent_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'INGRESO_INTERNO';

    FOR v_rec IN
        SELECT id, serie, correlativo
        FROM doc.entrega
        WHERE entrega_tipo_id = v_ent_tipo_id
        ORDER BY id
    LOOP
        v_seq := nextval('doc.ingreso_interno_seq');

        UPDATE doc.entrega
        SET serie       = 'II',
            correlativo = v_seq::TEXT,
            -- preserve the old invoice ref in observacion if not already set
            observacion = COALESCE(observacion, v_rec.correlativo)
        WHERE id = v_rec.id;
    END LOOP;
END;
$$;

GRANT USAGE ON SEQUENCE doc.ingreso_interno_seq TO authenticated;

COMMIT;

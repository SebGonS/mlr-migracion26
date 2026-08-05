-- ═══════════════════════════════════════════════════════════════════════════════
-- 43 · INGRESO_INTERNO: serie becomes the auto-generated collision guard,
--      correlativo stays the factura hilo
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY: doc.entrega was never given an observacion column (patch 07 only added it
-- to doc.orden_servicio). Both the pre-existing crear_ingreso_interno (committed,
-- pre-this-session) and patch 36 (36_ingreso_interno_seq.sql) tried to write
-- p_datos->>'observacion' into doc.entrega — both would have failed with
-- "column observacion of relation entrega does not exist" the moment they ran.
-- Nothing else reads/writes doc.entrega.observacion, so crear_ingreso_interno
-- (funciones/core.sql) has been fixed to drop that column from its INSERT
-- entirely rather than adding unused schema.
--
-- Patch 36 never ran against the live DB (confirmed) — so doc.entrega still
-- holds whatever patch 35 left: serie='OS-<os.id>' + correlativo=os.factura for
-- rows migrated from orden_servicio, or serie/correlativo written directly from
-- p_datos->>'serie' / p_datos->>'correlativo' by the older (pre-session)
-- crear_ingreso_interno signature, with no auto-generation.
--
-- Fix: for existing INGRESO_INTERNO rows, regenerate serie as 'II-<seq>' so
-- it's always unique; leave correlativo (factura hilo) untouched — it already
-- holds the right value from patch 35 or the prior crear_ingreso_interno.
--
-- After running: redeploy funciones/core.sql (crear_ingreso_interno updated;
-- p_datos key is now 'correlativo' (required, the factura hilo), writes it
-- directly to the correlativo column, serie is auto-generated 'II-'||seq,
-- no longer writes observacion at all).
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SEQUENCE IF NOT EXISTS doc.ingreso_interno_seq START 1;
GRANT USAGE ON SEQUENCE doc.ingreso_interno_seq TO authenticated;

DO $$
DECLARE
    v_ent_tipo_id SMALLINT;
    v_rec         RECORD;
    v_seq         BIGINT;
BEGIN
    SELECT id INTO STRICT v_ent_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'INGRESO_INTERNO';

    FOR v_rec IN
        SELECT id
        FROM doc.entrega
        WHERE entrega_tipo_id = v_ent_tipo_id
        ORDER BY id
    LOOP
        v_seq := nextval('doc.ingreso_interno_seq');

        UPDATE doc.entrega
        SET serie = 'II-' || v_seq::TEXT
        WHERE id = v_rec.id;
    END LOOP;
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════
-- Step 13: Backfill support — mes.empleado + mes.orden_produccion_paso
-- ═══════════════════════════════════════════════════════════════

-- Allow linking a plant-floor employee to their auth user account.
-- Used for backfill attribution and future employee portal login.
ALTER TABLE mes.empleado
    ADD COLUMN IF NOT EXISTS activo     BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS perfil_id  INT     REFERENCES public.usuario(id);

-- Free-text field for supervisors to note context when registering
-- production retroactively (e.g. "sistema caído, dato tomado del turno").
ALTER TABLE mes.orden_produccion_paso
    ADD COLUMN IF NOT EXISTS observacion_backfill TEXT;

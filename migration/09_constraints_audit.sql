-- ═══════════════════════════════════════════════════════════════
-- Step 9: Audit schema, triggers, and REVOKEs
-- This is constraints.sql verbatim — no changes needed.
-- Run AFTER all tables exist.
-- ═══════════════════════════════════════════════════════════════

-- Source: constraints.sql (run that file as-is for this step)
-- Included here as a reference pointer only.
-- To execute: \i constraints.sql  (or paste contents)

-- The lote sequence trigger (from constraints.sql) is critical:
--   inventario.trfn_generar_secuencia_lote → trg_bi_lote_secuencia ON inventario.lote

-- All audit triggers from constraints.sql depend on:
--   audit.fn_audit_row (defined in constraints.sql itself)
--   public.fn_trg_set_cre_fields / fn_trg_set_mod_fields / fn_trg_set_elm_fields (step 3)

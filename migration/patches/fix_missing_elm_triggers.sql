-- ═══════════════════════════════════════════════════════════════
-- Patch: missing elm triggers on soft-deletable tables
--
-- These were omitted from step 12. Each table already has usr_elm/fyh_elm
-- columns; this patch wires up fn_trg_set_elm_fields() so that setting
-- fyh_elm on UPDATE automatically populates usr_elm = get_user_id()
-- and normalises fyh_elm = now().
-- ═══════════════════════════════════════════════════════════════

CREATE TRIGGER trg_bu_partida_elm
    BEFORE UPDATE ON mes.partida
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

CREATE TRIGGER trg_bu_guia_remision_elm
    BEFORE UPDATE ON doc.guia_remision
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

CREATE TRIGGER trg_bu_lote_elm
    BEFORE UPDATE ON inventario.lote
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

CREATE TRIGGER trg_bu_catalogo_precios_elm
    BEFORE UPDATE ON doc.catalogo_precios
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

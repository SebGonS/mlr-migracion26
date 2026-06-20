-- Audit triggers for doc.orden_servicio + doc.orden_servicio_detalle
-- Mirrors the pattern on doc.guia_remision / doc.guia_remision_detalle.

CREATE TRIGGER trg_biud_orden_servicio_audit
    BEFORE INSERT OR UPDATE OR DELETE ON doc.orden_servicio
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();

CREATE TRIGGER trg_bi_orden_servicio_audit
    BEFORE INSERT ON doc.orden_servicio
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

CREATE TRIGGER trg_bu_orden_servicio_audit
    BEFORE UPDATE ON doc.orden_servicio
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

CREATE TRIGGER trg_biud_orden_servicio_detalle_audit
    BEFORE INSERT OR UPDATE OR DELETE ON doc.orden_servicio_detalle
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();

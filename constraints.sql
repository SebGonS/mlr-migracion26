CREATE SCHEMA IF NOT EXISTS audit;
CREATE TABLE audit.data_audit (
    audit_id      bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,

    schema_name   TEXT NOT NULL,
    table_name    TEXT NOT NULL,

    row_id        bigint NOT NULL,          -- PK(s) of the affected row
    operacion     TEXT NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),

    old_data      JSONB,                   -- NULL for INSERT
    new_data      JSONB,                   -- NULL for DELETE

    usr_id        int,                    -- auth.uid() in Supabase
    fyh_evento    TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE OR REPLACE FUNCTION public.fn_trg_set_cre_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
        NEW.usr_cre := COALESCE(NEW.usr_cre, get_user_id());
        NEW.fyh_cre := COALESCE(NEW.fyh_cre, now());
    RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION public.fn_trg_set_mod_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
        NEW.usr_cre := OLD.usr_cre;
        NEW.fyh_cre := OLD.fyh_cre;
        NEW.usr_mod := get_user_id();
        NEW.fyh_mod := now();
    RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION public.fn_trg_set_elm_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- detect transition: NOT deleted → deleted
    IF OLD.flg_elm IS FALSE
       AND NEW.flg_elm IS TRUE
       AND OLD.fyh_elm IS NULL
    THEN
        NEW.usr_elm := get_user_id();
        NEW.fyh_elm := now();
    END IF;

    RETURN NEW;
END;
$$;

   
CREATE OR REPLACE FUNCTION audit.fn_audit_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$

DECLARE
    v_id bigint;
BEGIN
IF TG_TABLE_SCHEMA = 'audit' THEN
    RETURN COALESCE(NEW, OLD);
END IF;
    -- assume single-column PK named "id"
    -- if you have composite PKs, adapt this
    v_id := COALESCE(NEW.id, OLD.id);
    INSERT INTO audit.data_audit (
        schema_name,
        table_name,
        row_id,
        operacion,
        old_data,
        new_data,
        usr_id
    )
    VALUES (
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        v_id,
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
        CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END,
        get_user_id()
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

-----UNIDAD
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON unidad
FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)
ON unidad
FROM anon, authenticated;
CREATE TRIGGER trg_bi_unidad_audit
BEFORE INSERT ON unidad
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_unidad_audit
BEFORE UPDATE ON unidad
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----ITEM TIPO

REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON item_tipo
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON item_tipo
FROM anon, authenticated;

CREATE TRIGGER trg_bi_item_tipo_audit
BEFORE INSERT ON item_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_tipo_audit
BEFORE UPDATE ON item_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

------ITEM
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod,usr_elm,fyh_elm)
ON item
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON item
FROM anon, authenticated;

CREATE TRIGGER trg_bi_item_audit
BEFORE INSERT ON item
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_audit
BEFORE UPDATE ON item
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_item_audit
BEFORE UPDATE ON item
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_elm_fields();

----ITEM MOVIEMIENTO TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod,usr_elm,fyh_elm)
ON inventario.item_movimiento_tipo
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON inventario.item_movimiento_tipo
FROM anon, authenticated;

CREATE TRIGGER trg_bi_item_movimiento_tipo
BEFORE INSERT ON inventario.item_movimiento_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_movimiento_tipo
BEFORE UPDATE ON inventario.item_movimiento_tipo    
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_item_movimiento_tipo_elm
BEFORE UPDATE ON inventario.item_movimiento_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_elm_fields();

REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON insumo_tipo
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON insumo_tipo
FROM anon, authenticated;

----Insumo TIPO
CREATE TRIGGER trg_bi_insumo_tipo_audit
BEFORE INSERT ON insumo_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_insumo_tipo_audit
BEFORE UPDATE ON insumo_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

--COLORANTE TIPO

REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON colorante_tipo
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON colorante_tipo
FROM anon, authenticated;

CREATE TRIGGER trg_bi_colorante_tipo_audit
BEFORE INSERT ON colorante_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_colorante_tipo_audit
BEFORE UPDATE ON colorante_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();


---ITEM INSUMO DETALLE
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON insumo_detalle
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON insumo_detalle
FROM anon, authenticated;

CREATE TRIGGER trg_bi_insumo_detalle_audit
BEFORE INSERT ON insumo_detalle
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_insumo_detalle_audit
BEFORE UPDATE ON insumo_detalle
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---ITEM ROLLO DETALLE

REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON item_rollo_detalle
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON item_rollo_detalle
FROM anon, authenticated;

CREATE TRIGGER trg_bi_item_rollo_detalle_audit
BEFORE INSERT ON item_rollo_detalle
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_rollo_detalle_audit
BEFORE UPDATE ON item_rollo_detalle
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----ALMACEN
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON inventario.almacen
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON inventario.almacen
FROM anon, authenticated;

CREATE TRIGGER trg_bi_almacen_audit
BEFORE INSERT ON inventario.almacen
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_almacen_audit
BEFORE UPDATE ON inventario.almacen
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----UBICACION
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON inventario.ubicacion
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON inventario.ubicacion
FROM anon, authenticated;

CREATE TRIGGER trg_bi_ubicacion_audit
BEFORE INSERT ON inventario.ubicacion
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_ubicacion_audit
BEFORE UPDATE ON inventario.ubicacion
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----PARTIDA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON doc.partida
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON doc.partida
FROM anon, authenticated;

CREATE TRIGGER trg_biud_partida_audit
BEFORE INSERT OR UPDATE OR DELETE ON doc.partida
FOR EACH ROW
EXECUTE FUNCTION audit.fn_audit_row();

CREATE TRIGGER trg_bi_partida_audit
BEFORE INSERT ON doc.partida
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_audit
BEFORE UPDATE ON doc.partida
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----PARTIDA DETALLE

REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
ON doc.partida_detalle
FROM anon, authenticated;

REVOKE UPDATE (usr_cre, fyh_cre)
ON doc.partida_detalle
FROM anon, authenticated;

CREATE TRIGGER trg_biud_partida_detalle_audit
BEFORE INSERT OR UPDATE OR DELETE ON doc.partida_detalle
FOR EACH ROW
EXECUTE FUNCTION audit.fn_audit_row();

CREATE TRIGGER trg_bi_partida_detalle_audit
BEFORE INSERT ON doc.partida_detalle
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_detalle_audit
BEFORE UPDATE ON doc.partida_detalle
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_mod_fields();



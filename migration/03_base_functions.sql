-- ═══════════════════════════════════════════════════════════════
-- Step 3: Base trigger functions
-- Must come before any table that uses these as triggers.
-- ═══════════════════════════════════════════════════════════════

-- Canonical code: lowercased, unaccented version of codigo
-- Used by: item, unidad, item_tipo, insumo_tipo, colorante_tipo,
--          inventario.almacen/ubicacion, mes.operacion/maquina/etc.
-- NOTE: only attach to tables that have BOTH 'codigo' AND 'codigo_canon' columns.
CREATE OR REPLACE FUNCTION public.fn_trg_set_codigo_canon()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.codigo IS NOT NULL THEN
        NEW.codigo_canon := lower(unaccent(NEW.codigo));
    END IF;
    RETURN NEW;
END;
$$;

-- Audit helpers (from constraints.sql — needed before constraint file)
CREATE OR REPLACE FUNCTION public.fn_trg_set_cre_fields()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.usr_cre := COALESCE(NEW.usr_cre, get_user_id());
    NEW.fyh_cre := COALESCE(NEW.fyh_cre, now());
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_trg_set_mod_fields()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.usr_cre := OLD.usr_cre;
    NEW.fyh_cre := OLD.fyh_cre;
    NEW.usr_mod := get_user_id();
    NEW.fyh_mod := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_trg_set_elm_fields()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
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

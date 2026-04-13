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

-- ── User identity helper ──────────────────────────────────────────────────────
-- Reads id_usuario from the JWT (injected at login by custom_access_token_hook).
-- Zero DB cost. Requires hook registered: Supabase Dashboard →
--   Authentication → Hooks → Custom Access Token → public.custom_access_token_hook
CREATE OR REPLACE FUNCTION public.get_user_id()
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt()->>'id_usuario')::int;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_id TO authenticated, anon;

-- Audit helpers
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

-- ── Code immutability ─────────────────────────────────────────────────────────
-- Applied to every table with a codigo column. Codes are write-once: once set,
-- they can never change. Rename = soft-delete old + create new.
CREATE OR REPLACE FUNCTION public.fn_trg_immutable_codigo()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.codigo IS NOT NULL AND OLD.codigo IS DISTINCT FROM NEW.codigo THEN
        RAISE EXCEPTION 'el codigo es inmutable en %. Desactive y cree un nuevo registro en su lugar.', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$;

-- ── Hard-delete prevention ────────────────────────────────────────────────────
-- Core business documents must never be hard-deleted — use flg_elm = true instead.
CREATE OR REPLACE FUNCTION public.fn_trg_prevent_hard_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'el borrado no está permitido en %. Establezca flg_elm = true para borrar.', TG_TABLE_NAME;
END;
$$;

-- ── Auto-gen: mes.maquina ─────────────────────────────────────────────────────
-- Generates codigo = {maquina_tipo.codigo}-{NNN} scoped per tipo, if not provided.
CREATE OR REPLACE FUNCTION mes.fn_trg_gen_codigo_maquina()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_tipo_codigo TEXT;
    v_seq         INT;
BEGIN
    IF NEW.codigo IS NULL THEN
        SELECT codigo INTO v_tipo_codigo FROM mes.maquina_tipo WHERE id = NEW.maquina_tipo_id;
        SELECT COALESCE(MAX(
            CASE WHEN codigo ~ ('^' || v_tipo_codigo || '-[0-9]+$')
                 THEN (regexp_match(codigo, '[0-9]+$'))[1]::int
                 ELSE 0 END
        ), 0) + 1
        INTO v_seq
        FROM mes.maquina WHERE maquina_tipo_id = NEW.maquina_tipo_id;
        NEW.codigo := v_tipo_codigo || '-' || LPAD(v_seq::text, 3, '0');
    END IF;
    RETURN NEW;
END;
$$;

-- ── Auto-gen: inventario.ubicacion ───────────────────────────────────────────
-- Generates codigo = {almacen_abbrev}-{NN} scoped per almacen, if not provided.
-- Strips the 'ALM_' prefix from almacen.codigo to get the abbreviation.
-- Convention: almacen codes are user-set with ALM_ prefix (e.g. ALM_INS, ALM_CRU).
CREATE OR REPLACE FUNCTION inventario.fn_trg_gen_codigo_ubicacion()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_abbrev TEXT;
    v_seq    INT;
BEGIN
    IF NEW.codigo IS NULL THEN
        SELECT regexp_replace(codigo, '^ALM_', '') INTO v_abbrev
        FROM inventario.almacen WHERE id = NEW.almacen_id;
        SELECT COUNT(*) + 1 INTO v_seq
        FROM inventario.ubicacion WHERE almacen_id = NEW.almacen_id;
        NEW.codigo := v_abbrev || '-' || LPAD(v_seq::text, 2, '0');
    END IF;
    RETURN NEW;
END;
$$;

-- ── Auto-gen: color ───────────────────────────────────────────────────────────
-- Derives codigo by stripping non-alphanumeric from color name, uppercased.
CREATE OR REPLACE FUNCTION public.fn_trg_gen_codigo_color()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.codigo IS NULL THEN
        NEW.codigo := UPPER(regexp_replace(NEW.color, '[^a-zA-Z0-9]', '', 'g'));
    END IF;
    RETURN NEW;
END;
$$;

-- ── Auto-gen: item (rollo) ────────────────────────────────────────────────────
-- Fires AFTER INSERT on item_rollo_detalle, updates item.codigo when not yet set.
-- Format: R-{articulo.codigo}-{fibra}  (R-RB-... for rib variants)
-- One item per (articulo, fibra, rib) — no C/T suffix. Processing state (tenido/crudo)
-- lives on lote_rollo_detalle, not the item catalog.
CREATE OR REPLACE FUNCTION public.fn_trg_gen_codigo_item_rollo()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_articulo_codigo TEXT;
    v_fibra           TEXT;
    v_rib             TEXT;
BEGIN
    SELECT codigo INTO v_articulo_codigo FROM articulo WHERE id = NEW.articulo_id;
    SELECT COALESCE(fibra::text, '1') INTO v_fibra FROM articulo WHERE id = NEW.articulo_id;
    v_rib    := CASE WHEN COALESCE(NEW.flg_rib, false) THEN 'RB-' ELSE '' END;
    UPDATE item
       SET codigo = UPPER('R-' || v_rib || v_articulo_codigo || '-' || v_fibra)
     WHERE id = NEW.item_id AND codigo IS NULL;
    RETURN NEW;
END;
$$;

-- ── Auto-gen: item (insumo) ───────────────────────────────────────────────────
-- Fires AFTER INSERT on item_insumo_detalle, updates item.codigo when not yet set.
-- Format: I-{QUIM|COL|AUX}-{DIR|DISP|RX?}-{NORMALIZED_NAME}
CREATE OR REPLACE FUNCTION public.fn_trg_gen_codigo_item_insumo()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_it_codigo TEXT;
    v_ct_codigo TEXT;
    v_nombre    TEXT;
    v_codigo    TEXT;
BEGIN
    SELECT it.codigo, ct.codigo, i.nombre
      INTO v_it_codigo, v_ct_codigo, v_nombre
      FROM item i
      JOIN insumo_tipo it ON it.id = NEW.insumo_tipo_id
      LEFT JOIN colorante_tipo ct ON ct.id = NEW.colorante_tipo_id
     WHERE i.id = NEW.item_id;

    v_codigo := 'I-' || v_it_codigo;
    IF v_ct_codigo IS NOT NULL THEN
        v_codigo := v_codigo || '-' || v_ct_codigo;
    END IF;
    v_codigo := v_codigo || '-' ||
        trim(both '-' from
            regexp_replace(
                regexp_replace(UPPER(v_nombre) COLLATE "C", '\s+', ' ', 'g'),
                '[^A-Z0-9]+', '-', 'g'));

    UPDATE item SET codigo = v_codigo WHERE id = NEW.item_id AND codigo IS NULL;
    RETURN NEW;
END;
$$;

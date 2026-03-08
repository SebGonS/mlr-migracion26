-- ═══════════════════════════════════════════════════════════════
-- Step 9: Code immutability, audit schema, triggers, REVOKEs
-- Run AFTER all tables exist (steps 1–8).
-- Depends on: get_user_id(), fn_trg_set_*_fields (step 3).
-- ═══════════════════════════════════════════════════════════════

-- ── Code immutability triggers (apply after all tables exist) ─────────────────
-- Functions defined in step 3. Applied here after all tables are created.
DO $$ DECLARE t TEXT; BEGIN
    FOREACH t IN ARRAY ARRAY[
        'public.unidad',
        'public.item_tipo',
        'public.item',
        'public.insumo_tipo',
        'public.colorante_tipo',
        'public.articulo_tipo',
        'public.articulo',
        'public.color',
        'inventario.item_movimiento_tipo',
        'inventario.almacen',
        'inventario.ubicacion',
        'doc.guia_remision_tipo',
        'mes.operacion',
        'mes.maquina_tipo',
        'mes.maquina',
        'mes.empleado_rol',
        'calidad.tipo_defecto'
    ] LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_bu_immutable_codigo ON %s;
             CREATE TRIGGER trg_bu_immutable_codigo
             BEFORE UPDATE ON %s
             FOR EACH ROW EXECUTE FUNCTION public.fn_trg_immutable_codigo();',
            t, t
        );
    END LOOP;
END $$;

-- ── Hard-delete prevention triggers (apply after all tables exist) ────────────
-- Core business documents must never be hard-deleted — use flg_elm = true instead.
DO $$ DECLARE t TEXT; BEGIN
    FOREACH t IN ARRAY ARRAY[
        'doc.partida',
        'doc.guia_remision',
        'inventario.lote',
        'mes.orden_produccion'
    ] LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_bd_prevent_hard_delete ON %s;
             CREATE TRIGGER trg_bd_prevent_hard_delete
             BEFORE DELETE ON %s
             FOR EACH ROW EXECUTE FUNCTION public.fn_trg_prevent_hard_delete();',
            t, t
        );
    END LOOP;
END $$;

-- ── Audit schema ──────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS audit;
CREATE TABLE IF NOT EXISTS audit.data_audit (
    audit_id      bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    schema_name   TEXT NOT NULL,
    table_name    TEXT NOT NULL,
    row_id        bigint NOT NULL,
    operacion     TEXT NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    old_data      JSONB,
    new_data      JSONB,
    usr_id        int,
    fyh_evento    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Audit row function ────────────────────────────────────────────────────────
-- fn_trg_set_cre/mod/elm_fields are defined in step 3 (not repeated here).
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
    v_id := COALESCE(NEW.id, OLD.id);
    INSERT INTO audit.data_audit (
        schema_name, table_name, row_id, operacion, old_data, new_data, usr_id
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

-- ── Lote sequence trigger ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.trfn_generar_secuencia_lote()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_ano INT;
BEGIN
    v_ano := date_part('year', COALESCE(NEW.fyh_cre, NOW()));
    INSERT INTO inventario.lote_secuencia_anual (ano, ultimo_valor)
    VALUES (v_ano, 1)
    ON CONFLICT (ano)
    DO UPDATE SET ultimo_valor = inventario.lote_secuencia_anual.ultimo_valor + 1
    RETURNING ultimo_valor INTO NEW.secuencia;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bi_lote_secuencia
BEFORE INSERT ON inventario.lote
FOR EACH ROW
WHEN (NEW.secuencia IS NULL)
EXECUTE FUNCTION inventario.trfn_generar_secuencia_lote();

-- ── Per-table REVOKEs (audit/cre/mod/elm triggers are in step 12, after data migration) ───

-----UNIDAD
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON unidad FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON unidad FROM anon, authenticated;

---PESAJE
REVOKE INSERT (usr_cre, fyh_cre) ON inventario.pesaje FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre) ON inventario.pesaje FROM anon, authenticated;

----ITEM TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON item_tipo FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON item_tipo FROM anon, authenticated;

------ITEM
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON item FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON item FROM anon, authenticated;

----ITEM MOVIMIENTO TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON inventario.item_movimiento_tipo FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON inventario.item_movimiento_tipo FROM anon, authenticated;

----INSUMO TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON insumo_tipo FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON insumo_tipo FROM anon, authenticated;

--COLORANTE TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON colorante_tipo FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON colorante_tipo FROM anon, authenticated;

---ITEM INSUMO DETALLE
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON item_insumo_detalle FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON item_insumo_detalle FROM anon, authenticated;

---ITEM ROLLO DETALLE
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON item_rollo_detalle FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON item_rollo_detalle FROM anon, authenticated;

----ALMACEN
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON inventario.almacen FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON inventario.almacen FROM anon, authenticated;

----UBICACION
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON inventario.ubicacion FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON inventario.ubicacion FROM anon, authenticated;

----PARTIDA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.partida FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.partida FROM anon, authenticated;

-----PARTIDA DETALLE
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.partida_detalle FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.partida_detalle FROM anon, authenticated;

-----GUIA REMISION TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.guia_remision_tipo FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.guia_remision_tipo FROM anon, authenticated;

-----GUIA REMISION
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.guia_remision FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.guia_remision FROM anon, authenticated;

---LOTE
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON inventario.lote FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON inventario.lote FROM anon, authenticated;

----ITEM MOVIMIENTOS
REVOKE INSERT (usr_cre, fyh_cre) ON inventario.item_movimientos FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre) ON inventario.item_movimientos FROM anon, authenticated;

-----OPERACION
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.operacion FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.operacion FROM anon, authenticated;

-----ORDEN PRODUCCION ITEM
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.orden_produccion_item FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.orden_produccion_item FROM anon, authenticated;

-----MAQUINA TIPO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.maquina_tipo FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.maquina_tipo FROM anon, authenticated;

---MAQUINA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON mes.maquina FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON mes.maquina FROM anon, authenticated;

----EMPLEADO ROL
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.empleado_rol FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.empleado_rol FROM anon, authenticated;

---EMPLEADO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.empleado FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.empleado FROM anon, authenticated;

---RUTA PLANTILLA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON mes.ruta_plantilla FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON mes.ruta_plantilla FROM anon, authenticated;

-----ORDEN DE PRODUCCION
REVOKE INSERT (usr_cre, fyh_cre) ON mes.orden_produccion FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre) ON mes.orden_produccion FROM anon, authenticated;

-----ORDEN PRODUCCION PASO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.orden_produccion_paso FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.orden_produccion_paso FROM anon, authenticated;

-----ORDEN PRODUCCION PASO ITEM
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.orden_produccion_paso_item FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.orden_produccion_paso_item FROM anon, authenticated;

---PROGRAMACION
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON mes.programacion FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON mes.programacion FROM anon, authenticated;

---INSPECCION
REVOKE INSERT (usr_cre, fyh_cre) ON calidad.inspeccion FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre) ON calidad.inspeccion FROM anon, authenticated;

---INSPECCION FOTO
REVOKE INSERT (usr_cre, fyh_cre) ON calidad.inspeccion_foto FROM anon, authenticated;

-- ── Compras ───────────────────────────────────────────────────────────────────

-----FACTURA PROVEEDOR
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.factura_proveedor FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.factura_proveedor FROM anon, authenticated;

-----COMPRA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON doc.compra FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON doc.compra FROM anon, authenticated;

-----COMPRA DETALLE
REVOKE INSERT (usr_cre, fyh_cre) ON doc.compra_detalle FROM anon, authenticated;

-----LETRA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.letra FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.letra FROM anon, authenticated;

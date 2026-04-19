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
        'calidad.tipo_defecto',
        'public.tercero'
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

-- doc.factura: only block hard-delete once emitted or annulled.
-- Borradores (drafts) may be hard-deleted freely.
CREATE OR REPLACE FUNCTION doc.fn_trg_factura_prevent_hard_delete()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.estado IN ('emitida', 'anulada') THEN
        RAISE EXCEPTION
            'Factura id=% (%) no puede eliminarse: es un documento tributario emitido. Use una Nota de Crédito para anularla.',
            OLD.id, OLD.estado
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_bd_factura_prevent_hard_delete ON doc.factura;
CREATE TRIGGER trg_bd_factura_prevent_hard_delete
BEFORE DELETE ON doc.factura
FOR EACH ROW EXECUTE FUNCTION doc.fn_trg_factura_prevent_hard_delete();

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

-- ── Per-table REVOKEs (audit/cre/mod/elm triggers are in step 12, after data migration) ───

-----TERCERO
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON tercero FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON tercero FROM anon, authenticated;

-----UNIDAD
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON unidad FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON unidad FROM anon, authenticated;

---PESAJE
REVOKE INSERT (usr_cre, fyh_cre) ON inventario.pesaje FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre) ON inventario.pesaje FROM anon, authenticated;

---LOTE ROLLO DETALLE
REVOKE INSERT (usr_cre, fyh_cre, usr_mod, fyh_mod) ON inventario.lote_rollo_detalle FROM anon, authenticated;
-- Identity fields locked after insert: billing anchor and dyeing state
REVOKE UPDATE (guia_remision_id, color_x_cliente_id, tenido_id, flg_tenido) ON inventario.lote_rollo_detalle FROM anon, authenticated;

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
-- Identity fields are CREADA-only via actualizar_partida; block direct UPDATE to enforce the state gate
REVOKE UPDATE (tercero_id, color_x_cliente_id, tenido_id, articulo_tipo_id, flg_antipilling)
    ON doc.partida FROM anon, authenticated;

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

-----CATALOGO PRECIOS
REVOKE INSERT (usr_cre, fyh_cre, usr_elm, fyh_elm) ON doc.catalogo_precios FROM anon, authenticated;

-- One active row per key combination at any time.
-- COALESCE(-1): NULL dimensions participate correctly in the unique index.
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalogo_precios_activo
    ON doc.catalogo_precios (
        operacion_id,
        COALESCE(color_x_cliente_id,    -1),
        COALESCE(tercero_id,            -1),
        COALESCE(articulo_tipo_id::int, -1),
        COALESCE(tenido_id,             -1),
        COALESCE(fibra::int,            -1)
    )
    WHERE fyh_elm IS NULL;

-----FACTURA PROVEEDOR
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.factura_proveedor FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.factura_proveedor FROM anon, authenticated;

-----FACTURA PROVEEDOR DETALLE
REVOKE INSERT (usr_cre, fyh_cre) ON doc.factura_proveedor_detalle FROM anon, authenticated;

-----PARTIDA GUIA REMISION
REVOKE INSERT (usr_cre, fyh_cre) ON doc.partida_guia_remision FROM anon, authenticated;

-----COMPRA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON doc.compra FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON doc.compra FROM anon, authenticated;

-----COMPRA FACTURA PROVEEDOR
REVOKE INSERT (usr_cre, fyh_cre) ON doc.compra_factura_proveedor FROM anon, authenticated;

-----COMPRA DETALLE
REVOKE INSERT (usr_cre, fyh_cre) ON doc.compra_detalle FROM anon, authenticated;

-----LETRA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod) ON doc.letra FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                   ON doc.letra FROM anon, authenticated;

-----LETRA FACTURA
REVOKE INSERT (usr_cre, fyh_cre) ON doc.letra_factura FROM anon, authenticated;

-----FACTURA
REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod, usr_elm, fyh_elm) ON doc.factura FROM anon, authenticated;
REVOKE UPDATE (usr_cre, fyh_cre)                                      ON doc.factura FROM anon, authenticated;

-----FACTURA DETALLE
REVOKE INSERT (usr_cre, fyh_cre) ON doc.factura_detalle FROM anon, authenticated;

-- ── Performance indexes ───────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_opp_orden_id ON mes.orden_produccion_paso(orden_produccion_id);
CREATE INDEX IF NOT EXISTS idx_opi_orden_id ON mes.orden_produccion_item(orden_produccion_id);
CREATE INDEX IF NOT EXISTS idx_lote_doc             ON inventario.lote(documento_tipo, documento_id);
CREATE INDEX IF NOT EXISTS idx_im_lote_id           ON inventario.item_movimientos(lote_id);
CREATE INDEX IF NOT EXISTS idx_letra_factura_factura     ON doc.letra_factura(factura_proveedor_id);
CREATE INDEX IF NOT EXISTS idx_compra_factura_factura_id ON doc.compra_factura_proveedor(factura_proveedor_id);

-- lote_rollo_detalle lookup indexes
CREATE INDEX IF NOT EXISTS idx_lrd_guia
    ON inventario.lote_rollo_detalle (guia_remision_id)
    WHERE guia_remision_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_lrd_undyed
    ON inventario.lote_rollo_detalle (flg_tenido)
    WHERE flg_tenido = false;

CREATE INDEX IF NOT EXISTS idx_lrd_color
    ON inventario.lote_rollo_detalle (color_x_cliente_id)
    WHERE color_x_cliente_id IS NOT NULL;

-- Coverage check index: powers the unbilled dispatch guias query.
CREATE INDEX IF NOT EXISTS idx_factura_detalle_guia
    ON doc.factura_detalle (guia_remision_id)
    WHERE guia_remision_id IS NOT NULL;

-- Grouping/display index: invoice review screen grouped by dimensions.
CREATE INDEX IF NOT EXISTS idx_factura_detalle_dims
    ON doc.factura_detalle (operacion_id, articulo_tipo_id, color_x_cliente_id)
    WHERE operacion_id IS NOT NULL;

-- ── inventario.pesaje integrity ───────────────────────────────────────────────
-- One authoritative weight record per roll — regardless of when or why it was weighed.
-- Both ingress (partida) and post-assignment (orden) weighing upsert on this key.
CREATE UNIQUE INDEX IF NOT EXISTS uq_pesaje_lote
    ON inventario.pesaje(lote_id);

-- ═══════════════════════════════════════════════════════════════
-- Step 12: Audit cre/mod/elm triggers — run AFTER data migration (step 11).
--
-- These BEFORE INSERT triggers call fn_trg_set_cre_fields() which overwrites
-- usr_cre/fyh_cre with the current session user. Running them before data
-- migration would corrupt all migrated audit timestamps.
--
-- Depends on: fn_trg_set_cre/mod/elm_fields (step 3), audit.fn_audit_row (step 9).
-- ═══════════════════════════════════════════════════════════════

-----TERCERO
CREATE TRIGGER trg_biud_tercero_audit BEFORE INSERT OR UPDATE OR DELETE ON tercero
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_tercero_audit BEFORE INSERT ON tercero
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_tercero_audit BEFORE UPDATE ON tercero
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_tercero_elm   BEFORE UPDATE ON tercero
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

-----UNIDAD
CREATE TRIGGER trg_bi_unidad_audit BEFORE INSERT ON unidad
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_unidad_audit BEFORE UPDATE ON unidad
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---PESAJE
CREATE TRIGGER trg_bi_pesaje_audit BEFORE INSERT ON inventario.pesaje
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----LOTE ROLLO DETALLE
CREATE TRIGGER trg_bi_lote_rollo_detalle_audit
    BEFORE INSERT ON inventario.lote_rollo_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

CREATE TRIGGER trg_bu_lote_rollo_detalle_audit
    BEFORE UPDATE ON inventario.lote_rollo_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----ITEM TIPO
CREATE TRIGGER trg_bi_item_tipo_audit BEFORE INSERT ON item_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_tipo_audit BEFORE UPDATE ON item_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

------ITEM
CREATE TRIGGER trg_bi_item_audit BEFORE INSERT ON item
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_audit BEFORE UPDATE ON item
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_item_elm   BEFORE UPDATE ON item
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

----ITEM MOVIMIENTO TIPO
CREATE TRIGGER trg_bi_item_movimiento_tipo  BEFORE INSERT ON inventario.item_movimiento_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_movimiento_tipo  BEFORE UPDATE ON inventario.item_movimiento_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_item_movimiento_tipo_elm BEFORE UPDATE ON inventario.item_movimiento_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

----INSUMO TIPO
CREATE TRIGGER trg_bi_insumo_tipo_audit BEFORE INSERT ON insumo_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_insumo_tipo_audit BEFORE UPDATE ON insumo_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

--COLORANTE TIPO
CREATE TRIGGER trg_bi_colorante_tipo_audit BEFORE INSERT ON colorante_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_colorante_tipo_audit BEFORE UPDATE ON colorante_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---ITEM INSUMO DETALLE
CREATE TRIGGER trg_bi_item_insumo_detalle_audit BEFORE INSERT ON item_insumo_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_insumo_detalle_audit BEFORE UPDATE ON item_insumo_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---ITEM ROLLO DETALLE
CREATE TRIGGER trg_bi_item_rollo_detalle_audit BEFORE INSERT ON item_rollo_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_item_rollo_detalle_audit BEFORE UPDATE ON item_rollo_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----ALMACEN
CREATE TRIGGER trg_bi_almacen_audit BEFORE INSERT ON inventario.almacen
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_almacen_audit BEFORE UPDATE ON inventario.almacen
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----UBICACION
CREATE TRIGGER trg_bi_ubicacion_audit BEFORE INSERT ON inventario.ubicacion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_ubicacion_audit BEFORE UPDATE ON inventario.ubicacion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----PARTIDA
CREATE TRIGGER trg_biud_partida_audit BEFORE INSERT OR UPDATE OR DELETE ON mes.partida
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_partida_audit BEFORE INSERT ON mes.partida
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_audit BEFORE UPDATE ON mes.partida
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----PARTIDA DETALLE
CREATE TRIGGER trg_biud_partida_detalle_audit BEFORE INSERT OR UPDATE OR DELETE ON mes.partida_detalle
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_partida_detalle_audit BEFORE INSERT ON mes.partida_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_detalle_audit BEFORE UPDATE ON mes.partida_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----entrega REMISION TIPO
CREATE TRIGGER trg_bi_entrega_tipo_audit BEFORE INSERT ON doc.entrega_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_entrega_tipo_audit BEFORE UPDATE ON doc.entrega_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----entrega REMISION
CREATE TRIGGER trg_biud_entrega_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.entrega
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_entrega_audit BEFORE INSERT ON doc.entrega
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_entrega_audit BEFORE UPDATE ON doc.entrega
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---entrega REMISION DETALLE
CREATE TRIGGER trg_biud_entrega_detalle_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.entrega_detalle
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();

---LOTE
CREATE TRIGGER trg_bi_lote_audit BEFORE INSERT ON inventario.lote
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_lote_audit BEFORE UPDATE ON inventario.lote
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

----ITEM MOVIMIENTOS
CREATE TRIGGER trg_bi_item_movimientos_audit BEFORE INSERT ON inventario.item_movimientos
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----OPERACION
CREATE TRIGGER trg_bi_operacion_audit BEFORE INSERT ON mes.operacion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_operacion_audit BEFORE UPDATE ON mes.operacion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----ORDEN PRODUCCION ITEM
CREATE TRIGGER trg_bi_partida_componente_audit BEFORE INSERT ON mes.partida_componente
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_componente_audit BEFORE UPDATE ON mes.partida_componente
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----MAQUINA TIPO
CREATE TRIGGER trg_bi_maquina_tipo_audit BEFORE INSERT ON mes.maquina_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_maquina_tipo_audit BEFORE UPDATE ON mes.maquina_tipo
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---MAQUINA
CREATE TRIGGER trg_bi_maquina_audit BEFORE INSERT ON mes.maquina
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_maquina_audit BEFORE UPDATE ON mes.maquina
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_maquina_elm   BEFORE UPDATE ON mes.maquina
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

----EMPLEADO ROL
CREATE TRIGGER trg_bi_empleado_rol_audit BEFORE INSERT ON mes.empleado_rol
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_empleado_rol_audit BEFORE UPDATE ON mes.empleado_rol
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---EMPLEADO
CREATE TRIGGER trg_bi_empleado_audit BEFORE INSERT ON mes.empleado
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_empleado_audit BEFORE UPDATE ON mes.empleado
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---RUTA PLANTILLA
CREATE TRIGGER trg_biud_ruta_plantilla_audit BEFORE INSERT OR UPDATE OR DELETE ON mes.ruta_plantilla
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_ruta_plantilla_audit BEFORE INSERT ON mes.ruta_plantilla
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_ruta_plantilla_audit BEFORE UPDATE ON mes.ruta_plantilla
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_ruta_plantilla_elm   BEFORE UPDATE ON mes.ruta_plantilla
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

---RUTA PLANTILLA DETALLE
CREATE TRIGGER trg_biud_ruta_plantilla_detalle_audit BEFORE INSERT OR UPDATE OR DELETE ON mes.ruta_plantilla_detalle
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();

-----ORDEN PRODUCCION PASO
CREATE TRIGGER trg_biud_partida_paso_audit BEFORE INSERT OR UPDATE OR DELETE ON mes.partida_paso
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_partida_paso_audit BEFORE INSERT ON mes.partida_paso
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_paso_audit BEFORE UPDATE ON mes.partida_paso
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---PROGRAMACION
CREATE TRIGGER trg_bi_programacion_audit BEFORE INSERT ON mes.programacion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_programacion_audit BEFORE UPDATE ON mes.programacion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

---INSPECCION
CREATE TRIGGER trg_bi_inspeccion_audit BEFORE INSERT ON calidad.inspeccion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

---INSPECCION FOTO
CREATE TRIGGER trg_bi_inspeccion_foto_audit BEFORE INSERT ON calidad.inspeccion_foto
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----PARTIDA PASO EJECUCION
CREATE TRIGGER trg_bi_partida_paso_ejecucion_audit BEFORE INSERT ON mes.partida_paso_ejecucion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_partida_paso_ejecucion_audit BEFORE UPDATE ON mes.partida_paso_ejecucion
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-- ── Compras ───────────────────────────────────────────────────────────────────

-----CATALOGO PRECIOS
-- No mod trigger: rows are immutable. fyh_elm is set by upsert_catalogo_precio.
CREATE TRIGGER trg_bi_catalogo_precios_audit
    BEFORE INSERT ON doc.catalogo_precios
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----FACTURA PROVEEDOR
CREATE TRIGGER trg_biud_factura_proveedor_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.factura_proveedor
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_factura_proveedor_audit BEFORE INSERT ON doc.factura_proveedor
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_factura_proveedor_audit BEFORE UPDATE ON doc.factura_proveedor
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----FACTURA PROVEEDOR DETALLE
CREATE TRIGGER trg_bi_factura_proveedor_detalle_audit BEFORE INSERT ON doc.factura_proveedor_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----COMPRA FACTURA PROVEEDOR
CREATE TRIGGER trg_bi_compra_factura_proveedor_audit BEFORE INSERT ON doc.compra_factura_proveedor
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----COMPRA
CREATE TRIGGER trg_biud_compra_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.compra
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_compra_audit BEFORE INSERT ON doc.compra
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_compra_audit BEFORE UPDATE ON doc.compra
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
CREATE TRIGGER trg_bu_compra_elm   BEFORE UPDATE ON doc.compra
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_elm_fields();

-----COMPRA DETALLE
CREATE TRIGGER trg_bi_compra_detalle_audit BEFORE INSERT ON doc.compra_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-----LETRA
CREATE TRIGGER trg_biud_letra_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.letra
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_letra_audit BEFORE INSERT ON doc.letra
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_letra_audit BEFORE UPDATE ON doc.letra
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();

-----FACTURA
CREATE TRIGGER trg_biud_factura_audit BEFORE INSERT OR UPDATE OR DELETE ON doc.factura
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_row();
CREATE TRIGGER trg_bi_factura_audit BEFORE INSERT ON doc.factura
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();
CREATE TRIGGER trg_bu_factura_audit BEFORE UPDATE ON doc.factura
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_mod_fields();
-- trg_bu_factura_elm removed: doc.factura uses estado enum for cancellation, not fyh_elm

-----FACTURA DETALLE
CREATE TRIGGER trg_bi_factura_detalle_audit BEFORE INSERT ON doc.factura_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_set_cre_fields();

-- ── Stock balance maintenance ──────────────────────────────────────────────────
-- Maintains lote_saldo (MCHB) and item_saldo (MARD) on every posted movement.
-- Direction is derived from location field presence — no factor lookup needed.
-- destino IS NOT NULL → ingress (+cantidad at destino)
-- origen  IS NOT NULL → egress  (-cantidad at origen)
-- Both set            → transfer (both sides fire in one call — SAP 311 pattern)
CREATE OR REPLACE FUNCTION inventario.fn_trg_sync_cantidad_actual()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Ingress: credit destino
    IF NEW.destino_ubicacion_id IS NOT NULL THEN
        IF NEW.lote_id IS NOT NULL THEN
            INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
            VALUES (NEW.lote_id, NEW.destino_ubicacion_id, NEW.cantidad)
            ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
                SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
        END IF;
        INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
        VALUES (NEW.item_id, NEW.destino_ubicacion_id, NEW.cantidad)
        ON CONFLICT (item_id, ubicacion_id) DO UPDATE
            SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
    END IF;

    -- Egress: debit origen
    IF NEW.origen_ubicacion_id IS NOT NULL THEN
        IF NEW.lote_id IS NOT NULL THEN
            INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
            VALUES (NEW.lote_id, NEW.origen_ubicacion_id, -NEW.cantidad)
            ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
                SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
        END IF;
        INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
        VALUES (NEW.item_id, NEW.origen_ubicacion_id, -NEW.cantidad)
        ON CONFLICT (item_id, ubicacion_id) DO UPDATE
            SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ai_im_sync_cantidad_actual
    AFTER INSERT ON inventario.item_movimientos
    FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_sync_cantidad_actual();

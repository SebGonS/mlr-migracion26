-- ═══════════════════════════════════════════════════════════════
-- Step 14: Corte de inventario — bloqueo de movimientos retroactivos
-- Bloquea cualquier INSERT (o UPDATE de fecha_hora) en item_movimientos
-- cuya fecha_hora sea anterior a la fecha_cuadre de cualquier
-- cuadre no cancelado, evitando corromper una conciliación ya tomada.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION inventario.fn_trg_check_corte_cuadre()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'inventario', 'public'
AS $$
DECLARE
    v_almacen_ids INT[];
    v_corte       TIMESTAMPTZ;
BEGIN
    -- Resolve which almacenes this movement touches via its ubicaciones.
    SELECT array_agg(DISTINCT u.almacen_id)
    INTO v_almacen_ids
    FROM inventario.ubicacion u
    WHERE u.id IN (NEW.origen_ubicacion_id, NEW.destino_ubicacion_id);

    -- Global cuadres (almacen_id IS NULL) apply to all movements.
    -- Warehouse-scoped cuadres apply only when the movement touches that almacen.
    SELECT MAX(fecha_cuadre)
    INTO v_corte
    FROM inventario.cuadre
    WHERE estado <> 'cancelado'
      AND (
          almacen_id IS NULL
          OR (v_almacen_ids IS NOT NULL AND almacen_id = ANY(v_almacen_ids))
      );

    IF v_corte IS NOT NULL AND NEW.fecha_hora < v_corte THEN
        RAISE EXCEPTION
            'Movimiento rechazado: fecha_hora (%) es anterior al corte de inventario (%).',
            NEW.fecha_hora, v_corte;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bi_item_movimientos_corte_cuadre
BEFORE INSERT ON inventario.item_movimientos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_check_corte_cuadre();

CREATE TRIGGER trg_bu_item_movimientos_corte_cuadre
BEFORE UPDATE OF fecha_hora ON inventario.item_movimientos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_check_corte_cuadre();

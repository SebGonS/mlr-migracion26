-- ═══════════════════════════════════════════════════════════════
-- Step 14: Corte de inventario — bloqueo de movimientos retroactivos
-- Bloquea cualquier INSERT (o UPDATE de fecha_hora) en item_movimientos
-- cuya fecha_hora sea anterior a la fecha_cuadre de cualquier
-- cuadre no cancelado, evitando corromper una conciliación ya tomada.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION inventario.fn_trg_check_corte_cuadre()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_corte TIMESTAMPTZ;
BEGIN
    SELECT MAX(fecha_cuadre)
    INTO v_corte
    FROM inventario.cuadre
    WHERE estado <> 'cancelado';

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

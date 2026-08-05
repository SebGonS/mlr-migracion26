-- ═══════════════════════════════════════════════════════════════
-- Step 14: Corte de inventario — bloqueo de movimientos retroactivos
-- Bloquea cualquier INSERT (o UPDATE de fecha_hora) en item_movimientos
-- cuya fecha_hora sea anterior a la fecha_cuadre de un cuadre EJECUTADO
-- (finalizado), evitando corromper una conciliación ya cerrada.
--
-- Un cuadre en 'borrador'/'preparado' sigue en proceso de conteo: bloquear
-- retroactivos ahi impediria justamente registrar los movimientos que el
-- conteo esta destinado a descubrir. En su lugar, ver el trigger de resync
-- mas abajo: mantiene cantidad_sistema al dia mientras el cuadre sigue abierto.
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
    -- Only 'ejecutado' (finalized) cuadres lock the cutoff.
    SELECT MAX(fecha_cuadre)
    INTO v_corte
    FROM inventario.cuadre
    WHERE estado = 'ejecutado'
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

DROP TRIGGER IF EXISTS trg_bi_item_movimientos_corte_cuadre ON inventario.item_movimientos;
CREATE TRIGGER trg_bi_item_movimientos_corte_cuadre
BEFORE INSERT ON inventario.item_movimientos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_check_corte_cuadre();

DROP TRIGGER IF EXISTS trg_bu_item_movimientos_corte_cuadre ON inventario.item_movimientos;
CREATE TRIGGER trg_bu_item_movimientos_corte_cuadre
BEFORE UPDATE OF fecha_hora ON inventario.item_movimientos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_check_corte_cuadre();

-- ═══════════════════════════════════════════════════════════════
-- Resync cuadre_detalle while a cuadre is still open
-- Movements are never blocked by an open ('borrador'/'preparado') cuadre,
-- so cantidad_sistema (captured live from item_saldo at inicio_cuadre time)
-- can go stale the moment a late movement posts for an item already on the
-- count sheet. This keeps it current: same source (item_saldo +
-- item_valoracion) crear_cuadre() itself uses, just rescoped to one item.
-- No point-in-time ledger replay needed — cantidad_sistema was always a
-- "system stock right now" snapshot, never a historical-instant one.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION inventario.fn_trg_resync_cuadre_detalle()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'inventario', 'public'
AS $$
DECLARE
    v_almacen_ids INT[];
BEGIN
    SELECT array_agg(DISTINCT u.almacen_id)
    INTO v_almacen_ids
    FROM inventario.ubicacion u
    WHERE u.id IN (NEW.origen_ubicacion_id, NEW.destino_ubicacion_id);

    UPDATE inventario.cuadre_detalle cd
    SET cantidad_sistema        = COALESCE(sg.cantidad_total, 0),
        precio_promedio_sistema = COALESCE(iv.precio_promedio, 0),
        stock_valorado_sistema  = COALESCE(iv.stock_valorado, 0),
        fyh_mod                 = now()
    FROM inventario.cuadre c
    LEFT JOIN LATERAL (
        SELECT SUM(si.cantidad_actual) AS cantidad_total
        FROM inventario.item_saldo si
        LEFT JOIN inventario.ubicacion u ON u.id = si.ubicacion_id
        WHERE si.item_id = NEW.item_id
          AND (c.almacen_id IS NULL OR u.almacen_id = c.almacen_id)
    ) sg ON true
    LEFT JOIN inventario.item_valoracion iv ON iv.item_id = NEW.item_id
    WHERE cd.cuadre_id = c.id
      AND cd.item_id = NEW.item_id
      AND c.estado IN ('borrador', 'preparado')
      -- Never let a cuadre's own AJUSTE_* movements poison its own baseline
      -- (would overwrite cantidad_sistema to equal cantidad_contada mid-finalize,
      -- breaking execute→anular→re-execute). Scoped to the cuadre id, so a
      -- different cuadre's committed stock change still refreshes the baseline.
      -- See migration/patches/63_fix_resync_cuadre_self_poison.sql.
      AND NOT (NEW.documento_tipo = 'cuadre' AND NEW.documento_id = c.id)
      AND (
          c.almacen_id IS NULL
          OR (v_almacen_ids IS NOT NULL AND c.almacen_id = ANY(v_almacen_ids))
      );

    RETURN NEW;
END;
$$;

-- Runs after trg_ai_im_sync_cantidad_actual (migration 12) so item_saldo
-- already reflects this movement — alphabetical trigger order within the
-- same AFTER INSERT event guarantees "im_sync..." fires before "item_mov...".
DROP TRIGGER IF EXISTS trg_ai_item_movimientos_resync_cuadre ON inventario.item_movimientos;
CREATE TRIGGER trg_ai_item_movimientos_resync_cuadre
AFTER INSERT ON inventario.item_movimientos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_resync_cuadre_detalle();

-- ═══════════════════════════════════════════════════════════════
-- Patch 63: fix cuadre re-execution posting zero after anular
--
-- Bug
-- ───
-- inventario.fn_trg_resync_cuadre_detalle (AFTER INSERT on
-- item_movimientos) refreshes cuadre_detalle.cantidad_sistema from live
-- item_saldo for any OPEN (borrador/preparado) cuadre. During
-- finalizar_cuadre the cuadre is still 'borrador' when its own AJUSTE_*
-- movements are posted, and the saldo trigger (trg_ai_im_sync_cantidad_actual)
-- runs first, so by the time resync reads item_saldo it already includes
-- the cuadre's own adjustment. Result: cantidad_sistema is overwritten to
-- equal cantidad_contada.
--
-- After an anular (which restores stock but does NOT restore the snapshot,
-- since its reversals run while estado='ejecutado'), re-finalizing sees
-- cantidad_contada - cantidad_sistema = 0 and posts nothing. The count is
-- silently lost. Real incident: cuadre 35 (ALM_INS) — 94 of 200 lines left
-- at their pre-cuadre book values, ~20,475 kg of adjustments never applied.
--
-- Fix
-- ───
-- Guard the resync so a cuadre's OWN movements never refresh its OWN
-- baseline. Scoped to the specific cuadre id (NEW.documento_id = c.id),
-- NOT a blanket documento_tipo='cuadre' skip, so a DIFFERENT cuadre's
-- committed stock change (e.g. a global cuadre reacting to a per-almacen
-- cuadre's finalize) still refreshes the baseline correctly.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION inventario.fn_trg_resync_cuadre_detalle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'inventario','public'
AS $function$
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
      AND cd.item_id   = NEW.item_id
      AND c.estado IN ('borrador','preparado')
      -- Never let a cuadre's own AJUSTE_* movements poison its own baseline.
      AND NOT (NEW.documento_tipo = 'cuadre' AND NEW.documento_id = c.id)
      AND (
          c.almacen_id IS NULL
          OR (v_almacen_ids IS NOT NULL AND c.almacen_id = ANY(v_almacen_ids))
      );

    RETURN NEW;
END;
$function$;


-- ── Data recovery for cuadre 35 (ALM_INS) ─────────────────────────────
-- Run ONLY after the function above is deployed.
-- The already-poisoned cantidad_sistema rows won't self-heal (no external
-- movement fires the resync), so re-snapshot from true live stock once.
--
--   1) SELECT inventario.anular_cuadre_ejecutado(35, 'reset baseline');
--
--   2) UPDATE inventario.cuadre_detalle cd
--      SET cantidad_sistema = COALESCE((
--              SELECT SUM(si.cantidad_actual)
--              FROM inventario.item_saldo si
--              JOIN inventario.ubicacion u ON u.id = si.ubicacion_id
--              WHERE si.item_id = cd.item_id AND u.almacen_id = 7
--          ), 0)
--      WHERE cd.cuadre_id = 35;
--
--   3) SELECT inventario.finalizar_cuadre(35);

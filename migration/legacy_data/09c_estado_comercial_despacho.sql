-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX: set estado_comercial for legacy-dispatched partidas
--
-- 09_despacho_egreso_legacy.sql egressed the rolls + created entregas but did NOT
-- touch partida estado. The normal crear_entrega flow doesn't set it either — the
-- commercial axis was only ever seeded by 11_data_migration's legacy-estado map
-- ('Despachado' → ENTREGADA). So a partida that has a legacy despacho row but a
-- different legacy estado (e.g. 'Para Despachar', or a rework whose family shipped)
-- is stuck at estado_comercial = 'PENDIENTE' despite being delivered.
--
-- This sets the COMMERCIAL axis to match reality:
--   ENTREGADA       — no dyed output of the family remains in stock (fully out)
--   ENTREGA_PARCIAL — some dyed output of the family is still in stock
--
-- SCOPE / GUARDS
--   • ORIGINALS only (partida_origen_id IS NULL). Rework children must stay
--     PENDIENTE — migration 07 CHECK enforces it and settlement runs on the parent.
--   • Only upgrades from PENDIENTE. Never downgrades ENTREGADA / DEVUELTA_* states
--     that 11_data_migration already set.
--   • "Family" stock = the original partida + all its rework children.
--
-- NOT TOUCHED
--   • estado_produccion — CERRADA needs the billing axis (estado_facturacion =
--     'facturado'), which isn't migrated. Left as 11_data_migration set it.
--   • estado_facturacion — out of scope (billing migration).
--
-- PRIVILEGE: estado_comercial UPDATE is revoked from anon/authenticated — run as
--   postgres / table owner (as with the other legacy_data scripts). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PREVIEW  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- remaining dyed output in stock, per legacy family (original + reworks)
WITH family_stock AS (
    SELECT COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
           COUNT(DISTINCT l.id) AS rolls_en_stock
    FROM mes.partida mp
    JOIN mes.partida_paso pp            ON pp.partida_id = mp.id
    JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    JOIN inventario.lote l              ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE mp.estado_produccion != 'CANCELADA'
    GROUP BY 1
)
SELECT
    p.id                                        AS partida_id,
    p.estado_comercial                          AS estado_actual,
    COALESCE(fs.rolls_en_stock, 0)              AS rolls_en_stock,
    CASE WHEN COALESCE(fs.rolls_en_stock, 0) = 0
         THEN 'ENTREGADA' ELSE 'ENTREGA_PARCIAL' END AS estado_propuesto,
    CASE
        WHEN p.estado_comercial = 'PENDIENTE'   THEN 'se actualizará'
        WHEN p.estado_comercial = 'ENTREGADA' AND COALESCE(fs.rolls_en_stock,0) > 0
                                                THEN 'revisar: ENTREGADA pero queda stock'
        ELSE 'sin cambio'
    END                                         AS accion
FROM mes.partida p
LEFT JOIN family_stock fs ON fs.legacy_partida_id = p.id
WHERE p.partida_origen_id IS NULL
  AND EXISTS (
      SELECT 1 FROM public.despacho d
      WHERE d.flg_elm = false AND d.rollos_total > 0 AND d.partida_id = p.id
  )
ORDER BY accion, p.id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — EXECUTE  (idempotent; originals, PENDIENTE → ENTREGADA/PARCIAL)
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_entregada  INT;
    v_parcial    INT;
BEGIN
    WITH family_stock AS (
        SELECT COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
               COUNT(DISTINCT l.id) AS rolls_en_stock
        FROM mes.partida mp
        JOIN mes.partida_paso pp            ON pp.partida_id = mp.id
        JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
        JOIN inventario.lote l              ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
        JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
        WHERE mp.estado_produccion != 'CANCELADA'
        GROUP BY 1
    ),
    target AS (
        SELECT p.id,
               CASE WHEN COALESCE(fs.rolls_en_stock, 0) = 0
                    THEN 'ENTREGADA'::partida_estado_comercial_enum
                    ELSE 'ENTREGA_PARCIAL'::partida_estado_comercial_enum END AS nuevo_estado
        FROM mes.partida p
        LEFT JOIN family_stock fs ON fs.legacy_partida_id = p.id
        WHERE p.partida_origen_id IS NULL
          AND p.estado_comercial = 'PENDIENTE'
          AND EXISTS (
              SELECT 1 FROM public.despacho d
              WHERE d.flg_elm = false AND d.rollos_total > 0 AND d.partida_id = p.id
          )
    ),
    upd AS (
        UPDATE mes.partida p
        SET estado_comercial = t.nuevo_estado, fyh_mod = NOW()
        FROM target t
        WHERE p.id = t.id
        RETURNING t.nuevo_estado
    )
    SELECT
        COUNT(*) FILTER (WHERE nuevo_estado = 'ENTREGADA'),
        COUNT(*) FILTER (WHERE nuevo_estado = 'ENTREGA_PARCIAL')
    INTO v_entregada, v_parcial
    FROM upd;

    RAISE NOTICE '═══════════ ESTADO COMERCIAL DESPACHO ═══════════';
    RAISE NOTICE '  → ENTREGADA        : %', v_entregada;
    RAISE NOTICE '  → ENTREGA_PARCIAL  : %', v_parcial;
    RAISE NOTICE '═════════════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. estado_comercial distribution for legacy-dispatched originals.
SELECT p.estado_comercial, COUNT(*) AS partidas
FROM mes.partida p
WHERE p.partida_origen_id IS NULL
  AND EXISTS (SELECT 1 FROM public.despacho d
              WHERE d.flg_elm = false AND d.rollos_total > 0 AND d.partida_id = p.id)
GROUP BY p.estado_comercial
ORDER BY p.estado_comercial;

-- 2b. Leftover: dispatched originals still PENDIENTE (should be 0).
SELECT COUNT(*) AS dispatched_aun_pendiente
FROM mes.partida p
WHERE p.partida_origen_id IS NULL
  AND p.estado_comercial = 'PENDIENTE'
  AND EXISTS (SELECT 1 FROM public.despacho d
              WHERE d.flg_elm = false AND d.rollos_total > 0 AND d.partida_id = p.id);

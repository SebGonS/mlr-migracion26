-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX: undo the cuadre-cutoff date bump on legacy despacho egress movements
--
-- 09_despacho_egreso_legacy.sql stamped every egress movement with
--   fecha_hora = GREATEST(despacho_ts, MAX(cuadre.fecha_cuadre) + 1 min)
-- using a CONSERVATIVE GLOBAL max cuadre. But the migration-14 trigger only blocks
-- a movement when a cuadre is GLOBAL (almacen_id IS NULL) or for the SAME almacen
-- the movement touches. The 2026-06-06 cuadre is for a different warehouse (not the
-- finished-rolls one), so it never actually applied to these egresses — the bump
-- was spurious.
--
-- This restores fecha_hora to the true historical despacho date, recovered from the
-- despacho id stamped in observacion ('MIG-DESP despacho=<id> partida=<legacy_id>').
--
-- OVERRIDE: the cuadre that caused the bump is for another warehouse, so it never
-- applied to these egresses. We surgically DISABLE trg_bu_item_movimientos_corte_cuadre
-- (the BEFORE UPDATE OF fecha_hora guard) for the duration of the fix and re-ENABLE
-- it after, then force fecha_hora back to the true legacy date. The disable is
-- transactional — any failure rolls it back automatically.
--
-- guia.fecha_emision already holds the true date and is left unchanged.
-- lote_saldo is unaffected (the saldo trigger is AFTER INSERT only, not UPDATE).
-- Idempotent: only moves rows whose fecha_hora still differs from the true date.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — VERIFY SCOPE  (read-only) — confirm the cuadre doesn't apply
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0a. Non-cancelled cuadres and their scope. A row with almacen IS NULL = GLOBAL
--     (would block everything). Otherwise it only blocks its own almacen.
SELECT c.id, c.almacen_id, a.codigo AS almacen, c.fecha_cuadre, c.estado
FROM inventario.cuadre c
LEFT JOIN inventario.almacen a ON a.id = c.almacen_id
WHERE c.estado <> 'cancelado'
ORDER BY c.fecha_cuadre DESC;

-- 0b. Which almacen(es) the migration egress movements actually touch.
--     If these codes do NOT appear in 0a (and 0a has no NULL/global row), the undo
--     will fully succeed.
SELECT a.codigo AS almacen, COUNT(*) AS movimientos
FROM inventario.item_movimientos im
JOIN inventario.ubicacion u ON u.id = im.origen_ubicacion_id
JOIN inventario.almacen a   ON a.id = u.almacen_id
WHERE im.documento_tipo = 'guia_remision'
  AND im.observacion LIKE 'MIG-DESP despacho=%'
GROUP BY a.codigo;

-- 0c. Preview: current (bumped) fecha_hora vs the true despacho date to restore.
SELECT
    im.fecha_hora                                   AS fecha_actual,
    ((d.fecha_despacho + '17:00'::time)::timestamp + INTERVAL '5 hours')::timestamptz AS fecha_real,
    COUNT(*)                                        AS movimientos
FROM inventario.item_movimientos im
JOIN public.despacho d
  ON d.id = (substring(im.observacion FROM 'despacho=([0-9]+)'))::int
WHERE im.documento_tipo = 'guia_remision'
  AND im.observacion LIKE 'MIG-DESP despacho=%'
GROUP BY 1, 2
ORDER BY 1;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — RESTORE TRUE DATES  (cutoff trigger overridden, idempotent)
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_moved  INT;
BEGIN
    -- Override the cutoff guard so the legacy date can be forced in.
    ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

    UPDATE inventario.item_movimientos im
    SET fecha_hora = tgt.fecha_real
    FROM (
        SELECT im2.id,
               ((d.fecha_despacho + '17:00'::time)::timestamp + INTERVAL '5 hours')::timestamptz AS fecha_real
        FROM inventario.item_movimientos im2
        JOIN public.despacho d
          ON d.id = (substring(im2.observacion FROM 'despacho=([0-9]+)'))::int
        WHERE im2.documento_tipo = 'guia_remision'
          AND im2.observacion LIKE 'MIG-DESP despacho=%'
    ) tgt
    WHERE im.id = tgt.id
      AND im.fecha_hora IS DISTINCT FROM tgt.fecha_real;
    GET DIAGNOSTICS v_moved = ROW_COUNT;

    -- restore the cutoff guard
    ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

    RAISE NOTICE '═══════════ CORRECCION FECHA EGRESO ═══════════';
    RAISE NOTICE '  movimientos re-fechados : %', v_moved;
    RAISE NOTICE '═══════════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Distinct fecha_hora now present on the migration egresses (should match the
-- true despacho dates, no longer clustered on the old corte+1min timestamp).
SELECT im.fecha_hora, COUNT(*) AS movimientos
FROM inventario.item_movimientos im
WHERE im.documento_tipo = 'guia_remision'
  AND im.observacion LIKE 'MIG-DESP despacho=%'
GROUP BY im.fecha_hora
ORDER BY im.fecha_hora;

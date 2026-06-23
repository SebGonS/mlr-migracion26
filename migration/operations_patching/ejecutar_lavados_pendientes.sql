-- ═══════════════════════════════════════════════════════════════════════════════
-- EXECUTE PENDING MACHINE WASHES (lavado_maquina never finalized)
--
-- 27 PENDIENTE + 2 EN_PROCESO washes were created/started in the live system but
-- never finalized, so their chemical consumption was never posted. This completes
-- them: posts the recipe consumption (kg, FIFO + fungible-lotless) BACKDATED to the
-- wash's own timestamp, and sets estado=COMPLETADO with fyh_inicio/fyh_fin.
--
-- Mirrors mes.finalizar_lavado_maquina but: (a) backdated, (b) no JWT/permission
-- dependency (run as admin), (c) does NOT raise on short stock — FIFO posts what it
-- can, fungibles go lotless (may push negative; that's the legacy-ingress gap).
-- Lavado quantities are fixed kg (no g/L scaling), so there is NO unit conversion here.
--
-- EVENT TIMESTAMP per wash = COALESCE(fyh_inicio, fyh_cre).
--   prog.fecha is NOT used: washes have multiple programacion rows (ambiguous) and
--   some none; fyh_cre is unambiguous and within ~1 day of the scheduled date.
--
-- IDEMPOTENT: skips washes that already have a lavado_maquina egress, and only
-- transitions washes that are PENDIENTE/EN_PROCESO. Stamp: 'BACKFILL_LAVADO_NO_EJECUTADO'.
-- Run AFTER patch 28. WORKFLOW: SECTION 0 → 1 → 2.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════
SELECT lm.estado,
       COUNT(DISTINCT lm.id)                       AS washes,
       COUNT(*)                                    AS lineas,
       ROUND(SUM(agg.cantidad), 4)                 AS kg_total
FROM mes.lavado_maquina lm
JOIN LATERAL (
    SELECT lmpi.item_id, SUM(lmpi.cantidad) AS cantidad
    FROM receta.lavado_maquina_paso lmp
    JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id = lmp.id
    WHERE lmp.receta_id = lm.receta_id
    GROUP BY lmpi.item_id
) agg ON TRUE
WHERE lm.estado IN ('PENDIENTE','EN_PROCESO')
  AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  WHERE im.documento_tipo='lavado_maquina' AND im.documento_id = lm.id)
GROUP BY lm.estado;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — EXECUTE  (one transaction)
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;

-- 1a. Materialize one egress line per (wash, insumo) in kg, backdated.
CREATE TEMP TABLE _lavado_backfill (
    lavado_id  BIGINT      NOT NULL,
    item_id    INT         NOT NULL,
    cantidad   NUMERIC(15,7),
    fyh_evento TIMESTAMPTZ NOT NULL
) ON COMMIT DROP;

INSERT INTO _lavado_backfill (lavado_id, item_id, cantidad, fyh_evento)
SELECT lm.id, lmpi.item_id, SUM(lmpi.cantidad),
       COALESCE(lm.fyh_inicio, lm.fyh_cre)
FROM mes.lavado_maquina lm
JOIN receta.lavado_maquina_paso        lmp  ON lmp.receta_id = lm.receta_id
JOIN receta.lavado_maquina_paso_insumo lmpi ON lmpi.paso_id  = lmp.id
WHERE lm.estado IN ('PENDIENTE','EN_PROCESO')
  AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  WHERE im.documento_tipo='lavado_maquina' AND im.documento_id = lm.id)
GROUP BY lm.id, lmpi.item_id, COALESCE(lm.fyh_inicio, lm.fyh_cre);

DELETE FROM _lavado_backfill WHERE cantidad IS NULL OR cantidad <= 0;

-- 1b. Lift the corte-de-cuadre guard for backdated posting (stock+MAP triggers stay ON).
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

-- 1c. Post movements per wash, chronologically (FIFO depletes in order).
DO $$
DECLARE
    r              RECORD;
    v_egr_tipo     SMALLINT;
    v_motivo       SMALLINT;
    v_doc          BIGINT;
    v_consumos_std JSONB;
    v_fifo         JSONB;
BEGIN
    SELECT id INTO v_egr_tipo FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO';
    SELECT id INTO v_motivo   FROM inventario.item_movimiento_motivo
    WHERE item_movimiento_tipo_id = v_egr_tipo AND codigo='LAVADO_MAQUINA';

    FOR r IN
        SELECT lavado_id, fyh_evento
        FROM _lavado_backfill
        GROUP BY lavado_id, fyh_evento
        ORDER BY fyh_evento, lavado_id
    LOOP
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc;

        -- Non-fungible → FIFO lot resolution against current stock
        SELECT jsonb_agg(jsonb_build_object('item_id', e.item_id, 'cantidad', e.cantidad))
        INTO v_consumos_std
        FROM _lavado_backfill e
        JOIN item it ON it.id = e.item_id
        WHERE e.lavado_id = r.lavado_id AND it.flg_fungible = false;

        IF v_consumos_std IS NOT NULL THEN
            v_fifo := mes.calcular_fifo(v_consumos_std);
            IF v_fifo IS NOT NULL THEN
                INSERT INTO inventario.item_movimientos(
                    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                    origen_ubicacion_id, cantidad, precio_unitario, fecha_hora,
                    documento_tipo, documento_id, motivo_id, observacion)
                SELECT v_doc, (c->>'item_id')::INT, (c->>'lote_id')::INT, v_egr_tipo,
                       (c->>'ubicacion_id')::INT, (c->>'cantidad')::NUMERIC,
                       (SELECT precio_promedio FROM inventario.item_valoracion WHERE item_id=(c->>'item_id')::INT),
                       r.fyh_evento, 'lavado_maquina', r.lavado_id, v_motivo,
                       'BACKFILL_LAVADO_NO_EJECUTADO'
                FROM jsonb_array_elements(v_fifo) c;
            END IF;
        END IF;

        -- Fungible → lotless egress, same ubicacion fallback as registrar_consumo_paso
        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, precio_unitario, fecha_hora,
            documento_tipo, documento_id, motivo_id, observacion)
        SELECT v_doc, e.item_id, NULL, v_egr_tipo,
               COALESCE(
                   (SELECT ubicacion_id FROM inventario.item_saldo
                     WHERE item_id=e.item_id ORDER BY cantidad_actual DESC LIMIT 1),
                   (SELECT im2.origen_ubicacion_id FROM inventario.item_movimientos im2
                     WHERE im2.item_id=e.item_id AND im2.origen_ubicacion_id IS NOT NULL
                     ORDER BY im2.id DESC LIMIT 1),
                   (SELECT ity.ubicacion_default_id FROM item it2
                     JOIN item_tipo ity ON ity.id=it2.item_tipo_id WHERE it2.id=e.item_id)),
               e.cantidad,
               (SELECT precio_promedio FROM inventario.item_valoracion WHERE item_id=e.item_id),
               r.fyh_evento, 'lavado_maquina', r.lavado_id, v_motivo,
               'BACKFILL_LAVADO_NO_EJECUTADO'
        FROM _lavado_backfill e
        JOIN item it ON it.id = e.item_id
        WHERE e.lavado_id = r.lavado_id AND it.flg_fungible = true;
    END LOOP;

    RAISE NOTICE 'Lavados ejecutados: % washes procesados.',
        (SELECT COUNT(DISTINCT lavado_id) FROM _lavado_backfill);
END $$;

-- 1d. Restore the corte-de-cuadre guard.
ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;
ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bu_item_movimientos_corte_cuadre;

-- 1e. Transition the executed washes to COMPLETADO with their proper timestamps.
UPDATE mes.lavado_maquina lm
SET estado     = 'COMPLETADO',
    fyh_inicio = COALESCE(lm.fyh_inicio, lm.fyh_cre),
    fyh_fin    = COALESCE(lm.fyh_fin, lm.fyh_inicio, lm.fyh_cre),
    usr_mod    = 1,
    fyh_mod    = now()
WHERE lm.estado IN ('PENDIENTE','EN_PROCESO')
  AND EXISTS (SELECT 1 FROM inventario.item_movimientos im
              WHERE im.documento_tipo='lavado_maquina' AND im.documento_id = lm.id);

COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VERIFY
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. Washes still not COMPLETADO (should be only no-insumo recipes, if any)
SELECT estado, COUNT(*) FROM mes.lavado_maquina
WHERE estado IN ('PENDIENTE','EN_PROCESO') GROUP BY estado;

-- 2b. What posted
SELECT COUNT(*) AS movimientos, COUNT(DISTINCT documento_id) AS washes,
       ROUND(SUM(cantidad),4) AS kg_total, ROUND(SUM(monto),2) AS valor_total
FROM inventario.item_movimientos
WHERE observacion = 'BACKFILL_LAVADO_NO_EJECUTADO';

-- 2c. Items driven negative by these washes (expected — legacy-ingress gap)
SELECT i.id, i.codigo, i.nombre, ROUND(SUM(si.cantidad_actual),4) AS stock
FROM inventario.item_saldo si JOIN item i ON i.id = si.item_id
WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
             WHERE im.item_id=i.id AND im.observacion='BACKFILL_LAVADO_NO_EJECUTADO')
GROUP BY i.id,i.codigo,i.nombre HAVING SUM(si.cantidad_actual) < 0
ORDER BY 4;

-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL: DELETE FROM inventario.item_movimientos WHERE observacion='BACKFILL_LAVADO_NO_EJECUTADO';
--   (stock+MAP triggers reverse balances on delete is NOT automatic — re-derive saldo
--    if needed) then reset those washes: UPDATE mes.lavado_maquina SET estado='PENDIENTE',
--    fyh_inicio=NULL, fyh_fin=NULL WHERE id IN (...).
-- ═══════════════════════════════════════════════════════════════════════════════

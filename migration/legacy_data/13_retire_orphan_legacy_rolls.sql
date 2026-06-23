-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY RECONCILE: retirar rollos legacy huérfanos con stock fantasma
--
-- PROBLEMA: el backfill de migración creó un lote por rollo físico histórico
-- (vía flujo PARTIDA, por eso entrega_id IS NULL) pero NO posteó su consumo/
-- despacho. Resultado: ~67k rollos con saldo > 0 que en realidad ya se
-- procesaron/despacharon en el sistema viejo. 1.46M kg de stock fantasma que
-- distorsiona vw_stock_lotes, valuación y el reporte doc.vw_pendientes_proceso.
--
-- DECISIÓN: retirarlos (están "idos"). Se postea un egreso de ajuste por cada
-- lote y se da de baja el lote.
--
-- POR QUÉ ES SEGURO PARA VALUACIÓN:
--   • AJUSTE_NEG es valorizable, PERO el trigger de MAP (fn_trg_actualizar_map)
--     corta si precio_unitario IS NULL. Posteamos SIN precio_unitario → el
--     egreso baja el stock físico (item_saldo / lote_saldo) sin tocar
--     item_valoracion. Correcto: estos rollos entraron por SERV_ING (NO
--     valorizable), nunca estuvieron en la valuación.
--   • fecha_hora = now() (NO backdated) → no dispara el guard de corte-de-cuadre
--     ni altera snapshots de cuadres cerrados.
--
-- SCOPE: solo rollos PRE go-live (fyh_cre <= cutoff). Los huérfanos recientes
-- (cargas patch de compactado/perchado) quedan FUERA — se resuelven en su patch.
--
-- IDEMPOTENTE: no re-postea si el lote ya tiene un movimiento RECONCILE_LEGACY_ORPHAN.
-- REVERSIBLE: ver bloque REVERSAL al final.
--
-- ⚠️ Si hay un cuadre ABIERTO (borrador/preparado) que cubra estos ítems/almacenes,
--    coordinar antes — su conteo físico debe contemplar que estos rollos ya no están.
--
-- WORKFLOW: correr SECTION 0 (read-only) y revisar números → luego SECTION 1.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PRE-FLIGHT (read-only). Revisar antes de SECTION 1.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0a. Alcance: cuántos lotes / kg se van a retirar
SELECT COUNT(DISTINCT l.id)                       AS lotes,
       ROUND(SUM(ls.cantidad_actual)::numeric, 2) AS kg,
       MIN(l.fyh_cre)::date                        AS desde,
       MAX(l.fyh_cre)::date                        AS hasta
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.lote_saldo ls          ON ls.lote_id = l.id AND ls.cantidad_actual > 0
WHERE l.fyh_elm IS NULL
  AND lrd.entrega_id IS NULL
  AND lrd.orden_servicio_id IS NULL
  AND l.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;

-- 0b. Por propietario (sanity: deberían ser material de cliente / servicio)
SELECT COALESCE(t.nombre, '— sin propietario —')  AS propietario,
       COUNT(DISTINCT l.id)                        AS lotes,
       ROUND(SUM(ls.cantidad_actual)::numeric, 2)  AS kg
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.lote_saldo ls          ON ls.lote_id = l.id AND ls.cantidad_actual > 0
LEFT JOIN tercero t                    ON t.id = l.propietario_id
WHERE l.fyh_elm IS NULL
  AND lrd.entrega_id IS NULL
  AND lrd.orden_servicio_id IS NULL
  AND l.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
GROUP BY 1 ORDER BY kg DESC;

-- 0c. Exposición de valuación: si esto da > 0, esos ítems SÍ tienen costo MAP y
--     conviene revisar antes (no debería: rollos de servicio = sin valuación).
SELECT ROUND(SUM(ls.cantidad_actual * COALESCE(iv.precio_promedio, 0))::numeric, 2)
           AS valuacion_expuesta
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd  ON lrd.lote_id = l.id
JOIN inventario.lote_saldo ls           ON ls.lote_id = l.id AND ls.cantidad_actual > 0
LEFT JOIN inventario.item_valoracion iv ON iv.item_id = l.item_id
WHERE l.fyh_elm IS NULL
  AND lrd.entrega_id IS NULL
  AND lrd.orden_servicio_id IS NULL
  AND l.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — RETIRAR (una transacción). Editar el cutoff si hace falta.
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;
DO $$
DECLARE
    v_cutoff timestamptz := '2026-05-25 15:27:52+00';
    v_tipo   smallint;
    v_motivo smallint;
    v_doc    bigint;
    v_movs   int;
    v_lotes  int;
BEGIN
    SELECT id INTO v_tipo   FROM inventario.item_movimiento_tipo
        WHERE codigo = 'AJUSTE_NEG';
    SELECT id INTO v_motivo FROM inventario.item_movimiento_motivo
        WHERE item_movimiento_tipo_id = v_tipo AND codigo = 'FALTANTE_FISICO';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc;  -- un evento de posteo para todo el lote

    -- 1a. Egreso de ajuste por (lote, ubicacion) con saldo > 0.
    --     precio_unitario NULL → trigger MAP no toca valuación (solo stock físico).
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, cantidad, fecha_hora,
        documento_tipo, documento_id, motivo_id, observacion)
    SELECT v_doc, l.item_id, l.id, v_tipo,
           ls.ubicacion_id, ls.cantidad_actual, now(),
           'RECONCILE_LEGACY_ORPHAN', l.id, v_motivo, 'RECONCILE_LEGACY_ORPHAN'
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    JOIN inventario.lote_saldo ls          ON ls.lote_id = l.id AND ls.cantidad_actual > 0
    WHERE l.fyh_elm IS NULL
      AND lrd.entrega_id IS NULL
      AND lrd.orden_servicio_id IS NULL
      AND l.fyh_cre <= v_cutoff
      AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      WHERE im.lote_id = l.id
                        AND im.observacion = 'RECONCILE_LEGACY_ORPHAN');
    GET DIAGNOSTICS v_movs = ROW_COUNT;

    -- 1b. Dar de baja los lotes ya retirados (saldo 0 tras el egreso).
    --     lote_rollo_detalle se conserva para trazabilidad.
    UPDATE inventario.lote l
    SET fyh_elm = now()
    WHERE l.fyh_elm IS NULL
      AND EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  WHERE im.lote_id = l.id
                    AND im.observacion = 'RECONCILE_LEGACY_ORPHAN');
    GET DIAGNOSTICS v_lotes = ROW_COUNT;

    RAISE NOTICE 'Retirados: % movimientos de egreso, % lotes dados de baja.', v_movs, v_lotes;
END $$;
COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VERIFY
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. No deberían quedar huérfanos pre-cutoff en stock (esperado: 0)
SELECT COUNT(*) AS huerfanos_pre_cutoff_en_stock
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.lote_saldo ls          ON ls.lote_id = l.id AND ls.cantidad_actual > 0
WHERE l.fyh_elm IS NULL
  AND lrd.entrega_id IS NULL
  AND lrd.orden_servicio_id IS NULL
  AND l.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;

-- 2b. Lo posteado
SELECT COUNT(*)                          AS movimientos,
       COUNT(DISTINCT lote_id)           AS lotes,
       ROUND(SUM(cantidad)::numeric, 2)  AS kg_retirados
FROM inventario.item_movimientos
WHERE observacion = 'RECONCILE_LEGACY_ORPHAN';


-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL (deshacer este script)
--   El trigger de stock restaura lote_saldo al borrar los movimientos.
-- ═══════════════════════════════════════════════════════════════════════════════
-- BEGIN;
-- UPDATE inventario.lote l
-- SET fyh_elm = NULL, usr_elm = NULL
-- WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
--               WHERE im.lote_id = l.id AND im.observacion = 'RECONCILE_LEGACY_ORPHAN');
-- DELETE FROM inventario.item_movimientos WHERE observacion = 'RECONCILE_LEGACY_ORPHAN';
-- COMMIT;

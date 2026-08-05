-- ============================================================================
-- TRACK A · Re-home migrated DYED dispatches onto outbound doc.entrega
-- ============================================================================
-- WHAT: migration-11 (lifecycle step 8) posted the dispatch egress of every dyed
--   output roll as a movement tagged documento_tipo='partida_paso_ejecucion' —
--   NOT on a proper outbound (emitida) delivery document. This re-homes those
--   egresses onto headless doc.entrega docs, WITHOUT reversing/re-posting.
--
-- WHY RE-HOME (not reverse+09): the egresses already name the exact dyed rolls;
--   public.despacho only has partida-level totals AND commingles the Track-B raw
--   dispatches, so it can't cleanly drive the dyed set. Re-home is self-contained,
--   changes NO stock (only relabels the movement's documento), and the saldo
--   trigger is AFTER INSERT only so UPDATEs don't perturb it.
--
-- SCOPE (verified): dyed (flg_tenido=true) SERV_EGR (16,466) + VENTA_EGR (3,067)
--   on partida_paso_ejecucion, all legacy (fyh_cre <= go-live), all already out of
--   stock. Movement type → outbound entrega tipo:
--     SERV_EGR  → DESPACHO_CLIENTE  (client-serviced)
--     VENTA_EGR → VENTA_EGRESO      (MLR-owned sold)
--   One HEADLESS entrega per (partida, tipo) — the real guía-de-salida number
--   lived only on paper; serie/correlativo NULL (chk allows both-null).
--
-- WRITES: doc.entrega (+ _detalle) created; item_movimientos.documento_tipo/id
--   repointed. Does NOT touch lote_rollo_detalle.entrega_id (that is the INGRESS
--   billing anchor, not a dispatch link) nor any stock/quantity.
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- ── §0 · DRY RUN — scope + gates ──────────────────────────────────────────────
WITH disp AS (
    SELECT im.id AS mov_id, im.lote_id, imt.codigo AS mov_code,
           pp.partida_id, im.fyh_cre,
           COALESCE((SELECT SUM(ls.cantidad_actual) FROM inventario.lote_saldo ls
                     WHERE ls.lote_id = im.lote_id), 0) AS stock
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                            AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id AND im.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
)
SELECT mov_code,
       COUNT(*)                                                          AS egresses,
       COUNT(*) FILTER (WHERE fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz) AS legacy_in_scope,
       COUNT(*) FILTER (WHERE fyh_cre >  '2026-05-25 15:27:52+00'::timestamptz) AS post_golive_EXCLUDED,
       COUNT(*) FILTER (WHERE stock > 0)                                 AS still_in_stock_flag,
       COUNT(DISTINCT partida_id)                                        AS partida_headers
FROM disp
GROUP BY mov_code ORDER BY egresses DESC;


-- ── §1 · Execute ──────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL statement_timeout = 0;

DO $$
DECLARE
    grp          RECORD;
    v_tipo_id    SMALLINT;
    v_entrega_id BIGINT;
    v_n_headers  INT := 0;
    v_n_moves    INT := 0;
    v_cnt        INT;
BEGIN
    FOR grp IN
        SELECT pp.partida_id,
               p.tercero_id,
               imt.codigo                                          AS mov_code,
               CASE imt.codigo WHEN 'SERV_EGR'  THEN 'DESPACHO_CLIENTE'
                               WHEN 'VENTA_EGR' THEN 'VENTA_EGRESO' END AS tipo_code,
               MIN(im.fecha_hora)                                  AS fecha
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                                                AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
        JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id AND im.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
        JOIN mes.partida p ON p.id = pp.partida_id
        WHERE im.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz     -- LEGACY GATE
          AND p.tercero_id IS NOT NULL
        GROUP BY pp.partida_id, p.tercero_id, imt.codigo
        ORDER BY pp.partida_id, imt.codigo
    LOOP
        SELECT id INTO STRICT v_tipo_id FROM doc.entrega_tipo WHERE codigo = grp.tipo_code;

        -- headless outbound entrega for this (partida, tipo)
        INSERT INTO doc.entrega (entrega_tipo_id, tercero_id, serie, correlativo,
                                 fecha_emision, usr_cre, fyh_cre)
        VALUES (v_tipo_id, grp.tercero_id, NULL, NULL, grp.fecha, 4, grp.fecha)
        RETURNING id INTO v_entrega_id;

        -- one detalle line per dispatched roll (still on pp_ejec at this point)
        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, lote_id, cantidad, n_rollos)
        SELECT v_entrega_id,
               (row_number() OVER (ORDER BY im.lote_id))::smallint,
               im.item_id, im.lote_id, l.cantidad, 1
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = grp.mov_code
        JOIN inventario.lote l ON l.id = im.lote_id
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
        JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id AND im.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
        WHERE pp.partida_id = grp.partida_id
          AND im.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;

        -- repoint the egress movements onto the entrega
        UPDATE inventario.item_movimientos im
        SET documento_tipo = 'entrega', documento_id = v_entrega_id
        FROM inventario.item_movimiento_tipo imt, mes.partida_paso_ejecucion ppe, mes.partida_paso pp
        WHERE imt.id = im.item_movimiento_tipo_id AND imt.codigo = grp.mov_code
          AND im.documento_tipo = 'partida_paso_ejecucion' AND ppe.id = im.documento_id
          AND pp.id = ppe.partida_paso_id AND pp.partida_id = grp.partida_id
          AND im.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
          AND EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle lrd
                      WHERE lrd.lote_id = im.lote_id AND lrd.flg_tenido = true);
        GET DIAGNOSTICS v_cnt = ROW_COUNT;

        v_n_headers := v_n_headers + 1;
        v_n_moves   := v_n_moves + v_cnt;
    END LOOP;

    RAISE NOTICE 'Done. % outbound entregas, % egress movements re-homed.', v_n_headers, v_n_moves;
END;
$$;


-- ── §2 · Verify ───────────────────────────────────────────────────────────────
-- (a) no legacy dyed SERV_EGR/VENTA_EGR left stranded on pp_ejec — expect 0
SELECT COUNT(*) AS dyed_dispatch_still_on_pp_ejec
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = true
WHERE im.documento_tipo = 'partida_paso_ejecucion'
  AND im.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;

-- (b) every re-homed egress now points at an EMITIDA entrega — expect 0 bad
SELECT COUNT(*) AS repointed_not_on_emitida
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE e.usr_cre = 4 AND et.flg_emitida = false;

-- (c) detalle lines == repointed movements for the new headers
SELECT (SELECT COUNT(*) FROM doc.entrega_detalle ed JOIN doc.entrega e ON e.id = ed.entrega_id
        WHERE e.usr_cre = 4 AND e.serie IS NULL
          AND e.entrega_tipo_id IN (SELECT id FROM doc.entrega_tipo WHERE codigo IN ('DESPACHO_CLIENTE','VENTA_EGRESO'))) AS detalle_lines,
       (SELECT COUNT(*) FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
        JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE e.usr_cre = 4) AS repointed_moves;

-- COMMIT;    -- ← after §2: (a)=0, (b)=0, (c) two columns equal
-- ROLLBACK;  -- ← if anything is off



-- 1. Which cuadre(s) touched this item today, and their current state
SELECT c.id, c.estado, c.fecha_cierre, c.usr_mod, c.fyh_mod, c.almacen_id
FROM inventario.cuadre c
WHERE c.fyh_mod::date = '2026-07-07'
ORDER BY c.fyh_mod;

-- 2. Every AJUSTE_POS / AJUSTE_NEG movement posted today
SELECT im.id, im.fecha_hora, imt.codigo, im.cantidad,
       im.origen_ubicacion_id, im.destino_ubicacion_id,
       im.documento_tipo, im.documento_id, im.doc_movimiento_id,
       im.item_id, im.lote_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE imt.codigo IN ('AJUSTE_POS','AJUSTE_NEG')
  AND im.fecha_hora::date = '2026-07-07'
ORDER BY im.fecha_hora;

-- 3. logs_api entries for the reversal/finalize calls today
SELECT id, function_name, user_id, params, called_at
FROM logs_api
WHERE function_name IN ('finalizar_cuadre','anular_cuadre_ejecutado','revertir_cuadre_preparado')
  AND called_at::date = '2026-07-07'
ORDER BY called_at;

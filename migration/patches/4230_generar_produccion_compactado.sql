-- Partida 4230 — COMPACTADO (ejecucion 7766, paso 17512, operacion COMPACTADO)
-- Same root cause as partida 4320 (mistakenly patched first):
-- Legacy migration posted SERV_ING+SERV_EGR atomically, netting input rolls to
-- saldo=0. registrar_produccion was never called, so no output lotes exist.
-- Fix:
--   1. Reopen partida (CERRADA → EN_PRODUCCION)
--   2. Create output lotes linked to ejecucion 7766 (enables Path A QC)
--   3. Post PROD_ING movements + insert lote_saldo directly (trigger skips NULL ubicacion)
--   4. lote_rollo_detalle inherits entrega/os anchor + origin link from input lotes

DO $$
DECLARE
    v_doc_mov_id    BIGINT;
    v_ing_tipo_id   SMALLINT;
    v_new_lote_id   INT;
    v_count         INT := 0;
    r               RECORD;
    v_ancho         TEXT;
    v_malla         TEXT;
    v_rendimiento   TEXT;
    v_cxc_id        INT;
    v_tenido_id     INT;
    v_antipilling   BOOLEAN;
BEGIN
    -- ── Guards ──────────────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM mes.partida_paso_ejecucion ppe
        JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
        WHERE ppe.id = 7766 AND pp.partida_id = 4230
    ) THEN
        RAISE EXCEPTION 'Ejecucion 7766 does not belong to partida 4230 — aborting';
    END IF;

    IF EXISTS (
        SELECT 1 FROM inventario.lote
        WHERE documento_tipo = 'partida_paso_ejecucion'
          AND documento_id = 7766
          AND fyh_elm IS NULL
    ) THEN
        RAISE EXCEPTION 'Output lotes already exist for ejecucion 7766 — aborting to prevent duplicates';
    END IF;

    -- ── 1. Reopen partida ───────────────────────────────────────────────────
    UPDATE mes.partida
    SET estado_produccion = 'EN_PRODUCCION',
        fyh_mod           = now(),
        usr_mod           = NULL
    WHERE id = 4230
      AND estado_produccion = 'CERRADA';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida 4230 is not CERRADA — unexpected state, aborting';
    END IF;

    -- ── Fetch partida-level lrd attributes ─────────────────────────────────
    SELECT ancho, malla, rendimiento, color_x_cliente_id, tenido_id, flg_antipilling
    INTO v_ancho, v_malla, v_rendimiento, v_cxc_id, v_tenido_id, v_antipilling
    FROM mes.partida WHERE id = 4230;

    SELECT id INTO v_ing_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- ── One output lote per input roll ──────────────────────────────────────
    FOR r IN
        SELECT
            l.id             AS input_lote_id,
            l.item_id,
            l.propietario_id,
            l.cantidad,
            lrd.entrega_id,
            lrd.orden_servicio_id,
            lrd.flg_tenido
        FROM mes.partida_componente           pc
        JOIN inventario.lote                  l   ON l.id = pc.lote_id
        LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
        WHERE pc.partida_id = 4230
          AND pc.lote_id IS NOT NULL
        ORDER BY l.id
    LOOP
        INSERT INTO inventario.lote(item_id, documento_tipo, documento_id, cantidad, propietario_id)
        VALUES (r.item_id, 'partida_paso_ejecucion', 7766, r.cantidad, r.propietario_id)
        RETURNING id INTO v_new_lote_id;

        INSERT INTO inventario.item_movimientos(
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            destino_ubicacion_id, cantidad, documento_tipo, documento_id
        )
        VALUES (v_doc_mov_id, r.item_id, v_new_lote_id, v_ing_tipo_id,
                NULL, r.cantidad, 'partida_paso_ejecucion', 7766);

        -- fn_trg_sync_cantidad_actual only fires for non-NULL ubicacion_id.
        INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
        VALUES (v_new_lote_id, NULL, r.cantidad)
        ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
            SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;

        INSERT INTO inventario.lote_rollo_detalle(
            lote_id, entrega_id, orden_servicio_id, origen_lote_id,
            ancho, malla, rendimiento, color_x_cliente_id, tenido_id,
            flg_tenido, flg_antipilling
        )
        VALUES (
            v_new_lote_id, r.entrega_id, r.orden_servicio_id, r.input_lote_id,
            v_ancho, v_malla, v_rendimiento, v_cxc_id, v_tenido_id,
            r.flg_tenido, v_antipilling
        );

        v_count := v_count + 1;
    END LOOP;

    RAISE NOTICE 'Done: partida 4230 reopened, % output lotes created for ejecucion 7766 (doc_movimiento_id=%)',
        v_count, v_doc_mov_id;
END;
$$;

-- ── Verify ──────────────────────────────────────────────────────────────────
SELECT
    l.id                AS output_lote_id,
    EXTRACT(YEAR FROM l.fyh_cre)::int % 100 || '-' || LPAD(l.secuencia::text, 5, '0') AS lote_codigo,
    l.cantidad          AS kg,
    ls.cantidad_actual  AS saldo_actual,
    p.estado_produccion AS partida_estado
FROM inventario.lote l
LEFT JOIN inventario.lote_saldo       ls  ON ls.lote_id = l.id
JOIN mes.partida_paso_ejecucion       ppe ON ppe.id = l.documento_id
JOIN mes.partida_paso                 pp  ON pp.id  = ppe.partida_paso_id
JOIN mes.partida                      p   ON p.id   = pp.partida_id
WHERE l.documento_tipo = 'partida_paso_ejecucion'
  AND l.documento_id   = 7766
  AND l.fyh_elm IS NULL
ORDER BY l.id;

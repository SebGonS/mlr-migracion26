-- ============================================================================
-- TRACK B · Production backfill for raw shortcut-dispatched rolls (CLEAN RUN)
-- ============================================================================
-- WHAT: 529 legacy partidas / 10,185 raw rolls (flg_tenido=false) were shipped raw
--   as a shortcut — SERV_ING then straight SERV_EGR on documento_tipo='PARTIDA',
--   production flow SKIPPED. They must instead go THROUGH production: consume the
--   raw roll → produce a dyed child → dispatch the dyed child on a proper outbound
--   entrega. This synthesizes that lifecycle on the partida's COMPACTADO ejecucion
--   (compactado = the app's PROD_CONSUMO closure step, funciones/mes.sql:4709;
--   movement shape mirrors registrar_produccion mes.sql:1674-1767).
--
-- WHY DIRECT LEDGER WRITES (not registrar_produccion): the rolls already egressed —
--   0 stock — so the function would underflow. We write movements DIRECTLY in
--   historical order and set lote_saldo explicitly.
--
-- PER RAW ROLL (net stock 0 for raw, 0 for dyed child):
--   1. DELETE the phantom raw SERV_EGR on PARTIDA (it stood in for consumption).
--   2. PROD_CONSUMO (-1) on the raw roll → doc=partida_paso_ejecucion (compactado ejec).
--   3. NEW dyed lote (documento_tipo='partida_paso_ejecucion', doc=ejec, cantidad=raw
--      weight, propietario inherited) + lote_rollo_detalle (origen_lote_id=raw,
--      flg_tenido=true, entrega_id inherited from raw anchor, dyeing identity from partida).
--   4. PROD_ING (+1) on the dyed child → into stock (ALM_CRU).
--   5. SERV_EGR|VENTA_EGR (-1) on the dyed child → headless outbound entrega
--      (one per partida×tipo; tipo by propietario: 1→VENTA_EGRESO else DESPACHO_CLIENTE).
--
-- ROLL→EJEC: within a partida, distribute rolls across its compactado ejec(s),
--   bucketed by each ejec's cantidad_rollos (never overflow one). 407 partidas have
--   1 ejec (trivial); 122 have >1 (2,470 rolls).
--
-- SCOPE (locked, track_b_build_scope_lock.sql + track_b_scope_tighten.sql):
--   legacy partida.fyh_cre<=go-live + compactado paso+ejec + SUPPLY(Σ ejec
--   cantidad_rollos) >= DEMAND(raw rolls) + roll out of stock + NO roll already has a
--   child + partida is NOT live (terminal estado AND no post-go-live ejec).
--   → 525 partidas / 10,116 rolls.
--   EXCLUDED as LIVE app data (activity-level gate, NOT just partida.fyh_cre):
--     • 4320 (12 rolls) — children 131340-131351 produced POST-go-live (2026-06-11) on
--       compactado ejec 7863; EN_PRODUCCION; rework child 6075. NOT a devolución.
--     • 4941 (CERRADA), 5058 (TECO) — nominally closed but carry post-go-live ejec.
--     • 4595 (CREADA, active; also holds return roll 90129).
--   DEFERRED (NOT here): 60 supply<demand partidas, 35 no-compactado-ejec gaps.
--   Does NOT touch ejec cantidad_rollos/peso_kg snapshots.
--
-- WRITES: DELETE item_movimientos (phantom SERV_EGR); INSERT item_movimientos
--   (PROD_CONSUMO/PROD_ING/dyed-egress), inventario.lote + lote_rollo_detalle (dyed
--   children), doc.entrega + entrega_detalle (outbound), lote_saldo (explicit).
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════════
-- §0 · DRY RUN — scope + integrity (no writes)
-- ══════════════════════════════════════════════════════════════════════════════
WITH tb_roll AS (
    SELECT im.id AS egr_mov_id, im.lote_id, im.documento_id AS partida_id,
           im.item_id, im.cantidad, im.fecha_hora, im.origen_ubicacion_id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
    WHERE im.documento_tipo='PARTIDA'
      AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=im.lote_id),0) = 0
),
demand AS (SELECT partida_id, COUNT(DISTINCT lote_id) AS raw_shipped FROM tb_roll GROUP BY partida_id),
supply AS (
    SELECT pp.partida_id, SUM(ppe.cantidad_rollos) AS supply_rollos
    FROM mes.partida_paso pp
    JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
    JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
    GROUP BY pp.partida_id
),
-- partidas where ANY raw roll already has a child lote (origen_lote_id) — a real
-- rework already recorded (e.g. 4320 re-ingress). Exclude the WHOLE partida.
childed_partida AS (
    SELECT DISTINCT tr.partida_id
    FROM tb_roll tr
    WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id = tr.lote_id)
),
-- ACTIVITY-level legacy gate (TIMESTAMP-based, NOT estado_produccion — status is
-- mutable and lies: 4941 CERRADA / 5058 TECO both carry live post-go-live ejecs).
-- partida.fyh_cre<=go-live is not enough — a legacy-created partida can carry LIVE
-- post-go-live production. Exclude any partida with post-go-live ACTIVITY: an ejec
-- started or created post-go-live, OR a rework child partida created post-go-live
-- (catches 4595, whose live signal is only the rework child). Verified this gate
-- excludes exactly {4320(childed),4595,4941,5058} — track_b_gate_options.sql.
live_partida AS (
    SELECT p.id AS partida_id
    FROM mes.partida p
    WHERE EXISTS (SELECT 1 FROM mes.partida_paso pp
                  JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                  WHERE pp.partida_id=p.id
                    AND (ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz
                      OR ppe.fyh_cre    > '2026-05-25 15:27:52+00'::timestamptz))
       OR EXISTS (SELECT 1 FROM mes.partida ch
                  WHERE ch.partida_origen_id = p.id
                    AND ch.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz)
),
in_scope AS (
    SELECT d.partida_id
    FROM demand d
    JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
    JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
    WHERE d.partida_id NOT IN (SELECT partida_id FROM childed_partida)
      AND d.partida_id NOT IN (SELECT partida_id FROM live_partida)
),
scope_rolls AS (SELECT tr.* FROM tb_roll tr JOIN in_scope s ON s.partida_id=tr.partida_id)
SELECT
    (SELECT COUNT(DISTINCT partida_id) FROM scope_rolls)                  AS partidas_expect_525,
    (SELECT COUNT(*) FROM scope_rolls)                                    AS rolls_expect_10116,
    -- every scope roll has exactly one raw SERV_EGR to delete
    (SELECT COUNT(*) FROM scope_rolls sr WHERE (SELECT COUNT(*) FROM inventario.item_movimientos im2
        JOIN inventario.item_movimiento_tipo i2 ON i2.id=im2.item_movimiento_tipo_id AND i2.codigo='SERV_EGR'
        WHERE im2.lote_id=sr.lote_id AND im2.documento_tipo='PARTIDA') <> 1) AS rolls_not_single_egr_expect_0,
    -- none already have a PROD_CONSUMO or dyed child (would be double-processing)
    (SELECT COUNT(*) FROM scope_rolls sr WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im2
        JOIN inventario.item_movimiento_tipo i2 ON i2.id=im2.item_movimiento_tipo_id AND i2.codigo='PROD_CONSUMO'
        WHERE im2.lote_id=sr.lote_id))                                    AS rolls_already_consumed_expect_0,
    (SELECT COUNT(*) FROM scope_rolls sr WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id=sr.lote_id))                              AS rolls_already_have_child_expect_0,
    -- partida.tercero_id present for every scope partida (needed for the entrega header)
    (SELECT COUNT(*) FROM in_scope s JOIN mes.partida p ON p.id=s.partida_id WHERE p.tercero_id IS NULL) AS partidas_no_tercero_expect_0;


-- ══════════════════════════════════════════════════════════════════════════════
-- §1 · Execute
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL statement_timeout = 0;

-- historical-dated movements would trip the cuadre-cutoff guard; disable for backfill
ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

DO $$
DECLARE
    v_cutoff      timestamptz := '2026-05-25 15:27:52+00';
    v_consumo_tid int;  v_ing_tid int;  v_egr_tid int;  v_venta_tid int;
    v_alm_cru_ubic int;
    v_n_rolls int := 0;  v_n_children int := 0;  v_n_entregas int := 0;
BEGIN
    SELECT id INTO v_consumo_tid FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO';
    SELECT id INTO v_ing_tid     FROM inventario.item_movimiento_tipo WHERE codigo='PROD_ING';
    SELECT id INTO v_egr_tid     FROM inventario.item_movimiento_tipo WHERE codigo='SERV_EGR';
    SELECT id INTO v_venta_tid   FROM inventario.item_movimiento_tipo WHERE codigo='VENTA_EGR';
    -- ALM_CRU default ubicacion (raw + dyed rolls live in crudo warehouse pre-dispatch)
    SELECT u.id INTO v_alm_cru_ubic
    FROM inventario.ubicacion u JOIN inventario.almacen a ON a.id=u.almacen_id
    WHERE a.codigo='ALM_CRU' ORDER BY u.id LIMIT 1;

    ------------------------------------------------------------------------------
    -- Materialize the in-scope raw rolls + assign each to a compactado ejec.
    -- ejec picked by bucketing: order ejecs by id, give each a running capacity =
    -- cantidad_rollos; order rolls by lote_id; the k-th roll lands in the ejec whose
    -- cumulative capacity first covers k. (supply>=demand guarantees a home.)
    ------------------------------------------------------------------------------
    CREATE TEMP TABLE _tb ON COMMIT DROP AS
    WITH tb_roll AS (
        SELECT im.id AS egr_mov_id, im.lote_id, im.documento_id AS partida_id,
               im.item_id, im.cantidad AS peso, im.fecha_hora, im.origen_ubicacion_id
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
        WHERE im.documento_tipo='PARTIDA'
          AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=im.lote_id),0)=0
    ),
    demand AS (SELECT partida_id, COUNT(DISTINCT lote_id) AS raw_shipped FROM tb_roll GROUP BY partida_id),
    supply AS (
        SELECT pp.partida_id, SUM(ppe.cantidad_rollos) AS supply_rollos
        FROM mes.partida_paso pp
        JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
        GROUP BY pp.partida_id
    ),
    childed_partida AS (   -- exclude whole partida if any raw roll already has a child
        SELECT DISTINCT tr.partida_id
        FROM tb_roll tr
        WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id = tr.lote_id)
    ),
    live_partida AS (   -- timestamp-based activity gate (see §0 comment); NOT estado
        SELECT p.id AS partida_id
        FROM mes.partida p
        WHERE EXISTS (SELECT 1 FROM mes.partida_paso pp
                      JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
                      WHERE pp.partida_id=p.id
                        AND (ppe.fyh_inicio > v_cutoff OR ppe.fyh_cre > v_cutoff))
           OR EXISTS (SELECT 1 FROM mes.partida ch
                      WHERE ch.partida_origen_id = p.id AND ch.fyh_cre > v_cutoff)
    ),
    in_scope AS (
        SELECT d.partida_id
        FROM demand d
        JOIN supply s ON s.partida_id=d.partida_id AND s.supply_rollos >= d.raw_shipped
        JOIN mes.partida p ON p.id=d.partida_id AND p.fyh_cre <= v_cutoff
        WHERE d.partida_id NOT IN (SELECT partida_id FROM childed_partida)
          AND d.partida_id NOT IN (SELECT partida_id FROM live_partida)
    ),
    -- compactado ejecs per scope partida, with a running-capacity upper bound
    ejec AS (
        SELECT pp.partida_id, ppe.id AS ejec_id, ppe.cantidad_rollos,
               COALESCE(SUM(ppe.cantidad_rollos) OVER (PARTITION BY pp.partida_id
                        ORDER BY ppe.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),0) AS cum_cap,
               COALESCE(SUM(ppe.cantidad_rollos) OVER (PARTITION BY pp.partida_id
                        ORDER BY ppe.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS cum_cap_prev
        FROM mes.partida_paso pp
        JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
        JOIN in_scope s ON s.partida_id=pp.partida_id
    ),
    ranked AS (
        SELECT tr.*, row_number() OVER (PARTITION BY tr.partida_id ORDER BY tr.lote_id) AS rn
        FROM tb_roll tr JOIN in_scope s ON s.partida_id=tr.partida_id
    )
    SELECT r.egr_mov_id, r.lote_id, r.partida_id, r.item_id, r.peso, r.fecha_hora,
           COALESCE(r.origen_ubicacion_id, v_alm_cru_ubic) AS ubic_id,
           e.ejec_id
    FROM ranked r
    JOIN ejec e ON e.partida_id=r.partida_id
               AND r.rn > e.cum_cap_prev AND r.rn <= e.cum_cap;  -- bucket assignment

    -- guard: exactly 10,185 rolls, every one assigned to exactly one ejec.
    -- (a NULL cantidad_rollos on any in-scope compactado ejec would break the bucket
    --  math — the coverage diagnostic showed 0 such, but fail loudly if that changes:
    --  a roll whose rn exceeds all cum_cap would be UNASSIGNED and caught below.)
    IF (SELECT COUNT(*) FROM _tb) <> 10116
       OR (SELECT COUNT(*) FROM _tb WHERE ejec_id IS NULL) <> 0
       OR (SELECT COUNT(*) FROM (SELECT lote_id FROM _tb GROUP BY lote_id HAVING COUNT(*)>1) x) <> 0 THEN
        RAISE EXCEPTION 'scope/assignment mismatch: n=%, unassigned=%, dupes=%',
            (SELECT COUNT(*) FROM _tb),
            (SELECT COUNT(*) FROM _tb WHERE ejec_id IS NULL),
            (SELECT COUNT(*) FROM (SELECT lote_id FROM _tb GROUP BY lote_id HAVING COUNT(*)>1) x);
    END IF;

    -- doc_movimiento_id groups movements of one posting event (NOT NULL column).
    -- One id per ejec (shared by that ejec's PROD_CONSUMO + PROD_ING), mirroring
    -- registrar_produccion which shares a single doc id across backflush + output.
    ALTER TABLE _tb ADD COLUMN doc_mov_id bigint;
    UPDATE _tb SET doc_mov_id = d.doc_id
    FROM (SELECT ejec_id, nextval('inventario.mov_doc_seq') AS doc_id
          FROM (SELECT DISTINCT ejec_id FROM _tb) e) d
    WHERE _tb.ejec_id = d.ejec_id;

    ------------------------------------------------------------------------------
    -- STEP 1 · delete the phantom raw SERV_EGR (stood in for consumption)
    ------------------------------------------------------------------------------
    DELETE FROM inventario.item_movimientos im USING _tb WHERE im.id = _tb.egr_mov_id;

    ------------------------------------------------------------------------------
    -- STEP 2 · PROD_CONSUMO on the raw roll (egress; origen set, destino NULL)
    ------------------------------------------------------------------------------
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT doc_mov_id, item_id, lote_id, v_consumo_tid, ubic_id, NULL, peso,
           fecha_hora, 'partida_paso_ejecucion', ejec_id, 4, fecha_hora
    FROM _tb;

    ------------------------------------------------------------------------------
    -- STEP 3 · create the dyed child lote + its lote_rollo_detalle
    --   (inherit item/propietario/entrega anchor from the raw parent; dyeing identity
    --    from the partida — mirrors registrar_produccion). One INSERT ... RETURNING
    --    per raw roll so the raw→child id mapping stays exact even when pesos collide.
    ------------------------------------------------------------------------------
    -- source rows for children (immutable; we iterate this, write into _map)
    CREATE TEMP TABLE _src ON COMMIT DROP AS
    SELECT t.lote_id AS raw_lote_id, t.ejec_id, t.item_id, t.peso, t.fecha_hora, t.ubic_id,
           rl.propietario_id, lrd.entrega_id,
           p.ancho, p.malla, p.rendimiento, p.color_x_cliente_id, p.tenido_id, p.flg_antipilling
    FROM _tb t
    JOIN inventario.lote rl ON rl.id = t.lote_id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = t.lote_id
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = t.ejec_id
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p ON p.id = pp.partida_id;

    CREATE TEMP TABLE _map(raw_lote_id int PRIMARY KEY, new_lote_id int, ejec_id int, item_id int,
                           peso numeric, fecha_hora timestamptz, ubic_id int,
                           propietario_id int, entrega_id bigint) ON COMMIT DROP;

    -- create one dyed lote per source row, capturing its id into _map (iterate _src,
    -- write _map — never mutate the table being iterated)
    DECLARE r record; v_id int;
    BEGIN
        FOR r IN SELECT * FROM _src ORDER BY raw_lote_id LOOP
            INSERT INTO inventario.lote(item_id, documento_tipo, documento_id, cantidad, propietario_id, fyh_cre)
            VALUES (r.item_id, 'partida_paso_ejecucion', r.ejec_id, r.peso, r.propietario_id, r.fecha_hora)
            RETURNING id INTO v_id;

            INSERT INTO _map(raw_lote_id, new_lote_id, ejec_id, item_id, peso, fecha_hora, ubic_id,
                             propietario_id, entrega_id)
            VALUES (r.raw_lote_id, v_id, r.ejec_id, r.item_id, r.peso, r.fecha_hora, r.ubic_id,
                    r.propietario_id, r.entrega_id);

            INSERT INTO inventario.lote_rollo_detalle(
                lote_id, entrega_id, origen_lote_id, ancho, malla, rendimiento,
                color_x_cliente_id, tenido_id, flg_tenido, flg_antipilling, usr_cre, fyh_cre)
            VALUES (v_id, r.entrega_id, r.raw_lote_id, r.ancho, r.malla, r.rendimiento,
                    r.color_x_cliente_id, r.tenido_id, true, r.flg_antipilling, 4, r.fecha_hora);
        END LOOP;
    END;

    ------------------------------------------------------------------------------
    -- STEP 4 · PROD_ING on the dyed child (ingress; destino set)
    ------------------------------------------------------------------------------
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT dm.doc_mov_id, m.item_id, m.new_lote_id, v_ing_tid, NULL, m.ubic_id, m.peso,
           m.fecha_hora, 'partida_paso_ejecucion', m.ejec_id, 4, m.fecha_hora
    FROM _map m
    JOIN (SELECT DISTINCT ejec_id, doc_mov_id FROM _tb) dm ON dm.ejec_id = m.ejec_id;

    ------------------------------------------------------------------------------
    -- STEP 5 · dispatch the dyed child: headless outbound entrega per (partida,tipo)
    --   + SERV_EGR|VENTA_EGR egress. tipo by propietario (1→VENTA else DESPACHO).
    ------------------------------------------------------------------------------
    CREATE TEMP TABLE _disp ON COMMIT DROP AS
    SELECT m.new_lote_id, m.item_id, m.peso, m.ubic_id, m.fecha_hora,
           pp.partida_id, p.tercero_id,
           (m.propietario_id = 1) AS is_venta,
           NULL::bigint AS entrega_id,
           NULL::bigint AS doc_mov_id
    FROM _map m
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id = m.ejec_id
    JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p ON p.id = pp.partida_id;

    -- one headless entrega per (partida, is_venta); fecha = MIN dispatch date in group.
    -- nested PL/pgSQL block (NOT a DO — DO is not valid inside a function/DO body)
    DECLARE g record; v_tipo_id smallint; v_eid bigint;
    BEGIN
        FOR g IN SELECT partida_id, tercero_id, is_venta, MIN(fecha_hora) AS fecha
                 FROM _disp GROUP BY partida_id, tercero_id, is_venta LOOP
            SELECT id INTO v_tipo_id FROM doc.entrega_tipo
              WHERE codigo = CASE WHEN g.is_venta THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END;
            INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo,
                                    fecha_emision, usr_cre, fyh_cre)
            VALUES (v_tipo_id, g.tercero_id, NULL, NULL, g.fecha, 4, g.fecha)
            RETURNING id INTO v_eid;
            UPDATE _disp SET entrega_id = v_eid
            WHERE partida_id=g.partida_id AND is_venta=g.is_venta;
        END LOOP;
    END;

    -- one doc_movimiento_id per entrega (shared by that dispatch's egress movements)
    UPDATE _disp SET doc_mov_id = d.doc_id
    FROM (SELECT entrega_id, nextval('inventario.mov_doc_seq') AS doc_id
          FROM (SELECT DISTINCT entrega_id FROM _disp) e) d
    WHERE _disp.entrega_id = d.entrega_id;

    -- entrega_detalle: one line per dyed roll (linea unique per entrega)
    INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, lote_id, cantidad, n_rollos)
    SELECT entrega_id,
           (row_number() OVER (PARTITION BY entrega_id ORDER BY new_lote_id))::smallint,
           item_id, new_lote_id, peso, 1
    FROM _disp;

    -- egress movement on the dyed child (origen set, destino NULL)
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT doc_mov_id, item_id, new_lote_id,
           CASE WHEN is_venta THEN v_venta_tid ELSE v_egr_tid END,
           ubic_id, NULL, peso, fecha_hora, 'entrega', entrega_id, 4, fecha_hora
    FROM _disp;

    ------------------------------------------------------------------------------
    -- STEP 6 · lote_saldo — both raw (consumed) and dyed (dispatched) net to 0.
    --   Saldo trigger is AFTER INSERT only and we inserted mixed +/-; set explicitly.
    ------------------------------------------------------------------------------
    -- raw rolls: consumed → 0 (delete any stale positive saldo row)
    DELETE FROM inventario.lote_saldo ls USING _tb t
    WHERE ls.lote_id = t.lote_id AND ls.cantidad_actual <> 0;
    -- dyed children: produced then dispatched → net 0 (no saldo row needed)
    DELETE FROM inventario.lote_saldo ls USING _map m
    WHERE ls.lote_id = m.new_lote_id;

    SELECT COUNT(*) INTO v_n_rolls    FROM _tb;
    SELECT COUNT(*) INTO v_n_children FROM _map;
    SELECT COUNT(DISTINCT entrega_id) INTO v_n_entregas FROM _disp;
    RAISE NOTICE 'Track B backfill: % raw consumed, % dyed children, % outbound entregas.',
        v_n_rolls, v_n_children, v_n_entregas;
END $$;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify  (run BEFORE COMMIT — references this run's temp tables _tb/_map/_disp,
--   which are the exact set we touched; immune to usr_cre=4 collision with prior scripts)
-- ══════════════════════════════════════════════════════════════════════════════
-- (a) every raw roll we touched now shows received→consumed, NO raw SERV_EGR left,
--     and a dyed child exists. Expect: with_child=10116, consumed=10116, egr_left=0.
SELECT
    (SELECT COUNT(*) FROM _tb)                                                AS raw_touched_expect_10116,
    (SELECT COUNT(*) FROM _tb t WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id=t.lote_id AND c.flg_tenido=true))             AS raw_with_dyed_child,
    (SELECT COUNT(*) FROM _tb t WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='PROD_CONSUMO'
        WHERE im.lote_id=t.lote_id AND im.documento_tipo='partida_paso_ejecucion')) AS raw_consumed,
    (SELECT COUNT(*) FROM _tb t WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
        WHERE im.lote_id=t.lote_id AND im.documento_tipo='PARTIDA'))          AS raw_still_partida_egr_expect_0;

-- (b) every new dyed child nets to 0 (PROD_ING +1, dispatch -1) and its raw parent
--     nets to 0 (SERV_ING +1, PROD_CONSUMO -1). Expect pairs=10173, both net0=10173.
SELECT
    COUNT(*)                                                          AS pairs_expect_10116,
    COUNT(*) FILTER (WHERE dyed_net = 0)                              AS dyed_net0,
    COUNT(*) FILTER (WHERE raw_net  = 0)                              AS raw_net0
FROM (
    SELECT m.new_lote_id AS dyed, m.raw_lote_id AS raw,
        (SELECT COALESCE(SUM(imt.factor*im.cantidad),0) FROM inventario.item_movimientos im
         JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id WHERE im.lote_id=m.new_lote_id) AS dyed_net,
        (SELECT COALESCE(SUM(imt.factor*im.cantidad),0) FROM inventario.item_movimientos im
         JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id WHERE im.lote_id=m.raw_lote_id)  AS raw_net
    FROM _map m
) x;

-- (c) outbound entregas created + detalle lines == dispatched children (10173)
SELECT
    (SELECT COUNT(DISTINCT entrega_id) FROM _disp)                            AS outbound_entregas,
    (SELECT COUNT(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT DISTINCT entrega_id FROM _disp)) AS detalle_lines_expect_10116,
    (SELECT COUNT(*) FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
        WHERE im.documento_tipo='entrega' AND im.documento_id IN (SELECT DISTINCT entrega_id FROM _disp)) AS dyed_egress_moves_expect_10116;

-- (d) no lote_saldo left nonzero for any raw or dyed roll we touched (this run only). Expect 0.
SELECT COUNT(*) AS nonzero_saldo_expect_0
FROM inventario.lote_saldo ls
WHERE ls.cantidad_actual <> 0
  AND (ls.lote_id IN (SELECT lote_id FROM _tb)
    OR ls.lote_id IN (SELECT new_lote_id FROM _map));

-- (e) remaining Track-B raw SERV_EGR on PARTIDA = original 12,072 - 10,116 = 1,956
--     (deferred: 60 supply<demand + 35 no-compactado-ejec gaps + already-childed 4320
--      + live partidas 4595/4941/5058 + return 90129 + their overlaps).
SELECT COUNT(DISTINCT im.lote_id) AS track_b_raw_remaining_expect_1956
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo='SERV_EGR'
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=im.lote_id AND lrd.flg_tenido=false
WHERE im.documento_tipo='PARTIDA';

-- COMMIT;    -- ← after §2: (a) 10116/10116/10116/0, (b) 10116/10116/10116, (c) lines=10116 & egress=10116, (d)=0, (e)=1956
-- ROLLBACK;  -- ← if anything is off

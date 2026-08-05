-- ============================================================================
-- TRACK B · Phase 1b — physical-ledger backfill for lote-less DISPATCHED rolls
--   (multi-line / multi-shipment partidas — LEDGER-FIRST linkage)
-- ============================================================================
-- WHAT: 411 legacy partidas / 6,839 dispatched rolls, same situation as Phase 1
--   (billed via a live doc.venta, but no dyed output lote and no item_movimientos;
--   raw input rolls still in stock) — EXCEPT these partidas have MORE THAN ONE live
--   venta line (they were dispatched across multiple shipments/ventas, same
--   tenido×color). Identical consume→dye→dispatch mechanic as Phase 1.
--
-- LEDGER-FIRST LINKAGE (decided with user 2026-07-28): the physical ledger is the
--   goal; per-shipment venta precision is a LOWER priority (deferred to the billing
--   cleanup). So we create ONE entrega per partida and link it to the partida's
--   PRIMARY venta = the lowest-id live venta (its lowest venta_detalle line). The
--   other ventas of the partida are left un-entrega'd for now — a known, accepted
--   approximation. This is NOT a ledger problem (every roll is egressed exactly once);
--   it only under-links the secondary shipments commercially, to be perfected later
--   via the deterministic despacho→venta grp_key mapping (F:/R:/N: keys, see
--   migrate_despacho_to_venta.sql). ~3-8 partidas whose internal refs don't recompose
--   cleanly are the reason the exact split was deferred rather than done here.
--
-- Everything else is IDENTICAL to backfill_track_b_phase1_single_line.sql:
--   • WEIGHT BASIS B (proration) — dyed child inherits the raw roll's lote.cantidad.
--   • PRISTINE guard (raw, in-stock, no prior SERV_EGR/VENTA_EGR/SERV_DEV_ING/
--     PROD_ING/PROD_CONSUMO) — the double-egress protection; also excludes patch-57
--     restocked rolls. supply(7,622) - demand(6,839) = 783 leftover raw stay in stock.
--   • OVERDRAW = ledger double-egress only; no lote egressed twice; PROD_CONSUMO only
--     on saldo>0 rolls; verified 0 intra-scope roll sharing. Reservation correctness
--     (partida_componente) intentionally NOT validated — deferred.
--   • Movement-aware scope: verified 0 Phase-1b partidas already have a dispatch egress.
--   • No phantom-egress DELETE (rolls are in stock, never egressed).
--   • Historical dating (MIN despacho.fecha_despacho); corte_cuadre trigger disabled.
--
-- PER DISPATCHED ROLL (raw net → 0, dyed child net → 0):
--   1. PROD_CONSUMO (-1) raw → doc=partida_paso_ejecucion (MIN compactado ejec).
--   2. NEW dyed child lote (inherit weight, estado_calidad=APROBADO, origen_lote_id=raw).
--   3. PROD_ING (+1) dyed child.
--   4. SERV_EGR|VENTA_EGR (-1) dyed child → one entrega per partida, venta_id = PRIMARY
--      venta. tipo by propietario (1 → VENTA_EGRESO else DESPACHO_CLIENTE).
--   5. entrega_detalle line, venta_detalle_id = primary venta's line.
--
-- WRITES: same as Phase 1 (item_movimientos, lote + lote_rollo_detalle, entrega +
--   entrega_detalle; cleans zero lote_saldo). Creates/modifies NO doc.venta.
--
-- ⚠ DRY-RUN §0 (read-only), run §1, read §2, then COMMIT.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════════
-- §0 · DRY RUN — scope + integrity (no writes)
-- ══════════════════════════════════════════════════════════════════════════════
WITH
despacho_p AS (SELECT DISTINCT partida_id FROM public.despacho WHERE flg_elm IS NOT TRUE AND partida_id IS NOT NULL),
has_output AS (
  SELECT DISTINCT pp.partida_id FROM inventario.lote l
  JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
  JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id),
live_p AS (SELECT partida_id FROM (
    SELECT pp.partida_id FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
      WHERE ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz OR ppe.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz
    UNION SELECT ch.partida_origen_id FROM mes.partida ch WHERE ch.partida_origen_id IS NOT NULL AND ch.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz
    UNION SELECT pc.partida_id FROM mes.partida_componente pc JOIN inventario.pesaje pz ON pz.lote_id=pc.lote_id WHERE pz.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz
  ) u WHERE partida_id IS NOT NULL),
in_scope AS (SELECT d.partida_id FROM despacho_p d
  WHERE d.partida_id NOT IN (SELECT partida_id FROM has_output) AND d.partida_id NOT IN (SELECT partida_id FROM live_p)),
compactado AS (SELECT DISTINCT pp.partida_id FROM mes.partida_paso pp
  JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
  JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id),
demand AS (SELECT partida_id, SUM(COALESCE(rollos_total,0)) AS dispatched
  FROM public.despacho WHERE flg_elm IS NOT TRUE GROUP BY partida_id),
supply AS (SELECT pc.partida_id, count(*) AS raw_rolls
  FROM mes.partida_componente pc JOIN in_scope s ON s.partida_id=pc.partida_id
  JOIN inventario.lote l ON l.id=pc.lote_id
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=pc.lote_id AND lrd.flg_tenido=false
  WHERE COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=pc.lote_id),0) > 0
    AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im       -- PRISTINE only: no prior
                    JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id   -- egress / restock / production —
                      AND t.codigo IN ('PROD_CONSUMO','SERV_EGR','VENTA_EGR','SERV_DEV_ING','PROD_ING')  -- excludes patch-57 rolls
                    WHERE im.lote_id=pc.lote_id)
  GROUP BY pc.partida_id),
-- PRIMARY venta per partida = lowest-id live venta (its lowest line). MULTI-line/venta
-- partidas qualify (Phase 1 already handled the single-line ones → now has_output).
primary_venta AS (SELECT DISTINCT ON (vd.partida_id) vd.partida_id, vd.venta_id, vd.id AS venta_detalle_id
  FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false
  WHERE vd.partida_id IN (SELECT partida_id FROM in_scope)
  ORDER BY vd.partida_id, vd.venta_id, vd.id),
p1 AS (
  SELECT s.partida_id, d.dispatched, u.raw_rolls
  FROM in_scope s
  JOIN compactado c ON c.partida_id=s.partida_id
  JOIN demand d ON d.partida_id=s.partida_id
  JOIN supply u ON u.partida_id=s.partida_id
  JOIN primary_venta pv ON pv.partida_id=s.partida_id
  WHERE u.raw_rolls >= d.dispatched)
SELECT
  (SELECT count(*) FROM p1)                                              AS partidas_expect_411,
  (SELECT COALESCE(sum(dispatched),0) FROM p1)                          AS rebuild_rolls_expect_6839,
  (SELECT COALESCE(sum(raw_rolls),0) FROM p1)                           AS eligible_supply_expect_7622,
  -- transparency: how many are genuinely multi-venta (the deferred-precision ones)
  (SELECT count(*) FROM p1 WHERE (SELECT count(DISTINCT vd.venta_id) FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id
     WHERE vd.partida_id=p1.partida_id AND v.flg_elm=false) > 1)        AS multi_venta_partidas_info,
  -- tercero present for the outbound entrega header
  (SELECT count(*) FROM p1 JOIN mes.partida p ON p.id=p1.partida_id WHERE p.tercero_id IS NULL) AS no_tercero_expect_0,
  -- movement-awareness: any p1 partida already has a dispatch egress? (expect 0)
  (SELECT count(DISTINCT pc.partida_id) FROM mes.partida_componente pc JOIN p1 ON p1.partida_id=pc.partida_id
     JOIN inventario.item_movimientos im ON im.lote_id=pc.lote_id
     JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo IN ('SERV_EGR','VENTA_EGR')) AS partidas_with_existing_dispatch_expect_0;


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
    v_n_rolls int := 0;  v_n_children int := 0;  v_n_entregas int := 0;
BEGIN
    SELECT id INTO v_consumo_tid FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO';
    SELECT id INTO v_ing_tid     FROM inventario.item_movimiento_tipo WHERE codigo='PROD_ING';
    SELECT id INTO v_egr_tid     FROM inventario.item_movimiento_tipo WHERE codigo='SERV_EGR';
    SELECT id INTO v_venta_tid   FROM inventario.item_movimiento_tipo WHERE codigo='VENTA_EGR';

    --------------------------------------------------------------------------
    -- Scope: the Phase-1b partidas + their PRIMARY venta line, anchor ejec,
    -- tercero, and dispatch date.
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _p1 ON COMMIT DROP AS
    WITH
    despacho_p AS (SELECT DISTINCT partida_id FROM public.despacho WHERE flg_elm IS NOT TRUE AND partida_id IS NOT NULL),
    has_output AS (SELECT DISTINCT pp.partida_id FROM inventario.lote l
      JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
      JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id),
    live_p AS (SELECT partida_id FROM (
        SELECT pp.partida_id FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id
          WHERE ppe.fyh_inicio > v_cutoff OR ppe.fyh_cre > v_cutoff
        UNION SELECT ch.partida_origen_id FROM mes.partida ch WHERE ch.partida_origen_id IS NOT NULL AND ch.fyh_cre > v_cutoff
        UNION SELECT pc.partida_id FROM mes.partida_componente pc JOIN inventario.pesaje pz ON pz.lote_id=pc.lote_id WHERE pz.fyh_cre > v_cutoff
      ) u WHERE partida_id IS NOT NULL),
    in_scope AS (SELECT d.partida_id FROM despacho_p d
      WHERE d.partida_id NOT IN (SELECT partida_id FROM has_output) AND d.partida_id NOT IN (SELECT partida_id FROM live_p)),
    compactado AS (SELECT pp.partida_id, MIN(ppe.id) AS anchor_ejec_id
      FROM mes.partida_paso pp JOIN mes.operacion o ON o.id=pp.operacion_id AND o.codigo='COMPACTADO'
      JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id GROUP BY pp.partida_id),
    demand AS (SELECT partida_id, SUM(COALESCE(rollos_total,0)) AS dispatched, MIN(fecha_despacho) AS fecha
      FROM public.despacho WHERE flg_elm IS NOT TRUE GROUP BY partida_id),
    supply AS (SELECT pc.partida_id, count(*) AS raw_rolls
      FROM mes.partida_componente pc JOIN in_scope s ON s.partida_id=pc.partida_id
      JOIN inventario.lote l ON l.id=pc.lote_id
      JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=pc.lote_id AND lrd.flg_tenido=false
      WHERE COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=pc.lote_id),0) > 0
        AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im   -- PRISTINE only (see §0):
                        JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id
                          AND t.codigo IN ('PROD_CONSUMO','SERV_EGR','VENTA_EGR','SERV_DEV_ING','PROD_ING')
                        WHERE im.lote_id=pc.lote_id)
      GROUP BY pc.partida_id),
    -- PRIMARY venta per partida = lowest-id live venta + its lowest line (ledger-first)
    primary_venta AS (SELECT DISTINCT ON (vd.partida_id) vd.partida_id, vd.venta_id, vd.id AS venta_detalle_id
      FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false
      WHERE vd.partida_id IN (SELECT partida_id FROM in_scope)
      ORDER BY vd.partida_id, vd.venta_id, vd.id)
    SELECT s.partida_id, d.dispatched, (d.fecha)::timestamptz AS fecha_hora,
           c.anchor_ejec_id, pv.venta_id, pv.venta_detalle_id,
           p.tercero_id, p.ancho, p.malla, p.rendimiento, p.color_x_cliente_id, p.tenido_id, p.flg_antipilling
    FROM in_scope s
    JOIN compactado c ON c.partida_id=s.partida_id
    JOIN demand d ON d.partida_id=s.partida_id
    JOIN supply u ON u.partida_id=s.partida_id AND u.raw_rolls >= d.dispatched
    JOIN primary_venta pv ON pv.partida_id=s.partida_id
    JOIN mes.partida p ON p.id=s.partida_id;

    --------------------------------------------------------------------------
    -- The rolls to rebuild: the FIRST `dispatched` eligible raw rolls per
    -- partida (ordered by lote_id), with each roll's current stock ubicacion.
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _roll ON COMMIT DROP AS
    WITH elig AS (
      SELECT pc.partida_id, pc.lote_id, l.item_id, l.cantidad AS peso, l.propietario_id,
             lrd.entrega_id AS ingress_entrega_id,
             (SELECT ls.ubicacion_id FROM inventario.lote_saldo ls
              WHERE ls.lote_id=pc.lote_id AND ls.cantidad_actual>0 ORDER BY ls.ubicacion_id LIMIT 1) AS ubic_id
      FROM mes.partida_componente pc
      JOIN _p1 x ON x.partida_id=pc.partida_id
      JOIN inventario.lote l ON l.id=pc.lote_id
      JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=pc.lote_id AND lrd.flg_tenido=false
      WHERE COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=pc.lote_id),0) > 0
        AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im   -- PRISTINE only (see §0):
                        JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id
                          AND t.codigo IN ('PROD_CONSUMO','SERV_EGR','VENTA_EGR','SERV_DEV_ING','PROD_ING')
                        WHERE im.lote_id=pc.lote_id)),
    ranked AS (
      SELECT e.*, row_number() OVER (PARTITION BY e.partida_id ORDER BY e.lote_id) AS rn
      FROM elig e)
    SELECT r.partida_id, r.lote_id AS raw_lote_id, r.item_id, r.peso, r.propietario_id,
           r.ingress_entrega_id, r.ubic_id,
           x.anchor_ejec_id, x.fecha_hora, x.venta_id, x.venta_detalle_id, x.tercero_id,
           x.ancho, x.malla, x.rendimiento, x.color_x_cliente_id, x.tenido_id, x.flg_antipilling
    FROM ranked r JOIN _p1 x ON x.partida_id=r.partida_id
    WHERE r.rn <= x.dispatched;

    -- guards: exactly 6,839 rolls, each raw roll once, each with a ubicacion
    IF (SELECT count(*) FROM _roll) <> 6839
       OR (SELECT count(*) FROM _roll WHERE ubic_id IS NULL) <> 0
       OR (SELECT count(*) FROM (SELECT raw_lote_id FROM _roll GROUP BY raw_lote_id HAVING count(*)>1) z) <> 0 THEN
        RAISE EXCEPTION 'scope mismatch: n=%, no_ubic=%, dup_raw=%',
            (SELECT count(*) FROM _roll),
            (SELECT count(*) FROM _roll WHERE ubic_id IS NULL),
            (SELECT count(*) FROM (SELECT raw_lote_id FROM _roll GROUP BY raw_lote_id HAVING count(*)>1) z);
    END IF;

    -- one production doc_movimiento_id per partida (shared by its PROD_CONSUMO + PROD_ING)
    ALTER TABLE _roll ADD COLUMN prod_doc_mov_id bigint;
    UPDATE _roll SET prod_doc_mov_id = d.doc_id
    FROM (SELECT partida_id, nextval('inventario.mov_doc_seq') AS doc_id
          FROM (SELECT DISTINCT partida_id FROM _roll) p) d
    WHERE _roll.partida_id = d.partida_id;

    --------------------------------------------------------------------------
    -- STEP 1 · PROD_CONSUMO on the in-stock raw roll (egress; origen set → saldo
    --   trigger nets the raw roll to 0 at its own ubicacion). documento=anchor ejec.
    --------------------------------------------------------------------------
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT prod_doc_mov_id, item_id, raw_lote_id, v_consumo_tid, ubic_id, NULL, peso,
           fecha_hora, 'partida_paso_ejecucion', anchor_ejec_id, 4, fecha_hora
    FROM _roll;

    --------------------------------------------------------------------------
    -- STEP 2 · create the dyed child lote + lote_rollo_detalle (one per raw roll,
    --   capturing the raw→child id map). estado_calidad=APROBADO (dispatched).
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _map(raw_lote_id int PRIMARY KEY, new_lote_id int) ON COMMIT DROP;
    DECLARE r record; v_id int;
    BEGIN
        FOR r IN SELECT * FROM _roll ORDER BY raw_lote_id LOOP
            INSERT INTO inventario.lote(item_id, documento_tipo, documento_id, cantidad,
                                        estado_calidad, propietario_id, usr_cre, fyh_cre)
            VALUES (r.item_id, 'partida_paso_ejecucion', r.anchor_ejec_id, r.peso,
                    'APROBADO', r.propietario_id, 4, r.fecha_hora)
            RETURNING id INTO v_id;

            INSERT INTO _map(raw_lote_id, new_lote_id) VALUES (r.raw_lote_id, v_id);

            INSERT INTO inventario.lote_rollo_detalle(
                lote_id, entrega_id, origen_lote_id, ancho, malla, rendimiento,
                color_x_cliente_id, tenido_id, flg_tenido, flg_antipilling, usr_cre, fyh_cre)
            VALUES (v_id, r.ingress_entrega_id, r.raw_lote_id, r.ancho, r.malla, r.rendimiento,
                    r.color_x_cliente_id, r.tenido_id, true, r.flg_antipilling, 4, r.fecha_hora);
        END LOOP;
    END;

    --------------------------------------------------------------------------
    -- STEP 3 · PROD_ING on the dyed child (ingress; destino = same ubicacion)
    --------------------------------------------------------------------------
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT rr.prod_doc_mov_id, rr.item_id, m.new_lote_id, v_ing_tid, NULL, rr.ubic_id, rr.peso,
           rr.fecha_hora, 'partida_paso_ejecucion', rr.anchor_ejec_id, 4, rr.fecha_hora
    FROM _map m JOIN _roll rr ON rr.raw_lote_id=m.raw_lote_id;

    --------------------------------------------------------------------------
    -- STEP 4 · outbound entrega — ONE per partida, linked to the PRIMARY venta.
    --   tipo by propietario (1 → VENTA_EGRESO else DESPACHO_CLIENTE); a partida's
    --   rolls share a propietario (verified homogeneous), so one tipo per partida.
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _ent(partida_id bigint PRIMARY KEY, entrega_id bigint,
                           is_venta boolean, doc_mov_id bigint) ON COMMIT DROP;

    DECLARE g record; v_tipo_id smallint; v_eid bigint;
    BEGIN
        FOR g IN
            SELECT rr.partida_id, x.tercero_id, x.venta_id, x.fecha_hora,
                   bool_or(rr.propietario_id = 1) AS is_venta
            FROM _roll rr JOIN _p1 x ON x.partida_id=rr.partida_id
            GROUP BY rr.partida_id, x.tercero_id, x.venta_id, x.fecha_hora
        LOOP
            SELECT id INTO v_tipo_id FROM doc.entrega_tipo
              WHERE codigo = CASE WHEN g.is_venta THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END;
            INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, venta_id, serie, correlativo,
                                    fecha_emision, usr_cre, fyh_cre)
            VALUES (v_tipo_id, g.tercero_id, g.venta_id, NULL, NULL, g.fecha_hora, 4, g.fecha_hora)
            RETURNING id INTO v_eid;
            INSERT INTO _ent(partida_id, entrega_id, is_venta, doc_mov_id)
            VALUES (g.partida_id, v_eid, g.is_venta, nextval('inventario.mov_doc_seq'));
        END LOOP;
    END;

    --------------------------------------------------------------------------
    -- STEP 5 · entrega_detalle (one line per dyed roll; venta_detalle_id = the
    --   partida's PRIMARY billing line) + the dyed-child egress movement.
    --------------------------------------------------------------------------
    INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, lote_id, cantidad, n_rollos, venta_detalle_id)
    SELECT e.entrega_id,
           (row_number() OVER (PARTITION BY e.entrega_id ORDER BY m.new_lote_id))::smallint,
           rr.item_id, m.new_lote_id, rr.peso, 1, rr.venta_detalle_id
    FROM _map m
    JOIN _roll rr ON rr.raw_lote_id=m.raw_lote_id
    JOIN _ent e ON e.partida_id=rr.partida_id;

    -- egress on the dyed child (origen set → nets child to 0); documento='entrega'
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT e.doc_mov_id, rr.item_id, m.new_lote_id,
           CASE WHEN e.is_venta THEN v_venta_tid ELSE v_egr_tid END,
           rr.ubic_id, NULL, rr.peso, rr.fecha_hora, 'entrega', e.entrega_id, 4, rr.fecha_hora
    FROM _map m
    JOIN _roll rr ON rr.raw_lote_id=m.raw_lote_id
    JOIN _ent e ON e.partida_id=rr.partida_id;

    --------------------------------------------------------------------------
    -- STEP 6 · saldo — the sync trigger already netted raw (consumed) and dyed
    --   (produced→dispatched) to 0 at their ubicacion. Drop the resulting 0-rows.
    --------------------------------------------------------------------------
    DELETE FROM inventario.lote_saldo ls USING _roll rr
      WHERE ls.lote_id=rr.raw_lote_id AND ls.cantidad_actual = 0;
    DELETE FROM inventario.lote_saldo ls USING _map m
      WHERE ls.lote_id=m.new_lote_id AND ls.cantidad_actual = 0;

    SELECT count(*) INTO v_n_rolls    FROM _roll;
    SELECT count(*) INTO v_n_children FROM _map;
    SELECT count(*) INTO v_n_entregas FROM _ent;
    RAISE NOTICE 'Track B Phase 1b: % raw consumed, % dyed children, % venta-linked entregas.',
        v_n_rolls, v_n_children, v_n_entregas;
END $$;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify  (run BEFORE COMMIT — references this run's temp tables)
-- ══════════════════════════════════════════════════════════════════════════════
-- (a) every raw roll consumed, a dyed child exists, no raw roll left in stock
SELECT
    (SELECT count(*) FROM _roll)                                                       AS raw_touched_expect_6839,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id=r.raw_lote_id AND c.flg_tenido=true))                   AS raw_with_dyed_child,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_CONSUMO'
        WHERE im.lote_id=r.raw_lote_id AND im.documento_tipo='partida_paso_ejecucion')) AS raw_consumed,
    (SELECT count(*) FROM _roll r WHERE COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=r.raw_lote_id),0) <> 0) AS raw_still_in_stock_expect_0;

-- (b) raw parent AND dyed child each net to 0 (double-entry intact). Expect all 6839.
SELECT
    COUNT(*)                                                          AS pairs_expect_6839,
    COUNT(*) FILTER (WHERE dyed_net = 0)                              AS dyed_net0,
    COUNT(*) FILTER (WHERE raw_net  = 0)                              AS raw_net0
FROM (
    SELECT m.new_lote_id, m.raw_lote_id,
        (SELECT COALESCE(SUM(imt.factor*im.cantidad),0) FROM inventario.item_movimientos im
         JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id WHERE im.lote_id=m.new_lote_id) AS dyed_net,
        (SELECT COALESCE(SUM(imt.factor*im.cantidad),0) FROM inventario.item_movimientos im
         JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id WHERE im.lote_id=m.raw_lote_id)  AS raw_net
    FROM _map m
) x;

-- (c) venta-linked outbound entregas + detalle lines == dispatched children (6839),
--     every entrega carries a venta_id, every detalle line a venta_detalle_id.
SELECT
    (SELECT count(*) FROM _ent)                                                              AS entregas_expect_411,
    (SELECT count(*) FROM _ent WHERE entrega_id IN (SELECT id FROM doc.entrega WHERE venta_id IS NULL)) AS entregas_without_venta_expect_0,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)) AS detalle_lines_expect_6839,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)
        AND ed.venta_detalle_id IS NULL)                                                    AS lines_without_venta_detalle_expect_0,
    (SELECT count(*) FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
        WHERE im.documento_tipo='entrega' AND im.documento_id IN (SELECT entrega_id FROM _ent)) AS dyed_egress_moves_expect_6839;

-- (d) no nonzero lote_saldo for any raw or dyed roll we touched. Expect 0.
SELECT COUNT(*) AS nonzero_saldo_expect_0
FROM inventario.lote_saldo ls
WHERE ls.cantidad_actual <> 0
  AND (ls.lote_id IN (SELECT raw_lote_id FROM _roll) OR ls.lote_id IN (SELECT new_lote_id FROM _map));

-- (e) NO new egress-without-ingress anywhere for the dyed children (each has PROD_ING).
SELECT COUNT(*) AS dyed_missing_ingress_expect_0
FROM _map m
WHERE NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_ING'
    WHERE im.lote_id=m.new_lote_id);

-- COMMIT;    -- ← after §2: (a) 6839/6839/6839/0, (b) 6839/6839/6839, (c) 411/0/6839/0/6839, (d)=0, (e)=0
-- ROLLBACK;  -- ← if anything is off

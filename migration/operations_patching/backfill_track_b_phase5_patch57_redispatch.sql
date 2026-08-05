-- ============================================================================
-- TRACK B · Phase 5 — patch-57 restocked rolls: clean + dispatch
-- ============================================================================
-- WHAT: 86 partidas / 1,729 crudo rolls that patch-57 restocked. Each carries the
--   EXACT signature `SERV_ING, SERV_EGR(documento='PARTIDA', bogus placeholder),
--   SERV_DEV_ING(patch-57 restock)` and nothing else (audited: uniform, 1 of each,
--   single ubicacion, single saldo row). They are physically dispatched in legacy but
--   have no proper dispatch record. This mirrors the ORIGINAL Track-B mechanic
--   (backfill_track_b_production.sql): DELETE the bogus egress, then rebuild — except
--   here we also delete patch-57's SERV_DEV_ING (the bogus SERV_EGR + its reversal are
--   a net-0 pair that only added noise), returning each roll to a clean SERV_ING state,
--   then consume->dye->dispatch. No bloat left behind.
--
-- SAFE DELETE (audited): all 3 movements share one ubicacion and there is one saldo
--   row per lote, so deleting the (-1 bogus egress, +1 restock) pair leaves lote_saldo
--   unchanged at +cantidad (= SERV_ING alone). No DELETE trigger exists on
--   item_movimientos, so no side effects. Verified: no PROD_CONSUMO / AJUSTE / PESAJE /
--   second egress on any of these lotes; the only post-go-live movement is patch-57's
--   own SERV_DEV_ING (which we delete).
--
-- SCOPE guards: patch-57 restocked (has SERV_DEV_ING) + in stock + partida not-live +
--   has a live venta + partida has an anchor ejec + EXCLUDES the 1 partida (id 338)
--   that already had rolls dispatched by an earlier phase (would double-count). Cap at
--   LEAST(supply, demand): 1,640 dispatched, 89 leftover stay in stock (cleaned).
--
-- Mechanic otherwise identical to backfill_track_b_phase4_last_step_anchor.sql: weight
--   basis B (inherit lote.cantidad), ledger-first primary-venta linkage, anchor = last
--   available ejec (own MAX else rework-child MAX), historical dating, dyed-child
--   genealogy. No venta created, no rolls fabricated.
--
-- ⚠ DRY-RUN §0 (read-only), run §1, read §2, then COMMIT.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════════
-- §0 · DRY RUN — scope + integrity (no writes)
-- ══════════════════════════════════════════════════════════════════════════════
WITH
live_p AS (SELECT partida_id FROM (
    SELECT pp.partida_id FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id WHERE ppe.fyh_inicio > '2026-05-25 15:27:52+00'::timestamptz OR ppe.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz
    UNION SELECT ch.partida_origen_id FROM mes.partida ch WHERE ch.partida_origen_id IS NOT NULL AND ch.fyh_cre > '2026-05-25 15:27:52+00'::timestamptz) u WHERE partida_id IS NOT NULL),
venta AS (SELECT DISTINCT partida_id FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false),
cand AS (SELECT DISTINCT l.id AS lote_id,
    (SELECT pc.partida_id FROM mes.partida_componente pc WHERE pc.lote_id=l.id ORDER BY pc.partida_id LIMIT 1) AS partida_id
  FROM inventario.lote l JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=false
  WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='SERV_DEV_ING' WHERE im.lote_id=l.id)
    AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=l.id),0)>0),
prior AS (SELECT DISTINCT c.partida_id FROM cand c WHERE EXISTS (SELECT 1 FROM inventario.lote l
      JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
      JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
      JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id AND pp.partida_id=c.partida_id
      WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo IN ('SERV_EGR','VENTA_EGR') WHERE im.lote_id=l.id))),
candf AS (SELECT c.* FROM cand c
   WHERE c.partida_id NOT IN (SELECT partida_id FROM live_p)
     AND c.partida_id IN (SELECT partida_id FROM venta)
     AND c.partida_id NOT IN (SELECT partida_id FROM prior)),
supply AS (SELECT partida_id, count(*) AS raw_rolls FROM candf GROUP BY partida_id),
demand AS (SELECT partida_id, SUM(COALESCE(rollos_total,0)) AS dispatched FROM public.despacho WHERE flg_elm IS NOT TRUE GROUP BY partida_id),
own_ejec AS (SELECT pp.partida_id, MAX(ppe.id) AS ejec_id FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id GROUP BY pp.partida_id),
child_ejec AS (SELECT ch.partida_origen_id AS partida_id, MAX(ppe.id) AS ejec_id FROM mes.partida ch JOIN mes.partida_paso pp ON pp.partida_id=ch.id JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id WHERE ch.partida_origen_id IS NOT NULL GROUP BY ch.partida_origen_id)
SELECT
  (SELECT count(*) FROM supply)                                              AS partidas_expect_86,
  (SELECT count(*) FROM candf)                                               AS candidate_rolls_expect_1729,
  (SELECT COALESCE(sum(LEAST(s.raw_rolls,d.dispatched)),0) FROM supply s JOIN demand d ON d.partida_id=s.partida_id) AS dispatch_rolls_expect_1640,
  (SELECT COALESCE(sum(s.raw_rolls)-sum(LEAST(s.raw_rolls,d.dispatched)),0) FROM supply s JOIN demand d ON d.partida_id=s.partida_id) AS leftover_expect_89,
  (SELECT count(*) FROM supply s WHERE s.partida_id NOT IN (SELECT partida_id FROM own_ejec) AND s.partida_id NOT IN (SELECT partida_id FROM child_ejec)) AS no_anchor_expect_0,
  (SELECT count(*) FROM supply s JOIN mes.partida p ON p.id=s.partida_id WHERE p.tercero_id IS NULL) AS no_tercero_expect_0;


-- ══════════════════════════════════════════════════════════════════════════════
-- §1 · Execute
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL statement_timeout = 0;

ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

DO $$
DECLARE
    v_cutoff      timestamptz := '2026-05-25 15:27:52+00';
    v_consumo_tid int;  v_ing_tid int;  v_egr_tid int;  v_venta_tid int;  v_dev_tid int;
    v_n_del int := 0;  v_n_rolls int := 0;  v_n_children int := 0;  v_n_entregas int := 0;
BEGIN
    SELECT id INTO v_consumo_tid FROM inventario.item_movimiento_tipo WHERE codigo='PROD_CONSUMO';
    SELECT id INTO v_ing_tid     FROM inventario.item_movimiento_tipo WHERE codigo='PROD_ING';
    SELECT id INTO v_egr_tid     FROM inventario.item_movimiento_tipo WHERE codigo='SERV_EGR';
    SELECT id INTO v_venta_tid   FROM inventario.item_movimiento_tipo WHERE codigo='VENTA_EGR';
    SELECT id INTO v_dev_tid      FROM inventario.item_movimiento_tipo WHERE codigo='SERV_DEV_ING';

    --------------------------------------------------------------------------
    -- Scope: partida-level (anchor = last available ejec; primary venta; dispatch
    -- cap = LEAST(supply, demand)).
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _p1 ON COMMIT DROP AS
    WITH
    live_p AS (SELECT partida_id FROM (
        SELECT pp.partida_id FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id WHERE ppe.fyh_inicio > v_cutoff OR ppe.fyh_cre > v_cutoff
        UNION SELECT ch.partida_origen_id FROM mes.partida ch WHERE ch.partida_origen_id IS NOT NULL AND ch.fyh_cre > v_cutoff) u WHERE partida_id IS NOT NULL),
    venta AS (SELECT DISTINCT partida_id FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false),
    cand AS (SELECT DISTINCT l.id AS lote_id,
        (SELECT pc.partida_id FROM mes.partida_componente pc WHERE pc.lote_id=l.id ORDER BY pc.partida_id LIMIT 1) AS partida_id
      FROM inventario.lote l JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=false
      WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='SERV_DEV_ING' WHERE im.lote_id=l.id)
        AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=l.id),0)>0),
    prior AS (SELECT DISTINCT c.partida_id FROM cand c WHERE EXISTS (SELECT 1 FROM inventario.lote l
          JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
          JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
          JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id AND pp.partida_id=c.partida_id
          WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo IN ('SERV_EGR','VENTA_EGR') WHERE im.lote_id=l.id))),
    candf AS (SELECT c.* FROM cand c WHERE c.partida_id NOT IN (SELECT partida_id FROM live_p) AND c.partida_id IN (SELECT partida_id FROM venta) AND c.partida_id NOT IN (SELECT partida_id FROM prior)),
    supply AS (SELECT partida_id, count(*) AS raw_rolls FROM candf GROUP BY partida_id),
    demand AS (SELECT partida_id, SUM(COALESCE(rollos_total,0)) AS dispatched, MIN(fecha_despacho) AS fecha FROM public.despacho WHERE flg_elm IS NOT TRUE GROUP BY partida_id),
    own_ejec AS (SELECT pp.partida_id, MAX(ppe.id) AS ejec_id FROM mes.partida_paso pp JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id GROUP BY pp.partida_id),
    child_ejec AS (SELECT ch.partida_origen_id AS partida_id, MAX(ppe.id) AS ejec_id FROM mes.partida ch JOIN mes.partida_paso pp ON pp.partida_id=ch.id JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id=pp.id WHERE ch.partida_origen_id IS NOT NULL GROUP BY ch.partida_origen_id),
    primary_venta AS (SELECT DISTINCT ON (vd.partida_id) vd.partida_id, vd.venta_id, vd.id AS venta_detalle_id
      FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false
      ORDER BY vd.partida_id, vd.venta_id, vd.id)
    SELECT s.partida_id, LEAST(s.raw_rolls, d.dispatched) AS dispatched,
           (d.fecha)::timestamptz AS fecha_hora,
           COALESCE(oe.ejec_id, ce.ejec_id) AS anchor_ejec_id, pv.venta_id, pv.venta_detalle_id,
           p.tercero_id, p.ancho, p.malla, p.rendimiento, p.color_x_cliente_id, p.tenido_id, p.flg_antipilling
    FROM supply s
    JOIN demand d ON d.partida_id=s.partida_id
    JOIN primary_venta pv ON pv.partida_id=s.partida_id
    LEFT JOIN own_ejec oe ON oe.partida_id=s.partida_id
    LEFT JOIN child_ejec ce ON ce.partida_id=s.partida_id
    JOIN mes.partida p ON p.id=s.partida_id;

    --------------------------------------------------------------------------
    -- All candidate rolls of the scope partidas (for the DELETE + the pool).
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _cand ON COMMIT DROP AS
    WITH cand AS (SELECT DISTINCT l.id AS lote_id, l.item_id, l.cantidad AS peso, l.propietario_id,
        (SELECT pc.partida_id FROM mes.partida_componente pc WHERE pc.lote_id=l.id ORDER BY pc.partida_id LIMIT 1) AS partida_id,
        (SELECT lrd.entrega_id FROM inventario.lote_rollo_detalle lrd WHERE lrd.lote_id=l.id) AS ingress_entrega_id,
        (SELECT ls.ubicacion_id FROM inventario.lote_saldo ls WHERE ls.lote_id=l.id AND ls.cantidad_actual>0 ORDER BY ls.ubicacion_id LIMIT 1) AS ubic_id
      FROM inventario.lote l JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=false
      WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='SERV_DEV_ING' WHERE im.lote_id=l.id)
        AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=l.id),0)>0)
    SELECT c.*, row_number() OVER (PARTITION BY c.partida_id ORDER BY c.lote_id) AS rn
    FROM cand c JOIN _p1 x ON x.partida_id=c.partida_id;

    -- guard: candidate count matches scope
    IF (SELECT count(*) FROM _cand) <> 1729 OR (SELECT count(*) FROM _cand WHERE ubic_id IS NULL) <> 0 THEN
        RAISE EXCEPTION 'candidate mismatch: n=%, no_ubic=%',
            (SELECT count(*) FROM _cand), (SELECT count(*) FROM _cand WHERE ubic_id IS NULL);
    END IF;

    --------------------------------------------------------------------------
    -- STEP 0 · DELETE the bogus SERV_EGR (documento='PARTIDA') + patch-57 SERV_DEV_ING
    --   for ALL candidate rolls → returns each to a clean SERV_ING-only state.
    --   Safe: single ubicacion + single saldo row (audited) → lote_saldo stays correct.
    --------------------------------------------------------------------------
    DELETE FROM inventario.item_movimientos im USING _cand c
    WHERE im.lote_id = c.lote_id
      AND ( (im.item_movimiento_tipo_id = v_egr_tid AND im.documento_tipo = 'PARTIDA')
         OR (im.item_movimiento_tipo_id = v_dev_tid) );
    GET DIAGNOSTICS v_n_del = ROW_COUNT;

    --------------------------------------------------------------------------
    -- The rolls to dispatch: FIRST `dispatched` (=LEAST(supply,demand)) candidates.
    --------------------------------------------------------------------------
    CREATE TEMP TABLE _roll ON COMMIT DROP AS
    SELECT c.partida_id, c.lote_id AS raw_lote_id, c.item_id, c.peso, c.propietario_id,
           c.ingress_entrega_id, c.ubic_id,
           x.anchor_ejec_id, x.fecha_hora, x.venta_id, x.venta_detalle_id, x.tercero_id,
           x.ancho, x.malla, x.rendimiento, x.color_x_cliente_id, x.tenido_id, x.flg_antipilling
    FROM _cand c JOIN _p1 x ON x.partida_id=c.partida_id
    WHERE c.rn <= x.dispatched;

    IF (SELECT count(*) FROM _roll) <> 1640
       OR (SELECT count(*) FROM _roll WHERE anchor_ejec_id IS NULL) <> 0
       OR (SELECT count(*) FROM (SELECT raw_lote_id FROM _roll GROUP BY raw_lote_id HAVING count(*)>1) z) <> 0 THEN
        RAISE EXCEPTION 'roll mismatch: n=%, no_anchor=%, dup=%',
            (SELECT count(*) FROM _roll),
            (SELECT count(*) FROM _roll WHERE anchor_ejec_id IS NULL),
            (SELECT count(*) FROM (SELECT raw_lote_id FROM _roll GROUP BY raw_lote_id HAVING count(*)>1) z);
    END IF;

    ALTER TABLE _roll ADD COLUMN prod_doc_mov_id bigint;
    UPDATE _roll SET prod_doc_mov_id = d.doc_id
    FROM (SELECT partida_id, nextval('inventario.mov_doc_seq') AS doc_id FROM (SELECT DISTINCT partida_id FROM _roll) p) d
    WHERE _roll.partida_id = d.partida_id;

    -- STEP 1 · PROD_CONSUMO on the (now clean) raw roll
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT prod_doc_mov_id, item_id, raw_lote_id, v_consumo_tid, ubic_id, NULL, peso,
           fecha_hora, 'partida_paso_ejecucion', anchor_ejec_id, 4, fecha_hora
    FROM _roll;

    -- STEP 2 · dyed child lote + lote_rollo_detalle
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

    -- STEP 3 · PROD_ING on the dyed child
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT rr.prod_doc_mov_id, rr.item_id, m.new_lote_id, v_ing_tid, NULL, rr.ubic_id, rr.peso,
           rr.fecha_hora, 'partida_paso_ejecucion', rr.anchor_ejec_id, 4, rr.fecha_hora
    FROM _map m JOIN _roll rr ON rr.raw_lote_id=m.raw_lote_id;

    -- STEP 4 · outbound entrega — ONE per partida, linked to PRIMARY venta
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

    -- STEP 5 · entrega_detalle + dyed-child egress
    INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, lote_id, cantidad, n_rollos, venta_detalle_id)
    SELECT e.entrega_id,
           (row_number() OVER (PARTITION BY e.entrega_id ORDER BY m.new_lote_id))::smallint,
           rr.item_id, m.new_lote_id, rr.peso, 1, rr.venta_detalle_id
    FROM _map m JOIN _roll rr ON rr.raw_lote_id=m.raw_lote_id JOIN _ent e ON e.partida_id=rr.partida_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad,
        fecha_hora, documento_tipo, documento_id, usr_cre, fyh_cre)
    SELECT e.doc_mov_id, rr.item_id, m.new_lote_id,
           CASE WHEN e.is_venta THEN v_venta_tid ELSE v_egr_tid END,
           rr.ubic_id, NULL, rr.peso, rr.fecha_hora, 'entrega', e.entrega_id, 4, rr.fecha_hora
    FROM _map m JOIN _roll rr ON rr.raw_lote_id=m.raw_lote_id JOIN _ent e ON e.partida_id=rr.partida_id;

    -- STEP 6 · drop resulting zero lote_saldo rows (dispatched raw + dyed net to 0;
    --   the 89 leftover keep their +cantidad SERV_ING row — clean in stock).
    DELETE FROM inventario.lote_saldo ls USING _roll rr WHERE ls.lote_id=rr.raw_lote_id AND ls.cantidad_actual = 0;
    DELETE FROM inventario.lote_saldo ls USING _map m   WHERE ls.lote_id=m.new_lote_id AND ls.cantidad_actual = 0;

    SELECT count(*) INTO v_n_rolls FROM _roll;
    SELECT count(*) INTO v_n_children FROM _map;
    SELECT count(*) INTO v_n_entregas FROM _ent;
    RAISE NOTICE 'Track B Phase 5: % bogus movements deleted, % rolls dispatched, % dyed children, % entregas.',
        v_n_del, v_n_rolls, v_n_children, v_n_entregas;
END $$;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify  (run BEFORE COMMIT — references this run's temp tables)
-- ══════════════════════════════════════════════════════════════════════════════
-- (a) dispatched raw rolls consumed, dyed child exists, no bogus egress left, net 0
SELECT
    (SELECT count(*) FROM _roll)                                                       AS raw_touched_expect_1640,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id=r.raw_lote_id AND c.flg_tenido=true)) AS raw_with_dyed_child,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_CONSUMO' WHERE im.lote_id=r.raw_lote_id)) AS raw_consumed,
    (SELECT count(*) FROM _cand c WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im WHERE im.lote_id=c.lote_id AND im.documento_tipo='PARTIDA')) AS bogus_partida_egr_left_expect_0;

-- (b) every dispatched raw + its dyed child net to 0
SELECT
    COUNT(*)                                                          AS pairs_expect_1640,
    COUNT(*) FILTER (WHERE dyed_net = 0)                              AS dyed_net0,
    COUNT(*) FILTER (WHERE raw_net  = 0)                              AS raw_net0
FROM (
    SELECT m.new_lote_id, m.raw_lote_id,
        (SELECT COALESCE(SUM(imt.factor*im.cantidad),0) FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id WHERE im.lote_id=m.new_lote_id) AS dyed_net,
        (SELECT COALESCE(SUM(imt.factor*im.cantidad),0) FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id WHERE im.lote_id=m.raw_lote_id)  AS raw_net
    FROM _map m
) x;

-- (c) leftover 89 are clean in stock: SERV_ING only, saldo>0
SELECT
    (SELECT count(*) FROM _cand c WHERE c.lote_id NOT IN (SELECT raw_lote_id FROM _roll)) AS leftover_expect_89,
    (SELECT count(*) FROM _cand c WHERE c.lote_id NOT IN (SELECT raw_lote_id FROM _roll)
        AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=c.lote_id),0) <= 0) AS leftover_not_in_stock_expect_0,
    (SELECT count(*) FROM _cand c WHERE c.lote_id NOT IN (SELECT raw_lote_id FROM _roll)
        AND EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo IN ('SERV_EGR','SERV_DEV_ING') WHERE im.lote_id=c.lote_id)) AS leftover_not_clean_expect_0;

-- (d) entregas venta-linked, detalle lines == dispatched (1640)
SELECT
    (SELECT count(*) FROM _ent)                                                              AS entregas_expect_86,
    (SELECT count(*) FROM _ent WHERE entrega_id IN (SELECT id FROM doc.entrega WHERE venta_id IS NULL)) AS entregas_without_venta_expect_0,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)) AS detalle_lines_expect_1640,
    (SELECT count(*) FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR') WHERE im.documento_tipo='entrega' AND im.documento_id IN (SELECT entrega_id FROM _ent)) AS dyed_egress_moves_expect_1640;

-- (e) no nonzero saldo for dispatched raw / dyed; dyed all have PROD_ING
SELECT
  (SELECT COUNT(*) FROM inventario.lote_saldo ls WHERE ls.cantidad_actual <> 0 AND (ls.lote_id IN (SELECT raw_lote_id FROM _roll) OR ls.lote_id IN (SELECT new_lote_id FROM _map))) AS nonzero_saldo_expect_0,
  (SELECT COUNT(*) FROM _map m WHERE NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_ING' WHERE im.lote_id=m.new_lote_id)) AS dyed_missing_ingress_expect_0;

-- COMMIT;    -- ← after §2: (a) 1640/1640/1640/0, (b) 1640/1640/1640, (c) 89/0/0, (d) 86/0/1640/1640, (e) 0/0
-- ROLLBACK;  -- ← if anything is off

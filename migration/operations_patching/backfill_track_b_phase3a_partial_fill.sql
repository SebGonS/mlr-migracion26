-- ============================================================================
-- TRACK B · Phase 3a — PARTIAL-FILL of shortfall partidas (supply < demand)
-- ============================================================================
-- WHAT: 56 legacy partidas that Phase 1/1b SKIPPED because their pristine supply is
--   LESS than the legacy dispatched count (the all-or-nothing `supply >= demand` gate
--   dropped them whole). But their real, in-stock, pristine rolls ARE dispatchable —
--   we just left them un-recorded alongside the over-count. This backfills those
--   **1,024 real rolls** (consume→dye→dispatch, exactly like Phase 1/1b) and simply
--   **FLAGS the 550-roll excess** (demand − supply) — it does NOT create it.
--
-- WHY THIS IS SAFE (no fabrication): every roll here is a real pristine componente
--   roll in stock (verified: partida_componente == legacy partida.cantidad for 454/464
--   in-scope partidas — componente IS the legacy roll set). We dispatch min(supply,
--   demand) = ALL of supply, and stop. The excess is genuine legacy OVER-DISPATCH
--   (demand 1,574 > supply 1,024; and total in-scope demand 9,188 > legacy cantidad
--   8,870) — return-redispatch with no physical roll to source. It is left UNBACKFILLED
--   and flagged; fabricating it would inflate inventory that never existed.
--   (The tiny set of genuinely-missing legacy-attested rolls — componente < cantidad,
--   ~16 rolls / ~9 partidas — is handled SEPARATELY in Phase 3b, which materialises
--   output from nothing; that fabrication is kept isolated and reviewed on its own.)
--
-- Mechanic, weight basis, PRISTINE double-egress guard, ledger-first primary-venta
-- linkage, historical dating, movement-awareness — ALL identical to
-- backfill_track_b_phase1b_multi_venta.sql. The ONLY difference is the scope gate:
--   `supply < demand` (shortfall) instead of `supply >= demand`, and we dispatch the
--   full available supply (each partida's pristine rolls; the `rn <= dispatched` cap
--   is a no-op here since supply < demand).
--
-- Billing consequence (expected, truthful): for these 56 partidas the venta bills
--   1,574 rolls but the ledger records 1,024 — billed over-count, NOT a ledger error.
--
-- WRITES: item_movimientos (PROD_CONSUMO/PROD_ING/dyed egress), lote +
--   lote_rollo_detalle, entrega + entrega_detalle (linked to EXISTING venta). No venta
--   created. No rolls fabricated.
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
    AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im       -- PRISTINE only
                    JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id
                      AND t.codigo IN ('PROD_CONSUMO','SERV_EGR','VENTA_EGR','SERV_DEV_ING','PROD_ING')
                    WHERE im.lote_id=pc.lote_id)
  GROUP BY pc.partida_id),
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
  WHERE u.raw_rolls < d.dispatched)     -- SHORTFALL gate (supply>0 implicit via supply CTE)
SELECT
  (SELECT count(*) FROM p1)                                              AS partidas_expect_56,
  (SELECT COALESCE(sum(raw_rolls),0) FROM p1)                           AS rolls_to_backfill_expect_1024,
  (SELECT COALESCE(sum(dispatched),0) FROM p1)                          AS demand_billed_expect_1574,
  (SELECT COALESCE(sum(dispatched - raw_rolls),0) FROM p1)              AS excess_flagged_not_created_expect_550,
  -- tercero + movement-awareness guards
  (SELECT count(*) FROM p1 JOIN mes.partida p ON p.id=p1.partida_id WHERE p.tercero_id IS NULL) AS no_tercero_expect_0,
  (SELECT count(DISTINCT pc.partida_id) FROM mes.partida_componente pc JOIN p1 ON p1.partida_id=pc.partida_id
     JOIN inventario.item_movimientos im ON im.lote_id=pc.lote_id
     JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo IN ('SERV_EGR','VENTA_EGR')) AS partidas_with_existing_dispatch_expect_0;


-- ══════════════════════════════════════════════════════════════════════════════
-- §1 · Execute
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL statement_timeout = 0;

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
    -- Scope: shortfall partidas + PRIMARY venta line, anchor ejec, tercero, date.
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
        AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                        JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id
                          AND t.codigo IN ('PROD_CONSUMO','SERV_EGR','VENTA_EGR','SERV_DEV_ING','PROD_ING')
                        WHERE im.lote_id=pc.lote_id)
      GROUP BY pc.partida_id),
    primary_venta AS (SELECT DISTINCT ON (vd.partida_id) vd.partida_id, vd.venta_id, vd.id AS venta_detalle_id
      FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false
      WHERE vd.partida_id IN (SELECT partida_id FROM in_scope)
      ORDER BY vd.partida_id, vd.venta_id, vd.id)
    SELECT s.partida_id, u.raw_rolls AS dispatched,   -- dispatch ALL supply (< demand)
           (d.fecha)::timestamptz AS fecha_hora,
           c.anchor_ejec_id, pv.venta_id, pv.venta_detalle_id,
           p.tercero_id, p.ancho, p.malla, p.rendimiento, p.color_x_cliente_id, p.tenido_id, p.flg_antipilling
    FROM in_scope s
    JOIN compactado c ON c.partida_id=s.partida_id
    JOIN demand d ON d.partida_id=s.partida_id
    JOIN supply u ON u.partida_id=s.partida_id AND u.raw_rolls < d.dispatched
    JOIN primary_venta pv ON pv.partida_id=s.partida_id
    JOIN mes.partida p ON p.id=s.partida_id;

    --------------------------------------------------------------------------
    -- The rolls to rebuild: ALL pristine raw rolls of each shortfall partida
    -- (ordered by lote_id; `rn <= dispatched` = all, since we set dispatched=supply).
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
        AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
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

    -- guards: exactly 1,024 rolls, each raw roll once, each with a ubicacion
    IF (SELECT count(*) FROM _roll) <> 1024
       OR (SELECT count(*) FROM _roll WHERE ubic_id IS NULL) <> 0
       OR (SELECT count(*) FROM (SELECT raw_lote_id FROM _roll GROUP BY raw_lote_id HAVING count(*)>1) z) <> 0 THEN
        RAISE EXCEPTION 'scope mismatch: n=%, no_ubic=%, dup_raw=%',
            (SELECT count(*) FROM _roll),
            (SELECT count(*) FROM _roll WHERE ubic_id IS NULL),
            (SELECT count(*) FROM (SELECT raw_lote_id FROM _roll GROUP BY raw_lote_id HAVING count(*)>1) z);
    END IF;

    ALTER TABLE _roll ADD COLUMN prod_doc_mov_id bigint;
    UPDATE _roll SET prod_doc_mov_id = d.doc_id
    FROM (SELECT partida_id, nextval('inventario.mov_doc_seq') AS doc_id
          FROM (SELECT DISTINCT partida_id FROM _roll) p) d
    WHERE _roll.partida_id = d.partida_id;

    -- STEP 1 · PROD_CONSUMO on the in-stock raw roll
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

    -- STEP 6 · drop resulting zero lote_saldo rows
    DELETE FROM inventario.lote_saldo ls USING _roll rr WHERE ls.lote_id=rr.raw_lote_id AND ls.cantidad_actual = 0;
    DELETE FROM inventario.lote_saldo ls USING _map m   WHERE ls.lote_id=m.new_lote_id AND ls.cantidad_actual = 0;

    SELECT count(*) INTO v_n_rolls FROM _roll;
    SELECT count(*) INTO v_n_children FROM _map;
    SELECT count(*) INTO v_n_entregas FROM _ent;
    RAISE NOTICE 'Track B Phase 3a: % raw consumed, % dyed children, % venta-linked entregas.',
        v_n_rolls, v_n_children, v_n_entregas;
END $$;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify  (run BEFORE COMMIT — references this run's temp tables)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT
    (SELECT count(*) FROM _roll)                                                       AS raw_touched_expect_1024,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id=r.raw_lote_id AND c.flg_tenido=true))                   AS raw_with_dyed_child,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_CONSUMO'
        WHERE im.lote_id=r.raw_lote_id AND im.documento_tipo='partida_paso_ejecucion')) AS raw_consumed,
    (SELECT count(*) FROM _roll r WHERE COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=r.raw_lote_id),0) <> 0) AS raw_still_in_stock_expect_0;

SELECT
    COUNT(*)                                                          AS pairs_expect_1024,
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

SELECT
    (SELECT count(*) FROM _ent)                                                              AS entregas_expect_56,
    (SELECT count(*) FROM _ent WHERE entrega_id IN (SELECT id FROM doc.entrega WHERE venta_id IS NULL)) AS entregas_without_venta_expect_0,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)) AS detalle_lines_expect_1024,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)
        AND ed.venta_detalle_id IS NULL)                                                    AS lines_without_venta_detalle_expect_0,
    (SELECT count(*) FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
        WHERE im.documento_tipo='entrega' AND im.documento_id IN (SELECT entrega_id FROM _ent)) AS dyed_egress_moves_expect_1024;

SELECT COUNT(*) AS nonzero_saldo_expect_0
FROM inventario.lote_saldo ls
WHERE ls.cantidad_actual <> 0
  AND (ls.lote_id IN (SELECT raw_lote_id FROM _roll) OR ls.lote_id IN (SELECT new_lote_id FROM _map));

SELECT COUNT(*) AS dyed_missing_ingress_expect_0
FROM _map m
WHERE NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_ING'
    WHERE im.lote_id=m.new_lote_id);

-- COMMIT;    -- ← after §2: (a) 1024/1024/1024/0, (b) 1024/1024/1024, (c) 56/0/1024/0/1024, (d)=0, (e)=0
-- ROLLBACK;  -- ← if anything is off

-- ============================================================================
-- TRACK B · Phase 1 — physical-ledger backfill for lote-less DISPATCHED rolls
--   (single-line / unambiguous subset)
-- ============================================================================
-- WHAT: 2,515 legacy partidas / 50,021 dispatched rolls that were BILLED (a live
--   doc.venta line exists) but have NO physical ledger — no dyed output lote and no
--   item_movimientos. Their RAW input rolls are still sitting in stock (weighed,
--   never consumed). This synthesizes the missing lifecycle: consume the raw roll →
--   produce a dyed child (inheriting the raw roll's real, already-prorated weight) →
--   dispatch the dyed child on an outbound entrega LINKED to the existing venta.
--
-- WHY THIS IS THE MIRROR OF backfill_track_b_production.sql (and simpler):
--   The original Track-B rolls had been shortcut-EGRESSED (0 stock) so it had to
--   DELETE a phantom SERV_EGR (its STEP 1) before rebuilding. Here the raw rolls are
--   STILL IN STOCK (saldo>0, never egressed) — so there is NO phantom egress and NO
--   delete step. We add PROD_CONSUMO on the in-stock raw roll and the saldo trigger
--   (inventario.fn_trg_sync_cantidad_actual, ON CONFLICT upsert keyed on
--   (lote_id, ubicacion_id)) nets it to 0 at that SAME ubicacion — hence every
--   movement below sources the raw roll's CURRENT positive-saldo ubicacion.
--
-- WEIGHT BASIS (decided with user, 2026-07-28): B — partida-level measured
--   proration. Realised by INHERITING each raw roll's existing lote.cantidad, which
--   the migration already prorated from partida.peso_rollos/peso_rib (verified:
--   Σ input kg == partida measured total for 3,458/3,507 gap partidas). No per-roll
--   measured weight exists in legacy; this is the most faithful the source permits
--   and it reconciles to the measured partida total by construction. The eligible
--   set has 0 weightless rolls, so no fallback is exercised here.
--
-- SCOPE (Phase 1 = the clean, unambiguous tranche):
--   partida referenced in public.despacho (legacy-dispatched)
--   AND no migrated output lote (documento_tipo='partida_paso_ejecucion')
--   AND NOT live/new: no post-go-live paso_ejecucion (fyh_inicio/fyh_cre), no
--       post-go-live rework child, no post-go-live pesaje  ← excludes "new partidas"
--   AND has a COMPACTADO partida_paso_ejecucion (the production-step anchor)
--   AND eligible raw supply >= dispatched, where an eligible raw roll is PRISTINE:
--       raw (flg_tenido=false), in-stock (saldo>0), and with NO prior egress/restock/
--       production movement (no SERV_EGR/VENTA_EGR/SERV_DEV_ING/PROD_ING/PROD_CONSUMO).
--       ⚠ This is the guard that EXCLUDES the 1,729 patch-57 restocked rolls
--       (signature SERV_ING→SERV_EGR→SERV_DEV_ING) — those are the Track-B-deferred
--       ghost-egress rolls slated for MANUAL re-dispatch through the app; auto-
--       dispatching them here would collide with that flow and leave a stale ghost
--       SERV_EGR. Their 54 dependent partidas fall to supply<demand and defer out.
--   AND exactly ONE doc.venta_detalle line (so roll→billing-line linkage is
--       unambiguous — the 412 multi-shipment partidas are DEFERRED to Phase 1b).
--   → 2,515 partidas / 50,021 rebuilt rolls. supply(50,367) - demand(50,021) = 346
--     leftover raw rolls stay in stock (genuine partial-dispatch).
--
-- OVERDRAW = LEDGER DOUBLE-EGRESS ONLY (per user). The PRISTINE filter is the guard:
--   no lote is egressed twice (no roll with a prior SERV_EGR/VENTA_EGR is re-egressed;
--   dyed children are brand-new lotes), and PROD_CONSUMO only fires on a roll that
--   currently has saldo>0 — so no saldo can go negative. Verified: 0 intra-scope roll
--   sharing, so no lote is consumed twice within this run.
--   RESERVATION correctness (partida_componente) is intentionally NOT validated here —
--   deferred to a later reservation cleanup. One known overlap stays IN scope: partida
--   4237's rolls are also reserved by LIVE partida 6418 (EN_PRODUCCION). Consuming them
--   here is a single, valid ledger egress; the reservation conflict (6418) is a separate
--   later concern, not a double-egress.
--
-- PER DISPATCHED ROLL (raw net → 0, dyed child net → 0):
--   1. PROD_CONSUMO (-1) on the in-stock raw roll → doc=partida_paso_ejecucion
--      (the partida's MIN compactado ejec); origen = raw roll's current saldo ubic.
--   2. NEW dyed child lote (documento_tipo='partida_paso_ejecucion', doc=ejec,
--      cantidad = raw weight, propietario inherited, estado_calidad=APROBADO since
--      the roll was physically dispatched) + lote_rollo_detalle (origen_lote_id=raw,
--      flg_tenido=true, ingress entrega_id inherited from raw, dyeing identity from
--      the partida — mirrors registrar_produccion & the original Track-B).
--   3. PROD_ING (+1) on the dyed child → destino = same ubicacion.
--   4. SERV_EGR|VENTA_EGR (-1) on the dyed child → outbound entrega (one per partida)
--      whose venta_id = the partida's EXISTING venta (NOT a new venta). tipo by
--      propietario (1 → VENTA_EGRESO else DESPACHO_CLIENTE). fecha = MIN fecha_despacho.
--   5. entrega_detalle line with venta_detalle_id = the partida's single billing line
--      (finest linkage the coarse historical billing supports — articulo_id is NULL
--      on migrated lines; the single line carries the matching tenido×color).
--
-- ROLL SELECTION: the FIRST `dispatched` raw rolls per partida ordered by lote_id;
--   remaining raw rolls are left untouched in stock.
--
-- HISTORICAL DATING: all movements + entrega carry the legacy dispatch date
--   (MIN public.despacho.fecha_despacho for the partida). Disables the cuadre-cutoff
--   guard for the load, like the original.
--
-- WRITES: INSERT item_movimientos (PROD_CONSUMO / PROD_ING / dyed egress),
--   inventario.lote + lote_rollo_detalle (dyed children), doc.entrega +
--   entrega_detalle (outbound, venta-linked). Cleans zero lote_saldo rows.
--   Does NOT create/modify any doc.venta / venta_detalle. Does NOT touch ejec
--   cantidad_rollos/peso_kg snapshots.
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
                      AND t.codigo IN ('PROD_CONSUMO','SERV_EGR','VENTA_EGR','SERV_DEV_ING','PROD_ING')  -- excludes patch-57 restocked rolls
                    WHERE im.lote_id=pc.lote_id)
  GROUP BY pc.partida_id),
single_line AS (SELECT partida_id FROM doc.venta_detalle
  WHERE partida_id IN (SELECT partida_id FROM in_scope) GROUP BY partida_id HAVING count(*)=1),
p1 AS (
  SELECT s.partida_id, d.dispatched, u.raw_rolls
  FROM in_scope s
  JOIN compactado c ON c.partida_id=s.partida_id
  JOIN demand d ON d.partida_id=s.partida_id
  JOIN supply u ON u.partida_id=s.partida_id
  JOIN single_line sl ON sl.partida_id=s.partida_id
  WHERE u.raw_rolls >= d.dispatched)
SELECT
  (SELECT count(*) FROM p1)                                              AS partidas_expect_2515,
  (SELECT COALESCE(sum(dispatched),0) FROM p1)                          AS rebuild_rolls_expect_50021,
  (SELECT COALESCE(sum(raw_rolls),0) FROM p1)                           AS eligible_supply_expect_50367,
  -- every p1 partida has exactly one live venta line (venta not voided)
  (SELECT count(*) FROM p1 WHERE (SELECT count(*) FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id
     WHERE vd.partida_id=p1.partida_id AND v.flg_elm=false) <> 1)        AS not_single_live_venta_expect_0,
  -- tercero present for the outbound entrega header
  (SELECT count(*) FROM p1 JOIN mes.partida p ON p.id=p1.partida_id WHERE p.tercero_id IS NULL) AS no_tercero_expect_0,
  -- legacy dispatch date present
  (SELECT count(*) FROM p1 WHERE NOT EXISTS (SELECT 1 FROM public.despacho d
     WHERE d.partida_id=p1.partida_id AND d.flg_elm IS NOT TRUE AND d.fecha_despacho IS NOT NULL)) AS no_despacho_date_expect_0;


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
    -- Scope: the Phase-1 partidas + their single venta line, anchor ejec,
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
    single_line AS (SELECT vd.partida_id, MIN(vd.id) AS venta_detalle_id, MIN(vd.venta_id) AS venta_id
      FROM doc.venta_detalle vd JOIN doc.venta v ON v.id=vd.venta_id AND v.flg_elm=false
      WHERE vd.partida_id IN (SELECT partida_id FROM in_scope)
      GROUP BY vd.partida_id HAVING count(*)=1)
    SELECT s.partida_id, d.dispatched, (d.fecha)::timestamptz AS fecha_hora,
           c.anchor_ejec_id, sl.venta_id, sl.venta_detalle_id,
           p.tercero_id, p.ancho, p.malla, p.rendimiento, p.color_x_cliente_id, p.tenido_id, p.flg_antipilling
    FROM in_scope s
    JOIN compactado c ON c.partida_id=s.partida_id
    JOIN demand d ON d.partida_id=s.partida_id
    JOIN supply u ON u.partida_id=s.partida_id AND u.raw_rolls >= d.dispatched
    JOIN single_line sl ON sl.partida_id=s.partida_id
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

    -- guards: exactly 51,138 rolls, each raw roll once, each with a ubicacion
    IF (SELECT count(*) FROM _roll) <> 50021
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
    -- STEP 4 · outbound entrega — ONE per partida, linked to the EXISTING venta.
    --   tipo by propietario (1 → VENTA_EGRESO else DESPACHO_CLIENTE); a partida's
    --   rolls share a propietario (same venta), so one tipo per partida.
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
    --   partida's single billing line) + the dyed-child egress movement.
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
    RAISE NOTICE 'Track B Phase 1: % raw consumed, % dyed children, % venta-linked entregas.',
        v_n_rolls, v_n_children, v_n_entregas;
END $$;

ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify  (run BEFORE COMMIT — references this run's temp tables)
-- ══════════════════════════════════════════════════════════════════════════════
-- (a) every raw roll consumed, a dyed child exists, no raw roll left in stock
SELECT
    (SELECT count(*) FROM _roll)                                                       AS raw_touched_expect_50021,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c
        WHERE c.origen_lote_id=r.raw_lote_id AND c.flg_tenido=true))                   AS raw_with_dyed_child,
    (SELECT count(*) FROM _roll r WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='PROD_CONSUMO'
        WHERE im.lote_id=r.raw_lote_id AND im.documento_tipo='partida_paso_ejecucion')) AS raw_consumed,
    (SELECT count(*) FROM _roll r WHERE COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id=r.raw_lote_id),0) <> 0) AS raw_still_in_stock_expect_0;

-- (b) raw parent AND dyed child each net to 0 (double-entry intact). Expect all 50021.
SELECT
    COUNT(*)                                                          AS pairs_expect_50021,
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

-- (c) venta-linked outbound entregas + detalle lines == dispatched children (50021),
--     every entrega carries a venta_id, every detalle line a venta_detalle_id.
SELECT
    (SELECT count(*) FROM _ent)                                                              AS entregas_expect_2515,
    (SELECT count(*) FROM _ent WHERE entrega_id IN (SELECT id FROM doc.entrega WHERE venta_id IS NULL)) AS entregas_without_venta_expect_0,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)) AS detalle_lines_expect_50021,
    (SELECT count(*) FROM doc.entrega_detalle ed WHERE ed.entrega_id IN (SELECT entrega_id FROM _ent)
        AND ed.venta_detalle_id IS NULL)                                                    AS lines_without_venta_detalle_expect_0,
    (SELECT count(*) FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
        WHERE im.documento_tipo='entrega' AND im.documento_id IN (SELECT entrega_id FROM _ent)) AS dyed_egress_moves_expect_50021;

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

-- COMMIT;    -- ← after §2: (a) 50021/50021/50021/0, (b) 50021/50021/50021, (c) 2515/0/50021/0/50021, (d)=0, (e)=0
-- ROLLBACK;  -- ← if anything is off

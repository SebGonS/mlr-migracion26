-- ============================================================================
-- FIX · duplicate/mis-directed DEV_CLI_EGR on 3 crudo lotes (136721/173125/173126)
-- ============================================================================
-- WHAT: manual data-entry (usr 20, post-go-live) posted DEV_CLI_EGR (return crudo to
--   client, factor −1) multiple times against a single SERV_ING per roll, some with the
--   WRONG direction (destino set = ingress) instead of origen set (egress). Result:
--   factor-sum goes negative (−40/−120/−40) while lote_saldo nets to 0 (the mixed
--   directions cancel in location accounting). It is NOT a stock overdraw — it is a
--   direction/duplication mess. Physically a roll received once can be returned at most
--   once.
--
-- DECISION (user, 2026-07-28): final state = "returned once" (net 0). Keep, per lote,
--   the SERV_ING (+20) + the FIRST correctly-directed DEV_CLI_EGR (origen=8, −20);
--   DELETE every other DEV_CLI_EGR on these 3 lotes (the duplicate egresses + the
--   wrong-direction ones). The 10 deleted movements net to 0 in location terms, so
--   lote_saldo is unaffected; §1 rebuilds saldo explicitly to be safe.
--
-- These are bad MANUAL movements (not function-created), so straight DELETE is correct
--   (a compensating reversal would just add more noise). No FK/DELETE-trigger side
--   effects (item_movimientos has only INSERT/UPDATE triggers).
--
-- ⚠ DRY-RUN §0 (read-only), run §1, read §2, then COMMIT.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════════
-- §0 · DRY RUN — what will be deleted + before/after (no writes)
-- ══════════════════════════════════════════════════════════════════════════════
WITH lotes(id) AS (VALUES (136721),(173125),(173126)),
keeper AS (   -- the ONE DEV_CLI_EGR to keep per lote = min-id correctly-directed (origen set)
  SELECT im.lote_id, MIN(im.id) AS keep_id
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='DEV_CLI_EGR'
  WHERE im.lote_id IN (SELECT id FROM lotes) AND im.origen_ubicacion_id IS NOT NULL
  GROUP BY im.lote_id),
to_delete AS (
  SELECT im.id, im.lote_id, im.origen_ubicacion_id AS origen, im.destino_ubicacion_id AS destino
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='DEV_CLI_EGR'
  JOIN keeper k ON k.lote_id=im.lote_id
  WHERE im.lote_id IN (SELECT id FROM lotes) AND im.id <> k.keep_id)
SELECT
  (SELECT count(*) FROM to_delete)                                          AS movements_to_delete_expect_10,
  (SELECT count(*) FROM to_delete WHERE destino IS NOT NULL)                AS wrong_direction_ingress,
  (SELECT count(*) FROM to_delete WHERE origen IS NOT NULL)                 AS duplicate_egress,
  -- delete-set must net to 0 in location terms per lote (so saldo is safe)
  (SELECT count(*) FROM (
     SELECT lote_id, SUM(CASE WHEN destino IS NOT NULL THEN 20 ELSE 0 END)
                   - SUM(CASE WHEN origen  IS NOT NULL THEN 20 ELSE 0 END) AS net
     FROM to_delete GROUP BY lote_id HAVING SUM(CASE WHEN destino IS NOT NULL THEN 20 ELSE 0 END)
                   - SUM(CASE WHEN origen IS NOT NULL THEN 20 ELSE 0 END) <> 0) z) AS lotes_delete_net_nonzero_expect_0,
  -- after: each lote should be SERV_ING + 1 DEV_CLI_EGR → factor-sum 0
  (SELECT jsonb_agg(jsonb_build_object('lote', lote_id, 'factor_sum_now', fs))
   FROM (SELECT im.lote_id, SUM(t.factor*im.cantidad) AS fs
         FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id
         WHERE im.lote_id IN (SELECT id FROM lotes) GROUP BY im.lote_id) x) AS factor_sum_before;


-- ══════════════════════════════════════════════════════════════════════════════
-- §1 · Execute
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE TEMP TABLE _del ON COMMIT DROP AS
WITH lotes(id) AS (VALUES (136721),(173125),(173126)),
keeper AS (
  SELECT im.lote_id, MIN(im.id) AS keep_id
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='DEV_CLI_EGR'
  WHERE im.lote_id IN (SELECT id FROM lotes) AND im.origen_ubicacion_id IS NOT NULL
  GROUP BY im.lote_id)
SELECT im.id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id AND t.codigo='DEV_CLI_EGR'
JOIN keeper k ON k.lote_id=im.lote_id
WHERE im.lote_id IN (SELECT id FROM lotes) AND im.id <> k.keep_id;

-- guard: exactly 10
DO $$ BEGIN
  IF (SELECT count(*) FROM _del) <> 10 THEN
    RAISE EXCEPTION 'expected 10 movements to delete, got %', (SELECT count(*) FROM _del);
  END IF;
END $$;

DELETE FROM inventario.item_movimientos im USING _del d WHERE im.id = d.id;

-- rebuild lote_saldo for the 3 lotes from remaining movements (nets to 0 → no rows)
DELETE FROM inventario.lote_saldo WHERE lote_id IN (136721,173125,173126);
INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT lote_id, ubic, SUM(delta)
FROM (
  SELECT lote_id, destino_ubicacion_id AS ubic, cantidad AS delta
    FROM inventario.item_movimientos WHERE lote_id IN (136721,173125,173126) AND destino_ubicacion_id IS NOT NULL
  UNION ALL
  SELECT lote_id, origen_ubicacion_id, -cantidad
    FROM inventario.item_movimientos WHERE lote_id IN (136721,173125,173126) AND origen_ubicacion_id IS NOT NULL
) x
GROUP BY lote_id, ubic
HAVING abs(SUM(delta)) > 0.01;   -- omit zero-saldo rows (all 3 net to 0 → none inserted)


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify (before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════════
-- (a) each lote now = SERV_ING + exactly one DEV_CLI_EGR, factor-sum 0
SELECT im.lote_id,
       count(*) FILTER (WHERE t.codigo='SERV_ING')    AS serv_ing_expect_1,
       count(*) FILTER (WHERE t.codigo='DEV_CLI_EGR') AS dev_cli_egr_expect_1,
       round(SUM(t.factor*im.cantidad)::numeric,1)    AS factor_sum_expect_0
FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id
WHERE im.lote_id IN (136721,173125,173126)
GROUP BY im.lote_id ORDER BY im.lote_id;

-- (b) no lote_saldo left for the 3 (all net 0 = out) + system-wide overdraw back to baseline
SELECT
  (SELECT count(*) FROM inventario.lote_saldo WHERE lote_id IN (136721,173125,173126) AND abs(cantidad_actual)>0.01) AS residual_saldo_expect_0,
  (SELECT count(*) FROM (SELECT im.lote_id FROM inventario.item_movimientos im JOIN inventario.item_movimiento_tipo t ON t.id=im.item_movimiento_tipo_id WHERE im.lote_id IS NOT NULL GROUP BY im.lote_id HAVING SUM(t.factor*im.cantidad) < -0.01) z) AS roll_lotes_net_negative_expect_0;

-- COMMIT;    -- ← after §2: (a) each row 1/1/0, (b) 0 / 0  (overdraw fully cleared)
-- ROLLBACK;  -- ← if anything is off

-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY DISPATCH: create headless delivery guias + egress shipped output lotes
--
-- PURPOSE
--   For every legacy dispatch EVENT (public.despacho row), egress the number of
--   dyed production-output rolls it declares (rollos_total) from new-system stock,
--   creating a delivery document (doc.guia_remision) and posting the egress
--   movements so those lotes LEAVE inventory (lote_saldo → 0).
--
-- COUNTS-DRIVEN (not stock-sweeping)
--   Legacy public.despacho is partida-level: it has NO roll/lote identity, only
--   counts (rollos + rib = rollos_total), a date, and the invoice number. So the
--   exact lotes shipped are unknowable; we egress rollos_total rolls from the
--   partida's in-stock dyed output, picked deterministically (ORDER BY lote_id).
--
--   Per event we ship min(rollos_total, rolls_available):
--     • stock > count  → extras STAY in inventory (surfaced in SECTION 2 / 0).
--     • stock < count  → ship what's there, RAISE NOTICE the shortfall.
--   Rib flag is NOT honoured (decision: total only) — rollos_total rolls are pulled
--   from the pool regardless of lote_rollo_detalle.flg_rib.
--
-- MULTIPLE EVENTS PER PARTIDA
--   A partida may have several despacho rows (partial dispatches). Events are
--   processed oldest-first; each consumes from the remaining pool, so two events
--   of 10 + 8 ship 18 distinct rolls (or fewer if stock is short).
--
-- POOL = original + reworks
--   A legacy despacho.partida_id references the ORIGINAL legacy partida. A rework is
--   a separate mes.partida (partida_origen_id → original). The output pool for a
--   legacy partida is the COMBINED dyed output of the original and all its reworks
--   (legacy_partida_id = COALESCE(partida_origen_id, id)).
--
-- POOL MEMBERSHIP (which lotes are eligible):
--   inventario.lote  documento_tipo='partida_paso_ejecucion', documento_id =
--     COMPLETADO mes.partida_paso_ejecucion
--   ∧ lote_rollo_detalle.flg_tenido = true                       (dyed output)
--   ∧ inventario.vw_stock_lotes_ubicacion.cantidad_disponible>0  (still in stock)
--   1 lote = 1 physical roll, so COUNT(lote) = roll count.
--
-- OWNERSHIP SPLIT (per lote, same rule as get_despacho_partida):
--   propietario_id = 1  → VENTA_EGRESO    (MLR-owned roll sold)        → VENTA_EGR
--   propietario_id ≠ 1  → DESPACHO_CLIENTE (client-owned, serviced)    → SERV_EGR
--   guia.tercero_id = partida.tercero_id. If an event's picked rolls are mixed
--   ownership it produces one headless guia per tipo (rare; normally uniform).
--
-- HEADLESS GUIAS (serie/correlativo NULL)
--   The real guía de remisión number lived only in the legacy paper/external
--   system; we don't have it. doc.guia_remision allows serie/correlativo NULL
--   (chk_guia_doc_fields: both-or-neither) precisely for these movement events.
--   Because NULLs don't participate in UNIQUE(tercero,serie,correlativo,tipo),
--   that key can no longer dedup — so IDEMPOTENCY is re-anchored on the legacy
--   despacho.id, stamped into each egress movement's observacion as
--   'MIG-DESP despacho=<id> partida=<legacy_id>' and re-checked before each event.
--
-- CUADRE CUTOFF (migration 14): item_movimientos has a BEFORE INSERT trigger that
--   rejects fecha_hora < an APPLICABLE cuadre (global, or one scoped to the same
--   almacen the movement touches). We post movements on their TRUE legacy despacho
--   date, so we surgically DISABLE just trg_bi_item_movimientos_corte_cuadre for
--   the duration of the load and re-ENABLE it after — the saldo-sync AFTER INSERT
--   trigger stays live, so stock is still debited. The disable is transactional:
--   any failure rolls it back automatically.
--
-- TIMEZONE: despacho.fecha_despacho is a DATE (no time) → pinned to 17:00 local
--   Peru (UTC-5) and shifted +5h, as elsewhere.
--
-- HOW TO RUN: SECTION 0 (preview, read-only) → SECTION 1 (execute) → SECTION 2.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0 — PREVIEW  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0a. Per dispatch EVENT: declared count vs available pool vs what will ship.
--     "available" is the partida-level pool; when a partida has several events the
--     pool is shared and consumed oldest-first, so per-event availability at run
--     time may be lower than shown here (this column is the partida total).
WITH pool AS (
    SELECT
        COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
        l.id AS lote_id
    FROM mes.partida mp
    JOIN mes.partida_paso pp            ON pp.partida_id = mp.id
    JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    JOIN inventario.lote l              ON l.documento_tipo = 'partida_paso_ejecucion'
                                        AND l.documento_id   = pe.id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE mp.estado_produccion != 'CANCELADA'
    GROUP BY 1, 2
),
pool_cnt AS (
    SELECT legacy_partida_id, COUNT(*) AS rolls_disponibles
    FROM pool GROUP BY legacy_partida_id
)
SELECT
    d.id                                    AS despacho_id,
    d.partida_id                            AS legacy_partida_id,
    d.fecha_despacho,
    d.rollos_total                          AS declarado,
    COALESCE(pc.rolls_disponibles, 0)       AS pool_disponible_partida,
    LEAST(d.rollos_total, COALESCE(pc.rolls_disponibles, 0)) AS shipra_aprox,
    CASE WHEN d.rollos_total > COALESCE(pc.rolls_disponibles, 0) THEN 'FALTA STOCK'
         WHEN d.rollos_total < COALESCE(pc.rolls_disponibles, 0) THEN 'sobra stock'
         ELSE 'ok' END                      AS nota,
    EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        WHERE im.documento_tipo = 'guia_remision'
          AND im.observacion LIKE 'MIG-DESP despacho=' || d.id || ' partida=%'
    )                                       AS ya_migrado
FROM public.despacho d
LEFT JOIN pool_cnt pc ON pc.legacy_partida_id = d.partida_id
WHERE d.flg_elm = false
  AND d.rollos_total > 0
ORDER BY d.partida_id, d.fecha_despacho, d.id;

-- 0b. Dyed output in stock for partidas with NO legacy despacho at all (genuinely
--     pending — never touched by this script).
SELECT
    COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
    COUNT(DISTINCT l.id) AS rolls_en_stock,
    ROUND(SUM(sa.cantidad_disponible)::numeric, 2) AS kg
FROM mes.partida mp
JOIN mes.partida_paso pp            ON pp.partida_id = mp.id
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l              ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE mp.estado_produccion != 'CANCELADA'
  AND NOT EXISTS (
      SELECT 1 FROM public.despacho d
      WHERE d.flg_elm = false
        AND d.partida_id = COALESCE(mp.partida_origen_id, mp.id)
  )
GROUP BY 1
ORDER BY 1
LIMIT 100;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — EXECUTE  (idempotent on legacy despacho.id)
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_guia_id      BIGINT;
    v_doc_mov_id   BIGINT;
    v_fecha_mov    TIMESTAMPTZ;
    v_n_guias      INT := 0;
    v_n_lotes      INT := 0;
    v_n_events     INT := 0;
    v_n_short      INT := 0;
    v_picked       INT;
    v_obs          TEXT;
    ev             RECORD;
    grp            RECORD;
BEGIN
    -- Override the cutoff guard so egresses post on their true legacy date.
    -- Surgical: only the corte trigger is off; saldo-sync stays on. Rolled back
    -- automatically if anything below fails.
    ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

    -- ── Output-lote pool (live stock), keyed by legacy partida (original+reworks) ──
    DROP TABLE IF EXISTS tmp_pool;
    CREATE TEMP TABLE tmp_pool AS
    SELECT
        COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
        mp.tercero_id,
        l.id                                   AS lote_id,
        l.item_id,
        sa.ubicacion_id,
        sa.cantidad_disponible                 AS cantidad,
        grt.id                                 AS guia_tipo_id,
        grt.item_movimiento_tipo_id            AS mov_tipo_id
    FROM mes.partida mp
    JOIN mes.partida_paso pp            ON pp.partida_id = mp.id
    JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    JOIN inventario.lote l              ON l.documento_tipo = 'partida_paso_ejecucion'
                                        AND l.documento_id   = pe.id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    JOIN doc.guia_remision_tipo grt
        ON grt.codigo = CASE WHEN l.propietario_id = 1 THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END
    WHERE mp.estado_produccion != 'CANCELADA';

    CREATE INDEX ON tmp_pool (legacy_partida_id, lote_id);

    -- scratch table for the rolls picked per event (recreated via TRUNCATE)
    DROP TABLE IF EXISTS tmp_pick;
    CREATE TEMP TABLE tmp_pick (LIKE tmp_pool);

    -- ── Process each dispatch event, oldest first; idempotent on despacho.id ──────
    FOR ev IN
        SELECT
            d.id                                   AS despacho_id,
            d.partida_id                           AS legacy_partida_id,
            d.rollos_total,
            ((d.fecha_despacho + '17:00'::time)::timestamp + INTERVAL '5 hours')::timestamptz
                                                   AS fecha_despacho_ts
        FROM public.despacho d
        WHERE d.flg_elm = false
          AND d.rollos_total > 0
          AND EXISTS (SELECT 1 FROM tmp_pool p WHERE p.legacy_partida_id = d.partida_id)
          AND NOT EXISTS (
              SELECT 1 FROM inventario.item_movimientos im
              WHERE im.documento_tipo = 'guia_remision'
                AND im.observacion LIKE 'MIG-DESP despacho=' || d.id || ' partida=%'
          )
        ORDER BY d.partida_id, d.fecha_despacho, d.id
    LOOP
        -- pick up to rollos_total rolls from the remaining pool (total only)
        TRUNCATE tmp_pick;
        INSERT INTO tmp_pick
        SELECT * FROM tmp_pool
        WHERE legacy_partida_id = ev.legacy_partida_id
        ORDER BY lote_id
        LIMIT ev.rollos_total;

        GET DIAGNOSTICS v_picked = ROW_COUNT;
        IF v_picked = 0 THEN
            CONTINUE;   -- pool already drained by earlier events
        END IF;

        v_n_events := v_n_events + 1;
        IF v_picked < ev.rollos_total THEN
            v_n_short := v_n_short + 1;
            RAISE NOTICE 'despacho #% partida % : declarado % rolls, solo % en stock (faltan %)',
                ev.despacho_id, ev.legacy_partida_id, ev.rollos_total, v_picked, ev.rollos_total - v_picked;
        END IF;

        v_fecha_mov := ev.fecha_despacho_ts;   -- true legacy despacho date (cutoff trigger overridden)
        v_obs := 'MIG-DESP despacho=' || ev.despacho_id || ' partida=' || ev.legacy_partida_id;

        -- one headless guia per ownership tipo present in the picked set (normally one)
        FOR grp IN
            SELECT tercero_id, guia_tipo_id, mov_tipo_id
            FROM tmp_pick
            GROUP BY tercero_id, guia_tipo_id, mov_tipo_id
        LOOP
            INSERT INTO doc.guia_remision (
                guia_remision_tipo_id, tercero_id, serie, correlativo,
                fecha_emision, fecha_recepcion, usr_cre, fyh_cre
            ) VALUES (
                grp.guia_tipo_id, grp.tercero_id, NULL, NULL,
                ev.fecha_despacho_ts, NULL, NULL, ev.fecha_despacho_ts
            )
            RETURNING id INTO v_guia_id;
            v_n_guias := v_n_guias + 1;

            -- shared posting document id for this guia's egress movements
            SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

            -- guia detalle (one line per roll)
            INSERT INTO doc.guia_remision_detalle (
                guia_remision_id, linea, item_id, lote_id, ubicacion_id, cantidad, n_rollos
            )
            SELECT
                v_guia_id,
                ROW_NUMBER() OVER (ORDER BY c.lote_id)::smallint,
                c.item_id, c.lote_id, c.ubicacion_id, c.cantidad, 1
            FROM tmp_pick c
            WHERE c.guia_tipo_id = grp.guia_tipo_id;

            -- egress movements (origen set, destino NULL → debit; saldo trigger zeroes stock)
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id,
                cantidad, fecha_hora, documento_tipo, documento_id, observacion
            )
            SELECT
                v_doc_mov_id, c.item_id, c.lote_id, grp.mov_tipo_id,
                c.ubicacion_id, NULL,
                c.cantidad, v_fecha_mov, 'guia_remision', v_guia_id, v_obs
            FROM tmp_pick c
            WHERE c.guia_tipo_id = grp.guia_tipo_id;

            v_n_lotes := v_n_lotes + (SELECT COUNT(*) FROM tmp_pick WHERE guia_tipo_id = grp.guia_tipo_id);
        END LOOP;

        -- consume picked rolls so later events don't reuse them
        DELETE FROM tmp_pool p USING tmp_pick k WHERE p.lote_id = k.lote_id;
    END LOOP;

    -- restore the cutoff guard
    ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

    RAISE NOTICE '═══════════ DESPACHO EGRESO LEGACY ═══════════';
    RAISE NOTICE '  eventos procesados   : %', v_n_events;
    RAISE NOTICE '  eventos con faltante : %', v_n_short;
    RAISE NOTICE '  guias creadas        : %', v_n_guias;
    RAISE NOTICE '  lotes egresados      : %', v_n_lotes;
    RAISE NOTICE '  fecha egreso         : real (legacy despacho date)';
    RAISE NOTICE '═══════════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. Migration guias created (headless: serie IS NULL), identified via the
--     despacho-id token on their egress movements.
SELECT
    grt.codigo                              AS tipo,
    COUNT(DISTINCT gr.id)                   AS guias,
    COUNT(grd.id)                           AS lineas,
    ROUND(SUM(grd.cantidad)::numeric, 2)    AS kg_total
FROM doc.guia_remision gr
JOIN doc.guia_remision_tipo grt ON grt.id = gr.guia_remision_tipo_id
LEFT JOIN doc.guia_remision_detalle grd ON grd.guia_remision_id = gr.id
WHERE gr.id IN (
    SELECT DISTINCT documento_id
    FROM inventario.item_movimientos
    WHERE documento_tipo = 'guia_remision'
      AND observacion LIKE 'MIG-DESP despacho=%'
)
GROUP BY grt.codigo
ORDER BY grt.codigo;

-- 2b. Declared vs shipped per legacy partida — surfaces shortfalls and leftovers.
WITH declarado AS (
    SELECT partida_id AS legacy_partida_id, SUM(rollos_total) AS rolls_declarados
    FROM public.despacho WHERE flg_elm = false
    GROUP BY partida_id
),
egresado AS (
    SELECT
        substring(im.observacion FROM 'partida=([0-9]+)')::int AS legacy_partida_id,
        COUNT(*) AS rolls_egresados
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'guia_remision'
      AND im.observacion LIKE 'MIG-DESP despacho=%'
    GROUP BY 1
)
SELECT
    COALESCE(d.legacy_partida_id, e.legacy_partida_id) AS legacy_partida_id,
    COALESCE(d.rolls_declarados, 0)  AS declarados,
    COALESCE(e.rolls_egresados, 0)   AS egresados,
    COALESCE(d.rolls_declarados, 0) - COALESCE(e.rolls_egresados, 0) AS diferencia
FROM declarado d
FULL JOIN egresado e ON e.legacy_partida_id = d.legacy_partida_id
WHERE COALESCE(d.rolls_declarados, 0) <> COALESCE(e.rolls_egresados, 0)
ORDER BY diferencia DESC
LIMIT 100;

-- 2c. Egress movements posted by this migration.
SELECT imt.codigo AS mov_tipo, COUNT(*) AS movimientos, ROUND(SUM(im.cantidad)::numeric,2) AS kg
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'guia_remision'
  AND im.observacion LIKE 'MIG-DESP despacho=%'
GROUP BY imt.codigo
ORDER BY imt.codigo;

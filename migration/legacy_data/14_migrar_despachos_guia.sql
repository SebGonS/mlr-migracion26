-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY DISPATCH BY GUIA — create named outbound entregas from public.partida.guia
--
-- WHAT THIS DOES (vs 09_despacho_egreso_legacy.sql)
--   09: headless entregas (serie/correlativo NULL), driven by public.despacho
--       COUNT rows (roll identity unknown, only totals).
--   14: named entregas (serie+correlativo from public.partida.guia), driven at
--       roll level — actual output lotes are identified and linked.
--       Multiple partidas sharing the same guia value → ONE entrega header.
--       lote_rollo_detalle.entrega_id updated on dispatched rolls (full genealogy).
--
-- PREREQUISITE
--   09_despacho_egreso_legacy.sql must NOT have been run, OR its effects must be
--   reversed first (see REVERSAL block below). This script pools lotes by
--   cantidad_disponible > 0; if 09 already egressed them, the pool is empty.
--
-- COLUMN NOTE
--   The legacy dispatch document reference is stored in public.partida.guia
--   (patch 29 names it "varchar free-text legacy field").
--   The user describes it as "guia_remision" — same field, different name.
--   Run SECTION 0a to confirm the column exists before proceeding.
--
-- GUIA PARSING
--   'T001-00123'  → serie='T001'  correlativo='00123'  (first '-' splits)
--   'T001'        → no dash → headless (both NULL) — same as no guia
--   NULL / merged → headless (MLR-owned) or SKIP (client-owned)
--
-- "MERGED" GUIA DETECTION
--   Values containing '/', '|', ',' or matching ' y ' (case-insensitive) are
--   considered concatenated multi-document references and treated as unclear.
--
-- OWNERSHIP SPLIT (per lote, consistent with funciones/despacho.sql)
--   lote.propietario_id = 1  → VENTA_EGRESO    (MLR sells its own dyed output)
--   lote.propietario_id ≠ 1  → DESPACHO_CLIENTE (client-owned, serviced by MLR)
--
-- MLR IDENTIFICATION (for skip exception)
--   tercero.nombre ILIKE '%MLR%' OR '%Oswaldo%' OR tercero.procedencia = 'MLR'
--   MLR-owned partidas without a clear guia get a headless VENTA_EGRESO entrega.
--
-- MERGE RULE
--   Two partidas with the same guia + same tercero_id → single entrega header.
--   ON CONFLICT (tercero_id, serie, correlativo, entrega_tipo_id) handles dedup
--   for named entregas.
--
-- GENEALOGY
--   After dispatch: lote_rollo_detalle.entrega_id ← dispatch entrega id
--   Full chain: ingress_entrega → input_lote → partida_componente → partida
--               → partida_paso_ejecucion → output_lote → dispatch_entrega
--
-- IDEMPOTENCY
--   Named entregas: UNIQUE constraint deduplicates repeated runs.
--   Headless MLR:   guarded by observacion token 'MIG-GUIA14 partida=X'.
--   Pool:           cantidad_disponible > 0 only; already-egressed rolls absent.
--
-- CUADRE CUTOFF
--   Cuadre trigger disabled for the session (same pattern as 09); re-enabled
--   at end or on failure. Saldo trigger stays live — stock properly debited.
--
-- HOW TO RUN
--   1. Section 0a — verify column name
--   2. Section 0b — dry run (read-only)
--   3. Section 0c — (optional) review merged/unclear guias
--   4. Section 1  — execute
--   5. Section 2  — validate
-- ═══════════════════════════════════════════════════════════════════════════════
SELECT schemaname, relname, n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'entrega_tipo';

-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0a — COLUMN VERIFICATION (read-only)
-- Confirm the dispatch guia column name. Expected: 'guia' from public.partida.
-- ═══════════════════════════════════════════════════════════════════════════════
SELECT column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'partida'
  AND column_name  ILIKE '%guia%'
ORDER BY column_name;
-- Expected: one row, column_name = 'guia', data_type = 'character varying' or 'text'
-- If the column is named differently, replace p.guia with p.<actual_name> throughout.

-- Sample non-null values to understand format:
SELECT DISTINCT guia, COUNT(*) AS n_partidas
FROM public.partida
WHERE guia IS NOT NULL AND guia <> ''
GROUP BY guia
ORDER BY n_partidas DESC
LIMIT 30;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0b — PRE-FLIGHT DRY RUN (read-only)
-- Shows how the pool will be classified by guia value.
-- ═══════════════════════════════════════════════════════════════════════════════

WITH pool AS (
    SELECT
        COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
        mp.tercero_id,
        t.nombre                               AS tercero_nombre,
        (t.nombre ILIKE '%MLR%'
            OR t.nombre ILIKE '%Oswaldo%'
            OR t.procedencia = 'MLR')          AS es_mlr,
        l.id                                   AS lote_id,
        l.propietario_id,
        CASE WHEN l.propietario_id = 1
             THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END AS tipo_codigo,
        sa.cantidad_disponible                 AS cantidad,
        NULLIF(TRIM(p.guia), '')               AS guia          -- ← col: p.guia
    FROM mes.partida mp
    JOIN public.partida p    ON p.id = COALESCE(mp.partida_origen_id, mp.id)
    JOIN tercero t           ON t.id = mp.tercero_id
    JOIN mes.partida_paso pp ON pp.partida_id = mp.id
    JOIN mes.partida_paso_ejecucion pe
         ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    JOIN inventario.lote l
         ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
    JOIN inventario.lote_rollo_detalle lrd
         ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE mp.estado_produccion != 'CANCELADA'
      AND sa.cantidad_disponible > 0
),
classified AS (
    SELECT
        guia,
        tercero_id,
        tercero_nombre,
        es_mlr,
        tipo_codigo,
        COUNT(DISTINCT legacy_partida_id)  AS n_partidas,
        COUNT(*)                           AS n_rolls,
        ROUND(SUM(cantidad)::numeric, 2)   AS kg_total,
        (guia IS NOT NULL AND guia !~ '[/|,]' AND guia !~* '\y y \y')
                                           AS guia_clara
    FROM pool
    GROUP BY guia, tercero_id, tercero_nombre, es_mlr, tipo_codigo,
             (guia IS NOT NULL AND guia !~ '[/|,]' AND guia !~* '\y y \y')
)
SELECT
    COALESCE(guia, '(null)')               AS guia_valor,
    tercero_nombre,
    tipo_codigo,
    n_partidas,
    n_rolls,
    kg_total,
    guia_clara,
    CASE
        WHEN guia_clara                     THEN 'INCLUIR con correlativo'
        WHEN NOT guia_clara AND es_mlr      THEN 'INCLUIR headless (MLR sin guia clara)'
        ELSE                                     'OMITIR (sin documento claro)'
    END                                    AS accion
FROM classified
ORDER BY accion, guia NULLS LAST, tercero_nombre;

-- Totals by action:
WITH pool AS (
    SELECT
        COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
        t.nombre ILIKE '%MLR%' OR t.nombre ILIKE '%Oswaldo%' OR t.procedencia = 'MLR' AS es_mlr,
        l.id AS lote_id,
        sa.cantidad_disponible AS cantidad,
        NULLIF(TRIM(p.guia), '') AS guia
    FROM mes.partida mp
    JOIN public.partida p    ON p.id = COALESCE(mp.partida_origen_id, mp.id)
    JOIN tercero t           ON t.id = mp.tercero_id
    JOIN mes.partida_paso pp ON pp.partida_id = mp.id
    JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    JOIN inventario.lote l   ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE mp.estado_produccion != 'CANCELADA' AND sa.cantidad_disponible > 0
)
SELECT
    CASE
        WHEN guia IS NOT NULL AND guia !~ '[/|,]' AND guia !~* '\y y \y' THEN 'con correlativo'
        WHEN es_mlr THEN 'headless MLR'
        ELSE 'OMITIR'
    END AS accion,
    COUNT(*) AS rolls,
    ROUND(SUM(cantidad)::numeric, 2) AS kg
FROM pool
GROUP BY 1 ORDER BY 1;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 0c — MERGED / UNCLEAR GUIA DETAIL
-- Review these before running Section 1 — they will be skipped for client rolls.
-- ═══════════════════════════════════════════════════════════════════════════════
SELECT DISTINCT
    p.guia,
    mp.id AS partida_id,
    t.nombre AS tercero
FROM public.partida p
JOIN mes.partida mp ON mp.id = p.id
JOIN tercero t ON t.id = mp.tercero_id
WHERE p.guia IS NOT NULL
  AND (p.guia ~ '[/|,]' OR p.guia ~* '\y y \y')
ORDER BY p.guia, mp.id;


-- ═══════════════════════════════════════════════════════════════════════════════
-- REVERSAL OF 09_despacho_egreso_legacy (RUN ONLY IF 09 ALREADY EXECUTED)
-- ─────────────────────────────────────────────────────────────────────────────
-- WARNING: this posts counter-movements (restoring stock) then removes all
-- movements, entrega_detalle, and entrega records created by script 09.
-- Only execute if 09 has been run and you want to switch to this (14) approach.
-- ═══════════════════════════════════════════════════════════════════════════════
/*
DO $$
DECLARE
    v_doc_mov_id BIGINT;
    v_mig09_entrega_ids BIGINT[];
    v_count INT;
BEGIN
    -- Collect entrega ids created by 09
    SELECT ARRAY_AGG(DISTINCT documento_id)
    INTO v_mig09_entrega_ids
    FROM inventario.item_movimientos
    WHERE documento_tipo = 'entrega'
      AND observacion LIKE 'MIG-DESP despacho=%';

    IF cardinality(COALESCE(v_mig09_entrega_ids, ARRAY[]::BIGINT[])) = 0 THEN
        RAISE NOTICE '09_despacho_egreso_legacy: nada que revertir.';
        RETURN;
    END IF;

    -- Disable cuadre guard (stock reversal may touch historical dates)
    ALTER TABLE inventario.item_movimientos DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

    -- Post counter-movements (restores stock saldo)
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, observacion
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id,
        imt_rev.id,
        im.destino_ubicacion_id,  -- swap: debit → credit direction
        im.origen_ubicacion_id,
        im.cantidad, NOW(),
        'entrega', im.documento_id,
        'REV-MIG09 orig_mov=' || im.id
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    JOIN inventario.item_movimiento_tipo imt_rev
         ON imt_rev.codigo = CASE imt.codigo
             WHEN 'VENTA_EGR' THEN 'DEV_CLI_ING'
             WHEN 'SERV_EGR'  THEN 'SERV_DEV_ING'
         END
    WHERE im.documento_tipo = 'entrega'
      AND im.observacion LIKE 'MIG-DESP despacho=%';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Reversal: % contra-movimientos insertados', v_count;

    -- Delete original 09 movements
    DELETE FROM inventario.item_movimientos
    WHERE documento_tipo = 'entrega'
      AND observacion LIKE 'MIG-DESP despacho=%';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Eliminados % movimientos de script 09', v_count;

    -- Delete reversal counter-movements reference rows
    DELETE FROM inventario.item_movimientos
    WHERE observacion LIKE 'REV-MIG09 orig_mov=%';

    -- Delete entrega_detalle + entrega headers from 09
    DELETE FROM doc.entrega_detalle WHERE entrega_id = ANY(v_mig09_entrega_ids);
    DELETE FROM doc.entrega          WHERE id         = ANY(v_mig09_entrega_ids);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Eliminadas % entregas headless de script 09', v_count;

    ALTER TABLE inventario.item_movimientos ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

    RAISE NOTICE 'Reversal de 09_despacho_egreso_legacy completado.';
END;
$$;
*/


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — EXECUTE
-- ═══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    v_venta_egr_tipo_id    SMALLINT;
    v_despacho_cli_tipo_id SMALLINT;
    v_venta_egr_imt_id     SMALLINT;
    v_despacho_cli_imt_id  SMALLINT;

    grp                    RECORD;
    v_entrega_id           BIGINT;
    v_doc_mov_id           BIGINT;
    v_serie                TEXT;
    v_corr                 TEXT;
    v_tipo_id              SMALLINT;
    v_imt_id               SMALLINT;
    v_obs_guia             TEXT;
    v_linea_base           SMALLINT;
    v_rows                 INT;

    v_n_entregas           INT := 0;
    v_n_rolls              INT := 0;
    v_n_skipped_grp        INT := 0;
    v_n_already_done       INT := 0;
BEGIN
    -- ── Resolve tipo / movement ids ────────────────────────────────────────────
    SELECT id INTO STRICT v_venta_egr_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'VENTA_EGRESO';

    SELECT id INTO STRICT v_despacho_cli_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'DESPACHO_CLIENTE';

    SELECT id INTO STRICT v_venta_egr_imt_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'VENTA_EGR';

    SELECT id INTO STRICT v_despacho_cli_imt_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_EGR';

    -- ── Override cutoff guard (same pattern as 09_despacho_egreso_legacy) ─────
    ALTER TABLE inventario.item_movimientos
        DISABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

    -- ── Build pool of dispatchable dyed output rolls ──────────────────────────
    -- One row per lote currently in stock on a COMPLETADO TENIDO paso output.
    DROP TABLE IF EXISTS tmp_guia14_pool;
    CREATE TEMP TABLE tmp_guia14_pool AS
    SELECT
        COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
        mp.tercero_id,
        t.nombre                               AS tercero_nombre,
        (t.nombre ILIKE '%MLR%'
            OR t.nombre ILIKE '%Oswaldo%'
            OR t.procedencia = 'MLR')          AS es_mlr,
        l.id                                   AS lote_id,
        l.item_id,
        l.propietario_id,
        CASE WHEN l.propietario_id = 1
             THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END AS tipo_codigo,
        CASE WHEN l.propietario_id = 1
             THEN v_venta_egr_tipo_id ELSE v_despacho_cli_tipo_id END AS tipo_id,
        CASE WHEN l.propietario_id = 1
             THEN v_venta_egr_imt_id  ELSE v_despacho_cli_imt_id  END AS imt_id,
        sa.ubicacion_id,
        sa.cantidad_disponible                 AS cantidad,
        -- Dispatch guia from the legacy partida (the ORIGINAL partida's guia).
        -- COLUMN: public.partida.guia — change here if named differently.
        NULLIF(TRIM(p.guia), '')               AS guia,
        -- "Clear" = not null, no merged-doc indicators
        (p.guia IS NOT NULL
            AND TRIM(p.guia) <> ''
            AND TRIM(p.guia) !~ '[/|,]'
            AND TRIM(p.guia) !~* '\y y \y')    AS guia_clara,
        -- Dispatch date: prefer public.despacho.fecha_despacho, fall back to production end
        COALESCE(
            (SELECT ((MAX(d.fecha_despacho) + '17:00'::time)::TIMESTAMP
                        + INTERVAL '5 hours')::TIMESTAMPTZ
             FROM public.despacho d
             WHERE d.flg_elm = false
               AND d.partida_id = COALESCE(mp.partida_origen_id, mp.id)),
            COALESCE(mp.fyh_fin, mp.fyh_cre)
        )                                      AS fecha_despacho_ts
    FROM mes.partida mp
    JOIN public.partida p    ON p.id = COALESCE(mp.partida_origen_id, mp.id)
    JOIN tercero t           ON t.id = mp.tercero_id
    JOIN mes.partida_paso pp ON pp.partida_id = mp.id
    JOIN mes.partida_paso_ejecucion pe
         ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
    JOIN inventario.lote l
         ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
    JOIN inventario.lote_rollo_detalle lrd
         ON lrd.lote_id = l.id AND lrd.flg_tenido = true
    JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE mp.estado_produccion != 'CANCELADA'
      AND sa.cantidad_disponible > 0
      -- Skip lotes already dispatched by THIS script (idempotency)
      AND NOT EXISTS (
          SELECT 1 FROM inventario.item_movimientos im
          WHERE im.documento_tipo = 'entrega'
            AND im.lote_id = l.id
            AND im.observacion LIKE 'MIG-GUIA14%'
      );

    CREATE INDEX ON tmp_guia14_pool (guia, tercero_id, tipo_codigo);
    CREATE INDEX ON tmp_guia14_pool (lote_id);

    -- ── Process each (guia, tercero_id, ownership_tipo) group ─────────────────
    FOR grp IN
        SELECT
            guia,
            tercero_id,
            tercero_nombre,
            es_mlr,
            tipo_codigo,
            tipo_id,
            imt_id,
            guia_clara,
            MIN(fecha_despacho_ts) AS fecha_despacho_ts,   -- earliest event date for header
            COUNT(*)               AS n_rolls,
            COUNT(DISTINCT legacy_partida_id) AS n_partidas
        FROM tmp_guia14_pool
        GROUP BY guia, tercero_id, tercero_nombre, es_mlr,
                 tipo_codigo, tipo_id, imt_id, guia_clara
        ORDER BY guia NULLS LAST, tercero_id, tipo_codigo
    LOOP
        -- ── Skip logic ─────────────────────────────────────────────────────────
        -- Client-owned rolls with no clear document → skip
        IF NOT grp.guia_clara AND NOT grp.es_mlr THEN
            v_n_skipped_grp := v_n_skipped_grp + 1;
            RAISE NOTICE 'SKIP guia=% tercero=% tipo=% (% rolls, sin documento claro)',
                grp.guia, grp.tercero_nombre, grp.tipo_codigo, grp.n_rolls;
            CONTINUE;
        END IF;

        -- ── Parse guia → serie / correlativo ──────────────────────────────────
        IF grp.guia_clara AND POSITION('-' IN grp.guia) > 0 THEN
            v_serie := SPLIT_PART(grp.guia, '-', 1);
            v_corr  := SUBSTRING(grp.guia FROM POSITION('-' IN grp.guia) + 1);
        ELSE
            -- No dash, or unclear/null guia for MLR → headless
            v_serie := NULL;
            v_corr  := NULL;
        END IF;

        v_obs_guia := 'MIG-GUIA14 guia=' || COALESCE(grp.guia, 'NULL');

        -- ── Create or reuse entrega header ─────────────────────────────────────
        v_entrega_id := NULL;

        IF v_serie IS NOT NULL THEN
            -- Named entrega: UNIQUE (tercero_id, serie, correlativo, entrega_tipo_id)
            INSERT INTO doc.entrega (
                entrega_tipo_id, tercero_id, serie, correlativo,
                fecha_emision, fyh_cre
            )
            VALUES (
                grp.tipo_id, grp.tercero_id, v_serie, v_corr,
                grp.fecha_despacho_ts, grp.fecha_despacho_ts
            )
            ON CONFLICT (tercero_id, serie, correlativo, entrega_tipo_id) DO NOTHING
            RETURNING id INTO v_entrega_id;

            -- Lookup if another partida in the same guia group created it first
            IF v_entrega_id IS NULL THEN
                SELECT id INTO v_entrega_id
                FROM doc.entrega
                WHERE entrega_tipo_id = grp.tipo_id
                  AND tercero_id      = grp.tercero_id
                  AND serie           = v_serie
                  AND correlativo     = v_corr;

                v_n_already_done := v_n_already_done + 1;  -- reusing existing header
            ELSE
                v_n_entregas := v_n_entregas + 1;
            END IF;
        ELSE
            -- Headless: NULLs don't participate in UNIQUE → always new row
            -- (MLR-owned rolls without clear guia)
            INSERT INTO doc.entrega (
                entrega_tipo_id, tercero_id, serie, correlativo,
                fecha_emision, fyh_cre
            )
            VALUES (
                grp.tipo_id, grp.tercero_id, NULL, NULL,
                grp.fecha_despacho_ts, grp.fecha_despacho_ts
            )
            RETURNING id INTO v_entrega_id;
            v_n_entregas := v_n_entregas + 1;
        END IF;

        -- Shared doc_movimiento_id for this entrega's egress movements
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

        -- Current max linea for this entrega (safe when header reused by multi-partida guia)
        SELECT COALESCE(MAX(linea), 0)
        INTO v_linea_base
        FROM doc.entrega_detalle
        WHERE entrega_id = v_entrega_id;

        -- ── entrega_detalle — one line per roll ────────────────────────────────
        INSERT INTO doc.entrega_detalle (
            entrega_id, linea, item_id, lote_id, ubicacion_id, cantidad, n_rollos
        )
        SELECT
            v_entrega_id,
            (v_linea_base
                + ROW_NUMBER() OVER (ORDER BY pl.lote_id))::SMALLINT,
            pl.item_id,
            pl.lote_id,
            pl.ubicacion_id,
            pl.cantidad,
            1
        FROM tmp_guia14_pool pl
        WHERE pl.guia         IS NOT DISTINCT FROM grp.guia
          AND pl.tercero_id    = grp.tercero_id
          AND pl.tipo_codigo   = grp.tipo_codigo;

        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_n_rolls := v_n_rolls + v_rows;

        -- ── Egress movements — debit stock ─────────────────────────────────────
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, fecha_hora, documento_tipo, documento_id, observacion
        )
        SELECT
            v_doc_mov_id,
            pl.item_id, pl.lote_id, grp.imt_id,
            pl.ubicacion_id, NULL,
            pl.cantidad,
            grp.fecha_despacho_ts,
            'entrega', v_entrega_id,
            v_obs_guia || ' partida=' || pl.legacy_partida_id
        FROM tmp_guia14_pool pl
        WHERE pl.guia         IS NOT DISTINCT FROM grp.guia
          AND pl.tercero_id    = grp.tercero_id
          AND pl.tipo_codigo   = grp.tipo_codigo;

        -- ── Update lrd.entrega_id → full genealogy anchor on output rolls ──────
        -- Only set if not already pointing to an entrega (preserve manually set links).
        UPDATE inventario.lote_rollo_detalle
        SET entrega_id = v_entrega_id
        FROM tmp_guia14_pool pl
        WHERE pl.guia          IS NOT DISTINCT FROM grp.guia
          AND pl.tercero_id     = grp.tercero_id
          AND pl.tipo_codigo    = grp.tipo_codigo
          AND inventario.lote_rollo_detalle.lote_id = pl.lote_id
          AND inventario.lote_rollo_detalle.entrega_id IS NULL;

        RAISE NOTICE '% entrega=% (serie=% corr=%) tercero=% %rolls % kg',
            grp.tipo_codigo, v_entrega_id, v_serie, v_corr,
            grp.tercero_nombre, grp.n_rolls,
            ROUND((SELECT SUM(cantidad) FROM tmp_guia14_pool
                   WHERE guia IS NOT DISTINCT FROM grp.guia
                     AND tercero_id = grp.tercero_id
                     AND tipo_codigo = grp.tipo_codigo)::numeric, 2);

        -- Remove dispatched rows from pool so next iteration doesn't double-pick
        DELETE FROM tmp_guia14_pool pl
        WHERE pl.guia          IS NOT DISTINCT FROM grp.guia
          AND pl.tercero_id     = grp.tercero_id
          AND pl.tipo_codigo    = grp.tipo_codigo;

    END LOOP;

    -- ── Re-enable cuadre guard ─────────────────────────────────────────────────
    ALTER TABLE inventario.item_movimientos
        ENABLE TRIGGER trg_bi_item_movimientos_corte_cuadre;

    RAISE NOTICE '══════════════════════════════════════════';
    RAISE NOTICE ' DESPACHO BY GUIA — RESUMEN';
    RAISE NOTICE '  entregas creadas          : %', v_n_entregas;
    RAISE NOTICE '  headers reutilizados      : %', v_n_already_done;
    RAISE NOTICE '  grupos omitidos (sin doc) : %', v_n_skipped_grp;
    RAISE NOTICE '  lotes despachados         : %', v_n_rolls;
    RAISE NOTICE '══════════════════════════════════════════';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a. Entregas created by this migration (named + headless)
SELECT
    grt.codigo                              AS tipo,
    gr.serie IS NOT NULL                    AS tiene_serie,
    COUNT(DISTINCT gr.id)                   AS entregas,
    COUNT(grd.id)                           AS lineas,
    ROUND(SUM(grd.cantidad)::numeric, 2)    AS kg_total
FROM doc.entrega gr
JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
LEFT JOIN doc.entrega_detalle grd ON grd.entrega_id = gr.id
WHERE gr.id IN (
    SELECT DISTINCT documento_id
    FROM inventario.item_movimientos
    WHERE documento_tipo = 'entrega'
      AND observacion LIKE 'MIG-GUIA14%'
)
GROUP BY grt.codigo, gr.serie IS NOT NULL
ORDER BY grt.codigo, tiene_serie DESC;

-- 2b. Per-entrega summary — one row per created entrega (correct, no cross-product)
SELECT
    gr.id                                            AS entrega_id,
    COALESCE(gr.serie || '-' || gr.correlativo,
             '(headless)')                           AS entrega_doc,
    -- Show which guia value(s) sourced this entrega (stripped of partida suffix)
    (SELECT STRING_AGG(DISTINCT
                REGEXP_REPLACE(im2.observacion, ' partida=\d+', ''), ', '
              ORDER BY REGEXP_REPLACE(im2.observacion, ' partida=\d+', ''))
     FROM inventario.item_movimientos im2
     WHERE im2.documento_tipo = 'entrega'
       AND im2.documento_id = gr.id
       AND im2.observacion LIKE 'MIG-GUIA14%')       AS guia_tokens,
    grt.codigo                                       AS tipo,
    t.nombre                                         AS tercero,
    COUNT(DISTINCT grd.lote_id)                      AS rolls,
    ROUND(SUM(grd.cantidad)::numeric, 2)             AS kg
FROM doc.entrega gr
JOIN doc.entrega_tipo grt    ON grt.id = gr.entrega_tipo_id
JOIN tercero t               ON t.id   = gr.tercero_id
JOIN doc.entrega_detalle grd ON grd.entrega_id = gr.id
WHERE gr.id IN (
    SELECT DISTINCT documento_id FROM inventario.item_movimientos
    WHERE documento_tipo = 'entrega' AND observacion LIKE 'MIG-GUIA14%'
)
GROUP BY gr.id, gr.serie, gr.correlativo, grt.codigo, t.nombre
ORDER BY gr.serie NULLS LAST, gr.correlativo, gr.id;

-- 2c. Output rolls with lrd.entrega_id set (genealogy anchor)
SELECT
    COUNT(*)                                         AS lotes_con_entrega_dispatch,
    COUNT(*) FILTER (WHERE lrd.entrega_id IS NULL)   AS lotes_sin_entrega
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
WHERE l.documento_tipo = 'partida_paso_ejecucion';

-- 2d. Dyed output rolls in stock with NO egress entrega movement at all
--     These are genuinely undispatched (skipped by this script AND by 09).
SELECT
    COALESCE(mp.partida_origen_id, mp.id)    AS legacy_partida_id,
    p.guia                                   AS guia_valor,
    t.nombre                                 AS tercero,
    (t.nombre ILIKE '%MLR%'
       OR t.nombre ILIKE '%Oswaldo%'
       OR t.procedencia = 'MLR')             AS es_mlr,
    COUNT(DISTINCT l.id)                     AS rolls_en_stock,
    ROUND(SUM(sa.cantidad_disponible)::numeric, 2) AS kg,
    CASE
        WHEN NULLIF(TRIM(p.guia), '') IS NULL           THEN 'sin guia'
        WHEN TRIM(p.guia) ~ '[/|,]'
          OR TRIM(p.guia) ~* '\y y \y'                  THEN 'guia dudosa'
        WHEN POSITION('-' IN TRIM(p.guia)) = 0          THEN 'guia sin dash (headless)'
        ELSE                                                  'guia clara'
    END                                      AS motivo_restante
FROM mes.partida mp
JOIN public.partida p    ON p.id = COALESCE(mp.partida_origen_id, mp.id)
JOIN tercero t           ON t.id = mp.tercero_id
JOIN mes.partida_paso pp ON pp.partida_id = mp.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l   ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
WHERE mp.estado_produccion != 'CANCELADA'
  AND sa.cantidad_disponible > 0
  AND NOT EXISTS (
      SELECT 1 FROM inventario.item_movimientos im
      WHERE im.documento_tipo = 'entrega' AND im.lote_id = l.id
  )
GROUP BY COALESCE(mp.partida_origen_id, mp.id), p.guia, t.nombre,
         (t.nombre ILIKE '%MLR%' OR t.nombre ILIKE '%Oswaldo%' OR t.procedencia = 'MLR')
ORDER BY motivo_restante, legacy_partida_id;

-- 2e. Dyed output rolls in stock that DO have an egress movement (stock imbalance check)
--     These appear in stock views but have a dispatch movement — investigate if non-empty.
SELECT
    l.id                          AS lote_id,
    COALESCE(mp.partida_origen_id, mp.id) AS legacy_partida_id,
    imt.codigo                    AS mov_tipo,
    im.documento_tipo             AS mov_doc_tipo,
    im.observacion                AS mov_obs,
    sa.cantidad_disponible        AS qty_en_stock,
    im.cantidad                   AS qty_egresada,
    im.fecha_hora                 AS fecha_mov
FROM mes.partida mp
JOIN mes.partida_paso pp ON pp.partida_id = mp.id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
JOIN inventario.lote l ON l.documento_tipo = 'partida_paso_ejecucion' AND l.documento_id = pe.id
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id AND sa.cantidad_disponible > 0
JOIN inventario.item_movimientos im ON im.lote_id = l.id AND im.documento_tipo = 'entrega'
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE mp.estado_produccion != 'CANCELADA'
ORDER BY l.id, im.fecha_hora
LIMIT 50;

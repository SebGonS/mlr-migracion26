-- ============================================================================
-- FINISHER · Migrate remaining partida.guia → doc.entrega headers
-- ============================================================================
-- WHAT: the separable guias were already migrated (their lotes now point at a
--   doc.entrega). What's LEFT are the rolls still stranded on the placeholder
--   anchor `lote.documento_tipo='PARTIDA'` — the composites and the MLR/Oswaldo
--   us-owned partidas. The client wants the guia column preserved, so we derive a
--   serie/correlativo from it (isolate when a doc number is clear, else dump whole
--   into correlativo) and give every remaining roll a CLIENTE_ENVIO_PROCESO header.
--
-- DECISIONS (deliberate, per owner):
--   · PRESERVE the meaningful part of the guia — isolate serie+correlativo when a
--     document number is recognizable, else dump the whole tag into correlativo:
--       T003-0297 / EG07-72 / B182-01 / FB182-01  → serie=prefix, correlativo=digits
--       F204                                       → serie=F,      correlativo=204
--       2555 / 698-699 / 182/01 / REPROCESOS / …   → serie='00',  correlativo=<whole>
--       0 / 0000 / - / NULL                        → HEADLESS (serie+correlativo NULL)
--     No token-dropping: composites/free-text kept verbatim. serie='00' sentinel
--     matches the earlier migration's convention for plain-numeric guias (and the
--     CHECK forbids a correlativo with NULL serie anyway).
--   · DEDUP: one entrega per (tercero, serie, correlativo) — repeats REUSE the
--     header. These migrated entregas are a compatibility TAG only; they lack the
--     line-level grain real (post-go-live) entregas carry — that is expected.
--   · MLR/Oswaldo us-owned partidas: same treatment (forced into entrega, not OS).
--
-- SCOPE: driven ENTIRELY by `lote.documento_tipo='PARTIDA'`. Already-migrated
--   rolls (documento_tipo='entrega') self-exclude. Idempotent: a second run finds
--   nothing left on 'PARTIDA'.
--
-- PER ROLL (mirrors ingreso_rollos_guia_bulk Mode-B + migration-11 §1936 lote flip):
--   1. lote           : documento_tipo 'PARTIDA' → 'entrega', documento_id → entrega
--   2. lote_rollo_detalle(lote_id, entrega_id)   — billing anchor
--   3. entrega_detalle(entrega_id, linea, item_id, lote_id, cantidad, n_rollos)
--        (explicit running `linea` — UNIQUE(entrega_id, linea) would reject default 1)
--   4. re-stamp the PARTIDA ingreso movement → 'entrega'
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- ── Section 0 · DRY RUN — sizing ──────────────────────────────────────────────
WITH parts AS (
    SELECT mp.id AS partida_id, mp.tercero_id,
           NULLIF(TRIM(pub.guia), '') AS guia_clean
    FROM mes.partida mp
    JOIN public.partida pub ON pub.id = mp.id
    WHERE EXISTS (SELECT 1 FROM inventario.lote l
                  WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = mp.id)
)
SELECT
    (SELECT COUNT(*) FROM parts)                                              AS partidas_to_process,
    (SELECT COUNT(*) FROM parts WHERE guia_clean IS NOT NULL
        AND (guia_clean ~ '[,/]' OR (guia_clean ~ '-' AND guia_clean ~ '^[0-9]')))
                                                                             AS with_composite_guia,
    (SELECT COUNT(*) FROM parts WHERE guia_clean IS NULL)                     AS headless_no_guia,
    -- distinct headers that will exist (dedup on tercero+guia for the non-null set)
    (SELECT COUNT(DISTINCT (tercero_id, guia_clean)) FROM parts WHERE guia_clean IS NOT NULL)
                                                                             AS distinct_headers_with_guia,
    -- collisions = partidas sharing a (tercero, guia) → will reuse one header
    (SELECT COUNT(*) - COUNT(DISTINCT (tercero_id, guia_clean))
        FROM parts WHERE guia_clean IS NOT NULL)                             AS reuse_collisions,
    (SELECT COUNT(*) FROM inventario.lote l
        WHERE l.documento_tipo = 'PARTIDA'
          AND l.documento_id IN (SELECT partida_id FROM parts))              AS lotes_to_move,
    -- anchor state of those lotes (they already carry a lote_rollo_detalle row):
    (SELECT COUNT(*) FROM inventario.lote l
        LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
        WHERE l.documento_tipo = 'PARTIDA' AND lrd.lote_id IS NULL)          AS lotes_missing_lrd,
    (SELECT COUNT(*) FROM inventario.lote l
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
        WHERE l.documento_tipo = 'PARTIDA' AND lrd.entrega_id IS NULL)       AS anchor_null_to_fill,
    (SELECT COUNT(*) FROM inventario.lote l
        JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
        WHERE l.documento_tipo = 'PARTIDA' AND lrd.entrega_id IS NOT NULL)   AS already_anchored_SKIP,
    (SELECT COUNT(*) FROM doc.entrega_detalle ed
        JOIN inventario.lote l ON l.id = ed.lote_id
        WHERE l.documento_tipo = 'PARTIDA')                                  AS already_has_line,
    (SELECT COUNT(*) FROM inventario.item_movimientos im
        WHERE im.documento_tipo = 'PARTIDA'
          AND im.documento_id IN (SELECT partida_id FROM parts))             AS partida_movements_to_restamp;


-- ── §0b · PARSE PREVIEW — validate the serie/correlativo derivation ───────────
-- Same ladder as §1, expressed in SQL. First the bucket split, then samples so you
-- can eyeball how real guias map before committing.
WITH g AS (
    SELECT DISTINCT NULLIF(TRIM(pub.guia), '') AS guia
    FROM mes.partida mp
    JOIN public.partida pub ON pub.id = mp.id
    WHERE EXISTS (SELECT 1 FROM inventario.lote l
                  WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = mp.id)
),
d AS (
    SELECT guia,
        CASE
            WHEN guia IS NULL OR upper(guia) = 'NULL' OR guia ~ '^[0\- ]+$' THEN 'headless'
            WHEN guia ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'                     THEN 'isolated_dash'
            WHEN guia ~ '^[A-Za-z]+[0-9]+$'                                 THEN 'isolated_alnum'
            ELSE 'dumped_00'
        END AS bucket,
        CASE
            WHEN guia IS NULL OR upper(guia) = 'NULL' OR guia ~ '^[0\- ]+$' THEN NULL
            WHEN guia ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'                     THEN split_part(guia,'-',1)
            WHEN guia ~ '^[A-Za-z]+[0-9]+$'          THEN (regexp_match(guia,'^([A-Za-z]+)([0-9]+)$'))[1]
            ELSE '00'
        END AS d_serie,
        CASE
            WHEN guia IS NULL OR upper(guia) = 'NULL' OR guia ~ '^[0\- ]+$' THEN NULL
            WHEN guia ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'                     THEN split_part(guia,'-',2)
            WHEN guia ~ '^[A-Za-z]+[0-9]+$'          THEN (regexp_match(guia,'^([A-Za-z]+)([0-9]+)$'))[2]
            ELSE guia
        END AS d_correlativo
    FROM g
)
SELECT bucket, COUNT(*) AS distinct_guias FROM d GROUP BY bucket ORDER BY 2 DESC;
-- sample rows (uncomment to inspect the actual mapping):
-- SELECT bucket, guia, d_serie, d_correlativo FROM d ORDER BY bucket, guia LIMIT 100;


-- ── Section 1 · Execute ───────────────────────────────────────────────────────
-- Long op (~100k rolls + per-row audit triggers). The whole DO block is ONE
-- statement, so statement_timeout applies to all of it — lift it. Work SET-BASED
-- per partida (4 bulk statements) instead of 100k per-roll iterations.
SET statement_timeout = 0;
BEGIN;

DO $$
DECLARE
    v_tipo_id       SMALLINT;
    v_mov_tipo_id   SMALLINT;   -- resolved for parity; movements re-stamped, not re-posted
    p               RECORD;
    v_g             TEXT;
    v_m             TEXT[];
    v_serie         TEXT;
    v_correlativo   TEXT;
    v_entrega_id    BIGINT;
    v_base_linea    INT;
    v_n_part        INT := 0;
BEGIN
    SELECT grt.id, grt.item_movimiento_tipo_id
    INTO STRICT v_tipo_id, v_mov_tipo_id
    FROM doc.entrega_tipo grt
    WHERE grt.codigo = 'CLIENTE_ENVIO_PROCESO';

    FOR p IN
        SELECT mp.id AS partida_id, mp.tercero_id,
               NULLIF(TRIM(pub.guia), '')            AS guia_clean,
               COALESCE(mp.fyh_cre, now())           AS fecha_emision
        FROM mes.partida mp
        JOIN public.partida pub ON pub.id = mp.id
        WHERE EXISTS (SELECT 1 FROM inventario.lote l
                      WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = mp.id)
        ORDER BY mp.id
    LOOP
        -- derive serie/correlativo from the legacy guia, preserving the meaningful
        -- part (see DECISIONS header). Isolate serie+correlativo for recognizable
        -- doc numbers; otherwise dump the whole tag into correlativo.
        v_g := p.guia_clean;
        IF v_g IS NULL OR upper(v_g) = 'NULL' OR v_g ~ '^[0\- ]+$' THEN
            v_serie := NULL;  v_correlativo := NULL;                       -- placeholder → headless
        ELSIF v_g ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$' THEN                   -- T003-0297, EG07-72, B182-01, FB182-01
            v_serie       := split_part(v_g, '-', 1);
            v_correlativo := split_part(v_g, '-', 2);
        ELSIF v_g ~ '^[A-Za-z]+[0-9]+$' THEN                              -- F204
            v_m := regexp_match(v_g, '^([A-Za-z]+)([0-9]+)$');
            v_serie := v_m[1];  v_correlativo := v_m[2];
        ELSE                                                              -- numeric / composite / free-text → preserve whole
            v_serie := '00';   v_correlativo := v_g;
        END IF;

        -- header: create, or reuse the shared one (non-null keys only)
        INSERT INTO doc.entrega (entrega_tipo_id, tercero_id, serie, correlativo,
                                 fecha_emision, usr_cre, fyh_cre)
        VALUES (v_tipo_id, p.tercero_id, v_serie, v_correlativo,
                p.fecha_emision, 4, p.fecha_emision)
        ON CONFLICT (tercero_id, serie, correlativo, entrega_tipo_id) DO NOTHING
        RETURNING id INTO v_entrega_id;

        IF v_entrega_id IS NULL THEN   -- collided → reuse (only reachable when keys non-null)
            SELECT id INTO STRICT v_entrega_id
            FROM doc.entrega
            WHERE tercero_id = p.tercero_id AND serie = v_serie
              AND correlativo = v_correlativo AND entrega_tipo_id = v_tipo_id;
        END IF;

        SELECT COALESCE(MAX(linea), 0) INTO v_base_linea
        FROM doc.entrega_detalle WHERE entrega_id = v_entrega_id;

        -- ---- SET-BASED over this partida's PARTIDA rolls (all reads BEFORE the flip) ----
        -- 1. billing anchor: the lrd row already exists (migration-11) — fill entrega_id
        --    where NULL; the ~397 truly-missing rows get inserted. Never clobber.
        INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id, usr_cre)
        SELECT l.id, v_entrega_id, 4
        FROM inventario.lote l
        WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = p.partida_id
        ON CONFLICT (lote_id) DO UPDATE
            SET entrega_id = COALESCE(inventario.lote_rollo_detalle.entrega_id, EXCLUDED.entrega_id),
                usr_mod = 4, fyh_mod = now()
            WHERE inventario.lote_rollo_detalle.entrega_id IS NULL;

        -- 2. entrega lines: one per roll, running linea = base + row_number()
        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, lote_id, cantidad, n_rollos)
        SELECT v_entrega_id,
               (v_base_linea + row_number() OVER (ORDER BY l.id))::smallint,
               l.item_id, l.id, l.cantidad, 1
        FROM inventario.lote l
        WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = p.partida_id;

        -- 3. re-stamp ONLY the ingreso movements (by partida doc; egresos stay put)
        UPDATE inventario.item_movimientos im
        SET documento_tipo = 'entrega', documento_id = v_entrega_id
        WHERE im.documento_tipo = 'PARTIDA' AND im.documento_id = p.partida_id
          AND im.origen_ubicacion_id IS NULL AND im.destino_ubicacion_id IS NOT NULL;

        -- 4. de-placeholder the lotes LAST (after the reads above)
        UPDATE inventario.lote l
        SET documento_tipo = 'entrega', documento_id = v_entrega_id, usr_mod = 4, fyh_mod = now()
        WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = p.partida_id;

        v_n_part := v_n_part + 1;
    END LOOP;

    RAISE NOTICE 'Done. % partidas routed to entrega headers.', v_n_part;
END;
$$;

-- reset identity seq in case (no-op if untouched)
SELECT setval(pg_get_serial_sequence('doc.entrega',        'id'), (SELECT MAX(id) FROM doc.entrega));
SELECT setval(pg_get_serial_sequence('doc.entrega_detalle','id'), (SELECT MAX(id) FROM doc.entrega_detalle));


-- ── Section 2 · Verify (inspect BEFORE COMMIT) ────────────────────────────────
-- (a) no un-anchored client-roll placeholders remain — expect 0
--     (rolls that already carried a real entrega anchor are intentionally left)
SELECT COUNT(*) AS lotes_still_on_partida_unexpected
FROM inventario.lote l
WHERE l.documento_tipo = 'PARTIDA'
  AND NOT EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle lrd
                  WHERE lrd.lote_id = l.id AND lrd.entrega_id IS NOT NULL);

-- (b) every moved lote now has its billing anchor — expect 0 missing
SELECT COUNT(*) AS moved_lotes_missing_lrd
FROM inventario.lote l
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE l.documento_tipo = 'entrega' AND lrd.lote_id IS NULL
  AND l.usr_mod = 4;   -- restrict to rows this script touched

-- (c) no INGRESO left on PARTIDA for de-placeholdered lotes — expect 0.
--     Egresos are DELIBERATELY left on PARTIDA (informational count too).
SELECT
  COUNT(*) FILTER (WHERE im.origen_ubicacion_id IS NULL
                    AND im.destino_ubicacion_id IS NOT NULL) AS ingreso_still_on_partida_expect0,
  COUNT(*) FILTER (WHERE im.origen_ubicacion_id IS NOT NULL) AS egreso_left_on_partida_informational
FROM inventario.item_movimientos im
JOIN inventario.lote l ON l.id = im.lote_id AND l.documento_tipo = 'entrega'
WHERE im.documento_tipo = 'PARTIDA';

-- (d) header/line spot-check
SELECT e.id AS entrega_id, e.serie, e.correlativo, t.nombre AS tercero,
       COUNT(ed.id) AS lineas
FROM doc.entrega e
JOIN tercero t ON t.id = e.tercero_id
JOIN doc.entrega_detalle ed ON ed.entrega_id = e.id
WHERE e.serie = '00' AND e.usr_cre = 4
GROUP BY e.id, e.serie, e.correlativo, t.nombre
ORDER BY e.id DESC
LIMIT 25;

-- COMMIT;    -- ← after §2: (a)=0, (b)=0, (c)=0
-- ROLLBACK;  -- ← if anything is off


SELECT
  COUNT(*) FILTER (WHERE origen_ubicacion_id IS NULL  AND destino_ubicacion_id IS NOT NULL) AS ingreso,
  COUNT(*) FILTER (WHERE origen_ubicacion_id IS NOT NULL AND destino_ubicacion_id IS NULL)  AS egreso,
  COUNT(*) FILTER (WHERE origen_ubicacion_id IS NOT NULL AND destino_ubicacion_id IS NOT NULL) AS transfer
FROM inventario.item_movimientos
WHERE documento_tipo = 'PARTIDA';



SELECT imt.codigo, COUNT(*)
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'PARTIDA'
  AND im.origen_ubicacion_id IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;




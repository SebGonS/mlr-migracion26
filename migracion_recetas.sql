-- ═══════════════════════════════════════════════════════════════
-- DATA MIGRATION: public.receta* → receta schema
--
-- Prerequisites:
--   1. recetas.sql has been run (receta schema + tables created + seeded)
--   2. item.legacy_id is populated (insumo → item migration done)
--   3. articulo table populated (articulo_tipo_id + fibra rows exist)
--   4. Old public.receta* tables still exist in source DB
--
-- Assumptions about old column names (from DDL migration comments):
--   receta2                        : tipo_articulo_id, fibra, flg_produccion, flg_activo
--   receta_paso                    : receta_id, receta_operacion_id, orden, ph, temperatura, tiempo_min, nota
--   receta_paso_insumo             : receta_paso_id, insumo_id, cantidad  (orden generated if missing)
--   receta_lavado_maquina_paso     : receta_lavado_maquina_id, receta_operacion_id, orden, ph, temperatura, tiempo_min, nota
--   receta_lavado_maquina_paso_insumo: receta_lavado_maquina_paso_id, insumo_id, cantidad  (orden generated if missing)
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- PRE-MIGRATION PREP: Stage parsed values into public.receta_paso
--
-- Run these steps BEFORE the BEGIN block below.
-- They add four staging columns to the source table, auto-populate
-- them via regex, then let you manually review and correct any NULLs.
-- ═══════════════════════════════════════════════════════════════

-- ── Step 1: Add staging columns ──────────────────────────────────
ALTER TABLE public.receta_paso
    ADD COLUMN IF NOT EXISTS op_id      SMALLINT,
    ADD COLUMN IF NOT EXISTS ph_val     NUMERIC(4,2),
    ADD COLUMN IF NOT EXISTS temp_val   NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS tiempo_val SMALLINT;

-- ── Step 2: Auto-populate via CASE + regex ───────────────────────
UPDATE public.receta_paso SET
    op_id = CASE
        -- TINTURA / TEÑIDO family (check before LAVADO to catch combined steps)
        WHEN unaccent(upper(paso)) LIKE '%TINTURA%'
          OR unaccent(upper(paso)) LIKE '%TENIDO%'
          OR unaccent(upper(paso)) LIKE '%TENIR%'
          OR unaccent(upper(paso)) LIKE '%TNTURA%'             THEN 1  -- TINTURA
        WHEN unaccent(upper(paso)) LIKE '%LAVADO%REDUCTIVO%'   THEN 3  -- LAVADO_REDUCTIVO
        WHEN unaccent(upper(paso)) LIKE '%BLANQUEO%OPTICO%'    THEN 5  -- BLANQUEO_OPTICO
        WHEN unaccent(upper(paso)) LIKE '%BLANQUEO%'
          OR unaccent(upper(paso)) LIKE 'B.QUIM%'              THEN 4  -- BLANQUEO_QUIMICO
        WHEN unaccent(upper(paso)) LIKE '%LAVADO%'             THEN 2  -- LAVADO
        WHEN unaccent(upper(paso)) LIKE '%DESCRUDE%'           THEN 6  -- DESCRUDE
        WHEN unaccent(upper(paso)) LIKE '%NEUTRALIZA%'         THEN 7  -- NEUTRALIZADO
        WHEN unaccent(upper(paso)) LIKE '%FIJADO%'             THEN 9  -- FIJADO
        WHEN unaccent(upper(paso)) LIKE '%SUAVIZADO%'
          OR unaccent(upper(paso)) LIKE '%SUAVIZANTE%'         THEN 8  -- SUAVIZADO
        WHEN unaccent(upper(paso)) LIKE '%JABONADO%'           THEN 10 -- JABONADO
        WHEN unaccent(upper(paso)) LIKE '%ENJUAGUE%'           THEN 11 -- ENJUAGUE
        WHEN unaccent(upper(paso)) LIKE '%MATIZ%'              THEN 12 -- MATIZADO
        WHEN unaccent(upper(paso)) LIKE '%ANTIPILLING%'        THEN 13 -- ANTIPILLING
        WHEN unaccent(upper(paso)) LIKE '%SIMULTANEO%'         THEN 15 -- SIMULTANEO
        WHEN unaccent(upper(paso)) LIKE '%REGULAR%PH%'
          OR unaccent(upper(paso)) LIKE '%REGULACION%PH%'
          OR unaccent(upper(paso)) LIKE '%REGULANDO%PH%'
          OR unaccent(upper(paso)) LIKE '%REGULO%PH%'
          OR unaccent(upper(paso)) LIKE 'CHECK%PH%'
          OR unaccent(upper(paso)) LIKE '%NO REGULAR%'         THEN 14 -- REGULACION_PH
        WHEN unaccent(upper(paso)) LIKE '%DESMONTADO%'
          OR unaccent(upper(paso)) LIKE '%ELIMINACI%'          THEN 16 -- DESMONTADO
        WHEN unaccent(upper(paso)) LIKE '%REBAJE%'             THEN 17 -- REBAJE
        ELSE NULL  -- unmappable rows get skipped in the final INSERT
    END,
    ph_val    = (regexp_match(upper(paso), 'PH\s*[=:]?\s*(\d+(?:[.,]\d+)?)'))[1]::numeric(4,2),
    temp_val  = (regexp_match(paso, '(\d{2,3})\s*[°º]'))[1]::numeric(5,2),
    tiempo_val = COALESCE(
        ( (regexp_match(lower(paso), '(\d+):(\d+)\s*min'))[1]::smallint * 60
        + (regexp_match(lower(paso), '(\d+):(\d+)\s*min'))[2]::smallint ),
        (regexp_match(lower(paso), '(\d+)\s*hora'))[1]::smallint * 60,
        (regexp_match(lower(paso), '(\d+)\s*min'))[1]::smallint,
        (regexp_match(paso, $$(\d+)\s*'$$))[1]::smallint
    );

-- ── Step 3: Diagnostics — run these and review before proceeding ──
-- After Step 2, check how many rows have no op_id:
--   SELECT COUNT(*) FROM public.receta_paso WHERE op_id IS NULL;
--   -- Aim for 0 or only genuinely unmappable rows (e.g. 'Paso Test').
--
-- Full mapping review (every distinct paso and what it resolved to):
--   SELECT DISTINCT paso, op_id, ph_val, temp_val, tiempo_val
--   FROM public.receta_paso
--   ORDER BY op_id NULLS LAST, paso;

-- ── Step 4: Manual corrections — add UPDATE rows here as needed ───
-- After reviewing Step 3, fix anything wrong or still NULL:
--   UPDATE public.receta_paso SET op_id = 14 WHERE paso = 'A 80°C REGULO PH 10.8';
--   UPDATE public.receta_paso SET op_id = 2  WHERE paso = 'LAVADO DE MAQUINA 98° X 45 MIN';
-- Rows intentionally left as NULL will be skipped in the final INSERT.

-- ═══════════════════════════════════════════════════════════════
-- END PRE-MIGRATION PREP — run Steps 1–4 above, verify, then run below
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────
-- 1. receta.tenido
--    OVERRIDING SYSTEM VALUE: preserves original IDs from receta2
--    articulo_id: derived via articulo.articulo_tipo_id + articulo.fibra
--    estado_id:   derived from dual-boolean (flg_produccion / flg_activo)
--    flg_produccion: trigger (trg_bi_receta_tenido_flg_produccion) sets it on INSERT
-- ───────────────────────────────────────

INSERT INTO receta.tenido (
    id,
    color_x_cliente_id,
    articulo_tipo_id,
    fibra,
    tenido_id,
    flg_antipilling,
    tipo_receta_id,
    estado_id,
    fyh_produccion,
    usr_cre, fyh_cre,
    usr_mod, fyh_mod
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (r.color_x_cliente_id, r.tipo_articulo_id, r.fibra, r.tenido_id, r.flg_antipilling)
    r.id,
    r.color_x_cliente_id,
    r.tipo_articulo_id,
    r.fibra,
    r.tenido_id,
    r.flg_antipilling,
    r.tipo_receta_id,
    CASE
        WHEN r.flg_produccion = true
            THEN (SELECT id FROM estado_desarrollo_color WHERE codigo = 'APROBADO')
        WHEN r.flg_activo = true
            THEN (SELECT id FROM estado_desarrollo_color WHERE codigo = 'EN_DESARROLLO')
        ELSE
            (SELECT id FROM estado_desarrollo_color WHERE codigo = 'CANCELADO')
    END AS estado_id,
    r.fyh_produccion,
    CASE WHEN r.usr_cre NOT IN ('authenticated','anon','postgres') THEN r.usr_cre::integer ELSE NULL END,
    r.fyh_cre,
    CASE WHEN r.usr_mod NOT IN ('authenticated','anon','postgres') THEN r.usr_mod::integer ELSE NULL END,
    r.fyh_mod
FROM public.receta2 r
ORDER BY r.color_x_cliente_id, r.tipo_articulo_id, r.fibra, r.tenido_id, r.flg_antipilling, r.id DESC;
-- NOTE: no flg_elm filter on receta2 — add "WHERE r.flg_elm = false" if that column exists

SELECT setval(
    pg_get_serial_sequence('receta.tenido', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.tenido), 1)
);


-- ───────────────────────────────────────
-- 2. receta.tenido_paso
--    Reads op_id, ph_val, temp_val, tiempo_val from staging columns populated
--    during PRE-MIGRATION PREP (Steps 1–4 above the BEGIN block).
--    Rows with op_id IS NULL are skipped (intentionally unmappable pasos).
-- ───────────────────────────────────────

INSERT INTO receta.tenido_paso (
    id,
    receta_id,
    operacion_id,
    orden,
    ph,
    temperatura,
    tiempo_min,
    nota
)
OVERRIDING SYSTEM VALUE
SELECT
    rp.id,
    rp.receta_id,
    rp.op_id        AS operacion_id,
    rp.orden,
    rp.ph_val       AS ph,
    rp.temp_val     AS temperatura,
    rp.tiempo_val   AS tiempo_min,
    rp.paso         AS nota
FROM public.receta_paso rp
WHERE rp.op_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM receta.tenido WHERE id = rp.receta_id);

SELECT setval(
    pg_get_serial_sequence('receta.tenido_paso', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.tenido_paso), 1)
);


-- ───────────────────────────────────────
-- 3. receta.tenido_paso_insumo
--    paso_id:  old receta_paso_id (IDs preserved, maps directly)
--    item_id:  resolved via item.legacy_id = insumo_id
--    orden:    preserved from source
-- ───────────────────────────────────────

INSERT INTO receta.tenido_paso_insumo (
    id,
    paso_id,
    item_id,
    cantidad,
    orden
)
OVERRIDING SYSTEM VALUE
SELECT
    rpi.id,
    rpi.receta_paso_id              AS paso_id,
    it.id                           AS item_id,
    rpi.cantidad,
    rpi.orden
FROM public.receta_paso_insumo rpi
JOIN item it ON it.legacy_id = rpi.insumo_id
WHERE EXISTS (SELECT 1 FROM receta.tenido_paso WHERE id = rpi.receta_paso_id);
-- NOTE: insumos whose insumo_id has no item.legacy_id match are silently dropped.
-- Check first: SELECT insumo_id FROM public.receta_paso_insumo
--   WHERE NOT EXISTS (SELECT 1 FROM item WHERE legacy_id = insumo_id);

SELECT setval(
    pg_get_serial_sequence('receta.tenido_paso_insumo', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.tenido_paso_insumo), 1)
);


-- ───────────────────────────────────────
-- 4. receta.lavado_maquina
-- ───────────────────────────────────────

INSERT INTO receta.lavado_maquina (
    id,
    tipo_lavado_mq_id,
    valor_origen_id,
    valor_destino_id,
    flg_activo,
    usr_cre, fyh_cre,
    usr_mod, fyh_mod
)
OVERRIDING SYSTEM VALUE
SELECT
    rlm.id,
    rlm.tipo_lavado_mq_id,
    rlm.valor_origen_id,
    rlm.valor_destino_id,
    rlm.flg_activo,
    rlm.usr_cre, rlm.fyh_cre,
    rlm.usr_mod, rlm.fyh_mod
FROM public.receta_lavado_maquina rlm;

SELECT setval(
    pg_get_serial_sequence('receta.lavado_maquina', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.lavado_maquina), 1)
);


-- ───────────────────────────────────────
-- 5. receta.lavado_maquina_paso
-- ───────────────────────────────────────

INSERT INTO receta.lavado_maquina_paso (
    id,
    receta_id,
    operacion_id,
    orden,
    ph,
    temperatura,
    tiempo_min,
    nota
)
OVERRIDING SYSTEM VALUE
SELECT
    rlmp.id,
    rlmp.receta_lavado_maquina_id   AS receta_id,
    nop.id                          AS operacion_id,
    rlmp.orden,
    rlmp.ph,
    rlmp.temperatura,
    rlmp.tiempo_min,
    rlmp.nota
FROM public.receta_lavado_maquina_paso rlmp
JOIN public.receta_operacion  ro  ON ro.id      = rlmp.receta_operacion_id
JOIN receta.operacion         nop ON nop.codigo  = ro.codigo
WHERE EXISTS (SELECT 1 FROM receta.lavado_maquina WHERE id = rlmp.receta_lavado_maquina_id);

SELECT setval(
    pg_get_serial_sequence('receta.lavado_maquina_paso', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.lavado_maquina_paso), 1)
);


-- ───────────────────────────────────────
-- 6. receta.lavado_maquina_paso_insumo
--    orden: preserved from source
-- ───────────────────────────────────────

INSERT INTO receta.lavado_maquina_paso_insumo (
    id,
    paso_id,
    item_id,
    cantidad,
    orden
)
OVERRIDING SYSTEM VALUE
SELECT
    rlmpi.id,
    rlmpi.receta_lavado_maquina_paso_id  AS paso_id,
    it.id                                AS item_id,
    rlmpi.cantidad,
    rlmpi.orden
FROM public.receta_lavado_maquina_paso_insumo rlmpi
JOIN item it ON it.legacy_id = rlmpi.insumo_id
WHERE EXISTS (SELECT 1 FROM receta.lavado_maquina_paso WHERE id = rlmpi.receta_lavado_maquina_paso_id);

SELECT setval(
    pg_get_serial_sequence('receta.lavado_maquina_paso_insumo', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.lavado_maquina_paso_insumo), 1)
);


-- ═══════════════════════════════════════════════════════════════
-- VERIFY (run before COMMIT)
-- ═══════════════════════════════════════════════════════════════

-- Row count sanity check
SELECT 'receta.tenido'                  AS tabla, COUNT(*) FROM receta.tenido
UNION ALL
SELECT 'receta.tenido_paso'             , COUNT(*) FROM receta.tenido_paso
UNION ALL
SELECT 'receta.tenido_paso_insumo'      , COUNT(*) FROM receta.tenido_paso_insumo
UNION ALL
SELECT 'receta.lavado_maquina'          , COUNT(*) FROM receta.lavado_maquina
UNION ALL
SELECT 'receta.lavado_maquina_paso'     , COUNT(*) FROM receta.lavado_maquina_paso
UNION ALL
SELECT 'receta.lavado_maquina_paso_insumo', COUNT(*) FROM receta.lavado_maquina_paso_insumo;

-- tenido rows with no matching articulo_tipo (need manual review)
SELECT id, tipo_articulo_id, fibra
FROM public.receta2 r
WHERE NOT EXISTS (SELECT 1 FROM articulo_tipo WHERE id = r.tipo_articulo_id);

-- insumos that didn't resolve to an item (dropped from migration)
SELECT 'tenido_paso_insumo orphans', COUNT(*)
FROM public.receta_paso_insumo
WHERE NOT EXISTS (SELECT 1 FROM item WHERE legacy_id = insumo_id)
UNION ALL
SELECT 'lavado_maquina_paso_insumo orphans', COUNT(*)
FROM public.receta_lavado_maquina_paso_insumo
WHERE NOT EXISTS (SELECT 1 FROM item WHERE legacy_id = insumo_id);

COMMIT;

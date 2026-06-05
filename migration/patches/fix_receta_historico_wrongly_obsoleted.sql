-- ─────────────────────────────────────────────────────────────────────
-- PATCH: fix unique index + restore wrongly-obsoleted APROBADO recipes
--
-- Root cause (two-part):
--   1. transicionar_tenido's HISTORICO-swap was missing tipo_receta_id
--      (fixed in funciones/receta.sql).
--   2. The partial unique index uq_receta_tenido_aprobada also omitted
--      tipo_receta_id, so the DB only allowed one APROBADO recipe per
--      base spec regardless of type — consistent with the buggy function,
--      but wrong for the intended design where each (spec + tipo_receta_id)
--      manages its own approval lifecycle independently.
--
-- This patch must run AFTER funciones/receta.sql has been redeployed.
--
-- Steps:
--   0. Preview candidates before touching anything
--   1. Drop the narrow unique index
--   2. Restore wrongly-obsoleted APROBADO recipes
--   3. Create the corrected unique index (now includes tipo_receta_id)
-- ─────────────────────────────────────────────────────────────────────


-- Step 0: preview — shows exactly the rows that Step 2 will restore (one per bucket).
-- Run this first. After the index is fixed each row must be the sole
-- flg_produccion = true entry for its (spec + tipo_receta_id) — verify manually.
WITH candidates AS (
    SELECT
        t.id,
        t.color_x_cliente_id,
        t.articulo_tipo_id,
        t.fibra,
        t.tenido_id,
        t.flg_antipilling,
        t.tipo_receta_id,
        t.fyh_produccion,
        t.fyh_mod,
        ROW_NUMBER() OVER (
            PARTITION BY
                t.color_x_cliente_id,
                t.articulo_tipo_id,
                t.fibra,
                t.tenido_id,
                t.flg_antipilling,
                t.tipo_receta_id
            ORDER BY t.fyh_produccion DESC NULLS LAST
        ) AS rn
    FROM receta.tenido t
    JOIN public.estado_desarrollo_color e ON e.id = t.estado_id
    WHERE e.codigo = 'HISTORICO'
      AND t.fyh_produccion IS NOT NULL
      AND t.fyh_mod        IS NOT NULL  -- bug always sets fyh_mod; NULL means a different path
      AND NOT EXISTS (
          SELECT 1
          FROM receta.tenido t2
          JOIN public.estado_desarrollo_color e2 ON e2.id = t2.estado_id
          WHERE t2.color_x_cliente_id = t.color_x_cliente_id
            AND t2.articulo_tipo_id   = t.articulo_tipo_id
            AND t2.fibra              = t.fibra
            AND t2.tenido_id          = t.tenido_id
            AND t2.flg_antipilling    = t.flg_antipilling
            AND t2.tipo_receta_id     IS NOT DISTINCT FROM t.tipo_receta_id
            AND e2.codigo NOT IN ('HISTORICO', 'CANCELADO', 'RECHAZADO')
      )
)
SELECT
    c.id,
    c.color_x_cliente_id,
    c.articulo_tipo_id,
    c.fibra,
    c.tenido_id,
    c.flg_antipilling,
    c.tipo_receta_id,
    tr.tipo_receta AS tipo_receta_nombre,
    c.fyh_produccion,
    c.fyh_mod
FROM candidates c
LEFT JOIN public.tipo_receta tr ON tr.id = c.tipo_receta_id
WHERE c.rn = 1
ORDER BY c.tipo_receta_id, c.fyh_produccion DESC;


-- Steps 1–3: apply — run as a single transaction.
BEGIN;

-- Step 1: drop the narrow index so the restoration UPDATE can succeed.
DROP INDEX receta.uq_receta_tenido_aprobada;

-- Step 2: restore the most recently approved per orphaned (spec + tipo_receta_id) bucket.
DO $$
DECLARE
    v_aprobado_id SMALLINT;
    v_restored    INT := 0;
BEGIN
    SELECT id INTO v_aprobado_id
    FROM public.estado_desarrollo_color
    WHERE codigo = 'APROBADO';

    WITH candidates AS (
        SELECT
            t.id,
            ROW_NUMBER() OVER (
                PARTITION BY
                    t.color_x_cliente_id,
                    t.articulo_tipo_id,
                    t.fibra,
                    t.tenido_id,
                    t.flg_antipilling,
                    t.tipo_receta_id
                ORDER BY t.fyh_produccion DESC NULLS LAST
            ) AS rn
        FROM receta.tenido t
        JOIN public.estado_desarrollo_color e ON e.id = t.estado_id
        WHERE e.codigo = 'HISTORICO'
          AND t.fyh_produccion IS NOT NULL
          AND t.fyh_mod        IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM receta.tenido t2
              JOIN public.estado_desarrollo_color e2 ON e2.id = t2.estado_id
              WHERE t2.color_x_cliente_id = t.color_x_cliente_id
                AND t2.articulo_tipo_id   = t.articulo_tipo_id
                AND t2.fibra              = t.fibra
                AND t2.tenido_id          = t.tenido_id
                AND t2.flg_antipilling    = t.flg_antipilling
                AND t2.tipo_receta_id     IS NOT DISTINCT FROM t.tipo_receta_id
                AND e2.codigo NOT IN ('HISTORICO', 'CANCELADO', 'RECHAZADO')
          )
    ),
    restored AS (
        UPDATE receta.tenido t
        SET estado_id      = v_aprobado_id,
            flg_produccion = true,
            fyh_mod        = now()
        FROM candidates c
        WHERE t.id = c.id
          AND c.rn = 1
        RETURNING t.id
    )
    SELECT COUNT(*) INTO v_restored FROM restored;

    RAISE NOTICE 'Restored % recipe(s) to APROBADO.', v_restored;
END;
$$;

-- Step 3: recreate the index with tipo_receta_id included.
-- NULL-safe: two NULLs are treated as equal by partial unique indexes in Postgres,
-- so recipes without a tipo_receta_id still get a unique APROBADO slot per base spec.
CREATE UNIQUE INDEX uq_receta_tenido_aprobada
    ON receta.tenido(color_x_cliente_id, articulo_tipo_id, fibra, tenido_id, flg_antipilling, tipo_receta_id)
    WHERE flg_produccion = true;

COMMIT;



SELECT * FROM receta.tenido t where t.id IN (6740,3911)


Select * from vw_partidas_resumen where estado in ('Pendiente Receta', 'Pendiente Termofijar','Para Programar')



 UPDATE mes.partida
 SET estado_produccion ='PLANIFICADA'
    WHERE id IN (Select partida from vw_partidas_resumen where estado in 
    ('Pendiente Receta', 'Pendiente Termofijar','Para Programar') and cliente <> 'Fredy Gaytan')
    and mes.partida.estado_produccion != 'PLANIFICADA';

-- Step 1: verify
-- Step 2: revert (run only after step 1 confirms the right rows)
UPDATE mes.partida p
SET estado_produccion = (a.old_data->>'estado_produccion')::mes.estado_produccion
FROM audit.data_audit a
JOIN public.tercero t ON t.id = (a.old_data->>'tercero_id')::int
WHERE a.table_name = 'partida'
  AND a.schema_name = 'mes'
  AND a.operacion = 'UPDATE'
  AND a.fyh_evento = '2026-06-02 15:55:03.59658+00'
  AND t.nombre ILIKE '%Fredy%Gaytan%'
  AND p.id = a.row_id;


SELECT inventario.get_movimientos_item(27);
SELECT get_insumo_movimientos_rango(27, '2024-01-01', '2026-12-31');

-- Count AJUSTE_POS entries in new system vs reconteos in legacy
SELECT imt.codigo, COUNT(*), SUM(im.cantidad)
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 27
  AND imt.factor = 1  -- ingress movements only
GROUP BY imt.codigo;
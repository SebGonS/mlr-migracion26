--4595 4588

----ROLLOS LA REAL
BEGIN;
DO $$
DECLARE
    v_peso_kg_por_rollo  NUMERIC := 20.0;   -- ← change nominal kg/roll here

    v_doc_mov_id         BIGINT;
    v_lote_id            INT;
    v_ajuste_pos_id      SMALLINT;
    rec                  RECORD;
    i                    INT;
BEGIN
    -- Resolve AJUSTE_POS type id once
    SELECT id INTO STRICT v_ajuste_pos_id
    FROM inventario.item_movimiento_tipo
    WHERE codigo = 'AJUSTE_POS';

    -- One doc_movimiento_id per partida (groups all roll inserts per partida)
    -- We'll generate two: one for 5237, one for 5238.

    FOR rec IN
        SELECT
            pd.partida_id,
            pd.item_id,
            pd.cantidad::INT AS n_rollos   -- cantidad = roll count in partida_detalle
        FROM mes.partida_detalle pd
        WHERE pd.partida_id IN (4502
,4502
,4452
,4502
,4502)
        ORDER BY pd.partida_id, pd.item_id
    LOOP
        -- New doc_movimiento_id groups all rolls of this (partida, item) together
        v_doc_mov_id := nextval('inventario.mov_doc_seq');

        FOR i IN 1 .. rec.n_rollos LOOP

            -- 1. Create the lote (secuencia auto-assigned by trigger)
            INSERT INTO inventario.lote (
                item_id,
                documento_tipo,   -- 'ajuste' marks manual injection (no real cuadre doc)
                documento_id,
                cantidad,
                propietario_id,   -- NULL = MLR-owned
                usr_cre
            )
            VALUES (
                rec.item_id,
                'PARTIDA',
                rec.partida_id,
                v_peso_kg_por_rollo,
                NULL,
                NULL              -- no user context in batch script
            )
            RETURNING id INTO v_lote_id;

            -- 2. Reserve roll in partida (roll row: item_id NULL, partida_paso_id NULL)
            INSERT INTO mes.partida_componente (
                partida_id,
                lote_id,
                item_id,
                partida_paso_id,
                cantidad_reservada,
                usr_cre
            )
            VALUES (
                rec.partida_id,
                v_lote_id,
                NULL,
                NULL,
                v_peso_kg_por_rollo,
                NULL
            )
ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

            -- 3. Post inventory movement (AJUSTE_POS → stock enters MLR warehouse)
            --    destino_ubicacion_id NULL = no specific bin (adjust if needed)
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id,
                item_id,
                lote_id,
                item_movimiento_tipo_id,
                origen_ubicacion_id,
                destino_ubicacion_id,
                cantidad,
                documento_tipo,
                documento_id,
                observacion,
                usr_cre
            )
            VALUES (
                v_doc_mov_id,
                rec.item_id,
                v_lote_id,
                v_ajuste_pos_id,
                NULL,
                (SELECT id FROM inventario.ubicacion WHERE almacen_id = (SELECT id FROM inventario.almacen WHERE codigo = 'ALM_CRU') LIMIT 1),               -- ← set to your bodega's ubicacion_id if needed
                v_peso_kg_por_rollo,
                'PARTIDA',
                rec.partida_id,
                'Ingreso artificial de rollo MLR propio para partida ' || rec.partida_id,
                NULL
            );

        END LOOP;
    END LOOP;
END;
$$;





-- SELECT * FROM mes.partida_paso WHERE partida_id=4502;

-- Delete existing partida_detalle for 4502, then insert from 4410
-- DELETE FROM mes.partida_detalle WHERE partida_id = 4502;

-- INSERT INTO mes.partida_detalle (partida_id, item_id, cantidad, cantidad_producida, unidad_id, usr_cre, fyh_cre)
-- SELECT 4502, item_id, cantidad, cantidad_producida, unidad_id, usr_cre, fyh_cre
-- FROM mes.partida_detalle
-- WHERE partida_id = 4410;


---Copy outpuit into reservation (componenete)

-- INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada, usr_cre)
-- SELECT 4502, l.id, l.cantidad, l.usr_cre
-- FROM inventario.lote l
-- JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
--                                    AND l.documento_tipo = 'partida_paso_ejecucion'
-- JOIN mes.partida_paso pp            ON pp.id = pe.partida_paso_id
-- WHERE pp.partida_id = 4410
--   AND l.fyh_elm IS NULL
-- ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

-- SELECT l.id, l.cantidad, ird.flg_rib
-- FROM inventario.lote l
-- JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id
--                                    AND l.documento_tipo = 'partida_paso_ejecucion'
-- JOIN mes.partida_paso pp            ON pp.id = pe.partida_paso_id
-- JOIN item_rollo_detalle ird         ON ird.item_id = l.item_id
-- WHERE pp.partida_id = 4410
--   AND l.fyh_elm IS NULL
-- ORDER BY ird.flg_rib, l.id;


--4595,4588
SELECT * FROm mes.partida_paso_ejecucion WHERE partida_paso_id IN
(SELECT id FROM mes.partida_paso WHERe partida_id=4502);
-- UPDATE mes.partida_paso_ejecucion set cantidad=18, fyh_inicio='2026-05-25 16:30:00.00+00', fyh_fin='2026-05-25 17:40:00.00+00' where id=1845
-- DELETE FROM mes.partida_paso_ejecucion WHERE id=1846
-- State of partida 4502 + whether ghost fired on any of its lotes

-- SELECT mes.get_partida(5906)
--check for ghost egress
SELECT
    p.id,
    p.estado_produccion,
    p.estado_comercial,
    l.id            AS lote_id,
    ird.flg_rib,
    l.cantidad,
    EXISTS (
        SELECT 1 FROM inventario.item_movimientos m
        WHERE m.lote_id = l.id
          AND m.item_movimiento_tipo_id = (
              SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_EGR'
          )
    ) AS ghost_fired,
    EXISTS (
        SELECT 1 FROM inventario.item_movimientos m
        WHERE m.lote_id = l.id
          AND m.item_movimiento_tipo_id = (
              SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'
          )
    ) AS prod_consumo_fired
FROM mes.partida p
JOIN inventario.lote l ON l.documento_id = p.id AND l.documento_tipo = 'PARTIDA'
JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
WHERE p.id IN (4595,4588)
GROUP BY 1,2,3,4,5,6,7
ORDER BY ird.flg_rib, l.id;

-- SELECT * FROm inventario.pesaje WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo='PARTIDA' AND documento_id=4502);

--check for ghost egress
SELECT
    p.estado_produccion,
    p.estado_comercial,
    l.id            AS lote_id,
    ird.flg_rib,
    l.cantidad,
    EXISTS (
        SELECT 1 FROM inventario.item_movimientos m
        WHERE m.lote_id = l.id
          AND m.item_movimiento_tipo_id = (
              SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_EGR'
          )
    ) AS ghost_fired,
    EXISTS (
        SELECT 1 FROM inventario.item_movimientos m
        WHERE m.lote_id = l.id
          AND m.item_movimiento_tipo_id = (
              SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'
          )
    ) AS prod_consumo_fired
FROM mes.partida p
JOIN inventario.lote l ON l.documento_id = p.id AND l.documento_tipo = 'PARTIDA'
JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
WHERE p.id = 4588
ORDER BY ird.flg_rib, l.id;

--reverse ghost egress
WITH alm_cru AS (
    SELECT ub.id AS ubicacion_id
    FROM inventario.ubicacion ub
    JOIN inventario.almacen alm ON alm.id = ub.almacen_id
    WHERE alm.codigo = 'ALM_CRU'
    LIMIT 1
),
ghost_egr AS (
    SELECT DISTINCT m.lote_id, m.cantidad, l.item_id, l.usr_cre
    FROM inventario.item_movimientos m
    JOIN inventario.lote l ON l.id = m.lote_id
    WHERE m.documento_tipo  = 'PARTIDA'
      AND m.documento_id    IN (4452,4502,4502,4502)
      AND m.item_movimiento_tipo_id = (
          SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_EGR'
      )
),
doc AS (
    SELECT nextval('inventario.mov_doc_seq') AS doc_movimiento_id
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id,
    item_id,
    lote_id,
    item_movimiento_tipo_id,
    destino_ubicacion_id,
    cantidad,
    documento_tipo,
    documento_id,
    observacion,
    usr_cre,
    fyh_cre,
    fecha_hora
)
SELECT
    doc.doc_movimiento_id,
    ge.item_id,
    ge.lote_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS'),
    alm_cru.ubicacion_id,
    ge.cantidad,
    'PARTIDA',
    4502,
    'Reversión: SERV_EGR fantasma se ejecutó incorrectamente en partida CREADA - restaurando balance para producción',
    ge.usr_cre,
    NOW(),
    NOW()
FROM ghost_egr ge, alm_cru, doc;
SELECT * FROM mes.partida_componente WHERE partida_id=4502;
UPDATE mes.partida_componente 
SET partida_id=4502
WHERE partida_id=4452;

-- UPDATE mes.partida_paso SET operacion_id=2 WHERe partida_id=4502;
-- (4502,4502,4452,4502,4502)
SELECT * FROM mes.partida_paso WHERe partida_id=4502;
SELECT * FROm partida WHERE id=4502;
SELECT * FROm partida_x_recetas WHERE partida_id=4502;
SELECT * FROm produccion_tenido WHERE partida_id=4502;

SELECT * FROm produccion_tenido WHERE partida_id=4502;


(4500,5037,4452,4502,4502)
SELECT * FROm partida_x_recetas WHERE partida_id IN (4502,4502,4452,4502,4502);
SELECT * FROm produccion_tenido WHERE partida_id IN (4502,4502,4452,4502,4502);

INSERT INTO mes.partida_paso(
    partida_id, secuencia, operacion_id, maquina_planificada_id,receta_id)
    SELECT 4502, 1, 2, maquina_id,  receta_id
    FROM partida_x_recetas WHERE partida_id=4502 AND flg_elm = False;

INSERT INTO mes.partida_paso_ejecucion(
    partida_paso_id, cantidad, estado, maquina_id,receta_id, fyh_inicio, fyh_fin)
SELECT 
    (SELECT id FROM mes.partida_paso WHERE partida_id = 4502 AND operacion_id=2),
    (SELECT COUNT(*) FROM mes.partida_componente WHERE partida_id = 4502 AND lote_id IS NOT NULL),
    'EN_PROCESO',
    (SELECT maquina_planificada_id FROM mes.partida_paso WHERE partida_id = 4502 AND operacion_id=2),
    6367,--(SELECT receta_id FROM mes.partida_paso WHERE partida_id = 4502 AND operacion_id=2),
    TIMESTAMPTZ '2026-04-27 14:00:00-05',
    TIMESTAMPTZ '2026-04-27 18:20:00-05'
;


-- UPDATE mes.partida 
-- SET estado_produccion = 'PROGRAMADA', fyh_mod = NOW() 
-- WHERE id = 4502 AND estado_produccion = 'CREADA';

-- UPDATE mes.partida_paso_ejecucion SET 
--     fyh_inicio = TIMESTAMPTZ '2026-03-20 14:10:00-05',
--     fyh_fin    = TIMESTAMPTZ '2026-03-20 23:30:00-05',
--     estado     = 'COMPLETADO'
-- WHERE id IN (
--     SELECT ppe.id FROM mes.partida_paso_ejecucion ppe
--     JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
--     WHERE pp.partida_id = 4502
-- );

----JSON PAYLOAD
-- SELECT jsonb_build_object(
--     'ubicacion_id', (
--         SELECT ub.id FROM inventario.ubicacion ub
--         JOIN inventario.almacen alm ON alm.id = ub.almacen_id
--         WHERE alm.codigo = 'ALM_PT' LIMIT 1
--     ),
--     'peso_rib',    90.6,
--     'output', jsonb_agg(jsonb_build_object('input_lote_id', l.id))
-- )
-- FROM inventario.lote l
-- WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = 4502;

-- SELECT mes.registrar_produccion((SELECT id FROm mes.partida_paso_ejecucion WHERE partida_paso_id IN
-- (SELECT id FROM mes.partida_paso WHERe partida_id=4502)), '{"output": [{"input_lote_id": 122731}, {"input_lote_id": 122732}, {"input_lote_id": 122733}, {"input_lote_id": 122734}, {"input_lote_id": 122735}, {"input_lote_id": 122736}, {"input_lote_id": 122738}, {"input_lote_id": 122739}, {"input_lote_id": 122740}, {"input_lote_id": 122741}, {"input_lote_id": 122742}, {"input_lote_id": 122743}, {"input_lote_id": 122744}, {"input_lote_id": 122745}, {"input_lote_id": 122746}, {"input_lote_id": 122748}, {"input_lote_id": 122749}, {"input_lote_id": 122750}, {"input_lote_id": 122751}, {"input_lote_id": 122752}, {"input_lote_id": 122737}, {"input_lote_id": 122747}], "peso_rib": 90.6, "ubicacion_id": 9}')

UPDATE mes.partida SET estado_produccion='PROGRAMADA' WHERE id=4502;
update mes.partida_paso_ejecucion set estado='EN_PROCESO' where id=(SELECT id FROm mes.partida_paso_ejecucion WHERE partida_paso_id IN
(SELECT id 
FROM mes.partida_paso WHERe partida_id=4502 AND operacion_id=2));

SELECT mes.registrar_produccion(
    (SELECT id FROM mes.partida_paso_ejecucion
     WHERE partida_paso_id IN (SELECT id FROM mes.partida_paso WHERE partida_id = 4502 AND operacion_id=2)
       AND estado = 'EN_PROCESO'),
    (SELECT jsonb_build_object(
        'ubicacion_id', (SELECT ub.id FROM inventario.ubicacion ub
                         JOIN inventario.almacen alm ON alm.id = ub.almacen_id
                         WHERE alm.codigo = 'ALM_PT' LIMIT 1),
        'peso_rollos', SUM(l.cantidad) FILTER (WHERE ird.flg_rib = false),
        'peso_rib',    SUM(l.cantidad) FILTER (WHERE ird.flg_rib = true),
        'output',      jsonb_agg(jsonb_build_object('input_lote_id', pc.lote_id))
     )
     FROM mes.partida_componente pc
     JOIN inventario.lote l      ON l.id = pc.lote_id
     JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
     WHERE pc.partida_id = 4502 AND pc.lote_id IS NOT NULL)
);

-- SELECT * FROM mes.partida_paso_ejecucion 
-- WHERE partida_paso_id= (SELECT id FROM mes.partida_paso WHERE partida_id=4143 AND operacion_id=2);
-- --2105
-- SELECT * FROM inventario.lote WHERE documento_tipo='partida_paso_ejecucion' AND documento_id=2105;


update mes.partida_paso set estado='COMPLETADO' 
where partida_id= 4502;

UPDATE mes.partida SET estado_produccion='TECO' WHERE id=4502;
UPDATE mes.partida SET estado_comercial='PENDIENTE' WHERE id=4502;

-- (SELECT id FROM mes.partida_paso WHERe partida_id=4502);
update mes.partida_paso_ejecucion set estado='COMPLETADO' where id=(SELECT id FROm mes.partida_paso_ejecucion WHERE partida_paso_id IN
(SELECT id FROM mes.partida_paso WHERe partida_id=4502));

update mes.partida_paso_ejecucion set estado='COMPLETADO' 
where id=(SELECT id FROm mes.partida_paso_ejecucion WHERE partida_paso_id IN
(SELECT id FROM mes.partida_paso WHERe partida_id=4502));

SELECT * FROM mes.partida_paso_ejecucion WHERE partida_paso_id IN
(SELECT id FROM mes.partida_paso WHERe partida_id=4502)

UPDATE mes.partida SET estado_produccion='TECO' WHERE id=4502;

SELECT * FROm inventario.lote WHERE secuencia=28733

DO $$
DECLARE
    v_peso_nuevo        NUMERIC := 22.7; -- <<< fill in
    v_tipo              TEXT    := 'CORRECCION'; -- INGRESO | CORRECCION | SALIDA
    v_obs               TEXT    := NULL;
    v_doc_tipo          TEXT    := NULL;
    v_doc_id            BIGINT  := NULL;

    v_lote_id           INT;
    v_item_id           INT;
    v_peso_anterior     NUMERIC;
    v_ubicacion_id      INT;
    v_pesaje_pos_id     SMALLINT;
    v_pesaje_neg_id     SMALLINT;
    v_doc_movimiento_id BIGINT;
BEGIN
    -- resolve lote
    SELECT l.id, l.item_id, l.cantidad, sa.ubicacion_id
    INTO   v_lote_id, v_item_id, v_peso_anterior, v_ubicacion_id
    FROM   inventario.lote l
    JOIN   inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
    WHERE  l.secuencia = 28733
      AND  l.fyh_elm IS NULL;

    IF v_lote_id IS NULL THEN
        RAISE EXCEPTION 'Lote secuencia=28733 not found or already eliminated';
    END IF;

    SELECT id INTO v_pesaje_pos_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_POS';
    SELECT id INTO v_pesaje_neg_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_NEG';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    -- upsert pesaje record
    INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, observacion, usr_cre)
    VALUES (v_lote_id, v_tipo, v_peso_nuevo, v_obs, 1)
    ON CONFLICT (lote_id) DO UPDATE
        SET peso_real   = EXCLUDED.peso_real,
            tipo        = EXCLUDED.tipo,
            observacion = EXCLUDED.observacion;

    -- post delta movement only when weight actually changed
    IF v_peso_nuevo <> v_peso_anterior THEN
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, documento_tipo, documento_id
        ) VALUES (
            v_doc_movimiento_id,
            v_item_id, v_lote_id,
            CASE WHEN v_peso_nuevo > v_peso_anterior THEN v_pesaje_pos_id
                 ELSE v_pesaje_neg_id END,
            CASE WHEN v_peso_nuevo < v_peso_anterior THEN v_ubicacion_id ELSE NULL END,
            CASE WHEN v_peso_nuevo > v_peso_anterior THEN v_ubicacion_id ELSE NULL END,
            ABS(v_peso_nuevo - v_peso_anterior),
            v_doc_tipo, v_doc_id
        );
    END IF;

    -- update stock
    UPDATE inventario.lote SET cantidad = v_peso_nuevo WHERE id = v_lote_id;

    RAISE NOTICE 'Pesaje patched: lote=% (secuencia=28733) % kg → % kg (%)',
        v_lote_id, v_peso_anterior, v_peso_nuevo, v_tipo;
END;
$$;


CREATE OR REPLACE FUNCTION inventario.registrar_pesaje(
    p_lote_id   INT,
    p_peso_kg   NUMERIC,
    p_tipo      TEXT    DEFAULT 'INGRESO',   -- INGRESO | CORRECCION | SALIDA
    p_obs       TEXT    DEFAULT NULL,
    p_doc_tipo  TEXT    DEFAULT NULL,        -- documento_tipo for the movement
    p_doc_id    BIGINT  DEFAULT NULL         -- documento_id for the movement
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'inventario', 'mes', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id            int := get_user_id();
    v_pesaje_pos_id     smallint;
    v_pesaje_neg_id     smallint;
    v_doc_movimiento_id bigint;
BEGIN

    SELECT id INTO v_pesaje_pos_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_POS';
    SELECT id INTO v_pesaje_neg_id FROM inventario.item_movimiento_tipo WHERE codigo = 'PESAJE_NEG';
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

    WITH roll AS (
        SELECT
            l.item_id,
            l.cantidad              AS peso_anterior,
            sa.ubicacion_id,
            p_peso_kg               AS peso_nuevo
        FROM inventario.lote l
        JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
        WHERE l.id = p_lote_id
          AND l.fyh_elm IS NULL
    ),
    pesaje AS (
        INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, observacion, usr_cre)
        VALUES (p_lote_id, p_tipo, p_peso_kg, p_obs, v_usr_id)
        ON CONFLICT (lote_id) DO UPDATE
            SET peso_real   = EXCLUDED.peso_real,
                tipo        = EXCLUDED.tipo,
                observacion = EXCLUDED.observacion
        RETURNING lote_id
    ),
    mov AS (
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, documento_tipo, documento_id
        )
        SELECT
            v_doc_movimiento_id,
            r.item_id, p_lote_id,
            CASE WHEN p_peso_kg > r.peso_anterior THEN v_pesaje_pos_id
                 ELSE v_pesaje_neg_id END,
            CASE WHEN p_peso_kg < r.peso_anterior THEN r.ubicacion_id ELSE NULL END,
            CASE WHEN p_peso_kg > r.peso_anterior THEN r.ubicacion_id ELSE NULL END,
            ABS(p_peso_kg - r.peso_anterior),
            p_doc_tipo, p_doc_id
        FROM roll r
        JOIN pesaje ps ON ps.lote_id = p_lote_id
        WHERE p_peso_kg <> r.peso_anterior
    )
    UPDATE inventario.lote l
    SET cantidad = p_peso_kg
    FROM roll r
    WHERE l.id = p_lote_id;

    INSERT INTO logs_api (function_name, user_id, params)
    VALUES ('registrar_pesaje', v_usr_id, jsonb_build_object(
        'lote_id', p_lote_id, 'peso_kg', p_peso_kg, 'tipo', p_tipo
    ));

    RETURN format('Pesaje registrado: lote #%s → %s kg (%s)', p_lote_id, p_peso_kg, p_tipo);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error en registrar_pesaje - User: %, lote: %, Error: %, Detail: %',
              v_usr_id, p_lote_id, v_message, v_detail;
    RAISE;
END;
$$;



SELECT
    p.id                                                                        AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT,4,'0')   AS codigo,
    p.estado_produccion,
    COUNT(pp.id)                                                                AS pasos_pendientes,
    (SELECT COUNT(*) FROM mes.partida_componente pc
     WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL)                    AS rolls_asignados,
    COUNT(pp.id) FILTER (WHERE
        (SELECT COUNT(*) FROM mes.partida_paso_ejecucion pe
         WHERE pe.partida_paso_id = pp.id AND pe.estado IN ('COMPLETADO','OMITIDO')) = 0
    )                                                                           AS pasos_sin_ninguna_ejecucion
FROM mes.partida_paso pp
JOIN mes.partida p ON p.id = pp.partida_id
WHERE p.estado_produccion NOT IN ('CERRADA','CANCELADA','TECO','CREADA')
  AND p.fyh_elm IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM mes.partida_paso_ejecucion pe
      WHERE pe.partida_paso_id = pp.id AND pe.estado = 'EN_PROCESO'
  )
  AND NOT EXISTS (
      SELECT 1 FROM mes.programacion prog
      WHERE prog.actividad_tipo = 'partida_paso' AND prog.actividad_id = pp.id
        AND prog.fecha >= CURRENT_DATE
  )
GROUP BY p.id, p.numero, p.fyh_cre, p.estado_produccion
ORDER BY pasos_pendientes DESC;

SELECT MIN(id) FROm mes.partida WHERE estado_produccion='CREADA' and id>1000 AND EXISTS (SELECT 1 FROM mes.partida_paso pp WHERE pp.partida_id=mes.partida.id );
SELECT MIN(id) FROm mes.partida WHERE estado_produccion='CREADA' and id>3000

-- UPDATE mes.partida SET estado_produccion='CERRADA' WHERE id<=2000

SELECT * FROm mes.operacion

SELECT * FROM calidad.vw_partidas_pendientes_calidad
WHERE partida_id =5955

SELECT * FROM mes.partida WHERE id=5955


-- -- -- id	nombre	codigo	codigo_canon
-- -- -- 44	Spun 20/1	SPUN201	spun201
-- -- -- 38	Spun	SPUN	spun

SELECT * FROM  articulo
JOIN articulo_tipo ON articulo.articulo_tipo_id = articulo_tipo.id
WHERE articulo_tipo.nombre ILIKE '%spun%';
SELECT * FROm item_rollo_detalle WHERE articulo_id IN (SELECT id FROM articulo WHERE articulo_tipo_id IN (SELECT id FROM articulo_tipo WHERE nombre ILIKE '%spun%'));
SELECT * FROm item WHERE nombre ILIKE '%spun%';
SELECT * FROm item_rollo_detalle WHERE item_id IN (SELECT id FROm item WHERE nombre ILIKE '%spun%');
SELECT item_id,articulo_tipo_id,count(*) FROM inventario.vw_lotes_rollos_disponibles WHERE articulo_tipo_id IN (38,44)
GROUP BY  item_id, articulo_tipo_id

SELECT * FROM inventario.vw_lotes_rollos_disponibles
WHERE articulo_tipo_id IN (38,44)
 LIMIT 50;



 -- How many lotes were created for partida 4502?
SELECT COUNT(*) FROM inventario.lote WHERE documento_tipo='PARTIDA' AND documento_id=4502;

-- Was registrar_produccion successful (output lotes exist)?
SELECT COUNT(*) FROM inventario.lote WHERE documento_tipo='partida_paso_ejecucion'
  AND documento_id IN (SELECT id FROM mes.partida_paso_ejecucion
                       WHERE partida_paso_id IN (SELECT id FROM mes.partida_paso WHERE partida_id=4502));

-- Current partida state
SELECT estado_produccion FROM mes.partida WHERE id=4502;


BEGIN;

-- 1. movements for the 46 new lotes
DELETE FROM inventario.item_movimientos
WHERE lote_id IN (
    SELECT id FROM inventario.lote
    WHERE documento_tipo = 'PARTIDA' AND documento_id = 4502
);

-- 2. partida_componente reservations
DELETE FROM mes.partida_componente
WHERE partida_id = 4502
  AND lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo='PARTIDA' AND documento_id=4502);

-- 3. the 46 lotes
DELETE FROM inventario.lote WHERE documento_tipo = 'PARTIDA' AND documento_id = 4502;

-- 4. ejecucion + paso added by the script
DELETE FROM mes.partida_paso_ejecucion
WHERE partida_paso_id IN (SELECT id FROM mes.partida_paso WHERE partida_id=4502 AND operacion_id=2);
DELETE FROM mes.partida_paso WHERE partida_id=4502 AND operacion_id=2;

-- CHECK before committing
SELECT COUNT(*) FROM inventario.lote WHERE documento_tipo='PARTIDA' AND documento_id=4502;

BEGIN;

-- Classify lotes once
CREATE TEMP TABLE _lote_class AS
WITH expected AS (
    SELECT item_id, cantidad::INT AS expected_count
    FROM mes.partida_detalle WHERE partida_id = 4502
),
ranked AS (
    SELECT l.id, l.item_id, l.cantidad,
           ROW_NUMBER() OVER (PARTITION BY l.item_id ORDER BY l.id ASC) AS rn,
           e.expected_count
    FROM inventario.lote l
    JOIN expected e ON e.item_id = l.item_id
    WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = 4502
)
SELECT id, item_id, cantidad,
       CASE WHEN rn <= expected_count THEN 'valid' ELSE 'bad' END AS status
FROM ranked;

-- Verify split before touching anything
SELECT status, COUNT(*) FROM _lote_class GROUP BY status;

-- 1. Purge bad lotes
DELETE FROM inventario.item_movimientos WHERE lote_id IN (SELECT id FROM _lote_class WHERE status='bad');
DELETE FROM mes.partida_componente      WHERE lote_id IN (SELECT id FROM _lote_class WHERE status='bad');
DELETE FROM inventario.lote             WHERE id      IN (SELECT id FROM _lote_class WHERE status='bad');

-- 2. Re-add valid lotes to partida_componente (no-op if already there)
INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada, usr_cre)
SELECT 4502, id, cantidad, NULL
FROM _lote_class WHERE status = 'valid'
ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING;

-- Final check
SELECT COUNT(*) AS valid_lotes   FROM _lote_class WHERE status='valid';
SELECT COUNT(*) AS in_componente FROM mes.partida_componente WHERE partida_id=4502 AND lote_id IS NOT NULL;

-- COMMIT; / ROLLBACK;


SELECT * FROm mes.partida WHERE id=5963;
SELECT * FROm mes.partida_paso WHERE partida_id=5963;
SELECT * FROM mes.partida_paso_ejecucion WHERE partida_paso_id IN (SELECT id FROM mes.partida_paso WHERE partida_id=5963)





-- 1. What partida_detalle says should exist (source of truth)
SELECT item_id, cantidad::INT AS expected_rolls
FROM mes.partida_detalle
WHERE partida_id = 4502;

-- 2. What lotes actually exist, per item
SELECT item_id, COUNT(*) AS actual_lotes, MIN(id) AS first_id, MAX(id) AS last_id
FROM inventario.lote
WHERE documento_tipo = 'PARTIDA' AND documento_id = 4502
GROUP BY item_id ORDER BY item_id;

-- 3. How many movements exist for those lotes (and what type)
SELECT imt.codigo, COUNT(*) AS cnt
FROM inventario.item_movimientos m
JOIN inventario.item_movimiento_tipo imt ON imt.id = m.item_movimiento_tipo_id
WHERE m.lote_id IN (
    SELECT id FROM inventario.lote WHERE documento_tipo='PARTIDA' AND documento_id=4502
)
GROUP BY imt.codigo;

-- 4. partida_componente state
SELECT COUNT(*) AS componente_rows
FROM mes.partida_componente
WHERE partida_id = 4502 AND lote_id IS NOT NULL;

-- 5. partida_paso and ejecucion state
SELECT pp.id, pp.operacion_id, pp.secuencia,
       ppe.id AS ejecucion_id, ppe.estado, ppe.fyh_inicio, ppe.fyh_fin
FROM mes.partida_paso pp
LEFT JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
WHERE pp.partida_id = 4502;








BEGIN;
    
CREATE TEMP TABLE _lote_class AS
WITH expected AS (
    SELECT item_id, cantidad::INT AS expected_count
    FROM mes.partida_detalle WHERE partida_id = 4502
),
ranked AS (
    SELECT l.id, l.item_id, l.cantidad,
           ROW_NUMBER() OVER (PARTITION BY l.item_id ORDER BY l.id ASC) AS rn,
           e.expected_count
    FROM inventario.lote l
    JOIN expected e ON e.item_id = l.item_id
    WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = 4502
)
SELECT id, item_id, cantidad,
       CASE WHEN rn <= expected_count THEN 'valid' ELSE 'bad' END AS status
FROM ranked;

-- Verify before touching anything
SELECT status, COUNT(*), MIN(id), MAX(id) FROM _lote_class GROUP BY status, item_id ORDER BY item_id, status;


-- 1. Delete bad lotes (no movements to clean, componente already empty)
DELETE FROM inventario.lote_saldo
WHERE lote_id IN (SELECT id FROM _lote_class WHERE status = 'bad');

DELETE FROM inventario.lote WHERE id IN (SELECT id FROM _lote_class WHERE status = 'bad');
ALTER TABLE inventario.lote DISABLE TRIGGER USER;

DELETE FROM inventario.lote WHERE id IN (SELECT id FROM _lote_class WHERE status = 'bad');

ALTER TABLE inventario.lote ENABLE TRIGGER USER;

-- 2. Restore AJUSTE_POS movements for valid lotes
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    destino_ubicacion_id, cantidad, documento_tipo, documento_id, observacion, usr_cre
)
SELECT
    nextval('inventario.mov_doc_seq'),
    lc.item_id, lc.id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS'),
    (SELECT ub.id FROM inventario.ubicacion ub
     JOIN inventario.almacen alm ON alm.id = ub.almacen_id
     WHERE alm.codigo = 'ALM_CRU' LIMIT 1),
    lc.cantidad, 'PARTIDA', 4502,
    'Ingreso artificial de rollo MLR propio para partida 4502', NULL
FROM _lote_class lc WHERE lc.status = 'valid';

-- 3. Restore partida_componente for valid lotes
INSERT INTO mes.partida_componente (partida_id, lote_id, cantidad_reservada, usr_cre)
SELECT 4502, id, cantidad, NULL
FROM _lote_class WHERE status = 'valid';

-- Final verification
SELECT COUNT(*) AS lotes   FROM inventario.lote WHERE documento_tipo='PARTIDA' AND documento_id=4502;
SELECT COUNT(*) AS movs    FROM inventario.item_movimientos WHERE lote_id IN (SELECT id FROM _lote_class WHERE status='valid');
SELECT COUNT(*) AS comps   FROM mes.partida_componente WHERE partida_id=4502 AND lote_id IS NOT NULL;

-- COMMIT; / ROLLBACK;
-- ══════════════════════════════════════════════════════════════════
-- STEP 1 — Diagnostic: see what both sources hold before touching anything
-- Run this first and compare against the legacy JSON you have.
-- ══════════════════════════════════════════════════════════════════
SELECT
    im.id             AS mov_id,
    im.lote_id,
    im.cantidad,
    im.fecha_hora                                   AS fecha_migrada,
    si.fyh_salida_real,
    si.fyh_solicitud_tz,
    COALESCE(si.fyh_salida_real, si.fyh_solicitud_tz) AS fecha_salida_inventario,
    -- fallback: date from the dyeing run (if salida dates are also wrong)
    ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP
     + INTERVAL '5 hours')::TIMESTAMPTZ             AS fecha_produccion_tenido,
    pt.partida_id                                   AS legacy_partida_id
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt
    ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
-- lote → sdxs: the exact row that generated this movement
JOIN public.salida_inventario_detalle_x_stock sdxs
    ON sdxs.inventario_id = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN public.salida_inventario_detalle sid
    ON sid.id = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si
    ON si.id = sid.salida_inventario_id
    AND si.estado = 'aprobado'
-- also pull produccion_tenido date as backup
LEFT JOIN mes.partida_paso pp
    ON pp.id = im.documento_id
   AND im.documento_tipo IN ('partida_paso', 'partida_paso_ejecucion')
LEFT JOIN public.produccion_tenido pt ON pt.id = pp.id
WHERE im.item_id = 27
  AND im.fecha_hora = '2025-09-11 22:53:28.212517+00'
ORDER BY COALESCE(si.fyh_salida_real, si.fyh_solicitud_tz), im.id;



-- ══════════════════════════════════════════════════════════════════
-- STEP 2A — Update using salida_inventario timestamps (most precise)
-- Wrap in a transaction so you can verify before committing.
-- ══════════════════════════════════════════════════════════════════
BEGIN;

UPDATE inventario.item_movimientos im
SET    fecha_hora = COALESCE(si.fyh_salida_real, si.fyh_solicitud_tz)
FROM   public.salida_inventario_detalle_x_stock sdxs
JOIN   public.salida_inventario_detalle sid
    ON sid.id = sdxs.salida_inventario_detalle_id
JOIN   public.salida_inventario si
    ON si.id  = sid.salida_inventario_id
    AND si.estado = 'aprobado'
    AND si.motivo::text IN ('receta','matizado','lavado','lavado maquina','desmontado','ajuste receta')
JOIN   inventario.item_movimiento_tipo imt
    ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
WHERE  sdxs.inventario_id            = im.lote_id
  AND  sdxs.cantidad::numeric(12,4)  = im.cantidad
  AND  im.item_id   = 27
  AND  im.fecha_hora = '2025-09-11 22:53:28.212517+00';

-- Verify the result looks right before committing
SELECT fecha_hora, COUNT(*) 
FROM inventario.item_movimientos 
WHERE item_id = 27 
GROUP BY fecha_hora 
ORDER BY fecha_hora;

-- ROLLBACK;   ← uncomment to abort; COMMIT to apply
COMMIT;


-- ══════════════════════════════════════════════════════════════════
-- STEP 2B — Fallback: use produccion_tenido.fecha if 2A dates are wrong
-- Same transaction pattern.
-- ══════════════════════════════════════════════════════════════════
BEGIN;

UPDATE inventario.item_movimientos im
SET    fecha_hora =
           ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP
            + INTERVAL '5 hours')::TIMESTAMPTZ
FROM   inventario.item_movimiento_tipo imt
JOIN   mes.partida_paso pp
    ON pp.id = im.documento_id
   AND im.documento_tipo IN ('partida_paso', 'partida_paso_ejecucion')
JOIN   public.produccion_tenido pt ON pt.id = pp.id
WHERE  imt.id  = im.item_movimiento_tipo_id
  AND  imt.codigo = 'PROD_CONSUMO'
  AND  im.item_id   = 27
  AND  im.fecha_hora = '2025-09-11 22:53:28.212517+00';

SELECT fecha_hora, COUNT(*)
FROM inventario.item_movimientos
WHERE item_id = 27
GROUP BY fecha_hora
ORDER BY fecha_hora;

-- ROLLBACK;
COMMIT;




-- ══════════════════════════════════════════════════════════════════
-- STEP 1 — Scope: how many rows are affected across all items,
--           and confirm sdxs.fecha has the correct original dates
-- ══════════════════════════════════════════════════════════════════
SELECT
    it.codigo                       AS item_tipo,
    i.codigo                        AS item_codigo,
    i.nombre                        AS item_nombre,
    imt.codigo                      AS mov_tipo,
    COUNT(*)                        AS rows_affected,
    MIN(sdxs.fecha)                 AS earliest_correct_date,
    MAX(sdxs.fecha)                 AS latest_correct_date
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
JOIN item i   ON i.id  = im.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id
JOIN public.salida_inventario_detalle_x_stock sdxs
    ON  sdxs.inventario_id         = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN public.salida_inventario_detalle sid
    ON sid.id = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si
    ON si.id = sid.salida_inventario_id AND si.estado = 'aprobado'
WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
GROUP BY it.codigo, i.codigo, i.nombre, imt.codigo
ORDER BY it.codigo, i.nombre, imt.codigo;


-- ══════════════════════════════════════════════════════════════════
-- STEP 2 — Ambiguity check: rows where (lote_id, cantidad) maps
--           to more than one sdxs candidate — these need manual review
-- ══════════════════════════════════════════════════════════════════
SELECT
    im.id       AS mov_id,
    im.item_id,
    im.lote_id,
    im.cantidad,
    imt.codigo  AS mov_tipo,
    COUNT(sdxs.id) AS sdxs_candidates
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
JOIN public.salida_inventario_detalle_x_stock sdxs
    ON  sdxs.inventario_id           = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
JOIN public.salida_inventario si ON si.id = sid.salida_inventario_id AND si.estado = 'aprobado'
WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
GROUP BY im.id, im.item_id, im.lote_id, im.cantidad, imt.codigo
HAVING COUNT(sdxs.id) > 1
ORDER BY sdxs_candidates DESC, im.item_id;


-- ══════════════════════════════════════════════════════════════════
-- STEP 3 — The fix: update all unambiguous rows (exactly 1 sdxs match)
--           Ambiguous rows (from step 2) are left untouched for review.
-- ══════════════════════════════════════════════════════════════════
BEGIN;

WITH candidates AS (
    SELECT
        im.id                        AS im_id,
        MIN(sdxs.fecha)              AS fecha_correcta,   -- MIN = MAX when COUNT = 1
        COUNT(sdxs.id)               AS n
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
        AND imt.codigo IN ('PROD_CONSUMO', 'AJUSTE_NEG', 'MUESTRA_EGR')
    JOIN public.salida_inventario_detalle_x_stock sdxs
        ON  sdxs.inventario_id           = im.lote_id
        AND sdxs.cantidad::numeric(12,4) = im.cantidad
    JOIN public.salida_inventario_detalle sid ON sid.id = sdxs.salida_inventario_detalle_id
    JOIN public.salida_inventario si ON si.id = sid.salida_inventario_id AND si.estado = 'aprobado'
    WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
    GROUP BY im.id
    HAVING COUNT(sdxs.id) = 1      -- skip ambiguous; handle separately
)
UPDATE inventario.item_movimientos im
SET    fecha_hora = c.fecha_correcta
FROM   candidates c
WHERE  im.id = c.im_id;

GET DIAGNOSTICS ... -- rows updated shown by client

-- Sanity check: any rows still at the migration timestamp?
SELECT COUNT(*), imt.codigo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
GROUP BY imt.codigo;

-- Spot-check item 27 timeline
SELECT fecha_hora, imt.codigo, im.cantidad * imt.factor AS neta,
       SUM(im.cantidad * imt.factor) OVER (ORDER BY fecha_hora, im.id) AS saldo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.item_id = 27
ORDER BY fecha_hora, im.id
LIMIT 30;

-- ROLLBACK;
COMMIT;







-- ══════════════════════════════════════════════════════════════════
-- PHASE 2 — Resolve ambiguous rows via doc_movimiento_id fingerprint
--
-- Strategy:
--   1. For each doc group, collect its full consumed-lote set
--   2. Match to the salida_inventario with the same lote set
--   3. That 1:1 mapping lets us find sdxs.fecha for any (lote,qty) pair
--      inside the group, even if (lote,qty) alone is ambiguous
-- ══════════════════════════════════════════════════════════════════

-- STEP A — Check how many doc groups resolve cleanly (should be near 100%)
WITH im_fingerprints AS (
    SELECT
        im.doc_movimiento_id,
        -- Collect every lote_id consumed in this doc group (all movement types)
        array_agg(DISTINCT im.lote_id ORDER BY im.lote_id) AS lote_set
    FROM inventario.item_movimientos im
    WHERE im.doc_movimiento_id IN (
        SELECT DISTINCT doc_movimiento_id
        FROM inventario.item_movimientos im2
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im2.item_movimiento_tipo_id
            AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
        WHERE im2.fecha_hora = '2025-09-11 22:53:28.212517+00'
    )
    GROUP BY im.doc_movimiento_id
),
si_fingerprints AS (
    SELECT
        si.id AS si_id,
        array_agg(DISTINCT sdxs.inventario_id ORDER BY sdxs.inventario_id) AS lote_set
    FROM public.salida_inventario si
    JOIN public.salida_inventario_detalle sid ON sid.salida_inventario_id = si.id
    JOIN public.salida_inventario_detalle_x_stock sdxs ON sdxs.salida_inventario_detalle_id = sid.id
    WHERE si.estado = 'aprobado'
    GROUP BY si.id
),
matches AS (
    SELECT
        imf.doc_movimiento_id,
        COUNT(sif.si_id) AS si_count  -- 1 = unique, >1 = still ambiguous
    FROM im_fingerprints imf
    JOIN si_fingerprints sif ON sif.lote_set = imf.lote_set
    GROUP BY imf.doc_movimiento_id
)
SELECT si_count, COUNT(*) AS doc_groups
FROM matches
GROUP BY si_count
ORDER BY si_count;


-- STEP B — Apply the fix (after verifying step A shows mostly si_count = 1)
BEGIN;

WITH im_fingerprints AS (
    SELECT
        im.doc_movimiento_id,
        array_agg(DISTINCT im.lote_id ORDER BY im.lote_id) AS lote_set
    FROM inventario.item_movimientos im
    WHERE im.doc_movimiento_id IN (
        SELECT DISTINCT doc_movimiento_id
        FROM inventario.item_movimientos im2
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im2.item_movimiento_tipo_id
            AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
        WHERE im2.fecha_hora = '2025-09-11 22:53:28.212517+00'
    )
    GROUP BY im.doc_movimiento_id
),
si_fingerprints AS (
    SELECT
        si.id AS si_id,
        array_agg(DISTINCT sdxs.inventario_id ORDER BY sdxs.inventario_id) AS lote_set
    FROM public.salida_inventario si
    JOIN public.salida_inventario_detalle sid ON sid.salida_inventario_id = si.id
    JOIN public.salida_inventario_detalle_x_stock sdxs ON sdxs.salida_inventario_detalle_id = sid.id
    WHERE si.estado = 'aprobado'
    GROUP BY si.id
),
doc_to_si AS (
    -- Keep only uniquely-resolved docs (si_count = 1)
    SELECT imf.doc_movimiento_id, MIN(sif.si_id) AS si_id
    FROM im_fingerprints imf
    JOIN si_fingerprints sif ON sif.lote_set = imf.lote_set
    GROUP BY imf.doc_movimiento_id
    HAVING COUNT(sif.si_id) = 1
)
UPDATE inventario.item_movimientos im
SET    fecha_hora = sdxs.fecha
FROM   doc_to_si d
JOIN   public.salida_inventario_detalle sid
    ON sid.salida_inventario_id = d.si_id
JOIN   public.salida_inventario_detalle_x_stock sdxs
    ON sdxs.salida_inventario_detalle_id = sid.id
    AND sdxs.inventario_id           = im.lote_id
    AND sdxs.cantidad::numeric(12,4) = im.cantidad
JOIN   inventario.item_movimiento_tipo imt
    ON imt.id = im.item_movimiento_tipo_id
    AND imt.codigo IN ('PROD_CONSUMO','AJUSTE_NEG','MUESTRA_EGR')
WHERE  im.doc_movimiento_id = d.doc_movimiento_id
  AND  im.fecha_hora = '2025-09-11 22:53:28.212517+00';

-- How many rows still need attention?
SELECT COUNT(*), imt.codigo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.fecha_hora = '2025-09-11 22:53:28.212517+00'
GROUP BY imt.codigo;

-- ROLLBACK;
COMMIT;





SELECT * FROM doc.entrega
WHERE correlativo ILIKE '%2646%'

SELECT * FROM item WHERE nombre ILIKE '%rib%f poly%24%1%'
--297
SELECT * FROM item WHERE id=258




UPDATE inventario.lote
SET item_id=297
WHERE item_id=258
AND id IN (SELECT lote_id FROM inventario.lote_rollo_detalle WHERE entrega_id=739)

SELECT * FROM doc.entrega_detalle

UPDATE doc.entrega_detalle
SET item_id=297
WHERE entrega_id=739 AND item_id=258 


SELECT tipo_articulo_id, COUNT(*) AS rows
FROM public.catalogo_precios
WHERE activo = 1
GROUP BY 1 ORDER BY 1;


WITH grupo_base(tipo, bucket) AS (
    -- the legacy grouping, made visible (client-independent part)
    VALUES (4,18),(9,18),(8,12),(10,14),(17,14),(22,16),(23,16)
)
SELECT
    at.id                                   AS tipo_id,
    at.nombre                               AS tipo_nombre,
    COALESCE(g.bucket, at.id)               AS bucket_precio,
    bt.nombre                               AS bucket_nombre,
    (SELECT COUNT(*) FROM mes.partida p
       WHERE p.articulo_tipo_id = at.id AND p.fyh_elm IS NULL)                         AS partidas_activas,
    (SELECT COUNT(*) FROM doc.catalogo_precios cp
       WHERE cp.articulo_tipo_id = at.id AND cp.fyh_elm IS NULL)                       AS precios_propios,
    (SELECT COUNT(*) FROM doc.catalogo_precios cp
       WHERE cp.articulo_tipo_id = COALESCE(g.bucket, at.id) AND cp.fyh_elm IS NULL)   AS precios_en_bucket
FROM articulo_tipo at
LEFT JOIN grupo_base    g  ON g.tipo = at.id
LEFT JOIN articulo_tipo bt ON bt.id  = COALESCE(g.bucket, at.id)
ORDER BY partidas_activas DESC;




SELECT *From doc.orden_servicio WHere id=10

SELECT *From doc.orden_servicio_detalle
WHere orden_servicio_id=10

UPDATE doc.orden_servicio_detalle
SET malla='3.40-1.35'
WHere orden_servicio_id=10



SELECT * FROM item_rollo_detalle WHERE item_id=272

SELECT * FROM articulo WHERE id=30

SELECT * FROM articulo_tipo WHERE id=5

-- A) Where is the 2,242 actually coming from? (by operation)
SELECT op.codigo, COUNT(*) AS combos_sin_precio
FROM doc.vw_precios_pendientes vpp
JOIN mes.operacion op ON op.id = vpp.operacion_id
GROUP BY op.codigo
ORDER BY 2 DESC;

-- B) Apples-to-apples vs the original ~2,000: TENIDO partidas still unpriced (with family logic)
SELECT COUNT(*)
FROM mes.partida p
WHERE p.fyh_elm IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM doc.catalogo_precios cp
    WHERE cp.operacion_id = (SELECT id FROM mes.operacion WHERE codigo='TENIDO')
      AND cp.fyh_elm IS NULL
      AND (cp.articulo_tipo_id   IS NULL OR cp.articulo_tipo_id   = doc.fn_familia_precio(p.articulo_tipo_id, p.tercero_id))
      AND (cp.color_x_cliente_id IS NULL OR cp.color_x_cliente_id = p.color_x_cliente_id)
      AND (cp.tenido_id          IS NULL OR cp.tenido_id          = p.tenido_id)
  );


SELECT * FROM doc.vw_rollos_estado;


SELECT COUNT(*) AS rollos_huerfanos_en_stock,
       ROUND(SUM(l.cantidad)::numeric, 2) AS kg
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.vw_stock_lotes sl      ON sl.lote_id = l.id
WHERE l.fyh_elm IS NULL
  AND lrd.entrega_id IS NULL
  AND lrd.orden_servicio_id IS NULL;


--6049
SELECT * FROM mes.partida where id =6049;
SELECT * FROM mes.partida_paso WHERE partida_id=6049;
SELECT * FROM mes.partida_paso_ejecucion WHERE partida_paso_id IN (SELECT id FROM mes.partida_paso WHERE partida_id=6049)


UPDATE mes.partida_paso
SET estado = 'EN_PROCESO', fyh_mod = NOW()
WHERE id = 18908;


SELECT * FROM mes.partida_paso WHERE partida_id=6094
SELECT * FROM mes.partida_paso_ejecucion WHERE
SELEct * FROm mes.operacion

ALTER TABLE mes.partida_paso_ejecucion DISABLE TRIGGER trg_bu_ejecucion_receta_immutable;

UPDATE mes.partida_paso_ejecucion 
SET receta_id = NULL
WHERE partida_paso_id IN (
    SELECT id FROM mes.partida_paso WHERE partida_id = 6094 AND operacion_id != 2
);

ALTER TABLE mes.partida_paso_ejecucion ENABLE TRIGGER trg_bu_ejecucion_receta_immutable;
UPDATE mes.partida_paso 
SET receta_id = NULL
WHERE receta_id IS NOT NULL AND operacion_id != 2
;
SELECT * FROM mes.partida_paso WHERE receta_id IS NOT NULL AND operacion_id != 2


--6063 cambiar 1010 a 1011


SELECT
    pe.id           AS ejecucion_id,
    pe.estado,
    pe.cantidad_rollos,
    pe.peso_kg,
    pe.fyh_inicio,
    pe.fyh_fin
FROM mes.partida_paso pp
JOIN mes.operacion o ON o.id = pp.operacion_id
JOIN mes.partida_paso_ejecucion pe ON pe.partida_paso_id = pp.id
WHERE pp.partida_id = 6063
  AND o.codigo ILIKE '%secado%'
ORDER BY pe.fyh_inicio;


SELECT COUNT(*) FROM inventario.lote
WHERE documento_tipo = 'partida_paso_ejecucion'
  AND documento_id IN (9650, 9598);

BEGIN;

UPDATE mes.partida_paso_ejecucion
SET cantidad_rollos = 11,
    usr_mod = get_user_id(),
    fyh_mod = NOW()
WHERE id = 9650;

SELECT mes.actualizar_estado_partida(6063);

COMMIT;


BEGIN;

-- 1. Correct the roll count
UPDATE mes.partida_paso_ejecucion
SET cantidad_rollos = 11,
    usr_mod = get_user_id(),
    fyh_mod = NOW()
WHERE id = 9650;

-- 2. Re-evaluate paso estado using same formula as finalizar_paso
UPDATE mes.partida_paso pp
SET estado = CASE
        WHEN (
            SELECT COALESCE(SUM(pe.cantidad_rollos) FILTER (WHERE pe.estado = 'COMPLETADO'), 0)
            FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = pp.id
        ) >= (
            SELECT COUNT(*)
            FROM mes.partida_componente pc
            WHERE pc.partida_id = pp.partida_id
              AND pc.lote_id IS NOT NULL
        ) THEN 'COMPLETADO'::partida_paso_estado_enum
        ELSE 'EN_PROCESO'::partida_paso_estado_enum
    END,
    fyh_mod = NOW()
WHERE pp.id = (
    SELECT partida_paso_id FROM mes.partida_paso_ejecucion WHERE id = 9650
);

-- 3. Now paso.estado is correct → partida state recalculation is accurate
SELECT mes.actualizar_estado_partida(6063);

COMMIT;
--4595 4588






-- 1) Does this tipo satisfy esDevolucion (codigo LIKE 'DEV_%') and !esEmitida (flg_emitida = false)?
select id, codigo, nombre, flg_emitida, flg_cliente
from doc.entrega_tipo
where nombre ilike '%devoluci%cliente%servicio%';

-- 2) Does the dispatched view actually return rows for the client you selected?
--    Replace <CLIENTE_ID> with the tercero id you pick as emisor.
select lote_id, item_nombre, propietario_id, partida_codigo, cantidad_disponible
from inventario.vw_lotes_rollos_despachados
where propietario_id = (SELECT id FROm tercero WHERE nombre ILIKE '%faride%');



SELECT * FROM doc.entrega ORDER by id desc

SELECT * FROM doc.entrega_detalle WHERE entrega_id=834 --5854

SELECT * FROm inventario.item_movimientos WHERE documento_id=834 

SELECT * FROM inventario.lote 
WHERE id IN (SELECT lote_id FROm inventario.item_movimientos WHERE documento_id>=834 and documento_tipo='entrega')
SELECT * FROM tercero WHERE id=1
SELECT lote_id, entrega_id, entrega_serie, orden_servicio_id, os_serie, factura_hilo
FROM inventario.vw_lotes_rollos_stock
WHERE entrega_id IS NOT NULL
LIMIT 20;


SELECT
  count(*)                       AS total,
  count(entrega_id)              AS with_entrega,
  count(entrega_serie)           AS searchable_by_entrega_serie,
  count(orden_servicio_id)       AS with_os,
  count(os_serie)                AS searchable_by_os_serie,
  count(factura_hilo)            AS searchable_by_factura_hilo
FROM inventario.vw_lotes_rollos_disponibles;




-- 1. Is the entrega itself headless (no correlativo to search by)?
SELECT id, serie, correlativo, entrega_tipo_id FROM doc.entrega WHERE id = 834;

-- 2. Are its rolls linked in lote_rollo_detalle? (THE likely culprit)
SELECT count(*) AS rolls_linked
FROM inventario.lote_rollo_detalle WHERE entrega_id = 834;

-- 3. Do they surface in the stock view with a serie/correlativo?
SELECT lote_id, entrega_id, entrega_serie, entrega_correlativo, cantidad_disponible
FROM inventario.vw_lotes_rollos_stock WHERE entrega_id = 834 LIMIT 10;

-- 4. And are they actually available (not reserved/consumed)?
SELECT count(*) AS available
FROM inventario.vw_lotes_rollos_disponibles WHERE entrega_id = 834;

SELECT * FROM produccion_tenido

SELECT p.id
FROM partida p
LEFT JOIN produccion_tenido pt ON pt.partida_id=p.id
LEFT JOIN partida_x_recetas pxr ON pxr.partida_id=pt.id AND 



SELECT date_trunc('month', l.fyh_cre) AS mes, COUNT(*) AS rollos
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
JOIN inventario.vw_stock_lotes sl      ON sl.lote_id = l.id
WHERE l.fyh_elm IS NULL
  AND lrd.guia_remision_id IS NULL
  AND lrd.orden_servicio_id IS NULL
GROUP BY 1 ORDER BY 1 DESC;


SELECT cuadre_id, COUNT(*) AS movs, COUNT(DISTINCT item_id) AS items, ROUND(SUM(cantidad),4) AS kg_restado
FROM inventario.cuadre_backfill_ajuste
GROUP BY cuadre_id;


SELECT lm.id, lm.estado, lm.maquina_id, lm.receta_id,
       lm.fyh_inicio, lm.fyh_fin, lm.fyh_cre,
       prog.fecha AS prog_fecha
FROM mes.lavado_maquina lm
LEFT JOIN mes.programacion prog
       ON prog.actividad_tipo = 'LAVADO_MAQUINA' AND prog.actividad_id = lm.id
WHERE lm.estado IN ('PENDIENTE','EN_PROCESO')
ORDER BY lm.estado, lm.id;



SELECT id, numero, estado_facturacion, flg_antipilling, fyh_elm,
       color_x_cliente_id, tercero_id, tenido_id, articulo_tipo_id
FROM mes.partida
WHERE id = 6114
   OR numero IN (4632, 4631);


-- fn_precios_partida filters on partida_componente with lote_id IS NOT NULL
SELECT p.id, COUNT(pc.lote_id) AS rollos_asignados
FROM mes.partida p
LEFT JOIN mes.partida_componente pc ON pc.partida_id = p.id AND pc.lote_id IS NOT NULL
WHERE p.id IN (SELECT id FROM mes.partida WHERE numero IN (4631, 4632))
   OR p.id = 6114
GROUP BY p.id;


SELECT opp.partida_id, op.codigo, op.nombre,
       EXISTS (
           SELECT 1 FROM mes.partida_paso_ejecucion pe
           WHERE pe.partida_paso_id = opp.id AND pe.estado = 'COMPLETADO'
       ) AS completado
FROM mes.partida_paso opp
JOIN mes.operacion op ON op.id = opp.operacion_id
WHERE opp.partida_id IN (6114 /*, other id */);


-- vw_precios_pendientes requires an approved recipe for TENIDO
-- Run for the specific dimensions of partida 6114
SELECT rt.id, rt.flg_produccion, rt.flg_antipilling,
       rt.color_x_cliente_id, rt.articulo_tipo_id, rt.fibra, rt.tenido_id
FROM receta.tenido rt
WHERE rt.color_x_cliente_id = (SELECT color_x_cliente_id FROM mes.partida WHERE id = 6114)
  AND rt.articulo_tipo_id   = (SELECT articulo_tipo_id    FROM mes.partida WHERE id = 6114)
  AND rt.tenido_id          = (SELECT tenido_id           FROM mes.partida WHERE id = 6114);


SELECT cp.*
FROM doc.catalogo_precios cp
WHERE cp.fyh_elm IS NULL
  AND cp.color_x_cliente_id = (SELECT color_x_cliente_id FROM mes.partida WHERE id = 6114)
  AND (cp.articulo_tipo_id IS NULL
       OR cp.articulo_tipo_id = doc.fn_familia_precio(
           (SELECT articulo_tipo_id FROM mes.partida WHERE id = 6114),
           (SELECT tercero_id FROM mes.partida WHERE id = 6114)
       ));


SELECT id, estado_facturacion FROM mes.partida WHERE id = 6114;







-- Mirror the EXACT TENIDO gate from vw_precios_pendientes, per partida.
-- fibra=1 for all three (confirmed). Base variant → flg_antipilling=false.
WITH parts(partida_id, cxc, tipo, ten, fibra) AS (
    VALUES (6111, 1587, 18::smallint, 4, 1::smallint),
           (6112, 31,   18::smallint, 4, 1::smallint),
           (6114, 1585, 18::smallint, 4, 1::smallint)
)
SELECT pp.partida_id, pp.cxc,
       EXISTS (
         SELECT 1 FROM receta.tenido rt
         WHERE rt.flg_produccion = true
           AND (rt.color_x_cliente_id IS NULL OR rt.color_x_cliente_id = pp.cxc)
           AND rt.articulo_tipo_id = pp.tipo
           AND rt.fibra            = pp.fibra
           AND (rt.tenido_id IS NULL OR rt.tenido_id = pp.ten)
           AND rt.flg_antipilling  = false
       ) AS tenido_gate_passes
FROM parts pp;


-- Mirror the EXACT TENIDO gate from vw_precios_pendientes, per partida.
-- fibra=1 for all three (confirmed). Base variant → flg_antipilling=false.
WITH parts(partida_id, cxc, tipo, ten, fibra) AS (
    VALUES (6111, 1587, 18::smallint, 4, 1::smallint),
           (6112, 31,   18::smallint, 4, 1::smallint),
           (6114, 1585, 18::smallint, 4, 1::smallint)
)
SELECT pp.partida_id, pp.cxc,
       EXISTS (
         SELECT 1 FROM receta.tenido rt
         WHERE rt.flg_produccion = true
           AND (rt.color_x_cliente_id IS NULL OR rt.color_x_cliente_id = pp.cxc)
           AND rt.articulo_tipo_id = pp.tipo
           AND rt.fibra            = pp.fibra
           AND (rt.tenido_id IS NULL OR rt.tenido_id = pp.ten)
           AND rt.flg_antipilling  = false
       ) AS tenido_gate_passes
FROM parts pp;


SELECT flg_produccion, flg_antipilling, fibra,
       color_x_cliente_id,
       COUNT(*) AS n
FROM receta.tenido
WHERE articulo_tipo_id = 18 AND tenido_id = 4
GROUP BY flg_produccion, flg_antipilling, fibra, color_x_cliente_id
ORDER BY flg_produccion DESC, color_x_cliente_id NULLS FIRST;




SELECT id, flg_produccion, flg_antipilling, color_x_cliente_id, fibra, tenido_id
FROM receta.tenido
WHERE articulo_tipo_id = 18 AND tenido_id = 4
  AND color_x_cliente_id IN (1585, 1587, 31);


SELECT id, flg_produccion, flg_antipilling, color_x_cliente_id, fibra, tenido_id
FROM receta.tenido
WHERE articulo_tipo_id = 18 AND tenido_id = 4
  AND color_x_cliente_id IN (1585, 1587, 31);



SELECT id, tipo_receta_id, flg_activo, flg_produccion,
       color_x_cliente_id, tipo_articulo_id, fibra, tenido_id, flg_antipilling
FROM receta2
WHERE tipo_articulo_id = 18 AND tenido_id = 4
  AND color_x_cliente_id IN (1585, 1587, 31);







SELECT
  p.id AS partida_id,
  p.color_x_cliente_id AS p_cxc,    rt.color_x_cliente_id AS r_cxc,
  p.articulo_tipo_id   AS p_tipo,   rt.articulo_tipo_id   AS r_tipo,
  p.tenido_id          AS p_tenido, rt.tenido_id          AS r_tenido,
  p.flg_antipilling    AS p_antip,  rt.flg_antipilling    AS r_antip
FROM mes.partida p
JOIN mes.partida_paso pp ON pp.partida_id = p.id
JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
LEFT JOIN receta.tenido rt ON rt.id = pp.receta_id
WHERE p.id IN (6112, 6114);

ROLLBACK

SELECT * FROM public.articulo_tipo WHERE id IN (4, 18);
SELECT cxc.id, cxc.color_id, c.color, cxc.tercero_id, t.nombre AS cliente
FROM color_x_cliente cxc
JOIN public.color c ON c.id = cxc.color_id
JOIN tercero t      ON t.id = cxc.tercero_id
WHERE cxc.id IN (31, 257, 1585, 929)
ORDER BY cxc.color_id;
SELECT doc.fn_familia_precio(18::smallint, 225) AS fam_18,
       doc.fn_familia_precio(4::smallint, 225)  AS fam_4;



WITH partidas_tenido AS (
    SELECT DISTINCT
        p.id, p.color_x_cliente_id, p.tercero_id,
        p.articulo_tipo_id, p.tenido_id, p.flg_antipilling,
        (SELECT ar.fibra
         FROM mes.partida_componente pc
         JOIN inventario.lote l ON l.id = pc.lote_id
         JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
         JOIN articulo ar ON ar.id = ird.articulo_id
         WHERE pc.partida_id = p.id AND pc.lote_id IS NOT NULL
         LIMIT 1)::smallint AS fibra
    FROM mes.partida p
    JOIN mes.partida_paso pp ON pp.partida_id = p.id
    JOIN mes.operacion op    ON op.id = pp.operacion_id AND op.codigo = 'TENIDO'
    WHERE p.fyh_elm IS NULL
      AND p.estado_facturacion <> 'facturado'
      AND EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id AND pe.estado = 'COMPLETADO'
      )
)
SELECT
    pt.id AS partida_id,
    EXTRACT(YEAR FROM pp2.fyh_cre)::text || '-' ||
        LPAD(pp2.numero::text, 4, '0') AS codigo,
    t.nombre  AS cliente,
    c.color,
    at.nombre AS articulo_tipo
FROM partidas_tenido pt
JOIN mes.partida pp2          ON pp2.id = pt.id
JOIN tercero t                ON t.id = pt.tercero_id
JOIN color_x_cliente cxc      ON cxc.id = pt.color_x_cliente_id
JOIN public.color c           ON c.id = cxc.color_id
JOIN public.articulo_tipo at  ON at.id = pt.articulo_tipo_id
WHERE NOT EXISTS (
    SELECT 1 FROM receta.tenido rt
    WHERE rt.flg_produccion = true
      AND (rt.color_x_cliente_id IS NULL OR rt.color_x_cliente_id = pt.color_x_cliente_id)
      AND rt.articulo_tipo_id = pt.articulo_tipo_id
      AND rt.fibra            = pt.fibra
      AND (rt.tenido_id IS NULL OR rt.tenido_id = pt.tenido_id)
      AND rt.flg_antipilling  = COALESCE(pt.flg_antipilling, false)
)
ORDER BY t.nombre, c.color, at.nombre, pt.id;



-- ── 1. Color (color_x_cliente_id) → match the assigned recipe's cxc ──
-- Same physical color (Azulino 22 / Italiano 69); only the shade entry changes.
-- Billing client unaffected (stays on partida.tercero_id = 225).
UPDATE mes.partida p
SET color_x_cliente_id = v.cxc,
    usr_mod = 4,
    fyh_mod = NOW()
FROM (VALUES (6112, 257), (6114, 929)) AS v(pid, cxc)
WHERE p.id = v.pid;


-- 6112 — Azulino, Dueñas, J301 Card, después de corrección
SELECT * FROM doc.fn_precio_info(
    2,    -- TENIDO operacion_id
    257,  -- color_x_cliente_id (post-update)
    225,  -- tercero_id (Dueñas, unchanged)
    4,    -- articulo_tipo_id (J301 Card, post-update)
    4,    -- tenido_id
    1,    -- fibra (algodón)
    false -- flg_antipilling
);

-- 6114 — Italiano, Dueñas, J301 Card, después de corrección
SELECT * FROM doc.fn_precio_info(
    2,    -- TENIDO operacion_id
    929,  -- color_x_cliente_id (post-update)
    225,  -- tercero_id (Dueñas, unchanged)
    4,    -- articulo_tipo_id (J301 Card, post-update)
    4,    -- tenido_id
    1,    -- fibra (algodón)
    false -- flg_antipilling
);




-- 1. What entregas are linked?
SELECT ce.entrega_id, e.serie, e.correlativo, e.fecha_recepcion
FROM doc.compra_entrega ce
JOIN doc.entrega e ON e.id = ce.entrega_id
WHERE ce.compra_id = 989;

-- 2. Any entrega_detalle lines for those entregas?
SELECT grd.entrega_id, grd.item_id, grd.cantidad
FROM doc.compra_entrega ce
JOIN doc.entrega_detalle grd ON grd.entrega_id = ce.entrega_id
WHERE ce.compra_id = 989;

-- 3. Any movements via those entregas?
SELECT im.documento_tipo, im.documento_id, im.item_id, im.cantidad, imt.codigo
FROM doc.compra_entrega ce
JOIN inventario.item_movimientos im 
    ON im.documento_tipo = 'entrega' AND im.documento_id = ce.entrega_id
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE ce.compra_id = 989;

-- 4. Any direct compra movements?
SELECT im.item_id, im.cantidad, imt.codigo
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE im.documento_tipo = 'compra' AND im.documento_id = 989;


UPDATE doc.compra_detalle cd
SET cantidad_recibida = COALESCE((
    SELECT SUM(im.cantidad)
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE imt.codigo = 'COMPRA_ING'
      AND im.item_id = cd.item_id
      AND im.documento_tipo = 'compra'
      AND im.documento_id = 989
), 0)
WHERE cd.compra_id = 989;



ROLLBACK;
SELECT * FROM doc.orden_servicio;
SELECT * FROM doc.orden_servicio_detalle;
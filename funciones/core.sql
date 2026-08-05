
CREATE OR REPLACE FUNCTION public.get_item(p_item_id int)
RETURNS jsonb
LANGUAGE sql
AS $$
SELECT
jsonb_build_object('item',
jsonb_build_object(
    'id', i.item_id,
    'codigo', i.item_codigo,
    'nombre', i.item_nombre,
    'item_tipo_id', i.item_tipo_id,
    'item_tipo_codigo', i.item_tipo_codigo,
    'unidad_id', i.unidad_id,
    'unidad_codigo', i.unidad_codigo,
    'detalle', 
        CASE i.item_tipo_codigo
      WHEN 'INSUMO' THEN jsonb_build_object(
        'insumo', (
          SELECT jsonb_build_object(
            'medida', iin.medida,
            'insumo_tipo', jsonb_build_object(
              'id', ti.id,
              'codigo', ti.codigo,
              'nombre', ti.nombre
            ),
            'colorante_tipo',
              CASE WHEN iin.colorante_tipo_id IS NOT NULL THEN
                jsonb_build_object(
                  'id', tc.id,
                  'nombre', tc.nombre
                )
              END
          )
          FROM item_insumo_detalle iin
          JOIN insumo_tipo ti ON ti.id = iin.insumo_tipo_id
          LEFT JOIN colorante_tipo tc ON tc.id = iin.colorante_tipo_id
          WHERE iin.item_id = i.item_id
        )
      )

      WHEN 'ROLLO' THEN jsonb_build_object(
        'rollo', (
          SELECT jsonb_build_object(
            'articulo_id', ir.articulo_id,
            'articulo',ar.nombre,
            'grupo_articulo_id', ta.id,
            'grupo_articulo', ta.nombre,
            'fibra', ar.fibra,
            'flg_rib', ir.flg_rib,
            'construccion_id', ar.construccion_id,
            'construccion', co.nombre,
            'titulo', ar.titulo,
            'preparacion', ar.preparacion
          )
          FROM item_rollo_detalle ir
          LEFT JOIN articulo ar ON ar.id=ir.articulo_id
          LEFT JOIN grupo_articulo_miembro gam ON gam.articulo_id = ar.id
          LEFT JOIN grupo_articulo ta ON ta.id = gam.grupo_articulo_id
          LEFT JOIN construccion co ON co.id = ar.construccion_id
          WHERE ir.item_id = i.item_id
        )
      )
    END
))
FROM vw_items i
WHERE i.item_id = p_item_id;
$$;

CREATE OR REPLACE FUNCTION public.crear_item_insumo(p_item jsonb, p_item_id int)
RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_usr_id int := get_user_id();
BEGIN
    IF p_item ? 'medida' AND p_item ? 'insumo_tipo_id' THEN
    BEGIN
        INSERT INTO item_insumo_detalle (item_id, medida, insumo_tipo_id, colorante_tipo_id)
        VALUES (
            p_item_id,
            (p_item->>'medida')::medida_enum,
            (p_item->>'insumo_tipo_id')::SMALLINT,
            CASE
                WHEN p_item ? 'colorante_tipo_id' THEN (p_item->>'colorante_tipo_id')::SMALLINT
                ELSE NULL
            END
        );
        EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_item_insumo - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_item::TEXT, v_message, v_detail;
        RAISE;
        END;
    ELSE
       RAISE EXCEPTION
        'Los campos medida e insumo_tipo_id son obligatorios para crear un item de tipo insumo';
    END IF;
    RETURN format('Detalle de insumo para item_id %s creado correctamente.', p_item_id);
END;
$function$;
CREATE OR REPLACE FUNCTION public.crear_item_rollo(p_item jsonb, p_item_id int)
RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_usr_id int := get_user_id();
BEGIN
    IF p_item ? 'articulo_id' THEN
    BEGIN
        INSERT INTO item_rollo_detalle (item_id, articulo_id, flg_rib)
        VALUES (
            p_item_id,
            (p_item->>'articulo_id')::INT,
            COALESCE((p_item->>'flg_rib')::BOOLEAN, FALSE)
        );
        EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_item_rollo - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_item::TEXT, v_message, v_detail;
        RAISE;
        END;
    ELSE
       RAISE EXCEPTION
        'El campo articulo_id es obligatorio para crear un item de tipo rollo';
    END IF;
    RETURN format('Detalle de rollo para item_id %s creado correctamente.', p_item_id);
END;
$function$;


CREATE OR REPLACE FUNCTION inventario.get_almacen(p_almacen_id int)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT 
jsonb_build_object(
    'id', a.id,
    'codigo', a.codigo,
    'nombre', a.nombre,
    'ubicaciones', (
        SELECT jsonb_agg( 
            jsonb_build_object(
                'id', u.id,
                'codigo', u.codigo,
                'nombre', u.nombre
            )
        )
        FROM inventario.ubicacion u
        WHERE u.almacen_id = a.id
    )
)FROM inventario.almacen a WHERE a.id = p_almacen_id;
$$;


CREATE OR REPLACE FUNCTION inventario.crear_almacen(p_almacen json)
RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','doc','inventario'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_almacen_id   INT;
    v_entrega_tipo entrega_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_lote_id int;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('configuracion.operacional') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.operacional'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

INSERT INTO inventario.almacen(codigo,nombre,usr_cre)
VALUES ((p_almacen->>'codigo')::TEXT,(p_almacen->>'nombre')::TEXT,v_usr_id)
RETURNING id INTO v_almacen_id;
IF p_almacen ? 'ubicaciones' THEN
    INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,usr_cre)
    SELECT v_almacen_id,(u->>'codigo')::TEXT,(u->>'nombre')::TEXT,v_usr_id
    FROM jsonb_array_elements(p_almacen->'ubicaciones') AS u;
END IF;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nuevo almacen y ubicaciones', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' creó un nuevo almacen y ubicaciones', 'info',jsonb_build_object('objeto_tipo','almacen','almacen_id',v_almacen_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras','inventario') AND v_usr_id<>ur.user_id;
   RETURN format('Almacen con ID %s creado correctamente.', v_almacen_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_almacen - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_almacen::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION inventario.modificar_almacen(p_almacen json)
RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','doc','inventario'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_almacen_id   INT;
    v_entrega_tipo entrega_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_lote_id int;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('configuracion.operacional') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.operacional'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

v_almacen_id := (p_almacen->>'id')::INT;

UPDATE inventario.almacen
SET codigo = (p_almacen->>'codigo')::TEXT,
    nombre = (p_almacen->>'nombre')::TEXT,
    usr_mod = v_usr_id,
    fyh_mod = NOW()
WHERE id = v_almacen_id;

IF p_almacen ? 'ubicaciones' THEN
    INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,usr_cre)
    SELECT (p_almacen->>'id')::INT,(u->>'codigo')::TEXT,(u->>'nombre')::TEXT,v_usr_id
    FROM jsonb_array_elements(p_almacen->'ubicaciones') AS u
    ON CONFLICT (almacen_id,codigo_canon) DO UPDATE SET nombre = EXCLUDED.nombre, usr_mod = v_usr_id, fyh_mod = NOW();

    DELETE FROM inventario.ubicacion WHERE almacen_id = (p_almacen->>'id')::INT
    AND codigo NOT IN (SELECT u->>'codigo' FROM jsonb_array_elements(p_almacen->'ubicaciones') AS u);
END IF;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Almacen y/o ubicaciones actualizadas', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' modifico un almacen y/o sus ubicaciones', 'info',jsonb_build_object('objeto_tipo','almacen','almacen_id',v_almacen_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras','inventario') AND v_usr_id<>ur.user_id;
   RETURN format('Almacen con ID %s modificado correctamente.', v_almacen_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in modificar_almacen - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_almacen::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


CREATE OR REPLACE FUNCTION inventario.eliminar_almacen(p_almacen_id int)
RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','doc','inventario'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_almacen_id   INT;
    v_entrega_tipo entrega_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_almacen_nombre text;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('configuracion.operacional') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.operacional'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

DELETE FROM inventario.ubicacion WHERE almacen_id = p_almacen_id;
DELETE FROM inventario.almacen WHERE id = p_almacen_id
RETURNING nombre INTO v_almacen_nombre;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Almacen eliminado', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' eliminó un almacen y sus ubicaciones', 'info',jsonb_build_object('objeto_tipo','almacen','almacen_id',p_almacen_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras','inventario') AND v_usr_id<>ur.user_id;
   RETURN format('Almacen %s eliminado ', v_almacen_nombre);
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'No se puede eliminar el almacen porque tiene ubicaciones en uso.';
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in eliminar_almacen - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_almacen_id, v_message, v_detail;
        RAISE;
END;
$function$;


----LOGICA PARA VALIDAR ROLLOS A RESERVAR
-- --------------------------------------------------
-- ---VALIDAR DISPONIBILIDAD DE ROLLOS RESERVADOS
-- --------------------------------------------------
-- WITH partida_rollos AS (
--         SELECT
--             (i->>'item_id')::int        AS item_id,
--             (i->>'lote_id')::int        AS lote_id,
--             (i->>'ubicacion_id')::int  AS ubicacion_id,
--             SUM((i->>'cantidad')::numeric)  AS cantidad
--         FROM jsonb_array_elements(p_partida->'partida_rollos') i
--         GROUP BY 1,2,3
--     ),errores as(  SELECT
--             im.item_id,
--             im.lote_id,
--             COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id) AS ubicacion_id,
--             items.cantidad,
--             SUM(
--                 CASE
--                     WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad
--                     WHEN im.movimiento_tipo = 'EGRESO'  THEN -im.cantidad
--                 END
--             ) AS saldo
--         FROM inventario.item_movimientos im
--         JOIN partida_rollos AS items ON items.item_id=im.item_id AND items.lote_id=im.lote_id AND items.ubicacion_id= COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
--         GROUP BY im.item_id, im.lote_id, COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id),items.cantidad
--         HAVING SUM(
--                 CASE
--                     WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad
--                     WHEN im.movimiento_tipo = 'EGRESO'  THEN -im.cantidad
--                 END
--             )< items.cantidad
--     ) SELECT jsonb_agg(
--         jsonb_build_object(
--             'item_id', item_id,
--             'lote_id', lote_id,
--             'ubicacion_id', ubicacion_id,
--             'saldo_disponible', saldo,
--             'cantidad_requerida', cantidad
--         )
--     )
--     INTO v_error_payload
--     FROM errores;
--     IF v_error_payload IS NOT NULL THEN 
--         RAISE EXCEPTION
--             'Stock insuficiente para emitir la guía'
--             USING
--                 DETAIL  = v_error_payload::text;
--     END IF;




-- ─────────────────────────────────────────────────────────────────────────────
-- mes.crear_partida
-- Creates a production order atomically: header, planned items, steps, and
-- optionally roll reservations.  Merges the old crear_partida (commercial
-- header) + crear_proceso (steps + roll assignment) into a single call so no
-- partial state can exist after creation.
--
-- Required payload fields:
--   tercero_id, color_x_cliente_id, tenido_id, grupo_articulo_id, fibra
--   partida_detalles[]  — { item_id, cantidad, unidad_id }
--
-- Optional payload fields:
--   pasos[]      — steps; can be added later via actualizar_pasos_partida while
--                  order is in CREADA/PENDIENTE state.
--     each paso: { secuencia, operacion_id, receta_id?,
--                  ph_objetivo?, temperatura_objetivo?, tiempo_estandar?,
--                  relacion_bano_objetivo? }
--     (machine is NOT set here — it is assigned on the scheduling board, mes.programacion)
--   componentes[] — roll reservations; can be supplied now or later via
--                   actualizar_componentes_partida.
--     each componente: { lote_id, cantidad }
--     ubicacion_id is NOT required — derived from item_movimientos.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mes.crear_partida(p_partida jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'mes', 'inventario'
AS $function$
DECLARE
    v_message        text;
    v_detail         text;
    v_hint           text;
    v_context        text;
    v_sqlstate       text;
    v_partida_id           BIGINT;
    v_usr_id               int := get_user_id();
    v_error_payload        jsonb;
    v_overflow_item_id     INT;
    v_rollos_submitted     INT;
    v_cantidad_planificada NUMERIC;
    v_grupo                INT;
    v_fibra                SMALLINT;
    v_fibra_max            SMALLINT;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- ── Required header fields ────────────────────────────────────────────────
    IF (p_partida->>'tercero_id') IS NULL THEN
        RAISE EXCEPTION 'tercero_id es requerido' USING ERRCODE = 'not_null_violation';
    END IF;
    IF (p_partida->>'color_x_cliente_id') IS NULL THEN
        RAISE EXCEPTION 'color_x_cliente_id es requerido' USING ERRCODE = 'not_null_violation';
    END IF;
    IF (p_partida->>'tenido_id') IS NULL THEN
        RAISE EXCEPTION 'tenido_id es requerido' USING ERRCODE = 'not_null_violation';
    END IF;
    -- CLEAN BREAK (migración 32): la partida se identifica por grupo_articulo_id.
    -- grupo_articulo_id no se acepta ni se escribe aquí — lo deriva del grupo el
    -- trigger trg_bi_partida_derive_grupo_articulo (puente temporal hasta que la
    -- migración de precios mueva a sus lectores).
    IF (p_partida->>'grupo_articulo_id') IS NULL THEN
        RAISE EXCEPTION 'grupo_articulo_id es requerido' USING ERRCODE = 'not_null_violation';
    END IF;
    IF (p_partida->>'fibra') IS NULL THEN
        RAISE EXCEPTION 'fibra es requerido' USING ERRCODE = 'not_null_violation';
    END IF;

    v_grupo := (p_partida->>'grupo_articulo_id')::int;
    v_fibra := (p_partida->>'fibra')::smallint;

    PERFORM 1 FROM grupo_articulo WHERE id = v_grupo AND fyh_elm IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'grupo_articulo_id % no existe o está dado de baja.', v_grupo
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- ── Techo de fibra ────────────────────────────────────────────────────────
    -- fibra = sistemas de tintura EJECUTADOS. Puede ser MENOR a lo que el sustrato
    -- requiere (colores jaspeados: reactivo solo sobre algodón/poliéster deja el
    -- poliéster blanco), pero nunca MAYOR — correr disperso sobre algodón puro no
    -- tiene sentido. El techo es el MAX de lo que requieren los miembros del grupo.
    SELECT MAX(a.fibra) INTO v_fibra_max
    FROM grupo_articulo_miembro gm
    JOIN articulo a ON a.id = gm.articulo_id
    WHERE gm.grupo_articulo_id = v_grupo;

    IF v_fibra_max IS NOT NULL AND v_fibra > v_fibra_max THEN
        RAISE EXCEPTION
            'fibra % excede el máximo del grupo (%): no se pueden correr más sistemas de tintura de los que requiere el sustrato.',
            v_fibra, v_fibra_max
            USING ERRCODE = 'check_violation';
    END IF;

    -- ── Roll validations (only when componentes provided) ────────────────────
    IF p_partida->'componentes' IS NOT NULL AND jsonb_array_length(p_partida->'componentes') > 0 THEN

        -- Stock availability: ubicacion derived from item_movimientos (rolls are unsplittable)
        WITH solicitado AS (
            SELECT (c->>'lote_id')::int      AS lote_id,
                   (c->>'cantidad')::numeric  AS cantidad
            FROM jsonb_array_elements(p_partida->'componentes') c
        )
        SELECT jsonb_agg(jsonb_build_object(
            'lote_id',            s.lote_id,
            'cantidad_requerida', s.cantidad,
            'saldo_disponible',   COALESCE(sa.cantidad_disponible, 0)
        ))
        INTO v_error_payload
        FROM solicitado s
        LEFT JOIN inventario.vw_stock_lotes sa ON sa.lote_id = s.lote_id
        WHERE COALESCE(sa.cantidad_disponible, 0) < s.cantidad;

        IF v_error_payload IS NOT NULL THEN
            RAISE EXCEPTION 'Stock insuficiente para reservar los rollos'
                USING DETAIL = v_error_payload::text;
        END IF;

        -- Composición: cada rollo asignado debe pertenecer al grupo de la partida.
        -- Reemplaza la antigua igualdad contra grupo_articulo_id: misma severidad,
        -- pero expresable para lotes mezclados — un grupo con varios miembros acepta
        -- rollos de cualquiera de ellos, y sigue rechazando telas ajenas al grupo.
        IF EXISTS (
            SELECT 1
            FROM jsonb_array_elements(p_partida->'componentes') c
            JOIN inventario.lote l      ON l.id  = (c->>'lote_id')::int
            JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
            JOIN articulo a             ON a.id   = ird.articulo_id
            WHERE NOT EXISTS (
                SELECT 1 FROM grupo_articulo_miembro gm
                WHERE gm.grupo_articulo_id = v_grupo
                  AND gm.articulo_id       = a.id
            )
        ) THEN
            RAISE EXCEPTION 'Los rollos asignados no pertenecen al grupo de artículo de la partida'
                USING ERRCODE = 'check_violation';
        END IF;

        -- Double-booking: roll must not be reserved in another active order
        IF EXISTS (
            SELECT 1
            FROM jsonb_array_elements(p_partida->'componentes') c
            JOIN mes.partida_componente pc ON pc.lote_id  = (c->>'lote_id')::int
            JOIN mes.partida pr            ON pr.id       = pc.partida_id
            WHERE pc.lote_id IS NOT NULL
              AND pr.estado_produccion NOT IN ('CANCELADA', 'TECO', 'CERRADA')
        ) THEN
            RAISE EXCEPTION 'Uno o más rollos ya están reservados en otra orden activa'
                USING ERRCODE = 'check_violation';
        END IF;

    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_partida', v_usr_id, p_partida);

    -- ── Header ────────────────────────────────────────────────────────────────
    INSERT INTO mes.partida (
        prioridad_id, tercero_id, tenido_id, grupo_articulo_id, fibra,
        malla, rendimiento, ancho, color_x_cliente_id, flg_antipilling, flg_doble_bolsa,
        fecha_acordada, observacion
    )
    VALUES (
        (p_partida->>'prioridad_id')::int,
        (p_partida->>'tercero_id')::int,
        (p_partida->>'tenido_id')::int,
        v_grupo,
        v_fibra,
        p_partida->>'malla',
        p_partida->>'rendimiento',
        p_partida->>'ancho',
        (p_partida->>'color_x_cliente_id')::int,
        COALESCE((p_partida->>'flg_antipilling')::boolean, false),
        COALESCE((p_partida->>'flg_doble_bolsa')::boolean, false),
        (p_partida->>'fecha_acordada')::date,
        p_partida->>'observacion'
    )
    RETURNING id INTO v_partida_id;

    -- ── Planned items / quantities ────────────────────────────────────────────
    INSERT INTO mes.partida_detalle(partida_id, item_id, cantidad, unidad_id)
    SELECT v_partida_id,
           (u->>'item_id')::int,
           (u->>'cantidad')::numeric,
           (u->>'unidad_id')::int
    FROM jsonb_array_elements(p_partida->'partida_detalles') u;

    -- ── Steps (optional at creation; add later via actualizar_pasos_partida) ──
    IF p_partida->'pasos' IS NOT NULL AND jsonb_array_length(p_partida->'pasos') > 0 THEN
        -- Machine is assigned later on the scheduling board (mes.programacion), not here.
        -- Bath ratio lives on programacion (machine-coupled), not on paso.
        -- Backend computes secuencia from array position to avoid frontend desync bugs.
        INSERT INTO mes.partida_paso(
            partida_id, secuencia, operacion_id,
            receta_id,
            ph_objetivo, temperatura_objetivo, tiempo_estandar
        )
        SELECT
            v_partida_id,
            (ROW_NUMBER() OVER ()) * 10,
            (p->>'operacion_id')::smallint,
            (p->>'receta_id')::int,
            (p->>'ph_objetivo')::numeric,
            (p->>'temperatura_objetivo')::numeric,
            (p->>'tiempo_estandar')::int
        FROM jsonb_array_elements(p_partida->'pasos') WITH ORDINALITY AS t(p, idx);
    END IF;

    -- ── Roll reservations (optional at creation; validated above if present) ──
    IF p_partida->'componentes' IS NOT NULL AND jsonb_array_length(p_partida->'componentes') > 0 THEN

        -- Per-item roll count guard: submitted rolls per item_id must not exceed partida_detalle.cantidad.
        -- Also catches rolls whose item has no partida_detalle entry (unplanned item).
        SELECT l.item_id, COUNT(*)::int, pd.cantidad
        INTO v_overflow_item_id, v_rollos_submitted, v_cantidad_planificada
        FROM jsonb_array_elements(p_partida->'componentes') c
        JOIN inventario.lote l ON l.id = (c->>'lote_id')::int
        LEFT JOIN mes.partida_detalle pd ON pd.item_id = l.item_id
                                        AND pd.partida_id = v_partida_id
        WHERE (c->>'lote_id') IS NOT NULL
        GROUP BY l.item_id, pd.cantidad
        HAVING COUNT(*) > COALESCE(pd.cantidad, 0)
        LIMIT 1;

        IF v_overflow_item_id IS NOT NULL THEN
            RAISE EXCEPTION
                'El ítem % tiene % rollos asignados pero solo % están planificados.',
                v_overflow_item_id, v_rollos_submitted, COALESCE(v_cantidad_planificada, 0)
                USING ERRCODE = 'check_violation';
        END IF;

        INSERT INTO mes.partida_componente(partida_id, lote_id, cantidad_reservada)
        SELECT v_partida_id,
               (c->>'lote_id')::int,
               (c->>'cantidad')::numeric
        FROM jsonb_array_elements(p_partida->'componentes') c
        WHERE (c->>'lote_id') IS NOT NULL;
    END IF;

    -- -- ── Auto-request recipe if no live recipe exists for this spec ────────────
    -- PERFORM receta.solicitar_si_ausente(v_partida_id);

    -- ── Notify plant staff ────────────────────────────────────────────────────
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Nueva Orden de Producción',
           COALESCE(
               (SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido
                FROM usuario WHERE id = v_usr_id),
               'sistema'
           ) || ' creó la orden de producción #' || v_partida_id,
           'info',
           jsonb_build_object('objeto_tipo', 'partida', 'partida_id', v_partida_id)
    FROM iam.user_rol ur
    LEFT JOIN usuario p ON p.id = ur.user_id
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras')
      AND v_usr_id <> ur.user_id;

    PERFORM mes.actualizar_estado_partida(v_partida_id);

    RETURN jsonb_build_object(
        'partida_id', v_partida_id,
        'message',    format('Orden de producción #%s creada correctamente.', v_partida_id)
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE LOG 'Error in crear_partida - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_partida::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION mes.actualizar_partida(p_partida_id INT, p_partida jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public', 'doc', 'mes'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_estado    text;
    v_usr_id    int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_partida', v_usr_id, jsonb_build_object('partida_id', p_partida_id, 'partida', p_partida));

    -- Get current state
    SELECT estado_produccion INTO v_estado
    FROM mes.partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida con ID % no encontrada.', p_partida_id;
    END IF;

    -- Reject if terminal state
    IF v_estado IN ('CERRADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'No se puede modificar una partida en estado %.', v_estado;
    END IF;

    -------------------------------------------------------------------------
    -- Always editable: prioridad_id, observacion
    -------------------------------------------------------------------------
    UPDATE mes.partida
    SET prioridad_id = (p_partida->>'prioridad_id')::INT,
        observacion  = p_partida->>'observacion'
    WHERE id = p_partida_id;

    -------------------------------------------------------------------------
    -- CREADA or PLANIFICADA: also malla, rendimiento
    -------------------------------------------------------------------------
    IF v_estado IN ('CREADA', 'PLANIFICADA') THEN
        UPDATE mes.partida
        SET malla          = (p_partida->>'malla')::TEXT,
            rendimiento    = p_partida->>'rendimiento',
            fecha_acordada = (p_partida->>'fecha_acordada')::DATE
        WHERE id = p_partida_id;
    END IF;

    -------------------------------------------------------------------------
    -- CREADA only: identity fields — tercero, tenido, color, grupo_articulo, fibra, antipilling
    -------------------------------------------------------------------------
    IF v_estado = 'CREADA' THEN
        UPDATE mes.partida
        SET tercero_id          = COALESCE((p_partida->>'tercero_id')::INT,           tercero_id),
            tenido_id           = COALESCE((p_partida->>'tenido_id')::INT,            tenido_id),
            color_x_cliente_id  = COALESCE((p_partida->>'color_x_cliente_id')::INT,  color_x_cliente_id),
            -- Identidad de sustrato: grupo_articulo_id. grupo_articulo_id lo deriva el
            -- trigger trg_bi_partida_derive_grupo_articulo; nunca se escribe aquí.
            grupo_articulo_id   = COALESCE((p_partida->>'grupo_articulo_id')::INT,   grupo_articulo_id),
            fibra               = COALESCE((p_partida->>'fibra')::SMALLINT,           fibra),
            flg_antipilling     = COALESCE((p_partida->>'flg_antipilling')::BOOLEAN,  flg_antipilling),
            flg_doble_bolsa     = COALESCE((p_partida->>'flg_doble_bolsa')::BOOLEAN,  flg_doble_bolsa),
            fecha_acordada      = (p_partida->>'fecha_acordada')::DATE
        WHERE id = p_partida_id;

        -- Full replace of detail rows
       -- Remove rows no longer in the incoming array
DELETE FROM mes.partida_detalle pd
WHERE pd.partida_id = p_partida_id
  AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_partida->'partida_detalles') u
      WHERE (u->>'item_id')::INT = pd.item_id
  );

-- Upsert the rest
INSERT INTO mes.partida_detalle(partida_id, item_id, cantidad,unidad_id)
SELECT p_partida_id, (u->>'item_id')::INT, (u->>'cantidad')::INT, (u->>'unidad_id')::INT
FROM jsonb_array_elements(p_partida->'partida_detalles') u
ON CONFLICT (partida_id, item_id) DO UPDATE
  SET cantidad = EXCLUDED.cantidad;

    END IF;

    -------------------------------------------------------------------------
    -- Notification
    -------------------------------------------------------------------------
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Partida Modificada',
           COALESCE(
               (SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido
                FROM usuario WHERE id = v_usr_id),
               'sistema'
           ) || ' modificó la partida #' || p_partida_id,
           'info',
           jsonb_build_object('objeto_tipo', 'partida', 'partida_id', p_partida_id)
    FROM iam.user_rol ur
    LEFT JOIN usuario p ON p.id = ur.user_id
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras')
      AND v_usr_id <> ur.user_id;

    RETURN format('Partida con ID %s actualizada correctamente.', p_partida_id);

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error en actualizar_partida - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_partida::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


-- mes.get_partida defined in mes.sql (canonical).

-- ═══════════════════════════════════════════════════════════════
-- ACTUALIZAR PASOS DE ORDEN DE PRODUCCION (bulk)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.actualizar_pasos_partida(p_partida_id BIGINT, p_pasos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','mes'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id    int := get_user_id();
    v_estado    partida_estado_produccion_enum;
    v_count     int;
BEGIN
    IF NOT jwt_has_permission('produccion.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Validar que la orden existe y no está en estado terminal
    SELECT estado_produccion INTO v_estado
    FROM mes.partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden de producción con ID % no encontrada.', p_partida_id;
    END IF;

    IF v_estado IN ('TECO','CERRADA','CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden modificar pasos de una orden en estado %.', v_estado;
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_pasos_partida', v_usr_id, jsonb_build_object('partida_id', p_partida_id, 'pasos', p_pasos));

    -- Clear chemical reservations for pasos where receta_id is changing;
    -- generar_receta re-populates them after the frontend confirms the new recipe
    DELETE FROM mes.partida_componente
    WHERE item_id IS NOT NULL
      AND partida_paso_id IN (
          SELECT pp.id
          FROM mes.partida_paso pp
          JOIN jsonb_array_elements(p_pasos) p
            ON (p->>'secuencia')::SMALLINT = pp.secuencia
          WHERE pp.partida_id = p_partida_id
            AND pp.receta_id IS DISTINCT FROM (p->>'receta_id')::INT
      );

    -- Bulk upsert: update existing, insert new (planning columns only)
    -- Machine is assigned on the scheduling board (mes.programacion), not on the step.
    -- Bath ratio lives on programacion (machine-coupled), not on paso.
    -- Backend computes secuencia from array position to avoid frontend desync bugs.
    --
    -- secuencia MUST be numbered once across the whole ordered array — existing and
    -- new pasos share the range, so numbering them in two independent passes lets a
    -- new paso reuse a secuencia already held by an existing one (violates
    -- partida_paso_partida_id_secuencia_key). We therefore:
    --   0) delete removed pasos first (frees their secuencia slots),
    --   1) park surviving existing pasos in a temporary high range so no live row
    --      blocks the target secuencia (the unique constraint is not deferrable),
    --   2) UPDATE existing + INSERT new using one unified ROW_NUMBER over the array.

    -- 0) Eliminar pasos que ya no están en la lista (solo si no han sido ejecutados).
    -- Cascade first into mes.programacion: a deleted paso may still be sitting on
    -- the scheduling board, and leaving that row behind creates an orphan whose
    -- actividad_id points at nothing (get_programacion_diaria then silently
    -- returns paso_id=NULL for it, which poisons the frontend's next save).
    DELETE FROM mes.programacion
    WHERE actividad_tipo = 'partida_paso'
      AND actividad_id IN (
          SELECT pp.id
          FROM mes.partida_paso pp
          WHERE pp.partida_id = p_partida_id
            AND pp.id NOT IN (
                SELECT (p->>'id')::BIGINT
                FROM jsonb_array_elements(p_pasos) p
                WHERE p->>'id' IS NOT NULL
            )
            AND NOT EXISTS (
                SELECT 1 FROM mes.partida_paso_ejecucion pe
                WHERE pe.partida_paso_id = pp.id
            )
      );

    DELETE FROM mes.partida_paso
    WHERE partida_id = p_partida_id
      AND id NOT IN (
          SELECT (p->>'id')::BIGINT
          FROM jsonb_array_elements(p_pasos) p
          WHERE p->>'id' IS NOT NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = mes.partida_paso.id
      );

    -- 1) Park all surviving pasos out of the target secuencia range so neither the
    --    UPDATE nor the INSERT below transiently collides with a not-yet-moved row.
    UPDATE mes.partida_paso
    SET secuencia = secuencia + 10000
    WHERE partida_id = p_partida_id
      AND secuencia < 10000;

    -- Unified ordering: existing (has id) and new (no id) pasos numbered together
    -- by array position → 10, 20, 30 … with no cross-set overlap.
    WITH datos AS (
        SELECT
            (p->>'id')::BIGINT                    AS id,
            (ROW_NUMBER() OVER ()) * 10           AS secuencia,
            (p->>'operacion_id')::SMALLINT        AS operacion_id,
            (p->>'receta_id')::INT                AS receta_id,
            (p->>'ph_objetivo')::NUMERIC          AS ph_objetivo,
            (p->>'temperatura_objetivo')::NUMERIC AS temperatura_objetivo,
            (p->>'tiempo_estandar')::INT          AS tiempo_estandar
        FROM jsonb_array_elements(p_pasos) AS p
    )
    -- 2a) Update existing pasos by id
    UPDATE mes.partida_paso pp
    SET secuencia = d.secuencia,
        operacion_id = d.operacion_id,
        receta_id = d.receta_id,
        ph_objetivo = d.ph_objetivo,
        temperatura_objetivo = d.temperatura_objetivo,
        tiempo_estandar = d.tiempo_estandar,
        usr_mod = v_usr_id,
        fyh_mod = NOW()
    FROM datos d
    WHERE d.id IS NOT NULL
      AND pp.id = d.id
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id
            AND pe.estado IN ('EN_PROCESO', 'COMPLETADO', 'OMITIDO')
      );

    -- 2a-bis) Executed pasos are protected from column edits above, but their
    -- secuencia must still follow their array position (kept in sync with the
    -- reordered range) — otherwise the parked +10000 value would linger or the
    -- restore step would land on a slot already taken. Move only secuencia.
    UPDATE mes.partida_paso pp
    SET secuencia = d.secuencia
    FROM (
        SELECT
            (p->>'id')::BIGINT          AS id,
            (ROW_NUMBER() OVER ()) * 10 AS secuencia
        FROM jsonb_array_elements(p_pasos) AS p
    ) d
    WHERE d.id IS NOT NULL
      AND pp.id = d.id
      AND pp.secuencia >= 10000
      AND EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = pp.id
            AND pe.estado IN ('EN_PROCESO', 'COMPLETADO', 'OMITIDO')
      );

    -- 2b) Insert new pasos (without id), reusing the same unified secuencia
    INSERT INTO mes.partida_paso(
        partida_id, secuencia, operacion_id,
        receta_id,
        ph_objetivo, temperatura_objetivo, tiempo_estandar,
        usr_cre
    )
    WITH datos AS (
        SELECT
            (p->>'id')::BIGINT                    AS id,
            (ROW_NUMBER() OVER ()) * 10           AS secuencia,
            (p->>'operacion_id')::SMALLINT        AS operacion_id,
            (p->>'receta_id')::INT                AS receta_id,
            (p->>'ph_objetivo')::NUMERIC          AS ph_objetivo,
            (p->>'temperatura_objetivo')::NUMERIC AS temperatura_objetivo,
            (p->>'tiempo_estandar')::INT          AS tiempo_estandar
        FROM jsonb_array_elements(p_pasos) AS p
    )
    SELECT p_partida_id, d.secuencia, d.operacion_id,
           d.receta_id, d.ph_objetivo, d.temperatura_objetivo, d.tiempo_estandar,
           v_usr_id
    FROM datos d
    WHERE d.id IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Safety net: any paso still parked (present in DB but absent from p_pasos and
    -- undeletable due to an ejecucion) gets restored below the reordered range so it
    -- never collides. Should be empty in normal edits — the frontend always sends
    -- every non-removable paso — but guarantees no row is left stranded at +10000.
    UPDATE mes.partida_paso
    SET secuencia = secuencia - 10000 + 100000
    WHERE partida_id = p_partida_id
      AND secuencia >= 10000;

    PERFORM mes.actualizar_estado_partida(p_partida_id);

    RETURN format('%s pasos actualizados para orden #%s.', v_count, p_partida_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_pasos_partida - User: %, orden: %, Error: %, Detail: %',
              v_usr_id, p_partida_id, v_message, v_detail;
    RAISE;
END;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- ACTUALIZAR COMPONENTES DE ORDEN DE PRODUCCION
-- Guard: no paso in EN_PROCESO or COMPLETADO.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION mes.actualizar_componentes_partida(
    p_partida_id  BIGINT,
    p_componentes jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'mes', 'inventario'
AS $function$
DECLARE
    v_message  text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id               int  := get_user_id();
    v_estado               partida_estado_produccion_enum;
    v_error_payload        jsonb;
    v_overflow_item_id     INT;
    v_rollos_submitted     INT;
    v_cantidad_planificada NUMERIC;
BEGIN
    IF NOT jwt_has_permission('produccion.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT estado_produccion INTO v_estado
    FROM mes.partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden de producción con ID % no encontrada.', p_partida_id;
    END IF;

    IF v_estado IN ('TECO','CERRADA','CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden modificar componentes de una orden en estado %.', v_estado;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mes.partida_paso pp
        JOIN mes.partida_paso_ejecucion ppe ON ppe.partida_paso_id = pp.id
        WHERE pp.partida_id = p_partida_id
          AND ppe.estado IN ('EN_PROCESO','COMPLETADO','OMITIDO')
    ) THEN
        RAISE EXCEPTION
            'No se pueden modificar los componentes porque uno o más pasos ya han sido iniciados o completados.'
            USING ERRCODE = 'check_violation';
    END IF;

    WITH partida_rollos AS (
        SELECT
            (i->>'item_id')::int       AS item_id,
            (i->>'lote_id')::int       AS lote_id,
            (i->>'ubicacion_id')::int  AS ubicacion_id,
            SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_componentes) i
        GROUP BY 1,2,3
    ), errores AS (
        SELECT
            im.item_id,
            im.lote_id,
            COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id) AS ubicacion_id,
            items.cantidad,
            SUM(im.cantidad * (
                CASE WHEN im.destino_ubicacion_id IS NOT NULL THEN  1 ELSE 0 END +
                CASE WHEN im.origen_ubicacion_id  IS NOT NULL THEN -1 ELSE 0 END
            )) AS saldo
        FROM inventario.item_movimientos im
        JOIN partida_rollos AS items
          ON items.lote_id = im.lote_id
         AND items.ubicacion_id = COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id)
        GROUP BY im.item_id, im.lote_id,
                 COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id),
                 items.cantidad
        HAVING SUM(im.cantidad * (
            CASE WHEN im.destino_ubicacion_id IS NOT NULL THEN  1 ELSE 0 END +
            CASE WHEN im.origen_ubicacion_id  IS NOT NULL THEN -1 ELSE 0 END
        )) < items.cantidad
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'item_id', item_id,
            'lote_id', lote_id,
            'ubicacion_id', ubicacion_id,
            'saldo_disponible', saldo,
            'cantidad_requerida', cantidad
        )
    )
    INTO v_error_payload
    FROM errores;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente para asignar los componentes'
            USING DETAIL = v_error_payload::text;
    END IF;
    -- Per-item roll count guard: submitted rolls per item_id must not exceed partida_detalle.cantidad.
    -- Also catches rolls whose item has no partida_detalle entry (unplanned item).
    SELECT l.item_id, COUNT(*)::int, pd.cantidad
    INTO v_overflow_item_id, v_rollos_submitted, v_cantidad_planificada
    FROM jsonb_array_elements(p_componentes) i
    JOIN inventario.lote l ON l.id = (i->>'lote_id')::int
    LEFT JOIN mes.partida_detalle pd ON pd.item_id = l.item_id
                                    AND pd.partida_id = p_partida_id
    WHERE (i->>'lote_id') IS NOT NULL
    GROUP BY l.item_id, pd.cantidad
    HAVING COUNT(*) > COALESCE(pd.cantidad, 0)
    LIMIT 1;

    IF v_overflow_item_id IS NOT NULL THEN
        RAISE EXCEPTION
            'El ítem % tiene % rollos asignados pero solo % están planificados.',
            v_overflow_item_id, v_rollos_submitted, COALESCE(v_cantidad_planificada, 0)
            USING ERRCODE = 'check_violation';
    END IF;

    -- Reservation conflict check (exclude current order, rolls only)
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_componentes) i
        JOIN mes.partida_componente pc ON pc.lote_id = (i->>'lote_id')::int
        JOIN mes.partida pr ON pr.id = pc.partida_id
        WHERE pc.lote_id IS NOT NULL
          AND pr.estado_produccion NOT IN ('CANCELADA','TECO','CERRADA')
          AND pc.partida_id <> p_partida_id
    ) THEN
        RAISE EXCEPTION 'Uno o más rollos ya están reservados en otra orden activa'
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_componentes_partida', v_usr_id,
            jsonb_build_object('partida_id', p_partida_id, 'componentes', p_componentes));

    -- Remove roll components no longer in the list (never touch chemical rows)
    DELETE FROM mes.partida_componente
    WHERE partida_id = p_partida_id
      AND lote_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(p_componentes) i
          WHERE (i->>'lote_id')::int = lote_id
      );

    -- Insert/update roll components (skip elements with missing/null lote_id)
    INSERT INTO mes.partida_componente(partida_id, lote_id, cantidad_reservada, usr_cre)
    SELECT p_partida_id,
           (i->>'lote_id')::int,
           (i->>'cantidad')::numeric,
           v_usr_id
    FROM jsonb_array_elements(p_componentes) i
    WHERE (i->>'lote_id') IS NOT NULL
    ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL
    DO UPDATE SET cantidad_reservada = EXCLUDED.cantidad_reservada;

    -- Roll weight changed → chemical reservations are stale; force re-generation per paso
    DELETE FROM mes.partida_componente
    WHERE item_id IS NOT NULL
      AND partida_paso_id IN (
          SELECT id FROM mes.partida_paso WHERE partida_id = p_partida_id
      );

    RETURN format('Componentes actualizados para orden #%s.', p_partida_id);

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in actualizar_componentes_partida - User: %, partida: %, Error: %, Detail: %',
              v_usr_id, p_partida_id, v_message, v_detail;
    RAISE;
END;
$function$;

-- Stock de rollos disponibles ahora vive en inventario.vw_stock_rollos (tablas.sql)

CREATE OR REPLACE FUNCTION mes.crear_plantilla(p_plantilla jsonb)
 RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','inventario','doc','mes'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_plantilla_id   INT;
    v_tipo_codigo text;
    v_usr_id int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('produccion.configurar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.configurar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_plantilla', v_usr_id, p_plantilla);

INSERT INTO ruta_plantilla (nombre)
    SELECT 
        p_plantilla->>'nombre'
    RETURNING id INTO v_plantilla_id;

INSERT INTO ruta_plantilla_detalle (ruta_plantilla_id, operacion_id, secuencia, ph, temperatura, tiempo_estandar)
    SELECT v_plantilla_id,
           (detalle->>'operacion_id')::INT,
           (detalle->>'secuencia')::SMALLINT,
           (detalle->>'ph')::NUMERIC(4,2),
           (detalle->>'temperatura')::NUMERIC(5,2),
           (detalle->>'tiempo_estandar')::INT
           FROM jsonb_array_elements(p_plantilla->'plantilla_detalles') AS detalle;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Plantilla Creada', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' creó una nueva plantilla', 'info',jsonb_build_object('objeto_tipo','plantilla','plantilla_id',v_plantilla_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras') AND v_usr_id<>ur.user_id;
   RETURN format('Plantilla con ID %s creada correctamente.', v_plantilla_id);
 EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_plantilla - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_plantilla::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION mes.actualizar_plantilla(p_plantilla_id int, p_plantilla jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam','notification','public','inventario','doc','mes'
AS $function$
DECLARE
    v_usr_id int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('produccion.configurar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere produccion.configurar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_plantilla', v_usr_id, p_plantilla);

    UPDATE ruta_plantilla 
    SET nombre = p_plantilla->>'nombre', usr_mod = v_usr_id, fyh_mod = NOW()
    WHERE id = p_plantilla_id;

    DELETE FROM ruta_plantilla_detalle WHERE ruta_plantilla_id = p_plantilla_id;

    INSERT INTO ruta_plantilla_detalle (ruta_plantilla_id, operacion_id, secuencia, ph, temperatura, tiempo_estandar)
    SELECT p_plantilla_id,
           (d->>'operacion_id')::INT,
           (d->>'secuencia')::SMALLINT,
           (d->>'ph')::NUMERIC(4,2),
           (d->>'temperatura')::NUMERIC(5,2),
           (d->>'tiempo_estandar')::INT
    FROM jsonb_array_elements(p_plantilla->'plantilla_detalles') AS d;

    RETURN format('Plantilla con ID %s actualizada correctamente.', p_plantilla_id);
END;
$function$;



-- RETURNS bigint (the created entrega_id) — changed 2026-07-14 from `text` (a
-- formatted message) so callers get what a good RPC should return: the id.
-- BREAKING CHANGE for both of its direct callers (receipt/CLIENTE_ENVIO_PROCESO
-- and dispatch/VENTA_EGRESO+DESPACHO_CLIENTE flows) — frontend must be updated
-- to read the returned id instead of a display message. See
-- VENTA_MODULE_HANDOFF.md item 6b.
-- DROP FUNCTION IF EXISTS doc.crear_entrega(jsonb);
CREATE OR REPLACE FUNCTION doc.crear_entrega(p_entrega jsonb)
RETURNS bigint
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','doc','inventario'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_entrega_id           BIGINT;
    v_entrega_tipo         entrega_tipo%ROWTYPE;
    v_doc_movimiento_id BIGINT;
    v_usr_id            int := get_user_id();
    v_lote_id           int;
    v_error_payload     jsonb;
    v_fecha_mov         TIMESTAMPTZ;
    v_detalle_id        BIGINT;
    v_linea_rec         RECORD;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

 SELECT * INTO v_entrega_tipo FROM entrega_tipo WHERE id = (p_entrega->>'entrega_tipo_id')::SMALLINT;
 IF NOT FOUND THEN
     RAISE EXCEPTION 'Tipo de guía con id % no existe', (p_entrega->>'entrega_tipo_id');
 END IF;

 -- COMPRA_INGRESO is handled by doc.registrar_entrega_compra (dedicated supplier flow).
 IF v_entrega_tipo.codigo = 'COMPRA_INGRESO' THEN
     RAISE EXCEPTION 'Use doc.registrar_entrega_compra para entregas de proveedor (COMPRA_INGRESO).'
         USING HINT = 'crear_entrega handles client flows only (SERVICIO_INGRESO, despacho, devolucion).';
 END IF;

 -- Devolution tipos have dedicated RPCs with domain-specific validation.
 IF v_entrega_tipo.codigo IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
     RAISE EXCEPTION 'Use doc.registrar_devolucion_cliente para devoluciones de cliente (%).',
         v_entrega_tipo.codigo
         USING HINT = 'registrar_devolucion_cliente validates prior dispatch to the same tercero.';
 END IF;
 IF v_entrega_tipo.codigo = 'DEVOLUCION_CLIENTE_CRUDO' THEN
     RAISE EXCEPTION 'Use doc.registrar_devolucion_crudo_cliente para devoluciones de crudo.'
         USING HINT = 'registrar_devolucion_crudo_cliente validates service ingress origin.';
 END IF;
 IF v_entrega_tipo.codigo = 'DEVOLUCION_PROVEEDOR' THEN
     RAISE EXCEPTION 'Use doc.registrar_devolucion_proveedor para devoluciones a proveedor.'
         USING HINT = 'registrar_devolucion_proveedor validates INSUMO item tipo.';
 END IF;

 -- Movement timestamp: for incoming entregas use fecha_recepcion (allows backdating), for outgoing use now()
 v_fecha_mov := CASE
    WHEN v_entrega_tipo.flg_emitida THEN (p_entrega->>'fecha_emision')::TIMESTAMPTZ
    ELSE COALESCE((p_entrega->>'fecha_recepcion')::TIMESTAMPTZ, now())
END;

-- Single posting document id shared by all movements from this entrega call
SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

IF v_entrega_tipo.flg_emitida THEN
        -- SELECT im.lote_id,COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id),SUM(CASE WHEN im.movimiento_tipo = 'EGRESO' THEN -im.cantidad WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad ELSE 0 END) FROM inventario.item_movimientos im
        -- JOIN jsonb_array_elements(p_entrega->'items') AS items ON items.item_id=im.item_id AND items.lote_id=im.lote_id AND items.ubicacion_id= COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        -- GROUP BY im.lote_id,COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        ---------------------
        --VALIDAR DISPONIBILIDAD DE items
        -------------------
        WITH entrega_items AS (
        SELECT
            (i->>'item_id')::int        AS item_id,
            (i->>'lote_id')::int        AS lote_id,
            (i->>'ubicacion_id')::int  AS ubicacion_id,
            SUM((i->>'cantidad')::numeric)  AS cantidad
        FROM jsonb_array_elements(p_entrega->'items') i
        GROUP BY 1,2,3
    ),errores AS (
    SELECT
        items.item_id,
        item.nombre AS item_nombre,
        items.lote_id,
        items.ubicacion_id,
        items.cantidad,
        COALESCE(sa.cantidad_disponible, 0) AS cantidad_disponible
    FROM entrega_items items
    LEFT JOIN inventario.vw_stock_lotes sa
        ON sa.item_id = items.item_id
        AND sa.lote_id = items.lote_id
    JOIN item ON item.id = items.item_id
    WHERE COALESCE(sa.cantidad_disponible, 0) < items.cantidad
)
 SELECT jsonb_agg(
        jsonb_build_object(
            'item_id', item_id,
            'item_nombre', item_nombre,
            'lote_id', lote_id,
            'ubicacion_id', ubicacion_id,
            'saldo_disponible', cantidad_disponible,
            'cantidad_requerida', cantidad
        )
    )
    INTO v_error_payload
    FROM errores;
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION
            'Stock insuficiente para emitir la guía'
            USING
                DETAIL  = v_error_payload::text;
    END IF;
END IF; -- stock validation (flg_emitida only)

-- Guard: inbound devolutions (flg_emitida=false) must reference lots that are actually
-- out (saldo=0). vw_stock_lotes only contains rows with cantidad_disponible > 0, so a
-- JOIN hit means the lot is still in stock → already returned or never dispatched.
IF NOT v_entrega_tipo.flg_emitida AND v_entrega_tipo.codigo LIKE 'DEVOLUCION%' THEN
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id, 'cantidad_disponible', sl.cantidad_disponible))
    INTO v_error_payload
    FROM (
        SELECT DISTINCT (i->>'lote_id')::int AS lote_id
        FROM jsonb_array_elements(p_entrega->'items') i
        WHERE (i->>'lote_id') IS NOT NULL
    ) ei
    JOIN inventario.vw_stock_lotes sl ON sl.lote_id = ei.lote_id;

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución inválida: los siguientes lotes ya tienen stock positivo (¿ya fueron devueltos?)'
            USING DETAIL = v_error_payload::text;
    END IF;
END IF;
-----------------------------------------------------------------------------------------------------------------------
-- tercero validation applies to all entrega types
IF (p_entrega->>'tercero_id') IS NULL THEN
    RAISE EXCEPTION 'Guía inválida: se esperaba tercero_id';
END IF;
IF v_entrega_tipo.flg_cliente AND NOT EXISTS (
    SELECT 1 FROM tercero WHERE id = (p_entrega->>'tercero_id')::INT AND flg_cliente = true
) THEN
    RAISE EXCEPTION 'Guía inválida: tercero_id % no corresponde a un cliente', (p_entrega->>'tercero_id');
ELSIF NOT v_entrega_tipo.flg_cliente AND NOT EXISTS (
    SELECT 1 FROM tercero WHERE id = (p_entrega->>'tercero_id')::INT AND flg_proveedor = true
) THEN
    RAISE EXCEPTION 'Guía inválida: tercero_id % no corresponde a un proveedor', (p_entrega->>'tercero_id');
END IF;


 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_entrega', v_usr_id, p_entrega);

    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (
        (p_entrega->>'entrega_tipo_id')::INT,
        (p_entrega->>'tercero_id')::INT,
        p_entrega->>'serie',
        p_entrega->>'correlativo',
        (p_entrega->>'fecha_emision')::TIMESTAMPTZ,
        CASE
            WHEN v_entrega_tipo.flg_emitida THEN NULL
            ELSE COALESCE((p_entrega->>'fecha_recepcion')::TIMESTAMPTZ, now())
        END
    )
    RETURNING id INTO v_entrega_id;

IF v_entrega_tipo.flg_emitida THEN
    
    -- Issued guides (dispatch/devolution-out): EGRESO of existing lotes.
    -- Insert detalle first (one line per item) capturing each line id, then post
    -- movements linked to their line via documento_linea_id (≈ MSEG.EBELP).
    WITH items AS (
        SELECT
            COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
            (item->>'item_id')::INT                             AS item_id,
            (item->>'cantidad')::NUMERIC(12,4)                  AS cantidad,
            (item->>'lote_id')::INT                             AS lote_id,
            (item->>'ubicacion_id')::INT                        AS ubicacion_id,
            (item->>'n_rollos')::INT                            AS n_rollos
        FROM jsonb_array_elements(p_entrega->'items') WITH ORDINALITY AS t(item, idx)
    ),
    det AS (
        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos
        FROM items
        RETURNING id, linea
    )
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id, documento_linea_id)
    SELECT
        v_doc_movimiento_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
        i.ubicacion_id,   -- per-item origin location
        NULL,             -- destination is external
        i.cantidad, v_fecha_mov, 'entrega', v_entrega_id, d.id
    FROM items i
    JOIN det d ON d.linea = i.linea;
ELSE
    -- Inbound (non-emitida): two item kinds.
    --   (a) lote_id present → devolution: move an existing lote, no new lote.
    --   (b) lote_id absent  → new client rolls: create N lotes + lrd + movements.
    -- Both stamp documento_linea_id (≈ MSEG.EBELP) so receipts are line-auditable.

    -- (a) Devolution lines: detalle first, movements linked per line.
    WITH items AS (
        SELECT
            COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
            (item->>'item_id')::INT                             AS item_id,
            (item->>'cantidad')::NUMERIC(12,4)                  AS cantidad,
            (item->>'lote_id')::INT                             AS lote_id,
            (item->>'ubicacion_id')::INT                        AS ubicacion_id
        FROM jsonb_array_elements(p_entrega->'items') WITH ORDINALITY AS t(item, idx)
        WHERE item->>'lote_id' IS NOT NULL
    ),
    det AS (
        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id
        FROM items
        RETURNING id, linea
    )
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, fecha_hora,
        documento_tipo, documento_id, documento_linea_id)
    SELECT
        v_doc_movimiento_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
        i.ubicacion_id, i.cantidad, v_fecha_mov, 'entrega', v_entrega_id, d.id
    FROM items i
    JOIN det d ON d.linea = i.linea;

    -- (b) New client rolls — one declared line per item, expanded to N lotes,
    --     each lote/lrd/movement carrying that line's documento_linea_id.
    FOR v_linea_rec IN
        SELECT
            COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
            (item->>'item_id')::INT                             AS item_id,
            (item->>'ubicacion_id')::INT                        AS ubicacion_id,
            (item->>'cantidad')::NUMERIC                        AS cantidad,
            COALESCE((item->>'cantidad_rollos')::INT, 1)        AS cantidad_rollos
        FROM jsonb_array_elements(p_entrega->'items') WITH ORDINALITY AS t(item, idx)
        WHERE item->>'lote_id' IS NULL
    LOOP
        INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, n_rollos)
        VALUES (v_entrega_id, v_linea_rec.linea, v_linea_rec.item_id,
                v_linea_rec.cantidad, v_linea_rec.cantidad_rollos)
        RETURNING id INTO v_detalle_id;

        WITH nuevos_lotes AS (
            INSERT INTO lote (item_id, documento_tipo, documento_id, cantidad, propietario_id)
            SELECT v_linea_rec.item_id, 'entrega', v_entrega_id,
                   COALESCE(v_linea_rec.cantidad / NULLIF(v_linea_rec.cantidad_rollos, 0),
                            v_linea_rec.cantidad),
                   (p_entrega->>'propietario_id')::INT
            FROM generate_series(1, v_linea_rec.cantidad_rollos)
            RETURNING id, item_id, cantidad
        ),
        lrd_rows AS (
            INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id, flg_tenido)
            SELECT nl.id, v_entrega_id, false
            FROM nuevos_lotes nl
            JOIN item i       ON i.id = nl.item_id
            JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
        )
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, fecha_hora, documento_tipo, documento_id, documento_linea_id)
        SELECT
            v_doc_movimiento_id, nl.item_id, nl.id, v_entrega_tipo.item_movimiento_tipo_id,
            NULL, (p_entrega->>'destino_ubicacion_id')::INT,
            nl.cantidad, v_fecha_mov, 'entrega', v_entrega_id, v_detalle_id
        FROM nuevos_lotes nl;
    END LOOP;
END IF;
INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva entrega y movimientos', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' creó una nueva guía de remisión y generó movimientos de inventario', 'info',jsonb_build_object('objeto_tipo','entrega','entrega_id',v_entrega_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras','inventario') AND v_usr_id<>ur.user_id;
   RETURN v_entrega_id;
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_entrega - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_entrega::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;

GRANT USAGE ON SCHEMA mes to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- INGRESO INTERNO — one-shot MLR roll ingress (replaces orden_servicio)
-- ───────────────────────────────────────────────────────────────
-- MLR-confected rolls (propietario_id=NULL) arrive with a thread-supplier
-- invoice reference. crear_ingreso_interno creates a headless-or-numbered
-- INGRESO_INTERNO entrega, N roll lotes, SERV_ING movements, and
-- entrega_detalle lines atomically.
--
-- Reversal: anular_entrega (same as every other inbound entrega).
-- Read:     get_entrega (same as every other entrega).
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- doc.crear_ingreso_interno
-- One-shot ingress of MLR-confected rolls (INGRESO_INTERNO entrega).
-- Creates the entrega, N lotes, SERV_ING movements, and entrega_detalle
-- lines atomically. Reversal via anular_entrega.
--
-- p_datos:
-- {
--   "correlativo":     "F-201/2024",  -- required; hilo supplier invoice/factura
--   "fecha_emision":   "2026-06-25", -- optional, defaults to today
--   "ubicacion_id":    8,            -- optional, defaults to ALM_CRU
--   "rendimiento":     "3.90",       -- applied to all rolls (lrd.rendimiento)
--   "ancho":           "90",         -- applied to all rolls (lrd.ancho)
--   "flg_antipilling": false,
--   "lineas": [
--     {
--       "item_id":            253,
--       "malla":              "2.60",
--       "cantidad_rollos":    12,
--       "peso_total":         null,   -- optional; split evenly; 0.1 kg sentinel if absent
--       "color_x_cliente_id": 125     -- optional; stamps lrd for dispatch grouping
--     }
--   ]
-- }
-- serie auto-generated (serie='II-'||nextval(ingreso_interno_seq)) so the same
-- factura hilo can recur across multiple ingress dates without violating
-- UNIQUE(tercero_id, serie, correlativo, entrega_tipo_id). correlativo is the
-- user-supplied factura hilo reference — required.
-- Returns the new entrega_id (BIGINT).
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.crear_ingreso_interno(p_datos jsonb)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_usr_id         INT      := get_user_id();
    v_ent_tipo_id    SMALLINT;
    v_serv_ing_tipo  SMALLINT;
    v_ent_id         BIGINT;
    v_doc_mov_id     BIGINT;
    v_ubicacion_id   INT;
    v_fecha_mov      TIMESTAMPTZ;
    v_linea_json     JSONB;
    v_det_linea      SMALLINT := 1;
    v_det_id         BIGINT;
    v_new_lote_id    BIGINT;
    v_peso_por_rollo NUMERIC;
    v_item_id        INT;
    v_cant_rollos    INT;
    v_i              INT;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_ingreso_interno', v_usr_id, p_datos);

    IF NULLIF(TRIM(p_datos->>'correlativo'), '') IS NULL THEN
        RAISE EXCEPTION 'crear_ingreso_interno: correlativo (factura hilo) es requerido';
    END IF;

    SELECT id INTO STRICT v_ent_tipo_id
    FROM doc.entrega_tipo WHERE codigo = 'INGRESO_INTERNO';

    SELECT id INTO STRICT v_serv_ing_tipo
    FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING';

    v_ubicacion_id := COALESCE(
        (p_datos->>'ubicacion_id')::INT,
        (SELECT ub.id
         FROM   inventario.ubicacion ub
         JOIN   inventario.almacen alm ON alm.id = ub.almacen_id
         WHERE  alm.codigo = 'ALM_CRU'
         LIMIT  1)
    );
    v_fecha_mov := COALESCE((p_datos->>'fecha_emision')::DATE::TIMESTAMPTZ, now());

    -- ── Entrega header ───────────────────────────────────────────
    INSERT INTO doc.entrega (
        entrega_tipo_id, tercero_id,
        serie,                  correlativo,
        fecha_emision, usr_cre
    ) VALUES (
        v_ent_tipo_id,
        1,  -- MLR self; INGRESO_INTERNO has no external counterparty
        'II-' || nextval('doc.ingreso_interno_seq')::TEXT,  -- auto, always unique
        p_datos->>'correlativo',  -- hilo supplier invoice/factura, e.g. 'F-201/2024'
        COALESCE((p_datos->>'fecha_emision')::DATE, CURRENT_DATE),
        v_usr_id
    )
    RETURNING id INTO v_ent_id;

    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    -- ── Roll lines ───────────────────────────────────────────────
    FOR v_linea_json IN SELECT jsonb_array_elements(p_datos->'lineas')
    LOOP
        v_item_id     := (v_linea_json->>'item_id')::INT;
        v_cant_rollos := (v_linea_json->>'cantidad_rollos')::INT;

        IF v_cant_rollos IS NULL OR v_cant_rollos <= 0 THEN
            RAISE EXCEPTION 'crear_ingreso_interno: cada línea requiere cantidad_rollos > 0';
        END IF;

        v_peso_por_rollo := COALESCE(
            (v_linea_json->>'peso_total')::NUMERIC / NULLIF(v_cant_rollos, 0),
            0.1   -- sentinel; corrected at weighing gate
        );

        FOR v_i IN 1 .. v_cant_rollos
        LOOP
            -- lote (propietario_id=NULL → MLR-owned)
            INSERT INTO inventario.lote (
                item_id, documento_tipo, documento_id,
                cantidad, propietario_id, usr_cre
            ) VALUES (
                v_item_id, 'entrega', v_ent_id,
                v_peso_por_rollo, NULL, v_usr_id
            )
            RETURNING id INTO v_new_lote_id;

            -- lrd (entrega_id is NOT NULL after patch 35)
            INSERT INTO inventario.lote_rollo_detalle (
                lote_id,       entrega_id,
                ancho,         malla,
                rendimiento,   color_x_cliente_id,
                flg_tenido,    flg_antipilling
            ) VALUES (
                v_new_lote_id, v_ent_id,
                p_datos->>'ancho',
                v_linea_json->>'malla',
                p_datos->>'rendimiento',
                (v_linea_json->>'color_x_cliente_id')::INT,
                false,
                COALESCE((p_datos->>'flg_antipilling')::BOOLEAN, false)
            );

            -- entrega_detalle
            INSERT INTO doc.entrega_detalle (
                entrega_id, linea, lote_id, item_id, cantidad, ubicacion_id
            ) VALUES (
                v_ent_id, v_det_linea, v_new_lote_id, v_item_id,
                v_peso_por_rollo, v_ubicacion_id
            )
            RETURNING id INTO v_det_id;

            -- SERV_ING movement
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id,
                item_movimiento_tipo_id,
                destino_ubicacion_id, cantidad, fecha_hora,
                documento_tipo, documento_id, documento_linea_id, usr_cre
            ) VALUES (
                v_doc_mov_id, v_item_id, v_new_lote_id,
                v_serv_ing_tipo,
                v_ubicacion_id, v_peso_por_rollo, v_fecha_mov,
                'entrega', v_ent_id, v_det_id, v_usr_id
            );

            v_det_linea := v_det_linea + 1;
        END LOOP;
    END LOOP;

    RETURN v_ent_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE LOG 'Error in crear_ingreso_interno - User: %, Params: %, Error: %',
                  v_usr_id, p_datos::TEXT, SQLERRM;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.crear_ingreso_interno(jsonb) TO authenticated;




CREATE OR REPLACE FUNCTION doc.get_entrega(p_entrega_id BIGINT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'inventario'
AS $$
SELECT jsonb_build_object(
    'id', gr.id,
    'entrega_tipo_id', gr.entrega_tipo_id,
    'tipo_codigo', grt.codigo,
    'tipo_nombre', grt.nombre,
    'flg_emitida', grt.flg_emitida,
    'fyh_elm', gr.fyh_elm,
    'serie', gr.serie,
    'correlativo', gr.correlativo,
    'fecha_emision', gr.fecha_emision,
    'fecha_recepcion', gr.fecha_recepcion,
    'tercero_id', gr.tercero_id,
    'tercero_codigo', t.codigo,
    'tercero_nombre', t.nombre,
    'tercero_ruc', t.ruc,
    'emisor',        CASE WHEN grt.flg_emitida THEN 'Manufacturas la Real' ELSE t.nombre END,
    'emisor_ruc',    CASE WHEN grt.flg_emitida THEN NULL                   ELSE t.ruc   END,
    'receptor',      CASE WHEN grt.flg_emitida THEN t.nombre ELSE 'Manufacturas la Real' END,
    'receptor_ruc',  CASE WHEN grt.flg_emitida THEN t.ruc   ELSE NULL                   END,
    'fyh_cre', gr.fyh_cre,
    'detalles', (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', grd.id,
                'item_id', grd.item_id,
                'item_codigo', i.codigo,
                'item_nombre', i.nombre,
                'cantidad', grd.cantidad,
                'unidad_codigo', u.codigo,
                'lote_id', grd.lote_id,
                'ubicacion_id', grd.ubicacion_id,
                'ubicacion_codigo', ub.codigo,
                'almacen_nombre', al.nombre,
                'saldo_actual', (
                    SELECT ROUND(SUM(sa.cantidad_disponible)::NUMERIC, 4)
                    FROM inventario.vw_stock_lotes sa
                    WHERE sa.lote_id = grd.lote_id
                )
            ) ORDER BY grd.id
        ), '[]'::jsonb)
        FROM doc.entrega_detalle grd
        LEFT JOIN item i ON i.id = grd.item_id
        LEFT JOIN unidad u ON u.id = i.unidad_id
        LEFT JOIN inventario.ubicacion ub ON ub.id = grd.ubicacion_id
        LEFT JOIN inventario.almacen al ON al.id = ub.almacen_id
        WHERE grd.entrega_id = gr.id
    ),
    'compras', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'compra_id',   c.id,
            'fecha',       c.fecha,
            'observacion', c.observacion,
            'fyh_elm',     c.fyh_elm
        ) ORDER BY c.fecha, c.id)
        FROM doc.compra_entrega cgr
        JOIN doc.compra c ON c.id = cgr.compra_id
        WHERE cgr.entrega_id = gr.id
    ), '[]'::jsonb)
)
FROM doc.entrega gr
LEFT JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
LEFT JOIN tercero t ON t.id = gr.tercero_id
WHERE gr.id = p_entrega_id;
$$;

GRANT EXECUTE ON FUNCTION doc.get_entrega(BIGINT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- doc.actualizar_entrega
-- Edit an inbound entrega (SERVICIO_INGRESO, COMPRA_INGRESO, etc.)
-- in-place without changing its ID.
--
-- Header fields (all optional — omit key to keep current value):
--   serie, correlativo, fecha_emision, fecha_recepcion, tercero_id
--
-- Line edit (supply "items" key to replace all lines):
--   Reverses the original inventory movements, soft-deletes the lotes
--   created by this entrega, deletes entrega_detalle rows, then
--   recreates everything exactly as crear_entrega would.
--   Items without lote_id → new-roll path (create lotes + lrd).
--   Items with lote_id    → devolution path (move existing lote).
--
-- Blocked when:
--   • entrega is anulada
--   • entrega is outbound (flg_emitida = true) — use anular + crear
--   • any lote born from this entrega has downstream movements
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.actualizar_entrega(
    p_entrega_id BIGINT,
    p_datos      JSONB
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_usr_id        INT  := get_user_id();
    v_entrega       RECORD;
    v_reversal_tipo SMALLINT;
    v_doc_mov_id    BIGINT;
    v_fecha_mov     TIMESTAMPTZ;
    v_linea_rec     RECORD;
    v_detalle_id    BIGINT;
    v_compra_id     BIGINT;
    v_compra_det_id BIGINT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_entrega', v_usr_id,
            jsonb_build_object('entrega_id', p_entrega_id, 'datos', p_datos));

    SELECT gr.id, gr.fyh_elm, gr.tercero_id,
           grt.flg_emitida, grt.codigo AS tipo_codigo,
           grt.item_movimiento_tipo_id
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id
    FOR UPDATE OF gr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya está anulada; no se puede editar.', p_entrega_id;
    END IF;
    IF v_entrega.flg_emitida THEN
        RAISE EXCEPTION
            'Guía #% es una guía de salida; use anular + crear para corregirla.',
            p_entrega_id
            USING HINT = 'actualizar_entrega sólo admite guías de entrada (flg_emitida = false).';
    END IF;

    -- Devolution tipos have dedicated anulación RPCs (funciones/devoluciones.sql)
    -- and no edit path — anular + re-registrar with the correct data instead.
    IF v_entrega.tipo_codigo IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_cliente para corregir esta devolución (%).', v_entrega.tipo_codigo;
    END IF;

    -- Block if any lote born from this entrega has downstream movements
    IF EXISTS (
        SELECT 1
        FROM inventario.lote l
        JOIN inventario.item_movimientos im ON im.lote_id = l.id
        WHERE l.documento_tipo = 'entrega'
          AND l.documento_id   = p_entrega_id
          AND l.fyh_elm        IS NULL
          AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id)
    ) THEN
        RAISE EXCEPTION
            'No se puede editar la guía #%: uno o más lotes ya tienen movimientos posteriores (producción, pesaje, redespacho).',
            p_entrega_id;
    END IF;

    -- ── Header update (only fields present in p_datos are touched) ──────────
    UPDATE doc.entrega SET
        serie           = CASE WHEN p_datos ? 'serie'
                               THEN p_datos->>'serie'
                               ELSE serie           END,
        correlativo     = CASE WHEN p_datos ? 'correlativo'
                               THEN p_datos->>'correlativo'
                               ELSE correlativo     END,
        fecha_emision   = CASE WHEN p_datos ? 'fecha_emision'
                               THEN (p_datos->>'fecha_emision')::TIMESTAMPTZ
                               ELSE fecha_emision   END,
        fecha_recepcion = CASE WHEN p_datos ? 'fecha_recepcion'
                               THEN (p_datos->>'fecha_recepcion')::TIMESTAMPTZ
                               ELSE fecha_recepcion END,
        tercero_id      = CASE WHEN p_datos ? 'tercero_id'
                               THEN (p_datos->>'tercero_id')::INT
                               ELSE tercero_id      END,
        usr_mod         = v_usr_id,
        fyh_mod         = NOW()
    WHERE id = p_entrega_id;

    -- ── Line replacement (only when "items" key is supplied) ────────────────
    IF p_datos ? 'items' THEN

        -- Resolve the PO this entrega is linked to (if any), so replacement
        -- lines can keep the EKPO link and cantidad_recibida can be resynced.
        SELECT ce.compra_id INTO v_compra_id
        FROM doc.compra_entrega ce WHERE ce.entrega_id = p_entrega_id LIMIT 1;

        -- Resolve the paired reversal movement tipo (same table as anular_entrega)
        SELECT imt2.id INTO v_reversal_tipo
        FROM inventario.item_movimiento_tipo imt1
        JOIN inventario.item_movimiento_tipo imt2
          ON imt2.codigo = CASE imt1.codigo
              WHEN 'COMPRA_ING' THEN 'DEV_PROV_EGR'
              WHEN 'SERV_ING'   THEN 'DEV_CLI_EGR'
              WHEN 'SERV_EGR'   THEN 'SERV_DEV_ING'
              WHEN 'VENTA_EGR'  THEN 'DEV_CLI_ING'
              ELSE NULL END
        WHERE imt1.id = v_entrega.item_movimiento_tipo_id;

        IF v_reversal_tipo IS NULL THEN
            RAISE EXCEPTION
                'Guía #%: no existe tipo de movimiento de reversal para "%". Contactar administrador.',
                p_entrega_id, v_entrega.tipo_codigo;
        END IF;

        -- Post counter-movements for all original movements
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id,
            item_movimiento_tipo_id,
            origen_ubicacion_id, destino_ubicacion_id,
            cantidad, fecha_hora,
            documento_tipo, documento_id, observacion
        )
        SELECT
            v_doc_mov_id, im.item_id, im.lote_id,
            v_reversal_tipo,
            im.destino_ubicacion_id,  -- swap: was destination, now origin
            im.origen_ubicacion_id,   -- swap: was origin, now destination
            im.cantidad, NOW(),
            'entrega', p_entrega_id,
            'EDICION guía #' || p_entrega_id
        FROM inventario.item_movimientos im
        WHERE im.documento_tipo = 'entrega'
          AND im.documento_id   = p_entrega_id;

        -- Soft-delete lotes that were created by this entrega
        UPDATE inventario.lote
        SET usr_elm = v_usr_id, fyh_elm = NOW()
        WHERE documento_tipo = 'entrega'
          AND documento_id   = p_entrega_id
          AND fyh_elm        IS NULL;

        -- Drop old detalle lines
        DELETE FROM doc.entrega_detalle WHERE entrega_id = p_entrega_id;

        -- New doc_mov_id for the incoming replacement movements
        SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

        v_fecha_mov := COALESCE(
            (p_datos->>'fecha_recepcion')::TIMESTAMPTZ,
            NOW()
        );

        -- (a) New-roll lines (lote_id absent): create lotes + lrd + movements
        FOR v_linea_rec IN
            SELECT
                COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
                (item->>'item_id')::INT                             AS item_id,
                (item->>'ubicacion_id')::INT                        AS ubicacion_id,
                (item->>'cantidad')::NUMERIC                        AS cantidad,
                COALESCE((item->>'cantidad_rollos')::INT, 1)        AS cantidad_rollos,
                (item->>'compra_detalle_id')::BIGINT                AS compra_detalle_id_explicit
            FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)
            WHERE item->>'lote_id' IS NULL
        LOOP
            -- Resolve EKPO link: explicit from payload, or auto-match by item_id
            -- (mirrors doc.registrar_entrega_compra) so the corrected line keeps
            -- counting toward the PO instead of going silently unlinked.
            v_compra_det_id := v_linea_rec.compra_detalle_id_explicit;
            IF v_compra_det_id IS NULL AND v_compra_id IS NOT NULL THEN
                SELECT id INTO v_compra_det_id
                FROM doc.compra_detalle
                WHERE compra_id = v_compra_id AND item_id = v_linea_rec.item_id
                ORDER BY id LIMIT 1;
            END IF;

            INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, n_rollos, compra_detalle_id)
            VALUES (p_entrega_id, v_linea_rec.linea, v_linea_rec.item_id,
                    v_linea_rec.cantidad, v_linea_rec.cantidad_rollos, v_compra_det_id)
            RETURNING id INTO v_detalle_id;

            WITH nuevos_lotes AS (
                INSERT INTO inventario.lote (
                    item_id, documento_tipo, documento_id,
                    cantidad, propietario_id, usr_cre
                )
                SELECT
                    v_linea_rec.item_id, 'entrega', p_entrega_id,
                    COALESCE(
                        v_linea_rec.cantidad / NULLIF(v_linea_rec.cantidad_rollos, 0),
                        v_linea_rec.cantidad
                    ),
                    (p_datos->>'propietario_id')::INT,
                    v_usr_id
                FROM generate_series(1, v_linea_rec.cantidad_rollos)
                RETURNING id, item_id, cantidad
            ),
            lrd_rows AS (
                INSERT INTO inventario.lote_rollo_detalle (lote_id, entrega_id, flg_tenido)
                SELECT nl.id, p_entrega_id, false
                FROM nuevos_lotes nl
                JOIN item      i  ON i.id  = nl.item_id
                JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
            )
            INSERT INTO inventario.item_movimientos (
                doc_movimiento_id, item_id, lote_id,
                item_movimiento_tipo_id,
                origen_ubicacion_id, destino_ubicacion_id,
                cantidad, fecha_hora,
                documento_tipo, documento_id, documento_linea_id, usr_cre
            )
            SELECT
                v_doc_mov_id, nl.item_id, nl.id,
                v_entrega.item_movimiento_tipo_id,
                NULL,
                COALESCE((p_datos->>'destino_ubicacion_id')::INT, v_linea_rec.ubicacion_id),
                nl.cantidad, v_fecha_mov,
                'entrega', p_entrega_id, v_detalle_id, v_usr_id
            FROM nuevos_lotes nl;
        END LOOP;

        -- (b) Devolution lines (lote_id present): move existing lotes back in
        WITH items AS (
            SELECT
                COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
                (item->>'item_id')::INT                             AS item_id,
                (item->>'cantidad')::NUMERIC(12,4)                  AS cantidad,
                (item->>'lote_id')::INT                             AS lote_id,
                (item->>'ubicacion_id')::INT                        AS ubicacion_id,
                COALESCE(
                    (item->>'compra_detalle_id')::BIGINT,
                    (SELECT cd.id FROM doc.compra_detalle cd
                     WHERE cd.compra_id = v_compra_id AND cd.item_id = (item->>'item_id')::INT
                     ORDER BY cd.id LIMIT 1)
                ) AS compra_detalle_id
            FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)
            WHERE item->>'lote_id' IS NOT NULL
        ),
        det AS (
            INSERT INTO doc.entrega_detalle
                (entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, compra_detalle_id)
            SELECT p_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, compra_detalle_id
            FROM items
            RETURNING id, linea
        )
        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id,
            item_movimiento_tipo_id,
            destino_ubicacion_id,
            cantidad, fecha_hora,
            documento_tipo, documento_id, documento_linea_id
        )
        SELECT
            v_doc_mov_id, i.item_id, i.lote_id,
            v_entrega.item_movimiento_tipo_id,
            i.ubicacion_id,
            i.cantidad, v_fecha_mov,
            'entrega', p_entrega_id, d.id
        FROM items i
        JOIN det d ON d.linea = i.linea;

        -- Resync compra_detalle.cantidad_recibida against the movements just posted
        IF v_compra_id IS NOT NULL THEN
            PERFORM doc.fn_refresh_compra_detalle_qtys(v_compra_id);
        END IF;

    END IF; -- items replacement

    RETURN format('Guía #%s actualizada correctamente.', p_entrega_id);
EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'Error in actualizar_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, SQLERRM;
    RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.actualizar_entrega(BIGINT, JSONB) TO authenticated;

GRANT EXECUTE ON FUNCTION mes.crear_partida(jsonb)                            TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_partida(int, jsonb)                  TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_pasos_partida(bigint, jsonb)         TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_componentes_partida(bigint, jsonb)   TO authenticated;


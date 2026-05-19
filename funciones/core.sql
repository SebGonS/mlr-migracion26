
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
            'articulo_tipo_id', ta.id,
            'articulo_tipo', ta.nombre,
            'fibra', ar.fibra,
            'flg_rib', ir.flg_rib
          )
          FROM item_rollo_detalle ir
          LEFT JOIN articulo ar ON ar.id=ir.articulo_id
          LEFT JOIN articulo_tipo ta ON ta.id=ar.articulo_tipo_id
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
            p_item->>'medida',
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
CREATE OR REPLACE FUNCTION public.crear_item(p_item jsonb)
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
    v_item_id   INT;
    v_tipo_codigo text;
    v_usr_id int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('inventario.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere inventario.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_item', v_usr_id, p_item::TEXT);
    INSERT INTO item (codigo, nombre, item_tipo_id, unidad_id)
    VALUES (
        p_item->>'codigo',
        p_item->>'nombre',
        (p_item->>'item_tipo_id')::INT,
        (p_item->>'unidad_id')::INT
    )
    RETURNING id INTO v_item_id;
     SELECT codigo INTO v_tipo_codigo FROM item_tipo WHERE id = (p_item->>'item_tipo_id')::INT;

    -- Create rollo or insumo detail
    IF v_tipo_codigo = 'ROLLO' THEN
        PERFORM crear_item_rollo(p_item, v_item_id);
    ELSIF v_tipo_codigo = 'INSUMO' THEN
        PERFORM crear_item_insumo(p_item, v_item_id);
    END IF;
INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nuevo Item Creado', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' creó un nuevo item de tipo' || COALESCE(p_item->>'nombre','sin nombre'), 'info',jsonb_build_object('objeto_tipo','item','item_id',v_item_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras') AND v_usr_id<>ur.user_id;
   RETURN format('Item con ID %s creado correctamente.', v_item_id);
 EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_item - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_item::TEXT, v_message, v_detail;
        RAISE;
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
    v_guia_tipo guia_remision_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_lote_id int;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
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
    v_guia_tipo guia_remision_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_lote_id int;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
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
    v_guia_tipo guia_remision_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_almacen_nombre text;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
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
--   tercero_id, color_x_cliente_id, tenido_id, articulo_tipo_id, fibra
--   partida_detalles[]  — { item_id, cantidad, unidad_id }
--
-- Optional payload fields:
--   pasos[]      — steps; can be added later via actualizar_pasos_partida while
--                  order is in CREADA/PENDIENTE state.
--     each paso: { secuencia, operacion_id, maquina_planificada_id?, receta_id?,
--                  ph_objetivo?, temperatura_objetivo?, tiempo_estandar?,
--                  relacion_bano_objetivo? }
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
    v_partida_id     BIGINT;
    v_usr_id         int := get_user_id();
    v_error_payload  jsonb;
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
    IF (p_partida->>'articulo_tipo_id') IS NULL THEN
        RAISE EXCEPTION 'articulo_tipo_id es requerido' USING ERRCODE = 'not_null_violation';
    END IF;
    IF (p_partida->>'fibra') IS NULL THEN
        RAISE EXCEPTION 'fibra es requerido' USING ERRCODE = 'not_null_violation';
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

        -- Article type: all rolls must match the order's articulo_tipo_id
        IF EXISTS (
            SELECT 1
            FROM jsonb_array_elements(p_partida->'componentes') c
            JOIN inventario.lote l      ON l.id  = (c->>'lote_id')::int
            JOIN item_rollo_detalle ird ON ird.item_id = l.item_id
            JOIN articulo a             ON a.id   = ird.articulo_id
            WHERE a.articulo_tipo_id IS DISTINCT FROM (p_partida->>'articulo_tipo_id')::smallint
        ) THEN
            RAISE EXCEPTION 'Los rollos asignados no coinciden con el tipo de artículo de la partida'
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
        prioridad_id, tercero_id, tenido_id, articulo_tipo_id, fibra,
        malla, rendimiento, ancho, color_x_cliente_id, flg_antipilling, fecha_acordada
    )
    VALUES (
        (p_partida->>'prioridad_id')::int,
        (p_partida->>'tercero_id')::int,
        (p_partida->>'tenido_id')::int,
        (p_partida->>'articulo_tipo_id')::smallint,
        (p_partida->>'fibra')::smallint,
        p_partida->>'malla',
        p_partida->>'rendimiento',
        p_partida->>'ancho',
        (p_partida->>'color_x_cliente_id')::int,
        COALESCE((p_partida->>'flg_antipilling')::boolean, false),
        (p_partida->>'fecha_acordada')::date
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
        INSERT INTO mes.partida_paso(
            partida_id, secuencia, operacion_id,
            maquina_planificada_id, receta_id,
            ph_objetivo, temperatura_objetivo, tiempo_estandar, relacion_bano_objetivo
        )
        SELECT
            v_partida_id,
            (p->>'secuencia')::smallint,
            (p->>'operacion_id')::smallint,
            (p->>'maquina_planificada_id')::int,
            (p->>'receta_id')::int,
            (p->>'ph_objetivo')::numeric,
            (p->>'temperatura_objetivo')::numeric,
            (p->>'tiempo_estandar')::int,
            COALESCE((p->>'relacion_bano_objetivo')::numeric, m.relacion_bano)
        FROM jsonb_array_elements(p_partida->'pasos') p
        LEFT JOIN mes.maquina m ON m.id = (p->>'maquina_planificada_id')::int;
    END IF;

    -- ── Roll reservations (optional at creation; validated above if present) ──
    IF p_partida->'componentes' IS NOT NULL AND jsonb_array_length(p_partida->'componentes') > 0 THEN
        INSERT INTO mes.partida_componente(partida_id, lote_id, cantidad_reservada)
        SELECT v_partida_id,
               (c->>'lote_id')::int,
               (c->>'cantidad')::numeric
        FROM jsonb_array_elements(p_partida->'componentes') c;
    END IF;

    -- ── Auto-request recipe if no live recipe exists for this spec ────────────
    PERFORM receta.solicitar_si_ausente(v_partida_id);

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
    -- Always editable: prioridad_id
    -------------------------------------------------------------------------
    UPDATE mes.partida
    SET prioridad_id = (p_partida->>'prioridad_id')::INT
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
    -- CREADA only: identity fields — tercero, tenido, color, articulo_tipo, fibra, antipilling
    -------------------------------------------------------------------------
    IF v_estado = 'CREADA' THEN
        UPDATE mes.partida
        SET tercero_id          = COALESCE((p_partida->>'tercero_id')::INT,           tercero_id),
            tenido_id           = COALESCE((p_partida->>'tenido_id')::INT,            tenido_id),
            color_x_cliente_id  = COALESCE((p_partida->>'color_x_cliente_id')::INT,  color_x_cliente_id),
            articulo_tipo_id    = COALESCE((p_partida->>'articulo_tipo_id')::SMALLINT, articulo_tipo_id),
            fibra               = COALESCE((p_partida->>'fibra')::SMALLINT,           fibra),
            flg_antipilling     = COALESCE((p_partida->>'flg_antipilling')::BOOLEAN,  flg_antipilling),
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
    WITH datos AS (
        SELECT
            (p->>'id')::BIGINT                AS id,
            (p->>'secuencia')::SMALLINT       AS secuencia,
            (p->>'operacion_id')::SMALLINT    AS operacion_id,
            (p->>'maquina_planificada_id')::INT AS maquina_planificada_id,
            (p->>'receta_id')::INT            AS receta_id,
            (p->>'ph_objetivo')::NUMERIC               AS ph_objetivo,
            (p->>'temperatura_objetivo')::NUMERIC      AS temperatura_objetivo,
            (p->>'tiempo_estandar')::INT      AS tiempo_estandar,
            COALESCE((p->>'relacion_bano_objetivo')::NUMERIC, m.relacion_bano) AS relacion_bano_objetivo
        FROM jsonb_array_elements(p_pasos) p
        LEFT JOIN mes.maquina m ON m.id = (p->>'maquina_planificada_id')::INT
    )
    INSERT INTO mes.partida_paso(
        partida_id, secuencia, operacion_id,
        maquina_planificada_id, receta_id,
        ph_objetivo, temperatura_objetivo, tiempo_estandar, relacion_bano_objetivo,
        usr_cre
    )
    SELECT p_partida_id, d.secuencia, d.operacion_id,
           d.maquina_planificada_id, d.receta_id,
           d.ph_objetivo, d.temperatura_objetivo, d.tiempo_estandar, d.relacion_bano_objetivo,
           v_usr_id
    FROM datos d
    ON CONFLICT (partida_id, secuencia)
    DO UPDATE SET
        operacion_id            = EXCLUDED.operacion_id,
        maquina_planificada_id  = EXCLUDED.maquina_planificada_id,
        receta_id               = EXCLUDED.receta_id,
        ph_objetivo             = EXCLUDED.ph_objetivo,
        temperatura_objetivo    = EXCLUDED.temperatura_objetivo,
        tiempo_estandar         = EXCLUDED.tiempo_estandar,
        relacion_bano_objetivo  = EXCLUDED.relacion_bano_objetivo,
        usr_mod                 = v_usr_id,
        fyh_mod                 = NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM mes.partida_paso_ejecucion pe
            WHERE pe.partida_paso_id = mes.partida_paso.id
              AND pe.estado IN ('EN_PROCESO', 'COMPLETADO', 'OMITIDO')
        );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Eliminar pasos que ya no están en la lista (solo si no han sido ejecutados)
    DELETE FROM mes.partida_paso
    WHERE partida_id = p_partida_id
      AND secuencia NOT IN (
          SELECT (p->>'secuencia')::SMALLINT
          FROM jsonb_array_elements(p_pasos) p
      )
      AND NOT EXISTS (
          SELECT 1 FROM mes.partida_paso_ejecucion pe
          WHERE pe.partida_paso_id = mes.partida_paso.id
      );

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
    v_usr_id     int  := get_user_id();
    v_estado     partida_estado_produccion_enum;
    v_error_payload jsonb;
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
            SUM(im.cantidad * imt.factor) AS saldo
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON im.item_movimiento_tipo_id = imt.id
        JOIN partida_rollos AS items
          ON items.lote_id = im.lote_id
         AND items.ubicacion_id = COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id)
        GROUP BY im.item_id, im.lote_id,
                 COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id),
                 items.cantidad
        HAVING SUM(im.cantidad * imt.factor) < items.cantidad
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

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_componentes) i
        JOIN inventario.lote l       ON l.id = (i->>'lote_id')::INT
        JOIN item_rollo_detalle ird  ON ird.item_id = l.item_id
        JOIN articulo a              ON a.id = ird.articulo_id
        JOIN mes.partida p           ON p.id = p_partida_id
        WHERE a.articulo_tipo_id IS DISTINCT FROM p.articulo_tipo_id
    ) THEN
        RAISE EXCEPTION
            'Los rollos asignados no coinciden con el tipo de artículo de la partida (articulo_tipo_id)'
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

    -- Insert/update roll components
    INSERT INTO mes.partida_componente(partida_id, lote_id, cantidad_reservada, usr_cre)
    SELECT p_partida_id,
           (i->>'lote_id')::int,
           (i->>'cantidad')::numeric,
           v_usr_id
    FROM jsonb_array_elements(p_componentes) i
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



CREATE OR REPLACE FUNCTION doc.crear_guia(p_guia jsonb)
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
    v_guia_id           BIGINT;
    v_guia_tipo         guia_remision_tipo%ROWTYPE;
    v_doc_movimiento_id BIGINT;
    v_usr_id            int := get_user_id();
    v_lote_id           int;
    v_error_payload     jsonb;
    v_fecha_mov         TIMESTAMPTZ;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

 -- guard condition
 SELECT * INTO v_guia_tipo FROM guia_remision_tipo WHERE id = (p_guia->>'guia_remision_tipo_id')::SMALLINT;
--  SELECT * INTO v_item_movimiento_tipo FROM inventario.item_movimiento_tipo WHERE id = v_guia_tipo.item_movimiento_tipo_id;
 IF NOT FOUND THEN
     RAISE EXCEPTION 'Tipo de guía con id % no existe', (p_guia->>'guia_remision_tipo_id');
 END IF;

 -- Movement timestamp: for incoming guias use fecha_recepcion (allows backdating), for outgoing use now()
 v_fecha_mov := CASE
    WHEN v_guia_tipo.flg_emitida THEN (p_guia->>'fecha_emision')::TIMESTAMPTZ
    ELSE COALESCE((p_guia->>'fecha_recepcion')::TIMESTAMPTZ, now())
END;

-- Single posting document id shared by all movements from this guia call
SELECT nextval('inventario.mov_doc_seq') INTO v_doc_movimiento_id;

IF v_guia_tipo.flg_emitida THEN
        -- SELECT im.lote_id,COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id),SUM(CASE WHEN im.movimiento_tipo = 'EGRESO' THEN -im.cantidad WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad ELSE 0 END) FROM inventario.item_movimientos im
        -- JOIN jsonb_array_elements(p_guia->'items') AS items ON items.item_id=im.item_id AND items.lote_id=im.lote_id AND items.ubicacion_id= COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        -- GROUP BY im.lote_id,COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        ---------------------
        --VALIDAR DISPONIBILIDAD DE items
        -------------------
        WITH guia_items AS (
        SELECT
            (i->>'item_id')::int        AS item_id,
            (i->>'lote_id')::int        AS lote_id,
            (i->>'ubicacion_id')::int  AS ubicacion_id,
            SUM((i->>'cantidad')::numeric)  AS cantidad
        FROM jsonb_array_elements(p_guia->'items') i
        GROUP BY 1,2,3
    ),errores AS (
    SELECT
        items.item_id,
        item.nombre AS item_nombre,
        items.lote_id,
        items.ubicacion_id,
        items.cantidad,
        COALESCE(sa.cantidad_disponible, 0) AS cantidad_disponible
    FROM guia_items items
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
-----------------------------------------------------------------------------------------------------------------------
-- tercero validation applies to all guia types
IF (p_guia->>'tercero_id') IS NULL THEN
    RAISE EXCEPTION 'Guía inválida: se esperaba tercero_id';
END IF;
IF v_guia_tipo.flg_cliente AND NOT EXISTS (
    SELECT 1 FROM tercero WHERE id = (p_guia->>'tercero_id')::INT AND flg_cliente = true
) THEN
    RAISE EXCEPTION 'Guía inválida: tercero_id % no corresponde a un cliente', (p_guia->>'tercero_id');
ELSIF NOT v_guia_tipo.flg_cliente AND NOT EXISTS (
    SELECT 1 FROM tercero WHERE id = (p_guia->>'tercero_id')::INT AND flg_proveedor = true
) THEN
    RAISE EXCEPTION 'Guía inválida: tercero_id % no corresponde a un proveedor', (p_guia->>'tercero_id');
END IF;


 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_guia', v_usr_id, p_guia);

    INSERT INTO doc.guia_remision(guia_remision_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
    VALUES (
        (p_guia->>'guia_remision_tipo_id')::INT,
        (p_guia->>'tercero_id')::INT,
        p_guia->>'serie',
        p_guia->>'correlativo',
        (p_guia->>'fecha_emision')::TIMESTAMPTZ,
        CASE
            WHEN v_guia_tipo.flg_emitida THEN NULL
            ELSE COALESCE((p_guia->>'fecha_recepcion')::TIMESTAMPTZ, now())
        END
    )
    RETURNING id INTO v_guia_id;

-- Link guia to compra if compra_id is provided (purchase receipts only)
IF p_guia ? 'compra_id' THEN
    INSERT INTO doc.compra_guia_remision (compra_id, guia_remision_id)
    VALUES ((p_guia->>'compra_id')::BIGINT, v_guia_id)
    ON CONFLICT DO NOTHING;
END IF;

IF v_guia_tipo.flg_emitida THEN
    
    INSERT INTO doc.guia_remision_detalle (guia_remision_id , item_id, cantidad,lote_id,ubicacion_id)
    SELECT
        v_guia_id,
        (item->>'item_id')::INT,
        (item->>'cantidad')::NUMERIC(12,4),
        (item->>'lote_id')::INT,
        (item->>'ubicacion_id')::INT
    FROM jsonb_array_elements(p_guia->'items') AS item;
    -- For issued guides, create item movements as EGRESO from warehouse
    INSERT INTO inventario.item_movimientos
    (
        doc_movimiento_id, item_id,
        lote_id,
        item_movimiento_tipo_id,
        origen_ubicacion_id,
        destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id)
    SELECT
        v_doc_movimiento_id,
        (item->>'item_id')::INT,
        (item->>'lote_id')::INT,
        v_guia_tipo.item_movimiento_tipo_id,
        (item->>'ubicacion_id')::INT,  -- per-item origin location
        NULL, -- destination is external
        (item->>'cantidad')::NUMERIC(12,4),
        v_fecha_mov,
        'GUIA_REMISION',
        v_guia_id
    FROM jsonb_array_elements(p_guia->'items') AS item;
ELSE
 -- Items WITH lote_id → existing lots (devolution)
    INSERT INTO inventario.item_movimientos
        (doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
         destino_ubicacion_id, cantidad, fecha_hora,
         documento_tipo, documento_id)
    SELECT
        v_doc_movimiento_id,
        (item->>'item_id')::INT,
        (item->>'lote_id')::INT,
        v_guia_tipo.item_movimiento_tipo_id,
        (item->>'ubicacion_id')::INT,
        (item->>'cantidad')::NUMERIC(12,4),
        v_fecha_mov,
        'GUIA_REMISION',
        v_guia_id
    FROM jsonb_array_elements(p_guia->'items') AS item
    WHERE item->>'lote_id' IS NOT NULL;
    -- This is missing (detail line):
INSERT INTO doc.guia_remision_detalle (guia_remision_id, item_id, cantidad, lote_id, ubicacion_id)
SELECT v_guia_id, (item->>'item_id')::INT, (item->>'cantidad')::NUMERIC, (item->>'lote_id')::INT, (item->>'ubicacion_id')::INT
FROM jsonb_array_elements(p_guia->'items') AS item
WHERE item->>'lote_id' IS NOT NULL;
    ---INSERSION de items sin lote existente (nuevos lotes) y registro de movimientos de ingreso al almacen
WITH 
expanded AS (
    SELECT
        (item->>'item_id')::INT AS item_id,
        (item->>'ubicacion_id')::INT AS ubicacion_id,
        (item->>'cantidad')::NUMERIC AS cantidad,
        (item->>'cantidad')::NUMERIC
            / NULLIF((item->>'cantidad_rollos')::INT, 0) AS peso_estimado,
        (p_guia->>'propietario_id')::INT AS propietario_id
    FROM jsonb_array_elements(p_guia->'items') AS item
    LEFT JOIN LATERAL generate_series(1, (item->>'cantidad_rollos')::INT) rollo_numero ON true
    WHERE item->>'lote_id' IS NULL
),
nuevos_lotes AS(
    INSERT INTO lote (
        item_id, 
        documento_tipo, 
        documento_id, 
        cantidad,
        detalles,
        propietario_id
        )
    SELECT
    item.item_id,
    'GUIA_REMISION',
    v_guia_id,
    COALESCE(item.peso_estimado,item.cantidad), -- si hay cantidad de rollos, usar peso estimado, sino usar cantidad total (caso de no tener cantidad_rollos)
    NULL,
    item.propietario_id
    FROM expanded AS item
    RETURNING id,item_id,documento_tipo,documento_id,cantidad,propietario_id
) -- Para guias recibidas con items sin lote_id, se crean nuevos lotes y se registra el movimiento de ingreso al almacen
,detalles as(
    INSERT INTO doc.guia_remision_detalle (guia_remision_id , item_id, cantidad,lote_id)
    SELECT
        v_guia_id,
        nl.item_id,
        nl.cantidad,
        nl.id --id del lote recien creado
        FROM nuevos_lotes nl
)
-- Create lote_rollo_detalle for each new ROLLO lote.
-- guia_remision_id is the billing anchor carried forward through production.
-- ancho/malla/rendimiento are NULL at ingress — set during weighing.
, lrd_rows AS (
    INSERT INTO inventario.lote_rollo_detalle (lote_id, guia_remision_id, flg_tenido)
    SELECT nl.id, v_guia_id, false
    FROM nuevos_lotes nl
    JOIN item i   ON i.id = nl.item_id
    JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
)
INSERT INTO inventario.item_movimientos (doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id, origen_ubicacion_id, destino_ubicacion_id, cantidad, precio_unitario, fecha_hora, documento_tipo, documento_id)
    SELECT
        v_doc_movimiento_id,
        nl.item_id,
        nl.id,
        v_guia_tipo.item_movimiento_tipo_id,
        NULL, -- origin is external
        (p_guia->>'destino_ubicacion_id')::INT,
        nl.cantidad,
        -- For COMPRA_ING: look up unit price from compra_detalle; NULL for non-purchase guias
        (SELECT cd.precio_unitario FROM doc.compra_detalle cd
         WHERE cd.compra_id = (p_guia->>'compra_id')::BIGINT
           AND cd.item_id = nl.item_id
         ORDER BY cd.id LIMIT 1),
        v_fecha_mov,
        'GUIA_REMISION',
        v_guia_id
    FROM nuevos_lotes nl;
END IF;
INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Guia y movimientos', COALESCE((SELECT COALESCE(nombre,'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id=v_usr_id),'sistema') || ' creó una nueva guía de remisión y generó movimientos de inventario', 'info',jsonb_build_object('objeto_tipo','guia_remision','guia_remision_id',v_guia_id)
FROM iam.user_rol ur LEFT JOIN usuario p ON p.id=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras','inventario') AND v_usr_id<>ur.user_id;
   RETURN format('Guía de remisión con ID %s creada correctamente.', v_guia_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error in crear_guia - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_guia::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;

GRANT USAGE ON SCHEMA mes to authenticated;




CREATE OR REPLACE FUNCTION doc.get_guia_remision(p_guia_id BIGINT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'inventario'
AS $$
SELECT jsonb_build_object(
    'id', gr.id,
    'guia_remision_tipo_id', gr.guia_remision_tipo_id,
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
        FROM doc.guia_remision_detalle grd
        LEFT JOIN item i ON i.id = grd.item_id
        LEFT JOIN unidad u ON u.id = i.unidad_id
        LEFT JOIN inventario.ubicacion ub ON ub.id = grd.ubicacion_id
        LEFT JOIN inventario.almacen al ON al.id = ub.almacen_id
        WHERE grd.guia_remision_id = gr.id
    )
)
FROM doc.guia_remision gr
LEFT JOIN doc.guia_remision_tipo grt ON grt.id = gr.guia_remision_tipo_id
LEFT JOIN tercero t ON t.id = gr.tercero_id
WHERE gr.id = p_guia_id;
$$;

GRANT EXECUTE ON FUNCTION doc.get_guia_remision(BIGINT) TO authenticated;

GRANT EXECUTE ON FUNCTION mes.crear_partida(jsonb)                            TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_partida(int, jsonb)                  TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_pasos_partida(bigint, jsonb)         TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_componentes_partida(bigint, jsonb)   TO authenticated;




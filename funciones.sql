
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
            'articulo',ar.articulo,
            'tipo_articulo_id', ta.id,
            'tipo_articulo', ta.tipo_articulo,
            'fibra', ir.fibra,
            'color_x_cliente',
              CASE WHEN ir.color_x_cliente_id IS NOT NULL THEN
                jsonb_build_object(
                  'id', cxc.id,
                  'color_id', cxc.color_id,
                  'color', cxc.color,
                  'cliente_id', cxc.cliente_id,
                  'cliente', cxc.cliente
                )
              END
          )
          FROM item_rollo_detalle ir
          LEFT JOIN color_x_cliente cxc ON cxc.id = ir.color_x_cliente_id
          LEFT JOIN articulo ar ON ar.id=ir.articulo_id
          LEFT JOIN tipo_articulo ta ON ta.id=ar.tipo_articulo_id
          WHERE ir.item_id = i.item_id
        )
      )
    END
))
FROM vw_items i
WHERE i.item_id = p_item_id;
$$;

CREATE OR REPLACE FUNCTION public.crear_item_insumo(p_item jsonb,ptcr p_item_id int)
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
    IF p_item ? 'articulo' AND p_item ? 'fibra' THEN
    BEGIN
        INSERT INTO item_insumo_detalle (item_id, medida, insumo_tipo_id, colorante_tipo_id)
        VALUES (
            p_item_id,
            p_item->>'medida',
            (p_item->>'insumo_tipo')::SMALLINT,
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
        'Los campos articulo y fibra son obligatorios para crear un item de tipo insumo'
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
        INSERT INTO item_rollo_detalle (item_id, articulo_id, fibra,color_x_cliente_id)
        VALUES (
            p_item_id,
            (p_item->>'articulo_id')::INT,
            (p_item->>'fibra')::SMALLINT,
            (p_item->>'color_x_cliente_id')::INT
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
        'El campo articulo_id es obligatorio para crear un item de tipo rollo'
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
SELECT ur.user_id,'Nuevo Item Creado', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' creó un nuevo item de tipo' || COALESCE(p_item->>'nombre','sin nombre'), 'info',jsonb_build_object('objeto_tipo','item','item_id',v_item_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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
$$


CREATE FUNCTION inventario.crear_almacen(p_almacen json)
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
INSERT INTO inventario.almacen(codigo,nombre,usr_cre)
VALUES ((p_almacen->>'codigo')::TEXT,(p_almacen->>'nombre')::TEXT)
RETURNING id INTO v_almacen_id;
IF p_almacen ? 'ubicaciones' THEN
    INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,usr_cre)
    SELECT v_almacen_id,(u->>'codigo')::TEXT,(u->>'nombre')::TEXT
    FROM jsonb_array_elements(p_almacen->'ubicaciones') AS u;
END IF;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nuevo almacen y ubicaciones', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' creó un nuevo almacen y ubicaciones', 'info',jsonb_build_object('objeto_tipo','almacen','almacen_id',v_almacen_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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

CREATE FUNCTION inventario.modificar_almacen(p_almacen json)
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
UPDATE inventario.almacen
SET codigo = (p_almacen->>'codigo')::TEXT,
    nombre = (p_almacen->>'nombre')::TEXT,
    usr_mod = v_usr_id,
    fyh_mod = NOW()
WHERE id = (p_almacen->>'id')::INT;

IF p_almacen ? 'ubicaciones' THEN
    INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,usr_cre)
    SELECT (p_almacen->>'id')::INT,(u->>'codigo')::TEXT,(u->>'nombre')::TEXT,v_usr_id
    FROM jsonb_array_elements(p_almacen->'ubicaciones') AS u
    ON CONFLICT (almacen_id,codigo) DO UPDATE SET nombre = EXCLUDED.nombre, usr_mod = v_usr_id, fyh_mod = NOW();

    DELETE FROM inventario.ubicacion WHERE almacen_id = (p_almacen->>'id')::INT 
    AND codigo NOT IN (SELECT u->>'id' FROM jsonb_array_elements(p_almacen->'ubicaciones') AS u);
END IF;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Almacen y/o ubicaciones actualizadas', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' modifico un almacen y/o sus ubicaciones', 'info',jsonb_build_object('objeto_tipo','almacen','almacen_id',v_almacen_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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

        RAISE LOG 'Error in modificar_almacen - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_almacen::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;


CREATE FUNCTION inventario.eliminar_almacen(p_almacen_id int)
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

DELETE FROM ubicacion WHERE almacen_id = p_almacen_id;
DELETE FROM almacen WHERE id = p_almacen_id
RETURNING nombre INTO v_almacen_nombre;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Almacen eliminado', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' eliminó un almacen y sus ubicaciones', 'info',jsonb_build_object('objeto_tipo','almacen','almacen_id',v_almacen_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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




CREATE OR REPLACE FUNCTION doc.crear_partida(p_partida jsonb)
 RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','doc','mes'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_partida_id   INT;
    v_tipo_codigo text;
    v_usr_id int := get_user_id();

BEGIN
 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_partida', v_usr_id, p_partida);

-------------------------------------------------------------------------
    INSERT INTO doc.partida (prioridad_id,cliente_id,tenido_id,malla,rendimiento,color_x_cliente_id,flg_antipilling)
    VALUES (
       ( p_partida->>'prioridad_id')::INT,
        (p_partida->>'cliente_id')::INT,
        (p_partida->>'tenido_id')::INT,
        (p_partida->>'malla')::TEXT,
        p_partida->>'rendimiento',
        (p_partida->>'color_x_cliente_id')::INT,
        (p_partida->>'flg_antipilling')::BOOLEAN
    )
    RETURNING id INTO v_partida_id;
     INSERT INTO doc.partida_detalle(partida_id, item_id,cantidad)
     SELECT v_partida_id, (u->>'item_id')::INT, (u->>'cantidad')::INT
     FROM jsonb_array_elements(p_partida->'partida_detalles') AS u;


INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Partida Creada', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' creó una nueva partida', 'info',jsonb_build_object('objeto_tipo','partida','partida_id',v_partida_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras') AND v_usr_id<>ur.user_id;
   RETURN format('Partida con ID %s creada correctamente.', v_partida_id);
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

CREATE OR REPLACE FUNCTION doc.actualizar_partida(p_partida_id INT, p_partida jsonb)
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
    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_partida', v_usr_id, jsonb_build_object('partida_id', p_partida_id, 'partida', p_partida));

    -- Get current state
    SELECT estado INTO v_estado
    FROM doc.partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida con ID % no encontrada.', p_partida_id;
    END IF;

    -- Reject if terminal state
    IF v_estado IN ('CERRADA', 'CANCELADA', 'FACTURADA') THEN
        RAISE EXCEPTION 'No se puede modificar una partida en estado %.', v_estado;
    END IF;

    -------------------------------------------------------------------------
    -- Always editable: prioridad_id
    -------------------------------------------------------------------------
    UPDATE doc.partida
    SET prioridad_id = (p_partida->>'prioridad_id')::INT
    WHERE id = p_partida_id;

    -------------------------------------------------------------------------
    -- CREADA or CONFIRMADA: also malla, rendimiento
    -------------------------------------------------------------------------
    IF v_estado IN ('CREADA', 'CONFIRMADA') THEN
        UPDATE doc.partida
        SET malla       = (p_partida->>'malla')::TEXT,
            rendimiento = p_partida->>'rendimiento'
        WHERE id = p_partida_id;
    END IF;

    -------------------------------------------------------------------------
    -- CREADA only: cliente, tenido, color, and full detail replace
    -------------------------------------------------------------------------
    IF v_estado = 'CREADA' THEN
        UPDATE doc.partida
        SET cliente_id          = (p_partida->>'cliente_id')::INT,
            tenido_id           = (p_partida->>'tenido_id')::INT,
            color_x_cliente_id  = (p_partida->>'color_x_cliente_id')::INT,
            flg_antipilling     = (p_partida->>'flg_antipilling')::BOOLEAN
        WHERE id = p_partida_id;

        -- Full replace of detail rows
       -- Remove rows no longer in the incoming array
DELETE FROM doc.partida_detalle pd
WHERE pd.partida_id = p_partida_id
  AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_partida->'partida_detalles') u
      WHERE (u->>'item_id')::INT = pd.item_id
  );

-- Upsert the rest
INSERT INTO doc.partida_detalle(partida_id, item_id, cantidad)
SELECT p_partida_id, (u->>'item_id')::INT, (u->>'cantidad')::INT
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
               (SELECT COALESCE(first_name, 'Usuario desconocido') || ' ' || last_name
                FROM profiles WHERE id_usuario = v_usr_id),
               'sistema'
           ) || ' modificó la partida #' || p_partida_id,
           'info',
           jsonb_build_object('objeto_tipo', 'partida', 'partida_id', p_partida_id)
    FROM iam.user_rol ur
    LEFT JOIN profiles p ON p.id_usuario = ur.user_id
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


SELECT * FROM logs_api ORDER BY called_at DESC

CREATE OR REPLACE FUNCTION doc.get_partida(p_partida_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql  -- ✅ FIXED
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public','inventario','doc','mes','calidad'
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- ═══════════════════════════════════════
        -- PARTIDA HEADER
        -- ═══════════════════════════════════════
        'id', p.id,
        'numero', p.numero,
        'codigo', EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
        
        -- Cliente & Especificaciones
        'prioridad_id', p.prioridad_id,
        'prioridad', pri.prioridad,
        'cliente_id', p.cliente_id,
        'cliente', c.cliente,
        'color_x_cliente_id', p.color_x_cliente_id,
        'color', vc.color,
        'color_hex', vc.color_hex,
        'color_x_cliente_hex', vc.color_x_cliente_hex,
        'tono', vc.tono,
        'flg_antipilling', p.flg_antipilling,
        'tenido_id', p.tenido_id,
        'tenido', tenido.tenido,
        'malla', p.malla,
        'rendimiento', p.rendimiento,
        
        -- Estado y fechas
        'estado', p.estado,
        'fyh_inicio', p.fyh_inicio,
        'fyh_fin', p.fyh_fin,
        'fyh_cre', p.fyh_cre,
        
        -- ═══════════════════════════════════════
        -- PARTIDA DETALLES (Output esperado)
        -- ═══════════════════════════════════════
        'partida_detalles', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', pd.id,
                'item_id', pd.item_id,
                'item_tipo_codigo', vi.item_tipo_codigo,
                'item_codigo', vi.item_codigo,
                'item_nombre', vi.item_nombre,
                'cantidad', pd.cantidad,
                'unidad', vi.unidad_codigo
            ) ORDER BY pd.id)
            FROM doc.partida_detalle pd
            LEFT JOIN vw_items vi ON vi.item_id = pd.item_id  -- ✅ FIXED
            WHERE pd.partida_id = p.id
        ), '[]'::jsonb),
        'resumen_progreso', jsonb_build_object(
    'total_ordenes', (SELECT COUNT(*) FROM mes.orden_produccion WHERE partida_id = p.id),
    'ordenes_completadas', (SELECT COUNT(*) FROM mes.orden_produccion WHERE partida_id = p.id AND estado IN ('FINALIZADA', 'TECO', 'CERRADA')),
    'total_pasos', (
        SELECT COUNT(*) 
        FROM mes.orden_produccion_paso opp
        JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
        WHERE op.partida_id = p.id
    ),
    'pasos_completados', (
        SELECT COUNT(*) 
        FROM mes.orden_produccion_paso opp
        JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
        WHERE op.partida_id = p.id AND opp.estado = 'COMPLETADO'
    ),
    'porcentaje_completado', (
        SELECT ROUND(
            COUNT(*) FILTER (WHERE opp.estado = 'COMPLETADO')::NUMERIC / 
            NULLIF(COUNT(*), 0) * 100, 
            2
        )
        FROM mes.orden_produccion_paso opp
        JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
        WHERE op.partida_id = p.id
    )
),
'resumen_consumo_total', COALESCE((
    SELECT jsonb_agg(
        jsonb_build_object(
            'item_id', subq.item_id,
            'item_codigo', subq.item_codigo,
            'item_nombre', subq.item_nombre,
            'cantidad_total', subq.cantidad_total,
            'unidad', subq.unidad
        )
    )
    FROM (
        SELECT 
            m.item_id,
            vi.item_codigo,
            vi.item_nombre,
            vi.unidad_codigo as unidad,
            SUM(m.cantidad) as cantidad_total
        FROM inventario.item_movimientos m
        JOIN vw_items vi ON vi.item_id = m.item_id
        WHERE m.documento_tipo = 'orden_produccion_paso'
        AND m.documento_id IN (
            SELECT opp.id 
            FROM mes.orden_produccion_paso opp
            JOIN mes.orden_produccion op ON op.id = opp.orden_produccion_id
            WHERE op.partida_id = p.id
        )
        GROUP BY m.item_id, vi.item_codigo, vi.item_nombre, vi.unidad_codigo
    ) subq
), '[]'::jsonb),
        -- ═══════════════════════════════════════
        -- ORDENES DE PRODUCCION
        -- ═══════════════════════════════════════
        'ordenes_produccion', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', op.id,
                    'tipo', op.tipo,  -- ✅ FIXED (was op.lote_id)
                    'estado', op.estado,
                    'orden_origen_id', op.orden_origen_id,
                    'fyh_cre', op.fyh_cre,
                    'fyh_inicio', op.fyh_inicio,
                    'fyh_fin', op.fyh_fin,
                    
                    -- ───────────────────────────────────
                    -- PASOS DE PRODUCCION
                    -- ───────────────────────────────────
                    'pasos', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id', opp.id,
                                'secuencia', opp.secuencia,
                                
                                -- Operación
                                'operacion_id', opp.operacion_id,
                                'operacion_codigo', o.codigo,
                                'operacion_nombre', o.nombre,
                                
                                -- Recursos
                                'maquina_asignada_id', opp.maquina_asignada_id,
                                'maquina_nombre', maquina.nombre,
                                'empleado_id', opp.empleado_id,
                                
                                -- Parámetros
                                'ph', opp.ph,
                                'relacion_bano', opp.relacion_bano,
                                'temperatura', opp.temperatura,
                                'tiempo_estandar', opp.tiempo_estandar,
                                'receta_id', opp.receta_id,
                                
                                -- Estado
                                'estado', opp.estado,
                                'flg_final', opp.flg_final,
                                'fyh_inicio', opp.fyh_inicio,
                                'fyh_fin', opp.fyh_fin,
                                
                                -- ───────────────────────────────
                                -- CONSUMO (chemicals/auxiliaries)
                                -- ───────────────────────────────
                                'consumo', COALESCE((
                                    SELECT jsonb_agg(
                                        jsonb_build_object(
                                            'id', m.id,
                                            'item_id', m.item_id,
                                            'item_codigo', vi_mov.item_codigo,
                                            'item_nombre', vi_mov.item_nombre,
                                            'lote_id', m.lote_id,
                                            'cantidad', m.cantidad,
                                            'unidad', vi_mov.unidad_codigo,
                                            'origen_ubicacion_id', m.origen_ubicacion_id,
                                            'origen_ubicacion', ubi.nombre,
                                            'origen_almacen', al.nombre
                                        ) ORDER BY m.fyh_cre
                                    )
                                    FROM inventario.item_movimientos m
                                    LEFT JOIN vw_items vi_mov ON vi_mov.item_id = m.item_id
                                    LEFT JOIN inventario.ubicacion ubi ON ubi.id = m.origen_ubicacion_id
                                    LEFT JOIN inventario.almacen al ON al.id = ubi.almacen_id
                                    WHERE m.documento_tipo = 'orden_produccion_paso' 
                                    AND m.documento_id = opp.id
                                ), '[]'::jsonb),
                                
                                -- ───────────────────────────────
                                -- TRACKING (roll progression)
                                -- ───────────────────────────────
                                'items_procesados', COALESCE((
                                    SELECT jsonb_agg(
                                        jsonb_build_object(
                                            'id', oppi.id,
                                            'orden_produccion_item_id', oppi.orden_produccion_item_id,
                                            'cantidad', oppi.cantidad,
                                            'flg_consumido', oppi.flg_consumido
                                        ) ORDER BY oppi.id
                                    )
                                    FROM mes.orden_produccion_paso_item oppi
                                    WHERE oppi.orden_produccion_paso_id = opp.id
                                ), '[]'::jsonb)
                                
                            ) ORDER BY opp.secuencia
                        )
                        FROM mes.orden_produccion_paso opp
                        LEFT JOIN mes.operacion o ON o.id = opp.operacion_id
                        LEFT JOIN mes.maquina ON maquina.id = opp.maquina_asignada_id
                        WHERE opp.orden_produccion_id = op.id
                    ), '[]'::jsonb),
                    
                    -- ───────────────────────────────────
                    -- MATERIALS RESERVED (rolls)
                    -- ───────────────────────────────────
                    'materiales_reservados', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id', opi.id,
                                'lote_id', opi.lote_id,
                                'item_id', l.item_id,
                                'item_codigo', vi_mat.item_codigo,
                                'item_nombre', vi_mat.item_nombre,
                                'cantidad', opi.cantidad,
                                'peso_kg', opi.peso_kg,
                                'unidad', vi_mat.unidad_codigo,
                                'detalles', l.detalles,
                                'estado_calidad', l.estado_calidad
                            ) ORDER BY opi.id
                        )
                        FROM mes.orden_produccion_item opi
                        LEFT JOIN inventario.lote l ON l.id = opi.lote_id
                        LEFT JOIN vw_items vi_mat ON vi_mat.item_id = l.item_id
                        WHERE opi.orden_produccion_id = op.id  -- ✅ FIXED
                    ), '[]'::jsonb),
                    
                    -- ───────────────────────────────────
                    -- PRODUCTION OUTPUT (finished goods)
                    -- ───────────────────────────────────
                    'produccion', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id', l.id,
                                'item_id', l.item_id,
                                'item_codigo', vi_prod.item_codigo,
                                'item_nombre', vi_prod.item_nombre,
                                'cantidad', l.cantidad,
                                'unidad', vi_prod.unidad_codigo,
                                'detalles', l.detalles,
                                'estado_calidad', l.estado_calidad,
                                'fyh_cre', l.fyh_cre,
                                
                                -- ═══════════════════════════════
                                -- INSPECTIONS (QC history)
                                -- ═══════════════════════════════
                                'inspecciones', COALESCE((
                                    SELECT jsonb_agg(
                                        jsonb_build_object(
                                            'id', insp.id,
                                            'resultado', insp.resultado,
                                            'observacion', insp.observacion,
                                            'empleado_id', insp.empleado_id,
                                            'empleado_nombre', CONCAT(emp.nombre, ' ', emp.apellido),
                                            'fyh_inspeccion', insp.fyh_inspeccion
                                        ) ORDER BY insp.fyh_inspeccion DESC
                                    )
                                    FROM calidad.inspeccion insp
                                    LEFT JOIN mes.empleado emp ON emp.id = insp.empleado_id
                                    WHERE insp.lote_id = l.id
                                ), '[]'::jsonb)
                            ) ORDER BY l.fyh_cre
                        )
                        FROM inventario.lote l
                        LEFT JOIN vw_items vi_prod ON vi_prod.item_id = l.item_id
                        WHERE l.documento_tipo = 'orden_produccion'
                        AND l.documento_id = op.id
                    ), '[]'::jsonb)
                    
                ) ORDER BY op.id
            )
            FROM mes.orden_produccion op
            WHERE op.partida_id = p.id
        ), '[]'::jsonb)
        
    ) INTO v_result
    FROM doc.partida p
    LEFT JOIN prioridad pri ON pri.id = p.prioridad_id
    LEFT JOIN cliente c ON c.id = p.cliente_id
    LEFT JOIN tenido ON tenido.id = p.tenido_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE p.id = p_partida_id;
    
    RETURN v_result;
END;
$function$;

-- ══════════════════════════════════════════════════════════
-- NOTES ON STRUCTURE:
-- ══════════════════════════════════════════════════════════
/*
partida
├─ partida_detalles (what client ordered)
└─ ordenes_produccion[]
   ├─ pasos[]
   │  ├─ consumo[] (chemicals used)
   │  └─ items_procesados[] (which rolls went through this step)
   ├─ materiales_reservados[] (rolls assigned to this order)
   └─ produccion[] (finished goods)
      └─ inspecciones[] (QC history per lote) ← ADDED!

BENEFITS OF INCLUDING INSPECTIONS:
- Traceability: Know when/why/who rejected
- Compliance: Required for ISO/quality audits
- Analytics: Track inspector accuracy, rejection rates
- Debugging: Understand reproceso flow
*/

CREATE OR REPLACE FUNCTION mes.crear_orden_produccion(p_orden jsonb)
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
    v_orden_id  bigint;
    v_usr_id    int := get_user_id();
    v_error_payload jsonb;
BEGIN
    -- --------------------------------------------------
-- ---VALIDAR DISPONIBILIDAD DE ROLLOS RESERVADOS
-- --------------------------------------------------
WITH orden_rollos AS (
        SELECT
            (i->>'item_id')::int        AS item_id,
            (i->>'lote_id')::int        AS lote_id,
            (i->>'ubicacion_id')::int  AS ubicacion_id,
            SUM((i->>'cantidad')::numeric)  AS cantidad
        FROM jsonb_array_elements(p_orden->'orden_produccion_item') i
        GROUP BY 1,2,3
    ),errores as(  SELECT
            im.item_id,
            im.lote_id,
            COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id) AS ubicacion_id,
            items.cantidad,
            SUM(im.cantidad*imt.factor) AS saldo
        FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON im.item_movimiento_tipo_id = imt.id
        JOIN orden_rollos AS items ON items.lote_id=im.lote_id AND items.ubicacion_id= COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        GROUP BY im.item_id, im.lote_id, COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id),items.cantidad
        HAVING SUM(im.cantidad*imt.factor)< items.cantidad
    ) SELECT jsonb_agg(
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
        RAISE EXCEPTION
            'Stock insuficiente para emitir la guía'
            USING
                DETAIL  = v_error_payload::text;
    END IF;


    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_orden_produccion', v_usr_id, p_orden);

    INSERT INTO mes.orden_produccion(partida_id, tipo, orden_origen_id)
    VALUES (
        (p_orden->>'partida_id')::BIGINT,
        (p_orden->>'tipo')::orden_produccion_tipo_enum,
        (p_orden->>'orden_origen_id')::BIGINT
    )
    RETURNING id INTO v_orden_id;

    INSERT INTO mes.orden_produccion_item(
        orden_produccion_id, item_id, lote_id, cantidad, ubicacion_id
    )
    SELECT v_orden_id,
           (i->>'item_id')::INT,
           (i->>'lote_id')::INT,
           (i->>'cantidad')::NUMERIC,
           (i->>'ubicacion_id')::INT
    FROM jsonb_array_elements(p_orden->'orden_produccion_item') i;

    INSERT INTO mes.orden_produccion_paso(
        orden_produccion_id, secuencia, operacion_id,
        maquina_asignada_id, receta_id, ph,
        temperatura, tiempo_estandar, relacion_bano
    )
    SELECT v_orden_id,
           (p->>'secuencia')::SMALLINT,
           (p->>'operacion_id')::SMALLINT,
           (p->>'maquina_asignada_id')::INT,
           (p->>'receta_id')::INT,
           (p->>'ph')::NUMERIC,
           (p->>'temperatura')::NUMERIC,
           (p->>'tiempo_estandar')::INT,
           (p->>'relacion_bano')::NUMERIC
    FROM jsonb_array_elements(p_orden->'pasos') p;

    -- Notification (before RETURN)
    INSERT INTO notification.notifications(user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Nueva Orden de Producción',
           COALESCE(
               (SELECT COALESCE(first_name, 'Usuario desconocido') || ' ' || last_name
                FROM profiles WHERE id_usuario = v_usr_id),
               'sistema'
           ) || ' creó la orden de producción #' || v_orden_id,
           'info',
           jsonb_build_object('objeto_tipo', 'orden_produccion', 'orden_produccion_id', v_orden_id)
    FROM iam.user_rol ur
    LEFT JOIN profiles p ON p.id_usuario = ur.user_id
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras')
      AND v_usr_id <> ur.user_id;

    RETURN format('Orden de producción con ID %s creada correctamente.', v_orden_id);

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        RAISE LOG 'Error en crear_orden_produccion - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_orden::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION mes.get_orden_produccion(p_orden_produccion_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'iam','public','inventario','doc','mes','calidad'
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- ═══════════════════════════════════════
        -- HEADER
        -- ═══════════════════════════════════════
        'id',              op.id,
        'tipo',            op.tipo,
        'estado',          op.estado,
        'orden_origen_id', op.orden_origen_id,
        'fyh_cre',         op.fyh_cre,
        'fyh_inicio',      op.fyh_inicio,
        'fyh_fin',         op.fyh_fin,

        -- ═══════════════════════════════════════
        -- PARTIDA CONTEXT (lightweight)
        -- ═══════════════════════════════════════
        'partida', jsonb_build_object(
            'id',                   p.id,
            'numero',               p.numero,
            'codigo',               EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0'),
            'estado',               p.estado,
            'cliente_id',           p.cliente_id,
            'cliente',              c.cliente,
            'color_x_cliente_id',   p.color_x_cliente_id,
            'color',                vc.color,
            'tono',                 vc.tono,
            'flg_antipilling',      p.flg_antipilling,
            'color_hex',            vc.color_hex,
            'color_x_cliente_hex',  vc.color_x_cliente_hex,
            'tenido_id',            p.tenido_id,
            'tenido',               tenido.tenido,
            'malla',                p.malla,
            'rendimiento',          p.rendimiento
        ),

        -- ═══════════════════════════════════════
        -- PASOS DE PRODUCCION
        -- ═══════════════════════════════════════
        'pasos', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id',                   opp.id,
                    'secuencia',            opp.secuencia,

                    -- Operación
                    'operacion_id',         opp.operacion_id,
                    'operacion_codigo',     o.codigo,
                    'operacion_nombre',     o.nombre,

                    -- Recursos
                    'maquina_asignada_id',  opp.maquina_asignada_id,
                    'maquina_nombre',       maq.nombre,
                    'empleado_id',          opp.empleado_id,
                    'empleado_nombre',      CONCAT(emp.nombre, ' ', emp.apellido),

                    -- Parámetros
                    'ph',                   opp.ph,
                    'temperatura',          opp.temperatura,
                    'tiempo_estandar',      opp.tiempo_estandar,
                    'relacion_bano',        opp.relacion_bano,
                    'receta_id',            opp.receta_id,

                    -- Estado
                    'estado',               opp.estado,
                    'flg_final',            opp.flg_final,
                    'fyh_inicio',           opp.fyh_inicio,
                    'fyh_fin',              opp.fyh_fin,

                    -- ─── PROGRAMACION ───
                    'programacion', (
                        SELECT jsonb_build_object(
                            'id',        prog.id,
                            'maquina_id', prog.maquina_id,
                            'fecha',     prog.fecha,
                            'secuencia', prog.secuencia,
                            'nota',      prog.nota
                        )
                        FROM mes.programacion prog
                        WHERE prog.orden_produccion_paso_id = opp.id
                        LIMIT 1
                    ),

                    -- ─── CONSUMO (chemicals/auxiliaries) ───
                    'consumo', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',                   m.id,
                                'item_id',              m.item_id,
                                'item_codigo',          vi_mov.item_codigo,
                                'item_nombre',          vi_mov.item_nombre,
                                'lote_id',              m.lote_id,
                                'cantidad',             m.cantidad,
                                'unidad',               vi_mov.unidad_codigo,
                                'origen_ubicacion_id',  m.origen_ubicacion_id,
                                'origen_ubicacion',     ubi.nombre,
                                'origen_almacen',       al.nombre
                            ) ORDER BY m.fyh_cre
                        )
                        FROM inventario.item_movimientos m
                        LEFT JOIN vw_items vi_mov ON vi_mov.item_id = m.item_id
                        LEFT JOIN inventario.ubicacion ubi ON ubi.id = m.origen_ubicacion_id
                        LEFT JOIN inventario.almacen al ON al.id = ubi.almacen_id
                        WHERE m.documento_tipo = 'orden_produccion_paso'
                          AND m.documento_id = opp.id
                    ), '[]'::jsonb),

                    -- ─── ITEMS PROCESADOS (roll tracking) ───
                    'items_procesados', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',                        oppi.id,
                                'orden_produccion_item_id',  oppi.orden_produccion_item_id,
                                'cantidad',                  oppi.cantidad,
                                'flg_consumido',             oppi.flg_consumido
                            ) ORDER BY oppi.id
                        )
                        FROM mes.orden_produccion_paso_item oppi
                        WHERE oppi.orden_produccion_paso_id = opp.id
                    ), '[]'::jsonb)

                ) ORDER BY opp.secuencia
            )
            FROM mes.orden_produccion_paso opp
            LEFT JOIN mes.operacion o     ON o.id   = opp.operacion_id
            LEFT JOIN mes.maquina maq     ON maq.id = opp.maquina_asignada_id
            LEFT JOIN mes.empleado emp    ON emp.id = opp.empleado_id
            WHERE opp.orden_produccion_id = op.id
        ), '[]'::jsonb),

        -- ═══════════════════════════════════════
        -- MATERIALES RESERVADOS (rolls assigned)
        -- ═══════════════════════════════════════
        'materiales_reservados', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id',              opi.id,
                    'lote_id',         opi.lote_id,
                    'item_id',         l.item_id,
                    'item_codigo',     vi_mat.item_codigo,
                    'item_nombre',     vi_mat.item_nombre,
                    'cantidad',        opi.cantidad,
                    'peso_kg',         opi.peso_kg,
                    'unidad',          vi_mat.unidad_codigo,
                    'ubicacion_id',    opi.ubicacion_id,
                    'ubicacion',       ubic.nombre,
                    'almacen',         alm.nombre,
                    'detalles',        l.detalles,
                    'estado_calidad',  l.estado_calidad
                ) ORDER BY opi.id
            )
            FROM mes.orden_produccion_item opi
            LEFT JOIN inventario.lote l        ON l.id = opi.lote_id
            LEFT JOIN vw_items vi_mat          ON vi_mat.item_id = l.item_id
            LEFT JOIN inventario.ubicacion ubic ON ubic.id = opi.ubicacion_id
            LEFT JOIN inventario.almacen alm   ON alm.id = ubic.almacen_id
            WHERE opi.orden_produccion_id = op.id
        ), '[]'::jsonb),

        -- ═══════════════════════════════════════
        -- PRODUCCION (output lotes)
        -- ═══════════════════════════════════════
        'produccion', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id',              l.id,
                    'item_id',         l.item_id,
                    'item_codigo',     vi_prod.item_codigo,
                    'item_nombre',     vi_prod.item_nombre,
                    'cantidad',        l.cantidad,
                    'unidad',          vi_prod.unidad_codigo,
                    'detalles',        l.detalles,
                    'estado_calidad',  l.estado_calidad,
                    'fyh_cre',         l.fyh_cre,

                    -- ─── INSPECCIONES (QC) ───
                    'inspecciones', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',               insp.id,
                                'resultado',        insp.resultado,
                                'observacion',      insp.observacion,
                                'empleado_id',      insp.empleado_id,
                                'empleado_nombre',  CONCAT(emp_i.nombre, ' ', emp_i.apellido),
                                'fyh_inspeccion',   insp.fyh_inspeccion
                            ) ORDER BY insp.fyh_inspeccion DESC
                        )
                        FROM calidad.inspeccion insp
                        LEFT JOIN mes.empleado emp_i ON emp_i.id = insp.empleado_id
                        WHERE insp.lote_id = l.id
                    ), '[]'::jsonb)
                ) ORDER BY l.fyh_cre
            )
            FROM inventario.lote l
            LEFT JOIN vw_items vi_prod ON vi_prod.item_id = l.item_id
            WHERE l.documento_tipo = 'orden_produccion'
              AND l.documento_id = op.id
        ), '[]'::jsonb)

    ) INTO v_result
    FROM mes.orden_produccion op
    JOIN doc.partida p      ON p.id = op.partida_id
    LEFT JOIN cliente c     ON c.id = p.cliente_id
    LEFT JOIN tenido        ON tenido.id = p.tenido_id
    LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
    WHERE op.id = p_orden_produccion_id;

    RETURN v_result;
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
 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_plantilla', v_usr_id, p_plantilla::TEXT);

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
SELECT ur.user_id,'Nueva Plantilla Creada', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' creó una nueva plantilla', 'info',jsonb_build_object('objeto_tipo','plantilla','plantilla_id',v_plantilla_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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



CREATE OR REPLACE FUNCTION mes.planificar_partida(p_orden_produccion_pasos jsonb)
 RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','mes','doc'
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
 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('planificar_partida', v_usr_id, p_orden_produccion_pasos::TEXT);
    INSERT INTO orden_produccion_paso (
        partida_id,
        secuencia,
        operacion_id
        estado
    )
    VALUES (
        (p_orden_produccion_pasos->>'partida_id')::BIGINT,
        (p_orden_produccion_pasos->>'secuencia')::INT,
        (p_orden_produccion_pasos->>'operacion_id')::smallint,
        'PENDIENTE'
    )
    RETURNING id INTO v_item_id;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Partida Planificada', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' planificó la partida' || COALESCE(p_orden_produccion_pasos->>'partida_id','error'), 'info',jsonb_build_object('objeto_tipo','partida','partida_id', (p_orden_produccion_pasos->>'partida_id')::BIGINT)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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

        RAISE LOG 'Error in planificar_partida - User: %, Params: %, Error: %, Detail: %',
                  v_usr_id, p_orden_produccion_pasos::TEXT, v_message, v_detail;
        RAISE;
END;
$function$;



CREATE FUNCTION doc.crear_guia(p_guia json)
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
    v_guia_id   INT;
    v_guia_tipo guia_remision_tipo%ROWTYPE;
    -- v_item_movimiento_tipo item_movimiento_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_lote_id int;
    v_error_payload jsonb;
    v_fecha_mov TIMESTAMPTZ;
BEGIN
 -- guard condition
 SELECT * INTO v_guia_tipo FROM guia_remision_tipo WHERE id = (p_guia->>'guia_remision_tipo_id')::SMALLINT;
--  SELECT * INTO v_item_movimiento_tipo FROM inventario.item_movimiento_tipo WHERE id = v_guia_tipo.item_movimiento_tipo_id;
 IF NOT FOUND THEN
     RAISE EXCEPTION 'Tipo de guía con id % no existe', (p_guia->>'guia_remision_tipo_id');
 END IF;

 -- Movement timestamp: for incoming guias use fecha_recepcion (allows backdating), for outgoing use now()
 v_fecha_mov := CASE
     WHEN v_guia_tipo.flg_emitida THEN now()
     ELSE COALESCE((p_guia->>'fecha_recepcion')::TIMESTAMPTZ, now())
 END;

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
    ),errores as(  SELECT
            im.item_id,
            item.nombre AS item_nombre,
            im.lote_id,
            sa.ubicacion_id,
            items.cantidad,
            sa.cantidad_disponible
        FROM inventario.vw_stock_actual sa
        JOIN guia_items AS items ON guia_items.item_id=sa.item_id AND guia_items.lote_id=sa.lote_id AND guia_items.ubicacion_id= sa.ubicacion_id
        JOIN item ON item.id = sa.item_id
        WHERE sa.cantidad_disponible < items.cantidad
        GROUP BY sa.item_id, sa.lote_id, sa.ubicacion_id,items.cantidad
        
    ) SELECT jsonb_agg(
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
-----------------------------------------------------------------------------------------------------------------------
    IF v_guia_tipo.flg_cliente AND (p_guia->>'receptor_cliente_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba receptor_cliente_id para documento de cliente emitido';
    ELSIF NOT v_guia_tipo.flg_cliente AND (p_guia->>'receptor_proveedor_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba receptor_proveedor_id para documento de proveedor emitido';
    END IF;
ELSE
    -- incoming
    IF v_guia_tipo.flg_cliente AND (p_guia->>'emisor_cliente_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba emisor_cliente_id para documento de cliente recibido';
    ELSIF NOT v_guia_tipo.flg_cliente AND (p_guia->>'emisor_proveedor_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba emisor_proveedor_id para documento de proveedor recibido';
    END IF;
END IF;

 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_guia', v_usr_id, p_guia::TEXT);

    INSERT INTO doc.guia_remision(guia_remision_tipo_id, serie, correlativo, emisor_cliente_id, emisor_proveedor_id, receptor_cliente_id, receptor_proveedor_id, fecha_emision, fecha_recepcion)
    VALUES (
        (p_guia->>'guia_remision_tipo_id')::INT,
        p_guia->>'serie',
        p_guia->>'correlativo',
        CASE
            WHEN p_guia ? 'emisor_cliente_id' THEN (p_guia->>'emisor_cliente_id')::INT
            ELSE NULL
        END,
        CASE
            WHEN p_guia ? 'emisor_proveedor_id' THEN (p_guia->>'emisor_proveedor_id')::INT
            ELSE NULL
        END,
        CASE
            WHEN p_guia ? 'receptor_cliente_id' THEN (p_guia->>'receptor_cliente_id')::INT
            ELSE NULL
        END,
        CASE
            WHEN p_guia ? 'receptor_proveedor_id' THEN (p_guia->>'receptor_proveedor_id')::INT
            ELSE NULL
        END,
        (p_guia->>'fecha_emision')::DATE,
        CASE
            WHEN v_guia_tipo.flg_emitida THEN NULL
            ELSE COALESCE((p_guia->>'fecha_recepcion')::TIMESTAMPTZ, now())
        END
    )
    RETURNING id INTO v_guia_id;

INSERT INTO doc.guia_remision_detalle (guia_remision_id , item_id, cantidad,lote_id,ubicacion_id)
SELECT
    v_guia_id,
    (item->>'item_id')::INT,
    (item->>'cantidad')::NUMERIC(12,2),
    (item->>'lote_id')::INT,
    (item->>'ubicacion_id')::INT
FROM jsonb_array_elements(p_guia->'items') AS item;

IF v_guia_tipo.flg_emitida THEN
    -- For issued guides, create item movements as EGRESO from warehouse
    INSERT INTO inventario.item_movimientos 
    (
        item_id, 
        lote_id, 
        item_movimiento_tipo_id,
        origen_ubicacion_id,
        destino_ubicacion_id,
        cantidad, fecha_hora, documento_tipo, documento_id)
    SELECT
        (item->>'item_id')::INT,
        (item->>'lote_id')::INT, 
        v_guia_tipo.item_movimiento_tipo_id,
        (p_guia->>'origen_ubicacion_id')::INT,
        NULL, -- destination is external
        (item->>'cantidad')::NUMERIC(12,2),
        v_fecha_mov,
        'GUIA_REMISION',
        v_guia_id
    FROM jsonb_array_elements(p_guia->'items') AS item;
ELSE
 -- Items WITH lote_id → existing lots (devolution)
    INSERT INTO inventario.item_movimientos
        (item_id, lote_id, item_movimiento_tipo_id,
         destino_ubicacion_id, cantidad, fecha_hora,
         documento_tipo, documento_id)
    SELECT
        (item->>'item_id')::INT,
        (item->>'lote_id')::INT,
        v_guia_tipo.item_movimiento_tipo_id,
        (item->>'ubicacion_id')::INT,
        (item->>'cantidad')::NUMERIC(12,2),
        v_fecha_mov,
        'GUIA_REMISION',
        v_guia_id
    FROM jsonb_array_elements(p_guia->'items') AS item
    WHERE item->>'lote_id' IS NOT NULL;
WITH nuevos_lotes AS(
    INSERT INTO lote (
        item_id, 
        documento_tipo, 
        documento_id, 
        cantidad,
        detalles
        )
    SELECT
    (item->>'item_id')::INT,
    'GUIA_REMISION',
    v_guia_id,
    (item->>'cantidad')::NUMERIC(12,2),
    jsonb_build_object('peso', (item->>'peso')::NUMERIC(12,2))
    FROM jsonb_array_elements(p_guia->'items') AS item
    WHERE item->>'lote_id' IS NULL
    RETURNING id,item_id
) -- For received guides, create item movements as INGRESO to warehouse
INSERT INTO inventario.item_movimientos (item_id, lote_id, item_movimiento_tipo_id, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id)
    SELECT
        (item->>'item_id')::INT,
        nl.id, --id del lote recien creado
        v_guia_tipo.item_movimiento_tipo_id,
        NULL, -- origin is external
        (p_guia->>'destino_ubicacion_id')::INT,
        (item->>'cantidad')::NUMERIC(12,2),
        v_fecha_mov,
        'GUIA_REMISION',
        v_guia_id
    FROM jsonb_array_elements(p_guia->'items') AS item
    JOIN nuevos_lotes nl ON nl.item_id = (item->>'item_id')::INT
    ;
END IF;
INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Guia y movimientos', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' creó una nueva guía de remisión y generó movimientos de inventario', 'info',jsonb_build_object('objeto_tipo','guia_remision','guia_remision_id',v_guia_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
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
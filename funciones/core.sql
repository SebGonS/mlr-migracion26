
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
    v_partida_id           BIGINT;
    v_usr_id               int := get_user_id();
    v_error_payload        jsonb;
    v_overflow_item_id     INT;
    v_rollos_submitted     INT;
    v_cantidad_planificada NUMERIC;
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
        malla, rendimiento, ancho, color_x_cliente_id, flg_antipilling, flg_doble_bolsa,
        fecha_acordada, observacion
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



CREATE OR REPLACE FUNCTION doc.crear_entrega(p_entrega jsonb)
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

 -- COMPRA_INGRESO must always be tied to a compra — ensures precio_unitario is available
 -- and stock is traceable to a PO. Use doc.ingresar_compra when no entrega is in hand.
 IF v_entrega_tipo.codigo = 'COMPRA_INGRESO' AND (p_entrega->>'compra_id') IS NULL THEN
     RAISE EXCEPTION 'Guía tipo COMPRA_INGRESO requiere compra_id'
         USING HINT = 'Si no tiene guía física aún, use doc.ingresar_compra en su lugar.';
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

-- COMPRA_INGRESO: static document registration only.
-- Movements are always posted separately via doc.ingresar_compra.
-- Returning early here prevents any possibility of double-posting.
IF v_entrega_tipo.codigo = 'COMPRA_INGRESO' THEN
    INSERT INTO doc.compra_entrega (compra_id, entrega_id)
    VALUES ((p_entrega->>'compra_id')::BIGINT, v_entrega_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO doc.entrega_detalle (entrega_id, linea, item_id, cantidad, n_rollos)
    SELECT v_entrega_id,
           COALESCE((item->>'linea')::SMALLINT, (row_number() OVER ())::SMALLINT),
           (item->>'item_id')::INT, (item->>'cantidad')::NUMERIC,
           (item->>'cantidad_rollos')::INT
    FROM jsonb_array_elements(p_entrega->'items') AS item;

    RETURN format('Guía de remisión con ID %s registrada (documento SUNAT — sin movimientos).', v_entrega_id);
END IF;

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
   RETURN format('Guía de remisión con ID %s creada correctamente.', v_entrega_id);
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
-- ORDEN DE SERVICIO — order / receipt / reversal (compra-style split)
-- ───────────────────────────────────────────────────────────────
-- The OS document (header + lines) is ORDERED intent and posts no stock.
-- Receiving is a separate, additive ledger event (ingresar_orden_servicio)
-- that posts SERV_ING — mirrors doc.compra / doc.ingresar_compra.
--   orden_servicio_detalle.cantidad           = ordered roll count (intent)
--   orden_servicio_detalle.cantidad_recibida  = received so far (bumped by receipt)
-- Corrections never delete: more rolls = another receipt; fewer rolls =
-- revertir_recepcion_orden_servicio (posts SERV_ING_REV, append-only).
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- doc.ingresar_orden_servicio  (goods receipt — WRITES THE LEDGER)
-- Posts SERV_ING for rolls physically received against existing OS lines.
-- Additive: call once per arrival (first batch and every later one).
--
-- p_datos:
-- {
--   "orden_servicio_id": 6,
--   "ubicacion_id":      8,        -- optional, defaults to ALM_CRU
--   "fecha_recepcion":   null,     -- optional, defaults now()
--   "lineas": [
--     { "detalle_id": 18, "cantidad_rollos": 3,
--       "peso_total": null,        -- optional; split evenly, else 0.1/roll sentinel
--       "factura_hilo": null }     -- optional; else inherits the line's existing value
--   ]
-- }
-- Returns the doc_movimiento_id of the receipt.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.ingresar_orden_servicio(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_usr_id            INT    := get_user_id();
    v_os_id             BIGINT := (p_datos->>'orden_servicio_id')::BIGINT;
    v_os                RECORD;
    v_serv_ing_tipo_id  SMALLINT;
    v_doc_mov_id        BIGINT;
    v_ubicacion_id      INT;
    v_fecha_mov         TIMESTAMPTZ;
    v_linea             jsonb;
    v_detalle_id        BIGINT;
    v_extra             INT;
    v_item_id           INT;
    v_malla             TEXT;
    v_factura_hilo      TEXT;
    v_peso_por_rollo    NUMERIC;
    v_new_lote_id       INT;
    v_recibida          INT;
    v_ordenada          INT;
    i                   INT;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('ingresar_orden_servicio', v_usr_id, p_datos);

    SELECT * INTO v_os FROM doc.orden_servicio
    WHERE id = v_os_id AND flg_elm = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'orden_servicio % no existe o fue eliminada.', v_os_id;
    END IF;

    SELECT id INTO STRICT v_serv_ing_tipo_id
    FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING';

    IF (p_datos->>'ubicacion_id') IS NOT NULL THEN
        v_ubicacion_id := (p_datos->>'ubicacion_id')::INT;
    ELSE
        SELECT ub.id INTO STRICT v_ubicacion_id
        FROM inventario.ubicacion ub
        JOIN inventario.almacen alm ON alm.id = ub.almacen_id
        WHERE alm.codigo = 'ALM_CRU' LIMIT 1;
    END IF;

    v_fecha_mov  := COALESCE((p_datos->>'fecha_recepcion')::TIMESTAMPTZ, now());
    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    FOR v_linea IN SELECT jsonb_array_elements(p_datos->'lineas')
    LOOP
        v_detalle_id := (v_linea->>'detalle_id')::BIGINT;
        v_extra      := (v_linea->>'cantidad_rollos')::INT;

        IF v_extra IS NULL OR v_extra <= 0 THEN
            RAISE EXCEPTION 'Línea %: cantidad_rollos debe ser > 0.', v_detalle_id;
        END IF;

        SELECT osd.item_id, osd.malla
        INTO v_item_id, v_malla
        FROM doc.orden_servicio_detalle osd
        JOIN item it_      ON it_.id = osd.item_id
        JOIN item_tipo itp ON itp.id = it_.item_tipo_id
        WHERE osd.id = v_detalle_id
          AND osd.orden_servicio_id = v_os_id
          AND itp.codigo = 'ROLLO';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'detalle % no es una línea ROLLO de la orden_servicio %.', v_detalle_id, v_os_id;
        END IF;

        -- peso_total optional; 0.1 kg/roll sentinel until weighing corrects it
        v_peso_por_rollo := COALESCE(
            (v_linea->>'peso_total')::NUMERIC / NULLIF(v_extra, 0),
            0.1
        );

        -- factura_hilo line-level fallback (used when no grupos)
        v_factura_hilo := v_linea->>'factura_hilo';
        IF v_factura_hilo IS NULL THEN
            SELECT lrd.factura_hilo INTO v_factura_hilo
            FROM inventario.lote_rollo_detalle lrd
            JOIN inventario.item_movimientos im ON im.lote_id = lrd.lote_id
            WHERE im.documento_tipo     = 'orden_servicio'
              AND im.documento_id       = v_os_id
              AND im.documento_linea_id = v_detalle_id
            LIMIT 1;
        END IF;

        -- Build normalised groups: [{cantidad_rollos, factura_hilo}, ...]
        -- If caller supplies "grupos" array, validate its sum; otherwise treat
        -- the whole line as one group using the line-level factura_hilo.
        DECLARE
            v_grupos       JSONB;
            v_grupo        JSONB;
            v_grupo_cant   INT;
            v_grupo_fac    TEXT;
            v_grupos_sum   INT := 0;
        BEGIN
            v_grupos := v_linea->'grupos';

            IF v_grupos IS NOT NULL AND jsonb_array_length(v_grupos) > 0 THEN
                -- validate sum matches cantidad_rollos
                SELECT SUM((g->>'cantidad_rollos')::INT)
                INTO v_grupos_sum
                FROM jsonb_array_elements(v_grupos) g;

                IF v_grupos_sum <> v_extra THEN
                    RAISE EXCEPTION
                        'Línea %: suma de grupos (%) ≠ cantidad_rollos (%).',
                        v_detalle_id, v_grupos_sum, v_extra;
                END IF;
            ELSE
                -- synthesise a single group from line-level fields
                v_grupos := jsonb_build_array(
                    jsonb_build_object(
                        'cantidad_rollos', v_extra,
                        'factura_hilo',    v_factura_hilo
                    )
                );
            END IF;

            FOR v_grupo IN SELECT jsonb_array_elements(v_grupos)
            LOOP
                v_grupo_cant := (v_grupo->>'cantidad_rollos')::INT;
                v_grupo_fac  := v_grupo->>'factura_hilo';

                FOR i IN 1 .. v_grupo_cant
                LOOP
                    INSERT INTO inventario.lote (item_id, documento_tipo, documento_id, cantidad, propietario_id, usr_cre)
                    VALUES (v_item_id, 'orden_servicio', v_os_id, v_peso_por_rollo, NULL, v_usr_id)
                    RETURNING id INTO v_new_lote_id;

                    INSERT INTO inventario.lote_rollo_detalle (
                        lote_id, orden_servicio_id, ancho, malla, rendimiento,
                        flg_tenido, flg_antipilling, factura_hilo
                    ) VALUES (
                        v_new_lote_id, v_os_id, v_os.ancho, v_malla, v_os.rendimiento,
                        false, COALESCE(v_os.flg_antipilling, false), v_grupo_fac
                    );

                    INSERT INTO inventario.item_movimientos (
                        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
                        destino_ubicacion_id, cantidad, fecha_hora,
                        documento_tipo, documento_id, documento_linea_id, usr_cre
                    ) VALUES (
                        v_doc_mov_id, v_item_id, v_new_lote_id, v_serv_ing_tipo_id,
                        v_ubicacion_id, v_peso_por_rollo, v_fecha_mov,
                        'orden_servicio', v_os_id, v_detalle_id, v_usr_id
                    );
                END LOOP;
            END LOOP;
        END;

        UPDATE doc.orden_servicio_detalle
        SET cantidad_recibida = cantidad_recibida + v_extra
        WHERE id = v_detalle_id
        RETURNING cantidad_recibida, cantidad INTO v_recibida, v_ordenada;

        IF v_recibida > v_ordenada THEN
            RAISE NOTICE 'detalle %: recibido % supera lo ordenado % (over-receipt).',
                         v_detalle_id, v_recibida, v_ordenada;
        END IF;
    END LOOP;

    RETURN v_doc_mov_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE LOG 'Error in ingresar_orden_servicio - User: %, Params: %, Error: %',
                  v_usr_id, p_datos::TEXT, SQLERRM;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.ingresar_orden_servicio(jsonb) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- doc.crear_orden_servicio  (the ORDER — posts no stock by itself)
-- Inserts the header + ordered lines. If destino_ubicacion_id is given
-- (rolls arrived with the order), delegates the first receipt to
-- ingresar_orden_servicio; otherwise the OS is order-only and rolls are
-- received later. Receipt logic lives in one place.
--
-- Input JSON shape:
-- {
--   "tercero_id":          5,
--   "serie":               "OS",
--   "correlativo":         1,
--   "fecha_entrega":       "2026-06-20",   -- optional
--   "rendimiento":         "1.25",          -- optional, applies to all rolls
--   "ancho":               "160",           -- optional
--   "flg_antipilling":     false,
--   "flg_urgente":         false,
--   "observacion":         null,
--   "factura":             null,
--   "destino_ubicacion_id": 1,              -- present => post first receipt
--   "lineas": [
--     {
--       "linea":              1,
--       "item_id":            42,
--       "malla":              "28",
--       "factura_hilo":       "H-123",         -- optional; thread invoice (line default)
--       "cantidad_rollos":    5,                -- ordered count
--       "peso_total":         null,             -- optional; for the first receipt
--       "grupos": [                             -- optional; per-invoice roll groups
--         { "cantidad_rollos": 3, "factura_hilo": "H-123" },
--         { "cantidad_rollos": 2, "factura_hilo": "H-456" }
--       ],                                      -- sum must equal cantidad_rollos
--       "color_x_cliente_id": 10,
--       "tenido_id":          3,
--       "flg_doble_bolsa":    false
--     }
--   ]
-- }
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.crear_orden_servicio(p_orden jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_usr_id        INT := get_user_id();
    v_os_id         BIGINT;
    v_linea         jsonb;
    v_detalle_id    BIGINT;
    v_recibir       jsonb := '[]'::jsonb;   -- accumulated first-receipt lines
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF (p_orden->>'tercero_id') IS NULL THEN
        RAISE EXCEPTION 'crear_orden_servicio: se requiere tercero_id';
    END IF;

    INSERT INTO doc.orden_servicio (
        tercero_id, serie, correlativo,
        fecha_entrega, rendimiento, ancho,
        flg_antipilling, flg_urgente,
        observacion, factura, usr_cre
    ) VALUES (
        (p_orden->>'tercero_id')::INT,
        p_orden->>'serie',
        (p_orden->>'correlativo')::INT,
        (p_orden->>'fecha_entrega')::DATE,
        p_orden->>'rendimiento',
        p_orden->>'ancho',
        COALESCE((p_orden->>'flg_antipilling')::BOOLEAN, false),
        COALESCE((p_orden->>'flg_urgente')::BOOLEAN, false),
        p_orden->>'observacion',
        p_orden->>'factura',
        v_usr_id
    )
    RETURNING id INTO v_os_id;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('crear_orden_servicio', v_usr_id, p_orden);

    -- Ordered lines (intent only — no stock posted here)
    FOR v_linea IN SELECT value FROM jsonb_array_elements(p_orden->'lineas')
    LOOP
        INSERT INTO doc.orden_servicio_detalle (
            orden_servicio_id, linea, item_id, malla,
            cantidad, color_x_cliente_id, tenido_id, flg_doble_bolsa
        ) VALUES (
            v_os_id,
            COALESCE((v_linea->>'linea')::SMALLINT, 1),
            (v_linea->>'item_id')::INT,
            v_linea->>'malla',
            (v_linea->>'cantidad_rollos')::INT,
            (v_linea->>'color_x_cliente_id')::INT,
            (v_linea->>'tenido_id')::INT,
            COALESCE((v_linea->>'flg_doble_bolsa')::BOOLEAN, false)
        )
        RETURNING id INTO v_detalle_id;

        v_recibir := v_recibir || jsonb_build_object(
            'detalle_id',     v_detalle_id,
            'cantidad_rollos', (v_linea->>'cantidad_rollos')::INT,
            'peso_total',      (v_linea->>'peso_total'),
            'factura_hilo',    (v_linea->>'factura_hilo')
        );
    END LOOP;

    -- First receipt: only when a destination is given (rolls arrived with the order)
    IF (p_orden->>'destino_ubicacion_id') IS NOT NULL THEN
        PERFORM doc.ingresar_orden_servicio(jsonb_build_object(
            'orden_servicio_id', v_os_id,
            'ubicacion_id',      (p_orden->>'destino_ubicacion_id')::INT,
            'lineas',            v_recibir
        ));
    END IF;

    INSERT INTO notification.notifications (user_id, title, body, tipo, payload)
    SELECT ur.user_id,
           'Nueva Orden de Servicio',
           COALESCE((SELECT COALESCE(nombre, 'Usuario desconocido') || ' ' || apellido FROM usuario WHERE id = v_usr_id), 'sistema')
               || ' creó la orden de servicio ' || (p_orden->>'serie') || '-' || (p_orden->>'correlativo'),
           'info',
           jsonb_build_object('objeto_tipo', 'orden_servicio', 'orden_servicio_id', v_os_id)
    FROM iam.user_rol ur
    LEFT JOIN iam.rol r ON ur.rol_id = r.id
    WHERE r.code IN ('jefe_planta', 'compras', 'inventario')
      AND v_usr_id <> ur.user_id;

    RETURN format('Orden de servicio %s creada con ID %s.', (p_orden->>'serie') || '-' || (p_orden->>'correlativo'), v_os_id);
EXCEPTION
    WHEN OTHERS THEN
        RAISE LOG 'Error in crear_orden_servicio - User: %, Params: %, Error: %',
                  v_usr_id, p_orden::TEXT, SQLERRM;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.crear_orden_servicio(jsonb) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- doc.revertir_recepcion_orden_servicio  (append-only un-receive)
-- Reverses received rolls: posts SERV_ING_REV (egress, nets stock to
-- zero via lote_saldo trigger), soft-deletes the roll lote, decrements
-- cantidad_recibida. The original SERV_ING stays — the ledger only grows.
-- Refuses rolls reserved by an active partida or with downstream movements.
--
-- p_datos:
-- {
--   "orden_servicio_id": 6,
--   "lote_ids": [101, 102],
--   "motivo": "conteo corregido"   -- optional
-- }
-- Returns the doc_movimiento_id of the reversal.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.revertir_recepcion_orden_servicio(p_datos jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'mes', 'inventario'
AS $function$
DECLARE
    v_usr_id         INT    := get_user_id();
    v_os_id          BIGINT := (p_datos->>'orden_servicio_id')::BIGINT;
    v_rev_tipo_id    SMALLINT;
    v_serv_ing_id    SMALLINT;
    v_doc_mov_id     BIGINT;
    v_motivo         TEXT   := p_datos->>'motivo';
    v_lote           RECORD;
    v_ubic           INT;
    v_detalle_id     BIGINT;
BEGIN
    -- reversal/anular is an editar-tier action (per the entrega convention)
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('revertir_recepcion_orden_servicio', v_usr_id, p_datos);

    IF NOT EXISTS (SELECT 1 FROM doc.orden_servicio WHERE id = v_os_id AND flg_elm = false) THEN
        RAISE EXCEPTION 'orden_servicio % no existe o fue eliminada.', v_os_id;
    END IF;

    SELECT id INTO STRICT v_rev_tipo_id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING_REV';
    SELECT id INTO STRICT v_serv_ing_id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING';
    v_doc_mov_id := nextval('inventario.mov_doc_seq');

    FOR v_lote IN
        SELECT l.id, l.item_id, l.cantidad
        FROM inventario.lote l
        WHERE l.id IN (SELECT (jsonb_array_elements_text(p_datos->'lote_ids'))::INT)
          AND l.documento_tipo = 'orden_servicio'
          AND l.documento_id   = v_os_id
          AND l.fyh_elm IS NULL
    LOOP
        -- reserved by an active partida → block
        IF EXISTS (
            SELECT 1 FROM mes.partida_componente pc
            JOIN mes.partida p ON p.id = pc.partida_id
            WHERE pc.lote_id = v_lote.id
              AND p.estado_produccion NOT IN ('CANCELADA','TECO','CERRADA')
        ) THEN
            RAISE EXCEPTION 'Rollo % está reservado en una partida activa; no se puede revertir.', v_lote.id;
        END IF;

        -- any movement other than its SERV_ING ingress → already in play, block
        IF EXISTS (
            SELECT 1 FROM inventario.item_movimientos im
            WHERE im.lote_id = v_lote.id
              AND im.item_movimiento_tipo_id <> v_serv_ing_id
        ) THEN
            RAISE EXCEPTION 'Rollo % tiene movimientos posteriores; no se puede revertir.', v_lote.id;
        END IF;

        -- locate current location + the line from the ingress movement
        SELECT im.destino_ubicacion_id, im.documento_linea_id
        INTO v_ubic, v_detalle_id
        FROM inventario.item_movimientos im
        WHERE im.lote_id = v_lote.id
          AND im.documento_tipo = 'orden_servicio'
          AND im.documento_id   = v_os_id
        ORDER BY im.id LIMIT 1;

        INSERT INTO inventario.item_movimientos (
            doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
            origen_ubicacion_id, cantidad, fecha_hora,
            documento_tipo, documento_id, documento_linea_id, observacion, usr_cre
        ) VALUES (
            v_doc_mov_id, v_lote.item_id, v_lote.id, v_rev_tipo_id,
            v_ubic, v_lote.cantidad, now(),
            'orden_servicio', v_os_id, v_detalle_id, v_motivo, v_usr_id
        );

        UPDATE inventario.lote SET fyh_elm = now(), usr_elm = v_usr_id WHERE id = v_lote.id;

        UPDATE doc.orden_servicio_detalle
        SET cantidad_recibida = GREATEST(cantidad_recibida - 1, 0)
        WHERE id = v_detalle_id;
    END LOOP;

    RETURN v_doc_mov_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE LOG 'Error in revertir_recepcion_orden_servicio - User: %, Params: %, Error: %',
                  v_usr_id, p_datos::TEXT, SQLERRM;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.revertir_recepcion_orden_servicio(jsonb) TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- doc.actualizar_orden_servicio  (edit the ORDER — header + lines)
-- Edits intent only; never touches the ledger. Roll quantities arrive/
-- leave the ledger via ingresar_orden_servicio / revertir_recepcion_*.
-- Ordered (cantidad) and received (cantidad_recibida) are independent
-- axes coupled by one invariant: cantidad >= cantidad_recibida.
-- Exists so the direct INSERT/UPDATE grants on the tables can be revoked.
--
-- p_orden: header fields (NOT NULL cols keep value when omitted via COALESCE;
--   nullable cols touched only when the key is present). Optional 'lineas'
--   reconciles the ordered lines against the current set:
--     • line with "id"        → update (guarded)
--     • line without "id"      → insert (new ordered line)
--     • existing line omitted  → delete (blocked if it has received rolls)
--   Guards on received lines (cantidad_recibida > 0):
--     • cantidad cannot drop below cantidad_recibida
--     • item_id / color_x_cliente_id / tenido_id cannot change
--     • the line cannot be deleted (revert receipts first)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.actualizar_orden_servicio(p_os_id BIGINT, p_orden jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $function$
DECLARE
    v_usr_id     INT := get_user_id();
    v_existing   RECORD;
    v_linea      jsonb;
    v_recibida   INT;
    v_cur_item   INT;
    v_cur_color  INT;
    v_cur_tenido INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('actualizar_orden_servicio', v_usr_id,
            jsonb_build_object('os_id', p_os_id, 'orden', p_orden));

    IF NOT EXISTS (SELECT 1 FROM doc.orden_servicio WHERE id = p_os_id AND flg_elm = false) THEN
        RAISE EXCEPTION 'orden_servicio % no existe o fue eliminada.', p_os_id;
    END IF;

    -- ── Header ───────────────────────────────────────────────────
    UPDATE doc.orden_servicio SET
        tercero_id      = COALESCE((p_orden->>'tercero_id')::INT, tercero_id),
        serie           = COALESCE(p_orden->>'serie', serie),
        correlativo     = COALESCE((p_orden->>'correlativo')::INT, correlativo),
        flg_antipilling = COALESCE((p_orden->>'flg_antipilling')::BOOLEAN, flg_antipilling),
        flg_urgente     = COALESCE((p_orden->>'flg_urgente')::BOOLEAN, flg_urgente),
        fecha_entrega   = CASE WHEN p_orden ? 'fecha_entrega' THEN (p_orden->>'fecha_entrega')::DATE ELSE fecha_entrega END,
        rendimiento     = CASE WHEN p_orden ? 'rendimiento'   THEN p_orden->>'rendimiento'           ELSE rendimiento   END,
        ancho           = CASE WHEN p_orden ? 'ancho'         THEN p_orden->>'ancho'                 ELSE ancho         END,
        observacion     = CASE WHEN p_orden ? 'observacion'   THEN p_orden->>'observacion'           ELSE observacion   END,
        factura         = CASE WHEN p_orden ? 'factura'       THEN p_orden->>'factura'               ELSE factura       END
    WHERE id = p_os_id;

    -- ── Lines (optional reconcile) ───────────────────────────────
    IF p_orden ? 'lineas' THEN
        -- Deletions: existing lines absent from the payload.
        FOR v_existing IN
            SELECT id, cantidad_recibida
            FROM doc.orden_servicio_detalle
            WHERE orden_servicio_id = p_os_id
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_orden->'lineas') l
                WHERE (l->>'id')::BIGINT = v_existing.id
            ) THEN
                IF v_existing.cantidad_recibida > 0 THEN
                    RAISE EXCEPTION 'No se puede eliminar la línea %: tiene % rollos recibidos. Revierta la recepción primero.',
                        v_existing.id, v_existing.cantidad_recibida;
                END IF;
                DELETE FROM doc.orden_servicio_detalle WHERE id = v_existing.id;
            END IF;
        END LOOP;

        -- Upserts
        FOR v_linea IN SELECT jsonb_array_elements(p_orden->'lineas')
        LOOP
            IF (v_linea ? 'id') AND (v_linea->>'id') IS NOT NULL THEN
                SELECT cantidad_recibida, item_id, color_x_cliente_id, tenido_id
                INTO v_recibida, v_cur_item, v_cur_color, v_cur_tenido
                FROM doc.orden_servicio_detalle
                WHERE id = (v_linea->>'id')::BIGINT AND orden_servicio_id = p_os_id;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'La línea % no pertenece a la orden_servicio %.', (v_linea->>'id'), p_os_id;
                END IF;

                IF (v_linea->>'cantidad')::INT < v_recibida THEN
                    RAISE EXCEPTION 'Línea %: la cantidad ordenada (%) no puede ser menor a la recibida (%).',
                        (v_linea->>'id'), (v_linea->>'cantidad')::INT, v_recibida;
                END IF;

                IF v_recibida > 0 AND (
                       (v_linea->>'item_id')::INT            IS DISTINCT FROM v_cur_item
                    OR (v_linea->>'color_x_cliente_id')::INT IS DISTINCT FROM v_cur_color
                    OR (v_linea->>'tenido_id')::INT          IS DISTINCT FROM v_cur_tenido
                ) THEN
                    RAISE EXCEPTION 'Línea %: no se puede cambiar item/color/teñido con rollos ya recibidos.', (v_linea->>'id');
                END IF;

                UPDATE doc.orden_servicio_detalle SET
                    linea              = COALESCE((v_linea->>'linea')::SMALLINT, linea),
                    item_id            = (v_linea->>'item_id')::INT,
                    malla              = v_linea->>'malla',
                    cantidad           = (v_linea->>'cantidad')::INT,
                    color_x_cliente_id = (v_linea->>'color_x_cliente_id')::INT,
                    tenido_id          = (v_linea->>'tenido_id')::INT,
                    flg_doble_bolsa    = COALESCE((v_linea->>'flg_doble_bolsa')::BOOLEAN, false)
                WHERE id = (v_linea->>'id')::BIGINT;
            ELSE
                INSERT INTO doc.orden_servicio_detalle (
                    orden_servicio_id, linea, item_id, malla,
                    cantidad, color_x_cliente_id, tenido_id, flg_doble_bolsa
                ) VALUES (
                    p_os_id,
                    COALESCE((v_linea->>'linea')::SMALLINT, 1),
                    (v_linea->>'item_id')::INT,
                    v_linea->>'malla',
                    (v_linea->>'cantidad')::INT,
                    (v_linea->>'color_x_cliente_id')::INT,
                    (v_linea->>'tenido_id')::INT,
                    COALESCE((v_linea->>'flg_doble_bolsa')::BOOLEAN, false)
                );
            END IF;
        END LOOP;
    END IF;

    RETURN format('Orden de servicio %s actualizada.', p_os_id);
EXCEPTION
    WHEN OTHERS THEN
        RAISE LOG 'Error in actualizar_orden_servicio - User: %, os: %, Error: %',
                  v_usr_id, p_os_id, SQLERRM;
        RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.actualizar_orden_servicio(BIGINT, jsonb) TO authenticated;




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

GRANT EXECUTE ON FUNCTION mes.crear_partida(jsonb)                            TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_partida(int, jsonb)                  TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_pasos_partida(bigint, jsonb)         TO authenticated;
GRANT EXECUTE ON FUNCTION mes.actualizar_componentes_partida(bigint, jsonb)   TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- doc.get_orden_servicio — single order detail
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc.get_orden_servicio(p_os_id BIGINT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc', 'inventario'
AS $$
SELECT jsonb_build_object(
    'id',               os.id,
    'tercero_id',       os.tercero_id,
    'tercero_nombre',   t.nombre,
    'tercero_ruc',      t.ruc,
    'serie',            os.serie,
    'correlativo',      os.correlativo,
    'fecha_emision',    os.fecha_emision,
    'fecha_entrega',    os.fecha_entrega,
    'rendimiento',      os.rendimiento,
    'ancho',            os.ancho,
    'flg_antipilling',  os.flg_antipilling,
    'flg_urgente',      os.flg_urgente,
    'observacion',      os.observacion,
    'factura',          os.factura,
    'fyh_cre',          os.fyh_cre,
    'lineas', (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id',                   osd.id,
                'linea',                osd.linea,
                'articulo_id',          ird.articulo_id,
                'articulo_nombre',      a.nombre,
                'malla',                osd.malla,
                'cantidad',             osd.cantidad,
                'cantidad_recibida',    osd.cantidad_recibida,
                'color_x_cliente_id',   osd.color_x_cliente_id,
                'color',                vc.color,
                'tono',                 vc.tono,
                'color_hex',            vc.color_x_cliente_hex,
                'tenido_id',            osd.tenido_id,
                'tenido',               ten.tenido,
                'flg_doble_bolsa',      osd.flg_doble_bolsa
            ) ORDER BY osd.linea
        ), '[]'::jsonb)
        FROM doc.orden_servicio_detalle osd
        LEFT JOIN item_rollo_detalle ird ON ird.item_id = osd.item_id
        LEFT JOIN articulo          a   ON a.id   = ird.articulo_id
        LEFT JOIN vw_colores        vc  ON vc.color_x_cliente_id = osd.color_x_cliente_id
        LEFT JOIN tenido            ten ON ten.id  = osd.tenido_id
        WHERE osd.orden_servicio_id = os.id
    ),
    'rollos', (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'lote_id',          l.id,
                'codigo',           EXTRACT(YEAR FROM l.fyh_cre)::int % 100
                                    || '-' || LPAD(l.secuencia::text, 5, '0'),
                'cantidad',         l.cantidad,
                'flg_pesado',       EXISTS (
                                        SELECT 1 FROM inventario.pesaje p
                                        WHERE p.lote_id = l.id
                                    ),
                'item_id',          l.item_id,
                'detalle_id',       im.documento_linea_id,
                'factura_hilo',     lrd.factura_hilo
            ) ORDER BY l.id
        ), '[]'::jsonb)
        FROM inventario.lote_rollo_detalle lrd
        JOIN inventario.lote l ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
        JOIN inventario.item_movimientos im
            ON im.lote_id          = l.id
           AND im.documento_tipo   = 'orden_servicio'
           AND im.documento_id     = os.id
        WHERE lrd.orden_servicio_id = os.id
    )
)
FROM doc.orden_servicio os
LEFT JOIN tercero t ON t.id = os.tercero_id
WHERE os.id = p_os_id
  AND os.flg_elm = false;
$$;

GRANT EXECUTE ON FUNCTION doc.get_orden_servicio(BIGINT) TO authenticated;

-- Writes go through the functions (crear / ingresar / revertir / actualizar);
-- only SELECT is exposed on the tables so the frontend cannot bypass the gates.
GRANT SELECT ON doc.orden_servicio         TO authenticated;
GRANT SELECT ON doc.orden_servicio_detalle TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON doc.orden_servicio         FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON doc.orden_servicio_detalle FROM authenticated;



-- SELECT
--     osd.id          AS detalle_id,
--     osd.linea,
--     osd.cantidad    AS rollos_esperados,
--     i.nombre        AS item,
--     COUNT(DISTINCT l.id) AS lotes_existentes
-- FROM doc.orden_servicio_detalle osd
-- JOIN item i ON i.id = osd.item_id
-- LEFT JOIN inventario.item_movimientos im
--     ON im.documento_tipo     = 'orden_servicio'
--    AND im.documento_id       = osd.orden_servicio_id
--    AND im.documento_linea_id = osd.id
-- LEFT JOIN inventario.lote l
--     ON l.id = im.lote_id AND l.fyh_elm IS NULL
-- WHERE osd.orden_servicio_id = 2
-- GROUP BY osd.id, osd.linea, osd.cantidad, i.nombre
-- ORDER BY osd.linea;

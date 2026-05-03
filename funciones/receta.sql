-- ═══════════════════════════════════════════════════════════════
-- receta SCHEMA — lifecycle functions
--
-- Dyeing recipes (receta.tenido):
--   receta.crear_tenido              → create a new dyeing recipe (EN_DESARROLLO)
--   receta.transicionar_tenido       → state transitions with atomic HISTORICO swap on approval
--   receta.actualizar_tenido         → update header + replace pasos (EN_DESARROLLO / RE_LAB only)
--   receta.get_tenido                → full detail as JSONB (header + pasos + insumos)
--   receta.resolver_tenido_id        → resolve approved recipe ID for a (partida, tipo_receta)
--   receta.get_tenido_para_partida   → resolve + return full detail for a partida
--   receta.vw_tenido                 → all recipes enriched with display names (frontend filters by tab)
--
-- Machine wash recipes (receta.lavado_maquina):
--   receta.crear_lavado_maquina      → create new inactive wash recipe, optionally with pasos
--   receta.activar_lavado_maquina    → activate, atomically deactivating the current active one
--   receta.desactivar_lavado_maquina → deactivate without deleting
--   receta.actualizar_lavado_maquina → replace pasos (guarded: blocked if COMPLETADO executions)
--   receta.get_lavado_maquina        → full detail as JSONB (header + pasos + insumos)
-- ═══════════════════════════════════════════════════════════════


-- ───────────────────────────────────────
-- crear_tenido
-- Creates a new dyeing recipe in EN_DESARROLLO state.
-- Returns the new receta.tenido.id.
-- Steps and insumos are added separately via direct INSERT into
-- receta.tenido_paso / receta.tenido_paso_insumo (guarded by estado check).
-- ───────────────────────────────────────

-- p_data keys: color_x_cliente_id, articulo_tipo_id, fibra, tenido_id,
--              flg_antipilling (default false), tipo_receta_id (optional)
CREATE OR REPLACE FUNCTION receta.crear_tenido(p_data JSONB)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_id        INT;
    v_estado_id SMALLINT;
    v_usr_id    INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT id INTO v_estado_id FROM estado_desarrollo_color WHERE codigo = 'EN_DESARROLLO';

    INSERT INTO receta.tenido (
        color_x_cliente_id,
        articulo_tipo_id,
        fibra,
        tenido_id,
        flg_antipilling,
        tipo_receta_id,
        estado_id,
        usr_cre,
        fyh_cre
    ) VALUES (
        (p_data->>'color_x_cliente_id')::INT,
        (p_data->>'articulo_tipo_id')::SMALLINT,
        (p_data->>'fibra')::SMALLINT,
        (p_data->>'tenido_id')::INT,
        COALESCE((p_data->>'flg_antipilling')::BOOLEAN, false),
        (p_data->>'tipo_receta_id')::SMALLINT,
        v_estado_id,
        v_usr_id,
        now()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;$$;


-- ───────────────────────────────────────
-- transicionar_tenido
-- Transitions a recipe to a new state.
--
-- On APROBADO: atomically moves any existing approved recipe for the
-- same spec (color × articulo × tenido × antipilling) to HISTORICO
-- before approving this one. The partial unique index then allows
-- the new APROBADO to be committed cleanly.
--
-- p_estado_id: FK to public.estado_desarrollo_color.id
--   (frontend fetches the list and passes the id — no hardcoded codes on the client)
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.transicionar_tenido(
    p_receta_id INT,
    p_estado_id SMALLINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_receta       receta.tenido%ROWTYPE;
    v_aprobado_id  SMALLINT;
    v_historico_id SMALLINT;
    v_usr_id       INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Lock and fetch current recipe
    SELECT * INTO v_receta FROM receta.tenido WHERE id = p_receta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receta ID % no encontrada.', p_receta_id;
    END IF;

    -- Validate target state exists
    IF NOT EXISTS (SELECT 1 FROM estado_desarrollo_color WHERE id = p_estado_id) THEN
        RAISE EXCEPTION 'estado_id % no válido.', p_estado_id;
    END IF;

    -- Guard: already in target state — no-op
    IF v_receta.estado_id = p_estado_id THEN
        RETURN;
    END IF;

    -- Enforce allowed transitions (backend is authoritative — frontend may hide buttons
    -- as UX but cannot be the only enforcement).
    IF NOT EXISTS (
        SELECT 1
        FROM (VALUES
            ('INGRESADO',       'EN_DESARROLLO'),
            ('EN_DESARROLLO',   'ENVIADO_CLIENTE'),
            ('EN_DESARROLLO',   'RECHAZADO'),
            ('EN_DESARROLLO',   'CANCELADO'),
            ('ENVIADO_CLIENTE', 'APROBADO'),
            ('ENVIADO_CLIENTE', 'RECHAZADO'),
            ('ENVIADO_CLIENTE', 'RE_LAB'),
            ('RE_LAB',          'ENVIADO_CLIENTE'),
            ('RE_LAB',          'RECHAZADO'),
            ('RE_LAB',          'CANCELADO')
        ) AS allowed(desde, hasta)
        JOIN estado_desarrollo_color e_desde ON e_desde.codigo = allowed.desde AND e_desde.id = v_receta.estado_id
        JOIN estado_desarrollo_color e_hasta ON e_hasta.codigo = allowed.hasta AND e_hasta.id = p_estado_id
    ) THEN
        RAISE EXCEPTION 'Transición no permitida para receta %.', p_receta_id;
    END IF;

    SELECT id INTO v_aprobado_id  FROM estado_desarrollo_color WHERE codigo = 'APROBADO';
    SELECT id INTO v_historico_id FROM estado_desarrollo_color WHERE codigo = 'HISTORICO';

    -- Block leaving APROBADO to any state other than HISTORICO if production pasos exist.
    -- Those pasos hold a FK to this recipe — reverting it would corrupt traceability.
    -- Correct action: create a new version via crear_tenido.
    IF v_receta.flg_produccion = true AND p_estado_id != v_historico_id THEN
        IF EXISTS (SELECT 1 FROM mes.partida_paso WHERE receta_id = p_receta_id) THEN
            RAISE EXCEPTION
                'Receta % está asignada a pasos de producción — crear una nueva versión en lugar de revertir.',
                p_receta_id;
        END IF;
    END IF;

    -- On approval: supersede any existing approved recipe for the same spec.
    -- flg_produccion = true identifies the current APROBADO (trigger-maintained).
    IF p_estado_id = v_aprobado_id THEN
        UPDATE receta.tenido
        SET estado_id = v_historico_id,
            usr_mod   = v_usr_id,
            fyh_mod   = now()
        WHERE color_x_cliente_id = v_receta.color_x_cliente_id
          AND articulo_tipo_id   = v_receta.articulo_tipo_id
          AND fibra              = v_receta.fibra
          AND tenido_id          = v_receta.tenido_id
          AND flg_antipilling    = v_receta.flg_antipilling
          AND flg_produccion     = true   -- trigger-maintained: true only when APROBADO
          AND id                <> p_receta_id;
    END IF;

    -- Apply transition (trigger updates flg_produccion automatically)
    UPDATE receta.tenido
    SET estado_id      = p_estado_id,
        fyh_produccion = CASE WHEN p_estado_id = v_aprobado_id THEN now() ELSE fyh_produccion END,
        usr_mod        = v_usr_id,
        fyh_mod        = now()
    WHERE id = p_receta_id;
END;$$;


-- ───────────────────────────────────────
-- get_tenido
-- Returns the full recipe as JSONB: header + ordered pasos + insumos per paso.
-- Returns NULL if p_receta_id does not exist.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.get_tenido(p_receta_id INT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
    SELECT jsonb_build_object(
        'id',                 t.id,
        'color_x_cliente_id', t.color_x_cliente_id,
        'color_nombre',       vc.color,
        'color_hex',          vc.color_x_cliente_hex,
        'articulo_tipo_id',   t.articulo_tipo_id,
        'articulo_nombre',    at.nombre,
        'fibra',              t.fibra,
        'tenido_id',          t.tenido_id,
        'tenido_nombre',      td.tenido,
        'flg_antipilling',    t.flg_antipilling,
        'tipo_receta_id',     t.tipo_receta_id,
        'tipo_receta_nombre', tr.tipo_receta,
        'estado_id',          t.estado_id,
        'estado_codigo',      e.codigo,
        'estado_nombre',      e.nombre,
        'flg_produccion',     t.flg_produccion,
        'fyh_produccion',     t.fyh_produccion,
        'fyh_cre',            t.fyh_cre,
        'pasos', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id',              tp.id,
                    'operacion_id',    tp.operacion_id,
                    'operacion_codigo',op.codigo,
                    'operacion_nombre',op.nombre,
                    'orden',           tp.orden,
                    'ph',              tp.ph,
                    'temperatura',     tp.temperatura,
                    'tiempo_min',      tp.tiempo_min,
                    'nota',            tp.nota,
                    'insumos', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',          tpi.id,
                                'item_id',     tpi.item_id,
                                'item_codigo', i.codigo,
                                'item_nombre', i.nombre,
                                'cantidad',    tpi.cantidad,
                                'orden',       tpi.orden
                            ) ORDER BY tpi.orden
                        )
                        FROM receta.tenido_paso_insumo tpi
                        JOIN public.item i ON i.id = tpi.item_id
                        WHERE tpi.paso_id = tp.id
                    ), '[]'::jsonb)
                ) ORDER BY tp.orden
            )
            FROM receta.tenido_paso tp
            JOIN receta.operacion op ON op.id = tp.operacion_id
            WHERE tp.receta_id = t.id
        ), '[]'::jsonb)
    )
    FROM receta.tenido t
    JOIN  estado_desarrollo_color e  ON e.id  = t.estado_id
    LEFT JOIN vw_colores          vc ON vc.color_x_cliente_id = t.color_x_cliente_id
    LEFT JOIN articulo_tipo        at ON at.id = t.articulo_tipo_id
    LEFT JOIN public.tenido        td ON td.id = t.tenido_id
    LEFT JOIN tipo_receta          tr ON tr.id = t.tipo_receta_id
    WHERE t.id = p_receta_id;
$$;


-- ───────────────────────────────────────
-- actualizar_tenido
-- Updates header fields and optionally replaces all pasos + insumos.
-- Guard: only allowed in EN_DESARROLLO or RE_LAB states.
-- Pass p_pasos => NULL to leave pasos unchanged.
-- Pasos JSONB format: [{operacion_id, orden, ph?, temperatura?, tiempo_min?, nota?,
--                       insumos: [{item_id, cantidad, orden}]}]
-- ───────────────────────────────────────

-- p_data keys (all optional except receta_id):
--   color_x_cliente_id, articulo_tipo_id, fibra, tenido_id,
--   flg_antipilling, tipo_receta_id, pasos (array — replaces all if present)
CREATE OR REPLACE FUNCTION receta.actualizar_tenido(p_receta_id INT, p_data JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_receta receta.tenido%ROWTYPE;
    v_usr_id INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_receta FROM receta.tenido WHERE id = p_receta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receta ID % no encontrada.', p_receta_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM estado_desarrollo_color
        WHERE id = v_receta.estado_id AND codigo IN ('EN_DESARROLLO', 'RE_LAB')
    ) THEN
        RAISE EXCEPTION 'Receta ID % no es editable en su estado actual.', p_receta_id;
    END IF;

    UPDATE receta.tenido SET
        color_x_cliente_id = COALESCE((p_data->>'color_x_cliente_id')::INT,     color_x_cliente_id),
        articulo_tipo_id   = COALESCE((p_data->>'articulo_tipo_id')::SMALLINT,   articulo_tipo_id),
        fibra              = COALESCE((p_data->>'fibra')::SMALLINT,              fibra),
        tenido_id          = COALESCE((p_data->>'tenido_id')::INT,               tenido_id),
        flg_antipilling    = COALESCE((p_data->>'flg_antipilling')::BOOLEAN,     flg_antipilling),
        tipo_receta_id     = COALESCE((p_data->>'tipo_receta_id')::SMALLINT,     tipo_receta_id),
        usr_mod            = v_usr_id,
        fyh_mod            = now()
    WHERE id = p_receta_id;

    IF p_data ? 'pasos' THEN
        DELETE FROM receta.tenido_paso WHERE receta_id = p_receta_id;

        WITH paso_ins AS (
            INSERT INTO receta.tenido_paso (receta_id, operacion_id, orden, ph, temperatura, tiempo_min, nota)
            SELECT
                p_receta_id,
                (p->>'operacion_id')::SMALLINT,
                (p->>'orden')::SMALLINT,
                (p->>'ph')::NUMERIC,
                (p->>'temperatura')::NUMERIC,
                (p->>'tiempo_min')::SMALLINT,
                p->>'nota'
            FROM jsonb_array_elements(p_data->'pasos') p
            RETURNING id, orden
        )
        INSERT INTO receta.tenido_paso_insumo (paso_id, item_id, cantidad, orden)
        SELECT
            pi.id,
            (i->>'item_id')::INT,
            (i->>'cantidad')::NUMERIC,
            (i->>'orden')::SMALLINT
        FROM paso_ins pi
        JOIN jsonb_array_elements(p_data->'pasos') p ON (p->>'orden')::SMALLINT = pi.orden
        CROSS JOIN jsonb_array_elements(COALESCE(p->'insumos', '[]')) i;
    END IF;
END;$$;


-- ───────────────────────────────────────
-- crear_lavado_maquina
-- Creates a new inactive machine wash recipe.
-- Returns the new receta.lavado_maquina.id.
-- Pasos and insumos may be supplied immediately via p_pasos or added later.
-- ───────────────────────────────────────

-- p_data keys: tipo_lavado_mq_id, valor_origen_id, valor_destino_id,
--              pasos (optional array — same format as actualizar_lavado_maquina)
CREATE OR REPLACE FUNCTION receta.crear_lavado_maquina(p_data JSONB)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_id     INT;
    v_usr_id INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO receta.lavado_maquina (
        tipo_lavado_mq_id, valor_origen_id, valor_destino_id,
        flg_activo, usr_cre, fyh_cre
    ) VALUES (
        (p_data->>'tipo_lavado_mq_id')::SMALLINT,
        (p_data->>'valor_origen_id')::SMALLINT,
        (p_data->>'valor_destino_id')::SMALLINT,
        false, v_usr_id, now()
    )
    RETURNING id INTO v_id;

    IF p_data ? 'pasos' THEN
        WITH paso_ins AS (
            INSERT INTO receta.lavado_maquina_paso (receta_id, operacion_id, orden, ph, temperatura, tiempo_min, nota)
            SELECT
                v_id,
                (p->>'operacion_id')::SMALLINT,
                (p->>'orden')::SMALLINT,
                (p->>'ph')::NUMERIC,
                (p->>'temperatura')::NUMERIC,
                (p->>'tiempo_min')::SMALLINT,
                p->>'nota'
            FROM jsonb_array_elements(p_data->'pasos') p
            RETURNING id, orden
        )
        INSERT INTO receta.lavado_maquina_paso_insumo (paso_id, item_id, cantidad, orden)
        SELECT
            pi.id,
            (i->>'item_id')::INT,
            (i->>'cantidad')::NUMERIC,
            (i->>'orden')::SMALLINT
        FROM paso_ins pi
        JOIN jsonb_array_elements(p_data->'pasos') p ON (p->>'orden')::SMALLINT = pi.orden
        CROSS JOIN jsonb_array_elements(COALESCE(p->'insumos', '[]')) i;
    END IF;

    RETURN v_id;
END;$$;


-- ───────────────────────────────────────
-- activar_lavado_maquina
-- Activates a recipe, atomically deactivating the current active one for the
-- same (tipo_lavado_mq_id, valor_origen_id, valor_destino_id) transition.
-- Safe even when the outgoing recipe has COMPLETADO executions — the trigger
-- only guards definition columns, not flg_activo.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.activar_lavado_maquina(p_receta_id INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_receta receta.lavado_maquina%ROWTYPE;
    v_usr_id INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_receta FROM receta.lavado_maquina WHERE id = p_receta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'receta.lavado_maquina id=% no encontrada.', p_receta_id;
    END IF;

    IF v_receta.flg_activo THEN
        RETURN;  -- already active, no-op
    END IF;

    UPDATE receta.lavado_maquina
    SET flg_activo = false, usr_mod = v_usr_id, fyh_mod = now()
    WHERE tipo_lavado_mq_id = v_receta.tipo_lavado_mq_id
      AND valor_origen_id   = v_receta.valor_origen_id
      AND valor_destino_id  = v_receta.valor_destino_id
      AND flg_activo        = true
      AND id               <> p_receta_id;

    UPDATE receta.lavado_maquina
    SET flg_activo = true, usr_mod = v_usr_id, fyh_mod = now()
    WHERE id = p_receta_id;
END;$$;


-- ───────────────────────────────────────
-- desactivar_lavado_maquina
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.desactivar_lavado_maquina(p_receta_id INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_usr_id INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM receta.lavado_maquina WHERE id = p_receta_id) THEN
        RAISE EXCEPTION 'receta.lavado_maquina id=% no encontrada.', p_receta_id;
    END IF;

    UPDATE receta.lavado_maquina
    SET flg_activo = false, usr_mod = v_usr_id, fyh_mod = now()
    WHERE id = p_receta_id;
END;$$;


-- ───────────────────────────────────────
-- actualizar_lavado_maquina
-- Replaces all pasos + insumos for an unexecuted recipe.
-- Guard: blocked if any mes.lavado_maquina execution reached COMPLETADO.
-- (The header's definition columns are further guarded by trg_bu_lavado_maquina_immutable.)
-- Pasos JSONB format: [{operacion_id, orden, ph?, temperatura?, tiempo_min?, nota?,
--                       insumos: [{item_id, cantidad, orden}]}]
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.actualizar_lavado_maquina(
    p_receta_id INT,
    p_pasos     JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_usr_id INT := get_user_id();
BEGIN
    IF NOT jwt_has_permission('configuracion.admin') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere configuracion.admin'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM receta.lavado_maquina WHERE id = p_receta_id) THEN
        RAISE EXCEPTION 'receta.lavado_maquina id=% no encontrada.', p_receta_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mes.lavado_maquina
        WHERE receta_id = p_receta_id AND estado = 'COMPLETADO'
    ) THEN
        RAISE EXCEPTION 'receta.lavado_maquina id=% no es editable: tiene ejecuciones completadas.', p_receta_id;
    END IF;

    DELETE FROM receta.lavado_maquina_paso WHERE receta_id = p_receta_id;

    WITH paso_ins AS (
        INSERT INTO receta.lavado_maquina_paso (receta_id, operacion_id, orden, ph, temperatura, tiempo_min, nota)
        SELECT
            p_receta_id,
            (p->>'operacion_id')::SMALLINT,
            (p->>'orden')::SMALLINT,
            (p->>'ph')::NUMERIC,
            (p->>'temperatura')::NUMERIC,
            (p->>'tiempo_min')::SMALLINT,
            p->>'nota'
        FROM jsonb_array_elements(p_pasos) p
        RETURNING id, orden
    )
    INSERT INTO receta.lavado_maquina_paso_insumo (paso_id, item_id, cantidad, orden)
    SELECT
        pi.id,
        (i->>'item_id')::INT,
        (i->>'cantidad')::NUMERIC,
        (i->>'orden')::SMALLINT
    FROM paso_ins pi
    JOIN jsonb_array_elements(p_pasos) p ON (p->>'orden')::SMALLINT = pi.orden
    CROSS JOIN jsonb_array_elements(COALESCE(p->'insumos', '[]')) i;

    UPDATE receta.lavado_maquina
    SET usr_mod = v_usr_id, fyh_mod = now()
    WHERE id = p_receta_id;
END;$$;


-- ───────────────────────────────────────
-- get_lavado_maquina
-- Returns the full recipe as JSONB: header + ordered pasos + insumos per paso.
-- Returns NULL if p_receta_id does not exist.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.get_lavado_maquina(p_receta_id INT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
    SELECT jsonb_build_object(
        'id',               r.id,
        'tipo_lavado_mq_id',r.tipo_lavado_mq_id,
        'valor_origen_id',  r.valor_origen_id,
        'valor_destino_id', r.valor_destino_id,
        'flg_activo',       r.flg_activo,
        'pasos', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id',              p.id,
                    'operacion_id',    p.operacion_id,
                    'operacion_codigo',op.codigo,
                    'operacion_nombre',op.nombre,
                    'orden',           p.orden,
                    'ph',              p.ph,
                    'temperatura',     p.temperatura,
                    'tiempo_min',      p.tiempo_min,
                    'nota',            p.nota,
                    'insumos', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',          pi.id,
                                'item_id',     pi.item_id,
                                'item_codigo', i.codigo,
                                'item_nombre', i.nombre,
                                'cantidad',    pi.cantidad,
                                'orden',       pi.orden
                            ) ORDER BY pi.orden
                        )
                        FROM receta.lavado_maquina_paso_insumo pi
                        JOIN public.item i ON i.id = pi.item_id
                        WHERE pi.paso_id = p.id
                    ), '[]'::jsonb)
                ) ORDER BY p.orden
            )
            FROM receta.lavado_maquina_paso p
            JOIN receta.operacion op ON op.id = p.operacion_id
            WHERE p.receta_id = r.id
        ), '[]'::jsonb)
    )
    FROM receta.lavado_maquina r
    WHERE r.id = p_receta_id;
$$;


-- ───────────────────────────────────────
-- resolver_tenido_id
-- Resolves the approved receta.tenido for a (partida, tipo_receta) pair.
--
-- 4 keys come from mes.partida directly:
--   color_x_cliente_id, tenido_id
-- 2 keys come from mes.partida_detalle → item_rollo_detalle → articulo:
--   articulo_tipo_id, fibra
-- flg_antipilling is context-sensitive:
--   NORMAL tipo_receta  → use partida.flg_antipilling
--   REpartida tipo_receta → force false (antipilling is applied only on first dyeing)
--   p_tipo_receta_id NULL → use partida.flg_antipilling as-is (safe for existence checks)
--
-- Returns NULL when no approved recipe exists yet for the combination.
-- Raises if partida items resolve to more than one articulo_tipo/fibra (invariant
-- violation — a dyeing order must be single-fabric).
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.resolver_tenido_id(
    p_partida_id     BIGINT,
    p_tipo_receta_id SMALLINT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta', 'doc'
AS $$
DECLARE
    v_receta_id    INT;
    v_combos       INT;
    v_flg_antipill BOOLEAN;
    v_op_tipo      partida_tipo_enum;
BEGIN
    -- Guard: all items in a dyeing partida must share one articulo_tipo + fibra
    SELECT COUNT(DISTINCT (a.articulo_tipo_id, a.fibra)) INTO v_combos
    FROM mes.partida_detalle pd
    JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    JOIN articulo a ON a.id = ird.articulo_id
    WHERE pd.partida_id = p_partida_id;

    IF v_combos > 1 THEN
        RAISE EXCEPTION
            'Partida % tiene múltiples combinaciones articulo_tipo/fibra — no se puede resolver la receta de forma unívoca.',
            p_partida_id;
    END IF;

    SELECT flg_antipilling INTO v_flg_antipill FROM mes.partida WHERE id = p_partida_id;

    -- REpartida: antipilling already applied on first dyeing — always match false
    IF p_tipo_receta_id IS NOT NULL THEN
        SELECT partida_tipo INTO v_op_tipo FROM tipo_receta WHERE id = p_tipo_receta_id;
        IF v_op_tipo = 'REpartida' THEN
            v_flg_antipill := false;
        END IF;
    END IF;

    SELECT rt.id INTO v_receta_id
    FROM mes.partida p
    JOIN mes.partida_detalle pd ON pd.partida_id = p.id
    JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    JOIN articulo a ON a.id = ird.articulo_id
    JOIN receta.tenido rt
        ON  rt.color_x_cliente_id = p.color_x_cliente_id
        AND rt.tenido_id          = p.tenido_id
        AND rt.flg_antipilling    = v_flg_antipill
        AND rt.articulo_tipo_id   = a.articulo_tipo_id
        AND rt.fibra              = a.fibra
        AND rt.flg_produccion     = true   -- unique partial index: at most one row
    WHERE p.id = p_partida_id
    LIMIT 1;

    RETURN v_receta_id;
END;$$;


-- ───────────────────────────────────────
-- get_tenido_para_partida
-- Convenience wrapper: resolves the approved recipe for a (partida, tipo_receta)
-- and returns its full detail (same shape as get_tenido).
-- Returns NULL if no approved recipe exists yet.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.get_tenido_para_partida(
    p_partida_id     BIGINT,
    p_tipo_receta_id SMALLINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta', 'doc'
AS $$
    SELECT receta.get_tenido(receta.resolver_tenido_id(p_partida_id, p_tipo_receta_id));
$$;


-- ───────────────────────────────────────
-- solicitar_si_ausente
-- Called from mes.crear_partida after partida_detalle is inserted.
-- Creates a receta.tenido in INGRESADO state if no live recipe exists for
-- the partida's spec (color × articulo_tipo × fibra × tenido × antipilling).
-- Returns the new receta.tenido.id, or NULL if skipped.
-- Skipped when: item combo is ambiguous, no items yet, or a live recipe
-- (any state except HISTORICO / CANCELADO / RECHAZADO) already exists.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.solicitar_si_ausente(p_partida_id BIGINT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta', 'doc'
AS $$
DECLARE
    v_receta_id INT;
    v_combos    INT;
    v_estado_id SMALLINT;
    v_usr_id    INT := get_user_id();
    v_key       RECORD;
BEGIN
    -- Only proceed if all detalle items resolve to exactly one articulo_tipo + fibra
    SELECT COUNT(DISTINCT (a.articulo_tipo_id, a.fibra)) INTO v_combos
    FROM mes.partida_detalle pd
    JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    JOIN articulo a ON a.id = ird.articulo_id
    WHERE pd.partida_id = p_partida_id;

    IF COALESCE(v_combos, 0) != 1 THEN
        RETURN NULL;
    END IF;

    SELECT
        p.color_x_cliente_id,
        a.articulo_tipo_id,
        a.fibra,
        p.tenido_id,
        p.flg_antipilling
    INTO v_key
    FROM mes.partida p
    JOIN mes.partida_detalle pd ON pd.partida_id = p.id
    JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    JOIN articulo a ON a.id = ird.articulo_id
    WHERE p.id = p_partida_id
    LIMIT 1;

    -- Serialize concurrent calls for the same spec key to prevent duplicate INGRESADO rows.
    -- Advisory lock is transaction-scoped — auto-released on commit/rollback.
    PERFORM pg_advisory_xact_lock(
        hashtext('receta.solicitar_si_ausente'),
        hashtext(format('%s|%s|%s|%s|%s',
            v_key.color_x_cliente_id, v_key.articulo_tipo_id,
            v_key.fibra, v_key.tenido_id, v_key.flg_antipilling))
    );

    -- Skip if any live recipe already exists for this spec
    IF EXISTS (
        SELECT 1 FROM receta.tenido t
        JOIN estado_desarrollo_color e ON e.id = t.estado_id
        WHERE t.color_x_cliente_id = v_key.color_x_cliente_id
          AND t.articulo_tipo_id   = v_key.articulo_tipo_id
          AND t.fibra              = v_key.fibra
          AND t.tenido_id          = v_key.tenido_id
          AND t.flg_antipilling    = v_key.flg_antipilling
          AND e.codigo NOT IN ('HISTORICO', 'CANCELADO', 'RECHAZADO')
    ) THEN
        RETURN NULL;
    END IF;

    SELECT id INTO v_estado_id FROM estado_desarrollo_color WHERE codigo = 'INGRESADO';

    INSERT INTO receta.tenido (
        color_x_cliente_id, articulo_tipo_id, fibra, tenido_id,
        flg_antipilling, estado_id, usr_cre, fyh_cre
    ) VALUES (
        v_key.color_x_cliente_id, v_key.articulo_tipo_id, v_key.fibra, v_key.tenido_id,
        v_key.flg_antipilling, v_estado_id, v_usr_id, now()
    )
    RETURNING id INTO v_receta_id;

    RETURN v_receta_id;
END;$$;


-- ───────────────────────────────────────
-- vw_tenido
-- All recipes, all states — enriched with display names.
-- Frontend applies tab filters:
--   Pendientes: estado_codigo IN ('INGRESADO','EN_DESARROLLO','RE_LAB','ENVIADO_CLIENTE')
--   Historial:  no filter
-- ───────────────────────────────────────

CREATE OR REPLACE VIEW receta.vw_tenido AS
SELECT
    t.id,
    t.color_x_cliente_id,
    vc.color                  AS color_nombre,
    vc.color_x_cliente_hex    AS color_hex,
    t.articulo_tipo_id,
    at.nombre                 AS articulo_nombre,
    t.fibra,
    t.tenido_id,
    td.tenido                 AS tenido_nombre,
    t.flg_antipilling,
    t.tipo_receta_id,
    tr.tipo_receta            AS tipo_receta_nombre,
    t.estado_id,
    e.codigo                  AS estado_codigo,
    e.nombre                  AS estado_nombre,
    t.flg_produccion,
    t.fyh_produccion,
    t.fyh_cre,
    t.fyh_mod
FROM receta.tenido t
JOIN  public.estado_desarrollo_color e  ON e.id  = t.estado_id
LEFT JOIN public.vw_colores          vc ON vc.color_x_cliente_id = t.color_x_cliente_id
LEFT JOIN public.articulo_tipo        at ON at.id = t.articulo_tipo_id
LEFT JOIN public.tenido              td ON td.id = t.tenido_id
LEFT JOIN public.tipo_receta         tr ON tr.id = t.tipo_receta_id;


-- ───────────────────────────────────────
-- get_tenido_versiones
-- Returns all recipes that share the same spec
-- (color_x_cliente_id, articulo_tipo_id, fibra, tenido_id, flg_antipilling)
-- as the given recipe, ordered newest first.
-- Used to browse the version history and to populate a version picker for diff.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.get_tenido_versiones(p_receta_id INT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id',             v.id,
            'estado_codigo',  v.estado_codigo,
            'estado_nombre',  v.estado_nombre,
            'flg_produccion', v.flg_produccion,
            'fyh_cre',        v.fyh_cre,
            'fyh_produccion', v.fyh_produccion,
            'fyh_mod',        v.fyh_mod
        ) ORDER BY v.fyh_cre DESC
    ), '[]'::jsonb)
    FROM receta.vw_tenido v
    WHERE (v.color_x_cliente_id, v.articulo_tipo_id, v.fibra, v.tenido_id, v.flg_antipilling) = (
        SELECT t.color_x_cliente_id, t.articulo_tipo_id, t.fibra, t.tenido_id, t.flg_antipilling
        FROM receta.tenido t
        WHERE t.id = p_receta_id
    );
$$;


-- ───────────────────────────────────────
-- GRANTS
-- ───────────────────────────────────────

GRANT EXECUTE ON FUNCTION receta.crear_tenido                TO authenticated;
GRANT EXECUTE ON FUNCTION receta.transicionar_tenido(INT, SMALLINT) TO authenticated;
GRANT EXECUTE ON FUNCTION receta.actualizar_tenido           TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_tenido                  TO authenticated;
GRANT EXECUTE ON FUNCTION receta.crear_lavado_maquina(JSONB)  TO authenticated;
GRANT EXECUTE ON FUNCTION receta.activar_lavado_maquina      TO authenticated;
GRANT EXECUTE ON FUNCTION receta.desactivar_lavado_maquina   TO authenticated;
GRANT EXECUTE ON FUNCTION receta.actualizar_lavado_maquina   TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_lavado_maquina          TO authenticated;
GRANT EXECUTE ON FUNCTION receta.resolver_tenido_id          TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_tenido_para_partida     TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_tenido_versiones        TO authenticated;
-- solicitar_si_ausente: internal only — called from mes.crear_partida (SECURITY DEFINER).
-- No grant to authenticated; the owner context propagates through crear_partida.
GRANT SELECT  ON receta.vw_tenido                            TO authenticated;
GRANT SELECT  ON estado_desarrollo_color                     TO authenticated;

-- ───────────────────────────────────────
-- vw_lavado_maquina_lista
-- Machine-wash recipe list — enriched with display names.
-- ───────────────────────────────────────

CREATE OR REPLACE VIEW receta.vw_lavado_maquina_lista AS
SELECT
    lm.id,
    lm.tipo_lavado_mq_id,
    tlm.nombre   AS tipo_lavado_nombre,
    lm.valor_origen_id,
    vo.valor                  AS valor_origen_nombre,
    lm.valor_destino_id,
    vd.valor                  AS valor_destino_nombre,
    lm.flg_activo,
    lm.fyh_cre,
    lm.fyh_mod
FROM receta.lavado_maquina lm
LEFT JOIN public.tipo_lavado_maquina tlm ON tlm.id = lm.tipo_lavado_mq_id
LEFT JOIN public.valor               vo  ON vo.id  = lm.valor_origen_id
LEFT JOIN public.valor               vd  ON vd.id  = lm.valor_destino_id;

GRANT SELECT  ON receta.vw_lavado_maquina_lista              TO authenticated;




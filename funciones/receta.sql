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

CREATE OR REPLACE FUNCTION receta.crear_tenido(
    p_color_x_cliente_id INT,
    p_articulo_tipo_id   SMALLINT,
    p_fibra              SMALLINT,
    p_tenido_id          INT,
    p_flg_antipilling    BOOLEAN  DEFAULT false,
    p_tipo_receta_id     SMALLINT DEFAULT NULL
)
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
        p_color_x_cliente_id,
        p_articulo_tipo_id,
        p_fibra,
        p_tenido_id,
        p_flg_antipilling,
        p_tipo_receta_id,
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
-- p_estado_codigo: one of EN_DESARROLLO | ENVIADO_CLIENTE | APROBADO |
--                         RECHAZADO | CANCELADO | HISTORICO
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.transicionar_tenido(
    p_receta_id     INT,
    p_estado_codigo TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_receta           receta.tenido%ROWTYPE;
    v_nuevo_estado_id  SMALLINT;
    v_aprobado_id      SMALLINT;
    v_historico_id     SMALLINT;
    v_usr_id           INT := get_user_id();
BEGIN
    -- Lock and fetch current recipe
    SELECT * INTO v_receta FROM receta.tenido WHERE id = p_receta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receta ID % no encontrada.', p_receta_id;
    END IF;

    -- Resolve target state
    SELECT id INTO v_nuevo_estado_id FROM estado_desarrollo_color WHERE codigo = p_estado_codigo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Estado "%" no válido.', p_estado_codigo;
    END IF;

    -- Guard: already in target state — no-op
    IF v_receta.estado_id = v_nuevo_estado_id THEN
        RETURN;
    END IF;

    SELECT id INTO v_aprobado_id  FROM estado_desarrollo_color WHERE codigo = 'APROBADO';
    SELECT id INTO v_historico_id FROM estado_desarrollo_color WHERE codigo = 'HISTORICO';

    -- On approval: supersede any existing approved recipe for the same spec.
    -- flg_produccion = true identifies the current APROBADO (trigger-maintained).
    IF v_nuevo_estado_id = v_aprobado_id THEN
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
    SET estado_id      = v_nuevo_estado_id,
        fyh_produccion = CASE WHEN v_nuevo_estado_id = v_aprobado_id THEN now() ELSE fyh_produccion END,
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
        'articulo_tipo_id',   t.articulo_tipo_id,
        'fibra',              t.fibra,
        'tenido_id',          t.tenido_id,
        'flg_antipilling',    t.flg_antipilling,
        'tipo_receta_id',     t.tipo_receta_id,
        'estado_id',          t.estado_id,
        'estado_codigo',      e.codigo,
        'flg_produccion',     t.flg_produccion,
        'fyh_produccion',     t.fyh_produccion,
        'pasos', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id',          tp.id,
                    'operacion_id',tp.operacion_id,
                    'orden',       tp.orden,
                    'ph',          tp.ph,
                    'temperatura', tp.temperatura,
                    'tiempo_min',  tp.tiempo_min,
                    'nota',        tp.nota,
                    'insumos', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',       tpi.id,
                                'item_id',  tpi.item_id,
                                'cantidad', tpi.cantidad,
                                'orden',    tpi.orden
                            ) ORDER BY tpi.orden
                        )
                        FROM receta.tenido_paso_insumo tpi
                        WHERE tpi.paso_id = tp.id
                    ), '[]'::jsonb)
                ) ORDER BY tp.orden
            )
            FROM receta.tenido_paso tp
            WHERE tp.receta_id = t.id
        ), '[]'::jsonb)
    )
    FROM receta.tenido t
    JOIN estado_desarrollo_color e ON e.id = t.estado_id
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

CREATE OR REPLACE FUNCTION receta.actualizar_tenido(
    p_receta_id          INT,
    p_color_x_cliente_id INT      DEFAULT NULL,
    p_articulo_tipo_id   SMALLINT DEFAULT NULL,
    p_fibra              SMALLINT DEFAULT NULL,
    p_tenido_id          INT      DEFAULT NULL,
    p_flg_antipilling    BOOLEAN  DEFAULT NULL,
    p_tipo_receta_id     SMALLINT DEFAULT NULL,
    p_pasos              JSONB    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_receta  receta.tenido%ROWTYPE;
    v_usr_id  INT := get_user_id();
    v_paso    JSONB;
    v_insumo  JSONB;
    v_paso_id INT;
BEGIN
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
        color_x_cliente_id = COALESCE(p_color_x_cliente_id, color_x_cliente_id),
        articulo_tipo_id   = COALESCE(p_articulo_tipo_id,   articulo_tipo_id),
        fibra              = COALESCE(p_fibra,              fibra),
        tenido_id          = COALESCE(p_tenido_id,          tenido_id),
        flg_antipilling    = COALESCE(p_flg_antipilling,    flg_antipilling),
        tipo_receta_id     = COALESCE(p_tipo_receta_id,     tipo_receta_id),
        usr_mod            = v_usr_id,
        fyh_mod            = now()
    WHERE id = p_receta_id;

    IF p_pasos IS NOT NULL THEN
        DELETE FROM receta.tenido_paso WHERE receta_id = p_receta_id;

        FOR v_paso IN SELECT value FROM jsonb_array_elements(p_pasos)
        LOOP
            INSERT INTO receta.tenido_paso (receta_id, operacion_id, orden, ph, temperatura, tiempo_min, nota)
            VALUES (
                p_receta_id,
                (v_paso->>'operacion_id')::SMALLINT,
                (v_paso->>'orden')::SMALLINT,
                (v_paso->>'ph')::NUMERIC,
                (v_paso->>'temperatura')::NUMERIC,
                (v_paso->>'tiempo_min')::SMALLINT,
                v_paso->>'nota'
            )
            RETURNING id INTO v_paso_id;

            FOR v_insumo IN SELECT value FROM jsonb_array_elements(COALESCE(v_paso->'insumos', '[]'))
            LOOP
                INSERT INTO receta.tenido_paso_insumo (paso_id, item_id, cantidad, orden)
                VALUES (
                    v_paso_id,
                    (v_insumo->>'item_id')::INT,
                    (v_insumo->>'cantidad')::NUMERIC,
                    (v_insumo->>'orden')::SMALLINT
                );
            END LOOP;
        END LOOP;
    END IF;
END;$$;


-- ───────────────────────────────────────
-- crear_lavado_maquina
-- Creates a new inactive machine wash recipe.
-- Returns the new receta.lavado_maquina.id.
-- Pasos and insumos may be supplied immediately via p_pasos or added later.
-- ───────────────────────────────────────

CREATE OR REPLACE FUNCTION receta.crear_lavado_maquina(
    p_tipo_lavado_mq_id SMALLINT,
    p_valor_origen_id   SMALLINT,
    p_valor_destino_id  SMALLINT,
    p_pasos             JSONB DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'receta'
AS $$
DECLARE
    v_id      INT;
    v_usr_id  INT := get_user_id();
    v_paso    JSONB;
    v_insumo  JSONB;
    v_paso_id INT;
BEGIN
    INSERT INTO receta.lavado_maquina (
        tipo_lavado_mq_id, valor_origen_id, valor_destino_id,
        flg_activo, usr_cre, fyh_cre
    ) VALUES (
        p_tipo_lavado_mq_id, p_valor_origen_id, p_valor_destino_id,
        false, v_usr_id, now()
    )
    RETURNING id INTO v_id;

    IF p_pasos IS NOT NULL THEN
        FOR v_paso IN SELECT value FROM jsonb_array_elements(p_pasos)
        LOOP
            INSERT INTO receta.lavado_maquina_paso (receta_id, operacion_id, orden, ph, temperatura, tiempo_min, nota)
            VALUES (
                v_id,
                (v_paso->>'operacion_id')::SMALLINT,
                (v_paso->>'orden')::SMALLINT,
                (v_paso->>'ph')::NUMERIC,
                (v_paso->>'temperatura')::NUMERIC,
                (v_paso->>'tiempo_min')::SMALLINT,
                v_paso->>'nota'
            )
            RETURNING id INTO v_paso_id;

            FOR v_insumo IN SELECT value FROM jsonb_array_elements(COALESCE(v_paso->'insumos', '[]'))
            LOOP
                INSERT INTO receta.lavado_maquina_paso_insumo (paso_id, item_id, cantidad, orden)
                VALUES (
                    v_paso_id,
                    (v_insumo->>'item_id')::INT,
                    (v_insumo->>'cantidad')::NUMERIC,
                    (v_insumo->>'orden')::SMALLINT
                );
            END LOOP;
        END LOOP;
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
    v_usr_id  INT := get_user_id();
    v_paso    JSONB;
    v_insumo  JSONB;
    v_paso_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM receta.lavado_maquina WHERE id = p_receta_id) THEN
        RAISE EXCEPTION 'receta.lavado_maquina id=% no encontrada.', p_receta_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mes.lavado_maquina
        WHERE receta_id = p_receta_id AND estado = 'COMPLETADO'
    ) THEN
        RAISE EXCEPTION 'receta.lavado_maquina id=% no es editable: tiene ejecuciones completadas.', p_receta_id;
    END IF;

    -- Replace pasos (ON DELETE CASCADE removes insumos automatically)
    DELETE FROM receta.lavado_maquina_paso WHERE receta_id = p_receta_id;

    FOR v_paso IN SELECT value FROM jsonb_array_elements(p_pasos)
    LOOP
        INSERT INTO receta.lavado_maquina_paso (receta_id, operacion_id, orden, ph, temperatura, tiempo_min, nota)
        VALUES (
            p_receta_id,
            (v_paso->>'operacion_id')::SMALLINT,
            (v_paso->>'orden')::SMALLINT,
            (v_paso->>'ph')::NUMERIC,
            (v_paso->>'temperatura')::NUMERIC,
            (v_paso->>'tiempo_min')::SMALLINT,
            v_paso->>'nota'
        )
        RETURNING id INTO v_paso_id;

        FOR v_insumo IN SELECT value FROM jsonb_array_elements(COALESCE(v_paso->'insumos', '[]'))
        LOOP
            INSERT INTO receta.lavado_maquina_paso_insumo (paso_id, item_id, cantidad, orden)
            VALUES (
                v_paso_id,
                (v_insumo->>'item_id')::INT,
                (v_insumo->>'cantidad')::NUMERIC,
                (v_insumo->>'orden')::SMALLINT
            );
        END LOOP;
    END LOOP;

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
                    'id',          p.id,
                    'operacion_id',p.operacion_id,
                    'orden',       p.orden,
                    'ph',          p.ph,
                    'temperatura', p.temperatura,
                    'tiempo_min',  p.tiempo_min,
                    'nota',        p.nota,
                    'insumos', COALESCE((
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id',       pi.id,
                                'item_id',  pi.item_id,
                                'cantidad', pi.cantidad,
                                'orden',    pi.orden
                            ) ORDER BY pi.orden
                        )
                        FROM receta.lavado_maquina_paso_insumo pi
                        WHERE pi.paso_id = p.id
                    ), '[]'::jsonb)
                ) ORDER BY p.orden
            )
            FROM receta.lavado_maquina_paso p
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
-- 4 keys come from doc.partida directly:
--   color_x_cliente_id, tenido_id
-- 2 keys come from doc.partida_detalle → item_rollo_detalle → articulo:
--   articulo_tipo_id, fibra
-- flg_antipilling is context-sensitive:
--   NORMAL tipo_receta  → use partida.flg_antipilling
--   REPROCESO tipo_receta → force false (antipilling is applied only on first dyeing)
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
    v_op_tipo      orden_produccion_tipo_enum;
BEGIN
    -- Guard: all items in a dyeing partida must share one articulo_tipo + fibra
    SELECT COUNT(DISTINCT (a.articulo_tipo_id, a.fibra)) INTO v_combos
    FROM doc.partida_detalle pd
    JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    JOIN articulo a ON a.id = ird.articulo_id
    WHERE pd.partida_id = p_partida_id;

    IF v_combos > 1 THEN
        RAISE EXCEPTION
            'Partida % tiene múltiples combinaciones articulo_tipo/fibra — no se puede resolver la receta de forma unívoca.',
            p_partida_id;
    END IF;

    SELECT flg_antipilling INTO v_flg_antipill FROM doc.partida WHERE id = p_partida_id;

    -- REPROCESO: antipilling already applied on first dyeing — always match false
    IF p_tipo_receta_id IS NOT NULL THEN
        SELECT orden_produccion_tipo INTO v_op_tipo FROM tipo_receta WHERE id = p_tipo_receta_id;
        IF v_op_tipo = 'REPROCESO' THEN
            v_flg_antipill := false;
        END IF;
    END IF;

    SELECT rt.id INTO v_receta_id
    FROM doc.partida p
    JOIN doc.partida_detalle pd ON pd.partida_id = p.id
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
-- GRANTS
-- ───────────────────────────────────────

GRANT EXECUTE ON FUNCTION receta.crear_tenido                TO authenticated;
GRANT EXECUTE ON FUNCTION receta.transicionar_tenido         TO authenticated;
GRANT EXECUTE ON FUNCTION receta.actualizar_tenido           TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_tenido                  TO authenticated;
GRANT EXECUTE ON FUNCTION receta.crear_lavado_maquina        TO authenticated;
GRANT EXECUTE ON FUNCTION receta.activar_lavado_maquina      TO authenticated;
GRANT EXECUTE ON FUNCTION receta.desactivar_lavado_maquina   TO authenticated;
GRANT EXECUTE ON FUNCTION receta.actualizar_lavado_maquina   TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_lavado_maquina          TO authenticated;
GRANT EXECUTE ON FUNCTION receta.resolver_tenido_id          TO authenticated;
GRANT EXECUTE ON FUNCTION receta.get_tenido_para_partida     TO authenticated;
GRANT SELECT  ON estado_desarrollo_color                     TO authenticated;

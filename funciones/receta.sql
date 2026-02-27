-- ═══════════════════════════════════════════════════════════════
-- receta SCHEMA — lifecycle functions
--
-- Functions:
--   receta.crear_tenido          → create a new dyeing recipe (EN_DESARROLLO)
--   receta.transicionar_tenido   → state transitions with atomic HISTORICO swap on approval
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
    p_articulo_id        INT,
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
        articulo_id,
        tenido_id,
        flg_antipilling,
        tipo_receta_id,
        estado_id,
        usr_cre,
        fyh_cre
    ) VALUES (
        p_color_x_cliente_id,
        p_articulo_id,
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
          AND articulo_id        = v_receta.articulo_id
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
-- GRANTS
-- ───────────────────────────────────────

GRANT EXECUTE ON FUNCTION receta.crear_tenido      TO authenticated;
GRANT EXECUTE ON FUNCTION receta.transicionar_tenido TO authenticated;
GRANT SELECT  ON estado_desarrollo_color             TO authenticated;

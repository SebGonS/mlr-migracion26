-- ============================================================================
-- DISPATCH MODULE
-- ============================================================================
-- doc.vw_despacho_pendiente  — listing view: partidas with dyed stock pending dispatch
-- doc.get_despacho_partida   — detail function: pre-built payload for crear_entrega
-- doc.get_entrega      — getter: full entrega with items and linked lotes
-- doc.anular_entrega   — cancellation: reverses movements, marks entrega deleted
--
-- Flow:
--   1. Frontend queries vw_despacho_pendiente to list dispatchable partidas.
--   2. User selects a partida → frontend calls get_despacho_partida(partida_id).
--   3. Function returns pre-grouped entrega payloads (one per propietario group).
--   4. Frontend lets user filter/adjust lotes, add serie/correlativo/fecha_emision.
--   5. Frontend calls doc.crear_entrega once per entrega payload.
--
-- propietario split:
--   • propietario_id = 1 (MLR-owned rolls — MLR/* or OSWALDO/* clients) → VENTA_EGRESO
--   • propietario_id ≠ 1 (client-owned rolls)                          → DESPACHO_CLIENTE
--
-- Reversal tipo mapping (used by anular_entrega):
--   COMPRA_ING  → DEV_PROV_EGR
--   SERV_ING    → DEV_CLI_EGR
--   SERV_EGR    → SERV_DEV_ING
--   VENTA_EGR   → DEV_CLI_ING
-- Stock direction is derived from location fields: origen IS NOT NULL → debit, destino IS NOT NULL → credit.
-- ============================================================================


-- ── doc.vw_despacho_pendiente ─────────────────────────────────────────────
-- Partidas that have dyed roll lotes with available stock not yet dispatched.
-- Query-driven: a partida appears iff SUM(cantidad_disponible) > 0 on its dyed lotes.
-- Partial dispatch is handled naturally — remaining lotes keep the partida in view.
-- tiene_mixto = true means two entregas will be needed (MLR-owned + client-owned rolls).
-- ─────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS doc.vw_despacho_pendiente;
CREATE OR REPLACE VIEW doc.vw_despacho_pendiente AS
SELECT
    p.id                                                                            AS partida_id,
    p.numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT
        || '-' || LPAD(p.numero::TEXT, 4, '0')                                     AS codigo,
    p.estado_produccion AS estado,
    p.tercero_id,
    t.nombre                                                                        AS cliente,
    p.color_x_cliente_id,
    vc.color,
    vc.tono,
    p.fecha_acordada,
    COUNT(DISTINCT l.id)                                                            AS rolls_pendientes,
    ROUND(SUM(sa.cantidad_disponible)::NUMERIC, 2)                                  AS kg_pendientes,
    BOOL_OR(l.propietario_id = 1)                                                   AS tiene_rolls_mlr,
    BOOL_OR(l.propietario_id IS DISTINCT FROM 1)                                    AS tiene_rolls_cliente,
    (BOOL_OR(l.propietario_id = 1)
     AND BOOL_OR(l.propietario_id IS DISTINCT FROM 1))                              AS tiene_mixto
FROM mes.partida p
JOIN tercero t                      ON t.id                    = p.tercero_id
LEFT JOIN vw_colores vc             ON vc.color_x_cliente_id   = p.color_x_cliente_id
JOIN mes.partida_paso pp            ON pp.partida_id = p.id
JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                    AND pe.estado = 'COMPLETADO'   -- only completed steps produce output lotes
JOIN inventario.lote l
    ON  l.documento_tipo = 'partida_paso_ejecucion'
    AND l.documento_id   = pe.id
JOIN inventario.lote_rollo_detalle lrd
    ON  lrd.lote_id    = l.id
    AND lrd.flg_tenido = true           -- dyed rolls only
JOIN inventario.vw_stock_lotes sa  ON sa.lote_id = l.id
WHERE l.estado_calidad = 'APROBADO'
GROUP BY
    p.id, p.numero, p.estado_produccion, p.tercero_id, t.nombre,
    p.color_x_cliente_id, vc.color, vc.tono, p.fecha_acordada
HAVING SUM(sa.cantidad_disponible) > 0;

GRANT SELECT ON doc.vw_despacho_pendiente TO authenticated;


-- ── doc.get_despacho_partida ──────────────────────────────────────────────
-- Pre-builds the dispatch payload for one or more partidas (all must share
-- the same tercero_id). Groups rolls by ownership into DESPACHO_CLIENTE and
-- VENTA_EGRESO entries. Feeds doc.registrar_despacho (items[] — each item's
-- partida_id below maps directly); the older direct crear_entrega-per-entry
-- flow (frontend adds serie/correlativo/fecha_emision, calls crear_entrega
-- once per entry) still works unchanged.
--
-- Result shape:
-- {
--   "tercero_id": 7,
--   "cliente":    "Acme S.A.",
--   "partidas":   ["2026-0001", "2026-0003"],
--   "entregas": [
--     {
--       "entrega_tipo_id": 2, "entrega_tipo_codigo": "DESPACHO_CLIENTE", ...,
--       "rolls": 32, "kg_total": 480.60,
--       "items": [{ "item_id":44, "lote_id":901, "ubicacion_id":3, "cantidad":20.50, "propietario_id":7,
--                  "partida_id":123,
--                  "color_x_cliente_id":12, "color":"AZUL", "tono":"MARINO", "color_hex":"#001f5b",
--                  "ancho":"1.50", "articulo_id":3, "articulo_nombre":"RIB" }, ...]
--     }
--   ]
-- }
-- partida_id (added 2026-07-14): the producing partida (root or rework child)
-- for that roll — NOT part of the ownership GROUP BY, so it doesn't change
-- how items are pooled/grouped when multiple partidas are dispatched together.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_despacho_partida(p_partida_ids BIGINT[])
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'mes', 'inventario', 'public'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id     int := get_user_id();
    v_n_terceros int;
    v_tercero_id int;
    v_cliente    text;
    v_result     JSONB;
BEGIN
    IF NOT jwt_has_permission('comercial.ver') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.ver'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT COUNT(DISTINCT p.tercero_id)
    INTO   v_n_terceros
    FROM   mes.partida p
    WHERE  p.id = ANY(p_partida_ids);

    IF v_n_terceros = 0 THEN
        RAISE EXCEPTION 'No se encontraron las partidas indicadas';
    END IF;
    IF v_n_terceros > 1 THEN
        RAISE EXCEPTION 'Las partidas seleccionadas pertenecen a distintos clientes';
    END IF;

    SELECT p.tercero_id, t.nombre
    INTO   v_tercero_id, v_cliente
    FROM   mes.partida p
    JOIN   tercero t ON t.id = p.tercero_id
    WHERE  p.id = ANY(p_partida_ids)
    LIMIT  1;

    SELECT jsonb_build_object(
        'tercero_id', v_tercero_id,
        'cliente',    v_cliente,
        'partidas',   (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'partida_id',      id,
                    'partida_codigo',  EXTRACT(YEAR FROM fyh_cre)::TEXT || '-' || LPAD(numero::TEXT, 4, '0'),
                    'observacion',     observacion,
                    'flg_antipilling', flg_antipilling,
                    'flg_doble_bolsa', flg_doble_bolsa
                )
                ORDER BY fyh_cre
            )
            FROM mes.partida WHERE id = ANY(p_partida_ids)
        ),
        'entregas', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'entrega_tipo_id',     grt.id,
                    'entrega_tipo_codigo', grt.codigo,
                    'entrega_tipo_nombre', grt.nombre,
                    'tercero_id',          v_tercero_id,
                    'rolls',               lotes_agg.roll_count,
                    'kg_total',            ROUND(lotes_agg.kg_total::NUMERIC, 2),
                    'items',               lotes_agg.items
                )
                ORDER BY grt.codigo
            )
            FROM (
                SELECT
                    CASE WHEN l.propietario_id = 1
                         THEN 'VENTA_EGRESO'
                         ELSE 'DESPACHO_CLIENTE'
                    END                         AS tipo_codigo,
                    COUNT(*)                    AS roll_count,
                    SUM(sa.cantidad_disponible) AS kg_total,
                    jsonb_agg(
                        jsonb_build_object(
                            'item_id',              l.item_id,
                            'lote_id',              l.id,
                            'ubicacion_id',         sa.ubicacion_id,
                            -- Producing partida (root or rework child) — required by
                            -- doc.registrar_despacho's items[].partida_id (attributes the
                            -- charge). Not part of the GROUP BY below (grouping stays by
                            -- ownership only), so multi-partida dispatch is unaffected.
                            'partida_id',           pp.partida_id,
                            -- Raw, nullable — same convention as everywhere else in the app
                            -- (partida.partida_origen_id; NULL = this partida IS the root).
                            -- registrar_despacho bills/guards ownership against
                            -- COALESCE(partida_origen_id, id), never the rework child directly;
                            -- echoed here so the frontend can mirror that grouping BEFORE
                            -- submit (ownership-mix guard, cargo aggregation) instead of only
                            -- discovering a cross-sibling mix when the server rejects it.
                            'partida_origen_id',    prod_p.partida_origen_id,
                            -- Exact balance, not rounded: this value is echoed straight back
                            -- into crear_entrega as the requested cantidad, so rounding up
                            -- (e.g. 12.3467 → 12.35) would request more than is in stock and
                            -- trip the "Stock insuficiente" check on freshly-produced lots.
                            'cantidad',             sa.cantidad_disponible,
                            'propietario_id',       l.propietario_id,
                            'color_x_cliente_id',   lrd.color_x_cliente_id,
                            'color',                vc.color,
                            'tono',                 vc.tono,
                            'color_hex',            vc.color_x_cliente_hex,
                            'ancho',                lrd.ancho,
                            'articulo_id',          ird.articulo_id,
                            'articulo_nombre',      art.nombre,
                            'entrega_serie',        ent.serie,
                            'entrega_correlativo',  ent.correlativo
                        )
                        ORDER BY l.id
                    ) AS items
                FROM mes.partida_paso pp
                JOIN mes.partida_paso_ejecucion pe  ON pe.partida_paso_id = pp.id
                                                    AND pe.estado = 'COMPLETADO'
                JOIN inventario.lote l
                    ON  l.documento_tipo = 'partida_paso_ejecucion'
                    AND l.documento_id   = pe.id
                JOIN inventario.lote_rollo_detalle lrd
                    ON  lrd.lote_id    = l.id
                    AND lrd.flg_tenido = true
                LEFT JOIN vw_colores vc             ON vc.color_x_cliente_id = lrd.color_x_cliente_id
                LEFT JOIN item_rollo_detalle ird            ON ird.item_id   = l.item_id
                LEFT JOIN articulo art              ON art.id                = ird.articulo_id
                LEFT JOIN doc.entrega ent           ON ent.id               = lrd.entrega_id
                JOIN inventario.vw_stock_lotes_ubicacion sa ON sa.lote_id = l.id
                JOIN mes.partida prod_p             ON prod_p.id            = pp.partida_id
                WHERE pp.partida_id = ANY(p_partida_ids)
                  AND l.estado_calidad = 'APROBADO'
                GROUP BY
                    CASE WHEN l.propietario_id = 1 THEN 'VENTA_EGRESO' ELSE 'DESPACHO_CLIENTE' END
            ) lotes_agg
            JOIN doc.entrega_tipo grt ON grt.codigo = lotes_agg.tipo_codigo
        ), '[]'::jsonb)
    )
    INTO v_result;

    IF (v_result->>'entregas') = '[]' THEN
        RAISE EXCEPTION 'Las partidas seleccionadas no tienen rollos teñidos con stock disponible para despachar';
    END IF;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in get_despacho_partida - User: %, partidas: %, Error: %',
        v_usr_id, p_partida_ids, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.get_despacho_partida(bigint[]) TO authenticated;


-- ── doc.recompute_estado_comercial ────────────────────────────────────────
-- Refreshes mes.partida.estado_comercial — a CACHE of derived fulfillment
-- truth, never authoritative itself (see VENTA_MODULE_HANDOFF.md decision #12).
-- Follows the compra_detalle.cantidad_recibida precedent: inline recompute at
-- the end of every function that posts a fulfillment-affecting movement, not a
-- trigger (the caller already knows the partida; a trigger would have to
-- re-derive it per roll via genealogy).
--
-- CALL SITES (closed set — do not let it grow silently without updating here
-- and in the handoff doc): registrar_despacho, registrar_devolucion_cliente,
-- registrar_devolucion_crudo_cliente, anular_entrega, anular_devolucion_cliente,
-- anular_devolucion_crudo_cliente.
--
-- Denominator: terminal APROBADO output for the family, reusing
-- mes.vw_partida_familia_output — the SAME dedup rule cerrar_partida and
-- get_partida_familia use, so this number can't drift from theirs.
-- Numerator: of those terminal lotes, how many are CURRENTLY dispatched — a
-- lote counts if it has a SERV_EGR/VENTA_EGR movement with no later
-- SERV_DEV_ING/DEV_CLI_ING undoing it (rolls are atomic: dispatched/returned
-- as a whole, never partial — see UOM decisions in project memory).
--
-- DEVUELTA_* mapping is a first-pass heuristic (some dispatched-then-returned
-- history exists) — validate against real return scenarios before leaning on
-- it for anything beyond board display.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.recompute_estado_comercial(p_partida_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'mes', 'inventario', 'doc'
AS $$
DECLARE
    v_root_id      BIGINT;
    v_total        INT;
    v_dispatched   INT;   -- currently out (no return has undone it)
    v_ever_dispatched INT; -- has a dispatch movement at all (regardless of return)
    v_estado       partida_estado_comercial_enum;
BEGIN
    SELECT COALESCE(partida_origen_id, id) INTO v_root_id
    FROM mes.partida WHERE id = p_partida_id AND fyh_elm IS NULL;

    IF v_root_id IS NULL THEN
        RETURN;  -- partida not found / soft-deleted: nothing to recompute
    END IF;

    WITH terminal AS (
        SELECT lote_id FROM mes.vw_partida_familia_output
        WHERE root_id = v_root_id AND estado_calidad = 'APROBADO'
    )
    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = terminal.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
            )
            AND NOT EXISTS (
                SELECT 1 FROM inventario.item_movimientos im2
                JOIN inventario.item_movimiento_tipo imt2 ON imt2.id = im2.item_movimiento_tipo_id
                WHERE im2.lote_id = terminal.lote_id AND imt2.codigo IN ('SERV_DEV_ING','DEV_CLI_ING')
            )
        ),
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
                WHERE im.lote_id = terminal.lote_id AND imt.codigo IN ('SERV_EGR','VENTA_EGR')
            )
        )
    INTO v_total, v_dispatched, v_ever_dispatched
    FROM terminal;

    v_estado := CASE
        WHEN v_total = 0                                   THEN 'PENDIENTE'
        WHEN v_dispatched = 0 AND v_ever_dispatched = v_total THEN 'DEVUELTA_TOTAL'
        WHEN v_dispatched < v_ever_dispatched               THEN 'DEVUELTA_PARCIAL'
        WHEN v_dispatched >= v_total                        THEN 'ENTREGADA'
        WHEN v_dispatched > 0                                THEN 'ENTREGA_PARCIAL'
        ELSE 'PENDIENTE'
    END;

    UPDATE mes.partida
    SET estado_comercial = v_estado
    WHERE id = v_root_id AND estado_comercial IS DISTINCT FROM v_estado;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.recompute_estado_comercial(BIGINT) TO authenticated;


-- ── doc.registrar_despacho ──────────────────────────────────────────────────
-- ONE-SHOT dispatch: the user enters line items ONCE; that single submission
-- drives BOTH the physical document (entrega/entrega_detalle/item_movimientos,
-- via doc.crear_entrega — reused, not reimplemented) AND the commercial charge
-- (doc.venta/venta_detalle). Mirrors doc.registrar_compra_completa's shape:
-- one call, several downstream artifacts, everything else the function fetches
-- itself (price pre-fill, billing dims, movement type) rather than asking the
-- user to re-type it.
--
-- p_datos shape:
-- {
--   "tercero_id": 7,                          -- optional; derived from cargos' partidas if omitted
--   "items": [                                 -- the physical rolls to dispatch
--     { "item_id":44, "lote_id":901, "ubicacion_id":3, "cantidad":20.50,
--       "propietario_id":7, "partida_id":123 }  -- partida_id = the producing partida (root or rework child)
--   ],
--   "guias": {                                 -- optional per entrega_tipo; omit for headless (no serie/correlativo)
--     "VENTA_EGRESO":     { "serie":"F001", "correlativo":"00012345", "fecha_emision":"2026-07-13" },
--     "DESPACHO_CLIENTE":  { "serie":"T001", "correlativo":"00012345", "fecha_emision":"2026-07-13" }
--   },
--   "cargos": [                                -- ITEM lines (one per articulo × tenido × color)
--     { "partida_id":123, "articulo_id":3,     -- specific fabric (jersey/rib); dims else from partida
--       "cantidad_kg":480.60, "cantidad_rollos":24,
--       "item_id":null,                        -- only meaningful for tipo=VENTA lines
--       "lote_ids":[901,902],                   -- rolls this charge bills (traceability; resolved to
--                                                -- entrega_detalle via the entrega_ids created in step 1 —
--                                                -- those rows don't exist yet when the caller builds this
--                                                -- payload, so lote_id is what it links by, not detalle id)
--       "referencia_serie":null, "referencia_correlativo":null,  -- optional venta-level ref
--       "charges": [                            -- rate components; sum = the line's rate
--         { "operacion_id":2, "precio_kg":2.35 },   -- omit precio_kg → catalog fn_get_precio(op, line dims)
--         { "operacion_id":1 },                     -- termofijado (pruned client-side if N/A)
--         { "operacion_id":null, "precio_kg":24.0 } -- NULL op = product/base price (VENTA)
--       ] }
--   ]
-- }
--
-- Ownership (ledger truth) drives everything: ownership ≠ re-decided anywhere.
--   propietario_id = 1 (MLR)  → entrega_tipo VENTA_EGRESO     → movement VENTA_EGR → cargo tipo VENTA
--   propietario_id <> 1 (client) → entrega_tipo DESPACHO_CLIENTE → movement SERV_EGR  → cargo tipo SERVICIO
-- A cargo's partida must not mix ownership across its dispatched items in this
-- same call — that would mean two different sales pretending to be one line;
-- the function raises rather than guessing.
--
-- Billing dims color/tenido/grupo_articulo are SNAPSHOT from the INTENT partida
-- (root — COALESCE(partida_origen_id, id)); the specific articulo comes from the
-- cargo. Each charge stores its own precio_kg (typed, else catalog). Billing is
-- against intent; reworks are not billed separately.
--
-- Returns: { "venta_id":.., "entrega_ids":[..], "cargo_ids":[..] }
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_despacho(p_datos jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'mes', 'inventario'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_tercero_id    int  := (p_datos->>'tercero_id')::int;
    v_venta_id      bigint;
    v_entrega_ids   bigint[] := '{}';
    v_cargo_ids     bigint[] := '{}';
    v_entrega_id    bigint;
    v_tipo_codigo   text;
    v_tipo_id       smallint;
    v_guia          jsonb;
    v_items_grupo   jsonb;
    v_root_id       BIGINT;
    v_cargo         jsonb;
    v_charge        jsonb;
    v_detalle_id    bigint;
    v_op            smallint;
    v_partida       RECORD;
    v_precio_kg     NUMERIC(12,4);
    v_tipo_venta    venta_linea_tipo_enum;
    v_linea         SMALLINT;
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF jsonb_array_length(COALESCE(p_datos->'items', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'registrar_despacho: se requiere al menos un item.';
    END IF;

    IF v_tercero_id IS NULL THEN
        SELECT DISTINCT p.tercero_id INTO v_tercero_id
        FROM mes.partida p
        WHERE p.id = ANY(
            SELECT DISTINCT (c->>'partida_id')::bigint
            FROM jsonb_array_elements(COALESCE(p_datos->'cargos', '[]'::jsonb)) c
        );
    END IF;
    IF v_tercero_id IS NULL THEN
        RAISE EXCEPTION 'registrar_despacho: no se pudo determinar tercero_id (proporcione tercero_id o cargos con partida_id).';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_despacho', v_usr_id, p_datos);

    -- ── 1. Physical side: one entrega per ownership group, via crear_entrega ──
    -- Loops over exactly 2 fixed groups (ownership is structurally binary — see
    -- decision #5) but the BODY is 6 real steps (filter, tipo/guia lookup, build
    -- payload, call, recover id) — looping avoids duplicating that sequence, not
    -- just a value, so this earns its keep despite the fixed cardinality.
    --
    -- crear_entrega is reused as-is (not reimplemented, not wrapped) — it's ~140
    -- lines of already-live validated logic (stock checks, tercero validation,
    -- movement posting) called directly by the existing two-step frontend flow
    -- (get_despacho_partida → crear_entrega). As of 2026-07-14 it RETURNS bigint
    -- (the entrega_id) — changed from `text` specifically so this SELECT..INTO
    -- is clean, no currval/session-sequence trick needed. That change is
    -- breaking for BOTH of crear_entrega's direct callers (receipt AND
    -- dispatch) — see the note on crear_entrega itself (funciones/core.sql)
    -- and VENTA_MODULE_HANDOFF.md item 6b.
    FOR v_tipo_codigo IN SELECT unnest(ARRAY['VENTA_EGRESO','DESPACHO_CLIENTE'])
    LOOP
        SELECT jsonb_agg(item) INTO v_items_grupo
        FROM jsonb_array_elements(p_datos->'items') item
        WHERE (v_tipo_codigo = 'VENTA_EGRESO'    AND (item->>'propietario_id')::int = 1)
           OR (v_tipo_codigo = 'DESPACHO_CLIENTE' AND (item->>'propietario_id')::int IS DISTINCT FROM 1);

        CONTINUE WHEN v_items_grupo IS NULL;

        SELECT id INTO v_tipo_id FROM doc.entrega_tipo WHERE codigo = v_tipo_codigo;
        v_guia := (p_datos->'guias')->v_tipo_codigo;

        SELECT doc.crear_entrega(jsonb_build_object(
            'entrega_tipo_id', v_tipo_id,
            'tercero_id',      v_tercero_id,
            'serie',           v_guia->>'serie',
            'correlativo',     v_guia->>'correlativo',
            'fecha_emision',   COALESCE(v_guia->>'fecha_emision', now()::text),
            'items',           v_items_grupo
        )) INTO v_entrega_id;

        v_entrega_ids := array_append(v_entrega_ids, v_entrega_id);
    END LOOP;

    IF array_length(v_entrega_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'registrar_despacho: ningún item resolvió a un grupo de despacho válido.';
    END IF;

    -- ── 2. Commercial side: ONE venta per dispatch (no per-tercero tab-reuse) ──
    -- Each registrar_despacho call is its own priced, referenced outflow — the
    -- venta is the dispatch, not an accumulating tab. The reference
    -- (serie/correlativo) is FREE user input, stored verbatim and NOT attributed
    -- to any factura/guía doc type — that attribution flow is still TBD with the
    -- commercial users (physical guía already lives on doc.entrega separately).
    INSERT INTO doc.venta (tercero_id, referencia_serie, referencia_correlativo, usr_cre)
    VALUES (v_tercero_id,
            NULLIF(p_datos->>'referencia_serie', ''),
            NULLIF(p_datos->>'referencia_correlativo', ''),
            v_usr_id)
    RETURNING id INTO v_venta_id;

    UPDATE doc.entrega SET venta_id = v_venta_id WHERE id = ANY(v_entrega_ids);

    -- ── 3. Charge lines — ITEM line per (articulo × tenido × color) + charges ──
    -- Grain: the item line owns weight + pieces; each CHARGE (venta_detalle_cargo)
    -- owns a per-operación rate (≈ SAP SD pricing conditions). Dims color/tenido/
    -- grupo/fibra come from the partida (homogeneous within it); the specific
    -- articulo comes from the cargo. Charge rate = typed override, else catalog
    -- fn_get_precio(op, line dims). See VENTA_PER_ITEM_BILLING_SPEC.md.
    -- Fresh venta → line numbering starts at 0.
    v_linea := 0;

    FOR v_cargo IN SELECT * FROM jsonb_array_elements(COALESCE(p_datos->'cargos', '[]'::jsonb))
    LOOP
        v_linea := v_linea + 1;

        SELECT COALESCE(partida_origen_id, id) INTO v_root_id
        FROM mes.partida WHERE id = (v_cargo->>'partida_id')::bigint;

        IF v_root_id IS NULL THEN
            RAISE EXCEPTION 'registrar_despacho: partida % (cargo) no existe.', v_cargo->>'partida_id';
        END IF;

        SELECT p.tercero_id, p.color_x_cliente_id, p.tenido_id, p.grupo_articulo_id, p.fibra
        INTO v_partida
        FROM mes.partida p WHERE p.id = v_root_id;

        -- Ownership guard: this cargo's dispatched items (by root partida) must not mix owners.
        SELECT CASE
                 WHEN bool_and((item->>'propietario_id')::int = 1)          THEN 'VENTA'
                 WHEN bool_and((item->>'propietario_id')::int IS DISTINCT FROM 1) THEN 'SERVICIO'
                 ELSE NULL
               END
        INTO v_tipo_venta
        FROM jsonb_array_elements(p_datos->'items') item
        WHERE (
            SELECT COALESCE(partida_origen_id, id) FROM mes.partida
            WHERE id = (item->>'partida_id')::bigint
        ) = v_root_id;

        IF v_tipo_venta IS NULL THEN
            RAISE EXCEPTION 'registrar_despacho: partida % mezcla rollos propios y de cliente en este despacho — no se puede facturar como una sola línea.',
                v_root_id;
        END IF;

        -- Item line: weight + pieces, no rate (rate lives in the charges below).
        INSERT INTO doc.venta_detalle (
            venta_id, linea, tipo, item_id, articulo_id,
            color_x_cliente_id, tenido_id, grupo_articulo_id,
            partida_id, descripcion, cantidad_kg, cantidad_rollos, usr_cre
        ) VALUES (
            v_venta_id, v_linea, v_tipo_venta::venta_linea_tipo_enum,
            NULLIF(v_cargo->>'item_id','')::int,
            NULLIF(v_cargo->>'articulo_id','')::int,
            v_partida.color_x_cliente_id, v_partida.tenido_id, v_partida.grupo_articulo_id,
            v_root_id, v_cargo->>'descripcion',
            (v_cargo->>'cantidad_kg')::numeric,
            NULLIF(v_cargo->>'cantidad_rollos','')::int,
            v_usr_id
        )
        RETURNING id INTO v_detalle_id;

        v_cargo_ids := array_append(v_cargo_ids, v_detalle_id);

        -- Charges: one per operación. NULL operacion_id = product/base price (VENTA);
        -- non-NULL = an operation charge, priced from catalog if not typed.
        FOR v_charge IN SELECT * FROM jsonb_array_elements(COALESCE(v_cargo->'charges', '[]'::jsonb))
        LOOP
            v_op := NULLIF(v_charge->>'operacion_id','')::smallint;
            v_precio_kg := COALESCE(
                (v_charge->>'precio_kg')::numeric,
                CASE WHEN v_op IS NOT NULL THEN doc.fn_get_precio(
                    v_op, v_partida.color_x_cliente_id, v_partida.tercero_id,
                    v_partida.grupo_articulo_id, v_partida.tenido_id, v_partida.fibra
                ) END
            );
            IF v_precio_kg IS NULL THEN
                RAISE EXCEPTION 'registrar_despacho: sin precio para línea % / operación % — indique precio_kg.',
                    v_detalle_id, COALESCE(v_op::text, '(producto)');
            END IF;

            INSERT INTO doc.venta_detalle_cargo (venta_detalle_id, operacion_id, precio_kg, usr_cre)
            VALUES (v_detalle_id, v_op, v_precio_kg, v_usr_id);
        END LOOP;

        -- Traceability: point the dispatched physical lines at this charge line.
        -- Resolved by lote_id, not literal entrega_detalle ids — those rows are created
        -- by crear_entrega inside THIS call (step 1), so the caller can't know their ids
        -- in advance; lote_id is what it already sent in items[], scoped to the entregas
        -- this call just created so it can't touch unrelated rows.
        IF v_cargo ? 'lote_ids' THEN
            UPDATE doc.entrega_detalle
            SET venta_detalle_id = v_detalle_id
            WHERE entrega_id = ANY(v_entrega_ids)
              AND lote_id IN (SELECT jsonb_array_elements_text(v_cargo->'lote_ids')::int);
        END IF;
    END LOOP;

    -- ── 4. Refresh the fulfillment cache for every distinct partida touched ──
    PERFORM doc.recompute_estado_comercial(DISTINCT_ROOT.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM jsonb_array_elements(p_datos->'items') item
        JOIN mes.partida p ON p.id = (item->>'partida_id')::bigint
    ) DISTINCT_ROOT;

    RETURN jsonb_build_object(
        'venta_id',    v_venta_id,
        'entrega_ids', to_jsonb(v_entrega_ids),
        'cargo_ids',   to_jsonb(v_cargo_ids)
    );
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_despacho - User: %, Error: %', v_usr_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.registrar_despacho(jsonb) TO authenticated;


-- ── doc.asignar_referencia_venta ────────────────────────────────────────────
-- Sets/updates the reference document on a venta (serie + correlativo, verbatim,
-- non-unique). Replaces the old facturar_venta: no invoice lifecycle (no estado),
-- and the reference is NOT attributed to a factura/guía doc type — it's whatever
-- the commercial user records. (Old facturar_venta(BIGINT,TEXT,INT,DATE) is
-- DROPPED in patch 55.)
CREATE OR REPLACE FUNCTION doc.asignar_referencia_venta(
    p_venta_id     BIGINT,
    p_serie        TEXT,
    p_correlativo  TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id  int := get_user_id();
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE doc.venta
    SET referencia_serie       = NULLIF(p_serie, ''),
        referencia_correlativo = NULLIF(p_correlativo, ''),
        usr_mod                = v_usr_id
    WHERE id = p_venta_id AND flg_elm = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venta #% no encontrada o anulada.', p_venta_id;
    END IF;

    RETURN format('Referencia de venta #%s: %s-%s.', p_venta_id, p_serie, p_correlativo);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in asignar_referencia_venta - User: %, venta: %, Error: %', v_usr_id, p_venta_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.asignar_referencia_venta(BIGINT, TEXT, TEXT) TO authenticated;


-- ── doc.anular_venta ────────────────────────────────────────────────────────
-- Voids the commercial record via SOFT-DELETE (flg_elm) — there is no estado
-- column. Does NOT reverse entregas or movements — that is doc.anular_entrega's
-- job, run separately per entrega if the physical dispatch itself must be undone.
-- The reference (if any) is kept for audit trail, not cleared.
-- FIRST PASS: no cascade guard against still-active linked entregas — validate
-- this is the desired behavior before relying on it (see VENTA_MODULE_HANDOFF.md).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.anular_venta(p_venta_id BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'public', 'doc'
AS $$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id  int := get_user_id();
    v_flg_elm boolean;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT flg_elm INTO v_flg_elm FROM doc.venta WHERE id = p_venta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venta #% no encontrada.', p_venta_id;
    END IF;
    IF v_flg_elm THEN
        RAISE EXCEPTION 'Venta #% ya está anulada.', p_venta_id;
    END IF;

    -- Void = soft-delete (no estado column anymore). Does NOT reverse entregas
    -- or movements — that's doc.anular_entrega's job, run separately per entrega.
    UPDATE doc.venta
    SET flg_elm = true, usr_elm = v_usr_id, fyh_elm = now(), usr_mod = v_usr_id
    WHERE id = p_venta_id;

    RETURN format('Venta #%s anulada.', p_venta_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_venta - User: %, venta: %, Error: %', v_usr_id, p_venta_id, v_message;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION doc.anular_venta(BIGINT) TO authenticated;


-- ── doc.fn_descripcion_linea ─────────────────────────────────────────────────
-- Composes the human-readable venta_detalle line label from structured columns
-- — never free-typed. Generic items ("Jersey Poliéster/Algodón 30/1") are enriched
-- with order context (color, tenido) that lives on the partida, not the item —
-- see VENTA_MODULE_HANDOFF.md decision #10. Used by vw_venta to fill
-- venta_detalle.descripcion when the dispatch user left it blank (the normal
-- case); a non-NULL descripcion is a manual override and wins.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.fn_descripcion_linea(
    p_tipo               venta_linea_tipo_enum,
    p_operacion_id       SMALLINT,
    p_item_id            INT,
    p_grupo_articulo_id  INT,
    p_color_x_cliente_id INT,
    p_tenido_id          INT,
    p_flg_antipilling    BOOLEAN
)
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path TO 'public', 'mes', 'doc'
AS $$
    SELECT CASE
        WHEN p_tipo = 'VENTA' THEN
            COALESCE((SELECT nombre FROM item WHERE id = p_item_id), 'Producto')
        ELSE
            TRIM(BOTH ' · ' FROM
                COALESCE((SELECT nombre FROM mes.operacion WHERE id = p_operacion_id), '')
                || ' — '
                || COALESCE((SELECT nombre FROM grupo_articulo WHERE id = p_grupo_articulo_id), '')
                || COALESCE(' · ' || (SELECT color FROM vw_colores WHERE color_x_cliente_id = p_color_x_cliente_id), '')
                || COALESCE(' · ' || (SELECT tenido FROM tenido WHERE id = p_tenido_id), '')
                || CASE WHEN p_flg_antipilling THEN ' · Antipilling' ELSE '' END
            )
    END;
$$;

GRANT EXECUTE ON FUNCTION doc.fn_descripcion_linea(
    venta_linea_tipo_enum, SMALLINT, INT, INT, INT, INT, BOOLEAN
) TO authenticated;


-- ── doc.get_entrega ─────────────────────────────────────
-- Full read: entrega header + items (with lote and item detail).
-- Used for dispatch confirmation screen and entrega history view.
-- doc.get_entrega defined in core.sql

-- ── doc.anular_entrega ──────────────────────────────────
-- Cancels a entrega and reverses all its inventory movements.
--
-- Guards (outbound entregas — flg_emitida = true):
--   • Blocks if any non-anulada factura_cliente references this entrega.
--
-- Guards (inbound entregas — flg_emitida = false):
--   • Blocks if any lote created by this entrega has downstream movements
--     (production consumption, re-dispatch, adjustment). These lotes
--     can no longer be "un-received".
--   • Blocks if any lote created by this entrega is still reserved on an
--     active partida (mes.partida_componente), even if no movement has
--     posted yet (roll assignment alone posts no item_movimientos row).
--     Without this, anulación would soft-delete a lote a partida still
--     references. Caller must anular the partida (mes.anular_partida,
--     or unwind its pesaje/ejecución first) before the guía.
--
-- Reversal: posts one counter-movement per original movement,
-- swapping origen/destino. Uses the natural paired movement tipo:
--   COMPRA_ING  → DEV_PROV_EGR
--   SERV_ING    → DEV_CLI_EGR
--   SERV_EGR    → SERV_DEV_ING
--   VENTA_EGR   → DEV_CLI_ING
--
-- For inbound entregas: sets fyh_elm on lotes that were created
-- by this entrega (document trace: lote.documento_id = entrega_id).
-- ─────────────────────────────────────────────────────────────────────────
-- ── doc.get_entrega_anulacion_preview ────────────────────
-- Read-only diagnostic for the anulación confirmation screen. Reports every
-- reason doc.anular_entrega would currently refuse to void this guía:
--   • bloqueo_factura               — active client invoices referencing it
--   • bloqueo_movimiento_posterior  — lotes with movements beyond this entrega
--   • partidas_afectadas            — active partidas holding a roll reservation
--     (mes.partida_componente) against a lote this entrega created, each
--     flagged with tiene_pesaje / tiene_ejecucion so the caller knows whether
--     mes.anular_partida alone suffices or pesaje/ejecución must be reversed
--     first.
-- Does not change any state. anular_entrega does NOT auto-cascade into these
-- partidas — the caller resolves each blocker manually, in order, then
-- retries anular_entrega.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.get_entrega_anulacion_preview(p_entrega_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'mes', 'public'
AS $function$
DECLARE
    v_entrega RECORD;
    v_result  jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT gr.id, gr.fyh_elm, grt.flg_emitida, grt.codigo AS tipo_codigo
    INTO v_entrega
    FROM doc.entrega gr
    JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;

    SELECT jsonb_build_object(
        'entrega_id',   p_entrega_id,
        'ya_anulada',   v_entrega.fyh_elm IS NOT NULL,
        'flg_emitida',  v_entrega.flg_emitida,

        'bloqueo_factura', CASE WHEN v_entrega.flg_emitida THEN (
            SELECT jsonb_agg(DISTINCT f.id)
            FROM doc.factura_detalle fd
            JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
            WHERE fd.entrega_id = p_entrega_id
        ) END,

        'bloqueo_movimiento_posterior', CASE WHEN NOT v_entrega.flg_emitida THEN (
            -- PESAJE_POS/PESAJE_NEG movements (original + any reversal posted
            -- by inventario.anular_pesaje) are excluded here: they're pesaje-
            -- domain history, never deleted per this schema's audit-trail
            -- convention, and are resolved via bloqueo_pesaje_activo below
            -- (current pesaje state) rather than by presence of old movements.
            SELECT jsonb_agg(DISTINCT l.id)
            FROM inventario.lote l
            JOIN inventario.item_movimientos im ON im.lote_id = l.id
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE l.documento_tipo = 'entrega' AND l.documento_id = p_entrega_id
              AND l.fyh_elm IS NULL
              AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id)
              AND imt.codigo NOT IN ('PESAJE_POS', 'PESAJE_NEG')
        ) END,

        'bloqueo_pesaje_activo', CASE WHEN NOT v_entrega.flg_emitida THEN (
            -- Lotes still weighed (inventario.pesaje not yet reversed via
            -- inventario.anular_pesaje). Must be cleared before anulación.
            SELECT jsonb_agg(DISTINCT l.id)
            FROM inventario.lote l
            JOIN inventario.pesaje ps ON ps.lote_id = l.id
            WHERE l.documento_tipo = 'entrega' AND l.documento_id = p_entrega_id
              AND l.fyh_elm IS NULL
        ) END,

        'partidas_afectadas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'partida_id',         p.id,
                'numero',             p.numero,
                'estado_produccion',  p.estado_produccion,
                'rollos_de_esta_guia', sub.n_rollos,
                'tiene_pesaje', EXISTS (
                    SELECT 1 FROM mes.partida_componente pc2
                    JOIN inventario.pesaje ps ON ps.lote_id = pc2.lote_id
                    WHERE pc2.partida_id = p.id AND pc2.lote_id IS NOT NULL
                ),
                'tiene_ejecucion', EXISTS (
                    SELECT 1 FROM mes.partida_paso_ejecucion pe
                    JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
                    WHERE pp.partida_id = p.id
                )
            ))
            FROM (
                SELECT pc.partida_id, COUNT(*) AS n_rollos
                FROM mes.partida_componente pc
                JOIN inventario.lote l ON l.id = pc.lote_id
                WHERE l.documento_tipo = 'entrega'
                  AND l.documento_id   = p_entrega_id
                  AND pc.lote_id IS NOT NULL
                GROUP BY pc.partida_id
            ) sub
            JOIN mes.partida p ON p.id = sub.partida_id
            WHERE p.estado_produccion NOT IN ('CANCELADA', 'TECO', 'CERRADA')
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION doc.get_entrega_anulacion_preview(BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION doc.anular_entrega(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'inventario', 'public'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id          int := get_user_id();
    v_entrega            RECORD;
    v_reversal_tipo   SMALLINT;
    v_doc_mov_id      BIGINT;
    v_mov_count       INT;
    v_lote_count      INT;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_entrega', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT gr.id, gr.fyh_elm, grt.flg_emitida, grt.codigo AS tipo_codigo,
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
        RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id;
    END IF;

    -- Devolution tipos have dedicated anulación RPCs (funciones/devoluciones.sql):
    -- their forward movement codes are real business events, not anulación
    -- scaffolding, so they reverse via dedicated *_REV codes, not this
    -- function's generic CASE map.
    IF v_entrega.tipo_codigo IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_cliente para anular esta devolución (%).', v_entrega.tipo_codigo;
    END IF;
    IF v_entrega.tipo_codigo = 'DEVOLUCION_CLIENTE_CRUDO' THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_crudo_cliente para anular esta devolución.';
    END IF;
    IF v_entrega.tipo_codigo = 'DEVOLUCION_PROVEEDOR' THEN
        RAISE EXCEPTION 'Use doc.anular_devolucion_proveedor para anular esta devolución.';
    END IF;

    -- ── Outbound guard: block if any active client invoice references this entrega
    IF v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM doc.factura_detalle fd
            JOIN doc.factura f ON f.id = fd.factura_id AND f.estado <> 'anulada'
            WHERE fd.entrega_id = p_entrega_id
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: está referenciada en facturas activas. Anule primero las facturas.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote has downstream movements.
    -- PESAJE_POS/PESAJE_NEG are excluded here: pesaje-domain movements are
    -- never deleted (audit-trail convention), so old/reversed pesaje history
    -- would otherwise block forever. Active (unreversed) pesaje is caught by
    -- the dedicated guard below instead.
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN inventario.item_movimientos im ON im.lote_id = l.id
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
              -- Any movement NOT from this entrega means the lote was used downstream
              AND NOT (im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id)
              AND imt.codigo NOT IN ('PESAJE_POS', 'PESAJE_NEG')
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más lotes recibidos ya tienen movimientos posteriores (consumo, producción o redespacho).',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote still has an active
    -- (unreversed) pesaje record — must run inventario.anular_pesaje first.
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN inventario.pesaje ps ON ps.lote_id = l.id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más lotes recibidos tienen pesaje activo. Anule el pesaje (inventario.anular_pesaje) primero.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Inbound guard: block if any created lote is still reserved on an active partida
    IF NOT v_entrega.flg_emitida THEN
        IF EXISTS (
            SELECT 1
            FROM inventario.lote l
            JOIN mes.partida_componente pc ON pc.lote_id = l.id
            JOIN mes.partida pr             ON pr.id      = pc.partida_id
            WHERE l.documento_tipo = 'entrega'
              AND l.documento_id   = p_entrega_id
              AND l.fyh_elm        IS NULL
              AND pr.estado_produccion NOT IN ('CANCELADA', 'TECO', 'CERRADA')
        ) THEN
            RAISE EXCEPTION
                'No se puede anular la guía #%: uno o más rollos recibidos están reservados en una partida activa. Anule la partida (mes.anular_partida) antes de anular la guía.',
                p_entrega_id;
        END IF;
    END IF;

    -- ── Resolve reversal movement tipo
    SELECT imt2.id INTO v_reversal_tipo
    FROM inventario.item_movimiento_tipo imt1
    JOIN inventario.item_movimiento_tipo imt2 ON imt2.codigo = CASE imt1.codigo
        WHEN 'COMPRA_ING' THEN 'DEV_PROV_EGR'
        WHEN 'SERV_ING'   THEN 'DEV_CLI_EGR'
        WHEN 'SERV_EGR'   THEN 'SERV_DEV_ING'
        WHEN 'VENTA_EGR'  THEN 'DEV_CLI_ING'
        ELSE NULL
    END
    WHERE imt1.id = v_entrega.item_movimiento_tipo_id;

    IF v_reversal_tipo IS NULL THEN
        RAISE EXCEPTION
            'Guía #%: no existe tipo de movimiento de reversal para el tipo de guía "%". Contactar administrador.',
            p_entrega_id, v_entrega.tipo_codigo;
    END IF;

    -- ── Shared doc_movimiento_id for all reversal movements
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    -- ── Post reversal movements (swaps origen_ubicacion_id ↔ destino_ubicacion_id)
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id,
        item_id, lote_id,
        item_movimiento_tipo_id,
        origen_ubicacion_id,
        destino_ubicacion_id,
        cantidad, fecha_hora,
        documento_tipo, documento_id,
        observacion
    )
    SELECT
        v_doc_mov_id,
        im.item_id, im.lote_id,
        v_reversal_tipo,
        im.destino_ubicacion_id,   -- swap: destination becomes the new origin
        im.origen_ubicacion_id,    -- swap: origin becomes the new destination
        im.cantidad,
        NOW(),
        'entrega',
        p_entrega_id,
        'ANULACION guía #' || p_entrega_id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega'
      AND im.documento_id   = p_entrega_id;

    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    -- ── For inbound entregas: retire the lotes that were created by this entrega
    IF NOT v_entrega.flg_emitida THEN
        UPDATE inventario.lote
        SET usr_elm = v_usr_id, fyh_elm = NOW()
        WHERE documento_tipo = 'entrega'
          AND documento_id   = p_entrega_id
          AND fyh_elm        IS NULL;

        GET DIAGNOSTICS v_lote_count = ROW_COUNT;
    END IF;

    -- ── Mark entrega as cancelled
    UPDATE doc.entrega
    SET usr_elm = v_usr_id, fyh_elm = NOW()
    WHERE id = p_entrega_id;

    -- Resync compra_detalle.cantidad_recibida if this entrega is linked to a PO
    -- (no-op if unlinked — fn_refresh_compra_detalle_qtys nets the DEV_PROV_EGR
    -- reversal just posted above against the original COMPRA_ING).
    PERFORM doc.fn_refresh_compra_detalle_qtys(ce.compra_id)
    FROM doc.compra_entrega ce
    WHERE ce.entrega_id = p_entrega_id;

    -- Fulfillment cache: undoing an outbound (dispatch) entrega un-dispatches its rolls;
    -- for inbound entregas this join simply finds no rows (harmless no-op).
    -- See doc.recompute_estado_comercial's closed call-site list.
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (
        SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
        FROM doc.entrega_detalle ed
        JOIN inventario.lote l ON l.id = ed.lote_id
        JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
        JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
        JOIN mes.partida p ON p.id = pp.partida_id
        WHERE ed.entrega_id = p_entrega_id
    ) root;

    RETURN format('Guía #%s anulada. %s movimiento(s) revertido(s)%s.',
        p_entrega_id,
        v_mov_count,
        CASE WHEN NOT v_entrega.flg_emitida THEN format(', %s lote(s) dado(s) de baja', v_lote_count) ELSE '' END
    );
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;


-- ── doc.registrar_numero_entrega ─────────────────────────────────────────────
-- Backfills the legal serie/correlativo onto a headless entrega after the
-- EXTERNAL system (GRE) issues the number. The dispatch movement is posted at
-- crear_entrega time (serie NULL); this transcribes the number once it's known.
--
-- serie/correlativo are written together (the chk_entrega_doc_fields both-or-neither
-- CHECK enforces this). Only headless entregas (serie IS NULL) are eligible — a
-- entrega that already carries a number must be corrected by anulando + reissuing,
-- not silently overwritten. Collisions are caught by the UNIQUE
-- (tercero_id, serie, correlativo, entrega_tipo_id) constraint.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION doc.registrar_numero_entrega(
    p_entrega_id     BIGINT,
    p_serie       TEXT,
    p_correlativo TEXT
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'doc', 'public'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id       int := get_user_id();
    v_serie_actual text;
    v_fyh_elm      timestamptz;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_serie IS NULL OR trim(p_serie) = ''
       OR p_correlativo IS NULL OR trim(p_correlativo) = '' THEN
        RAISE EXCEPTION 'Se requieren serie y correlativo para numerar la guía.';
    END IF;

    SELECT gr.serie, gr.fyh_elm
    INTO   v_serie_actual, v_fyh_elm
    FROM   doc.entrega gr
    WHERE  gr.id = p_entrega_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id;
    END IF;
    IF v_fyh_elm IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% está anulada y no puede numerarse.', p_entrega_id;
    END IF;
    IF v_serie_actual IS NOT NULL THEN
        RAISE EXCEPTION 'Guía #% ya tiene número (%-%). Para corregirlo, anule y reemita.',
            p_entrega_id, v_serie_actual, (SELECT correlativo FROM doc.entrega WHERE id = p_entrega_id);
    END IF;

    BEGIN
        UPDATE doc.entrega
        SET serie       = trim(p_serie),
            correlativo = trim(p_correlativo),
            usr_mod     = v_usr_id,
            fyh_mod     = now()
        WHERE id = p_entrega_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'El número %-% ya existe para este cliente y tipo de guía.',
            trim(p_serie), trim(p_correlativo);
    END;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_numero_entrega', v_usr_id,
            jsonb_build_object('entrega_id', p_entrega_id,
                               'serie', trim(p_serie),
                               'correlativo', trim(p_correlativo)));

    RETURN format('Guía #%s numerada como %s-%s.', p_entrega_id, trim(p_serie), trim(p_correlativo));

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_numero_entrega - User: %, entrega: %, Error: %',
        v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;


-- ── doc.vw_entregas_sin_numerar ──────────────────────────────────────────────
-- Worklist of headless entregas (serie IS NULL) awaiting their external GRE
-- number. Drives the "guías pendientes de numerar" screen so a dispatched
-- (or received) document never sits untracked. flg_emitida lets the frontend
-- split outbound dispatch from inbound receipt; partidas shows which production
-- orders the dispatched rolls belong to.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW doc.vw_entregas_sin_numerar AS
SELECT
    gr.id                                   AS entrega_id,
    gr.entrega_tipo_id,
    grt.codigo                              AS tipo_codigo,
    grt.nombre                              AS tipo_nombre,
    grt.flg_emitida,
    gr.tercero_id,
    t.nombre                                AS tercero,
    gr.fecha_emision,
    gr.fyh_cre,
    COUNT(grd.id)                           AS lineas,
    COALESCE(SUM(grd.n_rollos), 0)          AS rollos,
    ROUND(COALESCE(SUM(grd.cantidad), 0)::numeric, 2) AS kg_total,
    ARRAY_AGG(DISTINCT EXTRACT(YEAR FROM p.fyh_cre)::TEXT
                       || '-' || LPAD(p.numero::TEXT, 4, '0'))
        FILTER (WHERE p.id IS NOT NULL)     AS partidas
FROM doc.entrega gr
JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
JOIN tercero t                  ON t.id  = gr.tercero_id
LEFT JOIN doc.entrega_detalle grd ON grd.entrega_id = gr.id
LEFT JOIN inventario.lote l ON l.id = grd.lote_id
LEFT JOIN mes.partida_paso_ejecucion pe
       ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
LEFT JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
LEFT JOIN mes.partida p       ON p.id = pp.partida_id
WHERE gr.serie   IS NULL
  AND gr.fyh_elm IS NULL
GROUP BY gr.id, gr.entrega_tipo_id, grt.codigo, grt.nombre, grt.flg_emitida,
         gr.tercero_id, t.nombre, gr.fecha_emision, gr.fyh_cre;

GRANT SELECT ON doc.vw_entregas_sin_numerar TO authenticated;


-- GRANT for get_despacho_partida(bigint[]) is above the function definition
-- doc.get_entrega grant is in core.sql
GRANT EXECUTE ON FUNCTION doc.anular_entrega(bigint)  TO authenticated;
GRANT EXECUTE ON FUNCTION doc.registrar_numero_entrega(bigint, text, text) TO authenticated;

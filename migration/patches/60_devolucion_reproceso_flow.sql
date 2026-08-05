-- ============================================================================
-- PATCH 60 · Devolución flow redesign (per DEVOLUCION_REPROCESO_FLOW_SPEC.md)
-- ============================================================================
-- Closes the three devolución/reproceso concepts cleanly:
--   #1 return undyed crudo (service cancelled)  · #2 client-QC dyed return → reprocess
--   · #3 our-QC fail → reprocess (crear_reproceso, unchanged here).
--
-- Changes (all reviewed against funciones/devoluciones.sql current bodies):
--   (A) NEW  doc.entrega.entrega_origen_id  — self-FK: the entrega this one reverses
--            (dispatch for #2, ingress for #1). Explicit entrega→entrega lineage.
--   (B) registrar_devolucion_crudo_cliente  — REMOVE the wrong venta link (crudo was
--            never sold); entrega_origen_id is ALWAYS DERIVED per lote from its ingress
--            movement (never a caller input — see 2026-07-29 correction below); rejects
--            batches whose lotes resolve to more than one origin entrega. GUARD: reject
--            if the crudo is committed to an active partida (producción cancels it first
--            — the cancellation is an explicit action, NOT a hidden side effect).
--   (C) registrar_devolucion_cliente        — entrega_origen_id ALWAYS DERIVED per lote
--            from its dispatch movement (never a caller input); same mixed-origin
--            rejection; mark returned rolls estado_calidad='REPROCESO' (unifies with #3);
--            venta link kept (link only — venta is NEVER credited/reversed).
--   (D) NEW  mes.vw_pendiente_reproceso      — in-stock dyed rolls flagged REPROCESO
--            (returned OR our-QC-failed) not yet moved into a rework partida.
--   (E) anular_devolucion_cliente            — on undo, revert REPROCESO→APROBADO; NEW
--            guard blocks anulación if the lote was already reassigned into a rework
--            partida (crear_reproceso moves via mes.partida_componente, not
--            item_movimientos, so the original movement-only guard would miss it).
--
-- 2026-07-29 correction (see DEVOLUCION_REPROCESO_FLOW_SPEC.md §4b, §3.5): earlier draft
-- of this patch took entrega_origen_id as an optional caller input with derive-as-
-- fallback, and assumed a single origin entrega per batch without checking. Both fixed:
-- derivation is now unconditional (never trust a caller-passed FK against the ledger),
-- and a batch resolving to multiple origin entregas is rejected, not silently collapsed
-- to one. The anular_devolucion_cliente guard also gained the rework-reassignment check
-- below, using current mes.partida_componente state — the full historical
-- partida_componente_movimiento ledger (immediate-source genealogy) stays deferred.
--
-- Deferred (NOT here): the rollo-scoped movement integrity guard (cross-cutting,
--   high blast radius → its own tested change) and the partida_componente genealogy
--   ledger (→ mlr-db).
--
-- ⚠ Business-critical, live functions. Review + test on a copy before prod.
-- ============================================================================

BEGIN;

-- ── (A) entrega_origen_id ─────────────────────────────────────────────────────
ALTER TABLE doc.entrega ADD COLUMN IF NOT EXISTS entrega_origen_id BIGINT REFERENCES doc.entrega(id);
COMMENT ON COLUMN doc.entrega.entrega_origen_id IS
  'The entrega this one reverses/follows: the original DISPATCH for a client return (#2), '
  'the INGRESS guía for a crudo return (#1). Chains back to the first dispatch.';


-- ── (B) registrar_devolucion_crudo_cliente (concept #1) ───────────────────────
--   crudo returned to client, service cancelled. NO venta (never sold).
CREATE OR REPLACE FUNCTION doc.registrar_devolucion_crudo_cliente(p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_entrega_id    BIGINT;
    v_entrega_tipo  entrega_tipo%ROWTYPE;
    v_doc_mov_id    BIGINT;
    v_fecha_mov     TIMESTAMPTZ;
    v_error_payload jsonb;
    v_origen_id     BIGINT;              -- CHANGE: ingress guía this return reverses (derived)
    v_origen_ids    BIGINT[];            -- CHANGE: distinct derived origins, for mixed-batch rejection
    v_lote_ids      int[];               -- CHANGE: returned lotes (for provenance + partida cancel)
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_entrega_tipo FROM entrega_tipo WHERE codigo = 'DEVOLUCION_CLIENTE_CRUDO';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tipo DEVOLUCION_CLIENTE_CRUDO no encontrado en entrega_tipo';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tercero WHERE id = (p_datos->>'tercero_id')::INT AND flg_cliente = true) THEN
        RAISE EXCEPTION 'tercero_id % no corresponde a un cliente', (p_datos->>'tercero_id');
    END IF;

    SELECT array_agg(DISTINCT (i->>'lote_id')::int) INTO v_lote_ids
    FROM jsonb_array_elements(p_datos->'items') i;

    -- Guard: only ROLLO lotes allowed (not insumos)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id, 'item_tipo', it.codigo))
    INTO v_error_payload
    FROM (SELECT DISTINCT (i->>'lote_id')::int AS lote_id FROM jsonb_array_elements(p_datos->'items') i) ei
    JOIN inventario.lote l  ON l.id = ei.lote_id
    JOIN item               ON item.id = l.item_id
    JOIN item_tipo it       ON it.id = item.item_tipo_id
    WHERE it.codigo <> 'ROLLO';
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución de crudo inválida: solo se pueden devolver rollos (no insumos)'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: lotes must have entered MLR from this client (SERV_ING via entrega)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id))
    INTO v_error_payload
    FROM (SELECT DISTINCT (i->>'lote_id')::int AS lote_id FROM jsonb_array_elements(p_datos->'items') i) ei
    WHERE NOT EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'SERV_ING'
        JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE im.lote_id = ei.lote_id AND e.tercero_id = (p_datos->>'tercero_id')::INT);
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución de crudo inválida: los siguientes lotes no ingresaron como material de servicio de este cliente'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- CHANGE (guard, not a hidden side effect): crudo committed to a NON-cancelled partida
    -- cannot be returned. Producción must cancel the service order first; comercial then
    -- returns the crudo. (Was previously an auto-cancel inside this function — removed.)
    SELECT jsonb_agg(DISTINCT jsonb_build_object('lote_id', pc.lote_id, 'partida_id', pc.partida_id, 'estado', p.estado_produccion))
    INTO v_error_payload
    FROM mes.partida_componente pc
    JOIN mes.partida p ON p.id = pc.partida_id
    WHERE pc.lote_id = ANY(v_lote_ids) AND p.estado_produccion <> 'CANCELADA';
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución de crudo inválida: los rollos están comprometidos en una partida activa. Cancele la partida antes de devolver el crudo.'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: sufficient available stock
    WITH entrega_items AS (
        SELECT (i->>'item_id')::int AS item_id, (i->>'lote_id')::int AS lote_id,
               (i->>'ubicacion_id')::int AS ubicacion_id, SUM((i->>'cantidad')::numeric) AS cantidad
        FROM jsonb_array_elements(p_datos->'items') i GROUP BY 1,2,3)
    SELECT jsonb_agg(jsonb_build_object('item_id', items.item_id, 'lote_id', items.lote_id,
        'saldo_disponible', COALESCE(sl.cantidad_disponible,0), 'cantidad_requerida', items.cantidad))
    INTO v_error_payload
    FROM entrega_items items
    LEFT JOIN inventario.vw_stock_lotes sl ON sl.lote_id = items.lote_id AND sl.item_id = items.item_id
    WHERE COALESCE(sl.cantidad_disponible,0) < items.cantidad;
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente para devolución de crudo' USING DETAIL = v_error_payload::text;
    END IF;

    -- CHANGE (2026-07-29): entrega_origen_id is ALWAYS DERIVED, never a caller input —
    -- resolve per lote from its SERV_ING ingress movement (the CLIENTE_ENVIO_PROCESO
    -- guía it arrived on), then reject if the batch spans more than one origin entrega
    -- (a mixed batch was previously silently collapsed to one — an unvalidated
    -- assumption, not a real constraint). Caller must split into one call per origin.
    SELECT array_agg(DISTINCT resolved.origen_id),
           jsonb_agg(jsonb_build_object('lote_id', resolved.lote_id, 'entrega_origen_id', resolved.origen_id))
    INTO v_origen_ids, v_error_payload
    FROM (
        SELECT ll.lote_id,
               (SELECT im.documento_id
                FROM inventario.item_movimientos im
                JOIN inventario.item_movimiento_tipo imt
                     ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'SERV_ING'
                WHERE im.lote_id = ll.lote_id AND im.documento_tipo = 'entrega'
                ORDER BY im.id LIMIT 1) AS origen_id
        FROM unnest(v_lote_ids) AS ll(lote_id)
    ) resolved;

    IF array_length(v_origen_ids, 1) > 1 THEN
        RAISE EXCEPTION 'Devolución de crudo inválida: los rollos provienen de guías de ingreso distintas; separe la devolución por guía de origen.'
            USING DETAIL = v_error_payload::text;
    END IF;

    v_origen_id := v_origen_ids[1];

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_devolucion_crudo_cliente', v_usr_id, p_datos);

    v_fecha_mov := COALESCE((p_datos->>'fecha_emision')::TIMESTAMPTZ, now());
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion, entrega_origen_id)
    VALUES (v_entrega_tipo.id, (p_datos->>'tercero_id')::INT, p_datos->>'serie', p_datos->>'correlativo',
            v_fecha_mov, NULL, v_origen_id)   -- CHANGE: entrega_origen_id set, NO venta
    RETURNING id INTO v_entrega_id;

    WITH items AS (
        SELECT COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
               (item->>'item_id')::INT AS item_id, (item->>'cantidad')::NUMERIC(12,4) AS cantidad,
               (item->>'lote_id')::INT AS lote_id, (item->>'ubicacion_id')::INT AS ubicacion_id,
               (item->>'n_rollos')::INT AS n_rollos
        FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)),
    det AS (
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id, n_rollos FROM items
        RETURNING id, linea)
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora,
        documento_tipo, documento_id, documento_linea_id)
    SELECT v_doc_mov_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
           i.ubicacion_id, NULL, i.cantidad, v_fecha_mov, 'entrega', v_entrega_id, d.id
    FROM items i JOIN det d ON d.linea = i.linea;

    -- (Partida cancellation is NOT done here — it's a producción action, enforced by the
    --  active-partida guard above. And the copy-pasted venta link is gone: crudo is never sold.)

    -- Fulfillment cache refresh
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
          FROM doc.entrega_detalle ed
          JOIN inventario.lote l ON l.id = ed.lote_id
          JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
          JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
          JOIN mes.partida p ON p.id = pp.partida_id
          WHERE ed.entrega_id = v_entrega_id) root;

    RETURN format('Devolución de crudo a cliente registrada. Guía #%s creada.', v_entrega_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_devolucion_crudo_cliente - User: %, Params: %, Error: %',
        v_usr_id, p_datos::TEXT, v_message;
    RAISE;
END;
$function$;


-- ── (C) registrar_devolucion_cliente (concept #2) ─────────────────────────────
--   client returns dispatched dyed rolls (their QC) → to be reprocessed.
CREATE OR REPLACE FUNCTION doc.registrar_devolucion_cliente(p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int  := get_user_id();
    v_entrega_id    BIGINT;
    v_entrega_tipo  entrega_tipo%ROWTYPE;
    v_doc_mov_id    BIGINT;
    v_fecha_mov     TIMESTAMPTZ;
    v_error_payload jsonb;
    v_origen_id     BIGINT;              -- CHANGE: dispatch guía this return reverses (derived)
    v_origen_ids    BIGINT[];            -- CHANGE: distinct derived origins, for mixed-batch rejection
    v_venta_id      BIGINT;
    v_lote_ids      int[];
BEGIN
    IF NOT jwt_has_permission('comercial.crear') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.crear' USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_entrega_tipo FROM entrega_tipo WHERE id = (p_datos->>'entrega_tipo_id')::SMALLINT;
    IF NOT FOUND OR v_entrega_tipo.codigo NOT IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'entrega_tipo_id inválido: use DEVOLUCION_CLIENTE_SERVICIO (8) o DEVOLUCION_CLIENTE_VENTA (7)';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tercero WHERE id = (p_datos->>'tercero_id')::INT AND flg_cliente = true) THEN
        RAISE EXCEPTION 'tercero_id % no corresponde a un cliente', (p_datos->>'tercero_id');
    END IF;

    SELECT array_agg(DISTINCT (i->>'lote_id')::int) INTO v_lote_ids
    FROM jsonb_array_elements(p_datos->'items') i;

    -- Guard: lotes must be fully out of stock (were dispatched)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id, 'cantidad_disponible', sl.cantidad_disponible))
    INTO v_error_payload
    FROM (SELECT DISTINCT (i->>'lote_id')::int AS lote_id FROM jsonb_array_elements(p_datos->'items') i) ei
    JOIN inventario.vw_stock_lotes sl ON sl.lote_id = ei.lote_id;
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución inválida: los siguientes lotes aún tienen stock positivo (¿ya devueltos o nunca despachados?)'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- Guard: each lote dispatched to this client at least once
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id))
    INTO v_error_payload
    FROM (SELECT DISTINCT (i->>'lote_id')::int AS lote_id FROM jsonb_array_elements(p_datos->'items') i) ei
    WHERE NOT EXISTS (
        SELECT 1 FROM inventario.item_movimientos im
        JOIN doc.entrega e ON e.id = im.documento_id AND im.documento_tipo = 'entrega'
        WHERE im.lote_id = ei.lote_id AND e.tercero_id = (p_datos->>'tercero_id')::INT
          AND im.origen_ubicacion_id IS NOT NULL);
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'Devolución inválida: los siguientes lotes no registran despacho previo a este cliente'
            USING DETAIL = v_error_payload::text;
    END IF;

    -- CHANGE (2026-07-29): entrega_origen_id is ALWAYS DERIVED, never a caller input —
    -- resolve per lote from its most recent dispatch (egress) movement to this client,
    -- then reject if the batch spans more than one origin entrega (mixed-batch case was
    -- previously unvalidated). Caller must split into one call per dispatch guía.
    SELECT array_agg(DISTINCT resolved.origen_id),
           jsonb_agg(jsonb_build_object('lote_id', resolved.lote_id, 'entrega_origen_id', resolved.origen_id))
    INTO v_origen_ids, v_error_payload
    FROM (
        SELECT ll.lote_id,
               (SELECT im.documento_id
                FROM inventario.item_movimientos im
                JOIN doc.entrega e2 ON e2.id = im.documento_id AND im.documento_tipo = 'entrega'
                WHERE im.lote_id = ll.lote_id AND im.origen_ubicacion_id IS NOT NULL
                  AND e2.tercero_id = (p_datos->>'tercero_id')::INT
                ORDER BY im.id DESC LIMIT 1) AS origen_id
        FROM unnest(v_lote_ids) AS ll(lote_id)
    ) resolved;

    IF array_length(v_origen_ids, 1) > 1 THEN
        RAISE EXCEPTION 'Devolución inválida: los rollos provienen de despachos distintos; separe la devolución por guía de despacho.'
            USING DETAIL = v_error_payload::text;
    END IF;

    v_origen_id := v_origen_ids[1];
    SELECT venta_id INTO v_venta_id FROM doc.entrega WHERE id = v_origen_id;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('registrar_devolucion_cliente', v_usr_id, p_datos);

    v_fecha_mov := COALESCE((p_datos->>'fecha_recepcion')::TIMESTAMPTZ, now());
    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO doc.entrega(entrega_tipo_id, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion, entrega_origen_id, venta_id)
    VALUES (v_entrega_tipo.id, (p_datos->>'tercero_id')::INT, p_datos->>'serie', p_datos->>'correlativo',
            v_fecha_mov, v_fecha_mov, v_origen_id, v_venta_id)   -- CHANGE: origen + venta LINK (never credited)
    RETURNING id INTO v_entrega_id;

    WITH items AS (
        SELECT COALESCE((item->>'linea')::SMALLINT, idx::SMALLINT) AS linea,
               (item->>'item_id')::INT AS item_id, (item->>'cantidad')::NUMERIC(12,4) AS cantidad,
               (item->>'lote_id')::INT AS lote_id, (item->>'ubicacion_id')::INT AS ubicacion_id
        FROM jsonb_array_elements(p_datos->'items') WITH ORDINALITY AS t(item, idx)),
    det AS (
        INSERT INTO doc.entrega_detalle(entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id)
        SELECT v_entrega_id, linea, item_id, cantidad, lote_id, ubicacion_id FROM items
        RETURNING id, linea)
    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id, documento_linea_id)
    SELECT v_doc_mov_id, i.item_id, i.lote_id, v_entrega_tipo.item_movimiento_tipo_id,
           i.ubicacion_id, i.cantidad, v_fecha_mov, 'entrega', v_entrega_id, d.id
    FROM items i JOIN det d ON d.linea = i.linea;

    -- CHANGE: returned rolls need rework → flag REPROCESO (unifies with concept #3 for vw_pendiente_reproceso).
    UPDATE inventario.lote SET estado_calidad = 'REPROCESO', usr_mod = v_usr_id, fyh_mod = now()
    WHERE id = ANY(v_lote_ids);

    -- Fulfillment cache refresh (a return un-dispatches rolls)
    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
          FROM doc.entrega_detalle ed
          JOIN inventario.lote l ON l.id = ed.lote_id
          JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
          JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
          JOIN mes.partida p ON p.id = pp.partida_id
          WHERE ed.entrega_id = v_entrega_id) root;

    RETURN format('Devolución de cliente registrada. Guía #%s creada.', v_entrega_id);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in registrar_devolucion_cliente - User: %, Params: %, Error: %',
        v_usr_id, p_datos::TEXT, v_message;
    RAISE;
END;
$function$;


-- ── (D) vw_pendiente_reproceso ────────────────────────────────────────────────
--   Unified queue for producción: in-stock dyed rolls flagged REPROCESO (returned by
--   client OR failed our QC) that have NOT yet been moved into a rework partida.
CREATE OR REPLACE VIEW mes.vw_pendiente_reproceso AS
SELECT l.id                        AS lote_id,
       l.item_id,
       l.propietario_id,
       l.cantidad                  AS peso_kg,
       lrd.color_x_cliente_id,
       lrd.tenido_id,
       CASE WHEN EXISTS (
              SELECT 1 FROM inventario.item_movimientos im
              JOIN inventario.item_movimiento_tipo t ON t.id = im.item_movimiento_tipo_id
                   AND t.codigo IN ('DEV_CLI_ING','SERV_DEV_ING')
              WHERE im.lote_id = l.id)
            THEN 'DEVOLUCION_CLIENTE' ELSE 'QC_INTERNO' END AS origen_reproceso
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
WHERE l.estado_calidad = 'REPROCESO'
  AND COALESCE((SELECT SUM(cantidad_actual) FROM inventario.lote_saldo WHERE lote_id = l.id), 0) > 0
  AND NOT EXISTS (   -- not already pulled into a rework child partida
      SELECT 1 FROM mes.partida_componente pc
      JOIN mes.partida p ON p.id = pc.partida_id AND p.partida_origen_id IS NOT NULL
      WHERE pc.lote_id = l.id);

GRANT SELECT ON mes.vw_pendiente_reproceso TO authenticated;


-- ── (E) anular_devolucion_cliente — revert REPROCESO on undo ───────────────────
--   Only ADD the estado_calidad revert; the rest of the function is unchanged from
--   funciones/devoluciones.sql. (CREATE OR REPLACE reproduces the full current body.)
CREATE OR REPLACE FUNCTION doc.anular_devolucion_cliente(p_entrega_id BIGINT)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'iam', 'notification', 'public', 'doc', 'inventario'
AS $function$
DECLARE
    v_message text; v_detail text; v_hint text; v_context text; v_sqlstate text;
    v_usr_id        int := get_user_id();
    v_entrega       RECORD;
    v_reversal_tipo SMALLINT;
    v_doc_mov_id    BIGINT;
    v_mov_count     INT;
    v_error_payload jsonb;
BEGIN
    IF NOT jwt_has_permission('comercial.editar') THEN
        RAISE EXCEPTION 'Sin permiso: se requiere comercial.editar' USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT gr.id, gr.fyh_elm, grt.codigo AS tipo_codigo INTO v_entrega
    FROM doc.entrega gr JOIN doc.entrega_tipo grt ON grt.id = gr.entrega_tipo_id
    WHERE gr.id = p_entrega_id FOR UPDATE OF gr;

    IF NOT FOUND THEN RAISE EXCEPTION 'Guía #% no encontrada.', p_entrega_id; END IF;
    IF v_entrega.tipo_codigo NOT IN ('DEVOLUCION_CLIENTE_SERVICIO', 'DEVOLUCION_CLIENTE_VENTA') THEN
        RAISE EXCEPTION 'Guía #% no es una devolución de cliente (tipo %); use doc.anular_entrega.', p_entrega_id, v_entrega.tipo_codigo;
    END IF;
    IF v_entrega.fyh_elm IS NOT NULL THEN RAISE EXCEPTION 'Guía #% ya está anulada.', p_entrega_id; END IF;

    -- Guard: lote must not have moved again since this devolución
    SELECT jsonb_agg(jsonb_build_object('lote_id', ei.lote_id)) INTO v_error_payload
    FROM (SELECT DISTINCT im.lote_id, im.id FROM inventario.item_movimientos im
          WHERE im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id) ei
    WHERE EXISTS (SELECT 1 FROM inventario.item_movimientos im2
                  WHERE im2.lote_id = ei.lote_id AND im2.id > ei.id
                    AND NOT (im2.documento_tipo = 'entrega' AND im2.documento_id = p_entrega_id));
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'No se puede anular la devolución #%: uno o más rollos devueltos ya tienen movimientos posteriores.', p_entrega_id
            USING DETAIL = v_error_payload::text;
    END IF;

    -- CHANGE (2026-07-29, §3.5 correction): the guard above only sees item_movimientos,
    -- but crear_reproceso moves a lote via mes.partida_componente reassignment, not a
    -- movement — so a roll already pulled into a rework partida would pass the check
    -- above undetected. Block it via current partida_componente state instead. (The full
    -- historical partida_componente_movimiento ledger, for immediate-source genealogy on
    -- reversal, stays deferred — this only needs current assignment.)
    SELECT jsonb_agg(jsonb_build_object('lote_id', ed.lote_id, 'rework_partida_id', pc.partida_id))
    INTO v_error_payload
    FROM doc.entrega_detalle ed
    JOIN mes.partida_componente pc ON pc.lote_id = ed.lote_id
    JOIN mes.partida p ON p.id = pc.partida_id AND p.partida_origen_id IS NOT NULL
    WHERE ed.entrega_id = p_entrega_id AND p.estado_produccion <> 'CANCELADA';

    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION 'No se puede anular la devolución #%: uno o más rollos ya fueron movidos a una partida de reproceso.', p_entrega_id
            USING DETAIL = v_error_payload::text;
    END IF;

    SELECT id INTO v_reversal_tipo FROM inventario.item_movimiento_tipo
    WHERE codigo = CASE v_entrega.tipo_codigo
        WHEN 'DEVOLUCION_CLIENTE_VENTA'    THEN 'DEV_CLI_ING_REV'
        WHEN 'DEVOLUCION_CLIENTE_SERVICIO' THEN 'SERV_DEV_ING_REV' END;

    INSERT INTO logs_api(function_name, user_id, params)
    VALUES ('anular_devolucion_cliente', v_usr_id, jsonb_build_object('entrega_id', p_entrega_id));

    SELECT nextval('inventario.mov_doc_seq') INTO v_doc_mov_id;

    INSERT INTO inventario.item_movimientos(
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora,
        documento_tipo, documento_id, observacion)
    SELECT v_doc_mov_id, im.item_id, im.lote_id, v_reversal_tipo,
           im.destino_ubicacion_id, im.origen_ubicacion_id, im.cantidad, NOW(),
           'entrega', p_entrega_id, 'ANULACION devolución #' || p_entrega_id
    FROM inventario.item_movimientos im
    WHERE im.documento_tipo = 'entrega' AND im.documento_id = p_entrega_id;
    GET DIAGNOSTICS v_mov_count = ROW_COUNT;

    -- CHANGE: the roll is re-dispatched (return undone) → it was APROBADO when it shipped.
    UPDATE inventario.lote SET estado_calidad = 'APROBADO', usr_mod = v_usr_id, fyh_mod = now()
    WHERE id IN (SELECT lote_id FROM doc.entrega_detalle WHERE entrega_id = p_entrega_id)
      AND estado_calidad = 'REPROCESO';

    UPDATE doc.entrega SET usr_elm = v_usr_id, fyh_elm = NOW() WHERE id = p_entrega_id;

    PERFORM doc.recompute_estado_comercial(root.root_id)
    FROM (SELECT DISTINCT COALESCE(p.partida_origen_id, p.id) AS root_id
          FROM doc.entrega_detalle ed
          JOIN inventario.lote l ON l.id = ed.lote_id
          JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
          JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
          JOIN mes.partida p ON p.id = pp.partida_id
          WHERE ed.entrega_id = p_entrega_id) root;

    RETURN format('Devolución #%s anulada. %s movimiento(s) revertido(s).', p_entrega_id, v_mov_count);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_detail=PG_EXCEPTION_DETAIL,
        v_hint=PG_EXCEPTION_HINT, v_context=PG_EXCEPTION_CONTEXT, v_sqlstate=RETURNED_SQLSTATE;
    RAISE LOG 'Error in anular_devolucion_cliente - User: %, entrega: %, Error: %', v_usr_id, p_entrega_id, v_message;
    RAISE;
END;
$function$;

-- ROLLBACK;  -- review first
-- COMMIT;

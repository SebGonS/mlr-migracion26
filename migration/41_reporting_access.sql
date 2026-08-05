-- ═══════════════════════════════════════════════════════════════
-- Step 41: Reporting access — Power BI read-only role + supporting index
-- ---------------------------------------------------------------------
-- Purpose: let a BI tool (Power BI, Import mode) read the `reporte` schema
-- and NOTHING else, without weakening RLS on the app's base tables.
--
-- Why this is safe:
--   * `reporte.*` views are owned by `postgres`, which has BYPASSRLS. With
--     the default view semantics (security_invoker = false), RLS on the
--     underlying tables is evaluated against the view OWNER, not the caller
--     → the reader gets rows, but only the columns the view projects.
--   * `powerbi_reader` is granted SELECT on the `reporte` schema ONLY. It has
--     no access to mes/inventario/doc/public base tables, and it is NOT a
--     Supabase PostgREST role, so the anon/public API cannot reach it.
--   * The `reporte` schema is intentionally NOT added to Supabase's
--     "Exposed schemas" → unreachable via the REST/anon key path the client
--     used before. Power BI connects with the Postgres connector instead.
--
-- Connection for Power BI: Postgres connector, direct connection / session
-- pooler (port 5432), database user `powerbi_reader`. Use Import mode with a
-- scheduled refresh (NOT DirectQuery) so prod sees only a few queries a day.
--
-- DEPENDS ON: 01 (reporte schema).
-- ═══════════════════════════════════════════════════════════════

-- ── 0. reporte.vw_matizado — BI fact for shade-correction (matizado) events
-- ---------------------------------------------------------------------
-- Legacy equivalent: public.vw_matizado (fed Power BI). In the new schema
-- there is no `matizado` table — a matizado is an insumo egress to
-- production (motivo MATIZADO) against a partida_paso_ejecucion in the
-- central ledger. This view IS the reporting contract: flat, typed, one
-- row per movement event. Owned by postgres → bypasses RLS for the
-- read-only `powerbi_reader` role. Consumed in Power BI Import mode; do
-- NOT pre-aggregate or bake client/article buckets here — that modelling
-- belongs in Power BI (DAX + dimensions).
--
-- Signing: consumo rows have item_movimiento_tipo.factor = -1, reversal
-- rows (from corregir_matizado) have factor = +1. `cantidad`/`costo` are
-- signed by (-factor) so consumo is positive, reversal negative → a plain
-- SUM already nets every correction to the true total — this is the ONLY
-- mechanism needed for correct numbers; nothing else in this view is
-- required for that to work.
--
-- No es_reversion / reversion_movimiento_id columns: those were considered
-- and dropped. They exist on inventario.item_movimientos (see migration/40b)
-- for ledger-level audit drill-down, but a Power BI cost/consumption report
-- doesn't need them — SUM(cantidad)/SUM(costo) is already correct without
-- inspecting them, and exposing raw original+reversal rows here only
-- invites confusion if someone drops rows into a table without aggregating.
-- Legacy's `matizado` table (public.matizado) had no correction tracking at
-- all — mistakes were just UPDATEd/DELETEd in place, no trace kept. These
-- columns are new to the append-only ledger design, not a legacy carryover
-- — and since they're not needed for this report's numbers, they're left
-- out of the BI-facing view entirely. If a future audit/drill-down report
-- ever needs them, query inventario.item_movimientos directly rather than
-- widening this view.
--
-- Costing: each event is valued at its point-in-time m.precio_unitario
-- (ledger snapshot), NOT a current average — strictly more accurate than
-- the legacy view's insumo.precio_prom_kg_usd.
CREATE SCHEMA IF NOT EXISTS reporte;
CREATE OR REPLACE VIEW reporte.vw_matizado AS
SELECT
    m.id                                                  AS movimiento_id,
    DATE(m.fecha_hora AT TIME ZONE 'America/Lima')        AS fecha,
    m.fecha_hora                                          AS fyh_movimiento,
    CASE WHEN EXTRACT(HOUR FROM m.fecha_hora AT TIME ZONE 'America/Lima') BETWEEN 7 AND 18
         THEN 'DIA' ELSE 'NOCHE' END                      AS turno,
    ppe.id                                                AS ejecucion_id,
    p.id                                                  AS partida_id,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    (p.partida_origen_id IS NOT NULL)                     AS es_reproceso,
    c.nombre                                              AS cliente,
    at.nombre                                             AS articulo_tipo,
    ga.nombre                                             AS grupo_articulo,
    ten.tenido                                            AS tenido,
    col.color                                             AS color,
    o.nombre                                              AS operacion,
    o.codigo                                              AS operacion_codigo,
    mq.nombre                                             AS maquina,
    i.codigo                                              AS insumo_codigo,
    i.nombre                                              AS insumo,
    u.codigo                                              AS unidad,
    ROUND((m.cantidad * (-t.factor))::numeric, 5)         AS cantidad,
    m.precio_unitario,
    ROUND((m.cantidad * (-t.factor) * COALESCE(m.precio_unitario, 0))::numeric, 4) AS costo
FROM inventario.item_movimientos m
JOIN inventario.item_movimiento_tipo   t  ON t.id  = m.item_movimiento_tipo_id
JOIN inventario.item_movimiento_motivo mo ON mo.id = m.motivo_id AND mo.codigo = 'MATIZADO'
JOIN item   i ON i.id = m.item_id
JOIN unidad u ON u.id = i.unidad_id
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = m.documento_id
                                    AND m.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.partida      p  ON p.id  = pp.partida_id
JOIN mes.operacion    o  ON o.id  = pp.operacion_id
LEFT JOIN mes.maquina      mq  ON mq.id  = ppe.maquina_id
LEFT JOIN tercero          c   ON c.id   = p.tercero_id
LEFT JOIN articulo_tipo    at  ON at.id  = p.articulo_tipo_id
LEFT JOIN grupo_articulo   ga  ON ga.id  = p.grupo_articulo_id
LEFT JOIN tenido           ten ON ten.id = p.tenido_id
LEFT JOIN vw_colores       col ON col.color_x_cliente_id = p.color_x_cliente_id;

-- ── 1. Read-only login role ───────────────────────────────────────────
-- The password here is a placeholder ONLY. Do NOT commit a real secret.
-- After running this file, set a strong password out-of-band (Supabase SQL
-- editor or psql), e.g.:
--     ALTER ROLE powerbi_reader PASSWORD '<generated-secret>';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_reader') THEN
        CREATE ROLE powerbi_reader LOGIN PASSWORD 'CHANGE_ME_SET_IN_SUPABASE';
    END IF;
END $$;



-- Belt-and-suspenders: this role must never inherit app privileges.
REVOKE ALL ON SCHEMA mes, inventario, doc, calidad, receta, public FROM powerbi_reader;

-- ── 2. Grant exactly the reporting contract ───────────────────────────
GRANT USAGE ON SCHEMA reporte TO powerbi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA reporte TO powerbi_reader;
-- Future reporte views are readable automatically.
ALTER DEFAULT PRIVILEGES IN SCHEMA reporte GRANT SELECT ON TABLES TO powerbi_reader;

-- ── 3. Supporting index for reporte.vw_matizado ────────────────────────
-- Matizado is a tiny slice of the ledger; this composite index keeps the
-- view's motivo filter + date range cheap on every refresh, so a plain
-- (non-materialized) view is performant enough. Escalate to a materialized
-- view only if a measured refresh actually proves slow.
--
-- Composite (motivo_id, fecha_hora): the planner seeks the MATIZADO motivo
-- then range-scans by date. A partial index is NOT used here because its
-- predicate cannot contain a subquery to resolve the motivo id, and the
-- motivo id is environment-specific (not a safe literal to hardcode).
--
-- NOTE: on a live DB prefer CREATE INDEX CONCURRENTLY (cannot run inside a
-- transaction block). If applying this file transactionally, run the
-- concurrent form separately:
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_im_motivo_fecha
--     ON inventario.item_movimientos (motivo_id, fecha_hora);
CREATE INDEX IF NOT EXISTS idx_im_motivo_fecha
    ON inventario.item_movimientos (motivo_id, fecha_hora);

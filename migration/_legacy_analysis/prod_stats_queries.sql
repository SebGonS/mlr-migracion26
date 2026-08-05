-- =====================================================================
-- Legacy-baseline analysis: 3 read-only production probes
-- Safe: reads only catalog + stats views. No writes, no heavy locks.
-- Run each block, export result (CSV or raw), paste back.
-- App schemas of interest:
--   public, doc, mes, inventario, receta, calidad, iam,
--   notification, alertas, audit, migration
-- =====================================================================


-- ---------------------------------------------------------------------
-- QUERY 1 — Size, live rows, and scan traffic per table
-- Answers: is this table populated? is it ever read/written?
--   seq_scan+idx_scan = 0  AND  n_live_tup = 0  => strong "dead" signal
-- ---------------------------------------------------------------------
SELECT
    s.schemaname,
    s.relname                                   AS table_name,
    s.n_live_tup                                AS live_rows,
    s.n_dead_tup                                AS dead_rows,
    s.seq_scan,
    s.idx_scan,
    (COALESCE(s.seq_scan,0) + COALESCE(s.idx_scan,0)) AS total_reads,
    s.n_tup_ins                                 AS inserts,
    s.n_tup_upd                                 AS updates,
    s.n_tup_del                                 AS deletes,
    s.last_autovacuum,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_stat_user_tables s
JOIN pg_class c     ON c.oid = (quote_ident(s.schemaname)||'.'||quote_ident(s.relname))::regclass
WHERE s.schemaname IN
    ('public','doc','mes','inventario','receta','calidad',
     'iam','notification','alertas','audit','migration')
ORDER BY s.schemaname, total_reads ASC, s.n_live_tup ASC;


-- ---------------------------------------------------------------------
-- QUERY 2 — Most-recent write per table (via audit columns)
-- Answers: when was this table last touched? A "legacy" table still
-- receiving writes recently is NOT legacy.
-- This block GENERATES a SQL statement; run it, then run its output.
-- (Handles tables with fyh_mod and/or fyh_cre; skips tables with neither.)
-- ---------------------------------------------------------------------
SELECT string_agg(stmt, E'\nUNION ALL\n' ORDER BY schemaname, tablename) || E'\nORDER BY last_write DESC NULLS LAST;'
FROM (
    SELECT
        t.table_schema AS schemaname,
        t.table_name   AS tablename,
        format(
            'SELECT %L AS schemaname, %L AS tablename, max(%s) AS last_write FROM %I.%I',
            t.table_schema, t.table_name,
            CASE
                WHEN bool_or(c.column_name = 'fyh_mod') AND bool_or(c.column_name = 'fyh_cre')
                    THEN 'GREATEST(fyh_mod, fyh_cre)'
                WHEN bool_or(c.column_name = 'fyh_mod') THEN 'fyh_mod'
                ELSE 'fyh_cre'
            END,
            t.table_schema, t.table_name
        ) AS stmt
    FROM information_schema.tables t
    JOIN information_schema.columns c
      ON c.table_schema = t.table_schema AND c.table_name = t.table_name
    WHERE t.table_type = 'BASE TABLE'
      AND t.table_schema IN
          ('public','doc','mes','inventario','receta','calidad',
           'iam','notification','alertas','audit','migration')
      AND c.column_name IN ('fyh_cre','fyh_mod')
    GROUP BY t.table_schema, t.table_name
) q;
-- >>> Copy the single returned string, run it as a query, paste THAT result.


-- ---------------------------------------------------------------------
-- QUERY 3 — Tables/functions actually referenced in executed queries
-- Answers: what has the running application actually touched?
-- Substitute for the app-code grep. Requires pg_stat_statements (present
-- in this DB). Only covers since last stats reset, but any hit = "in use".
-- ---------------------------------------------------------------------
-- 3a: does the view exist / how much history do we have?
SELECT count(*) AS statement_count,
       (SELECT stats_reset FROM pg_stat_statements_info) AS stats_since
FROM extensions.pg_stat_statements;

-- 3b: raw query texts (we'll parse table refs offline).
--     Filter out noise from platform schemas by keeping app-ish text.
SELECT queryid, calls, query
FROM extensions.pg_stat_statements
WHERE query ~* '\y(doc|mes|inventario|receta|calidad|iam|notification|alertas|audit)\.'
   OR query ~* '\yfrom\s+(item|tercero|partida|compra|venta|factura|entrega|lote|produccion|despacho|receta)'
ORDER BY calls DESC
LIMIT 2000;

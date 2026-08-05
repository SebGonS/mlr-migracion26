-- ============================================================================
-- DIAGNOSTIC · Roll (lote) lifecycle status — READ ONLY
-- ============================================================================
-- Purpose: reconstruct the CURRENT state of every roll lote and its movements
-- so we can see what the migration has/hasn't normalized — headers (origin),
-- consumption, production output, and dispatch — without recalling which
-- one-off scripts ran. Every section is a standalone SELECT; run top to bottom
-- and paste results. NOTHING here writes.
--
-- Reference lifecycle migration-11 intended to build (11_data_migration §2346):
--   raw lote (flg_tenido=false, doc=PARTIDA)
--     → SERV_ING   (received, doc=PARTIDA)          -- ingress header
--     → PROD_CONSUMO (consumed, doc=partida_paso)   -- consumption
--     → PROD_ING   (dyed child, flg_tenido=true)    -- production output (origen_lote_id→parent)
--     → SERV_EGR   (dispatched to client)           -- outbound
-- "Normalized" target: ingress lives on a doc.entrega (not PARTIDA); consumption
-- on partida_paso_ejecucion; output child carries origen_lote_id; dispatch on an
-- outbound (emitida) delivery — NOT on PARTIDA.
--
-- go-live cutoff (migration vs app data): '2026-05-25 15:27:52+00'::timestamptz
-- ============================================================================


-- ── §A · Lote population: origin doc × raw/dyed × era ─────────────────────────
-- The big picture. documento_tipo is GROUPED (not filtered) so real values surface.
SELECT
    l.documento_tipo,
    COALESCE(lrd.flg_tenido::text, '(no lrd)')                       AS dyed,
    lrd.origen_lote_id IS NOT NULL                                   AS has_parent,
    (l.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz)             AS migration_era,
    COUNT(*)                                                         AS lotes
FROM inventario.lote l
LEFT JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
GROUP BY 1, 2, 3, 4
ORDER BY lotes DESC;


-- ── §B · Ingress header / billing-anchor state (input rolls) ──────────────────
-- Input rolls (flg_tenido=false) should sit on a doc.entrega with entrega_id set.
SELECT
    l.documento_tipo,
    (lrd.entrega_id IS NOT NULL)          AS anchor_set,
    COUNT(*)                              AS lotes
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
WHERE lrd.flg_tenido = false
GROUP BY 1, 2
ORDER BY lotes DESC;


-- ── §C · Movement type × documento_tipo cross-tab ─────────────────────────────
-- Reveals mis-tags: e.g. SERV_EGR sitting on PARTIDA (should be an outbound doc),
-- PROD_CONSUMO/PROD_ING not on partida_paso_ejecucion, SERV_ING not on entrega.
SELECT
    imt.codigo                                                              AS mov_tipo,
    COUNT(*) FILTER (WHERE im.documento_tipo = 'PARTIDA')                   AS on_partida,
    COUNT(*) FILTER (WHERE im.documento_tipo = 'entrega')                   AS on_entrega,
    COUNT(*) FILTER (WHERE im.documento_tipo = 'partida_paso_ejecucion')    AS on_pp_ejec,
    COUNT(*) FILTER (WHERE im.documento_tipo NOT IN
                       ('PARTIDA','entrega','partida_paso_ejecucion')
                     OR im.documento_tipo IS NULL)                          AS on_other,
    COUNT(*)                                                                AS total
FROM inventario.item_movimientos im
JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
GROUP BY imt.codigo
ORDER BY total DESC;




WITH ins AS (
  SELECT pc.partida_id, COUNT(*) AS raw_in
  FROM mes.partida_componente pc
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id AND lrd.flg_tenido = false
  WHERE pc.lote_id IS NOT NULL
  GROUP BY pc.partida_id
),
outs AS (
  SELECT pp.partida_id, COUNT(*) AS dyed_out
  FROM inventario.lote l
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
  JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
  JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
  GROUP BY pp.partida_id
)
SELECT COUNT(*)                                                              AS partidas_with_dyed_output,
       COUNT(*) FILTER (WHERE COALESCE(raw_in,0) = dyed_out)                 AS counts_match,
       COUNT(*) FILTER (WHERE COALESCE(raw_in,0) <> dyed_out AND COALESCE(raw_in,0) > 0) AS counts_differ,
       COUNT(*) FILTER (WHERE COALESCE(raw_in,0) = 0)                        AS no_raw_input
FROM outs o
LEFT JOIN ins i USING (partida_id);






WITH ins AS (
  SELECT pc.partida_id, COUNT(*) AS raw_in
  FROM mes.partida_componente pc
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id AND lrd.flg_tenido = false
  WHERE pc.lote_id IS NOT NULL
  GROUP BY pc.partida_id
),
outs AS (
  SELECT pp.partida_id, COUNT(*) AS dyed_out
  FROM inventario.lote l
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
  JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
  JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
  GROUP BY pp.partida_id
)
SELECT o.dyed_out - COALESCE(i.raw_in,0) AS out_minus_in, COUNT(*) AS partidas
FROM outs o LEFT JOIN ins i ON i.partida_id = o.partida_id
GROUP BY 1 ORDER BY partidas DESC;


WITH consumed AS (
  SELECT pp.partida_id, COUNT(DISTINCT im.lote_id) AS raw_consumed
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = false
  JOIN mes.partida_paso_ejecucion ppe ON ppe.id = im.documento_id AND im.documento_tipo = 'partida_paso_ejecucion'
  JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
  GROUP BY pp.partida_id
),
produced AS (
  SELECT pp.partida_id, COUNT(*) AS dyed_produced
  FROM inventario.lote l
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
  JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
  JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
  GROUP BY pp.partida_id
)
SELECT COUNT(*)                                                            AS partidas,
       COUNT(*) FILTER (WHERE COALESCE(c.raw_consumed,0) = p.dyed_produced)  AS counts_match,
       COUNT(*) FILTER (WHERE COALESCE(c.raw_consumed,0) < p.dyed_produced)  AS consumed_short,
       COUNT(*) FILTER (WHERE COALESCE(c.raw_consumed,0) > p.dyed_produced)  AS consumed_extra,
       COUNT(*) FILTER (WHERE c.raw_consumed IS NULL)                        AS no_consumo_at_all
FROM produced p
LEFT JOIN consumed c ON c.partida_id = p.partida_id;





SELECT (p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz) AS partida_is_legacy,
       (l.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz) AS lote_is_legacy,
       COUNT(*) AS dyed_orphan_lotes
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
GROUP BY 1, 2;

WITH ejec_out AS (
  SELECT l.documento_id AS ejec_id, COUNT(*) AS out_lotes, SUM(l.cantidad) AS out_peso
  FROM inventario.lote l
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true
  WHERE l.documento_tipo = 'partida_paso_ejecucion'
  GROUP BY l.documento_id
)
SELECT COUNT(*)                                                          AS ejecs_with_output,
       COUNT(*) FILTER (WHERE eo.out_lotes  = ppe.cantidad_rollos)       AS count_matches,
       COUNT(*) FILTER (WHERE eo.out_lotes  > ppe.cantidad_rollos)       AS count_OVERFLOW,
       COUNT(*) FILTER (WHERE eo.out_lotes  < ppe.cantidad_rollos)       AS count_under,
       round(SUM(abs(eo.out_peso - ppe.peso_kg))::numeric, 2)            AS total_peso_drift
FROM ejec_out eo
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = eo.ejec_id;


WITH ins AS (
  SELECT pc.partida_id, COUNT(*) AS raw_in
  FROM mes.partida_componente pc
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = pc.lote_id AND lrd.flg_tenido = false
  WHERE pc.lote_id IS NOT NULL
  GROUP BY pc.partida_id
),
outs AS (
  SELECT pp.partida_id, COUNT(*) AS dyed_out
  FROM inventario.lote l
  JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
  JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
  JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
  GROUP BY pp.partida_id
)
SELECT (p.partida_origen_id IS NOT NULL)                                       AS is_rework,
       COUNT(*)                                                                AS partidas,
       COUNT(*) FILTER (WHERE COALESCE(i.raw_in,0) = o.dyed_out)               AS counts_match,
       COUNT(*) FILTER (WHERE COALESCE(i.raw_in,0) <> o.dyed_out)              AS counts_differ
FROM outs o
LEFT JOIN ins i ON i.partida_id = o.partida_id
JOIN mes.partida p ON p.id = o.partida_id
GROUP BY 1;






WITH per_ejec AS (
  SELECT im.documento_id AS ejec_id,
    COUNT(*) FILTER (WHERE imt.codigo='PROD_CONSUMO') AS consumed_in,
    COUNT(*) FILTER (WHERE imt.codigo='PROD_ING')     AS produced_out
  FROM inventario.item_movimientos im
  JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
  WHERE im.documento_tipo = 'partida_paso_ejecucion'
    AND imt.codigo IN ('PROD_CONSUMO','PROD_ING')
  GROUP BY im.documento_id
)
SELECT COUNT(*) AS ejecs,
       COUNT(*) FILTER (WHERE consumed_in = produced_out)  AS counts_match,
       COUNT(*) FILTER (WHERE consumed_in <> produced_out) AS counts_differ,
       COUNT(*) FILTER (WHERE produced_out = 0)            AS no_output,
       COUNT(*) FILTER (WHERE consumed_in = 0)             AS no_input
FROM per_ejec;


-- ── §D · Per-roll movement signature (lifecycle completeness) ─────────────────
-- Each roll's DISTINCT movement codes, bucketed. A healthy input roll that ran
-- the full cycle shows e.g. 'PROD_CONSUMO+SERV_EGR+SERV_ING'; '(none)' = a lote
-- with zero movements (dead weight); a bare 'SERV_ING' = received, never processed.
WITH sig AS (
    SELECT l.id AS lote_id,
           COALESCE(lrd.flg_tenido::text, '(no lrd)') AS dyed,
           string_agg(DISTINCT imt.codigo, '+' ORDER BY imt.codigo) AS moves
    FROM inventario.lote l
    LEFT JOIN inventario.lote_rollo_detalle  lrd ON lrd.lote_id = l.id
    LEFT JOIN inventario.item_movimientos    im  ON im.lote_id  = l.id
    LEFT JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY l.id, lrd.flg_tenido
)
SELECT dyed,
       COALESCE(moves, '(none)') AS movement_signature,
       COUNT(*)                  AS lotes
FROM sig
GROUP BY dyed, moves
ORDER BY lotes DESC;


-- ── §E · Anomaly detectors (each row = a problem bucket; 0 = clean) ───────────
WITH mv AS (   -- per-lote movement-type presence flags
    SELECT im.lote_id,
           bool_or(imt.codigo IN ('SERV_ING','COMPRA_ING','PROD_ING','DEV_CLI_ING')) AS has_ingreso,
           bool_or(imt.codigo = 'PROD_CONSUMO')                                       AS has_consumo,
           bool_or(imt.codigo = 'PROD_ING')                                           AS has_prod_ing,
           bool_or(imt.codigo = 'SERV_EGR')                                           AS has_dispatch,
           COUNT(*)                                                                   AS n_mov
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    GROUP BY im.lote_id
)
SELECT * FROM (
    SELECT 1 AS ord, 'lote missing lote_rollo_detalle (invariant violation)' AS anomaly,
           COUNT(*) AS n
    FROM inventario.lote l
    WHERE NOT EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle x WHERE x.lote_id = l.id)
  UNION ALL
    SELECT 2, 'lote with ZERO movements',
           COUNT(*)
    FROM inventario.lote l LEFT JOIN mv ON mv.lote_id = l.id
    WHERE mv.lote_id IS NULL
  UNION ALL
    SELECT 3, 'input roll (flg_tenido=false) with NO ingreso movement',
           COUNT(*)
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = false
    LEFT JOIN mv ON mv.lote_id = l.id
    WHERE COALESCE(mv.has_ingreso, false) = false
  UNION ALL
    SELECT 4, 'input roll still on documento_tipo=PARTIDA (un-normalized header)',
           COUNT(*)
    FROM inventario.lote l
    WHERE l.documento_tipo = 'PARTIDA'
  UNION ALL
    SELECT 5, 'input roll on entrega but entrega_id anchor NULL',
           COUNT(*)
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    WHERE l.documento_tipo = 'entrega' AND lrd.entrega_id IS NULL
  UNION ALL
    SELECT 6, 'dyed roll (flg_tenido=true) with origen_lote_id NULL (no parent link)',
           COUNT(*)
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id
    WHERE lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
  UNION ALL
    SELECT 7, 'SERV_EGR (dispatch) NOT on an outbound doc — still on PARTIDA/pp_ejec',
           COUNT(*)
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE imt.codigo = 'SERV_EGR'
      AND (im.documento_tipo IN ('PARTIDA','partida_paso_ejecucion') OR im.documento_tipo IS NULL)
  UNION ALL
    SELECT 8, 'consumed roll (PROD_CONSUMO) that is NOT dyed and has no dyed child',
           COUNT(*)
    FROM inventario.lote l
    JOIN mv ON mv.lote_id = l.id AND mv.has_consumo
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = false
    WHERE NOT EXISTS (SELECT 1 FROM inventario.lote_rollo_detalle c WHERE c.origen_lote_id = l.id)
) t
ORDER BY ord;


-- ── §F · Current stock position (where the rolls physically are) ──────────────
-- Location = destino of each roll's LAST movement; egress-last → out of stock.
WITH last_mov AS (
    SELECT DISTINCT ON (im.lote_id)
           im.lote_id, im.destino_ubicacion_id, imt.codigo AS last_code, imt.factor
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    ORDER BY im.lote_id, im.fecha_hora DESC, im.id DESC
)
SELECT
    COALESCE(a.codigo, CASE WHEN lm.lote_id IS NULL THEN '(no movements)'
                            ELSE '(dispatched / out)' END)  AS ubicacion_actual,
    COUNT(*)                                                AS lotes
FROM inventario.lote l
LEFT JOIN last_mov lm            ON lm.lote_id = l.id
LEFT JOIN inventario.ubicacion u ON u.id = lm.destino_ubicacion_id
LEFT JOIN inventario.almacen   a ON a.id = u.almacen_id
GROUP BY 1
ORDER BY lotes DESC;



SELECT l.documento_tipo, COUNT(*) AS lotes,
       COUNT(*) FILTER (WHERE e.id IS NULL) AS documento_id_unresolved
FROM inventario.lote l
LEFT JOIN doc.entrega e ON e.id = l.documento_id
WHERE l.documento_tipo IN ('GUIA_REMISION','guia_remision','entrega')
GROUP BY 1
UNION ALL
SELECT l.documento_tipo, COUNT(*),
       COUNT(*) FILTER (WHERE c.id IS NULL)
FROM inventario.lote l
LEFT JOIN inventario.cuadre c ON c.id = l.documento_id
WHERE l.documento_tipo IN ('CUADRE','cuadre')
GROUP BY 1;



SELECT e.serie,
       COUNT(*)                                              AS entregas,
       COUNT(*) FILTER (WHERE e.correlativo ~ '^[0-9]+$')    AS corr_numeric,
       COUNT(*) FILTER (WHERE e.correlativo !~ '^[0-9]+$')   AS corr_nonnumeric,
       (array_agg(e.correlativo ORDER BY e.id))[1:6]         AS sample_correlativos
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
WHERE et.codigo = 'CLIENTE_ENVIO_PROCESO'
GROUP BY e.serie
ORDER BY entregas DESC;


WITH g AS (
    SELECT NULLIF(TRIM(pub.guia), '') AS guia, COUNT(DISTINCT mp.id) AS partidas
    FROM mes.partida mp
    JOIN public.partida pub ON pub.id = mp.id
    WHERE EXISTS (SELECT 1 FROM inventario.lote l
                  WHERE l.documento_tipo = 'PARTIDA' AND l.documento_id = mp.id)
    GROUP BY 1
),
d AS (
    SELECT guia, partidas,
        CASE
            WHEN guia IS NULL OR upper(guia)='NULL' OR guia ~ '^[0\- ]+$' THEN 'headless'
            WHEN guia ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'                   THEN 'isolated_dash'
            WHEN guia ~ '^[A-Za-z]+[0-9]+$'                               THEN 'isolated_alnum'
            ELSE 'dumped_00'
        END AS bucket,
        CASE
            WHEN guia IS NULL OR upper(guia)='NULL' OR guia ~ '^[0\- ]+$' THEN NULL
            WHEN guia ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'                   THEN split_part(guia,'-',1)
            WHEN guia ~ '^[A-Za-z]+[0-9]+$'        THEN (regexp_match(guia,'^([A-Za-z]+)([0-9]+)$'))[1]
            ELSE '00'
        END AS d_serie,
        CASE
            WHEN guia IS NULL OR upper(guia)='NULL' OR guia ~ '^[0\- ]+$' THEN NULL
            WHEN guia ~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'                   THEN split_part(guia,'-',2)
            WHEN guia ~ '^[A-Za-z]+[0-9]+$'        THEN (regexp_match(guia,'^([A-Za-z]+)([0-9]+)$'))[2]
            ELSE guia
        END AS d_correlativo
    FROM g
)
-- (reuse the WITH g/d CTE from the last query, then:)
SELECT bucket, guia, d_serie, d_correlativo, partidas
FROM d WHERE bucket IN ('isolated_dash','isolated_alnum')
ORDER BY bucket, partidas DESC;

-- ② run separately: eyeball the mapping, esp. the isolated_* buckets to catch mis-splits
-- SELECT bucket, guia, d_serie, d_correlativo, partidas FROM d ORDER BY bucket, partidas DESC LIMIT 120;



BEGIN;

-- lote: collapse the entrega-concept variants → canonical 'entrega'
UPDATE inventario.lote
SET    documento_tipo = 'entrega'
WHERE  documento_tipo IN ('GUIA_REMISION','guia_remision');   -- ~7,084 rows

-- lote: cuadre casing → canonical 'cuadre'
UPDATE inventario.lote
SET    documento_tipo = 'cuadre'
WHERE  documento_tipo = 'CUADRE';                             -- ~332 rows

-- same relabel on the ledger
UPDATE inventario.item_movimientos
SET    documento_tipo = 'entrega'
WHERE  documento_tipo IN ('GUIA_REMISION','guia_remision');

UPDATE inventario.item_movimientos
SET    documento_tipo = 'cuadre'
WHERE  documento_tipo = 'CUADRE';

-- verify: these should all be 0 after
  SELECT COUNT(*) FROM inventario.lote            WHERE documento_tipo IN ('GUIA_REMISION','guia_remision','CUADRE');
  SELECT COUNT(*) FROM inventario.item_movimientos WHERE documento_tipo IN ('GUIA_REMISION','guia_remision','CUADRE');

-- COMMIT;




SELECT COUNT(*) AS total_lotes,
       COUNT(*) FILTER (WHERE documento_tipo = 'PARTIDA') AS on_partida,
       COUNT(*) FILTER (WHERE documento_tipo = 'entrega') AS on_entrega
FROM inventario.lote;
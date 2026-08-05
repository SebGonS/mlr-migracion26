-- ============================================================================
-- BACKFILL · origen_lote_id genealogy for migrated dyed rolls (LEDGER-based)
-- ============================================================================
-- WHAT: migration-11 recorded raw consumption (PROD_CONSUMO) and dyed output
--   (PROD_ING) as movements, but never wrote the output lote's origen_lote_id
--   (the parent-batch link dyed→raw that billing/traceability read). This fills it.
--
-- BASIS: the LEDGER, not partida_componente (which was never rebuilt and counts
--   reserved-but-unconsumed rolls). Verified: for every one of the 1030 in-scope
--   partidas, COUNT(distinct raw consumed) = COUNT(dyed produced), exactly. So the
--   1:1 pairing is REAL, not fabricated — only the specific roll↔roll assignment
--   among fungibles is nominal, and partida-total billing is invariant to it.
--
-- PAIRING: per partida, order raw-consumed and dyed-produced by (weight, id) and
--   pair by rank. Weight-order best approximates the physical roll and naturally
--   groups rib vs regular (they cluster by weight), without trusting a rib flag.
--
-- SCOPE: legacy only (partida.fyh_cre <= go-live). All 19,533 orphan dyed rolls
--   are legacy (verified). Post-go-live app rolls already have origen set and are
--   excluded by the origen_lote_id IS NULL filter AND the cutoff.
--
-- WRITES: inventario.lote_rollo_detalle.origen_lote_id ONLY. Never touches
--   documento_id / ejecucion / quantities / movements.
--
-- ⚠ DRY-RUN §0, run §1, read §2, then COMMIT.
-- ============================================================================

-- reusable pairing CTE (used in §0 and §1) --------------------------------------
--   consumed : distinct raw rolls consumed per partida, ranked by (weight,id)
--   produced : dyed output rolls (origen NULL) per partida, ranked by (weight,id)

-- ── §0 · DRY RUN — scope + integrity ──────────────────────────────────────────
WITH consumed_raw AS (
    SELECT DISTINCT pp.partida_id, im.lote_id AS raw_lote_id, l.cantidad AS raw_peso
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
    JOIN inventario.lote l                    ON l.id = im.lote_id
    JOIN inventario.lote_rollo_detalle lrd    ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = false
    JOIN mes.partida_paso_ejecucion ppe       ON ppe.id = im.documento_id AND im.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp                  ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p                        ON p.id = pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
consumed AS (
    SELECT partida_id, raw_lote_id,
           row_number() OVER (PARTITION BY partida_id ORDER BY raw_peso, raw_lote_id) AS rn
    FROM consumed_raw
),
produced AS (
    SELECT pp.partida_id, l.id AS dyed_lote_id,
           row_number() OVER (PARTITION BY pp.partida_id ORDER BY l.cantidad, l.id) AS rn
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd    ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
    JOIN mes.partida_paso_ejecucion ppe       ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp                  ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p                        ON p.id = pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
)
SELECT
    (SELECT COUNT(DISTINCT partida_id) FROM produced)                       AS partidas,
    (SELECT COUNT(*) FROM produced)                                         AS dyed_to_link,
    (SELECT COUNT(*) FROM produced pr JOIN consumed c
        ON c.partida_id = pr.partida_id AND c.rn = pr.rn)                   AS pairs_found,
    -- pairs_found MUST equal dyed_to_link (every dyed gets exactly one raw)
    (SELECT COUNT(*) FROM produced pr LEFT JOIN consumed c
        ON c.partida_id = pr.partida_id AND c.rn = pr.rn
        WHERE c.raw_lote_id IS NULL)                                        AS dyed_without_pair_expect0;


-- ── §1 · Execute ──────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL statement_timeout = 0;

WITH consumed_raw AS (
    SELECT DISTINCT pp.partida_id, im.lote_id AS raw_lote_id, l.cantidad AS raw_peso
    FROM inventario.item_movimientos im
    JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id AND imt.codigo = 'PROD_CONSUMO'
    JOIN inventario.lote l                    ON l.id = im.lote_id
    JOIN inventario.lote_rollo_detalle lrd    ON lrd.lote_id = im.lote_id AND lrd.flg_tenido = false
    JOIN mes.partida_paso_ejecucion ppe       ON ppe.id = im.documento_id AND im.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp                  ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p                        ON p.id = pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
),
consumed AS (
    SELECT partida_id, raw_lote_id,
           row_number() OVER (PARTITION BY partida_id ORDER BY raw_peso, raw_lote_id) AS rn
    FROM consumed_raw
),
produced AS (
    SELECT l.id AS dyed_lote_id, pp.partida_id,
           row_number() OVER (PARTITION BY pp.partida_id ORDER BY l.cantidad, l.id) AS rn
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd    ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
    JOIN mes.partida_paso_ejecucion ppe       ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
    JOIN mes.partida_paso pp                  ON pp.id = ppe.partida_paso_id
    JOIN mes.partida p                        ON p.id = pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
)
UPDATE inventario.lote_rollo_detalle lrd
SET origen_lote_id = c.raw_lote_id, usr_mod = 4, fyh_mod = now()
FROM produced pr
JOIN consumed c ON c.partida_id = pr.partida_id AND c.rn = pr.rn
WHERE lrd.lote_id = pr.dyed_lote_id;


-- ── §2 · Verify ───────────────────────────────────────────────────────────────
-- (a) no legacy dyed orphan left unlinked — expect ~0
SELECT COUNT(*) AS dyed_orphans_left
FROM inventario.lote l
JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id = l.id AND lrd.flg_tenido = true AND lrd.origen_lote_id IS NULL
JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id AND l.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id AND p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz;

-- (b) every origen we just set points at a RAW lote in the SAME partida — expect 0 bad
SELECT COUNT(*) AS origen_wrong_type_or_partida
FROM inventario.lote_rollo_detalle lrd
JOIN inventario.lote dyed   ON dyed.id = lrd.lote_id AND lrd.flg_tenido = true
JOIN mes.partida_paso_ejecucion dppe ON dppe.id = dyed.documento_id AND dyed.documento_tipo = 'partida_paso_ejecucion'
JOIN mes.partida_paso dpp   ON dpp.id = dppe.partida_paso_id
JOIN inventario.lote_rollo_detalle plrd ON plrd.lote_id = lrd.origen_lote_id  -- parent
WHERE lrd.usr_mod = 4 AND lrd.origen_lote_id IS NOT NULL
  AND (plrd.flg_tenido = true  -- parent should be RAW, not dyed
       OR NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                      JOIN mes.partida_paso_ejecucion e ON e.id = im.documento_id AND im.documento_tipo='partida_paso_ejecucion'
                      WHERE im.lote_id = lrd.origen_lote_id AND e.partida_paso_id = dpp.id));

-- (c) no raw lote assigned as parent to >1 dyed roll within a partida — expect 0
SELECT COUNT(*) AS raw_reused
FROM (
    SELECT origen_lote_id, COUNT(*) n
    FROM inventario.lote_rollo_detalle
    WHERE usr_mod = 4 AND origen_lote_id IS NOT NULL AND flg_tenido = true
    GROUP BY origen_lote_id HAVING COUNT(*) > 1
) x;

-- COMMIT;    -- ← after §2: (a)~0, (b)=0, (c)=0
-- ROLLBACK;  -- ← if anything is off

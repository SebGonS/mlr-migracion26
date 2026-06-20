-- ═══════════════════════════════════════════════════════════════
-- Patch 27: Derive receta.tenido.flg_antipilling from insumo presence
--
-- Before: flg_antipilling was manually set on the recipe header,
-- causing divergence when the flag was true but no antipilling chemical
-- appeared in the recipe steps.
--
-- After: flg_antipilling is recomputed inline in actualizar_tenido and
-- crear_tenido, driven by item_insumo_detalle.flg_antipilling on the
-- chemical item (item 19 — K-ZIME N/A). No hardcoded item IDs anywhere.
--
-- Changes:
--   1. Add flg_antipilling BOOLEAN to item_insumo_detalle
--   2. Tag item 19 (K-ZIME N/A) as the antipilling agent
--   3. Remove flg_antipilling from trg_bu_tenido_immutable column guard
--      (it is now a derived/computed field, not an identity field)
--   4. Backfill all existing recipes
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Add flag to item_insumo_detalle ────────────────────────

ALTER TABLE item_insumo_detalle
    ADD COLUMN IF NOT EXISTS flg_antipilling BOOLEAN NOT NULL DEFAULT false;


-- ── 2. Tag the antipilling chemical ───────────────────────────

UPDATE item_insumo_detalle
SET flg_antipilling = true
WHERE item_id = (
    SELECT id FROM item WHERE codigo = 'I-AUX-K-ZIME-N-A-ANTIPILLING'
);


-- ── 3. Rebuild immutable guard without flg_antipilling ────────

DROP TRIGGER IF EXISTS trg_bu_tenido_immutable ON receta.tenido;

CREATE TRIGGER trg_bu_tenido_immutable
BEFORE UPDATE OF color_x_cliente_id, articulo_tipo_id, fibra, tenido_id, tipo_receta_id
ON receta.tenido
FOR EACH ROW EXECUTE FUNCTION receta.fn_trg_tenido_immutable();


-- ── 4. Backfill all existing recipes ─────────────────────────
-- Step 1: historicize the older recipe in each colliding pair
WITH derived AS (
    SELECT rt.id, rt.fyh_cre,
           rt.color_x_cliente_id, rt.articulo_tipo_id, rt.fibra,
           rt.tenido_id, rt.tipo_receta_id,
           rt.flg_antipilling AS flag_actual,
           EXISTS (
               SELECT 1 FROM receta.tenido_paso tp
               JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
               JOIN item_insumo_detalle iid ON iid.item_id = tpi.item_id
               WHERE tp.receta_id = rt.id AND iid.flg_antipilling = true
           ) AS derived_flag
    FROM receta.tenido rt
    WHERE rt.flg_produccion = true
),
colliding_pairs AS (
    SELECT CASE WHEN d.fyh_cre < correct.fyh_cre THEN d.id ELSE correct.id END AS historicize_id
    FROM derived d
    JOIN derived correct
      ON correct.id != d.id
     AND correct.color_x_cliente_id IS NOT DISTINCT FROM d.color_x_cliente_id
     AND correct.articulo_tipo_id   IS NOT DISTINCT FROM d.articulo_tipo_id
     AND correct.fibra              IS NOT DISTINCT FROM d.fibra
     AND correct.tenido_id          IS NOT DISTINCT FROM d.tenido_id
     AND correct.tipo_receta_id     IS NOT DISTINCT FROM d.tipo_receta_id
     AND correct.flag_actual = d.derived_flag
    WHERE d.flag_actual != d.derived_flag
)
UPDATE receta.tenido
SET estado_id = (SELECT id FROM estado_desarrollo_color WHERE codigo = 'HISTORICO')
WHERE id IN (SELECT historicize_id FROM colliding_pairs);

-- Step 2: backfill all flags
UPDATE receta.tenido rt
SET flg_antipilling = EXISTS (
    SELECT 1
    FROM receta.tenido_paso tp
    JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
    JOIN item_insumo_detalle iid ON iid.item_id = tpi.item_id
    WHERE tp.receta_id = rt.id
      AND iid.flg_antipilling = true
);


WITH derived AS (
    SELECT rt.id, rt.fyh_cre,
           rt.color_x_cliente_id, rt.articulo_tipo_id, rt.fibra,
           rt.tenido_id, rt.tipo_receta_id,
           rt.flg_antipilling AS flag_actual,
           EXISTS (
               SELECT 1 FROM receta.tenido_paso tp
               JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
               JOIN item_insumo_detalle iid ON iid.item_id = tpi.item_id
               WHERE tp.receta_id = rt.id AND iid.flg_antipilling = true
           ) AS derived_flag
    FROM receta.tenido rt
    WHERE rt.flg_produccion = true
)
SELECT d.id, d.flag_actual, d.derived_flag, d.fyh_cre,
       correct.id AS keeping_id, correct.fyh_cre AS keeping_fyh_cre
FROM derived d
JOIN derived correct
  ON correct.id != d.id
 AND correct.color_x_cliente_id IS NOT DISTINCT FROM d.color_x_cliente_id
 AND correct.articulo_tipo_id   IS NOT DISTINCT FROM d.articulo_tipo_id
 AND correct.fibra              IS NOT DISTINCT FROM d.fibra
 AND correct.tenido_id          IS NOT DISTINCT FROM d.tenido_id
 AND correct.tipo_receta_id     IS NOT DISTINCT FROM d.tipo_receta_id
 AND correct.flag_actual = d.derived_flag
WHERE d.flag_actual != d.derived_flag
ORDER BY d.id;




SELECT rt.id, rt.color_x_cliente_id, rt.articulo_tipo_id, rt.fibra,
       rt.tenido_id, rt.tipo_receta_id, rt.flg_antipilling AS flag_actual,
       e.codigo AS estado, rt.flg_produccion, rt.fyh_cre
FROM receta.tenido rt
JOIN estado_desarrollo_color e ON e.id = rt.estado_id
WHERE rt.flg_produccion = true
  AND NOT EXISTS (
      SELECT 1 FROM receta.tenido_paso tp
      JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
      JOIN item_insumo_detalle iid ON iid.item_id = tpi.item_id
      WHERE tp.receta_id = rt.id AND iid.flg_antipilling = true
  )
  AND rt.flg_antipilling = true
UNION ALL
SELECT rt.id, rt.color_x_cliente_id, rt.articulo_tipo_id, rt.fibra,
       rt.tenido_id, rt.tipo_receta_id, rt.flg_antipilling,
       e.codigo, rt.flg_produccion, rt.fyh_cre
FROM receta.tenido rt
JOIN estado_desarrollo_color e ON e.id = rt.estado_id
WHERE rt.flg_produccion = true
  AND EXISTS (
      SELECT 1 FROM receta.tenido_paso tp
      JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
      JOIN item_insumo_detalle iid ON iid.item_id = tpi.item_id
      WHERE tp.receta_id = rt.id AND iid.flg_antipilling = true
  )
  AND rt.flg_antipilling = false
ORDER BY color_x_cliente_id, articulo_tipo_id, fibra, tenido_id, tipo_receta_id;

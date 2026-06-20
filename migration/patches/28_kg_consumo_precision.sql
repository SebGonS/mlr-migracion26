-- ═══════════════════════════════════════════════════════════════
-- 28. Widen inventory quantity columns NUMERIC(12,4) → NUMERIC(15,7)
-- ───────────────────────────────────────────────────────────────
-- generar_receta now returns chemical consumption in kg (= recipe grams ÷ 1000)
-- instead of the mislabeled grams it returned before. 7 decimals preserve the
-- recipe's 4 gram-decimals after the 3-place shift (frontend ×1000 to show g):
--   1234.5678 g  →  1.2345678 kg   (7 dp, lossless)
-- 8 integer digits remain ample for roll/bulk weights that share these columns.
--
-- Pairs with the unit fix in funciones/mes.sql (generar_receta / cantidad_reservada).
-- Apply BEFORE redeploying generar_receta so new kg values are not truncated.
--
-- ⚠ A column type change forces a table rewrite, which PostgreSQL refuses while any
--   view references the column. This patch DROPS every dependent view (CASCADE) first;
--   REBUILD them afterward by re-running migration/08_views.sql (idempotent).
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- Drop all views depending on the four tables being altered (CASCADE covers
-- view-on-view chains). They are recreated by re-running migration/08_views.sql.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT nv.nspname AS schema_name, v.relname AS view_name
        FROM pg_depend d
        JOIN pg_rewrite   rw ON rw.oid = d.objid
        JOIN pg_class     v  ON v.oid  = rw.ev_class AND v.relkind = 'v'
        JOIN pg_namespace nv ON nv.oid = v.relnamespace
        JOIN pg_class     t  ON t.oid  = d.refobjid
        JOIN pg_namespace nt ON nt.oid = t.relnamespace
        WHERE t.relname IN ('item_movimientos','item_saldo','item_valoracion','partida_componente')
          AND nt.nspname IN ('inventario','mes')
          AND v.oid <> t.oid
    LOOP
        EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.schema_name, r.view_name);
    END LOOP;
END $$;

-- item_movimientos.cantidad feeds the generated `monto` column; PostgreSQL forbids
-- ALTER TYPE on a column referenced by a generated column. Drop and recreate monto —
-- it is generated (no data lost) and not referenced by any view/function.
-- Note: recreating moves `monto` to the last ordinal position (cosmetic only).
ALTER TABLE inventario.item_movimientos DROP COLUMN monto;
ALTER TABLE inventario.item_movimientos ALTER COLUMN cantidad TYPE numeric(15,7);
ALTER TABLE inventario.item_movimientos
    ADD COLUMN monto NUMERIC(16,4) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED;

ALTER TABLE inventario.item_saldo     ALTER COLUMN cantidad_actual    TYPE numeric(15,7);
ALTER TABLE inventario.item_valoracion ALTER COLUMN stock_qty         TYPE numeric(15,7);
ALTER TABLE mes.partida_componente    ALTER COLUMN cantidad_reservada TYPE numeric(15,7);

-- Keep the MAP trigger's local accumulator in sync with the widened column,
-- else live valoración recomputes would truncate chemical kg below 7 dp.
CREATE OR REPLACE FUNCTION inventario.fn_trg_actualizar_map()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_flg_valorizable boolean;
    v_flg_recalcula   boolean;
    v_map             numeric(12,4);
    v_stock_qty       numeric(15,7);  -- widened with item_valoracion.stock_qty
    v_stock_valorado  numeric(16,4);
BEGIN
    IF NEW.precio_unitario IS NULL THEN RETURN NEW; END IF;

    SELECT imt.flg_valorizable, imt.flg_recalcula_costo
    INTO v_flg_valorizable, v_flg_recalcula
    FROM inventario.item_movimiento_tipo imt
    WHERE imt.id = NEW.item_movimiento_tipo_id;

    IF NOT v_flg_valorizable THEN RETURN NEW; END IF;

    INSERT INTO inventario.item_valoracion (item_id, precio_promedio, stock_qty, stock_valorado)
    VALUES (NEW.item_id, 0, 0, 0)
    ON CONFLICT (item_id) DO NOTHING;

    SELECT precio_promedio, stock_qty, stock_valorado
    INTO v_map, v_stock_qty, v_stock_valorado
    FROM inventario.item_valoracion
    WHERE item_id = NEW.item_id
    FOR UPDATE;

    IF NEW.destino_ubicacion_id IS NOT NULL THEN
        IF v_flg_recalcula THEN
            v_stock_valorado := v_stock_valorado + (NEW.cantidad * NEW.precio_unitario);
            v_stock_qty      := v_stock_qty + NEW.cantidad;
            v_map            := CASE WHEN v_stock_qty > 0
                                     THEN ROUND(v_stock_valorado / v_stock_qty, 4) ELSE 0 END;
        ELSE
            v_stock_valorado := v_stock_valorado + (NEW.cantidad * v_map);
            v_stock_qty      := v_stock_qty + NEW.cantidad;
        END IF;
    ELSE
        v_stock_valorado := GREATEST(0, v_stock_valorado - (NEW.cantidad * v_map));
        v_stock_qty      := GREATEST(0, v_stock_qty - NEW.cantidad);
        IF v_stock_qty = 0 THEN v_stock_valorado := 0; END IF;
    END IF;

    INSERT INTO inventario.item_valoracion (item_id, precio_promedio, stock_qty, stock_valorado, fyh_mod)
    VALUES (NEW.item_id, v_map, v_stock_qty, v_stock_valorado, now())
    ON CONFLICT (item_id) DO UPDATE
        SET precio_promedio = EXCLUDED.precio_promedio,
            stock_qty       = EXCLUDED.stock_qty,
            stock_valorado  = EXCLUDED.stock_valorado,
            fyh_mod         = EXCLUDED.fyh_mod;
    RETURN NEW;
END;
$$;

COMMIT;

-- ⇩ NEXT STEP (outside this transaction): rebuild the views dropped above.
--   psql -f migration/08_views.sql      (idempotent: DROP IF EXISTS + CREATE OR REPLACE)

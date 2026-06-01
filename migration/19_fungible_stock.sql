-- 19_fungible_stock.sql
-- Allows fungible items (chemicals, auxiliaries) to be consumed without
-- lot assignment and to carry negative stock balances.
--
-- Also restores item_movimiento_tipo.factor (was dropped) and adds
-- reversal_tipo_id (≈ SAP T156 XRUEM), fixing the trigger to use factor
-- as a fallback for location-agnostic (null-null) movements.
--
-- Lot-agnostic ingress is also supported by the same mechanism:
-- a null-null movement with factor=1 credits item_saldo(item_id, NULL).
--
-- Dependency order:
--   1. item.flg_fungible + item_tipo.ubicacion_default_id
--   2. item_movimiento_tipo: restore factor, add reversal_tipo_id
--   3. fn_trg_sync_cantidad_actual: factor-based null-null case
--   4. vw_stock_items / vw_stock_items_ubicacion: surface negatives
--   Functions (registrar_consumo_paso, corregir_matizado) → funciones/mes.sql


-- ══════════════════════════════════════════════════════════════════
-- 1. ITEM FLAGS
--    flg_fungible: consumption bypasses FIFO and posts lotless.
--    ubicacion_default_id on item_tipo: preferred storage location
--    for fungible consumption when item has stock history. Optional —
--    null-null (factor-based) saldo update is the final fallback.
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE item      ADD COLUMN IF NOT EXISTS flg_fungible         BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE item_tipo ADD COLUMN IF NOT EXISTS ubicacion_default_id INT REFERENCES inventario.ubicacion(id);


-- ══════════════════════════════════════════════════════════════════
-- 2. ITEM_MOVIMIENTO_TIPO — restore factor, add reversal_tipo_id
--    factor (≈ SAP SHKZG): -1 egress, +1 ingress, 0 neutral.
--    reversal_tipo_id (≈ SAP XRUEM): explicit reversal pairing.
--    Both were missing from live schema.
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE inventario.item_movimiento_tipo
    ADD COLUMN IF NOT EXISTS factor           SMALLINT,
    ADD COLUMN IF NOT EXISTS reversal_tipo_id SMALLINT
        REFERENCES inventario.item_movimiento_tipo(id);

UPDATE inventario.item_movimiento_tipo SET factor = CASE codigo
    WHEN 'COMPRA_ING'       THEN  1
    WHEN 'VENTA_EGR'        THEN -1
    WHEN 'PROD_CONSUMO'     THEN -1
    WHEN 'PROD_ING'         THEN  1
    WHEN 'EXT_ENVIO'        THEN -1
    WHEN 'EXT_RETORNO'      THEN  1
    WHEN 'INT_TRANSFER_ING' THEN  1
    WHEN 'INT_TRANSFER_EGR' THEN -1
    WHEN 'DEV_CLI_ING'      THEN  1
    WHEN 'DEV_CLI_EGR'      THEN -1
    WHEN 'DEV_PROV_EGR'     THEN -1
    WHEN 'SERV_ING'         THEN  1
    WHEN 'SERV_EGR'         THEN -1
    WHEN 'SERV_DEV_ING'     THEN  1
    WHEN 'AJUSTE_POS'       THEN  1
    WHEN 'AJUSTE_NEG'       THEN -1
    WHEN 'PESAJE_POS'       THEN  1
    WHEN 'PESAJE_NEG'       THEN -1
    WHEN 'MUESTRA_ING'      THEN  1
    WHEN 'MUESTRA_EGR'      THEN -1
    WHEN 'PROD_ING_REV'     THEN -1
    WHEN 'PROD_CONSUMO_REV' THEN  1
    WHEN 'PROD_SCRAP'       THEN -1
    ELSE 0
END;

ALTER TABLE inventario.item_movimiento_tipo
    ALTER COLUMN factor SET NOT NULL,
    ADD CONSTRAINT chk_imt_factor CHECK (factor IN (1, -1, 0));

-- Reversal pairs (symmetric where applicable)
UPDATE inventario.item_movimiento_tipo t
SET reversal_tipo_id = r.rev_id
FROM (
    SELECT a.id AS id, b.id AS rev_id
    FROM inventario.item_movimiento_tipo a
    JOIN inventario.item_movimiento_tipo b ON b.codigo = CASE a.codigo
        WHEN 'PROD_CONSUMO'     THEN 'PROD_CONSUMO_REV'
        WHEN 'PROD_CONSUMO_REV' THEN 'PROD_CONSUMO'
        WHEN 'PROD_ING'         THEN 'PROD_ING_REV'
        WHEN 'PROD_ING_REV'     THEN 'PROD_ING'
        WHEN 'AJUSTE_POS'       THEN 'AJUSTE_NEG'
        WHEN 'AJUSTE_NEG'       THEN 'AJUSTE_POS'
        WHEN 'PESAJE_POS'       THEN 'PESAJE_NEG'
        WHEN 'PESAJE_NEG'       THEN 'PESAJE_POS'
        WHEN 'INT_TRANSFER_ING' THEN 'INT_TRANSFER_EGR'
        WHEN 'INT_TRANSFER_EGR' THEN 'INT_TRANSFER_ING'
        WHEN 'MUESTRA_ING'      THEN 'MUESTRA_EGR'
        WHEN 'MUESTRA_EGR'      THEN 'MUESTRA_ING'
        ELSE NULL
    END
) r
WHERE t.id = r.id;


-- ══════════════════════════════════════════════════════════════════
-- 3. TRIGGER — factor-based fallback for null-null movements
--    Location-present path unchanged (SAP 311 pattern preserved).
--    Transfers (both locations set) now correctly fire both blocks
--    — early RETURN removed.
--    New: both locations null → use factor to debit/credit
--    item_saldo at ubicacion_id = NULL (location-agnostic bucket).
--    item_saldo already has UNIQUE NULLS NOT DISTINCT (item_id,
--    ubicacion_id) so a null-ubicacion row is valid by design.
--    lote_saldo skipped for null-null (no lot to reference).
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION inventario.fn_trg_sync_cantidad_actual()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_factor SMALLINT;
BEGIN
    -- Ingress: credit destino when present.
    -- Runs even when origen is also set (transfer — SAP 311 pattern).
    IF NEW.destino_ubicacion_id IS NOT NULL THEN
        IF NEW.lote_id IS NOT NULL THEN
            INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
            VALUES (NEW.lote_id, NEW.destino_ubicacion_id, NEW.cantidad)
            ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
                SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
        END IF;
        INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
        VALUES (NEW.item_id, NEW.destino_ubicacion_id, NEW.cantidad)
        ON CONFLICT (item_id, ubicacion_id) DO UPDATE
            SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
    END IF;

    -- Egress: debit origen when present.
    -- Runs even when destino is also set (transfer).
    IF NEW.origen_ubicacion_id IS NOT NULL THEN
        IF NEW.lote_id IS NOT NULL THEN
            INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
            VALUES (NEW.lote_id, NEW.origen_ubicacion_id, -NEW.cantidad)
            ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
                SET cantidad_actual = inventario.lote_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
        END IF;
        INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
        VALUES (NEW.item_id, NEW.origen_ubicacion_id, -NEW.cantidad)
        ON CONFLICT (item_id, ubicacion_id) DO UPDATE
            SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
    END IF;

    -- Location-agnostic: both null — use movement type factor.
    -- Covers fungible consumption/ingress where no location is known.
    -- Credits/debits item_saldo at ubicacion_id = NULL (suspense bucket).
    IF NEW.origen_ubicacion_id IS NULL AND NEW.destino_ubicacion_id IS NULL THEN
        SELECT imt.factor INTO v_factor
        FROM inventario.item_movimiento_tipo imt
        WHERE imt.id = NEW.item_movimiento_tipo_id;

        IF v_factor <> 0 THEN
            INSERT INTO inventario.item_saldo (item_id, ubicacion_id, cantidad_actual)
            VALUES (NEW.item_id, NULL, v_factor * NEW.cantidad)
            ON CONFLICT (item_id, ubicacion_id) DO UPDATE
                SET cantidad_actual = inventario.item_saldo.cantidad_actual + EXCLUDED.cantidad_actual;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


-- ══════════════════════════════════════════════════════════════════
-- 4. VIEWS — surface negative balances
--    Remove cantidad_actual > 0 gate; use <> 0 to suppress zero
--    noise while exposing debt positions (including null-ubicacion).
--    vw_stock_items aggregates across all ubicacion_id values per
--    item including NULL, so null-bucket debt nets correctly.
-- ══════════════════════════════════════════════════════════════════
-- CREATE OR REPLACE VIEW inventario.vw_stock_items AS
-- SELECT
--     vi.item_id, vi.item_codigo, vi.item_nombre,
--     vi.item_tipo_id, vi.item_tipo_codigo,
--     SUM(si.cantidad_actual) AS cantidad_total,
--     vi.unidad_id, vi.unidad_codigo
-- FROM inventario.item_saldo si
-- JOIN vw_items vi ON vi.item_id = si.item_id
-- WHERE si.cantidad_actual <> 0
-- GROUP BY vi.item_id, vi.item_codigo, vi.item_nombre,
--          vi.item_tipo_id, vi.item_tipo_codigo, vi.unidad_id, vi.unidad_codigo;

-- CREATE OR REPLACE VIEW inventario.vw_stock_items_ubicacion AS
-- SELECT
--     vi.item_id, vi.item_codigo, vi.item_nombre,
--     vi.item_tipo_id, vi.item_tipo_codigo,
--     si.ubicacion_id,
--     si.cantidad_actual AS cantidad_total,
--     vi.unidad_id, vi.unidad_codigo
-- FROM inventario.item_saldo si
-- JOIN vw_items vi ON vi.item_id = si.item_id
-- WHERE si.cantidad_actual <> 0;



UPDATE item SET flg_fungible = TRUE
WHERE item_tipo_id IN (SELECT id FROM item_tipo WHERE codigo IN ('INSUMO'));
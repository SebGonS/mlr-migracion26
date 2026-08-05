-- ═══════════════════════════════════════════════════════════════
-- Reverse partida-level weighing for partida 6314
-- ---------------------------------------------------------------
-- Goal: make partida 6314 show as PENDING WEIGHING again.
--
-- The weighing gate is EXISTS (SELECT 1 FROM inventario.pesaje
-- WHERE lote_id = <roll>).  registrar_pesaje_produccion wrote, per
-- roll assigned to the partida:
--   1. an inventario.pesaje row (tipo='INGRESO')
--   2. a PESAJE_POS / PESAJE_NEG movement for the delta vs declared
--   3. an updated lote.cantidad
--
-- NOTE: inventario.anular_pesaje() CANNOT be used here — the
-- deployed function still joins lote_rollo_detalle.entrega_detalle_id,
-- a column that no longer exists after the guia_remision→entrega
-- normalization.  So we reverse directly and self-contained.
--
-- pesaje has no FK to entrega and no stored "declared weight", so
-- lote.cantidad is left at its current (weighed) value; there is no
-- per-roll declared weight to restore it to. Re-weighing will set it.
--
-- Run STEP 1, eyeball it, then STEP 2 (one transaction), then STEP 3.
-- ═══════════════════════════════════════════════════════════════

-- ── STEP 1: inspect current state ──────────────────────────────
SELECT
    l.id                         AS lote_id,
    l.cantidad                   AS peso_actual,
    p.id                         AS pesaje_id,
    p.tipo,
    p.peso_real,
    EXISTS (SELECT 1 FROM inventario.item_movimientos im
            JOIN inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
            WHERE im.lote_id = l.id AND imt.codigo = 'PROD_CONSUMO') AS ya_en_produccion
FROM   mes.partida_componente pc
JOIN   inventario.lote l              ON l.id = pc.lote_id
LEFT   JOIN inventario.pesaje p       ON p.lote_id = l.id
WHERE  pc.partida_id = 6314
  AND  l.fyh_elm IS NULL
ORDER  BY l.id;


-- ── STEP 2: reverse the weighing (single transaction) ──────────
-- Aborts if any roll is already in production (PROD_CONSUMO).
-- Reverses the PESAJE_POS/NEG movements (ledger stays balanced) and
-- deletes the pesaje rows so the gate reads pending again.
BEGIN;

DO $$
DECLARE
    v_in_prod int;
BEGIN
    SELECT count(*) INTO v_in_prod
    FROM   mes.partida_componente pc
    JOIN   inventario.item_movimientos im  ON im.lote_id = pc.lote_id
    JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
    WHERE  pc.partida_id = 6314
      AND  imt.codigo = 'PROD_CONSUMO';

    IF v_in_prod > 0 THEN
        RAISE EXCEPTION
            'Abortado: % rollo(s) del partida 6314 ya están en producción (PROD_CONSUMO). No se puede revertir el pesaje.',
            v_in_prod;
    END IF;
END $$;

-- 2a. Reverse the weighing delta movements (PESAJE_POS/NEG) so the
--     inventory ledger nets to zero for the weighing event.
--     A POS was an increase → reverse with a NEG that flips
--     origen/destino; and vice-versa.
WITH tgt AS (
    SELECT pc.lote_id
    FROM   mes.partida_componente pc
    JOIN   inventario.lote l ON l.id = pc.lote_id
    WHERE  pc.partida_id = 6314 AND l.fyh_elm IS NULL
),
seq AS (SELECT nextval('inventario.mov_doc_seq') AS doc_id)
INSERT INTO inventario.item_movimientos(
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    origen_ubicacion_id, destino_ubicacion_id,
    cantidad, documento_tipo, documento_id)
SELECT
    (SELECT doc_id FROM seq),
    im.item_id, im.lote_id,
    CASE WHEN imt.codigo = 'PESAJE_POS'
         THEN (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo='PESAJE_NEG')
         ELSE (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo='PESAJE_POS')
    END,
    im.destino_ubicacion_id,   -- flip
    im.origen_ubicacion_id,    -- flip
    im.cantidad,
    'reversion_pesaje', 6314
FROM   inventario.item_movimientos im
JOIN   inventario.item_movimiento_tipo imt ON imt.id = im.item_movimiento_tipo_id
WHERE  im.lote_id IN (SELECT lote_id FROM tgt)
  AND  imt.codigo IN ('PESAJE_POS','PESAJE_NEG');

-- 2b. Clear the weighing gate.
DELETE FROM inventario.pesaje
WHERE lote_id IN (
    SELECT pc.lote_id
    FROM   mes.partida_componente pc
    JOIN   inventario.lote l ON l.id = pc.lote_id
    WHERE  pc.partida_id = 6314 AND l.fyh_elm IS NULL
);

INSERT INTO logs_api(function_name, user_id, params)
VALUES ('reverse_pesaje_partida_6314 (manual)', NULL,
        jsonb_build_object('partida_id', 6314,
                           'motivo', 'Marcar partida como pendiente de pesaje'));

COMMIT;


-- ── STEP 3: verify it now reads as pending ─────────────────────
SELECT
    count(*)                                    AS total_rollos,
    count(*) FILTER (WHERE p.id IS NOT NULL)    AS rollos_con_pesaje
FROM   mes.partida_componente pc
JOIN   inventario.lote l        ON l.id = pc.lote_id
LEFT   JOIN inventario.pesaje p ON p.lote_id = l.id
WHERE  pc.partida_id = 6314
  AND  l.fyh_elm IS NULL;
-- Expect rollos_con_pesaje = 0 → partida shows as pending weighing.

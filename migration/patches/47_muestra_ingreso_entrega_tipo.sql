-- ═══════════════════════════════════════════════════════════════════════════════
-- 47 · MUESTRA_INGRESO entrega_tipo — free supplier sample reception
-- ───────────────────────────────────────────────────────────────────────────────
-- Wires a receiving document type for zero-cost supplier samples to the existing
-- (but until now unused) MUESTRA_ING movement type. MUESTRA_ING is non-valorizable
-- (flg_valorizable=false) so the MAP trigger skips it entirely: a free sample
-- raises physical stock (item_saldo) WITHOUT touching item_valoracion — it neither
-- drives average cost down (a zero-priced valorized receipt would) nor fabricates
-- value at current MAP (an AJUSTE_POS would). Provenance is preserved via the
-- entrega's tercero_id. Never linked to doc.compra.
--
-- Consumed by doc.registrar_muestra_ingreso (funciones/compras.sql).
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO doc.entrega_tipo (codigo, nombre, flg_emitida, flg_cliente, item_movimiento_tipo_id)
SELECT 'MUESTRA_INGRESO', 'Muestra – Recepción de muestra de proveedor', false, false, imt.id
FROM inventario.item_movimiento_tipo imt
WHERE imt.codigo = 'MUESTRA_ING'
ON CONFLICT (codigo) DO UPDATE
    SET item_movimiento_tipo_id = EXCLUDED.item_movimiento_tipo_id,
        nombre                  = EXCLUDED.nombre;

SELECT * FROM item_rollo_detalle
SELECT DISTINCT a.id AS articulo_id, a.nombre AS articulo, a.fibra,
       i.id AS item_id, i.nombre AS item
FROM item_rollo_detalle ird
JOIN articulo a ON a.id = ird.articulo_id
JOIN item i     ON i.id = ird.item_id
WHERE ird.flg_rib
ORDER BY a.nombre, i.nombre;

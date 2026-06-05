-- ═══════════════════════════════════════════════════════════════
-- Step 20: Warehouse-scoped cuadre de inventario
-- Adds almacen_id to inventario.cuadre so reconciliations can be
-- run per warehouse independently.
--
-- NULL almacen_id = global cuadre (legacy behavior preserved).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE inventario.cuadre
    ADD COLUMN almacen_id INT REFERENCES inventario.almacen(id);

-- crear_cuadre gains a parameter (p_almacen_id INT DEFAULT NULL).
-- PostgreSQL CREATE OR REPLACE cannot change an existing function's arity,
-- so the old zero-arg signature must be dropped first.
DROP FUNCTION IF EXISTS inventario.crear_cuadre();

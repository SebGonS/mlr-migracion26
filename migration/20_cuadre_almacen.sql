-- ═══════════════════════════════════════════════════════════════
-- Step 20: Warehouse-scoped cuadre de inventario
-- Adds almacen_id to inventario.cuadre so reconciliations can be
-- run per warehouse independently.
--
-- NULL almacen_id = global cuadre (legacy behavior preserved).
-- ═══════════════════════════════════════════════════════════════
/*
Based on what changed, you need to rerun in this order:

migration/20_cuadre_almacen.sql — DDL first (adds column, drops old function)
migration/05_new_tables_foundation.sql — or just the vw_cuadre block
migration/14_cuadre_cutoff.sql — updated trigger function
funciones/inventario.sql — updated functions
And for the performance fix:
5. funciones/mes.sql — or just the get_actividades_sin_programar block
*/
ALTER TABLE inventario.cuadre
    ADD COLUMN almacen_id INT REFERENCES inventario.almacen(id);

-- crear_cuadre gains a parameter (p_almacen_id INT DEFAULT NULL).
-- PostgreSQL CREATE OR REPLACE cannot change an existing function's arity,
-- so the old zero-arg signature must be dropped first.
DROP FUNCTION IF EXISTS inventario.crear_cuadre();

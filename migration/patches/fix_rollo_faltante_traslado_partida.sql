-- ─────────────────────────────────────────────────────────────────────────────
-- CORRECCIÓN: rollo faltante trasladado a partida distinta para teñido
--
-- Contexto: operadores ejecutaron receta para 18 rollos pero uno no ingresó
-- físicamente. El consumo de insumos es correcto (baño preparado para 18).
-- El rollo faltante se tiñe en otra partida del mismo cliente/color y luego
-- se devuelve a la partida original para despacho.
--
-- partida_origen_id  = 5957   (18 rollos, uno faltante)
-- partida_destino_id = 5960   (donde se teñirá el rollo faltante)
-- lote_rollo_id      = 122217 (rollo que no ingresó)
-- usr_mod            = 4
--
-- Fases:
--   1. Corregir cantidad en ejecuciones de la partida original
--   2. Trasladar el rollo a la partida destino (antes del tenido)
--   3. Cerrar pasos pre-tenido ya ejecutados en la partida destino
--   4. (Al despacho) Devolver el rollo a la partida original
-- ─────────────────────────────────────────────────────────────────────────────


-- ─────────────────────────────────────────────────────────────────────────────
-- FASE 1 — Corregir cantidad en ejecuciones de la partida original
-- Verificar con el SELECT antes de ejecutar el bloque BEGIN/COMMIT.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT ppe.id, pp.id AS paso_id, ppe.cantidad, ppe.estado, ppe.notas
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
WHERE pp.partida_id = 5957
ORDER BY ppe.fyh_inicio;

ROLLBACK;

BEGIN;

-- Pasos con ejecucion única de 18: reducir directamente a 17
UPDATE mes.partida_paso_ejecucion ppe
SET cantidad = 17,
    notas    = COALESCE(notas || E'\n', '')
               || 'CORRECCIÓN: rollo lote #122217 no ingresó en proceso. Cantidad real: 17. Rollo trasladado a partida #5960 para teñido.',
    usr_mod  = 4,
    fyh_mod  = now()
FROM mes.partida_paso pp
WHERE pp.id         = ppe.partida_paso_id
  AND pp.partida_id = 5957
  AND ppe.cantidad  = 18;

-- Pasos con ejecuciones partidas (9237: 9+9, 9238: 10+8): restar 1 a la más antigua
UPDATE mes.partida_paso_ejecucion
SET cantidad = cantidad - 1,
    notas    = COALESCE(notas || E'\n', '')
               || 'CORRECCIÓN: rollo lote #122217 no ingresó en proceso. Cantidad ajustada -1. Rollo trasladado a partida #5960 para teñido.',
    usr_mod  = 4,
    fyh_mod  = now()
WHERE id IN (2020, 2023);

-- ─────────────────────────────────────────────────────────────────────────────
-- FASE 2 — Trasladar rollo a partida destino
-- partida_componente no tiene campo notas; queda trazado por usr_mod/fyh_mod.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE mes.partida_componente
SET partida_id = 5960,
    usr_mod    = 4,
    fyh_mod    = now()
WHERE partida_id = 5957
  AND lote_id   = 122217;

COMMIT;


-- ─────────────────────────────────────────────────────────────────────────────
-- FASE 3 — Cerrar pasos pre-tenido ya ejecutados en la partida destino
-- Ejecutar ANTES de que corra el tenido en la partida destino.
-- Verificar con el SELECT; ajustar el LIKE si el nombre de la operación difiere.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT ppe.id, pp.id AS paso_id, o.nombre AS operacion, ppe.estado, ppe.fyh_inicio
FROM mes.partida_paso_ejecucion ppe
JOIN mes.partida_paso pp ON pp.id = ppe.partida_paso_id
JOIN mes.operacion o     ON o.id  = pp.operacion_id
WHERE pp.partida_id = 5960
ORDER BY ppe.fyh_inicio;

BEGIN;

UPDATE mes.partida_paso_ejecucion ppe
SET estado  = 'COMPLETADO',
    fyh_fin = now(),
    notas   = COALESCE(notas || E'\n', '')
              || 'Cerrado manualmente: rollo adicional (lote #122217) asignado post-ejecución.',
    usr_mod = 4,
    fyh_mod = now()
FROM mes.partida_paso pp
WHERE pp.id         = ppe.partida_paso_id
  AND pp.partida_id = 5960
  AND ppe.estado    = 'EN_PROCESO'
  AND pp.id < (
      SELECT MIN(pp2.id)
      FROM mes.partida_paso pp2
      JOIN mes.operacion o ON o.id = pp2.operacion_id
      WHERE pp2.partida_id = 5960
        AND lower(o.nombre) LIKE '%tenido%'
  );

COMMIT;


-- ─────────────────────────────────────────────────────────────────────────────
-- FASE 4 — Devolver rollo a partida original al momento del despacho
-- ─────────────────────────────────────────────────────────────────────────────

-- SELECT * FROM mes.partida_componente WHERE lote_id = 122217;

BEGIN;

UPDATE mes.partida_componente
SET partida_id = 5957,
    usr_mod    = 4,
    fyh_mod    = now()
WHERE partida_id = 5960
  AND lote_id   = 122217;

COMMIT;

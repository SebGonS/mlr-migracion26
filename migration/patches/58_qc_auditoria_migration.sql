-- 58_qc_auditoria_migration.sql   ⚠ review before running (data insert/update)
--
-- Migrates legacy QC (public.auditoria, per-partida) into the new per-lote model
-- (calidad.inspeccion + inventario.lote.estado_calidad), unblocking ~28.7k dyed
-- output rolls for dispatch (vw_despacho_pendiente requires estado_calidad='APROBADO').
--
-- RULE — final-verdict-wins: latest fecha_auditoria per partida (pooled on the
-- rework root via COALESCE(partida_origen_id, id)). Validated: 4,977 partidas end
-- OK, 10 end blank, ZERO end Observado — so every OK partida's PENDIENTE output
-- lotes become APROBADO; nothing is held or needs a judgment call.
--
-- Mirrors the app (funciones/calidad.sql:80,116): INSERT inspeccion + UPDATE
-- estado_calidad, both explicit (no trigger does it). fyh_inspeccion carries the
-- legacy fecha_auditoria (accurate timestamp).
--
-- SCOPE: only lotes currently estado_calidad='PENDIENTE' whose partida's FINAL
-- verdict is OK, and that do NOT already have an inspeccion (61 skipped — don't
-- override existing QC). ~28,659 lotes. Leaves ~938 no-verdict lotes PENDIENTE.
-- Touches no stock/movements.
--
-- ⚠ §0 read-only → §1 in a txn → §2 verify → COMMIT.

-- ══════════════════════════════════════════════════════════════════════════
-- §0 · PRE-CHECK (read only)
-- ══════════════════════════════════════════════════════════════════════════
WITH final AS (
  SELECT DISTINCT ON (partida_id) partida_id, TRIM(estado) AS estado, fecha_auditoria
  FROM public.auditoria ORDER BY partida_id, fecha_auditoria DESC, id DESC
)
SELECT COUNT(*) AS to_insert_expect_28659
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
JOIN final f ON f.partida_id = COALESCE(p.partida_origen_id, p.id) AND f.estado='OK'
WHERE l.estado_calidad='PENDIENTE'
  AND NOT EXISTS (SELECT 1 FROM calidad.inspeccion i WHERE i.lote_id = l.id)
  -- GUARD: skip rolls that re-entered / are in production (not terminal approved output)
  AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
                  WHERE im.lote_id = l.id AND imt.codigo='PROD_CONSUMO')
  AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc
                  JOIN mes.partida p2 ON p2.id=pc.partida_id
                  WHERE pc.lote_id = l.id AND p2.fyh_elm IS NULL
                    AND p2.estado_produccion NOT IN ('CERRADA','CANCELADA'));


-- ══════════════════════════════════════════════════════════════════════════
-- §1 · Execute  (one transaction)
-- ══════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE TEMP TABLE _qc_target ON COMMIT DROP AS
WITH final AS (
  SELECT DISTINCT ON (partida_id) partida_id, TRIM(estado) AS estado, fecha_auditoria
  FROM public.auditoria ORDER BY partida_id, fecha_auditoria DESC, id DESC
)
SELECT l.id AS lote_id, pe.id AS pxe_id, f.fecha_auditoria
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion pe ON pe.id = l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id = pe.partida_paso_id
JOIN mes.partida p ON p.id = pp.partida_id
JOIN final f ON f.partida_id = COALESCE(p.partida_origen_id, p.id) AND f.estado='OK'
WHERE l.estado_calidad='PENDIENTE'
  AND NOT EXISTS (SELECT 1 FROM calidad.inspeccion i WHERE i.lote_id = l.id)
  -- GUARD: skip rolls that re-entered / are in production (not terminal approved output)
  AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
                  WHERE im.lote_id = l.id AND imt.codigo='PROD_CONSUMO')
  AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc
                  JOIN mes.partida p2 ON p2.id=pc.partida_id
                  WHERE pc.lote_id = l.id AND p2.fyh_elm IS NULL
                    AND p2.estado_produccion NOT IN ('CERRADA','CANCELADA'));

INSERT INTO calidad.inspeccion (lote_id, partida_paso_ejecucion_id, resultado, observacion, fyh_inspeccion, usr_cre)
SELECT lote_id, pxe_id, 'APROBADO'::calidad_estado_enum,
       'Migrado de auditoría legacy (final-verdict-wins) — patch 58',
       fecha_auditoria::timestamptz, 4
FROM _qc_target;
-- expect 28659

UPDATE inventario.lote SET estado_calidad = 'APROBADO'
WHERE id IN (SELECT lote_id FROM _qc_target);
-- expect 28659


-- ══════════════════════════════════════════════════════════════════════════
-- §2 · VERIFY (before COMMIT)
-- ══════════════════════════════════════════════════════════════════════════
-- -- new inspecciones + estado flip land together (expect equal, ~28659)
SELECT COUNT(*) AS inspecciones_migradas
FROM calidad.inspeccion WHERE observacion LIKE '%patch 58%';

-- -- output-lote QC distribution now (APROBADO up ~28659, PENDIENTE down to ~938)
SELECT estado_calidad, COUNT(*) FROM inventario.lote
WHERE documento_tipo='partida_paso_ejecucion' GROUP BY 1 ORDER BY 2 DESC;

-- -- no lote left PENDIENTE whose partida's final verdict was OK (expect 0)
WITH final AS (SELECT DISTINCT ON (partida_id) partida_id, TRIM(estado) AS estado
  FROM public.auditoria ORDER BY partida_id, fecha_auditoria DESC, id DESC)
SELECT COUNT(*) AS ok_partida_still_pendiente_expect_0
FROM inventario.lote l
JOIN mes.partida_paso_ejecucion pe ON pe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
JOIN mes.partida_paso pp ON pp.id=pe.partida_paso_id
JOIN mes.partida p ON p.id=pp.partida_id
JOIN final f ON f.partida_id = COALESCE(p.partida_origen_id,p.id) AND f.estado='OK'
WHERE l.estado_calidad='PENDIENTE'
  AND NOT EXISTS (SELECT 1 FROM calidad.inspeccion i WHERE i.lote_id=l.id)
  AND NOT EXISTS (SELECT 1 FROM inventario.item_movimientos im
                  JOIN inventario.item_movimiento_tipo imt ON imt.id=im.item_movimiento_tipo_id
                  WHERE im.lote_id=l.id AND imt.codigo='PROD_CONSUMO')
  AND NOT EXISTS (SELECT 1 FROM mes.partida_componente pc
                  JOIN mes.partida p2 ON p2.id=pc.partida_id
                  WHERE pc.lote_id=l.id AND p2.fyh_elm IS NULL
                    AND p2.estado_produccion NOT IN ('CERRADA','CANCELADA'));

-- ══════════════════════════════════════════════════════════════════════════
-- COMMIT;   -- only after §2 checks out
-- ══════════════════════════════════════════════════════════════════════════

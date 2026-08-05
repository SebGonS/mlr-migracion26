-- ============================================================================
-- DIAGNOSTIC · Validate the auditoría rejection rule — READ ONLY
-- ============================================================================
-- CLIENT RULE for migrating legacy public.auditoria → calidad.inspeccion:
--   • auditoria.estado='OK' partida  → ALL dyed rolls APPROVED (OK is always OK).
--   • non-OK partida (Observado/NULL) → VARIANT; ground truth = produccion_tenido:
--       rejected roll count = SUM(pt.rollos) for rows with a NON-TENIDO tipo
--       (tipo <> the dyeing value). A non-tenido recipe pass = reprocess ⇒ those
--       rolls failed QC. Remaining dyed rolls approved.
-- This checks the tipo vocabulary + how the rule lands before building. Nothing writes.
-- ============================================================================


-- ── §1 · What are the produccion_tenido.tipo values? (find the tenido vs non-tenido)
SELECT tipo,
       COUNT(*)                          AS rows,
       COUNT(DISTINCT partida_id)        AS partidas,
       SUM(rollos)                       AS total_rollos
FROM public.produccion_tenido
GROUP BY tipo
ORDER BY rows DESC;
-- expect a dominant 'Teñido' (dyeing) + a few non-tenido types (reprocess/recuperación…).


-- ── §2 · Cross auditoria estado × presence of a non-tenido tipo row ───────────
-- Does the "non-tenido ⇒ rejected" signal align with non-OK auditoría? And do OK
-- partidas also carry non-tenido rows (client says OK always wins — measure overlap).
WITH aud AS (   -- one estado per partida (worst-case: if any non-OK, take non-OK)
    SELECT partida_id,
           CASE WHEN bool_or(estado='OK') AND NOT bool_or(estado IS DISTINCT FROM 'OK')
                     THEN 'OK_only'
                WHEN bool_or(estado='OK') THEN 'OK_plus_other'
                WHEN bool_or(estado='Observado') THEN 'Observado'
                ELSE 'other_or_null' END AS aud_bucket
    FROM public.auditoria GROUP BY partida_id
),
nontenido AS (
    SELECT partida_id, SUM(rollos) FILTER (WHERE tipo <> 'Teñido') AS nontenido_rollos,
           COUNT(*) FILTER (WHERE tipo <> 'Teñido') AS nontenido_rows
    FROM public.produccion_tenido GROUP BY partida_id
)
SELECT
    COALESCE(a.aud_bucket, 'no_auditoria')                    AS aud_bucket,
    (COALESCE(n.nontenido_rows,0) > 0)                        AS has_nontenido,
    COUNT(*)                                                  AS partidas,
    SUM(COALESCE(n.nontenido_rollos,0))                       AS sum_nontenido_rollos
FROM mes.partida p
LEFT JOIN aud a ON a.partida_id = p.id
LEFT JOIN nontenido n ON n.partida_id = p.id
WHERE p.fyh_cre <= '2026-05-25 15:27:52+00'::timestamptz
GROUP BY 1, 2
ORDER BY aud_bucket, has_nontenido;


-- ── §3 · The non-OK partidas specifically: estado + non-tenido rollos + dyed out
-- The set the rule actually governs. Shows per-partida the rejected count it implies.
WITH aud AS (
    SELECT partida_id, string_agg(DISTINCT estado, ',') AS estados
    FROM public.auditoria GROUP BY partida_id
    HAVING NOT bool_or(estado='OK') OR bool_or(estado IS NULL) OR bool_or(estado='Observado')
),
nontenido AS (
    SELECT partida_id, SUM(rollos) FILTER (WHERE tipo <> 'Teñido') AS nontenido_rollos
    FROM public.produccion_tenido GROUP BY partida_id
),
dyed AS (
    SELECT pp.partida_id, COUNT(*) AS dyed_rolls
    FROM inventario.lote l
    JOIN inventario.lote_rollo_detalle lrd ON lrd.lote_id=l.id AND lrd.flg_tenido=true
    JOIN mes.partida_paso_ejecucion ppe ON ppe.id=l.documento_id AND l.documento_tipo='partida_paso_ejecucion'
    JOIN mes.partida_paso pp ON pp.id=ppe.partida_paso_id
    GROUP BY pp.partida_id
)
SELECT a.partida_id, a.estados,
       COALESCE(n.nontenido_rollos,0)  AS implied_rejected,
       COALESCE(d.dyed_rolls,0)        AS dyed_rolls,
       COALESCE(d.dyed_rolls,0) - COALESCE(n.nontenido_rollos,0) AS implied_approved
FROM aud a
LEFT JOIN nontenido n ON n.partida_id = a.partida_id
LEFT JOIN dyed d ON d.partida_id = a.partida_id
ORDER BY a.partida_id;

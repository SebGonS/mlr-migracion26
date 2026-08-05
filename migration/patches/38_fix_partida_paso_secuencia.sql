-- ─────────────────────────────────────────────────────────────────────────────
-- Migration 38: Fix partida_paso secuencia ordering
-- ─────────────────────────────────────────────────────────────────────────────
-- Cleans up messy secuencia values (1-7 mixed with 10+) from old partidas.
-- Re-sequences all pasos within each partida using sequential 1, 2, 3...
-- pattern, preserving the relative order of pasos.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- Create a temporary mapping table with new secuencia values
CREATE TEMP TABLE paso_secuencia_remap AS
WITH paso_ordered AS (
    -- Order pasos within each partida by current secuencia, then by id
    SELECT
        id,
        partida_id,
        secuencia,
        ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY secuencia, id) AS new_row_num
    FROM mes.partida_paso
)
SELECT
    id,
    partida_id,
    secuencia AS old_secuencia,
    new_row_num::SMALLINT AS new_secuencia
FROM paso_ordered;

-- Log the changes (for audit trail)
INSERT INTO logs_api(function_name, user_id, params)
SELECT
    'fix_partida_paso_secuencia',
    NULL,
    jsonb_build_object(
        'affected_pasos', COUNT(*),
        'affected_partidas', COUNT(DISTINCT partida_id)
    )
FROM paso_secuencia_remap
WHERE old_secuencia IS DISTINCT FROM new_secuencia;

-- Apply the fix: update pasos with new secuencia values
UPDATE mes.partida_paso pp
SET secuencia = remap.new_secuencia,
    usr_mod = NULL,
    fyh_mod = NOW()
FROM paso_secuencia_remap remap
WHERE pp.id = remap.id
  AND pp.secuencia IS DISTINCT FROM remap.new_secuencia;

-- Verify: no more mixed sequences
-- Expected: sequential integers 1, 2, 3, 4... per partida
-- This query should show clean ordering per partida
SELECT
    partida_id,
    COUNT(*) as paso_count,
    STRING_AGG(secuencia::text, ', ' ORDER BY secuencia) as secuencias
FROM mes.partida_paso
GROUP BY partida_id
HAVING COUNT(*) > 0
ORDER BY partida_id
LIMIT 20;

COMMIT;

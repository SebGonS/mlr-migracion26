-- ═══════════════════════════════════════════════════════════════════════════════
-- 44 · doc.entrega: partial unique index on document number
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY: UNIQUE (tercero_id, serie, correlativo, entrega_tipo_id) is a table-wide
-- constraint, so an anulada entrega (fyh_elm set) still permanently occupies its
-- serie/correlativo slot — a new entrega for the same client/tipo can never reuse
-- that number, even though the old one is void.
--
-- Scope: this only relaxes the DB-level constraint. It does not change dispatch
-- process — reissued legal documents (GRE-backed entregas, facturas) should still
-- get a NEW correlativo from their issuing system, not reuse a voided one. This
-- patch just stops the DB from permanently blocking reuse for series where reuse
-- legitimately happens (manual/internal series, corrections, etc).
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_constraint_name text;
    v_expected        smallint[];
BEGIN
    SELECT array_agg(attnum ORDER BY attnum) INTO v_expected
    FROM pg_attribute
    WHERE attrelid = 'doc.entrega'::regclass
      AND attname IN ('tercero_id', 'serie', 'correlativo', 'entrega_tipo_id');

    SELECT conname INTO v_constraint_name
    FROM pg_constraint
    WHERE conrelid = 'doc.entrega'::regclass
      AND contype = 'u'
      AND (SELECT array_agg(k ORDER BY k) FROM unnest(conkey) AS k) = v_expected;

    IF v_constraint_name IS NULL THEN
        RAISE EXCEPTION 'No se encontró el UNIQUE constraint esperado en doc.entrega.';
    END IF;

    EXECUTE format('ALTER TABLE doc.entrega DROP CONSTRAINT %I', v_constraint_name);
END $$;

CREATE UNIQUE INDEX uq_entrega_numero_activo
    ON doc.entrega (tercero_id, serie, correlativo, entrega_tipo_id)
    WHERE fyh_elm IS NULL;

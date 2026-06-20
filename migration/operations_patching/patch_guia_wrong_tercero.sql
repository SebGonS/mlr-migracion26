-- ============================================================
-- PATCH: Fix wrong tercero_id on a guia_remision
-- ------------------------------------------------------------
-- Use case: operator selected the wrong client/supplier when
-- calling doc.crear_guia. This script corrects:
--
--   1. doc.guia_remision.tercero_id
--   2. inventario.lote.propietario_id  (for lotes created by
--      this guia — CLIENTE_ENVIO_PROCESO path only; COMPRA_INGRESO
--      creates no lotes, so step 2 is a no-op in that case)
--
-- NOT touched (no tercero columns):
--   - doc.guia_remision_detalle
--   - inventario.lote_rollo_detalle
--   - inventario.item_movimientos
--
-- If this was a COMPRA_INGRESO guia, also check whether the linked
-- doc.compra.tercero_id needs a separate fix — that table is
-- independent and not updated here.
--
-- UNIQUE constraint on guia_remision:
--   (tercero_id, serie, correlativo, guia_remision_tipo_id)
-- The UPDATE will fail if the correct tercero already has a guia
-- with the same serie+correlativo+tipo. Check the pre-flight
-- query below first.
--
-- ── HOW TO USE ──────────────────────────────────────────────
-- 1. Set v_guia_id and v_tercero_correcto_id below.
-- 2. Run the whole script — it ends in ROLLBACK (dry-run).
-- 3. Review the output. If everything looks right, flip ROLLBACK
--    to COMMIT and run again.
-- ============================================================
-- SELECT * FROM doc.guia_remision WHERE id=818
-- SELECT * FROM tercero WHERE nombre ILIKE '%damaris%'
BEGIN;

-- ── PARAMETERS ───────────────────────────────────────────────
DO $$
DECLARE
    v_guia_id              BIGINT  := 818;  -- <-- SET THIS: doc.guia_remision.id to fix
    v_tercero_correcto_id  INT     := 266;  -- <-- SET THIS: the correct tercero.id

    -- internals
    v_guia          doc.guia_remision%ROWTYPE;
    v_tipo          doc.guia_remision_tipo%ROWTYPE;
    v_tercero_mal   tercero%ROWTYPE;
    v_tercero_bien  tercero%ROWTYPE;
    v_n_lotes       INT;
    v_conflict      BIGINT;
    v_rows          INT;
BEGIN
    IF v_guia_id IS NULL OR v_tercero_correcto_id IS NULL THEN
        RAISE EXCEPTION 'Set v_guia_id and v_tercero_correcto_id before running.';
    END IF;

    -- ── Pre-flight checks ─────────────────────────────────────

    SELECT * INTO v_guia FROM doc.guia_remision WHERE id = v_guia_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'guia_remision id=% not found', v_guia_id;
    END IF;

    SELECT * INTO v_tipo FROM doc.guia_remision_tipo WHERE id = v_guia.guia_remision_tipo_id;

    SELECT * INTO v_tercero_mal  FROM tercero WHERE id = v_guia.tercero_id;
    SELECT * INTO v_tercero_bien FROM tercero WHERE id = v_tercero_correcto_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Correct tercero id=% not found', v_tercero_correcto_id;
    END IF;

    -- Check for UNIQUE conflict
    SELECT id INTO v_conflict
    FROM doc.guia_remision
    WHERE tercero_id              = v_tercero_correcto_id
      AND guia_remision_tipo_id   = v_guia.guia_remision_tipo_id
      AND serie                   IS NOT DISTINCT FROM v_guia.serie
      AND correlativo             IS NOT DISTINCT FROM v_guia.correlativo
      AND id                     <> v_guia_id;

    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION
            'UNIQUE conflict: guia_remision id=% already exists for tercero_id=% with the same serie/correlativo/tipo. Cannot rename.',
            v_conflict, v_tercero_correcto_id;
    END IF;

    SELECT COUNT(*) INTO v_n_lotes
    FROM inventario.lote
    WHERE documento_tipo = 'guia_remision'
      AND documento_id   = v_guia_id;

    RAISE NOTICE '=== PRE-FLIGHT ===';
    RAISE NOTICE 'Guia id=% tipo=% serie=% correlativo=%',
        v_guia_id, v_tipo.codigo, v_guia.serie, v_guia.correlativo;
    RAISE NOTICE 'Wrong   tercero: id=% nombre=%', v_tercero_mal.id,  v_tercero_mal.nombre;
    RAISE NOTICE 'Correct tercero: id=% nombre=%', v_tercero_bien.id, v_tercero_bien.nombre;
    RAISE NOTICE 'Lotes created by this guia: %  (propietario_id will also be updated)', v_n_lotes;
    RAISE NOTICE 'UNIQUE conflict check: OK (no conflict)';

    -- ── Fix 1: guia header ────────────────────────────────────
    UPDATE doc.guia_remision
    SET    tercero_id = v_tercero_correcto_id,
           fyh_mod    = now()
    WHERE  id = v_guia_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'Updated doc.guia_remision: % row(s)', v_rows;

    -- ── Fix 2: lotes born from this guia ─────────────────────
    -- Only CLIENTE_ENVIO_PROCESO creates lotes here; COMPRA_INGRESO
    -- will show 0 rows, which is expected.
    UPDATE inventario.lote
    SET    propietario_id = v_tercero_correcto_id,
           fyh_mod        = now()
    WHERE  documento_tipo = 'guia_remision'
      AND  documento_id   = v_guia_id
      AND  propietario_id = v_guia.tercero_id;  -- only touch the ones that matched the wrong tercero
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'Updated inventario.lote (propietario_id): % row(s)', v_rows;

    -- ── Post-check ────────────────────────────────────────────
    RAISE NOTICE '=== POST-CHECK ===';
    RAISE NOTICE 'guia_remision tercero_id now: %',
        (SELECT tercero_id FROM doc.guia_remision WHERE id = v_guia_id);

    RAISE NOTICE 'lote propietario_id after patch:';
    FOR v_n_lotes IN
        SELECT propietario_id
        FROM inventario.lote
        WHERE documento_tipo = 'guia_remision'
          AND documento_id   = v_guia_id
        GROUP BY propietario_id
    LOOP
        RAISE NOTICE '  propietario_id=%  count=%', v_n_lotes,
            (SELECT COUNT(*) FROM inventario.lote
             WHERE documento_tipo='guia_remision' AND documento_id=v_guia_id
               AND propietario_id=v_n_lotes);
    END LOOP;

END;
$$;

-- ── Flip ROLLBACK → COMMIT when satisfied ────────────────────
-- ROLLBACK;
COMMIT;

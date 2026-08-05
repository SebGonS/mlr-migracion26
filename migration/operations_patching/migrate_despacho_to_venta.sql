-- ============================================================================
-- MIGRATE · legacy public.despacho → doc.venta + doc.venta_detalle (COMMERCIAL)
-- ============================================================================
-- WHAT: builds the commercial spine for all legacy dispatches. The venta layer is
--   DOCUMENT-level (bills by partida + kg + price) and does NOT reference lotes, so
--   it migrates cleanly even for the ~68k dispatched rolls that never got dyed-output
--   lotes. Physical entrega linkage is best-effort ("link as we go").
--
-- PRICING — see PRICING_OWNERSHIP_MODEL.md. `precio_unit` is UNIFORMLY per-kg;
--   there is NO unit conversion (a per-roll reading implies $1.12/kg for finished dyed
--   fabric — below yarn cost; disproven in venta_price_partida_overlap.sql). The >=10
--   test only LABELS the row, never transforms the number:
--     regular client            → tipo=SERVICIO, precio_kg = precio_unit (~$1.95 dyeing rate)
--     MLR client & >= 10        → tipo=VENTA,    precio_kg = precio_unit (~$24.10 sale price)
--     MLR client & <  10 (353)  → tipo=VENTA,    precio_kg = precio_unit — INCOMPLETE:
--                                 only the dye charge was ever stored; sale price is not
--                                 reconstructable. Flagged in venta.observacion.
--   MLR client := cliente.procedencia='MLR' OR cliente.cliente ~* '(MLR|Oswaldo)'.
--
-- cantidad_kg = rollos_total × (pt_kilos / pt_rollos)  [the row's dispatched weight]
--   pt = produccion_tenido (tipo='Teñido') per partida — validated 98.6% coverage,
--   agrees with dispatched-lote weight to ~1.5%. Fallback: rollos_total × 22.5.
--
-- VENTA GROUPING — one venta per (tercero, factura-or-ref):
--   • real factura F###/B###   → FACTURADA (factura_serie/numero parsed)
--   • GI-* / G0x-* internal ref→ ABIERTA, raw ref in observacion (NOT a factura:
--                                GI-13 spans 6 clients — it cannot be an invoice)
--   • multi-factura "F,F" (106)→ ABIERTA, raw string in observacion (1:1 model can't
--                                hold two refs — see handoff settled decision #3)
--   • malformed / null         → ABIERTA
--   FACTURA CONFLICTS (42 of 966 real facturas appear against >1 tercero — legacy
--   data-entry error, client: "swallow it"): the live index is GLOBAL
--   `uq_venta_factura (factura_serie, factura_numero)`, so the ref can exist ONCE.
--   Resolution: the group with the MOST kg keeps the ref; the rest go ABIERTA with the
--   raw ref + a conflict note in observacion. Deterministic, lossless, constraint intact.
--
-- MLR SELF-DISPATCHES — legacy cliente 'MLR' (145 partidas) maps to tercero 1 =
--   Manufacturas la Real itself. Per client decision (2026-07-20): MIGRATE THEM as
--   ordinary ventas to tercero 1 (a "sale to ourselves"). is_mlr is already true for
--   them, so they land as tipo=VENTA. The ledger egress already posts origen→NULL
--   regardless, so this keeps commercial and physical consistent. (Superseded the
--   earlier "exclude as internal movement" plan.)
--
-- WRITES: doc.venta, doc.venta_detalle, and doc.entrega.venta_id (back-link only).
--   Touches NO lotes, NO movements, NO stock.
--
-- ⚠ DRY-RUN §0, run §1 in a txn, read §2, then COMMIT.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════════
-- §0 · DRY RUN — scope, grouping, and the conflict/incomplete counts
-- ══════════════════════════════════════════════════════════════════════════════
WITH cli AS (
    SELECT c.id, c.cliente,
           (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr,
           (c.cliente = 'MLR')                                   AS is_self
    FROM public.cliente c
),
pt AS (
    SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
    FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
),
base AS (
    SELECT dsp.id AS despacho_id, dsp.partida_id, dsp.fecha_despacho, dsp.rollos_total,
           dsp.precio_unit, NULLIF(btrim(dsp.nfactura),'') AS nfactura,
           mp.tercero_id, cli.is_mlr,
           COALESCE(dsp.rollos_total * (pt.pt_kilos/NULLIF(pt.pt_rollos,0)),
                    dsp.rollos_total * 22.5)               AS cantidad_kg,
           CASE WHEN NULLIF(btrim(dsp.nfactura),'') ~ '^[A-Za-z0-9]+-[0-9]+$'
                 AND upper(split_part(btrim(dsp.nfactura),'-',1)) ~ '^[FB][0-9]+$'
                THEN true ELSE false END                   AS is_real_factura
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN cli               ON cli.id = lp.cliente_id
    JOIN mes.partida mp    ON mp.id = dsp.partida_id
    LEFT JOIN pt           ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      -- MLR self-dispatches now INCLUDED (no is_self filter). Same line guards as §1.
      AND dsp.fecha_despacho IS NOT NULL
      AND COALESCE(dsp.rollos_total,0) > 0
      AND dsp.precio_unit IS NOT NULL AND dsp.precio_unit >= 0
)
SELECT
    (SELECT COUNT(*) FROM base)                                                AS despacho_rows_in_scope,
    (SELECT COUNT(*) FROM base WHERE is_real_factura)                          AS rows_real_factura,
    (SELECT COUNT(*) FROM base WHERE nfactura IS NOT NULL AND NOT is_real_factura) AS rows_internal_or_multi_ref,
    (SELECT COUNT(*) FROM base WHERE nfactura IS NULL)                         AS rows_no_ref,
    (SELECT COUNT(*) FROM base WHERE is_mlr AND precio_unit < 10)              AS rows_INCOMPLETE_dye_only,
    (SELECT COUNT(*) FROM base WHERE cantidad_kg IS NULL OR cantidad_kg <= 0)  AS rows_bad_kg_expect_0,
    -- ventas that would be created
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT
          CASE WHEN is_real_factura THEN 'F:'||tercero_id||':'||upper(split_part(nfactura,'-',1))||':'||split_part(nfactura,'-',2)
               WHEN nfactura IS NOT NULL THEN 'R:'||tercero_id||':'||nfactura
               ELSE 'N:'||despacho_id END
        FROM base) g)                                                          AS ventas_to_create,
    -- real facturas whose ref lands on >1 tercero (only ONE can keep it)
    (SELECT COUNT(*) FROM (
        SELECT upper(split_part(nfactura,'-',1)) s, split_part(nfactura,'-',2) n
        FROM base WHERE is_real_factura
        GROUP BY 1,2 HAVING COUNT(DISTINCT tercero_id) > 1) x)                 AS factura_conflicts_expect_42,
    -- MLR self-dispatch rows now INCLUDED (informational — become tercero-1 VENTA lines)
    (SELECT COUNT(*) FROM public.despacho d2
       JOIN public.partida l2 ON l2.id=d2.partida_id
       JOIN public.cliente c2 ON c2.id=l2.cliente_id
      WHERE COALESCE(d2.flg_elm,false)=false AND c2.cliente='MLR')             AS mlr_self_rows_included;


-- ══════════════════════════════════════════════════════════════════════════════
-- §1 · Execute
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL statement_timeout = 0;

-- The cre/mod triggers would overwrite our explicit usr_cre/fyh_cre (historical dates),
-- and the audit triggers need a JWT user context this migration session doesn't have.
-- Same pattern as the cuadre-cutoff trigger in the Track B backfill.
ALTER TABLE doc.venta         DISABLE TRIGGER trg_bi_venta_cre;
ALTER TABLE doc.venta         DISABLE TRIGGER trg_bu_venta_mod;
ALTER TABLE doc.venta         DISABLE TRIGGER trg_biud_venta_audit;
ALTER TABLE doc.venta_detalle DISABLE TRIGGER trg_biud_venta_detalle_audit;

DO $$
DECLARE
    v_op_tenido smallint;
    v_n_venta int; v_n_linea int; v_n_link int;
BEGIN
    SELECT id INTO v_op_tenido FROM mes.operacion WHERE codigo='TENIDO';

    ------------------------------------------------------------------------------
    -- 1. Working set: one row per legacy despacho, classified + priced
    ------------------------------------------------------------------------------
    CREATE TEMP TABLE _d ON COMMIT DROP AS
    WITH cli AS (
        SELECT c.id, (c.procedencia='MLR' OR c.cliente ~* '(MLR|Oswaldo)') AS is_mlr,
               (c.cliente='MLR') AS is_self
        FROM public.cliente c
    ),
    pt AS (
        SELECT partida_id, SUM(kilos) AS pt_kilos, SUM(rollos) AS pt_rollos
        FROM public.produccion_tenido WHERE tipo='Teñido' GROUP BY partida_id
    )
    SELECT dsp.id AS despacho_id, dsp.partida_id, dsp.fecha_despacho,
           dsp.rollos_total, dsp.precio_unit,
           NULLIF(btrim(dsp.nfactura),'')                       AS nfactura,
           mp.tercero_id,
           COALESCE(mp.partida_origen_id, mp.id)                AS root_partida_id,
           cli.is_mlr,
           ROUND(COALESCE(dsp.rollos_total * (pt.pt_kilos/NULLIF(pt.pt_rollos,0)),
                          dsp.rollos_total * 22.5)::numeric, 4) AS cantidad_kg,
           (NULLIF(btrim(dsp.nfactura),'') ~ '^[A-Za-z0-9]+-[0-9]+$'
             AND upper(split_part(btrim(dsp.nfactura),'-',1)) ~ '^[FB][0-9]+$') AS is_real_factura,
           (cli.is_mlr AND dsp.precio_unit < 10)                AS is_incomplete_sale
    FROM public.despacho dsp
    JOIN public.partida lp ON lp.id = dsp.partida_id
    JOIN cli               ON cli.id = lp.cliente_id
    JOIN mes.partida mp    ON mp.id = dsp.partida_id
    LEFT JOIN pt           ON pt.partida_id = dsp.partida_id
    WHERE COALESCE(dsp.flg_elm,false)=false
      -- MLR self-dispatches INCLUDED (become tercero-1 VENTA lines). Guards so every
      -- venta ends up with >=1 valid line (venta_detalle NOT NULL + CHECK cantidad_kg>0
      -- / precio_kg>=0; venta.fecha is NOT NULL):
      AND dsp.fecha_despacho IS NOT NULL
      AND COALESCE(dsp.rollos_total,0) > 0
      AND dsp.precio_unit IS NOT NULL AND dsp.precio_unit >= 0;

    -- grouping key + parsed factura parts
    ALTER TABLE _d ADD COLUMN grp_key text,
                   ADD COLUMN f_serie text,
                   ADD COLUMN f_numero int;
    UPDATE _d SET
        f_serie  = CASE WHEN is_real_factura THEN upper(split_part(nfactura,'-',1)) END,
        f_numero = CASE WHEN is_real_factura THEN NULLIF(split_part(nfactura,'-',2),'')::int END;
    UPDATE _d SET
        grp_key = CASE
            WHEN is_real_factura      THEN 'F:'||tercero_id||':'||f_serie||':'||f_numero
            WHEN nfactura IS NOT NULL THEN 'R:'||tercero_id||':'||nfactura
            ELSE                           'N:'||despacho_id
        END;

    ------------------------------------------------------------------------------
    -- 2. Resolve factura conflicts: a (serie,numero) may keep its ref on exactly ONE
    --    venta group (global unique index). Winner = most kg; tie → lowest tercero_id.
    ------------------------------------------------------------------------------
    CREATE TEMP TABLE _grp ON COMMIT DROP AS
    SELECT grp_key,
           MIN(tercero_id)                              AS tercero_id,
           MIN(fecha_despacho)                          AS fecha,
           bool_or(is_real_factura)                     AS is_real_factura,
           MIN(f_serie)                                 AS f_serie,
           MIN(f_numero)                                AS f_numero,
           MIN(nfactura)                                AS nfactura_raw,
           SUM(cantidad_kg)                             AS kg_total,
           bool_or(is_incomplete_sale)                  AS has_incomplete
    FROM _d GROUP BY grp_key;

    ALTER TABLE _grp ADD COLUMN keeps_factura boolean NOT NULL DEFAULT false;
    UPDATE _grp g SET keeps_factura = true
    WHERE g.is_real_factura
      AND g.grp_key = (
        SELECT g2.grp_key FROM _grp g2
        WHERE g2.is_real_factura AND g2.f_serie = g.f_serie AND g2.f_numero = g.f_numero
        ORDER BY g2.kg_total DESC, g2.tercero_id ASC
        LIMIT 1);

    ------------------------------------------------------------------------------
    -- 3. Create the ventas.
    --    Iterate a STABLE snapshot (_grp_src) and write ids into a SEPARATE map
    --    (_vmap) — never mutate the table being iterated.
    ------------------------------------------------------------------------------
    CREATE TEMP TABLE _grp_src ON COMMIT DROP AS SELECT * FROM _grp;
    CREATE TEMP TABLE _vmap(grp_key text PRIMARY KEY, venta_id bigint) ON COMMIT DROP;

    DECLARE r record; v_id bigint; v_obs text;
    BEGIN
        FOR r IN SELECT * FROM _grp_src ORDER BY grp_key LOOP
            v_obs := 'Migrado de legacy despacho.';
            IF r.nfactura_raw IS NOT NULL AND NOT r.keeps_factura THEN
                v_obs := v_obs || ' Ref. original: "' || r.nfactura_raw || '"'
                      || CASE WHEN r.is_real_factura
                              THEN ' (factura compartida entre varios clientes en legacy — no asignada aqui).'
                              ELSE ' (referencia interna / multi-factura, no es una factura).' END;
            END IF;
            IF r.has_incomplete THEN
                v_obs := v_obs || ' ATENCION: incluye lineas donde legacy solo registro el cargo de tenido'
                              || ' (precio de venta del rollo nunca almacenado).';
            END IF;

            INSERT INTO doc.venta (tercero_id, fecha, factura_serie, factura_numero,
                                   estado, observacion, usr_cre, fyh_cre)
            VALUES (r.tercero_id, r.fecha,
                    CASE WHEN r.keeps_factura THEN r.f_serie END,
                    CASE WHEN r.keeps_factura THEN r.f_numero END,
                    CASE WHEN r.keeps_factura THEN 'FACTURADA' ELSE 'ABIERTA' END::venta_estado_enum,
                    v_obs, 4, r.fecha)
            RETURNING id INTO v_id;

            INSERT INTO _vmap(grp_key, venta_id) VALUES (r.grp_key, v_id);
        END LOOP;
    END;

    ------------------------------------------------------------------------------
    -- 4. Charge lines — one per legacy despacho row. precio_kg AS-IS (no conversion).
    ------------------------------------------------------------------------------
    INSERT INTO doc.venta_detalle (
        venta_id, linea, tipo, operacion_id, item_id,
        color_x_cliente_id, tenido_id, articulo_tipo_id, flg_antipilling,
        partida_id, descripcion, cantidad_kg, precio_kg, usr_cre, fyh_cre)
    SELECT
        vm.venta_id,
        (row_number() OVER (PARTITION BY vm.venta_id ORDER BY d.despacho_id))::smallint,
        CASE WHEN d.is_mlr THEN 'VENTA' ELSE 'SERVICIO' END::venta_linea_tipo_enum,
        CASE WHEN d.is_mlr THEN NULL ELSE v_op_tenido END,   -- servicio = teñido; venta = producto
        NULL,                                                -- item: not resolvable from legacy
        p.color_x_cliente_id, p.tenido_id, p.articulo_tipo_id, COALESCE(p.flg_antipilling,false),
        d.root_partida_id,
        CASE WHEN d.is_incomplete_sale
             THEN 'Venta de rollo teñido — legacy solo registró el cargo de teñido (precio incompleto)'
        END,
        d.cantidad_kg,
        d.precio_unit,                                       -- AS-IS, already per-kg
        4, d.fecha_despacho
    FROM _d d
    JOIN _vmap vm ON vm.grp_key = d.grp_key
    JOIN mes.partida p ON p.id = d.root_partida_id
    WHERE d.cantidad_kg > 0;

    ------------------------------------------------------------------------------
    -- 5. Back-link existing outbound entregas (Track A/B created them) to the venta
    --    of the same (tercero, partida). Best-effort: only unlinked outbound entregas.
    ------------------------------------------------------------------------------
    WITH ent AS (
        SELECT DISTINCT e.id AS entrega_id, pp.partida_id, e.tercero_id
        FROM doc.entrega e
        JOIN doc.entrega_tipo et ON et.id = e.entrega_tipo_id
                                AND et.codigo IN ('DESPACHO_CLIENTE','VENTA_EGRESO')
        JOIN doc.entrega_detalle ed ON ed.entrega_id = e.id
        JOIN inventario.lote l      ON l.id = ed.lote_id
        JOIN mes.partida_paso_ejecucion ppe ON ppe.id = l.documento_id
                                           AND l.documento_tipo='partida_paso_ejecucion'
        JOIN mes.partida_paso pp    ON pp.id = ppe.partida_paso_id
        WHERE e.venta_id IS NULL
    ),
    pick AS (   -- one venta per (tercero, root partida): the earliest
        SELECT DISTINCT ON (d.tercero_id, d.root_partida_id)
               d.tercero_id, d.root_partida_id, vm.venta_id
        FROM _d d JOIN _vmap vm ON vm.grp_key = d.grp_key
        ORDER BY d.tercero_id, d.root_partida_id, d.fecha_despacho, vm.venta_id
    )
    UPDATE doc.entrega e
    SET venta_id = pick.venta_id
    FROM ent
    JOIN mes.partida mp ON mp.id = ent.partida_id
    JOIN pick ON pick.root_partida_id = COALESCE(mp.partida_origen_id, mp.id)
             AND pick.tercero_id      = ent.tercero_id
    WHERE e.id = ent.entrega_id AND e.venta_id IS NULL;
    GET DIAGNOSTICS v_n_link = ROW_COUNT;

    SELECT COUNT(*) INTO v_n_venta FROM _vmap;
    SELECT COUNT(*) INTO v_n_linea FROM _d WHERE cantidad_kg > 0;
    RAISE NOTICE 'venta migration: % ventas, % lineas, % entregas enlazadas.',
        v_n_venta, v_n_linea, v_n_link;
END $$;

ALTER TABLE doc.venta         ENABLE TRIGGER trg_bi_venta_cre;
ALTER TABLE doc.venta         ENABLE TRIGGER trg_bu_venta_mod;
ALTER TABLE doc.venta         ENABLE TRIGGER trg_biud_venta_audit;
ALTER TABLE doc.venta_detalle ENABLE TRIGGER trg_biud_venta_detalle_audit;


-- ══════════════════════════════════════════════════════════════════════════════
-- §2 · Verify  (run BEFORE COMMIT)
-- ══════════════════════════════════════════════════════════════════════════════
-- NOTE: identifies OUR rows via the run's temp map (_vmap), not usr_cre — the cre
-- trigger is disabled during §1 but this stays correct regardless.

-- (a) ventas created, split by estado; every FACTURADA has both factura fields
SELECT v.estado, COUNT(*) AS ventas,
       COUNT(*) FILTER (WHERE v.factura_serie IS NOT NULL AND v.factura_numero IS NOT NULL) AS with_factura,
       COUNT(*) FILTER (WHERE (v.factura_serie IS NULL) <> (v.factura_numero IS NULL))      AS chk_violation_expect_0
FROM doc.venta v JOIN _vmap m ON m.venta_id = v.id
GROUP BY v.estado ORDER BY ventas DESC;

-- (b) no duplicate factura ref (the global unique index must hold) — expect 0
SELECT COUNT(*) AS duplicate_factura_refs_expect_0
FROM (SELECT factura_serie, factura_numero FROM doc.venta
      WHERE factura_serie IS NOT NULL GROUP BY 1,2 HAVING COUNT(*) > 1) x;

-- (c) lines: totals, tipo split, and that importe reconciles
SELECT COUNT(*)                                         AS lineas,
       COUNT(*) FILTER (WHERE vd.tipo='VENTA')          AS tipo_venta,
       COUNT(*) FILTER (WHERE vd.tipo='SERVICIO')       AS tipo_servicio,
       COUNT(*) FILTER (WHERE vd.cantidad_kg <= 0)      AS bad_kg_expect_0,
       round(SUM(vd.importe)::numeric,2)                AS importe_total,
       round(AVG(vd.precio_kg)::numeric,2)              AS precio_kg_prom
FROM doc.venta_detalle vd JOIN _vmap m ON m.venta_id = vd.venta_id;

-- (d) every migrated venta has >=1 line, and line count == in-scope despacho rows
SELECT
    (SELECT COUNT(*) FROM _vmap m
       WHERE NOT EXISTS (SELECT 1 FROM doc.venta_detalle vd WHERE vd.venta_id=m.venta_id)) AS ventas_sin_lineas_expect_0,
    (SELECT COUNT(*) FROM _d WHERE cantidad_kg > 0)                                        AS despacho_rows_expected,
    (SELECT COUNT(*) FROM doc.venta_detalle vd JOIN _vmap m ON m.venta_id=vd.venta_id)     AS lineas_creadas;

-- (e) entregas linked
SELECT COUNT(*) AS entregas_con_venta,
       COUNT(*) FILTER (WHERE e.venta_id IS NULL) AS entregas_outbound_sin_venta
FROM doc.entrega e
JOIN doc.entrega_tipo et ON et.id=e.entrega_tipo_id
                        AND et.codigo IN ('DESPACHO_CLIENTE','VENTA_EGRESO');

-- COMMIT;    -- ← after §2: (a) sane split, chk=0; (b)=0; (c) bad_kg=0; (d) both 0; (e) linked > 0
-- ROLLBACK;  -- ← if anything is off

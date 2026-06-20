-- ═══════════════════════════════════════════════════════════════
-- Migration 22: doc.orden_servicio + lote_rollo_detalle extension
-- Commercial service order for internal MLR roll ingress/dyeing.
-- Run once against the live DB.
-- ═══════════════════════════════════════════════════════════════

-- ── doc.orden_servicio ────────────────────────────────────────
CREATE TABLE doc.orden_servicio (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tercero_id      INT         NOT NULL REFERENCES tercero(id),
    serie           TEXT        NOT NULL,
    correlativo     INT         NOT NULL,
    fecha_emision   DATE        NOT NULL DEFAULT CURRENT_DATE,
    fecha_entrega   DATE,
    rendimiento     TEXT,
    ancho           TEXT,
    flg_antipilling BOOLEAN     NOT NULL DEFAULT false,
    flg_urgente     BOOLEAN     NOT NULL DEFAULT false,
    observacion     TEXT,
    factura         TEXT,
    usr_cre INT, fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT, fyh_mod TIMESTAMPTZ,
    flg_elm BOOLEAN NOT NULL DEFAULT false,
    usr_elm INT,  fyh_elm TIMESTAMPTZ,
    UNIQUE (tercero_id, serie, correlativo)
);

-- ── doc.orden_servicio_detalle ────────────────────────────────
CREATE TABLE doc.orden_servicio_detalle (
    id                  BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    orden_servicio_id   BIGINT      NOT NULL REFERENCES doc.orden_servicio(id),
    linea               SMALLINT    NOT NULL,
    articulo_id         INT         NOT NULL REFERENCES articulo(id),
    malla               TEXT,
    cantidad            INT         NOT NULL CHECK (cantidad > 0),
    color_x_cliente_id  INT         NOT NULL REFERENCES color_x_cliente(id),
    tenido_id           INT         NOT NULL REFERENCES tenido(id),
    flg_doble_bolsa     BOOLEAN     NOT NULL DEFAULT false,
    UNIQUE (orden_servicio_id, linea)
);

-- ── doc.guia_remision_detalle — add linea (backfill from migration 07) ───
ALTER TABLE doc.guia_remision_detalle
    ADD COLUMN IF NOT EXISTS linea SMALLINT NOT NULL DEFAULT 1;
ALTER TABLE doc.guia_remision_detalle
    ADD COLUMN IF NOT EXISTS n_rollos SMALLINT;

UPDATE doc.guia_remision_detalle grd
SET linea = sub.rn
FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY guia_remision_id ORDER BY id) AS rn
    FROM doc.guia_remision_detalle
) sub
WHERE grd.id = sub.id;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_guia_remision_detalle_linea'
    ) THEN
        ALTER TABLE doc.guia_remision_detalle
            ADD CONSTRAINT uq_guia_remision_detalle_linea UNIQUE (guia_remision_id, linea);
    END IF;
END $$;
-- SELECT * FROM doc.guia_remision_detalle
-- ── inventario.lote_rollo_detalle — add orden_servicio_id ─────
ALTER TABLE inventario.lote_rollo_detalle
    ADD COLUMN orden_servicio_id BIGINT REFERENCES doc.orden_servicio(id);

-- -- ── Placeholder for legacy unmapped MLR rolls ─────────────────
-- -- Backfills lrd rows where both FKs are NULL (manually-ingressed rolls
-- -- predating this migration). Replace <MLR_TERCERO_ID> with the actual
-- -- tercero.id for MLR's manufacturing arm before running.
-- INSERT INTO doc.orden_servicio (
--     tercero_id, serie, correlativo, observacion
-- ) VALUES (
--     <MLR_TERCERO_ID>, 'LEGADO', 0, 'Placeholder — rollos MLR ingresados antes de migración 22'
-- );

-- UPDATE inventario.lote_rollo_detalle
-- SET orden_servicio_id = (
--     SELECT id FROM doc.orden_servicio
--     WHERE serie = 'LEGADO' AND correlativo = 0
-- )
-- WHERE guia_remision_id IS NULL
--   AND orden_servicio_id IS NULL;

-- ── Enforce at least one origin doc per roll ──────────────────
ALTER TABLE inventario.lote_rollo_detalle
    ADD CONSTRAINT chk_lrd_doc_origen
    CHECK (guia_remision_id IS NOT NULL OR orden_servicio_id IS NOT NULL);

-- ── Index (mirrors existing guia_remision_id index) ───────────
CREATE INDEX idx_lrd_orden_servicio_id
    ON inventario.lote_rollo_detalle (orden_servicio_id)
    WHERE orden_servicio_id IS NOT NULL;

-- ── Lock orden_servicio_id against direct updates ─────────────
REVOKE UPDATE (orden_servicio_id) ON inventario.lote_rollo_detalle FROM anon, authenticated;

-- ── doc.vw_ordenes_servicio ───────────────────────────────────
CREATE OR REPLACE VIEW doc.vw_ordenes_servicio AS
SELECT
    os.id,
    os.tercero_id,
    t.nombre                        AS tercero_nombre,
    os.serie,
    os.correlativo,
    os.fecha_emision,
    os.fecha_entrega,
    os.flg_urgente,
    os.flg_antipilling,
    os.observacion,
    os.fyh_cre,
    COALESCE(lineas.total, 0)       AS total_rollos_pedidos,
    COALESCE(lotes.total, 0)        AS total_rollos_ingresados
FROM doc.orden_servicio os
LEFT JOIN tercero t ON t.id = os.tercero_id
LEFT JOIN LATERAL (
    SELECT SUM(osd.cantidad) AS total
    FROM doc.orden_servicio_detalle osd
    WHERE osd.orden_servicio_id = os.id
) lineas ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total
    FROM inventario.lote_rollo_detalle lrd
    JOIN inventario.lote l ON l.id = lrd.lote_id AND l.fyh_elm IS NULL
    WHERE lrd.orden_servicio_id = os.id
) lotes ON true
WHERE os.flg_elm = false;

-- ── Grants ────────────────────────────────────────────────────
GRANT SELECT ON doc.orden_servicio          TO authenticated;
GRANT SELECT ON doc.orden_servicio_detalle  TO authenticated;
GRANT SELECT ON doc.vw_ordenes_servicio     TO authenticated;

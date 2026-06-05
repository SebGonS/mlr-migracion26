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
    estado          TEXT        NOT NULL DEFAULT 'BORRADOR'
                    CHECK (estado IN ('BORRADOR','AUTORIZADA','EN_PROCESO','COMPLETADA','ANULADA')),
    estado_entrega  TEXT        NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (estado_entrega IN ('PENDIENTE','PARCIAL','COMPLETO')),
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

-- ── inventario.lote_rollo_detalle — add orden_servicio_id ─────
ALTER TABLE inventario.lote_rollo_detalle
    ADD COLUMN orden_servicio_id BIGINT REFERENCES doc.orden_servicio(id);

-- ── Grants ────────────────────────────────────────────────────
GRANT SELECT ON doc.orden_servicio          TO authenticated;
GRANT SELECT ON doc.orden_servicio_detalle  TO authenticated;

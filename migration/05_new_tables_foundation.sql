-- ═══════════════════════════════════════════════════════════════
-- Step 5: New foundation tables
-- Dependency order: unidad → item_tipo → item → item_*_detalle
--                   inventario.almacen → ubicacion → lote → movimientos
-- ═══════════════════════════════════════════════════════════════

-- ── unidad ─────────────────────────────────────────────────────
CREATE TABLE unidad (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    UNIQUE (codigo_canon),
    nombre TEXT NOT NULL,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ
);
CREATE TRIGGER trg_bi_unidad_codigo_canon
BEFORE INSERT OR UPDATE ON unidad
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

INSERT INTO unidad (codigo, nombre) VALUES
 ('kg',  'Kilogramo'),
 ('g',   'Gramo'),
 ('mg',  'Miligramo'),
 ('ton', 'Tonelada'),
 ('L',   'Litro'),
 ('mL',  'Mililitro'),
 ('UN',  'Unidad');

-- ── unidad_conversion ──────────────────────────────────────────
CREATE TABLE unidad_conversion (
    de_unidad_id INT REFERENCES unidad(id),
    a_unidad_id  INT REFERENCES unidad(id),
    factor NUMERIC(18,6) NOT NULL,
    PRIMARY KEY (de_unidad_id, a_unidad_id)
);
INSERT INTO unidad_conversion (de_unidad_id, a_unidad_id, factor) VALUES
((SELECT id FROM unidad WHERE codigo = 'kg'),  (SELECT id FROM unidad WHERE codigo = 'g'),   1000.000000),
((SELECT id FROM unidad WHERE codigo = 'g'),   (SELECT id FROM unidad WHERE codigo = 'kg'),  0.001000),
((SELECT id FROM unidad WHERE codigo = 'g'),   (SELECT id FROM unidad WHERE codigo = 'mg'),  1000.000000),
((SELECT id FROM unidad WHERE codigo = 'mg'),  (SELECT id FROM unidad WHERE codigo = 'g'),   0.001000),
((SELECT id FROM unidad WHERE codigo = 'kg'),  (SELECT id FROM unidad WHERE codigo = 'ton'), 0.001000),
((SELECT id FROM unidad WHERE codigo = 'ton'), (SELECT id FROM unidad WHERE codigo = 'kg'),  1000.000000),
((SELECT id FROM unidad WHERE codigo = 'L'),   (SELECT id FROM unidad WHERE codigo = 'mL'),  1000.000000),
((SELECT id FROM unidad WHERE codigo = 'mL'),  (SELECT id FROM unidad WHERE codigo = 'L'),   0.001000);

-- ── item_tipo ──────────────────────────────────────────────────
CREATE TABLE item_tipo (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_item_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON item_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
INSERT INTO item_tipo (codigo, descripcion) VALUES
    ('ROLLO',  'Rollo de tela (materia prima o en partida)'),
    ('INSUMO', 'Insumo químico / colorante / auxiliar');

-- ── insumo_tipo ────────────────────────────────────────────────
CREATE TABLE insumo_tipo (
    id  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text,
    descripcion text,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE (codigo_canon)
);
CREATE TRIGGER trg_bi_insumo_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON insumo_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
INSERT INTO insumo_tipo (codigo, nombre) VALUES
    ('QUIM',  'quimico'),
    ('COL',   'colorante'),
    ('AUX',   'auxiliar');

-- ── colorante_tipo ─────────────────────────────────────────────
CREATE TABLE colorante_tipo (
    id  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE (codigo_canon)
);
CREATE TRIGGER trg_bi_colorante_tipo_codigo_canon   -- NOTE: different from tablas.sql which reused wrong name
BEFORE INSERT OR UPDATE ON colorante_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
INSERT INTO colorante_tipo (nombre, codigo) VALUES
    ('directo',  'DIR'),
    ('disperso', 'DISP'),
    ('reactivo', 'RX');

-- ── item ───────────────────────────────────────────────────────
CREATE TABLE item (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre TEXT NOT NULL,
    item_tipo_id integer NOT NULL REFERENCES item_tipo(id),
    unidad_id integer NOT NULL REFERENCES unidad(id),
    stock_minimo NUMERIC(12,4),
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    flg_elm boolean NOT NULL DEFAULT FALSE,
    usr_elm int,
    fyh_elm timestamptz,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_item_codigo_canon
BEFORE INSERT OR UPDATE ON item
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

-- ── item_insumo_detalle ────────────────────────────────────────
-- Requires medida_enum to exist (legacy type or defined in 02_enums.sql)
CREATE TABLE item_insumo_detalle (
    item_id INT PRIMARY KEY REFERENCES item(id),
    medida medida_enum NOT NULL,
    insumo_tipo_id smallint NOT NULL REFERENCES insumo_tipo(id),
    colorante_tipo_id smallint REFERENCES colorante_tipo(id),
    factor_stock NUMERIC(8,6) NOT NULL DEFAULT 1,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_ai_gen_codigo_item_insumo ON item_insumo_detalle;
CREATE TRIGGER trg_ai_gen_codigo_item_insumo
AFTER INSERT ON item_insumo_detalle
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_gen_codigo_item_insumo();

-- ── item_rollo_detalle ─────────────────────────────────────────
-- FIX (BUG 1): CREATE before any ALTER on this table.
-- fibra column is NOT here — it lives on articulo (Step 4).
CREATE TABLE item_rollo_detalle (
    item_id INT PRIMARY KEY REFERENCES item(id),
    articulo_id INT NOT NULL REFERENCES articulo(id),
    flg_rib boolean NOT NULL DEFAULT FALSE,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_ai_gen_codigo_item_rollo ON item_rollo_detalle;
CREATE TRIGGER trg_ai_gen_codigo_item_rollo
AFTER INSERT ON item_rollo_detalle
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_gen_codigo_item_rollo();

-- ── inventario.item_movimiento_tipo ────────────────────────────
CREATE OR REPLACE VIEW inventario.vw_item_movimiento_categoria AS
SELECT
    c.codigo::text AS codigo,
    CASE c.codigo
        WHEN 'COMPRA'         THEN 'Compras'
        WHEN 'VENTA'          THEN 'Ventas'
        WHEN 'PRODUCCION'     THEN 'Producción'
        WHEN 'partida_EXTERNO'THEN 'partida externo'
        WHEN 'DEVOLUCION'     THEN 'Devoluciones'
        WHEN 'AJUSTE'         THEN 'Ajustes'
        WHEN 'TRANSFERENCIA'  THEN 'Transferencias'
    END AS nombre
FROM unnest(enum_range(NULL::item_movimiento_tipo_categoria_enum)) AS c(codigo);

CREATE TABLE inventario.item_movimiento_tipo (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text NOT NULL,
    categoria item_movimiento_tipo_categoria_enum NOT NULL,
    factor SMALLINT NOT NULL CHECK (factor IN (1, -1, 0)),
    descripcion text,
    flg_afecta_stock    BOOLEAN NOT NULL DEFAULT true,
    flg_valorizable     BOOLEAN NOT NULL DEFAULT true,
    flg_recalcula_costo BOOLEAN NOT NULL DEFAULT false,
    req_partner         BOOLEAN NOT NULL DEFAULT false,
    req_origen          BOOLEAN NOT NULL DEFAULT false,
    req_destino         BOOLEAN NOT NULL DEFAULT false,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    flg_elm boolean NOT NULL DEFAULT FALSE,
    usr_elm int,
    fyh_elm timestamptz,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_item_movimiento_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON inventario.item_movimiento_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

-- Seeds for item_movimiento_tipo (full list from tablas.sql)
INSERT INTO inventario.item_movimiento_tipo
(codigo, nombre, categoria, factor, flg_afecta_stock, flg_valorizable, flg_recalcula_costo, req_partner, req_origen, req_destino, descripcion)
VALUES
('COMPRA_ING',       'Compra – Recepción',                        'COMPRA',          1,  true,  true,  true,  true,  false, true,  'Ingreso por compra local o importación'),
('VENTA_EGR',        'Venta – Despacho',                          'VENTA',           -1, true,  true,  false, true,  true,  false, 'Salida por venta a cliente'),
('PROD_CONSUMO',     'Producción – Consumo MP',                   'PRODUCCION',      -1, true,  true,  false, false, true,  false, 'Consumo de materia prima hacia orden de producción'),
('PROD_ING',         'Producción – Ingreso PT',                   'PRODUCCION',      1,  true,  true,  true,  false, false, true,  'Ingreso de producto terminado'),
('EXT_ENVIO',        'partida Ext. – Envío',                      'partida_EXTERNO', -1, true,  false, false, true,  true,  false, 'Salida a maquilador/tercero para partida externo'),
('EXT_RETORNO',      'partida Ext. – Retorno',                    'partida_EXTERNO', 1,  true,  true,  true,  true,  false, true,  'Retorno con valor agregado'),
('INT_TRANSFER_ING', 'Transferencia Interna',                     'TRANSFERENCIA',   1,  true,  true,  false, false, true,  true,  'Movimiento entre almacenes propios'),
('INT_TRANSFER_EGR', 'Transferencia Interna',                     'TRANSFERENCIA',   -1, true,  true,  false, false, true,  true,  'Movimiento entre almacenes propios'),
('DEV_CLI_ING',      'Devolución Cliente',                        'DEVOLUCION',      1,  true,  true,  false, true,  false, true,  'Cliente devuelve'),
('DEV_CLI_EGR',      'Devolución Cliente',                        'DEVOLUCION',      -1, true,  true,  false, true,  true,  false, 'Se devuelve al cliente'),
('DEV_PROV_EGR',     'Devolución Proveedor',                      'DEVOLUCION',      -1, true,  true,  false, true,  true,  false, 'Salida por devolución a proveedor'),
('SERV_ING',         'Servicio – Recepción Material Cliente',     'partida_EXTERNO', 1,  true,  false, false, true,  false, true,  'Recepción de material de cliente'),
('SERV_EGR',         'Servicio – Despacho Material Cliente',      'partida_EXTERNO', -1, true,  false, false, true,  true,  false, 'Despacho de material procesado al cliente'),
('SERV_DEV_ING',     'Servicio – Devolución Material Cliente',    'partida_EXTERNO', 1,  true,  false, false, true,  false, true,  'Cliente devuelve material procesado'),
('AJUSTE_POS',       'Ajuste Inventario (+)',                     'AJUSTE',          1,  true,  true,  true,  false, false, true,  'Corrección positiva de inventario'),
('AJUSTE_NEG',       'Ajuste Inventario (-)',                     'AJUSTE',          -1, true,  true,  false, false, true,  false, 'Corrección negativa de inventario'),
('PESAJE_POS',       'Pesaje – Corrección (+)',                   'AJUSTE',          1,  true,  false, false, false, false, true,  'Corrección de peso (real > declarado)'),
('PESAJE_NEG',       'Pesaje – Corrección (-)',                   'AJUSTE',          -1, true,  false, false, false, true,  false, 'Corrección de peso (real < declarado)'),
-- Muestras: no valorizables ni recalculan costo — son movimientos de trazabilidad, no de compra.
-- MUESTRA_ING cubre recepciones de muestra de proveedor sin documento de compra.
-- MUESTRA_EGR cubre salidas de muestra (cliente, partida, etc.) registradas en salida_inventario con motivo='muestra'.
('MUESTRA_ING',      'Muestra – Ingreso',                         'AJUSTE',          1,  true,  false, false, false, false, true,  'Ingreso de muestra de proveedor'),
('MUESTRA_EGR',      'Muestra – Egreso',                          'AJUSTE',          -1, true,  false, false, false, true,  false, 'Salida de muestra para cliente/partida'),
-- Production reversals: paired with PROD_ING / PROD_CONSUMO to cancel a completed paso.
-- PROD_ING_REV     reverses the output lote ingress  (factor -1, removes it from stock).
-- PROD_CONSUMO_REV reverses the input lote backflush (factor +1, restores it to stock).
-- Not valorizable — the original movements already set valuation; reversal is stock-only.
('PROD_ING_REV',     'Producción – Anulación Ingreso PT',         'PRODUCCION',      -1, true,  false, false, false, true,  false, 'Anulación de ingreso de producto terminado (reversal de PROD_ING)'),
('PROD_CONSUMO_REV', 'Producción – Anulación Consumo MP',         'PRODUCCION',      1,  true,  false, false, false, false, true,  'Anulación de consumo de materia prima (reversal de PROD_CONSUMO)');

-- ── inventario.item_movimiento_motivo ────────────────────────
-- Movement reason catalog scoped per movement type (≈ SAP T157 / MSEG.GRUND).
-- motivo_id on item_movimientos is nullable — most movements need no reason.
CREATE TABLE inventario.item_movimiento_motivo (
    id                      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_movimiento_tipo_id smallint NOT NULL REFERENCES inventario.item_movimiento_tipo(id),
    codigo                  text NOT NULL,
    nombre                  text NOT NULL,
    UNIQUE (item_movimiento_tipo_id, codigo)
);

INSERT INTO inventario.item_movimiento_motivo (item_movimiento_tipo_id, codigo, nombre)
SELECT id, 'MATIZADO',        'Corrección de color en máquina' FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'
UNION ALL
SELECT id, 'SOBRANTE_FISICO', 'Sobrante en conteo físico'      FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS'
UNION ALL
SELECT id, 'FALTANTE_FISICO', 'Faltante en conteo físico'      FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_NEG'
UNION ALL
SELECT id, 'MERMA',           'Merma / pérdida en partida'     FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_NEG';

-- ── inventario.almacen ────────────────────────────────────────
CREATE TABLE inventario.almacen (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre TEXT NOT NULL,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_almacen_codigo_canon
BEFORE INSERT OR UPDATE ON inventario.almacen
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

-- ── inventario.ubicacion ──────────────────────────────────────
CREATE TABLE inventario.ubicacion (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    almacen_id INT NOT NULL REFERENCES inventario.almacen(id),
    codigo TEXT NOT NULL,
    codigo_canon TEXT NOT NULL,
    nombre TEXT NOT NULL,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE (almacen_id, codigo_canon)
);
CREATE TRIGGER trg_bi_ubicacion_codigo_canon
BEFORE INSERT OR UPDATE ON inventario.ubicacion
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

DROP TRIGGER IF EXISTS trg_bi_gen_codigo_ubicacion ON inventario.ubicacion;
CREATE TRIGGER trg_bi_gen_codigo_ubicacion
BEFORE INSERT ON inventario.ubicacion
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_gen_codigo_ubicacion();

-- ── tercero ───────────────────────────────────────────────────
-- Master entity for all external trading parties (ERP concept: "tercero").
-- Replaces the separate legacy `cliente` and `proveedor` tables as the
-- canonical source of truth. flg_cliente / flg_proveedor indicate roles —
-- a party can hold both simultaneously.
-- cliente_id / proveedor_id are kept as migration cross-references only;
-- they may be dropped once legacy tables are retired.
-- Row id=1 = MLR (our own company), with both flags false.
CREATE TABLE tercero (
    id               INT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo           TEXT NOT NULL UNIQUE,
    codigo_canon     TEXT NOT NULL UNIQUE,
    nombre           TEXT NOT NULL,              -- commercial / trade name
    razon_social     TEXT,                       -- legal registered name (razón social)
    ruc              TEXT UNIQUE,                -- 11-digit Peruvian tax ID
    direccion        TEXT,
    telefono         TEXT,
    correo           TEXT,
    procedencia      TEXT,                       -- country / region of origin
    flg_cliente      BOOLEAN NOT NULL DEFAULT false,
    flg_proveedor    BOOLEAN NOT NULL DEFAULT false,
    -- Migration cross-references (nullable; removed once legacy tables are retired)
    cliente_id       INT REFERENCES cliente(id),   -- primary legacy cliente id
    cliente_id2      INT REFERENCES cliente(id),   -- secondary: MLR/X alias that was merged into this row
    proveedor_id     INT REFERENCES proveedor(id),
    -- Audit
    usr_cre INT REFERENCES usuario(id),
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod INT REFERENCES usuario(id),
    fyh_mod TIMESTAMPTZ,
    flg_elm BOOL DEFAULT false,
    usr_elm INT,
    fyh_elm TIMESTAMPTZ
);

ALTER TABLE color_x_cliente ADD COLUMN IF NOT EXISTS tercero_id INT REFERENCES tercero(id);

CREATE TRIGGER trg_bi_tercero_codigo_canon
BEFORE INSERT OR UPDATE ON tercero
FOR EACH ROW EXECUTE FUNCTION fn_trg_set_codigo_canon();

-- Row 1 = MLR (our own company)
INSERT INTO tercero (codigo, nombre) VALUES ('MLR', 'Manufacturas la Real');

GRANT SELECT ON tercero TO authenticated;

-- ── inventario.lote ───────────────────────────────────────────
CREATE TABLE inventario.lote (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    secuencia int NOT NULL,
    item_id int NOT NULL REFERENCES item(id),
    documento_tipo TEXT,
    documento_id BIGINT,
    cantidad numeric(10,4) CHECK (cantidad > 0),
    detalles JSONB,
    estado_calidad calidad_estado_enum DEFAULT 'PENDIENTE',
    propietario_id int NULL REFERENCES tercero(id),
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    flg_elm BOOL DEFAULT false,
    usr_elm INT,
    fyh_elm TIMESTAMPTZ
);

CREATE TABLE inventario.lote_secuencia_anual (
    ano INT PRIMARY KEY,
    ultimo_valor INT NOT NULL DEFAULT 0
);

-- Auto-generates lote.secuencia on INSERT using a per-year counter.
-- Fires BEFORE INSERT so NEW.secuencia is set before the row lands.
-- WHEN (NEW.secuencia IS NULL) allows migration scripts to override by
-- supplying an explicit value (e.g. OVERRIDING SYSTEM VALUE inserts that
-- need to preserve a legacy secuencia).
CREATE OR REPLACE FUNCTION inventario.trfn_generar_secuencia_lote()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_ano INT;
BEGIN
    v_ano := date_part('year', COALESCE(NEW.fyh_cre, NOW()));
    INSERT INTO inventario.lote_secuencia_anual (ano, ultimo_valor)
    VALUES (v_ano, 1)
    ON CONFLICT (ano)
    DO UPDATE SET ultimo_valor = inventario.lote_secuencia_anual.ultimo_valor + 1
    RETURNING ultimo_valor INTO NEW.secuencia;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bi_lote_secuencia
BEFORE INSERT ON inventario.lote
FOR EACH ROW
WHEN (NEW.secuencia IS NULL)
EXECUTE FUNCTION inventario.trfn_generar_secuencia_lote();

-- ── inventario.item_movimientos ───────────────────────────────
CREATE SEQUENCE IF NOT EXISTS inventario.mov_doc_seq START 1;

CREATE TABLE inventario.item_movimientos (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_movimiento_id BIGINT NOT NULL,                  -- posting event grouping key (≈ SAP MBLNR)
    item_id INT NOT NULL REFERENCES item(id),
    lote_id int REFERENCES inventario.lote(id),
    item_movimiento_tipo_id smallint REFERENCES inventario.item_movimiento_tipo(id) NOT NULL,
    origen_ubicacion_id INT NULL REFERENCES inventario.ubicacion(id),
    destino_ubicacion_id INT NULL REFERENCES inventario.ubicacion(id),
    cantidad NUMERIC(12,4) NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12,4),                      -- NULL for non-valorizable movements (flg_valorizable=false)
    monto NUMERIC(16,4) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    documento_tipo TEXT,
    documento_id int,
    motivo_id smallint REFERENCES inventario.item_movimiento_motivo(id), -- ≈ SAP MSEG.GRUND
    observacion TEXT,
    usr_cre int,
    fyh_cre timestamptz DEFAULT NOW()
);

-- ── inventario.item_valoracion (Moving Average Price store — mirrors SAP MBEW) ──
CREATE TABLE inventario.item_valoracion (
    item_id         INT            PRIMARY KEY REFERENCES item(id),
    precio_promedio NUMERIC(12,4)  NOT NULL DEFAULT 0,
    stock_qty       NUMERIC(12,4)  NOT NULL DEFAULT 0,
    stock_valorado  NUMERIC(16,4)  NOT NULL DEFAULT 0,
    fyh_mod         TIMESTAMPTZ    DEFAULT now()
);

-- MAP trigger
CREATE OR REPLACE FUNCTION inventario.fn_trg_actualizar_map()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_flg_valorizable boolean;
    v_flg_recalcula   boolean;
    v_factor          smallint;
    v_map             numeric(12,4);
    v_stock_qty       numeric(12,4);
    v_stock_valorado  numeric(16,4);
BEGIN
    IF NEW.precio_unitario IS NULL THEN RETURN NEW; END IF;

    SELECT imt.flg_valorizable, imt.flg_recalcula_costo, imt.factor
    INTO v_flg_valorizable, v_flg_recalcula, v_factor
    FROM inventario.item_movimiento_tipo imt
    WHERE imt.id = NEW.item_movimiento_tipo_id;

    IF NOT v_flg_valorizable THEN RETURN NEW; END IF;

    -- Ensure row exists, then lock it to serialize concurrent postings for the same item
    INSERT INTO inventario.item_valoracion (item_id, precio_promedio, stock_qty, stock_valorado)
    VALUES (NEW.item_id, 0, 0, 0)
    ON CONFLICT (item_id) DO NOTHING;

    SELECT precio_promedio, stock_qty, stock_valorado
    INTO v_map, v_stock_qty, v_stock_valorado
    FROM inventario.item_valoracion
    WHERE item_id = NEW.item_id
    FOR UPDATE;  -- row-level lock: serializes concurrent movements for the same item

    IF v_factor > 0 THEN
        IF v_flg_recalcula THEN
            v_stock_valorado := v_stock_valorado + (NEW.cantidad * NEW.precio_unitario);
            v_stock_qty      := v_stock_qty + NEW.cantidad;
            v_map            := CASE WHEN v_stock_qty > 0
                                     THEN ROUND(v_stock_valorado / v_stock_qty, 4) ELSE 0 END;
        ELSE
            v_stock_valorado := v_stock_valorado + (NEW.cantidad * v_map);
            v_stock_qty      := v_stock_qty + NEW.cantidad;
        END IF;
    ELSE
        v_stock_valorado := GREATEST(0, v_stock_valorado - (NEW.cantidad * v_map));
        v_stock_qty      := GREATEST(0, v_stock_qty - NEW.cantidad);
        IF v_stock_qty = 0 THEN v_stock_valorado := 0; END IF;
    END IF;

    INSERT INTO inventario.item_valoracion (item_id, precio_promedio, stock_qty, stock_valorado, fyh_mod)
    VALUES (NEW.item_id, v_map, v_stock_qty, v_stock_valorado, now())
    ON CONFLICT (item_id) DO UPDATE
        SET precio_promedio = EXCLUDED.precio_promedio
        ,
            stock_qty       = EXCLUDED.stock_qty,
            stock_valorado  = EXCLUDED.stock_valorado,
            fyh_mod         = EXCLUDED.fyh_mod;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ai_item_movimientos_map
AFTER INSERT ON inventario.item_movimientos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_trg_actualizar_map();

-- ── inventario.cuadre / cuadre_detalle ────────────────────────
-- Inventory reconciliation (cuadre de inventario).
CREATE TYPE inventario.cuadre_estado_enum AS ENUM (
    'borrador',   -- just created, items being counted
    'preparado',  -- counts complete, ready to finalise
    'ejecutado',  -- adjustments posted, closed
    'cancelado'   -- cancelled before execution
);

CREATE TABLE inventario.cuadre (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_cuadre TIMESTAMPTZ NOT NULL DEFAULT now(),
    fecha_cierre TIMESTAMPTZ,
    estado       inventario.cuadre_estado_enum NOT NULL DEFAULT 'borrador',
    usr_cre      INT  REFERENCES usuario(id),
    fyh_cre      TIMESTAMPTZ DEFAULT now(),
    usr_mod      INT  REFERENCES usuario(id),
    fyh_mod      TIMESTAMPTZ
);

CREATE TABLE inventario.cuadre_detalle (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cuadre_id               BIGINT NOT NULL REFERENCES inventario.cuadre(id),
    item_id                 INT    NOT NULL REFERENCES item(id),
    cantidad_sistema        NUMERIC(12,4),
    precio_promedio_sistema NUMERIC(12,6),
    stock_valorado_sistema  NUMERIC(14,4),
    ult_precio_compra       NUMERIC(12,4),
    cantidad_contada        NUMERIC(12,4),
    usr_mod                 INT  REFERENCES usuario(id),
    fyh_mod                 TIMESTAMPTZ,
    UNIQUE (cuadre_id, item_id)
);

CREATE OR REPLACE VIEW inventario.vw_cuadre AS
SELECT
    c.id           AS cuadre_id,
    c.fecha_cuadre,
    c.fecha_cierre,
    c.estado,
    (SELECT MAX(c2.fecha_cierre)
     FROM inventario.cuadre c2
     WHERE c2.estado = 'ejecutado'
       AND c2.id < c.id) AS ult_cuadre_ejecutado_fecha
FROM inventario.cuadre c;

GRANT SELECT ON inventario.cuadre         TO authenticated;
GRANT SELECT ON inventario.cuadre_detalle TO authenticated;

GRANT SELECT ON inventario.vw_cuadre      TO authenticated;

-- -- -- Codigos de roles para notificaciones code
-- -- admin
-- -- calidad
-- -- compras
-- -- inventario
-- -- jefe_planta
-- -- operador_produccion
-- -- sistema
-- -- supervisor_produccion

-- 1. ENUM DEFINITIONS (Must be created before they are used in tables)
-- CREATE TYPE insumo_tipo_enum AS ENUM ('quimico', 'colorante', 'auxiliar'); -- Added based on usage below

-----AGREGAR NUEVA DEFINICION DE vw_COLOR_X_CLOETE ára terminar funcion de get insumo
----luego hacer get insumo
----Notas
----A futuro separar movimientos de los documentos de negocio
---Crear capa de "documentos de movimiento" con motivo explicito en vez de derivarlo



ALTER TABLE color
ADD COLUMN codigo text;
ALTER TABLE color ADD COLUMN hex text;
ALTER TABLE color_x_cliente ADD COLUMN hex text;

UPDATE color
SET codigo =
    UPPER(
        regexp_replace(color, '[^a-zA-Z0-9]', '', 'g')
    );

------ ALTER TABLE color
------ ALTER COLUMN codigo SET NOT NULL;

ALTER TABLE color
ADD CONSTRAINT color_codigo_uk UNIQUE (codigo);


CREATE OR REPLACE VIEW vw_colores AS 
 SELECT a.id AS color_x_cliente_id,
    b.id AS color_id,
    b.color,
    c.id AS cliente_id,
    c.cliente AS tono,
    c.cliente AS cliente,
    a.hex as color_x_cliente_hex,
    b.hex as color_hex
   FROM ((color_x_cliente a
     JOIN color b ON ((a.color_id = b.id)))
     JOIN cliente c ON ((a.cliente_id = c.id)));



CREATE TYPE calidad_estado_enum AS ENUM (
  'PENDIENTE',     -- waiting inspection
  'APROBADO',      -- usable
  'RECHAZADO',     -- scrap
  'REPROCESO',     -- must go back to process
  'CUARENTENA'     -- blocked, decision pending
);

-- CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION public.fn_trg_set_codigo_canon()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.codigo IS NOT NULL THEN
        NEW.codigo_canon := lower(unaccent(NEW.codigo));
    END IF;
    RETURN NEW;
END;
$$;


-- Unit of Measure master
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
INSERT INTO unidad (codigo, nombre)
VALUES
 ('kg',  'Kilogramo'),
 ('g',   'Gramo'),
 ('mg',  'Miligramo'),
 ('ton', 'Tonelada'),
 ('L',   'Litro'),
 ('mL',  'Mililitro');
INSERT INTO unidad (codigo, nombre)
VALUES
 ('UN', 'Unidad');


-- UoM conversions within a UoM group (all reduce to base_uom) Not needed for now
CREATE TABLE unidad_conversion (
    de_unidad_id INT REFERENCES unidad(id),
    a_unidad_id INT REFERENCES unidad(id),
    factor NUMERIC(18,6) NOT NULL,      -- qty_in_to = qty_in_from * factor
    PRIMARY KEY (de_unidad_id, a_unidad_id)
);
-- Mass conversions
INSERT INTO unidad_conversion (de_unidad_id, a_unidad_id, factor)
VALUES
-- kg <-> g
((SELECT id FROM unidad WHERE codigo = 'kg'),
 (SELECT id FROM unidad WHERE codigo = 'g'),
 1000.000000),

((SELECT id FROM unidad WHERE codigo = 'g'),
 (SELECT id FROM unidad WHERE codigo = 'kg'),
 0.001000),

-- g <-> mg
((SELECT id FROM unidad WHERE codigo = 'g'),
 (SELECT id FROM unidad WHERE codigo = 'mg'),
 1000.000000),

((SELECT id FROM unidad WHERE codigo = 'mg'),
 (SELECT id FROM unidad WHERE codigo = 'g'),
 0.001000),

-- kg <-> ton
((SELECT id FROM unidad WHERE codigo = 'kg'),
 (SELECT id FROM unidad WHERE codigo = 'ton'),
 0.001000),

((SELECT id FROM unidad WHERE codigo = 'ton'),
 (SELECT id FROM unidad WHERE codigo = 'kg'),
 1000.000000);

-- Volume conversions
INSERT INTO unidad_conversion (de_unidad_id, a_unidad_id, factor)
VALUES
-- L <-> mL
((SELECT id FROM unidad WHERE codigo = 'L'),
 (SELECT id FROM unidad WHERE codigo = 'mL'),
 1000.000000),

((SELECT id FROM unidad WHERE codigo = 'mL'),
 (SELECT id FROM unidad WHERE codigo = 'L'),
 0.001000);

CREATE TABLE item_tipo(
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
INSERT INTO item_tipo (codigo, descripcion)
VALUES
('ROLLO',     'Rollo de tela (materia prima o en proceso)'),
('INSUMO',    'Insumo químico / colorante / auxiliar');
-- ('ROLLO_TERMINADO',  'Producto terminado (rollo teñido)');


CREATE TABLE item (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo TEXT NOT NULL UNIQUE,
  codigo_canon TEXT NOT NULL,
  nombre TEXT NOT NULL,

  item_tipo_id integer NOT NULL REFERENCES item_tipo(id),
  unidad_id integer NOT NULL REFERENCES unidad(id),

  usr_cre int,
  fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
  flg_elm boolean NOT NULL DEFAULT FALSE,
  usr_elm int,
  fyh_elm timestamptz,
    UNIQUE(codigo_canon),
    legacy_id int--droppear luego de migracion
);
CREATE TRIGGER trg_bi_item_codigo_canon
BEFORE INSERT OR UPDATE ON item
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

CREATE SCHEMA inventario;
create TYPE inventario.item_movimiento_tipo_categoria_enum as enum (
    'COMPRA',
    'VENTA',
    'PRODUCCION',
    'PROCESO_EXTERNO',
    'DEVOLUCION',
    'AJUSTE',
    'TRANSFERENCIA'
    );
CREATE OR REPLACE VIEW inventario.vw_item_movimiento_categoria AS
SELECT
    c.codigo::text AS codigo,
    CASE c.codigo
        WHEN 'COMPRA' THEN 'Compras'
        WHEN 'VENTA' THEN 'Ventas'
        WHEN 'PRODUCCION' THEN 'Producción'
        WHEN 'PROCESO_EXTERNO' THEN 'Proceso externo'
        WHEN 'DEVOLUCION' THEN 'Devoluciones'
        WHEN 'AJUSTE' THEN 'Ajustes'
        WHEN 'TRANSFERENCIA' THEN 'Transferencias'
    END AS nombre
FROM unnest(enum_range(NULL::inventario.item_movimiento_tipo_categoria_enum)) AS c(codigo);

CREATE SCHEMA IF NOT EXISTS inventario;

CREATE TABLE inventario.item_movimiento_tipo(
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text NOT NULL,
    
    categoria inventario.item_movimiento_tipo_categoria_enum NOT NULL,
    
    -- REPLACED 'direccion' with 'factor'. 
    -- 1 = Adds Stock, -1 = Removes Stock, 0 = Neutral (Transfer)
    factor SMALLINT NOT NULL CHECK (factor IN (1, -1, 0)), 

    descripcion text,

    -- LOGIC FLAGS
    flg_afecta_stock    BOOLEAN NOT NULL DEFAULT true,  -- Does it touch QTY?
    flg_valorizable     BOOLEAN NOT NULL DEFAULT true,  -- Does it have $$ value?
    
    -- NEW: COSTING LOGIC
    -- If TRUE, this entry triggers a Weighted Average Cost recalculation (e.g., Purchases)
    -- If FALSE, it enters stock at current existing cost (e.g., Transfers, Returns)
    flg_recalcula_costo BOOLEAN NOT NULL DEFAULT false,

    -- NEW: VALIDATION FLAGS (For UI and Backend checks)
    req_partner         BOOLEAN NOT NULL DEFAULT false, -- Requires Client/Provider?
    req_origen          BOOLEAN NOT NULL DEFAULT false, -- Requires source warehouse?
    req_destino         BOOLEAN NOT NULL DEFAULT false, -- Requires target warehouse?

    -- AUDIT (Kept yours)
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

INSERT INTO inventario.item_movimiento_tipo
(codigo, nombre, categoria, factor, flg_afecta_stock, flg_valorizable, flg_recalcula_costo, req_partner, req_origen, req_destino, descripcion)
VALUES
-- =====================
-- COMPRAS (Adds stock, Updates Cost, Needs Provider)
-- =====================
('COMPRA_ING', 'Compra – Recepción', 'COMPRA', 1, 
 true, true, true, true, false, true, 
 'Ingreso por compra local o importación'),

-- =====================
-- VENTAS (Removes stock, No Cost Recalc, Needs Client)
-- =====================
('VENTA_EGR', 'Venta – Despacho', 'VENTA', -1, 
 true, true, false, true, true, false, 
 'Salida por venta a cliente'),

-- =====================
-- PRODUCCIÓN
-- =====================
('PROD_CONSUMO', 'Producción – Consumo MP', 'PRODUCCION', -1, 
 true, true, false, false, true, false, 
 'Consumo de materia prima hacia orden de producción'),

('PROD_ING', 'Producción – Ingreso PT', 'PRODUCCION', 1, 
 true, true, true, false, false, true, 
 'Ingreso de producto terminado (Recalcula costo base en recursos usados)'),

-- =====================
-- PROCESO EXTERNO (Tolling)
-- =====================
-- Note: Often "Sending to a 3rd party" is just a transfer to a "3rd Party Warehouse" 
-- but if you track it logically:
('EXT_ENVIO', 'Proceso Ext. – Envío', 'PROCESO_EXTERNO', -1, 
 true, false, false, true, true, false, 
 'Salida a maquilador (sigue siendo propiedad nuestra)'),

('EXT_RETORNO', 'Proceso Ext. – Retorno', 'PROCESO_EXTERNO', 1, 
 true, true, true, true, false, true, 
 'Retorno con valor agregado (servicio maquila)'),

-- =====================
-- TRANSFERENCIAS (Atomic)
-- =====================
-- Factor is 0 because the Company Total Stock doesn't change.
-- The transaction logic handles: -1 from Origin, +1 to Destination.
('INT_TRANSFER_ING', 'Transferencia Interna', 'TRANSFERENCIA', 1, 
 true, true, false, false, true, true, 
 'Movimiento entre almacenes propios'),
('INT_TRANSFER_EGR', 'Transferencia Interna', 'TRANSFERENCIA', -1, 
 true, true, false, false, true, true, 
 'Movimiento entre almacenes propios'),

-- =====================
-- DEVOLUCIONES
-- =====================
('DEV_CLI_ING', 'Devolución Cliente', 'DEVOLUCION', 1, 
 true, true, false, true, false, true, 
 'Cliente devuelve. Entra al costo original o actual (no promedia)'),
('DEV_CLI_EGR', 'Devolución Cliente', 'DEVOLUCION', -1, 
 true, true, false, true, true, false, 
 'Se devuelve al cliente. Sin valor agregado'),



('DEV_PROV_EGR', 'Devolución Proveedor', 'DEVOLUCION', -1, 
 true, true, false, true, true, false, 
 'Salida por devolución a proveedor'),
-- RECEPCION DE CRUDO
INSERT INTO inventario.item_movimiento_tipo
(codigo, nombre, categoria, factor, flg_afecta_stock, flg_valorizable, flg_recalcula_costo, req_partner, req_origen, req_destino, descripcion)
VALUES
('SERV_ING', 'Servicio – Recepción Material Cliente', 'PROCESO_EXTERNO', 1, 
 true, false, false, true, false, true, 
 'Recepción de material de cliente para servicio de teñido (maquila)');

-- =====================
-- AJUSTES
-- =====================
('AJUSTE_POS', 'Ajuste Inventario (+)', 'AJUSTE', 1, 
 true, true, true, false, false, true, 
 'Sobrante físico (puede recalcular costo si entra con costo 0 o específico)'),

('AJUSTE_NEG', 'Ajuste Inventario (-)', 'AJUSTE', -1, 
 true, true, false, false, true, false, 
 'Faltante físico / Merma');

CREATE TABLE insumo_tipo(
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
INSERT INTO insumo_tipo (codigo,nombre)
VALUES ('QUIM','quimico'),('COLOR','colorante'),('AUX','auxiliar');

CREATE TABLE colorante_tipo(
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
CREATE TRIGGER trg_bi_unidad_codigo_canon
BEFORE INSERT OR UPDATE ON colorante_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
INSERT INTO colorante_tipo (nombre,codigo)
VALUES ('directo','DIR'),('disperso','DISP'),('reactivo','RX');


CREATE TABLE item_insumo_detalle(
   item_id INT PRIMARY KEY REFERENCES item(id),
   medida medida_enum NOT NULL,
   insumo_tipo_id smallint NOT NULL references insumo_tipo(id),
   colorante_tipo_id smallint references colorante_tipo(id),
   usr_cre int,
   fyh_cre TIMESTAMPTZ DEFAULT NOW(),
   usr_mod int,
   fyh_mod TIMESTAMPTZ
);

---el rib es un tipo de item
CREATE TABLE item_rollo_detalle(
   item_id INT PRIMARY KEY REFERENCES item(id),
   articulo_id INT NOT NULL references articulo(id),
   flg_tenido boolean NOT NULL default false,
   flg_rib boolean NOT NULL default FALSE,
   fibra smallint NOT NULL,
   usr_cre int,
   fyh_cre TIMESTAMPTZ DEFAULT NOW(),
   usr_mod int,
   fyh_mod TIMESTAMPTZ
);


CREATE OR REPLACE VIEW vw_items AS
SELECT i.id item_id, i.codigo item_codigo, i.nombre item_nombre, i.item_tipo_id, i.unidad_id, it.codigo item_tipo_codigo, u.codigo unidad_codigo
FROM public.item i
JOIN public.item_tipo it ON i.item_tipo_id = it.id
JOIN public.unidad u ON i.unidad_id = u.id;


-------------------------Modulo de almacenes


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
-- SELECT conname
-- FROM pg_constraint
-- WHERE conrelid = 'inventario.ubicacion'::regclass
--   AND contype = 'u';
--   ALTER TABLE inventario.ubicacion
-- DROP CONSTRAINT ubicacion_codigo_key;

CREATE TRIGGER trg_bi_ubicacion_codigo_canon
BEFORE INSERT OR UPDATE ON inventario.ubicacion
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
CREATE SCHEMA doc;
DROP TYPE IF EXISTS orden_produccion_estado_enum;
CREATE TYPE orden_produccion_estado_enum AS ENUM (
  'CREADA',        -- exists, no routing
  'PLANIFICADA',   -- route + resources defined
  'PROGRAMADA',    -- scheduled in time
  'LIBERADA',      -- allowed to execute (SAP-style)
  'EN_PROCESO',    -- at least one paso started
  'PAUSADA',       -- execution stopped
  'FINALIZADA',    -- physically finished
  'TECO',          -- technically completed (no more postings)
  'CERRADA',       -- administratively closed
  'CANCELADA'
);
DROP TYPE IF EXISTS partida_estado_enum;
CREATE TYPE partida_estado_enum AS ENUM (
  'CREADA',            -- captured, not yet accepted
  'CONFIRMADA',        -- approved by client
  'EN_PRODUCCION',     -- at least one active orden_produccion exists
  'ENTREGA_PARCIAL',   -- some quantities delivered
  'ENTREGADA',         -- fully delivered
  'DEVUELTA_PARCIAL',  -- client returned part
  'DEVUELTA_TOTAL',    -- client returned everything
  'FACTURADA',         -- financially closed
  'CERRADA',
  'CANCELADA'          -- voided before completion
);

-- ALTER TABLE estado DROP COLUMN estado_produccion, DROP COLUMN estado_comercial;
ALTER TABLE estado
DROP COLUMN IF EXISTS estado_produccion,
DROP COLUMN IF EXISTS estado_comercial,
ADD COLUMN estado_produccion orden_produccion_estado_enum,
ADD COLUMN estado_comercial partida_estado_enum;

CREATE TABLE doc.partida(  --production order table ¿MES TABLE?
id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
numero int GENERATED BY DEFAULT AS IDENTITY, 
-- fecha_recepcion timestamptz DEFAULT NOW(),
prioridad_id int references prioridad(id),
cliente_id int references cliente(id),
tenido_id int references tenido(id),
color_x_cliente_id int references color_x_cliente(id),
malla text,
rendimiento text,
flg_antipilling boolean DEFAULT false,
-- Execution State
estado partida_estado_enum DEFAULT 'CREADA',
    -- Timestamps
fyh_programacion timestamptz,
fyh_inicio timestamptz,
fyh_fin timestamptz,
usr_cre int,
  fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ
);



CREATE TABLE doc.partida_detalle(
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partida_id bigint NOT NULL REFERENCES doc.partida(id),
    item_id int NOT NULL REFERENCES item(id),
    cantidad int NOT NULL,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE (partida_id, item_id)
);

CREATE TABLE doc.guia_remision_tipo(
    id  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text,
    flg_emitida boolean NOT NULL,
    flg_cliente boolean,
    item_movimiento_tipo_id SMALLINT REFERENCES inventario.item_movimiento_tipo(id),
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE(codigo_canon)
);


CREATE TRIGGER trg_bi_guia_remision_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON doc.guia_remision_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

INSERT INTO doc.guia_remision_tipo (codigo, nombre, flg_emitida, flg_cliente)
VALUES
('COMPRA_INGRESO',          'Compra - Ingreso de materia insumos', false, false),
('VENTA_EGRESO',            'Venta - Egreso de producto terminado', true, true),
('CLIENTE_ENVIO_PROCESO',   'Cliente - Envío a proceso (rollos crudos a teñido)', false, true),
('DESPACHO_CLIENTE',      'Devolución a cliente (producto terminado)', true, true),
('DEVOLUCION_CLIENTE_CRUDO', 'Devolución a Cliente (rollos crudos)', true, true),
('DEVOLUCION_PROVEEDOR',    'Devolución a proveedor', true, false);
UPDATE doc.guia_remision_tipo grt
SET item_movimiento_tipo_id = imt.id
FROM inventario.item_movimiento_tipo imt
WHERE 
    (grt.codigo = 'COMPRA_INGRESO'           AND imt.codigo = 'COMPRA_ING')
 OR (grt.codigo = 'VENTA_EGRESO'             AND imt.codigo = 'VENTA_EGR')
 OR (grt.codigo = 'CLIENTE_ENVIO_PROCESO'    AND imt.codigo = 'SERV_ING')      -- NEW TYPE
 OR (grt.codigo = 'DESPACHO_CLIENTE'         AND imt.codigo = 'VENTA_EGR')     -- Service sold
 OR (grt.codigo = 'DEVOLUCION_CLIENTE_CRUDO' AND imt.codigo = 'DEV_CLI_EGR')
 OR (grt.codigo = 'DEVOLUCION_PROVEEDOR'     AND imt.codigo = 'DEV_PROV_EGR');
-- CREATE TYPE guia_operacion_enum AS ENUM (
--     'COMPRA_INGRESO',          -- supplier → us
--     'VENTA_EGRESO',            -- us → client
--     'CLIENTE_ENVIO_PROCESO',   -- client → us (raw rolls to dye)
--     'DEVOLUCION_CLIENTE',      -- us → client (finished goods)
--     'DEVOLUCION_PROVEEDOR',    -- us → supplier
--     'TRANSFERENCIA_INTERNA',
--     'AJUSTE'
-- );

CREATE TABLE doc.guia_remision (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    guia_remision_tipo_id smallint NOT NULL REFERENCES doc.guia_remision_tipo(id),
    serie TEXT NOT NULL,
    correlativo TEXT NOT NULL,
    -- emisor_id INT, --proveedor for compra_recepcion, cliente for recepcion_material_cliente
    -- receptor_id INT, --cliente for devolucion_cliente and venta_envio, proveedor for devolucion proveedor
    emisor_cliente_id   INT, -- REFERENCES cliente(id),
    emisor_proveedor_id INT, -- REFERENCES proveedor(id),
    receptor_cliente_id   INT, -- REFERENCES cliente(id),
    receptor_proveedor_id INT, -- REFERENCES proveedor(id),
    fecha_emision DATE NOT NULL,
    fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT now(),
    usr_cre int,
    fyh_cre timestamptz DEFAULT NOW(),
    usr_mod int,
    fyh_mod timestamptz,
    UNIQUE (serie,correlativo,emisor_proveedor_id),
    UNIQUE (serie,correlativo,emisor_cliente_id) -- Removed trailing comma here
);

CREATE TABLE inventario.lote (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  item_id int REFERENCES item(id),
--   guia_remision_detalle_id bigint references guia_remision_detalle(id), ---guia_remision_detalle si es ingreso externo
  documento_tipo TEXT,      -- e.g., 'guia_remision', 'partida', 'cuadre'
  documento_id BIGINT,      -- ID of the document header
--   cuadre_detalle_id bigint references cuadre_detalle_id(id), ---cuadre si es ajuste
--   partida_detalle_id bigint references partida_detalle_id(id), ---partida si es resultado de produccion
cantidad numeric(10,2),
--     peso numeric(8,2), --only if roll, nullable otherwise,
--     color_x_cliente_id int,
detalles JSONB, --peso, color, ancho,etc
estado_calidad calidad_estado_enum DEFAULT 'PENDIENTE',
    propietario_id int NULL references cliente(id),
  usr_cre int,
  fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ
);


CREATE TABLE doc.guia_remision_detalle (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    guia_remision_id BIGINT NOT NULL REFERENCES doc.guia_remision(id),

    item_id INT NOT NULL REFERENCES item(id),
    lote_id int references inventario.lote(id),
    ubicacion_id int references inventario.ubicacion(id),
    cantidad NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    UNIQUE (guia_remision_id, item_id, lote_id, ubicacion_id)
);

-- REVOKE INSERT (usr_cre, usr_mod, fyh_cre, fyh_mod)
-- ON doc.guia_remision_detalle
-- FROM anon, authenticated;

-- REVOKE UPDATE (usr_cre, fyh_cre)
-- ON doc.guia_remision_detalle
-- FROM anon, authenticated;

-- CREATE TRIGGER trg_bi_guia_remision_detalle_audit
-- BEFORE INSERT ON doc.guia_remision_detalle
-- FOR EACH ROW
-- EXECUTE FUNCTION public.fn_trg_set_cre_fields();
-- CREATE TRIGGER trg_bu_guia_remision_detalle_audit
-- BEFORE UPDATE ON doc.guia_remision_detalle
-- FOR EACH ROW
-- EXECUTE FUNCTION public.fn_trg_set_mod_fields();




CREATE TABLE inventario.item_movimientos (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id INT NOT NULL REFERENCES item(id),           -- rollo crudo, rib, terminado
    lote_id int references inventario.lote(id),
    item_movimiento_tipo_id smallint references inventario.item_movimiento_tipo(id) NOT NULL,
    -- movimiento_tipo TEXT NOT NULL CHECK (movimiento_tipo IN (
    --     'INGRESO',
    --     'EGRESO',
    -- )),
    origen_ubicacion_id INT NULL REFERENCES inventario.ubicacion(id),
    destino_ubicacion_id INT NULL REFERENCES inventario.ubicacion(id),
    cantidad NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    owner_id int,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),

    documento_tipo TEXT,          -- 'GUIA', 'LOTE', 'AJUSTE', etc. DOCUMENT CAUSING THE MOVEMENT
    documento_id int,            -- identifier or number ID OF THE ROW FOR THE DOCUMENT IN THE CORRESPONDING DOCUMENT TYPE's TABLE
    observacion TEXT,
    usr_cre int,
    fyh_cre timestamptz DEFAULT NOW()
);



CREATE SCHEMA mes;

-- Production Order Status (ISA-95 Standard States)

-- Machine Status (For OEE calculation)
CREATE TYPE maquina_estado_enum AS ENUM (
    'activa',       -- Producing
    'espera',       -- Idle/Standby
    'configuracion',-- Changeover/Loading
    'averia',       -- Unplanned Downtime
    'mantenimiento' -- Planned Maintenance
);

-- Defines WHAT can be done (Dyeing, Drying, Stentering, etc.)
CREATE TABLE mes.operacion (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text NOT NULL UNIQUE, -- e.g., 'TEÑIDO', 'RAMA', 'HIDRO', 'PERCHADO'
    requiere_receta boolean DEFAULT false, -- If true, operator must select/verify a chemical recipe
    requiere_maquina boolean DEFAULT true,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE (nombre),
    UNIQUE (codigo_canon) 
);
CREATE TRIGGER trg_bi_operacion_codigo_canon
BEFORE INSERT OR UPDATE ON mes.operacion
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
-- Seed data based on your JSON
INSERT INTO mes.operacion (codigo, nombre, requiere_receta) VALUES
('TERMO',  'TERMOFIJADO',  false),
('TEN',    'TEÑIDO',       true),
('HIDRO',  'LAVADO_HIDRO', true),
('SEC',    'SECADO',       false),
('PLAN',   'PLANCHADO',   false),
('PERCH',  'PERCHADO',    false);



CREATE TABLE mes.maquina_tipo(
  id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo TEXT NOT NULL UNIQUE,
  codigo_canon TEXT NOT NULL,
  nombre text,
  usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
  UNIQUE(codigo_canon),
  UNIQUE(nombre)
);
CREATE TRIGGER trg_bi_maquina_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON mes.maquina_tipo
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
CREATE TABLE mes.maquina(
    id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text NOT NULL,
    maquina_tipo_id smallint references mes.maquina_tipo(id),
    estado_actual maquina_estado_enum NOT NULL DEFAULT 'espera',
    ultimo_mantenimiento timestamptz,
    horas_totales int,
    capacidad_min_kg int NOT NULL,
    capacidad_max_kg int NOT NULL,
    relacion_bano numeric(5,2),
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
  flg_elm bool DEFAULT false,
  usr_elm int,
  fyh_elm TIMESTAMPTZ,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_maquina_codigo_canon
BEFORE INSERT OR UPDATE ON mes.maquina
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();

CREATE TABLE mes.empleado_rol (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_empleado_rol_codigo_canon
BEFORE INSERT OR UPDATE ON mes.empleado_rol
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_set_codigo_canon();
CREATE TABLE mes.empleado(
  id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre text,
  apellido text,
  rol_id smallint NOT NULL references mes.empleado_rol(id),
  turno_id smallint references turno(id),
   usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ
);

-- Header for a standard process path
CREATE TABLE mes.ruta_plantilla (
    id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre text NOT NULL, -- e.g., 'Algodon Reactivo Estandar'
     usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
  flg_elm boolean DEFAULT false,
  usr_elm int,
  fyh_elm timestamptz
);


-- The specific steps for that path
CREATE TABLE mes.ruta_plantilla_detalle (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ruta_plantilla_id int NOT NULL REFERENCES mes.ruta_plantilla(id),
    operacion_id smallint NOT NULL REFERENCES mes.operacion(id),
    secuencia smallint NOT NULL, -- 10, 20, 30...
    
    -- Default standard times/costs can go here
    ph numeric(4,2),
    temperatura numeric(5,2),
    tiempo_estandar int,
    UNIQUE (ruta_plantilla_id,secuencia)
);

CREATE TYPE orden_produccion_tipo_enum as enum 
('NORMAL', 'REPROCESO', 'AJUSTE');
CREATE VIEW vw_orden_produccion_tipo AS
SELECT unnest(enum_range(NULL::orden_produccion_tipo_enum)) AS tipo;


CREATE TABLE mes.orden_produccion (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  partida_id bigint NOT NULL REFERENCES doc.partida(id),

  tipo orden_produccion_tipo_enum NOT NULL,

  orden_origen_id bigint REFERENCES mes.orden_produccion(id), --Para reprocesos o ajustes

  estado orden_produccion_estado_enum NOT NULL DEFAULT 'CREADA',

  fyh_cre timestamptz DEFAULT now(),
  fyh_inicio timestamptz,
  fyh_fin timestamptz,

  usr_cre int
);

CREATE TYPE orden_produccion_paso_estado_enum as ENUM('PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'OMITIDO');


CREATE TABLE mes.orden_produccion_paso (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    orden_produccion_id bigint NOT NULL REFERENCES mes.orden_produccion(id),
    secuencia smallint NOT NULL, -- Order of execution
    -- Routing Info
    operacion_id smallint NOT NULL REFERENCES mes.operacion(id),
    -- Resource Assignment
    maquina_asignada_id int REFERENCES mes.maquina(id), -- Specific machine for THIS step
    ph numeric(4,2),
    temperatura numeric(5,2),
    tiempo_estandar int,
    relacion_bano numeric(5,2),
    -- The specific recipe for THIS step (Solves "multiple recipes" issue)
    receta_id int references receta2(id), -- Foreign key to your existing Recipe Header table
    
    -- Status of THIS specific step
    estado orden_produccion_paso_estado_enum DEFAULT 'PENDIENTE',
    
    -- Timestamps for OEE
    empleado_id smallint references mes.empleado(id),
    flg_final bool DEFAULT false,
    fyh_inicio timestamptz,
    fyh_fin timestamptz,
     usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    -- Logic: Provide uniqueness on sequence per part
    UNIQUE (orden_produccion_id, secuencia)
);

----items especificos procurados para la partida, NO producto final a ser producido si no items que requieran seguimiento a través del rpoceso de produccion 
CREATE TABLE mes.orden_produccion_item(  --production order table detail ¿MES TABLE or public table? it contains the detail of which roll lot the partida is drawing from
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   orden_produccion_id bigint NOT NULL REFERENCES mes.orden_produccion(id),
   item_id int NOT NULL REFERENCES item(id),
    lote_id int NOT NULL REFERENCES inventario.lote(id), -- The specific roll of fabric
    ubicacion_id int NOT NULL REFERENCES inventario.ubicacion(id),
    peso_kg numeric(10,2),
    cantidad int,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    UNIQUE(orden_produccion_id, lote_id, ubicacion_id) -- Prevent adding same roll twice
);

DROP TABLE IF EXISTS mes.orden_produccion_paso_item;
CREATE TABLE mes.orden_produccion_paso_item (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    orden_produccion_paso_id bigint NOT NULL REFERENCES mes.orden_produccion_paso(id),
    orden_produccion_item_id int NOT NULL REFERENCES mes.orden_produccion_item(id), -- Must be one of the IDs in partida_rollo
    cantidad numeric(10,2) NOT NULL,
    flg_consumido bool DEFAULT false,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    UNIQUE (orden_produccion_paso_id, orden_produccion_item_id)
);


CREATE SCHEMA IF NOT EXISTS calidad;

-- ALTER TYPE calidad_estado_enum
-- RENAME VALUE 'RETRABAJO' TO 'REPROCESO';

-- ALTER TABLE inventario.lote
-- ADD COLUMN estado_calidad calidad_estado_enum
-- DEFAULT 'PENDIENTE';

CREATE TABLE calidad.inspeccion (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  lote_id int NOT NULL REFERENCES inventario.lote(id),
  orden_produccion_paso_id bigint REFERENCES mes.orden_produccion_paso(id),
  resultado calidad_estado_enum NOT NULL,
  observacion text,
  empleado_id int references mes.empleado(id),
  fyh_inspeccion timestamptz DEFAULT now(),
  usr_cre int,
  fyh_cre TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE mes.programacion (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    orden_produccion_paso_id bigint NOT NULL REFERENCES mes.orden_produccion_paso(id),
    maquina_id int NOT NULL REFERENCES mes.maquina(id),
    fecha date NOT NULL,
    secuencia smallint NOT NULL,
    nota text,
    usr_cre int,
    fyh_cre timestamptz DEFAULT now(),
    usr_mod int,
    fyh_mod timestamptz,
    UNIQUE (maquina_id, fecha, secuencia)
);


CREATE TABLE doc.compra_guia_remision(
  guia_remision_id int,
  compra_id int,
  usr_cre int,
  fyh_cre timestamptz,
  UNIQUE(guia_remision_id,compra_id)
);



GRANT USAGE ON SCHEMA doc TO authenticated;
-- Grant SELECT on the view

DROP VIEW IF EXISTS doc.vw_partidas_lista_comercial;
CREATE OR REPLACE VIEW doc.vw_partidas_lista_comercial AS
SELECT 
    -- ═══════════════════════════════════════
    -- BASIC INFO
    -- ═══════════════════════════════════════
    p.id,
    p.numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS codigo,
    
    -- ═══════════════════════════════════════
    -- COMMERCIAL DATA (doc/commercial schema)
    -- ═══════════════════════════════════════
    p.estado,  -- From partida_estado_enum (commercial states)
    
    p.cliente_id,
    c.cliente,
    
    p.prioridad_id,
    pri.prioridad,
    

    p.tenido_id,
    t.tenido,

    p.color_x_cliente_id,
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    vc.color_x_cliente_hex,

    p.malla,
    p.rendimiento,
    p.flg_antipilling,
    -- ═══════════════════════════════════════
    -- DATES (Commercial timeline)
    -- ═══════════════════════════════════════
    p.fyh_cre AS fecha_creacion,
    p.fyh_programacion AS fecha_programacion,
    p.fyh_inicio AS fecha_inicio,
    p.fyh_fin AS fecha_finalizacion,
    
    -- Days since creation
    EXTRACT(EPOCH FROM (NOW() - p.fyh_cre)) / 86400 AS dias_desde_creacion,
    
    -- ═══════════════════════════════════════
    -- ITEMS SOLICITADOS (Commercial layer)
    -- ═══════════════════════════════════════
    COALESCE(pd_agg.total_items, 0) AS total_items,
    COALESCE(pd_agg.cantidad_total, '0') AS cantidad_total,
    COALESCE(pd_agg.cantidad_principales, '0') AS cantidad_principales,
    COALESCE(pd_agg.cantidad_rib, '0') AS cantidad_rib,
    -- ═══════════════════════════════════════
    -- MINIMAL PRODUCTION INDICATOR
    -- Just enough to know "is it being worked on?"
    -- ═══════════════════════════════════════
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM mes.orden_produccion op 
            WHERE op.partida_id = p.id
        ) THEN true
        ELSE false
    END AS tiene_ordenes_produccion,
    
    -- ═══════════════════════════════════════
    -- AUDIT
    -- ═══════════════════════════════════════
    p.usr_cre,
    p.fyh_cre

FROM doc.partida p

-- Basic references (commercial layer only)
LEFT JOIN cliente c ON c.id = p.cliente_id
LEFT JOIN prioridad pri ON pri.id = p.prioridad_id

LEFT JOIN tenido t ON t.id = p.tenido_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id

-- Items (still commercial - what was ordered)
LEFT JOIN LATERAL (
    SELECT 
        COUNT(*) AS total_items,
        SUM(pd.cantidad) AS cantidad_total,
        -- Separate columns for each type
        SUM(CASE WHEN ird.flg_rib = FALSE THEN pd.cantidad ELSE 0 END) AS cantidad_principales,
        SUM(CASE WHEN ird.flg_rib = TRUE THEN pd.cantidad ELSE 0 END) AS cantidad_rib
    FROM doc.partida_detalle pd
    LEFT JOIN item_rollo_detalle ird ON ird.item_id = pd.item_id
    WHERE pd.partida_id = p.id
) pd_agg ON true;

GRANT SELECT ON doc.vw_partidas_lista_comercial TO authenticated;

-- View for listing ordenes de producción with essential information
-- This view provides a performant way to list orders with related data

CREATE OR REPLACE VIEW mes.vw_ordenes_produccion AS
SELECT 
    op.id,
    op.tipo,
    op.estado,
    op.orden_origen_id,
    op.fyh_cre,
    op.fyh_inicio,
    op.fyh_fin,
    
    -- Partida info
    op.partida_id,
    p.numero AS partida_numero,
    EXTRACT(YEAR FROM p.fyh_cre)::TEXT || '-' || LPAD(p.numero::TEXT, 4, '0') AS partida_codigo,
    p.estado AS partida_estado,
    
    -- Cliente info
    c.id AS cliente_id,
    c.cliente,
    
    -- Color info
    vc.color_id,
    vc.color,
    vc.tono,
    vc.color_hex,
    
    -- Tenido info
    t.id AS tenido_id,
    t.tenido,
    
 
    
    -- Progress info (pasos)
    COALESCE(pasos_stats.total_pasos, 0) AS total_pasos,
    COALESCE(pasos_stats.pasos_completados, 0) AS pasos_completados,
    COALESCE(pasos_stats.pasos_en_proceso, 0) AS pasos_en_proceso,
    COALESCE(pasos_stats.pasos_pendientes, 0) AS pasos_pendientes,
    
    -- Calculate progress percentage
    CASE 
        WHEN COALESCE(pasos_stats.total_pasos, 0) > 0 THEN
            ROUND((COALESCE(pasos_stats.pasos_completados, 0)::NUMERIC / pasos_stats.total_pasos::NUMERIC) * 100, 0)
        ELSE 0
    END AS progreso_porcentaje,
    
    -- Materials info
    COALESCE(materiales_stats.total_materiales, 0) AS total_materiales,
    COALESCE(materiales_stats.cantidad_total_kg, 0) AS cantidad_total_kg,
    
    -- Production output info
    COALESCE(produccion_stats.lotes_generados, 0) AS lotes_generados,
    
    -- Duration
    CASE 
        WHEN op.fyh_inicio IS NOT NULL AND op.fyh_fin IS NOT NULL THEN
            EXTRACT(EPOCH FROM (op.fyh_fin - op.fyh_inicio)) / 3600 -- hours
        WHEN op.fyh_inicio IS NOT NULL THEN
            EXTRACT(EPOCH FROM (NOW() - op.fyh_inicio)) / 3600 -- current duration
        ELSE NULL
    END AS duracion_horas,
    
    -- User info
    op.usr_cre,
    prof.first_name || ' ' || prof.last_name AS creado_por

FROM mes.orden_produccion op
JOIN doc.partida p ON p.id = op.partida_id
LEFT JOIN cliente c ON c.id = p.cliente_id
LEFT JOIN vw_colores vc ON vc.color_x_cliente_id = p.color_x_cliente_id
LEFT JOIN tenido t ON t.id = p.tenido_id
LEFT JOIN profiles prof ON prof.id_usuario = op.usr_cre

-- Aggregate pasos stats
LEFT JOIN LATERAL (
    SELECT 
        COUNT(*) AS total_pasos,
        COUNT(*) FILTER (WHERE estado = 'COMPLETADO') AS pasos_completados,
        COUNT(*) FILTER (WHERE estado = 'EN_PROCESO') AS pasos_en_proceso,
        COUNT(*) FILTER (WHERE estado = 'PENDIENTE') AS pasos_pendientes
    FROM mes.orden_produccion_paso opp
    WHERE opp.orden_produccion_id = op.id
) pasos_stats ON true

-- Aggregate materiales stats
LEFT JOIN LATERAL (
    SELECT 
        COUNT(*) AS total_materiales,
        SUM(opi.peso_kg) AS cantidad_total_kg
    FROM mes.orden_produccion_item opi
    WHERE opi.orden_produccion_id = op.id
) materiales_stats ON true

-- Aggregate production output
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS lotes_generados
    FROM inventario.lote l
    WHERE l.documento_tipo = 'orden_produccion'
      AND l.documento_id = op.id
) produccion_stats ON true;

-- Grant permissions
GRANT SELECT ON mes.vw_ordenes_produccion TO anon, authenticated;

-- -- Create indexes for better performance
-- CREATE INDEX IF NOT EXISTS idx_orden_produccion_partida_id 
--     ON mes.orden_produccion(partida_id);

-- CREATE INDEX IF NOT EXISTS idx_orden_produccion_estado 
--     ON mes.orden_produccion(estado);

-- CREATE INDEX IF NOT EXISTS idx_orden_produccion_tipo 
--     ON mes.orden_produccion(tipo);

-- CREATE INDEX IF NOT EXISTS idx_orden_produccion_fyh_cre 
--     ON mes.orden_produccion(fyh_cre DESC);

-- Example queries:
-- SELECT * FROM mes.vw_ordenes_produccion ORDER BY fyh_cre DESC LIMIT 20;
-- SELECT * FROM mes.vw_ordenes_produccion WHERE estado = 'EN_PROCESO';
-- SELECT * FROM mes.vw_ordenes_produccion WHERE cliente_id = 123;
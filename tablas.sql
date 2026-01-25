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
    c.cliente AS cliente
   FROM ((color_x_cliente a
     JOIN color b ON ((a.color_id = b.id)))
     JOIN cliente c ON ((a.cliente_id = c.id)));





CREATE EXTENSION IF NOT EXISTS unaccent;

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
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
INSERT INTO unidad (codigo, nombre)
VALUES
 ('kg',  'Kilogramo'),
 ('g',   'Gramo'),
 ('mg',  'Miligramo'),
 ('ton', 'Tonelada'),
 ('L',   'Litro'),
 ('mL',  'Mililitro');


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
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
INSERT INTO item_tipo (codigo, descripcion)
VALUES
('ROLLO',     'Rollo de tela (materia prima o en proceso)'),
('INSUMO',    'Insumo químico / colorante / auxiliar'),
('ROLLO_TERMINADO',  'Producto terminado (rollo teñido)');


CREATE TABLE item (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo TEXT NOT NULL UNIQUE,
  codigo_canon TEXT NOT NULL
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
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_item_codigo_canon
BEFORE INSERT OR UPDATE ON item
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_codigo_canon();

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
    unnest(enum_range(NULL::inventario.item_movimiento_tipo_categoria_enum))::text AS codigo,
    CASE unnest(enum_range(NULL::inventario.item_movimiento_tipo_categoria_enum))
        WHEN 'COMPRA' THEN 'Compras'
        WHEN 'VENTA' THEN 'Ventas'
        WHEN 'PRODUCCION' THEN 'Producción'
        WHEN 'PROCESO_EXTERNO' THEN 'Proceso externo'
        WHEN 'DEVOLUCION' THEN 'Devoluciones'
        WHEN 'AJUSTE' THEN 'Ajustes'
        WHEN 'TRANSFERENCIA' THEN 'Transferencias'
    END AS nombre;

CREATE SCHEMA IF NOT EXISTS inventario;

CREATE TABLE inventario.item_movimiento_tipo(
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();

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
    codigo_canon TEXT NOT NULL
    
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
INSERT INTO insumo_tipo (codigo,nombre)
VALUES ('QUIM','quimico'),('COLOR','colorante'),('AUX','auxiliar');

CREATE TABLE colorante_tipo(
     id  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
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
   fibra smallint NOT NULL,
   usr_cre int,
   fyh_cre TIMESTAMPTZ DEFAULT NOW(),
   usr_mod int,
   fyh_mod TIMESTAMPTZ
);


CREATE OR REPLACE VIEW vw_items AS
SELECT i.id item_id, i.codigo item_codigo, i.nombre item_nombre, i.item_tipo_id, i.unidad_id, it.item_tipo_codigo, u.unidad_codigo
FROM public.item i
JOIN public.item_tipo it ON i.item_tipo_id = it.id
JOIN public.unidad u ON i.unidad_id = u.id;


-------------------------Modulo de almacenes


CREATE TABLE inventario.almacen (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();

CREATE TABLE inventario.ubicacion (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    almacen_id INT NOT NULL REFERENCES almacen(id),
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
CREATE SCHEMA doc;
CREATE TYPE partida_estado_produccion_enum AS ENUM (
  'CREADA',        -- order exists, not routed
  'PLANIFICADA',   -- routing + resources assigned
  'EN_PROCESO',    -- at least one paso started
  'PAUSADA',       -- execution stopped
  'TECO',          -- technically completed (SAP-style)
  'CERRADA',       -- no more postings allowed
  'CANCELADA'      -- aborted
);
CREATE TYPE partida_estado_comercial_enum AS ENUM (
  'CREADA',            -- exists, not yet accepted
  'CONFIRMADA',        -- approved for execution
  'EN_PRODUCCION',     -- linked to an active production order
  'ENTREGA_PARCIAL',   -- partially delivered
  'ENTREGADA',         -- fully delivered
  'FACTURADA',         -- financially closed
  'CANCELADA'          -- voided before completion
);

CREATE TABLE doc.partida(  --production order table ¿MES TABLE?
id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
numero int, 
-- fecha_recepcion timestamptz DEFAULT NOW(),
prioridad_id int references prioridad(id),
cliente_id int references cliente(id),
tenido_id int references tipo_tenido(id),
previo_id int references previo(id),
malla text,
rendimiento text,
-- Execution State
estado_produccion partida_estado_produccion_enum NOT NULL DEFAULT 'CREADA',
estado_comercial partida_estado_comercial_enum NOT NULL DEFAULT 'CREADA',
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
    fyh_mod TIMESTAMPTZ
);

CREATE TABLE doc.guia_remision_tipo(
    smallint  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
    nombre text,
    flg_emitida boolean NOT NULL,
    flg_cliente boolean,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
    usr_mod int,
    fyh_mod TIMESTAMPTZ,
    UNIQUE(codigo_canon)
);
CREATE TRIGGER trg_bi_guia_remision_tipo_codigo_canon
BEFORE INSERT OR UPDATE ON doc.guia_remision_tipo
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_codigo_canon();

INSERT INTO doc.guia_remision_tipo (codigo, nombre, flg_emitida, flg_cliente)
VALUES
('COMPRA_INGRESO',          'Compra - Ingreso de materia insumos', false, false),
('VENTA_EGRESO',            'Venta - Egreso de producto terminado', true, true),
('CLIENTE_ENVIO_PROCESO',   'Cliente - Envío a proceso (rollos crudos a teñido)', false, true),
('DESPACHO_CLIENTE',      'Devolución a cliente (producto terminado)', true, true),
('DEVOLUCION_CLIENTE_CRUDO', 'Devolución a Cliente (rollos crudos)', true, true),
('DEVOLUCION_PROVEEDOR',    'Devolución a proveedor', true, false);

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
    guia_remision_tipo_id smallint NOT NULL REFERENCES guia_remision_tipo(id),
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
    UNIQUE (numero,emisor_proveedor_id),
    UNIQUE (numero,emisor_cliente_id) -- Removed trailing comma here
);


CREATE TABLE doc.guia_remision_detalle (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    guia_id BIGINT NOT NULL REFERENCES guia_remision(id),

    item_id INT NOT NULL REFERENCES item(id),
    lote_id int references lote(id),
    ubicacion_id int references ubicacion(id),
    cantidad NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    UNIQUE (guia_id, item_id, lote_id, ubicacion_id)
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
    propietario_id int NULL references cliente(id),
  usr_cre int,
  fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ
);



CREATE TABLE inventario.item_movimientos (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id INT NOT NULL REFERENCES item(id),           -- rollo crudo, rib, terminado
    lote_id int references lote(id),
    item_movimiento_tipo_id smallint references inventario.item_movimiento_tipo(id) NOT NULL,
    -- movimiento_tipo TEXT NOT NULL CHECK (movimiento_tipo IN (
    --     'INGRESO',
    --     'EGRESO',
    -- )),
    origen_ubicacion_id INT NULL REFERENCES ubicacion(id),
    destino_ubicacion_id INT NULL REFERENCES ubicacion(id),
    cantidad NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    owner_id int,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),

    documento_tipo TEXT,          -- 'GUIA', 'LOTE', 'AJUSTE', etc. DOCUMENT CAUSING THE MOVEMENT
    documento_id int,            -- identifier or number ID OF THE ROW FOR THE DOCUMENT IN THE CORRESPONDING DOCUMENT TYPE's TABLE
    observacion TEXT,
    usr_cre int,
    fyh_cre timestamptz DEFAULT NOW()
);


CREATE FUNCTION doc.crear_guia(p_guia json)
RETURNS text
LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iam', 'notification', 'public','doc','inventario'
AS $function$
DECLARE
    v_message   text;
    v_detail    text;
    v_hint      text;
    v_context   text;
    v_sqlstate  text;
    v_guia_id   INT;
    v_guia_tipo guia_remision_tipo%ROWTYPE;
    v_usr_id int := get_user_id();
    v_lote_id int;
    v_error_payload jsonb;
BEGIN
 -- guard condition
 SELECT * INTO v_guia_tipo FROM guia_remision_tipo WHERE id = (p_guia->>'guia_remision_tipo_id')::SMALLINT;
 IF NOT FOUND THEN
     RAISE EXCEPTION 'Tipo de guía con id % no existe', (p_guia->>'guia_remision_tipo_id');
 END IF;

IF v_guia_tipo.flg_emitida THEN
        -- SELECT im.lote_id,COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id),SUM(CASE WHEN im.movimiento_tipo = 'EGRESO' THEN -im.cantidad WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad ELSE 0 END) FROM inventario.item_movimientos im
        -- JOIN jsonb_array_elements(p_guia->'items') AS items ON items.item_id=im.item_id AND items.lote_id=im.lote_id AND items.ubicacion_id= COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        -- GROUP BY im.lote_id,COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        ---------------------
        --VALIDAR DISPONIBILIDAD DE items
        -------------------
        WITH guia_items AS (
        SELECT
            (i->>'item_id')::int        AS item_id,
            (i->>'lote_id')::int        AS lote_id,
            (i->>'ubicacion_id')::int  AS ubicacion_id,
            SUM((i->>'cantidad')::numeric)  AS cantidad
        FROM jsonb_array_elements(p_guia->'items') i
        GROUP BY 1,2,3
    ),errores as(  SELECT
            im.item_id,
            im.lote_id,
            COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id) AS ubicacion_id,
            items.cantidad,
            SUM(
                CASE
                    WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad
                    WHEN im.movimiento_tipo = 'EGRESO'  THEN -im.cantidad
                END
            ) AS saldo
        FROM inventario.item_movimientos im
        JOIN guia_items AS items ON guia_items.item_id=im.item_id AND guia_items.lote_id=im.lote_id AND guia_items.ubicacion_id= COALESCE(im.destino_ubicacion_id,im.origen_ubicacion_id)
        GROUP BY im.item_id, im.lote_id, COALESCE(im.destino_ubicacion_id, im.origen_ubicacion_id),items.cantidad
        HAVING SUM(
                CASE
                    WHEN im.movimiento_tipo = 'INGRESO' THEN im.cantidad
                    WHEN im.movimiento_tipo = 'EGRESO'  THEN -im.cantidad
                END
            )< items.cantidad
    ) SELECT jsonb_agg(
        jsonb_build_object(
            'item_id', item_id,
            'lote_id', lote_id,
            'ubicacion_id', ubicacion_id,
            'saldo_disponible', saldo,
            'cantidad_requerida', cantidad
        )
    )
    INTO v_error_payload
    FROM errores;
    IF v_error_payload IS NOT NULL THEN
        RAISE EXCEPTION
            'Stock insuficiente para emitir la guía'
            USING
                DETAIL  = v_error_payload::text;
    END IF;
-----------------------------------------------------------------------------------------------------------------------
    IF v_guia_tipo.flg_cliente AND (p_guia->>'receptor_cliente_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba receptor_cliente_id para documento de cliente emitido';
    ELSIF NOT v_guia_tipo.flg_cliente AND (p_guia->>'receptor_proveedor_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba receptor_proveedor_id para documento de proveedor emitido';
    END IF;
ELSE
    -- incoming
    IF v_guia_tipo.flg_cliente AND (p_guia->>'emisor_cliente_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba emisor_cliente_id para documento de cliente recibido';
    ELSIF NOT v_guia_tipo.flg_cliente AND (p_guia->>'emisor_proveedor_id') IS NULL THEN
        RAISE EXCEPTION 'Guía inválida: se esperaba emisor_proveedor_id para documento de proveedor recibido';
    END IF;
END IF;

 INSERT INTO logs_api(function_name, user_id, params)
        VALUES ('crear_guia', v_usr_id, p_guia::TEXT);

    INSERT INTO doc.guia_remision(guia_remision_tipo_id, serie, correlativo, emisor_cliente_id, emisor_proveedor_id, receptor_cliente_id, receptor_proveedor_id, fecha_emision, fecha_recepcion)
    VALUES (
        (p_guia->>'guia_remision_tipo_id')::INT,
        p_guia->>'serie',
        p_guia->>'correlativo',
        CASE
            WHEN p_guia ? 'emisor_cliente_id' THEN (p_guia->>'emisor_cliente_id')::INT
            ELSE NULL
        END,
        CASE
            WHEN p_guia ? 'emisor_proveedor_id' THEN (p_guia->>'emisor_proveedor_id')::INT
            ELSE NULL
        END,
        CASE
            WHEN p_guia ? 'receptor_cliente_id' THEN (p_guia->>'receptor_cliente_id')::INT
            ELSE NULL
        END,
        CASE
            WHEN p_guia ? 'receptor_proveedor_id' THEN (p_guia->>'receptor_proveedor_id')::INT
            ELSE NULL
        END,
        (p_guia->>'fecha_emision')::DATE
    )
    RETURNING id INTO v_guia_id;

INSERT INTO doc.guia_remision_detalle (guia_id, item_id, cantidad,lote_id,ubicacion_id)
SELECT
    v_guia_id,
    (item->>'item_id')::INT,
    (item->>'cantidad')::NUMERIC(12,2),
    (item->>'lote_id')::INT,
    (item->>'ubicacion_id')::INT
FROM jsonb_array_elements(p_guia->'items') AS item;

IF v_guia_tipo.flg_emitida THEN
    -- For issued guides, create item movements as EGRESO from warehouse
    INSERT INTO inventario.item_movimientos (item_id, lote_id, movimiento_tipo, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id, observacion)
    SELECT
        (item->>'item_id')::INT,
        (item->>'lote_id')::INT, 
        'EGRESO',
        (p_guia->>'origen_ubicacion_id')::INT,
        NULL, -- destination is external
        (item->>'cantidad')::NUMERIC(12,2),
        now(),
        'guia_remision',
        v_guia_id,
        NULL
    FROM jsonb_array_elements(p_guia->'items') AS item;
ELSE
WITH nuevos_lotes AS(
    INSERT INTO lote (item_id, documento_tipo, documento_id, cantidad, peso, color_x_cliente_id)
    SELECT
    (item->>'item_id')::INT,
    'guia_remision',
    v_guia_id,
    (item->>'cantidad')::NUMERIC(12,2),
    CASE
        WHEN (item->>'peso') IS NOT NULL THEN (item->>'peso')::NUMERIC(8,2)
        ELSE NULL
    END,
    CASE
        WHEN (item->>'color_x_cliente_id') IS NOT NULL THEN (item->>'color_x_cliente_id')::INT
        ELSE NULL
    END
    RETURNING id,item_id
)
    -- For received guides, create item movements as INGRESO to warehouse
    INSERT INTO inventario.item_movimientos (item_id, lote_id, movimiento_tipo, origen_ubicacion_id, destino_ubicacion_id, cantidad, fecha_hora, documento_tipo, documento_id, observacion)
    SELECT
        (item->>'item_id')::INT,
        nl.id, --id del lote recien creado
        'ingreso',
        NULL, -- origin is external
        (p_guia->>'destino_ubicacion_id')::INT,
        (item->>'cantidad')::NUMERIC(12,2),
        COALESCE((p_guia->>'fecha_emision'),now()),
        'guia_remision',
        v_guia_id,
        NULL
    FROM jsonb_array_elements(p_guia->'items') AS item
    LEFT JOIN nuevos_lotes nl ON nl.item_id = (item->>'item_id')::INT
    ;
END IF;

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Guia y movimientos', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=v_usr_id),'sistema') || ' creó una nueva guía de remisión y generó movimientos de inventario', 'info',jsonb_build_object('objeto_tipo','guia_remision','guia_remision_id',v_guia_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras','inventario') AND v_usr_id<>ur.user_id;
   RETURN format('Guía de remisión con ID %s creada correctamente.', v_guia_id);
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message  = MESSAGE_TEXT,
            v_detail   = PG_EXCEPTION_DETAIL,
            v_hint     = PG_EXCEPTION_HINT,
            v_context  = PG_EXCEPTION_CONTEXT,
            v_sqlstate = RETURNED_SQLSTATE;

        INSERT INTO logs_api(function_name, user_id, params,error_message,error_detail,error_context)
        VALUES ('crear_guia', v_usr_id, p_guia::TEXT, v_message, v_detail || COALESCE(v_hint,''), v_context);
        RAISE;
END;
$function$;





CREATE SCHEMA mes;

-- Production Order Status (ISA-95 Standard States)
CREATE TYPE partida_estado_enum AS ENUM (
 'CREADA',        -- exists, not yet planned
  'PLANIFICADA',   -- routing/steps defined, not yet started
  'EN_PROCESO',    -- at least one paso started
  'PAUSADA',       -- temporarily stopped (optional but useful)
  'TECO',          -- technically completed (manual decision)
  'CERRADA',       -- financially / logistically closed
  'ENTREGADA',
  'ENTREGA_PARCIAL'
  'CANCELADA'      -- aborted
);

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
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
-- Seed data based on your JSON
INSERT INTO mes.operacion (nombre, requiere_receta) VALUES 
('TERMOFIJADO', false), -- ID 19
('TEÑIDO', true),       -- ID 5/6
('LAVADO_HIDRO', true),-- ID 7
('SECADO', false),      -- ID 8
('PLANCHADO', false),   -- ID 9
('PERCHADO', false);    -- ID 20

----items especificos procurados para la partida, NO producto final a ser producido si no items que requieran seguimiento a través del rpoceso de produccion 
CREATE TABLE mes.partida_item(  --production order table detail ¿MES TABLE or public table? it contains the detail of which roll lot the partida is drawing from
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   partida_id bigint NOT NULL REFERENCES doc.partida(id),
    lote_id int NOT NULL REFERENCES lote(id), -- The specific roll of fabric
    ubicacion_id int NOT NULL REFERENCES ubicacion(id),
    peso_kg numeric(10,2),
    cantidad int,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    UNIQUE(partida_id, lote_id, ubicacion_id) -- Prevent adding same roll twice
);


CREATE TABLE mes.maquina_tipo(
  id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo TEXT NOT NULL UNIQUE,
  codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
CREATE TABLE mes.maquina(
    id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
    nombre text NOT NULL,
    maquina_tipo_id smallint references maquina_tipo(id),
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
EXECUTE FUNCTION public.trg_set_codigo_canon();

CREATE TABLE mes.empleado_rol (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    codigo_canon TEXT NOT NULL
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
EXECUTE FUNCTION public.trg_set_codigo_canon();
CREATE TABLE mes.empleado(
  id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre text,
  apellido text,
  rol_id smallint NOT NULL references empleado_rol(id),
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


-- This table replaces your "States" for tracking physical progress
CREATE TABLE mes.partida_paso (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partida_id bigint NOT NULL REFERENCES doc.partida(id),
    secuencia smallint NOT NULL, -- Order of execution
    -- Routing Info
    operacion_id smallint NOT NULL REFERENCES mes.operacion(id),
    -- Resource Assignment
    maquina_asignada_id int REFERENCES mes.maquina(id), -- Specific machine for THIS step
    ph numeric(4,2),
    temperatura numeric(5,2),
    tiempo_estandar int,

    -- The specific recipe for THIS step (Solves "multiple recipes" issue)
    receta_id int references receta2(id), -- Foreign key to your existing Recipe Header table
    
    -- Status of THIS specific step
    estado text CHECK (estado IN ('PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'OMITIDO')),
    
    -- Timestamps for OEE
    empleado_id smallint references mes.empleado(id),
    fyh_inicio timestamptz,
    fyh_fin timestamptz,
     usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    -- Logic: Provide uniqueness on sequence per part
    UNIQUE (partida_id, secuencia)
);

CREATE TABLE mes.partida_paso_item (
    partida_paso_id bigint NOT NULL REFERENCES mes.partida_paso(id),
    partida_item_id int NOT NULL REFERENCES mes.partida_item(id), -- Must be one of the IDs in partida_rollo
    cantidad numeric(10,2) NOT NULL,
    peso numeric(10,2) NOT NULL,
    usr_cre int,
    fyh_cre TIMESTAMPTZ DEFAULT NOW(),
  usr_mod int,
  fyh_mod TIMESTAMPTZ,
    PRIMARY KEY (partida_paso_id, partida_item_id)
);




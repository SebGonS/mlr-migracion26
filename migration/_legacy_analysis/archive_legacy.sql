-- =====================================================================
-- REFERENCE ONLY — legacy objects excluded from the clean baseline.
-- Do not execute against the new project. Kept for historical lookup.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABLE: doc.tmp_pricing_baseline
-- ---------------------------------------------------------------------
CREATE TABLE doc.tmp_pricing_baseline (
    partida_id bigint,
    operacion_id smallint,
    operacion text,
    es_antipilling boolean,
    precio_kg numeric,
    sin_precio boolean
);


ALTER TABLE doc.tmp_pricing_baseline OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: migration.legacy_executions
-- ---------------------------------------------------------------------
CREATE TABLE migration.legacy_executions (
    id integer NOT NULL,
    source_table text NOT NULL,
    legacy_id integer NOT NULL,
    partida_id integer NOT NULL,
    operacion_id integer NOT NULL,
    operacion_codigo text NOT NULL,
    fecha date,
    fyh_inicio timestamp with time zone,
    fyh_fin timestamp with time zone,
    legacy_maquina integer,
    legacy_rollos integer,
    legacy_kilos numeric,
    legacy_estado text,
    usr_cre integer,
    new_paso_id bigint,
    new_ejecucion_id bigint,
    status text DEFAULT 'PENDING'::text NOT NULL
);


ALTER TABLE migration.legacy_executions OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.adicional
-- ---------------------------------------------------------------------
CREATE TABLE public.adicional (
    id smallint NOT NULL,
    adicional text
);


ALTER TABLE public.adicional OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.auditoria
-- ---------------------------------------------------------------------
CREATE TABLE public.auditoria (
    id integer NOT NULL,
    partida_id integer,
    fecha_auditoria date,
    estado text
);


ALTER TABLE public.auditoria OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.catalogo_precios
-- ---------------------------------------------------------------------
CREATE TABLE public.catalogo_precios (
    id_precio integer NOT NULL,
    color_x_cliente_id integer,
    tipo_articulo_id integer,
    tenido_id integer,
    fibra integer,
    adicional_id integer,
    precio_tenido numeric(5,2),
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fyh_fin timestamp without time zone,
    activo smallint DEFAULT 1 NOT NULL,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.catalogo_precios OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.cliente
-- ---------------------------------------------------------------------
CREATE TABLE public.cliente (
    id integer NOT NULL,
    cliente text,
    empresa text,
    ruc text,
    correo text,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    cliente_normalizado text GENERATED ALWAYS AS (regexp_replace(lower(TRIM(BOTH FROM cliente)), '\s+'::text, ''::text, 'g'::text)) STORED,
    procedencia character varying(50)
);


ALTER TABLE public.cliente OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.compactado
-- ---------------------------------------------------------------------
CREATE TABLE public.compactado (
    partida_id integer,
    fecha date,
    rollos integer,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    duracion time without time zone,
    maquina_id integer,
    id integer NOT NULL,
    turno_id integer,
    tipo_proceso character varying,
    estado character varying,
    rib integer
);


ALTER TABLE public.compactado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.compra
-- ---------------------------------------------------------------------
CREATE TABLE public.compra (
    id integer NOT NULL,
    proveedor_id smallint,
    factura text,
    guia_remision text,
    tipo_pago public.tipo_pago_enum,
    fecha_remision date,
    fecha_giro date,
    fecha_vencimiento date,
    fecha_pago date,
    total_usd numeric(10,2) NOT NULL,
    estado_pago public.estado_pago_enum DEFAULT 'pendiente'::public.estado_pago_enum,
    fyh_recepcion timestamp without time zone,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre text DEFAULT CURRENT_USER,
    fyh_mod timestamp without time zone,
    usr_mod text,
    estado_ingreso public.estado_ingreso_compra_enum DEFAULT 'pendiente'::public.estado_ingreso_compra_enum,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.compra OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.compra_x_insumo
-- ---------------------------------------------------------------------
CREATE TABLE public.compra_x_insumo (
    id integer NOT NULL,
    compra_id integer,
    insumo_id smallint,
    cantidad numeric(10,2) NOT NULL,
    precio_x_kg_usd numeric(7,4) NOT NULL,
    insumo_x_proveedor_id integer
);


ALTER TABLE public.compra_x_insumo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.entrada_inventario
-- ---------------------------------------------------------------------
CREATE TABLE public.entrada_inventario (
    id integer NOT NULL,
    motivo public.motivo_entrada_inventario_enum NOT NULL,
    estado public.estado_entrada_inventario_enum DEFAULT 'pendiente'::public.estado_entrada_inventario_enum,
    fyh_solicitud timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_revision timestamp without time zone,
    usr_solicita smallint DEFAULT public.get_user_id(),
    usr_revisa smallint,
    observacion text,
    fyh_solicitud_tz timestamp with time zone DEFAULT now(),
    fyh_entrada_real timestamp with time zone
);


ALTER TABLE public.entrada_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.entrada_inventario_detalle
-- ---------------------------------------------------------------------
CREATE TABLE public.entrada_inventario_detalle (
    id integer NOT NULL,
    entrada_inventario_id integer NOT NULL,
    insumo_x_proveedor_id integer,
    compra_x_insumo_id integer,
    cantidad_solicitada numeric(8,4) NOT NULL,
    cantidad_recibida numeric(8,4),
    estado public.estado_entrada_inventario_enum DEFAULT 'pendiente'::public.estado_entrada_inventario_enum NOT NULL,
    observacion text,
    insumo_id integer,
    CONSTRAINT entrada_inventario_detalle_cantidad_recibida_check CHECK ((cantidad_recibida >= (0)::numeric)),
    CONSTRAINT entrada_inventario_detalle_cantidad_solicitada_check CHECK ((cantidad_solicitada > (0)::numeric))
);


ALTER TABLE public.entrada_inventario_detalle OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.insumo
-- ---------------------------------------------------------------------
CREATE TABLE public.insumo (
    id smallint NOT NULL,
    insumo text COLLATE public.case_insensitive,
    medida public.medida_enum,
    tipo public.tipo_insumo_enum,
    precio_prom_kg_usd numeric(8,4),
    fyh_mod timestamp with time zone,
    usr_mod smallint,
    flg_elm boolean,
    fyh_elm timestamp with time zone,
    usr_elm smallint
);


ALTER TABLE public.insumo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.insumo_x_proveedor
-- ---------------------------------------------------------------------
CREATE TABLE public.insumo_x_proveedor (
    insumo_id smallint,
    proveedor_id smallint,
    precio_x_kg_usd numeric(7,4),
    fyh_inicio date DEFAULT CURRENT_TIMESTAMP,
    fyh_fin date,
    nombre_comercial text,
    id integer NOT NULL
);


ALTER TABLE public.insumo_x_proveedor OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.inventario
-- ---------------------------------------------------------------------
CREATE TABLE public.inventario (
    id integer NOT NULL,
    entrada_inventario_detalle_id integer NOT NULL,
    insumo_x_proveedor_id smallint,
    cantidad numeric(8,4) NOT NULL,
    fyh_ingreso timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    costo_bruto_kg numeric(7,4),
    usr_cre integer,
    insumo_id integer,
    fyh_cre timestamp with time zone DEFAULT now(),
    CONSTRAINT inventario_cantidad_check CHECK ((cantidad >= (0)::numeric))
);


ALTER TABLE public.inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.proveedor
-- ---------------------------------------------------------------------
CREATE TABLE public.proveedor (
    id smallint NOT NULL,
    proveedor text NOT NULL COLLATE pg_catalog."C",
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre text DEFAULT CURRENT_USER,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    proveedor_normalizado text GENERATED ALWAYS AS (regexp_replace(lower(TRIM(BOTH FROM proveedor)), '\s+'::text, ''::text, 'g'::text)) STORED
);


ALTER TABLE public.proveedor OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.salida_inventario_detalle_x_stock
-- ---------------------------------------------------------------------
CREATE TABLE public.salida_inventario_detalle_x_stock (
    id integer NOT NULL,
    salida_inventario_detalle_id integer NOT NULL,
    inventario_id integer,
    cantidad numeric(12,5) NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_cre timestamp with time zone DEFAULT now(),
    CONSTRAINT salida_inventario_detalle_x_stock_cantidad_check CHECK ((cantidad > (0)::numeric))
);


ALTER TABLE public.salida_inventario_detalle_x_stock OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.cuadre_inventario
-- ---------------------------------------------------------------------
CREATE TABLE public.cuadre_inventario (
    id integer NOT NULL,
    fecha_cuadre timestamp with time zone DEFAULT now(),
    fecha_cierre timestamp with time zone,
    usr_cre integer DEFAULT public.get_user_id(),
    fyh_cre timestamp with time zone DEFAULT now(),
    usr_mod integer,
    fyh_mod timestamp with time zone,
    estado public.cuadre_estado_enum DEFAULT 'borrador'::public.cuadre_estado_enum
);


ALTER TABLE public.cuadre_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.cuadre_inventario_detalle
-- ---------------------------------------------------------------------
CREATE TABLE public.cuadre_inventario_detalle (
    id integer NOT NULL,
    cuadre_inventario_id integer,
    insumo_id integer,
    cantidad_sistema numeric(12,4),
    cantidad_contada numeric(12,4),
    costo_bruto_total_sistema numeric(14,4),
    costo_bruto_prom_kg_sistema numeric(12,6),
    ult_precio_compra numeric(12,4),
    usr_mod integer,
    fyh_mod timestamp with time zone
);


ALTER TABLE public.cuadre_inventario_detalle OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.desarrollo_color
-- ---------------------------------------------------------------------
CREATE TABLE public.desarrollo_color (
    id integer NOT NULL,
    color_x_cliente_id smallint,
    tipo_articulo_id smallint,
    tenido_id smallint,
    fecha_ingreso date NOT NULL,
    estado_desarrollo_color_id smallint,
    fecha_estado_actual date,
    descripcion text,
    fyh_cre timestamp without time zone DEFAULT now(),
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.desarrollo_color OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.despacho
-- ---------------------------------------------------------------------
CREATE TABLE public.despacho (
    partida_id integer,
    fecha_despacho date,
    rollos integer,
    rib integer,
    id integer NOT NULL,
    rollos_total integer GENERATED ALWAYS AS ((rollos + rib)) STORED,
    nfactura text,
    precio_unit real,
    flg_elm boolean DEFAULT false,
    fyh_cre timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.despacho OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.detecciones
-- ---------------------------------------------------------------------
CREATE TABLE public.detecciones (
    id bigint NOT NULL,
    partida_id integer NOT NULL,
    nro_rollo integer NOT NULL,
    clase text NOT NULL,
    coordenadas jsonb,
    frame text NOT NULL,
    hora timestamp with time zone DEFAULT now() NOT NULL,
    score numeric(4,2),
    CONSTRAINT detecciones_clase_check CHECK ((clase = ANY (ARRAY['hole'::text, 'line'::text, 'stain'::text, 'inicio'::text, 'fin'::text])))
);


ALTER TABLE public.detecciones OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.devolucion
-- ---------------------------------------------------------------------
CREATE TABLE public.devolucion (
    id integer NOT NULL,
    partida_id integer NOT NULL,
    fecha_devolucion date NOT NULL,
    guia_remision text NOT NULL,
    rollos integer NOT NULL,
    rib integer NOT NULL,
    motivo text,
    observacion text,
    flg_elm boolean DEFAULT false,
    fyh_cre timestamp with time zone DEFAULT now()
);


ALTER TABLE public.devolucion OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.estado
-- ---------------------------------------------------------------------
CREATE TABLE public.estado (
    id integer NOT NULL,
    estado text NOT NULL,
    descripcion text,
    fyh_cre timestamp with time zone,
    estado_produccion public.partida_estado_produccion_enum,
    estado_comercial public.partida_estado_comercial_enum
);


ALTER TABLE public.estado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.extra
-- ---------------------------------------------------------------------
CREATE TABLE public.extra (
    id smallint NOT NULL,
    cod_extra character varying(10),
    extra character varying(30)
);


ALTER TABLE public.extra OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.historial_estado_color
-- ---------------------------------------------------------------------
CREATE TABLE public.historial_estado_color (
    id_historial integer NOT NULL,
    desarrollo_color_id integer,
    estado_desarrollo_color_id smallint,
    fecha_estado date NOT NULL,
    observaciones text,
    usr_cre text DEFAULT CURRENT_USER,
    fyh_cre timestamp without time zone DEFAULT now(),
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.historial_estado_color OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.hora_inicio_maquina
-- ---------------------------------------------------------------------
CREATE TABLE public.hora_inicio_maquina (
    maquina_id smallint NOT NULL,
    hora_inicio time without time zone NOT NULL
);


ALTER TABLE public.hora_inicio_maquina OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.id_receta_x_partida
-- ---------------------------------------------------------------------
CREATE TABLE public.id_receta_x_partida (
    id integer
);


ALTER TABLE public.id_receta_x_partida OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.insumo_corregido
-- ---------------------------------------------------------------------
CREATE TABLE public.insumo_corregido (
    id smallint,
    insumo text,
    medida public.medida_enum,
    precio numeric(7,3),
    nombre_anterior character varying
);


ALTER TABLE public.insumo_corregido OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.insumos_precio
-- ---------------------------------------------------------------------
CREATE TABLE public.insumos_precio (
    id bigint NOT NULL,
    componente character varying,
    tipo character varying,
    proveedor character varying,
    precio_usd real,
    flg_elm integer,
    medida public.medida_enum
);


ALTER TABLE public.insumos_precio OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.json_debug_log
-- ---------------------------------------------------------------------
CREATE TABLE public.json_debug_log (
    id integer NOT NULL,
    received_at timestamp without time zone DEFAULT now(),
    received_json jsonb,
    received_at_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.json_debug_log OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.lavado_maquina
-- ---------------------------------------------------------------------
CREATE TABLE public.lavado_maquina (
    id integer NOT NULL,
    fecha date,
    receta_lavado_mq_id smallint,
    maquina_id smallint,
    fyh_cre timestamp without time zone
);


ALTER TABLE public.lavado_maquina OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.letra_compra
-- ---------------------------------------------------------------------
CREATE TABLE public.letra_compra (
    id integer NOT NULL,
    compra_id integer NOT NULL,
    numero_letra text NOT NULL,
    monto_usd numeric(12,2) NOT NULL,
    fecha_emision date NOT NULL,
    fecha_vencimiento date NOT NULL,
    estado public.estado_letra_enum DEFAULT 'emitida'::public.estado_letra_enum NOT NULL,
    fecha_pago date,
    observaciones text,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre integer DEFAULT public.get_user_id(),
    fyh_mod timestamp without time zone,
    usr_mod integer,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.letra_compra OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.maquina
-- ---------------------------------------------------------------------
CREATE TABLE public.maquina (
    id integer NOT NULL,
    nombre character varying(20),
    ubicacion character varying(20),
    seccion character varying(15),
    "RB" integer,
    impacto character varying(10)
);


ALTER TABLE public.maquina OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.matizado
-- ---------------------------------------------------------------------
CREATE TABLE public.matizado (
    id bigint NOT NULL,
    fecha date,
    insumo_id integer,
    cantidad real,
    partida_id integer,
    medida character varying,
    turno_id integer
);


ALTER TABLE public.matizado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.matizado_estados
-- ---------------------------------------------------------------------
CREATE TABLE public.matizado_estados (
    id integer NOT NULL,
    partida_id integer,
    fecha date,
    estado character varying(50)
);


ALTER TABLE public.matizado_estados OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.mersan
-- ---------------------------------------------------------------------
CREATE TABLE public.mersan (
    fecha text,
    partida text,
    ancho text,
    cliente text,
    rollos bigint,
    articulo text,
    maquina text,
    hora_inicio text,
    hora_final text
);


ALTER TABLE public.mersan OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.metas_produccion_tenido
-- ---------------------------------------------------------------------
CREATE TABLE public.metas_produccion_tenido (
    id integer NOT NULL,
    "año" integer NOT NULL,
    mes integer NOT NULL,
    kilos numeric(14,2) NOT NULL,
    observacion text,
    fyh_cre timestamp without time zone DEFAULT now(),
    fyh_mod timestamp without time zone DEFAULT now()
);


ALTER TABLE public.metas_produccion_tenido OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.motivo_parada
-- ---------------------------------------------------------------------
CREATE TABLE public.motivo_parada (
    id integer NOT NULL,
    categoria text,
    motivo text NOT NULL,
    tipo text,
    critico boolean DEFAULT false
);


ALTER TABLE public.motivo_parada OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.motivos_retraso
-- ---------------------------------------------------------------------
CREATE TABLE public.motivos_retraso (
    id bigint NOT NULL,
    motivo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.motivos_retraso OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.observaciones_planta
-- ---------------------------------------------------------------------
CREATE TABLE public.observaciones_planta (
    id integer NOT NULL,
    fecha date,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    turno_id smallint,
    maquina_id smallint,
    detalle text,
    duracion time without time zone
);


ALTER TABLE public.observaciones_planta OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.observado
-- ---------------------------------------------------------------------
CREATE TABLE public.observado (
    id bigint NOT NULL,
    partida_id integer,
    fecha date,
    rollos integer,
    motivo_observado_id integer,
    flg_elm integer,
    detalle text,
    fyh_cre timestamp without time zone DEFAULT now(),
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    rib integer
);


ALTER TABLE public.observado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.observado_estados
-- ---------------------------------------------------------------------
CREATE TABLE public.observado_estados (
    id integer NOT NULL,
    partida_id integer,
    fecha date,
    estado character varying(50)
);


ALTER TABLE public.observado_estados OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.observado_motivos
-- ---------------------------------------------------------------------
CREATE TABLE public.observado_motivos (
    id integer NOT NULL,
    motivo text
);


ALTER TABLE public.observado_motivos OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.parada_tintoreria
-- ---------------------------------------------------------------------
CREATE TABLE public.parada_tintoreria (
    id bigint NOT NULL,
    maquina_id integer NOT NULL,
    turno_id integer NOT NULL,
    motivo_id integer NOT NULL,
    fecha_inicio timestamp without time zone NOT NULL,
    fecha_fin timestamp without time zone,
    duracion interval GENERATED ALWAYS AS ((fecha_fin - fecha_inicio)) STORED,
    observacion text,
    usuario text DEFAULT CURRENT_USER,
    created_at timestamp without time zone DEFAULT now(),
    duracion_horas numeric GENERATED ALWAYS AS ((EXTRACT(epoch FROM (fecha_fin - fecha_inicio)) / (3600)::numeric)) STORED,
    duracion_minutos integer GENERATED ALWAYS AS ((EXTRACT(epoch FROM (fecha_fin - fecha_inicio)) / (60)::numeric)) STORED,
    CONSTRAINT chk_fechas_validas CHECK (((fecha_fin IS NULL) OR (fecha_fin >= fecha_inicio)))
);


ALTER TABLE public.parada_tintoreria OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.parada_tmp
-- ---------------------------------------------------------------------
CREATE TABLE public.parada_tmp (
    maquina_id integer,
    turno_id integer,
    motivo_id integer,
    fecha_inicio timestamp without time zone,
    fecha_fin timestamp without time zone,
    observacion text,
    usuario text
);


ALTER TABLE public.parada_tmp OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.partida
-- ---------------------------------------------------------------------
CREATE TABLE public.partida (
    id integer NOT NULL,
    fecha_registro date DEFAULT CURRENT_DATE,
    guia character varying(250),
    fecha_entrega date,
    prioridad_id smallint,
    cliente_id smallint,
    articulo_id smallint,
    color_x_cliente_id smallint,
    rib smallint DEFAULT 0,
    tenido_id smallint,
    fibra smallint,
    previo_id smallint,
    malla character varying(10),
    adicional_id smallint,
    ancho character varying(10),
    rendimiento character varying(10),
    rollos smallint,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_peso timestamp without time zone,
    receta_id integer,
    costo_total_usd double precision,
    precio_usd real,
    factura character varying,
    peso_rollos double precision,
    peso_rib double precision,
    usr_cre integer DEFAULT public.get_user_id(),
    observacion text,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    codigo integer DEFAULT nextval('public.partida_codigo_seq'::regclass)
);


ALTER TABLE public.partida OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.partida_estado_historial
-- ---------------------------------------------------------------------
CREATE TABLE public.partida_estado_historial (
    id integer NOT NULL,
    partida_id integer NOT NULL,
    estado_id integer NOT NULL,
    rollos_afectados integer NOT NULL,
    rib_afectados integer DEFAULT 0 NOT NULL,
    fecha_ejecucion date NOT NULL,
    fyh_cre timestamp with time zone DEFAULT now()
);


ALTER TABLE public.partida_estado_historial OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.partida_x_extra
-- ---------------------------------------------------------------------
CREATE TABLE public.partida_x_extra (
    partida_id integer,
    extra_id smallint,
    cantidad smallint,
    peso numeric(6,2)
);


ALTER TABLE public.partida_x_extra OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.partida_x_recetas
-- ---------------------------------------------------------------------
CREATE TABLE public.partida_x_recetas (
    id integer NOT NULL,
    fecha date,
    partida_id smallint,
    receta_id smallint,
    tipo_receta_id smallint,
    maquina_id smallint,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    flg_elm boolean DEFAULT false,
    fyh_elm timestamp without time zone,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    rollos integer,
    relacion_bano smallint,
    rib integer
);


ALTER TABLE public.partida_x_recetas OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.paso
-- ---------------------------------------------------------------------
CREATE TABLE public.paso (
    id smallint NOT NULL,
    paso text COLLATE public.case_insensitive,
    op_id smallint,
    ph_val numeric(4,2),
    temp_val numeric(5,2),
    tiempo_val smallint
);


ALTER TABLE public.paso OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.pasos_adicional_receta
-- ---------------------------------------------------------------------
CREATE TABLE public.pasos_adicional_receta (
    id_receta integer,
    pasos text,
    orden integer,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.pasos_adicional_receta OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.perchado
-- ---------------------------------------------------------------------
CREATE TABLE public.perchado (
    id integer NOT NULL,
    partida_id integer,
    fecha date,
    turno_id smallint,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    duracion time without time zone,
    rollos integer,
    pases integer
);


ALTER TABLE public.perchado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.previo
-- ---------------------------------------------------------------------
CREATE TABLE public.previo (
    id smallint NOT NULL,
    previo text
);


ALTER TABLE public.previo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.prod_tmp
-- ---------------------------------------------------------------------
CREATE TABLE public.prod_tmp (
    meta_id integer,
    "año" integer,
    mes character varying,
    kilos numeric(14,2),
    observacion text,
    fyh_cre timestamp without time zone,
    fyh_mod timestamp without time zone
);


ALTER TABLE public.prod_tmp OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.produccion
-- ---------------------------------------------------------------------
CREATE TABLE public.produccion (
    partida integer,
    "fecha_teñido" date,
    proceso character varying(15),
    maquina character varying(20),
    tipo character varying(50),
    hora_inicio time without time zone,
    hora_fin time without time zone,
    duracion_total time without time zone,
    duracion_estandar time without time zone,
    estado character varying(15)
);


ALTER TABLE public.produccion OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.produccion_tenido
-- ---------------------------------------------------------------------
CREATE TABLE public.produccion_tenido (
    id bigint NOT NULL,
    partida_id bigint NOT NULL,
    fecha date,
    maquina smallint,
    tipo character varying,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    duracion time without time zone,
    rollos double precision,
    kilos double precision,
    estado character varying,
    estandar time without time zone
);


ALTER TABLE public.produccion_tenido OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.programa_tenido
-- ---------------------------------------------------------------------
CREATE TABLE public.programa_tenido (
    id integer NOT NULL,
    fecha date NOT NULL,
    maquina_id smallint,
    orden smallint NOT NULL,
    partida_id integer,
    tipo_lavado_mq_id smallint,
    tipo_receta_id smallint,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    rollos_programados integer,
    rib_programados integer,
    CONSTRAINT chk_una_opcion CHECK ((((partida_id IS NOT NULL) AND (tipo_lavado_mq_id IS NULL)) OR ((partida_id IS NULL) AND (tipo_lavado_mq_id IS NOT NULL))))
);


ALTER TABLE public.programa_tenido OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.programacion
-- ---------------------------------------------------------------------
CREATE TABLE public.programacion (
    partida integer,
    fecha_programacion date,
    maquina_id smallint
);


ALTER TABLE public.programacion OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.proveedor_precio
-- ---------------------------------------------------------------------
CREATE TABLE public.proveedor_precio (
    id integer NOT NULL,
    insumo_x_proveedor_id integer NOT NULL,
    precio_x_kg_usd numeric(8,4) NOT NULL,
    fyh_inicio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fyh_fin timestamp without time zone,
    fyh_inicio_tz timestamp with time zone DEFAULT now(),
    CONSTRAINT proveedor_precio_check CHECK (((fyh_fin IS NULL) OR (fyh_fin > fyh_inicio))),
    CONSTRAINT proveedor_precio_precio_x_kg_usd_check CHECK ((precio_x_kg_usd > (0)::numeric))
);


ALTER TABLE public.proveedor_precio OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta2
-- ---------------------------------------------------------------------
CREATE TABLE public.receta2 (
    id integer NOT NULL,
    color_x_cliente_id smallint,
    tipo_articulo_id smallint,
    tenido_id smallint,
    fibra smallint,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre text DEFAULT CURRENT_USER,
    flg_activo boolean DEFAULT true,
    flg_antipilling boolean DEFAULT false,
    tipo_receta_id smallint,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    flg_produccion boolean DEFAULT false,
    fyh_produccion timestamp with time zone
);


ALTER TABLE public.receta2 OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta_id
-- ---------------------------------------------------------------------
CREATE TABLE public.receta_id (
    id integer
);


ALTER TABLE public.receta_id OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta_lavado_maquina
-- ---------------------------------------------------------------------
CREATE TABLE public.receta_lavado_maquina (
    id integer NOT NULL,
    tipo_lavado_mq_id smallint,
    valor_origen_id smallint,
    valor_destino_id smallint,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre text DEFAULT CURRENT_USER,
    flg_activo boolean DEFAULT true,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.receta_lavado_maquina OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta_lavado_maquina_x_insumo
-- ---------------------------------------------------------------------
CREATE TABLE public.receta_lavado_maquina_x_insumo (
    receta_lavado_mq_id integer,
    insumo_id smallint,
    cantidad numeric(10,4) NOT NULL,
    orden smallint NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.receta_lavado_maquina_x_insumo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta_lavado_maquina_x_paso
-- ---------------------------------------------------------------------
CREATE TABLE public.receta_lavado_maquina_x_paso (
    receta_lavado_mq_id integer,
    paso_id smallint,
    orden smallint NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.receta_lavado_maquina_x_paso OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta_x_insumo
-- ---------------------------------------------------------------------
CREATE TABLE public.receta_x_insumo (
    receta_id integer,
    insumo_id smallint,
    cantidad numeric(8,4) NOT NULL,
    orden smallint NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.receta_x_insumo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.receta_x_paso
-- ---------------------------------------------------------------------
CREATE TABLE public.receta_x_paso (
    receta_id integer,
    paso_id smallint,
    orden smallint NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.receta_x_paso OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.regla_peso_articulo
-- ---------------------------------------------------------------------
CREATE TABLE public.regla_peso_articulo (
    articulo_id smallint NOT NULL,
    min_kg_por_rollo numeric(10,3) NOT NULL
);


ALTER TABLE public.regla_peso_articulo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.regla_peso_cliente_articulo
-- ---------------------------------------------------------------------
CREATE TABLE public.regla_peso_cliente_articulo (
    cliente_id smallint NOT NULL,
    articulo_id smallint NOT NULL,
    min_kg_por_rollo numeric(10,3) NOT NULL
);


ALTER TABLE public.regla_peso_cliente_articulo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.retrasos_partida
-- ---------------------------------------------------------------------
CREATE TABLE public.retrasos_partida (
    id bigint NOT NULL,
    partida_id bigint NOT NULL,
    motivo_id bigint NOT NULL,
    observacion text,
    fecha date,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.retrasos_partida OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.salida_inventario
-- ---------------------------------------------------------------------
CREATE TABLE public.salida_inventario (
    id integer NOT NULL,
    motivo public.motivo_salida_inventario_enum NOT NULL,
    partida_x_recetas_id integer,
    estado public.estado_salida_inventario_enum DEFAULT 'pendiente'::public.estado_salida_inventario_enum,
    fyh_solicitud timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_revision timestamp without time zone,
    usr_solicita smallint DEFAULT public.get_user_id(),
    usr_revisa smallint,
    observacion text,
    fecha_salida date DEFAULT (CURRENT_DATE AT TIME ZONE 'America/Lima'::text),
    fyh_solicitud_tz timestamp with time zone DEFAULT now(),
    fyh_salida_real timestamp with time zone
);


ALTER TABLE public.salida_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.salida_inventario_detalle
-- ---------------------------------------------------------------------
CREATE TABLE public.salida_inventario_detalle (
    id integer NOT NULL,
    salida_inventario_id integer NOT NULL,
    cantidad_solicitada numeric(12,5) NOT NULL,
    insumo_id smallint NOT NULL,
    estado public.estado_salida_inventario_enum DEFAULT 'pendiente'::public.estado_salida_inventario_enum,
    observacion text,
    CONSTRAINT salida_inventario_detalle_cantidad_solicitada_check CHECK ((cantidad_solicitada > (0)::numeric))
);


ALTER TABLE public.salida_inventario_detalle OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.sertks1
-- ---------------------------------------------------------------------
CREATE TABLE public.sertks1 (
    fecha text,
    partida text,
    ancho text,
    cliente text,
    rollos text,
    articulo text,
    maquina text,
    hora_inicio text,
    hora_final text
);


ALTER TABLE public.sertks1 OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.sertks2
-- ---------------------------------------------------------------------
CREATE TABLE public.sertks2 (
    fecha text,
    partida bigint,
    ancho text,
    cliente text,
    rollos text,
    articulo text,
    maquina text,
    hora_inicio text,
    hora_final text
);


ALTER TABLE public.sertks2 OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.temp_id_partida
-- ---------------------------------------------------------------------
CREATE TABLE public.temp_id_partida (
    id integer
);


ALTER TABLE public.temp_id_partida OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.temp_id_receta
-- ---------------------------------------------------------------------
CREATE TABLE public.temp_id_receta (
    id integer
);


ALTER TABLE public.temp_id_receta OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.temp_insumos_corregidos
-- ---------------------------------------------------------------------
CREATE TABLE public.temp_insumos_corregidos (
    id bigint,
    insumo text,
    medida text,
    precio text,
    nombre_anterior text
);


ALTER TABLE public.temp_insumos_corregidos OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.termofijado
-- ---------------------------------------------------------------------
CREATE TABLE public.termofijado (
    id integer NOT NULL,
    partida_id integer,
    fecha date,
    turno_id smallint,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    duracion time without time zone,
    rollos integer
);


ALTER TABLE public.termofijado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tiempos_estandar_lavado
-- ---------------------------------------------------------------------
CREATE TABLE public.tiempos_estandar_lavado (
    id integer NOT NULL,
    tipo_lavado_mq_id smallint,
    duracion interval NOT NULL,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    flg_activo boolean DEFAULT true,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.tiempos_estandar_lavado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tiempos_estandar_tenido
-- ---------------------------------------------------------------------
CREATE TABLE public.tiempos_estandar_tenido (
    id integer NOT NULL,
    valor_id smallint,
    tenido_id smallint,
    adicional_id smallint,
    duracion interval NOT NULL,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    flg_activo boolean DEFAULT true,
    tipo_receta_id smallint,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.tiempos_estandar_tenido OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tmp
-- ---------------------------------------------------------------------
CREATE TABLE public.tmp (
    partida_ten bigint,
    fecha_ten date,
    maquina smallint,
    tipo character varying,
    tipo_receta_id smallint,
    tono text,
    color character varying(25),
    tipo_articulo text,
    fibra smallint,
    adicional text,
    receta_id integer,
    tipo_receta text COLLATE public.case_insensitive,
    fk_tipo_receta smallint
);


ALTER TABLE public.tmp OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tmp2
-- ---------------------------------------------------------------------
CREATE TABLE public.tmp2 (
    id bigint,
    partida_ten bigint,
    tipo character varying,
    maquina smallint,
    fecha_ten date,
    receta_id integer,
    tipo_receta text COLLATE public.case_insensitive,
    fecha_receta date
);


ALTER TABLE public.tmp2 OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tmp_parche
-- ---------------------------------------------------------------------
CREATE TABLE public.tmp_parche (
    fk_receta integer,
    paso text COLLATE public.case_insensitive,
    orden_representativo text COLLATE public.case_insensitive
);


ALTER TABLE public.tmp_parche OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tmp_receta
-- ---------------------------------------------------------------------
CREATE TABLE public.tmp_receta (
    fk_receta integer
);


ALTER TABLE public.tmp_receta OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.tmp_receta_casos
-- ---------------------------------------------------------------------
CREATE TABLE public.tmp_receta_casos (
    fk_receta integer
);


ALTER TABLE public.tmp_receta_casos OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.unidad_conversion
-- ---------------------------------------------------------------------
CREATE TABLE public.unidad_conversion (
    de_unidad_id integer NOT NULL,
    a_unidad_id integer NOT NULL,
    factor numeric(18,6) NOT NULL
);


ALTER TABLE public.unidad_conversion OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TABLE: public.v_receta_id
-- ---------------------------------------------------------------------
CREATE TABLE public.v_receta_id (
    receta_id integer
);


ALTER TABLE public.v_receta_id OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_insumos_proveedor
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_insumos_proveedor AS
 SELECT i.id AS insumo_id,
    ip.id AS insumo_x_proveedor_id,
    i.insumo,
    i.medida,
    i.tipo,
    p.id AS proveedor_id,
    p.proveedor,
    ip.precio_x_kg_usd,
    ip.fyh_inicio
   FROM ((public.insumo i
     JOIN public.insumo_x_proveedor ip ON ((i.id = ip.insumo_id)))
     JOIN public.proveedor p ON ((p.id = ip.proveedor_id)))
  WHERE (ip.fyh_fin IS NULL);


ALTER VIEW public.vw_insumos_proveedor OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_inventario
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_inventario AS
 WITH salidas AS (
         SELECT salida_inventario_detalle_x_stock.inventario_id AS fk_inventario,
            sum(salida_inventario_detalle_x_stock.cantidad) AS cantidad_egresada
           FROM public.salida_inventario_detalle_x_stock
          GROUP BY salida_inventario_detalle_x_stock.inventario_id
        )
 SELECT i.id AS inventario_id,
    i.entrada_inventario_detalle_id,
    i.insumo_x_proveedor_id,
    i.fyh_ingreso,
    i.cantidad AS cantidad_inicial,
    COALESCE(s.cantidad_egresada, (0)::numeric) AS cantidad_egresada,
    (i.cantidad - COALESCE(s.cantidad_egresada, (0)::numeric)) AS cantidad,
    i.costo_bruto_kg,
    ((i.cantidad - COALESCE(s.cantidad_egresada, (0)::numeric)) * i.costo_bruto_kg) AS costo_bruto_total,
    i.insumo_id
   FROM (public.inventario i
     LEFT JOIN salidas s ON ((i.id = s.fk_inventario)));


ALTER VIEW public.vw_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.comrpas_pendientes_completas
-- ---------------------------------------------------------------------
CREATE VIEW public.comrpas_pendientes_completas AS
 WITH ingresado AS (
         SELECT eid.compra_x_insumo_id AS fk_compra_x_insumo,
            sum(inventario.cantidad) AS cantidad_ingresada_total
           FROM (public.inventario
             LEFT JOIN public.entrada_inventario_detalle eid ON ((eid.id = inventario.entrada_inventario_detalle_id)))
          GROUP BY eid.compra_x_insumo_id
        ), compras AS (
         SELECT com.id AS pk_compra,
            com.proveedor_id AS fk_proveedor,
            com.factura,
            com.guia_remision,
            com.tipo_pago,
            com.fecha_remision,
            com.fecha_giro,
            com.fecha_vencimiento,
            com.fecha_pago,
            com.total_usd,
            com.estado_pago,
            com.fyh_recepcion,
            com.fyh_cre,
            com.usr_cre,
            com.fyh_mod,
            com.usr_mod,
            com.estado_ingreso,
            com.fyh_cre_tz,
            vi.insumo,
            ei.id AS pk_entrada_inventario,
            ci.id AS pk_compra_x_insumo,
            ei.estado,
            ei.fyh_solicitud,
            ei.fyh_revision,
            public.get_user_by_id((ei.usr_solicita)::integer) AS solicita,
            public.get_user_by_id((ei.usr_revisa)::integer) AS aprueba,
            inv.fyh_ingreso AS ingreso_inv,
            eid.cantidad_solicitada,
            ing.cantidad_ingresada_total,
            inv.cantidad_inicial AS cantidad_ingresada,
            inv.cantidad
           FROM ((((((public.entrada_inventario ei
             LEFT JOIN public.entrada_inventario_detalle eid ON ((ei.id = eid.entrada_inventario_id)))
             LEFT JOIN ingresado ing ON ((eid.compra_x_insumo_id = ing.fk_compra_x_insumo)))
             LEFT JOIN public.compra_x_insumo ci ON ((ing.fk_compra_x_insumo = ci.id)))
             LEFT JOIN public.vw_inventario inv ON ((inv.entrada_inventario_detalle_id = eid.id)))
             LEFT JOIN public.vw_insumos_proveedor vi ON ((ci.insumo_x_proveedor_id = vi.insumo_x_proveedor_id)))
             LEFT JOIN public.compra com ON ((com.id = ci.compra_id)))
          WHERE ((ei.motivo = 'compra'::public.motivo_entrada_inventario_enum) AND (com.estado_ingreso = 'pendiente'::public.estado_ingreso_compra_enum))
          ORDER BY ci.id
        )
 SELECT c.pk_compra AS id
   FROM compras c
  GROUP BY c.pk_compra
 HAVING bool_and((c.cantidad_ingresada_total >= c.cantidad_solicitada));


ALTER VIEW public.comrpas_pendientes_completas OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_compra_insumos
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_compra_insumos AS
 WITH ingresado AS (
         SELECT eid.compra_x_insumo_id AS fk_compra_x_insumo,
            eid.insumo_x_proveedor_id AS fk_insumo_x_proveedor,
            sum(eid.cantidad_recibida) AS cantidad_ingresada
           FROM public.entrada_inventario_detalle eid
          WHERE ((eid.compra_x_insumo_id IS NOT NULL) AND (eid.estado = 'aprobado'::public.estado_entrada_inventario_enum))
          GROUP BY eid.compra_x_insumo_id, eid.insumo_x_proveedor_id
        )
 SELECT c.id AS compra_id,
    cp.id AS compra_x_insumo_id,
    cp.insumo_x_proveedor_id,
    i.insumo,
    i.tipo,
    cp.cantidad,
    COALESCE(ing.cantidad_ingresada, (0)::numeric) AS cantidad_ingresada,
    (cp.cantidad - COALESCE(ing.cantidad_ingresada, (0)::numeric)) AS cantidad_restante,
    (cp.cantidad * cp.precio_x_kg_usd) AS valor_bruto,
    ((cp.cantidad * cp.precio_x_kg_usd) * 1.18) AS valor_neto,
    c.estado_ingreso,
    (cp.cantidad - COALESCE(ing.cantidad_ingresada, (0)::numeric)) AS ingreso_restante
   FROM ((((public.insumo i
     JOIN public.insumo_x_proveedor ip ON ((ip.insumo_id = i.id)))
     JOIN public.compra_x_insumo cp ON ((cp.insumo_x_proveedor_id = ip.id)))
     JOIN public.compra c ON ((c.id = cp.compra_id)))
     LEFT JOIN ingresado ing ON ((ing.fk_compra_x_insumo = cp.id)));


ALTER VIEW public.vw_compra_insumos OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_compras_reporte
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_compras_reporte AS
 SELECT c.id AS compra_id,
    ((EXTRACT(year FROM c.fecha_remision) * (100)::numeric) + EXTRACT(month FROM c.fecha_remision)) AS codmes,
    c.proveedor_id,
    p.proveedor,
    c.factura,
    (c.fyh_cre)::date AS fecha_registro,
    c.guia_remision,
    c.fecha_remision,
    c.total_usd,
    c.tipo_pago,
    c.fecha_giro,
    c.fecha_vencimiento,
    c.estado_pago,
    c.fecha_pago,
    c.estado_ingreso
   FROM (public.compra c
     JOIN public.proveedor p ON ((c.proveedor_id = p.id)));


ALTER VIEW public.vw_compras_reporte OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_compra_x_proveedor_x_mes
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_compra_x_proveedor_x_mes AS
 SELECT row_number() OVER () AS id,
    vcr.proveedor,
    vcr.codmes,
    vci.insumo,
    vci.tipo,
    sum(vci.cantidad) AS cantidad,
    sum(vci.valor_neto) AS costo_total
   FROM (public.vw_compras_reporte vcr
     JOIN public.vw_compra_insumos vci ON ((vcr.compra_id = vci.compra_id)))
  WHERE (vci.estado_ingreso <> 'cancelado'::public.estado_ingreso_compra_enum)
  GROUP BY vcr.codmes, vcr.proveedor, vci.insumo, vci.tipo
  ORDER BY vcr.proveedor, vcr.codmes, vci.insumo;


ALTER VIEW public.vw_compra_x_proveedor_x_mes OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_compras
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_compras AS
 SELECT c.id AS compra_id,
    c.factura,
    c.guia_remision,
    c.tipo_pago,
    p.proveedor,
    c.fecha_remision,
    c.fecha_giro,
    c.fecha_vencimiento,
    c.fecha_pago,
    c.total_usd,
    c.fyh_cre
   FROM (public.compra c
     JOIN public.proveedor p ON ((c.proveedor_id = p.id)));


ALTER VIEW public.vw_compras OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_produccion_tenido_procesada
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_produccion_tenido_procesada AS
 WITH base AS (
         SELECT produccion_tenido.fecha,
            produccion_tenido.partida_id AS fk_partida,
                CASE
                    WHEN (((produccion_tenido.tipo)::text ~~* '%Lavado%'::text) OR ((produccion_tenido.tipo)::text ~~* '%Mojar%'::text)) THEN 'Lavado'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Desmontado + Reteñido'::text) THEN 'Desmontado'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Reproceso Desmontado'::text) THEN 'Desmontado'::character varying
                    WHEN ((produccion_tenido.tipo)::text = ANY (ARRAY[('Reteñido'::character varying)::text, ('Rebaje'::character varying)::text, ('Reproceso Matizado'::character varying)::text, ('Reproceso Otros'::character varying)::text])) THEN 'Reproceso'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Teñido'::text) THEN 'Produccion'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Reproceso Antiguo'::text) THEN 'Rep. Antiguo'::character varying
                    ELSE produccion_tenido.tipo
                END AS tipo,
            produccion_tenido.tipo AS subtipo,
            produccion_tenido.maquina,
            produccion_tenido.rollos,
            produccion_tenido.kilos,
            produccion_tenido.estado,
            produccion_tenido.id,
            row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha) AS rn
           FROM public.produccion_tenido
          WHERE ((produccion_tenido.estado)::text = ANY (ARRAY[('En Proceso Teñido'::character varying)::text, ('Teñido'::character varying)::text]))
        ), marcado AS (
         SELECT b.fecha,
            b.fk_partida,
            b.tipo,
            b.subtipo,
            b.maquina,
            b.rollos,
            b.kilos,
            b.estado,
            b.id,
            b.rn,
            lag(b.estado) OVER (PARTITION BY b.fk_partida ORDER BY b.fecha) AS estado_prev,
            lag(b.rn) OVER (PARTITION BY b.fk_partida ORDER BY b.fecha) AS rn_prev
           FROM base b
        ), bloques AS (
         SELECT marcado.fk_partida,
            marcado.tipo,
            marcado.subtipo,
            marcado.maquina,
                CASE
                    WHEN (((marcado.estado)::text = 'Teñido'::text) AND ((marcado.estado_prev)::text = 'En Proceso Teñido'::text)) THEN marcado.rn_prev
                    ELSE marcado.rn
                END AS bloque_id,
            marcado.fecha,
            marcado.rollos,
            marcado.kilos,
            marcado.estado
           FROM marcado
        )
 SELECT bloques.fk_partida AS partida,
    bloques.tipo,
    bloques.subtipo,
    bloques.maquina,
    TRIM(BOTH FROM to_char((min(bloques.fecha))::timestamp with time zone, 'Month'::text)) AS mes,
    min(bloques.fecha) AS fecha_inicio,
    max(bloques.fecha) AS fecha_fin,
    sum(bloques.rollos) AS rollos,
    sum(bloques.kilos) AS kilos,
    string_agg(DISTINCT (bloques.estado)::text, ','::text) AS procesos
   FROM bloques
  GROUP BY bloques.fk_partida, bloques.tipo, bloques.subtipo, bloques.maquina, bloques.bloque_id
  ORDER BY bloques.fk_partida, (min(bloques.fecha));


ALTER VIEW public.vw_produccion_tenido_procesada OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_despacho_resumen
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_despacho_resumen AS
 SELECT v.partida_id,
    COALESCE(sum(v.rollos), (0)::bigint) AS rollos_enviados,
    COALESCE(sum(v.rib), (0)::bigint) AS rib_enviados,
    COALESCE(sum(v.rollos_total), (0)::bigint) AS rollos_total_enviados,
    min(v.fecha_despacho) AS primera_salida,
    max(v.fecha_despacho) AS ultima_salida,
    array_agg(DISTINCT v.nfactura ORDER BY v.nfactura) AS facturas_relacionadas,
    count(*) AS guias_emitidas,
    (COALESCE(sum(((v.rollos_total)::double precision * v.precio_unit)), (0)::double precision))::numeric(14,2) AS monto_facturado_total
   FROM public.despacho v
  WHERE (v.flg_elm = false)
  GROUP BY v.partida_id;


ALTER VIEW public.vw_despacho_resumen OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_enums
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_enums AS
 SELECT n.nspname AS schema,
    t.typname AS enum_type,
    e.enumlabel AS value,
    (e.enumsortorder)::integer AS sort_order
   FROM ((pg_enum e
     JOIN pg_type t ON ((t.oid = e.enumtypid)))
     JOIN pg_namespace n ON ((n.oid = t.typnamespace)))
  WHERE (n.nspname = 'public'::name)
  ORDER BY t.typname, e.enumsortorder;


ALTER VIEW public.vw_enums OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_error_inv_1
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_error_inv_1 AS
 WITH tmp AS (
         SELECT a.id AS pk_salida_inventario,
            a.motivo,
            a.partida_x_recetas_id AS fk_partida_x_recetas,
            a.estado,
            a.fyh_solicitud,
            a.fyh_revision,
            a.usr_solicita,
            a.usr_revisa,
            a.observacion,
            a.fecha_salida,
            b.id,
            b.fecha,
            b.partida_id AS fk_partida,
            b.receta_id AS fk_receta,
            b.tipo_receta_id AS fk_tipo_receta,
            b.maquina_id AS fk_maquina,
            b.fyh_cre,
            b.flg_elm,
            b.fyh_elm
           FROM (public.salida_inventario a
             LEFT JOIN public.partida_x_recetas b ON ((a.partida_x_recetas_id = b.id)))
          WHERE ((a.motivo = 'receta'::public.motivo_salida_inventario_enum) AND (a.estado = ANY (ARRAY['pendiente'::public.estado_salida_inventario_enum, 'aprobado'::public.estado_salida_inventario_enum])))
        )
 SELECT tmp.fk_partida AS partida_id,
    tmp.fk_tipo_receta AS tipo_receta_id
   FROM tmp
  GROUP BY tmp.fk_partida, tmp.fk_tipo_receta
 HAVING (count(*) > 1)
  ORDER BY tmp.fk_partida;


ALTER VIEW public.vw_error_inv_1 OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_estado_entrada_inventario
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_estado_entrada_inventario AS
 SELECT unnest(enum_range(NULL::public.estado_entrada_inventario_enum)) AS valor;


ALTER VIEW public.vw_estado_entrada_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_estado_ingreso_compra
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_estado_ingreso_compra AS
 SELECT unnest(enum_range(NULL::public.estado_ingreso_compra_enum)) AS valor;


ALTER VIEW public.vw_estado_ingreso_compra OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_estado_letra
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_estado_letra AS
 SELECT unnest(enum_range(NULL::public.estado_letra_enum)) AS valor;


ALTER VIEW public.vw_estado_letra OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_estado_pago
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_estado_pago AS
 SELECT unnest(enum_range(NULL::public.estado_pago_enum)) AS valor;


ALTER VIEW public.vw_estado_pago OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_estado_salida_inventario
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_estado_salida_inventario AS
 SELECT unnest(enum_range(NULL::public.estado_salida_inventario_enum)) AS valor;


ALTER VIEW public.vw_estado_salida_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_insumo_medida
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_insumo_medida AS
 SELECT unnest(enum_range(NULL::public.medida_enum)) AS valor;


ALTER VIEW public.vw_insumo_medida OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_insumo_tipo
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_insumo_tipo AS
 SELECT unnest(enum_range(NULL::public.tipo_insumo_enum)) AS valor;


ALTER VIEW public.vw_insumo_tipo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_inventario_duplicado
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_inventario_duplicado AS
 WITH ingresado AS (
         SELECT eid.compra_x_insumo_id AS fk_compra_x_insumo,
            sum(inventario.cantidad) AS cantidad_ingresada_total
           FROM (public.inventario
             LEFT JOIN public.entrada_inventario_detalle eid ON ((eid.id = inventario.entrada_inventario_detalle_id)))
          GROUP BY eid.compra_x_insumo_id
        ), doble AS (
         SELECT inv.inventario_id AS pk_inventario,
            row_number() OVER (PARTITION BY ci.id ORDER BY inv.fyh_ingreso) AS rw,
            sum(inv.cantidad_inicial) OVER (PARTITION BY ci.id ORDER BY inv.fyh_ingreso ROWS UNBOUNDED PRECEDING) AS running_total,
            eid.cantidad_solicitada,
            inv.fyh_ingreso AS ingreso_inv,
            vi.insumo,
            ei.id AS pk_entrada_inventario,
            ci.id AS pk_compra_x_insumo,
            ei.estado,
            ei.fyh_solicitud,
            ei.fyh_revision,
            ei.usr_solicita,
            ei.usr_revisa,
            ing.cantidad_ingresada_total,
            inv.cantidad_inicial AS cantidad_ingresada,
            inv.cantidad
           FROM (((((public.entrada_inventario ei
             LEFT JOIN public.entrada_inventario_detalle eid ON ((ei.id = eid.entrada_inventario_id)))
             LEFT JOIN ingresado ing ON ((eid.compra_x_insumo_id = ing.fk_compra_x_insumo)))
             LEFT JOIN public.compra_x_insumo ci ON ((ing.fk_compra_x_insumo = ci.id)))
             LEFT JOIN public.vw_inventario inv ON ((inv.entrada_inventario_detalle_id = eid.id)))
             LEFT JOIN public.vw_insumos_proveedor vi ON ((ci.insumo_x_proveedor_id = vi.insumo_x_proveedor_id)))
          WHERE ((ei.motivo = 'compra'::public.motivo_entrada_inventario_enum) AND (ing.cantidad_ingresada_total > ci.cantidad))
        )
 SELECT doble.pk_inventario AS inventario_id,
    doble.rw,
    doble.running_total,
    doble.cantidad_solicitada,
    doble.ingreso_inv,
    doble.insumo,
    doble.pk_entrada_inventario AS entrada_inventario_id,
    doble.pk_compra_x_insumo AS compra_x_insumo_id,
    doble.estado,
    doble.fyh_solicitud,
    doble.fyh_revision,
    doble.usr_solicita,
    doble.usr_revisa,
    doble.cantidad_ingresada_total,
    doble.cantidad_ingresada,
    doble.cantidad
   FROM doble
  WHERE ((doble.running_total > doble.cantidad_solicitada) AND (doble.rw <> 1))
  ORDER BY doble.pk_compra_x_insumo;


ALTER VIEW public.vw_inventario_duplicado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_inventario_movimientos
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_inventario_movimientos AS
 SELECT 'egreso'::text AS movimiento,
    ip.insumo_id,
    ip.insumo,
    ip.tipo,
    (si.motivo)::text AS motivo,
    pr.partida_id,
    pr.cliente,
    pr.articulo,
    pr.color,
    sidx.cantidad,
    sidx.fecha
   FROM (((((public.salida_inventario_detalle_x_stock sidx
     LEFT JOIN public.inventario inv ON ((inv.id = sidx.inventario_id)))
     LEFT JOIN public.vw_insumos_proveedor ip ON (((inv.insumo_x_proveedor_id = ip.insumo_x_proveedor_id) OR ((inv.insumo_x_proveedor_id IS NULL) AND (inv.insumo_id = ip.insumo_id)))))
     LEFT JOIN public.salida_inventario_detalle sid ON ((sid.id = sidx.salida_inventario_detalle_id)))
     LEFT JOIN public.salida_inventario si ON ((sid.salida_inventario_id = si.id)))
     LEFT JOIN public.vw_partida_x_receta pr ON ((pr.id = si.partida_x_recetas_id)))
  GROUP BY ip.insumo_id, ip.insumo, ip.tipo, si.motivo, pr.partida_id, pr.cliente, pr.articulo, pr.color, sidx.cantidad, sidx.fecha
UNION ALL
 SELECT 'ingreso'::text AS movimiento,
    ip.insumo_id,
    ip.insumo,
    ip.tipo,
    (ei.motivo)::text AS motivo,
    NULL::smallint AS partida_id,
    NULL::text AS cliente,
    NULL::text AS articulo,
    NULL::character varying AS color,
    inv.cantidad,
    inv.fyh_ingreso AS fecha
   FROM (((public.inventario inv
     LEFT JOIN public.entrada_inventario_detalle eid ON ((inv.entrada_inventario_detalle_id = eid.id)))
     LEFT JOIN public.entrada_inventario ei ON ((ei.id = eid.entrada_inventario_id)))
     LEFT JOIN public.vw_insumos_proveedor ip ON (((inv.insumo_x_proveedor_id = ip.insumo_x_proveedor_id) OR ((inv.insumo_x_proveedor_id IS NULL) AND (inv.insumo_id = ip.insumo_id)))))
  GROUP BY ip.insumo_id, ip.insumo, ip.tipo, ei.motivo, inv.cantidad, inv.fyh_ingreso;


ALTER VIEW public.vw_inventario_movimientos OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_inventario_valorizado_actual
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_inventario_valorizado_actual AS
SELECT
    NULL::integer AS pk_inventario,
    NULL::integer AS fk_insumo,
    NULL::text COLLATE public.case_insensitive AS insumo,
    NULL::public.tipo_insumo_enum AS tipo,
    NULL::smallint AS fk_proveedor,
    NULL::text COLLATE pg_catalog."C" AS proveedor,
    NULL::numeric(7,4) AS costo_unitario,
    NULL::numeric AS stock_actual,
    NULL::numeric AS valor_total_usd,
    NULL::text AS fuente_precio;


ALTER VIEW public.vw_inventario_valorizado_actual OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_inventario_x_ingreso
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_inventario_x_ingreso AS
 SELECT i.inventario_id,
    ins.tipo,
    ins.id AS insumo_id,
    ins.insumo,
    p.id AS proveedor_id,
    p.proveedor,
    ei.motivo AS tipo_de_ingreso,
    i.fyh_ingreso,
    i.costo_bruto_kg AS precio_x_kg_usd,
    eid.cantidad_recibida,
    i.cantidad,
    (i.cantidad * i.costo_bruto_kg) AS valor,
    ins.flg_elm
   FROM (((((public.vw_inventario i
     LEFT JOIN public.insumo_x_proveedor ip ON ((ip.id = i.insumo_x_proveedor_id)))
     LEFT JOIN public.insumo ins ON ((ins.id = ip.insumo_id)))
     LEFT JOIN public.proveedor p ON ((p.id = ip.proveedor_id)))
     LEFT JOIN public.entrada_inventario_detalle eid ON ((eid.id = i.entrada_inventario_detalle_id)))
     LEFT JOIN public.entrada_inventario ei ON ((ei.id = eid.entrada_inventario_id)));


ALTER VIEW public.vw_inventario_x_ingreso OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_inventario_x_insumo
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_inventario_x_insumo AS
 SELECT COALESCE((ip.insumo_id)::integer, i.insumo_id) AS insumo_id,
    ins.insumo,
    ins.tipo,
    sum(i.cantidad) AS cantidad,
    sum(i.costo_bruto_total) AS costo_bruto_total,
    (sum(i.costo_bruto_total) / NULLIF(sum(i.cantidad), (0)::numeric)) AS costo_bruto_prom_kg,
    ins.precio_prom_kg_usd AS ult_precio_compra,
    ins.flg_elm
   FROM ((public.vw_inventario i
     LEFT JOIN public.insumo_x_proveedor ip ON ((i.insumo_x_proveedor_id = ip.id)))
     LEFT JOIN public.insumo ins ON ((ins.id = COALESCE((ip.insumo_id)::integer, i.insumo_id))))
  GROUP BY COALESCE((ip.insumo_id)::integer, i.insumo_id), ins.insumo, ins.tipo, ins.precio_prom_kg_usd, ins.flg_elm;


ALTER VIEW public.vw_inventario_x_insumo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_lavado_maquina
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_lavado_maquina AS
 SELECT a.id,
    a.fecha,
    a.receta_lavado_mq_id,
    b.nombre AS maquina,
    f.tipo_lavado_mq,
    f.valor_origen,
    f.valor_destino,
    f.costo,
    ((f.costo * 1.18) + (80)::numeric) AS costo_total
   FROM ((public.lavado_maquina a
     JOIN public.maquina b ON ((a.maquina_id = b.id)))
     JOIN public.vw_receta_lavado_maquina f ON ((a.receta_lavado_mq_id = f.receta_lavado_mq_id)));


ALTER VIEW public.vw_lavado_maquina OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_letras
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_letras AS
 SELECT lc.compra_id,
    p.proveedor,
    c.factura,
    lc.id,
    lc.numero_letra,
    lc.monto_usd,
    lc.fecha_emision,
    lc.fecha_vencimiento,
    lc.estado,
    lc.fecha_pago,
    lc.fyh_cre AS fecha_registro
   FROM ((public.letra_compra lc
     LEFT JOIN public.compra c ON ((lc.compra_id = c.id)))
     LEFT JOIN public.proveedor p ON ((p.id = c.proveedor_id)))
  ORDER BY lc.compra_id, c.factura, lc.id;


ALTER VIEW public.vw_letras OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_maquina_acabado
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_maquina_acabado AS
 SELECT maquina.id AS maquina_id,
    maquina.nombre,
    maquina.ubicacion,
    maquina.seccion,
    maquina."RB"
   FROM public.maquina
  WHERE (maquina.id = ANY (ARRAY[17, 18, 12]));


ALTER VIEW public.vw_maquina_acabado OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_maquina_tenido
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_maquina_tenido AS
 SELECT maquina.id AS maquina_id,
    maquina.nombre
   FROM public.maquina
  WHERE ((maquina.ubicacion)::text = 'Maq Teñido'::text);


ALTER VIEW public.vw_maquina_tenido OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_motivo_entrada_inventario
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_motivo_entrada_inventario AS
 SELECT unnest(enum_range(NULL::public.motivo_entrada_inventario_enum)) AS valor;


ALTER VIEW public.vw_motivo_entrada_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_motivo_salida_inventario
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_motivo_salida_inventario AS
 SELECT unnest(enum_range(NULL::public.motivo_salida_inventario_enum)) AS valor;


ALTER VIEW public.vw_motivo_salida_inventario OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_partidas_x_pesar
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_partidas_x_pesar AS
 WITH extras AS (
         SELECT pxe.partida_id,
            string_agg((ex_1.cod_extra)::text, '+'::text) AS extras,
            COALESCE(sum(pxe.peso), (0)::numeric) AS peso_extra,
            COALESCE((sum(pxe.cantidad))::numeric, (0)::numeric) AS cantidad
           FROM (public.partida_x_extra pxe
             JOIN public.extra ex_1 ON ((pxe.extra_id = ex_1.id)))
          GROUP BY pxe.partida_id
        )
 SELECT part.partida,
    part.guia,
    part.cliente,
    concat(part.color, ' ', part.tenido) AS color,
    part.articulo,
    part.rollos,
        CASE
            WHEN (ex.cantidad > (0)::numeric) THEN ex.cantidad
            WHEN (part.rib > 0) THEN (part.rib)::numeric
            ELSE (part.rib)::numeric
        END AS rib_extra,
    part.ancho,
    part.malla,
    part.fibra
   FROM (public.vw_partidas_resumen part
     LEFT JOIN extras ex ON ((part.partida = ex.partida_id)))
  WHERE ((part.peso IS NULL) AND (part.estado = 'Programado'::text));


ALTER VIEW public.vw_partidas_x_pesar OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_recetas_precio_costo
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_recetas_precio_costo AS
 SELECT max(b.pk_receta) AS receta_id,
    b.color,
        CASE
            WHEN (b.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 cabos)'::text
            WHEN (b.tipo_articulo ~~ '%J Poly%'::text) THEN 'J Poly'::text
            WHEN (((b.tipo_articulo ~~ '%Gam%'::text) OR (b.tipo_articulo ~~ '%J %'::text)) AND (b.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text]))) THEN 'Jersey/Gamuza'::text
            WHEN (b.tipo_articulo ~~ '%J 30%'::text) THEN 'J 30/1'::text
            WHEN (b.tipo_articulo ~~ '%J 20%'::text) THEN 'J 20/1'::text
            WHEN (b.tipo_articulo ~~ '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
            WHEN ((b.tipo_articulo ~~ '%F Lycra%'::text) OR (b.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
            ELSE b.tipo_articulo
        END AS tipo_articulo,
    b.cliente,
    b.tenido,
    b.fibra,
        CASE
            WHEN (c.fk_receta IS NOT NULL) THEN 'antipilling'::text
            ELSE ''::text
        END AS antipil,
    COALESCE(a.precio_tenido, (0)::numeric) AS precio_tenido,
    (((max(b.costo) * 1.18) + 0.8))::numeric(5,2) AS costo
   FROM ((public.vw_catalogo_precios a
     RIGHT JOIN ( SELECT vw_receta.receta_id AS pk_receta,
            vw_receta.color,
            vw_receta.tipo_articulo,
            vw_receta.cliente,
            vw_receta.tenido,
            vw_receta.fibra,
            vw_receta.costo_12r,
            vw_receta.costo,
            vw_receta.flg_antipilling,
            vw_receta.tipo_receta
           FROM public.vw_receta
          WHERE (vw_receta.tipo_receta = 'Teñido'::text)) b ON ((((a.color)::text = (b.color)::text) AND (
        CASE
            WHEN (b.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 cabos)'::text
            WHEN (b.tipo_articulo ~~ '%J Poly%'::text) THEN 'J Poly'::text
            WHEN (((b.tipo_articulo ~~ '%Gam%'::text) OR (b.tipo_articulo ~~ '%J %'::text)) AND (b.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text]))) THEN 'Jersey/Gamuza'::text
            WHEN (b.tipo_articulo ~~ '%J 30%'::text) THEN 'J 30/1'::text
            WHEN (b.tipo_articulo ~~ '%J 20%'::text) THEN 'J 20/1'::text
            WHEN (b.tipo_articulo ~~ '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
            WHEN ((b.tipo_articulo ~~ '%F Lycra%'::text) OR (b.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
            ELSE b.tipo_articulo
        END =
        CASE
            WHEN (a.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 cabos)'::text
            WHEN (a.tipo_articulo ~~ '%J Poly%'::text) THEN 'J Poly'::text
            WHEN (((a.tipo_articulo ~~ '%Gam%'::text) OR (a.tipo_articulo ~~ '%J %'::text)) AND (a.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text]))) THEN 'Jersey/Gamuza'::text
            WHEN (a.tipo_articulo ~~ '%J 30%'::text) THEN 'J 30/1'::text
            WHEN (a.tipo_articulo ~~ '%J 20%'::text) THEN 'J 20/1'::text
            WHEN (a.tipo_articulo ~~ '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
            WHEN ((b.tipo_articulo ~~ '%F Lycra%'::text) OR (b.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
            ELSE a.tipo_articulo
        END) AND (a.tenido = b.tenido) AND (a.fibra = b.fibra) AND (a.cliente = b.cliente))))
     LEFT JOIN ( SELECT receta_x_insumo.receta_id AS fk_receta,
            receta_x_insumo.insumo_id AS fk_insumo,
            receta_x_insumo.cantidad,
            receta_x_insumo.orden,
            receta_x_insumo.id
           FROM public.receta_x_insumo
          WHERE (receta_x_insumo.insumo_id = 19)) c ON ((b.pk_receta = c.fk_receta)))
  GROUP BY b.color,
        CASE
            WHEN (b.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 cabos)'::text
            WHEN (b.tipo_articulo ~~ '%J Poly%'::text) THEN 'J Poly'::text
            WHEN (((b.tipo_articulo ~~ '%Gam%'::text) OR (b.tipo_articulo ~~ '%J %'::text)) AND (b.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text]))) THEN 'Jersey/Gamuza'::text
            WHEN (b.tipo_articulo ~~ '%J 30%'::text) THEN 'J 30/1'::text
            WHEN (b.tipo_articulo ~~ '%J 20%'::text) THEN 'J 20/1'::text
            WHEN (b.tipo_articulo ~~ '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
            WHEN ((b.tipo_articulo ~~ '%F Lycra%'::text) OR (b.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
            ELSE b.tipo_articulo
        END, b.cliente, b.tenido, b.fibra,
        CASE
            WHEN (c.fk_receta IS NOT NULL) THEN 'antipilling'::text
            ELSE ''::text
        END, a.precio_tenido
  ORDER BY b.cliente,
        CASE
            WHEN (b.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 cabos)'::text
            WHEN (b.tipo_articulo ~~ '%J Poly%'::text) THEN 'J Poly'::text
            WHEN (((b.tipo_articulo ~~ '%Gam%'::text) OR (b.tipo_articulo ~~ '%J %'::text)) AND (b.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text]))) THEN 'Jersey/Gamuza'::text
            WHEN (b.tipo_articulo ~~ '%J 30%'::text) THEN 'J 30/1'::text
            WHEN (b.tipo_articulo ~~ '%J 20%'::text) THEN 'J 20/1'::text
            WHEN (b.tipo_articulo ~~ '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
            WHEN ((b.tipo_articulo ~~ '%F Lycra%'::text) OR (b.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
            ELSE b.tipo_articulo
        END, b.tenido, b.color;


ALTER VIEW public.vw_recetas_precio_costo OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_reporte_detecciones
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_reporte_detecciones AS
 SELECT detecciones.partida_id,
    detecciones.nro_rollo,
    count(*) FILTER (WHERE (detecciones.clase = 'hole'::text)) AS huecos,
    count(*) FILTER (WHERE (detecciones.clase = 'line'::text)) AS lineas,
    count(*) FILTER (WHERE (detecciones.clase = 'stain'::text)) AS manchas,
    count(*) FILTER (WHERE (detecciones.clase <> ALL (ARRAY['inicio'::text, 'fin'::text]))) AS detecciones,
    min(detecciones.hora) FILTER (WHERE (detecciones.clase = 'inicio'::text)) AS hora_inicio,
    max(detecciones.hora) FILTER (WHERE (detecciones.clase = 'fin'::text)) AS hora_fin,
    (max(detecciones.hora) FILTER (WHERE (detecciones.clase = 'fin'::text)) - min(detecciones.hora) FILTER (WHERE (detecciones.clase = 'inicio'::text))) AS duracion
   FROM public.detecciones
  GROUP BY detecciones.partida_id, detecciones.nro_rollo;


ALTER VIEW public.vw_reporte_detecciones OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_tipo_insumo_x_mes
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_tipo_insumo_x_mes AS
 SELECT row_number() OVER () AS id,
    vci.tipo,
    vcr.codmes,
    sum(vci.cantidad) AS cantidad,
    sum(vci.valor_neto) AS costo_total
   FROM (public.vw_compras_reporte vcr
     JOIN public.vw_compra_insumos vci ON ((vcr.compra_id = vci.compra_id)))
  WHERE (vci.estado_ingreso <> 'cancelado'::public.estado_ingreso_compra_enum)
  GROUP BY vci.tipo, vcr.codmes
  ORDER BY vcr.codmes;


ALTER VIEW public.vw_tipo_insumo_x_mes OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_tipo_pago
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_tipo_pago AS
 SELECT unnest(enum_range(NULL::public.tipo_pago_enum)) AS valor;


ALTER VIEW public.vw_tipo_pago OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_tonos
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_tonos AS
 SELECT cliente.id AS cliente_id,
    cliente.cliente AS tono
   FROM public.cliente;


ALTER VIEW public.vw_tonos OWNER TO postgres;

-- ---------------------------------------------------------------------
-- VIEW: public.vw_ultimo_precio_insumo_proveedor
-- ---------------------------------------------------------------------
CREATE VIEW public.vw_ultimo_precio_insumo_proveedor AS
 WITH ult_compra AS (
         SELECT row_number() OVER (PARTITION BY ci.insumo_x_proveedor_id ORDER BY c.fyh_cre DESC) AS rw,
            ci.insumo_id AS fk_insumo,
            ci.precio_x_kg_usd,
            ci.cantidad,
            c.fyh_cre,
            c.guia_remision,
            ci.insumo_x_proveedor_id AS fk_insumo_x_proveedor
           FROM (public.compra_x_insumo ci
             LEFT JOIN public.compra c ON ((c.id = ci.compra_id)))
          ORDER BY ci.insumo_id, c.proveedor_id
        )
 SELECT ip.id AS insumo_x_proveedor_id,
    ip.insumo_id,
    i.insumo,
    ip.proveedor_id,
    p.proveedor,
    uc.precio_x_kg_usd,
    uc.fyh_cre,
    uc.cantidad
   FROM (((public.insumo i
     LEFT JOIN public.insumo_x_proveedor ip ON ((ip.insumo_id = i.id)))
     LEFT JOIN public.proveedor p ON ((ip.proveedor_id = p.id)))
     LEFT JOIN ult_compra uc ON ((uc.fk_insumo_x_proveedor = ip.id)))
  WHERE (uc.rw = 1)
  ORDER BY i.insumo, p.proveedor;


ALTER VIEW public.vw_ultimo_precio_insumo_proveedor OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.ajustar_secuestrante_en_receta(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.ajustar_secuestrante_en_receta(_fk_receta integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  cuenta int;
  r record;
begin
  -- Contar cuántos SECUESTRANTE MFP hay
  select count(*) into cuenta
  from receta_x_insumo
  where receta_id = _fk_receta and insumo_id = 133;

  -- CASO 1: más de uno → eliminar los de orden <= 6 (mantener uno)
  if cuenta > 1 then
    delete from receta_x_insumo
    where ctid in (
      select ctid
      from receta_x_insumo
      where receta_id = _fk_receta and insumo_id = 133 and orden <= 6
      order by orden
      limit cuenta - 1
    );

  -- CASO 2: solo uno → mover a orden 9 (haciendo espacio sin colisión)
  elsif cuenta = 1 then
    -- Desplazar en orden descendente para evitar conflicto
    for r in
      select id, orden
      from receta_x_insumo
      where receta_id = _fk_receta and orden >= 9
      order by orden desc
    loop
      update receta_x_insumo
      set orden = r.orden + 1
      where id = r.id;
    end loop;

    -- Mover SECUESTRANTE MFP a orden 9
    update receta_x_insumo
    set orden = 9
    where receta_id = _fk_receta and insumo_id = 133;
  end if;

  -- Finalmente, reordenar todo visualmente
  perform reordenar_orden_receta(_fk_receta);
end;
$$;


ALTER FUNCTION public.ajustar_secuestrante_en_receta(_fk_receta integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.approve_entrada_inventario(integer, jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.approve_entrada_inventario(entrada_id integer, detalles_json jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    violacion RECORD;
    diferencias INT;
    expected NUMERIC(8,4);
    received NUMERIC(8,4);
BEGIN
    -- Verificar estado
    IF (SELECT estado FROM entrada_inventario WHERE id = entrada_id) <> 'pendiente' THEN
        RETURN 'Error: El ingreso ya fue aprobado o rechazado.';
    END IF;

    -- Check for violations (excess received) Revisar que la cantidad recibida no exceda lo restante por recibir
    WITH detalles_ingreso AS (
        SELECT 
            (item->>'detalle_id')::INTEGER AS detalle_id,
            (item->>'cantidad_recibida')::NUMERIC(8,4) AS recibida
        FROM jsonb_array_elements(detalles_json) AS item
    ),
    joined AS (
        SELECT 
            d.detalle_id,
            d.recibida,
            eid.insumo_id,
            eid.compra_x_insumo_id,
            cx.cantidad - COALESCE((
                SELECT SUM(eid2.cantidad_recibida)
                FROM entrada_inventario_detalle eid2
                WHERE eid2.compra_x_insumo_id = eid.compra_x_insumo_id
                AND eid2.cantidad_recibida IS NOT NULL AND estado IN ('aprobado','ajustado')
            ), 0) AS restante
        FROM detalles_ingreso d
        JOIN entrada_inventario_detalle eid ON eid.id = d.detalle_id
        LEFT JOIN compra_x_insumo cx ON cx.id = eid.compra_x_insumo_id
        WHERE eid.entrada_inventario_id = entrada_id
    )
    SELECT * INTO violacion
    FROM joined
    WHERE compra_x_insumo_id IS NOT NULL AND recibida > restante
    LIMIT 1;

    IF FOUND THEN
        RETURN format(
            'Error: Ingreso rechazado. Insumo %s excede restante (%s)',
            violacion.insumo_id, violacion.restante
        );
    END IF;

    -- Update cantidades recibidas
    UPDATE entrada_inventario_detalle eid
SET 
    cantidad_recibida = (item->>'cantidad_recibida')::NUMERIC(8,4),
    estado = CASE
        WHEN (item->>'cantidad_recibida')::NUMERIC(8,4) = 0 THEN 'rechazado'
        WHEN eid.cantidad_solicitada IS NOT NULL 
             AND (item->>'cantidad_recibida')::NUMERIC(8,4) < eid.cantidad_solicitada THEN 'ajustado'::estado_entrada_inventario_enum
        WHEN eid.cantidad_solicitada IS NOT NULL 
             AND (item->>'cantidad_recibida')::NUMERIC(8,4) = eid.cantidad_solicitada THEN 'aprobado'::estado_entrada_inventario_enum
        ELSE 'pendiente'::estado_entrada_inventario_enum
    END
FROM jsonb_array_elements(detalles_json) AS item
WHERE eid.id = (item->>'detalle_id')::INTEGER
  AND eid.entrada_inventario_id = entrada_id;


    -- 1. Check if ALL lines are 'rechazado'
IF NOT EXISTS (
    SELECT 1
    FROM entrada_inventario_detalle
    WHERE entrada_inventario_id = entrada_id
      AND estado != 'rechazado'
) THEN
    UPDATE entrada_inventario
    SET estado = 'rechazado',
        fyh_revision = CURRENT_TIMESTAMP,
        usr_revisa = get_user_id()
    WHERE id = entrada_id;

    RETURN format('Ingreso #%s rechazado: todas las líneas rechazadas.', entrada_id);
END IF;

-- 2. Check if ANY line is 'ajustado'
IF EXISTS (
    SELECT 1
    FROM entrada_inventario_detalle
    WHERE entrada_inventario_id = entrada_id
      AND estado = 'ajustado'
) THEN
    UPDATE entrada_inventario
    SET estado = 'ajustado',
        fyh_revision = CURRENT_TIMESTAMP,
        usr_revisa = get_user_id()
    WHERE id = entrada_id;

    RETURN format('Ingreso #%s ajustado exitosamente.', entrada_id);
END IF;

-- 3. Otherwise, all must be 'aprobado'
UPDATE entrada_inventario
SET estado = 'aprobado',
    fyh_revision = CURRENT_TIMESTAMP,
    usr_revisa = get_user_id()
WHERE id = entrada_id;

RETURN format('Ingreso #%s aprobado exitosamente.', entrada_id);

END;
$$;


ALTER FUNCTION public.approve_entrada_inventario(entrada_id integer, detalles_json jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.aprobar_salida_inventario_total(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.aprobar_salida_inventario_total(salida_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    msj_error text;
    v_fyh_salida_real timestamptz;
BEGIN
    -- Check if exit exists and is in pending status
    IF NOT EXISTS (
        SELECT 1 FROM salida_inventario 
        WHERE id = salida_id AND estado = 'pendiente'
    ) THEN
        RETURN jsonb_build_object(
            'error', true,
            'mensaje', 'Error: La salida no existe o ya fue revisada.'
        );
    END IF;
    
    -- Validate sufficient stock for all items
    SELECT 
        string_agg(
            format('Insumo "%s" requiere %s pero solo hay %s disponible',
                   ins.insumo,
                   sid.cantidad_solicitada,
                   COALESCE(ixs.cantidad, 0)
            ),
            E';\n'
        )
    INTO msj_error
    FROM salida_inventario_detalle sid
    LEFT JOIN insumo ins ON ins.id = sid.insumo_id
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = sid.insumo_id
    WHERE sid.salida_inventario_id = salida_id
      AND sid.cantidad_solicitada > COALESCE(ixs.cantidad, 0);
      
    IF msj_error IS NOT NULL THEN
        RETURN jsonb_build_object(
            'error', true,
            'mensaje', 'Error: Stock insuficiente - ' || msj_error
        );
    END IF;

    -- Approve all details
    UPDATE salida_inventario_detalle 
    SET estado = 'aprobado'
    WHERE salida_inventario_id = salida_id;

    -- Update main exit record
    UPDATE salida_inventario 
    SET 
        estado = 'aprobado',
        fyh_revision = current_timestamp,
        usr_revisa = get_user_id()
    WHERE id = salida_id
    RETURNING fyh_salida_real INTO v_fyh_salida_real;

    -- Create FIFO stock allocation and deduct inventory
    WITH detalles AS (
        SELECT
            sid.id AS detalle_id,
            sid.insumo_id,
            sid.cantidad_solicitada
        FROM salida_inventario_detalle sid
        WHERE sid.salida_inventario_id = salida_id
    ),
    inventario_ordenado AS (
        SELECT
            d.detalle_id,
            i.inventario_id,
            i.cantidad AS lot_quantity,
            i.fyh_ingreso,
            d.cantidad_solicitada
        FROM detalles d
        LEFT JOIN insumo_x_proveedor ixp ON ixp.insumo_id = d.insumo_id
        LEFT JOIN vw_inventario i ON i.insumo_x_proveedor_id = ixp.id OR (i.insumo_x_proveedor_id IS NULL AND i.insumo_id=d.insumo_id)
        WHERE i.cantidad > 0
        GROUP BY  d.detalle_id,
            i.inventario_id,
            i.cantidad,
            i.fyh_ingreso,
            d.cantidad_solicitada
    ),
    inventario_fifo AS (
        SELECT
            detalle_id,
            inventario_id,
            lot_quantity,
            fyh_ingreso,
            cantidad_solicitada,
            SUM(lot_quantity) OVER (
                PARTITION BY detalle_id
                ORDER BY fyh_ingreso
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_total
        FROM inventario_ordenado
    ),
    inventario_con_prev AS (
        SELECT
            detalle_id,
            inventario_id,
            lot_quantity,
            cantidad_solicitada,
            running_total,
            LAG(running_total) OVER (
                PARTITION BY detalle_id
                ORDER BY fyh_ingreso
            ) AS prev_running_total
        FROM inventario_fifo
    ),
    inventario_consumo AS (
        SELECT
            detalle_id,
            inventario_id,
            LEAST(
                lot_quantity,
                GREATEST(
                    cantidad_solicitada - COALESCE(prev_running_total, 0),
                    0
                )
            ) AS cantidad_a_usar
        FROM inventario_con_prev
        WHERE LEAST(
            lot_quantity,
            GREATEST(
                cantidad_solicitada - COALESCE(prev_running_total, 0),
                0
            )
        ) > 0
    )
    -- Insert stock allocation records
    INSERT INTO salida_inventario_detalle_x_stock(salida_inventario_detalle_id, inventario_id, cantidad,fecha)
    SELECT
        ic.detalle_id,
        ic.inventario_id,
        ic.cantidad_a_usar,
        v_fyh_salida_real
    FROM inventario_consumo ic
    GROUP BY ic.detalle_id,
        ic.inventario_id,
        ic.cantidad_a_usar,
        v_fyh_salida_real
    ;

-----NO SE ACTUALIZA LA TABLE, se mantiene la cantidad y se maneja a través del view
    -- -- Deduct from inventory (FIXED: removed alias conflict)
    -- UPDATE inventario
    -- SET cantidad = inventario.cantidad - sixs.cantidad
    -- FROM salida_inventario_detalle_x_stock sixs
    -- JOIN salida_inventario_detalle sid ON sid.id = sixs.salida_inventario_detalle_id
    -- WHERE inventario.id = sixs.inventario_id
    --   AND sid.salida_inventario_id = salida_id;

    RETURN jsonb_build_object(
        'error', false,
        'mensaje', format('Salida #%s aprobada exitosamente', salida_id),
        'detalles', get_salida_inventario_detalles(salida_id)
    );
END;$$;


ALTER FUNCTION public.aprobar_salida_inventario_total(salida_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.cerrar_parada_tintoreria(integer, timestamp without time zone, text)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.cerrar_parada_tintoreria(p_id integer, p_fecha_fin timestamp without time zone, p_usuario text DEFAULT NULL::text) RETURNS TABLE(id_out integer, msj_out text)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE parada_tintoreria
  SET
    fecha_fin = p_fecha_fin,
    duracion = (p_fecha_fin - fecha_inicio),
    usuario = COALESCE(p_usuario, usuario)
  WHERE id = p_id
  RETURNING id, 'Parada cerrada correctamente' INTO id_out, msj_out;
END;
$$;


ALTER FUNCTION public.cerrar_parada_tintoreria(p_id integer, p_fecha_fin timestamp without time zone, p_usuario text) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.crear_cuadre_inventario()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.crear_cuadre_inventario() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cuadre_id INTEGER;
BEGIN
    -- Insert header
    INSERT INTO cuadre_inventario DEFAULT VALUES
    RETURNING id INTO v_cuadre_id;

    -- Insert details
    INSERT INTO cuadre_inventario_detalle(
        cuadre_inventario_id,
        insumo_id,
        cantidad_sistema,
        costo_bruto_total_sistema,
        costo_bruto_prom_kg_sistema,
        ult_precio_compra
    )
    SELECT
        v_cuadre_id,
        insumo_id,
        cantidad,
        costo_bruto_total,
        costo_bruto_prom_kg,
        ult_precio_compra
    FROM vw_inventario_x_insumo;

    -- Return only the ID
    RETURN v_cuadre_id;
END;
$$;


ALTER FUNCTION public.crear_cuadre_inventario() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.delete_partida_x_receta(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.delete_partida_x_receta(p_partida_x_receta_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_exists boolean;
BEGIN
    -- Verificar si la partida existe
    SELECT EXISTS (
        SELECT 1 FROM partida_x_recetas WHERE id = p_partida_x_receta_id
    )
    INTO v_exists;

    IF NOT v_exists THEN
        RETURN jsonb_build_object(
            'error', true,
            'mensaje', format('Error: La partida con ID %s no existe.', p_partida_x_receta_id)
        );
    END IF;

    -- Borrar en orden de dependencias
    DELETE FROM salida_inventario_detalle_x_stock
    WHERE salida_inventario_detalle_id IN (
        SELECT id
        FROM salida_inventario_detalle
        WHERE salida_inventario_id IN (
            SELECT id
            FROM salida_inventario
            WHERE partida_x_recetas_id = p_partida_x_receta_id
        )
    );

    DELETE FROM salida_inventario_detalle
    WHERE salida_inventario_id IN (
        SELECT id
        FROM salida_inventario
        WHERE partida_x_recetas_id = p_partida_x_receta_id
    );

    DELETE FROM salida_inventario
    WHERE partida_x_recetas_id = p_partida_x_receta_id;

    -- DELETE FROM partida_x_recetas
    -- WHERE id = p_partida_x_receta_id;
    UPDATE partida_x_recetas
    SET flg_elm=true
    WHERE id = p_partida_x_receta_id;

    RETURN jsonb_build_object(
        'error', false,
        'mensaje', format('La ejecucion con ID %s para la partida y sus registros relacionados fueron eliminados exitosamente.', p_partida_x_receta_id)
    );
END;$$;


ALTER FUNCTION public.delete_partida_x_receta(p_partida_x_receta_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.finalizar_cuadre_inventario(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.finalizar_cuadre_inventario(p_cuadre_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    faltantes jsonb;
    v_entrada_inventario_id integer;
    v_salida_inventario_id int;
    v_cuadre_fecha_cierre timestamptz;
    v_cuadre_fecha timestamptz;
    v_cuadre_estado cuadre_estado_enum;
BEGIN
    SELECT jsonb_agg(jsonb_build_object(
        'id', id,
        'insumo_id', insumo_id
    ))
    INTO faltantes
    FROM cuadre_inventario_detalle
    WHERE cuadre_inventario_id = p_cuadre_id
      AND cantidad_contada IS NULL;

    IF faltantes IS NOT NULL THEN
        RAISE EXCEPTION USING
    MESSAGE = 'Hay insumos sin cantidad contada',
    DETAIL  = faltantes::text,
    HINT    = 'Completa los conteos antes de ejecutar el cuadre';

    END IF;

    SELECT fecha_cierre, estado,fecha_cuadre INTO v_cuadre_fecha_cierre,v_cuadre_estado,v_cuadre_fecha FROM cuadre_inventario
    WHERE id=p_cuadre_id;
    IF v_cuadre_fecha_cierre IS NOT NULL OR v_cuadre_estado NOT IN ('borrador','preparado') THEN 
    RAISE EXCEPTION USING
    MESSAGE = 'El cuadre no puede ejecutarse',
    DETAIL = jsonb_build_object(
                'estado', v_cuadre_estado,
                'fecha_cierre', v_cuadre_fecha_cierre
             )::text,
    HINT = 'Solo los cuadres en estado borrador o preparado pueden ejecutarse';
    END IF;
    
    -- Mark cuadre as closed
    UPDATE cuadre_inventario
    SET fecha_cierre = now(),
        usr_mod = get_user_id(),
        fyh_mod = now()
    WHERE id = p_cuadre_id;

    IF EXISTS (SELECT 1 FROM cuadre_inventario_detalle WHERE cantidad_sistema>cantidad_contada and cuadre_inventario_id = p_cuadre_id) THEN
    INSERT INTO salida_inventario(motivo,fyh_salida_real)
    SELECT 'reconteo',v_cuadre_fecha
    RETURNING id INTO v_salida_inventario_id;
    INSERT INTO salida_inventario_detalle(salida_inventario_id,cantidad_solicitada,insumo_id)
    SELECT v_salida_inventario_id,cantidad_sistema-cantidad_contada,insumo_id FROM cuadre_inventario_detalle
    WHERE cuadre_inventario_id=p_cuadre_id AND cantidad_contada<cantidad_sistema;
    PERFORM  aprobar_salida_inventario_total(v_salida_inventario_id);
    END IF;

------NTOAS PARA SEBASTIANDE MAÑANA
-----DESCARGAR BACKUP ed la bd y explorar view y funciones que usen el vw_entrada o salida_inventario
-----AGregar columna de insumo al inventario, debe poder tener insumo sin proveedor
----UNA vez este esto se debe fusionar el ledger
    IF EXISTS (SELECT 1 FROM cuadre_inventario_detalle WHERE cantidad_sistema<cantidad_contada and cuadre_inventario_id = p_cuadre_id) THEN
    INSERT INTO entrada_inventario(motivo)
    SELECT 'reconteo'
    RETURNING id INTO v_entrada_inventario_id;

    INSERT INTO entrada_inventario_detalle(entrada_inventario_id,cantidad_solicitada,insumo_id)
    SELECT v_entrada_inventario_id,cantidad_contada-cantidad_sistema,insumo_id FROM cuadre_inventario_detalle
    WHERE cuadre_inventario_id=p_cuadre_id AND cantidad_contada>cantidad_sistema;

    INSERT INTO inventario(entrada_inventario_detalle_id,cantidad,costo_bruto_kg,usr_cre,fyh_ingreso,insumo_id)
    SELECT eid.id,eid.cantidad_solicitada,cid.costo_bruto_prom_kg_sistema,get_user_id(),v_cuadre_fecha,cid.insumo_id FROM cuadre_inventario_detalle cid
    JOIN entrada_inventario_detalle eid ON cid.insumo_id=eid.insumo_id AND eid.entrada_inventario_id=v_entrada_inventario_id
    WHERE cuadre_inventario_id=p_cuadre_id 
    --AND cantidad_contada<cantidad_sistema
    ;
    

    UPDATE entrada_inventario
    set estado='aprobado'
    WHERE id=v_entrada_inventario_id;
    UPDATE entrada_inventario_detalle
    set estado='aprobado'
    WHERE entrada_inventario_id=v_entrada_inventario_id;
    END IF;

    UPDATE cuadre_inventario SET fecha_cierre=now(), estado='ejecutado' WHERE id=p_cuadre_id;

RETURN jsonb_build_object(
        'message', 'Cuadre finalizado correctamente'
    );

END;
$$;


ALTER FUNCTION public.finalizar_cuadre_inventario(p_cuadre_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.fn_delete_ejecucion_previa(bigint, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.fn_delete_ejecucion_previa(p_partida_id bigint, p_tipo_receta_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
  v_result JSONB;
  v_params JSONB;
BEGIN
v_params := jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_tipo_receta_id', p_tipo_receta_id
  );
    INSERT into logs_api(function_name, user_id, params)
  SELECT 'fn_delete_ejecucion_previa', get_user_id(), v_params;

  IF p_tipo_receta_id =7 THEN
  SELECT delete_partida_x_receta(id)
  INTO v_result
  FROM partida_x_recetas
  WHERE partida_id = p_partida_id
    AND tipo_receta_id = p_tipo_receta_id
    AND flg_elm = false
  LIMIT 1;
END IF;
  IF v_result IS NULL THEN
    RETURN jsonb_build_object(
      'error', true,
      'mensaje', 'No se encontró ninguna ejecución previa para eliminar.'
    );
  END IF;

  RETURN v_result;
END;$$;


ALTER FUNCTION public.fn_delete_ejecucion_previa(p_partida_id bigint, p_tipo_receta_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.fn_reasignar_fifo_orphan(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.fn_reasignar_fifo_orphan(p_detalle_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_insumo_id   INT;
    v_cantidad    NUMERIC;
    v_salida_id   INT;
    v_fecha       TIMESTAMP;
    v_fecha_tz    TIMESTAMPTZ;
    msj_error     TEXT;
BEGIN
    -- Get detail info
    SELECT insumo_id, cantidad_solicitada, salida_inventario_id
    INTO v_insumo_id, v_cantidad, v_salida_id
    FROM salida_inventario_detalle
    WHERE id = p_detalle_id;

    IF v_insumo_id IS NULL THEN
        RETURN jsonb_build_object('error', true, 'mensaje', 'Detalle no encontrado.');
    END IF;

    -- Preserve original fecha and fecha_tz from orphaned allocation (if exists)
    SELECT MAX(fecha)
    INTO v_fecha
    FROM salida_inventario_detalle_x_stock
    WHERE salida_inventario_detalle_id = p_detalle_id
      AND inventario_id IS NULL;

    -- Validate stock
    SELECT 
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               v_cantidad,
               COALESCE(ixs.cantidad, 0))
    INTO msj_error
    FROM insumo ins
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = ins.id
    WHERE ins.id = v_insumo_id
      AND v_cantidad > COALESCE(ixs.cantidad, 0);

    IF msj_error IS NOT NULL THEN
        RETURN jsonb_build_object('error', true, 'mensaje', 'Stock insuficiente - ' || msj_error);
    END IF;

    -- Delete old orphan/previous allocations
    DELETE FROM salida_inventario_detalle_x_stock
    WHERE salida_inventario_detalle_id = p_detalle_id;

    -- FIFO allocation and reinsertion
    WITH inventario_ordenado AS (
        SELECT
            i.inventario_id AS inventario_id,
            i.cantidad AS lot_quantity,
            i.fyh_ingreso
        FROM vw_inventario i
        JOIN insumo_x_proveedor ixp ON ixp.id = i.insumo_x_proveedor_id
        WHERE ixp.insumo_id = v_insumo_id
          AND i.cantidad > 0
        ORDER BY i.fyh_ingreso
    ),
    inventario_fifo AS (
        SELECT
            inventario_id,
            lot_quantity,
            fyh_ingreso,
            SUM(lot_quantity) OVER (ORDER BY fyh_ingreso) AS running_total
        FROM inventario_ordenado
    ),
    inventario_con_prev AS (
        SELECT
            inventario_id,
            lot_quantity,
            running_total,
            LAG(running_total) OVER (ORDER BY fyh_ingreso) AS prev_running_total
        FROM inventario_fifo
    ),
    inventario_consumo AS (
        SELECT
            inventario_id,
            LEAST(
                lot_quantity,
                GREATEST(v_cantidad - COALESCE(prev_running_total, 0), 0)
            ) AS cantidad_a_usar
        FROM inventario_con_prev
        WHERE LEAST(
            lot_quantity,
            GREATEST(v_cantidad - COALESCE(prev_running_total, 0), 0)
        ) > 0
    )
    INSERT INTO salida_inventario_detalle_x_stock (
        salida_inventario_detalle_id,
        inventario_id,
        cantidad,
        fecha
    )
    SELECT
        p_detalle_id,
        inventario_id,
        cantidad_a_usar,
        COALESCE(v_fecha, NOW())       -- preserve fecha if availabl
    FROM inventario_consumo;

    RETURN jsonb_build_object(
        'error', false,
        'mensaje', format(
            'Reasignación FIFO completada para detalle #%s (Salida #%s)',
            p_detalle_id, v_salida_id
        ),
        'detalles', get_salida_inventario_detalles(v_salida_id)
    );
END;
$$;


ALTER FUNCTION public.fn_reasignar_fifo_orphan(p_detalle_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.generate_recipe(integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.generate_recipe(p_partida_id integer, p_id_receta integer, p_id_maquina integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_result JSON;
    v_partida_info JSON;
    v_receta_id int;
    v_receta_info JSON;
    v_maquina_info JSON;
    v_pasos JSON;
    v_volumen DECIMAL(10,2);
    v_peso DECIMAL(10,2);
    v_rollos INTEGER;
    v_rb DECIMAL(10,2);
    v_maquina_nombre TEXT;
BEGIN
    -- Main query consolidating all data sources
    IF NOT EXISTS (SELECT 1 FROM partida WHERE id=p_partida_id) THEN
    RAISE EXCEPTION 'No se encontraron datos para la partida ingresada.';
END IF;
    IF NOT EXISTS (SELECT 1 FROM maquina WHERE id = p_id_maquina) THEN
    RAISE EXCEPTION 'No se encontraron datos para la máquina ingresada.';
END IF;



    SELECT p_id_receta INTO v_receta_id;
   

IF v_receta_id IS NULL THEN RAISE  EXCEPTION 'No se encontro receta del tipo especificado para la partida'; END IF;


    WITH 
    maquina_data AS (
        SELECT 
            id,
            nombre,
            "RB"
        FROM maquina 
        WHERE id = p_id_maquina AND "RB" IS NOT NULL
    ),
    data AS (
        SELECT 
            'MLR - TINTORERÍA - RECETA ' || UPPER(r.tipo_receta) titulo,
            now() fecha,
            r.receta_id,
            p.partida,
            m.id maquina_id,
            p.cliente,
            p.rollos,
            p.articulo,
            p.peso,
            p.color ||' - ' ||p.tono color,
            p.rib,
            -- Volume calculation logic
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND p.rollos <= 12 THEN p.peso * 7
                ELSE p.peso * m."RB"
            END as volumen,
            -- Recipe adjustment factor
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND p.rollos = 12 THEN 1.08
                ELSE 1.0
            END as adjustment_factor,
            p.ancho,
        COALESCE(p.malla, '0') as malla,
        COALESCE(p.rendimiento, '0') as rendimiento,
        p.fibra,
        p.fecha_entrega,
        COALESCE(p.flg_prim_part, '') as flg_prim_part,
        COALESCE(p.observacion, '') as observacion
        FROM vw_partidas_resumen_v2 p 
        CROSS JOIN vw_receta_v2 r
        CROSS JOIN maquina_data m
        WHERE p.partida=p_partida_id AND r.receta_id=v_receta_id
    ),
    pasos as(
        SELECT orden, 
        1 as tipo, 
        paso_id AS fk, 
        paso AS nombre, 
        NULL::NUMERIC AS cantidad, 
        NULL::medida_enum AS medida,
        NULL tipo_insumo, 
        NULL::numeric as costo,
        NULL::numeric as cantidad_requerida
        FROM receta_x_paso rp
        JOIN paso p2 ON rp.paso_id = p2.id
        WHERE rp.receta_id = v_receta_id
        UNION
        SELECT orden, 
        2 as tipo, 
        insumo_id AS fk, 
        insumo AS nombre, 
        cantidad, 
        medida, 
        i.tipo,
        CASE 
            when i.medida = 'g/L' then ((5*cantidad)/1000)*i.precio_prom_kg_usd
            when i.medida = '%' then ((1*cantidad*10)/1000)*i.precio_prom_kg_usd
        END,
        CASE 
            WHEN i.medida = 'g/L' AND i.tipo IN('directo','disperso','reactivo') THEN (ri.cantidad * d.adjustment_factor) * d.volumen
            WHEN i.medida = '%' AND i.tipo IN('directo','disperso','reactivo') THEN (ri.cantidad * d.adjustment_factor) * d.peso * 10
            WHEN i.medida = 'g/L' THEN (ri.cantidad ) * d.volumen
            WHEN i.medida = '%' THEN (ri.cantidad ) * d.peso * 10
            ELSE NULL
        END as cantidad_requerida
        FROM receta_x_insumo ri
        JOIN insumo i ON ri.insumo_id = i.id
        JOIN data d ON 1=1
        WHERE ri.receta_id = v_receta_id 
    ),
    procesos AS (
    SELECT 
        CASE 
            WHEN d.articulo IN ('F Poly', 'Franela Poly 6535', 'Franela') THEN
                jsonb_build_array(
                    'REMALLADO', 'TEÑIDO', 'HIDRO', 'SECADO', 'PERCHADO', 'COMPACTADO'
                )
            WHEN d.articulo IN ('Full Lycra', 'J 30/1 Lycra', 'J Lycra', 'Rib Lycrado') THEN
                jsonb_build_array(
                    'REMALLADO', 'TERMOFIJADO', 'TEÑIDO', 'HIDRO', 'SECADO', 'COMPACTADO'
                )
            ELSE
                jsonb_build_array(
                    'REMALLADO', 'TEÑIDO', 'HIDRO', 'SECADO', 'COMPACTADO'
                )
        END as proceso_pasos
    FROM data d
),additional_info AS (
    SELECT 
        CASE 
            WHEN d.rendimiento = '0' AND (d.malla = '0' OR d.malla = '') THEN
                'Ancho: ' || d.ancho || ' - Fibra: ' || d.fibra
            WHEN d.malla = '0' OR d.malla = '' THEN
                'Ancho: ' || d.ancho || ' - Rendimiento: ' || d.rendimiento || 
                ' - Fibra: ' || d.fibra || ' - Fec.Entrega: ' || d.fecha_entrega
            WHEN d.rendimiento = '0' THEN
                'Ancho: ' || d.ancho || ' - Fibra: ' || d.fibra || 
                ' - Malla: ' || d.malla || ' - Fec.Entrega: ' || d.fecha_entrega
            ELSE
                'Ancho: ' || d.ancho || ' - Rendimiento: ' || d.rendimiento || 
                ' - Fibra: ' || d.fibra || ' - Malla: ' || d.malla --|| ' - Fec.Entrega: ' || d.fecha_entrega
        END as info_line
    FROM data d
)SELECT jsonb_build_object(
        'titulo', d.titulo,
        'fecha', d.fecha,
        'id_receta', d.receta_id,
        'partida', d.partida,
        'maquina', d.maquina_id,
        'cliente', d.cliente,
        'rollos', d.rollos,
        'articulo', d.articulo,
        'peso', d.peso,
        'color', d.color,
        'rib',d.rib,
        'volumen', ROUND(d.volumen::NUMERIC, 2),
    
    'pasos', (
        SELECT jsonb_agg(
            jsonb_build_object(
                'orden', p.orden,
                'insumo_id',p.fk,
                'tipo', p.tipo,
                'nombre', p.nombre,
                'cantidad', p.cantidad,
                'medida', p.medida,
                'tipo_insumo', p.tipo_insumo,
                'costo', ROUND(p.costo::NUMERIC, 4),
                'cantidad_requerida', ROUND(p.cantidad_requerida::NUMERIC, 2)
            ) ORDER BY p.orden
        )
        FROM pasos p
    ),
    'additional_info', ai.info_line,
    'fecha_entrega', d.fecha_entrega,
    'flg_primera_partida', d.flg_prim_part,
    'nota',  d.observacion,
    'process_steps', ps.proceso_pasos,
    'summary', jsonb_build_object(
        'total_cost', (
            SELECT COALESCE(SUM(p.costo), 0)
            FROM pasos p
            WHERE p.tipo = 2 AND p.costo IS NOT NULL
        ),
        'total_insumos', (
            SELECT COUNT(*)
            FROM pasos p
            WHERE p.tipo = 2
        )
    )
) INTO v_result
FROM data d
CROSS JOIN additional_info ai
CROSS JOIN procesos ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_recipe(p_partida_id integer, p_id_receta integer, p_id_maquina integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.generate_recipe(integer, integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.generate_recipe(p_partida_id integer, p_id_receta integer, p_id_maquina integer, p_num_rollos integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_result JSON;
    v_partida_info JSON;
    v_receta_id int;
    v_receta_info JSON;
    v_maquina_info JSON;
    v_pasos JSON;
    v_volumen DECIMAL(10,2);
    v_peso DECIMAL(10,2);
    v_rollos INTEGER;
    v_rb DECIMAL(10,2);
    v_maquina_nombre TEXT;
BEGIN
    -- Main query consolidating all data sources
    IF NOT EXISTS (SELECT 1 FROM partida WHERE id=p_partida_id) THEN
    RAISE EXCEPTION 'No se encontraron datos para la partida ingresada.';
END IF;
    IF NOT EXISTS (SELECT 1 FROM maquina WHERE id = p_id_maquina) THEN
    RAISE EXCEPTION 'No se encontraron datos para la máquina ingresada.';
END IF;



    SELECT p_id_receta INTO v_receta_id;
   

IF v_receta_id IS NULL THEN RAISE  EXCEPTION 'No se encontro receta del tipo especificado para la partida'; END IF;



    WITH 
    maquina_data AS (
        SELECT 
            id,
            nombre,
            "RB"
        FROM maquina 
        WHERE id = p_id_maquina AND "RB" IS NOT NULL
    ),
    data AS (
        SELECT 
            'MLR - TINTORERÍA - RECETA ' || UPPER(r.tipo_receta) titulo,
            now() fecha,
            r.receta_id,
            p.partida,
            m.id maquina_id,
            p.cliente,
            COALESCE(p_num_rollos,p.rollos) rollos,
            p.articulo,
            COALESCE(p_num_rollos*p.peso/p.rollos,p.peso) peso,
            p.color ||' - ' ||p.tono color,
            p.rib,
            -- Volume calculation logic
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) <= 12 THEN COALESCE(p_num_rollos*p.peso/p.rollos,p.peso) * 7
                ELSE COALESCE(p_num_rollos*p.peso/p.rollos,p.peso) * m."RB"
            END as volumen,
            -- Recipe adjustment factor
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) = 12 THEN 1.08
                ELSE 1.0
            END as adjustment_factor,
            p.ancho,
        COALESCE(p.malla, '0') as malla,
        COALESCE(p.rendimiento, '0') as rendimiento,
        p.fibra,
        p.fecha_entrega,
        COALESCE(p.flg_prim_part, '') as flg_prim_part,
        COALESCE(p.observacion, '') as observacion
        FROM vw_partidas_resumen_v2 p 
        CROSS JOIN vw_receta_v2 r
        CROSS JOIN maquina_data m
        WHERE p.partida=p_partida_id AND r.receta_id=v_receta_id
    ),
    pasos as(
        SELECT orden, 
        1 as tipo, 
        paso_id AS fk, 
        paso AS nombre, 
        NULL::NUMERIC AS cantidad, 
        NULL::medida_enum AS medida,
        NULL tipo_insumo, 
        NULL::numeric as costo,
        NULL::numeric as cantidad_requerida
        FROM receta_x_paso rp
        JOIN paso p2 ON rp.paso_id = p2.id
        WHERE rp.receta_id = v_receta_id
        UNION
        SELECT orden, 
        2 as tipo, 
        insumo_id AS fk, 
        insumo AS nombre, 
        cantidad, 
        medida, 
        i.tipo,
        CASE 
            when i.medida = 'g/L' then ((5*cantidad)/1000)*i.precio_prom_kg_usd
            when i.medida = '%' then ((1*cantidad*10)/1000)*i.precio_prom_kg_usd
        END,
        CASE 
            WHEN i.medida = 'g/L' AND i.tipo IN('directo','disperso','reactivo') THEN (ri.cantidad * d.adjustment_factor) * d.volumen
            WHEN i.medida = '%' AND i.tipo IN('directo','disperso','reactivo') THEN (ri.cantidad * d.adjustment_factor) * d.peso * 10
            WHEN i.medida = 'g/L' THEN (ri.cantidad ) * d.volumen
            WHEN i.medida = '%' THEN (ri.cantidad ) * d.peso * 10
            ELSE NULL
        END as cantidad_requerida
        FROM receta_x_insumo ri
        JOIN insumo i ON ri.insumo_id = i.id
        JOIN data d ON 1=1
        WHERE ri.receta_id = v_receta_id 
    ),
    procesos AS (
    SELECT 
        CASE 
            WHEN d.articulo IN ('F Poly', 'Franela Poly 6535', 'Franela') THEN
                jsonb_build_array(
                    'REMALLADO', 'TEÑIDO', 'HIDRO', 'SECADO', 'PERCHADO', 'COMPACTADO'
                )
            WHEN d.articulo IN ('Full Lycra', 'J 30/1 Lycra', 'J Lycra', 'Rib Lycrado') THEN
                jsonb_build_array(
                    'REMALLADO', 'TERMOFIJADO', 'TEÑIDO', 'HIDRO', 'SECADO', 'COMPACTADO'
                )
            ELSE
                jsonb_build_array(
                    'REMALLADO', 'TEÑIDO', 'HIDRO', 'SECADO', 'COMPACTADO'
                )
        END as proceso_pasos
    FROM data d
),additional_info AS (
    SELECT 
        CASE 
            WHEN d.rendimiento = '0' AND (d.malla = '0' OR d.malla = '') THEN
                'Ancho: ' || d.ancho || ' - Fibra: ' || d.fibra
            WHEN d.malla = '0' OR d.malla = '' THEN
                'Ancho: ' || d.ancho || ' - Rendimiento: ' || d.rendimiento || 
                ' - Fibra: ' || d.fibra || ' - Fec.Entrega: ' || d.fecha_entrega
            WHEN d.rendimiento = '0' THEN
                'Ancho: ' || d.ancho || ' - Fibra: ' || d.fibra || 
                ' - Malla: ' || d.malla || ' - Fec.Entrega: ' || d.fecha_entrega
            ELSE
                'Ancho: ' || d.ancho || ' - Rendimiento: ' || d.rendimiento || 
                ' - Fibra: ' || d.fibra || ' - Malla: ' || d.malla --|| ' - Fec.Entrega: ' || d.fecha_entrega
        END as info_line
    FROM data d
)SELECT jsonb_build_object(
        'titulo', d.titulo,
        'fecha', d.fecha,
        'id_receta', d.receta_id,
        'partida', d.partida,
        'maquina', d.maquina_id,
        'cliente', d.cliente,
        'rollos', d.rollos,
        'articulo', d.articulo,
        'peso', d.peso,
        'color', d.color,
        'rib',d.rib,
        'volumen', ROUND(d.volumen::NUMERIC, 2),
    
    'pasos', (
        SELECT jsonb_agg(
            jsonb_build_object(
                'orden', p.orden,
                'insumo_id',p.fk,
                'tipo', p.tipo,
                'nombre', p.nombre,
                'cantidad', p.cantidad,
                'medida', p.medida,
                'tipo_insumo', p.tipo_insumo,
                'costo', ROUND(p.costo::NUMERIC, 4),
                'cantidad_requerida', ROUND(p.cantidad_requerida::NUMERIC, 2)
            ) ORDER BY p.orden
        )
        FROM pasos p
    ),
    'additional_info', ai.info_line,
    'fecha_entrega', d.fecha_entrega,
    'flg_primera_partida', d.flg_prim_part,
    'nota',  d.observacion,
    'process_steps', ps.proceso_pasos,
    'summary', jsonb_build_object(
        'total_cost', (
            SELECT COALESCE(SUM(p.costo), 0)
            FROM pasos p
            WHERE p.tipo = 2 AND p.costo IS NOT NULL
        ),
        'total_insumos', (
            SELECT COUNT(*)
            FROM pasos p
            WHERE p.tipo = 2
        )
    )
) INTO v_result
FROM data d
CROSS JOIN additional_info ai
CROSS JOIN procesos ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_recipe(p_partida_id integer, p_id_receta integer, p_id_maquina integer, p_num_rollos integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_componentes_matizado(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_componentes_matizado(partida_param integer) RETURNS TABLE(partida integer, componente text, cantidad double precision, medida text)
    LANGUAGE sql
    AS $$
select a.partida_id,b.insumo componente,a.cantidad,a.medida
from matizado a
join insumo b on a.insumo_id = b.id
WHERE a.partida_id = partida_param;
$$;


ALTER FUNCTION public.get_componentes_matizado(partida_param integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_compra_detalles(text)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_compra_detalles(guia_compra text) RETURNS json
    LANGUAGE plpgsql
    AS $$DECLARE
    compra_json JSON;
    v_compra_id INTEGER;  -- assuming PK is an integer
BEGIN
    -- Derive the primary key from guia_compra
    SELECT id INTO v_compra_id
    FROM compra
    WHERE guia_remision = guia_compra;
    SELECT json_build_object(
        'compra_id',c.id,
        'proveedor_id', c.proveedor_id,
        'factura', c.factura,
        'guia_remision', c.guia_remision,
        'tipo_pago', c.tipo_pago,
        'fecha_remision', c.fecha_remision,
        'fecha_giro', c.fecha_giro,
        'fecha_vencimiento', c.fecha_vencimiento,
        'fecha_pago', c.fecha_pago,
        'total_bruto',c.total_usd/1.18,
        'igv',c.total_usd*0.18,
        'total_usd', c.total_usd,
        'estado_pago', c.estado_pago,
        'dias_gracia', CASE WHEN c.fecha_giro IS NOT NULL and c.fecha_vencimiento IS NOT NULL THEN c.fecha_vencimiento - c.fecha_giro ELSE NULL eND ,
        'fyh_cre', c.fyh_cre,
        'productos', (
            SELECT json_agg(sub)
            FROM (
              SELECT ci.insumo_id,ci.insumo_x_proveedor_id,i.insumo,ci.cantidad,ci.precio_x_kg_usd 
              FROm compra_x_insumo ci
              JOIN insumo i ON ci.insumo_id=i.id
              WHERE ci.compra_id=v_compra_id
            ) sub
        ),
        'letras', (
            SELECT json_agg(sub)
            FROM (
              SELECT l.id letra_id,l.numero_letra,l.monto_usd,l.fecha_emision,l.fecha_vencimiento,l.fecha_pago,l.estado 
              FROm letra_compra l
              WHERE l.compra_id=v_compra_id
            ) sub
        )
    ) INTO compra_json
    FROM compra c
    JOIN proveedor p ON c.proveedor_id = p.id
    WHERE c.id=v_compra_id;
    RETURN compra_json;
END;$$;


ALTER FUNCTION public.get_compra_detalles(guia_compra text) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_cuadre_inventario(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_cuadre_inventario(p_cuadre_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        
            'cuadre_inventario_id', ci.id,
            'fecha_cuadre', ci.fecha_cuadre,
            'fecha_cierre', ci.fecha_cierre,
            'usr_cre', ci.usr_cre,
            'fyh_cre', ci.fyh_cre,
            'usr_mod', ci.usr_mod,
            'fyh_mod', ci.fyh_mod,
        'detalle', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'cuadre_inventario_detalle_id', cid.id,
                    'insumo_id', cid.insumo_id,
                    'insumo',i.insumo,
                    'tipo',i.tipo,
                    'cantidad_sistema', cid.cantidad_sistema,
                    'cantidad_contada', cid.cantidad_contada,
                    'costo_bruto_total_sistema', cid.costo_bruto_total_sistema,
                    'costo_bruto_prom_kg_sistema', cid.costo_bruto_prom_kg_sistema,
                    'ult_precio_compra', cid.ult_precio_compra
                )
            ) FILTER (WHERE cid.id IS NOT NULL),
            '[]'::jsonb
        )
    )
    INTO result
    FROM cuadre_inventario ci
    LEFT JOIN cuadre_inventario_detalle cid 
        ON cid.cuadre_inventario_id = ci.id
    LEFT JOIN insumo i ON i.id=cid.insumo_id
    WHERE ci.id = p_cuadre_id
    GROUP BY ci.id;

    IF result IS NULL THEN
        RAISE EXCEPTION 'El cuadre_inventario % no existe', p_cuadre_id;
    END IF;

    RETURN result;
END;
$$;


ALTER FUNCTION public.get_cuadre_inventario(p_cuadre_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_entrada_inventario_detalles(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_entrada_inventario_detalles(entrada_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'entrada_inventario_detalle_id', eid.id,
      'insumo_x_proveedor_id', eid.insumo_x_proveedor_id,
      'insumo',i.insumo,
      'proveedor',p.proveedor,
      'cantidad_solicitada', eid.cantidad_solicitada,
      'cantidad_recibida', eid.cantidad_recibida,
      'estado', eid.estado,
      'observacion', eid.observacion
    ))
    FROM entrada_inventario_detalle eid
    LEFT JOIN insumo_x_proveedor ip ON ip.id=eid.insumo_x_proveedor_id
    LEFT JOIN insumo i ON i.id=ip.insumo_id
    LEFT JOIN proveedor p ON p.id=ip.proveedor_id
    WHERE eid.entrada_inventario_id = entrada_id
  );
END;
$$;


ALTER FUNCTION public.get_entrada_inventario_detalles(entrada_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_info_partida(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_info_partida(partida_param integer) RETURNS TABLE(partida integer, guia text, cliente text, articulo text, color text, ancho text, rendimiento text, malla text, fibra text, rollos integer, rib integer, rollos_rib text, peso double precision, fecha_entrega date, color2 text, primera_partida text, duracion interval, observacion text)
    LANGUAGE sql
    AS $$SELECT
    a.partida,
    a.guia,
    a.cliente,
    a.articulo,
    concat(a.color, ' ', a.tenido) AS color,
    a.ancho,
    a.rendimiento,
    a.malla,
    a.fibra,
    a.rollos,
    coalesce(a.rib,0) + coalesce(c.cantidad,0) rib,
    CASE 
        WHEN coalesce(a.rib,0) + coalesce(c.cantidad,0) = 0 THEN concat(a.rollos)
        ELSE concat(a.rollos, '+', coalesce(a.rib,0) + coalesce(c.cantidad,0) )
    END AS rollos_rib,
    a.peso,
    a.fecha_entrega,
    a.color AS color2,
    a.flg_prim_part,
    a.duracion,
    b.observacion
FROM vw_partidas_resumen a 
left join partida b on a.partida = b.id
left join partida_x_extra c on a.partida = c.partida_id 
WHERE a.partida = partida_param;$$;


ALTER FUNCTION public.get_info_partida(partida_param integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_insumo_movimientos_cuadre(integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_insumo_movimientos_cuadre(p_insumo_id integer, p_cuadre_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_fyh_desde timestamptz;
    v_fyh_hasta timestamptz;
BEGIN
    SELECT ult_cuadre_ejecutado_fecha,
           fecha_cuadre
    INTO v_fyh_desde, v_fyh_hasta
    FROM vw_cuadre_inventario
    WHERE cuadre_inventario_id = p_cuadre_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuadre % no existe', p_cuadre_id;
    END IF;

    RETURN public.get_insumo_movimientos_rango(
               p_insumo_id,
               COALESCE(v_fyh_desde,'2025-01-01'),
               v_fyh_hasta
           );
END;
$$;


ALTER FUNCTION public.get_insumo_movimientos_cuadre(p_insumo_id integer, p_cuadre_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_insumo_movimientos_rango(integer, timestamp with time zone, timestamp with time zone)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_insumo_movimientos_rango(p_insumo_id integer, p_fyh_desde timestamp with time zone, p_fyh_hasta timestamp with time zone) RETURNS jsonb
    LANGUAGE sql
    AS $$
  SELECT jsonb_agg(to_jsonb(t))
    FROM (
        SELECT 
            row_number() OVER (ORDER BY fecha ASC) AS row_id,
            t.*
        FROM vw_inventario_movimientos t
        WHERE t.insumo_id = p_insumo_id
          AND t.fecha > p_fyh_desde 
          AND t.fecha < p_fyh_hasta
        ORDER BY fecha
    ) t;
$$;


ALTER FUNCTION public.get_insumo_movimientos_rango(p_insumo_id integer, p_fyh_desde timestamp with time zone, p_fyh_hasta timestamp with time zone) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_inventario_insumo_lotes(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_inventario_insumo_lotes(p_insumo_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'inventario_id', inv.inventario_id,
      'insumo_x_proveedor_id', inv.insumo_x_proveedor_id,
      'insumo',ins.insumo,
      'proveedor',p.proveedor,
      'cantidad_inicial',inv.cantidad_inicial,
      'cantidad', inv.cantidad,
      'fyh_ingreso', inv.fyh_ingreso
    )
    ORDER by inv.fyh_ingreso ASC
    )
    FROM vw_inventario inv
    LEFT JOIN insumo_x_proveedor ip ON ip.id=inv.insumo_x_proveedor_id
    LEFT JOIN insumo ins ON ins.id=ip.insumo_id OR (ip.insumo_id IS NULL AND inv.insumo_id=ins.id)
    LEFT JOIN proveedor p ON p.id=ip.proveedor_id
    WHERE ins.id=p_insumo_id
  );
END;$$;


ALTER FUNCTION public.get_inventario_insumo_lotes(p_insumo_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_lavado_maquina_detalles(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_lavado_maquina_detalles(p_receta_id integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    receta_json JSON;
BEGIN
    SELECT json_build_object(
        'id',p_receta_id,
        'tipo_lavado_mq_id', r.tipo_lavado_mq_id,
        'valor_origen_id'  , r.valor_origen_id,
        'valor_destino_id' , r.valor_destino_id,
        'pasos', (
            SELECT json_agg(sub ORDER BY orden)
            FROM (
                SELECT orden, 1 as tipo, paso_id AS fk, paso AS nombre, NULL::NUMERIC AS cantidad, NULL::text AS medida,NULL tipo_insumo, NULL::NUMERIC costo
                FROM receta_lavado_maquina_x_paso rp
                JOIN paso p2 ON rp.paso_id = p2.id
                WHERE rp.receta_lavado_mq_id = p_receta_id
                UNION
                SELECT orden, 2 as tipo, insumo_id AS fk, insumo AS nombre, cantidad, 'kg' medida, i.tipo,
                cantidad*i.precio_prom_kg_usd
                FROM receta_lavado_maquina_x_insumo ri
                JOIN insumo i ON ri.insumo_id = i.id
                WHERE ri.receta_lavado_mq_id = p_receta_id
            ) sub
        )
    ) INTO receta_json
    FROM receta_lavado_maquina r
    WHERE r.id = p_receta_id;
    RETURN receta_json;
END;
$$;


ALTER FUNCTION public.get_lavado_maquina_detalles(p_receta_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_letras_compra(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_letras_compra(p_compra_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(to_jsonb(lc.*))
  INTO result
  FROM letra_compra lc
  WHERE lc.compra_id = p_compra_id;

  RETURN result;
END;
$$;


ALTER FUNCTION public.get_letras_compra(p_compra_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_max_pk_partida()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_max_pk_partida() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    max_value integer;
BEGIN
    -- Get the maximum value of id from the partida table
    SELECT MAX(id) INTO max_value FROM partida;

    -- Return the maximum value
    RETURN max_value;
END;
$$;


ALTER FUNCTION public.get_max_pk_partida() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_partida(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_partida(p_partida_id integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    partida_json JSON;
BEGIN
    SELECT json_build_object(
        'partida_id',p_partida_id,
        'guia',p.guia,
        'fecha_entrega',p.fecha_entrega,
        'prioridad_id', p.prioridad_id,
        'cliente_id', p.cliente_id,
        'tenido_id', p.tenido_id,
        'articulo_id', p.articulo_id,
        'fibra', CAST(p.fibra AS SMALLINT),
        'previo_id',p.previo_id,
        'ancho', p.ancho,
        'malla',p.malla,
        'rib',p.rib,
        'rendimiento',p.rendimiento,
        'rollos',p.rollos,
        'color_x_cliente_id',p.color_x_cliente_id,
        'adicional_id',adicional_id,
        'observacion',p.observacion,
        'extras', ( --pendiente de modificar para agregar extras (paquetes de cuellos y de puños)
            SELECT json_agg(sub)
            FROM (
                SELECT extra_id,extra,cantidad FROM partida_x_extra 
                JOIN extra ON extra_id=id
                WHERE partida_id=p_partida_id 
            ) sub
        )
    ) INTO partida_json
    FROM partida p
    WHERE p.id = p_partida_id;

    RETURN partida_json;
END;
$$;


ALTER FUNCTION public.get_partida(p_partida_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_productos_compra(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_productos_compra(compra_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(to_jsonb(lc.*))
  INTO result
  FROM  compra_x_insumo lc
  WHERE lc.compra_id = compra_id;

  RETURN result;
END;
$$;


ALTER FUNCTION public.get_productos_compra(compra_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_proyeccion_tenido_por_maquina()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_proyeccion_tenido_por_maquina() RETURNS TABLE(maquina_id integer, orden integer, tipo_registro text, id text, color text, tenido text, valor text, adicional text, kilos numeric, duracion interval, hora_inicio interval, hora_fin interval, produccion_total numeric, produccion_dia numeric)
    LANGUAGE plpgsql
    AS $$
begin
  return query
  with datos_base as (
    select 
      v.maquina_id::integer as maq,
      v.orden::integer as ord,
      v.tipo_registro::text as tipo_reg,
      v.partida_id::text as part_id,
      v.color::text as col,
      v.tenido::text as ten,
      v.valor::text as val,
      v.adicional::text as addi,
      v.kilos::numeric as kil,
      v.duracion as duracion_total,
      v.tipo_receta as tipo_receta
    from vw_union_programa_tenido v 
  ),
  con_horas as (
    select db.*,
           him.hora_inicio,
           row_number() over (partition by db.maq order by db.ord) - 1 as descanso_count
    from datos_base db
    left join hora_inicio_maquina him on db.maq = him.maquina_id
  ),
  con_tiempos as (
    select *,
      (
        make_interval(mins => extract(hour from con_horas.hora_inicio)::int * 60 + extract(minute from con_horas.hora_inicio)::int)
        + sum(coalesce(duracion_total, interval '0')) over (partition by maq order by ord)
        + descanso_count * interval '20 minutes'
      ) - coalesce(duracion_total, interval '0') as hora_ini,

      (
        make_interval(mins => extract(hour from con_horas.hora_inicio)::int * 60 + extract(minute from con_horas.hora_inicio)::int)
        + sum(coalesce(duracion_total, interval '0')) over (partition by maq order by ord)
        + descanso_count * interval '20 minutes'
      ) as hora_fin_calc
    from con_horas
  )
  select 
    maq as maquina_id,
    ord as orden,
    -- Aquí el cambio:
    case 
      when tipo_reg = 'Lavado' then tipo_receta
      else tipo_reg
    end as tipo_registro,
    part_id as id,
    col as color,
    ten as tenido,
    val as valor,
    addi as adicional,
    kil as kilos,
    duracion_total as duracion,
    hora_ini as hora_inicio,
    hora_fin_calc as hora_fin,

    -- Producción total
    case
      when tipo_reg = 'Lavado' then null
      when tipo_receta not in ('Teñido','Produccion') then null
      when hora_ini >= make_interval(hours => 31) then 0
      when hora_fin_calc <= make_interval(hours => 31) then kil
      else
        round((extract(epoch from (make_interval(hours => 31) - hora_ini)) /
               nullif(extract(epoch from duracion_total), 0)
             * kil)::numeric, 2)
    end as produccion_total,

    -- Producción día
    case
      when tipo_reg = 'Lavado' then null
      when tipo_receta not in ('Teñido','Produccion') then null
      when hora_ini >= make_interval(hours => 19) then 0
      when hora_fin_calc <= make_interval(hours => 19) then kil
      else
        round((extract(epoch from (make_interval(hours => 19) - hora_ini)) /
               nullif(extract(epoch from duracion_total), 0)
             * kil)::numeric, 2)
    end as produccion_dia

  from con_tiempos
  order by maq, ord;
end;
$$;


ALTER FUNCTION public.get_proyeccion_tenido_por_maquina() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_rb_maquina(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_rb_maquina(id_maquina_param integer) RETURNS TABLE(id integer, nombre text, rb numeric)
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT id, nombre,"RB" as rb
    FROM maquina
    WHERE id = id_maquina_param;
$$;


ALTER FUNCTION public.get_rb_maquina(id_maquina_param integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_receta_by_partida(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_receta_by_partida(partida_param integer) RETURNS TABLE(partida integer, cliente text, articulo text, color text, id_receta integer)
    LANGUAGE sql SECURITY DEFINER
    AS $$
SELECT 
    a.partida,
    a.cliente,
    a.articulo,
    a.color,
    b.pk_receta AS id_receta
FROM temp_partida a 
JOIN receta b 
    ON a.cliente = b.cliente 
    AND a.articulo = b.articulo 
    AND a.color = b.color
WHERE a.partida = partida_param;
$$;


ALTER FUNCTION public.get_receta_by_partida(partida_param integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_salida_inventario_detalles(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_salida_inventario_detalles(salida_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'salida_inventario_detalle_id', eid.id,
        'insumo_id', i.id,
        'insumo', i.insumo,
        'cantidad_solicitada', eid.cantidad_solicitada,
        'estado', eid.estado,
        'observacion', eid.observacion,
        'stock', (
          SELECT jsonb_agg(
            jsonb_build_object(
              'inventario_id', sidx.inventario_id,
              'cantidad', sidx.cantidad
            )
          )
          FROM salida_inventario_detalle_x_stock sidx
          WHERE sidx.salida_inventario_detalle_id = eid.id
        )
      )
    )
    FROM salida_inventario_detalle eid
    LEFT JOIN insumo i ON i.id = eid.insumo_id
    WHERE eid.salida_inventario_id = salida_id
  );
END;
$$;


ALTER FUNCTION public.get_salida_inventario_detalles(salida_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.get_user_by_id(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.get_user_by_id(user_id integer) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  SELECT first_name || ' ' || last_name
  FROM profiles
  WHERE id_usuario = user_id;
$$;


ALTER FUNCTION public.get_user_by_id(user_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.handle_new_user()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.profiles (id, first_name, last_name)
  values (new.id, new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'last_name');
  return new;
end;
$$;


ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.homologar_insumos(integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.homologar_insumos(p_keep_id integer, p_duplicate_id integer) RETURNS TABLE(table_name text, rows_updated integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    -- Validate inputs (same as above)
    IF NOT EXISTS (SELECT 1 FROM insumo WHERE id = p_keep_id) THEN
        RAISE EXCEPTION 'Insumo con ID % no existe', p_keep_id;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM insumo WHERE id = p_duplicate_id) THEN
        RAISE EXCEPTION 'Insumo con ID % no existe', p_duplicate_id;
    END IF;
    
    IF p_keep_id = p_duplicate_id THEN
        RAISE EXCEPTION 'No se puede homologar el insumo consigo mismo';
    END IF;
    
    -- Update with row count tracking
    UPDATE "compra_x_insumo"
    SET insumo_id = p_keep_id
    WHERE insumo_id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'compra_x_insumo'::TEXT, affected_rows;
    
    UPDATE "insumo_x_proveedor"
    SET insumo_id = p_keep_id
    WHERE insumo_id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'insumo_x_proveedor'::TEXT, affected_rows;
    
    UPDATE "matizado"
    SET insumo_id = p_keep_id
    WHERE insumo_id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'matizado'::TEXT, affected_rows;
    
    UPDATE "receta_lavado_maquina_x_insumo"
    SET insumo_id = p_keep_id
    WHERE insumo_id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'receta_lavado_maquina_x_insumo'::TEXT, affected_rows;
    
    UPDATE "receta_x_insumo"
    SET insumo_id = p_keep_id
    WHERE insumo_id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'receta_x_insumo'::TEXT, affected_rows;
    
    UPDATE "salida_inventario_detalle"
    SET insumo_id = p_keep_id
    WHERE insumo_id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'salida_inventario_detalle'::TEXT, affected_rows;
    
    -- Delete the duplicate
    DELETE FROM insumo WHERE id = p_duplicate_id;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN QUERY SELECT 'insumo (deleted)'::TEXT, affected_rows;
END;
$$;


ALTER FUNCTION public.homologar_insumos(p_keep_id integer, p_duplicate_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insert_compra(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insert_compra(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_compra_id INT;
    error_message TEXT;
    error_detail TEXT;
    error_context TEXT;
BEGIN
    INSERT into logs_api(function_name,user_id,params)
  SELECT 'insert_compra', get_user_id(),json_data;
    INSERT INTO compra AS c (
        proveedor_id,
        factura,
        guia_remision,
        tipo_pago,
        fecha_remision,
        fecha_giro,
        fecha_vencimiento,
        fecha_pago,
        total_usd
    )
    VALUES (
        (json_data->>'proveedor_id')::SMALLINT,
        (json_data->>'factura'),
        (json_data->>'guia_remision'),
        (json_data->>'tipo_pago')::tipo_pago_enum,
        nullif((json_data->>'fecha_remision'),'')::date,
        nullif((json_data->>'fecha_giro'),'')::date,
        nullif((json_data->>'fecha_vencimiento'),'')::date,
        nullif((json_data->>'fecha_pago'),'')::date,
        (json_data->>'total_usd')::numeric(7,2)
    )
    RETURNING c.id AS result_pk INTO new_compra_id;

    -- Bulk insert extras into compra_x_extra
    INSERT INTO compra_x_insumo (compra_id, insumo_id, insumo_x_proveedor_id, cantidad,precio_x_kg_usd)
    SELECT 
        new_compra_id,
        (item->>'insumo_id')::SMALLINT,
        (item->>'insumo_x_proveedor_id')::smallint,
        REPLACE((item->>'cantidad'),',','.')::NUMERIC(8,2),
        REPLACE((item->>'precio_x_kg_usd'),',','.')::NUMERIC(8,2)
    FROM jsonb_array_elements(json_data->'productos') AS item;

    --ACtualizar tabla historica de precios
    UPDATE proveedor_precio pp
    SET fyh_fin=current_timestamp
    FROM jsonb_array_elements(json_data->'productos') AS item
    WHERE pp.insumo_x_proveedor_id =(item->>'insumo_x_proveedor_id')::smallint AND
    REPLACE((item->>'precio_x_kg_usd'),',','.')::NUMERIC(8,2)!=pp.precio_x_kg_usd AND pp.fyh_fin IS NULL;

    INSERT INTO proveedor_precio(insumo_x_proveedor_id,precio_x_kg_usd)
    SELECT (item->>'insumo_x_proveedor_id')::smallint,REPLACE((item->>'precio_x_kg_usd'),',','.')::NUMERIC(8,2)
    FROM jsonb_array_elements(json_data->'productos') AS item
    WHERE NOT EXISTS (SELECT 1 FROM proveedor_precio pp WHERE pp.insumo_x_proveedor_id =(item->>'insumo_x_proveedor_id')::smallint AND
    REPLACE((item->>'precio_x_kg_usd'),',','.')::NUMERIC(8,2)=pp.precio_x_kg_usd AND pp.fyh_fin IS NULL);

    INSERT INTO letra_compra (compra_id, numero_letra, monto_usd,fecha_emision,fecha_vencimiento,fecha_pago,estado)
    SELECT 
        new_compra_id,
        (item->>'numero_letra'),
        REPLACE((item->>'monto_usd'),',','.')::NUMERIC(12,2),
        (item->>'fecha_emision')::date,
        nullif((item->>'fecha_vencimiento'),'')::date,
        nullif((item->>'fecha_pago'),'')::date,
        (item->>'estado')::estado_letra_enum
    FROM jsonb_array_elements(json_data->'letras') AS item;

    RETURN QUERY SELECT 'Compra registrada';
    EXCEPTION
    WHEN OTHERS THEN
        -- Capture error information
        GET STACKED DIAGNOSTICS
            error_message = MESSAGE_TEXT,
            error_detail = PG_EXCEPTION_DETAIL,
            error_context = PG_EXCEPTION_CONTEXT;
        
        -- Log the error with the JSON payload
        INSERT INTO logs_api(function_name, user_id, params, error_message, error_detail, error_context)
        VALUES (
            'insert_compra',
            get_user_id(),
            json_data,
            error_message,
            error_detail,
            error_context
        );
        
        -- Return error message to caller
        RETURN QUERY SELECT CONCAT('Error: ', error_message);
END;
$$;


ALTER FUNCTION public.insert_compra(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insert_partida(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insert_partida(json_data jsonb) RETURNS TABLE(new_partida_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_partida_id INT;
BEGIN
    -- Insert the main 'partida' record using an alias for clarity
    INSERT INTO partida AS p (
        guia,
        fecha_entrega,
        prioridad_id,
        cliente_id,
        articulo_id,
        color_x_cliente_id,  
        rib,
        tenido_id,
        fibra,
        previo_id,
        malla,
        adicional_id,
        ancho,
        rendimiento,
        rollos,
        observacion
    )
    VALUES (
        json_data->>'guia',
        (json_data->>'fecha_entrega')::DATE,
        (json_data->>'prioridad_id')::SMALLINT,
        (json_data->>'cliente_id')::SMALLINT,
        (json_data->>'articulo_id')::SMALLINT,
        (json_data->>'color_x_cliente_id')::SMALLINT,  
        (json_data->>'rib')::SMALLINT,
        (json_data->>'tenido_id')::SMALLINT,
        (json_data->>'fibra')::SMALLINT,
        (json_data->>'previo_id')::SMALLINT,
        json_data->>'malla',
        (json_data->>'adicional_id')::SMALLINT,
        json_data->>'ancho',
        json_data->>'rendimiento',
        (json_data->>'rollos')::SMALLINT,
        json_data->>'observacion'
    )
    RETURNING p.id AS result_pk INTO new_partida_id;

    -- Bulk insert extras into partida_x_extra
    INSERT INTO partida_x_extra (partida_id, extra_id, cantidad)
    SELECT 
        new_partida_id,
        (item->>'extra_id')::SMALLINT,
        (item->>'cantidad')::SMALLINT
    FROM jsonb_array_elements(json_data->'extras') AS item;

    RETURN QUERY SELECT new_partida_id;
END;
$$;


ALTER FUNCTION public.insert_partida(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insert_solicitud_ingreso_compra_parcial(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insert_solicitud_ingreso_compra_parcial(json_data jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pk_entrada_inventario INT;
BEGIN
    -- Validate: productos array is not empty
    IF jsonb_array_length(json_data->'productos') = 0 THEN
        RETURN 'Error: La solicitud no contiene productos.';
    END IF;

    -- Validate: all insumos belong to the compra for this receta
    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(json_data->'productos')
            AS p(compra_x_insumo_id INT, cantidad NUMERIC)
        LEFT JOIN vw_compra_insumos v
            ON v.compra_x_insumo_id = p.compra_x_insumo_id
           AND v.compra_id = (json_data->>'compra_id')::INT
        WHERE v.compra_x_insumo_id IS NULL
    ) THEN
        RETURN 'Uno o más insumos no pertenecen a la compra';
    END IF;

    -- Validate: quantities do not exceed cantidad_restante
    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(json_data->'productos')
            AS p(compra_x_insumo_id INT, cantidad NUMERIC)
        JOIN vw_compra_insumos v
            ON v.compra_x_insumo_id = p.compra_x_insumo_id
        WHERE p.cantidad > v.cantidad_restante
          AND v.compra_id = (json_data->>'compra_id')::INT
    ) THEN
        RETURN 'Uno o más insumos exceden la cantidad restante por entregar';
    END IF;

    -- Insert the ingress request
    INSERT INTO entrada_inventario(motivo, fyh_entrada_real)
    VALUES ('compra',(json_data->>'fyh_entrada_real')::timestamptz)
    RETURNING id INTO v_pk_entrada_inventario;

    INSERT INTO entrada_inventario_detalle(
        entrada_inventario_id,
        compra_x_insumo_id,
        insumo_x_proveedor_id,
        cantidad_solicitada,
        estado
    )
    SELECT
        v_pk_entrada_inventario,
        id,
        insumo_x_proveedor_id,
        cantidad,
        'pendiente'
    FROM jsonb_to_recordset(json_data->'productos')
        AS p(id INT, insumo_x_proveedor_id INT, cantidad NUMERIC);

    UPDATE compra
    SET estado_ingreso = 'solicitado'
    WHERE id = (json_data->>'id')::INT;

    RETURN 'Ingreso parcial registrado correctamente. Solicitud N° ' || v_pk_entrada_inventario;
END;
$$;


ALTER FUNCTION public.insert_solicitud_ingreso_compra_parcial(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_catalogo_precio_v2(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_catalogo_precio_v2(json_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_fk_color_x_cliente INT;
    p_fk_tipo_articulo   INT;
    p_fk_tenido          INT;
    p_fibra              INT;
    p_fk_adicional       INT;
    p_precio_tenido      DECIMAL(5,2);
BEGIN
    -- Extraer valores del JSON
    p_fk_color_x_cliente := (json_data ->> 'p_fk_color_x_cliente')::INT;
    p_fk_tipo_articulo   := (json_data ->> 'p_fk_tipo_articulo')::INT;
    p_fk_tenido          := (json_data ->> 'p_fk_tenido')::INT;
    p_fibra              := (json_data ->> 'p_fibra')::INT;
    p_fk_adicional       := (json_data ->> 'p_fk_adicional')::INT;
    p_precio_tenido      := (json_data ->> 'p_precio_tenido')::DECIMAL(5,2);

    -- Luego aplicas la misma lógica que ya tenías
    UPDATE catalogo_precios
       SET activo = 0,
           fyh_fin = CURRENT_TIMESTAMP
     WHERE color_x_cliente_id = p_fk_color_x_cliente
       AND tipo_articulo_id        = p_fk_tipo_articulo
       AND tenido_id          = p_fk_tenido
       AND fibra              = p_fibra
       AND adicional_id       = p_fk_adicional
       AND activo = 1;

    INSERT INTO catalogo_precios (
         color_x_cliente_id, tipo_articulo_id, tenido_id, fibra, adicional_id,
         precio_tenido, fyh_cre, activo
    )
    VALUES (
         p_fk_color_x_cliente, p_fk_tipo_articulo, p_fk_tenido, p_fibra, p_fk_adicional,
         p_precio_tenido, CURRENT_TIMESTAMP, 1
    );
END;
$$;


ALTER FUNCTION public.insertar_catalogo_precio_v2(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_catalogo_precio_v2(integer, integer, integer, integer, integer, numeric)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_catalogo_precio_v2(p_fk_color_x_cliente integer, p_fk_articulo integer, p_fk_tenido integer, p_fibra integer, p_fk_adicional integer, p_precio_tenido numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 1. Desactivar el precio anterior si existe con la misma combinación
    UPDATE catalogo_precios
       SET activo = 0,
           fyh_fin = CURRENT_TIMESTAMP
     WHERE color_x_cliente_id = p_fk_color_x_cliente
       AND articulo_id  = p_fk_articulo
       AND tenido_id    = p_fk_tenido
       AND fibra        = p_fibra
       AND adicional_id = p_fk_adicional
       AND activo = 1;

    -- 2. Insertar el nuevo precio con estado activo
    INSERT INTO catalogo_precios (
         color_x_cliente_id, articulo_id, tenido_id, fibra, adicional_id,
         precio_tenido, fyh_cre, activo
    )
    VALUES (
         p_fk_color_x_cliente, p_fk_articulo, p_fk_tenido, p_fibra, p_fk_adicional,
         p_precio_tenido, CURRENT_TIMESTAMP, 1
    );

EXCEPTION WHEN others THEN
    RAISE NOTICE 'Error al insertar precio: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.insertar_catalogo_precio_v2(p_fk_color_x_cliente integer, p_fk_articulo integer, p_fk_tenido integer, p_fibra integer, p_fk_adicional integer, p_precio_tenido numeric) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_catalogo_precio_v2(integer, integer, integer, integer, integer, integer, numeric, numeric, numeric)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_catalogo_precio_v2(p_fk_color integer, p_fk_articulo integer, p_fk_cliente integer, p_fk_tenido integer, p_fibra integer, p_fk_adicional integer, p_precio_tenido numeric, p_precio_antipilling numeric, p_precio_final numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE catalogo_precios
       SET activo = 0,
           fyh_fin = CURRENT_TIMESTAMP
     WHERE color_id     = p_fk_color
       AND articulo_id  = p_fk_articulo
       AND cliente_id   = p_fk_cliente
       AND tenido_id    = p_fk_tenido
       AND fibra        = p_fibra
       AND adicional_id = p_fk_adicional
       AND activo = 1;

    INSERT INTO catalogo_precioS (
         color_id, articulo_id, cliente_id, tenido_id, fibra, adicional_id,
         precio_tenido, precio_antipilling, precio_final,
         fyh_cre, activo
    )
    VALUES (
         p_fk_color, p_fk_articulo, p_fk_cliente, p_fk_tenido, p_fibra, p_fk_adicional,
         p_precio_tenido, p_precio_antipilling, p_precio_final,
         CURRENT_TIMESTAMP, 1
    );
END;
$$;


ALTER FUNCTION public.insertar_catalogo_precio_v2(p_fk_color integer, p_fk_articulo integer, p_fk_cliente integer, p_fk_tenido integer, p_fibra integer, p_fk_adicional integer, p_precio_tenido numeric, p_precio_antipilling numeric, p_precio_final numeric) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_catalogo_precio_v2(integer, integer, integer, integer, integer, integer, numeric, numeric, numeric, numeric, numeric)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_catalogo_precio_v2(p_fk_color integer, p_fk_articulo integer, p_fk_cliente integer, p_fk_tenido integer, p_fibra integer, p_fk_adicional integer, p_precio_tenido numeric, p_precio_termofijado numeric, p_precio_perchado numeric, p_precio_antipilling numeric, p_precio_final numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE catalogo_precios
       SET activo = 0,
           fyh_fin = CURRENT_TIMESTAMP
     WHERE color_id     = p_fk_color
       AND articulo_id  = p_fk_articulo
       AND cliente_id   = p_fk_cliente
       AND tenido_id    = p_fk_tenido
       AND fibra        = p_fibra
       AND adicional_id = p_fk_adicional
       AND activo = 1;

    INSERT INTO catalogo_precioS (
         color_id, articulo_id, cliente_id, tenido_id, fibra, adicional_id,
         precio_tenido, precio_termofijado, precio_perchado, precio_antipilling, precio_final,
         fyh_cre, activo
    )
    VALUES (
         p_fk_color, p_fk_articulo, p_fk_cliente, p_fk_tenido, p_fibra, p_fk_adicional,
         p_precio_tenido, p_precio_termofijado, p_precio_perchado, p_precio_antipilling, p_precio_final,
         CURRENT_TIMESTAMP, 1
    );
END;
$$;


ALTER FUNCTION public.insertar_catalogo_precio_v2(p_fk_color integer, p_fk_articulo integer, p_fk_cliente integer, p_fk_tenido integer, p_fibra integer, p_fk_adicional integer, p_precio_tenido numeric, p_precio_termofijado numeric, p_precio_perchado numeric, p_precio_antipilling numeric, p_precio_final numeric) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_compactado(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_compactado(json_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$declare
    v_fk_partida      int;
    v_tipo            text;
    v_estado          text;
    v_rollos          int;
    v_rib             int;

    rollos_total      int;
    rib_total         int;

    rollos_usados     int := 0;
    rib_usados        int := 0;

    rollos_restantes  int;
    rib_restantes     int;
begin
    -- Extraer campos del JSON
    v_fk_partida := (json_data->>'partida_id')::int;
    v_tipo       := (json_data->>'tipo_proceso')::text;
    v_estado     := (json_data->>'estado')::text;
    v_rollos     := coalesce((json_data->>'rollos')::int, 0);
    v_rib        := coalesce((json_data->>'rib')::int, 0);

    -- Obtener totales reales desde la tabla PARTIDA
    select rollos, coalesce(rib,0) + coalesce(b.cantidad,0) as rib
    into rollos_total, rib_total
    from partida a 
    left join partida_x_extra b on a.id = b.partida_id
    where id = v_fk_partida;

    ---------------------------------------------------------
    -- VALIDACIÓN SOLO PARA PRODUCCIÓN + COMPACTADO
    ---------------------------------------------------------
    if v_tipo = 'Produccion' and v_estado = 'Compactado' then
        
        -- Sumar solo rollos buenos (no Observados)
        select 
            coalesce(sum(rollos), 0),
            coalesce(sum(rib), 0)
        into rollos_usados, rib_usados
        from compactado
        where partida_id = v_fk_partida
          and tipo_proceso = 'Produccion'
          and estado = 'Compactado';

        rollos_restantes := rollos_total - rollos_usados;
        rib_restantes    := rib_total - rib_usados;

        if v_rollos > rollos_restantes or v_rib > rib_restantes then
            raise exception 
                'No se puede insertar (Produccion-Compactado). Disponibles: % rollos / % rib',
                rollos_restantes, rib_restantes;
        end if;
    end if;

    ---------------------------------------------------------
    -- INSERT REAL
    ---------------------------------------------------------
    insert into compactado (
        partida_id,
        fecha,
        maquina_id,
        turno_id,
        tipo_proceso,
        estado,
        rollos,
        rib,
        hora_inicio,
        hora_fin,
        duracion
    )
    values (
        v_fk_partida,
        (json_data->>'fecha')::date,
        (json_data->>'maquina_id')::int,
        (json_data->>'turno_id')::int,
        v_tipo,
        v_estado,
        v_rollos,
        v_rib,
        (json_data->>'hora_inicio')::time,
        (json_data->>'hora_fin')::time,
        (json_data->>'duracion')::time
    );

    ---------------------------------------------------------
    -- RETORNO ÚTIL PARA FORMULARIO
    ---------------------------------------------------------
    return jsonb_build_object(
        'status', 'ok',
        'rollos_usados', rollos_usados + case when v_tipo = 'Produccion' and v_estado = 'Compactado' then v_rollos else 0 end,
        'rollos_totales', rollos_total,
        'rib_usados', rib_usados + case when v_tipo = 'Produccion' and v_estado = 'Compactado' then v_rib else 0 end,
        'rib_totales', rib_total
    );
end;$$;


ALTER FUNCTION public.insertar_compactado(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_despacho(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_despacho(json_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO despacho (
        partida_id,
        fecha_despacho,
        nfactura,
        precio_unit,
        rollos,
        rib
    )
    VALUES (
        (json_data->>'partida_id')::SMALLINT,
        (json_data->>'fecha_despacho')::date,
        (json_data->>'nfactura')::text,
        (json_data->>'precio_unit')::float,
        (json_data->>'rollos')::smallint,
        (json_data->>'rib')::smallint
    );
END;
$$;


ALTER FUNCTION public.insertar_despacho(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_devolucion(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_devolucion(json_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$begin
    insert into devolucion (
        partida_id,
        fecha_devolucion,
        guia_remision,
        rollos,
        rib,
        motivo,
        observacion
    )
    values (
        (json_data->>'partida_id')::int,
        (json_data->>'fecha_devolucion')::date,
        (json_data->>'guia_remision')::text,
        (json_data->>'rollos')::int,
        (json_data->>'rib')::int,
        (json_data->>'motivo')::text
        (json_data->>'observacion')::text
    );
end;$$;


ALTER FUNCTION public.insertar_devolucion(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_estado_observado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_estado_observado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  estado_insertar text := TG_ARGV[0];       -- argumento del trigger: 'Programado' o 'Reprocesado'
  fecha_registro  date := NEW.fecha;        -- fecha del registro insertado
BEGIN
  -- Busca si ya estaba observado antes o el mismo día
  IF EXISTS (
    SELECT 1
    FROM vw_observado_lab
    WHERE partida = NEW.partida_id
      AND fecha <= fecha_registro
  ) THEN
    -- Evita duplicados del mismo estado para la misma fecha
    IF NOT EXISTS (
      SELECT 1
      FROM observado_estados
      WHERE partida_id = NEW.partida_id
        AND estado = estado_insertar
        AND fecha = fecha_registro
    ) THEN
      INSERT INTO observado_estados (
        partida_id,
        estado,
        fecha
      ) VALUES (
        NEW.partida_id,
        estado_insertar,
        fecha_registro
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.insertar_estado_observado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_historial_al_crear()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_historial_al_crear() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO historial_estado_color (
        desarrollo_color_id,
        estado_desarrollo_color_id,
        fecha_estado,
        observaciones,
        usr_cre
    )
    VALUES (
        NEW.id,
        NEW.estado_desarrollo_color_id,
        NEW.fecha_ingreso,
        'Ingreso inicial del desarrollo',
        CURRENT_USER
    );
    RETURN NEW;
END; 
$$;


ALTER FUNCTION public.insertar_historial_al_crear() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_historial_estado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_historial_estado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Solo actúa si realmente cambió el estado
    IF NEW.estado_desarrollo_color_id IS DISTINCT FROM OLD.estado_desarrollo_color_id THEN
        INSERT INTO historial_estado_color (
            desarrollo_color_id,
            estado_desarrollo_color_id,
            fecha_estado,
            observaciones,
            usr_cre
        )
        VALUES (
            NEW.id,
            NEW.estado_desarrollo_color_id,
            CURRENT_DATE,
            'Cambio automático desde trigger',
            CURRENT_USER
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.insertar_historial_estado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_observado(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_observado(json_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$BEGIN
    INSERT INTO observado (
        partida_id,
        fecha,
        rollos,
        rib,
        motivo_observado_id,
        detalle,
        flg_elm
    )
    VALUES (
        (json_data->>'partida_id')::SMALLINT,
        (json_data->>'fecha')::date,
        (json_data->>'rollos')::smallint,
        (json_data->>'rib')::smallint,
        (json_data->>'motivo_observado_id')::int,
        (json_data->>'detalle')::text,
        (json_data->>'flg_elm')::int
    );
END;$$;


ALTER FUNCTION public.insertar_observado(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_parada_tintoreria(integer, integer, integer, timestamp without time zone, timestamp without time zone, text, text)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_parada_tintoreria(p_maquina_id integer, p_turno_id integer, p_motivo_id integer, p_fecha_inicio timestamp without time zone, p_fecha_fin timestamp without time zone DEFAULT NULL::timestamp without time zone, p_observacion text DEFAULT NULL::text, p_usuario text DEFAULT NULL::text) RETURNS TABLE(id_out integer, msj_out text)
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO parada_tintoreria (
      maquina_id, turno_id, motivo_id,
      fecha_inicio, fecha_fin, observacion, usuario
  )
  VALUES (
      p_maquina_id, p_turno_id, p_motivo_id,
      p_fecha_inicio, p_fecha_fin, p_observacion, p_usuario
  )
  RETURNING id, 'Parada registrada correctamente' INTO id_out, msj_out;
END;
$$;


ALTER FUNCTION public.insertar_parada_tintoreria(p_maquina_id integer, p_turno_id integer, p_motivo_id integer, p_fecha_inicio timestamp without time zone, p_fecha_fin timestamp without time zone, p_observacion text, p_usuario text) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_perchado(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_perchado(json_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_partida_id INT := (json_data->>'partida_id')::INT;
    rollos_nuevos INT := COALESCE((json_data->>'rollos')::INT, 0);
    articulo_text TEXT;
BEGIN
    -- Verificar que el artículo sea válido (contenga 'F Poly')
    SELECT articulo
      INTO articulo_text
    FROM vw_partidas_resumen
    WHERE partida = p_partida_id;

    IF articulo_text IS NULL THEN
        RAISE EXCEPTION 'Partida % no encontrada en la vista vw_partidas_resumen', p_partida_id;
    END IF;

    IF articulo_text NOT ILIKE '%F Poly%' THEN
        RAISE EXCEPTION 'Solo se permiten registros para artículos tipo "F Poly". Artículo encontrado: %', articulo_text;
    END IF;

    -- Insertar registro (sin validación de máximo total de rollos)
    INSERT INTO public.perchado (
        partida_id,
        fecha,
        turno_id,
        hora_inicio,
        hora_fin,
        duracion,
        rollos,
        pases
    )
    VALUES (
        p_partida_id,
        (json_data->>'fecha')::DATE,
        (json_data->>'turno_id')::SMALLINT,
        (json_data->>'hora_inicio')::TIME,
        (json_data->>'hora_fin')::TIME,
        (json_data->>'duracion')::TIME,
        rollos_nuevos,
        COALESCE((json_data->>'pases')::INT, 0)
    );
END;
$$;


ALTER FUNCTION public.insertar_perchado(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_produccion_tenido(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_produccion_tenido(datos jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  item jsonb;
  contador integer := 0;
begin
  for item in select * from jsonb_array_elements(datos)
  loop
    -- Inserta solo si no existe un registro con la misma partida_id y fecha
    if not exists (
      select 1 from produccion_tenido 
      where partida_id = (item->>'partida_id')::int 
        and fecha = (item->>'fecha')::date
    ) then
      insert into produccion_tenido (
        partida_id, fecha, maquina, tipo, hora_inicio, hora_fin, duracion,
        rollos, kilos, estado, estandar
      )
      values (
        (item->>'partida_id')::int,
        (item->>'fecha')::date,
        (item->>'maquina')::smallint,
        item->>'tipo',
        (item->>'hora_inicio')::time,
        (item->>'hora_fin')::time,
        (item->>'duracion')::interval,
        (item->>'rollos')::int,
        (item->>'kilos')::numeric,
        item->>'estado',
        (item->>'estandar')::time
      );
      contador := contador + 1;
    end if;
  end loop;
  return jsonb_build_object('insertados', contador);
end;
$$;


ALTER FUNCTION public.insertar_produccion_tenido(datos jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_produccion_tenido_avanzado(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_produccion_tenido_avanzado(datos jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  item jsonb;
  contador int := 0;
  duracion_real interval;
  estado_final varchar;
  rollos_previos numeric := 0;
  kilos_previos numeric := 0;
  rollos_final numeric;
  kilos_final numeric;
  es_complemento boolean := false;
  peso_por_rollo numeric := 0;

  suma_rollos numeric;
  suma_kilos numeric;
  max_rollos numeric;
  max_kilos numeric;
begin
  for item in select * from jsonb_array_elements(datos)
  loop
    estado_final := case when (item->>'hora_fin') is null then 'En Proceso Teñido' else 'Teñido' end;

    duracion_real :=
      case
        when estado_final = 'En Proceso Teñido' then
          case
            when (item->>'hora_inicio')::time >= time '07:00:00'
              then interval '24 hours' - ((item->>'hora_inicio')::time - time '07:00:00')
            else time '07:00:00' - (item->>'hora_inicio')::time
          end
        when (item->>'hora_fin')::time < (item->>'hora_inicio')::time
          then ((item->>'hora_fin')::time + interval '24 hours') - (item->>'hora_inicio')::time
        else (item->>'hora_fin')::time - (item->>'hora_inicio')::time
      end;

    if estado_final = 'Teñido'
    and (item->>'hora_inicio')::time = time '07:00'
    then
      select 
        coalesce(sum(a.rollos),0),
        coalesce(sum(a.kilos),0)
      into rollos_previos, kilos_previos
      from produccion_tenido a
      where a.partida_id = (item->>'partida_id')::int
        and a.tipo = item->>'tipo'
        and a.estado = 'En Proceso Teñido';

      if rollos_previos > 0 then
        es_complemento := true;
      end if;
    end if;

    rollos_final := (item->>'rollos')::numeric;
    kilos_final  := (item->>'kilos')::numeric;

    if estado_final = 'En Proceso Teñido' then
      rollos_final := round(
        rollos_final * EXTRACT(EPOCH FROM duracion_real) / EXTRACT(EPOCH FROM (item->>'duracion_estandar')::interval)
      );

      if (item->>'rollos')::numeric > 0 then
        peso_por_rollo := (item->>'kilos')::numeric / (item->>'rollos')::numeric;
      else
        peso_por_rollo := 0;
      end if;

      kilos_final := round(peso_por_rollo * rollos_final, 2);

    elsif es_complemento then
      rollos_final := greatest(0, rollos_final - rollos_previos);
      kilos_final  := greatest(0, kilos_final  - kilos_previos);
    end if;

    if item->>'tipo' = 'Teñido' then
      select 
        coalesce(sum(rollos), 0),
        coalesce(sum(kilos), 0)
      into suma_rollos, suma_kilos
      from produccion_tenido
      where partida_id = (item->>'partida_id')::int and tipo = 'Teñido';

      suma_rollos := suma_rollos + rollos_final;
      suma_kilos := suma_kilos + kilos_final;

      select rollos, peso
      into max_rollos, max_kilos
      from vw_partidas_resumen
      where partida = (item->>'partida_id')::int;

      if suma_rollos > max_rollos or suma_kilos > max_kilos then
        raise exception 'Error: El total de rollos o kilos supera lo registrado en partidas resumen. Partida %, Rollos %/% - Kilos %/%',
          (item->>'partida_id')::int,
          suma_rollos, max_rollos,
          suma_kilos, max_kilos;
      end if;
    end if;

    insert into produccion_tenido (
      partida_id, fecha, maquina, tipo,
      hora_inicio, hora_fin, duracion, estandar,
      rollos, kilos, estado
    )
    values (
      (item->>'partida_id')::int,
      (item->>'fecha')::date,
      (item->>'maquina')::int,
      item->>'tipo',
      (item->>'hora_inicio')::time,
      nullif(item->>'hora_fin','')::time,
      duracion_real,
      (item->>'duracion_estandar')::interval,
      rollos_final,
      kilos_final,
      estado_final
    );

    contador := contador + 1;
  end loop;

  return jsonb_build_object(
    'insertados', contador,
    'estado', estado_final,
    'es_complemento', es_complemento,
    'rollos_usados_previo', rollos_previos,
    'rollos_insertados', rollos_final,
    'kilos_insertados', kilos_final
  );
end;
$$;


ALTER FUNCTION public.insertar_produccion_tenido_avanzado(datos jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertar_termofijado(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertar_termofijado(json_data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$DECLARE
  p_partida_id INT;
  total_rollos_actual INT;
  max_rollos INT;
  articulo_text TEXT;
BEGIN
  p_partida_id := (json_data->>'partida_id')::INT;

  -- Obtener el artículo y rollos actuales
  SELECT rollos, articulo INTO max_rollos, articulo_text
  FROM vw_partidas_resumen
  WHERE partida = p_partida_id;

  IF articulo_text IS NULL THEN
    RAISE EXCEPTION 'Partida % no encontrada en vw_partidas_resumen', p_partida_id;
  END IF;

  -- Validar artículo permitido
  IF articulo_text ILIKE '%Lycra%' OR articulo_text ILIKE '%J Poly%'  OR articulo_text ILIKE '%French Terry%' THEN
    -- Calcular total rollos ya registrados
    SELECT COALESCE(SUM(rollos), 0)
    INTO total_rollos_actual
    FROM termofijado
    WHERE partida_id = p_partida_id;

    IF total_rollos_actual + (json_data->>'rollos')::INT > max_rollos THEN
      RAISE EXCEPTION 'No se puede registrar. Rollos exceden el total de la partida (actual: %, nuevos: %, máximo: %)',
        total_rollos_actual, (json_data->>'rollos')::INT, max_rollos;
    END IF;

    -- Insertar registro
    INSERT INTO termofijado (
        partida_id,
        fecha,
        turno_id,
        hora_inicio,
        hora_fin,
        duracion,
        rollos
    ) VALUES (
        p_partida_id,
        (json_data->>'fecha')::DATE,
        (json_data->>'turno_id')::SMALLINT,
        (json_data->>'hora_inicio')::TIME,
        (json_data->>'hora_fin')::TIME,
        (json_data->>'duracion')::TIME,
        (json_data->>'rollos')::INT
    );
  ELSE
    RAISE EXCEPTION 'El artículo "%" no está permitido para termofijado. Solo Lycra o J Poly o French Terry.', articulo_text;
  END IF;
END;$$;


ALTER FUNCTION public.insertar_termofijado(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertarpartidahc(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertarpartidahc(json_data jsonb) RETURNS TABLE(new_partida_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_partida_id INT;
BEGIN
    -- Insertar el registro principal en 'partida' utilizando un alias para mayor claridad
    INSERT INTO partida AS p (
        guia,
        fecha_entrega,
        prioridad_id,
        cliente_id,
        articulo_id,
        color_x_cliente_id, 
        rib,
        tenido_id,
        fibra,
        previo_id,
        malla,
        adicional_id,
        ancho,
        rendimiento,
        rollos
    )
    VALUES (
        json_data->>'guia',
        (json_data->>'fecha_entrega')::DATE,
        (json_data->>'prioridad_id')::SMALLINT,
        (json_data->>'cliente_id')::SMALLINT,
        (json_data->>'articulo_id')::SMALLINT,
        (json_data->>'color_x_cliente_id')::SMALLINT,  -- Cambio realizado aquí
        (json_data->>'rib')::SMALLINT,
        (json_data->>'tenido_id')::SMALLINT,
        (json_data->>'fibra')::SMALLINT,
        (json_data->>'previo_id')::SMALLINT,
        json_data->>'malla',
        (json_data->>'adicional_id')::SMALLINT,
        json_data->>'ancho',
        json_data->>'rendimiento',
        (json_data->>'rollos')::SMALLINT
    )
    RETURNING p.id AS result_pk INTO new_partida_id;

    -- Inserción masiva de extras en 'partida_x_extra'
    INSERT INTO partida_x_extra (partida_id, extra_id, cantidad)
    SELECT 
        new_partida_id,
        (item->>'extra_id')::SMALLINT,
        (item->>'cantidad')::SMALLINT
    FROM jsonb_array_elements(json_data->'extras') AS item;

    RETURN QUERY SELECT new_partida_id;
END;
$$;


ALTER FUNCTION public.insertarpartidahc(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.insertarreceta(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.insertarreceta(json_data jsonb) RETURNS TABLE(new_receta_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Mensaje de depuración para verificar los valores
    RAISE NOTICE 'color_id: %, articulo_id: %, cliente_id: %, tenido_id: %, fibra: %',
        (json_data->>'color_id')::SMALLINT,
        (json_data->>'articulo_id')::SMALLINT,
        (json_data->>'cliente_id')::SMALLINT,
        (json_data->>'tenido_id')::INT,
        (json_data->>'fibra')::SMALLINT;

    INSERT INTO receta (
        color_id,
        articulo_id,
        cliente_id,
        tenido_id,
        fibra
    )
    VALUES (
        (json_data->>'color_id')::SMALLINT,
        (json_data->>'articulo_id')::SMALLINT,
        (json_data->>'cliente_id')::SMALLINT,
        (json_data->>'tenido_id')::SMALLINT,
        (json_data->>'fibra')::SMALLINT
    )
    RETURNING id INTO new_receta_id;

    RETURN QUERY SELECT new_receta_id;
END;
$$;


ALTER FUNCTION public.insertarreceta(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.inventario_movimientos_diario(integer, timestamp with time zone, timestamp with time zone)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.inventario_movimientos_diario(p_insumo_id integer, p_fyh_desde timestamp with time zone, p_fyh_hasta timestamp with time zone) RETURNS jsonb
    LANGUAGE sql
    AS $$
WITH movimientos AS (
    -- Ingress = positive
    SELECT
        inv.fyh_ingreso::date AS fecha,
        COALESCE(inv.insumo_id, ip.insumo_id) AS insumo_id,
        SUM(inv.cantidad) AS delta
    FROM inventario inv
    LEFT JOIN vw_insumos_proveedor ip
        ON inv.insumo_id IS NULL
       AND ip.insumo_x_proveedor_id = inv.insumo_x_proveedor_id
    WHERE (p_insumo_id IS NULL OR COALESCE(inv.insumo_id, ip.insumo_id) = p_insumo_id) 
      AND fyh_ingreso < p_fyh_hasta
    GROUP BY
        inv.fyh_ingreso::date,
        COALESCE(inv.insumo_id, ip.insumo_id)

    UNION ALL

    -- Egress = negative
    SELECT
        sidx.fecha::date AS fecha,
        sid.insumo_id,
        -SUM(sidx.cantidad) AS delta
    FROM salida_inventario_detalle_x_stock sidx
    JOIN salida_inventario_detalle sid
        ON sid.id = sidx.salida_inventario_detalle_id
    WHERE (p_insumo_id IS NULL OR sid.insumo_id = p_insumo_id) 
      AND sidx.fecha < p_fyh_hasta
    GROUP BY
        sidx.fecha::date,
        sid.insumo_id
), diarios AS (
    SELECT
        fecha,
        insumo_id,
        SUM(delta) AS variacion_dia,
        SUM(CASE WHEN delta > 0 THEN delta ELSE 0 END) AS ingresos,
        SUM(CASE WHEN delta < 0 THEN delta ELSE 0 END) AS egresos
    FROM movimientos
    GROUP BY fecha, insumo_id
)
SELECT jsonb_agg(
    to_jsonb(t) || jsonb_build_object(
        'movimientos', 
        get_insumo_movimientos_rango(
            t.insumo_id, 
            (t.fecha - INTERVAL '1 day'), 
            (t.fecha + INTERVAL '1 day')
        )
    )
)
FROM (
    SELECT
        fecha,
        insumo_id,
        i.insumo,
        ingresos,
        egresos,
        variacion_dia,
        SUM(variacion_dia) OVER (
            PARTITION BY insumo_id
            ORDER BY fecha
        ) AS stock_actual
    FROM diarios
    LEFT JOIN insumo i ON i.id = diarios.insumo_id
    ORDER BY insumo_id, fecha
) t;
$$;


ALTER FUNCTION public.inventario_movimientos_diario(p_insumo_id integer, p_fyh_desde timestamp with time zone, p_fyh_hasta timestamp with time zone) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.observado_ai_to_estados()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.observado_ai_to_estados() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO observado_estados (partida_id, fecha, estado)
  VALUES (NEW.partida_id, NEW.fecha, 'Pendiente');
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.observado_ai_to_estados() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.procesar_ingreso_inventario(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.procesar_ingreso_inventario(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    --SElECT * FROM json_debug_log
    --INSERT INTO json_debug_log (received_json) VALUES (json_data);
     IF(SELECT flg_recibido FROM compra WHERE id=(json_data->>'id')::int) THEN
        RETURN QUERY 
    SELECT 
        'La compra ya ha sido marcada como recibida';
        return;
    END IF;
    UPDATE compra
    SET
    flg_recibido=true,
    fyh_recepcion=(json_data->>'fyh_recepcion')::timestamp
    WHERE id=(json_data->>'id')::int;

    INSERT INTO inventario(compra_x_insumo_id,cantidad,fyh_ingreso)
    SELECT id,cantidad, (json_data->>'fyh_recepcion')::timestamp
    FROM compra_x_insumo
    WHERE compra_id=(json_data->>'id')::int;


    RETURN QUERY 
    SELECT 
        'Recepcion y nuevo inventario registrados exitosamente';
END;
$$;


ALTER FUNCTION public.procesar_ingreso_inventario(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.rechazar_salida_inventario(integer, text)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.rechazar_salida_inventario(salida_id integer, obs text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if exit exists and is in pending status
    IF NOT EXISTS (
        SELECT 1 FROM salida_inventario 
        WHERE id = salida_id AND estado = 'pendiente'
    ) THEN
        RETURN jsonb_build_object(
            'error', true,
            'mensaje', 'Error: La salida no existe o ya fue revisada.'
        );
    END IF;
    
    -- Update main exit record
    UPDATE salida_inventario 
    SET 
        estado = 'rechazado',
        fyh_revision = current_timestamp,
        usr_revisa = get_user_id(),
        observacion=obs
    WHERE id = salida_id;
    
    -- Update all details
    UPDATE salida_inventario_detalle 
    SET estado = 'rechazado'
    WHERE salida_inventario_id = salida_id;
    
    RETURN jsonb_build_object(
        'error', false,
        'mensaje', format('Salida #%s rechazada exitosamente', salida_id)
    );
END;
$$;


ALTER FUNCTION public.rechazar_salida_inventario(salida_id integer, obs text) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.reject_full_entrada_inventario(integer, text)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.reject_full_entrada_inventario(entrada_id integer, obs text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Ensure the entrada is still pending
    IF (SELECT estado FROM entrada_inventario WHERE id = entrada_id)!= 'pendiente'::estado_entrada_inventario_enum THEN
        RETURN 'Error: El ingreso ya fue aprobado o rechazado.';
    END IF;

    -- Reject all lines: don't set observación per detail
    UPDATE entrada_inventario_detalle
    SET 
        cantidad_recibida = 0,
        estado = 'rechazado'::estado_entrada_inventario_enum
    WHERE entrada_inventario_id = entrada_id;

    -- Update main entrada state + reason
    UPDATE entrada_inventario ei
    SET 
        estado = 'rechazado'::estado_entrada_inventario_enum,
        fyh_revision = CURRENT_TIMESTAMP,
        usr_revisa = get_user_id(),
        observacion = obs
    WHERE id = entrada_id;

    RETURN format('Ingreso #%s rechazado completamente.', entrada_id);
END;
$$;


ALTER FUNCTION public.reject_full_entrada_inventario(entrada_id integer, obs text) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.reordenar_orden_receta(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.reordenar_orden_receta(_fk_receta integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  r record;
  i int := 1;
begin
  -- ✅ Eliminar si ya existe de ejecuciones anteriores
  drop table if exists tmp_reordenar;

  -- Paso 1: capturar orden actual
  create temp table tmp_reordenar on commit drop as
  select 'paso' as tipo, ctid as ref, orden as orden_original
  from receta_x_paso where receta_id = _fk_receta
  union all
  select 'insumo' as tipo, ctid as ref, orden as orden_original
  from receta_x_insumo where receta_id = _fk_receta;

  -- Paso 2: aplicar nuevo orden
  for r in (select * from tmp_reordenar order by orden_original)
  loop
    if r.tipo = 'paso' then
      update receta_x_paso set orden = i where ctid = r.ref;
    else
      update receta_x_insumo set orden = i where ctid = r.ref;
    end if;
    i := i + 1;
  end loop;
end;
$$;


ALTER FUNCTION public.reordenar_orden_receta(_fk_receta integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, timestamp with time zone, integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario(motivo public.motivo_salida_inventario_enum, p_partida_id integer, detalles jsonb, p_receta_id integer DEFAULT NULL::integer, p_tipo_receta_id integer DEFAULT NULL::integer, p_maquina_id integer DEFAULT NULL::integer, p_fyh_salida_real timestamp with time zone DEFAULT NULL::timestamp with time zone, p_rollos integer DEFAULT NULL::integer, p_rib integer DEFAULT NULL::integer, p_relacion_bano integer DEFAULT NULL::integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
    id_receta_x_partida INTEGER;
BEGIN
    -- Validar motivo/partida coherencia
    IF motivo IN ('receta','matizado') AND p_partida_id IS NULL THEN
        RETURN 'Error: El motivo "receta" requiere una partida.';
    ELSIF motivo NOT IN ('receta','matizado') AND p_partida_id IS NOT NULL THEN
        RETURN 'Error: Solo "receta" y "matizado" permiten especificar partida.';
    END IF;
    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario', get_user_id(),to_jsonb(ROW(motivo, p_partida_id, detalles, p_receta_id, p_tipo_receta_id, p_maquina_id));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    --INSERTAR EJECUCION
    IF motivo='receta' THEN
    INSERT INTO partida_x_recetas (fecha,partida_id,receta_id,tipo_receta_id,maquina_id,rollos,rib,relacion_bano)
    SELECT current_date,p_partida_id,p_receta_id,p_tipo_receta_id, p_maquina_id,p_rollos,p_rib,p_relacion_bano
    RETURNING id INTO id_receta_x_partida;
    END IF;

    IF motivo='matizado' THEN
    SELECT id INTO id_receta_x_partida FROM partida_x_recetas WHERE receta_id=p_receta_id and partida_id=p_partida_id;
    END IF;
    IF motivo='matizado' AND id_receta_x_partida IS NULL THEN RETURN 'Error: no se encontro ejecucion de la receta para la partida'; END IF;
    -- Insertar cabecera
    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita,fyh_salida_real)
    VALUES (motivo, id_receta_x_partida, get_user_id(),p_fyh_salida_real)
    RETURNING id INTO salida_id;

-- Insertar detalles
INSERT INTO salida_inventario_detalle(
        salida_inventario_id,
        cantidad_solicitada,
        insumo_id
    )
SELECT
        salida_id,
        (elm->>'cantidad_requerida')::NUMERIC(12,5)
        * (
            CASE 
                WHEN motivo IN ('receta','matizado') AND (elm->>'insumo_id')::INT = 13 
                THEN 1.0/6.0 
                ELSE 1.0 
            END
          ),
        (elm->>'insumo_id')::INT
FROM jsonb_array_elements(detalles) AS elm;
PERFORM aprobar_salida_inventario_total(salida_id);
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario(motivo public.motivo_salida_inventario_enum, p_partida_id integer, detalles jsonb, p_receta_id integer, p_tipo_receta_id integer, p_maquina_id integer, p_fyh_salida_real timestamp with time zone, p_rollos integer, p_rib integer, p_relacion_bano integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_2(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_2(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
    id_receta_x_partida INTEGER;
BEGIN

    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario_2', get_user_id(),to_jsonb(ROW(motivo, partida_id, detalles, receta_id, tipo_receta_id, maquina_id));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita)
    VALUES (motivo, id_receta_x_partida, get_user_id())
    RETURNING id INTO salida_id;


    -- Insertar detalles
    INSERT INTO salida_inventario_detalle(
            salida_inventario_id,
            cantidad_solicitada,
            insumo_id
        )
    SELECT
            salida_id,
            (elm->>'cantidad_requerida')::NUMERIC(12,5)
            * (CASE WHEN motivo IN ('receta','matizado') AND (elm->>'insumo_id')=13 THEN 1.0/6.0 ELSE 1.0 END)
            ,
            (elm->>'insumo_id')::INTEGER
    FROM jsonb_array_elements(detalles) as elm;
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_2(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer, tipo_receta_id integer, maquina_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_3(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_3(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer, id_receta_x_partida integer DEFAULT NULL::integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
BEGIN

    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario_2', get_user_id(),to_jsonb(ROW(motivo, partida_id, detalles, receta_id, tipo_receta_id, maquina_id));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita)
    VALUES (motivo, id_receta_x_partida, get_user_id())
    RETURNING id INTO salida_id;


    -- Insertar detalles
    INSERT INTO salida_inventario_detalle(
            salida_inventario_id,
            cantidad_solicitada,
            insumo_id
        )
    SELECT
            salida_id,
            (elm->>'cantidad_requerida')::NUMERIC(12,5)
            * (CASE WHEN motivo IN ('receta','matizado') AND (elm->>'insumo_id')::integer=13 THEN 1.0/6.0 ELSE 1.0 END)
            ,
            (elm->>'insumo_id')::INTEGER
    FROM jsonb_array_elements(detalles) as elm;
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_3(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer, tipo_receta_id integer, maquina_id integer, id_receta_x_partida integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_l(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, date)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_l(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer, fecha date DEFAULT NULL::date) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
    id_receta_x_partida INTEGER;
BEGIN
    -- Validar motivo/partida coherencia
    IF motivo IN ('receta','matizado') AND partida_id IS NULL THEN
        RETURN 'Error: El motivo "receta" requiere una partida.';
    ELSIF motivo NOT IN ('receta','matizado') AND partida_id IS NOT NULL THEN
        RETURN 'Error: Solo "receta" y "matizado" permiten especificar partida.';
    END IF;
    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario', get_user_id(),to_jsonb(ROW(motivo, partida_id, detalles, receta_id, tipo_receta_id, maquina_id));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    --INSERTAR EJECUCION
    IF motivo='receta' THEN
    INSERT INTO partida_x_recetas (fecha,partida_id,receta_id,tipo_receta_id,maquina_id)
    SELECT current_date,partida_id,receta_id,tipo_receta_id, maquina_id
    RETURNING id INTO id_receta_x_partida;
    END IF;

    IF motivo='matizado' THEN
    SELECT id INTO id_receta_x_partida FROM partida_x_recetas WHERE receta_id=receta_id and partida_id=partida_id;
    END IF;
    IF motivo='lavado maquina' THEN
    INSERT INTO lavado_maquina(fecha,receta_lavado_mq_id,maquina_id)
    SELECT fecha,receta_id,maquina_id;
    END IF;
    IF motivo='matizado' AND id_receta_x_partida IS NULL THEN RETURN 'Error: no se encontro ejecucion de la receta para la partida'; END IF;
    -- Insertar cabecera
    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita,fecha_salida)
    VALUES (motivo, id_receta_x_partida, get_user_id(),fecha)
    RETURNING id INTO salida_id;

-- Insertar detalles
INSERT INTO salida_inventario_detalle(
        salida_inventario_id,
        cantidad_solicitada,
        insumo_id
    )
SELECT
        salida_id,
        (elm->>'cantidad_requerida')::NUMERIC(12,5)
        * (
            CASE 
                WHEN motivo IN ('receta','matizado') AND (elm->>'insumo_id')::INT = 13 
                THEN 1.0/6.0 
                ELSE 1.0 
            END
          ),
        (elm->>'insumo_id')::INT
FROM jsonb_array_elements(detalles) AS elm;
PERFORM aprobar_salida_inventario_total(salida_id);
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_l(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer, tipo_receta_id integer, maquina_id integer, fecha date) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_l(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, date, timestamp with time zone)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_l(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer, fecha date DEFAULT NULL::date, p_fyh_salida_real timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
    id_receta_x_partida INTEGER;
BEGIN
    -- Validar motivo/partida coherencia
    IF motivo IN ('receta','matizado') AND partida_id IS NULL THEN
        RETURN 'Error: El motivo "receta" requiere una partida.';
    ELSIF motivo NOT IN ('receta','matizado') AND partida_id IS NOT NULL THEN
        RETURN 'Error: Solo "receta" y "matizado" permiten especificar partida.';
    END IF;
    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario', get_user_id(),to_jsonb(ROW(motivo, partida_id, detalles, receta_id, tipo_receta_id, maquina_id));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    --INSERTAR EJECUCION
    IF motivo='receta' THEN
    INSERT INTO partida_x_recetas (fecha,partida_id,receta_id,tipo_receta_id,maquina_id)
    SELECT current_date,partida_id,receta_id,tipo_receta_id, maquina_id
    RETURNING id INTO id_receta_x_partida;
    END IF;

    IF motivo='matizado' THEN
    SELECT id INTO id_receta_x_partida FROM partida_x_recetas WHERE receta_id=receta_id and partida_id=partida_id;
    END IF;
    IF motivo='lavado maquina' THEN
    INSERT INTO lavado_maquina(fecha,receta_lavado_mq_id,maquina_id)
    SELECT fecha,receta_id,maquina_id;
    END IF;
    IF motivo='matizado' AND id_receta_x_partida IS NULL THEN RETURN 'Error: no se encontro ejecucion de la receta para la partida'; END IF;
    -- Insertar cabecera
    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita,fecha_salida,fyh_salida_real)
    VALUES (motivo, id_receta_x_partida, get_user_id(),fecha,p_fyh_salida_real)
    RETURNING id INTO salida_id;

-- Insertar detalles
INSERT INTO salida_inventario_detalle(
        salida_inventario_id,
        cantidad_solicitada,
        insumo_id
    )
SELECT
        salida_id,
        (elm->>'cantidad_requerida')::NUMERIC(12,5)
        * (
            CASE 
                WHEN motivo IN ('receta','matizado') AND (elm->>'insumo_id')::INT = 13 
                THEN 1.0/6.0 
                ELSE 1.0 
            END
          ),
        (elm->>'insumo_id')::INT
FROM jsonb_array_elements(detalles) AS elm;
PERFORM aprobar_salida_inventario_total(salida_id);
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_l(motivo public.motivo_salida_inventario_enum, partida_id integer, detalles jsonb, receta_id integer, tipo_receta_id integer, maquina_id integer, fecha date, p_fyh_salida_real timestamp with time zone) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_lavado_maquina(integer, integer, date)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_lavado_maquina(id_receta_lavado integer, maquina_id integer, fecha date) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    pasos JSONB;
    data JSONB;
BEGIN
    -- Call the function once and keep full JSON
    SELECT get_lavado_maquina_detalles(id_receta_lavado)
    INTO data;

    -- Aggregate pasos
    SELECT jsonb_agg(
        jsonb_build_object(
            'insumo_id', insumo_id,
            'cantidad_requerida', cantidad
        )
    )
    INTO pasos
    FROM (
        SELECT 
            (elem->>'fk')::int AS insumo_id,
            SUM(((elem->>'cantidad')::numeric)::numeric(12,4)) AS cantidad
        FROM jsonb_array_elements(data->'pasos') AS elem
        WHERE (elem->>'tipo')::int = 2
        GROUP BY (elem->>'fk')::int
    ) grouped;
    
-- Pass both id_receta and pasos forward
    RETURN solicitar_salida_inventario_l('lavado maquina', null, pasos, id_receta_lavado,null, maquina_id,fecha);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_lavado_maquina(id_receta_lavado integer, maquina_id integer, fecha date) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_lavado_maquina(integer, integer, date, timestamp with time zone)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_lavado_maquina(id_receta_lavado integer, maquina_id integer, fecha date, p_fyh_salida_real timestamp with time zone) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    pasos JSONB;
    data JSONB;
BEGIN
    -- Call the function once and keep full JSON
    SELECT get_lavado_maquina_detalles(id_receta_lavado)
    INTO data;

    -- Aggregate pasos
    SELECT jsonb_agg(
        jsonb_build_object(
            'insumo_id', insumo_id,
            'cantidad_requerida', cantidad
        )
    )
    INTO pasos
    FROM (
        SELECT 
            (elem->>'fk')::int AS insumo_id,
            SUM(((elem->>'cantidad')::numeric)::numeric(12,4)) AS cantidad
        FROM jsonb_array_elements(data->'pasos') AS elem
        WHERE (elem->>'tipo')::int = 2
        GROUP BY (elem->>'fk')::int
    ) grouped;
    
-- Pass both id_receta and pasos forward
    RETURN solicitar_salida_inventario_l('lavado maquina', null, pasos, id_receta_lavado,null, maquina_id,fecha,p_fyh_salida_real);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_lavado_maquina(id_receta_lavado integer, maquina_id integer, fecha date, p_fyh_salida_real timestamp with time zone) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_matizado(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, integer, date)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_matizado(motivo public.motivo_salida_inventario_enum, p_partida_id integer, detalles jsonb, p_receta_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer, turno_id integer DEFAULT NULL::integer, fecha date DEFAULT NULL::date) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
    id_receta_x_partida INTEGER;
BEGIN
    -- Validar motivo/partida coherencia
    IF motivo IN ('receta','matizado','lavado','ajuste receta','desmontado') AND p_partida_id IS NULL THEN
        RETURN 'Error: El motivo "receta" requiere una partida.';
    ELSIF motivo NOT IN ('receta','matizado','lavado','ajuste receta','desmontado') AND p_partida_id IS NOT NULL THEN
        RETURN 'Error: Solo "receta" y "matizado" permiten especificar partida.';
    END IF;
	IF motivo='matizado' AND (turno_id IS NULL OR fecha IS NULL) THEN RETURN 'Error: Información incompleta para registrar matizado'; END IF;
    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario', get_user_id(),to_jsonb(ROW(motivo, p_partida_id, detalles, p_receta_id, tipo_receta_id, maquina_id, turno_id, fecha));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    --INSERTAR EJECUCION
    IF motivo='receta' THEN
    INSERT INTO partida_x_recetas (fecha,partida_id,receta_id,tipo_receta_id,maquina_id)
    SELECT current_date,p_partida_id,p_receta_id,tipo_receta_id, maquina_id
    RETURNING id INTO id_receta_x_partida;
    END IF;

    IF motivo IN ('matizado','lavado','ajuste receta','desmontado') THEN
    SELECT id INTO id_receta_x_partida FROM partida_x_recetas WHERE receta_id=p_receta_id and partida_id=p_partida_id;
    END IF;
    IF motivo IN ('matizado','lavado','ajuste receta','desmontado') AND id_receta_x_partida IS NULL THEN RETURN 'Error: no se encontro ejecucion de la receta para la partida'; END IF;
    -- Insertar cabecera
    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita)
    VALUES (motivo, id_receta_x_partida, get_user_id())
    RETURNING id INTO salida_id;
	if motivo='matizado' THEN
	INSERT INTO matizado (fecha,insumo_id,cantidad,partida_id,medida,turno_id)
	SELECT fecha,(elm->>'insumo_id')::INTEGER,(elm->>'cantidad_requerida')::NUMERIC(12,5),p_partida_id,'kg',turno_id
	FROM jsonb_array_elements(detalles) as elm;
	END IF;

-- Insertar detalles
INSERT INTO salida_inventario_detalle(
        salida_inventario_id,
        cantidad_solicitada,
        insumo_id
    )
SELECT
        salida_id,
        (elm->>'cantidad_requerida')::NUMERIC(12,5)
        * (
            CASE 
                WHEN  motivo IN ('receta','matizado') AND (elm->>'insumo_id')::INT = 13 
                THEN 1.0/6.0 
                ELSE 1.0 
            END
          ),
        (elm->>'insumo_id')::INT
FROM jsonb_array_elements(detalles) AS elm;
PERFORM aprobar_salida_inventario_total(salida_id);
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_matizado(motivo public.motivo_salida_inventario_enum, p_partida_id integer, detalles jsonb, p_receta_id integer, tipo_receta_id integer, maquina_id integer, turno_id integer, fecha date) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_matizado(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, integer, date, timestamp with time zone)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_matizado(motivo public.motivo_salida_inventario_enum, p_partida_id integer, detalles jsonb, p_receta_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer, turno_id integer DEFAULT NULL::integer, fecha date DEFAULT NULL::date, p_fyh_salida_real timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    salida_id INTEGER;
    item JSONB;
    detalle_id INTEGER;
    violacion RECORD;
    error_message TEXT;
    id_receta_x_partida INTEGER;
BEGIN
    -- Validar motivo/partida coherencia
    IF motivo IN ('receta','matizado','lavado','ajuste receta','desmontado') AND p_partida_id IS NULL THEN
        RETURN 'Error: El motivo "receta" requiere una partida.';
    ELSIF motivo NOT IN ('receta','matizado','lavado','ajuste receta','desmontado') AND p_partida_id IS NOT NULL THEN
        RETURN 'Error: Solo "receta" y "matizado" permiten especificar partida.';
    END IF;
	IF motivo='matizado' AND (turno_id IS NULL OR fecha IS NULL) THEN RETURN 'Error: Información incompleta para registrar matizado'; END IF;
    INSERT into logs_api(function_name,user_id,params)
    SELECT 'solicitar_salida_inventario', get_user_id(),to_jsonb(ROW(motivo, p_partida_id, detalles, p_receta_id, tipo_receta_id, maquina_id, turno_id, fecha));
    SELECT 
    string_agg(
        format('Insumo "%s" requiere %s pero solo hay %s disponible',
               ins.insumo,
               (elm->>'cantidad_requerida')::NUMERIC(12,5),
               COALESCE(ixs.cantidad, 0)
        ),
        E';\n'
    )
    INTO error_message
    FROM jsonb_array_elements(detalles) AS elm
    LEFT JOIN insumo ins ON ins.id = (elm->>'insumo_id')::INTEGER
    LEFT JOIN vw_inventario_x_insumo ixs ON ixs.insumo_id = (elm->>'insumo_id')::INTEGER
    WHERE (elm->>'cantidad_requerida')::NUMERIC(12,5) > COALESCE(ixs.cantidad, 0);

    IF error_message IS NOT NULL THEN
        RETURN 'Error: ' || error_message;
    END IF;

    --INSERTAR EJECUCION
    IF motivo='receta' THEN
    INSERT INTO partida_x_recetas (fecha,partida_id,receta_id,tipo_receta_id,maquina_id)
    SELECT current_date,p_partida_id,p_receta_id,tipo_receta_id, maquina_id
    RETURNING id INTO id_receta_x_partida;
    END IF;

    IF motivo IN ('matizado','lavado','ajuste receta','desmontado') THEN
    SELECT id INTO id_receta_x_partida FROM partida_x_recetas WHERE receta_id=p_receta_id and partida_id=p_partida_id;
    END IF;
    IF motivo IN ('matizado','lavado','ajuste receta','desmontado') AND id_receta_x_partida IS NULL THEN RETURN 'Error: no se encontro ejecucion de la receta para la partida'; END IF;
    -- Insertar cabecera
    INSERT INTO salida_inventario (motivo, partida_x_recetas_id, usr_solicita,fecha_salida,fyh_salida_real)
    VALUES (motivo, id_receta_x_partida, get_user_id(),fecha,p_fyh_salida_real)
    RETURNING id INTO salida_id;
	if motivo='matizado' THEN
	INSERT INTO matizado (fecha,insumo_id,cantidad,partida_id,medida,turno_id)
	SELECT fecha,(elm->>'insumo_id')::INTEGER,(elm->>'cantidad_requerida')::NUMERIC(12,5),p_partida_id,'kg',turno_id
	FROM jsonb_array_elements(detalles) as elm;
	END IF;

-- Insertar detalles
INSERT INTO salida_inventario_detalle(
        salida_inventario_id,
        cantidad_solicitada,
        insumo_id
    )
SELECT
        salida_id,
        (elm->>'cantidad_requerida')::NUMERIC(12,5)
        * (
            CASE 
                WHEN  motivo IN ('receta','matizado') AND (elm->>'insumo_id')::INT = 13 
                THEN 1.0/6.0 
                ELSE 1.0 
            END
          ),
        (elm->>'insumo_id')::INT
FROM jsonb_array_elements(detalles) AS elm;
PERFORM aprobar_salida_inventario_total(salida_id);
    RETURN format('Solicitud de salida #%s registrada correctamente.', salida_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_matizado(motivo public.motivo_salida_inventario_enum, p_partida_id integer, detalles jsonb, p_receta_id integer, tipo_receta_id integer, maquina_id integer, turno_id integer, fecha date, p_fyh_salida_real timestamp with time zone) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_receta(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_receta(p jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  partida_id int := (p->>'partida_id')::int;
  tipo_receta_id int := (p->>'tipo_receta_id')::int;
  maquina_id int := (p->>'maquina_id')::int;
  p_fyh_salida_real timestamptz := (p->>'p_fyh_salida_real')::timestamptz;
  p_rollos int := (p->>'p_rollos')::int;
  p_rib int := (p->>'p_rib')::int;
  p_relacion_bano int := (p->>'p_relacion_bano')::int;
    pasos JSONB;
    id_receta INTEGER;
    data JSONB;
    v_params jsonb;
BEGIN
v_params := jsonb_build_object(
    'partida_id', partida_id,
    'tipo_receta_id', tipo_receta_id,
    'maquina_id', maquina_id,
    'fyh_salida_real', p_fyh_salida_real,
    'rollos', p_rollos,
    'p_rib',p_rib,
    'relacion_bano',p_relacion_bano
  );
  INSERT into logs_api(function_name, user_id, params)
  SELECT 'solicitar_salida_inventario_receta', get_user_id(), v_params;

    -- Call the function once and keep full JSON
    SELECT generate_complete_recipe(partida_id, tipo_receta_id, maquina_id,p_rollos,p_rib,p_relacion_bano)
    INTO data;

    -- Extract id
    id_receta := (data->>'id_receta')::int;
    p_rollos := (data->>'rollos')::int;
    p_rib := (data->>'rib')::int;
    p_relacion_bano := (data->>'relacion_bano')::int;
    -- Aggregate pasos
    SELECT jsonb_agg(
        jsonb_build_object(
            'insumo_id', insumo_id,
            'cantidad_requerida', total_cantidad
        )
    )
    INTO pasos
    FROM (
        SELECT 
            (elem->>'insumo_id')::int AS insumo_id,
            SUM(((elem->>'cantidad_requerida')::numeric / 1000)::numeric(12,4)) AS total_cantidad
        FROM jsonb_array_elements(data->'pasos') AS elem
        WHERE (elem->>'tipo')::int = 2
        GROUP BY (elem->>'insumo_id')::int
    ) grouped;

    -- Pass both id_receta and pasos forward
    RETURN solicitar_salida_inventario('receta', partida_id, pasos, id_receta,tipo_receta_id, maquina_id,p_fyh_salida_real,p_rollos,p_relacion_bano);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_receta(p jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_receta(integer, integer, integer, timestamp with time zone, integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_receta(partida_id integer DEFAULT NULL::integer, tipo_receta_id integer DEFAULT NULL::integer, maquina_id integer DEFAULT NULL::integer, p_fyh_salida_real timestamp with time zone DEFAULT NULL::timestamp with time zone, p_rollos integer DEFAULT NULL::integer, p_rib integer DEFAULT NULL::integer, p_relacion_bano integer DEFAULT NULL::integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    pasos JSONB;
    id_receta INTEGER;
    data JSONB;
    v_params jsonb;
BEGIN
v_params := jsonb_build_object(
    'partida_id', partida_id,
    'tipo_receta_id', tipo_receta_id,
    'maquina_id', maquina_id,
    'fyh_salida_real', p_fyh_salida_real,
    'rollos', p_rollos,
    'p_rib',p_rib,
    'relacion_bano',p_relacion_bano
  );
  INSERT into logs_api(function_name, user_id, params)
  SELECT 'solicitar_salida_inventario_receta', get_user_id(), v_params;

    -- Call the function once and keep full JSON
    SELECT generate_complete_recipe(partida_id, tipo_receta_id, maquina_id,p_rollos,p_rib,p_relacion_bano)
    INTO data;

    -- Extract id
    id_receta := (data->>'id_receta')::int;
    p_rollos := (data->>'rollos')::int;
    p_rib := (data->>'rib')::int;
    p_relacion_bano := (data->>'relacion_bano')::int;
    -- Aggregate pasos
    SELECT jsonb_agg(
        jsonb_build_object(
            'insumo_id', insumo_id,
            'cantidad_requerida', total_cantidad
        )
    )
    INTO pasos
    FROM (
        SELECT 
            (elem->>'insumo_id')::int AS insumo_id,
            SUM(((elem->>'cantidad_requerida')::numeric / 1000)::numeric(12,4)) AS total_cantidad
        FROM jsonb_array_elements(data->'pasos') AS elem
        WHERE (elem->>'tipo')::int = 2
        GROUP BY (elem->>'insumo_id')::int
    ) grouped;

    -- Pass both id_receta and pasos forward
    RETURN solicitar_salida_inventario('receta', partida_id, pasos, id_receta,tipo_receta_id, maquina_id,p_fyh_salida_real,p_rollos,p_relacion_bano);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_receta(partida_id integer, tipo_receta_id integer, maquina_id integer, p_fyh_salida_real timestamp with time zone, p_rollos integer, p_rib integer, p_relacion_bano integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_receta2(integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_receta2(partida_id integer, receta_id integer, maquina_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    pasos JSONB;
    id_receta INTEGER;
    data JSONB;
BEGIN
    -- Call the function once and keep full JSON
    SELECT generate_recipe(partida_id, receta_id, maquina_id)
    INTO data;

    -- Extract id
    id_receta := (data->>'id_receta')::int;

    -- Aggregate pasos
    SELECT jsonb_agg(
        jsonb_build_object(
            'insumo_id', insumo_id,
            'cantidad_requerida', total_cantidad
        )
    )
    INTO pasos
    FROM (
        SELECT 
            (elem->>'insumo_id')::int AS insumo_id,
            SUM(((elem->>'cantidad_requerida')::numeric / 1000)::numeric(12,4)) AS total_cantidad
        FROM jsonb_array_elements(data->'pasos') AS elem
        WHERE (elem->>'tipo')::int = 2
        GROUP BY (elem->>'insumo_id')::int
    ) grouped;

    -- Pass both id_receta and pasos forward
    RETURN solicitar_salida_inventario_2('receta', partida_id, pasos, id_receta,receta_id, maquina_id);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_receta2(partida_id integer, receta_id integer, maquina_id integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.solicitar_salida_inventario_receta3(integer, integer, integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.solicitar_salida_inventario_receta3(partida_id integer, receta_id integer, maquina_id integer, id_receta_x_partida integer) RETURNS text
    LANGUAGE plpgsql
    AS $$DECLARE
    pasos JSONB;
    id_receta INTEGER;
    data JSONB;
BEGIN
    -- Call the function once and keep full JSON
    SELECT generate_recipe(partida_id, receta_id, maquina_id)
    INTO data;

    -- Extract id
    id_receta := (data->>'id_receta')::int;

    -- Aggregate pasos
    SELECT jsonb_agg(
        jsonb_build_object(
            'insumo_id', insumo_id,
            'cantidad_requerida', total_cantidad
        )
    )
    INTO pasos
    FROM (
        SELECT 
            (elem->>'insumo_id')::int AS insumo_id,
            SUM(((elem->>'cantidad_requerida')::numeric / 1000)::numeric(12,4)) AS total_cantidad
        FROM jsonb_array_elements(data->'pasos') AS elem
        WHERE (elem->>'tipo')::int = 2
        GROUP BY (elem->>'insumo_id')::int
    ) grouped;

    -- Pass both id_receta and pasos forward
    RETURN solicitar_salida_inventario_3('receta', partida_id, pasos, id_receta,receta_id, maquina_id,id_receta_x_partida);
END;$$;


ALTER FUNCTION public.solicitar_salida_inventario_receta3(partida_id integer, receta_id integer, maquina_id integer, id_receta_x_partida integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_estado_observado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_estado_observado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_estado_id int;
begin
    -- Validar que haya partida válida
    if NEW.partida_id is null then
        return NEW;
    end if;

    -- Validar que haya algo observado
    if coalesce(NEW.rollos,0) <= 0 and coalesce(NEW.rib,0) <= 0 then
        return NEW;
    end if;

    -- Obtener ID del estado "Observado"
    select id
    into v_estado_id
    from estado
    where estado = 'Observado';

    -- Insertar en historial
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        v_estado_id,
        coalesce(NEW.rollos,0),
        coalesce(NEW.rib,0),
        NEW.fecha
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_estado_observado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_estado_tenido_inteligente()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_estado_tenido_inteligente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    id_en_proceso_tenido int;
    id_tenido int;
    id_reprocesado int;
    id_en_proceso_reproceso int;
    v_fecha date;
begin
    select id into id_en_proceso_tenido
    from estado where estado = 'En Proceso Teñido';

    select id into id_tenido
    from estado where estado = 'Teñido';

    select id into id_reprocesado
    from estado where estado = 'Reprocesado';

    select id into id_en_proceso_reproceso
    from estado where estado = 'En Proceso Reproceso';

    if NEW.partida_id is null then
        return NEW;
    end if;

    v_fecha := NEW.fecha;

    if NEW.tipo = 'Teñido' then
        if NEW.hora_fin is null then
            insert into partida_estado_historial
            (partida_id, estado_id, rollos_afectados, rib_afectados, fecha_ejecucion)
            values
            (NEW.partida_id, id_en_proceso_tenido, NEW.rollos, 0, v_fecha);
        else
            insert into partida_estado_historial
            (partida_id, estado_id, rollos_afectados, rib_afectados, fecha_ejecucion)
            values
            (NEW.partida_id, id_tenido, NEW.rollos, 0, v_fecha);
        end if;

    else
        if NEW.hora_fin is null then
            insert into partida_estado_historial
            (partida_id, estado_id, rollos_afectados, rib_afectados, fecha_ejecucion)
            values
            (NEW.partida_id, id_en_proceso_reproceso, NEW.rollos, 0, v_fecha);
        else
            insert into partida_estado_historial
            (partida_id, estado_id, rollos_afectados, rib_afectados, fecha_ejecucion)
            values
            (NEW.partida_id, id_reprocesado, NEW.rollos, 0, v_fecha);
        end if;
    end if;

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_estado_tenido_inteligente() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_estado_despachado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_estado_despachado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    id_despachado int;
begin
    -- obtener ID del estado "Despachado"
    select id into id_despachado
    from estado
    where estado = 'Despachado';

    if id_despachado is null then
        raise exception 'No existe el estado "Despachado" en la tabla estado.';
    end if;

    -- insertar en historial separando rollos y rib
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        id_despachado,
        coalesce(NEW.rollos, 0),
        coalesce(NEW.rib, 0),
        NEW.fecha_despacho
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_estado_despachado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_estado_devolucion()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_estado_devolucion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_estado_id int;
begin
    -- Obtener ID del estado "Devolución"
    select id
    into v_estado_id
    from estado
    where estado = 'Devolución';

    if v_estado_id is null then
        raise exception 'No existe el estado "Devolución" en la tabla estado';
    end if;

    -- Insertar en historial
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        v_estado_id,
        coalesce(NEW.rollos, 0),
        coalesce(NEW.rib, 0),
        NEW.fecha_devolucion
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_estado_devolucion() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_estado_para_despachar()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_estado_para_despachar() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    id_para_despachar int;
    v_rollos_total int;
    v_rib_total int;
begin
    -- Solo actuar si auditoría = OK
    if NEW.estado <> 'OK' then
        return NEW;
    end if;

    -- Obtener ID del estado "Para Despachar"
    select id
    into id_para_despachar
    from estado
    where estado = 'Para Despachar';

    if id_para_despachar is null then
        raise exception 'Estado "Para Despachar" no existe en tabla estado';
    end if;

    -- Obtener totales de la partida
    select rollos, rib
    into v_rollos_total, v_rib_total
    from partida
    where id = NEW.partida_id;

    -- Insertar en historial
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        id_para_despachar,
        coalesce(v_rollos_total, 0),
        coalesce(v_rib_total, 0),
        NEW.fecha_auditoria
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_estado_para_despachar() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_estado_perchado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_estado_perchado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    id_perchado int;
begin
    -- obtener ID del estado Perchado
    select id into id_perchado
    from estado
    where estado = 'Perchado';

    if id_perchado is null then
        raise exception 'No existe el estado "Perchado" en la tabla estado';
    end if;

    -- insertar en historial
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        id_perchado,
        NEW.rollos,
        0,               -- perchado NO afecta rib
        NEW.fecha
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_estado_perchado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_estado_planchado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_estado_planchado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    id_planchado int;
    id_replanchado int;
    v_estado_id int;
begin
    -- obtener IDs
    select id into id_planchado 
    from estado where estado = 'Planchado';

    select id into id_replanchado
    from estado where estado = 'Replanchado';

    -- solo actuamos cuando el registro es Compactado
    if NEW.estado <> 'Compactado' then
        return NEW;
    end if;

    -- determinar estado según tipo_proceso
    if NEW.tipo_proceso = 'Produccion' then

        v_estado_id := id_planchado;

    elsif NEW.tipo_proceso in ('Reproceso', 'Replanchado') then

        v_estado_id := id_replanchado;

    else
        return NEW; -- por si viene un tipo inválido
    end if;

    -- insertar historial
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        v_estado_id,
        NEW.rollos,
        new.rib,
        NEW.fecha
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_estado_planchado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_estado_termofijado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_estado_termofijado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_estado_id int;
begin
    -- Validar partida
    if NEW.partida_id is null then
        return NEW;
    end if;

    -- Validar rollos
    if NEW.rollos is null or NEW.rollos <= 0 then
        return NEW;
    end if;

    -- Obtener ID del estado Termofijado
    select id into v_estado_id
    from estado
    where estado = 'Termofijado';

    if v_estado_id is null then
        raise exception 'Estado "Termofijado" no existe en tabla estado.';
    end if;

    -- Insertar en historial (rib = 0)
    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        v_estado_id,
        NEW.rollos,
        0,
        NEW.fecha
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_estado_termofijado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_insertar_programado()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_insertar_programado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_estado_id int;
    v_rollos int;
    v_rib int;
begin
    if NEW.partida_id is null then
        return NEW;
    end if;

    select id into v_estado_id
    from estado
    where estado = 'Programado';

    -- eliminar programado previo del mismo día
    delete from partida_estado_historial
    where partida_id = NEW.partida_id
      and estado_id = v_estado_id
      and fecha_ejecucion = NEW.fecha;

    -- rollos
    if NEW.rollos_programados is not null then
        v_rollos := NEW.rollos_programados;
    else
        select rollos into v_rollos
        from partida
        where id = NEW.partida_id;
    end if;

    -- rib
    if NEW.rib_programados is not null then
        v_rib := NEW.rib_programados;
    else
        v_rib := 0;
    end if;

    insert into partida_estado_historial (
        partida_id,
        estado_id,
        rollos_afectados,
        rib_afectados,
        fecha_ejecucion
    )
    values (
        NEW.partida_id,
        v_estado_id,
        v_rollos,
        v_rib,
        NEW.fecha
    );

    return NEW;
end;
$$;


ALTER FUNCTION public.trg_insertar_programado() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_set_costo_bruto_kg()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_set_costo_bruto_kg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only set if not manually defined
  IF NEW.costo_bruto_kg IS NULL THEN
    SELECT cxi.precio_x_kg_usd
    INTO NEW.costo_bruto_kg
    FROM entrada_inventario_detalle eid
    LEFT JOIN compra_x_insumo cxi 
      ON eid.compra_x_insumo_id = cxi.id
    WHERE eid.id = NEW.entrada_inventario_detalle_id
      AND cxi.precio_x_kg_usd IS NOT NULL
    LIMIT 1;
  END IF;
  IF NEW.costo_bruto_kg IS NULL THEN
    SELECT cxi.precio_x_kg_usd
    INTO NEW.costo_bruto_kg
    FROM  compra_x_insumo cxi 
    WHERE cxi.insumo_x_proveedor_id = NEW.insumo_x_proveedor_id
      AND cxi.precio_x_kg_usd IS NOT NULL
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_set_costo_bruto_kg() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.trg_update_insumo_prices()
-- ---------------------------------------------------------------------
CREATE FUNCTION public.trg_update_insumo_prices() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Update insumo
  UPDATE insumo i
  SET precio_prom_kg_usd = NEW.costo_bruto_kg
  FROM insumo_x_proveedor ixp
  WHERE ixp.id = NEW.insumo_x_proveedor_id
    AND i.id = ixp.insumo_id;
  
  -- Update insumo_x_proveedor
  UPDATE insumo_x_proveedor ip
  SET precio_x_kg_usd = NEW.costo_bruto_kg
  WHERE id = NEW.insumo_x_proveedor_id;  -- Added semicolon here
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_update_insumo_prices() OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.upd_compra(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.upd_compra(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$BEGIN
    -- Debug log
    INSERT INTO json_debug_log (received_json) VALUES (json_data);

    -- Validate estado_ingreso
    -- IF (
    --     SELECT estado_ingreso
    --     FROM compra
    --     WHERE id = (json_data->>'compra_id')::int
    -- ) != 'pendiente' THEN
    --     RETURN QUERY
    --     SELECT 'Compra no editable, ya ha sido ingresada o cancelada';
    --     RETURN; -- exit the function
    -- END IF;

    -- Update compra
    UPDATE compra
    SET
        factura = COALESCE(NULLIF(TRIM(json_data->>'factura'), ''),NULLIF(factura, '')),--COALESCE(NULLIF(factura, ''), NULLIF(TRIM(json_data->>'factura'), '')),
        fecha_giro = COALESCE(fecha_giro, NULLIF(json_data->>'fecha_giro', '')::date),
        fecha_vencimiento = NULLIF(json_data->>'fecha_vencimiento', '')::date,
        fecha_pago = COALESCE(fecha_pago, NULLIF(json_data->>'fecha_pago', '')::date),
        estado_pago = (json_data->>'estado_pago')::estado_pago_enum,
        fyh_mod = CURRENT_TIMESTAMP,
        usr_mod = CURRENT_USER
    WHERE id = (json_data->>'compra_id')::int;

    -- Upsert compra_x_insumo
    INSERT INTO compra_x_insumo (
        compra_id,
        insumo_id,
        cantidad,
        precio_x_kg_usd,
        insumo_x_proveedor_id
    )
    SELECT
        (json_data->>'compra_id')::integer,
        (item->>'insumo_id')::smallint,
        (item->>'cantidad')::numeric(10,2),
        (item->>'precio_x_kg_usd')::numeric(7,4),
        (item->>'insumo_x_proveedor_id')::integer
    FROM jsonb_array_elements(json_data->'productos') AS item
    ON CONFLICT (compra_id, insumo_id)
    DO UPDATE SET
        cantidad = EXCLUDED.cantidad,
        precio_x_kg_usd = EXCLUDED.precio_x_kg_usd,
        insumo_x_proveedor_id = EXCLUDED.insumo_x_proveedor_id;

    -- Delete productos no longer present
    DELETE FROM compra_x_insumo
    WHERE compra_id = (json_data->>'compra_id')::integer
      AND insumo_x_proveedor_id NOT IN (
        SELECT (item->>'insumo_x_proveedor_id')::smallint
        FROM jsonb_array_elements(json_data->'productos') AS item
      );

    -- Upsert letra_compra
    INSERT INTO letra_compra (
        compra_id,
        numero_letra,
        monto_usd,
        fecha_emision,
        fecha_vencimiento
    )
    SELECT
        (json_data->>'compra_id')::integer,
        (item->>'numero_letra'),
        (item->>'monto_usd')::numeric(12,2),
        (item->>'fecha_emision')::date,
        (item->>'fecha_vencimiento')::date
    FROM jsonb_array_elements(json_data->'letras') AS item
    ON CONFLICT (compra_id, numero_letra)
    DO UPDATE SET
        monto_usd = EXCLUDED.monto_usd,
        fecha_emision = EXCLUDED.fecha_emision,
        fecha_vencimiento = EXCLUDED.fecha_vencimiento,
        fyh_mod = CURRENT_TIMESTAMP,
        usr_mod = get_user_id();

    -- Delete letras no longer present
    DELETE FROM letra_compra
    WHERE compra_id = (json_data->>'compra_id')::integer
      AND numero_letra NOT IN (
        SELECT (item->>'numero_letra')
        FROM jsonb_array_elements(json_data->'letras') AS item
      );

    RETURN QUERY
    SELECT 'Se actualizó la información de compra exitosamente';
END;$$;


ALTER FUNCTION public.upd_compra(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_cuadre_inventario_detalles(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_cuadre_inventario_detalles(p_json jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    /*
      Expected JSON format:
      [
        { "id": 101, "cantidad_contada": 12.3 },
        { "id": 102, "cantidad_contada": 0   }
      ]
    */

    UPDATE cuadre_inventario_detalle d
    SET cantidad_contada = u.cantidad_contada,
        fyh_mod = now(),
        usr_mod = get_user_id()
    FROM jsonb_to_recordset(p_json) AS u(cuadre_inventario_detalle_id int, cantidad_contada numeric)
    WHERE d.id = u.cuadre_inventario_detalle_id;
END;
$$;


ALTER FUNCTION public.update_cuadre_inventario_detalles(p_json jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_observado(integer[])
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_observado(partidas integer[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE observado
    SET flg_elm = 1
    WHERE partida_id = ANY(partidas);
END;
$$;


ALTER FUNCTION public.update_observado(partidas integer[]) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_observado(integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_observado(input_partida integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 1. Actualiza el flag en la tabla observado
    UPDATE observado
    SET flg_elm = 1
    WHERE partida_id = input_partida;

    -- 2. Inserta el estado "Solucionado" en observado_estados
    INSERT INTO observado_estados (partida_id, fecha, estado)
    VALUES (input_partida, CURRENT_DATE, 'Solucionado');
END;
$$;


ALTER FUNCTION public.update_observado(input_partida integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_observado(integer[], integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_observado(partida_id integer[], p_flg_elm integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE observado AS o
    SET flg_elm = p_flg_elm
    WHERE o.partida_id = ANY(partida_id);
END;
$$;


ALTER FUNCTION public.update_observado(partida_id integer[], p_flg_elm integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_observado(integer, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_observado(p_fk_partida integer, p_flg_elm integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE observado
    SET flg_elm = p_flg_elm
    WHERE partida_id::text = ANY(string_to_array(p_fk_partida, ','));
END;
$$;


ALTER FUNCTION public.update_observado(p_fk_partida integer, p_flg_elm integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_partida(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_partida(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT into logs_api(function_name,user_id,params)
  SELECT 'update_partida', get_user_id(),json_data;
 
  UPDATE partida
  SET 
    guia = COALESCE(json_data->>'guia', guia),
    fecha_entrega = COALESCE((json_data->>'fecha_entrega')::DATE, fecha_entrega),
    articulo_id = COALESCE((json_data->>'articulo_id')::smallint, articulo_id),
    prioridad_id = COALESCE((json_data->>'prioridad_id')::smallint, prioridad_id),
    cliente_id = COALESCE((json_data->>'cliente_id')::SMALLINT, cliente_id),
    tenido_id= COALESCE((json_data->>'tenido_id')::SMALLINT, tenido_id),
    color_x_cliente_id = COALESCE((json_data->>'color_x_cliente_id')::SMALLINT, color_x_cliente_id),
    rib = COALESCE((json_data->>'rib')::SMALLINT, rib),
    fibra = COALESCE((json_data->>'fibra')::SMALLINT, fibra),
    previo_id = COALESCE(NULLIF(json_data->>'previo_id', '')::SMALLINT, previo_id),
    malla = COALESCE((json_data->>'malla'),malla),
    observacion=json_data->>'observacion',
    adicional_id = 
    CASE
    WHEN jsonb_typeof(json_data->'adicional_id') = 'null' THEN NULL
    ELSE COALESCE((json_data->>'adicional_id')::SMALLINT, adicional_id)
  END,--COALESCE((json_data->>'adicional_id')::SMALLINT,adicional_id),
    ancho = COALESCE((json_data->>'ancho'),ancho),
    rendimiento = COALESCE((json_data->>'rendimiento'),rendimiento),
    rollos = COALESCE((json_data->>'rollos')::SMALLINT,rollos)
  WHERE id = (json_data->>'partida_id')::INTEGER;

-----UPDATE tabla de extras
-- Assuming a unique constraint exists on (partida_id, extra_id)
INSERT INTO partida_x_extra (partida_id, extra_id, cantidad)
SELECT 
    (json_data->>'partida_id')::INTEGER,
    (item->>'extra_id')::SMALLINT,
    (item->>'cantidad')::SMALLINT
FROM jsonb_array_elements(json_data->'extras') AS item
ON CONFLICT (partida_id, extra_id)
DO UPDATE SET cantidad = EXCLUDED.cantidad;

DELETE FROM partida_x_extra
WHERE partida_id = (json_data->>'partida_id')::INTEGER
AND extra_id NOT IN (
  SELECT (item->>'extra_id')::SMALLINT
  FROM jsonb_array_elements(json_data->'extras') AS item
);

  RETURN QUERY SELECT 'Se modifico exitosamente la partida: ' ||(json_data->>'partida_id');
END;
$$;


ALTER FUNCTION public.update_partida(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_peso(double precision, double precision, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_peso(peso_rollos_excel double precision, peso_rib_excel double precision, partida_excel integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cliente_id      smallint;
    v_articulo_id     smallint;
    v_rollos          numeric;
    v_min_cliente     numeric;
    v_min_global      numeric;
BEGIN
    -- Obtener datos base
    SELECT cliente_id, articulo_id, rollos
    INTO v_cliente_id, v_articulo_id, v_rollos
    FROM partida
    WHERE id = partida_excel;

    -- Si rollos es 0, actualizar sin validar
    IF v_rollos IS NULL OR v_rollos = 0 THEN
        UPDATE partida
        SET peso_rollos = COALESCE(peso_rollos_excel, 0),
            peso_rib    = COALESCE(peso_rib_excel, 0),
            fyh_peso    = now()
        WHERE id = partida_excel;
        RETURN;
    END IF;

    -------------------------------------------------------------------
    -- VALIDACIÓN
    -------------------------------------------------------------------

    -- Regla por cliente + artículo
    SELECT min_kg_por_rollo
    INTO v_min_cliente
    FROM regla_peso_cliente_articulo
    WHERE cliente_id = v_cliente_id
      AND articulo_id = v_articulo_id;

    -- Validación con regla por cliente
    IF v_min_cliente IS NOT NULL THEN
        IF peso_rollos_excel < v_rollos * (v_min_cliente * 0.95) THEN
            RAISE EXCEPTION 
                'Partida % - Peso inválido. Ingresado: % kg | Mínimo permitido: % kg. Verificar digitación.',
                partida_excel,
                peso_rollos_excel,
                ROUND(v_rollos * (v_min_cliente * 0.95), 2);
        END IF;

    ELSE
        -- Regla global por artículo
        SELECT min_kg_por_rollo
        INTO v_min_global
        FROM regla_peso_articulo
        WHERE articulo_id = v_articulo_id;

        IF v_min_global IS NOT NULL THEN
            IF peso_rollos_excel < v_rollos * (v_min_global * 0.95) THEN
                RAISE EXCEPTION 
                    'Partida % - Peso inválido. Ingresado: % kg | Mínimo permitido: % kg. Verificar digitación.',
                    partida_excel,
                    peso_rollos_excel,
                    ROUND(v_rollos * (v_min_global * 0.95), 2);
            END IF;
        END IF;
    END IF;

    -------------------------------------------------------------------
    -- ACTUALIZAR SI TODO ES VÁLIDO
    -------------------------------------------------------------------
    UPDATE partida
    SET 
        peso_rollos = COALESCE(peso_rollos_excel, 0),
        peso_rib    = COALESCE(peso_rib_excel, 0),
        fyh_peso    = now()
    WHERE id = partida_excel;

END;
$$;


ALTER FUNCTION public.update_peso(peso_rollos_excel double precision, peso_rib_excel double precision, partida_excel integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_peso(double precision, double precision, double precision, integer)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_peso(peso_rollos_excel double precision, peso_rib_excel double precision, peso_extra_excel double precision, partida_excel integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cliente_id      smallint;
    v_articulo_id     smallint;
    v_rollos          numeric;
    v_min_cliente     numeric;
    v_min_global      numeric;
BEGIN
    -- Obtener datos base
    SELECT cliente_id, articulo_id, rollos
    INTO v_cliente_id, v_articulo_id, v_rollos
    FROM partida
    WHERE id = partida_excel;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Partida % no existe.', partida_excel;
    END IF;

    -------------------------------------------------------------------
    -- CASO: rollos = 0 → no validar pesos
    -------------------------------------------------------------------
    IF v_rollos IS NULL OR v_rollos = 0 THEN
        UPDATE partida
        SET peso_rollos = COALESCE(peso_rollos_excel, 0),
            peso_rib    = COALESCE(peso_rib_excel, 0),
            fyh_peso    = now()
        WHERE id = partida_excel;

        UPDATE partida_x_extra
        SET peso = COALESCE(peso_extra_excel, 0)
        WHERE partida_id = partida_excel;

        RETURN;
    END IF;

    -------------------------------------------------------------------
    -- VALIDACIÓN SOLO PARA PESO_ROLLOS
    -------------------------------------------------------------------
    SELECT min_kg_por_rollo
    INTO v_min_cliente
    FROM regla_peso_cliente_articulo
    WHERE cliente_id = v_cliente_id
      AND articulo_id = v_articulo_id;

    IF v_min_cliente IS NOT NULL THEN
        IF peso_rollos_excel < v_rollos * (v_min_cliente * 0.95) THEN
            RAISE EXCEPTION
                'Partida % - Peso inválido. Ingresado: % kg | Mínimo permitido: % kg. Verificar digitación.',
                partida_excel,
                peso_rollos_excel,
                ROUND(v_rollos * (v_min_cliente * 0.95), 2);
        END IF;
    ELSE
        SELECT min_kg_por_rollo
        INTO v_min_global
        FROM regla_peso_articulo
        WHERE articulo_id = v_articulo_id;

        IF v_min_global IS NOT NULL THEN
            IF peso_rollos_excel < v_rollos * (v_min_global * 0.95) THEN
                RAISE EXCEPTION
                    'Partida % - Peso inválido. Ingresado: % kg | Mínimo permitido: % kg. Verificar digitación.',
                    partida_excel,
                    peso_rollos_excel,
                    ROUND(v_rollos * (v_min_global * 0.95), 2);
            END IF;
        END IF;
    END IF;

    -------------------------------------------------------------------
    -- ACTUALIZAR SI TODO ES VÁLIDO
    -------------------------------------------------------------------
    UPDATE partida
    SET
        peso_rollos = COALESCE(peso_rollos_excel, 0),
        peso_rib    = COALESCE(peso_rib_excel, 0),
        fyh_peso    = now()
    WHERE id = partida_excel;

    UPDATE partida_x_extra
    SET peso = COALESCE(peso_extra_excel, 0)
    WHERE partida_id = partida_excel;

END;
$$;


ALTER FUNCTION public.update_peso(peso_rollos_excel double precision, peso_rib_excel double precision, peso_extra_excel double precision, partida_excel integer) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_precio_x_partida(integer, double precision, character varying)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_precio_x_partida(partida_id integer, precio double precision, nfactura character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE partida
    SET 
        precio_usd = precio,
        factura = NFactura
    WHERE id = partida_id;
END;
$$;


ALTER FUNCTION public.update_precio_x_partida(partida_id integer, precio double precision, nfactura character varying) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_receta(jsonb)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_receta(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$BEGIN
  -- Log the API call
  INSERT into logs_api(function_name, user_id, params)
  SELECT 'update_receta', get_user_id(), json_data;
  
  IF (json_data->>'receta_id')::INTEGER IN (SELECT receta_id FROM partida_x_recetas) THEN RETURN QUERY SELECT 'La rececta ya ha sido ejecutada, no se puede editar ';
  RETURN;
   END IF;

  -- Update the main recipe table
  UPDATE receta2
  SET 
    color_x_cliente_id = COALESCE((json_data->>'color_x_cliente_id')::smallint, color_x_cliente_id),
    tipo_articulo_id = COALESCE((json_data->>'tipo_articulo_id')::smallint, tipo_articulo_id),
    tenido_id = COALESCE((json_data->>'tenido_id')::smallint, tenido_id),
    fibra = COALESCE((json_data->>'fibra')::smallint, fibra),
    tipo_receta_id = COALESCE((json_data->>'tipo_receta_id')::smallint, tipo_receta_id)
  WHERE id = (json_data->>'receta_id')::INTEGER;

  -- Handle pasos (tipo = 1) - Insert or update steps
  INSERT INTO receta_x_paso (receta_id, paso_id, orden)
  SELECT 
    (json_data->>'receta_id')::INTEGER,
    (item->>'fk')::SMALLINT,
    (item->>'orden')::SMALLINT
  FROM jsonb_array_elements(json_data->'pasos') AS item
  WHERE (item->>'tipo')::INTEGER = 1
  ON CONFLICT (receta_id, orden)
  DO UPDATE SET paso_id = EXCLUDED.paso_id;

  -- Handle insumos (tipo = 2) - Insert or update ingredients
  INSERT INTO receta_x_insumo (receta_id, insumo_id, cantidad, orden)
  SELECT 
    (json_data->>'receta_id')::INTEGER,
    (item->>'fk')::SMALLINT,
    COALESCE((item->>'cantidad')::numeric(8,4), 0),
    (item->>'orden')::SMALLINT
  FROM jsonb_array_elements(json_data->'pasos') AS item
  WHERE (item->>'tipo')::INTEGER = 2
  ON CONFLICT (receta_id, orden)
  DO UPDATE SET 
    insumo_id = EXCLUDED.insumo_id,
    cantidad = EXCLUDED.cantidad;

  -- Delete pasos that are no longer in the JSON data (tipo = 1)
  DELETE FROM receta_x_paso
  WHERE receta_id = (json_data->>'receta_id')::INTEGER
  AND orden NOT IN (
    SELECT (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'pasos') AS item
    WHERE (item->>'tipo')::INTEGER = 1
  );

  -- Delete insumos that are no longer in the JSON data (tipo = 2)
  DELETE FROM receta_x_insumo
  WHERE receta_id = (json_data->>'receta_id')::INTEGER
  AND orden NOT IN (
    SELECT (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'pasos') AS item
    WHERE (item->>'tipo')::INTEGER = 2
  );

  RETURN QUERY SELECT 'Se modifico exitosamente la receta: ' || (json_data->>'receta_id');
END;$$;


ALTER FUNCTION public.update_receta(json_data jsonb) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- FUNCTION: public.update_receta_x_partida(double precision, integer, double precision)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.update_receta_x_partida(id_receta double precision, partida_id integer, costo_total double precision) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE partida
    SET receta_id = id_receta,
        costo_total_usd = costo_total
    WHERE id = partida_id;
END;
$$;


ALTER FUNCTION public.update_receta_x_partida(id_receta double precision, partida_id integer, costo_total double precision) OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TYPE: public.estado_letra_enum
-- ---------------------------------------------------------------------
CREATE TYPE public.estado_letra_enum AS ENUM (
    'emitida',
    'pagada',
    'vencida',
    'protestada',
    'anulada'
);


ALTER TYPE public.estado_letra_enum OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TYPE: public.estado_salida_inventario_enum
-- ---------------------------------------------------------------------
CREATE TYPE public.estado_salida_inventario_enum AS ENUM (
    'pendiente',
    'aprobado',
    'rechazado',
    'ajustado',
    'lavado maquina'
);


ALTER TYPE public.estado_salida_inventario_enum OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TYPE: public.motivo_salida_inventario_enum
-- ---------------------------------------------------------------------
CREATE TYPE public.motivo_salida_inventario_enum AS ENUM (
    'receta',
    'matizado',
    'ajuste',
    'mantenimiento',
    'muestra',
    'merma',
    'transferencia',
    'otros',
    'lavado maquina',
    'lavado',
    'ajuste receta',
    'desmontado',
    'reconteo'
);


ALTER TYPE public.motivo_salida_inventario_enum OWNER TO postgres;

-- ---------------------------------------------------------------------
-- TYPE: public.tipo_insumo_enum
-- ---------------------------------------------------------------------
CREATE TYPE public.tipo_insumo_enum AS ENUM (
    'auxiliar',
    'directo',
    'disperso',
    'reactivo',
    'quimico'
);


ALTER TYPE public.tipo_insumo_enum OWNER TO postgres;

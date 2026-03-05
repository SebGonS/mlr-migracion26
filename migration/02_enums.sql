-- ═══════════════════════════════════════════════════════════════
-- Step 2: ENUM / TYPE definitions
-- Must come before any table that uses these types.
-- FIX: removed bare DROP TYPE (without CASCADE) — replaced with safe idiom.
-- ═══════════════════════════════════════════════════════════════

-- ── Inventory ──────────────────────────────────────────────────
CREATE TYPE calidad_estado_enum AS ENUM (
  'PENDIENTE',
  'APROBADO',
  'RECHAZADO',
  'REPROCESO',
  'CUARENTENA'
);

CREATE TYPE item_movimiento_tipo_categoria_enum AS ENUM (
    'COMPRA',
    'VENTA',
    'PRODUCCION',
    'PROCESO_EXTERNO',
    'DEVOLUCION',
    'AJUSTE',
    'TRANSFERENCIA'
);

-- ── MES / Production ───────────────────────────────────────────
-- FIX: was DROP TYPE IF EXISTS ... (no CASCADE) — would fail if type in use.
-- Use safe CREATE with duplicate guard instead.
DO $$
BEGIN
    CREATE TYPE orden_produccion_estado_enum AS ENUM (
      'CREADA',
      'PLANIFICADA',
      'PROGRAMADA',
      'LIBERADA',
      'EN_PROCESO',
      'PAUSADA',
      'FINALIZADA',
      'TECO',
      'CERRADA',
      'CANCELADA'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE partida_estado_enum AS ENUM (
      'CREADA',
      'CONFIRMADA',
      'EN_PRODUCCION',
      'ENTREGA_PARCIAL',
      'ENTREGADA',
      'DEVUELTA_PARCIAL',
      'DEVUELTA_TOTAL',
      'FACTURADA',
      'CERRADA',
      'CANCELADA'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE orden_produccion_tipo_enum AS ENUM (
        'NORMAL', 'REPROCESO', 'AJUSTE'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE orden_produccion_paso_estado_enum AS ENUM (
        'PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'OMITIDO'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TYPE maquina_estado_enum AS ENUM (
    'activa',
    'espera',
    'configuracion',
    'averia',
    'mantenimiento'
);

-- ── Compras ────────────────────────────────────────────────────
SELECT * FROM vw_tipo_pago;

DO $$
BEGIN
    CREATE TYPE tipo_pago_enum AS ENUM ('contado', 'credito');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE estado_pago_enum AS ENUM ('pendiente', 'parcial', 'total', 'anulado');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE letra_estado_enum AS ENUM ('emitida', 'pagada', 'vencida', 'protestada', 'anulada');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── medida_enum ────────────────────────────────────────────────
-- NOTE: This type likely already exists as a legacy type in your DB.
-- If applying to a FRESH DB, uncomment the block below.
-- DO $$
-- BEGIN
--     CREATE TYPE medida_enum AS ENUM ('g_L', 'g_kg', 'mL_L', 'mL_kg', '%');
-- EXCEPTION WHEN duplicate_object THEN NULL;
-- END $$;

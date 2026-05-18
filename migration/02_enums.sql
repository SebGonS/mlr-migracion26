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
    CREATE TYPE partida_estado_produccion_enum AS ENUM (
        'CREADA',        -- order created
        'PLANIFICADA',   -- full route (partida_paso rows) defined
        'PROGRAMADA',    -- scheduled on machines (programacion rows exist)
        'EN_PRODUCCION', -- first paso_ejecucion started
        'TECO',          -- all steps complete, pending closure
        'CERRADA',       -- settled
        'CANCELADA'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
    CREATE TYPE partida_estado_comercial_enum AS ENUM (
    'PENDIENTE',
    'ENTREGA_PARCIAL',
    'ENTREGADA',
    'DEVUELTA_PARCIAL',
    'DEVUELTA_TOTAL'
);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- partida_paso_estado_enum: kept for mes.lavado_maquina (needs PENDIENTE for scheduled washes)
DO $$
BEGIN
    CREATE TYPE partida_paso_estado_enum AS ENUM (
        'PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'OMITIDO'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Execution run state: no PENDIENTE — a run exists only when it has started
DO $$
BEGIN
    CREATE TYPE paso_ejecucion_estado_enum AS ENUM (
        'EN_PROCESO', 'COMPLETADO', 'OMITIDO'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE partida_tipo_enum AS ENUM ('NORMAL', 'REPROCESO');
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


DO $$
BEGIN
    CREATE TYPE tipo_pago_enum AS ENUM ('al contado', 'credito');
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

-- ── Facturación ────────────────────────────────────────────────

DO $$
BEGIN
    -- Lifecycle state of an emitted customer invoice
    CREATE TYPE factura_estado_enum AS ENUM (
        'borrador',   -- being built, not yet sent
        'emitida',    -- issued to client (sent / printed / FE submitted)
        'anulada'     -- voided (requires nota de crédito in SUNAT context)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    -- Billing progress on a sales order (partida), independent of production state.
    -- partida.estado tracks operational lifecycle; this tracks financial closure.
    CREATE TYPE partida_facturacion_enum AS ENUM (
        'pendiente',  -- no invoice issued yet
        'parcial',    -- at least one invoice line issued, not fully billed
        'facturado'   -- 100% of order value invoiced
    );
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

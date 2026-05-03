-- ═══════════════════════════════════════════════════════════════
-- Step 15: Alert infrastructure
-- Extends notification.notifications to support persistent,
-- system-resolved alerts alongside transient event notifications.
-- Creates alertas schema for cron functions.
-- Registers pg_cron schedules.
-- ═══════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS alertas;

-- ── Extend notification.notifications ───────────────────────────
-- objeto_tipo / objeto_id: link the alert back to the offending record.
-- fyh_resuelta: stamped by the system when the condition clears.
--   NULL  = condition still active.
--   NOT NULL = resolved, alert is historical.
--
-- Existing columns unchanged:
--   fyh_leido  = user acknowledged (read) — still valid for all types.
--   tipo CHECK ('info','warning','alert','task') — 'alert' already present.

ALTER TABLE notification.notifications
    ADD COLUMN IF NOT EXISTS objeto_tipo  TEXT,
    ADD COLUMN IF NOT EXISTS objeto_id    BIGINT,
    ADD COLUMN IF NOT EXISTS fyh_resuelta TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS categoria    TEXT;  -- alert subtype: 'stock_bajo' | 'partida_vencida' | 'rollo_sin_programar'

-- Deduplication: one active alert per user per (categoria × objeto_tipo × objeto_id).
-- Per-user so each recipient gets their own row, but no user gets the same alert twice.
-- Resolved by stamping fyh_resuelta = now() on all matching rows when condition clears.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_alerta_activa
    ON notification.notifications (user_id, categoria, objeto_tipo, objeto_id)
    WHERE tipo = 'alert' AND fyh_resuelta IS NULL;


-- ── pg_cron schedules ────────────────────────────────────────────
-- Requires pg_cron extension (enabled by default on Supabase).
-- All jobs call functions defined in funciones/alertas.sql.
-- Unschedule first to make this script idempotent on re-run.

SELECT cron.unschedule('alerta-partidas-vencidas')    FROM cron.job WHERE jobname = 'alerta-partidas-vencidas';
SELECT cron.unschedule('alerta-rollos-sin-programar') FROM cron.job WHERE jobname = 'alerta-rollos-sin-programar';
SELECT cron.unschedule('alerta-stock-bajo')           FROM cron.job WHERE jobname = 'alerta-stock-bajo';
SELECT cron.unschedule('alerta-stock-pasos')          FROM cron.job WHERE jobname = 'alerta-stock-pasos';

-- Daily at 8am (UTC-5 = 13:00 UTC for Peru)
SELECT cron.schedule(
    'alerta-partidas-vencidas',
    '0 13 * * *',
    $$ SELECT alertas.check_partidas_vencidas() $$
);

-- Daily at 8am
SELECT cron.schedule(
    'alerta-rollos-sin-programar',
    '0 13 * * *',
    $$ SELECT alertas.check_rollos_sin_programar() $$
);

-- Every 6 hours
SELECT cron.schedule(
    'alerta-stock-bajo',
    '0 */6 * * *',
    $$ SELECT alertas.check_stock_bajo() $$
);

-- Every 6 hours (offset by 30 min to avoid contention with stock-bajo)
SELECT cron.schedule(
    'alerta-stock-pasos',
    '30 */6 * * *',
    $$ SELECT alertas.check_stock_pasos() $$
);


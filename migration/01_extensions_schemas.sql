-- ═══════════════════════════════════════════════════════════════
-- Step 1: Extensions and Schemas
-- Must run first — all subsequent files depend on these.
-- ═══════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE SCHEMA IF NOT EXISTS mes;
CREATE SCHEMA IF NOT EXISTS inventario;    -- FIX: was CREATE SCHEMA (no IF NOT EXISTS) in tablas.sql
CREATE SCHEMA IF NOT EXISTS doc;
CREATE SCHEMA IF NOT EXISTS calidad;
CREATE SCHEMA IF NOT EXISTS receta;
CREATE SCHEMA IF NOT EXISTS audit;

-- Supabase storage bucket (only needed once, idempotent via ON CONFLICT)
INSERT INTO storage.buckets (id, name, public)
VALUES ('calidad', 'calidad', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Usuarios pueden subir iamgenes de QC"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'calidad');

CREATE POLICY "Usuarios pueden ver iamgenes de QC"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'calidad');

CREATE POLICY "Usuarios pueden borrar iamgenes de QC propios"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'calidad' AND auth.uid()::text = owner_id::text);

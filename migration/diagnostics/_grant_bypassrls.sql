-- Run once as superuser. RLS policies on doc.*/mes.*/etc. are scoped to the
-- 'authenticated' role (Supabase JWT users) — claude_ro doesn't match them,
-- so plain SELECT grants return 0 rows on RLS-enabled tables. BYPASSRLS only
-- affects reads here since claude_ro has no INSERT/UPDATE/DELETE grants.
ALTER ROLE claude_ro BYPASSRLS;

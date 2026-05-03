
--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO supabase_admin;

--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA extensions;


ALTER SCHEMA extensions OWNER TO postgres;

--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql;


ALTER SCHEMA graphql OWNER TO supabase_admin;

--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql_public;


ALTER SCHEMA graphql_public OWNER TO supabase_admin;

--
-- Name: iam; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA iam;


ALTER SCHEMA iam OWNER TO postgres;

--
-- Name: notification; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA notification;


ALTER SCHEMA notification OWNER TO postgres;

--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: pgbouncer
--

CREATE SCHEMA pgbouncer;


ALTER SCHEMA pgbouncer OWNER TO pgbouncer;

--
-- Name: pgsodium; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA pgsodium;


ALTER SCHEMA pgsodium OWNER TO supabase_admin;

--
-- Name: pgsodium; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgsodium WITH SCHEMA pgsodium;


--
-- Name: EXTENSION pgsodium; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgsodium IS 'Pgsodium is a modern cryptography library for Postgres.';


--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA realtime;


ALTER SCHEMA realtime OWNER TO supabase_admin;

--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA storage;


ALTER SCHEMA storage OWNER TO supabase_admin;

--
-- Name: supabase_migrations; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA supabase_migrations;


ALTER SCHEMA supabase_migrations OWNER TO postgres;

--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA vault;


ALTER SCHEMA vault OWNER TO supabase_admin;

--
-- Name: case_insensitive; Type: COLLATION; Schema: public; Owner: postgres
--

CREATE COLLATION public.case_insensitive (provider = icu, deterministic = false, locale = 'und-u-ks-level2');


ALTER COLLATION public.case_insensitive OWNER TO postgres;

--
-- Name: pg_graphql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;


--
-- Name: EXTENSION pg_graphql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_graphql IS 'pg_graphql: GraphQL support';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: pgjwt; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;


--
-- Name: EXTENSION pgjwt; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgjwt IS 'JSON Web Token API for Postgresql';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE auth.aal_level OWNER TO supabase_auth_admin;

--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


ALTER TYPE auth.code_challenge_method OWNER TO supabase_auth_admin;

--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE auth.factor_status OWNER TO supabase_auth_admin;

--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE auth.factor_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE auth.oauth_authorization_status OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE auth.oauth_client_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE auth.oauth_registration_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


ALTER TYPE auth.oauth_response_type OWNER TO supabase_auth_admin;

--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE auth.one_time_token_type OWNER TO supabase_auth_admin;

--
-- Name: cuadre_estado_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.cuadre_estado_enum AS ENUM (
    'borrador',
    'preparado',
    'ejecutado',
    'cancelado'
);


ALTER TYPE public.cuadre_estado_enum OWNER TO postgres;

--
-- Name: estado_entrada_inventario_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.estado_entrada_inventario_enum AS ENUM (
    'pendiente',
    'ajustado',
    'aprobado',
    'rechazado'
);


ALTER TYPE public.estado_entrada_inventario_enum OWNER TO postgres;

--
-- Name: estado_ingreso_compra_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.estado_ingreso_compra_enum AS ENUM (
    'pendiente',
    'parcial',
    'completo',
    'ajustado',
    'cancelado',
    'solicitado'
);


ALTER TYPE public.estado_ingreso_compra_enum OWNER TO postgres;

--
-- Name: estado_letra_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.estado_letra_enum AS ENUM (
    'emitida',
    'pagada',
    'vencida',
    'protestada',
    'anulada'
);


ALTER TYPE public.estado_letra_enum OWNER TO postgres;

--
-- Name: estado_pago_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.estado_pago_enum AS ENUM (
    'pendiente',
    'parcial',
    'total'
);


ALTER TYPE public.estado_pago_enum OWNER TO postgres;

--
-- Name: estado_salida_inventario_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.estado_salida_inventario_enum AS ENUM (
    'pendiente',
    'aprobado',
    'rechazado',
    'ajustado',
    'lavado maquina'
);


ALTER TYPE public.estado_salida_inventario_enum OWNER TO postgres;

--
-- Name: medida_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.medida_enum AS ENUM (
    'g/L',
    '%'
);


ALTER TYPE public.medida_enum OWNER TO postgres;

--
-- Name: motivo_entrada_inventario_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.motivo_entrada_inventario_enum AS ENUM (
    'compra',
    'ajuste',
    'devolucion',
    'transferencia',
    'reconteo',
    'muestra'
);


ALTER TYPE public.motivo_entrada_inventario_enum OWNER TO postgres;

--
-- Name: motivo_salida_inventario_enum; Type: TYPE; Schema: public; Owner: postgres
--

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

--
-- Name: tipo_insumo_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tipo_insumo_enum AS ENUM (
    'auxiliar',
    'directo',
    'disperso',
    'reactivo',
    'quimico'
);


ALTER TYPE public.tipo_insumo_enum OWNER TO postgres;

--
-- Name: tipo_pago_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tipo_pago_enum AS ENUM (
    'al contado',
    'credito'
);


ALTER TYPE public.tipo_pago_enum OWNER TO postgres;

--
-- Name: action; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


ALTER TYPE realtime.action OWNER TO supabase_admin;

--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in'
);


ALTER TYPE realtime.equality_op OWNER TO supabase_admin;

--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text
);


ALTER TYPE realtime.user_defined_filter OWNER TO supabase_admin;

--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


ALTER TYPE realtime.wal_column OWNER TO supabase_admin;

--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


ALTER TYPE realtime.wal_rls OWNER TO supabase_admin;

--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE storage.buckettype OWNER TO supabase_storage_admin;

--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION auth.email() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION auth.jwt() OWNER TO supabase_auth_admin;

--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION auth.role() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION auth.uid() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


--
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_cron_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$_$;


ALTER FUNCTION extensions.grant_pg_graphql_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_net_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_ddl_watch() OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_drop_watch() OWNER TO supabase_admin;

--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


ALTER FUNCTION extensions.set_graphql_placeholder() OWNER TO supabase_admin;

--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


--
-- Name: get_notificaciones(); Type: FUNCTION; Schema: notification; Owner: postgres
--

CREATE FUNCTION notification.get_notificaciones() RETURNS jsonb
    LANGUAGE sql
    AS $$
SELECT jsonb_agg(row_to_json(n))
FROM (
    SELECT n.*
    FROM notification.notifications n
    WHERE n.user_id = get_user_id()  
    ORDER BY n.fyh_cre DESC
    LIMIT 20
) AS n;
$$;


ALTER FUNCTION notification.get_notificaciones() OWNER TO postgres;

--
-- Name: leer_todas_notificaciones(); Type: FUNCTION; Schema: notification; Owner: postgres
--

CREATE FUNCTION notification.leer_todas_notificaciones() RETURNS void
    LANGUAGE sql
    AS $$
UPDATE notification.notifications
SET fyh_leido=NOW()
WHERE fyh_leido IS NULL
AND user_id=get_user_id()
$$;


ALTER FUNCTION notification.leer_todas_notificaciones() OWNER TO postgres;

--
-- Name: marcar_notificacion_leida(bigint); Type: FUNCTION; Schema: notification; Owner: postgres
--

CREATE FUNCTION notification.marcar_notificacion_leida(p_notification_id bigint) RETURNS void
    LANGUAGE sql
    AS $$
UPDATE notification.notifications
SET fyh_leido=NOW()
WHERE id=p_notification_id
AND fyh_leido IS NULL
AND user_id=get_user_id()
$$;


ALTER FUNCTION notification.marcar_notificacion_leida(p_notification_id bigint) OWNER TO postgres;

--
-- Name: notifications_cambios(); Type: FUNCTION; Schema: notification; Owner: postgres
--

CREATE FUNCTION notification.notifications_cambios() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  perform realtime.broadcast_changes(
    'topic:' || NEW.user_id::text,       -- topic - the topic to which you're broadcasting where you can use the topic id to build the topic name
    'notificacion',                                             -- event - the event that triggered the function
    TG_OP,                                             -- operation - the operation that triggered the function
    TG_TABLE_NAME,                                     -- table - the table that caused the trigger
    TG_TABLE_SCHEMA,                                   -- schema - the schema of the table that caused the trigger
    NEW,                                               -- new record - the record after the change
    OLD                                                -- old record - the record before the change
  );
  return null;
end;
$$;


ALTER FUNCTION notification.notifications_cambios() OWNER TO postgres;

--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: supabase_admin
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
begin
    raise debug 'PgBouncer auth request: %', p_usename;

    return query
    select 
        rolname::text, 
        case when rolvaliduntil < now() 
            then null 
            else rolpassword::text 
        end 
    from pg_authid 
    where rolname=$1 and rolcanlogin;
end;
$_$;


ALTER FUNCTION pgbouncer.get_auth(p_usename text) OWNER TO supabase_admin;

--
-- Name: ajustar_secuestrante_en_receta(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: approve_entrada_inventario(integer, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: approve_full_entrada_inventario(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.approve_full_entrada_inventario(entrada_id integer) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'iam', 'notification', 'public'
    AS $$DECLARE
    id_compra INT;
    msj_error TEXT;
    v_cantidad_restante INT;
    v_pk_compra INT;
    v_fyh_ingreso_real timestamptz;
BEGIN
    -- Ensure the entrada is still pending
    IF (SELECT estado FROM entrada_inventario WHERE id = entrada_id) <> 'pendiente' THEN
        RETURN 'Error: El ingreso ya fue aprobado o rechazado.';
    END IF;

    -- Check for excess in case of compra
    IF (SELECT motivo FROM entrada_inventario WHERE id = entrada_id) = 'compra' THEN
        WITH ingresos AS (
            SELECT
                eid.compra_x_insumo_id,
                ci.cantidad - SUM(eid.cantidad_recibida) AS cantidad_restante
            FROM entrada_inventario_detalle eid
            LEFT JOIN compra_x_insumo ci
              ON ci.id = eid.compra_x_insumo_id
              AND ci.id IN (
                  SELECT compra_x_insumo_id
                  FROM entrada_inventario_detalle
                  WHERE entrada_inventario_id = entrada_id
              )
            WHERE estado = 'aprobado'
            GROUP BY eid.compra_x_insumo_id, ci.cantidad
        )
        SELECT string_agg(
            format(
                'Insumo: %s excede el restante por ingresar %s de la compra',
                eid.cantidad_recibida, i.cantidad_restante
            ),
            E'\n'
        )
        INTO msj_error
        FROM ingresos i
        JOIN entrada_inventario_detalle eid
            ON i.compra_x_insumo_id = eid.compra_x_insumo_id
        WHERE eid.entrada_inventario_id = entrada_id
          AND i.cantidad_restante < eid.cantidad_recibida;

        IF msj_error IS NOT NULL THEN
            RETURN msj_error;
        END IF;
    END IF;

    -- Approve all lines
    UPDATE entrada_inventario_detalle
    SET
        cantidad_recibida = cantidad_solicitada,
        estado = 'aprobado'::estado_entrada_inventario_enum
    WHERE entrada_inventario_id = entrada_id;

    -- Update entrada
    UPDATE entrada_inventario
    SET
        estado = 'aprobado'::estado_entrada_inventario_enum,
        fyh_revision = CURRENT_TIMESTAMP,
        usr_revisa = get_user_id()
    WHERE id = entrada_id
    RETURNING fyh_entrada_real INTO v_fyh_ingreso_real;
    -- Insert into inventario
    INSERT INTO inventario(entrada_inventario_detalle_id, insumo_x_proveedor_id, cantidad,fyh_ingreso)
    SELECT id, insumo_x_proveedor_id, cantidad_recibida,v_fyh_ingreso_real
    FROM entrada_inventario_detalle
    WHERE entrada_inventario_id = entrada_id;

    -- Update compra if relevant
    IF (SELECT motivo FROM entrada_inventario WHERE id = entrada_id) = 'compra' THEN
        SELECT compra_id INTO v_pk_compra
        FROM entrada_inventario ei
            JOIN entrada_inventario_detalle eid ON ei.id = eid.entrada_inventario_id
            LEFT JOIN vw_compra_insumos cxi ON cxi.compra_x_insumo_id = eid.compra_x_insumo_id
        WHERE ei.id = entrada_id
        GROUP by compra_id
        LIMIT 1
        ;
    RAISE NOTICE 'Evaluando Compra';--'Debug: entrada_id = %', entrada_id;
        SELECT compra_id,SUM(COALESCE(cantidad_restante,0)) INTO id_compra,v_cantidad_restante
        FROM vw_compra_insumos cxi
        WHERE compra_id = v_pk_compra
        GROUP BY compra_id;
        IF NOT FOUND THEN
  id_compra := v_pk_compra;
  v_cantidad_restante := 0;
END IF;
RAISE NOTICE 'Debug: id_compra = %', id_compra;
RAISE NOTICE 'Debug: v_cantidad_restante = %', v_cantidad_restante;
       IF id_compra IS NOT NULL AND COALESCE(v_cantidad_restante, 0) = 0 THEN
           RAISE NOTICE 'Debug: Actualizando estado de compra a completo';
    UPDATE compra
    SET estado_ingreso = 'completo'::estado_ingreso_compra_enum
    WHERE id = id_compra;
ELSE
    RAISE NOTICE 'Debug: Actualizando estado de compra a parcial';
    UPDATE compra
    SET estado_ingreso = 'parcial'::estado_ingreso_compra_enum
    WHERE id = id_compra;
END IF;

    END IF;
    UPDATE compra
SET estado_ingreso='completo'
WHERE id IN(SELECT id FROM comrpas_pendientes_completas);

INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Solicitud de Ingreso Aprobada', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=get_user_id()),'sistema') || ' aprobó el ingreso total de la solicitud N°' || entrada_id, 'info',jsonb_build_object('objeto_tipo','entrada','objeto_id',entrada_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','compras');

    RETURN format('Ingreso #%s aprobado completamente.', entrada_id);
END;$$;


ALTER FUNCTION public.approve_full_entrada_inventario(entrada_id integer) OWNER TO postgres;

--
-- Name: aprobar_salida_inventario_total(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: cerrar_parada_tintoreria(integer, timestamp without time zone, text); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: crear_cuadre_inventario(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: delete_partida_x_receta(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: finalizar_cuadre_inventario(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: fn_delete_ejecucion_previa(bigint, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: fn_reasignar_fifo_orphan(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: generate_complete_recipe(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_result jsonb := '{}'::jsonb;
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
INSERT INTO logs_api (function_name, user_id, params)
VALUES (
  'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer)',
  get_user_id(),
  jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina
  )
);

    -- Main query consolidating all data sources
    SELECT peso_rollos
    INTO v_peso
    FROM partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La partida % no existe', p_partida_id;

    ELSIF v_peso IS NULL THEN
        RAISE EXCEPTION 'La partida % no ha sido pesada', p_partida_id
        USING DETAIL = jsonb_build_object(
  'function', 'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer)',
  'user_id', get_user_id(),
  'params', jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina
  )
)::text;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM maquina WHERE id = p_id_maquina) THEN
    RAISE EXCEPTION 'No se encontraron datos para la máquina ingresada.';
END IF;
IF NOT EXISTS (SELECT 1 FROM tipo_receta WHERE id = p_id_tipo_receta) THEN
    RAISE EXCEPTION 'No se encontro el tipo de receta especificada.';
END IF;


------ lógica antigua
-- WITH paritda_tipo_articulo as (SELECT * FROM partida JOIN articulo ON articulo_id=id)
--     SELECT id INTO v_receta_id
--     FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id 
--     AND r.flg_antipilling=(CASE WHEN p.adicional_id =1 AND p_id_tipo_receta=7 THEN true else false end)
--     WHERE r.flg_activo=true AND r.flg_produccion=true and p.id=p_partida_id
--     AND r.tipo_receta_id=p_id_tipo_receta;

-- IF v_receta_id IS NULL THEN RAISE  EXCEPTION 'No se encontro receta del tipo especificado para la partida'; END IF;


-- -- Materialize candidates into a temporary table
DROP TABLE IF EXISTS temp_candidates;
CREATE TEMP TABLE temp_candidates AS
WITH partida_tipo_articulo AS (
    SELECT p.*
         , a.id as id
         , a.tipo_articulo_id as tipo_articulo_id
    FROM partida p
    JOIN articulo a ON p.articulo_id = a.id
    WHERE p.id = p_partida_id
  )
SELECT
  r.id receta_id,
  r.tipo_receta_id,
  r.flg_activo,
  r.flg_produccion,
  (r.color_x_cliente_id = p.color_x_cliente_id) AS match_color,
  (r.tipo_articulo_id   = p.tipo_articulo_id)   AS match_tipo_articulo,
  (r.fibra              = p.fibra)              AS match_fibra,
  (r.tenido_id          = p.tenido_id)          AS match_tenido,
--   (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) AS match_antipilling,
CASE 
  WHEN p_id_tipo_receta = 7 THEN (r.flg_antipilling = (COALESCE(p.adicional_id,0) = 1))
  ELSE true
END AS match_antipilling,
  (r.tipo_receta_id = p_id_tipo_receta) AS match_tipo_receta,
  (
    (CASE WHEN r.color_x_cliente_id = p.color_x_cliente_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_articulo_id = p.tipo_articulo_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.fibra = p.fibra THEN 1 ELSE 0 END) +
    (CASE WHEN r.tenido_id = p.tenido_id THEN 1 ELSE 0 END) +
    (CASE WHEN (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_receta_id = p_id_tipo_receta THEN 1 ELSE 0 END)
  )/6.0 AS match_score,
  tr.tipo_receta,
  r.fyh_cre,
  r.fyh_produccion
FROM receta2 r
LEFT JOIN tipo_receta tr ON tr.id=r.tipo_receta_id
CROSS JOIN partida_tipo_articulo p
WHERE r.flg_activo = true
  AND r.flg_produccion = true;

-- Try to find exact match
SELECT receta_id INTO v_receta_id
FROM temp_candidates
WHERE match_color
  AND match_tipo_articulo
  AND match_fibra
  AND match_tenido
  AND match_antipilling
  AND match_tipo_receta
ORDER BY receta_id DESC
LIMIT 1;

-- If no exact match, return candidates
IF v_receta_id IS NULL THEN
    SELECT jsonb_build_object(
        'status', 'no_match',
        'message', 'No se encontro receta exacta para la partida y tipo solicitado.',
        'candidates', COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'receta_id', receta_id,
              'tipo_receta_id', tipo_receta_id,
              'tipo_receta', tipo_receta,
              'match_color', match_color,
              'match_tipo_articulo', match_tipo_articulo,
              'match_fibra', match_fibra,
              'match_tenido', match_tenido,
              'match_antipilling', match_antipilling,
              'match_tipo_receta', match_tipo_receta,
              'activo', flg_activo,
              'produccion', flg_produccion,
              'match_score', match_score,
              'fyh_cre', fyh_cre,
              'fyh_produccion',fyh_produccion
            ) ORDER BY match_score DESC, receta_id DESC
          ), '[]'::jsonb
        )
      ) INTO v_result
    FROM temp_candidates
    WHERE match_score >= 0.7;
    
    RETURN v_result;
END IF;

-- Clean up (optional, temp tables auto-drop at session end)
DROP TABLE IF EXISTS temp_candidates;

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
            m.id,
            p.cliente,
            p.rollos,
            p.articulo,
            p.peso,
            p.peso_rollos,
            p.peso_rib,
            p.color ||' - ' ||p.tono ||' - '|| p.tenido color,
            p.rib,
            -- Volume calculation logic
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND p.rollos <= 12 THEN p.peso * 7
                ELSE p.peso * m."RB"
            END as volumen,
            -- Recipe adjustment factor
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND p.rollos = 12 THEN 1.0 --1.08
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
    partidas AS (
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
        END as partida_pasos
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
        'maquina', d.id,
        'cliente', d.cliente,
        'rollos', d.rollos,
        'articulo', d.articulo,
        'peso', d.peso,
        'peso_rollos',d.peso_rollos,
           'peso_rib',d.peso_rib,
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
    'process_steps', ps.partida_pasos,
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
CROSS JOIN partidas ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer) OWNER TO postgres;

--
-- Name: generate_complete_recipe(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_result jsonb := '{}'::jsonb;
    v_partida_info JSON;
    v_receta_id int;
    v_receta_info JSON;
    v_maquina_info JSON;
    v_pasos JSON;
    v_volumen DECIMAL(10,2);
    v_peso DECIMAL(10,2);
    v_rollos INTEGER;
    v_rib INTEGER;
    v_rib_peso DECIMAL(10,2);
    v_rollos_peso DECIMAL(10,2);
    v_maquina_nombre TEXT;
BEGIN
INSERT INTO logs_api (function_name, user_id, params)
VALUES (
  'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer)',
  get_user_id(),
  jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina,
    'p_num_rollos', p_num_rollos
  )
);

    -- Main query consolidating all data sources
    SELECT 
    (CASE WHEN p_num_rollos IS NULL THEN
    peso_rollos
    ELSE 
    1.00*p_num_rollos*peso_rollos/rollos
    END)+COALESCE(peso_rib,0),rollos 
    INTO v_peso,
    v_rollos
    FROM partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La partida % no existe', p_partida_id;
    ELSIF v_peso IS NULL THEN
        RAISE EXCEPTION 'La partida % no ha sido pesada', p_partida_id
        USING DETAIL = jsonb_build_object(
  'function', 'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer)',
  'user_id', get_user_id(),
  'params', jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina,
    'p_num_rollos', p_num_rollos
  )
)::text;
    ELSIF p_num_rollos IS NOT NULL AND v_rollos < p_num_rollos THEN
        RAISE EXCEPTION 'Cantidad de rollos mayor a la de la partida %', p_partida_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM maquina WHERE id = p_id_maquina) THEN
    RAISE EXCEPTION 'No se encontraron datos para la máquina ingresada.';
END IF;
IF NOT EXISTS (SELECT 1 FROM tipo_receta WHERE id = p_id_tipo_receta) THEN
    RAISE EXCEPTION 'No se encontro el tipo de receta especificada.';
END IF;


------ lógica antigua
-- WITH paritda_tipo_articulo as (SELECT * FROM partida JOIN articulo ON articulo_id=id)
--     SELECT id INTO v_receta_id
--     FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id 
--     AND r.flg_antipilling=(CASE WHEN p.adicional_id =1 AND p_id_tipo_receta=7 THEN true else false end)
--     WHERE r.flg_activo=true AND r.flg_produccion=true and p.id=p_partida_id
--     AND r.tipo_receta_id=p_id_tipo_receta;

-- IF v_receta_id IS NULL THEN RAISE  EXCEPTION 'No se encontro receta del tipo especificado para la partida'; END IF;


-- -- Materialize candidates into a temporary table
DROP TABLE IF EXISTS temp_candidates;
CREATE TEMP TABLE temp_candidates AS
WITH partida_tipo_articulo AS (
    SELECT p.*
         , a.id as id
         , a.tipo_articulo_id as tipo_articulo_id
    FROM partida p
    JOIN articulo a ON p.articulo_id = a.id
    WHERE p.id = p_partida_id
  )
SELECT
  r.id receta_id,
  r.tipo_receta_id,
  r.flg_activo,
  r.flg_produccion,
  (r.color_x_cliente_id = p.color_x_cliente_id) AS match_color,
  (r.tipo_articulo_id   = p.tipo_articulo_id)   AS match_tipo_articulo,
  (r.fibra              = p.fibra)              AS match_fibra,
  (r.tenido_id          = p.tenido_id)          AS match_tenido,
--   (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) AS match_antipilling,
CASE 
  WHEN p_id_tipo_receta = 7 THEN (r.flg_antipilling = (COALESCE(p.adicional_id,0) = 1))
  ELSE true
END AS match_antipilling,
  (r.tipo_receta_id = p_id_tipo_receta) AS match_tipo_receta,
  (
    (CASE WHEN r.color_x_cliente_id = p.color_x_cliente_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_articulo_id = p.tipo_articulo_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.fibra = p.fibra THEN 1 ELSE 0 END) +
    (CASE WHEN r.tenido_id = p.tenido_id THEN 1 ELSE 0 END) +
    (CASE WHEN (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_receta_id = p_id_tipo_receta THEN 1 ELSE 0 END)
  )/6.0 AS match_score,
  tr.tipo_receta,
  r.fyh_cre,
  r.fyh_produccion
FROM receta2 r
LEFT JOIN tipo_receta tr ON tr.id=r.tipo_receta_id
CROSS JOIN partida_tipo_articulo p
WHERE r.flg_activo = true
  AND r.flg_produccion = true;

-- Try to find exact match
SELECT receta_id INTO v_receta_id
FROM temp_candidates
WHERE match_color
  AND match_tipo_articulo
  AND match_fibra
  AND match_tenido
  AND match_antipilling
  AND match_tipo_receta
ORDER BY receta_id DESC
LIMIT 1;

-- If no exact match, return candidates
IF v_receta_id IS NULL THEN
    SELECT jsonb_build_object(
        'status', 'no_match',
        'message', 'No se encontro receta exacta para la partida y tipo solicitado.',
        'candidates', COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'receta_id', receta_id,
              'tipo_receta_id', tipo_receta_id,
              'tipo_receta', tipo_receta,
              'match_color', match_color,
              'match_tipo_articulo', match_tipo_articulo,
              'match_fibra', match_fibra,
              'match_tenido', match_tenido,
              'match_antipilling', match_antipilling,
              'match_tipo_receta', match_tipo_receta,
              'activo', flg_activo,
              'produccion', flg_produccion,
              'match_score', match_score,
              'fyh_cre', fyh_cre,
              'fyh_produccion',fyh_produccion
            ) ORDER BY match_score DESC, receta_id DESC
          ), '[]'::jsonb
        )
      ) INTO v_result
    FROM temp_candidates
    WHERE match_score >= 0.7;
    
    RETURN v_result;
END IF;

-- Clean up (optional, temp tables auto-drop at session end)
DROP TABLE IF EXISTS temp_candidates;

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
            m.id,
            p.cliente,
            COALESCE(p_num_rollos,p.rollos) rollos,
            p.articulo,
            COALESCE(v_peso,p.peso) peso,
            COALESCE(1.00*p_num_rollos*p.peso_rollos/p.rollos,p.peso_rollos) peso_rollos,
            p.peso_rib,
            p.color ||' - ' ||p.tono ||' - '|| p.tenido color,
            p.rib,
            -- Volume calculation logic
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) <= 12 THEN COALESCE(v_peso,p.peso) * 7
                ELSE COALESCE(v_peso,p.peso) * m."RB"
            END as volumen,
            -- Recipe adjustment factor
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) = 12 THEN 1.0 --1.08
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
    partidas AS (
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
        END as partida_pasos
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
        'maquina', d.id,
        'cliente', d.cliente,
        'rollos', d.rollos,
        'articulo', d.articulo,
        'peso', d.peso,
        'peso_rollos',d.peso_rollos,
            'peso_rib',d.peso_rib,
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
    'process_steps', ps.partida_pasos,
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
CROSS JOIN partidas ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer) OWNER TO postgres;

--
-- Name: generate_complete_recipe(integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_result jsonb := '{}'::jsonb;
    v_partida_info JSON;
    v_receta_id int;
    v_receta_info JSON;
    v_maquina_info JSON;
    v_pasos JSON;
    v_volumen DECIMAL(10,2);
    v_peso DECIMAL(10,2);
    v_rollos INTEGER;
    v_rib INTEGER;
    v_rib_peso DECIMAL(10,2);
    v_rollos_peso DECIMAL(10,2);
    v_maquina_nombre TEXT;
BEGIN
INSERT INTO logs_api (function_name, user_id, params)
VALUES (
  'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer)',
  get_user_id(),
  jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina,
    'p_num_rollos', p_num_rollos,
    'p_rib', p_rib
  )
);

    -- Main query consolidating all data sources
    SELECT 
    (CASE WHEN p_num_rollos IS NULL THEN
    peso_rollos
    ELSE 
    1.00*p_num_rollos*peso_rollos/rollos
    END)+COALESCE(CASE WHEN p_rib IS NULL THEN
    peso_rib
    ELSE 
    1.00*p_rib*peso_rib/NULLIF(rib, 0)
    END,0),rollos,rib 
    INTO v_peso,
    v_rollos,v_rib
    FROM partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La partida % no existe', p_partida_id;
    ELSIF v_peso IS NULL THEN
        RAISE EXCEPTION 'La partida % no ha sido pesada', p_partida_id
        USING DETAIL = jsonb_build_object(
  'function', 'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer)',
  'user_id', get_user_id(),
  'params', jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina,
    'p_num_rollos', p_num_rollos,
    'p_rib', p_rib
  )
)::text;
    ELSIF p_num_rollos IS NOT NULL AND v_rollos < p_num_rollos THEN
        RAISE EXCEPTION 'Cantidad de rollos mayor a la de la partida %', p_partida_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM maquina WHERE id = p_id_maquina) THEN
    RAISE EXCEPTION 'No se encontraron datos para la máquina ingresada.';
END IF;
IF NOT EXISTS (SELECT 1 FROM tipo_receta WHERE id = p_id_tipo_receta) THEN
    RAISE EXCEPTION 'No se encontro el tipo de receta especificada.';
END IF;


------ lógica antigua
-- WITH paritda_tipo_articulo as (SELECT * FROM partida JOIN articulo ON articulo_id=id)
--     SELECT id INTO v_receta_id
--     FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id 
--     AND r.flg_antipilling=(CASE WHEN p.adicional_id =1 AND p_id_tipo_receta=7 THEN true else false end)
--     WHERE r.flg_activo=true AND r.flg_produccion=true and p.id=p_partida_id
--     AND r.tipo_receta_id=p_id_tipo_receta;

-- IF v_receta_id IS NULL THEN RAISE  EXCEPTION 'No se encontro receta del tipo especificado para la partida'; END IF;


-- -- Materialize candidates into a temporary table
DROP TABLE IF EXISTS temp_candidates;
CREATE TEMP TABLE temp_candidates AS
WITH partida_tipo_articulo AS (
    SELECT p.*
         , a.id as id
         , a.tipo_articulo_id as tipo_articulo_id
    FROM partida p
    JOIN articulo a ON p.articulo_id = a.id
    WHERE p.id = p_partida_id
  )
SELECT
  r.id receta_id,
  r.tipo_receta_id,
  r.flg_activo,
  r.flg_produccion,
  (r.color_x_cliente_id = p.color_x_cliente_id) AS match_color,
  (r.tipo_articulo_id   = p.tipo_articulo_id)   AS match_tipo_articulo,
  (r.fibra              = p.fibra)              AS match_fibra,
  (r.tenido_id          = p.tenido_id)          AS match_tenido,
--   (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) AS match_antipilling,
CASE 
  WHEN p_id_tipo_receta = 7 THEN (r.flg_antipilling = (COALESCE(p.adicional_id,0) = 1))
  ELSE true
END AS match_antipilling,
  (r.tipo_receta_id = p_id_tipo_receta) AS match_tipo_receta,
  (
    (CASE WHEN r.color_x_cliente_id = p.color_x_cliente_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_articulo_id = p.tipo_articulo_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.fibra = p.fibra THEN 1 ELSE 0 END) +
    (CASE WHEN r.tenido_id = p.tenido_id THEN 1 ELSE 0 END) +
    (CASE WHEN (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_receta_id = p_id_tipo_receta THEN 1 ELSE 0 END)
  )/6.0 AS match_score,
  tr.tipo_receta,
  r.fyh_cre,
  r.fyh_produccion
FROM receta2 r
LEFT JOIN tipo_receta tr ON tr.id=r.tipo_receta_id
CROSS JOIN partida_tipo_articulo p
WHERE r.flg_activo = true
  AND r.flg_produccion = true;

-- Try to find exact match
SELECT receta_id INTO v_receta_id
FROM temp_candidates
WHERE match_color
  AND match_tipo_articulo
  AND match_fibra
  AND match_tenido
  AND match_antipilling
  AND match_tipo_receta
ORDER BY receta_id DESC
LIMIT 1;

-- If no exact match, return candidates
IF v_receta_id IS NULL THEN
    SELECT jsonb_build_object(
        'status', 'no_match',
        'message', 'No se encontro receta exacta para la partida y tipo solicitado.',
        'candidates', COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'receta_id', receta_id,
              'tipo_receta_id', tipo_receta_id,
              'tipo_receta', tipo_receta,
              'match_color', match_color,
              'match_tipo_articulo', match_tipo_articulo,
              'match_fibra', match_fibra,
              'match_tenido', match_tenido,
              'match_antipilling', match_antipilling,
              'match_tipo_receta', match_tipo_receta,
              'activo', flg_activo,
              'produccion', flg_produccion,
              'match_score', match_score,
              'fyh_cre', fyh_cre,
              'fyh_produccion',fyh_produccion
            ) ORDER BY match_score DESC, receta_id DESC
          ), '[]'::jsonb
        )
      ) INTO v_result
    FROM temp_candidates
    WHERE match_score >= 0.7;
    
    RETURN v_result;
END IF;

-- Clean up (optional, temp tables auto-drop at session end)
DROP TABLE IF EXISTS temp_candidates;

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
            m.id,
            p.cliente,
            COALESCE(p_num_rollos,p.rollos) rollos,
            p.articulo,
            COALESCE(v_peso,p.peso) peso,
            COALESCE(1.00*p_num_rollos*p.peso_rollos/p.rollos,p.peso_rollos) peso_rollos,
            COALESCE(1.00*p_rib*p.peso_rib/NULLIF(p.rib, 0), p.peso_rib) peso_rib,
            p.color ||' - ' ||p.tono ||' - '|| p.tenido color,
            COALESCE(p_rib,p.rib) as rib,
            -- Volume calculation logic
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) <= 12 THEN COALESCE(v_peso,p.peso) * 7
                ELSE COALESCE(v_peso,p.peso) * m."RB"
            END as volumen,
            -- Recipe adjustment factor
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) = 12 THEN 1.0 --1.08
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
    partidas AS (
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
        END as partida_pasos
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
        'maquina', d.id,
        'cliente', d.cliente,
        'rollos', d.rollos,
        'articulo', d.articulo,
        'peso', d.peso,
        'peso_rollos',d.peso_rollos,
            'peso_rib',d.peso_rib,
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
    'process_steps', ps.partida_pasos,
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
CROSS JOIN partidas ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer) OWNER TO postgres;

--
-- Name: generate_complete_recipe(integer, integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer, p_relacion_bano integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$DECLARE
    v_result jsonb := '{}'::jsonb;
    v_partida_info JSON;
    v_receta_id int;
    v_receta_info JSON;
    v_maquina_info JSON;
    v_pasos JSON;
    v_volumen DECIMAL(10,2);
    v_peso DECIMAL(10,2);
    v_rollos INTEGER;
    v_rib INTEGER;
    v_rib_peso DECIMAL(10,2);
    v_rollos_peso DECIMAL(10,2);
    v_maquina_nombre TEXT;
BEGIN
INSERT INTO logs_api (function_name, user_id, params)
VALUES (
  'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer, p_relacion_bano)',
  get_user_id(),
  jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina,
    'p_num_rollos', p_num_rollos,
    'p_rib', p_rib,
    'p_relacion_bano',p_relacion_bano
  )
);

    -- Main query consolidating all data sources
    SELECT 
    (CASE WHEN p_num_rollos IS NULL THEN
    peso_rollos
    ELSE 
    1.00*p_num_rollos*peso_rollos/rollos
    END)+COALESCE(CASE WHEN p_rib IS NULL THEN
    peso_rib
    ELSE 
    1.00*p_rib*peso_rib/NULLIF(rib, 0)
    END,0),rollos,rib 
    INTO v_peso,
    v_rollos,v_rib
    FROM partida
    WHERE id = p_partida_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La partida % no existe', p_partida_id;
    ELSIF v_peso IS NULL THEN
        RAISE EXCEPTION 'La partida % no ha sido pesada', p_partida_id
        USING DETAIL = jsonb_build_object(
  'function', 'generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_relacion_bano, p_num_rollos integer, p_rib integer)',
  'user_id', get_user_id(),
  'params', jsonb_build_object(
    'p_partida_id', p_partida_id,
    'p_id_tipo_receta', p_id_tipo_receta,
    'p_id_maquina', p_id_maquina,
    'p_num_rollos', p_num_rollos,
    'p_rib', p_rib
  )
)::text;
    ELSIF p_num_rollos IS NOT NULL AND v_rollos < p_num_rollos THEN
        RAISE EXCEPTION 'Cantidad de rollos mayor a la de la partida %', p_partida_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM maquina WHERE id = p_id_maquina) THEN
    RAISE EXCEPTION 'No se encontraron datos para la máquina ingresada.';
END IF;
IF NOT EXISTS (SELECT 1 FROM tipo_receta WHERE id = p_id_tipo_receta) THEN
    RAISE EXCEPTION 'No se encontro el tipo de receta especificada.';
END IF;


------ lógica antigua
-- WITH paritda_tipo_articulo as (SELECT * FROM partida JOIN articulo ON articulo_id=id)
--     SELECT id INTO v_receta_id
--     FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id 
--     AND r.flg_antipilling=(CASE WHEN p.adicional_id =1 AND p_id_tipo_receta=7 THEN true else false end)
--     WHERE r.flg_activo=true AND r.flg_produccion=true and p.id=p_partida_id
--     AND r.tipo_receta_id=p_id_tipo_receta;

-- IF v_receta_id IS NULL THEN RAISE  EXCEPTION 'No se encontro receta del tipo especificado para la partida'; END IF;


-- -- Materialize candidates into a temporary table
DROP TABLE IF EXISTS temp_candidates;
CREATE TEMP TABLE temp_candidates AS
WITH partida_tipo_articulo AS (
    SELECT p.*
         , a.id as id
         , a.tipo_articulo_id as tipo_articulo_id
    FROM partida p
    JOIN articulo a ON p.articulo_id = a.id
    WHERE p.id = p_partida_id
  )
SELECT
  r.id receta_id,
  r.tipo_receta_id,
  r.flg_activo,
  r.flg_produccion,
  (r.color_x_cliente_id = p.color_x_cliente_id) AS match_color,
  (r.tipo_articulo_id   = p.tipo_articulo_id)   AS match_tipo_articulo,
  (r.fibra              = p.fibra)              AS match_fibra,
  (r.tenido_id          = p.tenido_id)          AS match_tenido,
--   (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) AS match_antipilling,
CASE 
  WHEN p_id_tipo_receta = 7 THEN (r.flg_antipilling = (COALESCE(p.adicional_id,0) = 1))
  ELSE true
END AS match_antipilling,
  (r.tipo_receta_id = p_id_tipo_receta) AS match_tipo_receta,
  (
    (CASE WHEN r.color_x_cliente_id = p.color_x_cliente_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_articulo_id = p.tipo_articulo_id THEN 1 ELSE 0 END) +
    (CASE WHEN r.fibra = p.fibra THEN 1 ELSE 0 END) +
    (CASE WHEN r.tenido_id = p.tenido_id THEN 1 ELSE 0 END) +
    (CASE WHEN (r.flg_antipilling = (CASE WHEN p.adicional_id = 1 AND p_id_tipo_receta = 7 THEN true ELSE false END)) THEN 1 ELSE 0 END) +
    (CASE WHEN r.tipo_receta_id = p_id_tipo_receta THEN 1 ELSE 0 END)
  )/6.0 AS match_score,
  tr.tipo_receta,
  r.fyh_cre,
  r.fyh_produccion
FROM receta2 r
LEFT JOIN tipo_receta tr ON tr.id=r.tipo_receta_id
CROSS JOIN partida_tipo_articulo p
WHERE r.flg_activo = true
  AND r.flg_produccion = true;

-- Try to find exact match
SELECT receta_id INTO v_receta_id
FROM temp_candidates
WHERE match_color
  AND match_tipo_articulo
  AND match_fibra
  AND match_tenido
  AND match_antipilling
  AND match_tipo_receta
ORDER BY receta_id DESC
LIMIT 1;

-- If no exact match, return candidates
IF v_receta_id IS NULL THEN
    SELECT jsonb_build_object(
        'status', 'no_match',
        'message', 'No se encontro receta exacta para la partida y tipo solicitado.',
        'candidates', COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'receta_id', receta_id,
              'tipo_receta_id', tipo_receta_id,
              'tipo_receta', tipo_receta,
              'match_color', match_color,
              'match_tipo_articulo', match_tipo_articulo,
              'match_fibra', match_fibra,
              'match_tenido', match_tenido,
              'match_antipilling', match_antipilling,
              'match_tipo_receta', match_tipo_receta,
              'activo', flg_activo,
              'produccion', flg_produccion,
              'match_score', match_score,
              'fyh_cre', fyh_cre,
              'fyh_produccion',fyh_produccion
            ) ORDER BY match_score DESC, receta_id DESC
          ), '[]'::jsonb
        )
      ) INTO v_result
    FROM temp_candidates
    WHERE match_score >= 0.7;
    
    RETURN v_result;
END IF;

-- Clean up (optional, temp tables auto-drop at session end)
DROP TABLE IF EXISTS temp_candidates;

    WITH 
    maquina_data AS (
        SELECT 
            id,
            nombre,
            COALESCE(p_relacion_bano,"RB") as "RB"
        FROM maquina 
        WHERE id = p_id_maquina AND "RB" IS NOT NULL
    ),
    data AS (
        SELECT 
            'MLR - TINTORERÍA - RECETA ' || UPPER(r.tipo_receta) titulo,
            now() fecha,
            r.receta_id,
            p.partida,
            m.id,
            p.cliente,
            COALESCE(p_num_rollos,p.rollos) rollos,
            p.articulo,
            COALESCE(v_peso,p.peso) peso,
            COALESCE(1.00*p_num_rollos*p.peso_rollos/p.rollos,p.peso_rollos) peso_rollos,
            COALESCE(1.00*p_rib*p.peso_rib/NULLIF(p.rib, 0), p.peso_rib) peso_rib,
            p.color ||' - ' ||p.tono ||' - '|| p.tenido color,
            COALESCE(p_rib,p.rib) as rib,
            -- Volume calculation logic
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) <= 12 THEN COALESCE(v_peso,p.peso) * 7
                ELSE COALESCE(v_peso,p.peso) * m."RB"
            END as volumen,
            -- Recipe adjustment factor
            CASE 
                WHEN m.nombre != 'BRAZOLI (1)' AND COALESCE(p_num_rollos,p.rollos) = 12 THEN 1.0 --1.08
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
    partidas AS (
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
        END as partida_pasos
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
        'maquina', d.id,
        'cliente', d.cliente,
        'rollos', d.rollos,
        'articulo', d.articulo,
        'peso', d.peso,
        'peso_rollos',d.peso_rollos,
            'peso_rib',d.peso_rib,
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
    'process_steps', ps.partida_pasos,
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
CROSS JOIN partidas ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_complete_recipe(p_partida_id integer, p_id_tipo_receta integer, p_id_maquina integer, p_num_rollos integer, p_rib integer, p_relacion_bano integer) OWNER TO postgres;

--
-- Name: generate_recipe(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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
    partidas AS (
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
        END as partida_pasos
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
    'process_steps', ps.partida_pasos,
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
CROSS JOIN partidas ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_recipe(p_partida_id integer, p_id_receta integer, p_id_maquina integer) OWNER TO postgres;

--
-- Name: generate_recipe(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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
    partidas AS (
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
        END as partida_pasos
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
    'process_steps', ps.partida_pasos,
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
CROSS JOIN partidas ps;

    RETURN v_result;
END;$$;


ALTER FUNCTION public.generate_recipe(p_partida_id integer, p_id_receta integer, p_id_maquina integer, p_num_rollos integer) OWNER TO postgres;

--
-- Name: get_componentes_matizado(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_componentes_matizado(partida_param integer) RETURNS TABLE(partida integer, componente text, cantidad double precision, medida text)
    LANGUAGE sql
    AS $$
select a.partida_id,b.insumo componente,a.cantidad,a.medida
from matizado a
join insumo b on a.insumo_id = b.id
WHERE a.partida_id = partida_param;
$$;


ALTER FUNCTION public.get_componentes_matizado(partida_param integer) OWNER TO postgres;

--
-- Name: get_compra_detalles(text); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_cuadre_inventario(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_distinct_tonos(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_distinct_tonos() RETURNS TABLE(tono text)
    LANGUAGE sql
    AS $$
  SELECT DISTINCT tono tono FROM color;
$$;


ALTER FUNCTION public.get_distinct_tonos() OWNER TO postgres;

--
-- Name: get_entrada_inventario_detalles(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_info_partida(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_info_partida_tenido(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_info_partida_tenido(partida_param integer, tipo_receta_param integer) RETURNS TABLE(partida integer, rollos integer, rib integer, peso double precision, duracion interval)
    LANGUAGE sql
    AS $$
SELECT
    a.id partida,
    a.rollos,
    a.rib,
    a.peso_rollos + a.peso_rib peso,
    te_std.duracion
FROM partida a 
LEFT JOIN color_x_cliente b 
    ON a.color_x_cliente_id = b.id
LEFT JOIN tiempos_estandar_tenido te_std 
ON 
  te_std.tipo_receta_id = tipo_receta_param AND
  te_std.valor_id = b.valor_id AND
  (
    (tipo_receta_param in (4,7,14) AND
     te_std.tenido_id = a.tenido_id AND 
     coalesce(te_std.adicional_id, 0) = coalesce(a.adicional_id, 0))
    OR tipo_receta_param not in (4,7,14)
  )
    AND te_std.flg_activo IS TRUE
WHERE a.id = partida_param;
$$;


ALTER FUNCTION public.get_info_partida_tenido(partida_param integer, tipo_receta_param integer) OWNER TO postgres;

--
-- Name: get_insumo_movimientos_cuadre(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_insumo_movimientos_rango(integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_inventario_insumo_lotes(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_lavado_maquina_detalles(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_letras_compra(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_max_pk_partida(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_partida(integer); Type: FUNCTION; Schema: public; Owner: postgres
--


SELECT 
'partida_id',p.id,
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
        'color_x_cliente_id',p.color_x_client_ied,
        'adicional_id',adicional_id,
        'observacion',p.observacion,
        'extras', ( --pendiente de modificar para agregar extras (paquetes de cuellos y de puños)
            SELECT json_agg(sub)
            FROM (
                SELECT extra_id,extra,cantidad FROM partida_x_extra 
                JOIN extra ON extra_id=id
                WHERE partida_id=7000 
            ) sub
        )
    
    FROM partida p
    WHERE p.id = 7000;

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
        'color_x_cliente_id',p.color_x_client_ied,
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

--
-- Name: get_partidas_despacho(integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_partidas_despacho(partida_param integer[]) RETURNS TABLE(partida integer, cliente text, articulo text, color text, rollos integer, rib integer, tenido text, malla text, fibra text, ancho text, rndmto text, antipil text, precio_tenido double precision, precio_antipil double precision, observacion text)
    LANGUAGE sql
    AS $$
WITH colores AS (
    SELECT
        color_x_cliente.id,
        color.color,
        cliente.cliente AS tono
    FROM color_x_cliente
    LEFT JOIN color ON color.id = color_x_cliente.color_id
    LEFT JOIN cliente ON color_x_cliente.cliente_id = cliente.id
)
SELECT
    part.id AS partida,
    cli.cliente,
    art.articulo,
    col.color,
    part.rollos,
    part.rib,
    ten.tenido,
    malla,
    part.fibra,
    ancho,
    rendimiento,
    COALESCE(ad.adicional, '') AS antipil,
    pre.precio_tenido,
    case when cli.cliente = 'Urban' then 0.15 else 0.1 end precio_antipil,
    observacion
FROM partida part
LEFT JOIN cliente cli ON cli.id = part.cliente_id
LEFT JOIN articulo art ON art.id = part.articulo_id
LEFT JOIN colores col ON col.id = part.color_x_cliente_id
LEFT JOIN tenido ten ON ten.id = part.tenido_id
LEFT JOIN adicional ad ON ad.id = part.adicional_id
LEFT JOIN catalogo_precios pre on pre.activo = 1 and part.color_x_cliente_id = pre.color_x_cliente_id and part.tenido_id= pre.tenido_id and part.fibra = pre.fibra and 
case
    when (art.tipo_articulo_id  in (4,8,9,10,11,12,14,15,17,18,20)) and part.cliente_id in (1,11,22) then 20
    when  art.tipo_articulo_id  in (4,9,18)   then 18
    when  art.tipo_articulo_id  in (8,12)     then 12
    when  art.tipo_articulo_id  in (10,14,17) then 14
    when  art.tipo_articulo_id in (16,22,23) then 16
    else  art.tipo_articulo_id  end
= pre.tipo_articulo_id 
WHERE part.id = ANY(partida_param);
$$;


ALTER FUNCTION public.get_partidas_despacho(partida_param integer[]) OWNER TO postgres;

--
-- Name: get_productos_compra(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_proyeccion_tenido(json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_proyeccion_tenido(json) RETURNS TABLE(maquina_id smallint, orden integer, tipo_registro text, id text, color text, tenido text, valor text, adicional text, kilos numeric, duracion interval, hora_inicio interval, hora_fin interval, peso_produccion numeric)
    LANGUAGE plpgsql
    AS $_$
declare
  payload alias for $1;
  hora_inicio_param time;
begin
  hora_inicio_param := (payload->>'hora_inicio')::time;
  return query
  with datos_teñido as (
    select 
      pt.maquina_id,
      pt.orden,
      'Partida'::text as tipo_registro,
      pa.id::text,
      co.color,
      te.tenido,
      val.valor,
      ad.adicional,
      case
        when peso_rollos is null then pa.rollos * 21 + pa.rib * 12
        else (peso_rollos + peso_rib)::numeric
      end as kilos,
      te_std.duracion
    from programa_tenido pt
    join partida pa on pt.partida_id = pa.id
    left join color_x_cliente cxc on pa.color_x_cliente_id = cxc.id
    left join color co on cxc.color_id = co.id
    left join tenido te on pa.tenido_id= te.id
    left join valor val on cxc.valor_id = val.id
    left join adicional ad on pa.adicional_id = ad.id
    left join tiempos_estandar_tenido te_std on 
      te_std.valor_id = val.id and
      te_std.tenido_id = te.id and
      coalesce(te_std.adicional_id, 0) = coalesce(pa.adicional_id, 0)
    where pt.fecha = current_date
  ),
  datos_lavado as (
    select 
      pt.maquina_id,
      pt.orden,
      'Lavado'::text as tipo_registro,
      null::text as id,
      null::text as color,
      null::text as tenido,
      null::text as valor,
      null::text as adicional,
      null::numeric as kilos,
      lstd.duracion
    from programa_tenido pt
    join tipo_lavado_maquina tl on pt.tipo_lavado_mq_id = tl.id
    left join tiempos_estandar_lavado lstd on lstd.tipo_lavado_mq_id = pt.tipo_lavado_mq_id
    where pt.fecha = current_date
  ),
  en_partida as (
    select 
      pt.maquina_id,
      pt.orden,
      'Partida'::text as tipo_registro,
      pa.id::text,
      co.color,
      te.tenido,
      val.valor,
      ad.adicional,
      (peso_rollos + peso_rib)::numeric - p.kilos as kilos,
      greatest(interval '0', te_std.duracion - p.duracion::interval) as duracion
    from produccion_tenido p 
    join programa_tenido pt on pt.partida_id = p.partida_id
    join partida pa on pa.id = p.partida_id
    left join color_x_cliente cxc on pa.color_x_cliente_id = cxc.id
    left join color co on cxc.color_id = co.id
    left join tenido te on pa.tenido_id= te.id
    left join valor val on cxc.valor_id = val.id
    left join adicional ad on pa.adicional_id = ad.id
    left join tiempos_estandar_tenido te_std on 
      te_std.valor_id = val.id and
      te_std.tenido_id = te.id and
      coalesce(te_std.adicional_id, 0) = coalesce(pa.adicional_id, 0)
    where p.estado = 'En partida Teñido'
      and pt.fecha = current_date
      and p.fecha between current_date - 1 and current_date
  ),
  union_total as (
    select a.* from datos_teñido a 
    left join en_partida b 
      on a.id = b.id and a.maquina_id = b.maquina_id 
    where b.id is null
    union all
    select * from datos_lavado
    union all
    select * from en_partida
  ),
  con_horas as (
    select *,
      make_interval(hours => extract(hour from hora_inicio_param)::int) +
      make_interval(minutes => extract(minute from hora_inicio_param)::int) +
      sum(coalesce(duracion, interval '0')) over (
        partition by maquina_id 
        order by orden
      ) - coalesce(duracion, interval '0') as hora_inicio,

      make_interval(hours => extract(hour from hora_inicio_param)::int) +
      make_interval(minutes => extract(minute from hora_inicio_param)::int) +
      sum(coalesce(duracion, interval '0')) over (
        partition by maquina_id 
        order by orden
      ) as hora_fin
    from union_total
  )
  select *,
    case
      when tipo_registro = 'Lavado' then null
      when hora_inicio >= interval '24 hours' + make_interval(hours => extract(hour from hora_inicio_param)::int) then 0
      when hora_fin <= interval '24 hours' + make_interval(hours => extract(hour from hora_inicio_param)::int) then kilos
      else
        round((
          extract(epoch from (interval '24 hours' + make_interval(hours => extract(hour from hora_inicio_param)::int) - hora_inicio)) /
          nullif(extract(epoch from duracion), 0)
          * kilos
        )::numeric, 2)
    end as peso_produccion
  from con_horas
  order by maquina_id, orden;
end;
$_$;


ALTER FUNCTION public.get_proyeccion_tenido(json) OWNER TO postgres;

--
-- Name: get_proyeccion_tenido_por_maquina(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_rb_maquina(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_rb_maquina(id_maquina_param integer) RETURNS TABLE(id integer, nombre text, rb numeric)
    LANGUAGE sql SECURITY DEFINER
    AS $$
    SELECT id, nombre,"RB" as rb
    FROM maquina
    WHERE id = id_maquina_param;
$$;


ALTER FUNCTION public.get_rb_maquina(id_maquina_param integer) OWNER TO postgres;

--
-- Name: get_receta_by_partida(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_receta_detalles(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_receta_detalles(p_receta_id integer) RETURNS json
    LANGUAGE plpgsql
    AS $$DECLARE
    receta_json jsonb;
BEGIN
    SELECT json_build_object(
        'receta_id', p_receta_id,
        'color_x_cliente_id', r.color_x_cliente_id,
        'color_tono', c.color || ' - ' || cl.cliente,
        'tipo_articulo_id', r.tipo_articulo_id,
        'tenido_id', r.tenido_id,
        'fibra', CAST(r.fibra AS SMALLINT),
        'tipo_receta_id', r.tipo_receta_id,
        'pasos', (
            SELECT json_agg(sub ORDER BY orden)
            FROM (
                SELECT 
                    ('10' || rp.id::text)::BIGINT as id,
                    orden, 1 as tipo, paso_id AS fk, paso AS nombre,
                    NULL::NUMERIC AS cantidad, NULL::medida_enum AS medida,
                    NULL AS tipo_insumo, NULL::NUMERIC AS precio, NULL::NUMERIC AS costo, NULL::NUMERIC AS costo_12r
                FROM receta_x_paso rp
                JOIN paso p2 ON rp.paso_id = p2.id
                WHERE rp.receta_id = p_receta_id

                UNION

                SELECT 
                    ('20' || ri.id::text)::BIGINT as id,
                    orden, 2 as tipo, insumo_id AS fk, insumo AS nombre,
                    cantidad, medida, i.tipo,i.precio_prom_kg_usd,
                    CASE 
                        WHEN i.medida = 'g/L' THEN ((5 * cantidad)/1000) * i.precio_prom_kg_usd
                        WHEN i.medida = '%'   THEN ((1 * cantidad * 10)/1000) * i.precio_prom_kg_usd
                        ELSE NULL
                    END AS costo,
                    CASE 
                        WHEN i.medida = 'g/L' THEN ((7 * cantidad)/1000) * i.precio_prom_kg_usd
                        WHEN i.medida = '%'   THEN ((1 * cantidad * 10)/1000) * i.precio_prom_kg_usd
                        ELSE NULL
                    END AS costo_12r
                FROM receta_x_insumo ri
                JOIN insumo i ON ri.insumo_id = i.id
                WHERE ri.receta_id = p_receta_id
            ) sub
        )
    ) INTO receta_json
    FROM receta2 r
    JOIN color_x_cliente cc ON cc.id = r.color_x_cliente_id
    JOIN color c ON cc.color_id = c.id
    JOIN cliente cl ON cc.cliente_id = cl.id
    WHERE r.id = p_receta_id;

    RETURN receta_json;
END;$$;


ALTER FUNCTION public.get_receta_detalles(p_receta_id integer) OWNER TO postgres;

--
-- Name: get_receta_detalles_partida(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_receta_detalles_partida(partida_id integer) RETURNS json
    LANGUAGE plpgsql
    AS $$DECLARE
    receta_json JSON;
    v_receta_id int;
BEGIN
    WITH paritda_tipo_articulo as (SELECT 
    p.*,
    a.articulo,
    a.tipo_articulo_id,
    a.grupo_articulo
     FROM partida p JOIN articulo a ON p.articulo_id=a.id)
    SELECT r.id INTO v_receta_id
    FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id 
    AND r.flg_antipilling=(CASE WHEN p.adicional_id =1 AND id_tipo_receta=7 THEN true else false end)
    WHERE r.flg_activo=true and r.flg_produccion=true and p.id=partida_id
    AND r.tipo_receta_id=id_tipo_receta;
    SELECT json_build_object(
        'receta_id',v_receta_id,
        'color_x_cliente_id', p.color_x_cliente_id,
        'color_tono', c.color || ' - ' || cl.cliente,
        'tipo_articulo_id', art.tipo_articulo_id,
        'tenido_id', p.tenido_id,
        'fibra', CAST(p.fibra AS SMALLINT),
        'pasos', (
            SELECT json_agg(sub ORDER BY orden)
            FROM (
                SELECT orden, 1 as tipo, paso_id AS fk, paso AS nombre, NULL::NUMERIC AS cantidad, NULL::medida_enum AS medida,NULL tipo_insumo, NULL::NUMERIC AS precio, NULL::numeric as costo, NULL::NUMERIC AS costo_12r
                FROM receta_x_paso rp
                JOIN paso p2 ON rp.paso_id = p2.id
                WHERE rp.receta_id = v_receta_id
                UNION
                SELECT orden, 2 as tipo, insumo_id AS fk, insumo AS nombre, cantidad, medida, i.tipo,i.precio_prom_kg_usd,
                  CASE 
                  when i.medida = 'g/L' then ((5*cantidad)/1000)*i.precio_prom_kg_usd
                  when i.medida = '%' then ((1*cantidad*10)/1000)*i.precio_prom_kg_usd
                  END,
                    CASE 
                        WHEN i.medida = 'g/L' THEN ((7 * cantidad)/1000) * i.precio_prom_kg_usd
                        WHEN i.medida = '%'   THEN ((1 * cantidad * 10)/1000) * i.precio_prom_kg_usd
                        ELSE NULL
                    END AS costo_12r
                FROM receta_x_insumo ri
                JOIN insumo i ON ri.insumo_id = i.id
                WHERE ri.receta_id = v_receta_id
            ) sub
        )
    ) INTO receta_json
    FROM partida p
    JOIN color_x_cliente cc ON cc.id = p.color_x_cliente_id
    JOIN color c ON cc.color_id = c.id
    JOIN cliente cl ON cc.cliente_id = cl.id
    JOIN articulo art ON p.articulo_id=art.id
    WHERE p.id = partida_id;

    RETURN receta_json;
END;$$;


ALTER FUNCTION public.get_receta_detalles_partida(partida_id integer) OWNER TO postgres;

--
-- Name: get_receta_detalles_partida(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_receta_detalles_partida(partida_id integer, id_tipo_receta integer) RETURNS json
    LANGUAGE plpgsql
    AS $$DECLARE
    receta_json JSON;
    v_receta_id int;
BEGIN
insert into logs_api(function_name, user_id, params)
values ('get_receta_detalles_partida', get_user_id(), jsonb_build_object('partida_id', partida_id,'id_tipo_receta',id_tipo_receta));

    WITH paritda_tipo_articulo as (SELECT 
    p.*,
    a.articulo,
    a.tipo_articulo_id,
    a.grupo_articulo
     FROM partida p JOIN articulo a ON p.articulo_id=a.id)
    SELECT r.id INTO v_receta_id
    FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id 
    AND r.flg_antipilling=(CASE WHEN p.adicional_id =1 AND id_tipo_receta=7 THEN true else false end)
    WHERE r.flg_activo=true and r.flg_produccion=true and p.id=partida_id
    AND r.tipo_receta_id=id_tipo_receta;

    SELECT json_build_object(
        'receta_id',v_receta_id,
        'color_x_cliente_id', p.color_x_cliente_id,
        'color_tono', c.color || ' - ' || cl.cliente,
        'tipo_articulo_id', art.tipo_articulo_id,
        'tenido_id', p.tenido_id,
        'fibra', CAST(p.fibra AS SMALLINT),
        'pasos', (
            SELECT json_agg(sub ORDER BY orden)
            FROM (
                SELECT orden, 1 as tipo, paso_id AS fk, paso AS nombre, NULL::NUMERIC AS cantidad, NULL::medida_enum AS medida,NULL tipo_insumo, NULL::NUMERIC AS precio, NULL::numeric as costo, NULL::NUMERIC AS costo_12r
                FROM receta_x_paso rp
                JOIN paso p2 ON rp.paso_id = p2.id
                WHERE rp.receta_id = v_receta_id
                UNION
                SELECT orden, 2 as tipo, insumo_id AS fk, insumo AS nombre, cantidad, medida, i.tipo,i.precio_prom_kg_usd,
                  CASE 
                  when i.medida = 'g/L' then ((5*cantidad)/1000)*i.precio_prom_kg_usd
                  when i.medida = '%' then ((1*cantidad*10)/1000)*i.precio_prom_kg_usd
                  END,
                    CASE 
                        WHEN i.medida = 'g/L' THEN ((7 * cantidad)/1000) * i.precio_prom_kg_usd
                        WHEN i.medida = '%'   THEN ((1 * cantidad * 10)/1000) * i.precio_prom_kg_usd
                        ELSE NULL
                    END AS costo_12r
                FROM receta_x_insumo ri
                JOIN insumo i ON ri.insumo_id = i.id
                WHERE ri.receta_id = v_receta_id
            ) sub
        )
    ) INTO receta_json
    FROM partida p
    JOIN color_x_cliente cc ON cc.id = p.color_x_cliente_id
    JOIN color c ON cc.color_id = c.id
    JOIN cliente cl ON cc.cliente_id = cl.id
    JOIN articulo art ON p.articulo_id=art.id
    WHERE p.id = partida_id;

    RETURN receta_json;
END;$$;


ALTER FUNCTION public.get_receta_detalles_partida(partida_id integer, id_tipo_receta integer) OWNER TO postgres;

--
-- Name: get_receta_detalles_partida2(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_receta_detalles_partida2(partida_id integer, id_tipo_receta integer) RETURNS json
    LANGUAGE plpgsql
    AS $$DECLARE
    receta_json JSON;
    v_receta_id int;
BEGIN
    WITH paritda_tipo_articulo as (SELECT * FROM partida JOIN articulo ON articulo_id=id)
    SELECT id INTO v_receta_id
    FROM receta2 r JOIN paritda_tipo_articulo p ON p.color_x_cliente_id=r.color_x_cliente_id and p.tipo_articulo_id=r.tipo_articulo_id and p.fibra=r.fibra and p.tenido_id=r.tenido_id AND r.flg_antipilling=CASE WHEN p.adicional_id =1 and id_tipo_receta =7 THEN true else false end
    WHERE r.flg_activo=true AND r.flg_produccion=true and p.id=partida_id
    AND r.tipo_receta_id=id_tipo_receta;

    SELECT json_build_object(
        'receta_id',v_receta_id,
        'color_x_cliente_id', p.color_x_cliente_id,
        'color_tono', c.color || ' - ' || cl.cliente,
        'tipo_articulo_id', art.tipo_articulo_id,
        'tenido_id', p.tenido_id,
        'fibra', CAST(p.fibra AS SMALLINT),
        'pasos', (
            SELECT json_agg(sub ORDER BY orden)
            FROM (
                SELECT orden, 1 as tipo, paso_id AS fk, paso AS nombre, NULL::NUMERIC AS cantidad, NULL::medida_enum AS medida,NULL tipo_insumo, NULL::numeric as costo
                FROM receta_x_paso rp
                JOIN paso p2 ON rp.paso_id = p2.id
                WHERE rp.receta_id = v_receta_id
                UNION
                SELECT orden, 2 as tipo, insumo_id AS fk, insumo AS nombre, cantidad, medida, i.tipo,
                  CASE 
                  when i.medida = 'g/L' then ((5*cantidad)/1000)*i.precio_prom_kg_usd
                  when i.medida = '%' then ((1*cantidad*10)/1000)*i.precio_prom_kg_usd
                  END
                FROM receta_x_insumo ri
                JOIN insumo i ON ri.insumo_id = i.id
                WHERE ri.receta_id = v_receta_id
            ) sub
        )
    ) INTO receta_json
    FROM partida p
    JOIN color_x_cliente cc ON cc.id = p.color_x_cliente_id
    JOIN color c ON cc.color_id = c.id
    JOIN cliente cl ON cc.cliente_id = cl.id
    JOIN articulo art ON p.articulo_id=art.id
    WHERE p.id = partida_id;

    RETURN receta_json;
END;$$;


ALTER FUNCTION public.get_receta_detalles_partida2(partida_id integer, id_tipo_receta integer) OWNER TO postgres;

--
-- Name: get_receta_precio(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_receta_precio(p_receta_id integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    receta_json JSON;
BEGIN
    SELECT json_build_object(
        'receta_id',p_receta_id,
        'color_x_cliente_id', r.color_x_cliente_id,
        'color_tono', c.color || ' - ' || cl.cliente,
        'tipo_articulo_id', case
                                when (r.tipo_articulo_id in (4,8,9,10,11,12,14,15,17,18,20)) and cc.cliente_id in (1,11,22) then 20
                                when  r.tipo_articulo_id in (4,9,18)   then 18
                                when  r.tipo_articulo_id in (8,12)     then 12
                                when  r.tipo_articulo_id in (10,14,17) then 14
                                when  r.tipo_articulo_id in (16,22,23) then 16
                                else  r.tipo_articulo_id end ,
        'tenido_id', r.tenido_id,
        'fibra', CAST(r.fibra AS SMALLINT),
        'adicional_id',CASE WHEN ri.insumo_id IS NOT NULL THEN 1 ELSE NULL END
    ) INTO receta_json
    FROM receta2 r
    JOIN color_x_cliente cc ON cc.id = r.color_x_cliente_id
    JOIN color c ON cc.color_id = c.id
    JOIN cliente cl ON cc.cliente_id = cl.id
    LEFT JOIN receta_x_insumo ri ON ri.receta_id=r.id AND insumo_id=19
    WHERE r.id = p_receta_id and r.tipo_receta_id = 7;

    RETURN receta_json;
END;
$$;


ALTER FUNCTION public.get_receta_precio(p_receta_id integer) OWNER TO postgres;

--
-- Name: get_salida_inventario_detalles(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: get_semana_mes(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_semana_mes(fecha date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
    primer_dia date := date_trunc('month', fecha)::date;
    primer_viernes date;
    dia_sabado_inicio date;
    dias_despues_del_sabado int;
begin
    -- encontrar primer viernes del mes
    primer_viernes := (
        select d::date
        from generate_series(primer_dia, primer_dia + interval '6 days', interval '1 day') d
        where extract(dow from d) = 5 -- viernes
        limit 1
    );

    -- si está antes del primer sábado, está en semana 1
    if fecha <= primer_viernes then
        return 1;
    end if;

    -- calcular primer sábado luego del primer viernes
    dia_sabado_inicio := primer_viernes + 1;

    dias_despues_del_sabado := fecha - dia_sabado_inicio;

    return floor(dias_despues_del_sabado / 7) + 2; -- +2 por la semana 1 que ya pasó
end;
$$;


ALTER FUNCTION public.get_semana_mes(fecha date) OWNER TO postgres;

--
-- Name: get_user_by_id(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_user_by_id(user_id integer) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  SELECT first_name || ' ' || last_name
  FROM profiles
  WHERE id_usuario = user_id;
$$;


ALTER FUNCTION public.get_user_by_id(user_id integer) OWNER TO postgres;

--
-- Name: get_user_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_user_id() RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
declare
  user_uuid uuid;
  int_id integer;
begin
  user_uuid := auth.uid();

  select u.id_usuario into int_id
  from profiles u
  where u.id = user_uuid;

  -- if int_id is null then
  --   raise exception 'No matching int ID for UUID %', user_uuid;
  -- end if;

  return int_id;
end;
$$;


ALTER FUNCTION public.get_user_id() OWNER TO postgres;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: homologar_insumos(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insert_compra(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insert_lavado_maquina(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_lavado_maquina(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_receta_id INT;
BEGIN
    -- Insertamos en la tabla principal, guardando el ID generado
    INSERT INTO receta_lavado_maquina AS p (
        tipo_lavado_mq_id,
        valor_origen_id,
        valor_destino_id
    )
    VALUES (
        (json_data->>'tipo_lavado_mq_id')::SMALLINT,
        (json_data->>'valor_origen_id')::SMALLINT,
        (json_data->>'valor_destino_id')::SMALLINT
    )
    RETURNING p.id INTO new_receta_id;

    -- Desactivamos registros previos con los mismos valores, excepto el recién insertado
    UPDATE receta_lavado_maquina 
    SET flg_activo = false
    WHERE tipo_lavado_mq_id = (json_data->>'tipo_lavado_mq_id')::SMALLINT
      AND valor_origen_id = (json_data->>'valor_origen_id')::SMALLINT
      AND valor_destino_id = (json_data->>'valor_destino_id')::SMALLINT
      AND id <> new_receta_id;

    -- Inserción masiva en receta_lavado_maquina_x_insumo
    INSERT INTO receta_lavado_maquina_x_insumo (receta_lavado_mq_id, insumo_id, cantidad, orden)
    SELECT 
        new_receta_id,
        (item->>'insumo_id')::SMALLINT,
        REPLACE(item->>'cantidad', ',', '.')::NUMERIC(8,4),
        (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'insumos') AS item;

    -- Inserción masiva en receta_lavado_maquina_x_paso
    INSERT INTO receta_lavado_maquina_x_paso (receta_lavado_mq_id, paso_id, orden)
    SELECT 
        new_receta_id,
        (item->>'paso_id')::SMALLINT,
        (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'pasos') AS item;

    -- Devolvemos un mensaje de éxito uniendo valores de la tabla 'valor'
    RETURN QUERY 
    SELECT 
        'Receta creada de ' || vo.valor || ' a ' || vd.valor || ' con codigo: ' || new_receta_id AS msj
    FROM valor vo, valor vd
    WHERE vo.id = (json_data->>'valor_origen_id')::SMALLINT
      AND vd.id = (json_data->>'valor_destino_id')::SMALLINT;
END;
$$;


ALTER FUNCTION public.insert_lavado_maquina(json_data jsonb) OWNER TO postgres;

--
-- Name: insert_partida(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insert_receta(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_receta(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_receta_id INT;
BEGIN
    -- Insert the main 'receta' record using an alias for clarity
    INSERT INTO receta2 AS p (
        color_x_cliente_id,
        tipo_articulo_id,
        tenido_id,
        fibra,
        tipo_receta_id
    )
    VALUES (
        (json_data->>'color_x_cliente_id')::SMALLINT,
        (json_data->>'tipo_articulo_id')::SMALLINT,
        (json_data->>'tenido_id')::SMALLINT,
        (json_data->>'fibra')::SMALLINT,
        (json_data->>'tipo_receta_id')::SMALLINT

    )
    RETURNING p.id AS result_pk INTO new_receta_id;

    IF EXISTS (
    SELECT 1 
    FROM jsonb_array_elements(json_data->'insumos') AS item
    WHERE (item->>'insumo_id')::SMALLINT = 19
) THEN
    -- Perform your extra update
    UPDATE receta2
    SET flg_antipilling = true
    WHERE id=new_receta_id;
END IF;

    UPDATE receta2 
    SET flg_activo=false
    WHERE color_x_cliente_id=(json_data->>'color_x_cliente_id')::SMALLINT
    AND tipo_articulo_id=(json_data->>'tipo_articulo_id')::SMALLINT
    AND tenido_id=(json_data->>'tenido_id')::SMALLINT
    AND fibra=(json_data->>'fibra')::SMALLINT
    AND flg_antipilling= (
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM jsonb_array_elements(json_data->'insumos') AS item
            WHERE (item->>'insumo_id')::SMALLINT = 19
        )
        THEN true  -- If insumo_id = 19 exists, update where flg_antipilling is true
        ELSE false  -- If insumo_id = 19 does not exist, update where flg_antipilling is false
    END
    )
    AND tipo_receta_id = (json_data->>'tipo_receta_id')::SMALLINT
    AND id!=new_receta_id;
    -- Bulk insert extras into receta_x_extra
    INSERT INTO receta_x_insumo (receta_id, insumo_id, cantidad,orden)
    SELECT 
        new_receta_id,
        (item->>'insumo_id')::SMALLINT,
        REPLACE((item->>'cantidad'),',','.')::NUMERIC(8,4),
        (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'insumos') AS item;

    INSERT INTO receta_x_paso (receta_id, paso_id,orden)
    SELECT 
        new_receta_id,
        (item->>'paso_id')::SMALLINT,
        (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'pasos') AS item;

    RETURN QUERY SELECT 'Receta creada para '|| c.color ||' - '|| cl.cliente || ' con codigo: '|| new_receta_id  FROM color_x_cliente cc JOIN color c ON c.id=cc.color_id JOIN cliente cl ON cc.cliente_id=cl.id WHERE id=(json_data->>'color_x_cliente_id')::SMALLINT;
END;
$$;


ALTER FUNCTION public.insert_receta(json_data jsonb) OWNER TO postgres;

--
-- Name: insert_receta_v2(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_receta_v2(json_data jsonb) RETURNS TABLE(msj text)
    LANGUAGE plpgsql
    AS $$DECLARE
    new_receta_id INT;
BEGIN
    -- Insert the main 'receta' record using an alias for clarity
    INSERT into logs_api(function_name,user_id,params)
    SELECT 'insert_receta_v2', get_user_id(),json_data;
    INSERT INTO receta2 AS p (
        color_x_cliente_id,
        tipo_articulo_id,
        tenido_id,
        fibra,
        tipo_receta_id
    )
    VALUES (
        (json_data->>'color_x_cliente_id')::SMALLINT,
        (json_data->>'tipo_articulo_id')::SMALLINT,
        (json_data->>'tenido_id')::SMALLINT,
        (json_data->>'fibra')::SMALLINT,
        (json_data->>'tipo_receta_id')::SMALLINT

    )
    RETURNING p.id AS result_pk INTO new_receta_id;

    IF EXISTS (
    SELECT 1 
    FROM jsonb_array_elements(json_data->'insumos') AS item
    WHERE (item->>'insumo_id')::SMALLINT = 19
) THEN
    -- Perform your extra update
    UPDATE receta2
    SET flg_antipilling = true
    WHERE id=new_receta_id;
END IF;
 IF EXISTS (
    SELECT 1 
    FROM jsonb_array_elements(json_data->'pasos') AS item
    WHERE (item->>'fk')::SMALLINT = 19 AND (item->>'tipo')::SMALLINT = 2 
) THEN
    -- Perform your extra update
    UPDATE receta2
    SET flg_antipilling = true
    WHERE id=new_receta_id;
END IF;
    UPDATE receta2 
    SET flg_activo=false
    WHERE color_x_cliente_id=(json_data->>'color_x_cliente_id')::SMALLINT
    AND tipo_articulo_id=(json_data->>'tipo_articulo_id')::SMALLINT
    AND tenido_id=(json_data->>'tenido_id')::SMALLINT
    AND fibra=(json_data->>'fibra')::SMALLINT
    AND flg_antipilling= (
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM jsonb_array_elements(json_data->'insumos') AS item
            WHERE (item->>'insumo_id')::SMALLINT = 19
            UNION ALL
            SELECT 1 
            FROM jsonb_array_elements(json_data->'pasos') AS item
            WHERE (item->>'fk')::SMALLINT = 19  AND (item->>'tipo')::SMALLINT = 2 
        )
        THEN true  -- If insumo_id = 19 exists, update where flg_antipilling is true
        ELSE false  -- If insumo_id = 19 does not exist, update where flg_antipilling is false
    END
    )
    AND tipo_receta_id = (json_data->>'tipo_receta_id')::SMALLINT
    AND id!=new_receta_id;
    -- Bulk insert extras into receta_x_extra
    INSERT INTO receta_x_insumo (receta_id, insumo_id, cantidad,orden)
    SELECT 
        new_receta_id,
        (item->>'fk')::SMALLINT,
        REPLACE((item->>'cantidad'),',','.')::NUMERIC(8,4),
        (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'pasos') AS item WHERE (item->>'tipo')::SMALLINT=2;

    INSERT INTO receta_x_paso (receta_id, paso_id,orden)
    SELECT 
        new_receta_id,
        (item->>'fk')::SMALLINT,
        (item->>'orden')::SMALLINT
    FROM jsonb_array_elements(json_data->'pasos') AS item WHERE (item->>'tipo')::SMALLINT=1;

    RETURN QUERY SELECT 'Receta creada para '|| c.color ||' - '|| cl.cliente || ' con codigo: '|| new_receta_id  FROM color_x_cliente cc JOIN color c ON c.id=cc.color_id JOIN cliente cl ON cc.cliente_id=cl.id WHERE cc.id=(json_data->>'color_x_cliente_id')::SMALLINT;
END;$$;


ALTER FUNCTION public.insert_receta_v2(json_data jsonb) OWNER TO postgres;

--
-- Name: insert_solicitud_ingreso_compra_parcial(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insert_solicitud_ingreso_compra_total(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_solicitud_ingreso_compra_total(id_compra integer) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'iam', 'notification', 'public'
    AS $$
DECLARE
    new_entrada_id INTEGER;
BEGIN

    IF EXISTS (
    SELECT 1 
    FROM entrada_inventario ei
    JOIN entrada_inventario_detalle eid ON ei.id = eid.entrada_inventario_id
    JOIN compra_x_insumo cxi ON eid.compra_x_insumo_id = cxi.id
    WHERE cxi.compra_id = id_compra
    AND ei.estado = 'pendiente'::estado_entrada_inventario_enum
) THEN
    RAISE EXCEPTION USING
    MESSAGE = 'Ya existe una solicitud pendiente para esta compra',
    -- DETAIL  = faltantes::text,
    HINT    = 'Actualizar la pagina y revisar el historial de solicitudes de ingreso';
END IF;
    -- Insert main record
    INSERT INTO entrada_inventario (
        motivo
    )
    VALUES (
        'compra'::motivo_entrada_inventario_enum
    )
    RETURNING id INTO new_entrada_id;

    -- Insert detail records using new_entrada_id
    INSERT INTO entrada_inventario_detalle (
        entrada_inventario_id,
        insumo_x_proveedor_id,
        cantidad_solicitada,
        compra_x_insumo_id
    )
    SELECT 
        new_entrada_id,
        insumo_x_proveedor_id,
        cantidad,
        id
    FROM compra_x_insumo
    WHERE compra_id=id_compra;

 INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Solicitud de Ingreso', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=get_user_id()),'sistema') || ' ha registrado una solicitud de ingreso con N°' || new_entrada_id, CASE WHEN r.code='inventario' THEN 'task' ELSE  'info' END,jsonb_build_object('objeto_tipo','entrada','objeto_id',new_entrada_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','inventario');

    RETURN 'Solicitud de ingreso registrada correctamente. N° Solicitud: ' || new_entrada_id;
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('Error: %s', SQLERRM);
END;
$$;


ALTER FUNCTION public.insert_solicitud_ingreso_compra_total(id_compra integer) OWNER TO postgres;

--
-- Name: insert_solicitud_ingreso_compra_total(integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_solicitud_ingreso_compra_total(id_compra integer, p_fyh_real timestamp with time zone) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'iam', 'notification', 'public'
    AS $$
DECLARE
    new_entrada_id INTEGER;
BEGIN

    IF EXISTS (
    SELECT 1 
    FROM entrada_inventario ei
    JOIN entrada_inventario_detalle eid ON ei.id = eid.entrada_inventario_id
    JOIN compra_x_insumo cxi ON eid.compra_x_insumo_id = cxi.id
    WHERE cxi.compra_id = id_compra
    AND ei.estado = 'pendiente'::estado_entrada_inventario_enum
) THEN
    RAISE EXCEPTION USING
    MESSAGE = 'Ya existe una solicitud pendiente para esta compra',
    -- DETAIL  = faltantes::text,
    HINT    = 'Actualizar la pagina y revisar el historial de solicitudes de ingreso';
END IF;
    -- Insert main record
    INSERT INTO entrada_inventario (
        motivo,
        fyh_entrada_real
    )
    VALUES (
        'compra'::motivo_entrada_inventario_enum,
        p_fyh_real
    )
    RETURNING id INTO new_entrada_id;

    -- Insert detail records using new_entrada_id
    INSERT INTO entrada_inventario_detalle (
        entrada_inventario_id,
        insumo_x_proveedor_id,
        cantidad_solicitada,
        compra_x_insumo_id
    )
    SELECT 
        new_entrada_id,
        insumo_x_proveedor_id,
        cantidad,
        id
    FROM compra_x_insumo
    WHERE compra_id=id_compra;


    INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Solicitud de Ingreso', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=get_user_id()),'sistema') || ' ha registrado una solicitud de ingreso con N°' || new_entrada_id, CASE WHEN r.code='inventario' THEN 'task' ELSE  'info' END,jsonb_build_object('objeto_tipo','entrada','objeto_id',new_entrada_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','inventario');
    RETURN 'Solicitud de ingreso registrada correctamente. N° Solicitud: ' || new_entrada_id;
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('Error: %s', SQLERRM);
END;
$$;


ALTER FUNCTION public.insert_solicitud_ingreso_compra_total(id_compra integer, p_fyh_real timestamp with time zone) OWNER TO postgres;

--
-- Name: insert_solicitud_ingreso_inventario(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_solicitud_ingreso_inventario(json_data jsonb) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'iam', 'notification', 'public'
    AS $$DECLARE
    new_entrada_id INTEGER;
BEGIN
    -- Insert main record
    INSERT INTO entrada_inventario (
        motivo,
        fyh_entrada_real,
        observacion
    )
    VALUES (
        (json_data->>'motivo')::motivo_entrada_inventario_enum,
        (json_data->>'fyh_entrada_real')::timestamptz,
        json_data->>'observacion'
    )
    RETURNING id INTO new_entrada_id;

    -- Insert detail records using new_entrada_id
    INSERT INTO entrada_inventario_detalle (
        entrada_inventario_id,
        cantidad_solicitada,
        compra_x_insumo_id,
        insumo_x_proveedor_id,
        observacion
    )
    SELECT 
        new_entrada_id,
        (item->>'cantidad_solicitada')::NUMERIC(8,4),
        NULLIF(item->>'compra_x_insumo_id', '')::INTEGER,
        (item->>'insumo_x_proveedor_id')::SMALLINT,
        NULLIF(item->>'observacion', '')
    FROM jsonb_array_elements(json_data->'detalles') AS item;

 INSERT INTO notification.notifications(user_id,title,body,tipo,payload)
SELECT ur.user_id,'Nueva Solicitud de Ingreso', COALESCE((SELECT COALESCE(first_name,'Usuario desconocido') || ' ' || last_name FROM profiles WHERE id_usuario=get_user_id()),'sistema') ||  ' ha registrado una solicitud de ingreso con N°' || new_entrada_id, CASE WHEN r.code='inventario' THEN 'task' ELSE  'info' END,jsonb_build_object('objeto_tipo','entrada','objeto_id',new_entrada_id)
FROM iam.user_rol ur LEFT JOIN profiles p ON p.id_usuario=ur.user_id
LEFT JOIN iam.rol r ON ur.rol_id=r.id
WHERE r.code IN ('jefe_planta','inventario');


    RETURN 'Solicitud de ingreso registrada correctamente. N° Solicitud: ' || new_entrada_id;
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('Error: %s', SQLERRM);
END;$$;


ALTER FUNCTION public.insert_solicitud_ingreso_inventario(json_data jsonb) OWNER TO postgres;

--
-- Name: insertar_catalogo_precio_v2(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_catalogo_precio_v2(integer, integer, integer, integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_catalogo_precio_v2(integer, integer, integer, integer, integer, integer, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_catalogo_precio_v2(integer, integer, integer, integer, integer, integer, numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_compactado(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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
    v_tipo       := (json_data->>'tipo_partida')::text;
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
          and tipo_partida = 'Produccion'
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
        tipo_partida,
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

--
-- Name: insertar_despacho(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_devolucion(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_estado_observado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_historial_al_crear(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_historial_estado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_observado(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_parada_tintoreria(integer, integer, integer, timestamp without time zone, timestamp without time zone, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_perchado(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_produccion_tenido(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertar_produccion_tenido_avanzado(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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
    estado_final := case when (item->>'hora_fin') is null then 'En partida Teñido' else 'Teñido' end;

    duracion_real :=
      case
        when estado_final = 'En partida Teñido' then
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
        and a.estado = 'En partida Teñido';

      if rollos_previos > 0 then
        es_complemento := true;
      end if;
    end if;

    rollos_final := (item->>'rollos')::numeric;
    kilos_final  := (item->>'kilos')::numeric;

    if estado_final = 'En partida Teñido' then
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

--
-- Name: insertar_termofijado(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertarpartidahc(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: insertarreceta(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: inventario_movimientos_diario(integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: observado_ai_to_estados(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: procesar_ingreso_inventario(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: prorratear_kilos_turno(time without time zone, interval, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prorratear_kilos_turno(hora_inicio time without time zone, duracion interval, kilos numeric) RETURNS TABLE(kilos_dia numeric, kilos_noche numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
  ts_inicio TIMESTAMP := '2000-01-01'::timestamp + hora_inicio;
  ts_fin TIMESTAMP := ts_inicio + duracion;
  ts_aux TIMESTAMP;

  dia_duracion INTERVAL := interval '0';
  noche_duracion INTERVAL := interval '0';

  turno_dia_ini TIME := '07:00:00';
  turno_dia_fin TIME := '19:00:00';

  bloque_ini TIMESTAMP;
  bloque_fin TIMESTAMP;
BEGIN
  WHILE ts_inicio < ts_fin LOOP
    ts_aux := LEAST(ts_fin, date_trunc('day', ts_inicio) + interval '1 day');

    -- Rango día (07:00–19:00)
    bloque_ini := date_trunc('day', ts_inicio) + turno_dia_ini;
    bloque_fin := date_trunc('day', ts_inicio) + turno_dia_fin;

    dia_duracion := dia_duracion + GREATEST(
      LEAST(ts_aux, bloque_fin) - GREATEST(ts_inicio, bloque_ini),
      interval '0'
    );

    -- Resto es noche
    noche_duracion := noche_duracion + GREATEST(
      ts_aux - ts_inicio - GREATEST(
        LEAST(ts_aux, bloque_fin) - GREATEST(ts_inicio, bloque_ini),
        interval '0'
      ),
      interval '0'
    );

    ts_inicio := ts_aux;
  END LOOP;

  IF (EXTRACT(EPOCH FROM dia_duracion) + EXTRACT(EPOCH FROM noche_duracion)) = 0 THEN
    RETURN QUERY SELECT 0::numeric, 0::numeric;
  END IF;

  RETURN QUERY SELECT
    ROUND(kilos * EXTRACT(EPOCH FROM dia_duracion) / EXTRACT(EPOCH FROM duracion), 4),
    ROUND(kilos * EXTRACT(EPOCH FROM noche_duracion) / EXTRACT(EPOCH FROM duracion), 4);
END;
$$;


ALTER FUNCTION public.prorratear_kilos_turno(hora_inicio time without time zone, duracion interval, kilos numeric) OWNER TO postgres;

--
-- Name: rechazar_salida_inventario(integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: reject_full_entrada_inventario(integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: reordenar_orden_receta(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, timestamp with time zone, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_2(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_3(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_l(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_l(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, date, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_lavado_maquina(integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_lavado_maquina(integer, integer, date, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_matizado(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_matizado(public.motivo_salida_inventario_enum, integer, jsonb, integer, integer, integer, integer, date, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_receta(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_receta(integer, integer, integer, timestamp with time zone, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_receta2(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: solicitar_salida_inventario_receta3(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_estado_observado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_estado_tenido_inteligente(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_estado_tenido_inteligente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    id_en_partida_tenido int;
    id_tenido int;
    id_reprocesado int;
    id_en_partida_repartida int;
    v_fecha date;
begin
    select id into id_en_partida_tenido
    from estado where estado = 'En partida Teñido';

    select id into id_tenido
    from estado where estado = 'Teñido';

    select id into id_reprocesado
    from estado where estado = 'Reprocesado';

    select id into id_en_partida_repartida
    from estado where estado = 'En partida Repartida';

    if NEW.partida_id is null then
        return NEW;
    end if;

    v_fecha := NEW.fecha;

    if NEW.tipo = 'Teñido' then
        if NEW.hora_fin is null then
            insert into partida_estado_historial
            (partida_id, estado_id, rollos_afectados, rib_afectados, fecha_ejecucion)
            values
            (NEW.partida_id, id_en_partida_tenido, NEW.rollos, 0, v_fecha);
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
            (NEW.partida_id, id_en_partida_repartida, NEW.rollos, 0, v_fecha);
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

--
-- Name: trg_insertar_estado_despachado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_insertar_estado_devolucion(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_insertar_estado_para_despachar(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_insertar_estado_perchado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_insertar_estado_planchado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

    -- determinar estado según tipo_partida
    if NEW.tipo_partida = 'Produccion' then

        v_estado_id := id_planchado;

    elsif NEW.tipo_partida in ('Repartida', 'Replanchado') then

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

--
-- Name: trg_insertar_estado_termofijado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_insertar_programado(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_set_costo_bruto_kg(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: trg_update_insumo_prices(); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: upd_compra(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_cuadre_inventario_detalles(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_observado(integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_observado(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_observado(integer[], integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_observado(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_partida(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_peso(double precision, double precision, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_peso(double precision, double precision, double precision, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_precio_x_partida(integer, double precision, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_receta(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: update_receta_x_partida(double precision, integer, double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

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

--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
-- Regclass of the table e.g. public.notes
entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

-- I, U, D, T: insert, update ...
action realtime.action = (
    case wal ->> 'action'
        when 'I' then 'INSERT'
        when 'U' then 'UPDATE'
        when 'D' then 'DELETE'
        else 'ERROR'
    end
);

-- Is row level security enabled for the table
is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

subscriptions realtime.subscription[] = array_agg(subs)
    from
        realtime.subscription subs
    where
        subs.entity = entity_
        -- Filter by action early - only get subscriptions interested in this action
        -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
        and (subs.action_filter = '*' or subs.action_filter = action::text);

-- Subscription vars
roles regrole[] = array_agg(distinct us.claims_role::text)
    from
        unnest(subscriptions) us;

working_role regrole;
claimed_role regrole;
claims jsonb;

subscription_id uuid;
subscription_has_access bool;
visible_to_subscription_ids uuid[] = '{}';

-- structured info for wal's columns
columns realtime.wal_column[];
-- previous identity values for update/delete
old_columns realtime.wal_column[];

error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

-- Primary jsonb output for record
output jsonb;

begin
perform set_config('role', null, true);

columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'columns') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

old_columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'identity') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

for working_role in select * from unnest(roles) loop

    -- Update `is_selectable` for columns and old_columns
    columns =
        array_agg(
            (
                c.name,
                c.type_name,
                c.type_oid,
                c.value,
                c.is_pkey,
                pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
            )::realtime.wal_column
        )
        from
            unnest(columns) c;

    old_columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(old_columns) c;

    if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            -- subscriptions is already filtered by entity
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 400: Bad Request, no primary key']
        )::realtime.wal_rls;

    -- The claims role does not have SELECT permission to the primary key of entity
    elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 401: Unauthorized']
        )::realtime.wal_rls;

    else
        output = jsonb_build_object(
            'schema', wal ->> 'schema',
            'table', wal ->> 'table',
            'type', action,
            'commit_timestamp', to_char(
                ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            ),
            'columns', (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'name', pa.attname,
                            'type', pt.typname
                        )
                        order by pa.attnum asc
                    )
                from
                    pg_attribute pa
                    join pg_type pt
                        on pa.atttypid = pt.oid
                where
                    attrelid = entity_
                    and attnum > 0
                    and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
            )
        )
        -- Add "record" key for insert and update
        || case
            when action in ('INSERT', 'UPDATE') then
                jsonb_build_object(
                    'record',
                    (
                        select
                            jsonb_object_agg(
                                -- if unchanged toast, get column name and value from old record
                                coalesce((c).name, (oc).name),
                                case
                                    when (c).name is null then (oc).value
                                    else (c).value
                                end
                            )
                        from
                            unnest(columns) c
                            full outer join unnest(old_columns) oc
                                on (c).name = (oc).name
                        where
                            coalesce((c).is_selectable, (oc).is_selectable)
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                    )
                )
            else '{}'::jsonb
        end
        -- Add "old_record" key for update and delete
        || case
            when action = 'UPDATE' then
                jsonb_build_object(
                        'old_record',
                        (
                            select jsonb_object_agg((c).name, (c).value)
                            from unnest(old_columns) c
                            where
                                (c).is_selectable
                                and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                        )
                    )
            when action = 'DELETE' then
                jsonb_build_object(
                    'old_record',
                    (
                        select jsonb_object_agg((c).name, (c).value)
                        from unnest(old_columns) c
                        where
                            (c).is_selectable
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                    )
                )
            else '{}'::jsonb
        end;

        -- Create the prepared statement
        if is_rls_enabled and action <> 'DELETE' then
            if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                deallocate walrus_rls_stmt;
            end if;
            execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
        end if;

        visible_to_subscription_ids = '{}';

        for subscription_id, claims in (
                select
                    subs.subscription_id,
                    subs.claims
                from
                    unnest(subscriptions) subs
                where
                    subs.entity = entity_
                    and subs.claims_role = working_role
                    and (
                        realtime.is_visible_through_filters(columns, subs.filters)
                        or (
                          action = 'DELETE'
                          and realtime.is_visible_through_filters(old_columns, subs.filters)
                        )
                    )
        ) loop

            if not is_rls_enabled or action = 'DELETE' then
                visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
            else
                -- Check if RLS allows the role to see the record
                perform
                    -- Trim leading and trailing quotes from working_role because set_config
                    -- doesn't recognize the role as valid if they are included
                    set_config('role', trim(both '"' from working_role::text), true),
                    set_config('request.jwt.claims', claims::text, true);

                execute 'execute walrus_rls_stmt' into subscription_has_access;

                if subscription_has_access then
                    visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
                end if;
            end if;
        end loop;

        perform set_config('role', null, true);

        return next (
            output,
            is_rls_enabled,
            visible_to_subscription_ids,
            case
                when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                else '{}'
            end
        )::realtime.wal_rls;

    end if;
end loop;

perform set_config('role', null, true);
end;
$$;


ALTER FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) OWNER TO supabase_admin;

--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


ALTER FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) OWNER TO supabase_admin;

--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


ALTER FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) OWNER TO supabase_admin;

--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  res jsonb;
begin
  if type_::text = 'bytea' then
    return to_jsonb(val);
  end if;
  execute format('select to_jsonb(%L::'|| type_::text || ')', val) into res;
  return res;
end
$$;


ALTER FUNCTION realtime."cast"(val text, type_ regtype) OWNER TO supabase_admin;

--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
      /*
      Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
      */
      declare
          op_symbol text = (
              case
                  when op = 'eq' then '='
                  when op = 'neq' then '!='
                  when op = 'lt' then '<'
                  when op = 'lte' then '<='
                  when op = 'gt' then '>'
                  when op = 'gte' then '>='
                  when op = 'in' then '= any'
                  else 'UNKNOWN OP'
              end
          );
          res boolean;
      begin
          execute format(
              'select %L::'|| type_::text || ' ' || op_symbol
              || ' ( %L::'
              || (
                  case
                      when op = 'in' then type_::text || '[]'
                      else type_::text end
              )
              || ')', val_1, val_2) into res;
          return res;
      end;
      $$;


ALTER FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) OWNER TO supabase_admin;

--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
    /*
    Should the record be visible (true) or filtered out (false) after *filters* are applied
    */
        select
            -- Default to allowed when no filters present
            $2 is null -- no filters. this should not happen because subscriptions has a default
            or array_length($2, 1) is null -- array length of an empty array is null
            or bool_and(
                coalesce(
                    realtime.check_equality_op(
                        op:=f.op,
                        type_:=coalesce(
                            col.type_oid::regtype, -- null when wal2json version <= 2.4
                            col.type_name::regtype
                        ),
                        -- cast jsonb to text
                        val_1:=col.value #>> '{}',
                        val_2:=f.value
                    ),
                    false -- if null, filter does not match
                )
            )
        from
            unnest(filters) f
            join unnest(columns) col
                on f.column_name = col.name;
    $_$;


ALTER FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) OWNER TO supabase_admin;

--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS TABLE(wal jsonb, is_rls_enabled boolean, subscription_ids uuid[], errors text[], slot_changes_count bigint)
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
  WITH pub AS (
    SELECT
      concat_ws(
        ',',
        CASE WHEN bool_or(pubinsert) THEN 'insert' ELSE NULL END,
        CASE WHEN bool_or(pubupdate) THEN 'update' ELSE NULL END,
        CASE WHEN bool_or(pubdelete) THEN 'delete' ELSE NULL END
      ) AS w2j_actions,
      coalesce(
        string_agg(
          realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
          ','
        ) filter (WHERE ppt.tablename IS NOT NULL AND ppt.tablename NOT LIKE '% %'),
        ''
      ) AS w2j_add_tables
    FROM pg_publication pp
    LEFT JOIN pg_publication_tables ppt ON pp.pubname = ppt.pubname
    WHERE pp.pubname = publication
    GROUP BY pp.pubname
    LIMIT 1
  ),
  -- MATERIALIZED ensures pg_logical_slot_get_changes is called exactly once
  w2j AS MATERIALIZED (
    SELECT x.*, pub.w2j_add_tables
    FROM pub,
         pg_logical_slot_get_changes(
           slot_name, null, max_changes,
           'include-pk', 'true',
           'include-transaction', 'false',
           'include-timestamp', 'true',
           'include-type-oids', 'true',
           'format-version', '2',
           'actions', pub.w2j_actions,
           'add-tables', pub.w2j_add_tables
         ) x
  ),
  -- Count raw slot entries before apply_rls/subscription filter
  slot_count AS (
    SELECT count(*)::bigint AS cnt
    FROM w2j
    WHERE w2j.w2j_add_tables <> ''
  ),
  -- Apply RLS and filter as before
  rls_filtered AS (
    SELECT xyz.wal, xyz.is_rls_enabled, xyz.subscription_ids, xyz.errors
    FROM w2j,
         realtime.apply_rls(
           wal := w2j.data::jsonb,
           max_record_bytes := max_record_bytes
         ) xyz(wal, is_rls_enabled, subscription_ids, errors)
    WHERE w2j.w2j_add_tables <> ''
      AND xyz.subscription_ids[1] IS NOT NULL
  )
  -- Real rows with slot count attached
  SELECT rf.wal, rf.is_rls_enabled, rf.subscription_ids, rf.errors, sc.cnt
  FROM rls_filtered rf, slot_count sc

  UNION ALL

  -- Sentinel row: always returned when no real rows exist so Elixir can
  -- always read slot_changes_count. Identified by wal IS NULL.
  SELECT null, null, null, null, sc.cnt
  FROM slot_count sc
  WHERE NOT EXISTS (SELECT 1 FROM rls_filtered)
$$;


ALTER FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) OWNER TO supabase_admin;

--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
      select
        (
          select string_agg('' || ch,'')
          from unnest(string_to_array(nsp.nspname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
        )
        || '.'
        || (
          select string_agg('' || ch,'')
          from unnest(string_to_array(pc.relname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
          )
      from
        pg_class pc
        join pg_namespace nsp
          on pc.relnamespace = nsp.oid
      where
        pc.oid = entity
    $$;


ALTER FUNCTION realtime.quote_wal2json(entity regclass) OWNER TO supabase_admin;

--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    -- Generate a new UUID for the id
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    -- Attempt to insert the message
    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      -- Capture and notify the error
      RAISE WARNING 'ErrorSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


ALTER FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) OWNER TO supabase_admin;

--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    /*
    Validates that the user defined filters for a subscription:
    - refer to valid columns that the claimed role may access
    - values are coercable to the correct column type
    */
    declare
        col_names text[] = coalesce(
                array_agg(c.column_name order by c.ordinal_position),
                '{}'::text[]
            )
            from
                information_schema.columns c
            where
                format('%I.%I', c.table_schema, c.table_name)::regclass = new.entity
                and pg_catalog.has_column_privilege(
                    (new.claims ->> 'role'),
                    format('%I.%I', c.table_schema, c.table_name)::regclass,
                    c.column_name,
                    'SELECT'
                );
        filter realtime.user_defined_filter;
        col_type regtype;

        in_val jsonb;
    begin
        for filter in select * from unnest(new.filters) loop
            -- Filtered column is valid
            if not filter.column_name = any(col_names) then
                raise exception 'invalid column for filter %', filter.column_name;
            end if;

            -- Type is sanitized and safe for string interpolation
            col_type = (
                select atttypid::regtype
                from pg_catalog.pg_attribute
                where attrelid = new.entity
                      and attname = filter.column_name
            );
            if col_type is null then
                raise exception 'failed to lookup type for column %', filter.column_name;
            end if;

            -- Set maximum number of entries for in filter
            if filter.op = 'in'::realtime.equality_op then
                in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
                if coalesce(jsonb_array_length(in_val), 0) > 100 then
                    raise exception 'too many values for `in` filter. Maximum 100';
                end if;
            else
                -- raises an exception if value is not coercable to type
                perform realtime.cast(filter.value, col_type);
            end if;

        end loop;

        -- Apply consistent order to filters so the unique constraint on
        -- (subscription_id, entity, filters) can't be tricked by a different filter order
        new.filters = coalesce(
            array_agg(f order by f.column_name, f.op, f.value),
            '{}'
        ) from unnest(new.filters) f;

        return new;
    end;
    $$;


ALTER FUNCTION realtime.subscription_check_filters() OWNER TO supabase_admin;

--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


ALTER FUNCTION realtime.to_regrole(role_name text) OWNER TO supabase_admin;

--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


ALTER FUNCTION realtime.topic() OWNER TO supabase_realtime_admin;

--
-- Name: allow_any_operation(text[]); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.allow_any_operation(expected_operations text[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION storage.allow_any_operation(expected_operations text[]) OWNER TO supabase_storage_admin;

--
-- Name: allow_only_operation(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.allow_only_operation(expected_operation text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION storage.allow_only_operation(expected_operation text) OWNER TO supabase_storage_admin;

--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) OWNER TO supabase_storage_admin;

--
-- Name: delete_leaf_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


ALTER FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) OWNER TO supabase_storage_admin;

--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION storage.enforce_bucket_name_length() OWNER TO supabase_storage_admin;

--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION storage.extension(name text) OWNER TO supabase_storage_admin;

--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION storage.filename(name text) OWNER TO supabase_storage_admin;

--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION storage.foldername(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) OWNER TO supabase_storage_admin;

--
-- Name: get_level(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_level(name text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


ALTER FUNCTION storage.get_level(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_prefix(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_prefix(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


ALTER FUNCTION storage.get_prefix(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_prefixes(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_prefixes(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


ALTER FUNCTION storage.get_prefixes(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION storage.get_size_by_bucket() OWNER TO supabase_storage_admin;

--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text) OWNER TO supabase_storage_admin;

--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text, sort_order text) OWNER TO supabase_storage_admin;

--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION storage.operation() OWNER TO supabase_storage_admin;

--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION storage.protect_delete() OWNER TO supabase_storage_admin;

--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: search_legacy_v1(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION storage.update_updated_at_column() OWNER TO supabase_storage_admin;

--
-- Name: secrets_encrypt_secret_secret(); Type: FUNCTION; Schema: vault; Owner: supabase_admin
--

CREATE FUNCTION vault.secrets_encrypt_secret_secret() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
		BEGIN
		        new.secret = CASE WHEN new.secret IS NULL THEN NULL ELSE
			CASE WHEN new.key_id IS NULL THEN NULL ELSE pg_catalog.encode(
			  pgsodium.crypto_aead_det_encrypt(
				pg_catalog.convert_to(new.secret, 'utf8'),
				pg_catalog.convert_to((new.id::text || new.description::text || new.created_at::text || new.updated_at::text)::text, 'utf8'),
				new.key_id::uuid,
				new.nonce
			  ),
				'base64') END END;
		RETURN new;
		END;
		$$;


ALTER FUNCTION vault.secrets_encrypt_secret_secret() OWNER TO supabase_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE auth.audit_log_entries OWNER TO supabase_auth_admin;

--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: custom_oauth_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.custom_oauth_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_type text NOT NULL,
    identifier text NOT NULL,
    name text NOT NULL,
    client_id text NOT NULL,
    client_secret text NOT NULL,
    acceptable_client_ids text[] DEFAULT '{}'::text[] NOT NULL,
    scopes text[] DEFAULT '{}'::text[] NOT NULL,
    pkce_enabled boolean DEFAULT true NOT NULL,
    attribute_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    authorization_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    email_optional boolean DEFAULT false NOT NULL,
    issuer text,
    discovery_url text,
    skip_nonce_check boolean DEFAULT false NOT NULL,
    cached_discovery jsonb,
    discovery_cached_at timestamp with time zone,
    authorization_url text,
    token_url text,
    userinfo_url text,
    jwks_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT custom_oauth_providers_authorization_url_https CHECK (((authorization_url IS NULL) OR (authorization_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_authorization_url_length CHECK (((authorization_url IS NULL) OR (char_length(authorization_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_client_id_length CHECK (((char_length(client_id) >= 1) AND (char_length(client_id) <= 512))),
    CONSTRAINT custom_oauth_providers_discovery_url_length CHECK (((discovery_url IS NULL) OR (char_length(discovery_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_identifier_format CHECK ((identifier ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::text)),
    CONSTRAINT custom_oauth_providers_issuer_length CHECK (((issuer IS NULL) OR ((char_length(issuer) >= 1) AND (char_length(issuer) <= 2048)))),
    CONSTRAINT custom_oauth_providers_jwks_uri_https CHECK (((jwks_uri IS NULL) OR (jwks_uri ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_jwks_uri_length CHECK (((jwks_uri IS NULL) OR (char_length(jwks_uri) <= 2048))),
    CONSTRAINT custom_oauth_providers_name_length CHECK (((char_length(name) >= 1) AND (char_length(name) <= 100))),
    CONSTRAINT custom_oauth_providers_oauth2_requires_endpoints CHECK (((provider_type <> 'oauth2'::text) OR ((authorization_url IS NOT NULL) AND (token_url IS NOT NULL) AND (userinfo_url IS NOT NULL)))),
    CONSTRAINT custom_oauth_providers_oidc_discovery_url_https CHECK (((provider_type <> 'oidc'::text) OR (discovery_url IS NULL) OR (discovery_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_issuer_https CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NULL) OR (issuer ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_requires_issuer CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NOT NULL))),
    CONSTRAINT custom_oauth_providers_provider_type_check CHECK ((provider_type = ANY (ARRAY['oauth2'::text, 'oidc'::text]))),
    CONSTRAINT custom_oauth_providers_token_url_https CHECK (((token_url IS NULL) OR (token_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_token_url_length CHECK (((token_url IS NULL) OR (char_length(token_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_userinfo_url_https CHECK (((userinfo_url IS NULL) OR (userinfo_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_userinfo_url_length CHECK (((userinfo_url IS NULL) OR (char_length(userinfo_url) <= 2048)))
);


ALTER TABLE auth.custom_oauth_providers OWNER TO supabase_auth_admin;

--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


ALTER TABLE auth.flow_state OWNER TO supabase_auth_admin;

--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE auth.identities OWNER TO supabase_auth_admin;

--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE auth.instances OWNER TO supabase_auth_admin;

--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


ALTER TABLE auth.mfa_amr_claims OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


ALTER TABLE auth.mfa_challenges OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


ALTER TABLE auth.mfa_factors OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


ALTER TABLE auth.oauth_authorizations OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


ALTER TABLE auth.oauth_client_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


ALTER TABLE auth.oauth_clients OWNER TO supabase_auth_admin;

--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


ALTER TABLE auth.oauth_consents OWNER TO supabase_auth_admin;

--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


ALTER TABLE auth.one_time_tokens OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


ALTER TABLE auth.refresh_tokens OWNER TO supabase_auth_admin;

--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: supabase_auth_admin
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE auth.refresh_tokens_id_seq OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: supabase_auth_admin
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


ALTER TABLE auth.saml_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


ALTER TABLE auth.saml_relay_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE auth.schema_migrations OWNER TO supabase_auth_admin;

--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


ALTER TABLE auth.sessions OWNER TO supabase_auth_admin;

--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


ALTER TABLE auth.sso_domains OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


ALTER TABLE auth.sso_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


ALTER TABLE auth.users OWNER TO supabase_auth_admin;

--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: webauthn_challenges; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.webauthn_challenges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    challenge_type text NOT NULL,
    session_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT webauthn_challenges_challenge_type_check CHECK ((challenge_type = ANY (ARRAY['signup'::text, 'registration'::text, 'authentication'::text])))
);


ALTER TABLE auth.webauthn_challenges OWNER TO supabase_auth_admin;

--
-- Name: webauthn_credentials; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.webauthn_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    credential_id bytea NOT NULL,
    public_key bytea NOT NULL,
    attestation_type text DEFAULT ''::text NOT NULL,
    aaguid uuid,
    sign_count bigint DEFAULT 0 NOT NULL,
    transports jsonb DEFAULT '[]'::jsonb NOT NULL,
    backup_eligible boolean DEFAULT false NOT NULL,
    backed_up boolean DEFAULT false NOT NULL,
    friendly_name text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


ALTER TABLE auth.webauthn_credentials OWNER TO supabase_auth_admin;

--
-- Name: permiso; Type: TABLE; Schema: iam; Owner: postgres
--

CREATE TABLE iam.permiso (
    id smallint NOT NULL,
    code text NOT NULL,
    descripcion text
);


ALTER TABLE iam.permiso OWNER TO postgres;

--
-- Name: permiso_id_seq; Type: SEQUENCE; Schema: iam; Owner: postgres
--

ALTER TABLE iam.permiso ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME iam.permiso_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: rol; Type: TABLE; Schema: iam; Owner: postgres
--

CREATE TABLE iam.rol (
    id smallint NOT NULL,
    code text NOT NULL,
    nombre text NOT NULL,
    descripcion text
);


ALTER TABLE iam.rol OWNER TO postgres;

--
-- Name: rol_id_seq; Type: SEQUENCE; Schema: iam; Owner: postgres
--

ALTER TABLE iam.rol ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME iam.rol_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: rol_permiso; Type: TABLE; Schema: iam; Owner: postgres
--

CREATE TABLE iam.rol_permiso (
    rol_id smallint NOT NULL,
    permiso_id smallint NOT NULL
);


ALTER TABLE iam.rol_permiso OWNER TO postgres;

--
-- Name: user_rol; Type: TABLE; Schema: iam; Owner: postgres
--

CREATE TABLE iam.user_rol (
    user_id integer NOT NULL,
    rol_id smallint NOT NULL
);


ALTER TABLE iam.user_rol OWNER TO postgres;

--
-- Name: notifications; Type: TABLE; Schema: notification; Owner: postgres
--

CREATE TABLE notification.notifications (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    tipo text NOT NULL,
    payload jsonb,
    fyh_leido timestamp with time zone,
    fyh_cre timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notifications_tipo_check CHECK ((tipo = ANY (ARRAY['info'::text, 'warning'::text, 'alert'::text, 'task'::text])))
);


ALTER TABLE notification.notifications OWNER TO postgres;

--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: notification; Owner: postgres
--

ALTER TABLE notification.notifications ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME notification.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: adicional; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.adicional (
    id smallint NOT NULL,
    adicional text
);


ALTER TABLE public.adicional OWNER TO postgres;

--
-- Name: adicional_pk_adicional_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.adicional ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.adicional_pk_adicional_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: articulo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.articulo (
    id smallint NOT NULL,
    articulo text,
    grupo_articulo text,
    tipo_articulo_id smallint NOT NULL
);


ALTER TABLE public.articulo OWNER TO postgres;

--
-- Name: articulo_pk_articulo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.articulo ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.articulo_pk_articulo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditoria; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auditoria (
    id integer NOT NULL,
    partida_id integer,
    fecha_auditoria date,
    estado text
);


ALTER TABLE public.auditoria OWNER TO postgres;

--
-- Name: auditoria_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auditoria ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: catalogo_precios; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: catalogo_precios_id_precio_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.catalogo_precios_id_precio_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.catalogo_precios_id_precio_seq OWNER TO postgres;

--
-- Name: catalogo_precios_id_precio_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.catalogo_precios_id_precio_seq OWNED BY public.catalogo_precios.id_precio;


--
-- Name: cliente; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: cliente_pk_cliente_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.cliente ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.cliente_pk_cliente_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: color; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.color (
    id integer NOT NULL,
    color character varying(25),
    usr_cre integer DEFAULT public.get_user_id(),
    color_normalizado text GENERATED ALWAYS AS (regexp_replace(lower(TRIM(BOTH FROM color)), '\s+'::text, ''::text, 'g'::text)) STORED
);


ALTER TABLE public.color OWNER TO postgres;

--
-- Name: color_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.color_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.color_id_seq OWNER TO postgres;

--
-- Name: color_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.color_id_seq OWNED BY public.color.id;


--
-- Name: color_x_cliente; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.color_x_cliente (
    id smallint NOT NULL,
    color_id smallint,
    cliente_id smallint,
    valor_id smallint,
    intensidad_id smallint,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre integer DEFAULT public.get_user_id(),
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.color_x_cliente OWNER TO postgres;

--
-- Name: color_x_cliente_pk_color_x_cliente_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.color_x_cliente ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.color_x_cliente_pk_color_x_cliente_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: colores; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.colores AS
 SELECT cc.id,
    col.color,
    cli.cliente AS tono
   FROM ((public.color_x_cliente cc
     LEFT JOIN public.color col ON ((col.id = cc.color_id)))
     LEFT JOIN public.cliente cli ON ((cli.id = cc.cliente_id)));


ALTER TABLE public.colores OWNER TO postgres;

--
-- Name: compactado; Type: TABLE; Schema: public; Owner: postgres
--

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
    tipo_partida character varying,
    estado character varying,
    rib integer
);


ALTER TABLE public.compactado OWNER TO postgres;

--
-- Name: compactado_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.compactado ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.compactado_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: compra; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: compra_pk_compra_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.compra ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.compra_pk_compra_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: compra_x_insumo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.compra_x_insumo (
    id integer NOT NULL,
    compra_id integer,
    insumo_id smallint,
    cantidad numeric(10,2) NOT NULL,
    precio_x_kg_usd numeric(7,4) NOT NULL,
    insumo_x_proveedor_id integer
);


ALTER TABLE public.compra_x_insumo OWNER TO postgres;

--
-- Name: compra_x_insumo_pk_compra_x_insumo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.compra_x_insumo ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.compra_x_insumo_pk_compra_x_insumo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: entrada_inventario; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: entrada_inventario_detalle; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: insumo; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: insumo_x_proveedor; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: inventario; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: proveedor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.proveedor (
    id smallint NOT NULL,
    proveedor text NOT NULL COLLATE pg_catalog."C",
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usr_cre text DEFAULT CURRENT_USER,
    fyh_cre_tz timestamp with time zone DEFAULT now(),
    proveedor_normalizado text GENERATED ALWAYS AS (regexp_replace(lower(TRIM(BOTH FROM proveedor)), '\s+'::text, ''::text, 'g'::text)) STORED
);


ALTER TABLE public.proveedor OWNER TO postgres;

--
-- Name: salida_inventario_detalle_x_stock; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: vw_insumos_proveedor; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_insumos_proveedor OWNER TO postgres;

--
-- Name: vw_inventario; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_inventario OWNER TO postgres;

--
-- Name: comrpas_pendientes_completas; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.comrpas_pendientes_completas OWNER TO postgres;

--
-- Name: cuadre_inventario; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: cuadre_inventario_detalle; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: cuadre_inventario_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.cuadre_inventario_detalle ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.cuadre_inventario_detalle_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cuadre_inventario_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.cuadre_inventario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.cuadre_inventario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: desarrollo_color; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: desarrollo_color_pk_desarrollo_color_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.desarrollo_color ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.desarrollo_color_pk_desarrollo_color_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: despacho; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: despacho_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.despacho ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.despacho_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: detecciones; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: detecciones_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.detecciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.detecciones_id_seq OWNER TO postgres;

--
-- Name: detecciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.detecciones_id_seq OWNED BY public.detecciones.id;


--
-- Name: devolucion; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: devolucion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.devolucion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.devolucion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: entrada_inventario_detalle_pk_entrada_inventario_detalle_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.entrada_inventario_detalle ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.entrada_inventario_detalle_pk_entrada_inventario_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: entrada_inventario_pk_entrada_inventario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.entrada_inventario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.entrada_inventario_pk_entrada_inventario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estado; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estado (
    id integer NOT NULL,
    estado text NOT NULL,
    descripcion text,
    fyh_cre timestamp with time zone
);


ALTER TABLE public.estado OWNER TO postgres;

--
-- Name: estado_desarrollo_color; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estado_desarrollo_color (
    id smallint NOT NULL,
    estado_desarrollo_color text NOT NULL
);


ALTER TABLE public.estado_desarrollo_color OWNER TO postgres;

--
-- Name: estado_desarrollo_color_pk_estado_desarrollo_color_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.estado_desarrollo_color ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.estado_desarrollo_color_pk_estado_desarrollo_color_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estado_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.estado_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.estado_id_seq OWNER TO postgres;

--
-- Name: estado_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.estado_id_seq OWNED BY public.estado.id;


--
-- Name: extra; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.extra (
    id smallint NOT NULL,
    cod_extra character varying(10),
    extra character varying(30)
);


ALTER TABLE public.extra OWNER TO postgres;

--
-- Name: extra_pk_extra_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.extra ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.extra_pk_extra_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: historial_estado_color; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: historial_estado_color_id_historial_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.historial_estado_color ALTER COLUMN id_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.historial_estado_color_id_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: hora_inicio_maquina; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.hora_inicio_maquina (
    maquina_id smallint NOT NULL,
    hora_inicio time without time zone NOT NULL
);


ALTER TABLE public.hora_inicio_maquina OWNER TO postgres;

--
-- Name: id_receta_x_partida; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.id_receta_x_partida (
    id integer
);


ALTER TABLE public.id_receta_x_partida OWNER TO postgres;

--
-- Name: insumo_corregido; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.insumo_corregido (
    id smallint,
    insumo text,
    medida public.medida_enum,
    precio numeric(7,3),
    nombre_anterior character varying
);


ALTER TABLE public.insumo_corregido OWNER TO postgres;

--
-- Name: insumo_pk_insumo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.insumo ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insumo_pk_insumo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: insumo_x_proveedor_pk_insumo_x_proveedor_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.insumo_x_proveedor ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insumo_x_proveedor_pk_insumo_x_proveedor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: insumos_precio; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: insumos_precio_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.insumos_precio ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insumos_precio_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: intensidad; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.intensidad (
    id smallint NOT NULL,
    intensidad text
);


ALTER TABLE public.intensidad OWNER TO postgres;

--
-- Name: intensidad_pk_intensidad_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.intensidad ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.intensidad_pk_intensidad_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_pk_inventario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.inventario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_pk_inventario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: json_debug_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.json_debug_log (
    id integer NOT NULL,
    received_at timestamp without time zone DEFAULT now(),
    received_json jsonb,
    received_at_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.json_debug_log OWNER TO postgres;

--
-- Name: json_debug_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.json_debug_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.json_debug_log_id_seq OWNER TO postgres;

--
-- Name: json_debug_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.json_debug_log_id_seq OWNED BY public.json_debug_log.id;


--
-- Name: lavado_maquina; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lavado_maquina (
    id integer NOT NULL,
    fecha date,
    receta_lavado_mq_id smallint,
    maquina_id smallint,
    fyh_cre timestamp without time zone
);


ALTER TABLE public.lavado_maquina OWNER TO postgres;

--
-- Name: lavado_maquina_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.lavado_maquina ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.lavado_maquina_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: letra_compra; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: letra_compra_pk_letra_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.letra_compra_pk_letra_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.letra_compra_pk_letra_seq OWNER TO postgres;

--
-- Name: letra_compra_pk_letra_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.letra_compra_pk_letra_seq OWNED BY public.letra_compra.id;


--
-- Name: logs_api; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.logs_api (
    id integer NOT NULL,
    function_name text,
    user_id integer,
    params jsonb,
    called_at timestamp with time zone DEFAULT now(),
    error_message text,
    error_detail text,
    error_context text
);


ALTER TABLE public.logs_api OWNER TO postgres;

--
-- Name: logs_api_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.logs_api ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.logs_api_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: maquina; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.maquina (
    id integer NOT NULL,
    nombre character varying(20),
    ubicacion character varying(20),
    seccion character varying(15),
    "RB" integer,
    impacto character varying(10)
);


ALTER TABLE public.maquina OWNER TO postgres;

--
-- Name: matizado; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: matizado_estados; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.matizado_estados (
    id integer NOT NULL,
    partida_id integer,
    fecha date,
    estado character varying(50)
);


ALTER TABLE public.matizado_estados OWNER TO postgres;

--
-- Name: matizado_estados_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.matizado_estados_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.matizado_estados_id_seq OWNER TO postgres;

--
-- Name: matizado_estados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.matizado_estados_id_seq OWNED BY public.matizado_estados.id;


--
-- Name: matizado_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.matizado ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.matizado_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: metas_produccion_tenido; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: metas_produccion_tenido_pk_meta_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.metas_produccion_tenido_pk_meta_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.metas_produccion_tenido_pk_meta_seq OWNER TO postgres;

--
-- Name: metas_produccion_tenido_pk_meta_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.metas_produccion_tenido_pk_meta_seq OWNED BY public.metas_produccion_tenido.id;


--
-- Name: motivo_parada; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.motivo_parada (
    id integer NOT NULL,
    categoria text,
    motivo text NOT NULL,
    tipo text,
    critico boolean DEFAULT false
);


ALTER TABLE public.motivo_parada OWNER TO postgres;

--
-- Name: motivo_parada_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.motivo_parada_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.motivo_parada_id_seq OWNER TO postgres;

--
-- Name: motivo_parada_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.motivo_parada_id_seq OWNED BY public.motivo_parada.id;


--
-- Name: motivos_retraso; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.motivos_retraso (
    id bigint NOT NULL,
    motivo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.motivos_retraso OWNER TO postgres;

--
-- Name: motivos_retraso_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.motivos_retraso_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.motivos_retraso_id_seq OWNER TO postgres;

--
-- Name: motivos_retraso_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.motivos_retraso_id_seq OWNED BY public.motivos_retraso.id;


--
-- Name: observaciones_planta; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: observaciones_planta_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.observaciones_planta ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.observaciones_planta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: observado; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: observado_estados; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.observado_estados (
    id integer NOT NULL,
    partida_id integer,
    fecha date,
    estado character varying(50)
);


ALTER TABLE public.observado_estados OWNER TO postgres;

--
-- Name: observado_estados_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.observado_estados_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.observado_estados_id_seq OWNER TO postgres;

--
-- Name: observado_estados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.observado_estados_id_seq OWNED BY public.observado_estados.id;


--
-- Name: observado_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.observado ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.observado_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: observado_motivos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.observado_motivos (
    id integer NOT NULL,
    motivo text
);


ALTER TABLE public.observado_motivos OWNER TO postgres;

--
-- Name: observado_motivos_pk_observado_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.observado_motivos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.observado_motivos_pk_observado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: parada_tintoreria; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: parada_tintoreria_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.parada_tintoreria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.parada_tintoreria_id_seq OWNER TO postgres;

--
-- Name: parada_tintoreria_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.parada_tintoreria_id_seq OWNED BY public.parada_tintoreria.id;


--
-- Name: parada_tmp; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: partida_codigo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partida_codigo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.partida_codigo_seq OWNER TO postgres;

--
-- Name: partida; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: partida_estado_historial; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: partida_estado_historial_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partida_estado_historial_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.partida_estado_historial_id_seq OWNER TO postgres;

--
-- Name: partida_estado_historial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partida_estado_historial_id_seq OWNED BY public.partida_estado_historial.id;


--
-- Name: partida_pk_partida_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.partida ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.partida_pk_partida_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: partida_x_extra; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partida_x_extra (
    partida_id integer,
    extra_id smallint,
    cantidad smallint,
    peso numeric(6,2)
);


ALTER TABLE public.partida_x_extra OWNER TO postgres;

--
-- Name: partida_x_recetas; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: partida_x_recetas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.partida_x_recetas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.partida_x_recetas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: paso; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.paso (
    id smallint NOT NULL,
    paso text COLLATE public.case_insensitive
);


ALTER TABLE public.paso OWNER TO postgres;

--
-- Name: paso_pk_paso_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.paso ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.paso_pk_paso_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pasos_adicional_receta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pasos_adicional_receta (
    id_receta integer,
    pasos text,
    orden integer,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.pasos_adicional_receta OWNER TO postgres;

--
-- Name: perchado; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: perchado_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.perchado ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.perchado_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: previo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.previo (
    id smallint NOT NULL,
    previo text
);


ALTER TABLE public.previo OWNER TO postgres;

--
-- Name: previo_pk_previo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.previo ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.previo_pk_previo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prioridad; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.prioridad (
    id smallint NOT NULL,
    prioridad text
);


ALTER TABLE public.prioridad OWNER TO postgres;

--
-- Name: prioridad_pk_prioridad_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.prioridad ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.prioridad_pk_prioridad_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prod_tmp; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: produccion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.produccion (
    partida integer,
    "fecha_teñido" date,
    partida character varying(15),
    maquina character varying(20),
    tipo character varying(50),
    hora_inicio time without time zone,
    hora_fin time without time zone,
    duracion_total time without time zone,
    duracion_estandar time without time zone,
    estado character varying(15)
);


ALTER TABLE public.produccion OWNER TO postgres;

--
-- Name: produccion_tenido; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: TABLE produccion_tenido; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.produccion_tenido IS 'Produccion diaria de teñido';


--
-- Name: produccion_tenido_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.produccion_tenido ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.produccion_tenido_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    id_usuario integer NOT NULL,
    first_name text,
    last_name text
);


ALTER TABLE public.profiles OWNER TO postgres;

--
-- Name: profiles_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.profiles ALTER COLUMN id_usuario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.profiles_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: programa_tenido; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: programa_tenido_pk_programa_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.programa_tenido_pk_programa_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.programa_tenido_pk_programa_seq OWNER TO postgres;

--
-- Name: programa_tenido_pk_programa_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.programa_tenido_pk_programa_seq OWNED BY public.programa_tenido.id;


--
-- Name: programacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.programacion (
    partida integer,
    fecha_programacion date,
    maquina_id smallint
);


ALTER TABLE public.programacion OWNER TO postgres;

--
-- Name: proveedor_pk_proveedor_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.proveedor ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.proveedor_pk_proveedor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: proveedor_precio; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: proveedor_precio_pk_proveedor_precio_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.proveedor_precio ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.proveedor_precio_pk_proveedor_precio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receta2; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: receta2_pk_receta_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.receta2 ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.receta2_pk_receta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receta_id; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.receta_id (
    id integer
);


ALTER TABLE public.receta_id OWNER TO postgres;

--
-- Name: receta_lavado_maquina; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: receta_lavado_maquina_pk_receta_lavado_mq_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.receta_lavado_maquina ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.receta_lavado_maquina_pk_receta_lavado_mq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receta_lavado_maquina_x_insumo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.receta_lavado_maquina_x_insumo (
    receta_lavado_mq_id integer,
    insumo_id smallint,
    cantidad numeric(10,4) NOT NULL,
    orden smallint NOT NULL
);


ALTER TABLE public.receta_lavado_maquina_x_insumo OWNER TO postgres;

--
-- Name: receta_lavado_maquina_x_paso; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.receta_lavado_maquina_x_paso (
    receta_lavado_mq_id integer,
    paso_id smallint,
    orden smallint NOT NULL
);


ALTER TABLE public.receta_lavado_maquina_x_paso OWNER TO postgres;

--
-- Name: receta_x_insumo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.receta_x_insumo (
    receta_id integer,
    insumo_id smallint,
    cantidad numeric(8,4) NOT NULL,
    orden smallint NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.receta_x_insumo OWNER TO postgres;

--
-- Name: receta_x_insumo_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.receta_x_insumo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.receta_x_insumo_id_seq OWNER TO postgres;

--
-- Name: receta_x_insumo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.receta_x_insumo_id_seq OWNED BY public.receta_x_insumo.id;


--
-- Name: receta_x_paso; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.receta_x_paso (
    receta_id integer,
    paso_id smallint,
    orden smallint NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.receta_x_paso OWNER TO postgres;

--
-- Name: receta_x_paso_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.receta_x_paso_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.receta_x_paso_id_seq OWNER TO postgres;

--
-- Name: receta_x_paso_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.receta_x_paso_id_seq OWNED BY public.receta_x_paso.id;


--
-- Name: regla_peso_articulo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.regla_peso_articulo (
    articulo_id smallint NOT NULL,
    min_kg_por_rollo numeric(10,3) NOT NULL
);


ALTER TABLE public.regla_peso_articulo OWNER TO postgres;

--
-- Name: regla_peso_cliente_articulo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.regla_peso_cliente_articulo (
    cliente_id smallint NOT NULL,
    articulo_id smallint NOT NULL,
    min_kg_por_rollo numeric(10,3) NOT NULL
);


ALTER TABLE public.regla_peso_cliente_articulo OWNER TO postgres;

--
-- Name: retrasos_partida; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.retrasos_partida (
    id bigint NOT NULL,
    partida_id bigint NOT NULL,
    motivo_id bigint NOT NULL,
    observacion text,
    fecha date,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.retrasos_partida OWNER TO postgres;

--
-- Name: retrasos_partida_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.retrasos_partida_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retrasos_partida_id_seq OWNER TO postgres;

--
-- Name: retrasos_partida_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.retrasos_partida_id_seq OWNED BY public.retrasos_partida.id;


--
-- Name: salida_inventario; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: salida_inventario_detalle; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: salida_inventario_detalle_pk_salida_inventario_detalle_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.salida_inventario_detalle ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salida_inventario_detalle_pk_salida_inventario_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salida_inventario_detalle_x_s_pk_salida_inventario_detalle__seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.salida_inventario_detalle_x_stock ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salida_inventario_detalle_x_s_pk_salida_inventario_detalle__seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salida_inventario_pk_salida_inventario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.salida_inventario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salida_inventario_pk_salida_inventario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: temp_id_partida; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.temp_id_partida (
    id integer
);


ALTER TABLE public.temp_id_partida OWNER TO postgres;

--
-- Name: temp_id_receta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.temp_id_receta (
    id integer
);


ALTER TABLE public.temp_id_receta OWNER TO postgres;

--
-- Name: temp_insumos_corregidos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.temp_insumos_corregidos (
    id bigint,
    insumo text,
    medida text,
    precio text,
    nombre_anterior text
);


ALTER TABLE public.temp_insumos_corregidos OWNER TO postgres;

--
-- Name: tenido; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tenido (
    id smallint NOT NULL,
    tenido text
);


ALTER TABLE public.tenido OWNER TO postgres;

--
-- Name: termofijado; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: termofijado_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.termofijado ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.termofijado_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: teñido_pk_teñido_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tenido ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."teñido_pk_teñido_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tiempos_estandar_lavado; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tiempos_estandar_lavado (
    id integer NOT NULL,
    tipo_lavado_mq_id smallint,
    duracion interval NOT NULL,
    fyh_cre timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    flg_activo boolean DEFAULT true,
    fyh_cre_tz timestamp with time zone DEFAULT now()
);


ALTER TABLE public.tiempos_estandar_lavado OWNER TO postgres;

--
-- Name: tiempos_estandar_lavado_pk_tiempo_lavado_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tiempos_estandar_lavado_pk_tiempo_lavado_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tiempos_estandar_lavado_pk_tiempo_lavado_seq OWNER TO postgres;

--
-- Name: tiempos_estandar_lavado_pk_tiempo_lavado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tiempos_estandar_lavado_pk_tiempo_lavado_seq OWNED BY public.tiempos_estandar_lavado.id;


--
-- Name: tiempos_estandar_tenido; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: tiempos_estandar_tenido_pk_tiempo_tenido_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tiempos_estandar_tenido_pk_tiempo_tenido_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tiempos_estandar_tenido_pk_tiempo_tenido_seq OWNER TO postgres;

--
-- Name: tiempos_estandar_tenido_pk_tiempo_tenido_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tiempos_estandar_tenido_pk_tiempo_tenido_seq OWNED BY public.tiempos_estandar_tenido.id;


--
-- Name: tipo_articulo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_articulo (
    id smallint NOT NULL,
    tipo_articulo text
);


ALTER TABLE public.tipo_articulo OWNER TO postgres;

--
-- Name: tipo_articulo_pk_tipo_articulo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tipo_articulo ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_articulo_pk_tipo_articulo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_lavado_maquina; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_lavado_maquina (
    id bigint NOT NULL,
    tipo_lavado_mq text
);


ALTER TABLE public.tipo_lavado_maquina OWNER TO postgres;

--
-- Name: tipo_lavado_fk_tipo_lavado_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tipo_lavado_maquina ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_lavado_fk_tipo_lavado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_receta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_receta (
    id smallint NOT NULL,
    tipo_receta text COLLATE public.case_insensitive
);


ALTER TABLE public.tipo_receta OWNER TO postgres;

--
-- Name: tipo_receta_pk_tipo_receta_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tipo_receta ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_receta_pk_tipo_receta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tmp; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: tmp2; Type: TABLE; Schema: public; Owner: postgres
--

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

--
-- Name: tmp_parche; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tmp_parche (
    fk_receta integer,
    paso text COLLATE public.case_insensitive,
    orden_representativo text COLLATE public.case_insensitive
);


ALTER TABLE public.tmp_parche OWNER TO postgres;

--
-- Name: tmp_receta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tmp_receta (
    fk_receta integer
);


ALTER TABLE public.tmp_receta OWNER TO postgres;

--
-- Name: tmp_receta_casos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tmp_receta_casos (
    fk_receta integer
);


ALTER TABLE public.tmp_receta_casos OWNER TO postgres;

--
-- Name: turno; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.turno (
    id bigint NOT NULL,
    nombre character varying NOT NULL
);


ALTER TABLE public.turno OWNER TO postgres;

--
-- Name: turno_pk_turno_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.turno ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turno_pk_turno_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_receta_id; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.v_receta_id (
    receta_id integer
);


ALTER TABLE public.v_receta_id OWNER TO postgres;

--
-- Name: valor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.valor (
    id smallint NOT NULL,
    valor text
);


ALTER TABLE public.valor OWNER TO postgres;

--
-- Name: valor_pk_valor_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.valor ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.valor_pk_valor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vw_catalogo_precios; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_catalogo_precios AS
 SELECT a.id_precio,
    b.color,
    b.tono AS cliente,
    c.tipo_articulo,
    d.tenido,
    a.fibra,
    e.adicional AS antipilling,
    a.precio_tenido
   FROM ((((public.catalogo_precios a
     LEFT JOIN public.colores b ON ((a.color_x_cliente_id = b.id)))
     LEFT JOIN public.tipo_articulo c ON ((a.tipo_articulo_id = c.id)))
     LEFT JOIN public.tenido d ON ((a.tenido_id = d.id)))
     LEFT JOIN public.adicional e ON ((a.adicional_id = e.id)))
  WHERE (a.activo = 1);


ALTER TABLE public.vw_catalogo_precios OWNER TO postgres;

--
-- Name: vw_colores; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_colores AS
 SELECT a.id AS color_x_cliente_id,
    b.id AS color_id,
    b.color,
    c.id AS cliente_id,
    c.cliente AS tono
   FROM ((public.color_x_cliente a
     JOIN public.color b ON ((a.color_id = b.id)))
     JOIN public.cliente c ON ((a.cliente_id = c.id)));


ALTER TABLE public.vw_colores OWNER TO postgres;

--
-- Name: vw_compra_insumos; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_compra_insumos OWNER TO postgres;

--
-- Name: vw_compras_reporte; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_compras_reporte OWNER TO postgres;

--
-- Name: vw_compra_x_proveedor_x_mes; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_compra_x_proveedor_x_mes OWNER TO postgres;

--
-- Name: vw_compras; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_compras OWNER TO postgres;

--
-- Name: vw_produccion_tenido_procesada; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_produccion_tenido_procesada AS
 WITH base AS (
         SELECT produccion_tenido.fecha,
            produccion_tenido.partida_id AS fk_partida,
                CASE
                    WHEN (((produccion_tenido.tipo)::text ~~* '%Lavado%'::text) OR ((produccion_tenido.tipo)::text ~~* '%Mojar%'::text)) THEN 'Lavado'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Desmontado + Reteñido'::text) THEN 'Desmontado'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Repartida Desmontado'::text) THEN 'Desmontado'::character varying
                    WHEN ((produccion_tenido.tipo)::text = ANY (ARRAY[('Reteñido'::character varying)::text, ('Rebaje'::character varying)::text, ('Repartida Matizado'::character varying)::text, ('Repartida Otros'::character varying)::text])) THEN 'Repartida'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Teñido'::text) THEN 'Produccion'::character varying
                    WHEN ((produccion_tenido.tipo)::text = 'Repartida Antiguo'::text) THEN 'Rep. Antiguo'::character varying
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
          WHERE ((produccion_tenido.estado)::text = ANY (ARRAY[('En partida Teñido'::character varying)::text, ('Teñido'::character varying)::text]))
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
                    WHEN (((marcado.estado)::text = 'Teñido'::text) AND ((marcado.estado_prev)::text = 'En partida Teñido'::text)) THEN marcado.rn_prev
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
    string_agg(DISTINCT (bloques.estado)::text, ','::text) AS partidas
   FROM bloques
  GROUP BY bloques.fk_partida, bloques.tipo, bloques.subtipo, bloques.maquina, bloques.bloque_id
  ORDER BY bloques.fk_partida, (min(bloques.fecha));


ALTER TABLE public.vw_produccion_tenido_procesada OWNER TO postgres;

--
-- Name: vw_costeo_lavado; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_costeo_lavado AS
 WITH tmp_partida_x_receta_fn AS (
         SELECT a.id AS pk_partida_receta,
            a.partida_id,
            a.receta_id,
            b.tipo_receta,
            c.id AS pk_salida_inventario,
            c.fecha_salida,
            a.fecha
           FROM ((public.partida_x_recetas a
             LEFT JOIN public.tipo_receta b ON ((a.tipo_receta_id = b.id)))
             JOIN public.salida_inventario c ON (((a.id = c.partida_x_recetas_id) AND (c.estado = 'aprobado'::public.estado_salida_inventario_enum) AND (c.motivo = 'receta'::public.motivo_salida_inventario_enum))))
        ), insumos_salida AS (
         SELECT sid.salida_inventario_id AS fk_salida_inventario,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS costo_total_dir
           FROM ((public.salida_inventario_detalle sid
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
          GROUP BY sid.salida_inventario_id
        ), costos_partida AS (
         SELECT a.partida,
            a.tipo,
            a.subtipo,
            a.fecha_inicio AS fecha_partida,
            b.receta_id,
            c.costo_total_dir
           FROM ((public.vw_produccion_tenido_procesada a
             LEFT JOIN tmp_partida_x_receta_fn b ON (((a.partida = b.partida_id) AND ((a.subtipo)::text = b.tipo_receta) AND ((b.fecha >= (a.fecha_inicio - '5 days'::interval)) AND (b.fecha <= a.fecha_inicio)))))
             LEFT JOIN insumos_salida c ON ((b.pk_salida_inventario = c.fk_salida_inventario)))
          WHERE (((a.tipo)::text = 'Lavado'::text) AND (a.fecha_inicio >= '2025-10-01'::date))
        ), ajuste_receta AS (
         SELECT c.partida_id,
            tr.tipo_receta,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS c_ajs
           FROM ((((((public.salida_inventario a
             JOIN public.salida_inventario_detalle sid ON ((a.id = sid.salida_inventario_id)))
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
             JOIN public.partida_x_recetas c ON ((a.partida_x_recetas_id = c.id)))
             JOIN public.tipo_receta tr ON ((c.tipo_receta_id = tr.id)))
             JOIN public.vw_produccion_tenido_procesada pr ON (((pr.partida = c.partida_id) AND ((pr.subtipo)::text = tr.tipo_receta) AND ((pr.tipo)::text = 'Lavado'::text) AND ((pr.fecha_inicio >= (c.fecha - '5 days'::interval)) AND (pr.fecha_inicio <= (c.fecha + '5 days'::interval))))))
          WHERE ((a.motivo = 'ajuste receta'::public.motivo_salida_inventario_enum) AND ((tr.tipo_receta COLLATE "C") = ANY (ARRAY['Lavado x Lineas Suavizante'::text, 'Lavado x Suavidad'::text, 'Lavado x Manchas'::text, 'Lavado x Lineas'::text, 'Lavado x Migrado'::text, 'Lavado x Quebradura'::text, 'Lavado x Fijado'::text])))
          GROUP BY c.partida_id, tr.tipo_receta
        ), lavado_fuera AS (
         SELECT c.partida_id,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS c_lavf
           FROM ((((public.salida_inventario a
             JOIN public.salida_inventario_detalle sid ON ((a.id = sid.salida_inventario_id)))
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
             LEFT JOIN public.partida_x_recetas c ON ((a.partida_x_recetas_id = c.id)))
          WHERE (a.motivo = 'lavado'::public.motivo_salida_inventario_enum)
          GROUP BY c.partida_id
        )
 SELECT cp.partida AS partida_id,
    cp.tipo,
    cp.subtipo AS tipo_lavado,
    cp.fecha_partida,
    max(cp.receta_id) AS receta_id,
    round(COALESCE(sum(cp.costo_total_dir), (0)::numeric), 2) AS c_lav,
    round(COALESCE(ar.c_ajs, (0)::numeric), 2) AS c_ajs,
    round(COALESCE(lavf.c_lavf, (0)::numeric), 2) AS c_lavf,
    round(((COALESCE(sum(cp.costo_total_dir), (0)::numeric) + COALESCE(ar.c_ajs, (0)::numeric)) + COALESCE(lavf.c_lavf, (0)::numeric)), 2) AS c_tot
   FROM ((costos_partida cp
     LEFT JOIN ajuste_receta ar ON (((cp.partida = ar.partida_id) AND ((cp.subtipo)::text = ar.tipo_receta))))
     LEFT JOIN lavado_fuera lavf ON ((cp.partida = lavf.partida_id)))
  GROUP BY cp.partida, cp.tipo, cp.subtipo, cp.fecha_partida, ar.c_ajs, lavf.c_lavf
  ORDER BY cp.fecha_partida, cp.partida;


ALTER TABLE public.vw_costeo_lavado OWNER TO postgres;

--
-- Name: vw_costeo_partida; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_costeo_partida AS
 WITH tmp_partida_x_receta_fn AS (
         SELECT a.id AS pk_partida_receta,
            a.partida_id,
            a.receta_id,
            b.tipo_receta,
            c.id AS pk_salida_inventario,
            c.fecha_salida,
            a.fecha
           FROM ((public.partida_x_recetas a
             LEFT JOIN public.tipo_receta b ON ((a.tipo_receta_id = b.id)))
             JOIN public.salida_inventario c ON (((a.id = c.partida_x_recetas_id) AND (c.estado = 'aprobado'::public.estado_salida_inventario_enum) AND (c.motivo = 'receta'::public.motivo_salida_inventario_enum))))
        ), insumos_salida AS (
         SELECT sid.salida_inventario_id AS fk_salida_inventario,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS costo_total_dir
           FROM ((public.salida_inventario_detalle sid
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
          GROUP BY sid.salida_inventario_id
        ), costos_partida AS (
         SELECT a.partida,
            a.tipo,
            b.receta_id,
            c.costo_total_dir
           FROM ((public.vw_produccion_tenido_procesada a
             LEFT JOIN tmp_partida_x_receta_fn b ON (((a.partida = b.partida_id) AND ((a.subtipo)::text = b.tipo_receta) AND (b.fecha <= a.fecha_inicio))))
             LEFT JOIN insumos_salida c ON ((b.pk_salida_inventario = c.fk_salida_inventario)))
          WHERE (a.fecha_inicio >= '2025-08-01'::date)
        ), ajuste_receta AS (
         SELECT c.partida_id,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS c_ajs
           FROM ((((public.salida_inventario a
             JOIN public.salida_inventario_detalle sid ON ((a.id = sid.salida_inventario_id)))
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
             LEFT JOIN public.partida_x_recetas c ON ((a.partida_x_recetas_id = c.id)))
          WHERE (a.motivo = 'ajuste receta'::public.motivo_salida_inventario_enum)
          GROUP BY c.partida_id
        ), matizado AS (
         SELECT c.partida_id,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS c_mat
           FROM ((((public.salida_inventario a
             JOIN public.salida_inventario_detalle sid ON ((a.id = sid.salida_inventario_id)))
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
             LEFT JOIN public.partida_x_recetas c ON ((a.partida_x_recetas_id = c.id)))
          WHERE (a.motivo = 'matizado'::public.motivo_salida_inventario_enum)
          GROUP BY c.partida_id
        ), lavado_fuera AS (
         SELECT c.partida_id,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS c_lavf
           FROM ((((public.salida_inventario a
             JOIN public.salida_inventario_detalle sid ON ((a.id = sid.salida_inventario_id)))
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
             LEFT JOIN public.partida_x_recetas c ON ((a.partida_x_recetas_id = c.id)))
          WHERE (a.motivo = 'lavado'::public.motivo_salida_inventario_enum)
          GROUP BY c.partida_id
        )
 SELECT cp.partida AS partida_id,
    max(cp.receta_id) AS receta_id,
    round(COALESCE(sum(cp.costo_total_dir) FILTER (WHERE ((cp.tipo)::text = 'Produccion'::text)), (0)::numeric), 2) AS c_ten,
    round((COALESCE(sum(cp.costo_total_dir) FILTER (WHERE ((cp.tipo)::text = 'Lavado'::text)), (0)::numeric) + COALESCE(lavf.c_lavf, (0)::numeric)), 2) AS c_lav,
    round(COALESCE(sum(cp.costo_total_dir) FILTER (WHERE ((cp.tipo)::text = ANY (ARRAY[('Repartida'::character varying)::text, ('Desmontado'::character varying)::text, ('Rep. Antiguo'::character varying)::text]))), (0)::numeric), 2) AS c_rep,
    round(COALESCE(ar.c_ajs, (0)::numeric), 2) AS c_ajs,
    round(COALESCE(mz.c_mat, (0)::numeric), 2) AS c_mat,
    round((((COALESCE(sum(cp.costo_total_dir), (0)::numeric) + COALESCE(ar.c_ajs, (0)::numeric)) + COALESCE(mz.c_mat, (0)::numeric)) + COALESCE(lavf.c_lavf, (0)::numeric)), 2) AS c_dir,
    round((((COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision)) * (0.8)::double precision))::numeric, 2) AS c_ind,
    round(((((((COALESCE(sum(cp.costo_total_dir), (0)::numeric) + COALESCE(ar.c_ajs, (0)::numeric)) + COALESCE(mz.c_mat, (0)::numeric)) + COALESCE(lavf.c_lavf, (0)::numeric)))::double precision + ((COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision)) * (0.8)::double precision)))::numeric, 2) AS c_tot,
        CASE
            WHEN ((COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision)) > (0)::double precision) THEN round((((((((COALESCE(sum(cp.costo_total_dir), (0)::numeric) + COALESCE(ar.c_ajs, (0)::numeric)) + COALESCE(mz.c_mat, (0)::numeric)) + COALESCE(lavf.c_lavf, (0)::numeric)))::double precision + ((COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision)) * (0.8)::double precision)) / (COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision))))::numeric, 2)
            ELSE NULL::numeric
        END AS c_kg
   FROM ((((costos_partida cp
     LEFT JOIN ajuste_receta ar ON ((cp.partida = ar.partida_id)))
     LEFT JOIN matizado mz ON ((cp.partida = mz.partida_id)))
     LEFT JOIN lavado_fuera lavf ON ((cp.partida = lavf.partida_id)))
     LEFT JOIN public.partida p ON ((cp.partida = p.id)))
  GROUP BY cp.partida, ar.c_ajs, mz.c_mat, lavf.c_lavf, p.peso_rollos, p.peso_rib
  ORDER BY cp.partida;


ALTER TABLE public.vw_costeo_partida OWNER TO postgres;

--
-- Name: vw_costeo_repartida; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_costeo_repartida AS
 WITH tmp_partida_x_receta_fn AS (
         SELECT a.id AS pk_partida_receta,
            a.partida_id,
            a.receta_id,
            b.tipo_receta,
            c.id AS pk_salida_inventario,
            c.fecha_salida,
            a.fecha
           FROM ((public.partida_x_recetas a
             LEFT JOIN public.tipo_receta b ON ((a.tipo_receta_id = b.id)))
             JOIN public.salida_inventario c ON (((a.id = c.partida_x_recetas_id) AND (c.estado = 'aprobado'::public.estado_salida_inventario_enum) AND (c.motivo = 'receta'::public.motivo_salida_inventario_enum))))
          WHERE ((b.tipo_receta COLLATE "C") = ANY (ARRAY['Desmontado + Reteñido'::text, 'Rebaje'::text, 'Repartida Matizado'::text, 'Reteñido'::text, 'Teñido a Negro'::text]))
        ), insumos_salida AS (
         SELECT sid.salida_inventario_id AS fk_salida_inventario,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS costo_total_dir
           FROM ((public.salida_inventario_detalle sid
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
          GROUP BY sid.salida_inventario_id
        ), costos_repro AS (
         SELECT a.partida,
            a.tipo,
            a.subtipo,
            a.fecha_inicio AS fecha_partida,
            b.receta_id,
            c.costo_total_dir
           FROM ((public.vw_produccion_tenido_procesada a
             LEFT JOIN tmp_partida_x_receta_fn b ON (((a.partida = b.partida_id) AND ((a.subtipo)::text = b.tipo_receta) AND ((b.fecha >= (a.fecha_inicio - '5 days'::interval)) AND (b.fecha <= a.fecha_inicio)))))
             LEFT JOIN insumos_salida c ON ((b.pk_salida_inventario = c.fk_salida_inventario)))
          WHERE (((a.tipo)::text = ANY (ARRAY[('Desmontado'::character varying)::text, ('Rep. Antiguo'::character varying)::text, ('Repartida'::character varying)::text, ('Teñido a Negro'::character varying)::text])) AND (a.fecha_inicio >= '2025-10-01'::date))
        ), ajuste_receta AS (
         SELECT c.partida_id,
            tr.tipo_receta,
            sum(((sidxs.cantidad * vwc.costo_bruto_kg) * 1.18)) AS c_ajs
           FROM ((((((public.salida_inventario a
             JOIN public.salida_inventario_detalle sid ON ((a.id = sid.salida_inventario_id)))
             JOIN public.salida_inventario_detalle_x_stock sidxs ON ((sid.id = sidxs.salida_inventario_detalle_id)))
             JOIN public.inventario vwc ON ((sidxs.inventario_id = vwc.id)))
             JOIN public.partida_x_recetas c ON ((a.partida_x_recetas_id = c.id)))
             JOIN public.tipo_receta tr ON ((c.tipo_receta_id = tr.id)))
             JOIN public.vw_produccion_tenido_procesada pr ON (((pr.partida = c.partida_id) AND ((pr.subtipo)::text = tr.tipo_receta) AND ((pr.tipo)::text = ANY (ARRAY[('Desmontado'::character varying)::text, ('Rep. Antiguo'::character varying)::text, ('Repartida'::character varying)::text, ('Teñido a Negro'::character varying)::text])) AND ((pr.fecha_inicio >= (c.fecha - '5 days'::interval)) AND (pr.fecha_inicio <= (c.fecha + '5 days'::interval))))))
          WHERE ((a.motivo = 'ajuste receta'::public.motivo_salida_inventario_enum) AND ((tr.tipo_receta COLLATE "C") = ANY (ARRAY['Desmontado + Reteñido'::text, 'Rebaje'::text, 'Repartida Matizado'::text, 'Reteñido'::text, 'Teñido a Negro'::text])))
          GROUP BY c.partida_id, tr.tipo_receta
        )
 SELECT cr.partida AS partida_id,
    cr.tipo AS tipo_repartida,
    cr.subtipo AS subtipo_repartida,
    cr.fecha_partida,
    max(cr.receta_id) AS receta_id,
    round(COALESCE(sum(cr.costo_total_dir), (0)::numeric), 2) AS c_rep_dir,
    round(COALESCE(ar.c_ajs, (0)::numeric), 2) AS c_ajs,
    round((COALESCE(sum(cr.costo_total_dir), (0)::numeric) + COALESCE(ar.c_ajs, (0)::numeric)), 2) AS c_total_repro,
        CASE
            WHEN ((COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision)) > (0)::double precision) THEN round(((((COALESCE(sum(cr.costo_total_dir), (0)::numeric) + COALESCE(ar.c_ajs, (0)::numeric)))::double precision / (COALESCE(p.peso_rollos, (0)::double precision) + COALESCE(p.peso_rib, (0)::double precision))))::numeric, 2)
            ELSE NULL::numeric
        END AS c_kg_repro
   FROM ((costos_repro cr
     LEFT JOIN ajuste_receta ar ON ((cr.partida = ar.partida_id)))
     LEFT JOIN public.partida p ON ((cr.partida = p.id)))
  GROUP BY cr.partida, cr.tipo, cr.subtipo, cr.fecha_partida, ar.c_ajs, p.peso_rollos, p.peso_rib
  ORDER BY cr.fecha_partida, cr.partida;


ALTER TABLE public.vw_costeo_repartida OWNER TO postgres;

--
-- Name: vw_cuadre_inventario; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_cuadre_inventario AS
 SELECT ci.id AS cuadre_inventario_id,
    ci.fecha_cuadre,
    ci.fecha_cierre,
    ci.usr_cre,
    ci.fyh_cre,
    ci.usr_mod,
    ci.fyh_mod,
    ci.estado,
    ((p.first_name || ' '::text) || p.last_name) AS usuario,
    ( SELECT ci2.id
           FROM public.cuadre_inventario ci2
          WHERE ((ci2.estado = 'ejecutado'::public.cuadre_estado_enum) AND (ci2.fecha_cuadre < ci.fecha_cuadre))
          ORDER BY ci2.fecha_cuadre DESC
         LIMIT 1) AS ult_cuadre_ejecutado_id,
    ( SELECT ci2.fecha_cuadre
           FROM public.cuadre_inventario ci2
          WHERE ((ci2.estado = 'ejecutado'::public.cuadre_estado_enum) AND (ci2.fecha_cuadre < ci.fecha_cuadre))
          ORDER BY ci2.fecha_cuadre DESC
         LIMIT 1) AS ult_cuadre_ejecutado_fecha
   FROM (public.cuadre_inventario ci
     LEFT JOIN public.profiles p ON ((p.id_usuario = ci.usr_cre)));


ALTER TABLE public.vw_cuadre_inventario OWNER TO postgres;

--
-- Name: vw_desarrollos_lab; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_desarrollos_lab AS
 WITH hist_estado AS (
         SELECT historial_estado_color.id_historial,
            historial_estado_color.desarrollo_color_id AS fk_desarrollo_color,
            historial_estado_color.estado_desarrollo_color_id AS fk_estado_desarrollo_color,
            historial_estado_color.fecha_estado,
            historial_estado_color.observaciones,
            historial_estado_color.usr_cre,
            historial_estado_color.fyh_cre,
            row_number() OVER (PARTITION BY historial_estado_color.desarrollo_color_id ORDER BY historial_estado_color.fecha_estado DESC) AS orden
           FROM public.historial_estado_color
        )
 SELECT dc.id AS desarrollo_color_id,
    cli.cliente,
    col.color,
    ta.tipo_articulo,
    te.tenido,
    edc.estado_desarrollo_color AS estado,
    dc.fecha_ingreso,
    dc.fecha_estado_actual,
    COALESCE(dc.descripcion, he.observaciones) AS descripcion,
        CASE
            WHEN (edc.estado_desarrollo_color = 'Aprobado'::text) THEN (dc.fecha_estado_actual - dc.fecha_ingreso)
            ELSE (CURRENT_DATE - dc.fecha_ingreso)
        END AS dias_transcurridos,
    hef.intentos AS reintentos,
        CASE
            WHEN (hef.rechazos > 0) THEN 1
            ELSE 0
        END AS flg_rechazado
   FROM ((((((((public.desarrollo_color dc
     LEFT JOIN public.color_x_cliente cxc ON ((dc.color_x_cliente_id = cxc.id)))
     LEFT JOIN public.cliente cli ON ((cxc.cliente_id = cli.id)))
     LEFT JOIN public.color col ON ((cxc.color_id = col.id)))
     LEFT JOIN public.tipo_articulo ta ON ((dc.tipo_articulo_id = ta.id)))
     LEFT JOIN public.tenido te ON ((dc.tenido_id = te.id)))
     LEFT JOIN public.estado_desarrollo_color edc ON ((dc.estado_desarrollo_color_id = edc.id)))
     LEFT JOIN hist_estado he ON (((dc.id = he.fk_desarrollo_color) AND (he.orden = 1))))
     LEFT JOIN ( SELECT hist_estado.fk_desarrollo_color,
            sum(
                CASE
                    WHEN (hist_estado.fk_estado_desarrollo_color = 3) THEN 1
                    ELSE 0
                END) AS intentos,
            sum(
                CASE
                    WHEN (hist_estado.fk_estado_desarrollo_color = 5) THEN 1
                    ELSE 0
                END) AS rechazos
           FROM hist_estado
          GROUP BY hist_estado.fk_desarrollo_color) hef ON ((dc.id = hef.fk_desarrollo_color)));


ALTER TABLE public.vw_desarrollos_lab OWNER TO postgres;

--
-- Name: vw_despacho; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_despacho AS
 SELECT a.id,
    a.partida_id,
        CASE (EXTRACT(month FROM a.fecha_despacho))::integer
            WHEN 1 THEN 'Enero'::text
            WHEN 2 THEN 'Febrero'::text
            WHEN 3 THEN 'Marzo'::text
            WHEN 4 THEN 'Abril'::text
            WHEN 5 THEN 'Mayo'::text
            WHEN 6 THEN 'Junio'::text
            WHEN 7 THEN 'Julio'::text
            WHEN 8 THEN 'Agosto'::text
            WHEN 9 THEN 'Septiembre'::text
            WHEN 10 THEN 'Octubre'::text
            WHEN 11 THEN 'Noviembre'::text
            WHEN 12 THEN 'Diciembre'::text
            ELSE NULL::text
        END AS mes,
    a.fecha_despacho,
    c.cliente,
    d.color,
    e.grupo_articulo,
    a.rollos,
    a.rib,
    a.rollos_total,
    a.nfactura,
    a.precio_unit,
    a.fyh_cre
   FROM ((((public.despacho a
     LEFT JOIN public.partida b ON ((a.partida_id = b.id)))
     LEFT JOIN public.cliente c ON ((b.cliente_id = c.id)))
     LEFT JOIN public.colores d ON ((b.color_x_cliente_id = d.id)))
     LEFT JOIN public.articulo e ON ((b.articulo_id = e.id)));


ALTER TABLE public.vw_despacho OWNER TO postgres;

--
-- Name: vw_despacho_resumen; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_despacho_resumen OWNER TO postgres;

--
-- Name: vw_entrada_inventario_resumen; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_entrada_inventario_resumen AS
 SELECT ei.id AS entrada_inventario_id,
    ei.motivo,
    ei.estado,
    ei.fyh_solicitud,
    ei.fyh_revision,
    ei.usr_solicita,
    ei.usr_revisa,
    concat(u_solicita.first_name, ' ', u_solicita.last_name) AS nombre_solicita,
    concat(u_revisa.first_name, ' ', u_revisa.last_name) AS nombre_revisa,
    ei.observacion,
    count(eid.id) AS num_items,
    sum(eid.cantidad_solicitada) AS total_solicitada,
    sum(eid.cantidad_recibida) AS total_recibida
   FROM (((public.entrada_inventario ei
     LEFT JOIN public.entrada_inventario_detalle eid ON ((eid.entrada_inventario_id = ei.id)))
     LEFT JOIN public.profiles u_solicita ON ((u_solicita.id_usuario = ei.usr_solicita)))
     LEFT JOIN public.profiles u_revisa ON ((u_revisa.id_usuario = ei.usr_revisa)))
  GROUP BY ei.id, ei.motivo, ei.estado, ei.fyh_solicitud, ei.fyh_revision, ei.usr_solicita, ei.usr_revisa, (concat(u_solicita.first_name, ' ', u_solicita.last_name)), (concat(u_revisa.first_name, ' ', u_revisa.last_name)), ei.observacion;


ALTER TABLE public.vw_entrada_inventario_resumen OWNER TO postgres;

--
-- Name: vw_error_inv_1; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_error_inv_1 OWNER TO postgres;

--
-- Name: vw_error_inv_2; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_error_inv_2 AS
 WITH tmp AS (
         SELECT partida_x_recetas.id,
            partida_x_recetas.fecha,
            partida_x_recetas.partida_id AS fk_partida,
            partida_x_recetas.receta_id AS fk_receta,
            partida_x_recetas.tipo_receta_id AS fk_tipo_receta,
            partida_x_recetas.maquina_id AS fk_maquina,
            partida_x_recetas.fyh_cre,
            partida_x_recetas.flg_elm,
            partida_x_recetas.fyh_elm,
            partida_x_recetas.fyh_cre_tz
           FROM public.partida_x_recetas
          WHERE ((partida_x_recetas.fecha >= '2025-08-01'::date) AND (partida_x_recetas.flg_elm = false))
        )
 SELECT a.id,
    a.fecha,
    a.fk_partida AS partida_id,
    a.fk_receta AS receta_id,
    a.fk_tipo_receta AS tipo_receta_id,
    a.fk_maquina AS maquina_id,
    a.fyh_cre,
    a.flg_elm,
    a.fyh_elm,
    a.fyh_cre_tz,
    c.fecha_ten,
    c.tipo
   FROM ((tmp a
     LEFT JOIN public.salida_inventario b ON ((a.id = b.partida_x_recetas_id)))
     LEFT JOIN ( SELECT a_1.partida_id AS fk_partida,
            a_1.tipo,
            b_1.id AS pk_tipo_receta,
            max(a_1.fecha) AS fecha_ten
           FROM (public.produccion_tenido a_1
             LEFT JOIN public.tipo_receta b_1 ON (((a_1.tipo)::text = b_1.tipo_receta)))
          WHERE (a_1.fecha >= '2025-08-01'::date)
          GROUP BY a_1.partida_id, a_1.tipo, b_1.id) c ON (((a.fk_partida = c.fk_partida) AND (a.fk_tipo_receta = c.pk_tipo_receta))))
  WHERE ((b.partida_x_recetas_id IS NULL) AND (c.fecha_ten IS NOT NULL));


ALTER TABLE public.vw_error_inv_2 OWNER TO postgres;

--
-- Name: vw_observado_lab; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_observado_lab AS
 WITH ultimos_estados AS (
         SELECT observado_estados.partida_id AS fk_partida,
            observado_estados.estado,
            observado_estados.fecha,
            row_number() OVER (PARTITION BY observado_estados.partida_id ORDER BY observado_estados.fecha DESC, observado_estados.id DESC) AS rn
           FROM public.observado_estados
        ), tmp_observado AS (
         SELECT a_1.partida_id AS partida,
            a_1.fecha,
            d.color,
            f.cliente,
            g.articulo,
            a_1.rollos,
            mot.motivo,
            a_1.detalle,
            row_number() OVER (PARTITION BY a_1.partida_id ORDER BY a_1.fecha DESC, a_1.id DESC) AS rn
           FROM ((((((public.observado a_1
             LEFT JOIN public.partida b ON ((a_1.partida_id = b.id)))
             LEFT JOIN public.color_x_cliente c ON ((b.color_x_cliente_id = c.id)))
             LEFT JOIN public.color d ON ((c.color_id = d.id)))
             LEFT JOIN public.cliente f ON ((b.cliente_id = f.id)))
             LEFT JOIN public.observado_motivos mot ON ((a_1.motivo_observado_id = mot.id)))
             LEFT JOIN public.articulo g ON ((b.articulo_id = g.id)))
          WHERE (a_1.flg_elm = 0)
        )
 SELECT a.partida,
    a.fecha,
    a.color,
    a.cliente,
    a.articulo,
    a.rollos,
    a.motivo,
    a.detalle,
    COALESCE(ue.estado, 'Pendiente'::character varying) AS estado,
    COALESCE(ue.fecha, a.fecha) AS fecha_estado
   FROM (tmp_observado a
     LEFT JOIN ultimos_estados ue ON (((a.partida = ue.fk_partida) AND (ue.rn = 1))))
  WHERE (a.rn = 1)
  ORDER BY ue.estado, a.fecha;


ALTER TABLE public.vw_observado_lab OWNER TO postgres;

--
-- Name: vw_partidas_resumen; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_partidas_resumen AS
 WITH extras AS (
         SELECT pxe.partida_id AS fk_partida,
            string_agg((ex_1.cod_extra)::text, '+'::text) AS extras,
            COALESCE(sum(pxe.peso), (0)::numeric) AS peso_extra
           FROM (public.partida_x_extra pxe
             JOIN public.extra ex_1 ON ((pxe.extra_id = ex_1.id)))
          GROUP BY pxe.partida_id
        ), prod_tenido AS (
         SELECT produccion_tenido.partida_id AS fk_partida,
            produccion_tenido.fecha,
            (produccion_tenido.estado)::text AS estado,
            row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha DESC) AS orden
           FROM public.produccion_tenido
        ), primera_partida AS (
         SELECT partida.id AS pk_partida,
            row_number() OVER (PARTITION BY partida.color_x_cliente_id, partida.cliente_id ORDER BY partida.id) AS orden
           FROM public.partida
        ), tmp_auditoria AS (
         SELECT auditoria.id,
            auditoria.partida_id AS fk_partida,
            auditoria.fecha_auditoria,
            auditoria.estado,
            row_number() OVER (PARTITION BY auditoria.partida_id ORDER BY auditoria.fecha_auditoria DESC) AS orden
           FROM public.auditoria
        ), programa AS (
         SELECT programacion.partida AS fk_partida,
            max(programacion.fecha_programacion) AS fecha
           FROM public.programacion
          GROUP BY programacion.partida
         HAVING (max(programacion.fecha_programacion) = CURRENT_DATE)
        UNION ALL
         SELECT programa_tenido.partida_id AS fk_partida,
            max(programa_tenido.fecha) AS fecha
           FROM public.programa_tenido
          GROUP BY programa_tenido.partida_id
         HAVING (max(programa_tenido.fecha) = CURRENT_DATE)
        )
 SELECT part.id AS partida,
    part.fecha_registro,
    part.guia,
    part.fecha_entrega,
    pri.prioridad,
    cli.cliente,
    art.articulo,
    ta.tipo_articulo,
    col.color,
    col.tono,
    part.rollos,
    part.rib,
    ten.tenido,
    part.fibra,
    prev.previo,
    part.malla,
    ad.adicional,
    part.ancho,
    part.rendimiento,
    ex.extras,
    ((part.peso_rollos + part.peso_rib) + (COALESCE(ex.peso_extra, (0)::numeric))::double precision) AS peso,
    COALESCE(part.receta_id, (partrecet.receta_id)::integer) AS receta_id,
        CASE
            WHEN ((obs.fecha IS NOT NULL) AND (desp.fecha_despacho >= obs.fecha)) THEN 'Despachado'::text
            WHEN ((obs.fecha > prod_ten.fecha) AND (obs.fecha IS NOT NULL)) THEN 'Observado'::text
            WHEN ((prod_ten.fecha >= obs.fecha) AND (obs.fecha IS NOT NULL) AND (prod_ten.estado = 'Teñido'::text)) THEN 'ReTeñido'::text
            WHEN (desp.fecha_despacho IS NOT NULL) THEN 'Despachado'::text
            WHEN ((obs.fecha IS NOT NULL) AND (audit.fecha_auditoria > obs.fecha)) THEN 'Para Despachar'::text
            WHEN (audit.fecha_auditoria IS NOT NULL) THEN 'Para Despachar'::text
            WHEN ((compact.fecha >= prod_ten.fecha) AND (compact.fecha IS NOT NULL)) THEN 'Compactado'::text
            WHEN (prod_ten.fk_partida IS NOT NULL) THEN prod_ten.estado
            WHEN (progra.fk_partida IS NOT NULL) THEN 'Programado'::text
            WHEN (recet.id IS NULL) THEN 'Pendiente Receta'::text
            WHEN ((termo.fk_partida IS NULL) AND (part.articulo_id = ANY (ARRAY[6, 22, 32, 33]))) THEN 'Pendiente Termofijar'::text
            WHEN ((termo.fk_partida IS NOT NULL) AND (part.articulo_id = ANY (ARRAY[6, 22, 32, 33]))) THEN 'Para Programar'::text
            ELSE 'Para Programar'::text
        END AS estado,
        CASE
            WHEN ((obs.fecha IS NOT NULL) AND (desp.fecha_despacho >= obs.fecha)) THEN desp.fecha_despacho
            WHEN ((obs.fecha > prod_ten.fecha) AND (obs.fecha IS NOT NULL)) THEN obs.fecha
            WHEN ((prod_ten.fecha >= obs.fecha) AND (obs.fecha IS NOT NULL) AND (prod_ten.estado = 'Teñido'::text)) THEN prod_ten.fecha
            WHEN (desp.fecha_despacho IS NOT NULL) THEN desp.fecha_despacho
            WHEN ((obs.fecha IS NOT NULL) AND (audit.fecha_auditoria > obs.fecha)) THEN audit.fecha_auditoria
            WHEN (audit.fecha_auditoria IS NOT NULL) THEN audit.fecha_auditoria
            WHEN ((compact.fecha >= prod_ten.fecha) AND (compact.fecha IS NOT NULL)) THEN compact.fecha
            WHEN (prod_ten.fk_partida IS NOT NULL) THEN prod_ten.fecha
            WHEN (termo.fk_partida IS NOT NULL) THEN termo.fecha
            WHEN (progra.fk_partida IS NOT NULL) THEN progra.fecha
            ELSE NULL::date
        END AS fecha_estado,
    obs.estado AS estado_obs,
    obs.rollos AS rollos_obs,
    obs.motivo AS motivo_obs,
        CASE
            WHEN ((part.fecha_entrega - CURRENT_DATE) < 0) THEN 'Entrega Vencida'::text
            WHEN ((part.fecha_entrega - CURRENT_DATE) = 0) THEN 'Entrega Hoy'::text
            WHEN (((part.fecha_entrega - CURRENT_DATE) >= 1) AND ((part.fecha_entrega - CURRENT_DATE) <= 3)) THEN 'Entrega Por Vencer'::text
            WHEN ((part.fecha_entrega - CURRENT_DATE) > 3) THEN 'Entrega En Tiempo'::text
            ELSE NULL::text
        END AS estado_entrega,
        CASE
            WHEN (abs((part.fecha_entrega - CURRENT_DATE)) = 0) THEN '0 días'::text
            WHEN ((abs((part.fecha_entrega - CURRENT_DATE)) >= 1) AND (abs((part.fecha_entrega - CURRENT_DATE)) <= 3)) THEN '1 a 3'::text
            WHEN ((abs((part.fecha_entrega - CURRENT_DATE)) >= 4) AND (abs((part.fecha_entrega - CURRENT_DATE)) <= 7)) THEN '3 a 7'::text
            WHEN (abs((part.fecha_entrega - CURRENT_DATE)) > 7) THEN 'más de 7'::text
            ELSE 'Sin rango'::text
        END AS rango_vencimiento_dias,
        CASE
            WHEN (part.fecha_entrega IS NULL) THEN NULL::integer
            ELSE (part.fecha_entrega - CURRENT_DATE)
        END AS vencimiento_dias,
        CASE
            WHEN (pripart.pk_partida IS NOT NULL) THEN 'PRIMERA PARTIDA'::text
            ELSE NULL::text
        END AS flg_prim_part,
    te_std.duracion
   FROM (((((((((((((((((((((public.partida part
     LEFT JOIN public.prioridad pri ON ((pri.id = part.prioridad_id)))
     LEFT JOIN public.cliente cli ON ((cli.id = part.cliente_id)))
     LEFT JOIN public.articulo art ON ((art.id = part.articulo_id)))
     LEFT JOIN public.colores col ON ((col.id = part.color_x_cliente_id)))
     LEFT JOIN public.tenido ten ON ((ten.id = part.tenido_id)))
     LEFT JOIN public.adicional ad ON ((ad.id = part.adicional_id)))
     LEFT JOIN extras ex ON ((ex.fk_partida = part.id)))
     LEFT JOIN public.previo prev ON ((part.previo_id = prev.id)))
     LEFT JOIN public.tipo_articulo ta ON ((art.tipo_articulo_id = ta.id)))
     LEFT JOIN ( SELECT despacho.partida_id AS fk_partida,
            max(despacho.fecha_despacho) AS fecha_despacho,
            sum(despacho.rollos) AS rollos
           FROM public.despacho
          GROUP BY despacho.partida_id) desp ON ((part.id = desp.fk_partida)))
     LEFT JOIN prod_tenido prod_ten ON (((part.id = prod_ten.fk_partida) AND (prod_ten.orden = 1))))
     LEFT JOIN ( SELECT programa.fk_partida,
            max(programa.fecha) AS fecha
           FROM programa
          GROUP BY programa.fk_partida
         HAVING (max(programa.fecha) = CURRENT_DATE)) progra ON ((part.id = progra.fk_partida)))
     LEFT JOIN public.vw_observado_lab obs ON ((part.id = obs.partida)))
     LEFT JOIN ( SELECT compactado.partida_id AS fk_partida,
            max(compactado.fecha) AS fecha
           FROM public.compactado
          GROUP BY compactado.partida_id
         HAVING (sum(compactado.rollos) > 0)) compact ON ((part.id = compact.fk_partida)))
     LEFT JOIN ( SELECT termofijado.partida_id AS fk_partida,
            max(termofijado.fecha) AS fecha
           FROM public.termofijado
          GROUP BY termofijado.partida_id) termo ON ((part.id = termo.fk_partida)))
     LEFT JOIN public.receta2 recet ON (((part.color_x_cliente_id = recet.color_x_cliente_id) AND (art.tipo_articulo_id = recet.tipo_articulo_id) AND (part.fibra = recet.fibra) AND (part.tenido_id = recet.tenido_id) AND (recet.flg_antipilling =
        CASE
            WHEN (part.adicional_id = 1) THEN true
            ELSE false
        END) AND (recet.flg_activo = true) AND (recet.tipo_receta_id = 7))))
     LEFT JOIN primera_partida pripart ON (((part.id = pripart.pk_partida) AND (pripart.orden = 1))))
     LEFT JOIN public.partida_x_recetas partrecet ON (((part.id = partrecet.partida_id) AND (partrecet.tipo_receta_id = 7) AND (partrecet.flg_elm = false))))
     LEFT JOIN tmp_auditoria audit ON (((part.id = audit.fk_partida) AND (audit.orden = 1) AND (audit.estado = 'OK'::text))))
     LEFT JOIN public.color_x_cliente val ON ((col.id = val.id)))
     LEFT JOIN public.tiempos_estandar_tenido te_std ON (((te_std.valor_id = val.valor_id) AND (te_std.tenido_id = part.tenido_id) AND (COALESCE((te_std.adicional_id)::integer, 0) = COALESCE((part.adicional_id)::integer, 0)) AND (te_std.tipo_receta_id = 7))))
  WHERE (part.id > 0)
  ORDER BY part.id;


ALTER TABLE public.vw_partidas_resumen OWNER TO postgres;

--
-- Name: vw_receta; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_receta AS
 WITH costos AS (
         SELECT a.receta_id AS fk_receta,
            sum(
                CASE
                    WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((7)::numeric * a.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                    WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                    ELSE NULL::numeric
                END) AS costo_12r,
            sum(
                CASE
                    WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((5)::numeric * a.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                    WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                    ELSE NULL::numeric
                END) AS costo
           FROM (public.receta_x_insumo a
             JOIN public.insumo b ON ((a.insumo_id = b.id)))
          GROUP BY a.receta_id
        )
 SELECT receta2.id AS receta_id,
    color.color,
    tipo_articulo.tipo_articulo,
    cliente.cliente,
    tenido.tenido,
    receta2.fibra,
    c.costo_12r,
    c.costo,
    receta2.flg_antipilling,
    tr.tipo_receta
   FROM (((((((public.receta2
     JOIN public.color_x_cliente ON ((receta2.color_x_cliente_id = color_x_cliente.id)))
     JOIN public.color ON ((color.id = color_x_cliente.color_id)))
     JOIN public.cliente ON ((color_x_cliente.cliente_id = cliente.id)))
     JOIN public.tipo_articulo ON ((tipo_articulo.id = receta2.tipo_articulo_id)))
     JOIN public.tenido ON ((tenido.id = receta2.tenido_id)))
     JOIN costos c ON ((c.fk_receta = receta2.id)))
     LEFT JOIN public.tipo_receta tr ON ((tr.id = receta2.tipo_receta_id)))
  WHERE (receta2.flg_activo = true);


ALTER TABLE public.vw_receta OWNER TO postgres;

--
-- Name: vw_error_inv_3; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_error_inv_3 AS
 WITH tmp AS (
         SELECT partida_x_recetas.id,
            partida_x_recetas.fecha,
            partida_x_recetas.partida_id AS fk_partida,
            partida_x_recetas.receta_id AS fk_receta,
            partida_x_recetas.tipo_receta_id AS fk_tipo_receta,
            partida_x_recetas.maquina_id AS fk_maquina,
            partida_x_recetas.fyh_cre,
            partida_x_recetas.flg_elm,
            partida_x_recetas.fyh_elm,
            partida_x_recetas.fyh_cre_tz
           FROM public.partida_x_recetas
          WHERE ((partida_x_recetas.fecha >= '2025-08-01'::date) AND (partida_x_recetas.flg_elm = false))
        ), casos_sin_partida_x_receta AS (
         SELECT c_1.fk_partida AS partida_ten,
            c_1.fecha_ten,
            c_1.maquina,
            c_1.tipo,
            c_1.pk_tipo_receta
           FROM (tmp a_1
             FULL JOIN ( SELECT a_2.partida_id AS fk_partida,
                    a_2.tipo,
                    b_1.id AS pk_tipo_receta,
                    a_2.maquina,
                    max(a_2.fecha) AS fecha_ten
                   FROM (public.produccion_tenido a_2
                     LEFT JOIN public.tipo_receta b_1 ON (((a_2.tipo)::text = b_1.tipo_receta)))
                  WHERE (a_2.fecha >= '2025-08-01'::date)
                  GROUP BY a_2.partida_id, a_2.tipo, a_2.maquina, b_1.id) c_1 ON (((a_1.fk_partida = c_1.fk_partida) AND (a_1.fk_tipo_receta = c_1.pk_tipo_receta))))
          WHERE ((c_1.fk_partida IS NOT NULL) AND (a_1.fk_partida IS NULL))
          ORDER BY c_1.tipo, c_1.fk_partida
        )
 SELECT a.partida_ten,
    a.fecha_ten,
    a.maquina,
    a.tipo,
    a.pk_tipo_receta,
    b.tono,
    b.color,
    b.tipo_articulo,
    b.fibra,
    b.adicional,
    c.pk_receta AS receta_id,
    c.tipo_receta,
    c.fk_tipo_receta AS tipo_receta_id
   FROM ((casos_sin_partida_x_receta a
     LEFT JOIN public.vw_partidas_resumen b ON ((a.partida_ten = b.partida)))
     LEFT JOIN ( SELECT a_1.receta_id AS pk_receta,
            a_1.color,
            a_1.tipo_articulo,
            a_1.cliente,
            a_1.tenido,
            a_1.fibra,
            a_1.costo_12r,
            a_1.costo,
            a_1.flg_antipilling,
            a_1.tipo_receta,
            b_1.tipo_receta_id AS fk_tipo_receta
           FROM (public.vw_receta a_1
             LEFT JOIN public.receta2 b_1 ON ((a_1.receta_id = b_1.id)))) c ON ((((b.color)::text = (c.color)::text) AND (c.cliente = b.tono) AND (c.tipo_articulo = b.tipo_articulo) AND (a.pk_tipo_receta = c.fk_tipo_receta) AND (
        CASE
            WHEN (((a.tipo)::text ~~ '%Teñido%'::text) AND (b.adicional = 'antipilling'::text)) THEN true
            ELSE false
        END =
        CASE
            WHEN (c.tipo_receta = 'Teñido'::text) THEN c.flg_antipilling
            ELSE false
        END) AND (b.tenido = c.tenido) AND (b.fibra = c.fibra))))
  ORDER BY a.partida_ten;


ALTER TABLE public.vw_error_inv_3 OWNER TO postgres;

--
-- Name: vw_estado_entrada_inventario; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_estado_entrada_inventario AS
 SELECT unnest(enum_range(NULL::public.estado_entrada_inventario_enum)) AS valor;


ALTER TABLE public.vw_estado_entrada_inventario OWNER TO postgres;

--
-- Name: vw_estado_ingreso_compra; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_estado_ingreso_compra AS
 SELECT unnest(enum_range(NULL::public.estado_ingreso_compra_enum)) AS valor;


ALTER TABLE public.vw_estado_ingreso_compra OWNER TO postgres;

--
-- Name: vw_estado_letra; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_estado_letra AS
 SELECT unnest(enum_range(NULL::public.estado_letra_enum)) AS valor;


ALTER TABLE public.vw_estado_letra OWNER TO postgres;

--
-- Name: vw_estado_pago; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_estado_pago AS
 SELECT unnest(enum_range(NULL::public.estado_pago_enum)) AS valor;


ALTER TABLE public.vw_estado_pago OWNER TO postgres;

--
-- Name: vw_estado_salida_inventario; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_estado_salida_inventario AS
 SELECT unnest(enum_range(NULL::public.estado_salida_inventario_enum)) AS valor;


ALTER TABLE public.vw_estado_salida_inventario OWNER TO postgres;

--
-- Name: vw_finanzas; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_finanzas AS
 WITH prod_tenido AS (
         SELECT produccion_tenido.partida_id AS fk_partida,
            produccion_tenido.tipo,
            produccion_tenido.fecha,
            row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha) AS orden
           FROM public.produccion_tenido
          WHERE ((produccion_tenido.estado)::text = 'Teñido'::text)
        ), matizado_costo AS (
         SELECT a_1.partida_id AS fk_partida,
            sum(
                CASE
                    WHEN ((a_1.medida)::text = 'g'::text) THEN ((a_1.cantidad * (b.precio_prom_kg_usd)::double precision) / (1000)::double precision)
                    ELSE (a_1.cantidad * (b.precio_prom_kg_usd)::double precision)
                END) AS costo_usd
           FROM (public.matizado a_1
             JOIN public.insumo b ON ((a_1.insumo_id = b.id)))
          GROUP BY a_1.partida_id
        ), costos AS (
         SELECT a_1.receta_id AS fk_receta,
            c.partida_id AS fk_partida,
                CASE
                    WHEN ((d.rollos + d.rib) <= 12) THEN sum(
                    CASE
                        WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((7)::numeric * a_1.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                        WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a_1.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                        ELSE (0)::numeric
                    END)
                    ELSE sum(
                    CASE
                        WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((5)::numeric * a_1.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                        WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a_1.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                        ELSE (0)::numeric
                    END)
                END AS costo_kg_receta
           FROM (((public.receta_x_insumo a_1
             JOIN public.insumo b ON ((a_1.insumo_id = b.id)))
             JOIN public.partida_x_recetas c ON (((a_1.receta_id = c.receta_id) AND (c.tipo_receta_id = 7))))
             LEFT JOIN public.partida d ON ((c.partida_id = d.id)))
          GROUP BY a_1.receta_id, d.rollos, d.rib, c.partida_id
        )
 SELECT a.id AS partida_id,
    art.tipo_articulo_id,
    a.cliente_id,
    a.color_x_cliente_id,
    a.tenido_id AS "teñido_id",
    a.rollos,
    a.rib,
    a.peso_rollos,
    a.peso_rib,
    cost.fk_receta AS receta_id,
    prodten.tipo AS tipo_tenido,
    prodten.fecha AS fecha_tenido,
    cost.costo_kg_receta AS costo_receta,
    (cost.costo_kg_receta * 0.18) AS igv,
    0.8 AS costo_mo,
        CASE
            WHEN ((art.tipo_articulo_id = ANY (ARRAY[24, 5])) AND (a.cliente_id <> ALL (ARRAY[49, 57]))) THEN 0.1
            WHEN (art.tipo_articulo_id = ANY (ARRAY[22, 23, 16])) THEN 0.1
            ELSE (0)::numeric
        END AS costo_termo_percha,
    ((COALESCE(f.costo_usd, (0)::double precision) / (a.peso_rollos + a.peso_rib)))::numeric(5,4) AS costo_matizado,
    pre.precio_tenido,
        CASE
            WHEN ((a.cliente_id = 11) AND (a.adicional_id = 1)) THEN 0.15
            WHEN (a.adicional_id = 1) THEN 0.1
            ELSE (0)::numeric
        END AS precio_antipilling,
        CASE
            WHEN ((art.tipo_articulo_id = ANY (ARRAY[24, 5])) AND (a.cliente_id <> ALL (ARRAY[49, 57]))) THEN 0.3
            WHEN (art.tipo_articulo_id = ANY (ARRAY[22, 23, 16])) THEN 0.25
            WHEN ((a.cliente_id = ANY (ARRAY[24, 4])) AND (art.tipo_articulo_id = 13)) THEN 0.1
            ELSE (0)::numeric
        END AS precio_termo_percha
   FROM (((((public.partida a
     LEFT JOIN matizado_costo f ON ((a.id = f.fk_partida)))
     JOIN prod_tenido prodten ON (((a.id = prodten.fk_partida) AND (prodten.orden = 1))))
     LEFT JOIN costos cost ON ((a.id = cost.fk_partida)))
     LEFT JOIN public.articulo art ON ((a.articulo_id = art.id)))
     LEFT JOIN public.catalogo_precios pre ON (((pre.activo = 1) AND (a.color_x_cliente_id = pre.color_x_cliente_id) AND (a.tenido_id = pre.tenido_id) AND (a.fibra = pre.fibra) AND (
        CASE
            WHEN (art.tipo_articulo_id = 13) THEN 13
            WHEN ((art.tipo_articulo_id = ANY (ARRAY[4, 8, 9, 10, 11, 12, 14, 15, 17, 18, 20, 30])) AND (a.cliente_id = ANY (ARRAY[1, 11, 22]))) THEN 20
            WHEN (art.tipo_articulo_id = ANY (ARRAY[4, 9, 18])) THEN 18
            WHEN (art.tipo_articulo_id = ANY (ARRAY[8, 12])) THEN 12
            WHEN (art.tipo_articulo_id = ANY (ARRAY[10, 14, 17])) THEN 14
            WHEN (art.tipo_articulo_id = ANY (ARRAY[16, 22, 23])) THEN 16
            ELSE (art.tipo_articulo_id)::integer
        END = pre.tipo_articulo_id))))
  ORDER BY a.id DESC;


ALTER TABLE public.vw_finanzas OWNER TO postgres;

--
-- Name: vw_insumo_medida; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_insumo_medida AS
 SELECT unnest(enum_range(NULL::public.medida_enum)) AS valor;


ALTER TABLE public.vw_insumo_medida OWNER TO postgres;

--
-- Name: vw_insumo_tipo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_insumo_tipo AS
 SELECT unnest(enum_range(NULL::public.tipo_insumo_enum)) AS valor;


ALTER TABLE public.vw_insumo_tipo OWNER TO postgres;

--
-- Name: vw_inventario_duplicado; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_inventario_duplicado OWNER TO postgres;

--
-- Name: vw_partida_x_receta; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_partida_x_receta AS
 SELECT pr.id,
    pr.fecha,
    pr.partida_id,
    pr.receta_id,
    pr.tipo_receta_id,
    tr.tipo_receta,
    pr.maquina_id,
    pr.fyh_cre,
    pr.flg_elm,
    pr.fyh_elm,
    m.nombre,
    p.cliente_id,
    c.cliente,
    cc.color_id,
    cc.color,
    cc.cliente_id AS tono_id,
    cc.tono,
    p.articulo_id,
    a.articulo,
    p.fibra,
    pr.rollos
   FROM ((((((public.partida_x_recetas pr
     LEFT JOIN public.partida p ON ((p.id = pr.partida_id)))
     LEFT JOIN public.cliente c ON ((c.id = p.cliente_id)))
     LEFT JOIN public.vw_colores cc ON ((cc.color_x_cliente_id = p.color_x_cliente_id)))
     LEFT JOIN public.articulo a ON ((a.id = p.articulo_id)))
     LEFT JOIN public.maquina m ON ((m.id = pr.maquina_id)))
     LEFT JOIN public.tipo_receta tr ON ((pr.tipo_receta_id = tr.id)));


ALTER TABLE public.vw_partida_x_receta OWNER TO postgres;

--
-- Name: vw_inventario_movimientos; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_inventario_movimientos OWNER TO postgres;

--
-- Name: vw_inventario_valorizado_actual; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_inventario_valorizado_actual OWNER TO postgres;

--
-- Name: vw_inventario_x_ingreso; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_inventario_x_ingreso OWNER TO postgres;

--
-- Name: vw_inventario_x_insumo; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_inventario_x_insumo OWNER TO postgres;

--
-- Name: vw_receta_lavado_maquina; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_receta_lavado_maquina AS
 WITH costos AS (
         SELECT a_1.receta_lavado_mq_id AS fk_receta_lavado_mq,
            sum((a_1.cantidad * b_1.precio_prom_kg_usd)) AS costo
           FROM (public.receta_lavado_maquina_x_insumo a_1
             JOIN public.insumo b_1 ON ((a_1.insumo_id = b_1.id)))
          GROUP BY a_1.receta_lavado_mq_id
        )
 SELECT a.id AS receta_lavado_mq_id,
    b.tipo_lavado_mq,
    c.valor AS valor_origen,
    d.valor AS valor_destino,
    e.costo
   FROM ((((public.receta_lavado_maquina a
     JOIN public.tipo_lavado_maquina b ON ((a.tipo_lavado_mq_id = b.id)))
     JOIN public.valor c ON ((a.valor_origen_id = c.id)))
     JOIN public.valor d ON ((a.valor_destino_id = d.id)))
     JOIN costos e ON ((a.id = e.fk_receta_lavado_mq)));


ALTER TABLE public.vw_receta_lavado_maquina OWNER TO postgres;

--
-- Name: vw_lavado_maquina; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_lavado_maquina OWNER TO postgres;

--
-- Name: vw_letras; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_letras OWNER TO postgres;

--
-- Name: vw_maquina_acabado; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_maquina_acabado AS
 SELECT maquina.id AS maquina_id,
    maquina.nombre,
    maquina.ubicacion,
    maquina.seccion,
    maquina."RB"
   FROM public.maquina
  WHERE (maquina.id = ANY (ARRAY[17, 18, 12]));


ALTER TABLE public.vw_maquina_acabado OWNER TO postgres;

--
-- Name: vw_maquina_tenido; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_maquina_tenido AS
 SELECT maquina.id AS maquina_id,
    maquina.nombre
   FROM public.maquina
  WHERE ((maquina.ubicacion)::text = 'Maq Teñido'::text);


ALTER TABLE public.vw_maquina_tenido OWNER TO postgres;

--
-- Name: vw_margenes; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_margenes AS
 SELECT a.partida_id AS partida,
    a.receta_id,
    a.tipo_tenido,
    a.rollos,
    a.rib,
    a.peso_rollos,
    a.peso_rib,
        CASE
            WHEN ((b.cliente ~~ '%MLR%'::text) OR (b.cliente ~~ '%Oswaldo%'::text) OR (b.cliente ~~ '%Alejandrina%'::text) OR (b.cliente ~~ '%Delia%'::text) OR (b.cliente ~~ '%Monica%'::text)) THEN 'La Real'::text
            ELSE 'Otros'::text
        END AS tipo_cliente,
        CASE
            WHEN ((b.cliente ~~ '%MLR%'::text) OR (b.cliente ~~ '%Oswaldo%'::text) OR (b.cliente ~~ '%Alejandrina%'::text) OR (b.cliente ~~ '%Delia%'::text) OR (b.cliente ~~ '%Monica%'::text)) THEN 'MLR'::text
            ELSE b.cliente
        END AS cliente,
    c.tipo_articulo,
    d.color,
    e.tenido,
    f.estado,
        CASE (EXTRACT(month FROM a.fecha_tenido))::integer
            WHEN 1 THEN 'Enero'::text
            WHEN 2 THEN 'Febrero'::text
            WHEN 3 THEN 'Marzo'::text
            WHEN 4 THEN 'Abril'::text
            WHEN 5 THEN 'Mayo'::text
            WHEN 6 THEN 'Junio'::text
            WHEN 7 THEN 'Julio'::text
            WHEN 8 THEN 'Agosto'::text
            WHEN 9 THEN 'Septiembre'::text
            WHEN 10 THEN 'Octubre'::text
            WHEN 11 THEN 'Noviembre'::text
            WHEN 12 THEN 'Diciembre'::text
            ELSE NULL::text
        END AS mes,
    a.fecha_tenido,
        CASE
            WHEN ((a.precio_tenido IS NULL) AND (a.costo_receta IS NULL)) THEN 'Pendiente Precio y Costo'::text
            WHEN (a.precio_tenido IS NULL) THEN 'Pendiente Precio'::text
            WHEN (a.costo_receta IS NULL) THEN 'Pendiente Costo'::text
            ELSE 'Con Informacion'::text
        END AS informacion,
        CASE
            WHEN ((a.rollos + a.rib) <= 12) THEN 'Partida de 12'::text
            ELSE 'Otras'::text
        END AS tipo_partida,
    ((((a.costo_receta + a.igv) + a.costo_mo) + a.costo_termo_percha) + a.costo_matizado) AS costo_kg,
    ((a.precio_tenido + a.precio_antipilling) + a.precio_termo_percha) AS precio_kg,
    (((((((a.costo_receta + a.igv) + a.costo_mo) + a.costo_termo_percha) + a.costo_matizado))::double precision * a.peso_rollos) + (((((a.costo_receta + a.igv) + a.costo_mo) + a.costo_matizado))::double precision * a.peso_rib)) AS costo_total,
    (((((a.precio_tenido + a.precio_antipilling) + a.precio_termo_percha))::double precision * a.peso_rollos) + (((a.precio_tenido + a.precio_antipilling))::double precision * a.peso_rib)) AS precio_total
   FROM (((((public.vw_finanzas a
     LEFT JOIN public.cliente b ON ((a.cliente_id = b.id)))
     LEFT JOIN public.tipo_articulo c ON ((a.tipo_articulo_id = c.id)))
     LEFT JOIN public.colores d ON ((a.color_x_cliente_id = d.id)))
     LEFT JOIN public.tenido e ON ((a."teñido_id" = e.id)))
     LEFT JOIN ( SELECT vw_partidas_resumen.partida,
            vw_partidas_resumen.estado
           FROM public.vw_partidas_resumen) f ON ((a.partida_id = f.partida)));


ALTER TABLE public.vw_margenes OWNER TO postgres;

--
-- Name: vw_matizado; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_matizado AS
 SELECT a.id,
    a.partida_id,
    e.cliente,
    f.articulo,
    i.tenido,
    h.color,
    a.fecha,
    c.nombre AS turno,
    b.insumo,
    b.tipo,
    a.cantidad,
    a.medida,
        CASE
            WHEN ((a.medida)::text = 'g'::text) THEN ((a.cantidad * (b.precio_prom_kg_usd)::double precision) / (1000)::double precision)
            ELSE (a.cantidad * (b.precio_prom_kg_usd)::double precision)
        END AS costo_usd
   FROM ((((((((public.matizado a
     JOIN public.insumo b ON ((a.insumo_id = b.id)))
     LEFT JOIN public.turno c ON ((a.turno_id = c.id)))
     LEFT JOIN public.partida d ON ((a.partida_id = d.id)))
     LEFT JOIN public.cliente e ON ((d.cliente_id = e.id)))
     LEFT JOIN public.articulo f ON ((d.articulo_id = f.id)))
     LEFT JOIN public.color_x_cliente g ON ((d.color_x_cliente_id = g.id)))
     LEFT JOIN public.color h ON ((g.color_id = h.id)))
     LEFT JOIN public.tenido i ON ((d.tenido_id = i.id)));


ALTER TABLE public.vw_matizado OWNER TO postgres;

--
-- Name: vw_matizado_agrupado; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_matizado_agrupado AS
 WITH primera_partida AS (
         SELECT partida.id AS pk_partida,
            row_number() OVER (PARTITION BY partida.color_x_cliente_id, partida.cliente_id ORDER BY partida.id) AS orden
           FROM public.partida
        )
 SELECT a.fecha,
    c.nombre AS turno,
    a.partida_id,
        CASE
            WHEN (e.cliente ~~ '%J.Ripaz%'::text) THEN 'J.Ripaz'::text
            WHEN (e.cliente ~~ '%Rudy%'::text) THEN 'Rudy'::text
            WHEN (e.cliente ~~ '%J.Urrutia%'::text) THEN 'J.Urrutia'::text
            WHEN (e.cliente ~~ '%Jimmy%'::text) THEN 'Jimmy'::text
            WHEN (e.cliente ~~ '%Oswaldo%'::text) THEN 'Oswaldo'::text
            ELSE e.cliente
        END AS cliente,
        CASE
            WHEN (primpart.pk_partida IS NOT NULL) THEN 'PRIMERA PARTIDA'::text
            ELSE NULL::text
        END AS prim_part,
        CASE
            WHEN (ta.tipo_articulo = ANY (ARRAY['F Lycra 30/1 Card'::text, 'F Lycra 30/1 Pei'::text])) THEN 'Full Lycra'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['Gam 50/1'::text, 'Gam 50/1 Pei'::text, 'Gamuza Winter'::text])) THEN 'Gam 50/1'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['J 30/1 Card'::text, 'J 30/1 Pei'::text, 'J 28/1'::text])) THEN 'J 30/1'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['J 20/1 Card'::text, 'J 20/1 Pei'::text, 'J 18/1 Pei'::text])) THEN 'J 20/1'::text
            WHEN (ta.tipo_articulo = 'F Alg 100%'::text) THEN 'F Alg'::text
            WHEN (ta.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 C)'::text
            WHEN (ta.tipo_articulo = 'J 30/1-Gam 50/1'::text) THEN 'Varios'::text
            ELSE ta.tipo_articulo
        END AS articulo,
    h.color,
    val.valor,
    i.tenido,
    sum(
        CASE
            WHEN ((a.medida)::text = 'g'::text) THEN ((a.cantidad * (b.precio_prom_kg_usd)::double precision) / (1000)::double precision)
            ELSE (a.cantidad * (b.precio_prom_kg_usd)::double precision)
        END) AS costo_usd,
    (max(part.peso_rollos) + max(part.peso_rib)) AS peso
   FROM ((((((((((((public.matizado a
     JOIN public.insumo b ON ((a.insumo_id = b.id)))
     LEFT JOIN public.turno c ON ((a.turno_id = c.id)))
     LEFT JOIN public.partida d ON ((a.partida_id = d.id)))
     LEFT JOIN public.cliente e ON ((d.cliente_id = e.id)))
     LEFT JOIN public.articulo f ON ((d.articulo_id = f.id)))
     LEFT JOIN public.tipo_articulo ta ON ((f.tipo_articulo_id = ta.id)))
     LEFT JOIN public.color_x_cliente g ON ((d.color_x_cliente_id = g.id)))
     LEFT JOIN public.color h ON ((g.color_id = h.id)))
     JOIN public.partida part ON ((a.partida_id = part.id)))
     LEFT JOIN primera_partida primpart ON (((a.partida_id = primpart.pk_partida) AND (primpart.orden = 1))))
     LEFT JOIN public.tenido i ON ((d.tenido_id = i.id)))
     LEFT JOIN public.valor val ON ((g.valor_id = val.id)))
  GROUP BY a.fecha, c.nombre, a.partida_id,
        CASE
            WHEN (e.cliente ~~ '%J.Ripaz%'::text) THEN 'J.Ripaz'::text
            WHEN (e.cliente ~~ '%Rudy%'::text) THEN 'Rudy'::text
            WHEN (e.cliente ~~ '%J.Urrutia%'::text) THEN 'J.Urrutia'::text
            WHEN (e.cliente ~~ '%Jimmy%'::text) THEN 'Jimmy'::text
            WHEN (e.cliente ~~ '%Oswaldo%'::text) THEN 'Oswaldo'::text
            ELSE e.cliente
        END,
        CASE
            WHEN (ta.tipo_articulo = ANY (ARRAY['F Lycra 30/1 Card'::text, 'F Lycra 30/1 Pei'::text])) THEN 'Full Lycra'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['Gam 50/1'::text, 'Gam 50/1 Pei'::text, 'Gamuza Winter'::text])) THEN 'Gam 50/1'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['J 30/1 Card'::text, 'J 30/1 Pei'::text, 'J 28/1'::text])) THEN 'J 30/1'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['J 20/1 Card'::text, 'J 20/1 Pei'::text, 'J 18/1 Pei'::text])) THEN 'J 20/1'::text
            WHEN (ta.tipo_articulo = 'F Alg 100%'::text) THEN 'F Alg'::text
            WHEN (ta.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 C)'::text
            WHEN (ta.tipo_articulo = 'J 30/1-Gam 50/1'::text) THEN 'Varios'::text
            ELSE ta.tipo_articulo
        END, h.color, i.tenido,
        CASE
            WHEN (primpart.pk_partida IS NOT NULL) THEN 'PRIMERA PARTIDA'::text
            ELSE NULL::text
        END, val.valor;


ALTER TABLE public.vw_matizado_agrupado OWNER TO postgres;

--
-- Name: vw_matizado_lab; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_matizado_lab AS
 WITH ultimos_estados AS (
         SELECT matizado_estados.partida_id AS fk_partida,
            matizado_estados.estado,
            matizado_estados.fecha,
            row_number() OVER (PARTITION BY matizado_estados.partida_id ORDER BY matizado_estados.fecha DESC, matizado_estados.id DESC) AS rn
           FROM public.matizado_estados
        )
 SELECT a.partida_id,
    max(a.fecha) AS fecha_matizado,
    e.cliente,
    f.articulo,
    h.color,
    COALESCE(ue.estado, 'Pendiente'::character varying) AS estado,
    COALESCE(ue.fecha, CURRENT_DATE) AS fecha_estado
   FROM ((((((((public.matizado a
     JOIN public.insumo b ON ((a.insumo_id = b.id)))
     LEFT JOIN public.turno c ON ((a.turno_id = c.id)))
     LEFT JOIN public.partida d ON ((a.partida_id = d.id)))
     LEFT JOIN public.cliente e ON ((d.cliente_id = e.id)))
     LEFT JOIN public.articulo f ON ((d.articulo_id = f.id)))
     LEFT JOIN public.color_x_cliente g ON ((d.color_x_cliente_id = g.id)))
     LEFT JOIN public.color h ON ((g.color_id = h.id)))
     LEFT JOIN ultimos_estados ue ON (((a.partida_id = ue.fk_partida) AND (ue.rn = 1))))
  GROUP BY a.partida_id, e.cliente, f.articulo, h.color, ue.estado, ue.fecha
  ORDER BY a.partida_id;


ALTER TABLE public.vw_matizado_lab OWNER TO postgres;

--
-- Name: vw_motivo_entrada_inventario; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_motivo_entrada_inventario AS
 SELECT unnest(enum_range(NULL::public.motivo_entrada_inventario_enum)) AS valor;


ALTER TABLE public.vw_motivo_entrada_inventario OWNER TO postgres;

--
-- Name: vw_motivo_salida_inventario; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_motivo_salida_inventario AS
 SELECT unnest(enum_range(NULL::public.motivo_salida_inventario_enum)) AS valor;


ALTER TABLE public.vw_motivo_salida_inventario OWNER TO postgres;

--
-- Name: vw_observaciones_acabados; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_observaciones_acabados AS
 SELECT a.id,
    a.fecha,
    c.nombre AS turno,
    a.hora_inicio,
    a.hora_fin,
    a.duracion,
    b.nombre AS maquina,
    b.seccion,
    a.detalle
   FROM ((public.observaciones_planta a
     JOIN public.maquina b ON ((a.maquina_id = b.id)))
     JOIN public.turno c ON ((a.turno_id = c.id)));


ALTER TABLE public.vw_observaciones_acabados OWNER TO postgres;

--
-- Name: vw_observado; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_observado AS
 WITH ultimos_estados AS (
         SELECT observado_estados.partida_id AS fk_partida,
            observado_estados.estado,
            observado_estados.fecha,
            row_number() OVER (PARTITION BY observado_estados.partida_id ORDER BY observado_estados.fecha DESC, observado_estados.id DESC) AS rn
           FROM public.observado_estados
        ), conteo_observados AS (
         SELECT observado.partida_id AS fk_partida,
            count(*) AS veces_observado
           FROM public.observado
          GROUP BY observado.partida_id
        ), tmp_observado AS (
         SELECT a_1.partida_id AS partida,
            a_1.fecha,
            d.color,
            tono.valor,
            ten.tenido,
            f.cliente,
            g.articulo,
            a_1.rollos,
            mot.motivo,
            a_1.detalle,
            a_1.flg_elm,
            row_number() OVER (PARTITION BY a_1.partida_id ORDER BY a_1.fecha DESC, a_1.id DESC) AS rn
           FROM ((((((((public.observado a_1
             LEFT JOIN public.partida b ON ((a_1.partida_id = b.id)))
             LEFT JOIN public.color_x_cliente c ON ((b.color_x_cliente_id = c.id)))
             LEFT JOIN public.color d ON ((c.color_id = d.id)))
             LEFT JOIN public.cliente f ON ((c.cliente_id = f.id)))
             LEFT JOIN public.observado_motivos mot ON ((a_1.motivo_observado_id = mot.id)))
             LEFT JOIN public.articulo g ON ((b.articulo_id = g.id)))
             LEFT JOIN public.valor tono ON ((c.valor_id = tono.id)))
             LEFT JOIN public.tenido ten ON ((b.tenido_id = ten.id)))
        )
 SELECT a.partida,
    a.fecha,
    a.color,
    a.cliente,
    a.articulo,
    a.tenido,
    a.valor,
    a.rollos,
    a.motivo,
    a.detalle,
    COALESCE(ue.estado, 'Pendiente'::character varying) AS estado,
    COALESCE(ue.fecha, a.fecha) AS fecha_estado,
        CASE
            WHEN (a.flg_elm = 0) THEN 'No'::text
            ELSE 'Si'::text
        END AS solucionado,
    co.veces_observado
   FROM ((tmp_observado a
     LEFT JOIN ultimos_estados ue ON (((a.partida = ue.fk_partida) AND (ue.rn = 1))))
     LEFT JOIN conteo_observados co ON ((a.partida = co.fk_partida)))
  WHERE (a.rn = 1);


ALTER TABLE public.vw_observado OWNER TO postgres;

--
-- Name: vw_paradas_tintoreria; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_paradas_tintoreria AS
 SELECT p.id,
    m.nombre AS maquina,
    m.ubicacion,
    m.seccion,
    m.impacto,
    t.nombre AS turno,
    mp.categoria,
    mp.motivo,
    mp.tipo,
    (EXTRACT(month FROM p.fecha_inicio))::integer AS mes,
    public.get_semana_mes((p.fecha_inicio)::date) AS semana_mes,
    p.fecha_inicio,
    p.fecha_fin,
    p.duracion,
    p.duracion_horas,
    p.duracion_minutos,
    p.observacion
   FROM (((public.parada_tintoreria p
     LEFT JOIN public.maquina m ON ((p.maquina_id = m.id)))
     LEFT JOIN public.turno t ON ((p.turno_id = t.id)))
     LEFT JOIN public.motivo_parada mp ON ((p.motivo_id = mp.id)));


ALTER TABLE public.vw_paradas_tintoreria OWNER TO postgres;

--
-- Name: vw_partidas_resumen_v2; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_partidas_resumen_v2 AS
 WITH extras AS (
         SELECT pxe.partida_id AS fk_partida,
            string_agg((ex_1.cod_extra)::text, '+'::text) AS extras,
            sum(pxe.peso) AS peso_extra,
            sum(pxe.cantidad) AS rollos_extra
           FROM (public.partida_x_extra pxe
             JOIN public.extra ex_1 ON ((pxe.extra_id = ex_1.id)))
          GROUP BY pxe.partida_id
        ), prod_tenido AS (
         SELECT produccion_tenido.partida_id AS fk_partida,
            produccion_tenido.fecha,
            (produccion_tenido.estado)::text AS estado,
            row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha DESC) AS orden
           FROM public.produccion_tenido
        ), primera_partida AS (
         SELECT partida.id AS pk_partida,
            row_number() OVER (PARTITION BY partida.color_x_cliente_id, partida.cliente_id ORDER BY partida.id) AS orden
           FROM public.partida
        ), tmp_auditoria AS (
         SELECT auditoria.id,
            auditoria.partida_id AS fk_partida,
            auditoria.fecha_auditoria,
            auditoria.estado,
            row_number() OVER (PARTITION BY auditoria.partida_id ORDER BY auditoria.fecha_auditoria DESC) AS orden
           FROM public.auditoria
        ), programa AS (
         SELECT programacion.partida AS fk_partida,
            max(programacion.fecha_programacion) AS fecha
           FROM public.programacion
          GROUP BY programacion.partida
         HAVING (max(programacion.fecha_programacion) = CURRENT_DATE)
        UNION ALL
         SELECT programa_tenido.partida_id AS fk_partida,
            max(programa_tenido.fecha) AS fecha
           FROM public.programa_tenido
          GROUP BY programa_tenido.partida_id
         HAVING (max(programa_tenido.fecha) = CURRENT_DATE)
        )
 SELECT part.id AS partida,
    part.fecha_registro,
    part.guia,
    part.fecha_entrega,
    pri.prioridad,
    part.cliente_id,
    cli.cliente,
    part.articulo_id,
    art.tipo_articulo_id,
    art.grupo_articulo,
    art.articulo,
    part.color_x_cliente_id,
    col.color_id,
    col.color,
    col.cliente_id AS tono_id,
    col.tono,
    part.rollos,
    part.rib,
    ten.tenido,
    part.tenido_id,
    part.fibra,
    prev.previo,
    part.malla,
    ad.adicional,
    part.ancho,
    part.rendimiento,
    part.observacion,
    ex.extras,
    ((part.peso_rollos + part.peso_rib) + (COALESCE(ex.peso_extra, (0)::numeric))::double precision) AS peso,
    COALESCE(part.receta_id, (partrecet.receta_id)::integer) AS receta_id,
        CASE
            WHEN ((obs.fecha > prod_ten.fecha) AND (obs.fecha IS NOT NULL)) THEN 'Observado'::text
            WHEN ((obs.fecha IS NOT NULL) AND (desp.fecha_despacho >= obs.fecha)) THEN 'Despachado'::text
            WHEN (desp.fecha_despacho IS NOT NULL) THEN 'Despachado'::text
            WHEN ((obs.fecha IS NOT NULL) AND (audit.fecha_auditoria > obs.fecha)) THEN 'Para Despachar'::text
            WHEN (audit.fecha_auditoria IS NOT NULL) THEN 'Para Despachar'::text
            WHEN ((compact.fecha >= prod_ten.fecha) AND (compact.fecha IS NOT NULL)) THEN 'Compactado'::text
            WHEN ((prod_ten.fecha >= obs.fecha) AND (obs.fecha IS NOT NULL)) THEN 'ReTeñido'::text
            WHEN (prod_ten.fk_partida IS NOT NULL) THEN prod_ten.estado
            WHEN (progra.fk_partida IS NOT NULL) THEN 'Programado'::text
            WHEN (recet.id IS NULL) THEN 'Pendiente Receta'::text
            WHEN ((termo.fk_partida IS NULL) AND (part.articulo_id = ANY (ARRAY[6, 22, 32, 33]))) THEN 'Pendiente Termofijar'::text
            WHEN ((termo.fk_partida IS NOT NULL) AND (part.articulo_id = ANY (ARRAY[6, 22, 32, 33]))) THEN 'Para Programar'::text
            ELSE 'Para Programar'::text
        END AS estado,
        CASE
            WHEN ((obs.fecha > prod_ten.fecha) AND (obs.fecha IS NOT NULL)) THEN obs.fecha
            WHEN ((obs.fecha IS NOT NULL) AND (desp.fecha_despacho >= obs.fecha)) THEN desp.fecha_despacho
            WHEN (desp.fecha_despacho IS NOT NULL) THEN desp.fecha_despacho
            WHEN ((obs.fecha IS NOT NULL) AND (audit.fecha_auditoria > obs.fecha)) THEN audit.fecha_auditoria
            WHEN (audit.fecha_auditoria IS NOT NULL) THEN audit.fecha_auditoria
            WHEN ((compact.fecha >= prod_ten.fecha) AND (compact.fecha IS NOT NULL)) THEN compact.fecha
            WHEN ((prod_ten.fecha >= obs.fecha) AND (obs.fecha IS NOT NULL)) THEN prod_ten.fecha
            WHEN (prod_ten.fk_partida IS NOT NULL) THEN prod_ten.fecha
            WHEN (termo.fk_partida IS NOT NULL) THEN termo.fecha
            WHEN (progra.fk_partida IS NOT NULL) THEN progra.fecha
            ELSE NULL::date
        END AS fecha_estado,
    obs.estado AS estado_obs,
    obs.rollos AS rollos_obs,
    obs.motivo AS motivo_obs,
        CASE
            WHEN ((part.fecha_entrega - CURRENT_DATE) < 0) THEN 'Entrega Vencida'::text
            WHEN ((part.fecha_entrega - CURRENT_DATE) = 0) THEN 'Entrega Hoy'::text
            WHEN (((part.fecha_entrega - CURRENT_DATE) >= 1) AND ((part.fecha_entrega - CURRENT_DATE) <= 3)) THEN 'Entrega Por Vencer'::text
            WHEN ((part.fecha_entrega - CURRENT_DATE) > 3) THEN 'Entrega En Tiempo'::text
            ELSE NULL::text
        END AS estado_entrega,
        CASE
            WHEN (abs((part.fecha_entrega - CURRENT_DATE)) = 0) THEN '0 días'::text
            WHEN ((abs((part.fecha_entrega - CURRENT_DATE)) >= 1) AND (abs((part.fecha_entrega - CURRENT_DATE)) <= 3)) THEN '1 a 3'::text
            WHEN ((abs((part.fecha_entrega - CURRENT_DATE)) >= 4) AND (abs((part.fecha_entrega - CURRENT_DATE)) <= 7)) THEN '3 a 7'::text
            WHEN (abs((part.fecha_entrega - CURRENT_DATE)) > 7) THEN 'más de 7'::text
            ELSE 'Sin rango'::text
        END AS rango_vencimiento_dias,
        CASE
            WHEN (part.fecha_entrega IS NULL) THEN NULL::integer
            ELSE (part.fecha_entrega - CURRENT_DATE)
        END AS vencimiento_dias,
        CASE
            WHEN (pripart.pk_partida IS NOT NULL) THEN 'PRIMERA PARTIDA'::text
            ELSE NULL::text
        END AS flg_prim_part,
    te_std.duracion,
    part.peso_rollos,
    part.peso_rib,
    ex.peso_extra,
    ex.rollos_extra
   FROM ((((((((((((((((((((public.partida part
     LEFT JOIN public.prioridad pri ON ((pri.id = part.prioridad_id)))
     LEFT JOIN public.cliente cli ON ((cli.id = part.cliente_id)))
     LEFT JOIN public.articulo art ON ((art.id = part.articulo_id)))
     LEFT JOIN public.vw_colores col ON ((col.color_x_cliente_id = part.color_x_cliente_id)))
     LEFT JOIN public.tenido ten ON ((ten.id = part.tenido_id)))
     LEFT JOIN public.adicional ad ON ((ad.id = part.adicional_id)))
     LEFT JOIN extras ex ON ((ex.fk_partida = part.id)))
     LEFT JOIN public.previo prev ON ((part.previo_id = prev.id)))
     LEFT JOIN ( SELECT despacho.partida_id AS fk_partida,
            max(despacho.fecha_despacho) AS fecha_despacho,
            sum(despacho.rollos) AS rollos
           FROM public.despacho
          GROUP BY despacho.partida_id) desp ON ((part.id = desp.fk_partida)))
     LEFT JOIN prod_tenido prod_ten ON (((part.id = prod_ten.fk_partida) AND (prod_ten.orden = 1))))
     LEFT JOIN ( SELECT programa.fk_partida,
            max(programa.fecha) AS fecha
           FROM programa
          GROUP BY programa.fk_partida
         HAVING (max(programa.fecha) = CURRENT_DATE)) progra ON ((part.id = progra.fk_partida)))
     LEFT JOIN public.vw_observado_lab obs ON ((part.id = obs.partida)))
     LEFT JOIN ( SELECT compactado.partida_id AS fk_partida,
            max(compactado.fecha) AS fecha
           FROM public.compactado
          GROUP BY compactado.partida_id
         HAVING (sum(compactado.rollos) > 0)) compact ON ((part.id = compact.fk_partida)))
     LEFT JOIN ( SELECT termofijado.partida_id AS fk_partida,
            max(termofijado.fecha) AS fecha
           FROM public.termofijado
          GROUP BY termofijado.partida_id) termo ON ((part.id = termo.fk_partida)))
     LEFT JOIN public.receta2 recet ON (((part.color_x_cliente_id = recet.color_x_cliente_id) AND (art.tipo_articulo_id = recet.tipo_articulo_id) AND (part.fibra = recet.fibra) AND (part.tenido_id = recet.tenido_id) AND (recet.flg_antipilling =
        CASE
            WHEN (part.adicional_id = 1) THEN true
            ELSE false
        END) AND (recet.flg_activo = true) AND (recet.tipo_receta_id = 7))))
     LEFT JOIN primera_partida pripart ON (((part.id = pripart.pk_partida) AND (pripart.orden = 1))))
     LEFT JOIN public.partida_x_recetas partrecet ON (((part.id = partrecet.partida_id) AND (partrecet.tipo_receta_id = 7))))
     LEFT JOIN tmp_auditoria audit ON (((part.id = audit.fk_partida) AND (audit.orden = 1) AND (audit.estado = 'OK'::text))))
     LEFT JOIN public.color_x_cliente val ON ((col.color_x_cliente_id = val.id)))
     LEFT JOIN public.tiempos_estandar_tenido te_std ON (((te_std.valor_id = val.valor_id) AND (te_std.tenido_id = part.tenido_id) AND (COALESCE((te_std.adicional_id)::integer, 0) = COALESCE((part.adicional_id)::integer, 0)) AND (te_std.tipo_receta_id = 8))))
  WHERE (part.id > 0)
  ORDER BY part.id;


ALTER TABLE public.vw_partidas_resumen_v2 OWNER TO postgres;

--
-- Name: vw_partidas_x_auditar; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_partidas_x_auditar AS
 WITH tmp AS (
         SELECT a_1.partida_id AS fk_partida,
            a_1.estado,
            max(a_1.fecha) AS fecha_compactado,
            sum(a_1.rollos) AS rollos,
            sum(a_1.rib) AS rib
           FROM public.compactado a_1
          WHERE ((a_1.estado)::text = 'Compactado'::text)
          GROUP BY a_1.partida_id, a_1.estado
        ), tmp_auditoria AS (
         SELECT auditoria.id,
            auditoria.partida_id AS fk_partida,
            auditoria.fecha_auditoria,
            auditoria.estado,
            row_number() OVER (PARTITION BY auditoria.partida_id ORDER BY auditoria.fecha_auditoria DESC) AS orden
           FROM public.auditoria
        )
 SELECT a.id AS partida_id,
    c.cliente,
    d.articulo,
    e.color,
    f.tenido,
    a.rollos AS rollos_total,
    a.rib AS rib_total,
    COALESCE(b.estado, pt.estado) AS estado_partida,
    COALESCE(b.fecha_compactado, pt.fecha_tenido) AS fecha_compactado_tenido,
        CASE
            WHEN ((a.cliente_id = 49) OR (a.id <= 600)) THEN 'Partida Completa'::text
            WHEN ((b.rollos >= a.rollos) AND (b.rib >= a.rib)) THEN 'Partida Completa'::text
            WHEN ((b.rollos >= a.rollos) AND (b.rib <= a.rib)) THEN concat('Pendiente ', (a.rib - b.rib), ' rib')
            WHEN ((b.rollos <= a.rollos) AND (b.rib >= a.rib)) THEN concat('Pendiente ', (a.rollos - b.rollos), ' rollos')
            WHEN ((b.rollos <= a.rollos) AND (b.rib <= a.rib)) THEN concat('Pendiente ', (a.rollos - b.rollos), ' rollos - ', (a.rib - b.rib), ' rib')
            ELSE NULL::text
        END AS estado_partida,
    COALESCE(audit.estado, 'Pendiente'::text) AS estado
   FROM ((((((((public.partida a
     LEFT JOIN tmp b ON ((a.id = b.fk_partida)))
     LEFT JOIN public.cliente c ON ((a.cliente_id = c.id)))
     LEFT JOIN public.articulo d ON ((a.articulo_id = d.id)))
     LEFT JOIN public.colores e ON ((a.color_x_cliente_id = e.id)))
     LEFT JOIN public.tenido f ON ((a.tenido_id = f.id)))
     LEFT JOIN tmp_auditoria audit ON (((a.id = audit.fk_partida) AND (audit.orden = 1))))
     LEFT JOIN ( SELECT observado.partida_id AS partida,
            max(observado.fecha) AS fecha
           FROM public.observado
          WHERE (observado.flg_elm = 0)
          GROUP BY observado.partida_id) obs ON ((a.id = obs.partida)))
     LEFT JOIN ( SELECT produccion_tenido.partida_id AS fk_partida,
            max(produccion_tenido.fecha) AS fecha_tenido,
            produccion_tenido.estado
           FROM public.produccion_tenido
          WHERE ((produccion_tenido.estado)::text = 'Teñido'::text)
          GROUP BY produccion_tenido.partida_id, produccion_tenido.estado) pt ON ((pt.fk_partida = a.id)))
  WHERE (((audit.estado <> 'OK'::text) OR (audit.estado IS NULL)) AND (a.id > 0) AND (((b.fecha_compactado >= COALESCE(obs.fecha, '2000-06-01'::date)) AND (b.rollos > 0)) OR ((pt.fecha_tenido >= COALESCE(obs.fecha, '2000-06-01'::date)) AND (a.cliente_id = ANY (ARRAY[49, 88]))) OR (a.id <= 600)))
  ORDER BY COALESCE(b.fecha_compactado, pt.fecha_tenido) DESC;


ALTER TABLE public.vw_partidas_x_auditar OWNER TO postgres;

--
-- Name: vw_partidas_x_despachar; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_partidas_x_despachar AS
 WITH tmp AS (
         SELECT a_1.partida_id AS fk_partida,
            a_1.estado,
            max(a_1.fecha) AS fecha_compactado,
            sum(a_1.rollos) AS rollos,
            sum(a_1.rib) AS rib
           FROM public.compactado a_1
          WHERE ((a_1.estado)::text = 'Compactado'::text)
          GROUP BY a_1.partida_id, a_1.estado
        ), tmp_auditoria AS (
         SELECT auditoria.id,
            auditoria.partida_id AS fk_partida,
            auditoria.fecha_auditoria,
            auditoria.estado,
            row_number() OVER (PARTITION BY auditoria.partida_id ORDER BY auditoria.fecha_auditoria DESC) AS orden
           FROM public.auditoria
        )
 SELECT a.id AS partida_id,
    a.guia,
    c.cliente,
    d.articulo,
    e.color,
    f.tenido,
    a.rollos,
    COALESCE(a.rib, ext.cantidad) AS rib_extra,
    a.ancho,
    COALESCE(b.estado, pt.estado) AS estado_partida,
    COALESCE(b.fecha_compactado, pt.fecha_tenido) AS fecha_compactado_tenido,
    a.observacion
   FROM ((((((((((public.partida a
     LEFT JOIN tmp b ON ((a.id = b.fk_partida)))
     LEFT JOIN public.cliente c ON ((a.cliente_id = c.id)))
     LEFT JOIN public.articulo d ON ((a.articulo_id = d.id)))
     LEFT JOIN public.colores e ON ((a.color_x_cliente_id = e.id)))
     LEFT JOIN public.tenido f ON ((a.tenido_id = f.id)))
     LEFT JOIN public.partida_x_extra ext ON ((a.id = ext.partida_id)))
     LEFT JOIN tmp_auditoria audit ON (((a.id = audit.fk_partida) AND (audit.orden = 1))))
     LEFT JOIN ( SELECT observado.partida_id AS partida,
            max(observado.fecha) AS fecha
           FROM public.observado
          WHERE (observado.flg_elm = 0)
          GROUP BY observado.partida_id) obs ON ((a.id = obs.partida)))
     LEFT JOIN ( SELECT produccion_tenido.partida_id AS fk_partida,
            max(produccion_tenido.fecha) AS fecha_tenido,
            produccion_tenido.estado
           FROM public.produccion_tenido
          WHERE ((produccion_tenido.estado)::text = 'Teñido'::text)
          GROUP BY produccion_tenido.partida_id, produccion_tenido.estado) pt ON ((pt.fk_partida = a.id)))
     LEFT JOIN ( SELECT DISTINCT despacho.partida_id AS fk_partida
           FROM public.despacho) desp ON ((a.id = desp.fk_partida)))
  WHERE ((audit.estado = 'OK'::text) AND (a.id > 0) AND (desp.fk_partida IS NULL) AND (audit.fecha_auditoria > COALESCE(obs.fecha, '2000-06-01'::date)))
  ORDER BY COALESCE(b.estado, pt.estado) DESC;


ALTER TABLE public.vw_partidas_x_despachar OWNER TO postgres;

--
-- Name: vw_partidas_x_pesar; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_partidas_x_pesar OWNER TO postgres;

--
-- Name: vw_partidas_x_programar; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_partidas_x_programar AS
 WITH prod_tenido AS (
         SELECT produccion_tenido.partida_id AS fk_partida,
            produccion_tenido.fecha,
            (produccion_tenido.estado)::text AS estado,
            row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha DESC) AS orden
           FROM public.produccion_tenido
        ), extras AS (
         SELECT pxe.partida_id AS fk_partida,
            string_agg((ex_1.cod_extra)::text, '+'::text) AS extras,
            COALESCE((sum(pxe.cantidad))::numeric, (0)::numeric) AS cant_extra,
            COALESCE(sum(pxe.peso), (0)::numeric) AS peso_extra
           FROM (public.partida_x_extra pxe
             JOIN public.extra ex_1 ON ((pxe.extra_id = ex_1.id)))
          GROUP BY pxe.partida_id
        )
 SELECT part.id AS partida,
    cli.cliente,
    col.color,
    valor.valor,
    art.grupo_articulo AS articulo,
    ten.tenido,
    (
        CASE
            WHEN (obs.partida IS NOT NULL) THEN obs.rollos
            ELSE (part.rollos)::integer
        END)::smallint AS rollos,
    (
        CASE
            WHEN ((obs.rollos IS NOT NULL) AND (part.rollos <> obs.rollos)) THEN 0
            ELSE (COALESCE((part.rib)::integer, 0) + (COALESCE(ex.cant_extra, (0)::numeric))::integer)
        END)::smallint AS rib,
    esta.estado,
        CASE
            WHEN ((part.fecha_entrega - CURRENT_DATE) < 0) THEN 'Entrega Vencida'::text
            WHEN ((part.fecha_entrega - CURRENT_DATE) = 0) THEN 'Entrega Hoy'::text
            WHEN (((part.fecha_entrega - CURRENT_DATE) >= 1) AND ((part.fecha_entrega - CURRENT_DATE) <= 3)) THEN 'Entrega Por Vencer'::text
            WHEN ((part.fecha_entrega - CURRENT_DATE) > 3) THEN 'Entrega En Tiempo'::text
            ELSE NULL::text
        END AS entrega,
    (part.fecha_entrega - CURRENT_DATE) AS dias,
        CASE
            WHEN (partrecet.partida_id IS NOT NULL) THEN concat(part.id, 'R')
            WHEN ((part.peso_rollos IS NOT NULL) AND (part.peso_rollos > (0)::double precision)) THEN concat(part.id, 'P')
            ELSE concat(part.id)
        END AS partida2,
        CASE
            WHEN (part.id IS NULL) THEN NULL::text
            ELSE concat(
            CASE
                WHEN (part.ancho IS NOT NULL) THEN concat('A:', part.ancho)
                ELSE ''::text
            END,
            CASE
                WHEN ((part.rendimiento IS NOT NULL) AND ((part.rendimiento)::text <> '0'::text)) THEN concat('/R:', part.rendimiento)
                ELSE ''::text
            END,
            CASE
                WHEN (part.fibra IS NOT NULL) THEN concat('/', part.fibra, 'F')
                ELSE ''::text
            END,
            CASE
                WHEN (part.adicional_id IS NOT NULL) THEN '/V.Tela'::text
                ELSE ''::text
            END,
            CASE
                WHEN ("left"(esta.flg_prim_part, 4) IS NOT NULL) THEN concat('/', "left"(esta.flg_prim_part, 4))
                ELSE ''::text
            END)
        END AS info
   FROM ((((((((((((((((public.partida part
     LEFT JOIN public.cliente cli ON ((cli.id = part.cliente_id)))
     LEFT JOIN public.articulo art ON ((art.id = part.articulo_id)))
     LEFT JOIN public.colores col ON ((col.id = part.color_x_cliente_id)))
     LEFT JOIN public.color_x_cliente val ON ((col.id = val.id)))
     LEFT JOIN public.valor valor ON ((val.valor_id = valor.id)))
     LEFT JOIN public.tenido ten ON ((ten.id = part.tenido_id)))
     LEFT JOIN extras ex ON ((part.id = ex.fk_partida)))
     LEFT JOIN ( SELECT despacho.partida_id AS fk_partida,
            max(despacho.fecha_despacho) AS fecha_despacho,
            sum(despacho.rollos) AS rollos
           FROM public.despacho
          GROUP BY despacho.partida_id) desp ON ((part.id = desp.fk_partida)))
     LEFT JOIN prod_tenido prod_ten ON (((part.id = prod_ten.fk_partida) AND (prod_ten.orden = 1))))
     LEFT JOIN ( SELECT programacion.partida,
            max(programacion.fecha_programacion) AS fecha
           FROM public.programacion
          GROUP BY programacion.partida
         HAVING (max(programacion.fecha_programacion) = CURRENT_DATE)) prog ON ((part.id = prog.partida)))
     LEFT JOIN ( SELECT compactado.partida_id AS fk_partida,
            max(compactado.fecha) AS fecha
           FROM public.compactado
          GROUP BY compactado.partida_id) compact ON ((part.id = compact.fk_partida)))
     LEFT JOIN ( SELECT termofijado.partida_id AS fk_partida,
            max(termofijado.fecha) AS fecha
           FROM public.termofijado
          GROUP BY termofijado.partida_id) termo ON ((part.id = termo.fk_partida)))
     LEFT JOIN ( SELECT vw_observado_lab.partida,
            vw_observado_lab.fecha,
            vw_observado_lab.color,
            vw_observado_lab.cliente,
            vw_observado_lab.articulo,
            vw_observado_lab.rollos,
            vw_observado_lab.motivo,
            vw_observado_lab.detalle,
            vw_observado_lab.estado,
            vw_observado_lab.fecha_estado
           FROM public.vw_observado_lab
          WHERE ((vw_observado_lab.estado)::text <> ALL (ARRAY[('Programado'::character varying)::text, ('Reprocesado'::character varying)::text]))) obs ON ((part.id = obs.partida)))
     LEFT JOIN public.receta2 recet ON (((part.color_x_cliente_id = recet.color_x_cliente_id) AND (art.tipo_articulo_id = recet.tipo_articulo_id) AND (part.fibra = recet.fibra) AND (part.tenido_id = recet.tenido_id) AND (recet.flg_antipilling =
        CASE
            WHEN (part.adicional_id = 1) THEN true
            ELSE false
        END) AND (recet.flg_activo = true) AND (recet.tipo_receta_id = 7))))
     LEFT JOIN public.partida_x_recetas partrecet ON (((part.id = partrecet.partida_id) AND (partrecet.tipo_receta_id = 7) AND (partrecet.flg_elm = false))))
     LEFT JOIN ( SELECT DISTINCT vw_partidas_resumen.partida,
            vw_partidas_resumen.estado,
            vw_partidas_resumen.flg_prim_part
           FROM public.vw_partidas_resumen) esta ON ((part.id = esta.partida)))
  WHERE ((part.id > 0) AND (esta.estado = ANY (ARRAY['Pendiente Termofijar'::text, 'Pendiente Receta'::text, 'Para Programar'::text, 'Observado'::text])))
  ORDER BY (part.fecha_entrega - CURRENT_DATE), part.id;


ALTER TABLE public.vw_partidas_x_programar OWNER TO postgres;

--
-- Name: vw_precio_costo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_precio_costo AS
 WITH receta_norm AS (
         SELECT b.color,
            b.cliente,
            b.tenido,
            b.fibra,
            b.flg_antipilling,
            b.tipo_articulo,
                CASE
                    WHEN (b.tipo_articulo ~~ '%2 cabos%'::text) THEN 'Jersey (2 cabos)'::text
                    WHEN ((b.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text])) AND ((b.tipo_articulo ~~* '%J 30%'::text) OR (b.tipo_articulo ~~* '%J 20%'::text) OR (b.tipo_articulo ~~* '%Gam 50/1%'::text))) THEN 'Jersey/Gamuza'::text
                    WHEN (b.tipo_articulo ~~* '%J 30%'::text) THEN 'J 30/1'::text
                    WHEN (b.tipo_articulo ~~* '%J 20%'::text) THEN 'J 20/1'::text
                    WHEN (b.tipo_articulo ~~* '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
                    WHEN ((b.tipo_articulo ~~* '%F Lycra%'::text) OR (b.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
                    ELSE b.tipo_articulo
                END AS tipo_norm,
            b.costo_12r,
            b.costo
           FROM public.vw_receta b
          WHERE ((b.cliente !~~* '%Osw%'::text) AND (b.cliente <> ALL (ARRAY['Delia'::text, 'Alejandrina'::text, 'Silv/Car'::text, 'Arecio'::text, 'Monica'::text, 'Maycol'::text, 'Ego'::text])) AND (concat(b.cliente, "left"(b.tipo_articulo, 8)) <> 'J.RipazGam 50/1'::text) AND (b.tipo_receta = 'Teñido'::text))
        ), receta_agg AS (
         SELECT receta_norm.color,
            receta_norm.cliente,
            receta_norm.tenido,
            receta_norm.fibra,
            receta_norm.flg_antipilling,
            receta_norm.tipo_norm,
            max(receta_norm.costo_12r) AS costo_12r_raw,
            max(receta_norm.costo) AS costo_raw
           FROM receta_norm
          GROUP BY receta_norm.color, receta_norm.cliente, receta_norm.tenido, receta_norm.fibra, receta_norm.flg_antipilling, receta_norm.tipo_norm
        ), catalogo_norm AS (
         SELECT a_1.color,
            a_1.cliente,
            a_1.tenido,
            a_1.fibra,
            a_1.tipo_articulo,
                CASE
                    WHEN (a_1.tipo_articulo ~~ '%2 cabos%'::text) THEN 'Jersey (2 cabos)'::text
                    WHEN ((a_1.cliente = ANY (ARRAY['Montes'::text, 'Urban'::text, 'Faride'::text])) AND ((a_1.tipo_articulo ~~* '%J 30%'::text) OR (a_1.tipo_articulo ~~* '%J 20%'::text) OR (a_1.tipo_articulo ~~* '%Gam 50/1%'::text))) THEN 'Jersey/Gamuza'::text
                    WHEN (a_1.tipo_articulo ~~* '%J 30%'::text) THEN 'J 30/1'::text
                    WHEN (a_1.tipo_articulo ~~* '%J 20%'::text) THEN 'J 20/1'::text
                    WHEN (a_1.tipo_articulo ~~* '%Gam 50/1%'::text) THEN 'Gam 50/1'::text
                    WHEN ((a_1.tipo_articulo ~~* '%F Lycra%'::text) OR (a_1.tipo_articulo = 'Full Lycra'::text)) THEN 'Full Lycra'::text
                    ELSE a_1.tipo_articulo
                END AS tipo_norm,
            a_1.precio_tenido
           FROM public.vw_catalogo_precios a_1
        ), catalogo_agg AS (
         SELECT catalogo_norm.color,
            catalogo_norm.cliente,
            catalogo_norm.tenido,
            catalogo_norm.fibra,
            catalogo_norm.tipo_norm,
            max(catalogo_norm.precio_tenido) AS precio_tenido
           FROM catalogo_norm
          GROUP BY catalogo_norm.color, catalogo_norm.cliente, catalogo_norm.tenido, catalogo_norm.fibra, catalogo_norm.tipo_norm
        )
 SELECT r.color,
    r.tipo_norm AS tipo_articulo,
    r.cliente,
    r.tenido,
    r.fibra,
    COALESCE(a.precio_tenido, (0)::numeric) AS precio_tenido,
    (((r.costo_12r_raw * 1.18) + 0.8))::numeric(5,2) AS costo_12r,
    (((r.costo_raw * 1.18) + 0.8))::numeric(5,2) AS costo,
        CASE
            WHEN (a.precio_tenido IS NULL) THEN NULL::numeric
            ELSE (a.precio_tenido - ((r.costo_raw * 1.18) + 0.8))
        END AS margen,
        CASE
            WHEN ((a.precio_tenido IS NULL) OR (a.precio_tenido = (0)::numeric)) THEN NULL::numeric
            ELSE ((a.precio_tenido - ((r.costo_raw * 1.18) + 0.8)) / a.precio_tenido)
        END AS "margen%",
        CASE
            WHEN ((r.tipo_norm ~~* '%F Poly%'::text) AND (r.cliente <> 'Camones'::text)) THEN (a.precio_tenido + 0.30)
            WHEN (r.tipo_norm ~~* '%Full Lycra%'::text) THEN (a.precio_tenido + 0.25)
            WHEN (r.cliente = 'Rudy'::text) THEN (a.precio_tenido + 0.10)
            ELSE a.precio_tenido
        END AS precio_sn_anti,
        CASE
            WHEN ((r.tipo_norm ~~* '%F Poly%'::text) AND (r.cliente <> 'Camones'::text)) THEN (a.precio_tenido + 0.30)
            WHEN ((r.tipo_norm ~~* '%Full Lycra%'::text) AND (r.flg_antipilling = true)) THEN (a.precio_tenido + 0.35)
            WHEN (r.tipo_norm ~~* '%Full Lycra%'::text) THEN (a.precio_tenido + 0.25)
            WHEN (r.cliente = 'Rudy'::text) THEN (a.precio_tenido + 0.10)
            WHEN ((r.flg_antipilling = true) AND (r.cliente = 'Urban'::text)) THEN (a.precio_tenido + 0.15)
            WHEN (r.flg_antipilling = true) THEN (a.precio_tenido + 0.10)
            ELSE a.precio_tenido
        END AS precio_cn_anti
   FROM (receta_agg r
     LEFT JOIN catalogo_agg a ON ((((a.color)::text = (r.color)::text) AND (a.cliente = r.cliente) AND (a.tenido = r.tenido) AND (a.fibra = r.fibra) AND (a.tipo_norm = r.tipo_norm))))
  ORDER BY r.tenido, r.cliente, r.fibra, r.tipo_norm;


ALTER TABLE public.vw_precio_costo OWNER TO postgres;

--
-- Name: vw_produccion_acabados; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_produccion_acabados AS
 SELECT sub.mes,
    sub.fecha,
    sub.mes_tenido,
    sub.partida_id,
    sub.tipo_partida,
    sub.turno,
    sub.maquina,
    sub.ubicacion,
    sub.color,
    sub.cliente,
    sub.rollos,
    sub.rib,
    sub.rollos_total,
    sub.peso_total,
    sub.grupo_articulo,
    sub.hora_inicio,
    sub.hora_fin,
    sub.duracion,
    sub.estado,
    sub.id,
    sub.fecha_tenido,
    sub.dias_desde_tenido
   FROM ( WITH produccion_acabados AS (
                 SELECT perchado.id,
                    perchado.fecha,
                    perchado.partida_id AS fk_partida,
                    'Percha'::text AS partida,
                    'Produccion'::text AS tipo_partida,
                    perchado.turno_id AS fk_turno,
                    13 AS fk_maquina,
                    perchado.rollos,
                    0 AS rib,
                    perchado.hora_inicio,
                    perchado.hora_fin,
                    perchado.duracion,
                    'Perchado'::text AS estado
                   FROM public.perchado
                UNION ALL
                 SELECT termofijado.id,
                    termofijado.fecha,
                    termofijado.partida_id AS fk_partida,
                    'Termo'::text AS partida,
                    'Produccion'::text AS tipo_partida,
                    termofijado.turno_id AS fk_turno,
                    19 AS fk_maquina,
                    termofijado.rollos,
                    0 AS rib,
                    termofijado.hora_inicio,
                    termofijado.hora_fin,
                    termofijado.duracion,
                    'Termofijado'::text AS estado
                   FROM public.termofijado
                UNION ALL
                 SELECT compactado.id,
                    compactado.fecha,
                    compactado.partida_id AS fk_partida,
                    'Compactadora'::text AS partida,
                    compactado.tipo_partida,
                    compactado.turno_id AS fk_turno,
                    compactado.maquina_id AS fk_maquina,
                    compactado.rollos,
                    compactado.rib,
                    compactado.hora_inicio,
                    compactado.hora_fin,
                    compactado.duracion,
                    compactado.estado
                   FROM public.compactado
                ), prod_tenido AS (
                 SELECT produccion_tenido.partida_id AS fk_partida,
                    produccion_tenido.tipo,
                    produccion_tenido.fecha,
                    row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha) AS orden
                   FROM public.produccion_tenido
                  WHERE ((produccion_tenido.estado)::text = 'Teñido'::text)
                )
         SELECT
                CASE (EXTRACT(month FROM a.fecha))::integer
                    WHEN 1 THEN 'Enero'::text
                    WHEN 2 THEN 'Febrero'::text
                    WHEN 3 THEN 'Marzo'::text
                    WHEN 4 THEN 'Abril'::text
                    WHEN 5 THEN 'Mayo'::text
                    WHEN 6 THEN 'Junio'::text
                    WHEN 7 THEN 'Julio'::text
                    WHEN 8 THEN 'Agosto'::text
                    WHEN 9 THEN 'Septiembre'::text
                    WHEN 10 THEN 'Octubre'::text
                    WHEN 11 THEN 'Noviembre'::text
                    WHEN 12 THEN 'Diciembre'::text
                    ELSE NULL::text
                END AS mes,
            a.fecha,
                CASE (EXTRACT(month FROM prodten.fecha))::integer
                    WHEN 1 THEN 'Enero'::text
                    WHEN 2 THEN 'Febrero'::text
                    WHEN 3 THEN 'Marzo'::text
                    WHEN 4 THEN 'Abril'::text
                    WHEN 5 THEN 'Mayo'::text
                    WHEN 6 THEN 'Junio'::text
                    WHEN 7 THEN 'Julio'::text
                    WHEN 8 THEN 'Agosto'::text
                    WHEN 9 THEN 'Septiembre'::text
                    WHEN 10 THEN 'Octubre'::text
                    WHEN 11 THEN 'Noviembre'::text
                    WHEN 12 THEN 'Diciembre'::text
                    ELSE NULL::text
                END AS mes_tenido,
            a.fk_partida AS partida_id,
            a.tipo_partida,
            i.nombre AS turno,
            h.nombre AS maquina,
            h.ubicacion,
            d.color,
            f.cliente,
            COALESCE(a.rollos, 0) AS rollos,
            (COALESCE(a.rib, 0) + COALESCE((ext.cantidad)::integer, 0)) AS rib,
            ((COALESCE(a.rollos, 0) + COALESCE(a.rib, 0)) + COALESCE((ext.cantidad)::integer, 0)) AS rollos_total,
                CASE
                    WHEN ((COALESCE(a.rib, 0) = 0) AND (COALESCE((ext.cantidad)::integer, 0) = 0) AND (COALESCE(a.rollos, 0) > 0)) THEN ((a.rollos)::double precision * (b.peso_rollos / (b.rollos)::double precision))
                    WHEN ((COALESCE(a.rollos, 0) = 0) AND (COALESCE(a.rib, 0) > 0) AND (COALESCE((ext.cantidad)::integer, 0) = 0)) THEN COALESCE(((a.rib)::double precision * (b.peso_rib / (COALESCE((b.rib)::integer, 1))::double precision)), (0)::double precision)
                    WHEN ((COALESCE(a.rollos, 0) = 0) AND (COALESCE(a.rib, 0) > 0) AND (COALESCE((ext.cantidad)::integer, 0) > 0)) THEN (COALESCE(((a.rib)::numeric * (ext.peso / (COALESCE((ext.cantidad)::integer, 1))::numeric)), (0)::numeric))::double precision
                    WHEN ((COALESCE(a.rollos, 0) > 0) AND (COALESCE(a.rib, 0) > 0) AND (COALESCE((ext.cantidad)::integer, 0) = 0)) THEN (((a.rollos)::double precision * (b.peso_rollos / (b.rollos)::double precision)) + ((a.rib)::double precision * (b.peso_rib / (b.rib)::double precision)))
                    ELSE ((COALESCE(((a.rib)::numeric * (ext.peso / (COALESCE((ext.cantidad)::integer, 1))::numeric)), (0)::numeric))::double precision + ((a.rollos)::double precision * (b.peso_rollos / (b.rollos)::double precision)))
                END AS peso_total,
            g.grupo_articulo,
            a.hora_inicio,
            a.hora_fin,
            a.duracion,
            a.estado,
            a.id,
            lt.fecha_tenido,
                CASE
                    WHEN ((a.partida = 'Compactadora'::text) AND (lt.fecha_tenido IS NOT NULL)) THEN (a.fecha - lt.fecha_tenido)
                    ELSE NULL::integer
                END AS dias_desde_tenido
           FROM (((((((((((produccion_acabados a
             LEFT JOIN public.partida b ON ((a.fk_partida = b.id)))
             LEFT JOIN public.color_x_cliente c ON ((b.color_x_cliente_id = c.id)))
             LEFT JOIN prod_tenido prodten ON (((a.fk_partida = prodten.fk_partida) AND (prodten.orden = 1))))
             LEFT JOIN public.color d ON ((c.color_id = d.id)))
             LEFT JOIN public.previo e ON ((b.previo_id = e.id)))
             LEFT JOIN public.cliente f ON ((b.cliente_id = f.id)))
             LEFT JOIN public.articulo g ON ((b.articulo_id = g.id)))
             LEFT JOIN public.maquina h ON ((a.fk_maquina = h.id)))
             LEFT JOIN public.turno i ON ((a.fk_turno = i.id)))
             LEFT JOIN public.partida_x_extra ext ON ((b.id = ext.partida_id)))
             LEFT JOIN LATERAL ( SELECT max(pt.fecha) AS fecha_tenido
                   FROM public.produccion_tenido pt
                  WHERE ((pt.partida_id = a.fk_partida) AND (pt.fecha <= a.fecha) AND ((pt.estado)::text = 'Teñido'::text))) lt ON ((a.partida = 'Compactadora'::text)))) sub;


ALTER TABLE public.vw_produccion_acabados OWNER TO postgres;

--
-- Name: vw_produccion_tenido; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_produccion_tenido AS
 SELECT
        CASE (EXTRACT(month FROM a.fecha))::integer
            WHEN 1 THEN 'Enero'::text
            WHEN 2 THEN 'Febrero'::text
            WHEN 3 THEN 'Marzo'::text
            WHEN 4 THEN 'Abril'::text
            WHEN 5 THEN 'Mayo'::text
            WHEN 6 THEN 'Junio'::text
            WHEN 7 THEN 'Julio'::text
            WHEN 8 THEN 'Agosto'::text
            WHEN 9 THEN 'Septiembre'::text
            WHEN 10 THEN 'Octubre'::text
            WHEN 11 THEN 'Noviembre'::text
            WHEN 12 THEN 'Diciembre'::text
            ELSE NULL::text
        END AS mes,
    a.fecha,
    public.get_semana_mes(a.fecha) AS semana_mes,
    a.partida_id,
    a.id,
        CASE
            WHEN (((a.tipo)::text ~~* '%Lavado%'::text) OR ((a.tipo)::text ~~* '%Mojar%'::text)) THEN 'Lavado'::character varying
            WHEN ((a.tipo)::text = 'Desmontado + Reteñido'::text) THEN 'Desmontado'::character varying
            WHEN ((a.tipo)::text = 'Repartida Desmontado'::text) THEN 'Desmontado'::character varying
            WHEN ((a.tipo)::text = ANY (ARRAY[('Reteñido'::character varying)::text, ('Rebaje'::character varying)::text, ('Repartida Matizado'::character varying)::text, 'Repartida Otros'::text])) THEN 'Repartida'::character varying
            WHEN ((a.tipo)::text = 'Teñido'::text) THEN 'Produccion'::character varying
            WHEN ((a.tipo)::text = 'Repartida Antiguo'::text) THEN 'Rep. Antiguo'::character varying
            ELSE a.tipo
        END AS tipo,
    a.tipo AS subtipo,
    a.maquina,
    h.tenido,
    d.color,
    j.valor,
        CASE
            WHEN (f.cliente ~~ '%J.Ripaz%'::text) THEN 'J.Ripaz'::text
            WHEN (f.cliente ~~ '%Rudy%'::text) THEN 'Rudy'::text
            WHEN (f.cliente ~~ '%J.Urrutia%'::text) THEN 'J.Urrutia'::text
            WHEN (f.cliente ~~ '%Jimmy%'::text) THEN 'Jimmy'::text
            WHEN (f.cliente ~~ '%Oswaldo%'::text) THEN 'Oswaldo'::text
            ELSE f.cliente
        END AS cliente,
    a.estado AS partida,
    a.rollos,
    a.kilos,
    (public.prorratear_kilos_turno(a.hora_inicio, (a.duracion)::interval, (a.kilos)::numeric)).kilos_dia AS kilos_dia,
    (public.prorratear_kilos_turno(a.hora_inicio, (a.duracion)::interval, (a.kilos)::numeric)).kilos_noche AS kilos_noche,
        CASE
            WHEN (i.tipo_articulo = ANY (ARRAY['F Lycra 30/1 Card'::text, 'F Lycra 30/1 Pei'::text])) THEN 'Full Lycra'::text
            WHEN (i.tipo_articulo = ANY (ARRAY['Gam 50/1'::text, 'Gam 50/1 Pei'::text, 'Gamuza Winter'::text])) THEN 'Gam 50/1'::text
            WHEN (i.tipo_articulo = ANY (ARRAY['J 30/1 Card'::text, 'J 30/1 Pei'::text, 'J 28/1'::text])) THEN 'J 30/1'::text
            WHEN (i.tipo_articulo = ANY (ARRAY['J 20/1 Card'::text, 'J 20/1 Pei'::text, 'J 18/1 Pei'::text])) THEN 'J 20/1'::text
            WHEN (i.tipo_articulo = 'F Alg 100%'::text) THEN 'F Alg'::text
            WHEN (i.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 C)'::text
            WHEN (i.tipo_articulo = 'J 30/1-Gam 50/1'::text) THEN 'Varios'::text
            ELSE i.tipo_articulo
        END AS articulo,
    a.hora_inicio,
    a.hora_fin,
    a.duracion,
    a.estandar
   FROM (((((((((public.produccion_tenido a
     LEFT JOIN public.partida b ON ((a.partida_id = b.id)))
     LEFT JOIN public.color_x_cliente c ON ((b.color_x_cliente_id = c.id)))
     LEFT JOIN public.color d ON ((c.color_id = d.id)))
     LEFT JOIN public.previo e ON ((b.previo_id = e.id)))
     LEFT JOIN public.cliente f ON ((b.cliente_id = f.id)))
     LEFT JOIN public.articulo g ON ((b.articulo_id = g.id)))
     LEFT JOIN public.tenido h ON ((b.tenido_id = h.id)))
     LEFT JOIN public.tipo_articulo i ON ((g.tipo_articulo_id = i.id)))
     LEFT JOIN public.valor j ON ((c.valor_id = j.id)))
  WHERE (a.fecha >= '2025-01-01'::date);


ALTER TABLE public.vw_produccion_tenido OWNER TO postgres;

--
-- Name: vw_programa_tenido_ultimo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_programa_tenido_ultimo AS
 WITH ultima_fecha AS (
         SELECT max(programa_tenido.fecha) AS fecha
           FROM public.programa_tenido
        ), extras AS (
         SELECT pxe.partida_id AS fk_partida,
            string_agg((ex_1.cod_extra)::text, '+'::text) AS extras,
            COALESCE((sum(pxe.cantidad))::numeric, (0)::numeric) AS cant_extra,
            COALESCE(sum(pxe.peso), (0)::numeric) AS peso_extra
           FROM (public.partida_x_extra pxe
             JOIN public.extra ex_1 ON ((pxe.extra_id = ex_1.id)))
          GROUP BY pxe.partida_id
        ), prog AS (
         SELECT p.id AS pk_programa,
            p.fecha,
            p.maquina_id AS fk_maquina,
            p.orden,
            p.partida_id AS fk_partida,
            p.tipo_lavado_mq_id AS fk_tipo_lavado_mq,
            p.tipo_receta_id AS fk_tipo_receta,
            p.fyh_cre,
            p.fyh_cre_tz
           FROM (public.programa_tenido p
             JOIN ultima_fecha u ON ((p.fecha = u.fecha)))
        ), primera_partida AS (
         SELECT partida.id AS pk_partida,
            row_number() OVER (PARTITION BY partida.color_x_cliente_id, partida.cliente_id ORDER BY partida.id) AS orden
           FROM public.partida
        )
 SELECT prog.pk_programa AS programa_id,
    prog.fecha,
    prog.orden,
    prog.fk_maquina AS maquina_id,
    pa.id AS partida_id,
    cl.cliente,
    co.color,
    te.tenido,
    ar.articulo,
    val.valor,
    (
        CASE
            WHEN (obs.partida IS NOT NULL) THEN obs.rollos
            ELSE (pa.rollos)::integer
        END)::smallint AS rollos,
    (
        CASE
            WHEN ((obs.rollos IS NOT NULL) AND (pa.rollos <> obs.rollos)) THEN 0
            ELSE (COALESCE((pa.rib)::integer, 0) + (COALESCE(ex.cant_extra, (0)::numeric))::integer)
        END)::smallint AS rib,
        CASE
            WHEN (prog.fk_partida IS NOT NULL) THEN tr.tipo_receta
            ELSE tl.tipo_lavado_mq
        END AS tipo,
        CASE
            WHEN (partrecet.partida_id IS NOT NULL) THEN concat(pa.id, 'R')
            WHEN ((pa.peso_rollos IS NOT NULL) AND (pa.peso_rollos > (0)::double precision)) THEN concat(pa.id, 'P')
            ELSE concat(pa.id)
        END AS partida2,
        CASE
            WHEN (pa.id IS NULL) THEN NULL::text
            ELSE concat(
            CASE
                WHEN (pa.ancho IS NOT NULL) THEN concat('A:', pa.ancho)
                ELSE ''::text
            END,
            CASE
                WHEN ((pa.rendimiento IS NOT NULL) AND ((pa.rendimiento)::text <> '0'::text)) THEN concat('/R:', pa.rendimiento)
                ELSE ''::text
            END,
            CASE
                WHEN (pa.fibra IS NOT NULL) THEN concat('/', pa.fibra, 'F')
                ELSE ''::text
            END,
            CASE
                WHEN ((pa.adicional_id IS NOT NULL) AND (pa.articulo_id <> ALL (ARRAY[2, 39, 15])) AND (pa.cliente_id <> 88)) THEN '/V.Tela'::text
                ELSE ''::text
            END,
            CASE
                WHEN (pripart.pk_partida IS NOT NULL) THEN concat('/', 'PRIM')
                ELSE ''::text
            END)
        END AS info
   FROM ((((((((((((((prog
     LEFT JOIN public.partida pa ON ((prog.fk_partida = pa.id)))
     LEFT JOIN public.cliente cl ON ((pa.cliente_id = cl.id)))
     LEFT JOIN public.articulo ar ON ((pa.articulo_id = ar.id)))
     LEFT JOIN public.color_x_cliente cc ON ((pa.color_x_cliente_id = cc.id)))
     LEFT JOIN public.color co ON ((cc.color_id = co.id)))
     LEFT JOIN public.tenido te ON ((pa.tenido_id = te.id)))
     LEFT JOIN public.tipo_receta tr ON ((prog.fk_tipo_receta = tr.id)))
     LEFT JOIN public.valor val ON ((cc.valor_id = val.id)))
     LEFT JOIN public.tipo_lavado_maquina tl ON ((prog.fk_tipo_lavado_mq = tl.id)))
     LEFT JOIN public.partida_x_recetas partrecet ON (((pa.id = partrecet.partida_id) AND (partrecet.tipo_receta_id = 7) AND (partrecet.flg_elm = false))))
     LEFT JOIN public.vw_observado_lab obs ON ((prog.fk_partida = obs.partida)))
     LEFT JOIN primera_partida pripart ON (((prog.fk_partida = pripart.pk_partida) AND (pripart.orden = 1))))
     LEFT JOIN extras ex ON ((prog.fk_partida = ex.fk_partida)))
     LEFT JOIN ( SELECT vw_partidas_resumen.partida
           FROM public.vw_partidas_resumen
          WHERE (vw_partidas_resumen.estado = ANY (ARRAY['Teñido'::text, 'Para Despachar'::text, 'Compactado'::text, 'Despachado'::text, 'ReTeñido'::text]))) ten ON ((pa.id = ten.partida)))
  WHERE (ten.partida IS NULL)
  ORDER BY prog.fk_maquina, prog.orden;


ALTER TABLE public.vw_programa_tenido_ultimo OWNER TO postgres;

--
-- Name: vw_receta_desarrollo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_receta_desarrollo AS
 WITH costos AS (
         SELECT a.receta_id AS fk_receta,
            sum(
                CASE
                    WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((7)::numeric * a.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                    WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                    ELSE NULL::numeric
                END) AS costo_12r,
            sum(
                CASE
                    WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((5)::numeric * a.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                    WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                    ELSE NULL::numeric
                END) AS costo
           FROM (public.receta_x_insumo a
             JOIN public.insumo b ON ((a.insumo_id = b.id)))
          GROUP BY a.receta_id
        )
 SELECT receta2.id AS receta_id,
    color.id AS fk_color,
    color.color,
    tipo_articulo.id AS fk_tipo_articulo,
    tipo_articulo.tipo_articulo,
    cliente.id AS fk_cliente,
    cliente.cliente,
    tenido.id AS fk_tenido,
    tenido.tenido,
    receta2.fibra,
    c.costo_12r,
    c.costo,
    receta2.flg_antipilling,
    tr.id AS fk_tipo_receta,
    tr.tipo_receta,
    receta2.fyh_cre
   FROM (((((((public.receta2
     JOIN public.color_x_cliente ON ((receta2.color_x_cliente_id = color_x_cliente.id)))
     JOIN public.color ON ((color.id = color_x_cliente.color_id)))
     JOIN public.cliente ON ((color_x_cliente.cliente_id = cliente.id)))
     JOIN public.tipo_articulo ON ((tipo_articulo.id = receta2.tipo_articulo_id)))
     JOIN public.tenido ON ((tenido.id = receta2.tenido_id)))
     JOIN costos c ON ((c.fk_receta = receta2.id)))
     LEFT JOIN public.tipo_receta tr ON ((tr.id = receta2.tipo_receta_id)))
  WHERE ((receta2.flg_activo = true) AND (receta2.flg_produccion = false));


ALTER TABLE public.vw_receta_desarrollo OWNER TO postgres;

--
-- Name: vw_receta_v2; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_receta_v2 AS
 WITH costos AS (
         SELECT a.receta_id AS fk_receta,
            sum(
                CASE
                    WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((7)::numeric * a.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                    WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                    ELSE NULL::numeric
                END) AS costo_12r,
            sum(
                CASE
                    WHEN (b.medida = 'g/L'::public.medida_enum) THEN ((((5)::numeric * a.cantidad) / (1000)::numeric) * b.precio_prom_kg_usd)
                    WHEN (b.medida = '%'::public.medida_enum) THEN (((((1)::numeric * a.cantidad) * (10)::numeric) / (1000)::numeric) * b.precio_prom_kg_usd)
                    ELSE NULL::numeric
                END) AS costo
           FROM (public.receta_x_insumo a
             JOIN public.insumo b ON ((a.insumo_id = b.id)))
          GROUP BY a.receta_id
        )
 SELECT receta2.id AS receta_id,
    color.id AS color_id,
    color.color,
    tipo_articulo.id AS tipo_articulo_id,
    tipo_articulo.tipo_articulo,
    cliente.id AS cliente_id,
    cliente.cliente,
    tenido.id AS tenido_id,
    tenido.tenido,
    receta2.fibra,
    c.costo_12r,
    c.costo,
    receta2.flg_antipilling,
    tr.id AS tipo_receta_id,
    tr.tipo_receta
   FROM (((((((public.receta2
     JOIN public.color_x_cliente ON ((receta2.color_x_cliente_id = color_x_cliente.id)))
     JOIN public.color ON ((color.id = color_x_cliente.color_id)))
     JOIN public.cliente ON ((color_x_cliente.cliente_id = cliente.id)))
     JOIN public.tipo_articulo ON ((tipo_articulo.id = receta2.tipo_articulo_id)))
     JOIN public.tenido ON ((tenido.id = receta2.tenido_id)))
     JOIN costos c ON ((c.fk_receta = receta2.id)))
     LEFT JOIN public.tipo_receta tr ON ((tr.id = receta2.tipo_receta_id)))
  WHERE (receta2.flg_activo = true);


ALTER TABLE public.vw_receta_v2 OWNER TO postgres;

--
-- Name: vw_recetas_precio_costo; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_recetas_precio_costo OWNER TO postgres;

--
-- Name: vw_reporte_detecciones; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_reporte_detecciones OWNER TO postgres;

--
-- Name: vw_resumen_auditorias; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_resumen_auditorias AS
 SELECT a.id,
    b.id AS partida,
    b.guia,
    a.fecha_auditoria,
    c.cliente,
    d.grupo_articulo AS tipo_articulo,
    e.color,
    b.rollos,
    b.rib,
    a.estado
   FROM ((((public.auditoria a
     LEFT JOIN public.partida b ON ((a.partida_id = b.id)))
     LEFT JOIN public.cliente c ON ((b.cliente_id = c.id)))
     LEFT JOIN public.articulo d ON ((b.articulo_id = d.id)))
     LEFT JOIN public.colores e ON ((b.color_x_cliente_id = e.id)))
  ORDER BY a.fecha_auditoria DESC;


ALTER TABLE public.vw_resumen_auditorias OWNER TO postgres;

--
-- Name: vw_salida_inventario_resumen; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_salida_inventario_resumen AS
 SELECT ei.id AS salida_inventario_id,
    ei.motivo,
    ei.estado,
    ei.fyh_solicitud,
    ei.fyh_revision,
    ei.usr_solicita,
    ei.usr_revisa,
    concat(u_solicita.first_name, ' ', u_solicita.last_name) AS nombre_solicita,
    concat(u_revisa.first_name, ' ', u_revisa.last_name) AS nombre_revisa,
    ei.observacion,
    vwpr.partida_id,
    vwpr.maquina_id,
    vwpr.nombre AS nombre_maquina,
    vwpr.receta_id,
    vwpr.cliente_id,
    vwpr.cliente,
    vwpr.color_id,
    vwpr.color,
    vwpr.tono_id,
    vwpr.tono,
    vwpr.articulo_id,
    vwpr.articulo,
    vwpr.fibra
   FROM ((((public.salida_inventario ei
     LEFT JOIN public.salida_inventario_detalle eid ON ((eid.salida_inventario_id = ei.id)))
     LEFT JOIN public.profiles u_solicita ON ((u_solicita.id_usuario = ei.usr_solicita)))
     LEFT JOIN public.profiles u_revisa ON ((u_revisa.id_usuario = ei.usr_revisa)))
     LEFT JOIN public.vw_partida_x_receta vwpr ON ((vwpr.id = ei.partida_x_recetas_id)))
  GROUP BY ei.id, ei.motivo, ei.estado, ei.fyh_solicitud, ei.fyh_revision, ei.usr_solicita, ei.usr_revisa, u_solicita.first_name, u_solicita.last_name, u_revisa.first_name, u_revisa.last_name, ei.observacion, vwpr.partida_id, vwpr.maquina_id, vwpr.nombre, vwpr.receta_id, vwpr.cliente_id, vwpr.cliente, vwpr.color_id, vwpr.color, vwpr.tono_id, vwpr.tono, vwpr.articulo_id, vwpr.articulo, vwpr.fibra;


ALTER TABLE public.vw_salida_inventario_resumen OWNER TO postgres;

--
-- Name: vw_seguimiento_entregas; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_seguimiento_entregas AS
 WITH prod_tenido AS (
         SELECT produccion_tenido.partida_id AS fk_partida,
            produccion_tenido.fecha,
            (produccion_tenido.estado)::text AS estado,
            row_number() OVER (PARTITION BY produccion_tenido.partida_id ORDER BY produccion_tenido.fecha DESC) AS orden
           FROM public.produccion_tenido
        ), motivo_retraso AS (
         SELECT r.partida_id AS fk_partida,
            r.motivo_id,
            m.motivo,
            r.observacion,
            r.fecha,
            row_number() OVER (PARTITION BY r.partida_id ORDER BY r.fecha DESC NULLS LAST, r.created_at DESC) AS orden
           FROM (public.retrasos_partida r
             JOIN public.motivos_retraso m ON ((m.id = r.motivo_id)))
        ), tmp_auditoria AS (
         SELECT auditoria.id,
            auditoria.partida_id AS fk_partida,
            auditoria.fecha_auditoria,
            auditoria.estado,
            row_number() OVER (PARTITION BY auditoria.partida_id ORDER BY auditoria.fecha_auditoria DESC) AS orden
           FROM public.auditoria
        ), programa AS (
         SELECT programacion.partida AS fk_partida,
            max(programacion.fecha_programacion) AS fecha
           FROM public.programacion
          GROUP BY programacion.partida
         HAVING (max(programacion.fecha_programacion) = CURRENT_DATE)
        UNION ALL
         SELECT programa_tenido.partida_id AS fk_partida,
            max(programa_tenido.fecha) AS fecha
           FROM public.programa_tenido
          GROUP BY programa_tenido.partida_id
         HAVING (max(programa_tenido.fecha) = CURRENT_DATE)
        )
 SELECT part.id AS partida,
    part.fecha_registro,
    part.guia,
    part.fecha_entrega,
        CASE
            WHEN (cli.cliente ~~ '%J.Ripaz%'::text) THEN 'J.Ripaz'::text
            WHEN (cli.cliente ~~ '%Rudy%'::text) THEN 'Rudy'::text
            WHEN (cli.cliente ~~ '%J.Urrutia%'::text) THEN 'J.Urrutia'::text
            WHEN (cli.cliente ~~ '%Jimmy%'::text) THEN 'Jimmy'::text
            WHEN (cli.cliente ~~ '%Oswaldo%'::text) THEN 'Oswaldo'::text
            ELSE cli.cliente
        END AS cliente,
        CASE
            WHEN (ta.tipo_articulo = ANY (ARRAY['F Lycra 30/1 Card'::text, 'F Lycra 30/1 Pei'::text])) THEN 'Full Lycra'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['Gam 50/1'::text, 'Gam 50/1 Pei'::text, 'Gamuza Winter'::text])) THEN 'Gam 50/1'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['J 30/1 Card'::text, 'J 30/1 Pei'::text, 'J 28/1'::text])) THEN 'J 30/1'::text
            WHEN (ta.tipo_articulo = ANY (ARRAY['J 20/1 Card'::text, 'J 20/1 Pei'::text, 'J 18/1 Pei'::text])) THEN 'J 20/1'::text
            WHEN (ta.tipo_articulo = 'F Alg 100%'::text) THEN 'F Alg'::text
            WHEN (ta.tipo_articulo = 'J 30/1 (2 cabos)'::text) THEN 'J 30/1 (2 C)'::text
            WHEN (ta.tipo_articulo = 'J 30/1-Gam 50/1'::text) THEN 'Varios'::text
            ELSE ta.tipo_articulo
        END AS tipo_articulo,
    concat(col.color, '-', ten.tenido) AS color,
    ten.tenido,
    part.rollos,
    part.rib,
    concat('A:', part.ancho, '/R:', part.rendimiento, '/', part.fibra, 'F') AS detalle,
        CASE
            WHEN ((obs.fecha IS NOT NULL) AND (desp.fecha_despacho >= obs.fecha)) THEN 'Despachado'::text
            WHEN ((obs.fecha > prod_ten.fecha) AND (obs.fecha IS NOT NULL)) THEN concat('Observado-', obs.fecha, '-', obs.motivo)
            WHEN ((prod_ten.fecha >= obs.fecha) AND (obs.fecha IS NOT NULL) AND (prod_ten.estado = 'Teñido'::text)) THEN 'ReTeñido'::text
            WHEN (desp.fecha_despacho IS NOT NULL) THEN 'Despachado'::text
            WHEN ((obs.fecha IS NOT NULL) AND (audit.fecha_auditoria > obs.fecha)) THEN 'Para Despachar'::text
            WHEN (audit.fecha_auditoria IS NOT NULL) THEN 'Para Despachar'::text
            WHEN ((compact.fecha >= prod_ten.fecha) AND (compact.fecha IS NOT NULL)) THEN 'Compactado'::text
            WHEN (prod_ten.fk_partida IS NOT NULL) THEN prod_ten.estado
            WHEN (progra.fk_partida IS NOT NULL) THEN 'Programado'::text
            WHEN (recet.id IS NULL) THEN 'Pendiente Receta'::text
            WHEN ((termo.fk_partida IS NULL) AND (part.articulo_id = ANY (ARRAY[6, 22, 32, 33]))) THEN 'Pendiente Termofijar'::text
            WHEN ((termo.fk_partida IS NOT NULL) AND (part.articulo_id = ANY (ARRAY[6, 22, 32, 33]))) THEN 'Para Programar'::text
            ELSE 'Para Programar'::text
        END AS estado,
        CASE
            WHEN ((obs.fecha IS NOT NULL) AND (desp.fecha_despacho >= obs.fecha)) THEN desp.fecha_despacho
            WHEN ((obs.fecha > prod_ten.fecha) AND (obs.fecha IS NOT NULL)) THEN obs.fecha
            WHEN ((prod_ten.fecha >= obs.fecha) AND (obs.fecha IS NOT NULL) AND (prod_ten.estado = 'Teñido'::text)) THEN prod_ten.fecha
            WHEN (desp.fecha_despacho IS NOT NULL) THEN desp.fecha_despacho
            WHEN ((obs.fecha IS NOT NULL) AND (audit.fecha_auditoria > obs.fecha)) THEN audit.fecha_auditoria
            WHEN (audit.fecha_auditoria IS NOT NULL) THEN audit.fecha_auditoria
            WHEN ((compact.fecha >= prod_ten.fecha) AND (compact.fecha IS NOT NULL)) THEN compact.fecha
            WHEN (prod_ten.fk_partida IS NOT NULL) THEN prod_ten.fecha
            WHEN (termo.fk_partida IS NOT NULL) THEN termo.fecha
            WHEN (progra.fk_partida IS NOT NULL) THEN progra.fecha
            ELSE NULL::date
        END AS fecha_estado,
        CASE
            WHEN ((obs.fecha IS NULL) AND ((audit.fecha_auditoria <= part.fecha_entrega) OR (desp.fecha_despacho <= part.fecha_entrega) OR (compact.fecha <= part.fecha_entrega))) THEN 1
            WHEN ((obs.fecha IS NOT NULL) AND (((audit.fecha_auditoria > obs.fecha) AND (audit.fecha_auditoria <= part.fecha_entrega)) OR ((desp.fecha_despacho > obs.fecha) AND (desp.fecha_despacho <= part.fecha_entrega)) OR ((compact.fecha > obs.fecha) AND (compact.fecha <= part.fecha_entrega)))) THEN 1
            ELSE 0
        END AS flg_listo,
    round(((100.0 * (sum(
        CASE
            WHEN ((obs.fecha IS NULL) AND ((audit.fecha_auditoria <= part.fecha_entrega) OR (desp.fecha_despacho <= part.fecha_entrega) OR (compact.fecha <= part.fecha_entrega))) THEN 1
            WHEN ((obs.fecha IS NOT NULL) AND (((audit.fecha_auditoria > obs.fecha) AND (audit.fecha_auditoria <= part.fecha_entrega)) OR ((desp.fecha_despacho > obs.fecha) AND (desp.fecha_despacho <= part.fecha_entrega)) OR ((compact.fecha > obs.fecha) AND (compact.fecha <= part.fecha_entrega)))) THEN 1
            ELSE 0
        END) OVER (PARTITION BY part.fecha_entrega, cli.cliente))::numeric) / (NULLIF(count(*) OVER (PARTITION BY part.fecha_entrega, cli.cliente), 0))::numeric), 0) AS pct_cumplimiento,
    round(((100.0 * (sum(
        CASE
            WHEN ((part.fecha_entrega <= CURRENT_DATE) AND (((obs.fecha IS NULL) AND ((audit.fecha_auditoria <= part.fecha_entrega) OR (desp.fecha_despacho <= part.fecha_entrega) OR (compact.fecha <= part.fecha_entrega))) OR ((obs.fecha IS NOT NULL) AND (((audit.fecha_auditoria > obs.fecha) AND (audit.fecha_auditoria <= part.fecha_entrega)) OR ((desp.fecha_despacho > obs.fecha) AND (desp.fecha_despacho <= part.fecha_entrega)) OR ((compact.fecha > obs.fecha) AND (compact.fecha <= part.fecha_entrega)))))) THEN 1
            ELSE 0
        END) OVER (PARTITION BY (date_trunc('month'::text, (part.fecha_entrega)::timestamp with time zone))))::numeric) / (NULLIF(sum(
        CASE
            WHEN (part.fecha_entrega <= CURRENT_DATE) THEN 1
            ELSE 0
        END) OVER (PARTITION BY (date_trunc('month'::text, (part.fecha_entrega)::timestamp with time zone))), 0))::numeric), 1) AS pct_cumplimiento_mes,
        CASE
            WHEN (sum(
            CASE
                WHEN (((obs.fecha IS NULL) AND ((audit.fecha_auditoria IS NOT NULL) OR (desp.fecha_despacho IS NOT NULL) OR (compact.fecha IS NOT NULL))) OR ((obs.fecha IS NOT NULL) AND ((audit.fecha_auditoria > obs.fecha) OR (desp.fecha_despacho > obs.fecha) OR (compact.fecha > obs.fecha)))) THEN 1
                ELSE 0
            END) OVER (PARTITION BY part.fecha_entrega, cli.cliente) = count(*) OVER (PARTITION BY part.fecha_entrega, cli.cliente)) THEN 'Completo'::text
            WHEN (sum(
            CASE
                WHEN (((obs.fecha IS NULL) AND ((audit.fecha_auditoria IS NOT NULL) OR (desp.fecha_despacho IS NOT NULL) OR (compact.fecha IS NOT NULL))) OR ((obs.fecha IS NOT NULL) AND ((audit.fecha_auditoria > obs.fecha) OR (desp.fecha_despacho > obs.fecha) OR (compact.fecha > obs.fecha)))) THEN 1
                ELSE 0
            END) OVER (PARTITION BY part.fecha_entrega, cli.cliente) > 0) THEN 'Parcial'::text
            ELSE 'Pendiente'::text
        END AS flg_entregado,
    (
        CASE
            WHEN (((obs.fecha IS NULL) AND ((audit.fecha_auditoria IS NOT NULL) OR (desp.fecha_despacho IS NOT NULL) OR (compact.fecha IS NOT NULL))) OR ((obs.fecha IS NOT NULL) AND ((audit.fecha_auditoria > obs.fecha) OR (desp.fecha_despacho > obs.fecha) OR (compact.fecha > obs.fecha)))) THEN COALESCE(compact.fecha, COALESCE(audit.fecha_auditoria, desp.fecha_despacho))
            ELSE CURRENT_DATE
        END - part.fecha_registro) AS dias_entrega,
    (
        CASE
            WHEN (((obs.fecha IS NULL) AND ((audit.fecha_auditoria IS NOT NULL) OR (desp.fecha_despacho IS NOT NULL) OR (compact.fecha IS NOT NULL))) OR ((obs.fecha IS NOT NULL) AND ((audit.fecha_auditoria > obs.fecha) OR (desp.fecha_despacho > obs.fecha) OR (compact.fecha > obs.fecha)))) THEN COALESCE(compact.fecha, COALESCE(audit.fecha_auditoria, desp.fecha_despacho))
            ELSE CURRENT_DATE
        END - part.fecha_entrega) AS dias_desfase_entrega,
    mr.motivo AS motivo_retraso,
    mr.observacion AS obs_retraso
   FROM ((((((((((((((((public.partida part
     LEFT JOIN public.cliente cli ON ((cli.id = part.cliente_id)))
     LEFT JOIN public.articulo art ON ((art.id = part.articulo_id)))
     LEFT JOIN public.colores col ON ((col.id = part.color_x_cliente_id)))
     LEFT JOIN public.tenido ten ON ((ten.id = part.tenido_id)))
     LEFT JOIN public.tipo_articulo ta ON ((art.tipo_articulo_id = ta.id)))
     LEFT JOIN ( SELECT despacho.partida_id AS fk_partida,
            max(despacho.fecha_despacho) AS fecha_despacho,
            sum(despacho.rollos) AS rollos
           FROM public.despacho
          GROUP BY despacho.partida_id) desp ON ((part.id = desp.fk_partida)))
     LEFT JOIN prod_tenido prod_ten ON (((part.id = prod_ten.fk_partida) AND (prod_ten.orden = 1))))
     LEFT JOIN ( SELECT programa.fk_partida,
            max(programa.fecha) AS fecha
           FROM programa
          GROUP BY programa.fk_partida
         HAVING (max(programa.fecha) = CURRENT_DATE)) progra ON ((part.id = progra.fk_partida)))
     LEFT JOIN public.vw_observado_lab obs ON ((part.id = obs.partida)))
     LEFT JOIN ( SELECT compactado.partida_id AS fk_partida,
            max(compactado.fecha) AS fecha
           FROM public.compactado
          GROUP BY compactado.partida_id
         HAVING (sum(compactado.rollos) > 0)) compact ON ((part.id = compact.fk_partida)))
     LEFT JOIN ( SELECT termofijado.partida_id AS fk_partida,
            max(termofijado.fecha) AS fecha
           FROM public.termofijado
          GROUP BY termofijado.partida_id) termo ON ((part.id = termo.fk_partida)))
     LEFT JOIN public.receta2 recet ON (((part.color_x_cliente_id = recet.color_x_cliente_id) AND (art.tipo_articulo_id = recet.tipo_articulo_id) AND (part.fibra = recet.fibra) AND (part.tenido_id = recet.tenido_id) AND (recet.flg_antipilling =
        CASE
            WHEN (part.adicional_id = 1) THEN true
            ELSE false
        END) AND (recet.flg_activo = true) AND (recet.tipo_receta_id = 7))))
     LEFT JOIN public.partida_x_recetas partrecet ON (((part.id = partrecet.partida_id) AND (partrecet.tipo_receta_id = 7) AND (partrecet.flg_elm = false))))
     LEFT JOIN public.color_x_cliente val ON ((col.id = val.id)))
     LEFT JOIN tmp_auditoria audit ON (((part.id = audit.fk_partida) AND (audit.orden = 1) AND (audit.estado = 'OK'::text))))
     LEFT JOIN motivo_retraso mr ON (((part.id = mr.fk_partida) AND (mr.orden = 1))))
  WHERE ((part.id > 0) AND (part.fecha_entrega >= '2025-02-01'::date))
  ORDER BY part.id;


ALTER TABLE public.vw_seguimiento_entregas OWNER TO postgres;

--
-- Name: vw_tipo_insumo_x_mes; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_tipo_insumo_x_mes OWNER TO postgres;

--
-- Name: vw_tipo_pago; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_tipo_pago AS
 SELECT unnest(enum_range(NULL::public.tipo_pago_enum)) AS valor;


ALTER TABLE public.vw_tipo_pago OWNER TO postgres;

--
-- Name: vw_tonos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_tonos AS
 SELECT cliente.id AS cliente_id,
    cliente.cliente AS tono
   FROM public.cliente;


ALTER TABLE public.vw_tonos OWNER TO postgres;

--
-- Name: vw_ultimo_precio_insumo_proveedor; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER TABLE public.vw_ultimo_precio_insumo_proveedor OWNER TO postgres;

--
-- Name: vw_union_programa_tenido; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_union_programa_tenido AS
 WITH "datos_teñido" AS (
         SELECT pt.maquina_id AS fk_maquina,
            pt.orden,
            'Partida'::text AS tipo_registro,
            (pa.id)::text AS pk_partida,
            co.color,
            te.tenido,
            val.valor,
            ad.adicional,
                CASE
                    WHEN (pa.peso_rollos IS NULL) THEN (((pa.rollos * 21) + (pa.rib * 12)))::numeric
                    ELSE ((pa.peso_rollos + pa.peso_rib))::numeric
                END AS kilos,
            te_std.duracion,
            tr.tipo_receta
           FROM ((((((((public.programa_tenido pt
             JOIN public.partida pa ON ((pt.partida_id = pa.id)))
             LEFT JOIN public.color_x_cliente cxc ON ((pa.color_x_cliente_id = cxc.id)))
             LEFT JOIN public.color co ON ((cxc.color_id = co.id)))
             LEFT JOIN public.tenido te ON ((pa.tenido_id = te.id)))
             LEFT JOIN public.valor val ON ((cxc.valor_id = val.id)))
             LEFT JOIN public.adicional ad ON ((pa.adicional_id = ad.id)))
             LEFT JOIN public.tipo_receta tr ON ((pt.tipo_receta_id = tr.id)))
             LEFT JOIN public.tiempos_estandar_tenido te_std ON (((te_std.tipo_receta_id = pt.tipo_receta_id) AND (te_std.valor_id = val.id) AND (((pt.tipo_receta_id = ANY (ARRAY[4, 7, 14])) AND (te_std.tenido_id = te.id) AND (COALESCE((te_std.adicional_id)::integer, 0) = COALESCE((pa.adicional_id)::integer, 0))) OR (pt.tipo_receta_id <> ALL (ARRAY[4, 7, 14]))))))
          WHERE (pt.fecha = CURRENT_DATE)
        ), datos_lavado AS (
         SELECT pt.maquina_id AS fk_maquina,
            pt.orden,
            'Lavado'::text AS tipo_registro,
            NULL::text AS pk_partida,
            NULL::text AS color,
            NULL::text AS tenido,
            NULL::text AS valor,
            NULL::text AS adicional,
            NULL::numeric AS kilos,
            lstd.duracion,
            tl.tipo_lavado_mq
           FROM ((public.programa_tenido pt
             JOIN public.tipo_lavado_maquina tl ON ((pt.tipo_lavado_mq_id = tl.id)))
             LEFT JOIN public.tiempos_estandar_lavado lstd ON ((lstd.tipo_lavado_mq_id = pt.tipo_lavado_mq_id)))
          WHERE (pt.fecha = CURRENT_DATE)
        ), en_partida AS (
         SELECT pt.maquina_id AS fk_maquina,
            pt.orden,
            'Partida'::text AS tipo_registro,
            (pa.id)::text AS pk_partida,
            co.color,
            te.tenido,
            val.valor,
            ad.adicional,
            ((((pa.peso_rollos + pa.peso_rib))::numeric)::double precision - p.kilos) AS kilos,
            GREATEST('00:00:00'::interval, ((p.estandar)::interval - (p.duracion)::interval)) AS duracion,
            p.tipo
           FROM (((((((public.produccion_tenido p
             JOIN public.programa_tenido pt ON ((pt.partida_id = p.partida_id)))
             JOIN public.partida pa ON ((pa.id = p.partida_id)))
             LEFT JOIN public.color_x_cliente cxc ON ((pa.color_x_cliente_id = cxc.id)))
             LEFT JOIN public.color co ON ((cxc.color_id = co.id)))
             LEFT JOIN public.tenido te ON ((pa.tenido_id = te.id)))
             LEFT JOIN public.valor val ON ((cxc.valor_id = val.id)))
             LEFT JOIN public.adicional ad ON ((pa.adicional_id = ad.id)))
          WHERE (((p.estado)::text = 'En partida Teñido'::text) AND (pt.fecha = CURRENT_DATE) AND ((p.fecha >= (CURRENT_DATE - 1)) AND (p.fecha <= CURRENT_DATE)))
        )
 SELECT "datos_teñido".fk_maquina AS maquina_id,
    "datos_teñido".orden,
    "datos_teñido".tipo_registro,
    "datos_teñido".pk_partida AS partida_id,
    "datos_teñido".color,
    "datos_teñido".tenido,
    "datos_teñido".valor,
    "datos_teñido".adicional,
    "datos_teñido".kilos,
    "datos_teñido".duracion,
    "datos_teñido".tipo_receta
   FROM "datos_teñido"
  WHERE (NOT ("datos_teñido".pk_partida IN ( SELECT en_partida.pk_partida
           FROM en_partida)))
UNION ALL
 SELECT datos_lavado.fk_maquina AS maquina_id,
    datos_lavado.orden,
    datos_lavado.tipo_registro,
    datos_lavado.pk_partida AS partida_id,
    datos_lavado.color,
    datos_lavado.tenido,
    datos_lavado.valor,
    datos_lavado.adicional,
    datos_lavado.kilos,
    datos_lavado.duracion,
    datos_lavado.tipo_lavado_mq AS tipo_receta
   FROM datos_lavado
UNION ALL
 SELECT en_partida.fk_maquina AS maquina_id,
    en_partida.orden,
    en_partida.tipo_registro,
    en_partida.pk_partida AS partida_id,
    en_partida.color,
    en_partida.tenido,
    en_partida.valor,
    en_partida.adicional,
    en_partida.kilos,
    en_partida.duracion,
    en_partida.tipo AS tipo_receta
   FROM en_partida;


ALTER TABLE public.vw_union_programa_tenido OWNER TO postgres;

--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: supabase_realtime_admin
--
-- =====================================================================
-- SIG-TEC | Replicación Nivel 1 (campus -> central) - SUSCRIPCIÓN
-- Se ejecuta en el CENTRAL, una vez por campus, conectado como postgres.
-- Variables psql: :esquema (campus), :repl_pass (clave de replicador)
--
-- "replicador" solo aparece en la cadena CONNECTION: es quien lee en el
-- publicador. El dueño de la suscripción (postgres) aplica los cambios.
--
-- Idempotente: si la suscripción ya existe, no hace nada. Si no existe, se
-- vacía antes la réplica de ese esquema para que copy_data no choque con
-- filas viejas. El central no es dueño de ningún esquema.
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF sig.fn_esquema_local() IS NOT NULL THEN
    RAISE EXCEPTION 'Este script solo se ejecuta en el nodo central';
  END IF;
END $$;

SELECT format('TRUNCATE %s', string_agg(format('%I.%I', schemaname, tablename), ', '))
FROM pg_tables
WHERE schemaname = :'esquema'
  AND NOT EXISTS (SELECT 1 FROM pg_subscription WHERE subname = 'sub_central_' || :'esquema')
HAVING count(*) > 0
\gexec

SELECT format(
         'CREATE SUBSCRIPTION %I CONNECTION %L PUBLICATION %I WITH (copy_data = true)',
         'sub_central_' || :'esquema',
         format('host=%s port=5432 dbname=%s user=replicador password=''%s''',
                'pg-' || :'esquema', current_database(),
                replace(replace(:'repl_pass', '\', '\\'), '''', '\''')),
         'pub_' || :'esquema')
WHERE NOT EXISTS (SELECT 1 FROM pg_subscription WHERE subname = 'sub_central_' || :'esquema')
\gexec

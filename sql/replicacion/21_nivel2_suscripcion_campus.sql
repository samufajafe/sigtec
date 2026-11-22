-- =====================================================================
-- SIG-TEC | Replicación Nivel 2 (central -> campus) - SUSCRIPCIÓN
-- Se ejecuta en CADA campus, conectado como postgres.
-- Variable psql: :repl_pass (clave de replicador)
--
-- Una sola suscripción, sub_<campus>_global, con las 4 pub_global_* de los
-- OTROS campus. Nunca incluye el esquema propio, y por eso no hay ciclos.
--
-- origin = any es obligatorio: las filas que reenvía el central llegaron
-- por el Nivel 1, así que tienen origen remoto. Con origin = none el
-- central no las enviaría.
--
-- Idempotente: si la suscripción ya existe, no hace nada. Si no existe, se
-- vacían antes las 4 réplicas. El esquema propio queda excluido del TRUNCATE.
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF sig.fn_esquema_local() IS NULL THEN
    RAISE EXCEPTION 'Este script solo se ejecuta en un nodo de campus';
  END IF;
END $$;

SELECT format('TRUNCATE %s', string_agg(format('%I.%I', t.schemaname, t.tablename), ', '))
FROM pg_tables t
JOIN sig.campus c ON c.codigo = t.schemaname
WHERE c.codigo <> sig.fn_esquema_local()
  AND NOT EXISTS (SELECT 1 FROM pg_subscription
                  WHERE subname = 'sub_' || sig.fn_esquema_local() || '_global')
HAVING count(*) > 0
\gexec

SELECT format(
         'CREATE SUBSCRIPTION %I CONNECTION %L PUBLICATION %s WITH (copy_data = true, origin = any)',
         'sub_' || l.e || '_global',
         format('host=pg-central port=5432 dbname=%s user=replicador password=''%s''',
                current_database(),
                replace(replace(:'repl_pass', '\', '\\'), '''', '\''')),
         (SELECT string_agg(quote_ident('pub_global_' || codigo), ', ' ORDER BY campus_id)
          FROM sig.campus WHERE codigo <> l.e))
FROM sig.fn_esquema_local() AS l(e)
WHERE NOT EXISTS (SELECT 1 FROM pg_subscription WHERE subname = 'sub_' || l.e || '_global')
\gexec

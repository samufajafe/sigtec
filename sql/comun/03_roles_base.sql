-- =====================================================================
-- SIG-TEC | 03 - Roles base (todos los nodos)
--   replicador      : usuario de las suscripciones lógicas y de pg_basebackup
--   sigtec_lectura  : grupo que puede consultar todas las capas
--   sigtec_editor   : grupo que además puede editar (vía vistas) su campus
-- Variable psql: :repl_pass
-- =====================================================================
CREATE ROLE replicador WITH LOGIN REPLICATION PASSWORD :'repl_pass';
COMMENT ON ROLE replicador IS 'SIG-TEC: replicación lógica entre nodos y respaldos físicos';

CREATE ROLE sigtec_lectura NOLOGIN;
CREATE ROLE sigtec_editor  NOLOGIN IN ROLE sigtec_lectura;

GRANT USAGE ON SCHEMA sig, capas TO sigtec_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA sig TO sigtec_lectura;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sig TO sigtec_lectura;

-- El replicador necesita leer el catálogo (copias iniciales de suscripción)
GRANT USAGE ON SCHEMA sig TO replicador;
GRANT SELECT ON ALL TABLES IN SCHEMA sig TO replicador;

-- Permite que replicador cree publicaciones/suscripciones en la BD
-- (las suscripciones en PG16 requieren superusuario o pg_create_subscription)
GRANT pg_create_subscription TO replicador;
SELECT format('GRANT CREATE ON DATABASE %I TO replicador', current_database()) \gexec

-- Permisos de concesión de acceso por esquema de campus
CREATE OR REPLACE FUNCTION sig.fn_otorgar_permisos_esquema(p_esquema text, p_es_local boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO sigtec_lectura, replicador', p_esquema);
  EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO sigtec_lectura, replicador', p_esquema);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO sigtec_lectura, replicador', p_esquema);
  -- Nota: la edición de los usuarios se hace por las vistas del esquema
  -- "capas" (disparadores INSTEAD OF). Aquí NO se da INSERT/UPDATE/DELETE
  -- directo sobre las tablas físicas a los usuarios finales.
  IF p_es_local THEN
    EXECUTE format('GRANT USAGE ON ALL SEQUENCES IN SCHEMA %I TO sigtec_editor', p_esquema);
  END IF;
END $$;

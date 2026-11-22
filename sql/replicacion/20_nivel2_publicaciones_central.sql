-- =====================================================================
-- SIG-TEC | Replicación Nivel 2 (central -> campus) - PUBLICACIONES
-- Se ejecuta en el CENTRAL, conectado como postgres.
-- Crea pub_global_<campus> para cada uno de los 5 esquemas.
-- Idempotente: solo crea las que falten.
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF sig.fn_esquema_local() IS NOT NULL THEN
    RAISE EXCEPTION 'Este script solo se ejecuta en el nodo central';
  END IF;
END $$;

SELECT format('CREATE PUBLICATION %I FOR TABLES IN SCHEMA %I', 'pub_global_' || codigo, codigo)
FROM sig.campus
WHERE NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'pub_global_' || codigo)
ORDER BY campus_id
\gexec

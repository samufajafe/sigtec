-- =====================================================================
-- SIG-TEC | Replicación Nivel 1 (campus -> central) - PUBLICACIÓN
-- Se ejecuta en CADA nodo de campus, conectado como postgres.
-- Publica únicamente el esquema propio del nodo: pub_<campus>.
-- Idempotente: si la publicación ya existe, no hace nada.
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF sig.fn_esquema_local() IS NULL THEN
    RAISE EXCEPTION 'Este script solo se ejecuta en un nodo de campus';
  END IF;
END $$;

SELECT format('CREATE PUBLICATION %I FOR TABLES IN SCHEMA %I', 'pub_' || e, e)
FROM sig.fn_esquema_local() AS e
WHERE NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'pub_' || e)
\gexec

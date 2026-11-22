-- =====================================================================
-- SIG-TEC | Desmontaje - SUSCRIPCIONES de este nodo
-- DROP SUBSCRIPTION también elimina el slot en el publicador, por lo que
-- ambos nodos deben estar arriba. Solo toca las suscripciones de SIG-TEC.
-- =====================================================================
\set ON_ERROR_STOP on

SELECT format('DROP SUBSCRIPTION %I', subname)
FROM pg_subscription
WHERE subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND (subname LIKE 'sub\_central\_%' OR subname LIKE 'sub\_%\_global')
ORDER BY subname
\gexec

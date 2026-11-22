-- =====================================================================
-- SIG-TEC | Desmontaje - SUSCRIPCIONES de este nodo
--
-- Se desasocia el slot antes del DROP. Un DROP SUBSCRIPTION normal intenta
-- borrar el slot en el publicador y FALLA si ya no existe, que es lo que
-- ocurre al restaurar un nodo con PITR (los respaldos no incluyen slots).
-- Los slots que queden en los publicadores los elimina
-- 91_desmontar_publicaciones.sql. Solo toca suscripciones de SIG-TEC.
-- =====================================================================
\set ON_ERROR_STOP on

SELECT format('ALTER SUBSCRIPTION %I DISABLE', subname),
       format('ALTER SUBSCRIPTION %I SET (slot_name = NONE)', subname),
       format('DROP SUBSCRIPTION %I', subname)
FROM pg_subscription
WHERE subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND (subname LIKE 'sub\_central\_%' OR subname LIKE 'sub\_%\_global')
ORDER BY subname
\gexec

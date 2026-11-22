-- =====================================================================
-- SIG-TEC | Desmontaje - PUBLICACIONES y slots huérfanos de este nodo
-- Ejecutar después de eliminar las suscripciones de todos los nodos.
-- Solo elimina slots inactivos con nombres de SIG-TEC.
-- =====================================================================
\set ON_ERROR_STOP on

SELECT format('DROP PUBLICATION %I', pubname)
FROM pg_publication
WHERE pubname LIKE 'pub\_%'
ORDER BY pubname
\gexec

SELECT pg_drop_replication_slot(slot_name)
FROM pg_replication_slots
WHERE NOT active
  AND slot_type = 'logical'
  AND database = current_database()
  AND (slot_name LIKE 'sub\_central\_%' OR slot_name LIKE 'sub\_%\_global');

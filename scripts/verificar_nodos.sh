#!/usr/bin/env bash
# =====================================================================
# Verifica el estado de los 6 nodos: disponibilidad, identidad del nodo
# y cantidad de registros por esquema en la capa edificios.
# Cuando la replicación esté configurada, cada nodo debe ver los
# edificios de los 5 campus (3 por campus con los datos de ejemplo).
# =====================================================================
PGUSER=${PG_SUPERUSER:-postgres}
DB=${SIGTEC_DB:-sigtec}

for n in central cartago sanjose sancarlos alajuela limon; do
  c="pg-$n"
  printf '\n==== %s ====\n' "$c"
  if ! docker exec "$c" pg_isready -q -U "$PGUSER" -d "$DB"; then
    echo "  NO DISPONIBLE"; continue
  fi
  docker exec "$c" psql -U "$PGUSER" -d "$DB" -tA -F ' | ' -c "
    SELECT 'nodo', tipo, coalesce(campus_id::text, '-') FROM sig.nodo_local;" -c "
    SELECT 'edificios', 'cartago', count(*) FROM cartago.edificios UNION ALL
    SELECT 'edificios', 'sanjose', count(*) FROM sanjose.edificios UNION ALL
    SELECT 'edificios', 'sancarlos', count(*) FROM sancarlos.edificios UNION ALL
    SELECT 'edificios', 'alajuela', count(*) FROM alajuela.edificios UNION ALL
    SELECT 'edificios', 'limon', count(*) FROM limon.edificios;" -c "
    SELECT 'wal_level', setting, '' FROM pg_settings WHERE name = 'wal_level';"
done

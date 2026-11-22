#!/usr/bin/env bash
# =====================================================================
# SIG-TEC - Distribución de estilos (layer_styles) central -> campus.
#
#   central : tabla layer_styles + funciones de versión + publicación pub_estilos
#   campus  : tabla layer_styles + suscripción sub_<campus>_estilos al central
#
# Idempotente: se puede correr varias veces. Crea las suscripciones como
# postgres; replicador solo va en la cadena CONNECTION (conexión y copia
# inicial en el central). Correr una vez después de "docker compose up -d".
#
# Uso: ./scripts/configurar_estilos.sh
# =====================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas /sigtec/...

PGUSER=${PG_SUPERUSER:-postgres}
DB=${SIGTEC_DB:-sigtec}
SQL=/sigtec/sql/estilos
CAMPUS=(cartago sanjose sancarlos alajuela limon)

psql_nodo() {
  local nodo=$1; shift
  docker exec -i "pg-$nodo" psql -v ON_ERROR_STOP=1 -q -X -U "$PGUSER" -d "$DB" "$@"
}

echo ">> central: layer_styles, versiones y publicación pub_estilos"
psql_nodo central -f "$SQL/01_layer_styles.sql"
psql_nodo central -f "$SQL/02_versiones.sql"
psql_nodo central -f "$SQL/03_publicacion_central.sql"

for c in "${CAMPUS[@]}"; do
  echo ">> $c: layer_styles y suscripción sub_${c}_estilos"
  psql_nodo "$c" -f "$SQL/01_layer_styles.sql"
  psql_nodo "$c" -f "$SQL/02_versiones.sql"
  psql_nodo "$c" -v sub="sub_${c}_estilos" <<'SQL'
\getenv repl_pass SIGTEC_REPL_PASSWORD
SELECT format('CREATE SUBSCRIPTION %I CONNECTION %L PUBLICATION pub_estilos',
              :'sub',
              format('host=pg-central port=5432 dbname=%s user=replicador password=%s',
                     current_database(), :'repl_pass'))
WHERE NOT EXISTS (SELECT 1 FROM pg_subscription WHERE subname = :'sub')
\gexec
SQL
done

echo ">> Estado de las suscripciones de estilos:"
for c in "${CAMPUS[@]}"; do
  docker exec "pg-$c" psql -X -U "$PGUSER" -d "$DB" -tA -F ' | ' -c "
    SELECT '$c', s.subname, s.subenabled, coalesce(st.latest_end_time::text, 'sin datos aún')
    FROM pg_subscription s LEFT JOIN pg_stat_subscription st ON st.subid = s.oid
    WHERE s.subname = 'sub_${c}_estilos';"
done

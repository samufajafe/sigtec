#!/usr/bin/env bash
# =====================================================================
# TEMPORAL - crea (o con --quitar, borra) las vistas capas.* de prueba en
# los 5 nodos de campus. Ver vistas_temporales.sql.
# Uso: ./plugin/dev/aplicar_vistas_temporales.sh [--quitar]
# =====================================================================
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVO="$DIR/vistas_temporales.sql"
[[ "${1:-}" == "--quitar" ]] && ARCHIVO="$DIR/quitar_vistas_temporales.sql"

for c in cartago sanjose sancarlos alajuela limon; do
  echo ">> pg-$c: $(basename "$ARCHIVO")"
  docker exec -i "pg-$c" psql -X -q -v ON_ERROR_STOP=1 -U "${PG_SUPERUSER:-postgres}" \
    -d "${SIGTEC_DB:-sigtec}" < "$ARCHIVO"
done

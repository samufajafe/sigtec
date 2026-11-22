#!/usr/bin/env bash
# =====================================================================
# SIG-TEC - Publica (o actualiza) los estilos de las capas en el central.
#
# Lee plugin/sigtec/estilos/<capa>.qml (y .sld si existe) y llama a
# sig.fn_publicar_estilo en pg-central, que crea la versión siguiente
# ('<capa> vN') y la deja vigente. Si el QML no cambió, no crea versión.
# Con la suscripción sub_<campus>_estilos activa, llega sola a los campus.
#
# Uso: ./scripts/publicar_estilos.sh [-m "descripción del cambio"] [capa ...]
#   sin capas: publica las 8 de sig.capa
#   ej.: ./scripts/publicar_estilos.sh -m "Edificios: colores por uso" edificios
#
# Volver a una versión anterior (en el central):
#   docker exec pg-central psql -U postgres -d sigtec -c "SELECT sig.fn_activar_estilo('edificios', 1)"
# =====================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas /tmp/...

PGUSER=${PG_SUPERUSER:-postgres}
DB=${SIGTEC_DB:-sigtec}
DIR_ESTILOS="$(cd "$(dirname "$0")/.." && pwd)/plugin/sigtec/estilos"
TMP=/tmp/sigtec_estilos
DESCRIPCION=""

while getopts "m:h" opt; do
  case $opt in
    m) DESCRIPCION=$OPTARG ;;
    *) sed -n '2,16p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -gt 0 ]]; then
  CAPAS=("$@")
else
  mapfile -t CAPAS < <(docker exec pg-central psql -X -U "$PGUSER" -d "$DB" -tA \
                         -c "SELECT capa_codigo FROM sig.capa ORDER BY orden" | tr -d '\r')
fi

docker exec -u postgres pg-central mkdir -p "$TMP"
trap 'docker exec -u postgres pg-central rm -rf "$TMP" >/dev/null 2>&1 || true' EXIT

for capa in "${CAPAS[@]}"; do
  if [[ ! "$capa" =~ ^[a-z_]+$ ]]; then
    echo "Nombre de capa inválido: $capa"; exit 1
  fi
  qml="$DIR_ESTILOS/$capa.qml"
  sld="$DIR_ESTILOS/$capa.sld"
  [[ -f "$qml" ]] || { echo "No existe $qml"; exit 1; }

  docker exec -i -u postgres pg-central sh -c "cat > $TMP/$capa.qml" < "$qml"
  sld_srv=""
  if [[ -f "$sld" ]]; then
    docker exec -i -u postgres pg-central sh -c "cat > $TMP/$capa.sld" < "$sld"
    sld_srv="$TMP/$capa.sld"
  fi

  printf '%-15s ' "$capa"
  docker exec -i pg-central psql -X -v ON_ERROR_STOP=1 -tA -U "$PGUSER" -d "$DB" \
    -v capa="$capa" -v qml="$TMP/$capa.qml" -v sld="$sld_srv" -v descr="$DESCRIPCION" <<'SQL'
SELECT sig.fn_publicar_estilo(
         :'capa',
         pg_read_file(:'qml'),
         CASE WHEN :'sld' = '' THEN NULL ELSE pg_read_file(:'sld') END,
         NULLIF(:'descr', ''));
SQL
done

echo
echo ">> Versiones vigentes en el central:"
docker exec pg-central psql -X -U "$PGUSER" -d "$DB" -c \
  "SELECT capa, version, stylename, update_time::timestamp(0) FROM sig.v_estilos WHERE vigente ORDER BY capa"

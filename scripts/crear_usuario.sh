#!/usr/bin/env bash
# =====================================================================
# Crea un usuario SIG-TEC en el central (auth.usuario) y su rol de login
# en el nodo de su campus, con la misma contraseña.
#
# Uso: ./scripts/crear_usuario.sh <usuario> <clave> <campus> <editor|consulta> "<Nombre completo>"
#   campus: cartago | sanjose | sancarlos | alajuela | limon
# Ej:   ./scripts/crear_usuario.sh samuel 'Clave123!' sancarlos editor "Samuel ..."
# =====================================================================
set -euo pipefail

if [[ $# -lt 5 ]]; then
  sed -n '5,9p' "$0"; exit 1
fi

USUARIO=$(echo "$1" | tr '[:upper:]' '[:lower:]')
CLAVE=$2
CAMPUS=$(echo "$3" | tr '[:upper:]' '[:lower:]')
ROL=$4
NOMBRE=$5
PGUSER=${PG_SUPERUSER:-postgres}
DB=${SIGTEC_DB:-sigtec}

case "$ROL" in
  editor)   GRUPO=sigtec_editor ;;
  consulta) GRUPO=sigtec_lectura ;;
  *) echo "Rol inválido: $ROL (editor|consulta)"; exit 1 ;;
esac

echo ">> Central: registrando $USUARIO ($ROL, $CAMPUS)"
docker exec -i pg-central psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$DB" \
  -v u="$USUARIO" -v c="$CLAVE" -v n="$NOMBRE" -v cam="$CAMPUS" -v r="$ROL" <<'SQL'
SELECT auth.fn_crear_usuario(:'u', :'c', :'n', :'cam', :'r');
SQL

echo ">> Nodo pg-$CAMPUS: creando rol de login"
docker exec -i "pg-$CAMPUS" psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$DB" \
  -v u="$USUARIO" -v c="$CLAVE" -v g="$GRUPO" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L IN ROLE %I', :'u', :'c', :'g') \gexec
SQL

echo ">> Listo."

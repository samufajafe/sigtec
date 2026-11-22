#!/usr/bin/env bash
# =====================================================================
# SIG-TEC - Inicialización de nodo (se ejecuta UNA sola vez, cuando el
# volumen de datos está vacío). Lo monta docker-compose en
# /docker-entrypoint-initdb.d/ y corre después de 10_postgis.sh.
#
# Variables de entorno (docker-compose.yml):
#   NODO_TIPO   central | campus
#   CAMPUS_ID   0 (central) | 1..5
# =====================================================================
set -euo pipefail

SQL_DIR=/sigtec/sql
PSQL=(psql -v ON_ERROR_STOP=1 -q --username "$POSTGRES_USER" --dbname "$POSTGRES_DB")

echo "[SIG-TEC] Inicializando nodo tipo=${NODO_TIPO} campus_id=${CAMPUS_ID}"

# ---------- Común a los 6 nodos ----------
"${PSQL[@]}" -f "$SQL_DIR/comun/00_extensiones.sql"
"${PSQL[@]}" -v campus_id="$CAMPUS_ID" -v nodo_tipo="$NODO_TIPO" \
             -f "$SQL_DIR/comun/01_catalogos.sql"
"${PSQL[@]}" -f "$SQL_DIR/comun/02_modelo_capas.sql"
"${PSQL[@]}" -v repl_pass="$SIGTEC_REPL_PASSWORD" \
             -f "$SQL_DIR/comun/03_roles_base.sql"

if [[ "$NODO_TIPO" == "central" ]]; then
  # ---------- Nodo central ----------
  "${PSQL[@]}" -f "$SQL_DIR/central/10_esquemas_replica.sql"
  "${PSQL[@]}" -v login_pass="$SIGTEC_LOGIN_PASSWORD" \
               -v host_cliente="$SIGTEC_HOST_CLIENTE" \
               -f "$SQL_DIR/central/11_autenticacion.sql"
  "${PSQL[@]}" -v demo_pass="$SIGTEC_DEMO_PASSWORD" \
               -f "$SQL_DIR/central/12_usuarios_demo.sql"
else
  # ---------- Nodo de campus ----------
  "${PSQL[@]}" -v campus_id="$CAMPUS_ID" \
               -f "$SQL_DIR/campus/10_esquemas_campus.sql"
  "${PSQL[@]}" -v campus_id="$CAMPUS_ID" -v demo_pass="$SIGTEC_DEMO_PASSWORD" \
               -f "$SQL_DIR/campus/11_usuarios_nodo.sql"
  "${PSQL[@]}" -v campus_id="$CAMPUS_ID" \
               -f "$SQL_DIR/campus/12_datos_ejemplo.sql"
fi

# Marca de init completo: la usa el healthcheck de docker-compose.yml.
touch "$PGDATA/sigtec_init_ok"

echo "[SIG-TEC] Nodo ${NODO_TIPO}/${CAMPUS_ID} listo."

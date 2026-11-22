#!/usr/bin/env bash
# =====================================================================
# SIG-TEC - Monta, desmonta y revisa la replicación lógica de dos niveles.
#
# Uso: ./scripts/configurar_replicacion.sh [modo]
#   montar     (por defecto) Nivel 1 + Nivel 2, espera la copia inicial
#   nivel1     solo campus -> central
#   nivel2     solo central -> campus (exige Nivel 1 completo)
#   desmontar  elimina suscripciones, publicaciones y copias réplica
#   remontar   desmontar + montar
#   estado     muestra publicaciones, suscripciones, slots y conteos
#
# Es idempotente: volver a ejecutar "montar" no duplica nada.
# "desmontar" nunca borra el esquema propio de un campus.
# Variable opcional: SIGTEC_REPL_TIMEOUT (segundos por suscripción, def. 180)
# =====================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash no debe reescribir rutas del contenedor

CAMPUS=(cartago sanjose sancarlos alajuela limon)
NODOS=(central "${CAMPUS[@]}")
SQL_DIR=/sigtec/sql/replicacion
TIMEOUT=${SIGTEC_REPL_TIMEOUT:-180}
TABLAS_POR_ESQUEMA=8

info()  { printf '>> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Ejecuta un archivo SQL dentro del nodo. La clave se lee del entorno del
# contenedor, así no pasa por la línea de comandos del host ni por el repo.
ejecutar() {
  local nodo=$1 archivo=$2; shift 2
  docker exec "pg-$nodo" bash -c \
    'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
       -v repl_pass="$SIGTEC_REPL_PASSWORD" "$@"' -- "$@" -f "$SQL_DIR/$archivo" >/dev/null
}

consulta() {
  docker exec "pg-$1" bash -c \
    'exec psql -X -qtA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"' -- "$2"
}

verificar_nodos_arriba() {
  local n estado
  for n in "${NODOS[@]}"; do
    estado=$(docker inspect -f '{{.State.Health.Status}}' "pg-$n" 2>/dev/null || echo ausente)
    [[ $estado == healthy ]] || error "pg-$n no está healthy (estado: $estado). Corra: docker compose up -d"
  done
}

# Espera a que todas las tablas de la suscripción lleguen al estado 'r' (ready).
esperar_copia() {
  local nodo=$1 sub=$2 esperadas=$3 limite=$((SECONDS + TIMEOUT)) avance=""
  while (( SECONDS < limite )); do
    avance=$(consulta "$nodo" "SELECT count(*) FILTER (WHERE r.srsubstate = 'r') || '/' || count(*)
      FROM pg_subscription s JOIN pg_subscription_rel r ON r.srsubid = s.oid
      WHERE s.subname = '$sub'")
    if [[ $avance == "$esperadas/$esperadas" ]]; then
      info "   $sub: copia inicial completa ($avance tablas)"
      return 0
    fi
    sleep 1
  done
  docker logs --tail 15 "pg-$nodo" >&2 || true
  error "$sub no terminó en ${TIMEOUT}s (tablas listas: $avance, esperadas: $esperadas)"
}

montar_nivel1() {
  local c
  info "Nivel 1: publicaciones en los campus"
  for c in "${CAMPUS[@]}"; do ejecutar "$c" 10_nivel1_publicacion_campus.sql; done
  info "Nivel 1: suscripciones en el central"
  for c in "${CAMPUS[@]}"; do
    ejecutar central 11_nivel1_suscripcion_central.sql -v esquema="$c"
    esperar_copia central "sub_central_$c" "$TABLAS_POR_ESQUEMA"
  done
}

montar_nivel2() {
  local c
  for c in "${CAMPUS[@]}"; do
    [[ $(consulta central "SELECT count(*) FROM pg_subscription WHERE subname = 'sub_central_$c'") == 1 ]] \
      || error "Falta sub_central_$c. Monte primero el Nivel 1."
    esperar_copia central "sub_central_$c" "$TABLAS_POR_ESQUEMA" >/dev/null
  done
  info "Nivel 2: publicaciones globales en el central"
  ejecutar central 20_nivel2_publicaciones_central.sql
  # Una por una: la copia inicial en paralelo agotaría max_replication_slots
  # (5 slots fijos + hasta 4 temporales por suscripción, con límite de 20).
  info "Nivel 2: suscripciones en los campus"
  for c in "${CAMPUS[@]}"; do
    ejecutar "$c" 21_nivel2_suscripcion_campus.sql
    esperar_copia "$c" "sub_${c}_global" $((TABLAS_POR_ESQUEMA * 4))
  done
}

desmontar() {
  local c n
  info "Eliminando suscripciones del Nivel 2"
  for c in "${CAMPUS[@]}"; do ejecutar "$c" 90_desmontar_suscripciones.sql; done
  info "Eliminando suscripciones del Nivel 1"
  ejecutar central 90_desmontar_suscripciones.sql
  info "Eliminando publicaciones y slots huérfanos"
  for n in "${NODOS[@]}"; do ejecutar "$n" 91_desmontar_publicaciones.sql; done
  info "Vaciando copias réplica (los esquemas propios no se tocan)"
  for n in "${NODOS[@]}"; do ejecutar "$n" 92_vaciar_replicas.sql; done
}

# Huella por tabla de los 5 esquemas, para comparar los 6 nodos.
HUELLA="SELECT string_agg(t.schemaname || '.' || t.tablename || '=' ||
          (xpath('/row/c/text()', query_to_xml(
             format('SELECT count(*) AS c FROM %I.%I', t.schemaname, t.tablename),
             false, true, '')))[1]::text, ' ' ORDER BY t.schemaname, t.tablename)
        FROM pg_tables t JOIN sig.campus c ON c.codigo = t.schemaname"

verificar_convergencia() {
  local limite=$((SECONDS + 30)) referencia n iguales
  while (( SECONDS < limite )); do
    referencia=$(consulta central "$HUELLA"); iguales=1
    for n in "${CAMPUS[@]}"; do
      [[ $(consulta "$n" "$HUELLA") == "$referencia" ]] || { iguales=0; break; }
    done
    if (( iguales )); then
      info "Convergencia OK: las 40 tablas tienen el mismo conteo en los 6 nodos"
      return 0
    fi
    sleep 1
  done
  error "Los nodos no convergieron: $n difiere del central"
}

estado() {
  local n
  for n in "${NODOS[@]}"; do
    printf '\n==== pg-%s ====\n' "$n"
    docker exec "pg-$n" psql -X -U postgres -d sigtec -P pager=off -c "
      SELECT 'publicacion' AS objeto, pubname AS nombre, '' AS detalle FROM pg_publication
      UNION ALL
      SELECT 'suscripcion', s.subname,
             CASE WHEN s.subenabled THEN 'activa' ELSE 'deshabilitada' END || ', tablas listas ' ||
             (SELECT count(*) FILTER (WHERE srsubstate = 'r') || '/' || count(*)
                FROM pg_subscription_rel r WHERE r.srsubid = s.oid) ||
             CASE WHEN EXISTS (SELECT 1 FROM pg_stat_subscription x
                               WHERE x.subid = s.oid AND x.pid IS NOT NULL)
                  THEN ', worker corriendo' ELSE ', SIN worker' END
      FROM pg_subscription s
      UNION ALL
      SELECT 'slot', slot_name, CASE WHEN active THEN 'activo' ELSE 'inactivo' END
      FROM pg_replication_slots
      ORDER BY 1, 2;"
  done
}

modo=${1:-montar}
case "$modo" in
  montar)    verificar_nodos_arriba; montar_nivel1; montar_nivel2; verificar_convergencia ;;
  nivel1)    verificar_nodos_arriba; montar_nivel1 ;;
  nivel2)    verificar_nodos_arriba; montar_nivel2; verificar_convergencia ;;
  desmontar) verificar_nodos_arriba; desmontar ;;
  remontar)  verificar_nodos_arriba; desmontar; montar_nivel1; montar_nivel2; verificar_convergencia ;;
  estado)    estado ;;
  *)         sed -n '5,11p' "$0"; exit 1 ;;
esac
info "Listo ($modo)."

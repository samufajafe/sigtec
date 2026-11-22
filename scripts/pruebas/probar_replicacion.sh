#!/usr/bin/env bash
# =====================================================================
# SIG-TEC - Pruebas de punta a punta de replicación y vistas capas.*
#
# Uso: ./scripts/pruebas/probar_replicacion.sh [--rapido]
#   --rapido  edita solo desde San Carlos (versión corta para el video)
# Requiere: nodos arriba y ./scripts/configurar_replicacion.sh ya ejecutado.
# Salida: una línea PASS/FAIL por prueba.
# Código de salida: 0 todo pasó · 1 alguna falló · 2 faltan requisitos.
# Las filas de prueba se eliminan al terminar, incluso si algo falla.
# Variable opcional: SIGTEC_PRUEBA_LATENCIA (segundos de espera, def. 30)
# =====================================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
CAMPUS=(cartago sanjose sancarlos alajuela limon)
NODOS=(central "${CAMPUS[@]}")
CAMPUS_PRUEBA=("${CAMPUS[@]}")
[[ ${1:-} == --rapido ]] && CAMPUS_PRUEBA=(sancarlos)
CAPAS=(edificios carreteras aceras parqueos zonas_verdes puntos_interes iluminacion accesibilidad)
LATENCIA=${SIGTEC_PRUEBA_LATENCIA:-30}
MARCA="PRB$$"
PASADAS=0
FALLIDAS=0
CREADAS=()   # "esquema capa id" de cada fila de prueba

pass()    { PASADAS=$((PASADAS + 1));  printf '  [PASS] %s\n' "$*"; }
fail()    { FALLIDAS=$((FALLIDAS + 1)); printf '  [FAIL] %s\n' "$*"; }
seccion() { printf '\n== %s ==\n' "$*"; }

# Consulta como superusuario, por socket local.
sql_pg() {
  docker exec "pg-$1" bash -c \
    'exec psql -X -qtA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1" 2>&1' -- "$2"
}

# Ejecuta SQL como usuario demo, por TCP y en una sola transacción.
sql_como() {
  printf '%s\n' "$3" | docker exec -i -e USUARIO="$2" "pg-$1" bash -c \
    'PGPASSWORD="$SIGTEC_DEMO_PASSWORD" exec psql -X -qtA -1 -v ON_ERROR_STOP=1 -v VERBOSITY=terse \
       -h 127.0.0.1 -U "$USUARIO" -d "$POSTGRES_DB" -f - 2>&1'
}

campus_id() {
  local i
  for i in "${!CAMPUS[@]}"; do [[ ${CAMPUS[$i]} == "$1" ]] && { echo $((i + 1)); return; }; done
}

# La operación debe fallar y el error debe contener el patrón indicado.
debe_fallar() {
  local desc=$1 nodo=$2 usuario=$3 consulta=$4 patron=$5 salida rc
  salida=$(sql_como "$nodo" "$usuario" "$consulta"); rc=$?
  if (( rc != 0 )) && grep -qi -- "$patron" <<<"$salida"; then
    pass "$desc"
  else
    fail "$desc (rc=$rc, salida: ${salida:0:140})"
  fi
}

# Espera a que la consulta devuelva el valor esperado en los 6 nodos.
esperar_en_nodos() {
  local desc=$1 consulta=$2 esperado=$3 limite=$((SECONDS + LATENCIA)) n
  local pendientes=("${NODOS[@]}") malos
  while :; do
    malos=()
    for n in "${pendientes[@]}"; do
      [[ $(sql_pg "$n" "$consulta") == "$esperado" ]] || malos+=("$n")
    done
    if (( ${#malos[@]} == 0 )); then pass "$desc"; return 0; fi
    if (( SECONDS >= limite )); then fail "$desc (sin converger: ${malos[*]})"; return 1; fi
    pendientes=("${malos[@]}")
    sleep 0.3
  done
}

insert_prueba() {
  local capa=$1 cid=$2 m="$MARCA-$2"
  local c="(SELECT centro FROM sig.campus WHERE campus_id = $cid)"
  local pol="ST_Buffer($c, 5, 1)" lin="ST_MakeLine($c, ST_Translate($c, 10, 0))"
  case $capa in
    edificios)      echo "INSERT INTO capas.edificios (codigo, nombre, geom) VALUES ('$m', 'Prueba', $pol) RETURNING id;" ;;
    carreteras)     echo "INSERT INTO capas.carreteras (tipo, superficie, geom) VALUES ('interna', 'asfalto', $lin) RETURNING id;" ;;
    aceras)         echo "INSERT INTO capas.aceras (material, condicion, geom) VALUES ('concreto', 'buena', $lin) RETURNING id;" ;;
    parqueos)       echo "INSERT INTO capas.parqueos (tipo, capacidad, geom) VALUES ('mixto', 5, $pol) RETURNING id;" ;;
    zonas_verdes)   echo "INSERT INTO capas.zonas_verdes (tipo_vegetacion, geom) VALUES ('cesped', $pol) RETURNING id;" ;;
    puntos_interes) echo "INSERT INTO capas.puntos_interes (nombre, tipo, geom) VALUES ('$m', 'otro', $c) RETURNING id;" ;;
    iluminacion)    echo "INSERT INTO capas.iluminacion (codigo, geom) VALUES ('$m', $c) RETURNING id;" ;;
    accesibilidad)  echo "INSERT INTO capas.accesibilidad (tipo, geom) VALUES ('rampa', $lin) RETURNING id;" ;;
  esac
}

limpiar() {
  local fila esquema capa id
  for fila in ${CREADAS[@]+"${CREADAS[@]}"}; do
    read -r esquema capa id <<<"$fila"
    sql_pg "$esquema" "DELETE FROM $esquema.$capa WHERE id = $id" >/dev/null || true
  done
  CREADAS=()
}
trap limpiar EXIT

# ---------------------------------------------------------------------
seccion "0. Requisitos"
for n in "${NODOS[@]}"; do
  estado=$(docker inspect -f '{{.State.Health.Status}}' "pg-$n" 2>/dev/null || echo ausente)
  if [[ $estado != healthy ]]; then echo "  pg-$n no está healthy ($estado)"; exit 2; fi
done
if [[ $(sql_pg central "SELECT count(*) FROM pg_subscription") != 5 ]]; then
  echo "  Falta la replicación. Corra: ./scripts/configurar_replicacion.sh"; exit 2
fi
for n in "${NODOS[@]}"; do
  if [[ $(sql_pg "$n" "SELECT count(*) FROM pg_views WHERE schemaname = 'capas'") != 8 ]]; then
    echo "  Faltan vistas en pg-$n. Corra: ./scripts/configurar_replicacion.sh vistas"; exit 2
  fi
done
pass "6 nodos healthy, replicación montada y 8 vistas en cada nodo"

# El contador es acumulado y también sube cuando un nodo se reinicia; por eso
# se compara contra su valor al inicio de esta corrida.
ERRORES_SUB="SELECT coalesce(sum(apply_error_count + sync_error_count), 0) FROM pg_stat_subscription_stats"
declare -A ERRORES_INICIALES
for n in "${NODOS[@]}"; do ERRORES_INICIALES[$n]=$(sql_pg "$n" "$ERRORES_SUB"); done

# ---------------------------------------------------------------------
seccion "1. Topología: dos niveles y sin ciclos"
for c in "${CAMPUS[@]}"; do
  pubs=$(sql_pg "$c" "SELECT array_to_string(subpublications, ',') FROM pg_subscription WHERE subname = 'sub_${c}_global'")
  if [[ $(tr ',' '\n' <<<"$pubs" | grep -c '^pub_global_') == 4 ]] && ! grep -qw "pub_global_$c" <<<"$pubs"; then
    pass "sub_${c}_global toma 4 publicaciones y excluye la propia"
  else
    fail "sub_${c}_global tiene publicaciones incorrectas: $pubs"
  fi
done

# ---------------------------------------------------------------------
seccion "2. INSERT/UPDATE/DELETE en las 8 capas llegan a los 6 nodos"
for c in "${CAMPUS_PRUEBA[@]}"; do
  cid=$(campus_id "$c")
  huella="SELECT md5(string_agg(coalesce(f, 'ausente'), '|' ORDER BY o)) FROM ("
  sep=""; orden=0; insertar=""; actualizar=""; borrar=""
  for capa in "${CAPAS[@]}"; do insertar+="$(insert_prueba "$capa" "$cid")"$'\n'; done
  salida=$(sql_como "$c" "editor_$c" "$insertar"); rc=$?
  if (( rc != 0 )); then fail "$c: INSERT en las 8 capas (${salida:0:140})"; continue; fi
  mapfile -t ids < <(tr -d '\r' <<<"$salida")
  for i in "${!CAPAS[@]}"; do
    capa=${CAPAS[$i]}; id=${ids[$i]}; orden=$((orden + 1))
    CREADAS+=("$c $capa $id")
    huella+="$sep SELECT $orden AS o, (SELECT md5(t::text) FROM capas.$capa t WHERE t.id = $id) AS f"
    sep=" UNION ALL"
    actualizar+="UPDATE capas.$capa SET geom = ST_Translate(geom, 1, 0) WHERE id = $id;"$'\n'
    borrar+="DELETE FROM capas.$capa WHERE id = $id;"$'\n'
  done
  huella+=") x"

  h1=$(sql_pg "$c" "$huella")
  esperar_en_nodos "$c: INSERT visible e idéntico en los 6 nodos" "$huella" "$h1"

  if salida=$(sql_como "$c" "editor_$c" "$actualizar"); then
    h2=$(sql_pg "$c" "$huella")
    if [[ $h2 != "$h1" ]]; then
      esperar_en_nodos "$c: UPDATE visible e idéntico en los 6 nodos" "$huella" "$h2"
    else
      fail "$c: el UPDATE no cambió las filas"
    fi
  else
    fail "$c: UPDATE en las 8 capas (${salida:0:140})"
  fi

  if salida=$(sql_como "$c" "editor_$c" "$borrar"); then
    h3=$(sql_pg "$c" "$huella")
    esperar_en_nodos "$c: DELETE aplicado en los 6 nodos" "$huella" "$h3"
    filas=0
    for fila in "${CREADAS[@]}"; do
      read -r e capa id <<<"$fila"
      [[ $e == "$c" ]] && filas=$((filas + $(sql_pg "$c" "SELECT count(*) FROM capas.$capa WHERE id = $id")))
    done
    if (( filas == 0 )); then pass "$c: las 8 filas de prueba ya no existen"; else fail "$c: quedaron $filas filas"; fi
  else
    fail "$c: DELETE en las 8 capas (${salida:0:140})"
  fi
done

# ---------------------------------------------------------------------
seccion "3. Un editor no puede tocar datos de otro campus"
for c in "${CAMPUS_PRUEBA[@]}"; do
  cid=$(campus_id "$c"); otro_id=$((cid % 5 + 1)); otro=${CAMPUS[$((otro_id - 1))]}
  fila=$(sql_pg "$c" "SELECT min(id) FROM capas.edificios WHERE campus_id = $otro_id")
  antes=$(sql_pg "$otro" "SELECT md5(t::text) FROM capas.edificios t WHERE id = $fila")
  debe_fallar "editor_$c: INSERT con campus de $otro rechazado" "$c" "editor_$c" \
    "INSERT INTO capas.edificios (campus_id, codigo, nombre, geom) VALUES ($otro_id, '$MARCA-X', 'X', ST_Buffer((SELECT centro FROM sig.campus WHERE campus_id = $otro_id), 5, 1));" \
    "solo edita el campus"
  debe_fallar "editor_$c: UPDATE de fila de $otro rechazado" "$c" "editor_$c" \
    "UPDATE capas.edificios SET nombre = 'hackeado' WHERE id = $fila;" "solo edita el campus"
  debe_fallar "editor_$c: DELETE de fila de $otro rechazado" "$c" "editor_$c" \
    "DELETE FROM capas.edificios WHERE id = $fila;" "solo edita el campus"
  debe_fallar "editor_$c: escritura directa en tabla física rechazada" "$c" "editor_$c" \
    "DELETE FROM $c.edificios WHERE id = (SELECT min(id) FROM $c.edificios);" "permission denied"
  despues=$(sql_pg "$otro" "SELECT md5(t::text) FROM capas.edificios t WHERE id = $fila")
  if [[ -n $antes && $antes == "$despues" ]]; then pass "fila $fila de $otro quedó intacta"; else fail "fila $fila de $otro cambió"; fi
done

# ---------------------------------------------------------------------
seccion "4. Un usuario de consulta no puede escribir"
for c in "${CAMPUS_PRUEBA[@]}"; do
  cid=$(campus_id "$c")
  fila=$(sql_pg "$c" "SELECT min(id) FROM capas.edificios WHERE campus_id = $cid")
  n=$(sql_como "$c" "consulta_$c" "SELECT count(*) FROM capas.edificios;")
  if [[ $n == 15 ]]; then pass "consulta_$c: lee los 15 edificios"; else fail "consulta_$c: lectura devolvió '$n'"; fi
  debe_fallar "consulta_$c: INSERT rechazado" "$c" "consulta_$c" \
    "INSERT INTO capas.edificios (codigo, nombre, geom) VALUES ('$MARCA-C', 'X', ST_Buffer((SELECT centro FROM sig.campus WHERE campus_id = $cid), 5, 1));" \
    "permission denied"
  debe_fallar "consulta_$c: UPDATE rechazado" "$c" "consulta_$c" \
    "UPDATE capas.edificios SET nombre = 'X' WHERE id = $fila;" "permission denied"
  debe_fallar "consulta_$c: DELETE rechazado" "$c" "consulta_$c" \
    "DELETE FROM capas.edificios WHERE id = $fila;" "permission denied"
done

# ---------------------------------------------------------------------
seccion "5. Normalización de SRID"
c=sancarlos; cid=3
centro="(SELECT centro FROM sig.campus WHERE campus_id = $cid)"
id=$(sql_como "$c" "editor_$c" "INSERT INTO capas.puntos_interes (nombre, tipo, geom) VALUES ('$MARCA-4326', 'otro', ST_Transform($centro, 4326)) RETURNING id;")
if [[ $id =~ ^[0-9]+$ ]]; then
  CREADAS+=("$c puntos_interes $id")
  esperar_en_nodos "INSERT en 4326 queda en 5367 y en la posición correcta, en los 6 nodos" \
    "SELECT ST_SRID(geom) = 5367 AND ST_DWithin(geom, $centro, 0.01) FROM capas.puntos_interes WHERE id = $id" "t"
  if salida=$(sql_como "$c" "editor_$c" "UPDATE capas.puntos_interes SET geom = ST_Transform(ST_Translate($centro, 25, 0), 4326) WHERE id = $id;"); then
    esperar_en_nodos "UPDATE en 4326 queda en 5367, en los 6 nodos" \
      "SELECT ST_SRID(geom) = 5367 AND ST_DWithin(geom, ST_Translate($centro, 25, 0), 0.01) FROM capas.puntos_interes WHERE id = $id" "t"
  else
    fail "UPDATE en 4326 (${salida:0:140})"
  fi
else
  fail "INSERT en 4326 ($id)"
fi
id=$(sql_como "$c" "editor_$c" "INSERT INTO capas.puntos_interes (nombre, tipo, geom) VALUES ('$MARCA-0', 'otro', ST_SetSRID($centro, 0)) RETURNING id;")
if [[ $id =~ ^[0-9]+$ ]]; then
  CREADAS+=("$c puntos_interes $id")
  esperar_en_nodos "INSERT con SRID 0 se asume 5367, en los 6 nodos" \
    "SELECT ST_SRID(geom) = 5367 AND ST_DWithin(geom, $centro, 0.01) FROM capas.puntos_interes WHERE id = $id" "t"
else
  fail "INSERT con SRID 0 ($id)"
fi
debe_fallar "Geometría de tipo incorrecto rechazada" "$c" "editor_$c" \
  "INSERT INTO capas.edificios (codigo, nombre, geom) VALUES ('$MARCA-T', 'X', $centro);" "does not match column type"

# ---------------------------------------------------------------------
seccion "6. id y campus_id son inmutables"
id=$(sql_como sancarlos editor_sancarlos "INSERT INTO capas.puntos_interes (id, nombre, tipo, geom) VALUES (1000000001, '$MARCA-ID', 'otro', (SELECT centro FROM sig.campus WHERE campus_id = 3)) RETURNING id;")
if [[ $id =~ ^3[0-9]{9}$ ]]; then
  CREADAS+=("sancarlos puntos_interes $id")
  pass "INSERT ignora el id enviado y usa la secuencia local ($id)"
else
  fail "INSERT con id explícito devolvió: ${id:0:140}"
fi
for c in "${CAMPUS_PRUEBA[@]}"; do
  cid=$(campus_id "$c"); otro_id=$((cid % 5 + 1))
  fila=$(sql_pg "$c" "SELECT min(id) FROM capas.edificios WHERE campus_id = $cid")
  debe_fallar "$c: UPDATE de id rechazado" "$c" "editor_$c" \
    "UPDATE capas.edificios SET id = id + 1 WHERE id = $fila;" "cambiar el id"
  debe_fallar "$c: UPDATE de campus_id rechazado" "$c" "editor_$c" \
    "UPDATE capas.edificios SET campus_id = $otro_id WHERE id = $fila;" "cambiar el campus_id"
done

# ---------------------------------------------------------------------
seccion "7. El central no tiene vistas editables"
for op in "INSERT INTO capas.edificios (codigo, nombre) VALUES ('X', 'X')" \
          "UPDATE capas.edificios SET nombre = 'X'" \
          "DELETE FROM capas.edificios"; do
  salida=$(sql_pg central "$op"); rc=$?
  if (( rc != 0 )) && grep -qi 'cannot .* view' <<<"$salida"; then
    pass "central rechaza: ${op%% capas*}"
  else
    fail "central aceptó o falló distinto: ${op} (${salida:0:120})"
  fi
done

# ---------------------------------------------------------------------
seccion "8. Columnas generadas y salud de las suscripciones"
limpiar
generadas="SELECT
  (SELECT count(*) FROM capas.edificios    WHERE area_m2    IS DISTINCT FROM round(ST_Area(geom)::numeric, 2)) +
  (SELECT count(*) FROM capas.parqueos     WHERE area_m2    IS DISTINCT FROM round(ST_Area(geom)::numeric, 2)) +
  (SELECT count(*) FROM capas.zonas_verdes WHERE area_m2    IS DISTINCT FROM round(ST_Area(geom)::numeric, 2)) +
  (SELECT count(*) FROM capas.carreteras   WHERE longitud_m IS DISTINCT FROM round(ST_Length(geom)::numeric, 2)) +
  (SELECT count(*) FROM capas.aceras       WHERE longitud_m IS DISTINCT FROM round(ST_Length(geom)::numeric, 2)) +
  (SELECT count(*) FROM capas.accesibilidad WHERE longitud_m IS DISTINCT FROM round(ST_Length(geom)::numeric, 2))"
esperar_en_nodos "area_m2 y longitud_m correctas en los 6 nodos" "$generadas" "0"
nuevos=""
for n in "${NODOS[@]}"; do
  actual=$(sql_pg "$n" "$ERRORES_SUB")
  [[ $actual == "${ERRORES_INICIALES[$n]}" ]] || nuevos+=" $n(${ERRORES_INICIALES[$n]}->$actual)"
done
if [[ -z $nuevos ]]; then
  pass "0 errores nuevos de apply/sync durante la corrida"
else
  fail "errores nuevos de apply/sync:$nuevos"
fi
esperar_en_nodos "Todas las suscripciones con worker corriendo" \
  "SELECT count(*) FROM pg_subscription s WHERE NOT EXISTS (SELECT 1 FROM pg_stat_subscription x WHERE x.subid = s.oid AND x.pid IS NOT NULL)" "0"

# ---------------------------------------------------------------------
seccion "9. Conteos finales con verificar_nodos.sh"
limite=$((SECONDS + LATENCIA))
while :; do
  salida=$(bash "$RAIZ/scripts/verificar_nodos.sh" 2>&1)
  total=$(grep -c '^edificios | ' <<<"$salida")
  con_tres=$(grep -cE '^edificios \| [a-z]+ \| 3$' <<<"$salida")
  if [[ $total == 30 && $con_tres == 30 ]] || (( SECONDS >= limite )); then break; fi
  sleep 0.5
done
if [[ $total == 30 && $con_tres == 30 ]]; then
  pass "3 edificios por campus en los 6 nodos (30/30 conteos)"
else
  fail "conteos incorrectos: $con_tres de $total con 3 edificios"
fi

# ---------------------------------------------------------------------
printf '\n========================================\n'
printf ' RESULTADO: %d PASS, %d FAIL\n' "$PASADAS" "$FALLIDAS"
printf '========================================\n'
(( FALLIDAS == 0 ))

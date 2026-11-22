# Notas de Gabo — Replicación y vistas

Bitácora de decisiones, problemas y pendientes del módulo. Materia prima de `docs/02_replicacion_vistas.md`.

## Lista de tareas

- [x] Levantar los 6 nodos y verificar el estado inicial
- [x] A. Nivel 1 (campus → central)
- [x] B. Nivel 2 (central → campus)
- [x] C. `scripts/configurar_replicacion.sh` idempotente, con desmontaje y remontaje
- [x] D. Vistas `capas.*` y disparadores INSTEAD OF
- [x] E. Pruebas automáticas en `scripts/pruebas/`
- [x] F. `docs/02_replicacion_vistas.md`
- [ ] Publicar la rama `replicacion` y abrir el PR (Gabo)
- [ ] Probar edición real desde QGIS con el complemento
- [ ] Ensayar un PITR real con Justin y luego `remontar`
- [ ] Repetir el montaje desde volúmenes vacíos, ya con `main` integrado (requiere `down -v`; avisar antes)

## Decisiones

| # | Decisión | Motivo |
|---|---|---|
| 1 | Crear la rama `replicacion` local desde `main` | No existía ni local ni en `origin`. No se hizo push. |
| 2 | Crear las suscripciones de una en una y esperar su copia inicial | Limita la carga sobre el central e identifica cuál falla. `main` ya subió los límites a 40, así que no es indispensable. |
| 3 | `origin = any` explícito en `sub_<campus>_global` | Las filas que reenvía el central tienen origen remoto. Con `origin = none` no llegarían. |
| 4 | La clave de replicación se lee del entorno del contenedor | No pasa por la línea de comandos del host ni queda en el repo. |
| 5 | `geom` se expone como `geometry` simple en las vistas | Con `geometry(Polygon,5367)`, PostgreSQL rechaza 4326 antes del INSTEAD OF. El índice GiST se sigue usando (verificado con `EXPLAIN`). |
| 6 | Un solo disparador genérico para las 8 capas | Las columnas salen del catálogo; evita 8 copias de la misma lógica. |
| 7 | El INSTEAD OF devuelve la fila real | `INSERT ... RETURNING` entrega el `id`, las fechas y las columnas generadas. |
| 8 | En INSERT, un `id` enviado por el cliente se ignora | El contrato pide que lo asigne la secuencia local. |
| 9 | El central también tiene vistas `capas.*`, solo de consulta | Sirven para revisar la copia consolidada. Sin disparador, PostgreSQL rechaza escribir en un `UNION ALL`. |
| 10 | `remontar` es el procedimiento de resincronización | Vacía solo las réplicas y las vuelve a copiar desde cada campus dueño. |
| 11 | No integrar `origin/main` en la rama | La instrucción es no hacer merge. La simulación con `git merge-tree` no da conflictos. |
| 12 | Las vistas reales reemplazan las temporales del complemento | Las temporales declaran `geom` con tipo y SRID, y `CREATE OR REPLACE VIEW` no puede cambiarlo. |

## Problemas encontrados

### `desmontar` se detenía si faltaba un slot (resuelto)
- **Síntoma:** `could not drop replication slot ... does not exist`, con la replicación a medio desmontar.
- **Causa:** `DROP SUBSCRIPTION` intenta borrar el slot remoto y falla si ya no existe. Es lo esperable después de restaurar un nodo, porque los respaldos físicos no incluyen slots.
- **Solución:** `DISABLE`, `SET (slot_name = NONE)` y `DROP`. Después, `91_desmontar_publicaciones.sql` limpia los slots en cada publicador.
- **Verificación:** se borró un slot real y `remontar` terminó bien, con los 6 nodos convergentes.

### `desmontar` habría borrado `pub_estilos` (resuelto antes de publicar)
- **Síntoma:** detectado al revisar `origin/main`, que agregó `pub_estilos` durante la sesión.
- **Causa:** el script borraba toda publicación con prefijo `pub_`, y los slots de copia inicial por patrón.
- **Solución:** los nombres se derivan de `sig.campus` y se comparan exactos. Las suscripciones se borran una por una según exista o no su slot.
- **Verificación:** con una publicación y una suscripción de estilos activas, `remontar` y `desmontar` las dejaron intactas y siguieron replicando.

### Falso FAIL en el contador de errores (resuelto)
- **Síntoma:** la prueba de errores de apply falló después de apagar nodos a propósito.
- **Causa:** `pg_stat_subscription_stats` es acumulado y también cuenta desconexiones. Los logs no mostraron ningún conflicto de datos.
- **Solución:** la prueba compara contra el valor al inicio de la corrida.

### Columnas generadas (verificado, sin problema)
`area_m2` y `longitud_m` no rompen las suscripciones. Tras mover geometrías por la vista, las filas son idénticas en los 6 nodos y los valores coinciden con `ST_Area`/`ST_Length`.

## Para Samuel (no modifiqué sus archivos)

### 1. `wal_archive/` crece dentro de OneDrive — prioridad alta
- **Causa:** `docker-compose.yml` monta `./wal_archive/<nodo>` y en mi máquina el repo está en OneDrive. Tras esta sesión pesa **más de 1 GB**, en parte por las pruebas.
- **Riesgo:** consumo de cuota y sincronización de archivos de 16 MB. También puede afectar `archive_command`, que el propio compose ya documenta como sensible en bind mounts de Windows.
- **Cambio propuesto**, en los 6 servicios (ejemplo con central), más la variable en `.env.example`:

```diff
-      - ./wal_archive/central:/wal_archive
+      - ${SIGTEC_WAL_DIR:-./wal_archive}/central:/wal_archive
```

```env
# Carpeta del WAL archivado. En Windows, usar una ruta fuera de OneDrive.
SIGTEC_WAL_DIR=./wal_archive
```

Alternativa sin tocar sus archivos: mover el repo fuera de OneDrive (por ejemplo `C:\dev\sigtec`).

### 2. Suposición sobre el complemento (confirmada)
Como `geom` no declara tipo ni SRID en la vista, QGIS debe recibirlos en la URI. `plugin/sigtec/nucleo.py` ya usa `setSrid` y `setWkbType`, así que no requiere cambios.

### 3. Vistas en el central
`plugin/dev/vistas_temporales.sql` dice que en el central no hay vistas `capas.*`. Las reales sí existen allí, pero son solo de consulta y no tienen disparadores.

### 4. Observación opcional (no probada)
`sql/comun/03_roles_base.sql` da a `replicador` `pg_create_subscription` y `CREATE` sobre la base. La replicación no los usa, porque todo se crea como `postgres`. Se podrían quitar por mínimo privilegio, probándolo antes.

# SIG-TEC — Sistema Distribuido de Gestión de Información Geográfica de los Campus del TEC

Proyecto 3 · Bases de Datos II · TEC San Carlos · Entrega: lunes 30/11/2026 08:00

Equipo: Samuel · Gabo · Justin — ver [división del trabajo](docs/00_division_trabajo.md).

## Requisitos
- Docker Desktop (o Docker Engine + compose v2)
- QGIS 3.34+ o 4.x (el complemento funciona con ambos)
- En Windows: clonar con `git config core.autocrlf input` (los `.sh` deben quedar en LF).

## Levantar los 6 nodos
```bash
cp .env.example .env          # opcional: cambiar contraseñas
docker compose up -d
docker compose ps             # esperar a que los 6 estén "healthy"
./scripts/verificar_nodos.sh
```
La primera vez cada nodo ejecuta `initdb/00_sigtec_init.sh`, que crea extensiones, catálogos, las 8 capas en los 5 esquemas, roles, usuarios demo, datos de ejemplo y la tabla de estilos `layer_styles`.

Después, una sola vez (los scripts se pueden repetir sin problema):
```bash
./scripts/configurar_estilos.sh                        # suscripciones de estilos central -> campus
./scripts/publicar_estilos.sh -m "Versión inicial"     # estilos de plugin/sigtec/estilos al central
./scripts/configurar_replicacion.sh                    # replicación Nivel 1 + Nivel 2 y vistas capas.*
./scripts/pruebas/probar_replicacion.sh --rapido       # opcional: comprueba replicación, vistas y permisos
```

## Complemento QGIS
```powershell
powershell -ExecutionPolicy Bypass -File plugin\instalar_windows.ps1   # al perfil de QGIS (QGIS3 y/o QGIS4)
powershell -ExecutionPolicy Bypass -File plugin\empaquetar_zip.ps1     # dist\sigtec-<versión>.zip
```
Activar *SIG-TEC* en *Complementos › Administrar e instalar complementos*. Detalle en [docs/03_plugin_y_estilos.md](docs/03_plugin_y_estilos.md).

> Los scripts de init **solo corren con el volumen vacío**. Si cambian algo en `sql/`, reiniciar desde cero con:
> `docker compose down -v && rm -rf wal_archive backups && docker compose up -d`
> Después hay que volver a correr los scripts de configuración de la sección anterior.
>
> `down -v` no borra `./wal_archive` (es carpeta del host). Si se deja, el clúster nuevo genera WAL con los
> mismos nombres (`000000010000000000000001`…), el `archive_command` se niega a sobrescribirlos y el archivado
> queda detenido. Si necesitan conservar ese WAL (pruebas de PITR), muévanlo a otra carpeta en vez de borrarlo.
>
> Un nodo aparece `healthy` solo cuando terminó su init completo. Si queda `unhealthy`, revisar `docker logs pg-<nodo>`.

## Conexión desde QGIS / psql
| Nodo | Puerto | Usuario demo |
|---|---|---|
| central | 5440 | `sigtec_login` / `login2026` (solo `auth.fn_login`) |
| cartago | 5441 | `editor_cartago` / `Tec2026!` |
| sanjose | 5442 | `editor_sanjose` / `Tec2026!` |
| sancarlos | 5443 | `editor_sancarlos` / `Tec2026!` |
| alajuela | 5444 | `editor_alajuela` / `Tec2026!` |
| limon | 5445 | `editor_limon` / `Tec2026!` |

También existen `consulta_<campus>` (solo lectura). Superusuario: `postgres/postgres`. Base de datos: `sigtec`.

Prueba rápida de login:
```bash
psql -h localhost -p 5440 -U sigtec_login -d sigtec -c "SELECT * FROM auth.fn_login('editor_sancarlos','Tec2026!')"
```

Crear un usuario nuevo (central + nodo de su campus):
```bash
./scripts/crear_usuario.sh samuel 'MiClave1!' sancarlos editor "Samuel ..."
```

## Estructura
```
docker-compose.yml        6 nodos PostGIS (central + 5 campus)
config/pg_hba.conf        acceso por red y replicación
initdb/00_sigtec_init.sh  orquesta la inicialización según NODO_TIPO / CAMPUS_ID
sql/comun/                extensiones, catálogos, modelo de capas, roles (todos los nodos)
sql/central/              esquemas réplica, autenticación, usuarios demo
sql/campus/               esquema propio + réplicas, usuarios del nodo, datos ejemplo
sql/estilos/              (Samuel) layer_styles, versiones de estilos, publicación pub_estilos
sql/replicacion/          (Gabo) publicaciones y suscripciones
sql/vistas/               (Gabo) vistas capas.* + INSTEAD OF
plugin/                   (Samuel) complemento PyQGIS
  sigtec/                   el complemento (estilos/*.qml de respaldo, config.json)
  dev/                      vistas TEMPORALES, generadores de estilos/icono, pruebas sin interfaz
  *.ps1                     instalar en el perfil de QGIS / generar el .zip
scripts/                  verificar_nodos, crear_usuario, configurar_estilos, publicar_estilos,
                          configurar_replicacion
scripts/pruebas/          (Gabo) pruebas de replicación, vistas y permisos
scripts/respaldos/        (Justin) pg_dump, pg_basebackup, PITR
docs/                     arquitectura y documentación
```

La arquitectura completa y los contratos entre módulos están en [docs/01_arquitectura.md](docs/01_arquitectura.md). La replicación y las vistas se explican en [docs/02_replicacion_vistas.md](docs/02_replicacion_vistas.md).

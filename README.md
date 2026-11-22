# SIG-TEC — Sistema Distribuido de Gestión de Información Geográfica de los Campus del TEC

Proyecto 3 · Bases de Datos II · TEC San Carlos · Entrega: lunes 30/11/2026 08:00

Equipo: Samuel · Gabo · Andrés · Justin — ver [división del trabajo](docs/00_division_trabajo.md).

## Requisitos
- Docker Desktop (o Docker Engine + compose v2)
- QGIS 3.28+ (LTR recomendado)
- En Windows: clonar con `git config core.autocrlf input` (los `.sh` deben quedar en LF).

## Levantar los 6 nodos
```bash
cp .env.example .env          # opcional: cambiar contraseñas
docker compose up -d
docker compose ps             # esperar a que los 6 estén "healthy"
./scripts/verificar_nodos.sh
```
La primera vez cada nodo ejecuta `initdb/00_sigtec_init.sh`, que crea extensiones, catálogos, las 8 capas en los 5 esquemas, roles, usuarios demo y datos de ejemplo.

> Los scripts de init **solo corren con el volumen vacío**. Si cambian algo en `sql/`, reiniciar desde cero con:
> `docker compose down -v && rm -rf wal_archive backups && docker compose up -d`
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
sql/replicacion/          (Gabo) publicaciones y suscripciones
sql/vistas/               (Gabo) vistas capas.* + INSTEAD OF
plugin/                   (Andrés) complemento PyQGIS
scripts/respaldos/        (Justin) pg_dump, pg_basebackup, PITR
docs/                     arquitectura y documentación
```

La arquitectura completa y los contratos entre módulos están en [docs/01_arquitectura.md](docs/01_arquitectura.md).

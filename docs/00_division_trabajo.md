# SIG-TEC — División del trabajo

Entrega: **lunes 30 de noviembre 2026, 08:00 am** (cada hora tarde = −10 %).
Meta interna: todo integrado el **sábado 28** y entregado el **domingo 29 en la noche**.

## Reparto por rubro de evaluación

| Integrante | Módulo | Rubros (peso) | Entregables principales |
|---|---|---|---|
| **Samuel** | Arquitectura, infraestructura y modelo geográfico | Diseño de arquitectura y modelo geográfico (15 %) · Implementación de los 5 nodos y estructura PostGIS (15 %) | `docker-compose.yml`, `config/`, `initdb/`, `sql/comun`, `sql/central`, `sql/campus`, `docs/01_arquitectura.md` |
| **Gabo** | Replicación lógica y vistas distribuidas | Replicación lógica y vistas distribuidas (20 %) | `sql/replicacion/` (Nivel 1 y Nivel 2), `sql/vistas/` (vistas `capas.*` + disparadores INSTEAD OF), `scripts/configurar_replicacion.sh` |
| **Andrés** | Complemento PyQGIS y edición desde QGIS | Edición geográfica desde QGIS y complemento PyQGIS (20 %) | `plugin/sigtec/` (ventana de login, conexión al nodo, carga automática de capas), estilos en `layer_styles` del central, formularios/value maps en QGIS |
| **Justin** | Transacciones distribuidas, respaldos y recuperación + documento final y video | Transacciones distribuidas, respaldos y recuperación (20 %) · Documentación y demostración integral (10 %) | `scripts/respaldos/` (pg_dump, pg_basebackup, archivado WAL, PITR), transacciones 2PC entre nodos, pruebas de recuperación ante falla simulada · documento final integrado · video (≤ 10 min) |

**Documentación:** cada quien escribe la sección de su propio módulo en `docs/` (Samuel: `01_arquitectura.md`). Justin las integra en el documento final y graba el video. El enunciado no exige que salgan todos en el video.

## Dependencias

```
Samuel (nodos + esquemas + auth)  ──►  Gabo (replicación ──► vistas + INSTEAD OF)  ──►  Andrés (carga de vistas y edición)
          │                                                                     ▲
          └──►  Justin (respaldos/PITR: puede empezar ya)     Andrés (login): puede empezar ya contra auth.fn_login
```

- **Gabo** depende de que existan los esquemas idénticos en todos los nodos → ya están.
- **Andrés** puede hacer el login hoy mismo (`auth.fn_login` ya funciona). Para la carga de capas usa temporalmente las tablas físicas hasta que Gabo publique las vistas `capas.*`.
- **Justin** puede empezar ya: el archivado WAL, el usuario `replicador` y `max_prepared_transactions` ya vienen configurados.

## Cronograma

| Fecha | Samuel | Gabo | Andrés | Justin |
|---|---|---|---|---|
| Dom 22 | Repo base arriba; todos levantan los 6 nodos | Levantar nodos, diseñar publicaciones | Levantar nodos, esqueleto del plugin | Levantar nodos, pg_dump por nodo |
| Lun 23 – Mar 24 | Documento de arquitectura, apoyo | Nivel 1 (campus → central) y Nivel 2 (central → campus) | Login + conexión al nodo del campus | pg_basebackup + archivado WAL |
| Mié 25 – Jue 26 | Integración y pruebas cruzadas | Vistas `capas.*` + INSTEAD OF | Carga automática de vistas + estilos en BD | PITR + transacciones 2PC |
| Vie 27 | Prueba de punta a punta | Ajustes | Ajustes | Simulacro de caída y recuperación de un nodo |
| Sáb 28 | Doc. de su módulo (a Justin) | Doc. de su módulo (a Justin) | Doc. de su módulo (a Justin) | Integra el documento final + guion del video |
| Dom 29 | Revisión del documento y del video | Revisión | Revisión | Graba el video + entrega en Moodle |

## Convenciones del repositorio

- Una rama por módulo (`infra`, `replicacion`, `plugin`, `respaldos`), merge a `main` por PR.
- SQL nuevo en carpetas numeradas; nunca editar a mano una BD sin dejar el script.
- Las convenciones técnicas (nombres de esquemas, publicaciones, vistas, roles) están en `docs/01_arquitectura.md` — **son el contrato entre módulos**.

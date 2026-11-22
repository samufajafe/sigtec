# SIG-TEC — División del trabajo

Entrega: **lunes 30 de noviembre 2026, 08:00 am** (cada hora tarde = −10 %).
Meta interna: todo integrado el **sábado 28** y entregado el **domingo 29 en la noche**.

## Reparto por rubro de evaluación

| Integrante | Módulo | Rubros (peso) | Entregables principales |
|---|---|---|---|
| **Samuel** | Arquitectura, infraestructura y modelo geográfico (base lista) + complemento PyQGIS y edición desde QGIS | Diseño de arquitectura y modelo geográfico (15 %) · Implementación de los 5 nodos y estructura PostGIS (15 %) · Edición geográfica desde QGIS y complemento PyQGIS (20 %) | Base (lista): `docker-compose.yml`, `config/`, `initdb/`, `sql/comun`, `sql/central`, `sql/campus`, `docs/01_arquitectura.md` · Plugin: `plugin/sigtec/` (ventana de login, conexión al nodo, carga automática de capas), estilos en `layer_styles` del central, formularios/value maps en QGIS |
| **Gabo** | Replicación lógica y vistas distribuidas | Replicación lógica y vistas distribuidas (20 %) | `sql/replicacion/` (Nivel 1 y Nivel 2), `sql/vistas/` (vistas `capas.*` + disparadores INSTEAD OF), `scripts/configurar_replicacion.sh` |
| **Justin** | Transacciones distribuidas, respaldos y recuperación + documento final y video | Transacciones distribuidas, respaldos y recuperación (20 %) · Documentación y demostración integral (10 %) | `scripts/respaldos/` (pg_dump, pg_basebackup, archivado WAL, PITR), transacciones 2PC entre nodos, pruebas de recuperación ante falla simulada · documento final integrado · video (≤ 10 min) |

**Documentación:** cada quien escribe la sección de su propio módulo en `docs/` (Samuel: `01_arquitectura.md` y la sección del complemento). Justin las integra en el documento final y graba el video. El enunciado no exige que salgan todos en el video.

## Dependencias

```
Samuel (nodos + esquemas + auth)  ──►  Gabo (replicación ──► vistas + INSTEAD OF)  ──►  Samuel (plugin: carga de vistas y edición)
          │
          ├──►  Samuel (plugin: login) — puede empezar ya contra auth.fn_login
          └──►  Justin (respaldos/PITR: puede empezar ya)
```

- **Gabo** depende de que existan los esquemas idénticos en todos los nodos → ya están.
- **Samuel (plugin)** puede hacer el login ya (`auth.fn_login` ya funciona). Para la carga de capas usa temporalmente las tablas físicas hasta que Gabo publique las vistas `capas.*`.
- **Justin** puede empezar ya: el archivado WAL, el usuario `replicador` y `max_prepared_transactions` ya vienen configurados.

## Cronograma

| Fecha | Samuel | Gabo | Justin |
|---|---|---|---|
| Dom 22 | Repo base arriba (todos levantan los 6 nodos); esqueleto del plugin | Levantar nodos, diseñar publicaciones | Levantar nodos, pg_dump por nodo |
| Lun 23 – Mar 24 | Plugin: login + conexión al nodo del campus; documento de arquitectura | Nivel 1 (campus → central) y Nivel 2 (central → campus) | pg_basebackup + archivado WAL |
| Mié 25 – Jue 26 | Plugin: carga automática de vistas + estilos en BD; integración y pruebas cruzadas | Vistas `capas.*` + INSTEAD OF | PITR + transacciones 2PC |
| Vie 27 | Prueba de punta a punta; ajustes del plugin | Ajustes | Simulacro de caída y recuperación de un nodo |
| Sáb 28 | Doc. de su módulo: arquitectura + plugin (a Justin) | Doc. de su módulo (a Justin) | Integra el documento final + guion del video |
| Dom 29 | Revisión del documento y del video | Revisión | Graba el video + entrega en Moodle |

## Convenciones del repositorio

- Una rama por módulo, merge a `main` por PR: `infra` y `plugin` (Samuel), `replicacion` (Gabo), `respaldos` (Justin).
- SQL nuevo en carpetas numeradas; nunca editar a mano una BD sin dejar el script.
- Las convenciones técnicas (nombres de esquemas, publicaciones, vistas, roles) están en `docs/01_arquitectura.md` — **son el contrato entre módulos**.

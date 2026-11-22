-- =====================================================================
-- SIG-TEC | 00 - Extensiones y esquema base (todos los nodos)
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Esquema "sig": catálogos y funciones institucionales (NO se replica,
-- se crea igual en cada nodo por este script).
CREATE SCHEMA IF NOT EXISTS sig;
COMMENT ON SCHEMA sig IS 'SIG-TEC: catálogos, funciones y utilidades comunes del sistema';

-- Esquema "capas": aquí van las VISTAS distribuidas que QGIS carga
-- (las crea el módulo de vistas/INSTEAD OF). Se deja creado desde ya.
CREATE SCHEMA IF NOT EXISTS capas;
COMMENT ON SCHEMA capas IS 'SIG-TEC: vistas integradas (una por capa) que consume QGIS';

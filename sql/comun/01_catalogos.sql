-- =====================================================================
-- SIG-TEC | 01 - Catálogos institucionales (todos los nodos)
--   sig.campus      : los 5 campus, su esquema y punto de referencia
--   sig.capa        : las 8 capas comunes y su tipo de geometría
--   sig.nodo_local  : identidad de ESTE nodo (a qué campus pertenece)
-- Variables psql: :campus_id (0 = central), :nodo_tipo (central|campus)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Sistema de referencia institucional: CR05 / CRTM05 (EPSG:5367)
-- Proyección oficial de Costa Rica (Decreto 33797-MJ-MOPT). Unidades: metros.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sig.fn_srid()
RETURNS integer LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT 5367 $$;
COMMENT ON FUNCTION sig.fn_srid() IS 'SRID institucional SIG-TEC: 5367 (CR05/CRTM05)';

-- Normaliza cualquier geometría al SRID institucional.
--   * SRID 0 (sin definir)  -> se asume que ya viene en CRTM05
--   * Otro SRID (ej. 4326)  -> se transforma con ST_Transform
-- La usan los disparadores INSTEAD OF antes de insertar/actualizar.
CREATE OR REPLACE FUNCTION sig.fn_a_srid_institucional(p_geom geometry)
RETURNS geometry LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
BEGIN
  IF p_geom IS NULL THEN
    RETURN NULL;
  ELSIF ST_SRID(p_geom) = 0 THEN
    RETURN ST_SetSRID(p_geom, sig.fn_srid());
  ELSIF ST_SRID(p_geom) <> sig.fn_srid() THEN
    RETURN ST_Transform(p_geom, sig.fn_srid());
  END IF;
  RETURN p_geom;
END $$;

-- ---------------------------------------------------------------------
-- Catálogo de campus
-- ---------------------------------------------------------------------
CREATE TABLE sig.campus (
  campus_id   smallint PRIMARY KEY CHECK (campus_id BETWEEN 1 AND 5),
  codigo      text NOT NULL UNIQUE,            -- también es el nombre del esquema
  nombre      text NOT NULL,
  ubicacion   text NOT NULL,
  centro      geometry(Point, 5367) NOT NULL   -- punto de referencia aproximado
);
COMMENT ON TABLE sig.campus IS 'Campus del TEC. codigo = nombre del esquema físico de sus datos';

-- Coordenadas WGS84 aproximadas de cada campus, transformadas a CRTM05.
INSERT INTO sig.campus (campus_id, codigo, nombre, ubicacion, centro)
SELECT id, cod, nom, ubi, ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 5367)
FROM (VALUES
  (1, 'cartago',   'Campus Tecnológico Central Cartago',        'Cartago',            -83.9126,  9.8557),
  (2, 'sanjose',   'Campus Tecnológico Local San José',         'Barrio Amón, San José', -84.0763, 9.9376),
  (3, 'sancarlos', 'Campus Tecnológico Local San Carlos',       'Santa Clara, San Carlos', -84.5111, 10.3627),
  (4, 'alajuela',  'Campus Tecnológico Local Alajuela',         'Alajuela',           -84.2128, 10.0175),
  (5, 'limon',     'Campus Tecnológico Local Limón',            'Limón',              -83.0300,  9.9890)
) AS v(id, cod, nom, ubi, lon, lat);

-- Devuelve el nombre de esquema de un campus.
CREATE OR REPLACE FUNCTION sig.fn_esquema_campus(p_campus_id smallint)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT codigo FROM sig.campus WHERE campus_id = p_campus_id
$$;

-- ---------------------------------------------------------------------
-- Catálogo de capas comunes (lo usa el complemento PyQGIS para saber
-- qué vistas cargar, y estilos para asociar simbología)
-- ---------------------------------------------------------------------
CREATE TABLE sig.capa (
  capa_codigo   text PRIMARY KEY,        -- nombre de tabla física y de vista
  nombre        text NOT NULL,           -- nombre visible en QGIS
  tipo_geom     text NOT NULL CHECK (tipo_geom IN ('POINT','LINESTRING','POLYGON')),
  orden         smallint NOT NULL UNIQUE, -- orden de dibujo en QGIS (1 = abajo)
  descripcion   text
);

INSERT INTO sig.capa (capa_codigo, nombre, tipo_geom, orden, descripcion) VALUES
  ('zonas_verdes',   'Zonas verdes',      'POLYGON',    1, 'Áreas verdes y tipo de vegetación'),
  ('parqueos',       'Parqueos',          'POLYGON',    2, 'Estacionamientos, capacidad y disponibilidad'),
  ('edificios',      'Edificios',         'POLYGON',    3, 'Edificaciones del campus'),
  ('carreteras',     'Carreteras',        'LINESTRING', 4, 'Vías vehiculares'),
  ('aceras',         'Aceras',            'LINESTRING', 5, 'Aceras peatonales'),
  ('accesibilidad',  'Accesibilidad',     'LINESTRING', 6, 'Rampas y pasos accesibles (Ley 7600)'),
  ('iluminacion',    'Iluminación',       'POINT',      7, 'Luminarias'),
  ('puntos_interes', 'Puntos de interés', 'POINT',      8, 'Cajeros, laboratorios, sodas, etc.');

-- ---------------------------------------------------------------------
-- Identidad del nodo. Tabla de una sola fila; solo el superusuario la
-- modifica. Se usa una tabla (y no un parámetro SET) para que un usuario
-- no pueda "hacerse pasar" por otro campus cambiando una variable de sesión.
-- ---------------------------------------------------------------------
CREATE TABLE sig.nodo_local (
  unico      boolean PRIMARY KEY DEFAULT true CHECK (unico),
  campus_id  smallint REFERENCES sig.campus(campus_id),   -- NULL en el central
  tipo       text NOT NULL CHECK (tipo IN ('central','campus')),
  CHECK ((tipo = 'central') = (campus_id IS NULL))
);

INSERT INTO sig.nodo_local (campus_id, tipo)
VALUES (NULLIF(:campus_id, 0)::smallint, :'nodo_tipo');

-- campus_id del nodo actual (NULL en el central). Base de las
-- restricciones de edición de los disparadores INSTEAD OF.
CREATE OR REPLACE FUNCTION sig.fn_campus_local()
RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT campus_id FROM sig.nodo_local
$$;

CREATE OR REPLACE FUNCTION sig.fn_esquema_local()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT c.codigo FROM sig.nodo_local n JOIN sig.campus c USING (campus_id)
$$;

-- =====================================================================
-- SIG-TEC | 02 - Modelo geográfico (todos los nodos)
--
-- sig.fn_crear_capas(campus_id, es_local) crea el esquema del campus
-- (cartago, sanjose, sancarlos, alajuela, limon) con las 8 tablas físicas.
--
--   es_local = true  -> el nodo es DUEÑO de esos datos: se crea la
--                       secuencia de ID global y el disparador de auditoría.
--   es_local = false -> el esquema es una RÉPLICA de solo consulta que se
--                       llena por replicación lógica.
--
-- Como todos los nodos usan exactamente la misma estructura
-- (mismo esquema, mismo nombre de tabla, mismas columnas), la replicación
-- lógica funciona directo entre ellos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auditoría: fecha y usuario de la última modificación (solo tablas locales;
-- los disparadores normales no se ejecutan en el proceso de replicación).
-- Se usa session_user para registrar al usuario real aunque el cambio
-- pase por una función SECURITY DEFINER.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sig.fn_tg_auditoria()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.creado_en := now();
  ELSE
    NEW.creado_en := OLD.creado_en;   -- no se permite alterar la fecha de creación
  END IF;
  NEW.actualizado_en  := now();
  NEW.actualizado_por := session_user;
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------
-- Creación de las 8 capas de un campus
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sig.fn_crear_capas(p_campus_id smallint, p_es_local boolean)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  e        text := sig.fn_esquema_campus(p_campus_id);
  srid     int  := sig.fn_srid();
  id_ini   bigint := p_campus_id::bigint * 1000000000 + 1;
  id_fin   bigint := p_campus_id::bigint * 1000000000 + 999999999;
  col_id   text;
  comunes  text;
  t        record;
BEGIN
  IF e IS NULL THEN
    RAISE EXCEPTION 'Campus % no existe en sig.campus', p_campus_id;
  END IF;

  EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', e);
  EXECUTE format('COMMENT ON SCHEMA %I IS %L', e,
    CASE WHEN p_es_local
         THEN 'Datos PROPIOS del campus (editables en este nodo)'
         ELSE 'Réplica de solo consulta (replicación lógica)' END);

  -- ID global: una secuencia por campus compartida por sus 8 capas.
  -- Rango reservado por campus => nunca hay colisiones entre nodos.
  --   Cartago 1 000 000 001..1 999 999 999, San José 2 000 000 001.., etc.
  IF p_es_local THEN
    EXECUTE format(
      'CREATE SEQUENCE IF NOT EXISTS %I.seq_id_global AS bigint
         START WITH %s MINVALUE %s MAXVALUE %s NO CYCLE',
      e, id_ini, id_ini, id_fin);
    col_id := format('id bigint PRIMARY KEY DEFAULT nextval(%L)', e || '.seq_id_global');
  ELSE
    col_id := 'id bigint PRIMARY KEY';
  END IF;

  -- Columnas comunes a todas las capas
  comunes := format(
    '%s,
     campus_id smallint NOT NULL DEFAULT %s
               CHECK (campus_id = %s) REFERENCES sig.campus(campus_id),
     creado_en       timestamptz NOT NULL DEFAULT now(),
     actualizado_en  timestamptz NOT NULL DEFAULT now(),
     actualizado_por text        NOT NULL DEFAULT session_user,
     CHECK (id BETWEEN %s AND %s)',
    col_id, p_campus_id, p_campus_id, id_ini, id_fin);

  -- 1. Edificios (Polygon)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.edificios (
      %2$s,
      codigo   text NOT NULL,
      nombre   text NOT NULL,
      pisos    smallint NOT NULL DEFAULT 1 CHECK (pisos BETWEEN 1 AND 30),
      uso      text CHECK (uso IN ('academico','administrativo','laboratorio','biblioteca',
                                   'deportivo','residencia','servicios','otro')),
      area_m2  numeric(12,2) GENERATED ALWAYS AS (round(ST_Area(geom)::numeric, 2)) STORED,
      geom     geometry(Polygon, %3$s) NOT NULL CHECK (ST_IsValid(geom)),
      UNIQUE (campus_id, codigo)
    )$q$, e, comunes, srid);

  -- 2. Carreteras (LineString)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.carreteras (
      %2$s,
      nombre      text,
      tipo        text NOT NULL CHECK (tipo IN ('principal','secundaria','interna','servicio')),
      superficie  text NOT NULL CHECK (superficie IN ('asfalto','concreto','adoquin','lastre','tierra')),
      longitud_m  numeric(12,2) GENERATED ALWAYS AS (round(ST_Length(geom)::numeric, 2)) STORED,
      geom        geometry(LineString, %3$s) NOT NULL
    )$q$, e, comunes, srid);

  -- 3. Aceras (LineString)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.aceras (
      %2$s,
      material    text NOT NULL CHECK (material IN ('concreto','adoquin','asfalto','lastre','otro')),
      ancho_m     numeric(4,2) CHECK (ancho_m > 0),
      condicion   text NOT NULL CHECK (condicion IN ('buena','regular','mala')),
      longitud_m  numeric(12,2) GENERATED ALWAYS AS (round(ST_Length(geom)::numeric, 2)) STORED,
      geom        geometry(LineString, %3$s) NOT NULL
    )$q$, e, comunes, srid);

  -- 4. Parqueos (Polygon)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.parqueos (
      %2$s,
      nombre                text,
      tipo                  text NOT NULL CHECK (tipo IN ('estudiantes','funcionarios','visitantes',
                                                          'discapacidad','motos','bicicletas','mixto')),
      capacidad             integer NOT NULL CHECK (capacidad >= 0),
      espacios_disponibles  integer CHECK (espacios_disponibles BETWEEN 0 AND capacidad),
      area_m2               numeric(12,2) GENERATED ALWAYS AS (round(ST_Area(geom)::numeric, 2)) STORED,
      geom                  geometry(Polygon, %3$s) NOT NULL CHECK (ST_IsValid(geom))
    )$q$, e, comunes, srid);

  -- 5. Zonas verdes (Polygon)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.zonas_verdes (
      %2$s,
      nombre           text,
      tipo_vegetacion  text NOT NULL CHECK (tipo_vegetacion IN ('cesped','arbustos','bosque','jardin','mixta')),
      area_m2          numeric(12,2) GENERATED ALWAYS AS (round(ST_Area(geom)::numeric, 2)) STORED,
      geom             geometry(Polygon, %3$s) NOT NULL CHECK (ST_IsValid(geom))
    )$q$, e, comunes, srid);

  -- 6. Puntos de interés (Point)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.puntos_interes (
      %2$s,
      nombre       text NOT NULL,
      tipo         text NOT NULL CHECK (tipo IN ('cajero','laboratorio','soda','biblioteca','auditorio',
                                                 'oficina','servicio_sanitario','parada_bus','otro')),
      descripcion  text,
      horario      text,
      geom         geometry(Point, %3$s) NOT NULL
    )$q$, e, comunes, srid);

  -- 7. Iluminación (Point)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.iluminacion (
      %2$s,
      codigo        text NOT NULL,
      potencia_w    numeric(7,2) CHECK (potencia_w > 0),
      tipo_lampara  text CHECK (tipo_lampara IN ('led','sodio','halogenuro','fluorescente','solar','otro')),
      estado        text NOT NULL DEFAULT 'funcionando'
                    CHECK (estado IN ('funcionando','danada','mantenimiento')),
      geom          geometry(Point, %3$s) NOT NULL,
      UNIQUE (campus_id, codigo)
    )$q$, e, comunes, srid);

  -- 8. Accesibilidad (LineString)
  EXECUTE format($q$
    CREATE TABLE IF NOT EXISTS %1$I.accesibilidad (
      %2$s,
      tipo             text NOT NULL CHECK (tipo IN ('rampa','paso_accesible','ruta_podotactil',
                                                     'pasamanos','otro')),
      descripcion      text,
      cumple_ley_7600  boolean NOT NULL DEFAULT true,
      estado           text NOT NULL DEFAULT 'buena' CHECK (estado IN ('buena','regular','mala')),
      longitud_m       numeric(12,2) GENERATED ALWAYS AS (round(ST_Length(geom)::numeric, 2)) STORED,
      geom             geometry(LineString, %3$s) NOT NULL
    )$q$, e, comunes, srid);

  -- Índices espaciales, comentarios y auditoría para cada capa
  FOR t IN SELECT capa_codigo, nombre FROM sig.capa ORDER BY orden LOOP
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.%I USING gist (geom)',
                   'idx_' || t.capa_codigo || '_geom', e, t.capa_codigo);
    EXECUTE format('COMMENT ON TABLE %I.%I IS %L', e, t.capa_codigo,
                   t.nombre || ' - ' || initcap(e) ||
                   CASE WHEN p_es_local THEN ' (datos propios)' ELSE ' (réplica)' END);
    IF p_es_local THEN
      EXECUTE format('DROP TRIGGER IF EXISTS tg_auditoria ON %I.%I', e, t.capa_codigo);
      EXECUTE format('CREATE TRIGGER tg_auditoria BEFORE INSERT OR UPDATE ON %I.%I
                      FOR EACH ROW EXECUTE FUNCTION sig.fn_tg_auditoria()', e, t.capa_codigo);
    END IF;
  END LOOP;
END
$fn$;

COMMENT ON FUNCTION sig.fn_crear_capas(smallint, boolean) IS
  'Crea el esquema de un campus con las 8 capas. es_local=true en el nodo dueño, false para réplicas';

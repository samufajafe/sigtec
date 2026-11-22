-- =====================================================================
-- SIG-TEC | Campus 12 - Datos de ejemplo del campus local
-- Genera geometrías alrededor del punto de referencia del campus
-- (sig.campus.centro) para tener algo que ver en QGIS desde el día 1.
-- Las coordenadas son ilustrativas; se reemplazan con la digitalización real.
-- Variable psql: :campus_id
-- =====================================================================
CREATE OR REPLACE FUNCTION sig.fn_cargar_datos_ejemplo(p_campus_id smallint)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  e   text;
  pre text;
  x   double precision;
  y   double precision;
BEGIN
  SELECT codigo, upper(left(codigo, 3)), ST_X(centro), ST_Y(centro)
    INTO e, pre, x, y
  FROM sig.campus WHERE campus_id = p_campus_id;

  -- Edificios (rectángulos en metros, relativos al centro)
  EXECUTE format($q$
    INSERT INTO %I.edificios (codigo, nombre, pisos, uso, geom) VALUES
      ($3 || '-B01', 'Biblioteca',                 2, 'biblioteca',  ST_MakeEnvelope($1-60, $2+10, $1-20, $2+40, 5367)),
      ($3 || '-A01', 'Edificio Académico',         3, 'academico',   ST_MakeEnvelope($1+10, $2+10, $1+70, $2+35, 5367)),
      ($3 || '-L01', 'Laboratorios de Computación',2, 'laboratorio', ST_MakeEnvelope($1+10, $2-45, $1+50, $2-15, 5367))
  $q$, e) USING x, y, pre;

  -- Carreteras
  EXECUTE format($q$
    INSERT INTO %I.carreteras (nombre, tipo, superficie, geom) VALUES
      ('Acceso principal', 'principal', 'asfalto',
        ST_SetSRID(ST_MakeLine(ST_MakePoint($1-150, $2-80), ST_MakePoint($1+150, $2-80)), 5367)),
      ('Calle interna',    'interna',   'concreto',
        ST_SetSRID(ST_MakeLine(ST_MakePoint($1-5, $2-80), ST_MakePoint($1-5, $2+80)), 5367))
  $q$, e) USING x, y;

  -- Aceras
  EXECUTE format($q$
    INSERT INTO %I.aceras (material, ancho_m, condicion, geom) VALUES
      ('concreto', 1.50, 'buena',
        ST_SetSRID(ST_MakeLine(ST_MakePoint($1-60, $2+5), ST_MakePoint($1+70, $2+5)), 5367)),
      ('adoquin',  2.00, 'regular',
        ST_SetSRID(ST_MakeLine(ST_MakePoint($1+5, $2-75), ST_MakePoint($1+5, $2+75)), 5367))
  $q$, e) USING x, y;

  -- Parqueos
  EXECUTE format($q$
    INSERT INTO %I.parqueos (nombre, tipo, capacidad, espacios_disponibles, geom) VALUES
      ('Parqueo principal', 'mixto',        80, 25, ST_MakeEnvelope($1-140, $2-70, $1-70, $2-20, 5367)),
      ('Parqueo Ley 7600',  'discapacidad',  6,  4, ST_MakeEnvelope($1-65,  $2-30, $1-50, $2-15, 5367))
  $q$, e) USING x, y;

  -- Zonas verdes
  EXECUTE format($q$
    INSERT INTO %I.zonas_verdes (nombre, tipo_vegetacion, geom) VALUES
      ('Plaza central', 'cesped', ST_MakeEnvelope($1-45, $2-45, $1-10, $2+0, 5367)),
      ('Área boscosa',  'bosque', ST_MakeEnvelope($1+80, $2-60, $1+150, $2+60, 5367))
  $q$, e) USING x, y;

  -- Puntos de interés
  EXECUTE format($q$
    INSERT INTO %I.puntos_interes (nombre, tipo, descripcion, horario, geom) VALUES
      ('Cajero automático', 'cajero',      'Cajero en vestíbulo de biblioteca', '24 horas',      ST_SetSRID(ST_MakePoint($1-40, $2+8), 5367)),
      ('Soda comedor',      'soda',        'Soda institucional',                'L-V 7:00-19:00', ST_SetSRID(ST_MakePoint($1+40, $2+40), 5367)),
      ('Laboratorio 1',     'laboratorio', 'Laboratorio de cómputo',            'L-S 7:30-21:00', ST_SetSRID(ST_MakePoint($1+30, $2-30), 5367))
  $q$, e) USING x, y;

  -- Iluminación
  EXECUTE format($q$
    INSERT INTO %I.iluminacion (codigo, potencia_w, tipo_lampara, estado, geom) VALUES
      ($3 || '-LUM-001', 100, 'led',   'funcionando',   ST_SetSRID(ST_MakePoint($1-100, $2-78), 5367)),
      ($3 || '-LUM-002', 100, 'led',   'funcionando',   ST_SetSRID(ST_MakePoint($1,     $2-78), 5367)),
      ($3 || '-LUM-003', 150, 'sodio', 'mantenimiento', ST_SetSRID(ST_MakePoint($1+100, $2-78), 5367))
  $q$, e) USING x, y, pre;

  -- Accesibilidad
  EXECUTE format($q$
    INSERT INTO %I.accesibilidad (tipo, descripcion, cumple_ley_7600, estado, geom) VALUES
      ('rampa',          'Rampa de acceso a biblioteca', true, 'buena',
        ST_SetSRID(ST_MakeLine(ST_MakePoint($1-40, $2+5), ST_MakePoint($1-40, $2+10)), 5367)),
      ('paso_accesible', 'Paso del parqueo al edificio académico', true, 'regular',
        ST_SetSRID(ST_MakeLine(ST_MakePoint($1-58, $2-15), ST_MakePoint($1+15, $2+10)), 5367))
  $q$, e) USING x, y;
END
$fn$;

SELECT sig.fn_cargar_datos_ejemplo(:campus_id::smallint);

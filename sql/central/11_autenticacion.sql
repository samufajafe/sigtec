-- =====================================================================
-- SIG-TEC | Central 11 - Autenticación y coordinación
--
-- Flujo (complemento PyQGIS):
--   1. El complemento se conecta al central con el rol "sigtec_login".
--   2. Llama:  SELECT * FROM auth.fn_login('usuario', 'clave');
--   3. Si devuelve una fila: trae el campus del usuario y los datos de
--      conexión de su nodo (host, puerto, base). Si no hay filas: rechazo.
--   4. El complemento abre la conexión al nodo del campus con el mismo
--      usuario/clave y carga las vistas del esquema "capas".
--
-- Variables psql: :login_pass, :host_cliente
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS auth;
COMMENT ON SCHEMA auth IS 'SIG-TEC: usuarios, nodos y bitácora de accesos (solo en el central)';

-- ---------------------------------------------------------------------
-- Nodos: cómo llegar a cada campus
--   host_cliente/puerto_cliente : lo que usa QGIS desde la máquina del usuario
--   host_interno/puerto_interno : lo que usan los nodos entre sí (red docker)
-- ---------------------------------------------------------------------
CREATE TABLE auth.nodo (
  campus_id       smallint PRIMARY KEY REFERENCES sig.campus(campus_id),
  host_cliente    text    NOT NULL,
  puerto_cliente  integer NOT NULL,
  host_interno    text    NOT NULL,
  puerto_interno  integer NOT NULL DEFAULT 5432,
  base_datos      text    NOT NULL DEFAULT 'sigtec',
  activo          boolean NOT NULL DEFAULT true
);

INSERT INTO auth.nodo (campus_id, host_cliente, puerto_cliente, host_interno, base_datos)
SELECT campus_id, :'host_cliente', 5440 + campus_id, 'pg-' || codigo, current_database()
FROM sig.campus;

-- ---------------------------------------------------------------------
-- Usuarios del sistema (contraseña con bcrypt vía pgcrypto)
-- ---------------------------------------------------------------------
CREATE TABLE auth.usuario (
  usuario_id       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  username         text NOT NULL UNIQUE CHECK (username = lower(username) AND username ~ '^[a-z][a-z0-9_]{2,40}$'),
  password_hash    text NOT NULL,
  nombre_completo  text NOT NULL,
  correo           text,
  campus_id        smallint NOT NULL REFERENCES sig.campus(campus_id),
  rol              text NOT NULL CHECK (rol IN ('editor','consulta')),
  activo           boolean NOT NULL DEFAULT true,
  creado_en        timestamptz NOT NULL DEFAULT now(),
  ultimo_acceso    timestamptz
);

-- ---------------------------------------------------------------------
-- Bitácora de intentos de ingreso
-- ---------------------------------------------------------------------
CREATE TABLE auth.bitacora_acceso (
  acceso_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  username    text NOT NULL,
  exito       boolean NOT NULL,
  motivo      text,
  ip_cliente  inet DEFAULT inet_client_addr(),
  fecha       timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Crear usuario (lo usa scripts/crear_usuario.sh)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth.fn_crear_usuario(
  p_username text, p_password text, p_nombre text,
  p_campus_codigo text, p_rol text DEFAULT 'editor', p_correo text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  v_campus smallint;
  v_id     integer;
BEGIN
  SELECT campus_id INTO v_campus FROM sig.campus WHERE codigo = lower(p_campus_codigo);
  IF v_campus IS NULL THEN
    RAISE EXCEPTION 'Campus "%" no existe (use: cartago, sanjose, sancarlos, alajuela, limon)', p_campus_codigo;
  END IF;
  INSERT INTO auth.usuario (username, password_hash, nombre_completo, correo, campus_id, rol)
  VALUES (lower(p_username), crypt(p_password, gen_salt('bf', 10)), p_nombre, p_correo, v_campus, p_rol)
  RETURNING usuario_id INTO v_id;
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------
-- LOGIN: valida credenciales y devuelve el nodo del campus del usuario.
-- SECURITY DEFINER: el rol sigtec_login no ve las tablas, solo ejecuta esto.
-- Devuelve 0 filas si las credenciales son inválidas o el usuario está inactivo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth.fn_login(p_username text, p_password text)
RETURNS TABLE (
  usuario_id       integer,
  username         text,
  nombre_completo  text,
  rol              text,
  campus_id        smallint,
  campus_codigo    text,
  campus_nombre    text,
  host             text,
  puerto           integer,
  base_datos       text,
  esquema_vistas   text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, auth, sig
AS $$
#variable_conflict use_column
DECLARE
  u auth.usuario%ROWTYPE;
BEGIN
  SELECT * INTO u FROM auth.usuario x WHERE x.username = lower(trim(p_username));

  -- IS DISTINCT FROM (y no <>): con p_password NULL, crypt() devuelve NULL y
  -- "hash <> NULL" es NULL, lo que el IF trataría como "clave correcta".
  IF NOT FOUND OR p_password IS NULL
     OR u.password_hash IS DISTINCT FROM crypt(p_password, u.password_hash) THEN
    INSERT INTO auth.bitacora_acceso (username, exito, motivo)
    VALUES (coalesce(lower(trim(p_username)), ''), false, 'credenciales inválidas');
    RETURN;
  END IF;

  IF NOT u.activo THEN
    INSERT INTO auth.bitacora_acceso (username, exito, motivo)
    VALUES (u.username, false, 'usuario inactivo');
    RETURN;
  END IF;

  UPDATE auth.usuario x SET ultimo_acceso = now() WHERE x.usuario_id = u.usuario_id;
  INSERT INTO auth.bitacora_acceso (username, exito, motivo) VALUES (u.username, true, NULL);

  RETURN QUERY
  SELECT u.usuario_id, u.username, u.nombre_completo, u.rol,
         c.campus_id, c.codigo, c.nombre,
         n.host_cliente, n.puerto_cliente, n.base_datos, 'capas'::text
  FROM sig.campus c
  JOIN auth.nodo n ON n.campus_id = c.campus_id
  WHERE c.campus_id = u.campus_id AND n.activo;
END $$;

COMMENT ON FUNCTION auth.fn_login(text, text) IS
  'Autenticación central SIG-TEC. 1 fila = acceso concedido con datos del nodo; 0 filas = rechazado';

-- ---------------------------------------------------------------------
-- Rol que usa el complemento PyQGIS para autenticar (mínimo privilegio)
-- ---------------------------------------------------------------------
CREATE ROLE sigtec_login WITH LOGIN PASSWORD :'login_pass';
REVOKE ALL ON SCHEMA auth FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA auth FROM PUBLIC;
GRANT USAGE ON SCHEMA auth TO sigtec_login;
GRANT EXECUTE ON FUNCTION auth.fn_login(text, text) TO sigtec_login;
-- Puede leer catálogos de capas/campus (y luego layer_styles en public)
GRANT USAGE ON SCHEMA sig TO sigtec_login;
GRANT SELECT ON sig.capa, sig.campus TO sigtec_login;

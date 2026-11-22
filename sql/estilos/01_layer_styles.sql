-- =====================================================================
-- SIG-TEC | Estilos 01 - Tabla public.layer_styles (TODOS los nodos)
--
-- Estructura EXACTA de la tabla que crea QGIS 3.x/4.x al "Guardar estilo
-- en la base de datos" (verificada dejando que QGIS 4.2 la creara en una
-- base vacía). Si cambia una columna, QGIS deja de reconocerla.
--
-- Fuente de verdad: el nodo CENTRAL. Los campus reciben una copia por la
-- suscripción sub_<campus>_estilos (ver 03_publicacion_central.sql y
-- scripts/configurar_estilos.sh). En los campus es de solo lectura.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.layer_styles (
  id                 serial PRIMARY KEY,
  f_table_catalog    varchar,
  f_table_schema     varchar,
  f_table_name       varchar,
  f_geometry_column  varchar,
  stylename          text,
  styleqml           xml,
  stylesld           xml,
  useasdefault       boolean,
  description        text,
  owner              varchar(63) DEFAULT CURRENT_USER,
  ui                 xml,
  update_time        timestamp DEFAULT CURRENT_TIMESTAMP,
  type               varchar,
  r_raster_column    varchar
);
COMMENT ON TABLE public.layer_styles IS
  'SIG-TEC: estilos QGIS compartidos. Se publican en el central (sig.fn_publicar_estilo) y se replican a los campus (pub_estilos)';

-- ---------------------------------------------------------------------
-- Un solo estilo vigente (useasdefault) por capa.
-- Es un disparador y no un índice único para no interferir con el "Guardar
-- estilo" de QGIS, que al limpiar el vigente anterior filtra también por "type".
-- Los disparadores normales no se ejecutan al aplicar replicación, así que
-- en los campus solo llega el resultado que ya calculó el central.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sig.fn_tg_estilo_vigente_unico()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.layer_styles s
     SET useasdefault = false
   WHERE s.id <> NEW.id
     AND s.useasdefault
     AND s.f_table_catalog   IS NOT DISTINCT FROM NEW.f_table_catalog
     AND s.f_table_schema    IS NOT DISTINCT FROM NEW.f_table_schema
     AND s.f_table_name      IS NOT DISTINCT FROM NEW.f_table_name
     AND s.f_geometry_column IS NOT DISTINCT FROM NEW.f_geometry_column;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS tg_estilo_vigente_unico ON public.layer_styles;
CREATE TRIGGER tg_estilo_vigente_unico
  AFTER INSERT OR UPDATE OF useasdefault ON public.layer_styles
  FOR EACH ROW WHEN (NEW.useasdefault)
  EXECUTE FUNCTION sig.fn_tg_estilo_vigente_unico();

-- ---------------------------------------------------------------------
-- En los nodos de campus la tabla es una réplica: se impide escribir en
-- ella localmente (incluso a postgres desde QGIS), porque un id local
-- chocaría con los que llegan del central y detendría la suscripción.
-- La replicación no dispara este trigger (session_replication_role=replica).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sig.fn_tg_estilos_solo_central()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF sig.fn_campus_local() IS NOT NULL THEN
    RAISE EXCEPTION 'SIG-TEC: los estilos se publican en el nodo central (scripts/publicar_estilos.sh); este nodo solo tiene una copia'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END $$;

DROP TRIGGER IF EXISTS tg_estilos_solo_central ON public.layer_styles;
CREATE TRIGGER tg_estilos_solo_central
  BEFORE INSERT OR UPDATE OR DELETE ON public.layer_styles
  FOR EACH ROW EXECUTE FUNCTION sig.fn_tg_estilos_solo_central();

-- Lectura para todos los usuarios SIG-TEC (QGIS consulta la tabla al cargar
-- capas) y para replicador (copia inicial de la suscripción).
GRANT SELECT ON public.layer_styles TO sigtec_lectura, replicador;

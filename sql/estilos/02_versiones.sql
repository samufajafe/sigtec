-- =====================================================================
-- SIG-TEC | Estilos 02 - Versiones de estilos (TODOS los nodos)
--
-- Convención (sin tablas extra; todo vive en public.layer_styles):
--   * Cada versión es una fila:  stylename = '<capa_codigo> v<N>'
--       f_table_catalog = 'sigtec', f_table_schema = 'capas',
--       f_table_name = <capa_codigo>, f_geometry_column = 'geom', type = NULL
--   * La versión vigente es la única con useasdefault = true
--     (lo garantiza tg_estilo_vigente_unico).
--   * Las versiones anteriores se conservan: se ven en QGIS en
--     Propiedades de la capa > Estilo > Cargar estilo > Base de datos.
--
-- type = NULL a propósito: QGIS busca "type = <tipo del URI> OR type IS NULL",
-- así el estilo aplica aunque la capa se cargue sin tipo de geometría en el URI.
--
-- Las funciones solo se ejecutan en el central (en un campus fallan).
-- =====================================================================

-- Publica una nueva versión del estilo de una capa y la deja vigente.
-- Si el QML es idéntico al vigente no crea versión nueva.
CREATE OR REPLACE FUNCTION sig.fn_publicar_estilo(
  p_capa        text,
  p_qml         text,
  p_sld         text DEFAULT NULL,
  p_descripcion text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_nombre_capa text;
  v_vigente     record;
  v_version     integer;
  v_stylename   text;
BEGIN
  IF sig.fn_campus_local() IS NOT NULL THEN
    RAISE EXCEPTION 'Los estilos se publican en el nodo central, no en un campus';
  END IF;

  SELECT nombre INTO v_nombre_capa FROM sig.capa WHERE capa_codigo = p_capa;
  IF v_nombre_capa IS NULL THEN
    RAISE EXCEPTION 'La capa "%" no existe en sig.capa', p_capa;
  END IF;

  SELECT id, stylename, styleqml::text AS qml INTO v_vigente
  FROM public.layer_styles
  WHERE f_table_catalog = current_database() AND f_table_schema = 'capas'
    AND f_table_name = p_capa AND f_geometry_column = 'geom' AND useasdefault
  ORDER BY update_time DESC, id DESC LIMIT 1;

  IF FOUND AND v_vigente.qml = p_qml THEN
    RETURN 'sin cambios: ' || v_vigente.stylename;
  END IF;

  SELECT coalesce(max(substring(stylename FROM ' v([0-9]+)$')::integer), 0) + 1
    INTO v_version
  FROM public.layer_styles
  WHERE f_table_catalog = current_database() AND f_table_schema = 'capas'
    AND f_table_name = p_capa AND stylename ~ ('^' || p_capa || ' v[0-9]+$');

  v_stylename := p_capa || ' v' || v_version;

  INSERT INTO public.layer_styles
    (f_table_catalog, f_table_schema, f_table_name, f_geometry_column,
     stylename, styleqml, stylesld, useasdefault, description, type)
  VALUES
    (current_database(), 'capas', p_capa, 'geom',
     v_stylename, p_qml::xml, p_sld::xml, true,
     format('SIG-TEC · %s · versión %s%s', v_nombre_capa, v_version,
            coalesce(' · ' || nullif(p_descripcion, ''), '')),
     NULL);

  RETURN 'publicado: ' || v_stylename;
END $$;

-- Vuelve a dejar vigente una versión anterior (rollback de estilo).
CREATE OR REPLACE FUNCTION sig.fn_activar_estilo(p_capa text, p_version integer)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_id integer;
BEGIN
  IF sig.fn_campus_local() IS NOT NULL THEN
    RAISE EXCEPTION 'Los estilos se administran en el nodo central, no en un campus';
  END IF;

  UPDATE public.layer_styles SET useasdefault = true
  WHERE f_table_catalog = current_database() AND f_table_schema = 'capas'
    AND f_table_name = p_capa AND stylename = p_capa || ' v' || p_version
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No existe la versión % del estilo de "%"', p_version, p_capa;
  END IF;
  RETURN 'vigente: ' || p_capa || ' v' || p_version;
END $$;

REVOKE ALL ON FUNCTION sig.fn_publicar_estilo(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sig.fn_activar_estilo(text, integer) FROM PUBLIC;

-- Listado legible de versiones (en cualquier nodo).
CREATE OR REPLACE VIEW sig.v_estilos AS
SELECT f_table_name                                          AS capa,
       substring(stylename FROM ' v([0-9]+)$')::integer      AS version,
       coalesce(useasdefault, false)                         AS vigente,
       stylename, description, owner, update_time,
       length(styleqml::text)                                AS bytes_qml,
       stylesld IS NOT NULL                                  AS tiene_sld
FROM public.layer_styles
WHERE f_table_schema = 'capas'
ORDER BY f_table_name, version DESC NULLS LAST;

GRANT SELECT ON sig.v_estilos TO sigtec_lectura;

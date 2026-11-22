-- =====================================================================
-- SIG-TEC | Vistas 20 - capas.<capa> para las 8 capas de sig.capa
--
-- Cada vista es un UNION ALL de los 5 esquemas con las columnas de la
-- tabla física. En los campus lleva el disparador INSTEAD OF y permisos de
-- edición para sigtec_editor. En el central es solo de consulta: un
-- UNION ALL sin disparador no admite INSERT, UPDATE ni DELETE.
--
-- geom se expone como "geometry" sin tipo ni SRID declarados. Si la vista
-- conservara geometry(Polygon,5367), PostgreSQL rechazaría un INSERT en
-- 4326 antes de llegar al disparador que lo transforma. El cast no impide
-- usar el índice GiST. Los datos almacenados siempre están en 5367.
--
-- Idempotente: se puede ejecutar varias veces.
-- =====================================================================
CREATE OR REPLACE FUNCTION sig.fn_crear_vista_capa(p_capa text)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
  v_columnas text;
  v_consulta text;
BEGIN
  SELECT string_agg(CASE WHEN a.attname = 'geom' THEN 'geom::geometry AS geom'
                         ELSE quote_ident(a.attname) END, ', ' ORDER BY a.attnum)
    INTO v_columnas
  FROM pg_attribute a
  WHERE a.attrelid = format('cartago.%I', p_capa)::regclass
    AND a.attnum > 0 AND NOT a.attisdropped;

  SELECT string_agg(format('SELECT %s FROM %I.%I', v_columnas, codigo, p_capa),
                    E'\nUNION ALL\n' ORDER BY campus_id)
    INTO v_consulta
  FROM sig.campus;

  -- Las vistas temporales del complemento (COMMENT 'TEMPORAL...') declaran
  -- geom con tipo y SRID, y CREATE OR REPLACE no puede cambiar ese tipo.
  IF coalesce(obj_description(to_regclass(format('capas.%I', p_capa)), 'pg_class'), '')
     LIKE 'TEMPORAL%' THEN
    EXECUTE format('DROP VIEW capas.%I', p_capa);
  END IF;

  EXECUTE format('CREATE OR REPLACE VIEW capas.%I AS %s', p_capa, v_consulta);
  EXECUTE format('COMMENT ON VIEW capas.%I IS %L', p_capa,
                 'Capa integrada de los 5 campus. Clave: id. Geometría: geom (SRID 5367)');
  EXECUTE format('GRANT SELECT ON capas.%I TO sigtec_lectura', p_capa);

  IF sig.fn_campus_local() IS NOT NULL THEN
    EXECUTE format('GRANT INSERT, UPDATE, DELETE ON capas.%I TO sigtec_editor', p_capa);
    EXECUTE format('CREATE OR REPLACE TRIGGER tg_capa_editar
                    INSTEAD OF INSERT OR UPDATE OR DELETE ON capas.%I
                    FOR EACH ROW EXECUTE FUNCTION sig.fn_tg_capa_editar()', p_capa);
  END IF;
END
$fn$;

REVOKE ALL ON FUNCTION sig.fn_crear_vista_capa(text) FROM PUBLIC;

SELECT sig.fn_crear_vista_capa(capa_codigo) FROM sig.capa ORDER BY orden;

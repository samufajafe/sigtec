-- =====================================================================
-- ⚠️  TEMPORAL — SOLO PARA DESARROLLAR Y PROBAR EL COMPLEMENTO  ⚠️
--
-- Crea capas.<capa> como UNION ALL de los 5 esquemas, de SOLO LECTURA
-- (sin disparadores INSTEAD OF). Las vistas reales las hace Gabo en
-- sql/vistas/ y deben reemplazar a estas.
--
-- Cada vista queda con un COMMENT que empieza con 'TEMPORAL', y
-- quitar_vistas_temporales.sql solo borra las que lo tengan.
-- Se aplica en los nodos de CAMPUS (en el central no hay vistas capas.*):
--   ./plugin/dev/aplicar_vistas_temporales.sh
-- =====================================================================
DO $$
DECLARE
  c       record;
  cuerpo  text;
  actual  text;
BEGIN
  FOR c IN SELECT capa_codigo FROM sig.capa ORDER BY orden LOOP
    -- No pisar una vista real (sin el comentario TEMPORAL)
    SELECT obj_description(format('capas.%I', c.capa_codigo)::regclass, 'pg_class')
      INTO actual
    FROM pg_class k JOIN pg_namespace n ON n.oid = k.relnamespace
    WHERE n.nspname = 'capas' AND k.relname = c.capa_codigo;

    IF FOUND AND coalesce(actual, '') NOT LIKE 'TEMPORAL%' THEN
      RAISE NOTICE 'capas.% ya existe y no es temporal: no se toca', c.capa_codigo;
      CONTINUE;
    END IF;

    SELECT string_agg(format('SELECT * FROM %I.%I', codigo, c.capa_codigo),
                      E'\n  UNION ALL ' ORDER BY campus_id)
      INTO cuerpo
    FROM sig.campus;

    EXECUTE format('CREATE OR REPLACE VIEW capas.%I AS %s', c.capa_codigo, cuerpo);
    EXECUTE format('COMMENT ON VIEW capas.%I IS %L', c.capa_codigo,
      'TEMPORAL (plugin/dev/vistas_temporales.sql): solo lectura, sin INSTEAD OF. '
      'Se reemplaza por las vistas de sql/vistas/.');
    EXECUTE format('GRANT SELECT ON capas.%I TO sigtec_lectura', c.capa_codigo);
  END LOOP;
END $$;

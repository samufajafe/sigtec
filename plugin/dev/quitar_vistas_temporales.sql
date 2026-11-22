-- =====================================================================
-- Borra SOLO las vistas temporales del complemento (COMMENT 'TEMPORAL...').
-- Las vistas reales de sql/vistas/ (sin ese comentario) no se tocan.
-- Correr antes de crear las vistas reales si cambian columnas u orden.
-- =====================================================================
DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT k.relname
    FROM pg_class k JOIN pg_namespace n ON n.oid = k.relnamespace
    WHERE n.nspname = 'capas' AND k.relkind = 'v'
      AND coalesce(obj_description(k.oid, 'pg_class'), '') LIKE 'TEMPORAL%'
  LOOP
    EXECUTE format('DROP VIEW capas.%I', v.relname);
    RAISE NOTICE 'borrada vista temporal capas.%', v.relname;
  END LOOP;
END $$;

-- =====================================================================
-- SIG-TEC | Desmontaje - PUBLICACIONES y slots de datos de este nodo
-- Ejecutar DESPUÉS de eliminar las suscripciones de todos los nodos.
--
-- Los nombres se derivan de sig.campus y se comparan exactos, para no
-- tocar objetos de otros módulos como pub_estilos o sub_<campus>_estilos.
-- Un slot sin suscriptor retiene WAL indefinidamente, por eso se elimina.
-- Si un walsender sigue conectado, se termina primero: su suscripción ya
-- no existe.
-- =====================================================================
\set ON_ERROR_STOP on

SELECT format('DROP PUBLICATION %I', p.pubname)
FROM pg_publication p
WHERE p.pubname IN (SELECT 'pub_' || codigo FROM sig.campus
                    UNION ALL
                    SELECT 'pub_global_' || codigo FROM sig.campus)
ORDER BY p.pubname
\gexec

DO $$
DECLARE
  v_slots    text[];
  v_slot     text;
  v_intentos int := 0;
BEGIN
  SELECT array_agg(n) INTO v_slots
  FROM (SELECT 'sub_central_' || codigo AS n FROM sig.campus
        UNION ALL
        SELECT 'sub_' || codigo || '_global' FROM sig.campus) x;

  LOOP
    PERFORM pg_terminate_backend(active_pid)
    FROM pg_replication_slots
    WHERE active AND database = current_database() AND slot_name = ANY (v_slots);

    EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_replication_slots
                          WHERE active AND database = current_database()
                            AND slot_name = ANY (v_slots));

    v_intentos := v_intentos + 1;
    IF v_intentos > 50 THEN
      RAISE EXCEPTION 'Hay slots de datos que siguen activos después de 10 s';
    END IF;
    PERFORM pg_sleep(0.2);
  END LOOP;

  FOR v_slot IN
    SELECT slot_name FROM pg_replication_slots
    WHERE database = current_database() AND slot_name = ANY (v_slots)
  LOOP
    PERFORM pg_drop_replication_slot(v_slot);
  END LOOP;
END $$;

-- =====================================================================
-- SIG-TEC | Desmontaje - PUBLICACIONES y slots de este nodo
-- Ejecutar DESPUÉS de eliminar las suscripciones de todos los nodos.
--
-- Un slot sin suscriptor retiene WAL indefinidamente, así que se eliminan
-- los de SIG-TEC: sub_central_*, sub_*_global y los temporales de copia
-- inicial (pg_<id>_sync_*). Si un walsender sigue conectado a uno de ellos
-- se termina primero, porque su suscripción ya no existe.
-- =====================================================================
\set ON_ERROR_STOP on

SELECT format('DROP PUBLICATION %I', pubname)
FROM pg_publication
WHERE pubname LIKE 'pub\_%'
ORDER BY pubname
\gexec

DO $$
DECLARE
  v_slot     text;
  v_intentos int := 0;
BEGIN
  LOOP
    PERFORM pg_terminate_backend(active_pid)
    FROM pg_replication_slots
    WHERE active AND slot_type = 'logical' AND database = current_database()
      AND (slot_name LIKE 'sub\_central\_%' OR slot_name LIKE 'sub\_%\_global'
           OR slot_name LIKE 'pg\_%\_sync\_%');

    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM pg_replication_slots
      WHERE active AND slot_type = 'logical' AND database = current_database()
        AND (slot_name LIKE 'sub\_central\_%' OR slot_name LIKE 'sub\_%\_global'
             OR slot_name LIKE 'pg\_%\_sync\_%'));

    v_intentos := v_intentos + 1;
    IF v_intentos > 50 THEN
      RAISE EXCEPTION 'Hay slots de SIG-TEC que siguen activos después de 10 s';
    END IF;
    PERFORM pg_sleep(0.2);
  END LOOP;

  FOR v_slot IN
    SELECT slot_name FROM pg_replication_slots
    WHERE slot_type = 'logical' AND database = current_database()
      AND (slot_name LIKE 'sub\_central\_%' OR slot_name LIKE 'sub\_%\_global'
           OR slot_name LIKE 'pg\_%\_sync\_%')
  LOOP
    PERFORM pg_drop_replication_slot(v_slot);
  END LOOP;
END $$;

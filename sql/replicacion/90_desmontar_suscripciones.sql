-- =====================================================================
-- SIG-TEC | Desmontaje - UNA suscripción de datos de este nodo
-- Variables psql: :sub (nombre), :slot_existe (1 si el slot sigue en el
-- publicador, 0 si no). Las pasa scripts/configurar_replicacion.sh.
--
-- Con slot: DROP normal, que también limpia los slots de copia inicial.
-- Sin slot: se desasocia antes del DROP, porque un DROP normal FALLA si el
-- slot ya no existe. Es lo que ocurre al restaurar un nodo con PITR.
--
-- No toca las suscripciones de estilos (sub_<campus>_estilos).
-- =====================================================================
\set ON_ERROR_STOP on

\if :slot_existe
SELECT format('DROP SUBSCRIPTION %I', subname)
FROM pg_subscription
WHERE subname = :'sub'
\gexec
\else
SELECT format('ALTER SUBSCRIPTION %I DISABLE', subname),
       format('ALTER SUBSCRIPTION %I SET (slot_name = NONE)', subname),
       format('DROP SUBSCRIPTION %I', subname)
FROM pg_subscription
WHERE subname = :'sub'
\gexec
\endif

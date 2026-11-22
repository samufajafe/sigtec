-- =====================================================================
-- SIG-TEC | Desmontaje - Vacía las RÉPLICAS de este nodo
-- Nunca toca el esquema propio: en un campus excluye sig.fn_esquema_local();
-- en el central (sin esquema propio) vacía las 5 copias.
-- Se niega a correr si el nodo todavía tiene suscripciones de SIG-TEC.
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_subscription
             WHERE subname LIKE 'sub\_central\_%' OR subname LIKE 'sub\_%\_global') THEN
    RAISE EXCEPTION 'Aún hay suscripciones activas en este nodo; no se vacían las réplicas';
  END IF;
END $$;

SELECT format('TRUNCATE %s', string_agg(format('%I.%I', t.schemaname, t.tablename), ', '))
FROM pg_tables t
JOIN sig.campus c ON c.codigo = t.schemaname
WHERE c.codigo IS DISTINCT FROM sig.fn_esquema_local()
HAVING count(*) > 0
\gexec

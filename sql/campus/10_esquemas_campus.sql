-- =====================================================================
-- SIG-TEC | Campus 10 - Esquemas del nodo de campus
--   * Esquema PROPIO  (ej. sancarlos)  : tablas editables, ID global.
--   * 4 esquemas RÉPLICA (los demás)   : solo consulta, se llenan desde
--                                        el central (Nivel 2).
-- Variable psql: :campus_id
-- =====================================================================
SELECT sig.fn_crear_capas(campus_id, campus_id = :campus_id)
FROM sig.campus ORDER BY campus_id;

SELECT sig.fn_otorgar_permisos_esquema(codigo, campus_id = :campus_id)
FROM sig.campus ORDER BY campus_id;

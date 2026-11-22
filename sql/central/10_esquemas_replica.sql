-- =====================================================================
-- SIG-TEC | Central 10 - Esquemas de réplica (Nivel 1)
-- El central mantiene una copia física de los datos de CADA campus en
-- esquemas independientes: cartago, sanjose, sancarlos, alajuela, limon.
-- Todos son de solo consulta; se llenan por suscripción lógica.
-- =====================================================================
SELECT sig.fn_crear_capas(campus_id, false) FROM sig.campus ORDER BY campus_id;
SELECT sig.fn_otorgar_permisos_esquema(codigo, false) FROM sig.campus ORDER BY campus_id;

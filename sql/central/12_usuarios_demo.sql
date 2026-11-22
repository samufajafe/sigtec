-- =====================================================================
-- SIG-TEC | Central 12 - Usuarios de demostración
-- Un editor y un usuario de consulta por campus. La misma contraseña
-- (:demo_pass) se crea como rol de login en el nodo de su campus
-- (campus/11_usuarios_nodo.sql), para que el complemento pueda
-- conectarse al nodo con las mismas credenciales.
-- =====================================================================
SELECT auth.fn_crear_usuario('editor_'   || codigo, :'demo_pass', 'Editor '   || nombre, codigo, 'editor')
FROM sig.campus ORDER BY campus_id;

SELECT auth.fn_crear_usuario('consulta_' || codigo, :'demo_pass', 'Consulta ' || nombre, codigo, 'consulta')
FROM sig.campus ORDER BY campus_id;

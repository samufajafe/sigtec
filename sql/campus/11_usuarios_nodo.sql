-- =====================================================================
-- SIG-TEC | Campus 11 - Roles de login de los usuarios de ESTE campus
-- Deben coincidir con auth.usuario del central (mismo usuario y clave).
-- Variables psql: :campus_id, :demo_pass
-- =====================================================================
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L IN ROLE sigtec_editor',   'editor_'   || codigo, :'demo_pass'),
       format('CREATE ROLE %I LOGIN PASSWORD %L IN ROLE sigtec_lectura',  'consulta_' || codigo, :'demo_pass')
FROM sig.campus WHERE campus_id = :campus_id
\gexec

-- =====================================================================
-- SIG-TEC | Estilos 03 - Publicación de estilos (SOLO nodo central)
--
-- pub_estilos publica únicamente public.layer_styles. Es independiente de
-- las publicaciones de datos (pub_<campus>, pub_global_<campus>), que son
-- FOR TABLES IN SCHEMA <campus> y no incluyen el esquema public.
--
-- Cada campus se suscribe con sub_<campus>_estilos
-- (scripts/configurar_estilos.sh, creada como postgres).
-- =====================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'pub_estilos') THEN
    CREATE PUBLICATION pub_estilos FOR TABLE public.layer_styles;
  END IF;
END $$;

-- El rol del complemento puede leer los estilos del central.
GRANT SELECT ON public.layer_styles TO sigtec_login;

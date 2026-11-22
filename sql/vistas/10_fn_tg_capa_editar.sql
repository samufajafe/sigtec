-- =====================================================================
-- SIG-TEC | Vistas 10 - Disparador INSTEAD OF común a las 8 capas
--
-- Traduce INSERT/UPDATE/DELETE sobre capas.<capa> a la tabla física del
-- esquema local. Reglas:
--   * Solo se escriben filas del campus de este nodo.
--   * campus_id NULL en INSERT -> se usa sig.fn_campus_local().
--   * La geometría se normaliza con sig.fn_a_srid_institucional().
--   * INSERT omite id (secuencia local) y las columnas generadas.
--   * UPDATE no permite cambiar id ni campus_id.
--   * creado_en, actualizado_en y actualizado_por los mantiene tg_auditoria.
--
-- SECURITY DEFINER: los editores no tienen permisos sobre las tablas
-- físicas; solo pueden escribir a través de esta función. El search_path
-- fijo evita que un objeto de otro esquema suplante a uno legítimo.
-- La función devuelve la fila real para que INSERT ... RETURNING (QGIS)
-- reciba el id, las fechas y area_m2/longitud_m calculados.
-- =====================================================================
CREATE OR REPLACE FUNCTION sig.fn_tg_capa_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
  v_campus  smallint := sig.fn_campus_local();
  v_esquema text     := sig.fn_esquema_local();
  v_tabla   text;
  v_todas   text;   -- todas las columnas, en el orden de la vista
  v_cols    text;   -- columnas editables
  v_vals    text;   -- valores para INSERT
  v_set     text;   -- asignaciones para UPDATE
  v_filas   bigint;
BEGIN
  IF v_campus IS NULL OR v_esquema IS NULL THEN
    RAISE EXCEPTION 'El nodo central no admite edición de capas'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM sig.capa WHERE capa_codigo = TG_TABLE_NAME) THEN
    RAISE EXCEPTION 'La vista "%" no corresponde a una capa de SIG-TEC', TG_TABLE_NAME;
  END IF;

  -- Validaciones de pertenencia al campus
  IF TG_OP = 'INSERT' THEN
    NEW.campus_id := coalesce(NEW.campus_id, v_campus);
    IF NEW.campus_id <> v_campus THEN
      RAISE EXCEPTION 'No se puede insertar en %: la fila es del campus %, pero este nodo solo edita el campus % (%)',
        TG_TABLE_NAME, NEW.campus_id, v_campus, v_esquema
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    IF OLD.campus_id <> v_campus THEN
      RAISE EXCEPTION 'No se puede modificar %.id=%: la fila es del campus %, pero este nodo solo edita el campus % (%)',
        TG_TABLE_NAME, OLD.id, OLD.campus_id, v_campus, v_esquema
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'No se permite cambiar el id de una fila (%.id=%)', TG_TABLE_NAME, OLD.id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF NEW.campus_id IS DISTINCT FROM OLD.campus_id THEN
      RAISE EXCEPTION 'No se permite cambiar el campus_id de una fila (%.id=%)', TG_TABLE_NAME, OLD.id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;

  v_tabla := format('%I.%I', v_esquema, TG_TABLE_NAME);

  IF TG_OP = 'DELETE' THEN
    EXECUTE format('DELETE FROM %s WHERE id = $1', v_tabla) USING OLD.id;
    GET DIAGNOSTICS v_filas = ROW_COUNT;
    IF v_filas = 0 THEN RETURN NULL; END IF;
    RETURN OLD;
  END IF;

  -- Las listas de columnas salen del catálogo: un solo disparador sirve
  -- para las 8 capas. En INSERT, un NULL en columna NOT NULL con DEFAULT
  -- toma el valor por defecto de la tabla física.
  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum),
         string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) FILTER (WHERE x.editable),
         string_agg(CASE WHEN a.attnotnull AND d.adbin IS NOT NULL
                         THEN format('coalesce(%s, %s)', x.valor, pg_get_expr(d.adbin, d.adrelid))
                         ELSE x.valor END, ', ' ORDER BY a.attnum) FILTER (WHERE x.editable),
         string_agg(format('%I = %s', a.attname, x.valor), ', ' ORDER BY a.attnum) FILTER (WHERE x.editable)
    INTO v_todas, v_cols, v_vals, v_set
  FROM pg_attribute a
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  CROSS JOIN LATERAL (
    SELECT a.attgenerated = ''
           AND a.attname NOT IN ('id', 'campus_id', 'creado_en', 'actualizado_en', 'actualizado_por') AS editable,
           CASE WHEN a.attname = 'geom'
                THEN 'sig.fn_a_srid_institucional(($1).geom)'
                ELSE format('($1).%I', a.attname) END AS valor
  ) x
  WHERE a.attrelid = v_tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped;

  IF TG_OP = 'INSERT' THEN
    EXECUTE format('INSERT INTO %s (campus_id, %s) VALUES ($2, %s) RETURNING %s',
                   v_tabla, v_cols, v_vals, v_todas)
      INTO NEW USING NEW, v_campus;
    RETURN NEW;
  END IF;

  EXECUTE format('UPDATE %s SET %s WHERE id = $2 RETURNING %s', v_tabla, v_set, v_todas)
    INTO NEW USING NEW, OLD.id;
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas = 0 THEN RETURN NULL; END IF;
  RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION sig.fn_tg_capa_editar() FROM PUBLIC;
COMMENT ON FUNCTION sig.fn_tg_capa_editar() IS
  'INSTEAD OF de capas.*: valida el campus, normaliza el SRID y escribe en el esquema local';

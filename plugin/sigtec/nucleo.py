# -*- coding: utf-8 -*-
"""
SIG-TEC - lógica del complemento sin interfaz gráfica.

  autenticar()    -> valida usuario/clave contra auth.fn_login en el nodo central
  cargar_capas()  -> conecta al nodo del campus y agrega las vistas capas.* al proyecto

Solo usa la API de QGIS (sin psycopg2): las consultas van por
QgsProviderRegistry.providerMetadata('postgres').createConnection(...).executeSql().
Compatible con QGIS 3.34+ (Qt5) y QGIS 4.x (Qt6).
"""
import json
import os
from dataclasses import dataclass, field

from qgis.core import (
    Qgis,
    QgsCoordinateReferenceSystem,
    QgsDataSourceUri,
    QgsDefaultValue,
    QgsMessageLog,
    QgsProject,
    QgsProviderConnectionException,
    QgsProviderRegistry,
    QgsRectangle,
    QgsVectorLayer,
)
from qgis.PyQt.QtXml import QDomDocument

DIR_PLUGIN = os.path.dirname(os.path.abspath(__file__))
DIR_ESTILOS = os.path.join(DIR_PLUGIN, "estilos")
RUTA_CONFIG = os.path.join(DIR_PLUGIN, "config.json")

SRID = 5367
ETIQUETA_LOG = "SIG-TEC"
PROP_GRUPO = "sigtec/grupo"
PROP_CAPA = "sigtec/capa"
PROP_ESTILO = "sigtec/estilo"

CONFIG_POR_DEFECTO = {
    "central": {
        "host": "localhost",
        "puerto": 5440,
        "base_datos": "sigtec",
        "usuario": "sigtec_login",
        "clave": "login2026",
    },
    # medio ancho (m) del recuadro al que se hace zoom alrededor del campus
    "margen_zoom_m": 250,
}


# ---------------------------------------------------------------------
# Errores (cada uno tiene su propio mensaje en el diálogo)
# ---------------------------------------------------------------------
class ErrorSigtec(Exception):
    """Base de los errores del complemento. str(e) es el mensaje para el usuario."""

    def __init__(self, mensaje, detalle=""):
        super().__init__(mensaje)
        self.detalle = detalle


class DatosIncompletos(ErrorSigtec):
    pass


class ErrorConexionCentral(ErrorSigtec):
    pass


class CredencialesInvalidas(ErrorSigtec):
    pass


class ErrorServidor(ErrorSigtec):
    pass


class ErrorConexionNodo(ErrorSigtec):
    pass


# ---------------------------------------------------------------------
# Compatibilidad QGIS 3.x / 4.x
# ---------------------------------------------------------------------
def _enum(clase, enum, miembro, alterno=None):
    """Qgis.WkbType.Point (3.30+/4.x) o el nombre antiguo (QgsWkbTypes.Point)."""
    contenedor = getattr(clase, enum, None)
    if contenedor is not None and hasattr(contenedor, miembro):
        return getattr(contenedor, miembro)
    if alterno is not None:
        return getattr(alterno, miembro)
    return getattr(clase, miembro)


def _tipo_wkb(tipo_geom):
    nombres = {"POINT": "Point", "LINESTRING": "LineString", "POLYGON": "Polygon"}
    try:
        from qgis.core import QgsWkbTypes  # solo existe el viejo en 3.x
    except ImportError:  # pragma: no cover
        QgsWkbTypes = None
    return _enum(Qgis, "WkbType", nombres[tipo_geom], QgsWkbTypes)


def nivel_mensaje(nombre):
    """Qgis.MessageLevel.<nombre> con respaldo a Qgis.<nombre>."""
    return _enum(Qgis, "MessageLevel", nombre)


def log(mensaje, nivel="Info"):
    QgsMessageLog.logMessage(mensaje, ETIQUETA_LOG, nivel_mensaje(nivel))


# ---------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------
def cargar_config(ruta=RUTA_CONFIG):
    """config.json del complemento combinado con los valores por defecto."""
    config = json.loads(json.dumps(CONFIG_POR_DEFECTO))
    if ruta and os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            leido = json.load(f)
        for clave, valor in leido.items():
            if isinstance(valor, dict) and isinstance(config.get(clave), dict):
                config[clave].update(valor)
            elif not clave.startswith("_"):
                config[clave] = valor
    return config


# ---------------------------------------------------------------------
# SQL por la API de QGIS
# ---------------------------------------------------------------------
def literal(valor):
    """Literal SQL seguro (E'...'), sin depender de standard_conforming_strings."""
    if valor is None:
        return "NULL"
    texto = str(valor)
    if "\x00" in texto:
        raise DatosIncompletos("El texto contiene caracteres no válidos.")
    return "E'" + texto.replace("\\", "\\\\").replace("'", "''") + "'"


def _uri_conexion(host, puerto, base, usuario, clave):
    uri = QgsDataSourceUri()
    uri.setConnection(str(host), str(puerto), str(base), str(usuario), str(clave))
    return uri


def abrir_conexion(host, puerto, base, usuario, clave):
    """Conexión de la API de proveedores de QGIS (no abre el socket hasta executeSql)."""
    metadata = QgsProviderRegistry.instance().providerMetadata("postgres")
    if metadata is None:
        raise ErrorSigtec("Este QGIS no tiene el proveedor PostgreSQL.")
    uri = _uri_conexion(host, puerto, base, usuario, clave)
    return metadata.createConnection(uri.uri(False), {})


def ejecutar(conexion, sql):
    """executeSql devolviendo lista de filas (listas de valores Python)."""
    filas = conexion.executeSql(sql)
    return [list(f) for f in (filas or [])]


# ---------------------------------------------------------------------
# Autenticación contra el central
# ---------------------------------------------------------------------
@dataclass
class Sesion:
    usuario_id: int
    username: str
    nombre_completo: str
    rol: str
    campus_id: int
    campus_codigo: str
    campus_nombre: str
    host: str
    puerto: int
    base_datos: str
    esquema_vistas: str
    clave: str = field(default="", repr=False)  # solo en memoria, para conectar al nodo

    @property
    def es_consulta(self):
        return self.rol != "editor"

    def descripcion(self):
        return f"{self.username} ({self.rol}) · {self.campus_nombre}"


COLUMNAS_LOGIN = ("usuario_id, username, nombre_completo, rol, campus_id, campus_codigo, "
                  "campus_nombre, host, puerto, base_datos, esquema_vistas")


def autenticar(usuario, clave, config=None):
    """Valida las credenciales con auth.fn_login. Devuelve una Sesion o lanza ErrorSigtec."""
    config = config or cargar_config()
    usuario = (usuario or "").strip()
    clave = clave or ""
    if not usuario or not clave:
        raise DatosIncompletos("Escriba el usuario y la contraseña.")

    c = config["central"]
    destino = f"{c['host']}:{c['puerto']}"
    try:
        conexion = abrir_conexion(c["host"], c["puerto"], c["base_datos"], c["usuario"], c["clave"])
        ejecutar(conexion, "SELECT 1")
    except QgsProviderConnectionException as e:
        log(f"Sin conexión al central {destino}: {e}", "Warning")
        raise ErrorConexionCentral(
            f"No se puede conectar al servidor central ({destino}). "
            "Verifique que esté encendido y la configuración del complemento (config.json).",
            str(e),
        )

    try:
        filas = ejecutar(
            conexion,
            f"SELECT {COLUMNAS_LOGIN} FROM auth.fn_login({literal(usuario)}, {literal(clave)})",
        )
    except QgsProviderConnectionException as e:
        log(f"Error en auth.fn_login: {e}", "Critical")
        raise ErrorServidor("El servidor central respondió con un error al validar el usuario.", str(e))

    if not filas:
        log(f"Ingreso rechazado para '{usuario}'", "Warning")
        raise CredencialesInvalidas("Usuario o contraseña incorrectos, o el usuario está inactivo.")

    f = filas[0]
    sesion = Sesion(
        usuario_id=int(f[0]), username=str(f[1]), nombre_completo=str(f[2]), rol=str(f[3]),
        campus_id=int(f[4]), campus_codigo=str(f[5]), campus_nombre=str(f[6]),
        host=str(f[7]), puerto=int(f[8]), base_datos=str(f[9]), esquema_vistas=str(f[10]),
        clave=clave,
    )
    log(f"Ingreso concedido: {sesion.descripcion()} -> {sesion.host}:{sesion.puerto}/{sesion.base_datos}")
    return sesion


# ---------------------------------------------------------------------
# Carga de capas en el nodo del campus
# ---------------------------------------------------------------------
@dataclass
class ResultadoCarga:
    grupo: object = None
    capas: list = field(default_factory=list)        # QgsVectorLayer cargadas
    errores: list = field(default_factory=list)      # capas que no se pudieron cargar
    advertencias: list = field(default_factory=list)
    extension: QgsRectangle = None                   # recuadro del campus (EPSG:5367)


def nombre_grupo(sesion):
    return f"SIG-TEC · {sesion.campus_nombre}"


def quitar_grupos_sigtec(proyecto=None):
    """Quita del proyecto los grupos (y sus capas) creados por un ingreso anterior."""
    proyecto = proyecto or QgsProject.instance()
    raiz = proyecto.layerTreeRoot()
    quitados = 0
    for grupo in list(raiz.findGroups(True)):
        if grupo.customProperty(PROP_GRUPO) in (True, "1", "true"):
            ids = grupo.findLayerIds()
            if ids:
                proyecto.removeMapLayers(ids)
            grupo.parent().removeChildNode(grupo)
            quitados += 1
    return quitados


def _estilos_vigentes(conexion):
    """{capa_codigo: (stylename, qml)} con el estilo vigente de cada vista en este nodo."""
    filas = ejecutar(conexion, """
        SELECT DISTINCT ON (f_table_name) f_table_name, stylename, styleqml::text
        FROM public.layer_styles
        WHERE f_table_catalog = current_database() AND f_table_schema = 'capas'
          AND f_geometry_column = 'geom' AND useasdefault
        ORDER BY f_table_name, update_time DESC, id DESC""")
    return {str(f[0]): (str(f[1]), str(f[2])) for f in filas if f[2]}


def aplicar_estilo(capa, codigo, estilos_bd):
    """Aplica el estilo vigente de la BD; si no hay, el .qml del complemento. Devuelve el origen."""
    if codigo in estilos_bd:
        nombre, qml = estilos_bd[codigo]
        doc = QDomDocument()
        doc.setContent(qml)
        if not doc.documentElement().isNull():
            resultado = capa.importNamedStyle(doc)
            ok = resultado[0] if isinstance(resultado, tuple) else bool(resultado)
            if ok:
                capa.setCustomProperty(PROP_ESTILO, f"bd:{nombre}")
                return f"bd:{nombre}"
            log(f"No se pudo aplicar el estilo '{nombre}' de la BD: {resultado}", "Warning")

    ruta = os.path.join(DIR_ESTILOS, f"{codigo}.qml")
    if os.path.exists(ruta):
        resultado = capa.loadNamedStyle(ruta)
        ok = resultado[1] if isinstance(resultado, tuple) else bool(resultado)
        if ok:
            capa.setCustomProperty(PROP_ESTILO, f"qml:{codigo}.qml")
            return f"qml:{codigo}.qml"
    capa.setCustomProperty(PROP_ESTILO, "ninguno")
    return "ninguno"


def crear_capa(sesion, codigo, nombre, tipo_geom):
    """QgsVectorLayer de la vista <esquema_vistas>.<codigo> con clave id, geom, SRID y tipo explícitos."""
    uri = _uri_conexion(sesion.host, sesion.puerto, sesion.base_datos, sesion.username, sesion.clave)
    uri.setDataSource(sesion.esquema_vistas, codigo, "geom", "", "id")
    uri.setKeyColumn("id")
    uri.setSrid(str(SRID))
    uri.setWkbType(_tipo_wkb(tipo_geom))
    # Es una vista: no recorrerla entera para comprobar que id es único (es ID global).
    uri.setParam("checkPrimaryKeyUnicity", "0")
    opciones = QgsVectorLayer.LayerOptions()
    opciones.loadDefaultStyle = False  # el estilo lo elige aplicar_estilo()
    return QgsVectorLayer(uri.uri(False), nombre, "postgres", opciones)


def cargar_capas(sesion, proyecto=None, config=None):
    """Agrega al proyecto las vistas del campus del usuario. Lanza ErrorConexionNodo si no llega al nodo."""
    proyecto = proyecto or QgsProject.instance()
    config = config or cargar_config()
    destino = f"{sesion.host}:{sesion.puerto}/{sesion.base_datos}"

    try:
        conexion = abrir_conexion(sesion.host, sesion.puerto, sesion.base_datos,
                                  sesion.username, sesion.clave)
        capas_def = ejecutar(conexion,
                             "SELECT capa_codigo, nombre, tipo_geom FROM sig.capa ORDER BY orden")
        centro = ejecutar(conexion,
                          f"SELECT ST_X(centro), ST_Y(centro) FROM sig.campus "
                          f"WHERE campus_id = {int(sesion.campus_id)}")
    except QgsProviderConnectionException as e:
        log(f"Sin conexión al nodo {destino}: {e}", "Critical")
        raise ErrorConexionNodo(
            f"El usuario es válido, pero no se puede conectar al nodo del campus "
            f"{sesion.campus_nombre} ({sesion.host}:{sesion.puerto}).",
            str(e),
        )

    resultado = ResultadoCarga()
    try:
        estilos_bd = _estilos_vigentes(conexion)
    except QgsProviderConnectionException as e:
        estilos_bd = {}
        resultado.advertencias.append("No se pudieron leer los estilos de la base de datos; "
                                      "se usan los incluidos en el complemento.")
        log(f"layer_styles no disponible en {destino}: {e}", "Warning")

    quitar_grupos_sigtec(proyecto)
    raiz = proyecto.layerTreeRoot()
    grupo = raiz.insertGroup(0, nombre_grupo(sesion))
    grupo.setCustomProperty(PROP_GRUPO, "1")
    resultado.grupo = grupo

    # sig.capa.orden: 1 = abajo. Se inserta cada capa arriba de la anterior,
    # así la última (puntos) queda en la cima del grupo y se dibuja encima.
    for codigo, nombre, tipo_geom in capas_def:
        codigo, nombre, tipo_geom = str(codigo), str(nombre), str(tipo_geom)
        capa = crear_capa(sesion, codigo, nombre, tipo_geom)
        if not capa.isValid():
            detalle = capa.error().summary() if capa.error() else ""
            resultado.errores.append(f"{nombre} ({sesion.esquema_vistas}.{codigo})")
            log(f"Capa no válida {sesion.esquema_vistas}.{codigo}: {detalle}", "Warning")
            continue

        origen = aplicar_estilo(capa, codigo, estilos_bd)
        capa.setCustomProperty(PROP_CAPA, codigo)

        if sesion.es_consulta:
            capa.setReadOnly(True)
        else:
            # Las capas nuevas nacen con el campus del usuario. Igual lo valida el
            # disparador INSTEAD OF en el servidor; esto solo es comodidad.
            idx = capa.fields().indexOf("campus_id")
            if idx >= 0:
                capa.setDefaultValueDefinition(idx, QgsDefaultValue(str(int(sesion.campus_id))))

        proyecto.addMapLayer(capa, False)
        grupo.insertLayer(0, capa)
        resultado.capas.append(capa)
        log(f"Cargada {sesion.esquema_vistas}.{codigo} (estilo {origen})")

    proyecto.setCrs(QgsCoordinateReferenceSystem(f"EPSG:{SRID}"))
    if centro and centro[0][0] is not None:
        x, y = float(centro[0][0]), float(centro[0][1])
        m = float(config.get("margen_zoom_m", 250))
        resultado.extension = QgsRectangle(x - m, y - m, x + m, y + m)
    return resultado

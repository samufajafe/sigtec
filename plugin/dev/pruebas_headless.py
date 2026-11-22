# -*- coding: utf-8 -*-
"""
SIG-TEC - Pruebas del complemento sin abrir QGIS (Python de QGIS + Qt "offscreen").

Requisitos: los 6 nodos levantados, scripts/configurar_estilos.sh,
scripts/publicar_estilos.sh y las vistas capas.* (reales o plugin/dev/vistas_temporales.sql).

Uso (OSGeo4W Shell / python-qgis.bat):
  python-qgis plugin/dev/pruebas_headless.py               # datos sin replicación
  python-qgis plugin/dev/pruebas_headless.py --replicacion # exige ver los 5 campus en cada capa
"""
import argparse
import os
import sys
import tempfile
import shutil

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(AQUI, "..")))  # carpeta plugin/ -> paquete sigtec

from qgis.core import QgsApplication, QgsProject, QgsVectorLayer  # noqa: E402

APP = QgsApplication([], True)
APP.initQgis()

from qgis.gui import QgsMapCanvas, QgsMessageBar  # noqa: E402
from qgis.PyQt.QtWidgets import QMainWindow  # noqa: E402

from sigtec import nucleo  # noqa: E402
from sigtec.dialogo_login import DialogoLogin  # noqa: E402

CLAVE_DEMO = "Tec2026!"
RESULTADOS = []


def prueba(nombre, condicion, detalle=""):
    RESULTADOS.append((nombre, bool(condicion)))
    print(f"[{'OK' if condicion else 'FALLA'}] {nombre}" + (f"  -> {detalle}" if detalle else ""))


def lanza(funcion, tipo):
    try:
        funcion()
    except tipo as e:
        return e
    except Exception as e:  # otro tipo de error: la prueba falla
        return RuntimeError(f"{type(e).__name__}: {e}")
    return None


def sql_admin(puerto, sql):
    con = nucleo.abrir_conexion("localhost", puerto, "sigtec", "postgres", "postgres")
    return nucleo.ejecutar(con, sql)


class IfaceFalsa:
    """Lo mínimo de QgisInterface que usa el complemento."""

    def __init__(self):
        self._ventana = QMainWindow()
        self._lienzo = QgsMapCanvas(self._ventana)
        self._lienzo.resize(800, 600)
        self._barra = QgsMessageBar(self._ventana)
        self.barra_herramientas, self.menu = [], []

    def mainWindow(self):
        return self._ventana

    def mapCanvas(self):
        return self._lienzo

    def messageBar(self):
        return self._barra

    def addToolBarIcon(self, a):
        self.barra_herramientas.append(a)

    def removeToolBarIcon(self, a):
        self.barra_herramientas.remove(a)

    def addPluginToMenu(self, m, a):
        self.menu.append((m, a))

    def removePluginMenu(self, m, a):
        self.menu.remove((m, a))


def grupos_sigtec():
    return [g for g in QgsProject.instance().layerTreeRoot().findGroups(True)
            if g.customProperty(nucleo.PROP_GRUPO) == "1"]


# =====================================================================
def pruebas_login(config):
    print("\n== Login contra el central ==")
    try:
        s = nucleo.autenticar("editor_sancarlos", CLAVE_DEMO, config)
    except Exception as e:  # noqa
        s = None
        prueba("login correcto devuelve sesión", False, e)
    if s:
        prueba("login correcto devuelve sesión", s.username == "editor_sancarlos",
               f"{s.descripcion()} -> {s.host}:{s.puerto}/{s.base_datos}, vistas en '{s.esquema_vistas}'")
        prueba("sesión: campus 3, puerto 5443, rol editor",
               (s.campus_id, s.puerto, s.rol) == (3, 5443, "editor"))
    e = nucleo.autenticar("  EDITOR_SanCarlos ", CLAVE_DEMO, config)
    prueba("usuario con mayúsculas/espacios se normaliza", e.username == "editor_sancarlos")

    for nombre, (u, c) in {"clave incorrecta": ("editor_sancarlos", "mala"),
                           "usuario inexistente": ("nadie", CLAVE_DEMO),
                           "intento de inyección": ("x' OR '1'='1", "x' OR '1'='1"),
                           "barras invertidas": ("editor_sancarlos\\", "Tec2026!\\")}.items():
        err = lanza(lambda: nucleo.autenticar(u, c, config), nucleo.CredencialesInvalidas)
        prueba(f"login rechazado: {nombre}", isinstance(err, nucleo.CredencialesInvalidas), err)

    antes = sql_admin(5440, "SELECT count(*) FROM auth.bitacora_acceso")[0][0]
    for u, c in (("", CLAVE_DEMO), ("editor_sancarlos", ""), ("   ", "   "), (None, None)):
        err = lanza(lambda: nucleo.autenticar(u, c, config), nucleo.DatosIncompletos)
        prueba(f"vacío rechazado sin consultar: usuario={u!r} clave={c!r}",
               isinstance(err, nucleo.DatosIncompletos), err)
    despues = sql_admin(5440, "SELECT count(*) FROM auth.bitacora_acceso")[0][0]
    prueba("datos vacíos no llegan al servidor (bitácora igual)", antes == despues, f"{antes} -> {despues}")

    nucleo.autenticar("consulta_limon", CLAVE_DEMO, config)
    ultimo = sql_admin(5440, "SELECT username, exito FROM auth.bitacora_acceso ORDER BY acceso_id DESC LIMIT 1")[0]
    prueba("el login queda en auth.bitacora_acceso (no es conexión de solo lectura)",
           ultimo == ["consulta_limon", True], ultimo)

    caido = {"central": dict(config["central"], puerto=5999), "margen_zoom_m": 250}
    err = lanza(lambda: nucleo.autenticar("editor_sancarlos", CLAVE_DEMO, caido), nucleo.ErrorConexionCentral)
    prueba("central apagado -> ErrorConexionCentral", isinstance(err, nucleo.ErrorConexionCentral), err)
    mala = {"central": dict(config["central"], clave="incorrecta"), "margen_zoom_m": 250}
    err = lanza(lambda: nucleo.autenticar("editor_sancarlos", CLAVE_DEMO, mala), nucleo.ErrorConexionCentral)
    prueba("clave de sigtec_login mala -> ErrorConexionCentral", isinstance(err, nucleo.ErrorConexionCentral))
    prueba("mensaje de conexión distinto al de credenciales",
           "No se puede conectar al servidor central" in str(err), str(err))
    return s


def pruebas_capas(config, exigir_5_campus):
    print("\n== Carga de capas (editor_sancarlos) ==")
    s = nucleo.autenticar("editor_sancarlos", CLAVE_DEMO, config)
    r = nucleo.cargar_capas(s, QgsProject.instance(), config)
    prueba("8 capas cargadas y sin errores", len(r.capas) == 8 and not r.errores,
           f"{len(r.capas)} capas, errores={r.errores}")
    prueba("grupo 'SIG-TEC · <campus>'", r.grupo.name() == "SIG-TEC · Campus Tecnológico Local San Carlos",
           r.grupo.name())
    orden = [n.layer().customProperty(nucleo.PROP_CAPA) for n in r.grupo.findLayers()]
    esperado = ["puntos_interes", "iluminacion", "accesibilidad", "aceras", "carreteras",
                "edificios", "parqueos", "zonas_verdes"]
    prueba("orden de dibujo: puntos arriba, polígonos abajo", orden == esperado, " > ".join(orden))
    prueba("CRS del proyecto EPSG:5367", QgsProject.instance().crs().authid() == "EPSG:5367")

    tipos = {"POLYGON": "Polygon", "LINESTRING": "LineString", "POINT": "Point"}
    capas_def = {c: t for c, _, t in nucleo.ejecutar(
        nucleo.abrir_conexion("localhost", 5443, "sigtec", "postgres", "postgres"),
        "SELECT capa_codigo, nombre, tipo_geom FROM sig.capa")}
    for capa in r.capas:
        codigo = capa.customProperty(nucleo.PROP_CAPA)
        from qgis.core import QgsWkbTypes
        tipo = QgsWkbTypes.displayString(capa.wkbType())
        pk = [capa.fields()[i].name() for i in capa.primaryKeyAttributes()]
        por_campus = {}
        for f in capa.getFeatures():
            por_campus[f["campus_id"]] = por_campus.get(f["campus_id"], 0) + 1
        estilo = capa.customProperty(nucleo.PROP_ESTILO)
        idx_area = capa.fields().indexOf("area_m2") if capa.fields().indexOf("area_m2") >= 0 \
            else capa.fields().indexOf("longitud_m")
        ok = (capa.isValid() and capa.crs().authid() == "EPSG:5367"
              and tipo == tipos[capas_def[codigo]] and pk == ["id"]
              and capa.renderer().type() == "categorizedSymbol"
              and str(estilo).startswith("bd:")
              and (idx_area < 0 or capa.editFormConfig().readOnly(idx_area))
              and capa.editFormConfig().readOnly(capa.fields().indexOf("id"))
              and capa.defaultValueDefinition(capa.fields().indexOf("campus_id")).expression() == "3"
              and not capa.readOnly())
        campus_ok = set(por_campus) == {1, 2, 3, 4, 5} if exigir_5_campus else 3 in por_campus
        prueba(f"capa {codigo}: válida, {tipo}, 5367, pk id, estilo BD, formulario", ok,
               f"estilo={estilo}, registros por campus={dict(sorted(por_campus.items()))}")
        prueba(f"capa {codigo}: campus visibles {'(los 5)' if exigir_5_campus else '(propio)'}", campus_ok,
               sorted(por_campus))

    edif = [c for c in r.capas if c.customProperty(nucleo.PROP_CAPA) == "edificios"][0]
    widget = edif.editorWidgetSetup(edif.fields().indexOf("uso"))
    prueba("edificios.uso usa Value Map con 8 valores + nulo",
           widget.type() == "ValueMap" and len(widget.config()["map"]) == 9)
    vig = sql_admin(5443, "SELECT stylename FROM layer_styles WHERE f_table_name='edificios' AND useasdefault")[0][0]
    prueba("se aplica el estilo VIGENTE del nodo", edif.customProperty(nucleo.PROP_ESTILO) == f"bd:{vig}",
           f"{edif.customProperty(nucleo.PROP_ESTILO)} (vigente en el nodo: {vig})")
    centro = sql_admin(5443, "SELECT ST_X(centro), ST_Y(centro) FROM sig.campus WHERE campus_id=3")[0]
    prueba("recuadro de zoom centrado en el campus",
           abs(r.extension.center().x() - centro[0]) < 1 and abs(r.extension.center().y() - centro[1]) < 1,
           r.extension.toString(0))
    total_bbox = sum(1 for c in r.capas for f in c.getFeatures() if f["campus_id"] == 3
                     and r.extension.intersects(f.geometry().boundingBox()))
    prueba("los datos del campus caen dentro del recuadro de zoom", total_bbox > 0, f"{total_bbox} elementos")

    print("\n== Respaldo de estilo y capa inválida ==")
    capa = nucleo.crear_capa(s, "edificios", "Edificios", "POLYGON")
    prueba("sin estilo en BD usa el .qml del complemento",
           nucleo.aplicar_estilo(capa, "edificios", {}) == "qml:edificios.qml"
           and capa.renderer().type() == "categorizedSymbol")
    capa = nucleo.crear_capa(s, "edificios", "Edificios", "POLYGON")
    prueba("QML dañado en BD -> respaldo .qml",
           nucleo.aplicar_estilo(capa, "edificios", {"edificios": ("roto", "<esto no es xml")}) == "qml:edificios.qml")

    vista = open(os.path.join(AQUI, "vistas_temporales.sql"), encoding="utf-8").read()
    es_temporal = sql_admin(5445, "SELECT coalesce(obj_description('capas.aceras'::regclass), '') LIKE 'TEMPORAL%'")[0][0]
    if es_temporal:
        sql_admin(5445, "DROP VIEW capas.aceras")
        sl = nucleo.autenticar("editor_limon", CLAVE_DEMO, config)
        rl = nucleo.cargar_capas(sl, QgsProject.instance(), config)
        sql_admin(5445, vista)
        prueba("capa inválida: avisa cuál y sigue con las demás",
               len(rl.capas) == 7 and rl.errores == ["Aceras (capas.aceras)"], f"errores={rl.errores}")
    else:
        print("   (omitida: capas.aceras en limon no es temporal)")

    print("\n== Reingreso con usuario de consulta ==")
    sc = nucleo.autenticar("consulta_sancarlos", CLAVE_DEMO, config)
    rc = nucleo.cargar_capas(sc, QgsProject.instance(), config)
    prueba("reingreso quita el grupo anterior (queda 1 grupo SIG-TEC)", len(grupos_sigtec()) == 1,
           [g.name() for g in grupos_sigtec()])
    prueba("proyecto sin capas huérfanas (solo las 8 nuevas)", len(QgsProject.instance().mapLayers()) == 8)
    prueba("rol consulta -> 8 capas en solo lectura", all(c.readOnly() for c in rc.capas) and len(rc.capas) == 8)
    prueba("rol consulta -> no puede empezar edición", not rc.capas[0].startEditing())

    print("\n== Nodo del campus inalcanzable ==")
    s.puerto = 5999
    err = lanza(lambda: nucleo.cargar_capas(s, QgsProject.instance(), config), nucleo.ErrorConexionNodo)
    prueba("credenciales válidas pero nodo caído -> ErrorConexionNodo",
           isinstance(err, nucleo.ErrorConexionNodo), err)
    prueba("si el nodo no responde, no se borran las capas actuales", len(grupos_sigtec()) == 1)


def pruebas_interfaz(config):
    print("\n== Diálogo de ingreso (Qt offscreen) ==")
    llamadas = []

    def al_ingresar(u, c):
        llamadas.append(u)
        nucleo.autenticar(u, c, config)

    d = DialogoLogin(None, al_ingresar, servidor="localhost:5440")
    prueba("botón Ingresar deshabilitado con campos vacíos", not d.btn_ingresar.isEnabled())
    d.txt_usuario.setText("   ")
    d.txt_clave.setText("x")
    prueba("usuario con solo espacios -> botón deshabilitado", not d.btn_ingresar.isEnabled())
    d.ingresar()
    prueba("Enter con datos vacíos no llama al servidor y avisa",
           not llamadas and "Escriba el usuario" in d.lbl_error.text())
    d.txt_usuario.setText("editor_sancarlos")
    d.txt_clave.setText("mala")
    prueba("con usuario y clave el botón se habilita", d.btn_ingresar.isEnabled())
    d.btn_ingresar.click()
    prueba("clave incorrecta: mensaje claro, borra la clave, no cierra",
           "incorrectos" in d.lbl_error.text() and d.txt_clave.text() == "" and d.result() == 0,
           d.lbl_error.text())
    caido = {"central": dict(config["central"], puerto=5999), "margen_zoom_m": 250}
    d2 = DialogoLogin(None, lambda u, c: nucleo.autenticar(u, c, caido))
    d2.txt_usuario.setText("editor_sancarlos")
    d2.txt_clave.setText(CLAVE_DEMO)
    d2.btn_ingresar.click()
    prueba("central caído: mensaje 'no se puede conectar al servidor central'",
           "No se puede conectar al servidor central" in d2.lbl_error.text(), d2.lbl_error.text())
    d.txt_clave.setText(CLAVE_DEMO)
    d.btn_ingresar.click()
    prueba("clave correcta: el diálogo se acepta", d.result() == 1)

    print("\n== Complemento completo con iface simulado ==")
    import qgis.utils
    from sigtec import classFactory
    iface = IfaceFalsa()
    plugin = classFactory(iface)
    plugin.initGui()
    prueba("initGui: botón en barra y 2 entradas en menú SIG-TEC",
           len(iface.barra_herramientas) == 1 and len(iface.menu) == 2)
    plugin.ingresar("editor_sancarlos", CLAVE_DEMO)
    prueba("barra de estado muestra usuario y campus",
           plugin.lbl_estado.text() == "SIG-TEC: editor_sancarlos (editor) · Campus Tecnológico Local San Carlos",
           plugin.lbl_estado.text())
    textos = [i.text() for i in iface.messageBar().items()]
    prueba("mensaje de bienvenida en la barra de mensajes",
           any("Conectado como editor_sancarlos" in t for t in textos), textos[:1])
    lienzo = iface.mapCanvas()
    centro = sql_admin(5443, "SELECT ST_X(centro), ST_Y(centro) FROM sig.campus WHERE campus_id=3")[0]
    prueba("lienzo en EPSG:5367 con zoom al campus",
           lienzo.mapSettings().destinationCrs().authid() == "EPSG:5367"
           and abs(lienzo.extent().center().x() - centro[0]) < 5
           and abs(lienzo.extent().center().y() - centro[1]) < 5, lienzo.extent().toString(0))
    plugin.cerrar_sesion()
    prueba("cerrar sesión quita grupo y capas", not grupos_sigtec() and not QgsProject.instance().mapLayers())
    plugin.unload()
    prueba("unload quita botón y menú", not iface.barra_herramientas and not iface.menu)

    print("\n== Carga como complemento instalado (qgis.utils) ==")
    tmp = tempfile.mkdtemp()
    shutil.copytree(os.path.join(AQUI, "..", "sigtec"), os.path.join(tmp, "sigtec"))
    sys.modules.pop("sigtec", None)
    for k in [k for k in sys.modules if k.startswith("sigtec.")]:
        sys.modules.pop(k)
    qgis.utils.iface = iface
    qgis.utils.plugin_paths = [tmp]
    sys.path.insert(0, tmp)
    qgis.utils.updateAvailablePlugins()
    meta = qgis.utils.pluginMetadata("sigtec", "name"), qgis.utils.pluginMetadata("sigtec", "qgisMaximumVersion")
    cargado = qgis.utils.loadPlugin("sigtec") and qgis.utils.startPlugin("sigtec")
    prueba("qgis.utils carga e inicia el complemento", cargado and "sigtec" in qgis.utils.active_plugins, meta)
    from pyplugin_installer.version_compare import isCompatible
    from qgis.core import Qgis
    prueba("metadata compatible con este QGIS", isCompatible(Qgis.version().split("-")[0], "3.34", "4.99"),
           Qgis.version())
    qgis.utils.unloadPlugin("sigtec")
    shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--replicacion", action="store_true",
                    help="exige que cada capa tenga datos de los 5 campus")
    a = ap.parse_args()
    config = nucleo.cargar_config()
    pruebas_login(config)
    pruebas_capas(config, a.replicacion)
    pruebas_interfaz(config)
    fallas = [n for n, ok in RESULTADOS if not ok]
    print(f"\n{len(RESULTADOS) - len(fallas)}/{len(RESULTADOS)} pruebas OK")
    for n in fallas:
        print("  FALLA:", n)
    QgsProject.instance().clear()
    return 1 if fallas else 0


if __name__ == "__main__":
    codigo = main()
    APP.exitQgis()
    sys.exit(codigo)

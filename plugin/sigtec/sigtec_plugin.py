# -*- coding: utf-8 -*-
"""Clase principal del complemento SIG-TEC: botón, menú, ingreso y carga de capas."""
import os

from qgis.core import QgsProject, QgsSettings
from qgis.PyQt.QtGui import QIcon
from qgis.PyQt.QtWidgets import QAction, QLabel

from . import nucleo
from .dialogo_login import DialogoLogin

MENU = "&SIG-TEC"
CLAVE_ULTIMO_USUARIO = "sigtec/ultimo_usuario"


class SigTecPlugin:
    def __init__(self, iface):
        self.iface = iface
        self.config = nucleo.cargar_config()
        self.sesion = None
        self.accion_ingresar = None
        self.accion_salir = None
        self.lbl_estado = None

    # ------------------------------------------------------------------
    # Ciclo de vida del complemento
    # ------------------------------------------------------------------
    def initGui(self):
        icono = QIcon(os.path.join(nucleo.DIR_PLUGIN, "icon.png"))
        ventana = self.iface.mainWindow()

        self.accion_ingresar = QAction(icono, "Ingresar a SIG-TEC…", ventana)
        self.accion_ingresar.setToolTip("SIG-TEC: ingresar y cargar las capas del campus")
        self.accion_ingresar.triggered.connect(self.abrir_login)
        self.iface.addToolBarIcon(self.accion_ingresar)
        self.iface.addPluginToMenu(MENU, self.accion_ingresar)

        self.accion_salir = QAction("Cerrar sesión SIG-TEC", ventana)
        self.accion_salir.setEnabled(False)
        self.accion_salir.triggered.connect(self.cerrar_sesion)
        self.iface.addPluginToMenu(MENU, self.accion_salir)

        self.lbl_estado = QLabel("SIG-TEC: sin sesión")
        ventana.statusBar().addPermanentWidget(self.lbl_estado)

    def unload(self):
        for accion in (self.accion_ingresar, self.accion_salir):
            if accion is not None:
                self.iface.removePluginMenu(MENU, accion)
        if self.accion_ingresar is not None:
            self.iface.removeToolBarIcon(self.accion_ingresar)
        if self.lbl_estado is not None:
            self.iface.mainWindow().statusBar().removeWidget(self.lbl_estado)
            self.lbl_estado.deleteLater()
        self.accion_ingresar = self.accion_salir = self.lbl_estado = None

    # ------------------------------------------------------------------
    # Acciones
    # ------------------------------------------------------------------
    def abrir_login(self):
        c = self.config["central"]
        previo = QgsSettings().value(CLAVE_ULTIMO_USUARIO, "", type=str)
        dialogo = DialogoLogin(self.iface.mainWindow(), self.ingresar,
                               servidor=f"{c['host']}:{c['puerto']}", usuario_previo=previo)
        dialogo.exec()

    def ingresar(self, usuario, clave):
        """Autentica, carga las capas y actualiza el mapa. Lanza nucleo.ErrorSigtec si falla."""
        sesion = nucleo.autenticar(usuario, clave, self.config)
        resultado = nucleo.cargar_capas(sesion, QgsProject.instance(), self.config)

        self.sesion = sesion
        QgsSettings().setValue(CLAVE_ULTIMO_USUARIO, sesion.username)

        lienzo = self.iface.mapCanvas()
        lienzo.setDestinationCrs(QgsProject.instance().crs())
        if resultado.extension is not None:
            lienzo.setExtent(resultado.extension)
        lienzo.refresh()

        modo = "solo consulta" if sesion.es_consulta else "edición del campus propio"
        if self.lbl_estado is not None:
            self.lbl_estado.setText(f"SIG-TEC: {sesion.descripcion()}")
            self.lbl_estado.setToolTip(f"{sesion.nombre_completo} · {sesion.host}:{sesion.puerto} · {modo}")
        if self.accion_salir is not None:
            self.accion_salir.setEnabled(True)

        barra = self.iface.messageBar()
        barra.pushMessage(
            "SIG-TEC",
            f"Conectado como {sesion.username} ({sesion.rol}) al campus {sesion.campus_nombre}: "
            f"{len(resultado.capas)} capas cargadas, {modo}.",
            level=nucleo.nivel_mensaje("Success"), duration=8)
        if resultado.errores:
            barra.pushMessage(
                "SIG-TEC",
                "No se pudieron cargar: " + ", ".join(resultado.errores)
                + ". Revise el registro de mensajes (pestaña SIG-TEC).",
                level=nucleo.nivel_mensaje("Warning"), duration=0)
        for aviso in resultado.advertencias:
            barra.pushMessage("SIG-TEC", aviso, level=nucleo.nivel_mensaje("Warning"), duration=10)
        return resultado

    def cerrar_sesion(self):
        nucleo.quitar_grupos_sigtec(QgsProject.instance())
        self.sesion = None
        if self.lbl_estado is not None:
            self.lbl_estado.setText("SIG-TEC: sin sesión")
            self.lbl_estado.setToolTip("")
        if self.accion_salir is not None:
            self.accion_salir.setEnabled(False)
        self.iface.mapCanvas().refresh()

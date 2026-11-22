# -*- coding: utf-8 -*-
"""Ventana de autenticación SIG-TEC (Qt puro, sin Qt Designer)."""
import os

from qgis.PyQt.QtCore import Qt
from qgis.PyQt.QtGui import QIcon, QPixmap
from qgis.PyQt.QtWidgets import (
    QApplication,
    QDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
)

from .nucleo import DIR_PLUGIN, CredencialesInvalidas, ErrorSigtec


class DialogoLogin(QDialog):
    """Pide usuario y contraseña y llama a `al_ingresar(usuario, clave)`.

    al_ingresar debe lanzar ErrorSigtec si algo falla; el mensaje se muestra
    en la ventana y esta sigue abierta. Si no lanza nada, la ventana se cierra.
    """

    def __init__(self, parent, al_ingresar, servidor="", usuario_previo=""):
        super().__init__(parent)
        self._al_ingresar = al_ingresar
        self.setWindowTitle("SIG-TEC · Ingreso")
        self.setWindowIcon(QIcon(os.path.join(DIR_PLUGIN, "icon.png")))
        self.setMinimumWidth(380)

        # Encabezado
        icono = QLabel()
        icono.setPixmap(QPixmap(os.path.join(DIR_PLUGIN, "icon.png")).scaled(
            48, 48, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
        titulo = QLabel("<b>SIG-TEC</b><br>Sistema de Información Geográfica<br>de los Campus del TEC")
        encabezado = QHBoxLayout()
        encabezado.addWidget(icono)
        encabezado.addWidget(titulo, 1)

        # Campos
        self.txt_usuario = QLineEdit(usuario_previo)
        self.txt_usuario.setPlaceholderText("ej. editor_sancarlos")
        self.txt_clave = QLineEdit()
        self.txt_clave.setEchoMode(QLineEdit.EchoMode.Password)
        formulario = QFormLayout()
        formulario.addRow("Usuario:", self.txt_usuario)
        formulario.addRow("Contraseña:", self.txt_clave)

        self.lbl_error = QLabel()
        self.lbl_error.setWordWrap(True)
        self.lbl_error.setStyleSheet("color: #b00020;")
        self.lbl_error.setVisible(False)

        self.lbl_servidor = QLabel(f"Servidor central: {servidor}" if servidor else "")
        self.lbl_servidor.setStyleSheet("color: gray; font-size: 8pt;")

        # Botones
        self.btn_ingresar = QPushButton("Ingresar")
        self.btn_ingresar.setDefault(True)
        self.btn_cancelar = QPushButton("Cancelar")
        botones = QHBoxLayout()
        botones.addStretch(1)
        botones.addWidget(self.btn_cancelar)
        botones.addWidget(self.btn_ingresar)

        capa = QVBoxLayout(self)
        capa.addLayout(encabezado)
        capa.addSpacing(8)
        capa.addLayout(formulario)
        capa.addWidget(self.lbl_error)
        capa.addWidget(self.lbl_servidor)
        capa.addLayout(botones)

        self.txt_usuario.textChanged.connect(self._actualizar_boton)
        self.txt_clave.textChanged.connect(self._actualizar_boton)
        self.txt_clave.returnPressed.connect(self.ingresar)
        self.txt_usuario.returnPressed.connect(self.txt_clave.setFocus)
        self.btn_ingresar.clicked.connect(self.ingresar)
        self.btn_cancelar.clicked.connect(self.reject)
        self._actualizar_boton()
        (self.txt_clave if usuario_previo else self.txt_usuario).setFocus()

    def _datos_completos(self):
        return bool(self.txt_usuario.text().strip()) and bool(self.txt_clave.text())

    def _actualizar_boton(self):
        self.btn_ingresar.setEnabled(self._datos_completos())

    def mostrar_error(self, mensaje):
        self.lbl_error.setText(mensaje)
        self.lbl_error.setVisible(bool(mensaje))

    def ingresar(self):
        if not self._datos_completos():
            self.mostrar_error("Escriba el usuario y la contraseña.")
            return
        self.mostrar_error("")
        self.btn_ingresar.setEnabled(False)
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        QApplication.processEvents()
        try:
            self._al_ingresar(self.txt_usuario.text().strip(), self.txt_clave.text())
        except CredencialesInvalidas as e:
            self.mostrar_error(str(e))
            self.txt_clave.clear()
            self.txt_clave.setFocus()
        except ErrorSigtec as e:
            self.mostrar_error(str(e))
            if e.detalle:
                self.lbl_error.setToolTip(e.detalle)
        else:
            self.accept()
        finally:
            QApplication.restoreOverrideCursor()
            self._actualizar_boton()

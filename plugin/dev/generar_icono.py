# -*- coding: utf-8 -*-
"""Genera plugin/sigtec/icon.png (64x64) con Qt. Uso: python-qgis plugin/dev/generar_icono.py"""
import os
import sys

from qgis.PyQt.QtCore import QPointF, QRectF, Qt
from qgis.PyQt.QtGui import QBrush, QColor, QGuiApplication, QImage, QPainter, QPainterPath, QPen

app = QGuiApplication(sys.argv)
T = 64
img = QImage(T, T, QImage.Format.Format_ARGB32)
img.fill(Qt.GlobalColor.transparent)
p = QPainter(img)
p.setRenderHint(QPainter.RenderHint.Antialiasing)

# Fondo: azul institucional con esquinas redondeadas
p.setPen(Qt.PenStyle.NoPen)
p.setBrush(QBrush(QColor("#1f4e79")))
p.drawRoundedRect(QRectF(2, 2, T - 4, T - 4), 12, 12)

# Retícula de "mapa"
p.setPen(QPen(QColor(255, 255, 255, 60), 1.5))
for k in (18, 32, 46):
    p.drawLine(QPointF(k, 8), QPointF(k, T - 8))
    p.drawLine(QPointF(8, k), QPointF(T - 8, k))

# Edificio (polígono) y camino (línea)
p.setPen(Qt.PenStyle.NoPen)
p.setBrush(QBrush(QColor("#9ad0f5")))
p.drawRect(QRectF(10, 36, 16, 16))
p.setPen(QPen(QColor("#f2c14e"), 4, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
p.drawLine(QPointF(10, 58), QPointF(56, 30))

# Marcador
pin = QPainterPath()
pin.moveTo(42, 40)
pin.cubicTo(30, 26, 30, 12, 42, 10)
pin.cubicTo(54, 12, 54, 26, 42, 40)
p.setPen(QPen(QColor("#ffffff"), 2))
p.setBrush(QBrush(QColor("#e03131")))
p.drawPath(pin)
p.setBrush(QBrush(QColor("#ffffff")))
p.setPen(Qt.PenStyle.NoPen)
p.drawEllipse(QPointF(42, 20), 4, 4)
p.end()

ruta = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sigtec", "icon.png"))
print("ok" if img.save(ruta) else "ERROR", ruta)

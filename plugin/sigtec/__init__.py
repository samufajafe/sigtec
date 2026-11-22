# -*- coding: utf-8 -*-
"""Complemento SIG-TEC para QGIS."""


def classFactory(iface):  # noqa: N802 (nombre exigido por QGIS)
    from .sigtec_plugin import SigTecPlugin

    return SigTecPlugin(iface)

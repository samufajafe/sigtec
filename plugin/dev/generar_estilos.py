# -*- coding: utf-8 -*-
"""
SIG-TEC - Genera plugin/sigtec/estilos/<capa>.qml y .sld con PyQGIS.

Carga cada vista capas.<capa> de un nodo de campus (para tener los campos
reales), le arma simbología + etiquetas + formulario y guarda el estilo.
Así el QML queda exactamente en el formato de la versión de QGIS que lo genera.

Formulario (según docs/01_arquitectura.md, tabla 4.2 y los CHECK del modelo):
  * Value Map con los valores permitidos de cada campo con CHECK
  * Solo lectura: id, campus_id, area_m2, longitud_m, creado_en, actualizado_en, actualizado_por
  * Alias legibles, valores por defecto y restricciones de no nulo / rango

Uso (OSGeo4W Shell o python-qgis.bat; necesita las vistas capas.*):
  python-qgis plugin/dev/generar_estilos.py [--host localhost --puerto 5443]
Después: ./scripts/publicar_estilos.sh -m "descripción"
"""
import argparse
import os
import sys

from qgis.core import (
    QgsApplication,
    QgsCategorizedSymbolRenderer,
    QgsDataSourceUri,
    QgsDefaultValue,
    QgsEditorWidgetSetup,
    QgsFieldConstraints,
    QgsFillSymbol,
    QgsLineSymbol,
    QgsMarkerSymbol,
    QgsPalLayerSettings,
    QgsRendererCategory,
    QgsTextBufferSettings,
    QgsTextFormat,
    QgsVectorLayer,
    QgsVectorLayerSimpleLabeling,
)
from qgis.PyQt.QtGui import QColor

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.normpath(os.path.join(AQUI, "..", "sigtec", "estilos"))

NULO = "{2839923C-8B7D-419E-B84B-CA2FE9B80EC7}"  # representación de NULL en Value Map

SOLO_LECTURA = ["id", "campus_id", "area_m2", "longitud_m", "creado_en", "actualizado_en",
                "actualizado_por"]

CAMPUS = [("Cartago", 1), ("San José", 2), ("San Carlos", 3), ("Alajuela", 4), ("Limón", 5)]

ALIAS_COMUNES = {
    "id": "ID global", "campus_id": "Campus", "creado_en": "Creado",
    "actualizado_en": "Última modificación", "actualizado_por": "Modificado por",
    "area_m2": "Área (m²)", "longitud_m": "Longitud (m)", "nombre": "Nombre",
    "codigo": "Código", "tipo": "Tipo", "descripcion": "Descripción", "estado": "Estado",
}

# ---------------------------------------------------------------------
# Definición de cada capa: (valor, etiqueta, color, extra) por categoría
# ---------------------------------------------------------------------
CAPAS = {
    "edificios": {
        "campo": "uso",
        "nulo": "Sin uso definido",
        "categorias": [
            ("academico", "Académico", "#4e79a7"),
            ("administrativo", "Administrativo", "#9c755f"),
            ("laboratorio", "Laboratorio", "#b07aa1"),
            ("biblioteca", "Biblioteca", "#f28e2b"),
            ("deportivo", "Deportivo", "#59a14f"),
            ("residencia", "Residencia", "#edc948"),
            ("servicios", "Servicios", "#76b7b2"),
            ("otro", "Otro", "#bab0ac"),
        ],
        "etiqueta": "nombre", "escala_etiqueta": 4000,
        "mostrar": "\"codigo\" || ' · ' || \"nombre\"",
        "alias": {"pisos": "Pisos", "uso": "Uso"},
        "requeridos": ["codigo", "nombre"],
        "rangos": {"pisos": (1, 30)},
        "defectos": {"pisos": "1"},
    },
    "carreteras": {
        "campo": "tipo",
        "categorias": [
            ("principal", "Principal", "#c0392b", 1.6),
            ("secundaria", "Secundaria", "#e67e22", 1.2),
            ("interna", "Interna", "#7f8c8d", 0.9),
            ("servicio", "Servicio", "#95a5a6", 0.6),
        ],
        "otros_mapas": {"superficie": [("asfalto", "Asfalto"), ("concreto", "Concreto"),
                                       ("adoquin", "Adoquín"), ("lastre", "Lastre"),
                                       ("tierra", "Tierra")]},
        "etiqueta": "nombre", "escala_etiqueta": 6000,
        "mostrar": "coalesce(\"nombre\", \"tipo\")",
        "alias": {"superficie": "Superficie"},
        "requeridos": ["tipo", "superficie"],
    },
    "aceras": {
        "campo": "condicion",
        "categorias": [
            ("buena", "Buena", "#2a9d8f", 0.7, "solid"),
            ("regular", "Regular", "#e9a23b", 0.7, "solid"),
            ("mala", "Mala", "#e63946", 0.7, "dash"),
        ],
        "otros_mapas": {"material": [("concreto", "Concreto"), ("adoquin", "Adoquín"),
                                     ("asfalto", "Asfalto"), ("lastre", "Lastre"),
                                     ("otro", "Otro")]},
        "mostrar": "\"material\" || ' (' || \"condicion\" || ')'",
        "alias": {"material": "Material", "ancho_m": "Ancho (m)", "condicion": "Condición"},
        "requeridos": ["material", "condicion"],
        "expresiones": {"ancho_m": ("\"ancho_m\" IS NULL OR \"ancho_m\" > 0", "El ancho debe ser mayor que 0")},
    },
    "parqueos": {
        "campo": "tipo",
        "categorias": [
            ("estudiantes", "Estudiantes", "#a6cee3"),
            ("funcionarios", "Funcionarios", "#1f78b4"),
            ("visitantes", "Visitantes", "#b2df8a"),
            ("discapacidad", "Discapacidad (Ley 7600)", "#6a3d9a"),
            ("motos", "Motos", "#fb9a99"),
            ("bicicletas", "Bicicletas", "#33a02c"),
            ("mixto", "Mixto", "#cab2d6"),
        ],
        "etiqueta": "nombre", "escala_etiqueta": 4000,
        "mostrar": "coalesce(\"nombre\", \"tipo\") || ' · ' || \"espacios_disponibles\" || '/' || \"capacidad\"",
        "alias": {"capacidad": "Capacidad", "espacios_disponibles": "Espacios disponibles"},
        "requeridos": ["tipo", "capacidad"],
        "rangos": {"capacidad": (0, 100000), "espacios_disponibles": (0, 100000)},
        "expresiones": {"espacios_disponibles": (
            "\"espacios_disponibles\" IS NULL OR \"espacios_disponibles\" <= \"capacidad\"",
            "No puede haber más espacios disponibles que la capacidad")},
    },
    "zonas_verdes": {
        "campo": "tipo_vegetacion",
        "categorias": [
            ("cesped", "Césped", "#b7e4c7"),
            ("arbustos", "Arbustos", "#74c69d"),
            ("bosque", "Bosque", "#2d6a4f"),
            ("jardin", "Jardín", "#95d5b2"),
            ("mixta", "Mixta", "#52b788"),
        ],
        "mostrar": "coalesce(\"nombre\", \"tipo_vegetacion\")",
        "alias": {"tipo_vegetacion": "Tipo de vegetación"},
        "requeridos": ["tipo_vegetacion"],
    },
    "puntos_interes": {
        "campo": "tipo",
        "categorias": [
            ("cajero", "Cajero", "#2b8a3e", "square"),
            ("laboratorio", "Laboratorio", "#7048e8", "diamond"),
            ("soda", "Soda", "#f08c00", "circle"),
            ("biblioteca", "Biblioteca", "#d9480f", "pentagon"),
            ("auditorio", "Auditorio", "#c2255c", "hexagon"),
            ("oficina", "Oficina", "#495057", "square"),
            ("servicio_sanitario", "Servicio sanitario", "#1c7ed6", "circle"),
            ("parada_bus", "Parada de bus", "#f59f00", "triangle"),
            ("otro", "Otro", "#868e96", "circle"),
        ],
        "etiqueta": "nombre", "escala_etiqueta": 3000,
        "mostrar": "\"nombre\"",
        "alias": {"horario": "Horario"},
        "requeridos": ["nombre", "tipo"],
    },
    "iluminacion": {
        "campo": "estado",
        "categorias": [
            ("funcionando", "Funcionando", "#ffd43b", "star"),
            ("danada", "Dañada", "#e03131", "cross2"),
            ("mantenimiento", "En mantenimiento", "#f76707", "triangle"),
        ],
        "otros_mapas": {"tipo_lampara": [("led", "LED"), ("sodio", "Sodio"),
                                         ("halogenuro", "Halogenuro metálico"),
                                         ("fluorescente", "Fluorescente"), ("solar", "Solar"),
                                         ("otro", "Otro")]},
        "nulos_permitidos": ["tipo_lampara"],
        "mostrar": "\"codigo\"",
        "alias": {"potencia_w": "Potencia (W)", "tipo_lampara": "Tipo de lámpara"},
        "requeridos": ["codigo"],
        "defectos": {"estado": "'funcionando'"},
        "expresiones": {"potencia_w": ("\"potencia_w\" IS NULL OR \"potencia_w\" > 0", "La potencia debe ser mayor que 0")},
    },
    "accesibilidad": {
        "campo": "tipo",
        "categorias": [
            ("rampa", "Rampa", "#1971c2", 1.3, "solid"),
            ("paso_accesible", "Paso accesible", "#1098ad", 1.0, "solid"),
            ("ruta_podotactil", "Ruta podotáctil", "#f59f00", 1.0, "dot"),
            ("pasamanos", "Pasamanos", "#5f3dc4", 0.7, "solid"),
            ("otro", "Otro", "#868e96", 0.7, "dash"),
        ],
        "otros_mapas": {"estado": [("buena", "Buena"), ("regular", "Regular"), ("mala", "Mala")]},
        "mostrar": "\"tipo\" || coalesce(' · ' || \"descripcion\", '')",
        "alias": {"cumple_ley_7600": "Cumple Ley 7600"},
        "requeridos": ["tipo"],
        "defectos": {"estado": "'buena'", "cumple_ley_7600": "true"},
    },
}


# ---------------------------------------------------------------------
def simbolo(geom, color, extra):
    """Símbolo simple según tipo de geometría."""
    c = QColor(color)
    borde = c.darker(160).name()
    if geom == "POLYGON":
        relleno = QColor(c)
        relleno.setAlpha(210)
        return QgsFillSymbol.createSimple({
            "color": f"{relleno.red()},{relleno.green()},{relleno.blue()},{relleno.alpha()}",
            "outline_color": borde, "outline_width": "0.35", "outline_width_unit": "MM"})
    if geom == "LINESTRING":
        ancho = extra[0] if extra else 0.8
        estilo = extra[1] if len(extra) > 1 else "solid"
        return QgsLineSymbol.createSimple({
            "line_color": color, "line_width": str(ancho), "line_width_unit": "MM",
            "line_style": estilo, "capstyle": "round", "joinstyle": "round"})
    forma = extra[0] if extra else "circle"
    return QgsMarkerSymbol.createSimple({
        "name": forma, "color": color, "outline_color": "#ffffff" if forma != "cross2" else color,
        "outline_width": "0.4", "size": "3.6" if forma != "star" else "4.2", "size_unit": "MM"})


def mapa_valores(pares, permite_nulo=False, etiqueta_nulo="Sin definir"):
    mapa = [{etiqueta: valor} for valor, etiqueta in pares]
    if permite_nulo:
        mapa.insert(0, {etiqueta_nulo: NULO})
    return QgsEditorWidgetSetup("ValueMap", {"map": mapa})


def etiquetas(capa, campo, escala):
    s = QgsPalLayerSettings()
    s.fieldName = campo
    s.enabled = True
    formato = QgsTextFormat()
    formato.setSize(8)
    formato.setColor(QColor("#212529"))
    buffer = QgsTextBufferSettings()
    buffer.setEnabled(True)
    buffer.setSize(0.8)
    buffer.setColor(QColor("white"))
    formato.setBuffer(buffer)
    s.setFormat(formato)
    s.scaleVisibility = True
    s.minimumScale = escala   # se ven al acercarse más que 1:escala
    s.maximumScale = 1
    capa.setLabeling(QgsVectorLayerSimpleLabeling(s))
    capa.setLabelsEnabled(True)


def configurar_formulario(capa, d):
    campos = capa.fields()
    fc = capa.editFormConfig()
    alias = dict(ALIAS_COMUNES, **d.get("alias", {}))
    duro = QgsFieldConstraints.ConstraintStrength.ConstraintStrengthHard

    for i, f in enumerate(campos):
        nombre = f.name()
        if nombre in alias:
            capa.setFieldAlias(i, alias[nombre])
        if nombre in SOLO_LECTURA:
            fc.setReadOnly(i, True)

    idx = campos.indexOf
    # Value Maps
    capa.setEditorWidgetSetup(idx("campus_id"), QgsEditorWidgetSetup(
        "ValueMap", {"map": [{n: v} for n, v in CAMPUS]}))
    principal = d["campo"]
    capa.setEditorWidgetSetup(idx(principal), mapa_valores(
        [(c[0], c[1]) for c in d["categorias"]],
        permite_nulo=bool(d.get("nulo")), etiqueta_nulo=d.get("nulo") or "Sin definir"))
    for campo, pares in d.get("otros_mapas", {}).items():
        capa.setEditorWidgetSetup(idx(campo), mapa_valores(
            pares, permite_nulo=campo in d.get("nulos_permitidos", [])))
    if idx("cumple_ley_7600") >= 0:
        capa.setEditorWidgetSetup(idx("cumple_ley_7600"), QgsEditorWidgetSetup("CheckBox", {}))
    for campo, (minimo, maximo) in d.get("rangos", {}).items():
        capa.setEditorWidgetSetup(idx(campo), QgsEditorWidgetSetup("Range", {
            "Min": minimo, "Max": maximo, "Step": 1, "Style": "SpinBox",
            "AllowNull": campo not in d.get("requeridos", [])}))

    # Restricciones (las mismas que valida la BD, para avisar antes de guardar)
    for campo in d.get("requeridos", []):
        capa.setFieldConstraint(idx(campo), QgsFieldConstraints.Constraint.ConstraintNotNull, duro)
    for campo, (expresion, mensaje) in d.get("expresiones", {}).items():
        capa.setConstraintExpression(idx(campo), expresion, mensaje)
        capa.setFieldConstraint(idx(campo), QgsFieldConstraints.Constraint.ConstraintExpression, duro)
    for campo, expresion in d.get("defectos", {}).items():
        capa.setDefaultValueDefinition(idx(campo), QgsDefaultValue(expresion))

    capa.setEditFormConfig(fc)
    capa.setDisplayExpression(d["mostrar"])


def guardar(capa, codigo):
    ruta_qml = os.path.join(SALIDA, f"{codigo}.qml")
    ruta_sld = os.path.join(SALIDA, f"{codigo}.sld")
    msg, ok = capa.saveNamedStyle(ruta_qml)
    if not ok:
        raise RuntimeError(f"No se guardó {ruta_qml}: {msg}")
    try:
        msg, ok = capa.saveSldStyle(ruta_sld)
    except TypeError:
        from qgis.core import QgsSldExportContext
        msg, ok = capa.saveSldStyleV2(ruta_sld, QgsSldExportContext())
    for ruta in (ruta_qml, ruta_sld):  # LF siempre (git y comparación de versiones)
        with open(ruta, "rb") as f:
            datos = f.read().replace(b"\r\n", b"\n")
        with open(ruta, "wb") as f:
            f.write(datos)
    return ruta_qml


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--puerto", default="5443")
    ap.add_argument("--usuario", default="postgres")
    ap.add_argument("--clave", default="postgres")
    ap.add_argument("--base", default="sigtec")
    a = ap.parse_args()

    app = QgsApplication([], False)
    app.initQgis()
    os.makedirs(SALIDA, exist_ok=True)
    tipos = {"edificios": "POLYGON", "parqueos": "POLYGON", "zonas_verdes": "POLYGON",
             "carreteras": "LINESTRING", "aceras": "LINESTRING", "accesibilidad": "LINESTRING",
             "puntos_interes": "POINT", "iluminacion": "POINT"}
    errores = 0
    for codigo, d in CAPAS.items():
        uri = QgsDataSourceUri()
        uri.setConnection(a.host, a.puerto, a.base, a.usuario, a.clave)
        uri.setDataSource("capas", codigo, "geom", "", "id")
        uri.setSrid("5367")
        capa = QgsVectorLayer(uri.uri(False), codigo, "postgres")
        if not capa.isValid():
            print(f"ERROR: capas.{codigo} no es válida (¿existen las vistas?)")
            errores += 1
            continue
        geom = tipos[codigo]
        cats = []
        for c in d["categorias"]:
            cats.append(QgsRendererCategory(c[0], simbolo(geom, c[2], c[3:]), c[1]))
        if d.get("nulo"):
            cats.append(QgsRendererCategory(None, simbolo(geom, "#d9d9d9", ()), d["nulo"]))
        capa.setRenderer(QgsCategorizedSymbolRenderer(d["campo"], cats))
        if d.get("etiqueta"):
            etiquetas(capa, d["etiqueta"], d["escala_etiqueta"])
        configurar_formulario(capa, d)
        ruta = guardar(capa, codigo)
        print(f"ok  {os.path.relpath(ruta, os.path.join(AQUI, '..', '..'))}  ({len(cats)} categorías)")

    app.exitQgis()
    return 1 if errores else 0


if __name__ == "__main__":
    sys.exit(main())

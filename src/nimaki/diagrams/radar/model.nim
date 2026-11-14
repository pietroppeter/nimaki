## port-of: src/diagrams/radar/model.ts
## port-status: draft
import std/[options, tables]
import ../../errors
import parser
import ../../jsregex

type
  RadarAxis* = object
    name*: string
    label*: string

  RadarCurve* = object
    name*: string
    label*: string
    entries*: seq[float]

  RadarOptions* = object
    showLegend*: bool
    ticks*: float
    max*: Option[float]   ## none for null
    min*: float
    graticule*: string    ## "circle" or "polygon"

  RadarModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    axes*: seq[RadarAxis]
    curves*: seq[RadarCurve]
    options*: RadarOptions

const MAX_TICKS = 32.0

proc invalid(message: string): ref PeleError =
  newPeleError(message, "semantic", ErrorInfo(diagramType: "radar"))

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc buildRadar*(ast: RadarAst, title: string): RadarModel =
  var axes: seq[RadarAxis]
  for axis in ast.axes:
    axes.add RadarAxis(name: axis.name, label: if axis.hasLabel: axis.label else: axis.name)

  var curves: seq[RadarCurve]
  for curve in ast.curves:
    var entries: seq[float]
    if not curve.entries[0].hasAxis:
      for entry in curve.entries: entries.add entry.value
    else:
      if axes.len == 0: raise invalid("Axes must be populated before curves for reference entries")
      var byAxis = initTable[string, float]()
      for entry in curve.entries:
        if entry.hasAxis and entry.axis notin byAxis: byAxis[entry.axis] = entry.value
      for axis in axes:
        if axis.name notin byAxis: raise invalid("Missing entry for axis " & axis.label)
        entries.add byAxis[axis.name]
    curves.add RadarCurve(name: curve.name, label: if curve.hasLabel: curve.label else: curve.name,
                          entries: entries)

  var options = RadarOptions(showLegend: true, ticks: 5, max: none(float), min: 0, graticule: "circle")
  for option in ast.options:
    case option.name
    of "showLegend": options.showLegend = option.flag
    of "graticule": options.graticule = option.text
    of "ticks": options.ticks = option.number
    of "max": options.max = some(option.number)
    of "min": options.min = option.number
  if options.ticks > MAX_TICKS: options.ticks = MAX_TICKS

  RadarModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": ast.accTitle.replace(jsre"/^\s+/g", "") else: "",
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "",
    axes: axes,
    curves: curves,
    options: options)

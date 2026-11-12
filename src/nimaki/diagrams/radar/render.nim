## port-of: src/diagrams/radar/render.ts
## port-status: draft
import std/options
from std/math import PI, ceil, classify, FloatClass
import ../../jsmath
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/fit_width
import model

const
  SWATCH = 12.0
  ROW = 26.0
  GAP = 24.0

type Point = object
  x, y: float

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

proc option(config: Config, key: string, fallback, min, max: float): float =
  let value = config["radar"][key]
  if value != nil and value.kind == yNumber and value.n >= min: jsMin(value.n, max) else: fallback

func relativeRadius*(value, min, max, radius: float): float =
  let clipped = jsMin(jsMax(value, min), max)
  let scaled = radius * (clipped - min)
  # Keep the original rounding unless multiplication overflows.
  if scaled.isFinite: scaled / (max - min) else: radius * ((clipped - min) / (max - min))

func closedRoundCurve*(points: seq[Point], tension: float): string =
  ## A closed Catmull-Rom spline through the points, as cubic Bézier segments.
  let n = points.len
  result = "M" & num(points[0].x) & "," & num(points[0].y)
  for i in 0 ..< n:
    let p0 = points[(i - 1 + n) mod n]
    let p1 = points[i]
    let p2 = points[(i + 1) mod n]
    let p3 = points[(i + 2) mod n]
    result.add " C" & num(p1.x + (p2.x - p0.x) * tension) & "," & num(p1.y + (p2.y - p0.y) * tension) &
      " " & num(p2.x - (p3.x - p1.x) * tension) & "," & num(p2.y - (p3.y - p1.y) * tension) & " " &
      num(p2.x) & "," & num(p2.y)
  result.add " Z"

func polygon(points: seq[Point]): string =
  for p in points:
    result.add (if result != "": " " else: "") & num(p.x) & "," & num(p.y)

proc draw(model: RadarModel, config: Config, options: RenderOptions, width, height: float, tight: bool): Rendered

proc renderRadar*(model: RadarModel, config: Config, options: RenderOptions): Rendered =
  let natural = option(config, "width", 320, 1, 4000)
  fitWidth(options, natural, 160, proc (width: float, tight: bool): Rendered =
    draw(model, config, options, width, (option(config, "height", 320, 1, 4000) * width) / natural, tight))

proc draw(model: RadarModel, config: Config, options: RenderOptions, width, height: float, tight: bool): Rendered =
  ## `tight` is set when the chart does not fit the width it has with its legend beside it.
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let axisScale = option(config, "axisScaleFactor", 1, 0, 10)
  let labelFactor = option(config, "axisLabelFactor", 1.05, 0, 10)
  let tension = option(config, "curveTension", 0.17, 0, 1)
  let radius = jsMin(width, height) / 2

  let axes = model.axes
  let curves = model.curves
  let ticks = model.options.ticks
  let graticule = model.options.graticule
  let min = model.options.min
  let count = axes.len
  var unit: seq[Point]
  for i in 0 ..< count:
    let angle = (2 * PI * float(i)) / float(count) - PI / 2
    unit.add Point(x: cos(angle), y: sin(angle))

  var max: float
  if model.options.max.isSome: max = model.options.max.get
  else:
    max = -Inf
    for curve in curves:
      for value in curve.entries:
        if value > max: max = value

  # The chart is drawn around the origin. Margins reserve space; labels and the legend widen it.
  var x0 = -width / 2 - option(config, "marginLeft", 16, 0, 2000)
  var x1 = width / 2 + option(config, "marginRight", 16, 0, 2000)
  var y0 = -height / 2 - option(config, "marginTop", 16, 0, 2000)
  var y1 = height / 2 + option(config, "marginBottom", 16, 0, 2000)

  var grid = ""
  var i = 0.0
  while i < ticks:
    let r = jsMin(radius, (radius * (i + 1)) / ticks)
    if graticule == "circle": grid.add "<circle r=\"" & num(r) & "\"/>"
    else:
      var pts: seq[Point]
      for u in unit: pts.add Point(x: u.x * r, y: u.y * r)
      grid.add "<polygon points=\"" & polygon(pts) & "\"/>"
    i += 1

  var spokes = ""
  var labels = ""
  for i, u in unit:
    let reach = radius * axisScale
    spokes.add "M0,0L" & num(u.x * reach) & "," & num(u.y * reach)
    let label = layoutLabel(axes[i].label, false, measurer, small, 4000)
    let at = radius * labelFactor + 6
    # Each label hangs off its axis on the side away from the center.
    let cx = u.x * at + (if u.x > 0.01: label.width / 2 elif u.x < -0.01: -label.width / 2 else: 0)
    let cy = u.y * at + (if u.y > 0.01: label.height / 2 elif u.y < -0.01: -label.height / 2 else: 0)
    labels.add "<g class=\"pele-axis-label\" data-id=\"" & escText(axes[i].name) & "\">" & labelSvg(label, cx, cy, "") & "</g>"
    x0 = jsMin(x0, cx - label.width / 2)
    x1 = jsMax(x1, cx + label.width / 2)
    y0 = jsMin(y0, cy - label.height / 2)
    y1 = jsMax(y1, cy + label.height / 2)

  var shapes = ""
  for index, curve in curves:
    # Mermaid leaves out a curve that does not have a value for every axis.
    if curve.entries.len != count: continue
    var points: seq[Point]
    for i, value in curve.entries:
      let r = relativeRadius(value, min, max, radius)
      let safe = if r.isFinite: r else: 0
      points.add Point(x: unit[i].x * safe, y: unit[i].y * safe)
    let color = seriesColor(index)
    let attrs = " class=\"pele-curve\" data-id=\"" & escText(curve.name) & "\" fill=\"" & color & "\" stroke=\"" & color & "\""
    shapes.add(if graticule == "circle": "<path" & attrs & " d=\"" & closedRoundCurve(points, tension) & "\"/>"
               else: "<polygon" & attrs & " points=\"" & polygon(points) & "\"/>")

  var legend: seq[Label]
  if model.options.showLegend:
    for curve in curves: legend.add layoutLabel(curve.label, false, measurer, small, 4000)
  var legendWidth = 0.0
  for label in legend: legendWidth = jsMax(legendWidth, label.width)
  let legendHeight = float(legend.len) * ROW
  let legendX = if tight: -(SWATCH + 8 + legendWidth) / 2 else: x1 + GAP
  let legendTop = if tight: y1 + GAP / 2 else: -legendHeight / 2
  if legend.len > 0 and tight:
    x0 = jsMin(x0, legendX)
    x1 = jsMax(x1, -legendX)
    y1 = legendTop + legendHeight
  elif legend.len > 0:
    x1 = legendX + SWATCH + 8 + legendWidth
    y0 = jsMin(y0, -legendHeight / 2)
    y1 = jsMax(y1, legendHeight / 2)
  var legendOut = ""
  for index, label in legend:
    let y = legendTop + float(index) * ROW + ROW / 2
    let color = seriesColor(index)
    legendOut.add "<g class=\"pele-legend-item\" data-id=\"" & escText(curves[index].name) & "\">" &
      "<rect x=\"" & num(legendX) & "\" y=\"" & num(y - SWATCH / 2) & "\" width=\"" & jsString(SWATCH) &
      "\" height=\"" & jsString(SWATCH) & "\" rx=\"2\" fill=\"" & color & "\" fill-opacity=\"0.4\" stroke=\"" & color & "\"/>" &
      labelSvg(label, legendX + SWATCH + 8 + label.width / 2, y, "") &
      "</g>"

  let title = layoutLabel(model.title, false, measurer, size, titleRoom(options), Bold)
  let titleHeight = if title.height > 0: title.height + 8 else: 0
  let bodyWidth = jsMax(x1 - x0, title.width)
  let totalWidth = ceil(bodyWidth + 2 * pad)
  let totalHeight = ceil(y1 - y0 + titleHeight + 2 * pad)
  let origin = "translate(" & num(pad + (bodyWidth - (x1 - x0)) / 2 - x0) & "," & num(pad + titleHeight - y0) & ")"

  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g transform=\"" & origin & "\">" &
    (if grid != "": "<g class=\"pele-graticule\" fill=\"none\" stroke=\"var(--_a)\">" & grid & "</g>" else: "") &
    (if spokes != "": "<path class=\"pele-axes\" d=\"" & spokes & "\" fill=\"none\" stroke=\"var(--_b)\"/>" else: "") &
    (if shapes != "": "<g class=\"pele-curves\" fill-opacity=\"0.2\" stroke-width=\"1.5\" stroke-linejoin=\"round\">" & shapes & "</g>" else: "") &
    (if labels != "": "<g class=\"pele-axis-labels\" font-size=\"" & jsString(small) & "\">" & labels & "</g>" else: "") &
    (if legendOut != "": "<g class=\"pele-legend\" font-size=\"" & jsString(small) & "\">" & legendOut & "</g>" else: "") &
    "</g>"

  Rendered(
    svg: svgDocument("radar", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight)

## port-of: src/diagrams/pie/render.ts
## port-status: conformant
import std/[tables, options]
from std/math import PI, ceil
import ../../jsmath
import ../../preprocess
import ../../svg/[builder, root, palette, theme]
import ../../text/[label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/fit_width
import model

const
  RADIUS = 120.0
  SWATCH = 12.0
  ROW = 26.0
  GAP = 32.0
  OUTSIDE = 28.0

proc option(config: Config, key: string): YamlValue = config["pie"][key]

proc point(angle, radius: float): string =
  num(sin(angle) * radius) & "," & num(-cos(angle) * radius)

proc slice(start, stop, outer, inner: float): string =
  if stop - start >= PI * 2 - 1e-9:
    proc ring(r: float, sweep: int): string =
      "M0," & num(-r) & "A" & num(r) & "," & num(r) & " 0 1 " & $sweep & " 0," & num(r) & "A" &
        num(r) & "," & num(r) & " 0 1 " & $sweep & " 0," & num(-r) & "Z"
    return ring(outer, 1) & (if inner > 0: ring(inner, 0) else: "")
  let large = if stop - start > PI: 1 else: 0
  if inner <= 0:
    return "M0,0L" & point(start, outer) & "A" & num(outer) & "," & num(outer) & " 0 " & $large &
      " 1 " & point(stop, outer) & "Z"
  "M" & point(start, outer) & "A" & num(outer) & "," & num(outer) & " 0 " & $large & " 1 " &
    point(stop, outer) & "L" & point(stop, inner) & "A" & num(inner) & "," & num(inner) & " 0 " &
    $large & " 0 " & point(start, inner) & "Z"

proc draw(model: PieModel, config: Config, options: RenderOptions, radius: float, tight: bool): Rendered

proc renderPie*(model: PieModel, config: Config, options: RenderOptions): Rendered =
  fitWidth(options, RADIUS * 2, 140, proc (diameter: float, tight: bool): Rendered =
    draw(model, config, options, diameter / 2, tight))

func isNumber(v: YamlValue): bool = v != nil and v.kind == yNumber

proc draw(model: PieModel, config: Config, options: RenderOptions, radius: float, tight: bool): Rendered =
  ## `tight` is set when the chart does not fit the width it has with its legend beside it.
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let position = option(config, "textPosition")
  let textPosition = if isNumber(position) and position.n >= 0 and position.n <= 1: position.n else: 0.75
  let hole = option(config, "donutHole")
  let inner = if isNumber(hole) and hole.n > 0 and hole.n <= 0.9: hole.n * radius else: 0
  let placedRaw = option(config, "legendPosition")
  let placed = if placedRaw == nil or placedRaw.kind == yNull: "right" else: jsStr(placedRaw)
  let legendPosition = if tight and (placed == "left" or placed == "right"): "bottom" else: placed

  var entries: seq[(string, float)]
  for label, value in model.sections: entries.add (label, value)
  var sum = 0.0
  for (_, value) in entries: sum += value

  var legend: seq[Label]
  for (label, value) in entries:
    legend.add layoutLabel(if model.showData: label & " [" & jsString(value) & "]" else: label,
                           false, measurer, small, 4000)
  var legendWidth = 0.0
  for label in legend: legendWidth = max(legendWidth, label.width)
  legendWidth += (if legend.len > 0: SWATCH + 8 else: 0)
  let legendHeight = float(legend.len) * ROW

  let title = layoutLabel(model.title, false, measurer, size, titleRoom(options), Bold)
  let titleHeight = if title.height > 0: title.height + 16 else: 0

  # A slice too thin for its percentage gets the label outside the rim, which needs a margin.
  var shares: seq[float]
  for (_, value) in entries:
    let share = if sum > 0: value / sum else: 0
    shares.add(if share * 100 >= 1 and toFixed(share * 100, 0) != "0": share else: 0)
  var narrow: seq[bool]
  for share in shares:
    if share == 0 or share >= 0.5:
      narrow.add false
    else:
      let chord = 2 * radius * textPosition * sin(share * PI)
      narrow.add chord < measurer.width(toFixed(share * 100, 0) & "%", small, 0) + 6
  let margin = if true in narrow: OUTSIDE else: 0

  let side = if legendPosition in ["left", "right", "center"]: legendPosition else: ""
  let stacked = legendPosition == "top" or legendPosition == "bottom"
  let diameter = (radius + margin) * 2
  var width = diameter
  var height = diameter
  if side == "left" or side == "right":
    width += (if legendWidth > 0: GAP + legendWidth else: 0)
    height = max(height, legendHeight)
  elif stacked:
    width = max(width, legendWidth)
    height += (if legendHeight > 0: 20 + legendHeight else: 0)
  width = max(width, title.width)

  let cx = pad + (if side == "left": legendWidth + GAP + diameter / 2
                  elif side == "right": diameter / 2
                  else: width / 2)
  let bodyTop = pad + titleHeight
  let cy = bodyTop + (if legendPosition == "top": legendHeight + 20 + diameter / 2
                      elif stacked: diameter / 2
                      else: height / 2)

  var slices = ""
  var labels = ""
  var outside = ""
  var angle = 0.0
  let rim = radius + OUTSIDE / 2
  var placedOutside: seq[tuple[x, y, width: float]]
  proc clear(x, y, width: float): bool =
    for other in placedOutside:
      if not (abs(x - other.x) >= (width + other.width) / 2 + 2 or abs(y - other.y) >= small + 2):
        return false
    true
  for index, (label, _) in entries:
    let share = shares[index]
    if share == 0: continue
    let stop = angle + share * PI * 2
    slices.add "<path class=\"pele-slice\" data-id=\"" & escText(label) & "\" d=\"" &
      slice(angle, stop, radius, inner) & "\" fill=\"" & seriesColor(index) & "\"/>"
    let mid = (angle + stop) / 2
    let text = toFixed(share * 100, 0) & "%"
    if narrow[index]:
      let width = measurer.width(text, small, 0)
      var at = mid
      var step = 0
      while step < 360 and not clear(sin(at) * rim, -cos(at) * rim, width):
        at += 2 / rim
        inc step
      let x = sin(at) * rim
      let y = -cos(at) * rim
      placedOutside.add (x, y, width)
      outside.add "<text x=\"" & num(x) & "\" y=\"" & num(y + small * 0.35) & "\">" & text & "</text>"
    else:
      let r = radius * textPosition
      labels.add "<text x=\"" & num(sin(mid) * r) & "\" y=\"" & num(-cos(mid) * r + small * 0.35) &
        "\"" & seriesInkFill(index) & ">" & text & "</text>"
    angle = stop
  if slices == "":
    slices = "<circle class=\"pele-slice\" r=\"" & jsString(radius) & "\" fill=\"none\" stroke=\"var(--_b)\"/>"

  var legendOut = ""
  var lx, ly: float
  if side == "right":
    lx = cx + diameter / 2 + GAP
    ly = bodyTop + (height - legendHeight) / 2
  elif side == "left":
    lx = pad
    ly = bodyTop + (height - legendHeight) / 2
  elif side == "center":
    lx = cx - legendWidth / 2
    ly = cy - legendHeight / 2
  else:
    lx = pad + (width - legendWidth) / 2
    ly = if legendPosition == "top": bodyTop else: bodyTop + diameter + 20
  for index, label in legend:
    let y = ly + float(index) * ROW + ROW / 2
    legendOut.add "<g class=\"pele-legend-item\" data-id=\"" & escText(entries[index][0]) & "\">" &
      "<rect x=\"" & num(lx) & "\" y=\"" & num(y - SWATCH / 2) & "\" width=\"" & jsString(SWATCH) &
      "\" height=\"" & jsString(SWATCH) & "\" rx=\"2\" fill=\"" & seriesColor(index) & "\"/>" &
      labelSvg(label, lx + SWATCH + 8 + label.width / 2, y, "") &
      "</g>"

  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(height + titleHeight + 2 * pad)
  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g class=\"pele-slices\" transform=\"translate(" & num(cx) & "," & num(cy) &
      ")\" stroke=\"var(--_bg)\" stroke-width=\"1\" stroke-linejoin=\"round\">" & slices & "</g>" &
    (if labels != "":
      "<g class=\"pele-slice-labels\" transform=\"translate(" & num(cx) & "," & num(cy) &
        ")\" font-size=\"" & jsString(small) & "\" text-anchor=\"middle\" fill=\"var(--_bg)\">" & labels & "</g>"
     else: "") &
    (if outside != "":
      "<g class=\"pele-slice-labels\" transform=\"translate(" & num(cx) & "," & num(cy) &
        ")\" font-size=\"" & jsString(small) & "\" text-anchor=\"middle\">" & outside & "</g>"
     else: "") &
    (if legendOut != "": "<g class=\"pele-legend\" font-size=\"" & jsString(small) & "\">" & legendOut & "</g>" else: "")

  Rendered(
    svg: svgDocument("pie", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight,
    links: @[])

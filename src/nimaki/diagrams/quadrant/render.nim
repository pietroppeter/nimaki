## port-of: src/diagrams/quadrant/render.ts
## port-status: conformant
import std/[options, tables, strutils, algorithm]
from std/math import classify, FloatClass
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/fit_width
import db

const
  GAP = 4.0
  CAREFUL = 300

type Dot = object
  cx, cy, reach: float
  text: Label

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

proc setting(config: Config, key: string): YamlValue = config["quadrantChart"][key]

proc length(config: Config, key: string, fallback, max: float): float =
  let value = setting(config, key)
  if value != nil and value.kind == yNumber and value.n >= 0: jsMin(value.n, max) else: fallback

proc textSize(config: Config, key: string, fallback: float): float =
  ## Mermaid's quadrantChart font size keys; without them the sizes follow fontSize.
  let value = setting(config, key)
  if value != nil and value.kind == yNumber and value.n.isFinite: jsMin(72, jsMax(4, value.n)) else: fallback

proc isText(config: Config, key, text: string): bool =
  let value = setting(config, key)
  value != nil and value.kind == yString and value.s == text

func hex(color: string): string = (if color.startsWith("#"): color else: "#" & color)

func sizeAttr(own, inherited: float): string =
  ## Sizes that differ from the one a label inherits.
  if own == inherited: "" else: " font-size=\"" & jsString(own) & "\""

func pixels(width: string): float =
  ## parseInt of "<digits>px"
  jsToNumber(width[0 ..< width.len - 2])

proc renderQuadrant*(model: QuadrantModel, config: Config, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let titleSize = textSize(config, "titleFontSize", size)
  let quadrantSize = textSize(config, "quadrantLabelFontSize", size)
  let xAxisSize = textSize(config, "xAxisLabelFontSize", jsRound(size * 0.875))
  let yAxisSize = textSize(config, "yAxisLabelFontSize", jsRound(size * 0.875))
  let pointSize = textSize(config, "pointLabelFontSize", jsRound(size * 0.75))
  let measurer = measurerOf(options)
  let natural = jsRound(jsMax(100, length(config, "chartWidth", 500, 4000)))
  let width = jsRound(capWidth(options, natural, 280))
  let height = jsRound((jsMax(100, length(config, "chartHeight", 500, 4000)) * width) / natural)
  let outer = length(config, "quadrantPadding", options.padding.get(8), 200)
  let xPad = length(config, "xAxisLabelPadding", 5, 200)
  let yPad = length(config, "yAxisLabelPadding", 5, 200)
  let hasPoints = model.points.len > 0

  proc label(text: QuadrantText, fontSize, max: float): Label =
    layoutLabel(text.text, text.defined and text.markdown, measurer, fontSize, jsMax(max, 40))

  let title = layoutLabel(model.title, false, measurer, titleSize, jsMax(width - 2 * outer, 40), Bold)
  let titlePad = length(config, "titlePadding", 10, 200)
  let titleSpace = if title.height > 0: title.height + titlePad else: 0.0

  let hasX = model.xAxisLeft.text != "" or model.xAxisRight.text != ""
  let hasY = model.yAxisBottom.text != "" or model.yAxisTop.text != ""
  # Mermaid moves the x axis labels below the chart as soon as there are points.
  let xBelow = hasPoints or isText(config, "xAxisPosition", "bottom")
  let yRight = isText(config, "yAxisPosition", "right")

  let side = width - 2 * outer
  let xLeft = label(model.xAxisLeft, xAxisSize, (if model.xAxisRight.defined: side / 2 - 16 else: side))
  let xRight = label(model.xAxisRight, xAxisSize, side / 2 - 16)
  let xHeight = jsMax(xLeft.height, xRight.height)
  let xSpace = if hasX: xHeight + xPad else: 0.0
  let tall = height - 2 * outer - titleSpace - xSpace
  let yBottom = label(model.yAxisBottom, yAxisSize, (if model.yAxisTop.defined: tall / 2 - 16 else: tall))
  let yTop = label(model.yAxisTop, yAxisSize, tall / 2 - 16)
  let yHeight = jsMax(yBottom.height, yTop.height)
  let ySpace = if hasY: yHeight + yPad else: 0.0

  let left = outer + (if yRight: 0.0 else: ySpace)
  let top = outer + titleSpace + (if xBelow: 0.0 else: xSpace)
  let w = jsMax(0, side - ySpace)
  let h = jsMax(0, tall)
  let tileW = jsMax(0, (w - GAP) / 2)
  let tileH = jsMax(0, (h - GAP) / 2)

  # Boxes a point label keeps clear of: the gaps between quadrants, quadrant labels, points,
  # and the labels placed before it.
  var taken = @[left + tileW, top, left + w - tileW, top + h, left, top + tileH, left + w, top + h - tileH]
  proc isClear(start: int, x0, y0, x1, y1: float): bool =
    var k = start
    while k < taken.len:
      # Empty quadrant labels must not block point labels.
      if not (taken[k] >= taken[k + 2] or taken[k + 1] >= taken[k + 3]):
        if x0 < taken[k + 2] and x1 > taken[k] and y0 < taken[k + 3] and y1 > taken[k + 1]: return false
      k += 4
    true

  let textTop = length(config, "quadrantTextTopPadding", 5, 200)
  var quadrants = ""
  for k in 0 ..< 4:
    let x = if k == 0 or k == 3: left + w - tileW else: left
    let y = if k < 2: top else: top + h - tileH
    let text = label(model.quadrants[k], quadrantSize, tileW - 16)
    let cx = x + tileW / 2
    let cy = if hasPoints: y + textTop + text.height / 2 else: y + tileH / 2
    taken.add [cx - text.width / 2, cy - text.height / 2, cx + text.width / 2, cy + text.height / 2]
    quadrants.add "<g class=\"pele-quadrant\" data-id=\"" & $(k + 1) & "\">" &
      "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(tileW) & "\" height=\"" & num(tileH) & "\"" & ROUNDED & "/>" &
      labelSvg(text, cx, cy, " class=\"pele-label\"" & sizeAttr(quadrantSize, size) & " fill=\"var(--_fg)\" stroke=\"none\"") &
      "</g>"

  var axes = ""
  if hasX:
    let y = if xBelow: top + h + xPad + xHeight / 2 else: top - xPad - xHeight / 2
    axes.add labelSvg(xLeft, (if xRight.height > 0: left + w / 4 else: left + xLeft.width / 2), y, "") &
      labelSvg(xRight, left + (w * 3) / 4, y, "")
  if hasY:
    let x = if yRight: left + w + yPad + yHeight / 2 else: left - yPad - yHeight / 2
    proc turned(text: Label, y: float): string =
      if text.height > 0: "<g transform=\"translate(" & num(x) & "," & num(y) & ") rotate(-90)\"" &
                          sizeAttr(yAxisSize, xAxisSize) & ">" & labelSvg(text, 0, 0, "") & "</g>"
      else: ""
    axes.add turned(yBottom, (if yTop.height > 0: top + (h * 3) / 4 else: top + h - yBottom.width / 2)) &
      turned(yTop, top + h / 4)

  let radius = length(config, "pointRadius", 5, 200)
  let textPad = length(config, "pointTextPadding", 5, 200)
  let fill = seriesColor(0)
  var dots: seq[Dot]
  var circles: seq[string]
  for point in model.points:
    if not (point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1): continue
    let hasShared = point.className in model.classes
    let shared = if hasShared: model.classes[point.className] else: PointStyle()
    let r = jsMin(point.style.radius.get(shared.radius.get(radius)), 2000)
    let color = if point.style.color.isSome: point.style.color else: shared.color
    let strokeColor = if point.style.strokeColor.isSome: point.style.strokeColor else: shared.strokeColor
    let strokeWidth = if point.style.strokeWidth.isSome: point.style.strokeWidth else: shared.strokeWidth
    var styles: seq[string]
    if color.isSome: styles.add "fill:" & hex(color.get)
    if strokeWidth.isSome:
      if strokeColor.isSome: styles.add "stroke:" & hex(strokeColor.get)
      styles.add "stroke-width:" & strokeWidth.get
    let cx = left + point.x * w
    let cy = top + (1 - point.y) * h
    dots.add Dot(cx: cx, cy: cy,
                 reach: r + (if strokeWidth.isSome: jsMin(pixels(strokeWidth.get), 400) / 2 else: 0.0),
                 # Mermaid keeps point labels on one line; wrap only what is wider than the plot.
                 text: label(point.text, pointSize, w))
    circles.add "<circle class=\"pele-point" & classNames(point.className) & "\" data-id=\"" & escText(point.text.text) &
      "\" cx=\"" & num(cx) & "\" cy=\"" & num(cy) & "\" r=\"" & num(r) & "\"" &
      (if strokeWidth.isSome and strokeColor.isNone: " stroke=\"" & fill & "\"" else: "") &
      resolveStyle(styles).shape & "/>"

  # A label goes below its point, or above, right or left of it, or below its quadrant's title,
  # when that is the first place that is inside the chart and free. A second round lets it
  # cross the gaps between quadrants. Large charts skip the search for a free place.
  let careful = dots.len <= CAREFUL
  if careful:
    for dot in dots: taken.add [dot.cx - dot.reach, dot.cy - dot.reach, dot.cx + dot.reach, dot.cy + dot.reach]
  var labels = ""
  for dot in dots:
    let (cx, cy, reach, text) = (dot.cx, dot.cy, dot.reach, dot.text)
    let halfW = text.width / 2
    let halfH = text.size * 0.6 + (text.height - text.lineHeight) / 2
    let away = reach + textPad
    let inset = jsMin(away, jsMax(0, (tileW - text.width) / 2))
    let heading = 8 + 4 * (if cx < left + w / 2: (if cy < top + h / 2: 1 else: 2) else: (if cy < top + h / 2: 0 else: 3))
    let below = jsMax(cy + away, taken[heading + 3] + textPad) + halfH
    let spots = [cx, cy + away + halfH, cx, cy - away - halfH, cx + away + halfW, cy, cx - away - halfW, cy, cx, below]
    var tx = cx
    var ty = spots[1]
    var found = false
    var k = 0
    while k < 20:
      let spot = k mod 10
      # A label moved below a title keeps clear of the plot's edge.
      let margin = if spot == 8: inset else: 0.0
      let x = if (spot < 4 or spot == 8) and text.width < w:
                jsMin(jsMax(spots[spot], left + halfW + margin), left + w - halfW - margin)
              else: spots[spot]
      let y = spots[spot + 1]
      if x - halfW < left or x + halfW > left + w or y - halfH < top or y + halfH > top + h:
        k += 2
        continue
      let free = not careful or isClear((if k < 10: 0 else: 8), x - halfW, y - halfH, x + halfW, y + halfH)
      if not found or free:
        tx = x
        ty = y
        found = true
      if free: break
      k += 2
    if careful: taken.add [tx - halfW, ty - halfH, tx + halfW, ty + halfH]
    labels.add labelSvg(text, tx, ty, " class=\"pele-label\"")

  # Mermaid puts each new point under the ones before it.
  circles.reverse()
  let content =
    labelSvg(title, width / 2, titlePad / 2 + title.height / 2, " class=\"pele-title\"" & sizeAttr(titleSize, size) & " font-weight=\"var(--_tw)\"") &
    "<g class=\"pele-quadrants\" fill=\"var(--_s)\" stroke=\"var(--_b)\">" & quadrants & "</g>" &
    (if axes != "": "<g class=\"pele-axis-labels\" font-size=\"" & jsString(xAxisSize) & "\" fill=\"var(--_m)\">" & axes & "</g>" else: "") &
    (if dots.len > 0: "<g class=\"pele-points\" fill=\"" & fill & "\">" & circles.join("") & "</g>" &
                      "<g class=\"pele-point-labels\" font-size=\"" & jsString(pointSize) & "\">" & labels & "</g>"
     else: "")

  Rendered(
    svg: svgDocument("quadrantChart", width, height, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: width,
    height: height)

## port-of: src/diagrams/xychart/render.ts
## port-status: draft
##
## JavaScript's `undefined` for a number is NaN here: `finite` gives NaN for a value that is not
## a finite number, and `?? fallback` becomes `orElse`.
import std/options
from std/math import floor, ceil, isNaN, classify, FloatClass
import ../../errors
import ../../js
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../util/yaml
import ../common/fit_width
import db, ticks

const
  TICK = 4.0
  SWATCH = 12.0
  ROW = 26.0
  LEGEND_GAP = 24.0
  LIMIT = 1e300

type Mark = object
  at: float
  label: Label

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

func orElse(x, fallback: float): float = (if x.isNaN: fallback else: x)

func record(value: YamlValue): Config =
  if isRecord(value): value else: ymap()

func on(config: Config, key: string, fallback = true): bool =
  let value = config[key]
  if value != nil and value.kind == yBool: value.b else: fallback

func dimension(value: YamlValue, fallback: float): float =
  if value != nil and value.kind == yNumber and value.n > 0: jsRound(jsMin(jsMax(value.n, 100), 4000))
  else: fallback

func finite(value: float): float =
  if isFinite(value): jsMin(jsMax(value, -LIMIT), LIMIT) else: NaN

func widest(marks: seq[Mark]): float =
  for mark in marks: result = jsMax(result, mark.label.width)

proc aligned(label: Label, x, y: float, anchor: string): string =
  ## Writes a label with its left edge, center or right edge at x. A plain one-line label keeps
  ## its place when the text is wider or narrower than measured.
  if label.lines.len == 1:
    let line = label.lines[0]
    if line.len == 1 and not line[0].hasIcon and line[0].style == 0:
      return "<text x=\"" & num(x) & "\" y=\"" & num(y + label.size * 0.35) & "\" text-anchor=\"" & anchor &
        "\">" & esc(line[0].text) & "</text>"
  let shift = if anchor == "start": label.width / 2 elif anchor == "end": -label.width / 2 else: 0.0
  labelSvg(label, x + shift, y, "")

proc renderXyChart*(model: XyChartDb, config: Config, options: RenderOptions): Rendered =
  if model.plots.len == 0:
    raise newPeleError("No Plot to render, please provide a plot with some data", "semantic", "xychart")
  let chart = record(config["xyChart"])
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.75)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let natural = dimension(chart["width"], 700)
  let width = capWidth(options, natural, 240)
  # A narrower chart is not as much shorter, so that the plot keeps room for its marks.
  let height = jsRound(dimension(chart["height"], 500) * jsMax(0.6, width / natural))
  let orientation = if model.orientation != "": model.orientation
                    elif chart["chartOrientation"] != nil and chart["chartOrientation"].kind == yString: chart["chartOrientation"].s
                    else: ""
  let horizontal = orientation == "horizontal"
  # The value of a bar is always written past its end, which is what showDataLabelOutsideBar asks
  # for in Mermaid. Inside, whether it fits changes from bar to bar and with the width of the chart.
  let showValues = on(chart, "showDataLabel", false)
  let x = model.xAxis
  let plots = model.plots
  proc text(raw: string, fontSize, max: float): Label = layoutLabel(raw, false, measurer, fontSize, max)
  let lineHeight = text("0", small, 4000).height
  let tinyHeight = text("0", tiny, 4000).height

  let title = layoutLabel(if on(chart, "showTitle"): model.title else: "", false, measurer, size,
                          width - 2 * pad, Bold)
  let titleSpace = if title.height > 0: title.height + 12 else: 0.0

  var legend: seq[(int, Label)]
  var legendWidth = 0.0
  if on(chart, "showLegend"):
    for index, plot in plots:
      if plot.title == "": continue
      let label = text(plot.title, small, width * 0.3)
      legend.add (index, label)
      legendWidth = jsMax(legendWidth, label.width + SWATCH + 8)
  let legendSpace = if legend.len > 0: legendWidth + LEGEND_GAP else: 0.0

  # The value range: as written, or taken from the data, where bars stand on zero and the
  # range grows to whole steps.
  var bars = 0
  for plot in plots:
    if plot.bar: inc bars
  var lo = finite(model.yAxis.min).orElse(Inf)
  var hi = finite(model.yAxis.max).orElse(NegInf)
  let exact = model.hasSetYAxis and isFinite(lo) and isFinite(hi) and lo != hi
  if not exact:
    lo = Inf
    hi = NegInf
    for plot in plots:
      for (_, raw) in plot.data:
        let value = finite(raw)
        if value.isNaN: continue
        if value < lo: lo = value
        if value > hi: hi = value
    if lo > hi:
      lo = 0
      hi = 0
    if bars > 0:
      lo = jsMin(lo, 0)
      hi = jsMax(hi, 0)
    if lo == hi:
      if lo == 0: hi = 1
      else:
        lo -= abs(lo) / 2
        hi += abs(hi) / 2

  proc valueMarks(length, spacing: float): seq[Mark] =
    let step = tickStep(abs(hi - lo), jsMax(2, jsMin(10, floor(length / spacing))))
    if not exact:
      lo = tickValue(step, floor(tickIndex(step, lo) + 1e-9))
      hi = tickValue(step, ceil(tickIndex(step, hi) - 1e-9))
    for value in ticksBetween(jsMin(lo, hi), jsMax(lo, hi), step):
      result.add Mark(at: (value - lo) / (hi - lo), label: text(jsString(value), small, 4000))

  # Places along the category axis are fractions of its length. Categories and bars sit in the
  # middle of equal slots; the points of a line on a numeric axis run from end to end.
  var count = 1
  if x.band: count = max(x.categories.len, 1)
  else:
    for plot in plots: count = max(count, plot.data.len)
  let slot = 1 / float(count)
  let inset = if x.band or bars > 0: slot / 2 else: 0.0
  let x0 = finite(if not x.band: x.min else: NaN)
  let x1 = finite(if not x.band: x.max else: NaN)
  let ranged = not x0.isNaN and not x1.isNaN and x0 != x1
  proc place(i, n: int): float =
    if x.band: (float(i) + 0.5) * slot
    else: inset + (if n > 1: float(i) / float(n - 1) elif ranged: 0.0 else: 0.5) * (1 - 2 * inset)

  let categoryConf = record(chart["xAxis"])
  let valueConf = record(chart["yAxis"])
  let leftConf = if horizontal: categoryConf else: valueConf
  let bottomConf = if horizontal: valueConf else: categoryConf
  let leftTitle = text(if on(leftConf, "showTitle"): (if horizontal: x.title else: model.yAxis.title) else: "",
                       small, height * 0.8)
  let bottomTitle = text(if on(bottomConf, "showTitle"): (if horizontal: model.yAxis.title else: x.title) else: "",
                         small, width * 0.8)
  let leftTick = if on(leftConf, "showTick"): TICK else: 0.0
  let bottomTick = if on(bottomConf, "showTick"): TICK else: 0.0
  let leftLabels = on(leftConf, "showLabel")
  let bottomLabels = on(bottomConf, "showLabel")

  let wrapAt = if horizontal: width * 0.3 else: jsMax(48, (width - 2 * pad - 64 - legendSpace) * slot - 8)
  var categories: seq[Label]
  if x.band and on(categoryConf, "showLabel"):
    for category in x.categories: categories.add text(category, small, wrapAt)
  var categoryWidth = 0.0
  var categoryHeight = 0.0
  for label in categories:
    categoryWidth = jsMax(categoryWidth, label.width)
    categoryHeight = jsMax(categoryHeight, label.height)

  # The labelled places of the category axis. Labels that would run into each other are thinned out.
  proc categoryMarks(length: float): seq[Mark] =
    if x.band:
      let need = if categories.len == 0: 8.0 elif horizontal: categoryHeight else: categoryWidth + 12
      let every = int(jsMax(1, ceil(need / (length * slot))))
      var i = 0
      while i < x.categories.len:
        result.add Mark(at: (float(i) + 0.5) * slot,
                        label: if i < categories.len: categories[i] else: text("", small, 0))
        i += every
    elif ranged:
      let step = tickStep(abs(x1 - x0), jsMax(2, jsMin(10, floor(length / (if horizontal: 32.0 else: 80.0)))))
      for value in ticksBetween(jsMin(x0, x1), jsMax(x0, x1), step):
        result.add Mark(at: inset + ((value - x0) / (x1 - x0)) * (1 - 2 * inset),
                        label: text(jsString(value), small, 4000))
    elif not x0.isNaN:
      result.add Mark(at: 0.5, label: text(jsString(x0), small, 4000))

  # Room past the end of the value axis for what is written beside a point or a bar.
  var pointLabelWidth = 0.0
  var valueWidth = 0.0
  for plot in plots:
    for label in plot.pointLabels: pointLabelWidth = jsMax(pointLabelWidth, measurer.width(label, tiny, 0))
    if showValues and horizontal and plot.bar:
      for (_, value) in plot.data:
        let f = finite(value)
        valueWidth = jsMax(valueWidth, measurer.width(if f.isNaN: "" else: jsString(f), tiny, 0))

  let bottomLabelHeight = if not bottomLabels: 0.0 elif horizontal or not x.band: lineHeight else: categoryHeight
  let bottomSpace = bottomTick + (if bottomLabelHeight > 0: bottomLabelHeight + 4 else: 0.0) +
                    (if bottomTitle.height > 0: bottomTitle.height + 4 else: 0.0)
  let headroom = if horizontal: 0.0
                 elif pointLabelWidth > 0 or showValues: tinyHeight + 4
                 elif leftLabels: lineHeight / 2
                 else: 0.0
  let top = pad + titleSpace + headroom
  let plotHeight = jsMax(1, height - pad - bottomSpace - top)
  let bottom = top + plotHeight

  let leftMarks = if horizontal: categoryMarks(plotHeight) else: valueMarks(plotHeight, 56)
  let leftLabelWidth = if leftLabels: widest(leftMarks) else: 0.0
  let left = pad + (if leftTitle.height > 0: leftTitle.height + 6 else: 0.0) +
             (if leftLabelWidth > 0: leftLabelWidth + 6 else: 0.0) + leftTick
  let beside = jsMax(if pointLabelWidth > 0: pointLabelWidth + 12 else: 0.0,
                     if valueWidth > 0: valueWidth + 8 else: 0.0)
  let reach = if horizontal: jsMin(width * 0.25, beside) else: 0.0
  var plotWidth = jsMax(1, width - pad - left - legendSpace - reach)
  let bottomMarks = if horizontal: valueMarks(plotWidth, 80) else: categoryMarks(plotWidth)
  if bottomLabels and legendSpace + reach == 0:
    var over = 0.0
    for mark in bottomMarks: over = jsMax(over, mark.at * plotWidth + mark.label.width / 2 - plotWidth)
    plotWidth = jsMax(1, plotWidth - over)
  let right = left + plotWidth

  proc px(c, v: float): float = (if horizontal: left + v * plotWidth else: left + c * plotWidth)
  proc py(c, v: float): float = (if horizontal: top + c * plotHeight else: bottom - v * plotHeight)
  proc scale(value: float): float = (value - lo) / (hi - lo)
  func clamp(v: float): float = jsMin(jsMax(v, 0), 1)

  # A line across the plot at a place on the value axis.
  proc rule(v: float): string =
    if horizontal: "M" & num(px(0, v)) & "," & num(top) & "V" & num(bottom)
    else: "M" & num(left) & "," & num(py(0, v)) & "H" & num(right)

  var grid = ""
  for mark in (if horizontal: bottomMarks else: leftMarks): grid.add rule(mark.at)

  var axis = ""
  var labels = ""
  if on(leftConf, "showAxisLine"): axis.add "M" & num(left) & "," & num(top) & "V" & num(bottom)
  if on(bottomConf, "showAxisLine"): axis.add "M" & num(left) & "," & num(bottom) & "H" & num(right)
  for mark in leftMarks:
    let y = if horizontal: top + mark.at * plotHeight else: bottom - mark.at * plotHeight
    if leftTick != 0: axis.add "M" & num(left) & "," & num(y) & "h" & jsString(-leftTick)
    if leftLabels: labels.add aligned(mark.label, left - leftTick - 6, y, "end")
  for mark in bottomMarks:
    let at = left + mark.at * plotWidth
    if bottomTick != 0: axis.add "M" & num(at) & "," & num(bottom) & "v" & jsString(bottomTick)
    if bottomLabels: labels.add aligned(mark.label, at, bottom + bottomTick + 4 + mark.label.height / 2, "middle")

  let span = (if horizontal: plotHeight else: plotWidth) * slot
  let group = span * 0.7
  let thickness = group / float(max(bars, 1))
  let gap = if bars > 1: jsMin(2, thickness * 0.2) else: 0.0
  let base = clamp(scale(0))
  # Bars that go both ways get a line to stand on.
  if bars > 0 and base > 0 and base < 1: axis.add rule(base)
  # Lines are drawn over the bars wherever they were declared, as a bar would hide part of one
  # under it. A series keeps the color of its place in the source.
  var series = ""
  var lines = ""
  var outside = ""
  var pointLabels = ""
  var bar = 0
  for index, plot in plots:
    let color = seriesColor(index)
    let id = if plot.title != "": " data-id=\"" & escText(plot.title) & "\"" else: ""
    # A series declared before the categories can hold more values than there are categories.
    let n = if x.band: min(plot.data.len, count) else: plot.data.len
    if plot.bar:
      let offset = (float(bar) - float(bars - 1) / 2) * thickness - (thickness - gap) / 2
      inc bar
      var rects = ""
      for i in 0 ..< n:
        let value = finite(plot.data[i][1])
        if value.isNaN: continue
        let c = place(i, n)
        let v = clamp(scale(value))
        let source = jsMin(base, v)
        let to = jsMax(base, v)
        let bx = if horizontal: px(c, source) else: px(c, 0) + offset
        let by = if horizontal: py(c, 0) + offset else: py(c, to)
        let bw = if horizontal: (to - source) * plotWidth else: thickness - gap
        let bh = if horizontal: thickness - gap else: (to - source) * plotHeight
        rects.add "<rect x=\"" & num(bx) & "\" y=\"" & num(by) & "\" width=\"" & num(bw) & "\" height=\"" & num(bh) & "\"/>"
        if not showValues: continue
        let label = jsString(value)
        let w = measurer.width(label, tiny, 0)
        # Towards the end of the bar: 1 when it runs up or right from the baseline, -1 the other way.
        let outward = if v >= base: 1.0 else: -1.0
        var tx = bx + bw / 2
        var ty = by + bh / 2
        var anchor = "middle"
        if horizontal:
          if bh < tiny: continue
          tx = (if outward > 0: bx + bw else: bx) + outward * 6
          anchor = if outward > 0: "start" else: "end"
        else:
          if w + 2 > span / float(bars): continue
          ty = (if outward > 0: by else: by + bh) - outward * (tinyHeight / 2 + 2)
        outside.add "<text x=\"" & num(tx) & "\" y=\"" & num(ty + tiny * 0.35) & "\" text-anchor=\"" & anchor &
          "\">" & label & "</text>"
      series.add "<g class=\"pele-series pele-bars\"" & id & " fill=\"" & color & "\">" & rects & "</g>"
      continue

    # A line is cut where it leaves the value range, so it stays inside the plot.
    var d = ""
    var dots = ""
    var pen = false
    var pc = 0.0
    var pv = NaN
    for i in 0 ..< n:
      let value = finite(plot.data[i][1])
      if value.isNaN:
        pv = NaN
        continue
      let c = place(i, n)
      let v = scale(value)
      let visible = v >= 0 and v <= 1
      if pv.isNaN:
        if visible: d.add "M" & num(px(c, v)) & "," & num(py(c, v))
        pen = visible
      else:
        let dv = v - pv
        var t0 = 0.0
        var t1 = 1.0
        if dv != 0:
          let a = -pv / dv
          let b = (1 - pv) / dv
          t0 = jsMax(t0, jsMin(a, b))
          t1 = jsMin(t1, jsMax(a, b))
        elif not visible:
          t0 = 2
        if t0 <= t1:
          let c0 = pc + (c - pc) * t0
          let v0 = pv + dv * t0
          let c1 = pc + (c - pc) * t1
          let v1 = pv + dv * t1
          if not pen or t0 > 0: d.add "M" & num(px(c0, v0)) & "," & num(py(c0, v0))
          d.add "L" & num(px(c1, v1)) & "," & num(py(c1, v1))
        pen = visible
      pc = c
      pv = v
      if not visible: continue
      let cx = px(c, v)
      let cy = py(c, v)
      if span >= 12: dots.add "<circle cx=\"" & num(cx) & "\" cy=\"" & num(cy) & "\" r=\"3\"/>"
      let label = text(if plot.hasPointLabels and i < plot.pointLabels.len: plot.pointLabels[i] else: "", tiny, 4000)
      if label.height > 0:
        let half = label.width / 2
        pointLabels.add(
          if horizontal: aligned(label, cx + 10, cy, "start")
          else: aligned(label, jsMax(jsMin(cx, right - half), left + half), cy - 6 - label.height / 2, "middle"))
    lines.add "<g class=\"pele-series pele-line\"" & id & " fill=\"" & color & "\">" &
      (if d != "": "<path d=\"" & d & "\" fill=\"none\" stroke=\"" & color &
                   "\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" else: "") &
      dots & "</g>"

  var titles = ""
  if leftTitle.height > 0:
    titles.add "<g transform=\"translate(" & num(pad + leftTitle.height / 2) & "," & num(top + plotHeight / 2) &
      ") rotate(-90)\">" & labelSvg(leftTitle, 0, 0, "") & "</g>"
  titles.add labelSvg(bottomTitle, left + plotWidth / 2, height - pad - bottomTitle.height / 2, "")

  var legendOut = ""
  var legendHeight = 0.0
  for (_, label) in legend: legendHeight += jsMax(ROW, label.height + 6)
  var ly = top + jsMax(0, (plotHeight - legendHeight) / 2)
  let lx = right + reach + LEGEND_GAP
  for (index, label) in legend:
    let row = jsMax(ROW, label.height + 6)
    if ly + row > height: break
    let y = ly + row / 2
    let color = seriesColor(index)
    legendOut.add "<g class=\"pele-legend-item\" data-id=\"" & escText(plots[index].title) & "\">" &
      (if plots[index].bar:
        "<rect x=\"" & num(lx) & "\" y=\"" & num(y - SWATCH / 2) & "\" width=\"" & jsString(SWATCH) &
          "\" height=\"" & jsString(SWATCH) & "\" rx=\"2\" fill=\"" & color & "\"/>"
      else:
        "<path d=\"M" & num(lx) & "," & num(y) & "h" & jsString(SWATCH) & "\" stroke=\"" & color &
          "\" stroke-width=\"2\" stroke-linecap=\"round\"/>") &
      labelSvg(label, lx + SWATCH + 8 + label.width / 2, y, "") &
      "</g>"
    ly += row

  let content =
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    (if grid != "": "<path class=\"pele-grid\" d=\"" & grid & "\" stroke=\"var(--_a)\"/>" else: "") &
    "<g class=\"pele-plot\">" & series & lines & "</g>" &
    (if axis != "": "<path class=\"pele-axis\" d=\"" & axis & "\" fill=\"none\" stroke=\"var(--_b)\"/>" else: "") &
    (if labels != "": "<g class=\"pele-axis-labels\" font-size=\"" & jsString(small) & "\" fill=\"var(--_m)\">" & labels & "</g>" else: "") &
    (if titles != "": "<g class=\"pele-axis-titles\" font-size=\"" & jsString(small) & "\">" & titles & "</g>" else: "") &
    (if outside != "": "<g class=\"pele-data-labels\" font-size=\"" & jsString(tiny) & "\">" & outside & "</g>" else: "") &
    (if pointLabels != "": "<g class=\"pele-point-labels\" font-size=\"" & jsString(tiny) & "\">" & pointLabels & "</g>" else: "") &
    (if legendOut != "": "<g class=\"pele-legend\" font-size=\"" & jsString(small) & "\">" & legendOut & "</g>" else: "")

  Rendered(
    svg: svgDocument("xychart", width, height, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: width, height: height)

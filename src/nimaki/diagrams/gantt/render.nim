## port-of: src/diagrams/gantt/render.ts
## port-status: draft
import std/[algorithm, options, strutils, tables]
from std/math import ceil, floor
import ../../js
import ../../jsdate
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../util/[url, yaml]
import ../common/fit_width
import axis, dates, db

const
  WIDTH = 800.0
  MIN_PLOT = 240.0
  LABEL_GAP = 8.0

func finite(x: float): bool = x == x and x != Inf and x != -Inf

proc setting(config: Config, key: string, lo, hi: float): Option[float] =
  let value = config["gantt"][key]
  if value != nil and value.kind == yNumber and finite(value.n): some(min(hi, max(lo, value.n))) else: none(float)

proc text(config: Config, key: string): Option[string] =
  let value = config["gantt"][key]
  if value != nil and value.kind == yString: some(value.s) else: none(string)

proc flag(config: Config, key: string): bool =
  let value = config["gantt"][key]
  value != nil and value.kind == yBool and value.b

func dropBreaks(raw: string): string =
  ## raw.replace(/<br\s*\/?>/gi, ' ')
  var i = 0
  while i < raw.len:
    if raw[i] == '<' and i + 2 < raw.len and raw[i + 1] in {'b', 'B'} and raw[i + 2] in {'r', 'R'}:
      var j = i + 3
      while j < raw.len:
        let n = spaceLenAt(raw, j)
        if n == 0: break
        j += n
      if j < raw.len and raw[j] == '/': inc j
      if j < raw.len and raw[j] == '>':
        result.add ' '
        i = j + 1
        continue
    result.add raw[i]
    inc i

proc oneLine(raw: string, measurer: TextMeasurer, size: float): Label =
  ## A task label sits on one row, so only its first line is kept.
  result = layoutLabel(dropBreaks(raw), false, measurer, size, 4000)
  if result.lines.len <= 1: return
  result.lines = @[result.lines[0]]
  result.widths = @[result.widths[0]]
  result.width = result.widths[0]
  result.height = result.lineHeight

func scheduled(task: GanttTask): bool =
  ## Whether scheduling gave the task a start and an end. One that waits on a task that never resolves has neither.
  finite(task.startTime) and finite(task.endTime)

func key(task: GanttTask): int = cast[int](task)

proc packRows(tasks: seq[GanttTask], offset: int, rowOf: var Table[int, int]): int =
  ## Mermaid's compact mode: within a section, a task goes on the first row that is free when it starts.
  var sorted: seq[GanttTask]
  for task in tasks:
    if scheduled(task): sorted.add task
  sorted.sort(proc (a, b: GanttTask): int =
    let d = a.startTime - b.startTime
    if d != 0: (if d < 0: -1 else: 1) else: cmp(a.order, b.order))
  var free: seq[float]
  for task in sorted:
    let start = task.startTime
    var row = 0
    while row < free.len and start < free[row]: inc row
    if row == free.len: free.add task.endTime else: free[row] = task.endTime
    rowOf[key(task)] = offset + row
  var rows = free.len
  for task in tasks:
    if key(task) notin rowOf:
      rowOf[key(task)] = offset + rows
      inc rows
  max(rows, 1)

type Bar = object
  task: GanttTask
  label: Label
  row: int
  x0, x1: float
  labelX: float
  inside: bool

proc renderGantt*(model: GanttDb, config: Config, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let now = clock(options.now)

  let labelSize = setting(config, "fontSize", 4, 72).get(jsRound(size * 0.8125))
  let sectionSize = setting(config, "sectionFontSize", 4, 72).get(labelSize)
  let tickSize = jsRound(size * 0.75)
  let barHeight = setting(config, "barHeight", 4, 400).get(jsRound(labelSize * 1.85))
  let barGap = setting(config, "barGap", 0, 400).get(jsRound(barHeight / 4))
  let rowHeight = barHeight + barGap
  let sectionStyles = int(jsRound(setting(config, "numberSectionStyles", 1, 1000).get(4)))
  let compact = model.displayMode == "compact"
  let topAxis = model.topAxis or flag(config, "topAxis")

  let tasks = model.getTasks(now)
  var rowTasks, verts: seq[GanttTask]
  for task in tasks:
    if not task.vert: rowTasks.add task
    elif scheduled(task): verts.add task

  var categories = initOrderedTable[string, int]()
  for task in rowTasks:
    if task.section notin categories: categories[task.section] = categories.len

  var rowOf = initTable[int, int]()
  var rowSection: seq[string]
  if compact:
    var groups = initOrderedTable[string, seq[GanttTask]]()
    for task in rowTasks: groups.mgetOrPut(task.section, @[]).add task
    for section, group in groups:
      let rows = packRows(group, rowSection.len, rowOf)
      for i in 0 ..< rows: rowSection.add section
  else:
    for task in rowTasks:
      rowOf[key(task)] = rowSection.len
      rowSection.add task.section
  let rowCount = rowSection.len

  var start = Inf
  var stop = -Inf
  for task in tasks:
    if not scheduled(task): continue
    start = min(start, task.startTime)
    stop = max(stop, task.endTime)
  let hasPlot = start <= stop

  let title = layoutLabel(model.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 16 else: 0.0
  let acc = Accessible(accTitle: model.accTitle, accDescr: model.accDescr)

  if not hasPlot:
    let width = ceil(max(title.width, 1) + 2 * pad)
    let height = ceil(max(title.height, 1) + 2 * pad)
    let content = labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"")
    return Rendered(svg: svgDocument("gantt", width, height, size, options, acc, content), width: width,
                    height: height, links: @[])

  var sectionLabels = initTable[string, Label]()
  var sectionWidth = 0.0
  for section in categories.keys:
    let label = layoutLabel(section, false, measurer, sectionSize, 180)
    sectionLabels[section] = label
    sectionWidth = max(sectionWidth, label.width)

  let axisFormat = if model.axisFormat != "": model.axisFormat
                   elif model.dateFormat == "D": "%d"
                   else: text(config, "axisFormat").get("%Y-%m-%d")
  proc tickLabel(t: float): string = timeFormat(axisFormat, fromTime(t))
  let sampleWidth = max(measurer.width(tickLabel(start), tickSize, 0), measurer.width(tickLabel(stop), tickSize, 0))

  let left = pad + setting(config, "leftPadding", 0, 2000).get(
    max(if sectionWidth > 0: sectionWidth + 24 else: 0.0, sampleWidth / 2))
  let rightPadding = setting(config, "rightPadding", 0, 2000).get(max(16.0, sampleWidth / 2))
  let target = capWidth(options, setting(config, "useWidth", 100, 20000).get(WIDTH), 280)
  let plotWidth = max(MIN_PLOT, target - left - rightPadding - pad)
  let right = left + plotWidth
  let scale = if stop > start: plotWidth / (stop - start) else: 0.0
  proc x(t: float): float = (if scale == 0: left + plotWidth / 2 else: left + (t - start) * scale)

  let tickHeight = jsRound(tickSize * 1.75)
  let topPadding = setting(config, "topPadding", 0, 2000)
  let gridStart = setting(config, "gridLineStartPadding", 0, 2000)
  let headHeight = pad + titleHeight + (if topAxis: tickHeight else: 0.0)
  let plotTop = max(headHeight, topPadding.get(0))
  # Mermaid starts its grid lines above the first row by the difference between these two settings.
  # Here that only uses room a larger `topPadding` leaves free.
  let gridLead = if topPadding.isSome and gridStart.isSome:
                   max(0.0, min(topPadding.get - gridStart.get, plotTop - headHeight))
                 else: 0.0
  let plotHeight = float(max(rowCount, 1)) * rowHeight
  let plotBottom = plotTop + plotHeight

  # Bars and where their labels go: inside when they fit, otherwise beside the bar on the side with room.
  var bars: seq[Bar]
  var extent = right + rightPadding
  for task in rowTasks:
    let label = oneLine(task.task, measurer, labelSize)
    let row = rowOf[key(task)]
    if not scheduled(task):
      let labelX = left + LABEL_GAP + label.width / 2
      extent = max(extent, labelX + label.width / 2)
      bars.add Bar(task: task, label: label, row: row, x0: NaN, x1: NaN, labelX: labelX, inside: false)
      continue
    var x0 = x(task.startTime)
    var x1 = max(x(if task.hasRenderEnd: task.renderEndTime else: task.endTime),
                 x0 + (if task.milestone: 0.0 else: 2.0))
    if task.milestone:
      let mid = x0 + (x(task.endTime) - x0) / 2
      x0 = mid - barHeight / 2
      x1 = mid + barHeight / 2
    let inside = not task.milestone and label.width + 2 * LABEL_GAP <= x1 - x0
    var labelX = (x0 + x1) / 2
    if not inside:
      let fitsRight = x1 + LABEL_GAP + label.width <= right + rightPadding
      let fitsLeft = x0 - LABEL_GAP - label.width >= left
      labelX = if fitsRight or not fitsLeft: x1 + LABEL_GAP + label.width / 2 else: x0 - LABEL_GAP - label.width / 2
      extent = max(extent, labelX + label.width / 2)
    bars.add Bar(task: task, label: label, row: row, x0: x0, x1: x1, labelX: labelX, inside: inside)

  let interval = if model.tickInterval != "": model.tickInterval else: text(config, "tickInterval").get("")
  let weekday = if model.weekday != "": model.weekday else: text(config, "weekday").get("sunday")
  let count = max(2.0, min(10.0, floor(plotWidth / (sampleWidth + 24))))
  let ticks = intervalTicks(interval, weekday, start, stop, ceil(plotWidth / 3)).get(autoTicks(start, stop, count))

  var grid = ""
  var axisBottom = ""
  var axisTop = ""
  var lastRight = -Inf
  var lastLabel = ""
  let bottomY = plotBottom + tickHeight / 2 + 2
  let topY = plotTop - gridLead - tickHeight / 2 - 2
  for t in ticks:
    let tx = x(t)
    grid.add "M" & num(tx) & "," & num(plotTop - gridLead) & "V" & num(plotBottom)
    let label = tickLabel(t)
    let width = measurer.width(label, tickSize, 0)
    # A label is skipped when it would run into the one before it or only repeat it; its grid line stays.
    if tx - width / 2 < lastRight + 8 or label == lastLabel: continue
    lastRight = tx + width / 2
    lastLabel = label
    extent = max(extent, lastRight)
    let body = "text-anchor=\"middle\">" & esc(label) & "</text>"
    axisBottom.add "<text x=\"" & num(tx) & "\" y=\"" & num(bottomY + tickSize * 0.35) & "\" " & body
    if topAxis: axisTop.add "<text x=\"" & num(tx) & "\" y=\"" & num(topY + tickSize * 0.35) & "\" " & body

  # Vertical markers take no row. Their labels go under the axis, on as many lines as it takes to keep them apart.
  var vertLines = ""
  var vertLabels = ""
  var vertEnds: seq[float]
  let vertTop = plotBottom + tickHeight + 4
  let vertLine = jsRound(labelSize * 1.5)
  var sortedVerts = verts
  sortedVerts.sort(proc (a, b: GanttTask): int =
    let d = a.startTime - b.startTime
    if d < 0: -1 elif d > 0: 1 else: 0)
  for task in sortedVerts:
    let vx = x(task.startTime)
    let label = oneLine(task.task, measurer, labelSize)
    let cx = max(pad + label.width / 2, vx)
    var line = 0
    while line < vertEnds.len and cx - label.width / 2 < vertEnds[line] + 8: inc line
    if line == vertEnds.len: vertEnds.add 0
    vertEnds[line] = cx + label.width / 2
    extent = max(extent, vertEnds[line])
    vertLines.add "<path class=\"pele-vert\" data-id=\"" & escText(task.id) & "\" d=\"M" & num(vx) & "," &
      num(plotTop - gridLead) & "V" & num(plotBottom) & "\"/>"
    vertLabels.add labelSvg(label, cx, vertTop + float(line) * vertLine + vertLine / 2,
                            " class=\"pele-vert-label\" data-id=\"" & escText(task.id) & "\"")

  let width = ceil(max(extent, pad + title.width) + pad)
  let height = ceil(plotBottom + tickHeight + (if vertEnds.len > 0: 4 + float(vertEnds.len) * vertLine else: 0.0) + pad)

  # Section bands, one per run of rows that share a section, shaded on alternate sections.
  var bands = ""
  var sectionOut = ""
  var row = 0
  while row < rowCount:
    let section = rowSection[row]
    var stopRow = row + 1
    while stopRow < rowCount and rowSection[stopRow] == section: inc stopRow
    let index = categories[section] mod sectionStyles
    let y = plotTop + float(row) * rowHeight
    let h = float(stopRow - row) * rowHeight
    if categories.len > 1 or section != "":
      bands.add "<rect class=\"pele-section pele-section-" & $index & "\" x=\"0\" y=\"" & num(y) & "\" width=\"" &
        jsString(width) & "\" height=\"" & num(h) & "\" fill=\"" & (if index mod 2 == 0: "var(--_s)" else: "none") & "\"/>"
    let label = sectionLabels[section]
    sectionOut.add labelSvg(label, pad + 8 + label.width / 2, y + h / 2,
                            " class=\"pele-section-label\" data-id=\"" & escText(section) & "\"", options.icons)
    row = stopRow

  # Excluded days, as Mermaid marks them: a day at a time from the first task's start, and not at all
  # when the chart spans more than five years.
  var excluded = ""
  if (model.excludes.len > 0 or model.includes.len > 0) and add(fromTime(start), 6, "y") > stop:
    var dayFrom, dayTo: JsDate
    var open = false
    proc flush() =
      if not open: return
      let dayStart = dayFrom.setHours(0, 0, 0, 0)
      let dayEnd = dayTo.setHours(23, 59, 59, 999)
      let ex0 = max(left, x(dayStart))
      let ex1 = min(right, x(dayEnd))
      if ex1 > ex0:
        excluded.add "<rect x=\"" & num(ex0) & "\" y=\"" & num(plotTop) & "\" width=\"" & num(ex1 - ex0) &
          "\" height=\"" & num(plotHeight) & "\"/>"
      open = false
    var day = fromTime(start)
    while day <= stop:
      if model.isInvalidDate(day):
        if not open:
          dayFrom = day
          open = true
        dayTo = day
      else:
        flush()
      day = addDays(day, 1)
    flush()

  var links: seq[LinkInfo]
  var tasksOut = ""
  for bar in bars:
    let task = bar.task
    let cy = plotTop + float(bar.row) * rowHeight + rowHeight / 2
    let state = if task.active: "active" elif task.done: "done" else: ""
    var classes = "pele-task"
    if state != "": classes.add " pele-" & state
    if task.crit: classes.add " pele-crit"
    if task.milestone: classes.add " pele-milestone"
    if "clickable" in task.classes: classes.add " pele-clickable"

    var shape = ""
    var textFill = ""
    if bar.x0 != bar.x0:
      classes.add " pele-unscheduled"
      textFill = " fill=\"var(--_m)\""
    else:
      # A critical task takes the critical color in place of the accent. Done, it keeps the fill
      # of finished work and only its border is in that color.
      let color = if task.crit: CRITICAL else: "var(--_c)"
      let paint = if state == "done": "fill=\"var(--_a)\""
                  elif state == "active": "fill=\"" & color & "\" fill-opacity=\"0.25\""
                  else: "fill=\"" & color & "\""
      let stroke = "stroke=\"" & (if state == "done" and not task.crit: "var(--_b)" else: color) & "\""
      if task.milestone:
        let cx = (bar.x0 + bar.x1) / 2
        let r = barHeight / 2
        shape = "<path d=\"M" & num(cx) & "," & num(cy - r) & "L" & num(cx + r) & "," & num(cy) & "L" & num(cx) &
          "," & num(cy + r) & "L" & num(cx - r) & "," & num(cy) & "Z\" " & paint & " " & stroke & " stroke-linejoin=\"round\"/>"
      else:
        shape = "<rect x=\"" & num(bar.x0) & "\" y=\"" & num(cy - barHeight / 2) & "\" width=\"" & num(bar.x1 - bar.x0) &
          "\" height=\"" & num(barHeight) & "\" " & paint & " " & stroke & ROUNDED & "/>"
      if bar.inside: textFill = (if state == "": " fill=\"var(--_bg)\"" else: "")
      elif state == "done": textFill = " fill=\"var(--_m)\""

    var body = shape & labelSvg(bar.label, bar.labelX, cy, " class=\"pele-label\"" & textFill)
    if task.id in model.links: body = linked(body, model.links[task.id], task.id, links, options)
    tasksOut.add "<g class=\"" & classes & "\" data-id=\"" & escText(task.id) & "\">" & body & "</g>"

  var today = ""
  if model.todayMarker != "off" and now >= start and now <= stop and stop > start:
    let tx = x(now)
    let top = plotTop - gridLead
    let style = if model.todayMarker != "": resolveStyle(model.todayMarker.split(',')).line else: ""
    today = "<g class=\"pele-today\"><path d=\"M" & num(tx) & "," & num(top) & "V" & num(plotBottom) &
      "\" fill=\"none\" stroke=\"var(--_c)\" stroke-width=\"2\"" & style & "/>" &
      (if style != "": "" else: "<path d=\"M" & num(tx - 4) & "," & num(top - 5) & "H" & num(tx + 4) & "L" & num(tx) &
        "," & num(top + 1) & "Z\" fill=\"var(--_c)\"/>") &
      "</g>"

  let axisLine = "M" & num(left) & "," & num(plotBottom) & "H" & num(right) &
    (if topAxis: "M" & num(left) & "," & num(plotTop - gridLead) & "H" & num(right) else: "")
  let content =
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    (if bands != "": "<g class=\"pele-sections\">" & bands & "</g>" else: "") &
    (if excluded != "": "<g class=\"pele-excluded\" fill=\"var(--_a)\">" & excluded & "</g>" else: "") &
    "<g class=\"pele-grid\" fill=\"none\"><path d=\"" & grid & "\" stroke=\"var(--_b)\" stroke-dasharray=\"1 3\"/><path d=\"" &
      axisLine & "\" stroke=\"var(--_b)\"/></g>" &
    (if vertLines != "": "<g class=\"pele-verts\" fill=\"none\" stroke=\"var(--_l)\" stroke-width=\"1.5\" stroke-dasharray=\"4 3\">" &
       vertLines & "</g>" else: "") &
    today &
    "<g class=\"pele-tasks\" font-size=\"" & num(labelSize) & "\">" & tasksOut & "</g>" &
    "<g class=\"pele-section-labels\" font-size=\"" & num(sectionSize) & "\">" & sectionOut & "</g>" &
    "<g class=\"pele-axis\" font-size=\"" & jsString(tickSize) & "\" fill=\"var(--_m)\">" & axisBottom & axisTop & "</g>" &
    (if vertLabels != "": "<g class=\"pele-vert-labels\" font-size=\"" & num(labelSize) & "\">" & vertLabels & "</g>" else: "")

  Rendered(svg: svgDocument("gantt", width, height, size, options, acc, content), width: width, height: height,
           links: links)

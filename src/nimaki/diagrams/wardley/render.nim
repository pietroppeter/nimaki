## port-of: src/diagrams/wardley/render.ts
## port-status: draft
import std/[options, tables, sets, algorithm]
from std/math import ceil, PI
import ../../preprocess
import ../../svg/[builder, edges, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../util/yaml
import ../../js
import ../../jsmath
import ../common/fit_width
import builder as wbuilder
import model

const DEFAULT_STAGES = ["Genesis", "Custom Built", "Product", "Commodity"]
const
  CANVAS_MARGIN = 48.0
    ## Mermaid's canvas has this much room around the plot on every side.
  R = 6.0
  SQUARE = 10.0
  LABEL_OFFSET = 8.0
  PIPELINE_PAD = 15.0
  FORCE_WIDTH = 60.0
  FORCE_HEIGHT = 30.0
  FORCE_HEAD = 20.0
  ACCENT = "var(--_c)"
  LINE = "var(--_l)"
  SQRT2 = 1.4142135623730951

type Placed = ref object
  x, y: float
  node: WardleyNode

proc setting(config: Config, key: string, fallback, min, max: float): float =
  let value = config["wardley-beta"][key]
  if value != nil and value.kind == yNumber and value.n >= min and value.n <= max: value.n else: fallback

func clamp(value, min, max: float): float =
  if value < min: min elif value > max: max else: value

proc startLabel(label: Label, x, y: float, attrs: string): string =
  ## Writes a label with its lines starting at x and its first baseline at y.
  let shared = sharedStyle(label)
  var body = ""
  var baseline = y
  for line in label.lines:
    var first = true
    for span in line:
      if span.hasIcon: continue
      let style = spanStyle(span.style and not shared)
      body.add "<tspan" & (if first: " x=\"" & num(x) & "\" y=\"" & num(baseline) & "\"" else: "") & style & ">" &
        esc(span.text) & "</tspan>"
      first = false
    baseline += label.lineHeight
  if body == "": "" else: "<text" & textStyle(attrs, shared) & " xml:space=\"preserve\">" & body & "</text>"

proc dimension(config: Config, given: Option[float], key: string, fallback: float): float =
  let value = if given.isSome and given.get - given.get == 0: given.get
              else: setting(config, key, fallback, 1, 1e6)
  clamp(value, 200, 10000) - 2 * CANVAS_MARGIN

proc draw(model: WardleyModel, config: Config, options: RenderOptions, plotW, naturalW: float, tight: bool): Rendered

proc renderWardley*(model: WardleyModel, config: Config, options: RenderOptions): Rendered =
  let natural = dimension(config, model.built.size.map(proc (s: tuple[width, height: float]): float = s.width),
                          "width", 900)
  fitWidth(options, natural, 160, proc (plotW: float, tight: bool): Rendered =
    draw(model, config, options, plotW, natural, tight))

proc draw(model: WardleyModel, config: Config, options: RenderOptions, plotW, naturalW: float, tight: bool): Rendered =
  let m = model.built
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.8125)
  let tiny = jsRound(size * 0.6875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  # A narrower map is not as much shorter, so that components keep some room between them.
  let plotH = dimension(config, m.size.map(proc (s: tuple[width, height: float]): float = s.height), "height", 600) *
    max(0.75, plotW / naturalW)
  let gridV = config["wardley-beta"]["showGrid"]
  let showGrid = gridV != nil and gridV.kind == yBool and gridV.b

  var minX = 0.0
  var minY = 0.0
  var maxX = plotW
  var maxY = plotH
  proc grow(x0, y0, x1, y1: float) =
    if x0 < minX: minX = x0
    if y0 < minY: minY = y0
    if x1 > maxX: maxX = x1
    if y1 > maxY: maxY = y1
  proc centered(label: Label, cx, cy: float, attrs: string): string =
    grow(cx - label.width / 2, cy - label.height / 2, cx + label.width / 2, cy + label.height / 2)
    labelSvg(label, cx, cy, attrs, options.icons)
  proc starting(label: Label, x, y: float, attrs: string): string =
    grow(x, y - label.size, x + label.width, y - label.size + label.height + 4)
    startLabel(label, x, y, attrs)
  let defaultWidth = if tight: max(64.0, min(120.0, plotW / 2)) else: 4000.0
  proc text(raw: string, fontSize: float, maxWidth = -1.0, style = 0): Label =
    layoutLabel(raw, false, measurer, fontSize, (if maxWidth < 0: defaultWidth else: maxWidth), style)
  proc projectX(value: float): float = (value / 100) * plotW
  proc projectY(value: float): float = plotH - (value / 100) * plotH

  var stages = m.axes.stages   # not `if ...: m.axes.stages else: @DEFAULT_STAGES`: nim js drops that else
  if stages.len == 0: stages = @DEFAULT_STAGES
  let boundaries = m.axes.stageBoundaries
  let custom = boundaries.len == stages.len
  var frame = ""
  var stageLabels = ""
  var stageBottom = plotH
  var previous = 0.0
  for index, stage in stages:
    let start = if custom: previous else: float(index) / float(stages.len)
    let stop = if custom: clamp(boundaries[index], 0, 1) else: float(index + 1) / float(stages.len)
    previous = stop
    if index > 0:
      frame.add "<path class=\"pele-wardley-stage\" d=\"M" & num(start * plotW) & ",0V" & num(plotH) &
        "\" stroke=\"var(--_b)\" stroke-dasharray=\"4 4\"/>"
    let label = text(stage, small, max(48.0, abs(stop - start) * plotW - 12))
    stageLabels.add centered(label, ((start + stop) / 2) * plotW, plotH + 8 + label.height / 2,
      " class=\"pele-wardley-stage-label\" font-size=\"" & jsString(small) & "\" fill=\"var(--_m)\"")
    stageBottom = max(stageBottom, plotH + 8 + label.height)
  if showGrid:
    for i in 1 ..< 4:
      frame.add "<path class=\"pele-wardley-grid\" d=\"M" & num((plotW * float(i)) / 4) & ",0V" & num(plotH) & "M0," &
        num((plotH * float(i)) / 4) & "H" & num(plotW) & "\" stroke=\"var(--_b)\" stroke-dasharray=\"2 6\"/>"
  frame.add "<path class=\"pele-wardley-axis\" d=\"M0,0V" & num(plotH) & "H" & num(plotW) & "\" stroke=\"" & LINE & "\"/>"
  let xTitle = text("Evolution", small)
  let yTitle = text("Visibility", small)
  let axisAttrs = " class=\"pele-wardley-axis-label\" font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\""
  let axisLabels =
    centered(xTitle, plotW / 2, stageBottom + 6 + xTitle.height / 2, axisAttrs) &
    labelSvg(yTitle, -16, plotH / 2, axisAttrs & " transform=\"rotate(-90 -16 " & num(plotH / 2) & ")\"")
  grow(-16 - yTitle.height / 2, 0, 0, 0)
  let legendTop = stageBottom + 6 + xTitle.height + 10

  var positions = initOrderedTable[string, Placed]()
  for node in m.nodes: positions[node.id] = Placed(x: projectX(node.x.get), y: projectY(node.y.get), node: node)

  # Pipelines: a box around the components, with the parent as a square on its top edge.
  var pipelines = ""
  var members = initTable[string, HashSet[string]]()
  for pipeline in m.pipelines:
    members[pipeline.nodeId] = toHashSet(pipeline.componentIds)
    var parts: seq[Placed]
    for id in pipeline.componentIds:
      if id in positions: parts.add positions[id]
    if parts.len == 0: continue
    parts.sort(proc (a, b: Placed): int = cmp(a.x - b.x, 0.0))
    let left = parts[0].x
    let right = parts[^1].x
    let y = parts[0].y
    let top = y - 2 * R
    if pipeline.nodeId in positions:
      let parent = positions[pipeline.nodeId]
      parent.x = (left + right) / 2
      parent.y = top - SQUARE / 6
    grow(left - PIPELINE_PAD, top, right + PIPELINE_PAD, top + 4 * R)
    pipelines.add "<g class=\"pele-wardley-pipeline\" data-id=\"" & escText(pipeline.nodeId) & "\">" &
      "<rect x=\"" & num(left - PIPELINE_PAD) & "\" y=\"" & num(top) & "\" width=\"" &
      num(right - left + 2 * PIPELINE_PAD) & "\" height=\"" & num(4 * R) & "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" &
      ROUNDED & "/>" &
      (if parts.len > 1: "<path d=\"M" & num(left) & "," & num(y) & "H" & num(right) & "\" stroke=\"" & LINE &
         "\" stroke-dasharray=\"4 4\"/>" else: "") &
      "</g>"

  # How far from a node's center a line to it stops.
  var anchorLabels = initTable[string, Label]()
  let anchorWidth = if tight: max(64.0, plotW / 2) else: 4000.0
  proc reach(at: Placed, ux, uy: float): float =
    let node = at.node
    if node.className == "anchor":
      if node.id notin anchorLabels: anchorLabels[node.id] = text(node.label, small, anchorWidth, Bold)
      let label = anchorLabels[node.id]
      return 1 / hypot(ux / (label.width / 2 + 5), uy / (small * 0.8))
    if node.isPipelineParent: return SQUARE / SQRT2
    if node.sourceStrategy != "": 2 * R else: R

  # Quadrants around a node that a link runs through: 1 up and right, 2 down and right, 4 up and left, 8 down and left.
  var taken = initTable[string, int]()
  proc occupy(at: Placed, ux, uy: float) =
    if abs(ux) < 0.25 or abs(uy) < 0.25: return
    taken[at.node.id] = taken.getOrDefault(at.node.id, 0) or
      (if ux > 0: (if uy < 0: 1 else: 2) elif uy < 0: 4 else: 8)

  var links = ""
  for link in m.links:
    if link.source notin positions or link.target notin positions: continue
    let start = positions[link.source]
    let to = positions[link.target]
    if start == to: continue
    # A pipeline component belongs to its parent already.
    if link.target in members and link.source in members[link.target]: continue
    let dx = to.x - start.x
    let dy = to.y - start.y
    let distance = hypot(dx, dy)
    if distance < 0.01: continue
    let ux = dx / distance
    let uy = dy / distance
    let s = reach(start, ux, uy)
    let e = reach(to, ux, uy)
    if s + e >= distance: continue
    occupy(start, ux, uy)
    occupy(to, -ux, -uy)
    var x1 = start.x + ux * s
    var y1 = start.y + uy * s
    var x2 = to.x - ux * e
    var y2 = to.y - uy * e
    var heads = ""
    if link.flow == "forward" or link.flow == "bidirectional":
      heads.add marker("arrow_point", x2, y2, ux, uy, LINE)
      x2 -= ux * markerTrim("arrow_point")
      y2 -= uy * markerTrim("arrow_point")
    if link.flow == "backward" or link.flow == "bidirectional":
      heads.add marker("arrow_point", x1, y1, -ux, -uy, LINE)
      x1 += ux * markerTrim("arrow_point")
      y1 += uy * markerTrim("arrow_point")
    var caption = ""
    if link.label.isSome and link.label.get != "":
      let label = text(link.label.get, tiny + 1, 200)
      # Beside the middle of the line, on its upper side.
      let side = if ux >= 0: 1.0 else: -1.0
      let px = uy * side
      let py = -ux * side
      let away = 5 + (abs(px) * label.width) / 2 + (abs(py) * label.height) / 2
      caption = centered(label, (start.x + to.x) / 2 + px * away, (start.y + to.y) / 2 + py * away,
        " class=\"pele-edge-label\" font-size=\"" & jsString(tiny + 1) & "\" fill=\"var(--_m)\"")
    links.add "<g class=\"pele-edge" & (if link.dashed: " pele-wardley-dashed" else: "") & "\" data-id=\"" &
      escText(link.source) & "-" & escText(link.target) & "\">" &
      "<path d=\"M" & num(x1) & "," & num(y1) & "L" & num(x2) & "," & num(y2) & "\" stroke=\"" & LINE & "\"" &
      (if link.dashed: " stroke-dasharray=\"6 6\"" else: "") & "/>" &
      heads & caption & "</g>"

  # Evolution: a dashed arrow to where the component is heading, drawn as an open circle.
  var trends = ""
  for trend in m.trends:
    if trend.nodeId notin positions: continue
    let origin = positions[trend.nodeId]
    let tx = projectX(trend.targetX)
    let ty = projectY(trend.targetY)
    let dx = tx - origin.x
    let dy = ty - origin.y
    let distance = hypot(dx, dy)
    var arrow = ""
    let start = if distance > 0: reach(origin, dx / distance, dy / distance) else: 0.0
    if distance > start + R + 4:
      let ux = dx / distance
      let uy = dy / distance
      let ex = tx - ux * (R + 2)
      let ey = ty - uy * (R + 2)
      arrow = "<path d=\"M" & num(origin.x + ux * start) & "," & num(origin.y + uy * start) & "L" &
        num(ex - ux * markerTrim("arrow_point")) & "," & num(ey - uy * markerTrim("arrow_point")) & "\" stroke=\"" &
        ACCENT & "\" stroke-dasharray=\"4 4\"/>" & marker("arrow_point", ex, ey, ux, uy, ACCENT)
    grow(tx - R, ty - R, tx + R, ty + R)
    trends.add "<g class=\"pele-wardley-trend\" data-id=\"" & escText(trend.nodeId) & "\">" & arrow &
      "<circle cx=\"" & num(tx) & "\" cy=\"" & num(ty) & "\" r=\"" & jsString(R) & "\" fill=\"var(--_bg)\" stroke=\"" &
      ACCENT & "\"/></g>"

  var nodes = ""
  let tri = 1.2 * R
  let dot = 0.7 * R
  for at in positions.values:
    let node = at.node
    let x = at.x
    let y = at.y
    let anchor = node.className == "anchor"
    let strategy = node.sourceStrategy
    var shape = ""
    if strategy != "":
      let fill = if strategy == "outsource": "var(--_m)" elif strategy == "buy": "var(--_a)"
                 elif strategy == "build": "var(--_s)" else: "var(--_bg)"
      shape.add "<circle class=\"pele-wardley-" & strategy & "\" cx=\"" & num(x) & "\" cy=\"" & num(y) & "\" r=\"" &
        jsString(2 * R) & "\" fill=\"" & fill & "\" stroke=\"" & LINE & "\"/>"
    if strategy == "market":
      let bx = tri * cos(PI / 6)
      let by = y + tri * sin(PI / 6)
      shape.add "<path d=\"M" & num(x) & "," & num(y - tri) & "L" & num(x - bx) & "," & num(by) & "H" & num(x + bx) &
        "Z\" fill=\"none\" stroke=\"" & LINE & "\"/>"
      for (cx, cy) in [(x, y - tri), (x - bx, by), (x + bx, by)]:
        shape.add "<circle cx=\"" & num(cx) & "\" cy=\"" & num(cy) & "\" r=\"" & num(dot) & "\" fill=\"var(--_bg)\" stroke=\"" &
          LINE & "\"/>"
    elif node.isPipelineParent:
      shape.add "<rect x=\"" & num(x - SQUARE / 2) & "\" y=\"" & num(y - SQUARE / 2) & "\" width=\"" & jsString(SQUARE) &
        "\" height=\"" & jsString(SQUARE) & "\" fill=\"var(--_bg)\" stroke=\"" & LINE & "\"/>"
    elif not anchor:
      shape.add "<circle cx=\"" & num(x) & "\" cy=\"" & num(y) & "\" r=\"" & jsString(R) & "\" fill=\"var(--_bg)\" stroke=\"" &
        LINE & "\"/>"
    if node.inertia == some(true):
      let offset = (if node.isPipelineParent: SQUARE / 2 else: R) + 10 + (if strategy != "": R + 4 else: 0)
      shape.add "<rect class=\"pele-wardley-inertia\" x=\"" & num(x + offset) & "\" y=\"" & num(y - R) &
        "\" width=\"4\" height=\"" & jsString(2 * R) & "\" fill=\"" & LINE & "\"/>"
    let ox = node.labelOffsetX.map(proc (v: float): float = clamp(v, -5000, 5000))
    let oy = node.labelOffsetY.map(proc (v: float): float = clamp(v, -5000, 5000))
    var caption: string
    if anchor:
      let label = if node.id in anchorLabels: anchorLabels[node.id] else: text(node.label, small, anchorWidth, Bold)
      caption = centered(label, x + ox.get(0), y + oy.get(-3),
        " class=\"pele-label\" font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\"")
    else:
      let label = text(node.label, small)
      let attrs = " class=\"pele-label\" font-size=\"" & jsString(small) & "\""
      let lift = LABEL_OFFSET + (if strategy != "": 10 else: 0)
      if ox.isSome or oy.isSome:
        caption = starting(label, x + ox.get(lift), y + oy.get(-lift), attrs)
      elif node.inPipeline:
        caption = centered(label, x, y + 2 * R + 4 + label.height / 2, attrs)
      else:
        # The label goes up and to the right unless a link leaves that way; then the next free corner.
        let busy = taken.getOrDefault(node.id, 0)
        let corner = if (busy and 1) == 0: 1 elif (busy and 2) == 0: 2 elif (busy and 4) == 0: 4
                     elif (busy and 8) == 0: 8 else: 1
        let right = corner == 1 or corner == 2
        let up = corner == 1 or corner == 4
        caption = starting(label, (if right: x + lift else: x - lift - label.width),
                           (if up: y - lift else: y + lift + small * 0.75), attrs)
    grow(x - 2 * R, y - 2 * R, x + 2 * R + 20, y + 2 * R)
    let kind = if anchor: "anchor" elif node.isPipelineParent: "pipeline-parent"
               elif node.inPipeline: "pipeline-component" else: "component"
    nodes.add "<g class=\"pele-node pele-wardley-" & kind & "\" data-id=\"" & escText(node.id) & "\">" & shape & caption & "</g>"

  var annotations = ""
  for annotation in m.annotations:
    let label = text(jsString(annotation.number), tiny, 4000, Bold)
    var marks = ""
    for coordinate in annotation.coordinates:
      let x = projectX(coordinate.x)
      let y = projectY(coordinate.y)
      let r = max(10.0, label.width / 2 + 4)
      grow(x - r, y - r, x + r, y + r)
      marks.add "<circle cx=\"" & num(x) & "\" cy=\"" & num(y) & "\" r=\"" & num(r) & "\" fill=\"var(--_bg)\" stroke=\"" &
        LINE & "\"/>" & labelSvg(label, x, y, " font-size=\"" & jsString(tiny) & "\" font-weight=\"var(--_hw)\"")
    annotations.add "<g class=\"pele-wardley-annotation\" data-id=\"" & escText(jsString(annotation.number)) & "\">" &
      marks & "</g>"
  var listed: seq[WardleyAnnotation]
  for a in m.annotations:
    if a.text != "": listed.add a
  listed.sort(proc (a, b: WardleyAnnotation): int = cmp(a.number - b.number, 0.0))
  if listed.len > 0:
    var lines: seq[Label]
    for a in listed:
      lines.add text(jsString(a.number) & ". " & a.text, small, (if tight: max(80.0, plotW - 20) else: 320.0))
    var width = 0.0
    var height = 0.0
    for line in lines:
      width = max(width, line.width)
      height += line.height
    width += 20
    height += 14
    # Without a position the list goes under the map, where it covers nothing.
    let box = m.annotationsBox
    let bx = if box.isSome: clamp(projectX(box.get.x), 0, max(0.0, plotW - width)) else: 0.0
    let by = if box.isSome: clamp(projectY(box.get.y), 0, max(0.0, plotH - height)) else: legendTop
    grow(bx, by, bx + width, by + height)
    var rows = ""
    var y = by + 7
    for line in lines:
      rows.add startLabel(line, bx + 10, y + line.lineHeight / 2 + small * 0.35, " font-size=\"" & jsString(small) & "\"")
      y += line.height
    annotations.add "<g class=\"pele-wardley-annotations\"><rect x=\"" & num(bx) & "\" y=\"" & num(by) & "\" width=\"" &
      num(width) & "\" height=\"" & num(height) & "\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
      rows & "</g>"

  var notes = ""
  for note in m.notes:
    notes.add starting(text(note.text, small, min(360.0, plotW * 0.6), Bold), projectX(note.x), projectY(note.y),
      " class=\"pele-wardley-note\" font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\"")

  # Accelerators point right, deaccelerators left.
  var forces = ""
  proc force(name: string, px, py: float, forward: bool) =
    let x = projectX(px)
    let y = projectY(py)
    let half = FORCE_HEIGHT / 2
    let tip = if forward: x + FORCE_WIDTH else: x
    let tail = if forward: x else: x + FORCE_WIDTH
    let neck = if forward: x + FORCE_WIDTH - FORCE_HEAD else: x + FORCE_HEAD
    let d = "M" & num(tail) & "," & num(y - half) & "H" & num(neck) & "V" & num(y - half - 8) & "L" & num(tip) & "," &
      num(y) & "L" & num(neck) & "," & num(y + half + 8) & "V" & num(y + half) & "H" & num(tail) & "Z"
    grow(x, y - half - 8, x + FORCE_WIDTH, y + half + 8)
    forces.add "<g class=\"pele-wardley-" & (if forward: "accelerator" else: "deaccelerator") & "\" data-id=\"" &
      escText(name) & "\">" & "<path d=\"" & d & "\" fill=\"var(--_s)\" stroke=\"" & LINE & "\"/>" &
      centered(text(name, tiny + 1, 160, Bold), x + FORCE_WIDTH / 2, y + half + 8 + 12,
               " font-size=\"" & jsString(tiny + 1) & "\" font-weight=\"var(--_hw)\"") &
      "</g>"
  for a in m.accelerators: force(a.name, a.x, a.y, true)
  for d in m.deaccelerators: force(d.name, d.x, d.y, false)

  let title = layoutLabel(model.title, false, measurer, size, (if tight: max(80.0, plotW) else: 4000.0), Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let left = min(minX, plotW / 2 - title.width / 2)
  let right = max(maxX, plotW / 2 + title.width / 2)
  let tx = pad - left
  let ty = pad + titleHeight - minY
  let totalWidth = ceil(right - left + 2 * pad)
  let totalHeight = ceil(maxY - minY + titleHeight + 2 * pad)
  let content =
    labelSvg(title, tx + plotW / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g transform=\"translate(" & num(tx) & "," & num(ty) & ")\">" &
    "<g class=\"pele-wardley-frame\" fill=\"none\">" & frame & "</g>" &
    stageLabels & axisLabels & pipelines &
    (if links != "": "<g class=\"pele-edges\" fill=\"none\">" & links & "</g>" else: "") &
    (if trends != "": "<g class=\"pele-wardley-trends\" fill=\"none\">" & trends & "</g>" else: "") &
    nodes & annotations & notes & forces & "</g>"
  Rendered(svg: svgDocument("wardley", totalWidth, totalHeight, size, options,
                            Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
           width: totalWidth, height: totalHeight, links: @[])

## port-of: src/diagrams/requirement/render.ts
## port-status: conformant
import std/[algorithm, options, tables]
from std/math import ceil
import ../../js
import ../../layout/[compound, layered]
import ../../preprocess
import ../../svg/[builder, edges, ink, root, theme, title]
import ../../text/[label, measurer]
import ../../types
import ../common/fit_width
import db, graph
import ../../jsregex

const
  NODE_SEP = 40.0
  EDGE_SEP = 16.0
  RANK_SEP = 56.0
  PAD_X = 14.0
  PAD_Y = 10.0
  ROW_GAP = 2.0
  COLUMN_GAP = 12.0
  MIN_WIDTH = 120.0
  NAME_WRAP = 280.0
  VALUE_WRAP = 240.0
  LOOP = 26.0
  CONTAINS_RADIUS = 6.0
  ARROW_LENGTH = 9.0
  ARROW_HALF = 4.5
  END_STEP = 28.0
  END_MARGIN = 14.0

type
  Row = object
    key: Label
    value: Label
    height: float

  NodeView = object
    node: GraphNode
    style: ResolvedStyle
    kind: Label
    name: Label
    rows: seq[Row]
    keyWidth: float
    headHeight: float
    w, h: float

# Adds bold or italic to a whole label after its markdown is read, since emphasis markers only
# toggle styles the label does not start with.
proc restyle(label: Label, bits: int, measurer: TextMeasurer): Label =
  if bits == 0 or label.lines.len == 0: return label
  result = label
  var width = 0.0
  var widths: seq[float]
  for li, line in label.lines:
    var total = 0.0
    for si, span in line:
      let style = span.style or bits
      let w = if span.hasIcon or span.math != nil: span.width else: measurer.width(span.text, label.size, style)
      total += w
      result.lines[li][si].style = style
      result.lines[li][si].width = w
    widths.add total
    if total > width: width = total
  result.widths = widths
  result.width = width

# Writes a measured label with its lines starting at x, the first line's box starting at top.
proc startText(label: Label, x, top: float, attrs: string): string =
  let shared = sharedStyle(label)
  var body = ""
  var math = ""
  for i in 0 ..< label.lines.len:
    let line = label.lines[i]
    let middle = top + lineMiddle(label, i)
    if hasMath(line):
      math.add labelSvg(labelLine(label, i), x + label.widths[i] / 2, middle, attrs)
      continue
    let y = middle + label.size * 0.35
    var first = true
    for span in line:
      if span.hasIcon or span.text == "": continue
      body.add "<tspan" & (if first: " x=\"" & num(x) & "\" y=\"" & num(y) & "\"" else: "") &
        spanStyle(span.style and not shared) & ">" & esc(span.text) & "</tspan>"
      first = false
  (if body == "": "" else: "<text" & textStyle(attrs, shared) & " text-anchor=\"start\" xml:space=\"preserve\">" &
     body & "</text>") & math

# The containment mark: a circled plus whose rim touches (x, y), where (dx, dy) points at the node.
proc containsMarker(x, y, dx, dy: float): string =
  const r = CONTAINS_RADIUS
  let cx = x - dx * r
  let cy = y - dy * r
  "<circle class=\"pele-marker\" cx=\"" & num(cx) & "\" cy=\"" & num(cy) & "\" r=\"" & num(r) & "\"/>" &
    "<path class=\"pele-marker\" d=\"M" & num(cx - dx * r) & "," & num(cy - dy * r) & "L" & num(cx + dx * r) & "," &
    num(cy + dy * r) & "M" & num(cx + dy * r) & "," & num(cy - dx * r) & "L" & num(cx - dy * r) & "," &
    num(cy + dx * r) & "\"/>"

# An open arrowhead with its tip at (x, y), pointing along (dx, dy).
proc arrowMarker(x, y, dx, dy: float): string =
  let bx = x - dx * ARROW_LENGTH
  let by = y - dy * ARROW_LENGTH
  "<path class=\"pele-marker\" d=\"M" & num(bx - dy * ARROW_HALF) & "," & num(by + dx * ARROW_HALF) & "L" & num(x) &
    "," & num(y) & "L" & num(bx + dy * ARROW_HALF) & "," & num(by - dx * ARROW_HALF) & "\" stroke-linejoin=\"round\"/>"

type End = object
  edge: int
  at: int
  toward: float

# The layout attaches every edge to the middle of a node's side. Ends that share a side are
# spread along it, in the order of where they head, so their markers do not sit on each other.
proc spreadEnds(cnodes: seq[CNode], cedges: seq[CEdge], views: seq[NodeView]) =
  var sides = initOrderedTable[int, seq[End]]()
  for e, edge in cedges:
    let route = edge.route
    if edge.src == edge.dst or route.len < 6: continue
    for at in [0, route.len - 3]:
      let node = if at == 0: edge.src else: edge.dst
      let c = cnodes[node]
      let dx = route[at] - c.x
      let dy = route[at + 1] - c.y
      let next = if at == 0: 3 else: at - 3
      var side: int
      if abs(abs(dy) - c.h / 2) < 0.5: side = if dy < 0: 0 else: 2
      elif abs(abs(dx) - c.w / 2) < 0.5: side = if dx < 0: 3 else: 1
      else: continue
      let key = node * 4 + side
      sides.mgetOrPut(key, @[]).add End(edge: e, at: at, toward: route[if side mod 2 == 0: next else: next + 1])
  for key, list in sides.mpairs:
    if list.len < 2: continue
    let node = key shr 2
    let vertical = key mod 2 == 1
    let span = (if vertical: views[node].h else: views[node].w) - 2 * END_MARGIN
    let step = max(0.0, min(END_STEP, span / float(list.len - 1)))
    list.sort(proc (a, b: End): int =
      if a.toward < b.toward: -1 elif a.toward > b.toward: 1 else: 0)
    for j in 0 ..< list.len:
      let offset = (float(j) - float(list.len - 1) / 2) * step
      if vertical: cedges[list[j].edge].route[list[j].at + 1] = cnodes[node].y + offset
      else: cedges[list[j].edge].route[list[j].at] = cnodes[node].x + offset

proc draw(model: RequirementDb, options: RenderOptions, turned: bool): Rendered

proc renderRequirement*(model: RequirementDb, config: Config, options: RenderOptions): Rendered =
  if not runsAcross(model.direction): return draw(model, options, false)
  turnToFit(options, proc (down: bool): Rendered = draw(model, options, down))

# `turned` draws a diagram that runs across as one that runs down.
proc draw(model: RequirementDb, options: RenderOptions, turned: bool): Rendered =
  let graph = buildRequirementGraph(model)
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  var index = initTable[string, int]()
  var views: seq[NodeView]
  var cnodes: seq[CNode]
  for node in graph.nodes:
    let style = resolveStyle(node.cssStyles)
    let base = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let nameSize = if style.fontSize != 0: style.fontSize else: size
    let bodySize = if style.fontSize != 0: style.fontSize else: small
    let requirement = node.requirement
    let element = node.element
    let kind = restyle(layoutLabel("«" & (if requirement != nil: requirement.kind else: "Element") & "»", false,
                                   measurer, bodySize, 4000), base, measurer)
    let name = restyle(layoutLabel(node.id, true, measurer, nameSize, NAME_WRAP), base or Bold, measurer)
    let fields =
      if requirement != nil:
        @[("ID", requirement.requirementId), ("Text", requirement.text), ("Risk", requirement.risk),
          ("Verification", requirement.verifyMethod)]
      else:
        @[("Type", element.kind), ("Doc Ref", element.docRef)]
    var rows: seq[Row]
    var keyWidth = 0.0
    var valueWidth = 0.0
    var bodyHeight = 0.0
    for (label, text) in fields:
      if text == "": continue
      let key = restyle(layoutLabel(label, false, measurer, bodySize, 4000), base, measurer)
      let value = restyle(layoutLabel(text, true, measurer, bodySize, VALUE_WRAP), base, measurer)
      let height = max(key.height, value.height)
      rows.add Row(key: key, value: value, height: height)
      keyWidth = max(keyWidth, key.width)
      valueWidth = max(valueWidth, value.width)
      bodyHeight += height + ROW_GAP
    if rows.len > 0: bodyHeight += 2 * PAD_Y - ROW_GAP
    let headHeight = 2 * PAD_Y + kind.height + name.height
    let w = max(max(MIN_WIDTH, max(kind.width, name.width) + 2 * PAD_X),
                if rows.len > 0: keyWidth + COLUMN_GAP + valueWidth + 2 * PAD_X else: 0)
    # A requirement and an element may share a name; relationships then go to the requirement.
    if not index.hasKey(node.id): index[node.id] = views.len
    let c = cnode(w, headHeight + bodyHeight)
    c.seq = float(views.len)
    views.add NodeView(node: node, style: style, kind: kind, name: name, rows: rows, keyWidth: keyWidth,
                       headHeight: headHeight, w: w, h: headHeight + bodyHeight)
    cnodes.add c

  let rootDir = if turned: "TB" else: direction(graph.direction)
  let sideways = rootDir == "LR" or rootDir == "RL"
  var cedges: seq[CEdge]
  var edgeLabels: seq[Label]
  var drawn: seq[GraphEdge]
  for edge in graph.edges:
    let src = if not edge.hasStart: -1 else: index.getOrDefault(edge.start, -1)
    let dst = if not edge.hasStop: -1 else: index.getOrDefault(edge.stop, -1)
    if src == -1 or dst == -1: continue
    let label = layoutLabel("«" & edge.kind & "»", false, measurer, small, 4000)
    if src == dst:
      # A self-loop sits beside the node, across the flow, and the node's box grows to hold it.
      if sideways: cnodes[src].h += 2 * (LOOP + label.height + 8)
      else: cnodes[src].w += 2 * (LOOP + label.width + 12)
    drawn.add edge
    edgeLabels.add label
    cedges.add CEdge(src: src, dst: dst, minlen: 1, labelW: label.width + 12, labelH: label.height + 4,
                     route: @[], labelX: 0, labelY: 0)

  let layout = compoundLayout(cnodes, cedges, rootDir, LayeredOptions(
    nodeSep: NODE_SEP,
    edgeSep: EDGE_SEP,
    rankSep: RANK_SEP,
    portSep: 20,
  ))

  spreadEnds(cnodes, cedges, views)

  let title = titleLabel(model.title, measurer, size, 4000)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let inner = max(layout.width, title.width)
  let ox = pad + (inner - layout.width) / 2
  let oy = pad + titleHeight
  let width = ceil(inner + 2 * pad)
  let height = ceil(layout.height + titleHeight + 2 * pad)

  var nodesOut = ""
  for i in 0 ..< views.len:
    let view = views[i]
    let w = view.w
    let h = view.h
    let style = view.style
    let color = inkFill(style.shape, style.text)
    let muted = if color != "": color else: " fill=\"var(--_m)\""
    let left = -w / 2
    let top = -h / 2
    var body =
      "<rect x=\"" & num(left) & "\" y=\"" & num(top) & "\" width=\"" & num(w) & "\" height=\"" & num(h) &
        "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & rounded(style.shape) & "/>" &
      labelSvg(view.kind, 0, top + PAD_Y + view.kind.height / 2,
               " class=\"pele-stereotype\" font-size=\"" & jsString(view.kind.size) & "\"" & muted & style.text) &
      labelSvg(view.name, 0, top + PAD_Y + view.kind.height + view.name.height / 2,
               " class=\"pele-label\" font-size=\"" & jsString(view.name.size) & "\" font-weight=\"var(--_hw)\"" &
                 color & style.text)
    if view.rows.len > 0:
      let divider = top + view.headHeight
      body.add "<path class=\"pele-divider\" d=\"M" & num(left) & "," & num(divider) & "H" & num(-left) &
        "\" stroke=\"var(--_b)\"" & style.line & "/>"
      var y = divider + PAD_Y
      var rows = ""
      for row in view.rows:
        rows.add startText(row.key, left + PAD_X, y, " class=\"pele-field\"" & muted & style.text) &
          startText(row.value, left + PAD_X + view.keyWidth + COLUMN_GAP, y, " class=\"pele-value\"" & color &
                    style.text)
        y += row.height + ROW_GAP
      body.add "<g class=\"pele-fields\" font-size=\"" & jsString(view.rows[0].key.size) & "\">" & rows & "</g>"
    nodesOut.add "<g class=\"pele-node " & (if view.node.requirement != nil: "pele-requirement" else: "pele-element") &
      classNames(view.node.cssClasses.replace(jsre"/^default\s?/", "")) & "\" data-id=\"" & escText(view.node.id) &
      "\" transform=\"translate(" & num(cnodes[i].x + ox) & "," & num(cnodes[i].y + oy) & ")\">" & body & "</g>"

  var edgesOut = ""
  var labelsOut = ""
  var loopSeen = initTable[int, int]()
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    let startTrim = if edge.contains: 2 * CONTAINS_RADIUS else: 0
    var path: EdgePath
    var labelX = ce.labelX + ox
    var labelY = ce.labelY + oy
    if ce.src == ce.dst:
      let view = views[ce.src]
      let cx = cnodes[ce.src].x + ox
      let cy = cnodes[ce.src].y + oy
      let k = loopSeen.getOrDefault(ce.src, 0)
      loopSeen[ce.src] = k + 1
      let half = (if sideways: view.w else: view.h) / 2
      let spread = min(half - 4, 12 + float(k) * 6)
      let reach = LOOP + float(k) * 8
      # Local frame: `out` points away from the node, `along` runs along its side.
      proc at(output, along: float): string =
        if sideways: num(cx + along) & "," & num(cy + view.h / 2 + output)
        else: num(cx + view.w / 2 + output) & "," & num(cy + along)
      # A cubic whose control points are this far out peaks at `reach`.
      let pull = reach / 0.75
      path = EdgePath(
        d: "M" & at(startTrim, -spread) & "C" & at(pull, -spread) & " " & at(pull, spread) & " " & at(0, spread),
        sx: if sideways: cx - spread else: cx + view.w / 2,
        sy: if sideways: cy + view.h / 2 else: cy - spread,
        sdx: if sideways: 0 else: -1,
        sdy: if sideways: -1 else: 0,
        ex: if sideways: cx + spread else: cx + view.w / 2,
        ey: if sideways: cy + view.h / 2 else: cy + spread,
        edx: if sideways: 0 else: -1,
        edy: if sideways: -1 else: 0,
      )
      if sideways:
        labelX = cx
        labelY = cy + view.h / 2 + reach + 4 + ce.labelH / 2
      else:
        labelX = cx + view.w / 2 + reach + 4 + ce.labelW / 2
        labelY = cy
    else:
      var route = ce.route
      var k = 0
      while k < route.len:
        route[k] += ox
        route[k + 1] += oy
        k += 3
      path = routePath(route, "", startTrim, 0)
    edgesOut.add "<g class=\"pele-edge pele-relationship-" & (if edge.contains: "contains" else: "arrow") &
      "\" data-id=\"" & escText(edge.id) & "\">" &
      "<path d=\"" & path.d & "\"" & (if edge.contains: "" else: " stroke-dasharray=\"5 4\"") & "/>" &
      (if edge.contains: containsMarker(path.sx, path.sy, path.sdx, path.sdy)
       else: arrowMarker(path.ex, path.ey, path.edx, path.edy)) &
      "</g>"
    labelsOut.add edgeLabelSvg(edge.id, label, labelX, labelY, "")

  let svg = svgDocument(
    "requirement",
    width,
    height,
    size,
    options,
    Accessible(accTitle: model.accTitle, accDescr: model.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" &
        edgesOut & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\" fill=\"var(--_m)\">" &
        labelsOut & "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & "</g>"
  )
  Rendered(svg: svg, width: width, height: height)

## port-of: src/diagrams/er/render.ts
## port-status: draft
import std/[algorithm, options, strutils, tables]
from std/math import ceil
import ../../js
import ../../jsmath
import ../../layout/[compound, layered]
import ../../preprocess
import ../../svg/[builder, cluster, edges, ink, root, theme, title]
import ../../text/[entities, icons, label, measurer]
import ../../types
import ../../util/[url, yaml]
import ../common/[fit_width, generics]
import db, graph, markers
import types as erTypes

const
  NODE_SEP = 48.0
  EDGE_SEP = 20.0
  RANK_SEP = 64.0
  GROUP_PAD = 20.0
  LOOP = 28.0
  LOOP_BAND = 38.0
  MIN_WIDTH = 96.0
  BOX_PAD_X = 18.0
  BOX_PAD_Y = 12.0
  HEAD_PAD_Y = 9.0
  CELL_PAD_X = 12.0
  CELL_GAP = 16.0
  ROW_PAD = 9.0
  COMMENT_WRAP = 260.0
  NO_WRAP = 1e6
  PORT_GAP = 18.0
  PORT_MARGIN = 14.0
  BOX_ATTRS = " fill=\"var(--_s)\" stroke=\"var(--_b)\""

proc numberOption(config: Config, key: string, fallback: float): float =
  let value = config["er"][key]
  if value != nil and value.kind == yNumber and value.n > 0: min(value.n, 2000.0) else: fallback

type
  Cells = array[4, Label]
    ## Type, name, keys, comment.

  Row = object
    cells: Cells
    h: float

  NodeView = ref object
    node: ErGraphNode
    style: ResolvedStyle
    label: Label
    w, h: float
    headH: float
    rows: seq[Row]
    cols: seq[float]
      ## Left edge of each column, measured from the left edge of the box.
    rowSize: float
    keySize: float
    mono: int
    below: bool
      ## Whether self-relationships loop out of the bottom side rather than the right.

  SelfLoop = ref object
    ## A relationship from an entity to itself, with the stretch of the side it loops out of.
    label: Label
    band: float
    at: float

func stripDefault(s: string): string =
  ## s.replace(/^default\s?/, '')
  if not s.startsWith("default"): return s
  if isJsSpaceAt(s, 7): s.substr(7 + spaceLenAt(s, 7)) else: s.substr(7)

func hasInternalLink(s: string): bool =
  ## / internal-link(?: |$)/.test(s)
  var at = s.find(" internal-link")
  while at >= 0:
    let e = at + " internal-link".len
    if e == s.len or s[e] == ' ': return true
    at = s.find(" internal-link", at + 1)
  false

func setsFontFamily(text: string): bool =
  ## /[";]font-family:/.test(text)
  var at = text.find("font-family:")
  while at != -1:
    if at > 0 and text[at - 1] in {'"', ';'}: return true
    at = text.find("font-family:", at + 1)
  false

# Writes a measured label starting at x, with the baseline of its first line at y.
proc textLeft(label: Label, x, y: float, attrs: string, icons: IconResolver, mono = 0): string =
  let lines = label.lines
  if lines.len == 0: return ""
  if lines.len == 1 and lines[0].len == 1:
    let only = lines[0][0]
    # The short form collapses repeated spaces in monospace text.
    if not only.hasIcon and only.math == nil and only.style == mono and not (mono != 0 and "  " in only.text):
      return "<text" & textStyle(attrs, mono) & " x=\"" & num(x) & "\" y=\"" & num(y) & "\">" & esc(only.text) &
        "</text>"
  let shared = sharedStyle(label)
  let shift = label.size * 0.35
  let top = y - shift - label.lineHeight / 2
  var body = ""
  var extra = ""
  for i in 0 ..< lines.len:
    let line = lines[i]
    let middle = top + lineMiddle(label, i)
    if hasMath(line):
      extra.add labelSvg(labelLine(label, i), x + label.widths[i] / 2, middle, attrs, icons)
      continue
    let y = middle + shift
    var hasIcon = false
    for span in line:
      if span.hasIcon: hasIcon = true
    var sx = x
    var placed = false
    for span in line:
      if span.hasIcon:
        let side = label.size * 1.1
        extra.add "<svg class=\"pele-icon\" data-icon=\"" & escText(span.icon) & "\" x=\"" & num(sx) & "\" y=\"" &
          num(y - label.size * 0.35 - side / 2) & "\" width=\"" & num(side) & "\" height=\"" & num(side) &
          "\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
          (if icons != nil: icons(span.icon) else: "") & "</svg>"
      elif span.text != "":
        let pos = if hasIcon or not placed: " x=\"" & num(sx) & "\" y=\"" & num(y) & "\"" else: ""
        body.add "<tspan" & pos & spanStyle(span.style and not shared) & ">" & esc(span.text) & "</tspan>"
        placed = true
      sx += span.width
  "<text" & textStyle(attrs, shared) & " xml:space=\"preserve\">" & body & "</text>" & extra

# Mermaid reads `~` pairs as angle brackets. They are written as entities so the label parser
# does not take `<int>` for a tag.
func cellText(raw: string): string =
  let converted = parseGenericTypes(raw)
  if converted == raw: raw else: converted.replace("<", "&lt;").replace(">", "&gt;")

proc draw(db: ErDb, config: Config, options: RenderOptions, turned: bool): Rendered

proc renderEr*(db: ErDb, config: Config, options: RenderOptions): Rendered =
  if not runsAcross(db.direction): return draw(db, config, options, false)
  turnToFit(options, proc (down: bool): Rendered = draw(db, config, options, down))

proc straighten(route: seq[float]): seq[float] =
  var output = route[0 ..< min(3, route.len)]
  var k = 3
  while k < route.len:
    let prev = output.len - 3
    let flat0 = k + 3 < route.len and abs(output[prev] - route[k]) < 0.01 and abs(route[k] - route[k + 3]) < 0.01
    let flat1 = k + 3 < route.len and abs(output[prev + 1] - route[k + 1]) < 0.01 and
      abs(route[k + 1] - route[k + 4]) < 0.01
    if flat0 or flat1:
      k += 3
      continue
    output.add route[k]
    output.add route[k + 1]
    output.add route[k + 2]
    k += 3
  output

type End = object
  edge: int
  at: int
  toward: float

# The layout brings every edge that ends on one side of a box to the middle of that side, where
# their markers would cover each other. This spaces them along the side, in the order they fan out.
proc spreadEnds(cedges: seq[CEdge], cnodes: seq[CNode], views: seq[NodeView]) =
  var sides = initOrderedTable[int, seq[End]]()
  proc add(node, edge, at, next: int) =
    let c = cnodes[node]
    let route = cedges[edge].route
    let dx = route[at] - c.x
    let dy = route[at + 1] - c.y
    var side: int
    if abs(abs(dy) - c.h / 2) < 0.5: side = if dy < 0: 0 else: 2
    elif abs(abs(dx) - c.w / 2) < 0.5: side = if dx < 0: 3 else: 1
    else: return
    let key = node * 4 + side
    sides.mgetOrPut(key, @[]).add End(edge: edge, at: at, toward: route[next + (if (side and 1) != 0: 1 else: 0)])
  for k, e in cedges:
    let last = e.route.len - 3
    if e.src == e.dst or last < 3: continue
    add(e.src, k, 0, 3)
    add(e.dst, k, last, last - 3)
  for key, ends in sides.mpairs:
    if ends.len < 2: continue
    let node = key shr 2
    let vertical = (key and 1) == 1
    let length =
      if cnodes[node].isGroup: (if vertical: cnodes[node].h else: cnodes[node].w)
      else: (if vertical: views[node].h else: views[node].w)
    let step = max(min(PORT_GAP, (length - 2 * PORT_MARGIN) / float(ends.len - 1)), 0)
    let center = if vertical: cnodes[node].y else: cnodes[node].x
    ends.sort(proc (a, b: End): int =
      if a.toward < b.toward: -1 elif a.toward > b.toward: 1 else: 0)
    for i in 0 ..< ends.len:
      cedges[ends[i].edge].route[ends[i].at + (if vertical: 1 else: 0)] =
        center + (float(i) - float(ends.len - 1) / 2) * step

# An entity with a self-relationship is laid out larger than it is drawn; this moves a route end
# from the side of that larger box onto the entity's own side.
proc inset(route: var seq[float], at: int, view: NodeView, c: CNode) =
  if c.isGroup: return
  let dx = route[at] - c.x
  let dy = route[at + 1] - c.y
  proc sign(x: float): float = (if x > 0: 1.0 elif x < 0: -1.0 else: x)
  if c.w != view.w and abs(abs(dx) - c.w / 2) < 0.5: route[at] -= (sign(dx) * (c.w - view.w)) / 2
  if c.h != view.h and abs(abs(dy) - c.h / 2) < 0.5: route[at + 1] -= (sign(dy) * (c.h - view.h)) / 2

# `turned` draws a diagram that runs across as one that runs down.
proc draw(db: ErDb, config: Config, options: RenderOptions, turned: bool): Rendered =
  let graph = buildErGraph(db)
  let monospaced = "attributes" in options.monospace
  let size = options.fontSize.get(16)
  let smallSize = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons

  var index = initTable[string, int]()
  var views: seq[NodeView]
  var cnodes: seq[CNode]
  for i, node in graph.nodes: index[node.id] = i

  var cedges: seq[CEdge]
  var edgeLabels: seq[Label]
  var drawn: seq[ErGraphEdge]
  var loops = initOrderedTable[int, seq[SelfLoop]]()
  var loopOf: seq[SelfLoop]
  for edge in graph.edges:
    let src = index.getOrDefault(edge.start, -1)
    let dst = index.getOrDefault(edge.stop, -1)
    if src == -1 or dst == -1: continue
    let label = layoutLabel(edge.label, true, measurer, smallSize, 200)
    var loop: SelfLoop = nil
    if src == dst:
      loop = SelfLoop(label: label)
      loops.mgetOrPut(src, @[]).add loop
    loopOf.add loop
    drawn.add edge
    edgeLabels.add label
    cedges.add CEdge(src: src, dst: dst, minlen: 1,
                     labelW: if label.width > 0: label.width + 12 else: 0,
                     labelH: if label.height > 0: label.height + 4 else: 0,
                     route: @[], labelX: 0, labelY: 0)

  # The direction of the level a node is laid out in: its nearest subgraph that sets one, or the diagram's.
  proc horizontal(i: int): bool =
    var at = i
    # Subgraphs can name each other as members, so the walk up is bounded.
    for steps in 0 ..< graph.nodes.len:
      let parent = graph.nodes[at].parentId
      let up = if parent.isNone: -1 else: index.getOrDefault(parent.get, -1)
      if up == -1: break
      let dir = graph.nodes[up].dir
      if dir != "": return dir == "LR" or dir == "RL"
      at = up
    db.direction == "LR" or db.direction == "RL"

  for i in 0 ..< graph.nodes.len:
    let node = graph.nodes[i]
    let style = resolveStyle(
      if node.cssStyles.len > 0: node.cssCompiledStyles & node.cssStyles else: node.cssCompiledStyles)
    let base = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let mono = if monospaced and not setsFontFamily(style.text): Mono else: 0
    let nameSize = if style.fontSize != 0: style.fontSize else: size
    let rowSize = if style.fontSize != 0: style.fontSize else: smallSize
    let keySize = if style.fontSize != 0: style.fontSize else: jsRound(size * 0.75)
    let label =
      if node.isGroup: layoutLabel(node.label, true, measurer, nameSize, 4000, base)
      else: layoutLabel(if node.alias != "": node.alias else: node.label, true, measurer, nameSize, 240, base)
    let own = loops.getOrDefault(i, @[])
    # Loops leave by a side the layout keeps free of other edges: the right when ranks run down,
    # the bottom when they run across.
    let below = own.len > 0 and not node.isGroup and horizontal(i)
    let view = NodeView(node: node, style: style, label: label, rowSize: rowSize, keySize: keySize, mono: mono,
                        below: below)
    var reach = 0.0
    var bands = 0.0
    for loop in own:
      loop.band = max(LOOP_BAND, if below: loop.label.width + 12 else: loop.label.height + 6)
      bands += loop.band
      reach = max(reach, if below: loop.label.height else: loop.label.width)
    let minW = max(MIN_WIDTH, if below: bands + 8 else: 0.0)
    var c: CNode
    if node.isGroup:
      c = cnode(0, 0)
      c.isGroup = true
      c.dir = if node.dir != "": direction(node.dir) else: ""
      c.padX = GROUP_PAD
      c.padTop = if view.label.height > 0: view.label.height + 16 else: GROUP_PAD
      c.padBottom = GROUP_PAD
      c.minW = max(view.label.width + 2 * GROUP_PAD - 12, MIN_WIDTH)
    else:
      let nameH = max(label.height, jsRound(nameSize * 1.5))
      if node.attributes.len == 0:
        view.w = max(label.width + 2 * BOX_PAD_X, minW)
        view.h = max(nameH + 2 * BOX_PAD_Y, if below: 0.0 else: bands + 8)
      else:
        let rowLine = jsRound(rowSize * 1.5)
        var widths = [0.0, 0.0, 0.0, 0.0]
        for attribute in node.attributes:
          let cells: Cells = [
            layoutLabel(cellText(attribute.kind), true, measurer, rowSize, NO_WRAP, base or mono),
            layoutLabel(cellText(attribute.name), true, measurer, rowSize, NO_WRAP, base or mono),
            layoutLabel(attribute.keys.join(", "), false, measurer, keySize, NO_WRAP, base or mono),
            layoutLabel(cellText(attribute.comment), true, measurer, rowSize, COMMENT_WRAP, base),
          ]
          var h = rowLine
          for k in 0 ..< 4:
            if cells[k].width > widths[k]: widths[k] = cells[k].width
            if cells[k].height > h: h = cells[k].height
          view.rows.add Row(cells: cells, h: h + ROW_PAD)
          view.h += h + ROW_PAD
        var columns = 0
        var inner = 0.0
        for w in widths:
          if w == 0: continue
          inner += w + (if columns > 0: CELL_GAP else: 0)
          inc columns
        view.w = max(max(inner + 2 * CELL_PAD_X, label.width + 2 * BOX_PAD_X), minW)
        # A box wider than its table shares the spare width between the columns.
        let spare = if columns > 0: (view.w - inner - 2 * CELL_PAD_X) / float(columns) else: 0.0
        var x = CELL_PAD_X
        for w in widths:
          view.cols.add x
          if w > 0: x += w + spare + CELL_GAP
        view.headH = nameH + 2 * HEAD_PAD_Y
        view.h += view.headH
      # The layout keeps a node centered in its box, so room for loops is added on both sides.
      let room = if own.len > 0: 2 * (MARKER_LENGTH + LOOP * 0.75 + 10 + reach) else: 0.0
      c = if below: cnode(view.w, view.h + room) else: cnode(view.w + room, view.h)
    c.seq = float(views.len)
    views.add view
    cnodes.add c
  for i, node in graph.nodes:
    cnodes[i].parent = if node.parentId.isSome: index.getOrDefault(node.parentId.get, -1) else: -1

  let layout = compoundLayout(cnodes, cedges, if turned: "TB" else: direction(db.direction), LayeredOptions(
    nodeSep: numberOption(config, "nodeSpacing", NODE_SEP),
    edgeSep: EDGE_SEP,
    rankSep: numberOption(config, "rankSpacing", RANK_SEP),
    portSep: 24,
  ))

  spreadEnds(cedges, cnodes, views)

  # A subgraph gets its size from the layout, so its loops hang outside it and may widen the diagram.
  var layoutWidth = layout.width
  for i, own in loops:
    let c = cnodes[i]
    if not c.isGroup: continue
    var reach = 0.0
    for loop in own: reach = max(reach, loop.label.width)
    layoutWidth = max(layoutWidth, c.x + c.w / 2 + MARKER_LENGTH + LOOP * 0.75 + 10 + reach)

  let title = titleLabel(db.title, measurer, size, 4000)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let inner = max(layoutWidth, title.width)
  let ox = pad + (inner - layoutWidth) / 2
  let oy = pad + titleHeight
  shiftLayout(cnodes, cedges, ox, oy)
  let width = ceil(inner + 2 * pad)
  let height = ceil(layout.height + titleHeight + 2 * pad)
  var links: seq[LinkInfo]

  var crossings: Crossings = initTable[int, seq[float]]()
  var anyGroup = false
  for c in cnodes:
    if c.isGroup: anyGroup = true
  if anyGroup:
    for e in cedges: markCrossings(crossings, e.route)

  var clusters = ""
  var fills: seq[Fill]
  var nodesOut = ""
  for i in 0 ..< views.len:
    let view = views[i]
    let c = cnodes[i]
    let node = view.node
    let classes = classNames(stripDefault(node.cssClasses))
    if c.isGroup:
      view.w = c.w
      view.h = c.h
      let x = c.x - c.w / 2
      let y = c.y - c.h / 2
      let titleX = clusterTitleX(c, view.label.width, crossings, GROUP_PAD)
      if paints(view.style.shape): fills.add Fill(box: [x, y, x + c.w, y + c.h], shape: view.style.shape)
      clusters.add "<g class=\"pele-cluster" & classes & "\" data-id=\"" & escText(node.id) & "\">" &
        "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(c.w) & "\" height=\"" & num(c.h) &
        "\" fill=\"var(--_a)\"" & (if setsFill(view.style.shape): "" else: " fill-opacity=\"0.5\"") &
        " stroke=\"var(--_b)\"" & rounded(view.style.shape) & "/>" &
        labelSvg(view.label, titleX, y + 8 + view.label.height / 2,
                 " class=\"pele-cluster-label\"" & inkFill(view.style.shape, view.style.text, "var(--_m)") &
                   view.style.text, icons) &
        "</g>"
      continue

    let w = view.w
    let h = view.h
    let x0 = -w / 2
    let y0 = -h / 2
    let text = view.style.text
    let color = inkFill(view.style.shape, view.style.text)
    let muted = if color != "": color else: " fill=\"var(--_m)\""
    let shape = "x=\"" & num(x0) & "\" y=\"" & num(y0) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\""
    var name = labelSvg(view.label, 0, if view.rows.len > 0: y0 + view.headH / 2 else: 0,
                        " class=\"pele-label\"" & color & text, icons)
    let display = decodeEntities(if node.alias != "": node.alias else: node.label)
    if hasInternalLink(classes & " ") and name != "" and options.links != some(false):
      # The name ends up in an href, so it gets the same check as a URL.
      let safe = internalLink(display, options)
      let target = esc(display)
      name = "<a class=\"internal-link\"" & (if safe: " href=\"" & target & "\"" & relAttr(options) else: "") &
        " data-href=\"" & target & "\">" & name & "</a>"
      links.add LinkInfo(id: node.label, href: display, internal: true)

    var body: string
    if view.rows.len == 0:
      body = "<rect " & shape & rounded(BOX_ATTRS & view.style.shape) & "/>" & name
    else:
      let rowLine = jsRound(view.rowSize * 1.5)
      let lineColor = if view.style.stroke != "": esc(view.style.stroke) else: "var(--_b)"
      var stripes = ""
      var cells = ""
      var y = y0 + view.headH
      for r in 0 ..< view.rows.len:
        let row = view.rows[r]
        if r mod 2 == 0:
          let span = "x=\"" & num(x0) & "\" width=\"" & num(w) & "\""
          if r == view.rows.len - 1:
            # The last row follows the box's rounded bottom corners: a rounded rect, squared off on top.
            stripes.add "<rect " & span & " y=\"" & num(y) & "\" height=\"" & num(row.h) & "\"" & ROUNDED & "/>" &
              "<rect " & span & " y=\"" & num(y) & "\" height=\"" & num(row.h / 2) & "\"/>"
          else:
            stripes.add "<rect " & span & " y=\"" & num(y) & "\" height=\"" & num(row.h) & "\"/>"
        let baseline = y + ROW_PAD / 2 + rowLine / 2 + view.rowSize * 0.35
        cells.add textLeft(row.cells[0], x0 + view.cols[0], baseline, " class=\"pele-er-type\"" & muted & text, icons,
                           view.mono) &
          textLeft(row.cells[1], x0 + view.cols[1], baseline, " class=\"pele-er-name\"" & color & text, icons,
                   view.mono) &
          textLeft(row.cells[2], x0 + view.cols[2], baseline, " class=\"pele-er-keys\" font-size=\"" &
                   jsString(view.keySize) & "\"" & muted & text, icons, view.mono) &
          textLeft(row.cells[3], x0 + view.cols[3], baseline, " class=\"pele-er-comment\"" & muted & text, icons)
        y += row.h
      let dividerY = num(y0 + view.headH)
      # Keep row shading light on light fills and dark on dark fills to preserve text contrast.
      let (hasTone, tone) = ink(view.style.shape)
      let shade =
        if hasTone and tone == ON_LIGHT: ON_DARK
        elif hasTone and tone == ON_DARK: ON_LIGHT
        else: "var(--_bg)"
      body =
        "<rect " & shape & rounded(BOX_ATTRS & view.style.shape) & "/>" &
        # Over a fill the diagram chose, the shading is a tint of that fill. The opacity is on the
        # group because the two parts of the last row overlap.
        "<g class=\"pele-er-stripes\" fill=\"" & shade & "\"" &
          (if "fill:" in view.style.shape: " opacity=\"0.6\"" else: "") & ">" & stripes & "</g>" &
        "<path class=\"pele-er-divider\" d=\"M" & num(x0) & "," & dividerY & "H" & num(x0 + w) & "\" stroke=\"" &
          lineColor & "\"/>" &
        "<rect " & shape & " fill=\"none\" stroke=\"var(--_b)\"" & rounded(view.style.line) & "/>" &
        name &
        "<g class=\"pele-er-attributes\" font-size=\"" & jsString(view.rowSize) & "\">" & cells & "</g>"
    nodesOut.add "<g class=\"pele-node pele-entity" & classes & "\" data-id=\"" & escText(node.label) &
      "\" transform=\"translate(" & num(c.x) & "," & num(c.y) & ")\">" & body & "</g>"

  # Self-relationships share the side they loop out of, squeezed together if it is too short for them.
  for i, own in loops:
    let view = views[i]
    var total = 0.0
    for loop in own: total += loop.band
    let scale = min(1.0, max((if view.below: view.w else: view.h) - 8, 0) / total)
    var at = (-total * scale) / 2
    for loop in own:
      loop.band *= scale
      loop.at = at + loop.band / 2
      at += loop.band

  var edgesOut = ""
  var casings = ""
  var labelsOut = ""
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    var d, start, stop: string
    let loop = loopOf[i]
    if loop != nil:
      let c = cnodes[ce.src]
      let view = views[ce.src]
      let spread = max(min(loop.band / 2 - 6, 13), 1)
      let far = MARKER_LENGTH + LOOP * 0.75 + 6
      if view.below:
        let x = c.x + loop.at
        let y = c.y + view.h / 2
        let turn = num(y + MARKER_LENGTH)
        let output = num(y + MARKER_LENGTH + LOOP)
        d = "M" & num(x - spread) & "," & num(y) & "V" & turn & "C" & num(x - spread) & "," & output & " " &
          num(x + spread) & "," & output & " " & num(x + spread) & "," & turn & "V" & num(y)
        start = erMarker(edge.arrowTypeStart, x - spread, y, 0, -1)
        stop = erMarker(edge.arrowTypeEnd, x + spread, y, 0, -1)
        ce.labelX = x
        ce.labelY = y + far + label.height / 2
      else:
        let x = c.x + view.w / 2
        let y = c.y + loop.at
        let turn = num(x + MARKER_LENGTH)
        let output = num(x + MARKER_LENGTH + LOOP)
        d = "M" & num(x) & "," & num(y - spread) & "H" & turn & "C" & output & "," & num(y - spread) & " " &
          output & "," & num(y + spread) & " " & turn & "," & num(y + spread) & "H" & num(x)
        start = erMarker(edge.arrowTypeStart, x, y - spread, -1, 0)
        stop = erMarker(edge.arrowTypeEnd, x, y + spread, -1, 0)
        ce.labelX = x + far + label.width / 2
        ce.labelY = y
    else:
      var route = straighten(ce.route)
      if route.len < 6: continue
      inset(route, 0, views[ce.src], cnodes[ce.src])
      inset(route, route.len - 3, views[ce.dst], cnodes[ce.dst])
      # A curve stops short of each box so that the marker sits on a straight run of line.
      let dx = abs(route[route.len - 3] - route[0])
      let dy = abs(route[route.len - 2] - route[1])
      let direct = route.len == 6 and (dx < 0.01 or dy < 0.01 or hypot(dx, dy) <= 3 * MARKER_LENGTH)
      let stub = if direct: 0.0 else: MARKER_LENGTH
      let path = routePath(route, "", stub, stub)
      d = if stub > 0: "M" & num(path.sx) & "," & num(path.sy) & "L" & path.d.substr(1) & "L" & num(path.ex) & "," &
            num(path.ey)
          else: path.d
      start = erMarker(edge.arrowTypeStart, path.sx, path.sy, path.sdx, path.sdy)
      stop = erMarker(edge.arrowTypeEnd, path.ex, path.ey, path.edx, path.edy)
    let under = fillUnder(d, [], fills)
    let onFill = not under.none and not under.across
    # `over`: the fill's ink, '' for a casing, or undefined off fills.
    let over = if onFill: edgeInk(under.fill) else: ""
    let overSet = not under.none
    if overSet and over == "": casings.add casing(d, start & stop)
    if onFill and over != "":
      start = hollowOn(start, under.fill)
      stop = hollowOn(stop, under.fill)
    let dashed = edge.dashed
    edgesOut.add "<g class=\"pele-edge pele-er-" & (if dashed: "non-identifying" else: "identifying") &
      "\" data-id=\"" & escText(edge.id) & "\"" & (if over != "": " stroke=\"" & over & "\"" else: "") & ">" &
      "<path d=\"" & d & "\"" & (if dashed: " stroke-dasharray=\"4 3\"" else: "") & "/>" &
      start & stop & "</g>"
    if label.width > 0:
      labelsOut.add edgeLabelSvg(edge.id, label, ce.labelX, ce.labelY, "", icons)

  let svg = svgDocument(
    "er",
    width,
    height,
    size,
    options,
    Accessible(accTitle: db.accTitle, accDescr: db.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      casingsSvg(casings) &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" &
        edgesOut & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(smallSize) & "\">" & labelsOut &
        "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & "</g>"
  )
  Rendered(svg: svg, width: width, height: height, links: links)

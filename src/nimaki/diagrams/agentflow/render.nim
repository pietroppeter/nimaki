## port-of: src/diagrams/agentflow/render.ts
## port-status: conformant
import std/[options, strutils, tables]
from std/math import ceil
import ../../js
import ../../layout/[compound, layered]
import ../../preprocess
import ../../svg/[builder, cluster, edges, ink, root, shapes, theme]
import ../../text/[entities, label, measurer]
import ../../types as nimaki_types
import ../../util/[url, yaml]
import ../common/fit_width
import ../flowchart/shapes as flowShapes
import colorSlots, db, graph, types

const
  PALETTE* = 8  ## the number of series tokens, which is the palette Mermaid's slot rules apply to
  NODE_SEP = 40.0
  EDGE_SEP = 16.0
  RANK_SEP = 48.0
  GROUP_PAD = 20.0
  LOOP = 26.0
  DOTS = 14.0
  COLLAPSED = "collapsed"

proc flowEnd(dir: Dir): int =
  ## The side a flow runs toward, with sides numbered clockwise from the top.
  case dir
  of "TB": 2
  of "RL": 3
  of "BT": 0
  else: 1

# Builds the graph once per model.
proc agentGraph*(db: AgentflowDb, config: Config): AgentGraph =
  if db.graph != nil: return AgentGraph(db.graph)
  let curve = config["flowchart"]["curve"]
  result = buildAgentGraph(db, PALETTE, if curve != nil and curve.kind == yString: curve.s else: "")
  db.graph = result

proc numberOption(config: Config, key: string, fallback: float): float =
  let value = config["agentflow"][key]
  if value != nil and value.kind == yNumber and value.n > 0: min(value.n, 2000.0) else: fallback

# A palette color as an outline with a light wash of the same color inside.
# A fill the author set replaces the wash and stays opaque.
proc tint(slot: int, wash: string, style: ResolvedStyle): string =
  let color = seriesColor(slot)
  " fill=\"" & color & "\"" & (if setsFill(style.shape): "" else: " fill-opacity=\"" & wash & "\"") &
    " stroke=\"" & color & "\""

type NodeView = object
  node: GraphNode
  style: ResolvedStyle
  label: Label
  shape: string
  w, h: float
  dy: float
  loops: int

func stripDefault(s: string): string =
  ## s.replace(/^default\s?/, '')
  if not s.startsWith("default"): return s
  if s.len > 7 and isJsSpaceAt(s, 7): s.substr(7 + spaceLenAt(s, 7)) else: s.substr(7)

func hasInternalLink(s: string): bool =
  ## / internal-link(?: |$)/.test(s)
  var at = s.find(" internal-link")
  while at >= 0:
    let e = at + " internal-link".len
    if e == s.len or s[e] == ' ': return true
    at = s.find(" internal-link", at + 1)
  false

func withoutFlowClasses(s: string): string =
  ## s.replace(/edge-thickness-normal|edge-pattern-solid|flowchart-link/g, '')
  var i = 0
  while i < s.len:
    var matched = false
    for w in ["edge-thickness-normal", "edge-pattern-solid", "flowchart-link"]:
      if s.continuesWith(w, i):
        i += w.len
        matched = true
        break
    if not matched:
      result.add s[i]
      inc i

proc dot(x, y: float): string =
  "M" & num(x - 1.75) & "," & num(y) & "a1.75,1.75 0 1 0 3.5,0a1.75,1.75 0 1 0 -3.5,0Z"

proc draw(db: AgentflowDb, config: Config, options: RenderOptions, turned: bool): Rendered

proc renderAgentflow*(db: AgentflowDb, config: Config, options: RenderOptions): Rendered =
  if not runsAcross(db.direction): return draw(db, config, options, false)
  turnToFit(options, proc (down: bool): Rendered = draw(db, config, options, down))

# `turned` draws a diagram that runs across as one that runs down.
proc draw(db: AgentflowDb, config: Config, options: RenderOptions, turned: bool): Rendered =
  let graph = agentGraph(db, config)
  let size = options.fontSize.get(16)
  let edgeSize = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let wrapWidth = numberOption(config, "wrappingWidth", 120)
  let minWidth = numberOption(config, "minNodeWidth", 120)
  let pad = options.padding.get(8)
  let icons = options.icons

  var index = initTable[string, int]()
  var views: seq[NodeView]
  var cnodes: seq[CNode]
  for i, node in graph.nodes: index[node.id] = i

  for node in graph.nodes:
    let style = resolveStyle(
      if node.cssStyles.len > 0: node.cssCompiledStyles & node.cssStyles else: node.cssCompiledStyles)
    let textStyle = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let markdown = node.labelType == "markdown"
    let fontSize = if style.fontSize != 0: style.fontSize else: size
    var view: NodeView
    var c: CNode
    if node.isGroup:
      let label = layoutLabel(node.label, markdown, measurer, fontSize, 4000, textStyle)
      view = NodeView(node: node, style: style, label: label, shape: "group")
      c = cnode(0, 0)
      c.isGroup = true
      c.dir = if node.dir != "": direction(node.dir) else: ""
      c.padX = GROUP_PAD
      c.padTop = if label.height > 0: label.height + 16 else: GROUP_PAD
      c.padBottom = GROUP_PAD
      c.minW = label.width + 2 * GROUP_PAD - 12
    elif node.shape == "collapsedGroup":
      let label = layoutLabel(node.label, markdown, measurer, fontSize, wrapWidth, textStyle)
      let w = max(label.width, minWidth) + 2 * PAD_X
      let h = label.height + 2 * PAD_Y + DOTS
      view = NodeView(node: node, style: style, label: label, shape: COLLAPSED, w: w, h: h, dy: -DOTS / 2)
      c = cnode(w, h)
    else:
      let shape = canonicalShape(node.shape)
      let label = layoutLabel(node.label, markdown, measurer, fontSize, wrapWidth, textStyle)
      # A diamond grows twice as fast as its label, so it keeps the label's own width.
      let s = shapeSize(shape, if shape == "diam": label.width else: max(label.width, minWidth), label.height)
      view = NodeView(node: node, style: style, label: label, shape: shape, w: s.w, h: s.h, dy: s.dy)
      c = cnode(s.w, s.h)
    c.seq = float(views.len)
    views.add view
    cnodes.add c
  for i, node in graph.nodes:
    cnodes[i].parent = if node.parentId.isSome: index.getOrDefault(node.parentId.get, -1) else: -1
  var ends: seq[(int, int)]
  for edge in graph.edges: ends.add (index.getOrDefault(edge.start, -1), index.getOrDefault(edge.stop, -1))
  inheritCrossedDirections(cnodes, ends)

  let rootDir = if turned: "TB" else: direction(db.direction)
  # The direction of the level a node sits in.
  proc flowOf(i: int): Dir =
    var dir = ""
    var p = cnodes[i].parent
    var hops = 0
    while p >= 0 and dir == "" and hops < 10000:
      dir = cnodes[p].dir
      p = cnodes[p].parent
      inc hops
    if dir == "": rootDir else: dir
  proc flowsSideways(i: int): bool =
    let dir = flowOf(i)
    dir == "LR" or dir == "RL"

  var depth = newSeq[int](cnodes.len)
  for d in depth.mitems: d = -1
  for i in 0 ..< cnodes.len:
    var chain: seq[int]
    var j = i
    while j >= 0 and depth[j] < 0 and chain.len <= cnodes.len:
      chain.add j
      j = cnodes[j].parent
    var d = if j >= 0: depth[j] + 1 else: 0
    for k in countdown(chain.high, 0):
      depth[chain[k]] = d
      inc d
  proc contains(group, i: int): bool =
    var j = i
    var d = depth[i]
    while d > depth[group]:
      j = cnodes[j].parent
      dec d
    j == group and i != group

  type Held = object
    edge: GraphEdge
    label: Label
    src, dst: int
  var cedges: seq[CEdge]
  var edgeLabels: seq[Label]
  var drawn: seq[GraphEdge]
  # Edges between a node and a container around it. The layout has no place for them, so they
  # are drawn afterwards, between the node and the container's border.
  var held: seq[Held]
  for edge in graph.edges:
    if not index.hasKey(edge.start) or not index.hasKey(edge.stop): continue
    let src = index[edge.start]
    let dst = index[edge.stop]
    let label = layoutLabel(edge.label, edge.labelType == "markdown", measurer, edgeSize, wrapWidth)
    if contains(src, dst) or contains(dst, src):
      held.add Held(edge: edge, label: label, src: src, dst: dst)
      continue
    if src == dst:
      # A self-loop sits beside the node, across the flow, and the node's box grows to hold it.
      inc views[src].loops
      if flowsSideways(src): cnodes[src].h += 2 * (LOOP + (if label.height > 0: label.height + 8 else: 0))
      else: cnodes[src].w += 2 * (LOOP + (if label.width > 0: label.width + 12 else: 0))
    drawn.add edge
    edgeLabels.add label
    cedges.add CEdge(
      src: src,
      dst: dst,
      minlen: if edge.minlen != NO_LENGTH: edge.minlen else: 1,
      labelW: if label.width > 0: label.width + 12 else: 0,
      labelH: if label.height > 0: label.height + 4 else: 0,
      route: @[],
      labelX: 0,
      labelY: 0,
    )

  let layout = compoundLayout(cnodes, cedges, rootDir, LayeredOptions(
    nodeSep: numberOption(config, "nodeSpacing", NODE_SEP),
    edgeSep: EDGE_SEP,
    rankSep: numberOption(config, "rankSpacing", RANK_SEP),
    portSep: 20,
  ))

  let title = layoutLabel(db.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let inner = max(layout.width, title.width)
  let ox = pad + (inner - layout.width) / 2
  let oy = pad + titleHeight
  shiftLayout(cnodes, cedges, ox, oy)
  let width = ceil(inner + 2 * pad)
  let height = ceil(layout.height + titleHeight + 2 * pad)
  var links: seq[nimaki_types.LinkInfo]

  # An edge between a node and a container around it runs straight between the node and the
  # container's border: out along the flow, or in against it. If another node is in the way it
  # takes a side instead, and failing that the far end.
  var heldPaths: seq[EdgePath]
  var heldLabels: seq[float]
  var heldRoutes: seq[seq[float]]
  let careful = held.len * cnodes.len < 2_000_000
  for h in held:
    let output = contains(h.dst, h.src)
    let outer = if output: h.dst else: h.src
    let i = if output: h.src else: h.dst
    let g = cnodes[outer]
    let n = cnodes[i]
    let e = flowEnd(if g.dir != "": g.dir else: flowOf(outer))
    let first = if output: e else: (e + 2) and 3
    proc toward(side: int): seq[float] =
      let upright = (side and 1) == 0
      let sign = if side == 0 or side == 3: -1.0 else: 1.0
      let nx = if upright: n.x else: n.x + (sign * n.w) / 2
      let ny = if upright: n.y + (sign * n.h) / 2 else: n.y
      let bx = if upright: n.x else: g.x + (sign * g.w) / 2
      let by = if upright: g.y + (sign * g.h) / 2 else: n.y
      let axis = if upright: 0.0 else: 1.0
      if output: @[nx, ny, axis, bx, by, axis] else: @[bx, by, axis, nx, ny, axis]
    proc blocked(r: seq[float]): bool =
      for k in 0 ..< cnodes.len:
        let c = cnodes[k]
        if k != i and not c.isGroup and
            c.x + c.w / 2 > min(r[0], r[3]) - 1 and
            c.x - c.w / 2 < max(r[0], r[3]) + 1 and
            c.y + c.h / 2 > min(r[1], r[4]) - 1 and
            c.y - c.h / 2 < max(r[1], r[4]) + 1:
          return true
      false
    var route = toward(first)
    if careful and blocked(route):
      for side in [(first + 1) and 3, (first + 3) and 3, (first + 2) and 3]:
        let other = toward(side)
        if not blocked(other):
          route = other
          break
    heldRoutes.add route
    heldLabels.add (route[0] + route[3]) / 2
    heldLabels.add (route[1] + route[4]) / 2
    var drawnRoute = route
    let v = views[i]
    insetRoute(drawnRoute, if output: 0 else: 3, ShapeView(shape: v.shape, w: v.w, h: v.h), n)
    heldPaths.add routePath(drawnRoute, "linear", 0, markerTrim(h.edge.arrowTypeEnd))

  var crossings: Crossings = initTable[int, seq[float]]()
  var anyGroup = false
  for c in cnodes:
    if c.isGroup: anyGroup = true
  if anyGroup:
    for e in cedges: markCrossings(crossings, e.route)
    for route in heldRoutes: markCrossings(crossings, route)

  var clusters = ""
  var nodesOut = ""
  var fills: seq[Fill]
  for i in 0 ..< views.len:
    let view = views[i]
    let c = cnodes[i]
    let node = view.node
    let x = c.x
    let y = c.y
    let classes = classNames(stripDefault(node.cssClasses))
    let id = escText(node.id)
    let slotOf = if node.colorIndex >= 0: node.colorIndex else: KIND_COUNT
    if c.isGroup:
      if paints(view.style.shape):
        fills.add Fill(box: [x - c.w / 2, y - c.h / 2, x + c.w / 2, y + c.h / 2], shape: view.style.shape)
      let titleX = clusterTitleX(c, view.label.width, crossings, GROUP_PAD)
      clusters.add "<g class=\"pele-cluster pele-flow" & classes & "\" data-id=\"" & id & "\">" &
        "<rect x=\"" & num(x - c.w / 2) & "\" y=\"" & num(y - c.h / 2) & "\" width=\"" & num(c.w) &
        "\" height=\"" & num(c.h) & "\"" & rounded(tint(slotOf, "0.06", view.style) & view.style.shape) & "/>" &
        labelSvg(view.label, titleX, y - c.h / 2 + 8 + view.label.height / 2,
                 " class=\"pele-cluster-label\"" & inkFill(view.style.shape, view.style.text, "var(--_m)") &
                 view.style.text, icons) &
        "</g>"
      continue

    let w = view.w
    let h = view.h
    var kind = ""
    var shape: string
    if view.shape == COLLAPSED:
      let color = seriesColor(slotOf)
      let line = h / 2 - DOTS - 2
      let dots = line + (DOTS + 2) / 2
      shape =
        "<rect x=\"" & num(-w / 2) & "\" y=\"" & num(-h / 2) & "\" width=\"" & num(w) & "\" height=\"" & num(h) &
        "\"" & rounded(tint(slotOf, "0.06", view.style) & view.style.shape) & "/>" &
        "<path d=\"M" & num(-w / 2 + 10) & "," & num(line) & "H" & num(w / 2 - 10) &
        "\" fill=\"none\" stroke=\"" & color & "\" stroke-dasharray=\"3 3\"" & view.style.line & "/>" &
        "<path class=\"pele-collapsed-mark\" d=\"" & dot(-9, dots) & dot(0, dots) & dot(9, dots) &
        "\" fill=\"" & color & "\" stroke=\"none\"/>"
    else:
      let k = if node.kind != "": node.kind else: "task"
      let s = kindSlot(k)
      let slot = if s >= 0: s else: 1
      kind = " pele-kind-" & k
      shape = drawShape(view.shape, w, h, tint(slot, "0.14", view.style) & view.style.shape,
                        " stroke=\"" & seriesColor(slot) & "\"" & view.style.line)

    let ink = if view.shape == COLLAPSED or shapeFilled(view.shape): inkFill(view.style.shape, view.style.text) else: ""
    var text = labelSvg(view.label, 0, view.dy, " class=\"pele-label\"" & ink & view.style.text, icons)
    let internal = hasInternalLink(classes & " ")
    if internal and node.label != "" and options.links != some(false):
      # The label is a note name, but it still ends up in an href, so it gets the same check as a URL.
      let name = decodeEntities(node.label)
      let safe = internalLink(name, options)
      let target = esc(name)
      text = "<a class=\"internal-link\"" & (if safe: " href=\"" & target & "\"" & relAttr(options) else: "") &
        " data-href=\"" & target & "\">" & text & "</a>"
      links.add nimaki_types.LinkInfo(id: node.id, href: name, internal: true)
    var body = shape & text
    if node.tooltip != "": body = "<title>" & escText(node.tooltip) & "</title>" & body
    if node.link != "":
      body = linked(body, node.link, node.id, links, options,
                    if node.linkTarget != "": " target=\"" & esc(node.linkTarget) & "\"" else: "")
    nodesOut.add "<g class=\"pele-node pele-shape-" & view.shape & kind & classes & "\" data-id=\"" & id &
      "\" transform=\"translate(" & num(x) & "," & num(y) & ")\">" & body & "</g>"

  var casings = ""
  var edgesOut = ""
  var labelsOut = ""
  proc put(edge: GraphEdge, label: Label, path: EdgePath, x, y: float) =
    let styled = edge.style.len > 0 or edge.cssCompiledStyles.len > 0
    let style = if styled: resolveStyle(edge.cssCompiledStyles & edge.style) else: ResolvedStyle()
    let endType = edge.arrowTypeEnd
    let over = overFills(path.d, [path.ex, path.ey], fills, style.line, path.tokens)
    let overInk = not over.none and over.ink != ""
    let color =
      if overInk: over.ink
      elif styled and style.stroke != "": esc(style.stroke)
      else: "var(--_l)"
    let kind = if edge.thickness == "dotted": "reference" elif endType == "arrow_cross": "failure" else: "sequence"
    let classes = classNames(withoutFlowClasses(edge.classes))
    if not over.none and over.ink == "": casings.add edgeCasing(path, "none", endType, style.line)
    edgesOut.add "<g class=\"pele-edge pele-edge-" & kind & classes & "\" data-id=\"" & escText(edge.id) & "\"" &
      (if overInk: " stroke=\"" & over.ink & "\"" else: "") & style.line & ">" &
      "<path d=\"" & path.d & "\"" & (if edge.thickness == "dotted": " stroke-dasharray=\"3 4\"" else: "") & "/>" &
      marker(endType, path.ex, path.ey, path.edx, path.edy, color) &
      "</g>"
    if label.width > 0:
      labelsOut.add edgeLabelSvg(edge.id, label, x, y, style.text, icons)

  var loopSeen = initTable[int, int]()
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    let endType = edge.arrowTypeEnd
    var path: EdgePath
    if ce.src == ce.dst:
      let view = views[ce.src]
      let k = loopSeen.getOrDefault(ce.src, 0)
      loopSeen[ce.src] = k + 1
      path = loopPath((cnodes[ce.src].x, cnodes[ce.src].y), view.w, view.h, k, flowsSideways(ce.src), LOOP,
                      markerTrim(endType), ce)
    else:
      var route = ce.route
      let sv = views[ce.src]
      let dv = views[ce.dst]
      insetRoute(route, 0, ShapeView(shape: sv.shape, w: sv.w, h: sv.h), cnodes[ce.src])
      insetRoute(route, route.len - 3, ShapeView(shape: dv.shape, w: dv.w, h: dv.h), cnodes[ce.dst])
      path = routePath(route, edge.curve, 0, markerTrim(endType))
    put(edge, label, path, ce.labelX, ce.labelY)
  for i, h in held: put(h.edge, h.label, heldPaths[i], heldLabels[2 * i], heldLabels[2 * i + 1])

  let svg = svgDocument(
    "agentflow",
    width,
    height,
    size,
    options,
    Accessible(accTitle: db.accTitle, accDescr: db.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      casingsSvg(casings) &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" & edgesOut & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(edgeSize) & "\">" & labelsOut & "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & "</g>"
  )

  Rendered(svg: svg, width: width, height: height, links: links)

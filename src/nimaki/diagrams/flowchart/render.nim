## port-of: src/diagrams/flowchart/render.ts
## port-status: conformant
import std/[options, tables]
from std/math import ceil, isNaN
import ../../js
import ../../layout/[compound, layered]
import ../../preprocess
import ../../svg/[builder, cluster, edges, ink, root, shapes, theme, title]
import ../../text/[entities, icons, label, measurer]
import ../../types
import ../../util/[url, yaml]
import ../common/fit_width
import db, graph, types
import shapes as flowShapes
import ../../jsregex

const
  NODE_SEP = 40.0
  EDGE_SEP = 16.0
  RANK_SEP = 48.0
  GROUP_PAD = 20.0
  LOOP = 26.0
  SHAPE_ATTRS = " fill=\"var(--_s)\" stroke=\"var(--_b)\""
  LINE_ATTRS = " stroke=\"var(--_b)\""

proc numberOption(section: Config, key: string, fallback: float): float =
  let value = section[key]
  if value != nil and value.kind == yNumber and value.n > 0: min(value.n, 2000.0) else: fallback

type
  FlowVariant* = ref object
    ## A diagram type that is a flowchart with a different layout, which may draw its top-level
    ## groups itself.
    kind*: string
    prepare*: proc (graph: var FlowGraph)
    layout*: proc (nodes: seq[CNode], edges: seq[CEdge], dir: Dir, opt: LayeredOptions, tight: bool): CompoundResult
    drawGroup*: proc (c: CNode, label: Label, style: ResolvedStyle, classes, id: string, dir: Dir,
                      icons: IconResolver): string   ## nil for undefined
    filledBox*: proc (c: CNode, dir: Dir): array[4, float]
      ## The part of a drawGroup group that takes its fill, as [left, top, right, bottom]; nil
      ## for undefined.

proc assetSize(value: float, fallback: float): float =
  ## `value` NaN is undefined.
  if not value.isNaN and value > 0 and value <= 4000: value else: fallback

type NodeView = object
  node: GraphNode
  style: ResolvedStyle
  label: Label
  shape: string
  w, h: float
  dy: float
  loops: int

proc draw(db: FlowDb, config: Config, options: RenderOptions, variant: FlowVariant, turned, tight: bool): Rendered

proc renderFlowchart*(db: FlowDb, config: Config, options: RenderOptions, variant: FlowVariant = nil): Rendered =
  let fitted = proc (down: bool): Rendered =
    tighten(options, proc (tight: bool): Rendered = draw(db, config, options, variant, down, tight))
  if runsAcross(db.direction): turnToFit(options, fitted) else: fitted(false)

# `turned` draws a flowchart that runs across as one that runs down. `tight` sets nodes closer together.
proc draw(db: FlowDb, config: Config, options: RenderOptions, variant: FlowVariant, turned, tight: bool): Rendered =
  let groupPad = if tight: 12.0 else: GROUP_PAD
  let own = if variant != nil: config[variant.kind] else: nil
  let flow = if own.isRecord: own else: config["flowchart"]
  let curveOpt = flow["curve"]
  let isCurve = curveOpt != nil and curveOpt.kind == yString
  var graph = buildFlowGraph(db, if isCurve: curveOpt.s else: "")
  if variant != nil: variant.prepare(graph)
  let size = options.fontSize.get(16)
  let edgeSize = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let wrapWidth = min(numberOption(flow, "wrappingWidth", 200), if variant != nil and tight: 100.0 else: Inf)
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
      let label = layoutLabel(node.label, markdown, measurer, fontSize,
                              if variant != nil and tight: max(80.0, titleRoom(options) / 2) else: 4000.0, textStyle)
      view = NodeView(node: node, style: style, label: label, shape: "group")
      c = cnode(0, 0)
      c.isGroup = true
      c.dir = if node.dir != "": direction(node.dir) else: ""
      c.padX = groupPad
      c.padTop = if label.height > 0: label.height + 16 else: GROUP_PAD
      c.padBottom = groupPad
      c.minW = label.width + 2 * groupPad - 12
    else:
      let shape = canonicalShape(node.shape)
      let text = if node.img != "" or node.icon != "" or shapeHasLabel(shape): node.label else: ""
      let label = layoutLabel(text, markdown, measurer, fontSize, wrapWidth, textStyle)
      var w, h: float
      var dy = 0.0
      if node.img != "" or node.icon != "":
        let box = if node.img != "": 80.0 else: 48.0
        let aw = assetSize(node.assetWidth, box)
        let ah = assetSize(node.assetHeight, box)
        w = max(aw, label.width + 8)
        h = ah + (if label.height > 0: label.height + 6 else: 0)
        dy = if node.pos == "t": -ah / 2 else: ah / 2
        if label.height == 0: dy = 0
      else:
        let s = shapeSize(shape, label.width, label.height)
        w = s.w
        h = s.h
        dy = s.dy
      view = NodeView(node: node, style: style, label: label, shape: shape, w: w, h: h, dy: dy)
      c = cnode(w, h)
    c.seq = float(views.len)
    views.add view
    cnodes.add c
  for i, node in graph.nodes:
    cnodes[i].parent = if node.parentId.isSome: index.getOrDefault(node.parentId.get, -1) else: -1
  var ends: seq[(int, int)]
  for edge in graph.edges: ends.add (index.getOrDefault(edge.start, -1), index.getOrDefault(edge.stop, -1))
  inheritCrossedDirections(cnodes, ends)

  let rootDir = if turned: "TB" else: direction(db.direction)
  proc flowsSideways(i: int): bool =
    var dir = ""
    var p = cnodes[i].parent
    var hops = 0
    while p >= 0 and dir == "" and hops < 10000:
      dir = cnodes[p].dir
      p = cnodes[p].parent
      inc hops
    if dir == "": dir = rootDir
    dir == "LR" or dir == "RL"
  # The edges on one side of a node spread along it; a picture or an icon keeps them at its middle.
  for i, view in views:
    if view.node.isGroup: cnodes[i].span = Inf
    elif view.node.img == "" and view.node.icon == "":
      cnodes[i].span = shapeSpan(view.shape, view.w, view.h, flowsSideways(i))

  var cedges: seq[CEdge]
  var edgeLabels: seq[Label]
  var drawn: seq[GraphEdge]
  for edge in graph.edges:
    if not index.hasKey(edge.start) or not index.hasKey(edge.stop): continue
    let src = index[edge.start]
    let dst = index[edge.stop]
    let label = layoutLabel(edge.label, edge.labelType == "markdown", measurer, edgeSize, wrapWidth)
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

  let layoutOptions = LayeredOptions(
    nodeSep: numberOption(flow, "nodeSpacing", NODE_SEP) * (if tight: 0.5 else: 1),
    edgeSep: EDGE_SEP,
    rankSep: numberOption(flow, "rankSpacing", RANK_SEP) * (if tight: 0.75 else: 1),
    portSep: 20,
    tracks: isCurve and jsre"/^step/".test(curveOpt.s),
    straight: isCurve and curveOpt.s == "linear",
    headRoom: markerTrim("arrow_point"),
  )
  let layout =
    if variant != nil: variant.layout(cnodes, cedges, rootDir, layoutOptions, tight)
    else: compoundLayout(cnodes, cedges, rootDir, layoutOptions)

  let title = titleLabel(db.title, measurer, size, if tight: titleRoom(options) else: 4000)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let inner = max(layout.width, title.width)
  let ox = pad + (inner - layout.width) / 2
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
  var struckTitles = ""
  var nodesOut = ""
  var fills: seq[Fill]
  for i in 0 ..< views.len:
    let view = views[i]
    let c = cnodes[i]
    let node = view.node
    let x = c.x
    let y = c.y
    let classes = classNames(node.cssClasses.replace(jsre"/^default\s?/", ""))
    let id = escText(node.id)
    if c.isGroup and variant != nil and variant.drawGroup != nil and c.parent < 0:
      if paints(view.style.shape) and variant.filledBox != nil:
        fills.add Fill(box: variant.filledBox(c, rootDir), shape: view.style.shape)
      clusters.add variant.drawGroup(c, view.label, view.style, classes, id, rootDir, icons)
      continue
    if c.isGroup:
      if paints(view.style.shape):
        fills.add Fill(box: [x - c.w / 2, y - c.h / 2, x + c.w / 2, y + c.h / 2], shape: view.style.shape)
      let titleX = clusterTitleX(c, view.label.width, crossings, groupPad)
      let titleY = y - c.h / 2 + 8 + view.label.height / 2
      let struck = titleCrossed(c, view.label.width, titleX, crossings)
      # A title drawn over the edges sits on a halo in the theme's colors.
      let titleAttrs = " class=\"pele-cluster-label\"" &
        (if struck: " fill=\"var(--_m)\"" else: inkFill(view.style.shape, view.style.text, "var(--_m)")) &
        view.style.text
      if struck: struckTitles.add struckTitle(view.label, titleX, titleY, titleAttrs, id, cnodes, i, icons)
      clusters.add "<g class=\"pele-cluster" & classes & "\" data-id=\"" & id & "\">" &
        "<rect x=\"" & num(x - c.w / 2) & "\" y=\"" & num(y - c.h / 2) & "\" width=\"" & num(c.w) &
        "\" height=\"" & num(c.h) & "\" fill=\"var(--_a)\"" &
        (if setsFill(view.style.shape): "" else: " fill-opacity=\"0.5\"") & " stroke=\"var(--_b)\"" &
        rounded(view.style.shape) & "/>" &
        (if struck: "" else: labelSvg(view.label, titleX, titleY, titleAttrs, icons)) &
        "</g>"
      continue

    let w = view.w
    let h = view.h
    var inner: string
    var ink = ""
    if node.img != "":
      let aw = assetSize(node.assetWidth, 80)
      let ah = assetSize(node.assetHeight, 80)
      let top = if view.label.height > 0: (if node.pos == "t": h / 2 - ah else: -h / 2) else: -ah / 2
      let src = imageUrl(safeUrl(node.img), options)
      inner =
        if src.isNone: ""
        else:
          "<image href=\"" & esc(src.get) & "\" x=\"" & num(-aw / 2) & "\" y=\"" & num(top) & "\" width=\"" &
            num(aw) & "\" height=\"" & num(ah) & "\" preserveAspectRatio=\"" &
            (if node.constraint == "on": "xMidYMid meet" else: "none") & "\"/>"
    elif node.icon != "":
      let box = assetSize(node.assetHeight, 48)
      let top = if view.label.height > 0: (if node.pos == "t": h / 2 - box else: -h / 2) else: -box / 2
      let frame =
        if node.shape == "icon": ""
        elif node.shape == "iconCircle":
          "<circle cy=\"" & num(top + box / 2) & "\" r=\"" & num(box / 2) & "\"" & SHAPE_ATTRS & view.style.shape & "/>"
        else:
          "<rect x=\"" & num(-box / 2) & "\" y=\"" & num(top) & "\" width=\"" & num(box) & "\" height=\"" &
            num(box) & "\" rx=\"" & (if node.shape == "iconRounded": "8" else: "0") & "\"" & SHAPE_ATTRS &
            view.style.shape & "/>"
      let glyph = box * 0.6
      inner = frame &
        "<svg class=\"pele-icon\" data-icon=\"" & escText(node.icon) & "\" x=\"" & num(-glyph / 2) & "\" y=\"" &
        num(top + (box - glyph) / 2) & "\" width=\"" & num(glyph) & "\" height=\"" & num(glyph) &
        "\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
        (if icons != nil: icons(node.icon) else: "") & "</svg>"
    else:
      inner = drawShape(view.shape, w, h, SHAPE_ATTRS & view.style.shape, LINE_ATTRS & view.style.line)
      if shapeFilled(view.shape): ink = inkFill(view.style.shape, view.style.text)

    var text = labelSvg(view.label, 0, view.dy, " class=\"pele-label\"" & ink & view.style.text, icons)
    let internal = jsre"/ internal-link(?: |$)/".test(classes & " ")
    if internal and node.label != "" and options.links != some(false):
      # The label is a note name, but it still ends up in an href, so it gets the same check as a URL.
      let name = decodeEntities(node.label)
      let safe = internalLink(name, options)
      let target = esc(name)
      text = "<a class=\"internal-link\"" & (if safe: " href=\"" & target & "\"" & relAttr(options) else: "") &
        " data-href=\"" & target & "\">" & text & "</a>"
      links.add LinkInfo(id: node.id, href: name, internal: true)
    var body = inner & text
    if node.tooltip != "": body = "<title>" & escText(node.tooltip) & "</title>" & body
    if node.link != "":
      body = linked(body, node.link, node.id, links, options,
                    if node.linkTarget != "": " target=\"" & esc(node.linkTarget) & "\"" else: "")
    nodesOut.add "<g class=\"pele-node pele-shape-" & view.shape & classes & "\" data-id=\"" & id &
      "\" transform=\"translate(" & num(x) & "," & num(y) & ")\">" & body & "</g>"

  let reach = sideReach()
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    if ce.src == ce.dst or drawn[i].thickness == "invisible" or ce.route.len < 6: continue
    reach.add(ce.src, endSide(ce.route, 0, cnodes[ce.src]), drawn[i].arrowTypeStart)
    reach.add(ce.dst, endSide(ce.route, ce.route.len - 3, cnodes[ce.dst]), drawn[i].arrowTypeEnd)

  var casings = ""
  var edgesOut = ""
  var labelsOut = ""
  var loopSeen = initTable[int, int]()
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    let styled = edge.style.len > 0 or edge.cssCompiledStyles.len > 0
    let style = if styled: resolveStyle(edge.cssCompiledStyles & edge.style) else: ResolvedStyle()
    if edge.thickness != "invisible":
      let startType = edge.arrowTypeStart
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
        let leaves = reach.reachOf(ce.src, endSide(route, 0, cnodes[ce.src]))
        let arrives = reach.reachOf(ce.dst, endSide(route, route.len - 3, cnodes[ce.dst]))
        let sv = views[ce.src]
        let dv = views[ce.dst]
        insetRoute(route, 0, ShapeView(shape: sv.shape, w: sv.w, h: sv.h), cnodes[ce.src])
        insetRoute(route, route.len - 3, ShapeView(shape: dv.shape, w: dv.w, h: dv.h), cnodes[ce.dst])
        path = routePath(route, edge.curve, markerTrim(startType), markerTrim(endType), leaves, arrives)
      let over = overFills(path.d, [path.sx, path.sy, path.ex, path.ey], fills, style.line, path.tokens)
      let overInk = not over.none and over.ink != ""
      let color =
        if overInk: over.ink
        elif style.stroke != "" and edge.thickness != "invisible": esc(style.stroke)
        else: "var(--_l)"
      var attrs = ""
      if edge.thickness == "thick": attrs.add " stroke-width=\"2.5\""
      elif edge.thickness == "dotted": attrs.add " stroke-dasharray=\"3 4\""
      let classes = classNames(edge.classes.replace(jsre"/edge-thickness-normal|edge-pattern-solid|flowchart-link/g", ""))
      if not over.none and over.ink == "":
        casings.add edgeCasing(path, startType, endType, style.line, edge.thickness == "thick")
      edgesOut.add "<g class=\"pele-edge" & classes & "\" data-id=\"" & escText(edge.id) & "\"" &
        (if overInk: " stroke=\"" & over.ink & "\"" else: "") & style.line & ">" &
        "<path d=\"" & path.d & "\"" & attrs & "/>" &
        marker(startType, path.sx, path.sy, path.sdx, path.sdy, color) &
        marker(endType, path.ex, path.ey, path.edx, path.edy, color) &
        "</g>"
    if label.width > 0:
      let x = ce.labelX
      let y = ce.labelY
      labelsOut.add edgeLabelSvg(edge.id, label, x, y, style.text, icons)

  let svg = svgDocument(
    if variant != nil: variant.kind else: "flowchart",
    width,
    height,
    size,
    options,
    Accessible(accTitle: db.accTitle, accDescr: db.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      casingsSvg(casings) &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" & edgesOut & "</g>" else: "") &
      (if struckTitles != "": "<g class=\"pele-cluster-titles\">" & struckTitles & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(edgeSize) & "\">" & labelsOut & "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & "</g>"
  )

  Rendered(svg: svg, width: width, height: height, links: links)

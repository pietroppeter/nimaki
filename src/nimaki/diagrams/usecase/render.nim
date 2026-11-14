## port-of: src/diagrams/usecase/render.ts
## port-status: conformant
import std/[algorithm, options, strutils, tables]
from std/math import ceil
import ../../js
import ../../jsmath
import ../../layout/[compound, layered]
import ../../preprocess
import ../../svg/[builder, cluster, edges, ink, root, theme, title]
import ../../text/[icons, label, measurer]
import ../../types
import ../../util/yaml
import ../common/fit_width
import graph
import types as usecaseTypes

const
  NODE_SEP = 32.0
  EDGE_SEP = 16.0
  RANK_SEP = 72.0
  GROUP_PAD = 20.0
  LOOP = 26.0
  FIGURE_W = 40.0
  FIGURE_H = 60.0
  FIGURE_GAP = 6.0
  TAB_PAD = 6.0
  CELL_PAD = 10.0
  ROW_PAD = 8.0
  FOLD = 9.0
  EXTENSION = 12.0
  PORT_GAP = 14.0
  SHAPE_ATTRS = " fill=\"var(--_s)\" stroke=\"var(--_b)\""

type
  Kind = enum kActor, kEllipse, kBox, kJson, kBoundary

  View = ref object
    node: UsecaseGraphNode
    kind: Kind
    style: ResolvedStyle
    label: Label
    stereotype: Label
    # The size of what is drawn; the layout box is larger when the node carries a self-relationship.
    w, h: float
    rows: seq[(Label, Label)]
    keyW: float
    headH: float
    loops: int

proc numberOption(config: Config, key: string, fallback: float): float =
  let value = config["usecase"][key]
  if value != nil and value.kind == yNumber and value.n > 0: min(value.n, 2000.0) else: fallback

proc literal(text: string): string =
  ## A plain label is shown as written: no tags, no markdown, no `\n` breaks. Its markup
  ## characters are handed to the label parser as character references, which it turns back
  ## into characters.
  for c in text:
    if c in {'&', '<', '>', '\\'}: result.add "&#" & $ord(c) & ";"
    else: result.add c

proc text(raw: string, markdown: bool, measurer: TextMeasurer, size, wrap: float, base = 0): Label =
  layoutLabel(if raw != "" and not markdown: literal(raw) else: raw, markdown, measurer, size, wrap, base)

# The point of a node's outline on one of its four sides (0 top, 1 right, 2 bottom, 3 left),
# `along` away from the middle of that side. Lines meet an actor at its figure, not at its label.
proc anchor(view: View, c: CNode, side: int, along: float): (float, float) =
  let sign = if side == 1 or side == 2: 1.0 else: -1.0
  let upright = side == 1 or side == 3
  var reach = (if upright: view.w else: view.h) / 2
  var middle = 0.0
  if view.kind == kActor:
    if upright:
      reach = FIGURE_W / 2 + 3
      middle = (FIGURE_H - view.h) / 2
    else: reach += 2
  elif view.kind == kEllipse:
    let span = (if upright: view.h else: view.w) / 2
    reach *= sqrt(max(1 - pow(along / span, 2), 0))
  if upright: (c.x + sign * reach, c.y + middle + along) else: (c.x + along, c.y + sign * reach)

# How much of a side edges may spread over.
proc sideLength(view: View, side: int): float =
  let upright = side == 1 or side == 3
  if view.kind == kActor: return (if upright: FIGURE_H * 0.5 else: FIGURE_W * 0.6)
  let length = if upright: view.h else: view.w
  if view.kind == kEllipse: length * 0.6 else: length - 16

type End = object
  edge: int
  at: int
  toward: float

# The layout brings every edge that ends on one side of a node to the middle of that side. This
# spaces them along the side in the order they fan out, and puts each on the node's outline.
proc attachEnds(cedges: seq[CEdge], cnodes: seq[CNode], views: seq[View]) =
  var sides = initOrderedTable[int, seq[End]]()
  proc add(index, edge, at, next: int) =
    let c = cnodes[index]
    if c.isGroup: return
    let route = cedges[edge].route
    let dx = route[at] - c.x
    let dy = route[at + 1] - c.y
    var side: int
    if abs(abs(dy) - c.h / 2) < 0.5: side = if dy < 0: 0 else: 2
    elif abs(abs(dx) - c.w / 2) < 0.5: side = if dx < 0: 3 else: 1
    else: return
    let stop = End(edge: edge, at: at, toward: route[next + (if (side and 1) != 0: 1 else: 0)])
    sides.mgetOrPut(index * 4 + side, @[]).add stop
  for k, e in cedges:
    let last = e.route.len - 3
    if e.src == e.dst or last < 3: continue
    add(e.src, k, 0, 3)
    add(e.dst, k, last, last - 3)
  for key, ends in sides.mpairs:
    let index = key shr 2
    let side = key and 3
    let view = views[index]
    let step = if ends.len > 1: min(PORT_GAP, sideLength(view, side) / float(ends.len - 1)) else: 0.0
    ends.sort(proc (a, b: End): int = cmp(a.toward, b.toward))
    for i in 0 ..< ends.len:
      let (x, y) = anchor(view, cnodes[index], side, (float(i) - float(ends.len - 1) / 2) * step)
      cedges[ends[i].edge].route[ends[i].at] = x
      cedges[ends[i].edge].route[ends[i].at + 1] = y

# The hollow triangle of a generalization, with its tip at (x, y).
proc extension(x, y, dx, dy: float, color: string): string =
  let bx = x - dx * EXTENSION
  let by = y - dy * EXTENSION
  let half = EXTENSION * 0.5
  "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & num(bx - dy * half) & "," &
    num(by + dx * half) & "L" & num(bx + dy * half) & "," & num(by - dx * half) &
    "Z\" fill=\"var(--_bg)\" stroke=\"" & color & "\" stroke-linejoin=\"round\"/>"

proc trim(kind: string): float =
  if kind == "extension": EXTENSION else: markerTrim(kind)

proc mark(kind: string, x, y, dx, dy: float, color: string, stroke = "none"): string =
  if kind == "extension": extension(x, y, dx, dy, color) else: marker(kind, x, y, dx, dy, color, stroke)

proc figure(view: View, icons: IconResolver): string =
  let node = view.node
  let shape = view.style.shape
  let line = " fill=\"none\" stroke=\"var(--_b)\"" & view.style.line
  var head = -21.0
  var radius = 9.0
  var output: string
  if node.actorType == "hollow":
    radius = 8
    output =
      "<circle cy=\"-21\" r=\"8\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & shape & "/>" &
      "<path d=\"M-20,-9H20V0H5.5L20,15.5L12,25.5L0,12L-12,25.5L-20,15.5L-5.5,0H-20Z\" fill=\"var(--_bg)\" " &
      "stroke=\"var(--_b)\" stroke-linejoin=\"round\"" & shape & "/>"
  elif node.actorType == "awesome":
    output = "<path d=\"M0,-30A11,11 0 1 1 0,-8A11,11 0 1 1 0,-30ZM-20,25C-20,9 -12,-3 0,-3C12,-3 20,9 20,25C20,28 " &
      "18,30 15,30H-15C-18,30 -20,28 -20,25Z\" fill=\"var(--_b)\"" & shape & "/>"
  elif node.actorType == "icon":
    head = -14
    radius = 12
    output =
      "<rect x=\"-22\" y=\"-26\" width=\"44\" height=\"44\"" & rounded(SHAPE_ATTRS & shape) & "/>" &
      "<svg class=\"pele-icon\" data-icon=\"" & escText(node.icon) & "\" x=\"-14\" y=\"-18\" width=\"28\" " &
      "height=\"28\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" " &
      "stroke-linecap=\"round\" stroke-linejoin=\"round\">" & (if icons != nil: icons(node.icon) else: "") & "</svg>"
  else:
    output = "<circle cy=\"-21\" r=\"9\"" & SHAPE_ATTRS & shape & "/><path d=\"M0,-12V10M-14,-3H14M0,10L-12,30M0,10L12,30\"" &
      line & "/>"
  if node.business:
    # The slash of a business actor: a chord across the lower right of the head.
    output.add "<path class=\"pele-business\" d=\"M" & num(0.12 * radius) & "," & num(head + 0.99 * radius) & "L" &
      num(0.92 * radius) & "," & num(head - 0.39 * radius) & "\"" & line & "/>"
  output

proc draw(model: UsecaseModel, config: Config, options: RenderOptions, turned: bool): Rendered

proc renderUsecase*(model: UsecaseModel, config: Config, options: RenderOptions): Rendered =
  if not runsAcross(model.direction): return draw(model, config, options, false)
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

proc titleX(c: CNode, width: float, crossings: Table[int, seq[float]]): float

proc leftLabel(label: Label, x, cy: float, attrs: string, icons: IconResolver): string

# `turned` draws a diagram that runs across as one that runs down.
proc draw(model: UsecaseModel, config: Config, options: RenderOptions, turned: bool): Rendered =
  let graph = buildUsecaseGraph(model)
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.8125)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  let rootDir = if turned: "TB" else: direction(model.direction)
  let sideways = rootDir == "LR" or rootDir == "RL"

  var index = initTable[string, int]()
  var views: seq[View]
  var cnodes: seq[CNode]
  for i, node in graph.nodes: index[node.id] = i

  for node in graph.nodes:
    let style = resolveStyle(
      if node.cssStyles.len > 0: node.cssCompiledStyles & node.cssStyles else: node.cssCompiledStyles)
    let base = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let fontSize = if style.fontSize != 0: style.fontSize else: size
    let markdown = node.markdown
    let stereotype = text(if node.stereotype != "": "«" & node.stereotype & "»" else: "", false, measurer, tiny,
                          200, base)
    let view = View(node: node, kind: kBox, style: style, label: stereotype, stereotype: stereotype)
    var c: CNode
    if node.isGroup:
      view.kind = kBoundary
      view.label = text(node.label, markdown, measurer, fontSize, 4000, base)
      let titleH = view.label.height
      c = cnode(0, 0)
      c.isGroup = true
      c.padX = GROUP_PAD
      c.padBottom = GROUP_PAD
      c.padTop = if node.boundaryType == "package": titleH + 2 * TAB_PAD + 16
                 elif titleH > 0: titleH + 16
                 else: GROUP_PAD
      c.minW = view.label.width + 2 * GROUP_PAD
    else:
      if node.isJson:
        view.kind = kJson
        view.label = text(node.label, false, measurer, fontSize, 4000, base or Bold)
        var valueW = 0.0
        for row in node.jsonRows:
          let key = text(row.key, false, measurer, small, 4000, base)
          let value = text(row.value, false, measurer, small, 260, base)
          view.rows.add (key, value)
          view.keyW = max(view.keyW, key.width)
          valueW = max(valueW, value.width)
          view.h += max(max(key.height, value.height), jsRound(small * 1.5)) + ROW_PAD
        # The root of an empty object has a value and no key, and then there is no key column.
        if view.keyW > 0: view.keyW += 2 * CELL_PAD
        view.headH = max(view.label.height, jsRound(fontSize * 1.5)) + ROW_PAD
        view.w = max(max(view.label.width + 2 * CELL_PAD,
                         if view.rows.len > 0: view.keyW + valueW + 2 * CELL_PAD else: 0.0), 72.0)
        view.h += view.headH
      elif node.actorType != "":
        view.kind = kActor
        view.label = text(node.label, markdown, measurer, fontSize, 140, base)
        view.w = max(max(FIGURE_W, view.label.width), stereotype.width)
        view.h = FIGURE_H + FIGURE_GAP + stereotype.height + view.label.height
      else:
        view.label = text(node.label, markdown, measurer, if node.shape == "note": small else: fontSize, 180, base)
        let tw = max(view.label.width, stereotype.width)
        let th = view.label.height + stereotype.height
        if node.shape == "usecaseEllipse" or node.shape == "usecaseBusiness":
          view.kind = kEllipse
          # An oval needs more room around its text than a box, and a business oval room for its slash.
          view.w = max(tw + 2 * node.padding + (if node.business: 16.0 else: 4.0), 88.0)
          view.h = max(th + 28, 48.0)
        elif node.shape == "note":
          view.w = tw + 2 * node.padding + 6
          view.h = th + 18
        else:
          view.w = max(tw + 2 * node.padding + 12, 80.0)
          view.h = max(th + 24, 44.0)
      c = cnode(view.w, view.h)
    c.seq = float(views.len)
    views.add view
    cnodes.add c
  for i, node in graph.nodes:
    cnodes[i].parent = if node.parentId != "": index.getOrDefault(node.parentId, -1) else: -1

  var cedges: seq[CEdge]
  var edgeLabels: seq[Label]
  var drawn: seq[UsecaseGraphEdge]
  for edge in graph.edges:
    let src = index.getOrDefault(edge.start, -1)
    let dst = index.getOrDefault(edge.stop, -1)
    if src == -1 or dst == -1: continue
    let semantic = edge.relationshipType == "include" or edge.relationshipType == "extend"
    let label = text(if semantic: "«" & edge.label & "»" else: edge.label, edge.labelMarkdown, measurer, small, 200)
    if src == dst:
      # A self-relationship loops out across the flow, and the node's box grows to hold it.
      inc views[src].loops
      if sideways: cnodes[src].h += 2 * (LOOP + (if label.height > 0: label.height + 8 else: 0.0))
      else: cnodes[src].w += 2 * (LOOP + (if label.width > 0: label.width + 12 else: 0.0))
    drawn.add edge
    edgeLabels.add label
    cedges.add CEdge(src: src, dst: dst, minlen: edge.minlen,
                     labelW: if label.width > 0: label.width + 12 else: 0,
                     labelH: if label.height > 0: label.height + 4 else: 0,
                     route: @[], labelX: 0, labelY: 0)

  let layout = compoundLayout(cnodes, cedges, rootDir, LayeredOptions(
    nodeSep: numberOption(config, "nodeSpacing", NODE_SEP),
    edgeSep: EDGE_SEP,
    rankSep: numberOption(config, "rankSpacing", RANK_SEP),
    portSep: 20,
  ))

  let title = titleLabel(model.title, measurer, size, 4000)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let inner = max(layout.width, title.width)
  let ox = pad + (inner - layout.width) / 2
  let oy = pad + titleHeight
  shiftLayout(cnodes, cedges, ox, oy)
  let width = ceil(inner + 2 * pad)
  let height = ceil(layout.height + titleHeight + 2 * pad)

  # Where edges cross each boundary's top border, so that a title can keep out of their way.
  var crossings: Crossings = initTable[int, seq[float]]()
  for e in cedges: markCrossings(crossings, e.route)
  attachEnds(cedges, cnodes, views)

  var clusters = ""
  var fills: seq[Fill]
  var nodesOut = ""
  for i in 0 ..< views.len:
    let view = views[i]
    let c = cnodes[i]
    let node = view.node
    var stripped = node.cssClasses
    if stripped.startsWith("default"):
      stripped = stripped[7 .. ^1]
      if stripped.len > 0 and stripped[0] in Whitespace: stripped = stripped[1 .. ^1]
    let classes = classNames(stripped)
    let id = escText(node.id)
    let textAttrs = view.style.text
    let shape = view.style.shape
    let color = inkFill(view.style.shape, view.style.text)
    let muted = if color != "": color else: " fill=\"var(--_m)\""
    let w = view.w
    let h = view.h

    if view.kind == kBoundary:
      let x = c.x - c.w / 2
      let y = c.y - c.h / 2
      if paints(shape): fills.add Fill(box: [x, y, x + c.w, y + c.h], shape: shape)
      let box = " fill=\"var(--_a)\"" & (if setsFill(shape): "" else: " fill-opacity=\"0.5\"") &
        " stroke=\"var(--_b)\"" & shape
      let titleAttrs = " class=\"pele-cluster-label\"" & muted & textAttrs
      var body: string
      if node.boundaryType == "package":
        let tabW = min(view.label.width + 2 * TAB_PAD + 8, c.w)
        let tabH = view.label.height + 2 * TAB_PAD
        body =
          "<rect class=\"pele-boundary-tab\" x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(tabW) &
            "\" height=\"" & num(tabH) & "\"" & box & "/>" &
          "<rect x=\"" & num(x) & "\" y=\"" & num(y + tabH) & "\" width=\"" & num(c.w) & "\" height=\"" &
            num(c.h - tabH) & "\"" & box & "/>" &
          labelSvg(view.label, x + tabW / 2, y + tabH / 2, titleAttrs, icons)
      else:
        body =
          "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(c.w) & "\" height=\"" & num(c.h) & "\"" &
            rounded(box) & "/>" &
          labelSvg(view.label, titleX(c, view.label.width, crossings), y + 8 + view.label.height / 2, titleAttrs,
                   icons)
      clusters.add "<g class=\"pele-cluster pele-boundary" & classes & "\" data-id=\"" & id & "\">" & body & "</g>"
      continue

    var body: string
    var kind: string
    if view.kind == kActor:
      kind = "pele-actor"
      let top = -h / 2
      let stereotypeY = top + FIGURE_H + FIGURE_GAP + view.stereotype.height / 2
      body =
        "<g class=\"pele-actor-figure\" transform=\"translate(0," & num(top + FIGURE_H / 2) & ")\">" &
          figure(view, icons) & "</g>" &
        labelSvg(view.stereotype, 0, stereotypeY, " class=\"pele-stereotype\" font-size=\"" & jsString(tiny) &
                 "\" fill=\"var(--_m)\"", icons) &
        labelSvg(view.label, 0, h / 2 - view.label.height / 2, " class=\"pele-label\"" & textAttrs, icons)
    elif view.kind == kJson:
      kind = "pele-json"
      let x0 = -w / 2
      var y = -h / 2 + view.headH
      var cells = ""
      var lines = "M" & num(x0) & "," & num(y) & "H" & num(x0 + w)
      if view.keyW > 0: lines.add "M" & num(x0 + view.keyW) & "," & num(y) & "V" & num(h / 2)
      for (key, value) in view.rows:
        let rowH = max(max(key.height, value.height), jsRound(small * 1.5)) + ROW_PAD
        cells.add labelSvg(key, x0 + CELL_PAD + key.width / 2, y + rowH / 2, " class=\"pele-json-key\"" & muted,
                           icons) &
          leftLabel(value, x0 + view.keyW + CELL_PAD, y + rowH / 2, " class=\"pele-json-value\"" & color & textAttrs,
                    icons)
        y += rowH
      body =
        "<rect x=\"" & num(x0) & "\" y=\"" & num(-h / 2) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\"" &
          rounded(SHAPE_ATTRS & shape) & "/>" &
        "<path class=\"pele-json-lines\" d=\"" & lines & "\" fill=\"none\" stroke=\"var(--_b)\"" & view.style.line &
          "/>" &
        labelSvg(view.label, 0, -h / 2 + view.headH / 2, " class=\"pele-label\" font-weight=\"var(--_hw)\"" & color &
                 textAttrs, icons) &
        "<g font-size=\"" & jsString(small) & "\">" & cells & "</g>"
    else:
      let labelY = view.stereotype.height / 2
      var outline: string
      if view.kind == kEllipse:
        kind = "pele-usecase"
        outline = "<ellipse rx=\"" & num(w / 2) & "\" ry=\"" & num(h / 2) & "\"" & SHAPE_ATTRS & shape & "/>"
        if node.business:
          # The slash of a business use case, cutting off the right end of the oval beside the text.
          let first = w / 2 - 15
          let last = w / 2 - 5
          proc arc(at: float): float = (h / 2) * sqrt(1 - pow(at / (w / 2), 2))
          outline.add "<path class=\"pele-business\" d=\"M" & num(first) & "," & num(arc(first)) & "L" & num(last) &
            "," & num(-arc(last)) & "\" fill=\"none\" stroke=\"var(--_b)\"" & view.style.line & "/>"
      elif node.shape == "note":
        kind = "pele-note"
        let r = w / 2
        let b = h / 2
        outline =
          "<path d=\"M" & num(-r) & "," & num(-b) & "H" & num(r - FOLD) & "L" & num(r) & "," & num(FOLD - b) & "V" &
            num(b) & "H" & num(-r) & "Z\" fill=\"var(--_a)\" stroke=\"var(--_b)\" stroke-linejoin=\"round\"" & shape &
            "/>" &
          "<path d=\"M" & num(r - FOLD) & "," & num(-b) & "V" & num(FOLD - b) & "H" & num(r) &
            "\" fill=\"none\" stroke=\"var(--_b)\" stroke-linejoin=\"round\"" & view.style.line & "/>"
      else:
        kind = "pele-usecase"
        outline = "<rect x=\"" & num(-w / 2) & "\" y=\"" & num(-h / 2) & "\" width=\"" & num(w) & "\" height=\"" &
          num(h) & "\"" & rounded(SHAPE_ATTRS & shape) & "/>"
      body =
        outline &
        labelSvg(view.stereotype, 0, -view.label.height / 2,
                 " class=\"pele-stereotype\" font-size=\"" & jsString(tiny) & "\"" & muted, icons) &
        labelSvg(view.label, 0, labelY,
                 " class=\"pele-label\"" & (if node.shape == "note": " font-size=\"" & jsString(small) & "\"" else: "") &
                   color & textAttrs, icons)
    nodesOut.add "<g class=\"pele-node " & kind & classes & "\" data-id=\"" & id & "\" transform=\"translate(" &
      num(c.x) & "," & num(c.y) & ")\">" & body & "</g>"

  var casings = ""
  var edgesOut = ""
  var labelsOut = ""
  var loopSeen = initTable[int, int]()
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    let hasStyle = edge.style.len > 0 or edge.cssCompiledStyles.len > 0
    let style = if hasStyle: resolveStyle(edge.cssCompiledStyles & edge.style) else: ResolvedStyle()
    let startType = edge.arrowTypeStart
    let endType = edge.arrowTypeEnd
    var path: EdgePath
    if ce.src == ce.dst:
      let c = cnodes[ce.src]
      let view = views[ce.src]
      let k = loopSeen.getOrDefault(ce.src, 0)
      loopSeen[ce.src] = k + 1
      let side = if sideways: 2 else: 1
      let spread = min(sideLength(view, side) / 2, 8 + float(k) * 6)
      let reach = LOOP + float(k) * 8
      let (ax, ay) = anchor(view, c, side, -spread)
      let (bx, by) = anchor(view, c, side, spread)
      var len = hypot(reach, spread)
      if len == 0: len = 1
      let ux = if sideways: spread / len else: reach / len
      let uy = if sideways: reach / len else: spread / len
      let st = trim(startType)
      let et = trim(endType)
      # Both ends leave the node leaning away from each other, and the curve joins them outside it.
      proc outward(x, y, sign, far: float): string =
        let lean = if far != 0: 1.0 else: 0.0
        if sideways: num(x + sign * spread * lean) & "," & num(y + far)
        else: num(x + far) & "," & num(y + sign * spread * lean)
      let sx = if sideways: ax - ux * st else: ax + ux * st
      let sy = if sideways: ay + uy * st else: ay - uy * st
      let ex = bx + ux * et
      let ey = by + uy * et
      path = EdgePath(
        d: "M" & num(sx) & "," & num(sy) & "C" & outward(ax, ay, -1, reach) & " " & outward(bx, by, 1, reach) & " " &
          num(ex) & "," & num(ey),
        sx: ax, sy: ay,
        sdx: if sideways: ux else: -ux,
        sdy: if sideways: -uy else: uy,
        ex: bx, ey: by,
        edx: -ux, edy: -uy,
      )
      if sideways:
        ce.labelX = c.x
        ce.labelY = max(ay, by) + reach * 0.75 + 6 + label.height / 2
      else:
        ce.labelX = max(ax, bx) + reach * 0.75 + 8 + label.width / 2
        ce.labelY = c.y
    else:
      if ce.route.len < 6: continue
      path = routePath(ce.route, "", trim(startType), trim(endType))
    let under = fillUnder(path.d, [path.sx, path.sy, path.ex, path.ey], fills, path.tokens)
    # `over`: the fill's ink, '' for a casing, or undefined off fills.
    let overSet = not under.none
    let over = if not under.none and not under.across: edgeInk(under.fill, style.line) else: ""
    let color = if over != "": over elif style.stroke != "": esc(style.stroke) else: "var(--_l)"
    if overSet and over == "":
      let bg = "var(--_bg)"
      casings.add casing(path.d, mark(startType, path.sx, path.sy, path.sdx, path.sdy, bg, bg) &
                         mark(endType, path.ex, path.ey, path.edx, path.edy, bg, bg), style.line)
    # Mermaid animates these dashes. A still picture keeps the dashes.
    let dashes = if edge.internal: "2 3" elif edge.pattern == "dotted": "5 4" elif edge.animate: "9 5" else: ""
    let marks = mark(startType, path.sx, path.sy, path.sdx, path.sdy, color) &
      mark(endType, path.ex, path.ey, path.edx, path.edy, color)
    # edge.classes.replace(/^default relationship relationship-\S+\s?/, '')
    var extra = edge.classes
    const prefix = "default relationship relationship-"
    if extra.startsWith(prefix):
      var k = prefix.len
      while k < extra.len and extra[k] notin Whitespace: inc k
      if k > prefix.len:
        if k < extra.len: inc k
        extra = extra[k .. ^1]
    edgesOut.add "<g class=\"pele-edge pele-" & edge.relationshipType & classNames(extra) & "\" data-id=\"" &
      escText(edge.id) & "\"" & (if over != "": " stroke=\"" & over & "\"" else: "") & style.line & ">" &
      "<path d=\"" & path.d & "\"" & (if dashes != "": " stroke-dasharray=\"" & dashes & "\"" else: "") & "/>" &
      (if not under.none and not under.across and over != "": hollowOn(marks, under.fill) else: marks) & "</g>"
    if label.width > 0:
      let semantic = edge.relationshipType == "include" or edge.relationshipType == "extend"
      labelsOut.add edgeLabelSvg(edge.id, label, ce.labelX, ce.labelY,
                                 (if semantic: " fill=\"var(--_m)\"" else: "") & style.text, icons)

  let svg = svgDocument(
    "usecase",
    width,
    height,
    size,
    options,
    Accessible(accTitle: model.accTitle, accDescr: model.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      casingsSvg(casings) &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" &
        edgesOut & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\">" & labelsOut &
        "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & "</g>"
  )
  Rendered(svg: svg, width: width, height: height, links: @[])

# A boundary's title sits in the middle of its top edge. Where edges enter through that edge it
# moves into the stretch between them that is nearest the middle, or the widest if none has room.
proc titleX(c: CNode, width: float, crossings: Table[int, seq[float]]): float =
  let key = int(jsRound(c.y - c.h / 2))
  if width == 0 or not crossings.hasKey(key): return c.x
  let left = c.x - c.w / 2 + 6
  let right = c.x + c.w / 2 - 6
  var cuts: seq[float]
  for x in crossings[key]:
    if x > left and x < right: cuts.add x
  cuts.sort(system.cmp[float])
  cuts.add right
  let need = width / 2 + 6
  var best = c.x
  var bestOff = Inf
  var widest = 0.0
  var origin = left
  for cut in cuts:
    if cut - origin >= 2 * need:
      let x = min(max(c.x, origin + need), cut - need)
      if abs(x - c.x) < bestOff:
        bestOff = abs(x - c.x)
        best = x
    elif bestOff == Inf and cut - origin > widest:
      widest = cut - origin
      best = (origin + cut) / 2
    origin = cut
  best

proc leftLabel(label: Label, x, cy: float, attrs: string, icons: IconResolver): string =
  if label.lines.len < 2: return labelSvg(label, x + label.width / 2, cy, attrs, icons)
  for i in 0 ..< label.lines.len:
    result.add labelSvg(labelLine(label, i), x + label.widths[i] / 2, cy - label.height / 2 + lineMiddle(label, i),
                        attrs, icons)

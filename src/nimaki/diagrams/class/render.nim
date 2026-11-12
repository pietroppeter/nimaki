## port-of: src/diagrams/class/render.ts
## port-status: draft
##
## Port notes: an `End` keeps the edge whose route it changes (`route` in the TypeScript is the
## same array as the edge's; a Nim seq is a value). An annotation, a string or a label in
## the TypeScript, is an object with a flag. `mathText` returns `(found, label)`.
import std/[algorithm, options, sequtils, strutils, tables]
from std/math import ceil
import ../../js
import ../../layout/[components, compound, layered]
import ../../preprocess
import ../../svg/[builder, cluster, edges, ink, root, shapes, theme, title]
import ../../text/[entities, label, measurer]
import ../../types
import ../../util/[url, yaml]
import ../common/[fit_width, generics]
import db, graph, markers, members

const
  NODE_SEP = 40.0
  EDGE_SEP = 16.0
  RANK_SEP = 56.0
  GROUP_PAD = 20.0
  LOOP = 26.0
  PAD_X = 12.0
  TITLE_PAD = 8.0
  SECTION_PAD = 6.0
  EMPTY_SECTION = 10.0
  MIN_WIDTH = 64.0
  FOLD = 8.0
  LINE = "var(--_l)"
  TARGETS = ["_self", "_blank", "_parent", "_top"]

proc numberOption(config: Config, key: string, fallback: float): float =
  let value = config[key]
  if value != nil and value.kind == yNumber and value.n > 0: min(value.n, 2000.0) else: fallback

type
  MemberLine = object
    text: string
    width: float
    classifier: string

  Annotation = object
    ## Pele's `string | Label`: the text, or the label when it holds math.
    isLabel: bool
    text: string
    label: Label

  View = ref object
    node: GraphNode
    style: ResolvedStyle
    label: Label
    w, h: float
    loops: int
    annotations: seq[Annotation]
    attributes: seq[MemberLine]
    methods: seq[MemberLine]
    titleH: float
    attributesH: float
    fontSize: float

  End = ref object
    edge: CEdge
    at: int
    toward: float
    order: int
    room: float
    side: int
    after: bool
      ## Whether the text of this end goes on the right of, or below, its line.

  Card = object
    text: string
    hasMath: bool
    math: Label
    x, y, w, h: float
    parent: int

proc memberLine(member: ClassMember, measurer: TextMeasurer, size: float, mono: bool): MemberLine =
  let text = jsTrim(decodeEntities(member.getDisplayDetails().displayText))
  let style = (if member.classifier == "*": Italic else: 0) or (if mono: Mono else: 0)
  MemberLine(text: text, width: measurer.width(text, size, style), classifier: member.classifier)

func stripDefault(s: string): string =
  ## s.replace(/^default\s?/, '')
  if not s.startsWith("default"): return s
  if isJsSpaceAt(s, 7): s.substr(7 + spaceLenAt(s, 7)) else: s.substr(7)

func hasFontFamily(text: string): bool =
  ## /[";]font-family:/.test(text)
  "\"font-family:" in text or ";font-family:" in text

func escapeAngles(s: string): string =
  ## s.replace(/</g, '&lt;').replace(/>/g, '&gt;')
  s.replace("<", "&lt;").replace(">", "&gt;")

proc draw(db: ClassDb, config: Config, options: RenderOptions, turned, tight: bool): Rendered

proc renderClass*(db: ClassDb, config: Config, options: RenderOptions): Rendered =
  let fitted = proc (down: bool): Rendered =
    tighten(options, proc (tight: bool): Rendered = draw(db, config, options, down, tight))
  if runsAcross(db.direction): turnToFit(options, fitted) else: fitted(false)

# `turned` draws a diagram that runs across as one that runs down. `tight` gives up the room
# that keeps a namespace's name clear of an edge coming in beside it.
proc draw(db: ClassDb, config: Config, options: RenderOptions, turned, tight: bool): Rendered =
  let own = config["class"]
  let conf: Config = if own != nil: own else: nil
  let hier = conf["hierarchicalNamespaces"]
  let graph = buildClassGraph(db, not (hier != nil and hier.kind == yBool and not hier.b))
  let hideOpt = conf["hideEmptyMembersBox"]
  let hideEmpty = hideOpt != nil and hideOpt.kind == yBool and hideOpt.b
  let monospaced = "members" in options.monospace
  # Explicit class fonts override monospace.
  proc mono(style: ResolvedStyle): bool = monospaced and not hasFontFamily(style.text)
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.8)
  let tinyHeight = jsRound(tiny * 1.4)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  # Keep annotations and cardinalities literal unless math is typeset.
  proc mathText(raw: string, fontSize: float): (bool, Label) =
    if "$$" notin raw: return (false, Label())
    let label = layoutLabel(raw, false, measurer, fontSize, 4000)
    for line in label.lines:
      if hasMath(line): return (true, label)
    (false, Label())
  proc cardWidth(raw: string): float =
    if raw == "": return 0
    let (found, label) = mathText(raw, tiny)
    if found: label.width else: measurer.width(decodeEntities(raw), tiny, 0)
  let rootDir = if turned: "TB" else: direction(db.direction)

  # A class may carry the declarations of many classDefs many times over. Each distinct declaration
  # is checked once, and only the last value of each property that has an effect is resolved.
  var effect = initTable[string, string]()
  var fromDefs = initTable[string, seq[(string, string)]]()
  var kept = initOrderedTable[string, string]()
  proc keep(decl: string) =
    var prop: string
    if decl in effect: prop = effect[decl]
    else:
      let one = resolveStyle(@[decl])
      if one.shape == "" and one.text == "": prop = ""
      else:
        let colon = decl.find(':')
        # slice(0, -1) when there is no colon
        prop = toLowerAscii(jsTrim(decl[0 ..< (if colon >= 0: colon else: decl.len - 1)]))
      effect[decl] = prop
    if prop != "": kept[prop] = decl
  proc classStyle(cls: ClassNode): ResolvedStyle =
    kept.clear()
    if cls.cssClasses notin fromDefs:
      for name in cls.cssClasses.split(' '):
        let def = db.styleClasses.getOrDefault(name, nil)
        if def != nil:
          for s in def.styles:
            for part in s.split(','): keep(part)
      var base: seq[(string, string)]
      for prop, decl in kept: base.add (prop, decl)
      fromDefs[cls.cssClasses] = base
    else:
      for (prop, decl) in fromDefs[cls.cssClasses]: kept[prop] = decl
    for s in cls.styles: keep(s)
    var decls: seq[string]
    for decl in kept.values: decls.add decl
    resolveStyle(decls)

  var children = newSeq[int](graph.nodes.len)
  for node in graph.nodes:
    if node.parent >= 0: inc children[node.parent]

  # Namespaces that an edge may cross into are made wide enough for the title to sit beside it.
  var crossed = newSeq[uint8](graph.nodes.len)
  for edge in graph.edges:
    if edge.source < 0 or edge.target < 0: continue
    let a = graph.nodes[edge.source].parent
    let b = graph.nodes[edge.target].parent
    if a == b: continue
    var g = a
    while g >= 0 and crossed[g] == 0:
      crossed[g] = 1
      g = graph.nodes[g].parent
    g = b
    while g >= 0 and crossed[g] == 0:
      crossed[g] = 1
      g = graph.nodes[g].parent

  proc base(node: GraphNode, label: Label, w, h, fontSize: float): View =
    View(node: node, style: resolveStyle(@[]), label: label, w: w, h: h, loops: 0, fontSize: fontSize)

  proc classView(node: GraphNode, cls: ClassNode): View =
    let style = classStyle(cls)
    let fontSize = if style.fontSize != 0: style.fontSize else: size
    let memberSize = jsRound(fontSize * 0.875)
    let lineHeight = jsRound(memberSize * 1.5)
    # The generic type is escaped so that `<T>` is not read as a tag.
    let generic = if cls.kind != "": "&lt;" & escapeAngles(parseGenericTypes(cls.kind)) & "&gt;" else: ""
    let label = layoutLabel(cls.label & generic, false, measurer, fontSize, 4000,
                            Bold or (if style.italic: Italic else: 0))
    var annotations: seq[Annotation]
    for a in cls.annotations:
      let (found, math) = mathText("«" & jsTrim(a) & "»", tiny)
      annotations.add(if found: Annotation(isLabel: true, label: math)
                      else: Annotation(text: "«" & jsTrim(decodeEntities(a)) & "»"))
    var attributes: seq[MemberLine]
    for m in cls.members: attributes.add memberLine(m, measurer, memberSize, mono(style))
    var methods: seq[MemberLine]
    for m in cls.methods: methods.add memberLine(m, measurer, memberSize, mono(style))
    var inner = label.width
    var annotationsH = 0.0
    for a in annotations:
      inner = max(inner, if not a.isLabel: measurer.width(a.text, tiny, 0) else: a.label.width)
      annotationsH += (if not a.isLabel: tinyHeight else: max(tinyHeight, a.label.height))
    for line in attributes: inner = max(inner, line.width)
    for line in methods: inner = max(inner, line.width)
    let sections = not (hideEmpty and attributes.len == 0 and methods.len == 0)
    proc section(count: int): float =
      if not sections: 0.0 elif count > 0: 2 * SECTION_PAD + float(count) * lineHeight else: EMPTY_SECTION
    let titleH = 2 * TITLE_PAD + annotationsH + max(label.height, jsRound(fontSize * 1.5))
    let attributesH = section(attributes.len)
    View(node: node, style: style, label: label, w: max(inner + 2 * PAD_X, MIN_WIDTH),
         h: titleH + attributesH + section(methods.len), loops: 0, annotations: annotations,
         attributes: attributes, methods: methods, titleH: titleH, attributesH: attributesH,
         fontSize: fontSize)

  var views: seq[View]
  var cnodes: seq[CNode]
  for i, node in graph.nodes:
    var view: View
    var c: CNode
    if node.isGroup:
      let label = layoutLabel(node.label, false, measurer, size, 4000)
      view = base(node, label, 0, 0, size)
      if children[i] > 0:
        c = cnode(0, 0)
        c.isGroup = true
        c.padX = GROUP_PAD
        c.padTop = if label.height > 0: label.height + 16 else: GROUP_PAD
        c.padBottom = GROUP_PAD
        c.minW = label.width + 2 * GROUP_PAD - 12 +
          (if crossed[i] == 1 and not tight: min(label.width + 24, 240.0) else: 0.0)
      else:
        view.w = max(label.width + 2 * GROUP_PAD, 80.0)
        view.h = label.height + 2 * GROUP_PAD
        c = cnode(view.w, view.h)
    elif node.classNode != nil:
      view = classView(node, node.classNode)
      c = cnode(view.w, view.h)
    elif node.shape == "note":
      let label = layoutLabel(node.label, true, measurer, small, 260)
      view = base(node, label, max(label.width + 2 * PAD_X, 40.0), label.height + 2 * TITLE_PAD, small)
      c = cnode(view.w, view.h)
    else:
      let label = layoutLabel(node.label, false, measurer, small, 200)
      view = base(node, label, max(label.width, 12.0) + 4, max(label.height, 12.0), small)
      c = cnode(view.w, view.h)
    c.parent = node.parent
    c.seq = float(i)
    views.add view
    cnodes.add c

  var cedges: seq[CEdge]
  var drawn: seq[GraphEdge]
  var edgeLabels: seq[Label]
  var startRoom: seq[float]
  var endRoom: seq[float]
  # Edges leave one side of a class and arrive at the other, so a class with many of them
  # is widened until they, and the text at their ends, fit side by side.
  var crowd = newSeq[float](views.len * 4)
  proc meet(item, slot: int, room: float) =
    crowd[item * 4 + slot] += 1
    if room > crowd[item * 4 + slot + 1]: crowd[item * 4 + slot + 1] = room
  for edge in graph.edges:
    if edge.source < 0 or edge.target < 0: continue
    let label = layoutLabel(edge.label, true, measurer, small, 200)
    let startW = cardWidth(edge.startLabelRight)
    let endW = cardWidth(edge.endLabelLeft)
    if edge.source == edge.target:
      inc views[edge.source].loops
      cnodes[edge.source].w += 2 * (LOOP + (if label.width > 0: label.width + 12 else: 0))
    else:
      meet(edge.source, 0, startW)
      meet(edge.target, 2, endW)
    startRoom.add startW
    endRoom.add endW
    drawn.add edge
    edgeLabels.add label
    cedges.add CEdge(src: edge.source, dst: edge.target, minlen: 1,
                     labelW: (if label.width > 0: label.width + 12 else: 0),
                     labelH: (if label.height > 0: label.height + 4 else: 0),
                     route: @[], labelX: 0, labelY: 0)

  if rootDir == "TB" or rootDir == "BT":
    for i in 0 ..< views.len:
      if views[i].node.classNode == nil: continue
      var need = 0.0
      for slot in countup(0, 2, 2):
        let count = crowd[i * 4 + slot]
        let room = crowd[i * 4 + slot + 1]
        if count > 1: need = max(need, (count - 1) * (if room > 0: room + 24 else: 14.0) + 24)
      need = min(need, 480.0)
      if need > views[i].w:
        cnodes[i].w += need - views[i].w
        views[i].w = need

  var lettered = false
  for i in 0 ..< drawn.len:
    if lettered: break
    lettered = startRoom[i] > 0 or endRoom[i] > 0
  # Cardinalities at both ends of a vertical edge need room for their height between the ranks.
  var tallCards = 0.0
  if rootDir == "TB" or rootDir == "BT":
    proc cardHeight(raw: string): float =
      if raw == "": return 0
      let (found, math) = mathText(raw, tiny)
      max(tinyHeight, if found: math.height else: 0.0)
    for edge in drawn:
      tallCards = max(tallCards, cardHeight(edge.startLabelRight) + cardHeight(edge.endLabelLeft) - 2 * tinyHeight)
  let layout = compoundLayout(cnodes, cedges, rootDir, LayeredOptions(
    nodeSep: numberOption(conf, "nodeSpacing", NODE_SEP),
    edgeSep: EDGE_SEP,
    rankSep: numberOption(conf, "rankSpacing", if lettered: RANK_SEP + 16 else: RANK_SEP) + tallCards,
    portSep: 20,
    apart: true))

  # Every edge reaches the middle of a side. Where several share a side they are spread along it,
  # in the order of where they come from. An end with text runs straight for the length of the text,
  # which sits beside it on the side the line then bends toward, away from the neighbors that bend
  # the other way. Neighbors are set apart far enough for the text between them.
  var sides = initOrderedTable[int, seq[End]]()
  var cards: seq[Card]
  proc attach(ce: CEdge, at, item: int, room: float, order: int): End =
    let c = cnodes[item]
    let side = endSide(ce.route, at, c)
    if side < 0: return nil
    let slack = (c.w - views[item].w) / 2
    if side == 1: ce.route[at] -= slack
    elif side == 3: ce.route[at] += slack
    let across = side and 1
    let toward = ce.route[(if at == 0: 3 else: at - 3) + across]
    let bend = toward - ce.route[at + across]
    let e = End(edge: ce, at: at, toward: toward, order: order, room: room, side: side,
                after: (if across != 0: bend > 0 else: bend >= 0))
    let key = item * 4 + side
    if key in sides: sides[key].add e
    else: sides[key] = @[e]
    e
  var starts: seq[End]
  var ends: seq[End]
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let routed = ce.src != ce.dst and ce.route.len >= 6
    starts.add(if routed: attach(ce, 0, ce.src, startRoom[i], i) else: nil)
    ends.add(if routed: attach(ce, ce.route.len - 3, ce.dst, endRoom[i], i) else: nil)
  # Whether a point lies on the border of one of the namespaces around a class.
  proc onBorder(item: int, x, y: float): bool =
    var g = cnodes[item].parent
    var hops = 0
    while g >= 0 and hops < 10000:
      let c = cnodes[g]
      let dx = abs(x - c.x)
      let dy = abs(y - c.y)
      if (abs(dy - c.h / 2) < 0.5 and dx <= c.w / 2 + 0.5) or (abs(dx - c.w / 2) < 0.5 and dy <= c.h / 2 + 0.5):
        return true
      g = cnodes[g].parent
      inc hops
    false
  var gaps: seq[float]
  for key, list in sides.mpairs:
    if list.len < 2: continue
    let item = key shr 2
    let across = key and 1
    let length = if across != 0: views[item].h else: views[item].w
    list.sort(proc (a, b: End): int = orElse(a.toward - b.toward, a.order - b.order))
    var total = 0.0
    for j in 0 ..< list.len - 1:
      let a = list[j]
      let b = list[j + 1]
      var gap = if across != 0: 20.0 else: 24.0
      if a.room > 0 and a.after: gap += (if across != 0: tinyHeight + 6 else: a.room)
      if b.room > 0 and not b.after: gap += (if across != 0: tinyHeight + 6 else: b.room)
      if gaps.len <= j: gaps.setLen(j + 1)
      gaps[j] = gap
      total += gap
    let scale = min(1.0, (length - 24) / total)
    if scale <= 0: continue
    var at = (if across != 0: cnodes[item].y else: cnodes[item].x) - (total * scale) / 2
    for j in 0 ..< list.len:
      let ce = list[j].edge
      let stop = list[j].at
      # An edge that crosses the border of the class's namespace close by runs straight to it:
      # the point where it crosses moves into line with its end.
      let step = if stop == 0: 3 else: -3
      let first = stop + step
      var border = -1
      var k = first
      while k >= 0 and k < ce.route.len and abs(ce.route[k + across] - ce.route[first + across]) < 0.5:
        if onBorder(item, ce.route[k], ce.route[k + 1]):
          border = k
          break
        k += step
      if border >= 0 and abs(ce.route[first + across] - at) <= 24:
        k = first
        while k != border + step:
          ce.route[k + across] = at
          k += step
      ce.route[stop + across] = at
      # The last step reads past the gaps of this side (undefined in the TypeScript); its result is not used.
      if j < list.len - 1: at += gaps[j] * scale

  proc straighten(ce: CEdge, e: End, room: float, first: bool) =
    if e == nil or room <= 0: return
    let across = e.side and 1
    let at = if first: 0 else: ce.route.len - 3
    let along = at + 1 - across
    let reach = abs(ce.route[(if first: 3 else: at - 3) + 1 - across] - ce.route[along])
    let length = min(if across != 0: room + 10 else: tinyHeight + 6, reach * 0.35)
    if length < 4: return
    var point = [ce.route[at], ce.route[at + 1], ce.route[at + 2]]
    point[1 - across] += (if e.side == 0 or e.side == 3: -1.0 else: 1.0) * length
    ce.route.insert(point, if first: 3 else: at)
  for i in 0 ..< cedges.len:
    straighten(cedges[i], starts[i], startRoom[i], true)
    straighten(cedges[i], ends[i], endRoom[i], false)

  var minX = 0.0
  var minY = 0.0
  var maxX = layout.width
  var maxY = layout.height
  proc card(parent: int, raw: string, width, x, y: float, side: int, after: bool) =
    if raw == "": return
    let (found, math) = mathText(raw, tiny)
    let h = if found: max(tinyHeight, math.height) else: tinyHeight
    var cx = x
    var cy = y
    if (side and 1) != 0:
      cx += (if side == 3: -1.0 else: 1.0) * (5 + width / 2)
      cy += (if after: 1.0 else: -1.0) * (7 + h / 2)
    else:
      cx += (if after: 1.0 else: -1.0) * (9 + width / 2)
      cy += (if side == 0: -1.0 else: 1.0) * (3 + h / 2)
    cards.add Card(text: decodeEntities(raw), hasMath: found, math: math, x: cx, y: cy, w: width, h: h,
                   parent: parent)
    minX = min(minX, cx - width / 2)
    maxX = max(maxX, cx + width / 2)
    minY = min(minY, cy - h / 2)
    maxY = max(maxY, cy + h / 2)
  var loopSeen = initTable[int, int]()
  var loopAt = newSeq[int](cedges.len)
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    if ce.src == ce.dst:
      let k = loopSeen.getOrDefault(ce.src, 0)
      loopSeen[ce.src] = k + 1
      loopAt[i] = k
      let c = cnodes[ce.src]
      let view = views[ce.src]
      let x = c.x + view.w / 2
      let spread = min(view.h / 2 - 4, 8 + float(k) * 6)
      card(ce.src, edge.startLabelRight, startRoom[i], x, c.y - spread, 1, false)
      card(ce.dst, edge.endLabelLeft, endRoom[i], x, c.y + spread, 1, true)
      ce.labelX = c.x + view.w / 2 + LOOP + float(k) * 8 + 4 + ce.labelW / 2
      ce.labelY = c.y
    elif ce.route.len >= 6:
      let last = ce.route.len - 3
      let fromEnd = starts[i]
      let toEnd = ends[i]
      card(ce.src, edge.startLabelRight, startRoom[i], ce.route[0], ce.route[1],
           (if fromEnd != nil: fromEnd.side else: 2), (if fromEnd != nil: fromEnd.after else: true))
      card(ce.dst, edge.endLabelLeft, endRoom[i], ce.route[last], ce.route[last + 1],
           (if toEnd != nil: toEnd.side else: 0), (if toEnd != nil: toEnd.after else: true))

  if options.maxWidth.isSome:
    let available = options.maxWidth.get
    if available > 0 and maxX - minX + 2 * pad > available:
      var cardNodes: seq[CNode]
      for item in cards:
        let c = cnode(item.w, item.h, item.parent)
        c.x = item.x
        c.y = item.y
        cardNodes.add c
      let wrapped = wrapComponents(cnodes & cardNodes, cedges, max(1.0, available - 2 * pad),
                                   numberOption(conf, "nodeSpacing", NODE_SEP))
      if wrapped.isSome:
        for i in 0 ..< cards.len:
          cards[i].x = cardNodes[i].x
          cards[i].y = cardNodes[i].y
        minX = 0
        minY = 0
        maxX = wrapped.get.width
        maxY = wrapped.get.height

  let ox = pad - minX
  let oy = pad - minY
  let width = ceil(maxX - minX + 2 * pad)
  let height = ceil(maxY - minY + 2 * pad)
  var links: seq[LinkInfo]

  var crossings: Crossings = initTable[int, seq[float]]()
  if graph.nodes.len > 0 and graph.nodes[0].isGroup:
    for e in cedges: markCrossings(crossings, e.route)

  proc classSvg(view: View, cls: ClassNode, id, at: string): string =
    let w = view.w
    let h = view.h
    let style = view.style
    let left = -w / 2
    let top = -h / 2
    let memberSize = jsRound(view.fontSize * 0.875)
    let lineHeight = jsRound(memberSize * 1.5)
    var body = "<rect x=\"" & num(left) & "\" y=\"" & num(top) & "\" width=\"" & num(w) & "\" height=\"" &
      num(h) & "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & rounded(style.shape) & "/>"
    let ink = inkFill(style.shape, style.text)
    let first = top + view.titleH
    let second = first + view.attributesH
    if h > view.titleH:
      let stroke = if style.stroke != "": " style=\"stroke:" & esc(style.stroke) & "\"" else: ""
      body.add "<path class=\"pele-divider\" d=\"M" & num(left) & "," & num(first) & "H" & num(-left) & "M" &
        num(left) & "," & num(second) & "H" & num(-left) & "\" fill=\"none\" stroke=\"var(--_b)\"" & stroke & "/>"
    var y = top + TITLE_PAD
    let annotationInk = if ink != "": ink else: " fill=\"var(--_m)\""
    for annotation in view.annotations:
      if not annotation.isLabel:
        body.add "<text class=\"pele-annotation\" x=\"0\" y=\"" & num(y + tinyHeight / 2 + tiny * 0.35) &
          "\" text-anchor=\"middle\" font-size=\"" & jsString(tiny) & "\"" & annotationInk & ">" &
          esc(annotation.text) & "</text>"
        y += tinyHeight
      else:
        let ah = max(tinyHeight, annotation.label.height)
        body.add labelSvg(annotation.label, 0, y + ah / 2, " class=\"pele-annotation\" font-size=\"" &
                          jsString(tiny) & "\"" & annotationInk, icons)
        y += ah
    let titleSize = if view.fontSize == size: "" else: " font-size=\"" & num(view.fontSize) & "\""
    body.add labelSvg(view.label, 0, (y + first - TITLE_PAD) / 2, " class=\"pele-label\"" & titleSize &
                      " font-weight=\"var(--_hw)\"" & ink & style.text, icons)
    proc lines(list: seq[MemberLine], kind: string, start: float): string =
      var baseline = start + SECTION_PAD + lineHeight / 2 + memberSize * 0.35
      for line in list:
        let mark =
          if line.classifier == "$":
            " pele-static\"" & (if style.text != "": style.text[0 ..< ^1] & "text-decoration:underline\""
                                 else: " style=\"text-decoration:underline\"")
          elif line.classifier == "*": " pele-abstract\" font-style=\"italic\"" & style.text
          else: "\"" & style.text
        result.add "<text class=\"pele-member pele-" & kind & mark & " x=\"" & num(left + PAD_X) & "\" y=\"" &
          num(baseline) & "\">" & esc(line.text) & "</text>"
        baseline += lineHeight
    if view.attributes.len > 0 or view.methods.len > 0:
      body.add "<g class=\"pele-members\" font-size=\"" & jsString(memberSize) & "\"" & ink &
        (if mono(style): " font-family=\"" & FONT_MONO & "\"" else: "") & ">" &
        lines(view.attributes, "attribute", first) & lines(view.methods, "method", second) & "</g>"
    if cls.tooltip != "": body = "<title>" & escText(cls.tooltip) & "</title>" & body
    if cls.link != "":
      body = linked(body, cls.link, cls.id, links, options,
                    if cls.linkTarget != "" and cls.linkTarget in TARGETS: " target=\"" & cls.linkTarget & "\"" else: "")
    "<g class=\"pele-node pele-class" & classNames(stripDefault(cls.cssClasses)) & "\" data-id=\"" & id & "\"" &
      at & ">" & body & "</g>"

  var clusters = ""
  var struckTitles = ""
  var nodesOut = ""
  for i in 0 ..< views.len:
    let view = views[i]
    let c = cnodes[i]
    let node = view.node
    let x = c.x + ox
    let y = c.y + oy
    let id = escText(node.id)
    let w = if c.isGroup: c.w else: view.w
    let h = if c.isGroup: c.h else: view.h
    if node.isGroup:
      let titleX = if c.isGroup: clusterTitleX(c, view.label.width, crossings, GROUP_PAD) else: c.x
      let titleY = y - h / 2 + 8 + view.label.height / 2
      let titleAttrs = " class=\"pele-cluster-label\" fill=\"var(--_m)\""
      let struck = c.isGroup and titleCrossed(c, view.label.width, titleX, crossings)
      if struck: struckTitles.add struckTitle(view.label, titleX + ox, titleY, titleAttrs, id, cnodes, i)
      clusters.add "<g class=\"pele-cluster pele-namespace\" data-id=\"" & id & "\">" &
        "<rect x=\"" & num(x - w / 2) & "\" y=\"" & num(y - h / 2) & "\" width=\"" & num(w) & "\" height=\"" &
        num(h) & "\" fill=\"var(--_a)\" fill-opacity=\"0.5\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
        (if struck: "" else: labelSvg(view.label, titleX + ox, titleY, titleAttrs)) &
        "</g>"
      continue
    let at = " transform=\"translate(" & num(x) & "," & num(y) & ")\""
    if node.classNode != nil:
      nodesOut.add classSvg(view, node.classNode, id, at)
    elif node.shape == "note":
      let r = w / 2
      let t = -h / 2
      nodesOut.add "<g class=\"pele-node pele-note\" data-id=\"" & id & "\"" & at & ">" &
        "<path d=\"M" & num(-r) & "," & num(t) & "H" & num(r - FOLD) & "L" & num(r) & "," & num(t + FOLD) & "V" &
        num(-t) & "H" & num(-r) & "Z\" fill=\"var(--_a)\" stroke=\"var(--_b)\" stroke-linejoin=\"round\"/>" &
        "<path d=\"M" & num(r - FOLD) & "," & num(t) & "V" & num(t + FOLD) & "H" & num(r) &
        "\" fill=\"none\" stroke=\"var(--_b)\" stroke-linejoin=\"round\"/>" &
        labelSvg(view.label, 0, 0, " class=\"pele-label\" font-size=\"" & jsString(small) & "\"", icons) &
        "</g>"
    else:
      nodesOut.add "<g class=\"pele-node pele-interface\" data-id=\"" & id & "\"" & at & ">" &
        labelSvg(view.label, 0, 0, " class=\"pele-label\" font-size=\"" & jsString(small) & "\"", icons) &
        "</g>"

  var edgesOut = ""
  var labelsOut = ""
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    let startType = edge.arrowTypeStart
    let endType = edge.arrowTypeEnd
    let startTrim = classMarkerTrim(startType)
    let endTrim = classMarkerTrim(endType)
    var path: EdgePath
    if ce.src == ce.dst:
      let c = cnodes[ce.src]
      let view = views[ce.src]
      let k = float(loopAt[i])
      let x = c.x + ox + view.w / 2
      let y = c.y + oy
      let spread = min(view.h / 2 - 4, 8 + k * 6)
      let reach = LOOP + k * 8
      path = EdgePath(
        d: "M" & num(x + startTrim) & "," & num(y - spread) & "C" & num(x + reach + startTrim) & "," &
          num(y - spread) & " " & num(x + reach + endTrim) & "," & num(y + spread) & " " & num(x + endTrim) &
          "," & num(y + spread),
        sx: x, sy: y - spread, sdx: -1, sdy: 0, ex: x, ey: y + spread, edx: -1, edy: 0)
    else:
      for k in countup(0, ce.route.len - 1, 3):
        ce.route[k] += ox
        ce.route[k + 1] += oy
      path = routePath(ce.route, "", startTrim, endTrim)
    let attrs = if edge.pattern == "dashed": " stroke-dasharray=\"6 4\""
                elif edge.pattern == "dotted": " stroke-dasharray=\"2 4\""
                else: ""
    edgesOut.add "<g class=\"pele-edge" & (if edge.pattern == "dotted": " pele-note-edge" else: " pele-relation") &
      "\" data-id=\"" & escText(edge.id) & "\">" &
      "<path d=\"" & path.d & "\"" & attrs & "/>" &
      classMarker(startType, path.sx, path.sy, path.sdx, path.sdy, LINE) &
      classMarker(endType, path.ex, path.ey, path.edx, path.edy, LINE) &
      "</g>"
    if label.width > 0:
      labelsOut.add edgeLabelSvg(edge.id, label, ce.labelX + ox, ce.labelY + oy, "", icons)

  var cardsOut = ""
  for item in cards:
    cardsOut.add(
      if item.hasMath: labelSvg(item.math, item.x + ox, item.y + oy, " class=\"pele-cardinality\"", icons)
      else: "<text class=\"pele-cardinality\" x=\"" & num(item.x + ox) & "\" y=\"" & num(item.y + oy + tiny * 0.35) &
        "\" text-anchor=\"middle\">" & esc(item.text) & "</text>")

  let titled = withTitle(
    db.title, measurer, size, pad, width, height,
    (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"" & LINE & "\" stroke-linecap=\"round\">" & edgesOut & "</g>" else: "") &
      (if struckTitles != "": "<g class=\"pele-cluster-titles\">" & struckTitles & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\">" & labelsOut & "</g>" else: "") &
      (if cardsOut != "": "<g class=\"pele-cardinalities\" font-size=\"" & jsString(tiny) & "\" fill=\"var(--_m)\">" & cardsOut & "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & "</g>")
  let svg = svgDocument("class", titled.width, titled.height, size, options,
                        Accessible(accTitle: db.accTitle, accDescr: db.accDescr), titled.content)
  Rendered(svg: svg, width: titled.width, height: titled.height, links: links)

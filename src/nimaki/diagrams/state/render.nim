## port-of: src/diagrams/state/render.ts
## port-status: draft
import std/[algorithm, options, strutils, tables]
from std/math import ceil
import ../../js
import ../../jsmath
import ../../layout/[compound, layered]
import ../../preprocess
import ../../svg/[builder, edges, ink, root, shapes, theme, title]
import ../../text/[entities, label, measurer]
import ../../types
import ../../util/[url, yaml]
import ../common/fit_width
import db, graph

const
  NODE_SEP = 40.0
  EDGE_SEP = 16.0
  RANK_SEP = 44.0
  GROUP_PAD = 16.0
  REGION_PAD = 10.0
  PAD_X = 16.0
  PAD_Y = 10.0
  LOOP = 26.0
  FOLD = 8.0
  NOTE_WRAP = 320.0
  CORNER = 10.0
  BAR = 8.0
  SURFACE = " fill=\"var(--_s)\" stroke=\"var(--_b)\""
  RULE = " fill=\"none\" stroke=\"var(--_b)\""

type K = enum
  kState, kDescribed, kStart, kEnd, kChoice, kFork, kJoin, kNote, kComposite, kRegion, kHidden

func kindOf(shape: string): K =
  ## KINDS.get(shape) ?? K.State
  case shape
  of "rectWithTitle": kDescribed
  of "stateStart": kStart
  of "stateEnd": kEnd
  of "choice": kChoice
  of "fork": kFork
  of "join": kJoin
  of "note": kNote
  of "divider": kHidden
  else: kState

const CLASSES: array[kState .. kComposite, string] = [
  "pele-node pele-state",
  "pele-node pele-state",
  "pele-node pele-state-start",
  "pele-node pele-state-end",
  "pele-node pele-state-choice",
  "pele-node pele-state-fork",
  "pele-node pele-state-join",
  "pele-note",
  "pele-cluster pele-state-composite",
]

func withoutMermaidClasses(s: string): string =
  ## s.replace(/(?:^| )statediagram-(?:state|cluster-alt|cluster|note)(?= |$)/g, '')
  const names = ["state", "cluster-alt", "cluster", "note"]
  proc matchAt(s: string, p: int): int =
    if not s.continuesWith("statediagram-", p): return -1
    let q = p + "statediagram-".len
    for name in names:
      let e = q + name.len
      if s.continuesWith(name, q) and (e == s.len or s[e] == ' '): return e
    -1
  var i = 0
  while i < s.len:
    var e = -1
    if i == 0: e = matchAt(s, 0)
    if e < 0 and s[i] == ' ': e = matchAt(s, i + 1)
    if e >= 0:
      i = e
    else:
      result.add s[i]
      inc i

type View = ref object
  node: StateNode            ## nil for the unseen helpers the layout needs
  kind: K
  style: ResolvedStyle
  hasStyle: bool
  label: Label
  lines: seq[Label]
  w, h: float
  titleH: float

func vertical(dir: Dir): bool = dir == "TB" or dir == "BT"

proc numberOption(config: Config, key: string, fallback: float): float =
  let value = config["state"][key]
  if value != nil and value.kind == yNumber and value.n > 0: min(value.n, 2000.0) else: fallback

func unquote(text: string): string =
  ## Mermaid keeps the quotes of a click statement's strings and strips them when it draws.
  var a = 0
  var b = text.len
  while a < b and text[a] == '"': inc a
  while b > a and text[b - 1] == '"': dec b
  text[a ..< b]

func clamp(value, lo, hi: float): float =
  if value < lo: lo elif value > hi: hi else: value

func jsSign(x: float): float =
  if x > 0: 1.0 elif x < 0: -1.0 else: x

proc rect(x, y, w, h: float, rest: string): string =
  "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\"" & rest & "/>"

proc group(dir: Dir, padX, padTop, padBottom: float): CNode =
  result = cnode(0, 0)
  result.isGroup = true
  result.dir = dir
  result.padX = padX
  result.padTop = padTop
  result.padBottom = padBottom

proc titleX(c: CNode, width: float, crossings: Table[int, seq[float]]): float

proc draw(db: StateDb, config: Config, options: RenderOptions, turned: bool): Rendered

proc renderState*(db: StateDb, config: Config, options: RenderOptions): Rendered =
  if not runsAcross(db.direction): return draw(db, config, options, false)
  turnToFit(options, proc (down: bool): Rendered = draw(db, config, options, down))

# `turned` draws a diagram that runs across as one that runs down.
proc draw(db: StateDb, config: Config, options: RenderOptions, turned: bool): Rendered =
  let graph = db.graph
  # State diagrams follow the flowchart curve.
  let curveOpt = config["flowchart"]["curve"]
  let curve = if curveOpt != nil and curveOpt.kind == yString: curveOpt.s else: ""
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let wrapWidth = numberOption(config, "wrappingWidth", 200)
  let pad = options.padding.get(8)
  let icons = options.icons
  let rootDir = if turned: "TB" else: direction(db.direction)
  let noLabel = layoutLabel("", false, measurer, size, 0)
  proc text(raw: string, fontSize, wrap: float, style = 0): Label =
    layoutLabel(raw, true, measurer, fontSize, wrap, style)

  var index = initTable[string, int]()
  var views: seq[View]
  var cnodes: seq[CNode]
  proc addView(node: StateNode, kind: K, c: CNode): int =
    views.add View(node: node, kind: kind, label: noLabel)
    if c != nil: cnodes.add c
    views.len - 1
  for node in graph.nodes:
    if node.shape == "noteGroup": continue
    let kind =
      if node.isGroup: (if node.shape == "divider": kRegion else: kComposite)
      else: kindOf(node.shape)
    index[node.id] = addView(node, kind, nil)
  let states = views.len

  var logical: seq[int]
  for i in 0 ..< states:
    let parentId = views[i].node.parentId
    let parent = if parentId.isNone: -1 else: index.getOrDefault(parentId.get, -1)
    logical.add(if parent != -1 and parent != i and views[parent].node.isGroup: parent else: -1)
  # Composites that are redeclared inside each other form a ring with no way in from the root.
  # One member of each ring moves to the root, which leaves a tree.
  block:
    var kids = newSeq[seq[int]](states)
    var queue: seq[int]
    var placed = newSeq[bool](states)
    for i in 0 ..< states:
      if logical[i] == -1:
        placed[i] = true
        queue.add i
      else:
        kids[logical[i]].add i
    var done = 0
    proc settle() =
      while done < queue.len:
        for kid in kids[queue[done]]:
          if placed[kid]: continue
          placed[kid] = true
          queue.add kid
        inc done
    settle()
    var seen = newSeq[int](states)
    for s in seen.mitems: s = -1
    for i in 0 ..< states:
      if placed[i]: continue
      var ring = i
      while seen[ring] != i:
        seen[ring] = i
        ring = logical[ring]
      logical[ring] = -1
      placed[ring] = true
      queue.add ring
      settle()
  var owners = newSeq[int](states)
  for i in 0 ..< states:
    owners[i] = -1
    let noteFor = views[i].node.noteFor
    let owner = if noteFor.isNone: -1 else: index.getOrDefault(noteFor.get, -1)
    if owner == -1: continue
    owners[i] = owner
    logical[i] = logical[owner]

  # As in Mermaid, a composite that sets no direction runs top to bottom whatever surrounds it.
  proc innerDir(composite: int): Dir = direction(views[composite].node.dir)
  # Whether the flow around a state runs top to bottom or bottom to top.
  proc across(i: int): bool = vertical(if logical[i] == -1: rootDir else: innerDir(logical[i]))

  var degree = newSeq[int](states)
  var noted = newSeq[bool](states)
  # When each state first takes part in a transition. Layout follows this order rather than
  # the order of declaration, so a state declared up front does not become the top of the flow.
  var appear = newSeq[float](states)
  for a in appear.mitems: a = Inf
  var appeared = 0
  var counts = newSeq[int](2 * states)
  for edge in graph.edges:
    let src = index.getOrDefault(edge.start, -1)
    let dst = index.getOrDefault(edge.stop, -1)
    if src == -1 or dst == -1: continue
    if edge.dashed:
      noted[if views[src].kind == kNote: dst else: src] = true
      continue
    inc counts[2 * src]
    degree[src] = max(degree[src], counts[2 * src])
    inc counts[2 * dst + 1]
    degree[dst] = max(degree[dst], counts[2 * dst + 1])
    if appear[src] == Inf:
      appear[src] = float(appeared)
      inc appeared
    if appear[dst] == Inf:
      appear[dst] = float(appeared)
      inc appeared

  for i in 0 ..< states:
    let view = views[i]
    let node = view.node
    let style = resolveStyle(
      if node.cssStyles.len > 0: node.cssCompiledStyles & node.cssStyles else: node.cssCompiledStyles)
    let textStyle = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let fontSize = if style.fontSize != 0: style.fontSize else: size
    view.style = style
    view.hasStyle = true
    var c: CNode = nil
    case view.kind
    of kComposite:
      view.label = text(node.label, fontSize, 4000, textStyle)
      view.titleH = if view.label.height > 0: view.label.height + 12 else: 0
      c = group(innerDir(i), GROUP_PAD, view.titleH + GROUP_PAD, GROUP_PAD)
      c.minW = view.label.width + 2 * GROUP_PAD
    of kRegion:
      c = group(innerDir(i), REGION_PAD, REGION_PAD, REGION_PAD)
    of kStart:
      view.w = 14
      view.h = 14
    of kEnd:
      view.w = 18
      view.h = 18
    of kChoice:
      view.w = 30
      view.h = 30
    of kFork, kJoin:
      let length = clamp(40.0 * float(degree[i]) + 16, 72, 320)
      view.w = if across(i): length else: BAR
      view.h = if across(i): BAR else: length
    of kHidden:
      discard
    of kNote:
      view.label = text(node.label, small, max(wrapWidth, NOTE_WRAP))
      view.w = view.label.width + 24
      view.h = view.label.height + 16
    of kState, kDescribed:
      view.label = text(node.label, fontSize, wrapWidth, textStyle)
      var width = view.label.width
      var height = view.label.height + 2 * PAD_Y
      if view.kind == kDescribed:
        height += 14
        for line in node.description:
          let label = text(if line == "": " " else: line, small, wrapWidth, textStyle)
          view.lines.add label
          if label.width > width: width = label.width
          height += label.height
      view.w = max(width + 2 * PAD_X, 56)
      view.h = height
    if c == nil: c = cnode(view.w, view.h)
    # The transitions on one side of a state's box spread along it, clear of its corners.
    if view.kind == kState or view.kind == kDescribed: c.span = (if across(i): view.w else: view.h) - 24
    cnodes.add c

  var cedges: seq[CEdge]
  var edgeLabels: seq[Label]
  var drawn: seq[StateEdge]
  # The transitions each state makes to itself: how many, their widest label, and their labels' height.
  var loopCount = newSeq[int](states)
  var loopWidth = newSeq[float](states)
  var loopHeight = newSeq[float](states)
  # A transition between a composite and a state inside it runs between that state and a point
  # just inside the composite, and is then drawn on to the composite's border.
  var anchors = initTable[int, int]()
  proc encloses(composite, item: int): bool =
    if not cnodes[composite].isGroup: return false
    var p = logical[item]
    while p != -1:
      if p == composite: return true
      p = logical[p]
    false
  proc anchor(composite: int, first: bool): int =
    anchors[cedges.len] = composite
    appear.add(if first: -1.0 else: Inf)
    addView(nil, kHidden, cnode(0, 0, composite))
  for edge in graph.edges:
    var src = index.getOrDefault(edge.start, -1)
    var dst = index.getOrDefault(edge.stop, -1)
    if src == -1 or dst == -1: continue
    let label = text(edge.label, small, wrapWidth)
    let labelW = if label.width > 0: label.width + 12 else: 0
    if src == dst:
      inc loopCount[src]
      loopWidth[src] = max(loopWidth[src], labelW)
      loopHeight[src] += label.height
    elif encloses(src, dst):
      src = anchor(src, true)
    elif encloses(dst, src):
      dst = anchor(dst, false)
    drawn.add edge
    edgeLabels.add label
    cedges.add CEdge(src: src, dst: dst, minlen: 1, labelW: labelW,
                     labelH: if label.height > 0: label.height + 4 else: 0, route: @[], labelX: 0, labelY: 0)

  # A state with notes, or a composite with self-transitions, sits in an unseen group of its
  # own: the notes go beside the state, across the flow, without disturbing its transitions.
  for i in 0 ..< states:
    if owners[i] != -1: continue
    let item = cnodes[i]
    # Loops hang off the right, or below when the flow is horizontal, with their labels beyond them.
    var room = 0.0
    if loopCount[i] > 0:
      let reach = LOOP + float(loopCount[i] - 1) * 8
      room = if across(i): reach + loopWidth[i] else: reach * 0.75 + 4 + loopHeight[i]
      if not item.isGroup:
        if across(i):
          item.w += 2 * room
          item.h = max(item.h, loopHeight[i])
        else:
          item.h += 2 * room
          item.w = max(item.w, loopWidth[i])
        room = 0
    if not noted[i] and room == 0:
      item.parent = logical[i]
      continue
    let c = if across(i): group("LR", room, 0, 0) else: group("TB", 0, room, room)
    c.parent = logical[i]
    appear.add appear[i]
    cnodes[i].parent = addView(nil, kHidden, c)
  for i in 0 ..< states:
    if owners[i] != -1: cnodes[i].parent = cnodes[owners[i]].parent

  block:
    # Numbers the tree so that, at every level, initial states come first and the rest follow
    # in the order the transitions introduce them.
    var members = newSeq[seq[int]](cnodes.len)
    var top: seq[int]
    for i in 0 ..< cnodes.len:
      let p = cnodes[i].parent
      if p >= 0: members[p].add i
      else: top.add i
    proc initial(i: int): int = (if views[i].kind == kStart: 0 else: 1)
    proc byFlow(a, b: int): int =
      let d = initial(a) - initial(b)
      if d != 0: return d
      if appear[a] != appear[b]: return (if appear[a] < appear[b]: -1 else: 1)
      a - b
    var s = 0
    top.sort(byFlow)
    var pending = top.reversed
    while pending.len > 0:
      let i = pending.pop()
      cnodes[i].seq = float(s)
      inc s
      members[i].sort(byFlow)
      for k in countdown(members[i].high, 0): pending.add members[i][k]

  let layout = compoundLayout(cnodes, cedges, rootDir, LayeredOptions(
    nodeSep: numberOption(config, "nodeSpacing", NODE_SEP),
    edgeSep: EDGE_SEP,
    rankSep: numberOption(config, "rankSpacing", RANK_SEP),
    portSep: 20,
    tracks: curve == "step" or curve == "stepBefore" or curve == "stepAfter",
    straight: curve == "linear",
    headRoom: markerTrim("arrow_point"),
  ))

  let width = ceil(layout.width + 2 * pad)
  let height = ceil(layout.height + 2 * pad)
  var links: seq[LinkInfo]

  # Route points by rounded y, to find the edges that cross a composite's title bar.
  var crossings = initTable[int, seq[float]]()
  for e in cedges:
    let route = e.route
    var k = 3
    while k < route.len - 3:
      crossings.mgetOrPut(int(jsRound(route[k + 1])), @[]).add route[k]
      k += 3

  var children = newSeq[seq[int]](cnodes.len)
  var order: seq[int]
  for i in 0 ..< cnodes.len:
    let p = cnodes[i].parent
    if p >= 0: children[p].add i
    else: order.add i
  let roots = order
  var q = 0
  while q < order.len:
    for child in children[order[q]]: order.add child
    inc q

  var clusters = ""
  var fills: seq[Fill]
  var dividers = ""
  var nodesOut = ""
  var notesOut = ""
  # Draws the dashed lines between the regions among a composite's members.
  proc divide(items: seq[int], left, top, right, bottom: float) =
    var regions: seq[int]
    for i in items:
      if views[i].kind == kRegion: regions.add i
    if regions.len < 2: return
    proc lo(i: int, x: bool): float =
      if x: cnodes[i].x - cnodes[i].w / 2 else: cnodes[i].y - cnodes[i].h / 2
    proc hi(i: int, x: bool): float =
      if x: cnodes[i].x + cnodes[i].w / 2 else: cnodes[i].y + cnodes[i].h / 2
    for xAxis in [true, false]:
      let x = xAxis
      var sorted = regions
      sorted.sort(proc (a, b: int): int =
        let d = lo(a, x) - lo(b, x)
        if d < 0: -1 elif d > 0: 1 else: a - b)
      var apart = true
      for k in 1 ..< sorted.len:
        if hi(sorted[k - 1], x) > lo(sorted[k], x) + 0.5: apart = false
      if not apart: continue
      for k in 1 ..< sorted.len:
        let at = num((hi(sorted[k - 1], x) + lo(sorted[k], x)) / 2 + pad)
        dividers.add "<path class=\"pele-divider\" d=\"M" &
          (if x: at & "," & num(top) & "V" & num(bottom) else: num(left) & "," & at & "H" & num(right)) & "\"/>"
      return
    # Regions that sit neither side by side nor in a stack each get an outline.
    for i in regions:
      let c = cnodes[i]
      dividers.add rect(c.x - c.w / 2 + pad, c.y - c.h / 2 + pad, c.w, c.h,
                        " class=\"pele-divider\" rx=\"" & jsString(CORNER) & "\"")
  divide(roots, pad / 2, pad / 2, width - pad / 2, height - pad / 2)

  for i in order:
    let view = views[i]
    let node = view.node
    if node == nil or not view.hasStyle or view.kind >= kRegion: continue
    let style = view.style
    let c = cnodes[i]
    let x = c.x + pad
    let y = c.y + pad
    let w = view.w
    let h = view.h
    let ink = inkFill(style.shape, style.text)
    let labelAttrs = " class=\"pele-label\"" & ink & style.text
    var body: string

    case view.kind
    of kComposite:
      let left = x - c.w / 2
      let top = y - c.h / 2
      if paints(style.shape): fills.add Fill(box: [left, top, left + c.w, top + c.h], shape: style.shape)
      body = rect(left, top, c.w, c.h, " rx=\"" & jsString(CORNER) & "\" fill=\"var(--_a)\"" &
                  (if setsFill(style.shape): "" else: " fill-opacity=\"0.5\"") & " stroke=\"var(--_b)\"" & style.shape)
      if view.titleH > 0:
        body.add "<path d=\"M" & num(left) & "," & num(top + view.titleH) & "H" & num(left + c.w) & "\"" & RULE &
          style.line & "/>" &
          labelSvg(view.label, titleX(c, view.label.width, crossings) + pad, top + view.titleH / 2,
                   " class=\"pele-cluster-label\"" & ink & style.text, icons)
      divide(children[i], left, top + view.titleH, left + c.w, top + c.h)
    of kStart:
      body = "<circle r=\"7\" fill=\"var(--_l)\"" & style.shape & "/>"
    of kEnd:
      body = "<circle r=\"8.5\" fill=\"var(--_bg)\" stroke=\"var(--_l)\"" & style.line &
        "/><circle r=\"5\" fill=\"var(--_l)\"" & style.shape & "/>"
    of kChoice:
      body = "<polygon points=\"0," & num(-h / 2) & " " & num(w / 2) & ",0 0," & num(h / 2) & " " & num(-w / 2) &
        ",0\"" & SURFACE & style.shape & "/>"
    of kFork, kJoin:
      body = rect(-w / 2, -h / 2, w, h, " rx=\"2\" fill=\"var(--_l)\"" & style.shape)
    of kNote:
      let r = num(w / 2)
      let b = num(h / 2)
      let fold = num(w / 2 - FOLD)
      let corner = num(FOLD - h / 2)
      body =
        "<path d=\"M-" & r & ",-" & b & "H" & fold & "L" & r & "," & corner & "V" & b & "H-" & r &
          "Z\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"/>" &
        "<path d=\"M" & fold & ",-" & b & "V" & corner & "H" & r & "\"" & RULE & "/>" &
        labelSvg(view.label, 0, 0, " class=\"pele-label\" font-size=\"" & jsString(small) & "\" fill=\"var(--_m)\"",
                 icons)
    else:
      body = rect(-w / 2, -h / 2, w, h, " rx=\"" & num(min(CORNER, h / 2)) & "\"" & SURFACE & style.shape)
      if view.kind == kState:
        body.add labelSvg(view.label, 0, 0, labelAttrs, icons)
      else:
        var at = PAD_Y - h / 2 + view.label.height
        body.add "<path d=\"M" & num(-w / 2) & "," & num(at + 6) & "H" & num(w / 2) & "\"" & RULE & style.line &
          "/>" & labelSvg(view.label, 0, at - view.label.height / 2, labelAttrs, icons)
        at += 14
        for line in view.lines:
          body.add labelSvg(line, 0, at + line.height / 2, " class=\"pele-state-description\" font-size=\"" &
                            jsString(small) & "\"" & ink & style.text, icons)
          at += line.height

    if db.links.hasKey(node.id):
      let link = db.links[node.id]
      # Entity codes are resolved first, so the URL is checked in the form a browser would follow.
      let tooltip = decodeEntities(unquote(link.tooltip))
      if tooltip != "": body = "<title>" & esc(tooltip) & "</title>" & body
      body = linked(body, safeUrl(unquote(link.url)), node.id, links, options, " target=\"_blank\"")
    let open = "<g class=\"" & CLASSES[view.kind] & classNames(withoutMermaidClasses(node.cssClasses)) &
      "\" data-id=\"" & escText(node.id) & "\""
    if view.kind == kComposite: clusters.add open & ">" & body & "</g>"
    elif view.kind == kNote:
      notesOut.add open & " transform=\"translate(" & num(x) & "," & num(y) & ")\">" & body & "</g>"
    else: nodesOut.add open & " transform=\"translate(" & num(x) & "," & num(y) & ")\">" & body & "</g>"

  # Moves a route end from the layout box onto the drawn shape, and spreads the ends along a bar.
  proc attach(route: var seq[float], at, i: int) =
    let c = cnodes[i]
    if c.isGroup: return
    let view = views[i]
    let bar = view.kind == kFork or view.kind == kJoin
    let other = if at == 0: 3 else: at - 3
    # 0 is the x axis and 1 the y axis; the end sits on a side that faces along `axis`.
    for axis in [1, 0]:
      let extent = if axis == 1: c.h else: c.w
      let drawnExtent = if axis == 1: view.h else: view.w
      let breadth = if axis == 1: view.w else: view.h
      let center = (if axis == 1: c.y else: c.x) + pad
      let cross = (if axis == 1: c.x else: c.y) + pad
      let delta = route[at + axis] - center
      if abs(abs(delta) - extent / 2) >= 0.5: continue
      route[at + axis] -= (jsSign(delta) * (extent - drawnExtent)) / 2
      if bar and breadth > drawnExtent:
        route[at + 1 - axis] = clamp(route[other + 1 - axis], cross - breadth / 2 + 6, cross + breadth / 2 - 6)
      return

  let reach = sideReach()
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    if ce.src == ce.dst or ce.route.len < 6 or drawn[i].dashed: continue
    reach.add(ce.dst, endSide(ce.route, ce.route.len - 3, cnodes[ce.dst]), "arrow_point")

  var casings = ""
  var edgesOut = ""
  var labelsOut = ""
  var loopSeen = newSeq[int](states)
  var loopText = newSeq[float](states)
  for i in 0 ..< cedges.len:
    let ce = cedges[i]
    let edge = drawn[i]
    let label = edgeLabels[i]
    let note = edge.dashed
    let endType = if note: "none" else: "arrow_point"
    var path: EdgePath
    if ce.src == ce.dst:
      let a = cnodes[ce.src]
      let view = views[ce.src]
      let k = loopSeen[ce.src]
      inc loopSeen[ce.src]
      # The loop hangs off a side the flow does not use: the right, or below when the flow is horizontal.
      let side = across(ce.src)
      let w = if a.isGroup: a.w else: view.w
      let h = if a.isGroup: a.h else: view.h
      let output = (if side: w else: h) / 2
      let spread = max(min((if side: h else: w) / 2 - 4, 8 + float(k) * 6), 2)
      let reachK = LOOP + float(k) * 8
      let hyp = hypot(reachK, spread)
      let trim = markerTrim(endType) / (if hyp == 0 or hyp != hyp: 1.0 else: hyp)
      # Offsets are given for a loop on the right and turned a quarter for one below.
      proc px(dx, dy: float): float = a.x + pad + (if side: output + dx else: -dy)
      proc py(dx, dy: float): float = a.y + pad + (if side: dy else: output + dx)
      proc at(dx, dy: float): string = num(px(dx, dy)) & "," & num(py(dx, dy))
      path = EdgePath(
        d: "M" & at(0, -spread) & "C" & at(reachK, -2 * spread) & " " & at(reachK, 2 * spread) & " " &
          at(reachK * trim, spread + spread * trim),
        sx: 0, sy: 0, sdx: 0, sdy: 0,
        ex: px(0, spread),
        ey: py(0, spread),
        edx: px(-reachK, -spread) - px(0, 0),
        edy: py(-reachK, -spread) - py(0, 0),
      )
      let l = hypot(path.edx, path.edy)
      let len = if l == 0 or l != l: 1.0 else: l
      path.edx /= len
      path.edy /= len
      # Labels stack beyond the outermost loop, in the order of their transitions.
      let furthest = LOOP + float(loopCount[ce.src] - 1) * 8
      let below = loopText[ce.src] + label.height / 2
      loopText[ce.src] += label.height
      ce.labelX = if side: a.x + output + furthest + 4 + ce.labelW / 2 else: a.x
      ce.labelY = if side: a.y - loopHeight[ce.src] / 2 + below else: a.y + output + furthest * 0.75 + 4 + below
    else:
      var route = ce.route
      let leaves = reach.reachOf(ce.src, endSide(route, 0, cnodes[ce.src]))
      let arrives = reach.reachOf(ce.dst, endSide(route, route.len - 3, cnodes[ce.dst]))
      var k = 0
      while k < route.len:
        route[k] += pad
        route[k + 1] += pad
        k += 3
      attach(route, 0, ce.src)
      attach(route, route.len - 3, ce.dst)
      if anchors.hasKey(i) and route.len >= 6:
        let composite = anchors[i]
        let g = cnodes[composite]
        let inward = views[ce.src].kind == kHidden
        let at = if inward: 0 else: route.len - 3
        let near = (g.dir == "TB" or g.dir == "LR") == inward
        let point =
          if vertical(g.dir):
            @[route[at], g.y + pad + (if near: views[composite].titleH - g.h / 2 else: g.h / 2), 0.0]
          else:
            @[g.x + pad + (if near: -g.w / 2 else: g.w / 2), route[at + 1], 1.0]
        route = if inward: point & route else: route & point
      path = routePath(route, curve, 0, markerTrim(endType), leaves, arrives)
    let over = overFills(path.d, [path.ex, path.ey], fills, "", path.tokens)
    let overInk = not over.none and over.ink != ""
    if not over.none and over.ink == "": casings.add edgeCasing(path, "none", endType)
    let kind =
      if note: "pele-note-edge\" stroke=\"" & (if overInk: over.ink else: "var(--_b)") & "\" stroke-dasharray=\"3 4"
      elif overInk: "pele-transition\" stroke=\"" & over.ink
      else: "pele-transition"
    edgesOut.add "<g class=\"pele-edge " & kind & "\" data-id=\"" & escText(edge.id) & "\">" &
      "<path d=\"" & path.d & "\"/>" &
      marker(endType, path.ex, path.ey, path.edx, path.edy, if overInk: over.ink else: "var(--_l)") &
      "</g>"
    if label.width > 0:
      let x = ce.labelX + pad
      let y = ce.labelY + pad
      labelsOut.add edgeLabelSvg(edge.id, label, x, y, "", icons)

  let titled = withTitle(
    db.title,
    measurer,
    size,
    pad,
    width,
    height,
    (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      (if dividers != "": "<g class=\"pele-dividers\" stroke-dasharray=\"4 4\"" & RULE & ">" & dividers & "</g>" else: "") &
      casingsSvg(casings) &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" &
        edgesOut & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\">" & labelsOut &
        "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodesOut & notesOut & "</g>"
  )
  let svg = svgDocument("state", titled.width, titled.height, size, options,
                        Accessible(accTitle: db.accTitle, accDescr: db.accDescr), titled.content)
  Rendered(svg: svg, width: titled.width, height: titled.height, links: links)

# Picks where a composite's title sits in its title bar so that edges entering from above do not cross it.
proc titleX(c: CNode, width: float, crossings: Table[int, seq[float]]): float =
  let key = int(jsRound(c.y - c.h / 2))
  if not crossings.hasKey(key) or width == 0: return c.x
  let xs = crossings[key]
  let left = c.x - c.w / 2
  let half = width / 2
  var best = c.x
  var bestGap = -1.0
  for x in [c.x, left + GROUP_PAD + half, left + c.w - GROUP_PAD - half]:
    var gap = Inf
    for cx in xs:
      if cx > left and cx < left + c.w: gap = min(gap, abs(cx - x) - half)
    if gap >= 6: return x
    if gap > bestGap + 0.5:
      bestGap = gap
      best = x
  best

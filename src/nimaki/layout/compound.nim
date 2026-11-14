## port-of: src/layout/compound.ts
## port-status: conformant
##
## Port notes: `Dir | undefined` is a string, "" for undefined. A snapshot copies the routes (Nim
## seqs are values), which is the same as keeping the arrays in the TypeScript, since `place()`
## gives every edge a new route rather than changing the old one. The cache of laid out levels
## compares numbers as `Object.is` does (NaN is NaN, 0 is not -0).
import std/[algorithm, tables, sets, math]
import ../js
import layered

type
  Dir* = string
    ## 'TB' | 'BT' | 'LR' | 'RL'

proc direction*(dir: string): Dir =
  ## The direction a diagram names, or top to bottom for anything else.
  if dir == "BT" or dir == "LR" or dir == "RL": dir else: "TB"

type
  CNode* = ref object
    w*, h*: float
    parent*: int
    isGroup*: bool
    dir*: Dir                 ## "" for undefined
    padX*, padTop*, padBottom*: float
    minW*: float
    seq*: float
      ## Declaration order; a group takes the smallest value among its members.
    span*: float
      ## How much of a side its edges may spread along, measured across the flow; 0 keeps them
      ## at its middle.
    x*, y*: float

  CEdge* = ref object
    src*, dst*: int
    minlen*: int
    labelW*, labelH*: float
    route*: seq[float]
      ## x, y, axis triples; axis is 0 where the edge runs vertically into the point, 1 horizontally.
    labelX*, labelY*: float

  CompoundResult* = object
    width*, height*: float

  Side = enum
    Top = 0, Right, Bottom, Left

  PortEdge = ref object
    e: int
    inner: int
    output: bool              ## `out`
    side: Side
    hint: float
      ## Cross-flow position outside the group from a previous layout; NaN if unknown.
    px, py: float
    route: seq[float]

  LevelEdge = object
    e, a, b: int

  Level = ref object
    id: int
    dir: Dir
    items: seq[int]
    edges: seq[LevelEdge]
    ports: seq[PortEdge]
    portOf: Table[int, PortEdge]
    routes: Table[int, seq[float]]
    x, y: float

const
  MAX_PORTS = 40000
  MAX_ORDERED_PORTS = 400
    ## Limit repeated layouts to small graphs.
  MAX_ORDERED_EDGES = 500
  FLAT_SLACK = 1.5
    ## Crossing tolerance before trying independent group ordering.
  FLAT_SPARE = 4.0

type Snapshot = object
  nodes: seq[float]
  routes: seq[seq[float]]
  labels: seq[float]
  levels: seq[float]
  total: CompoundResult

proc snapshot(nodes: seq[CNode], edges: seq[CEdge], levels: seq[Level], total: CompoundResult): Snapshot =
  for c in nodes: result.nodes.add [c.x, c.y, c.w, c.h]
  for e in edges:
    result.labels.add [e.labelX, e.labelY]
    result.routes.add e.route
  for level in levels:
    result.levels.add [level.x, level.y]
    for port in level.ports: result.levels.add [port.px, port.py]
  result.total = total

proc restore(s: Snapshot, nodes: seq[CNode], edges: seq[CEdge], levels: seq[Level]): CompoundResult =
  for i, c in nodes:
    c.x = s.nodes[4 * i]
    c.y = s.nodes[4 * i + 1]
    c.w = s.nodes[4 * i + 2]
    c.h = s.nodes[4 * i + 3]
  for i, e in edges:
    e.route = s.routes[i]
    e.labelX = s.labels[2 * i]
    e.labelY = s.labels[2 * i + 1]
  var k = 0
  for level in levels:
    level.x = s.levels[k]
    level.y = s.levels[k + 1]
    k += 2
    for port in level.ports:
      port.px = s.levels[k]
      port.py = s.levels[k + 1]
      k += 2
  s.total

const
  FAN = 24.0
    ## Ignore crossings within this distance of a shared node.
  IN_LINE = 0.5
    ## Tolerance for collinear points.
  CURVE_PIECES = 3
  CORNER_PIECES = 2
  STEP_PIECES = max(3, max(CURVE_PIECES, CORNER_PIECES + 1))
    ## Allow for a step, an S-curve, or a straight segment plus a rounded corner.
  HANDLE = 0.62
    ## Match the renderer's corner handles.
  MAX_INSERT = 128

type
  Style* = enum
    Curved, Stepped, Linear

proc styleOf*(opt: LayeredOptions): Style =
  if opt.tracks: Stepped elif opt.straight: Linear else: Curved

proc routeCrossings*(nodes: seq[CNode], edges: seq[CEdge], style = Curved): int =
  var size = 0
  for e in edges:
    if e.src != e.dst and e.route.len > 3: size += (e.route.len div 3 - 1) * STEP_PIECES
  var ax = newSeq[float](size)
  var ay = newSeq[float](size)
  var bx = newSeq[float](size)
  var by = newSeq[float](size)
  var low = newSeq[float](size)
  var high = newSeq[float](size)
  var owner = newSeq[int](size)
  # Endpoint flags: 1 for the first segment, 2 for the last.
  var ends = newSeq[int](size)
  var count = 0
  var top = Inf
  var bottom = -Inf
  var fromX = NaN
  var fromY = NaN
  var toX = NaN
  var toY = NaN
  proc add(ei, part: int, x0In, y0In, x1, y1: float) =
    var x0 = x0In
    var y0 = y0In
    let p = count - 1
    let on = x0 == toX and y0 == toY and ((y1 == y0 and fromY == y0) or (x1 == x0 and fromX == x0))
    if on and owner[p] == ei and ends[p] == part and (x0 - fromX) * (x1 - x0) + (y0 - fromY) * (y1 - y0) > 0:
      dec count
      x0 = fromX
      y0 = fromY
    fromX = x0
    fromY = y0
    toX = x1
    toY = y1
    ends[count] = part
    ax[count] = min(x0, x1)
    bx[count] = max(x0, x1)
    ay[count] = if x0 <= x1: y0 else: y1
    by[count] = if x0 <= x1: y1 else: y0
    low[count] = min(y0, y1)
    high[count] = max(y0, y1)
    if low[count] < top: top = low[count]
    if high[count] > bottom: bottom = high[count]
    owner[count] = ei
    inc count
  for ei in 0 ..< edges.len:
    let e = edges[ei]
    if e.src == e.dst: continue
    let r = e.route
    template aligned(k: int): bool = abs(r[k] - r[k - 3]) < 0.01 or abs(r[k + 1] - r[k - 2]) < 0.01
    template length(k: int): float = abs(r[k] - r[k - 3]) + abs(r[k + 1] - r[k - 2])
    proc turns(k: int): bool =
      style == Curved and k > 0 and k < r.len - 3 and aligned(k) and aligned(k + 3) and
        length(k) >= 0.01 and length(k + 3) >= 0.01 and
        (abs(r[k] - r[k - 3]) < 0.01) != (abs(r[k + 3] - r[k]) < 0.01)
    # An edge without a route (between nodes the layout left out) reads undefined: NaN.
    var atX = if r.len > 0: r[0] else: NaN
    var atY = if r.len > 1: r[1] else: NaN
    var k = 3
    while k < r.len:
      let part = (if k == 3: 1 else: 0) or (if k == r.len - 3: 2 else: 0)
      let x0 = atX
      let y0 = atY
      let x1 = r[k]
      let y1 = r[k + 1]
      atX = x1
      atY = y1
      if aligned(k) or style == Linear:
        if not turns(k):
          add(ei, part, x0, y0, x1, y1)
          k += 3
          continue
        # Adjacent corners share a leg, so each gets half.
        let before = if turns(k - 3): length(k) / 2 else: length(k)
        let after = if turns(k + 3): length(k + 3) / 2 else: length(k + 3)
        let ux = (x1 - r[k - 3]) / length(k)
        let uy = (y1 - r[k - 2]) / length(k)
        let vx = (r[k + 3] - x1) / length(k + 3)
        let vy = (r[k + 4] - y1) / length(k + 3)
        let sx = x1 - ux * before
        let sy = y1 - uy * before
        add(ei, part, x0, y0, sx, sy)
        let c1x = x1 - ux * before * (1 - HANDLE)
        let c1y = y1 - uy * before * (1 - HANDLE)
        let c2x = x1 + vx * after * (1 - HANDLE)
        let c2y = y1 + vy * after * (1 - HANDLE)
        atX = x1 + vx * after
        atY = y1 + vy * after
        let turn = part or (if k + 3 == r.len - 3: 2 else: 0)
        var px = sx
        var py = sy
        for i in 1 .. CORNER_PIECES:
          let t = float(i) / float(CORNER_PIECES)
          let u = 1 - t
          let x = u * u * u * sx + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * atX
          let y = u * u * u * sy + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * atY
          add(ei, turn, px, py, x, y)
          px = x
          py = y
        k += 3
        continue
      if style == Stepped:
        let down = r[k + 2] == 0
        let mx = if down: x0 else: (x0 + x1) / 2
        let my = if down: (y0 + y1) / 2 else: y0
        add(ei, part, x0, y0, mx, my)
        add(ei, part, mx, my, (if down: x1 else: mx), (if down: my else: y1))
        add(ei, part, (if down: x1 else: mx), (if down: my else: y1), x1, y1)
        k += 3
        continue
      # Approximate the rendered S-curve with straight segments.
      let down = r[k + 2] == 0
      let c = if down: ease(x1 - x0, y1 - y0) else: ease(y1 - y0, x1 - x0)
      var px = x0
      var py = y0
      for i in 1 .. CURVE_PIECES:
        let t = float(i) / float(CURVE_PIECES)
        let u = 1 - t
        let across = t * t * (3 - 2 * t)
        let along = 3 * c * t * u * u + 3 * (1 - c) * t * t * u + t * t * t
        let x = x0 + (x1 - x0) * (if down: across else: along)
        let y = y0 + (y1 - y0) * (if down: along else: across)
        add(ei, part, px, py, x, y)
        px = x
        py = y
      k += 3
  # Count each pair only in the first band shared by both segments.
  let bands = if bottom > top: int(jsRound(sqrt(float(count)))) else: 1
  let scale = if bottom > top: float(bands) / (bottom - top) else: 0
  proc bandOf(y: float): int = min(bands - 1, int(floor((y - top) * scale)))
  var first = newSeq[int](count)
  var bandStart = newSeq[int](bands + 1)
  for p in 0 ..< count:
    first[p] = bandOf(low[p])
    for b in first[p] .. bandOf(high[p]): inc bandStart[b + 1]
  for b in 0 ..< bands: bandStart[b + 1] += bandStart[b]
  var fill = bandStart[0 ..< bands]
  var inBand = newSeq[int](bandStart[bands])
  for p in 0 ..< count:
    for b in first[p] .. bandOf(high[p]):
      inBand[fill[b]] = p
      inc fill[b]
  # Edges merging into a shared endpoint run do not count as crossings.
  var runs = newSeq[float](edges.len * 8)
  proc inLine(r: seq[float], a, b, c: int): bool =
    (abs(r[a] - r[b]) < IN_LINE and abs(r[a] - r[c]) < IN_LINE) or
      (abs(r[a + 1] - r[b + 1]) < IN_LINE and abs(r[a + 1] - r[c + 1]) < IN_LINE)
  for ei in 0 ..< edges.len:
    let r = edges[ei].route
    if r.len < 6: continue
    var k = 3
    while k + 3 < r.len and inLine(r, 0, k, k + 3): k += 3
    let last = r.len - 3
    var j = last - 3
    while j >= 3 and inLine(r, last, j, j - 3): j -= 3
    let vals = [r[0], r[1], r[k], r[k + 1], r[j], r[j + 1], r[last], r[last + 1]]
    for i, v in vals: runs[ei * 8 + i] = v
  proc onRun(ei, stop: int, x, y: float): bool =
    let o = ei * 8 + (if stop == 1: 0 else: 4)
    let x0 = runs[o]
    let y0 = runs[o + 1]
    let dx = runs[o + 2] - x0
    let dy = runs[o + 3] - y0
    let length = dx * dx + dy * dy
    let t = if length > 0: max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / length)) else: 0
    hypot(x - x0 - t * dx, y - y0 - t * dy) < IN_LINE
  var total = 0
  for band in 0 ..< bands:
    let bandEnd = bandStart[band + 1]
    if bandEnd - bandStart[band] > MAX_INSERT:
      var part = inBand[bandStart[band] ..< bandEnd]
      part.sort(proc (p, q: int): int = orElse(ax[p] - ax[q], p - q))
      for i, v in part: inBand[bandStart[band] + i] = v
    else:
      for i in bandStart[band] + 1 ..< bandEnd:
        let p = inBand[i]
        var j = i
        while j > bandStart[band] and ax[inBand[j - 1]] > ax[p]:
          inBand[j] = inBand[j - 1]
          dec j
        inBand[j] = p
    for s in bandStart[band] ..< bandEnd:
      let p = inBand[s]
      let dx = bx[p] - ax[p]
      let dy = by[p] - ay[p]
      let here = first[p] == band
      for t in s + 1 ..< bandEnd:
        let q = inBand[t]
        if ax[q] > bx[p]: break
        if high[q] < low[p] or low[q] > high[p] or owner[p] == owner[q] or (not here and first[q] != band): continue
        let d1 = dx * (ay[q] - ay[p]) - dy * (ax[q] - ax[p])
        let d2 = dx * (by[q] - ay[p]) - dy * (bx[q] - ax[p])
        # Treat points on the line as one side to count segment-boundary crossings once.
        if (d1 > 0) == (d2 > 0): continue
        let ex = bx[q] - ax[q]
        let ey = by[q] - ay[q]
        let d3 = ex * (ay[p] - ay[q]) - ey * (ax[p] - ax[q])
        let d4 = ex * (by[p] - ay[q]) - ey * (bx[p] - ax[q])
        if (d3 > 0) == (d4 > 0): continue
        let ep = edges[owner[p]]
        let eq = edges[owner[q]]
        let at = d3 / (d3 - d4)
        let x = ax[p] + at * dx
        let y = ay[p] + at * dy
        # Exclude fan-in and fan-out at shared nodes.
        proc fan(v, pe, qe: int): bool =
          ((ends[p] and pe) != 0 and (ends[q] and qe) != 0) or
            (abs(x - nodes[v].x) < nodes[v].w / 2 + FAN and abs(y - nodes[v].y) < nodes[v].h / 2 + FAN) or
            (onRun(owner[p], pe, x, y) and onRun(owner[q], qe, x, y))
        if ep.src == eq.src and fan(ep.src, 1, 1): continue
        if ep.src == eq.dst and fan(ep.src, 1, 2): continue
        if ep.dst == eq.src and fan(ep.dst, 2, 1): continue
        if ep.dst == eq.dst and fan(ep.dst, 2, 2): continue
        inc total
  total

proc inheritCrossedDirections*(nodes: seq[CNode], ends: seq[(int, int)]) =
  ## Match Mermaid: groups crossed by edges inherit their parent's direction.
  # Pele builds a Set of the ancestors of each end. A HashSet[int] is slow in nim js (its hash
  # multiplies 64-bit integers by hand), and an edge can cross thousands of groups, so each end
  # stamps its ancestors in an array instead: inA[g] == stamp means g is an ancestor of src.
  var inA = newSeq[int](nodes.len)
  var inB = newSeq[int](nodes.len)
  var a, b: seq[int]
  template ancestors(i, stamp: int, mark, list: var seq[int]) =
    list.setLen 0
    var p = nodes[i].parent
    while p >= 0 and mark[p] != stamp:
      mark[p] = stamp
      list.add p
      p = nodes[p].parent
  for k, (src, dst) in ends:
    if src < 0 or dst < 0 or src == dst: continue
    let stamp = k + 1
    ancestors(src, stamp, inA, a)
    ancestors(dst, stamp, inB, b)
    for g in a:
      if inB[g] != stamp: nodes[g].dir = ""
    for g in b:
      if inA[g] != stamp: nodes[g].dir = ""

proc shiftLayout*(nodes: seq[CNode], edges: seq[CEdge], ox, oy: float) =
  for c in nodes:
    c.x += ox
    c.y += oy
  for e in edges:
    var k = 0
    while k < e.route.len:
      e.route[k] += ox
      e.route[k + 1] += oy
      k += 3
    e.labelX += ox
    e.labelY += oy

proc cnode*(w, h: float, parent = -1): CNode =
  CNode(w: w, h: h, parent: parent)

func startSide(dir: Dir): Side =
  if dir == "TB": Top elif dir == "BT": Bottom elif dir == "LR": Left else: Right

func opposite(side: Side): Side = Side((ord(side) + 2) and 3)

func isSame(a, b: float): bool =
  ## `Object.is`
  if isNaN(a): isNaN(b)
  else: a == b and signbit(a) == signbit(b)

type
  Built = object
    lnodes: seq[LNode]
    ledges: seq[LEdge]
    dummies: seq[int]
  Laid = ref object
    given: seq[float]
    lnodes: seq[LNode]
    ledges: seq[LEdge]
    size: LayeredResult

proc compoundLayout*(nodes: seq[CNode], edges: seq[CEdge], rootDir: Dir, opt: LayeredOptions): CompoundResult =
  ## Lays out a graph whose nodes may be nested in groups. Each group is laid out on its own,
  ## in its own direction, and then placed in its parent as a single box. An edge that crosses
  ## a group's border passes through a port on the side facing its other end.
  let n = nodes.len
  var levelOf = initTable[int, Level]()
  var order: seq[Level]
  proc makeLevel(id: int, dir: Dir): Level =
    let level = Level(id: id, dir: dir)
    levelOf[id] = level
    level
  let root = makeLevel(-1, rootDir)

  var children = newSeq[seq[int]](n)
  var rootItems: seq[int]
  for i in 0 ..< n:
    let p = nodes[i].parent
    if p >= 0 and p < n and p != i and nodes[p].isGroup: children[p].add i
    else:
      nodes[i].parent = -1
      rootItems.add i
  root.items = rootItems
  order.add root
  var depth = newSeq[int](n)
  var placed = newSeq[bool](n)
  proc descend(start: int) =
    var q = start
    while q < order.len:
      let level = order[q]
      for item in level.items:
        placed[item] = true
        depth[item] = if level.id < 0: 0 else: depth[level.id] + 1
        if nodes[item].isGroup:
          let child = makeLevel(item, if nodes[item].dir != "": nodes[item].dir else: level.dir)
          child.items = children[item]
          order.add child
      inc q
  descend(0)
  # Groups that contain each other are unreachable from the root; lift them out.
  for i in 0 ..< n:
    if placed[i]: continue
    let former = nodes[i].parent
    var kept: seq[int]
    for c in children[former]:
      if c != i: kept.add c
    children[former] = kept
    nodes[i].parent = -1
    root.items.add i
    placed[i] = true
    depth[i] = 0
    if nodes[i].isGroup:
      let start = order.len
      let child = makeLevel(i, if nodes[i].dir != "": nodes[i].dir else: rootDir)
      child.items = children[i]
      order.add child
      descend(start)

  var q = order.len - 1
  while q > 0:
    let level = order[q]
    var sq = Inf
    for item in level.items:
      if nodes[item].seq < sq: sq = nodes[item].seq
    if sq != Inf: nodes[level.id].seq = sq
    dec q
  for level in order:
    level.items.sort(proc (a, b: int): int = orElse(nodes[a].seq - nodes[b].seq, a - b))

  # Every group border an edge crosses costs a port. Past the budget, an edge is drawn between
  # the groups that hold its ends, at the level they share.
  var ports = 0
  for e in edges:
    var a = e.src
    var b = e.dst
    var crossed = 0
    while depth[a] > depth[b]:
      a = nodes[a].parent
      inc crossed
    while depth[b] > depth[a]:
      b = nodes[b].parent
      inc crossed
    while a != b and nodes[a].parent != nodes[b].parent:
      a = nodes[a].parent
      b = nodes[b].parent
      crossed += 2
    if a == b: continue
    if ports + crossed > MAX_PORTS:
      e.src = a
      e.dst = b
    else:
      ports += crossed

  var loops: seq[int]
  var stray: seq[int]
  for ei in 0 ..< edges.len:
    let e = edges[ei]
    e.route = @[]
    if e.src == e.dst:
      loops.add ei
      continue
    var a = e.src
    var b = e.dst
    var aPath, bPath: seq[int]
    while depth[a] > depth[b]:
      aPath.add a
      a = nodes[a].parent
    while depth[b] > depth[a]:
      bPath.add b
      b = nodes[b].parent
    if a == b:
      stray.add ei
      continue
    while nodes[a].parent != nodes[b].parent:
      aPath.add a
      bPath.add b
      a = nodes[a].parent
      b = nodes[b].parent
    levelOf[nodes[a].parent].edges.add LevelEdge(e: ei, a: a, b: b)
    for (path, output) in [(aPath, true), (bPath, false)]:
      for inner in path:
        let level = levelOf[nodes[inner].parent]
        let port = PortEdge(e: ei, inner: inner, output: output, side: Top, hint: NaN)
        level.ports.add port
        level.portOf[ei * 2 + (if output: 0 else: 1)] = port

  var local = newSeq[int](n)
  proc endpointBelow(item: int, e: CEdge, output: bool): bool = (if output: e.src else: e.dst) != item

  let ordered = ports > 1 and ports <= MAX_ORDERED_PORTS and edges.len <= MAX_ORDERED_EDGES

  # Use a flat layout to coordinate node and port order across groups.
  var key = newSeq[float](n)
  for x in key.mitems: x = NaN
  var keyed = false
  var flatCrossings = 0
  var farHint: proc (level: Level, port: PortEdge): float = nil

  proc build(level: Level, sized: bool): Built =
    let vertical = level.dir == "TB" or level.dir == "BT"
    let start = startSide(level.dir)
    var lnodes: seq[LNode]
    var ledges: seq[LEdge]
    for i, item in level.items:
      local[item] = i
      let node = nodes[item]
      let ln = if sized: lnode((if vertical: node.w else: node.h), (if vertical: node.h else: node.w))
               else: lnode(0, 0)
      ln.span = if node.isGroup: min(node.span, ln.w - 2 * node.padX) else: node.span
      ln.key = if keyed: key[item] else: NaN
      lnodes.add ln
    proc held(item, ei: int, output: bool): bool = nodes[item].isGroup and endpointBelow(item, edges[ei], output)
    proc offset(item, ei: int, output: bool): float =
      if not sized or not nodes[item].isGroup or not endpointBelow(item, edges[ei], output): return 0
      let port = levelOf[item].portOf[ei * 2 + (if output: 0 else: 1)]
      if vertical: port.px - nodes[item].w / 2 else: port.py - nodes[item].h / 2
    for le in level.edges:
      let e = edges[le.e]
      let edge = ledge(local[le.a], local[le.b], e.minlen)
      if sized:
        edge.labelW = if vertical: e.labelW else: e.labelH
        edge.labelH = if vertical: e.labelH else: e.labelW
        edge.tailDx = offset(le.a, le.e, true)
        edge.headDx = offset(le.b, le.e, false)
        edge.tailFixed = held(le.a, le.e, true)
        edge.headFixed = held(le.b, le.e, false)
      ledges.add edge
    var dummies = newSeq[int](level.ports.len)
    for x in dummies.mitems: x = -1
    for i, port in level.ports:
      if port.side == start or port.side == opposite(start):
        let d = lnodes.len
        let ln = lnode(0, 0, if port.side == start: kStartPort else: kEndPort)
        ln.key = if keyed: key[if port.output: edges[port.e].dst else: edges[port.e].src] else: NaN
        ln.hint = if isNaN(port.hint) and keyed and farHint != nil: farHint(level, port) else: port.hint
        lnodes.add ln
        dummies[i] = d
        let edge = if port.output: ledge(local[port.inner], d) else: ledge(d, local[port.inner])
        if port.output:
          edge.tailDx = offset(port.inner, port.e, true)
          edge.tailFixed = held(port.inner, port.e, true)
        else:
          edge.headDx = offset(port.inner, port.e, false)
          edge.headFixed = held(port.inner, port.e, false)
        ledges.add edge
      else:
        lnodes[local[port.inner]].pin = if port.side == Top or port.side == Left: -1 else: 1
    Built(lnodes: lnodes, ledges: ledges, dummies: dummies)

  var flat = order.len > 1 and ordered
  for level in order:
    if level.dir != rootDir: flat = false
  if flat:
    let vertical = rootDir == "TB" or rootDir == "BT"
    var leaf = newSeq[int](n)
    var group = newSeq[int](n)
    for i in 0 ..< n:
      leaf[i] = -1
      group[i] = -1
    var lnodes: seq[LNode]
    var groupOf: seq[int]
    var parent: seq[int]
    for i in 0 ..< n:
      if not nodes[i].isGroup: continue
      group[i] = parent.len
      parent.add -1
    for i in 0 ..< n:
      let p = nodes[i].parent
      if nodes[i].isGroup: parent[group[i]] = (if p >= 0: group[p] else: -1)
      else:
        leaf[i] = lnodes.len
        lnodes.add lnode((if vertical: nodes[i].w else: nodes[i].h), (if vertical: nodes[i].h else: nodes[i].w))
        groupOf.add(if p >= 0: group[p] else: -1)
    var ledges: seq[LEdge]
    var ledgeOf = newSeq[int](edges.len)
    for x in ledgeOf.mitems: x = -1
    for ei, e in edges:
      if e.src == e.dst or leaf[e.src] < 0 or leaf[e.dst] < 0: continue
      ledgeOf[ei] = ledges.len
      ledges.add ledge(leaf[e.src], leaf[e.dst], e.minlen, (if vertical: e.labelW else: e.labelH),
                       (if vertical: e.labelH else: e.labelW))
    var flatOpt = opt
    flatOpt.hasGroups = true
    flatOpt.groups = Groups(`of`: groupOf, parent: parent)
    flatOpt.orderOnly = true
    let flatLayout = layered(lnodes, ledges, flatOpt)
    flatCrossings = min(flatLayout.crossings, flatLayout.declared)
    var sum = newSeq[float](n)
    var count = newSeq[int](n)
    # Last rank occupied by each group.
    var last = newSeq[int](n)
    for x in last.mitems: x = -1
    for i in 0 ..< n:
      if leaf[i] < 0: continue
      key[i] = lnodes[leaf[i]].x
      var p = nodes[i].parent
      while p >= 0:
        sum[p] += key[i]
        inc count[p]
        last[p] = max(last[p], lnodes[leaf[i]].rank)
        p = nodes[p].parent
    for i in 0 ..< n:
      if count[i] > 0: key[i] = sum[i] / float(count[i])
    # Order outgoing ports at the group's last rank; break ties using the next rank.
    farHint = proc (level: Level, port: PortEdge): float =
      let le = ledgeOf[port.e]
      if le < 0 or level.id < 0 or not port.output or port.side != opposite(startSide(level.dir)): return NaN
      let points = ledges[le].points
      var inside = key[edges[port.e].src]
      var outside = 0.0
      var k = 0
      while k < points.len:
        if points[k] == float(last[level.id]): inside = points[k + 1]
        if points[k] == float(last[level.id] + 1): outside = points[k + 1]
        k += 2
      inside + outside * 1e-6

  # Reuse unchanged levels across layout attempts.
  var laid = initTable[int, seq[Laid]]()
  proc layOut(level: Level, lnodes: seq[LNode], ledges: seq[LEdge]): Laid =
    if not ordered: return Laid(lnodes: lnodes, ledges: ledges, size: layered(lnodes, ledges, opt))
    var given: seq[float]
    for ln in lnodes: given.add [ln.w, ln.h, float(ord(ln.kind)), ln.pin, ln.hint, ln.key, ln.span]
    for le in ledges:
      given.add [float(le.tail), float(le.head), float(le.minlen), le.labelW, le.labelH, le.tailDx,
                 le.headDx, (if le.tailFixed: 1.0 else: 0.0), (if le.headFixed: 1.0 else: 0.0)]
    if level.id notin laid: laid[level.id] = @[]
    for p in laid[level.id]:
      var same = p.given.len == given.len
      var i = 0
      while same and i < given.len:
        same = isSame(p.given[i], given[i])
        inc i
      if same: return p
    let done = Laid(given: given, lnodes: lnodes, ledges: ledges, size: layered(lnodes, ledges, opt))
    laid[level.id].add done
    done

  var total = CompoundResult()
  proc place() =
    # Rank parents first to determine which group sides edges cross.
    for level in order:
      for port in level.ports:
        if nodes[port.inner].isGroup and endpointBelow(port.inner, edges[port.e], port.output):
          levelOf[port.inner].portOf[port.e * 2 + (if port.output: 0 else: 1)].side = port.side
      if level.edges.len == 0: continue
      var needed = false
      for le in level.edges:
        let e = edges[le.e]
        if (nodes[le.a].isGroup and e.src != le.a) or (nodes[le.b].isGroup and e.dst != le.b): needed = true
      if not needed: continue
      let built = build(level, false)
      orient(built.lnodes, built.ledges)
      rank(built.lnodes, built.ledges, 1)
      let start = startSide(level.dir)
      for i, le in level.edges:
        let e = edges[le.e]
        let aAbove = not built.ledges[i].reversed
        if nodes[le.a].isGroup and e.src != le.a:
          levelOf[le.a].portOf[le.e * 2].side = if aAbove: opposite(start) else: start
        if nodes[le.b].isGroup and e.dst != le.b:
          levelOf[le.b].portOf[le.e * 2 + 1].side = if aAbove: start else: opposite(start)

    # Lay out children first so their sizes are known.
    var q = order.len - 1
    while q >= 0:
      let level = order[q]
      dec q
      let group = if level.id >= 0: nodes[level.id] else: nil
      let vertical = level.dir == "TB" or level.dir == "BT"
      let flip = level.dir == "BT" or level.dir == "RL"
      let built = build(level, true)
      let laidOut = layOut(level, built.lnodes, built.ledges)
      let lnodes = laidOut.lnodes
      let ledges = laidOut.ledges
      let size = laidOut.size
      let dummies = built.dummies
      let contentW = if vertical: size.width else: size.height
      let contentH = if vertical: size.height else: size.width
      let padX = if group != nil: group.padX else: 0
      let padTop = if group != nil: group.padTop else: 0
      let boxW = max(contentW + 2 * padX, if group != nil: group.minW else: 0)
      let boxH = contentH + padTop + (if group != nil: group.padBottom else: 0)
      let offX = (boxW - contentW) / 2
      let offY = padTop
      proc tx(lx, ly: float): float = offX + (if vertical: lx elif flip: size.height - ly else: ly)
      proc ty(lx, ly: float): float = offY + (if vertical: (if flip: size.height - ly else: ly) else: lx)
      let axis = if vertical: 0.0 else: 1.0
      proc convert(points: seq[float]): seq[float] =
        var i = 0
        while i < points.len:
          result.add [tx(points[i], points[i + 1]), ty(points[i], points[i + 1]), axis]
          i += 2

      for i, item in level.items:
        nodes[item].x = tx(lnodes[i].x, lnodes[i].y)
        nodes[item].y = ty(lnodes[i].x, lnodes[i].y)
      for i, le in level.edges:
        let edge = ledges[i]
        level.routes[le.e] = convert(edge.points)
        let e = edges[le.e]
        if e.labelW > 0:
          e.labelX = tx(edge.labelX, edge.labelY)
          e.labelY = ty(edge.labelX, edge.labelY)
      var k = level.edges.len
      for i, port in level.ports:
        let item = nodes[port.inner]
        if dummies[i] >= 0:
          var route = convert(ledges[k].points)
          inc k
          let at = if port.output: route.len - 3 else: 0
          var bx = route[at]
          var by = route[at + 1]
          if port.side == Top: by = 0
          elif port.side == Bottom: by = boxH
          elif port.side == Left: bx = 0
          else: bx = boxW
          if port.output: route.add [bx, by, axis]
          else: route = @[bx, by, axis] & route
          port.px = bx
          port.py = by
          port.route = route
          continue
        var ix = item.x
        var iy = item.y
        if item.isGroup and endpointBelow(port.inner, edges[port.e], port.output):
          let inner = levelOf[port.inner].portOf[port.e * 2 + (if port.output: 0 else: 1)]
          ix += inner.px - item.w / 2
          iy += inner.py - item.h / 2
        elif port.side == Top: iy -= item.h / 2
        elif port.side == Bottom: iy += item.h / 2
        elif port.side == Left: ix -= item.w / 2
        else: ix += item.w / 2
        var bx = ix
        var by = iy
        if port.side == Top: by = 0
        elif port.side == Bottom: by = boxH
        elif port.side == Left: bx = 0
        else: bx = boxW
        let a = if port.side == Top or port.side == Bottom: 0.0 else: 1.0
        port.px = bx
        port.py = by
        port.route = if port.output: @[ix, iy, a, bx, by, a] else: @[bx, by, a, ix, iy, a]

      if group != nil:
        group.w = boxW
        group.h = boxH
      else:
        total = CompoundResult(width: boxW, height: boxH)

    for level in order:
      let ox = level.x
      let oy = level.y
      for item in level.items:
        let node = nodes[item]
        node.x += ox
        node.y += oy
        if node.isGroup:
          let child = levelOf[item]
          child.x = node.x - node.w / 2
          child.y = node.y - node.h / 2

    proc append(route: var seq[float], part: seq[float], ox, oy: float) =
      var i = 0
      while i < part.len:
        let x = part[i] + ox
        let y = part[i + 1] + oy
        let len = route.len
        if not (len >= 3 and abs(route[len - 3] - x) < 0.01 and abs(route[len - 2] - y) < 0.01):
          route.add [x, y, part[i + 2]]
        i += 3

    for level in order:
      for le in level.edges:
        let e = edges[le.e]
        var route: seq[float]
        var outward: seq[Level]
        var item = e.src
        while nodes[item].parent != level.id:
          outward.add levelOf[nodes[item].parent]
          item = nodes[item].parent
        for lv in outward: append(route, lv.portOf[le.e * 2].route, lv.x, lv.y)
        append(route, level.routes[le.e], level.x, level.y)
        var inward: seq[Level]
        item = e.dst
        while nodes[item].parent != level.id:
          inward.add levelOf[nodes[item].parent]
          item = nodes[item].parent
        var i = inward.len - 1
        while i >= 0:
          append(route, inward[i].portOf[le.e * 2 + 1].route, inward[i].x, inward[i].y)
          dec i
        e.route = route
        if e.labelW > 0:
          e.labelX += level.x
          e.labelY += level.y
  # The flat layout ignores group boxes, so independent ordering may yield fewer crossings.
  let style = styleOf(opt)
  keyed = flat
  place()
  var crossings = -1
  if flat:
    crossings = routeCrossings(nodes, edges, style)
    if float(crossings) > float(flatCrossings) * FLAT_SLACK + FLAT_SPARE:
      let first = snapshot(nodes, edges, order, total)
      keyed = false
      place()
      let own = routeCrossings(nodes, edges, style)
      if own >= crossings:
        keyed = true
        total = restore(first, nodes, edges, order)
      else: crossings = own

  # Refine port order using routes outside each group. Skip this if independent ordering won;
  # it rarely helps enough to justify another layout.
  if keyed == flat and ordered:
    var again = false
    for level in order:
      if level.id < 0: continue
      let box = nodes[level.id]
      let vertical = level.dir == "TB" or level.dir == "BT"
      let stop = opposite(startSide(level.dir))
      var seen: seq[(float, float)]
      for port in level.ports:
        if port.side != stop: continue
        # Skip the straight run out of the port to find where the edge turns.
        let route = edges[port.e].route
        let bx = level.x + port.px
        let by = level.y + port.py
        var at = -1
        var k = 0
        while k < route.len and (at < 0 or port.output):
          if abs(route[k] - bx) < 0.01 and abs(route[k + 1] - by) < 0.01: at = k
          k += 3
        if at < 0: continue
        let a = if vertical: 0 else: 1
        var next = if port.output: at + 3 else: at - 3
        while next >= 0 and next < route.len and abs(route[next + a] - route[at + a]) < IN_LINE:
          next += (if port.output: 3 else: -3)
        if next < 0 or next >= route.len: continue
        port.hint = route[next + a] - (if vertical: box.x - box.w / 2 else: box.y - box.h / 2)
        seen.add ((if vertical: port.px else: port.py), port.hint)
      seen.sort(proc (p, q: (float, float)): int = orElse(p[0] - q[0], 0))
      for i in 1 ..< seen.len:
        if seen[i - 1][1] > seen[i][1]: again = true
    if again:
      let before = if crossings >= 0: crossings else: routeCrossings(nodes, edges, style)
      if before > 0:
        let first = snapshot(nodes, edges, order, total)
        place()
        if routeCrossings(nodes, edges, style) >= before: total = restore(first, nodes, edges, order)

  for ei in stray:
    let e = edges[ei]
    let a = nodes[e.src]
    let b = nodes[e.dst]
    e.route = @[a.x, a.y, 0, b.x, b.y, 0]
    e.labelX = (a.x + b.x) / 2
    e.labelY = (a.y + b.y) / 2
  for ei in loops:
    let e = edges[ei]
    let node = nodes[e.src]
    e.labelX = node.x + node.w / 2 + 28 + e.labelW / 2
    e.labelY = node.y

  total

## port-of: src/layout/layered.ts
## port-status: draft
##
## Layered (Sugiyama-style) layout of one flat graph. Ranks run down the y axis; callers
## rotate the result for other directions.
##
## What the layout of edges aims for, most important first. Where two aims pull apart, the one
## higher up decides, and each names where it is carried out.
##
## 1. Lines can be told apart. No two touch or run along each other, and none runs through a
##    node or a label. Ends on one side of a node have places of their own (`spread`), and
##    curves that would pass within a few pixels turn at levels of their own (`assignTracks`).
## 2. Lines cross as little as the order of the nodes allows (`reduceCrossings`, and the order
##    of the levels in `assignTracks`).
## 3. An edge takes the shortest and simplest way: straight if it can, else one curve, else a
##    curve with a level run. One that passes several ranks runs in line with one of its ends
##    and turns once, at the other (`alignLabels`, `straighten`). Ends slide along their sides,
##    and nodes move a little, where that makes an edge straight (`settle`, `snap`).
## 4. An edge meets the middle of a side. An end with a side to itself stays there, and ends
##    that share a side sit around the middle in the order of where they lead. An end moves off
##    the middle only for the aims above (`settle`).
## 5. The drawing is balanced, and what is alike is drawn alike. A label sits midway along the
##    line that shows, the curves either side of it have much the same room to turn in, and a gap
##    whose curves mostly cross has them all as the same plain curve rather than each on a
##    level of its own (`headRoom` in `layered`, the crossed gaps in `assignTracks`).
## 6. An edge leaves and reaches a node square to it, and an arrowhead points straight at the
##    node (`routePath` in svg/edges.ts, which draws the routes).
## 7. Nodes keep the order they were written in, where nothing above says otherwise.
## 8. The drawing stays compact. A gap between ranks grows only to hold the levels in it, or
##    to let curves that cross do so at a clear angle.
##
## Port notes. Typed arrays are seqs (`Int32Array` and `Uint8Array` are `seq[int]`); an array
## that may be `undefined` is an empty seq when it can never be empty once made, or comes with a
## flag of its own (`hasEndKinds`). The arrays that the helpers change in place live in the
## `Graph`, a ref object, as they are shared in the TypeScript. Sorts with a comparator are
## Nim's stable merge sort, as JavaScript's sort is stable; a comparator `d || f` is `orElse`.
import std/[algorithm, sets, tables]
from std/math import isNaN
import ../jsmath

type
  Kind* = enum
    kNode = 0, kDummy, kLabel, kStartPort, kEndPort

  LNode* = ref object
    w*, h*: float
    kind*: Kind
    pin*: float
    hint*: float
      ## Port's cross-flow destination; NaN if unknown. Fully hinted port ranks keep this order.
    key*: float
      ## Initial cross-flow position; NaN if unknown. Used only when every node in a rank has one.
    span*: float
      ## How much of the side that edges meet may be shared out between them; 0 keeps them all
      ## at its middle.
    x*, y*: float
    rank*: int

  LEdge* = ref object
    tail*, head*: int
    minlen*: int
    labelW*, labelH*: float
    tailDx*, headDx*: float
    tailFixed*, headFixed*: bool
      ## An end that is held where its offset puts it, and takes no part in sharing out a node's side.
    reversed*: bool
    points*: seq[float]
    labelX*, labelY*: float

  Groups* = object
    `of`*: seq[int]
    parent*: seq[int]

  LayeredOptions* = object
    nodeSep*, edgeSep*, rankSep*, portSep*: float
    tracks*: bool
      ## Route edges at right angles, each on a track of its own across the gap between two ranks.
    straight*: bool
      ## Draw every edge straight from point to point: none is given a level to turn onto.
    apart*: bool
      ## The caller sets the ends of the edges on one side of a node apart itself, so two edges
      ## between the same two nodes need no bend to keep them from being drawn as one.
    headRoom*: float
      ## The room that the marker at the head of an edge takes (0 for undefined). A rank of
      ## labels whose edges all head the same way sits half of this nearer their tails, so that
      ## each label is midway along the line that shows, and the curves either side of it have
      ## the same room to turn in.
    hasGroups*: bool
    groups*: Groups
      ## Keep each group contiguous within ranks. `of` maps nodes to groups; `parent` maps groups
      ## to parents. Both use -1 for none.
    orderOnly*: bool
      ## Compute cross-flow positions in `x` without full routing.

  LayeredResult* = object
    width*, height*: float
    crossings*, declared*: int
      ## With `orderOnly`: final crossings and crossings before grouping or reordering.

proc lnode*(w, h: float, kind = kNode): LNode =
  LNode(w: w, h: h, kind: kind, pin: 0, hint: NaN, key: NaN, span: 0, x: 0, y: 0, rank: 0)

proc ledge*(tail, head: int, minlen = 1, labelW = 0.0, labelH = 0.0): LEdge =
  LEdge(tail: tail, head: head, minlen: minlen, labelW: labelW, labelH: labelH)

const
  MAX_SWEEPS = 24
  MAX_DUMMIES = 20000
    ## An edge gets a bend point in every rank it skips. Past this many, the longest edges are
    ## drawn as one direct curve instead, which keeps huge graphs from exhausting time and memory.
  PORT_PITCH = 16.0
    ## The room between two edges that meet one side of a node, and the least that keeps their
    ## arrowheads apart.
  MIN_PITCH = 8.0
  MIN_SLOPE = 0.125
    ## Where edges are not given levels, a gap between ranks grows to keep the edges that cross
    ## it at least this steep, up to this many times its usual height. Shallower than that, the
    ## edges of a wide rank are hard to tell apart.
  MAX_GAP = 3.0
  TRACK_MARGIN = 18.0
    ## Tracks: the room kept clear between a rank and the nearest track, the room between two
    ## tracks when the gap has to grow to hold them, and the most they spread to when it has
    ## room to spare.
  TRACK_PITCH = 10.0
  TRACK_SPREAD = 14.0
  LEVEL_WIDE = 2.0
    ## A curve is one plain S unless it runs more than this many times as far across as the gap
    ## is high, and so does another that it would run along. Then each turns onto a level of its
    ## own to run across on. The levels of a gap keep this far from its ranks, to leave room to
    ## turn in, and from each other.
  LEVEL_MARGIN = 28.0
  LEVEL_PITCH = 12.0
  LEVEL_LEAD = 12.0
    ## Two plain curves that would pass too near each other turn at levels of their own as
    ## well: nearer than LEVEL_CLEAR where one of them runs far across, since it stays near the
    ## other for a long way, and otherwise nearer than LEVEL_TOUCH. LEVEL_LEAD is the room a
    ## plain curve is taken to keep straight at each end of its gap.
  LEVEL_CLEAR = 8.0
  LEVEL_TOUCH = 4.0
  CROSSED_SLOPE = 0.5
    ## Levels tell apart curves that run alongside each other. Where the curves of a gap cross
    ## each other more often than that, runs along levels only make the crossings long and
    ## shallow, so each curve is one plain S instead, and the gap is made this many times as
    ## tall as its widest curve runs across (and no taller than MAX_GAP allows), for them to
    ## cross at a clear angle.
  IN_LINE = 0.5
    ## How far out of line two points may be and still count as in line.
  TWIN = 1.0
    ## How far apart two edges may be at both ends and still count as twins.
  SNAP = 12.0
    ## A node, with whatever it is already in line with, moves this far at most to bring one
    ## more of its edges into line.
  BEND_SNAP = 24.0
    ## Bends with no node in line with them move this far at most to bring an edge into line.
  LEAN_CLEAR = 40.0
    ## An end that cannot be brought into line leans towards where its edge goes, but keeps this
    ## far from the ends of the part of its side that edges spread along. On a narrow node that
    ## leaves it in the middle.
  MAX_WEIGHED = 400
    ## Past this many edges across one gap, tracks are given out in a plain order: weighing
    ## every pair of edges against each other would take too long.
  SAMPLES = 16

  Held = 0
  Leaves = 1
  Arrives = 2

var
  LINE_A = newSeq[float](2 * SAMPLES + 2)
  LINE_B = newSeq[float](2 * SAMPLES + 2)
    ## Reuse curve-sampling buffers across layouts.

template orElse*(d: float, f: untyped): int =
  ## A JavaScript comparator `d || f`: the sign of `d`, or `f` when `d` is 0 or NaN.
  block:
    let x = d
    if x < 0: -1 elif x > 0: 1 else: f

proc choose[T](cond: bool, a, b: var T): ptr T {.inline.} =
  ## `addr a` or `addr b`. Not `if cond: addr a else: addr b`: Nim's JavaScript backend loses
  ## the field of such an address (Nim 2.2), and the port is also built with nim js.
  if cond: result = addr a
  else: result = addr b

func isDummy(kind: int): bool = kind == ord(kDummy) or kind == ord(kLabel)

proc sortRange(list: var seq[int], first, to: int, key: seq[float]) =
  for i in first + 1 ..< to:
    let item = list[i]
    let k = key[item]
    var j = i - 1
    while j >= first and (key[list[j]] > k or (key[list[j]] == k and list[j] > item)):
      list[j + 1] = list[j]
      dec j
    list[j + 1] = item

proc sortByBary(list: var seq[int], count: int, bary: seq[float], pos: seq[int], right: bool,
                spare: var seq[int]) =
  ## Avoid the comparator overhead of built-in sort.
  template before(a, b: int): bool =
    bary[a] < bary[b] or (bary[a] == bary[b] and (if right: pos[a] > pos[b] else: pos[a] < pos[b]))
  const RUN = 8
  var s = 0
  while s < count:
    let stop = min(count, s + RUN)
    for i in s + 1 ..< stop:
      let item = list[i]
      var j = i - 1
      while j >= s and before(item, list[j]):
        list[j + 1] = list[j]
        dec j
      list[j + 1] = item
    s += RUN
  # Merge runs, alternating between `list` and `spare`.
  var inList = true
  var width = RUN
  while width < count:
    template merge(src, dst: untyped) =
      var s = 0
      while s < count:
        let mid = min(count, s + width)
        let stop = min(count, s + 2 * width)
        var i = s
        var j = mid
        var k = s
        while i < mid and j < stop:
          if before(src[j], src[i]):
            dst[k] = src[j]; inc j
          else:
            dst[k] = src[i]; inc i
          inc k
        while i < mid:
          dst[k] = src[i]; inc i; inc k
        while j < stop:
          dst[k] = src[j]; inc j; inc k
        s += 2 * width
    if inList: merge(list, spare) else: merge(spare, list)
    inList = not inList
    width *= 2
  if not inList:
    for i in 0 ..< count: list[i] = spare[i]

type
  Pieces = object
    ## The pieces of edges that each cross one gap: where they leave the rank above and reach
    ## the one below, the rank above, the bend they end at (or -1 at the edge's last node), and
    ## the track they run across on (or -1 when they have none). Where only some pieces are
    ## given a level to turn onto, `wide` marks those that run far across, `levels` is how many
    ## tracks the group a piece belongs to takes, or 0 for a piece that needs none, and each
    ## piece's track counts from its group's first. A piece that is not `wide` curves from the
    ## level above its own.
    `from`, to: seq[float]
    rank, lower, track, levels, wide: seq[int]

  Graph = ref object
    n, real, maxRank: int
    W: seq[float]
    kinds: seq[int]           ## KIND
    RANK: seq[int]
    EF, ET: seq[int]          ## segment endpoints
    EFD, ETD: seq[float]      ## and where each segment attaches on them
    succStart, succE, predStart, predE: seq[int]
    layerStart, order, pos: seq[int]
    offsets: bool
    fixed: seq[int]           ## ranks whose order must remain fixed
    GRP: seq[int]             ## empty for undefined
    hasGroupParent: bool
    groupParent: seq[int]

proc orient*(nodes: seq[LNode], edges: seq[LEdge])
proc rank*(nodes: seq[LNode], edges: seq[LEdge], step: int)
proc spread(g: Graph, nodes: seq[LNode], EFK, ETK: seq[int])
proc follow(g: Graph, empty: seq[int], e0: int, side: int): int
proc alignPorts(g: Graph, xs: var seq[float], empty: seq[int])
proc freeEnds(g: Graph, EFK, ETK: seq[int]): array[2, seq[int]]
proc alignLabels(g: Graph, nodes: seq[LNode], xsVar: var seq[float], free: array[2, seq[int]],
                 opt: LayeredOptions, empty: seq[int])
proc settle(g: Graph, nodes: seq[LNode], xsVar: var seq[float], EFK, ETK: seq[int],
            free: array[2, seq[int]], empty: seq[int])
proc snap(g: Graph, xs: var seq[float], empty: seq[int], opt: LayeredOptions)
proc emptyRanks(g: Graph): seq[int]
proc assignTracks(piecesVar: var Pieces, trackCount: var seq[int], curved: bool, room: seq[float],
                  tall: var seq[float])
proc straighten(g: Graph, xs: var seq[float], empty: seq[int], firstDummy, span: seq[int],
                sep: float, onLine: var seq[int])
proc pastLabels(g: Graph, xs: var seq[float], firstDummy, span: seq[int], clear: float,
                onLine: var seq[int])
proc reduceCrossings(g: Graph, nodes: seq[LNode]): (int, int)
proc position(g: Graph, opt: LayeredOptions): seq[float]

proc sortLayer(g: Graph, s, e: int, cmp: proc (a, b: int): int) =
  ## `order.set(Array.from(order.subarray(s, e)).sort(cmp), s)`
  var layer = g.order[s ..< e]
  layer.sort(cmp)
  for i, v in layer: g.order[s + i] = v

proc layered*(nodes: seq[LNode], edges: seq[LEdge], opt: LayeredOptions): LayeredResult =
  let real = nodes.len
  if real == 0: return LayeredResult()
  let m = edges.len
  if real == 1 and m == 0 and nodes[0].kind == kNode:
    let node = nodes[0]
    node.rank = 0
    node.x = node.w / 2
    node.y = node.h / 2
    return LayeredResult(width: node.w, height: node.h)

  # Every edge gets a middle rank of its own when labels or parallel edges need the room.
  var step = 1
  if m > 0:
    var seen = initHashSet[int]()
    for e in edges:
      let a = min(e.tail, e.head)
      let b = max(e.tail, e.head)
      let key = a * real + b
      if e.labelW > 0 or key in seen:
        step = 2
        break
      seen.incl key

  orient(nodes, edges)
  rank(nodes, edges, step)

  var span = newSeq[int](m)
  var dummies = 0
  for ei in 0 ..< m:
    let e = edges[ei]
    span[ei] = abs(nodes[e.head].rank - nodes[e.tail].rank)
    if span[ei] > 1: dummies += span[ei] - 1
  var direct = newSeq[int](m)
  if dummies > MAX_DUMMIES:
    var longest: seq[int]
    for ei in 0 ..< m:
      if span[ei] > 1: longest.add ei
    longest.sort(proc (a, b: int): int =
      let d = span[b] - span[a]
      if d != 0: d else: a - b)
    for ei in longest:
      if dummies <= MAX_DUMMIES: break
      direct[ei] = 1
      dummies -= span[ei] - 1

  let n = real + dummies
  let g = Graph(n: n, real: real)
  g.W = newSeq[float](n)
  var H = newSeq[float](n)
  g.kinds = newSeq[int](n)
  g.RANK = newSeq[int](n)
  var maxRank = 0
  for i in 0 ..< real:
    let node = nodes[i]
    g.W[i] = node.w
    H[i] = node.h
    g.kinds[i] = ord(node.kind)
    g.RANK[i] = node.rank
    if node.rank > maxRank: maxRank = node.rank
  g.maxRank = maxRank

  # The graph that gets ordered and positioned: every edge cut into rank-to-rank segments.
  var segments = 0
  for ei in 0 ..< m:
    if direct[ei] == 0: segments += span[ei]
  g.EF = newSeq[int](segments)
  g.ET = newSeq[int](segments)
  g.EFD = newSeq[float](segments)
  g.ETD = newSeq[float](segments)
  var firstDummy = newSeq[int](m)
  for x in firstDummy.mitems: x = -1
  # Which way the edges with a label in each rank head: 1 down, 2 up, 3 both.
  var heads = newSeq[int](maxRank + 1)
  var labelNode = newSeq[int](m)
  for x in labelNode.mitems: x = -1
  var spans = false
  for i in 0 ..< real:
    if nodes[i].span > 0 and nodes[i].kind == kNode: spans = true
  # What each segment's end is to the node it meets, for the ends that may move along the node's side.
  let hasEndKinds = spans
  var EFK = (if spans: newSeq[int](segments) else: @[])
  var ETK = (if spans: newSeq[int](segments) else: @[])
  var firstSeg = newSeq[int](m)
  var lastSeg = newSeq[int](m)
  for i in 0 ..< m:
    firstSeg[i] = -1
    lastSeg[i] = -1
  var KEY = newSeq[float](n)
  for x in KEY.mitems: x = NaN
  for i in 0 ..< real: KEY[i] = nodes[i].key
  var offsets = false
  block:
    var next = real
    var ce = 0
    for ei in 0 ..< m:
      if direct[ei] != 0: continue
      let e = edges[ei]
      let a = if e.reversed: e.head else: e.tail
      let b = if e.reversed: e.tail else: e.head
      let aDx = if e.reversed: e.headDx else: e.tailDx
      let bDx = if e.reversed: e.tailDx else: e.headDx
      if aDx != 0 or bDx != 0: offsets = true
      let ra = g.RANK[a]
      let rb = g.RANK[b]
      var labelRank = -1
      if e.labelW > 0:
        # The label goes halfway along. An edge that passes ranks of nodes on its way has its
        # label in one of those, beside the nodes, where it takes no height of its own: the one
        # halfway, or of the two either side of halfway, the one nearer the node the edge starts
        # from, which is the lower when the edge runs against the flow. An edge between two
        # neighbouring ranks has its label in the rank between them.
        labelRank = ra + ((rb - ra) shr 1)
        if step == 2 and rb - ra >= 4:
          if (labelRank and 1) == 1: labelRank += (if e.reversed: 1 else: -1)
        elif step == 2 and (labelRank and 1) == 0: labelRank += (if e.reversed: 1 else: -1)
      var prev = a
      if rb - ra > 1: firstDummy[ei] = next
      firstSeg[ei] = ce
      if hasEndKinds and not (if e.reversed: e.headFixed else: e.tailFixed):
        EFK[ce] = if e.reversed: Arrives else: Leaves
      for r in ra + 1 ..< rb:
        let d = next
        inc next
        g.RANK[d] = r
        KEY[d] = KEY[a] + ((KEY[b] - KEY[a]) * float(r - ra)) / float(rb - ra)
        if r == labelRank:
          g.W[d] = e.labelW
          H[d] = e.labelH
          g.kinds[d] = ord(kLabel)
          labelNode[ei] = d
          heads[r] = heads[r] or (if e.reversed: 2 else: 1)
        else:
          g.kinds[d] = ord(kDummy)
        g.EF[ce] = prev
        g.ET[ce] = d
        g.EFD[ce] = if prev == a: aDx else: 0
        inc ce
        prev = d
      g.EF[ce] = prev
      g.ET[ce] = b
      g.EFD[ce] = if prev == a: aDx else: 0
      g.ETD[ce] = bDx
      if hasEndKinds and not (if e.reversed: e.tailFixed else: e.headFixed):
        ETK[ce] = if e.reversed: Leaves else: Arrives
      lastSeg[ei] = ce
      inc ce
  g.offsets = offsets

  # Bends belong to the innermost group containing both edge endpoints.
  if opt.hasGroups:
    let groupOf = opt.groups.`of`
    let parent = opt.groups.parent
    g.GRP = newSeq[int](n)
    for i in 0 ..< real: g.GRP[i] = groupOf[i]
    proc depth(gr0: int): int =
      var gr = gr0
      while gr >= 0:
        inc result
        gr = parent[gr]
    proc lca(x0, y0: int): int =
      var x = x0
      var y = y0
      var dx = depth(x)
      var dy = depth(y)
      while dx > dy:
        x = parent[x]
        dec dx
      while dy > dx:
        y = parent[y]
        dec dy
      while x != y:
        x = parent[x]
        y = parent[y]
      x
    for ei in 0 ..< m:
      if firstDummy[ei] < 0: continue
      let e = edges[ei]
      let gr = lca(groupOf[e.tail], groupOf[e.head])
      for d in firstDummy[ei] ..< firstDummy[ei] + span[ei] - 1: g.GRP[d] = gr
    g.hasGroupParent = true
    g.groupParent = parent

  g.succStart = newSeq[int](n + 1)
  g.predStart = newSeq[int](n + 1)
  for e in 0 ..< segments:
    inc g.succStart[g.EF[e] + 1]
    inc g.predStart[g.ET[e] + 1]
  for i in 0 ..< n:
    g.succStart[i + 1] += g.succStart[i]
    g.predStart[i + 1] += g.predStart[i]
  g.succE = newSeq[int](segments)
  g.predE = newSeq[int](segments)
  block:
    var sf = g.succStart[0 ..< n]
    var pf = g.predStart[0 ..< n]
    for e in 0 ..< segments:
      g.succE[sf[g.EF[e]]] = e
      inc sf[g.EF[e]]
      g.predE[pf[g.ET[e]]] = e
      inc pf[g.ET[e]]

  g.layerStart = newSeq[int](maxRank + 2)
  for i in 0 ..< n: inc g.layerStart[g.RANK[i] + 1]
  for r in 0 .. maxRank: g.layerStart[r + 1] += g.layerStart[r]
  g.order = newSeq[int](n)
  g.pos = newSeq[int](n)

  # Initial order: depth-first from the top so that subtrees start out contiguous.
  block:
    var byRank = newSeq[int](n)
    var fill = g.layerStart[0 .. maxRank]
    for i in 0 ..< n:
      byRank[fill[g.RANK[i]]] = i
      inc fill[g.RANK[i]]
    for r in 0 .. maxRank: fill[r] = g.layerStart[r]
    var visited = newSeq[bool](n)
    var stack: seq[int]
    for k in 0 ..< n:
      if visited[byRank[k]]: continue
      stack.add byRank[k]
      while stack.len > 0:
        let v = stack.pop()
        if visited[v]: continue
        visited[v] = true
        g.order[fill[g.RANK[v]]] = v
        inc fill[g.RANK[v]]
        var j = g.succStart[v + 1] - 1
        while j >= g.succStart[v]:
          let w = g.ET[g.succE[j]]
          if not visited[w]: stack.add w
          dec j

  proc sortRank(r: int, key: proc (v: int): float): bool =
    let s = g.layerStart[r]
    let e = g.layerStart[r + 1]
    if e - s < 2: return false
    for i in s ..< e:
      if isNaN(key(g.order[i])): return false
    var index = initTable[int, int]()
    for i in s ..< e: index[g.order[i]] = i - s
    g.sortLayer(s, e, proc (a, b: int): int = orElse(key(a) - key(b), index[a] - index[b]))
    true
  for r in 0 .. maxRank: discard sortRank(r, proc (v: int): float = KEY[v])

  var pinned = false
  for i in 0 ..< real:
    if nodes[i].pin != 0: pinned = true
  if pinned:
    for r in 0 .. maxRank:
      var index = initTable[int, int]()
      for i in g.layerStart[r] ..< g.layerStart[r + 1]: index[g.order[i]] = i - g.layerStart[r]
      proc pinOf(v: int): float = (if v < real: nodes[v].pin else: 0)
      g.sortLayer(g.layerStart[r], g.layerStart[r + 1], proc (a, b: int): int =
        orElse(pinOf(a) - pinOf(b), index[a] - index[b]))
  # Preserve port order to avoid crossings outside the group.
  g.fixed = newSeq[int](maxRank + 1)
  proc hint(v: int): float =
    if v < real and (nodes[v].kind == kStartPort or nodes[v].kind == kEndPort): nodes[v].hint else: NaN
  for r in [0, maxRank]:
    if sortRank(r, hint): g.fixed[r] = 1
  proc setPositions() =
    for r in 0 .. maxRank:
      let s = g.layerStart[r]
      for i in s ..< g.layerStart[r + 1]: g.pos[g.order[i]] = i - s
  setPositions()

  var crossings = 0
  var declared = 0
  if segments > 0 and maxRank > 0:
    (crossings, declared) = reduceCrossings(g, nodes)
    setPositions()
  if opt.orderOnly:
    # Points are (rank, cross-flow position) pairs.
    let at = position(g, opt)
    for i in 0 ..< real: nodes[i].x = at[i]
    for ei in 0 ..< m:
      let e = edges[ei]
      let a = if e.reversed: e.head else: e.tail
      let b = if e.reversed: e.tail else: e.head
      var pts = @[float(g.RANK[a]), at[a]]
      if direct[ei] == 0 and firstDummy[ei] >= 0:
        for d in firstDummy[ei] ..< firstDummy[ei] + span[ei] - 1: pts.add [float(g.RANK[d]), at[d]]
      pts.add [float(g.RANK[b]), at[b]]
      e.points = pts
    return LayeredResult(width: 0, height: 0, crossings: crossings, declared: declared)

  if hasEndKinds: spread(g, nodes, EFK, ETK)

  var xs = position(g, opt)

  let empty = emptyRanks(g)
  let hasEmpty = empty.len > 0
  if hasEndKinds:
    let free = freeEnds(g, EFK, ETK)
    alignLabels(g, nodes, xs, free, opt, empty)
    settle(g, nodes, xs, EFK, ETK, free, empty)
    snap(g, xs, empty, opt)
    for ei in 0 ..< m:
      if direct[ei] != 0: continue
      let e = edges[ei]
      let aDx = g.EFD[firstSeg[ei]]
      let bDx = g.ETD[lastSeg[ei]]
      e.tailDx = if e.reversed: bDx else: aDx
      e.headDx = if e.reversed: aDx else: bDx

  alignPorts(g, xs, empty)

  # A rank that holds nothing but the bends of edges is only there because some other edge has a
  # label or a twin. Its bends move onto the straight line between the ends of their edges, and
  # one that gets there is left out of the route, so that the edge is drawn as a single curve.
  var onLine = newSeq[int](n)
  if hasEmpty and not opt.tracks:
    straighten(g, xs, empty, firstDummy, span, (if opt.apart: 0.0 else: opt.edgeSep), onLine)
  if not opt.tracks: pastLabels(g, xs, firstDummy, span, opt.edgeSep, onLine)
  # An edge is cut where it passes a rank that holds something, and each piece crosses one gap.
  # With `tracks`, every piece that does not run straight gets a track to run across on at
  # right angles. Otherwise, where edges spread along their nodes, a piece gets one only if it
  # needs a level to turn onto. `pieceStart` gives every edge's run of pieces.
  var pieceStart = newSeq[int](m + 1)
  let hasPieces = opt.tracks or (hasEndKinds and not opt.straight)
  var pieces: Pieces
  var trackCount = newSeq[int](maxRank + 1)
  if hasPieces:
    for ei in 0 ..< m:
      pieceStart[ei] = pieces.`from`.len
      if direct[ei] != 0: continue
      let d0 = firstDummy[ei]
      let stop = if d0 < 0: d0 else: d0 + span[ei] - 1
      # An edge that keeps a bend to stay clear of its twin is drawn through the bend, as it is.
      var twin = false
      for d in d0 ..< stop:
        # So is one that has a bend left out in a rank of labels: its curve crosses that rank.
        let bare = hasEmpty and empty[g.RANK[d]] == 1
        if not opt.tracks and bare != (onLine[d] == 1): twin = true
      if twin: continue
      var x = xs[g.EF[firstSeg[ei]]] + g.EFD[firstSeg[ei]]
      var rank = g.RANK[g.EF[firstSeg[ei]]]
      for d in d0 ..< stop:
        if hasEmpty and empty[g.RANK[d]] != 0: continue
        pieces.`from`.add x
        pieces.to.add xs[d]
        pieces.rank.add rank
        pieces.lower.add d
        x = xs[d]
        rank = g.RANK[d]
      pieces.`from`.add x
      pieces.to.add xs[g.ET[lastSeg[ei]]] + g.ETD[lastSeg[ei]]
      pieces.rank.add rank
      pieces.lower.add -1
    pieceStart[m] = pieces.`from`.len

  # Ranks that hold only border ports or their pass-through dummies need little room of their own.
  proc portOnly(r: int, kind: Kind): bool =
    var found = false
    for i in g.layerStart[r] ..< g.layerStart[r + 1]:
      let k = g.kinds[g.order[i]]
      if k == ord(kind): found = true
      elif k != ord(kDummy): return false
    found
  let startRanks = if portOnly(0, kStartPort): step else: 0
  let endRanks = if portOnly(maxRank, kEndPort): step else: 0
  # The longest way across that any edge travels in the gap below each rank.
  var run = newSeq[float](maxRank + 1)
  for e in 0 ..< segments:
    let across = abs(xs[g.EF[e]] + g.EFD[e] - xs[g.ET[e]] - g.ETD[e])
    if across > run[g.RANK[g.EF[e]]]: run[g.RANK[g.EF[e]]] = across
  var bandTop = newSeq[float](maxRank + 1)
  var bandBottom = newSeq[float](maxRank + 1)
  proc usual(r: int): float =
    (if r < startRanks or r >= maxRank - endRanks: opt.portSep else: opt.rankSep) / float(step)
  # The room under each rank. Edges that are not cut into pieces need more where they run far across.
  var gapUnder = newSeq[float](maxRank + 1)
  for r in 0 ..< maxRank:
    gapUnder[r] = if hasPieces: usual(r)
                  else: max(usual(r), min((MAX_GAP * opt.rankSep) / float(step), run[r] * MIN_SLOPE))
  # A rank between two ranks of nodes, which holds labels and bends only.
  var between = newSeq[int](maxRank + 1)
  for x in between.mitems: x = 1
  for i in 0 ..< real: between[g.RANK[i]] = 0
  for r in 1 ..< maxRank:
    if opt.tracks or between[r] == 0 or (heads[r] != 1 and heads[r] != 2): continue
    let shift = min(opt.headRoom / 2, gapUnder[if heads[r] == 1: r - 1 else: r] / 2)
    gapUnder[r - 1] += (if heads[r] == 1: -shift else: shift)
    gapUnder[r] += (if heads[r] == 1: shift else: -shift)
  # The part of its rank that an edge runs straight through at a bend or label. A bare bend
  # beside labels keeps to the middle half, which leaves the curves either side of it more room
  # and still keeps them clear of the labels' corners.
  proc inset(d: int): float =
    if g.kinds[d] == ord(kDummy) and between[g.RANK[d]] != 0 and not opt.tracks:
      (bandBottom[g.RANK[d]] - bandTop[g.RANK[d]]) / 4
    else: 0
  # The rank that the pieces leaving each rank arrive at, past any that hold only bends, and
  # the room between the two, which grows to hold the gap's tracks or levels: these keep
  # `margin` from the ranks, and between `leastPitch` and `mostPitch` from each other.
  let margin = if opt.tracks: TRACK_MARGIN else: LEVEL_MARGIN
  let leastPitch = if opt.tracks: TRACK_PITCH else: LEVEL_PITCH
  let mostPitch = if opt.tracks: TRACK_SPREAD else: LEVEL_PITCH
  var below = newSeq[int](maxRank + 1)
  if hasPieces:
    var room = newSeq[float](maxRank + 1)
    for r in 0 ..< maxRank:
      if hasEmpty and empty[r] != 0: continue
      var next = r + 1
      room[r] = gapUnder[r]
      while next < maxRank and hasEmpty and empty[next] != 0:
        room[r] += gapUnder[next]
        inc next
      below[r] = next
    for k in 0 ..< pieces.`from`.len:
      pieces.wide.add(if abs(pieces.`from`[k] - pieces.to[k]) > LEVEL_WIDE * room[pieces.rank[k]]: 1 else: 0)
    var tall = newSeq[float](maxRank + 1)
    assignTracks(pieces, trackCount, not opt.tracks, room, tall)
    for r in 0 ..< maxRank:
      if trackCount[r] > 0:
        gapUnder[r] += max(0.0, 2 * margin + float(trackCount[r] - 1) * leastPitch - room[r])
      elif tall[r] > 0:
        gapUnder[r] += max(0.0, min(MAX_GAP * opt.rankSep, tall[r]) - room[r])
  var y = 0.0
  for r in 0 .. maxRank:
    var h = 0.0
    for i in g.layerStart[r] ..< g.layerStart[r + 1]:
      if H[g.order[i]] > h: h = H[g.order[i]]
    bandTop[r] = y
    bandBottom[r] = y + h
    y += h + gapUnder[r]
  let height = y
  # Where a piece runs across its gap, or would on another track of its group: its tracks sit
  # in the middle of the gap, the first at the top.
  proc trackY(piece: int, onTrack: int): float =
    let r = pieces.rank[piece]
    let top = bandBottom[r]
    let bottom = bandTop[below[r]]
    let count = if opt.tracks: trackCount[r] else: pieces.levels[piece]
    let pitch = if count > 1: min(mostPitch, (bottom - top - 2 * margin) / float(count - 1)) else: 0
    (top + bottom) / 2 + (float(onTrack) - float(count - 1) / 2) * pitch

  var minX = Inf
  var maxX = -Inf
  for i in 0 ..< n:
    let half = g.W[i] / 2
    if xs[i] - half < minX: minX = xs[i] - half
    if xs[i] + half > maxX: maxX = xs[i] + half
  # Where edges spread along their nodes, a rank whose nodes only send edges on stands on one
  # line, and a rank whose nodes only receive them hangs from one, so that the edges of nodes of
  # different heights set out from, or arrive at, the same level. In any other rank the nodes
  # are centered.
  var arrives = newSeq[bool](maxRank + 1)
  var leaves = newSeq[bool](maxRank + 1)
  for i in 0 ..< real:
    if g.kinds[i] != ord(kNode) or not hasEndKinds: continue
    if g.predStart[i + 1] > g.predStart[i]: arrives[g.RANK[i]] = true
    if g.succStart[i + 1] > g.succStart[i]: leaves[g.RANK[i]] = true
  for i in 0 ..< real:
    let node = nodes[i]
    let r = node.rank
    node.x = xs[i] - minX
    if g.kinds[i] == ord(kNode) and leaves[r] and not arrives[r]: node.y = bandBottom[r] - node.h / 2
    elif g.kinds[i] == ord(kNode) and arrives[r] and not leaves[r]: node.y = bandTop[r] + node.h / 2
    else: node.y = (bandTop[r] + bandBottom[r]) / 2

  for ei in 0 ..< m:
    let e = edges[ei]
    let first = nodes[if e.reversed: e.head else: e.tail]
    let last = nodes[if e.reversed: e.tail else: e.head]
    var pts = @[first.x + (if e.reversed: e.headDx else: e.tailDx), first.y + first.h / 2]
    let d0 = firstDummy[ei]
    if hasPieces and pieceStart[ei + 1] > pieceStart[ei]:
      for k in pieceStart[ei] ..< pieceStart[ei + 1]:
        if pieces.track[k] >= 0 and (opt.tracks or pieces.wide[k] == 1):
          let across = trackY(k, pieces.track[k])
          pts.add [pieces.`from`[k] - minX, across, pieces.to[k] - minX, across]
        elif pieces.track[k] > 0:
          # A short piece among levels runs straight until it is past the level before its
          # own, and turns in one S from there, so that it crosses none of them.
          pts.add [pieces.`from`[k] - minX, trackY(k, pieces.track[k] - 1)]
        let d = pieces.lower[k]
        if d < 0: continue
        pts.add [xs[d] - minX, bandTop[g.RANK[d]] + inset(d)]
        if bandBottom[g.RANK[d]] > bandTop[g.RANK[d]]: pts.add [xs[d] - minX, bandBottom[g.RANK[d]] - inset(d)]
    elif d0 >= 0:
      for d in d0 ..< d0 + span[ei] - 1:
        if onLine[d] != 0: continue
        let x = xs[d] - minX
        let top = bandTop[g.RANK[d]]
        let bottom = bandBottom[g.RANK[d]]
        pts.add [x, top + inset(d)]
        if bottom > top: pts.add [x, bottom - inset(d)]
    pts.add [last.x + (if e.reversed: e.tailDx else: e.headDx), last.y - last.h / 2]
    if e.reversed:
      var i = 0
      var j = pts.len - 2
      while i < j:
        swap(pts[i], pts[j])
        swap(pts[i + 1], pts[j + 1])
        i += 2
        j -= 2
    e.points = pts
    let ln = labelNode[ei]
    if ln >= 0:
      e.labelX = xs[ln] - minX
      e.labelY = (bandTop[g.RANK[ln]] + bandBottom[g.RANK[ln]]) / 2
    elif e.labelW > 0:
      e.labelX = (pts[0] + pts[pts.len - 2]) / 2
      e.labelY = (pts[1] + pts[pts.len - 1]) / 2

  LayeredResult(width: maxX - minX, height: height)

proc orient*(nodes: seq[LNode], edges: seq[LEdge]) =
  ## Reverses the edges that close a cycle, found by depth-first search in declaration order.
  let n = nodes.len
  let m = edges.len
  var start = newSeq[int](n + 1)
  for i in 0 ..< m:
    let e = edges[i]
    e.reversed = nodes[e.head].kind == kStartPort or nodes[e.tail].kind == kEndPort
    if not e.reversed: inc start[e.tail + 1]
  for i in 0 ..< n: start[i + 1] += start[i]
  var output = newSeq[int](start[n])
  block:
    var fill = start[0 ..< n]
    for i in 0 ..< m:
      if not edges[i].reversed:
        output[fill[edges[i].tail]] = i
        inc fill[edges[i].tail]
  var state = newSeq[int](n)
  var cursor = start[0 ..< n]
  var stack: seq[int]
  for root in 0 ..< n:
    if state[root] != 0: continue
    stack.add root
    state[root] = 1
    while stack.len > 0:
      let v = stack[^1]
      if cursor[v] < start[v + 1]:
        let e = edges[output[cursor[v]]]
        inc cursor[v]
        let w = e.head
        if state[w] == 1: e.reversed = true
        elif state[w] == 0:
          state[w] = 1
          stack.add w
      else:
        state[v] = 2
        discard stack.pop()

proc rank*(nodes: seq[LNode], edges: seq[LEdge], step: int) =
  let n = nodes.len
  let m = edges.len
  var source = newSeq[int](m)
  var to = newSeq[int](m)
  var len = newSeq[int](m)
  var outStart = newSeq[int](n + 1)
  var inStart = newSeq[int](n + 1)
  for i in 0 ..< m:
    let e = edges[i]
    let a = if e.reversed: e.head else: e.tail
    let b = if e.reversed: e.tail else: e.head
    source[i] = a
    to[i] = b
    len[i] = max(1, e.minlen) * step
    inc outStart[a + 1]
    inc inStart[b + 1]
  for i in 0 ..< n:
    outStart[i + 1] += outStart[i]
    inStart[i + 1] += inStart[i]
  var outE = newSeq[int](m)
  var inE = newSeq[int](m)
  block:
    var outFill = outStart[0 ..< n]
    var inFill = inStart[0 ..< n]
    for i in 0 ..< m:
      outE[outFill[source[i]]] = i
      inc outFill[source[i]]
      inE[inFill[to[i]]] = i
      inc inFill[to[i]]

  var r = newSeq[int](n)
  # Start ports go above every node later, so they don't push their targets down a rank.
  for i in 0 ..< n:
    if nodes[i].kind == kStartPort: r[i] = -step
  var indeg = newSeq[int](n)
  for i in 0 ..< n: indeg[i] = inStart[i + 1] - inStart[i]
  var topo = newSeq[int](n)
  var count = 0
  for i in 0 ..< n:
    if indeg[i] == 0:
      topo[count] = i
      inc count
  var q = 0
  while q < count:
    let v = topo[q]
    for k in outStart[v] ..< outStart[v + 1]:
      let ei = outE[k]
      let w = to[ei]
      if r[v] + len[ei] > r[w]: r[w] = r[v] + len[ei]
      dec indeg[w]
      if indeg[w] == 0:
        topo[count] = w
        inc count
    inc q

  # Longest-path ranking leaves loosely attached nodes far from their neighbours.
  # Move each node toward the side that has more edges.
  for pass in 0 ..< 8:
    var changed = false
    var q = count - 1
    while q >= 0:
      let v = topo[q]
      dec q
      let ins = inStart[v + 1] - inStart[v]
      let outs = outStart[v + 1] - outStart[v]
      if ins == 0 and outs == 0: continue
      var lo = low(int)
      var hi = high(int)
      for k in inStart[v] ..< inStart[v + 1]:
        let ei = inE[k]
        lo = max(lo, r[source[ei]] + len[ei])
      for k in outStart[v] ..< outStart[v + 1]:
        let ei = outE[k]
        hi = min(hi, r[to[ei]] - len[ei])
      var next = r[v]
      if outs > ins and hi != high(int): next = hi
      elif ins > outs and lo != low(int): next = lo
      if next != r[v]:
        r[v] = next
        changed = true
    if not changed: break

  var lo = high(int)
  var hi = low(int)
  var startPorts = false
  for i in 0 ..< n:
    let kind = nodes[i].kind
    if kind == kStartPort: startPorts = true
    if kind == kStartPort or kind == kEndPort: continue
    if r[i] < lo: lo = r[i]
    if r[i] > hi: hi = r[i]
  if lo == high(int):
    lo = 0
    hi = 0
  for i in 0 ..< n:
    if nodes[i].kind == kStartPort: r[i] = lo - step
    elif nodes[i].kind == kEndPort: r[i] = hi + step
  if startPorts: lo -= step
  for i in 0 ..< n: nodes[i].rank = r[i] - lo

proc sideEnds(g: Graph, v, side: int, span: float, kinds: seq[int], idsVar: var seq[int],
              roomVar: var seq[float]): float =
  ## The ends of edges that may move along one side of a node (0 the side its edges arrive at,
  ## 1 the other), ordered by their opposite nodes to avoid crossings. `ids` and `room` must
  ## start empty. `ids` receives the ends; `room` receives their minimum gaps. Returns the sum
  ## of the gaps. When there is too little room for a full pitch between each pair, the edges
  ## that leave side by side move closer together, since they have no arrowheads to keep apart.
  ## With less room still, neighbours that run the same way share a place, which keeps an
  ## arrowhead apart from an edge that leaves beside it.
  let idsP = addr idsVar
  let roomP = addr roomVar
  template ids: untyped = idsP[]
  template room: untyped = roomP[]
  let startP = choose(side == 0, g.predStart, g.succStart)
  let listP = choose(side == 0, g.predE, g.succE)
  let otherP = choose(side == 0, g.EF, g.ET)
  template start: untyped = startP[]
  template list: untyped = listP[]
  template other: untyped = otherP[]
  for k in start[v] ..< start[v + 1]:
    if kinds[list[k]] != Held: ids.add list[k]
  if ids.len < 2: return 0
  ids.sort(proc (a, b: int): int =
    let d = g.pos[other[a]] - g.pos[other[b]]
    if d != 0: d else: a - b)
  room.setLen(ids.len)
  proc fill(share: proc (leaves, same: bool): float): float =
    var total = 0.0
    room[0] = 0
    for k in 1 ..< ids.len:
      let same = kinds[ids[k]] == kinds[ids[k - 1]]
      room[k] = share(same and kinds[ids[k]] == Leaves, same)
      total += room[k]
    total
  var total = fill(proc (leaves, same: bool): float = 1)
  if span / total < MIN_PITCH: total = fill(proc (leaves, same: bool): float = (if leaves: 0.5 else: 1))
  if span / total < MIN_PITCH: total = fill(proc (leaves, same: bool): float = (if same: 0 else: 1))
  if total == 0: return 0
  let pitch = min(PORT_PITCH, span / total)
  for k in 1 ..< ids.len: room[k] *= pitch
  total * pitch

proc spread(g: Graph, nodes: seq[LNode], EFK, ETK: seq[int]) =
  ## Gives the edges that meet one side of a node places of their own along it, around its middle.
  for v in 0 ..< g.real:
    let span = min(nodes[v].span, g.W[v])
    if span <= 0 or nodes[v].kind != kNode: continue
    for side in 0 ..< 2:
      var ids: seq[int]
      var room: seq[float]
      let total = if side == 0: sideEnds(g, v, side, span, ETK, ids, room)
                  else: sideEnds(g, v, side, span, EFK, ids, room)
      if total == 0: continue
      var at = -total / 2
      for k in 0 ..< ids.len:
        at += room[k]
        if side == 0: g.ETD[ids[k]] = at else: g.EFD[ids[k]] = at

proc follow(g: Graph, empty: seq[int], e0: int, side: int): int =
  ## The segment of an edge that reaches the next point held in place, on the way up from
  ## segment `e` (side 0) or down: past the bends in ranks that hold nothing else.
  var e = e0
  if empty.len == 0: return e
  for hops in 0 ..< 100000:
    let u = if side == 0: g.EF[e] else: g.ET[e]
    if g.kinds[u] != ord(kDummy) or empty[g.RANK[u]] == 0: break
    e = if side == 0: g.predE[g.predStart[u]] else: g.succE[g.succStart[u]]
  e

proc alignPorts(g: Graph, xs: var seq[float], empty: seq[int]) =
  ## Aligns border ports with the ends on their nodes so edges run straight across the gap.
  ## Ports are kept `edgeSep` apart while placed, more than ends on a short side get, so
  ## without this an edge turns outside the border and again in the gap.
  ## Leaves a rank alone unless every port can move without passing or meeting its neighbors.
  for (r, kind) in [(0, kStartPort), (g.maxRank, kEndPort)]:
    let s = g.layerStart[r]
    let stop = g.layerStart[r + 1]
    var to: seq[float]
    for i in s ..< stop:
      let v = g.order[i]
      let start = kind == kStartPort
      if g.kinds[v] != ord(kind) or
         (if start: g.succStart[v + 1] - g.succStart[v] else: g.predStart[v + 1] - g.predStart[v]) != 1:
        break
      let e = follow(g, empty, (if start: g.succE[g.succStart[v]] else: g.predE[g.predStart[v]]),
                     (if start: 1 else: 0))
      let at = if start: xs[g.ET[e]] + g.ETD[e] else: xs[g.EF[e]] + g.EFD[e]
      if to.len > 0 and at < to[^1] + TWIN: break
      to.add at
    if to.len == 0 or to.len != stop - s: continue
    for i in s ..< stop: xs[g.order[i]] = to[i - s]

proc freeEnds(g: Graph, EFK, ETK: seq[int]): array[2, seq[int]] =
  ## How many ends that may move along it each node has on the side its edges arrive at, and on
  ## the other. An end that has a side to itself keeps to the middle; ends that share one cannot
  ## all be there, so those may move.
  result = [newSeq[int](g.n), newSeq[int](g.n)]
  for e in 0 ..< g.EF.len:
    if ETK[e] != Held: inc result[0][g.ET[e]]
    if EFK[e] != Held: inc result[1][g.EF[e]]

proc ease*(across, along: float): float =
  ## How far along the flow the handles of a plain S reach, as a share of the way it travels
  ## along it. Half gives an even S. One that runs more than eight times as far across as along
  ## turns sooner and crosses in a straighter line, down to a quarter at sixteen times. The
  ## layout uses this to tell how near two curves will pass, and the drawing to draw them.
  let a = abs(across)
  max(0.25, min(0.5, (4 * abs(along)) / (if a == 0 or isNaN(a): 1.0 else: a)))

proc alignLabels(g: Graph, nodes: seq[LNode], xsVar: var seq[float], free: array[2, seq[int]],
                 opt: LayeredOptions, empty: seq[int]) =
  let xsP = addr xsVar
  template xs: untyped = xsP[]
  ## Brings the labels and bends of each edge into line with an end of the edge, so that it runs
  ## straight from that end and turns once, at the other: with the end that has fewer edges
  ## beside it on its node, which is the one nearer the middle of its side, or else with the
  ## other, and as near to that as what is beside them in their ranks leaves room. The other end
  ## may then move along its node to meet the line. Bends in ranks that hold nothing else are
  ## left to `straighten`. An edge with no one line that all of its labels and bends have room
  ## on has each brought into line with the nearest point above or below that is held in place.
  let sep = opt.edgeSep
  let real = g.real
  proc placed(v: int): bool =
    g.kinds[v] == ord(kLabel) or
      (g.kinds[v] == ord(kDummy) and not (empty.len > 0 and empty[g.RANK[v]] == 1))
  # Where segment `e` ends on the way up (side 0) or down, and how many ends share that side of
  # the node there: none for a point that is not on a node.
  proc stop(e, side: int): (float, int) =
    let u = if side == 0: g.EF[e] else: g.ET[e]
    let x = if side == 0: xs[u] + g.EFD[e] else: xs[u] + g.ETD[e]
    (x, (if u < real and nodes[u].kind == kNode: free[1 - side][u] else: 0))
  # The room the neighbours in its rank leave a label or bend: a full gap from a node or between
  # two labels, half of one between a label and a line that passes it.
  proc room(v: int): (float, float) =
    let s = g.layerStart[g.RANK[v]]
    let i = s + g.pos[v]
    proc clear(other: int): float =
      g.W[other] / 2 + g.W[v] / 2 +
        (if g.kinds[other] == ord(kNode): opt.nodeSep / 2 + sep / 2
         elif g.kinds[other] == g.kinds[v]: sep
         else: sep / 2)
    ((if i > s: xs[g.order[i - 1]] + clear(g.order[i - 1]) else: -Inf),
     (if i + 1 < g.layerStart[g.RANK[v] + 1]: xs[g.order[i + 1]] - clear(g.order[i + 1]) else: Inf))
  # The place between `lo` and `hi` that is in line with one of two ends, or else nearest the first choice.
  proc choose(x: float, up, down: (float, int), lo, hi: float): float =
    let upFirst = if up[1] != down[1]: up[1] < down[1] else: abs(up[0] - x) <= abs(down[0] - x)
    let choices = if upFirst: [up[0], down[0]] else: [down[0], up[0]]
    for choice in choices:
      if choice >= lo and choice <= hi: return choice
    max(lo, min(hi, choices[0]))
  var done = newSeq[bool](g.n)
  var chain: seq[int]
  for r in 1 ..< g.maxRank:
    for i in g.layerStart[r] ..< g.layerStart[r + 1]:
      if not placed(g.order[i]) or done[g.order[i]]: continue
      # The edge's labels and bends from its first node to its last, and the room they share.
      var top = g.order[i]
      while isDummy(g.kinds[g.EF[g.predE[g.predStart[top]]]]): top = g.EF[g.predE[g.predStart[top]]]
      var bottom = top
      var lo = -Inf
      var hi = Inf
      chain.setLen 0
      var d = top
      while isDummy(g.kinds[d]):
        bottom = d
        if placed(d):
          done[d] = true
          chain.add d
          let (least, most) = room(d)
          if least > lo: lo = least
          if most < hi: hi = most
        d = g.ET[g.succE[g.succStart[d]]]
      if lo <= hi:
        let x = choose(xs[chain[0]], stop(g.predE[g.predStart[top]], 0),
                       stop(g.succE[g.succStart[bottom]], 1), lo, hi)
        for d in chain: xs[d] = x
        continue
      for d in chain:
        let (least, most) = room(d)
        if least > most: continue
        xs[d] = choose(xs[d], stop(follow(g, empty, g.predE[g.predStart[d]], 0), 0),
                       stop(follow(g, empty, g.succE[g.succStart[d]], 1), 1), least, most)

type SideInfo = object
  v, side: int
  span: float
  ids: seq[int]
  room: seq[float]
  all: seq[int]

proc settle(g: Graph, nodes: seq[LNode], xsVar: var seq[float], EFK, ETK: seq[int],
            free: array[2, seq[int]], empty: seq[int]) =
  let xsP = addr xsVar
  template xs: untyped = xsP[]
  ## Once the nodes have their places, moves an end along its side when that lets its edge run
  ## straight: when the point the edge runs to, or some part of the side it runs to, is in line
  ## with the end's own side. Any other end leans towards the point its edge runs to, where its
  ## side is long enough, and an end with a side to itself stays in the middle. On a group, the
  ## ends keep clear of the points where other edges pass through its border.
  let real = g.real
  # Where the end of segment `e` on node `v` should be, from the middle of its side. The edge is
  # followed up from the segment (side 0) or down, past the bends in ranks that hold nothing
  # else, to where it next comes to a point that is held in place or to another node's side.
  proc wanted(e0, side, v: int, span: float, again: bool): float =
    if free[side][v] < 2: return 0
    let e = follow(g, empty, e0, side)
    let u = if side == 0: g.EF[e] else: g.ET[e]
    let point = if side == 0: xs[u] + g.EFD[e] else: xs[u] + g.ETD[e]
    # Once the other end has its place, this one comes into line with it if it can.
    if again and abs(point - xs[v]) <= span / 2 + IN_LINE: return max(-span / 2, min(span / 2, point - xs[v]))
    # The part of the other side that its end may move along, if it may move.
    var middle = point
    var width = 0.0
    if u < real and nodes[u].kind == kNode and (if side == 0: EFK[e] else: ETK[e]) != Held and free[1 - side][u] >= 2:
      width = max(0.0, min(nodes[u].span, g.W[u]))
      if width > 0: middle = xs[u]
    let lo = max(xs[v] - span / 2, middle - width / 2)
    let hi = min(xs[v] + span / 2, middle + width / 2)
    # Two sides with no part in line: the end leans towards the other, if its side is long enough.
    if lo > hi + IN_LINE:
      let lean = max(0.0, span / 2 - LEAN_CLEAR)
      return max(-lean, min(lean, point - xs[v]))
    # Both ends settle on one place in the part the two sides share: nearer the middle of the narrower.
    let place = (xs[v] * width + middle * span) / (width + span)
    max(lo, min(hi, place)) - xs[v]
  # End order and spacing stay fixed across passes; held ends divide free ends into runs.
  var sides: seq[SideInfo]
  for v in 0 ..< real:
    let span = min(nodes[v].span, g.W[v])
    if span <= 0 or nodes[v].kind != kNode: continue
    for side in 0 ..< 2:
      var ids: seq[int]
      var room: seq[float]
      if side == 0: discard sideEnds(g, v, side, span, ETK, ids, room)
      else: discard sideEnds(g, v, side, span, EFK, ids, room)
      if ids.len == 0: continue
      if ids.len == 1: room = @[0.0]
      var all: seq[int]
      let startP = choose(side == 0, g.predStart, g.succStart)
      let listP = choose(side == 0, g.predE, g.succE)
      let otherP = choose(side == 0, g.EF, g.ET)
      for k in startP[][v] ..< startP[][v + 1]: all.add listP[][k]
      all.sort(proc (a, b: int): int =
        let d = g.pos[otherP[][a]] - g.pos[otherP[][b]]
        if d != 0: d else: a - b)
      sides.add SideInfo(v: v, side: side, span: span, ids: ids, room: room, all: all)
  # The ends of an edge follow each other, so the nodes are gone over until none moves: a few
  # times at most, in practice.
  var pass = 0
  var moved = true
  while moved and pass < 6:
    moved = false
    for info in sides:
      let (v, side, span) = (info.v, info.side, info.span)
      template ids: untyped = info.ids
      template room: untyped = info.room
      template all: untyped = info.all
      let dxP = choose(side == 0, g.ETD, g.EFD)
      template kinds(i: int): int = (if side == 0: ETK[i] else: EFK[i])
      template dx: untyped = dxP[]
      var k = 0
      var lo = -span / 2
      for i in 0 .. all.len:
        let held = i < all.len and kinds(all[i]) == Held
        if i < all.len and not held: continue
        # Free ends since the last held end occupy ids[k..k + size).
        var size = 0
        var j0 = i - 1
        while j0 >= 0 and kinds(all[j0]) != Held:
          inc size
          dec j0
        let hi = if held: dx[all[i]] - PORT_PITCH else: span / 2
        if size > 0:
          # Isotonic fitting preserves order and spacing by pooling neighbours that are too close.
          var sum: seq[float]
          var count: seq[float]
          var before = 0.0
          for j in 0 ..< size:
            if j > 0: before += room[k + j]
            sum.add wanted(ids[k + j], side, v, span, pass > 0) - before
            count.add 1
            # Keep ends together when spacing forced them to share a place.
            var together = j > 0 and room[k + j] == 0
            while sum.len > 1 and (together or sum[^2] / count[^2] > sum[^1] / count[^1]):
              together = false
              let top = sum.pop()
              let pooled = count.pop()
              sum[^1] += top
              count[^1] += pooled
          let total = before
          var j = 0
          before = 0
          for b in 0 ..< sum.len:
            # Center the run if it cannot fit between held ends.
            let level = if hi - total < lo: (lo + hi - total) / 2
                        else: max(lo, min(hi - total, sum[b] / count[b]))
            var c = 0.0
            while c < count[b]:
              if j > 0: before += room[k + j]
              if abs(dx[ids[k + j]] - level - before) > 0.01: moved = true
              dx[ids[k + j]] = level + before
              c += 1
              inc j
          k += size
        if held: lo = dx[all[i]] + PORT_PITCH
    inc pass

proc halfRoom(g: Graph, opt: LayeredOptions, v: int): float =
  ## Half the room a node, bend or port takes across the flow, with its share of the gap beside
  ## it. A port on a group's border is a point that an edge passes through, and needs no more
  ## than a bend.
  g.W[v] / 2 + (if g.kinds[v] == ord(kNode): opt.nodeSep else: opt.edgeSep) / 2

proc snap(g: Graph, xs: var seq[float], empty: seq[int], opt: LayeredOptions) =
  ## Brings edges that are nearly straight into line, by moving a node or bend a little across
  ## the flow along with everything it is in line with already, where the nodes beside them
  ## leave room. What is in line stays in line, so each move leaves one more edge straight.
  proc passed(u: int): bool = empty.len > 0 and g.kinds[u] == ord(kDummy) and empty[g.RANK[u]] == 1
  # Each edge from one point that is held in place to the next, past the bends in ranks that hold nothing else.
  var a, b: seq[int]
  var da, db: seq[float]
  for e in 0 ..< g.EF.len:
    if passed(g.EF[e]): continue
    let f = follow(g, empty, e, 1)
    a.add g.EF[e]
    b.add g.ET[f]
    da.add g.EFD[e]
    db.add g.ETD[f]
  template off(k: int): float = xs[b[k]] + db[k] - xs[a[k]] - da[k]
  # The nodes in line with each other move as one.
  var blk = newSeq[int](g.n)
  var members: seq[seq[int]]
  for i in 0 ..< g.n:
    blk[i] = i
    members.add @[i]
  proc join(x, y: int) =
    var keep = blk[x]
    var drop = blk[y]
    if keep == drop: return
    if members[keep].len < members[drop].len: swap(keep, drop)
    for v in members[drop]:
      blk[v] = keep
      members[keep].add v
    members[drop] = @[]
  var near: seq[int]
  for k in 0 ..< a.len:
    let d = abs(off(k))
    if d < 0.01: join(a[k], b[k])
    elif d <= BEND_SNAP: near.add k
  if near.len == 0: return
  block:
    let xsCopy = xs
    near.sort(proc (x, y: int): int =
      orElse(abs(xsCopy[b[x]] + db[x] - xsCopy[a[x]] - da[x]) - abs(xsCopy[b[y]] + db[y] - xsCopy[a[y]] - da[y]), x - y))
  # Whether every node of a block can move by `shift` and keep its room from those beside it.
  proc free(id: int, shift: float, xs: seq[float]): bool =
    for v in members[id]:
      let s = g.layerStart[g.RANK[v]]
      let stop = g.layerStart[g.RANK[v] + 1]
      let i = s + g.pos[v]
      if i > s and blk[g.order[i - 1]] != id and
         xs[v] + shift - xs[g.order[i - 1]] < halfRoom(g, opt, v) + halfRoom(g, opt, g.order[i - 1]) - 0.01:
        return false
      if i + 1 < stop and blk[g.order[i + 1]] != id and
         xs[g.order[i + 1]] - xs[v] - shift < halfRoom(g, opt, v) + halfRoom(g, opt, g.order[i + 1]) - 0.01:
        return false
    true
  for k in near:
    let d = off(k)
    if abs(d) < 0.01:
      join(a[k], b[k])
      continue
    if abs(d) > BEND_SNAP or blk[a[k]] == blk[b[k]]: continue
    # The smaller of the two blocks moves, if it can; else the other.
    let upper = blk[a[k]]
    let lower = blk[b[k]]
    let first = if members[upper].len <= members[lower].len: upper else: lower
    for id in [first, (if first == upper: lower else: upper)]:
      let shift = if id == upper: d else: -d
      if abs(d) > SNAP:
        var allDummy = true
        for v in members[id]:
          if g.kinds[v] != ord(kDummy): allDummy = false
        if not allDummy: continue
      if not free(id, shift, xs): continue
      for v in members[id]: xs[v] += shift
      join(a[k], b[k])
      break

proc emptyRanks(g: Graph): seq[int] =
  ## Marks the ranks that hold nothing but the bends of edges, if there are any (else empty).
  var empty = newSeq[int](g.maxRank + 1)
  var any = false
  for r in 1 ..< g.maxRank:
    var only = g.layerStart[r + 1] > g.layerStart[r]
    var i = g.layerStart[r]
    while only and i < g.layerStart[r + 1]:
      if g.kinds[g.order[i]] != ord(kDummy): only = false
      inc i
    if only:
      empty[r] = 1
      any = true
  if any: empty else: @[]

proc assignTracks(piecesVar: var Pieces, trackCount: var seq[int], curved: bool, room: seq[float],
                  tall: var seq[float]) =
  let piecesP = addr piecesVar
  template pieces: untyped = piecesP[]
  ## Gives every piece that does not run straight down a track across its gap, and counts the
  ## tracks of each gap. Two pieces in one gap share a track only where they cannot be mistaken
  ## for each other: where they do not overlap, or where they leave from or arrive at the same
  ## point, as the branches of a tree do. Which of two goes above the other is whichever makes
  ## them cross less. With `curved`, the tracks are levels for curves to turn onto, and only the
  ## pieces that would run along or too near another get one: each group of those counts its
  ## tracks from its own first. `room` is the height of the gap under each rank, and `tall`
  ## receives the height that a gap whose curves mostly cross each other should have instead of levels.
  let source = pieces.`from`
  let to = pieces.to
  let rank = pieces.rank
  let wide = pieces.wide
  let total = source.len
  var byRank = initOrderedTable[int, seq[int]]()
  for k in 0 ..< total:
    pieces.track.add -1
    pieces.levels.add 0
    if abs(source[k] - to[k]) < IN_LINE: continue
    byRank.mgetOrPut(rank[k], @[]).add k
  if byRank.len == 0: return
  # The pieces are compared pair by pair, so where each begins and ends across the flow is worked out once.
  var LO = newSeq[float](total)
  var HI = newSeq[float](total)
  for k in 0 ..< total:
    LO[k] = min(source[k], to[k])
    HI[k] = max(source[k], to[k])
  proc within(x: float, k: int): int = (if x >= LO[k] - IN_LINE and x <= HI[k] + IN_LINE: 1 else: 0)
  proc mates(a, b: int): bool = abs(source[a] - source[b]) < IN_LINE or abs(to[a] - to[b]) < IN_LINE
  proc overlap(a, b: int): bool = LO[a] < HI[b] - IN_LINE and LO[b] < HI[a] - IN_LINE
  # Whether a and b need tracks of their own.
  proc clash(a, b: int): bool = overlap(a, b) and not mates(a, b)
  # Whether one of a and b could cross the other, depending on which is above.
  proc meet(a, b: int): bool =
    overlap(a, b) or within(to[a], b) + within(source[b], a) + within(to[b], a) + within(source[a], b) > 0
  # How often a and b cross with a on the higher track: a's way down through b, and b's way down to itself through a.
  proc crossings(a, b: int): int = within(to[a], b) + within(source[b], a)
  # Returns pairs of list indices, smaller first. Omitted pairs cannot meet or clash.
  proc nearPairs(list: seq[int]): seq[int] =
    var byLo = newSeq[int](list.len)
    for i in 0 ..< list.len: byLo[i] = i
    byLo.sort(proc (a, b: int): int = orElse(LO[list[a]] - LO[list[b]], 0))
    for x in 0 ..< byLo.len:
      let i = byLo[x]
      let reach = HI[list[i]] + 4 * IN_LINE
      var y = x + 1
      while y < byLo.len and LO[list[byLo[y]]] <= reach:
        let j = byLo[y]
        result.add [min(i, j), max(i, j)]
        inc y

  # Gives the pieces of one gap in `list` their tracks, and each the number of tracks that the
  # pieces it has to do with take between them, counting its own from the first of those.
  # Returns the number of tracks. The pieces come without tracks.
  proc lay(list: var seq[int]): int =
    # A plain order to start from, and to keep where nothing says otherwise: the pieces that
    # reach furthest go first, so that those of one fan nest.
    list.sort(proc (a, b: int): int =
      orElse(HI[b] - LO[b] - (HI[a] - LO[a]), orElse(LO[a] - LO[b], a - b)))
    let count = list.len
    var above: seq[seq[int]]
    var group = newSeq[int](count)
    for i in 0 ..< count: group[i] = i
    proc find(i0: int): int =
      var i = i0
      while group[i] != i:
        group[i] = group[group[i]]
        i = group[i]
      i
    let weighed = count <= MAX_WEIGHED
    # Avoid storing quadratically many pairs in dense gaps.
    let pairs = if weighed: nearPairs(list) else: @[]
    var clashes: seq[seq[int]] = if weighed: newSeq[seq[int]](count) else: @[]
    var p = 0
    while p < pairs.len:
      let i = pairs[p]
      let j = pairs[p + 1]
      p += 2
      if not clash(list[i], list[j]): continue
      clashes[i].add j
      clashes[j].add i
    var sequence = newSeq[int](count)
    for i in 0 ..< count: sequence[i] = i
    if weighed:
      # above[j] lists the pieces that should be above list[j]. The order follows as many of
      # these as it can: a piece is placed once all that should be above it are, and when
      # none is free, the one with the fewest still waiting.
      var waiting = newSeq[int](count)
      var after: seq[seq[int]]
      for i in 0 ..< count:
        above.add @[]
        after.add @[]
      var p = 0
      while p < pairs.len:
        let i = pairs[p]
        let j = pairs[p + 1]
        p += 2
        let a = list[i]
        let b = list[j]
        if not meet(a, b): continue
        group[find(i)] = find(j)
        let ab = crossings(a, b)
        let ba = crossings(b, a)
        if ab == ba: continue
        let first = if ab < ba: i else: j
        let second = if ab < ba: j else: i
        above[second].add first
        after[first].add second
        inc waiting[second]
      var placed = newSeq[bool](count)
      sequence = @[]
      for done in 0 ..< count:
        var pick = -1
        for i in 0 ..< count:
          if placed[i]: continue
          if pick < 0 or waiting[i] < waiting[pick]: pick = i
          if waiting[i] == 0: break
        placed[pick] = true
        sequence.add pick
        for j in after[pick]: dec waiting[j]
    var taken = initHashSet[int]()
    var onTrack: seq[seq[int]]
    var rows = 0
    for at in sequence:
      let k = list[at]
      var t = 0
      if at < above.len:
        for i in above[at]:
          if pieces.track[list[i]] >= t: t = pieces.track[list[i]] + 1
      if weighed:
        taken.clear()
        for i in clashes[at]: taken.incl pieces.track[list[i]]
        while t in taken: inc t
      else:
        while true:
          var hit = false
          if t < onTrack.len:
            for other in onTrack[t]:
              if clash(k, other):
                hit = true
                break
          if not hit: break
          inc t
        while onTrack.len <= t: onTrack.add @[]
        onTrack[t].add k
      pieces.track[k] = t
      if t >= rows: rows = t + 1
    var first = newSeq[int](count)
    var last = newSeq[int](count)
    for i in 0 ..< count:
      first[i] = rows
      last[i] = -1
    for i in 0 ..< count:
      let root = find(i)
      first[root] = min(first[root], pieces.track[list[i]])
      last[root] = max(last[root], pieces.track[list[i]])
    for i in 0 ..< count:
      let root = find(i)
      pieces.levels[list[i]] = last[root] - first[root] + 1
      if curved: pieces.track[list[i]] -= first[root]
    rows

  proc sample(k: int, h: float, output: var seq[float]) =
    let c = ease(to[k] - source[k], h)
    for i in 0 .. SAMPLES:
      let t = float(i) / float(SAMPLES)
      let u = 1 - t
      output[2 * i] = source[k] + (to[k] - source[k]) * t * t * (3 - 2 * t)
      output[2 * i + 1] = h * (3 * c * t * u * u + 3 * (1 - c) * t * t * u + t * t * t)
  proc reaches(points, line: seq[float], limit: float): bool =
    # Allow rounding error in the cheap distance check before calling Math.hypot.
    let bound = limit * limit * (1 + 1e-9)
    for i in 0 .. SAMPLES:
      let px = points[2 * i]
      let py = points[2 * i + 1]
      for j in 0 ..< SAMPLES:
        let dx = line[2 * j + 2] - line[2 * j]
        let dy = line[2 * j + 3] - line[2 * j + 1]
        let q = dx * dx + dy * dy
        let t = max(0.0, min(1.0, ((px - line[2 * j]) * dx + (py - line[2 * j + 1]) * dy) / (if q == 0: 1.0 else: q)))
        let ex = px - line[2 * j] - t * dx
        let ey = py - line[2 * j + 1] - t * dy
        if ex * ex + ey * ey < bound and hypot(ex, ey) < limit: return true
    false
  proc near(a, b: int, height, limit: float): bool =
    let h = max(height / 2, height - 2 * LEVEL_LEAD)
    sample(a, h, LINE_A)
    sample(b, h, LINE_B)
    reaches(LINE_A, LINE_B, limit) or reaches(LINE_B, LINE_A, limit)

  for r, all0 in byRank:
    var all = all0
    if not curved:
      trackCount[r] = lay(all)
      continue
    if all.len > MAX_WEIGHED: continue
    # The pieces that turn onto levels: first those that run far across and have another such
    # piece to be told apart from, then any two that would pass too near each other as plain
    # curves.
    var far: seq[int]
    for k in all:
      if wide[k] == 1: far.add k
    discard lay(far)
    var level = initHashSet[int]()
    for k in far:
      if pieces.levels[k] > 1: level.incl k
    let pairs = nearPairs(all)
    var p = 0
    while p < pairs.len:
      let a = all[pairs[p]]
      let b = all[pairs[p + 1]]
      p += 2
      if (a in level and b in level) or not clash(a, b) or (source[a] < to[a]) != (source[b] < to[b]): continue
      if near(a, b, room[r], (if wide[a] == 1 or wide[b] == 1: LEVEL_CLEAR else: LEVEL_TOUCH)):
        level.incl a
        level.incl b
    for k in far:
      pieces.track[k] = -1
      pieces.levels[k] = 0
    if level.len == 0: continue
    var crossing = 0
    var alongside = 0
    var beside = initHashSet[int]()
    p = 0
    while p < pairs.len:
      let a = all[pairs[p]]
      let b = all[pairs[p + 1]]
      p += 2
      if a in level and b in level:
        if not overlap(a, b): continue
        if (source[a] < to[a]) != (source[b] < to[b]): inc crossing
        elif not mates(a, b): inc alongside
      elif (a in level or b in level) and meet(a, b):
        beside.incl a
        beside.incl b
    if crossing > alongside:
      for k in all:
        if (HI[k] - LO[k]) * CROSSED_SLOPE > tall[r]: tall[r] = (HI[k] - LO[k]) * CROSSED_SLOPE
      continue
    # With them go the short pieces that could cross one of them, so that each has its place
    # among the levels and crosses none.
    var members: seq[int]
    for k in all:
      if k in level or (wide[k] != 1 and k in beside): members.add k
    discard lay(members)
    var most = 0
    for k in members:
      if pieces.levels[k] > most: most = pieces.levels[k]
    trackCount[r] = most

proc straighten(g: Graph, xs: var seq[float], empty: seq[int], firstDummy, span: seq[int],
                sep: float, onLine: var seq[int]) =
  ## Moves the bends in ranks that hold only bends onto the straight line between the nearest
  ## points of their edges that are held in place, and marks the ones that can be left out of
  ## the route. `firstDummy` and `span` give each edge's run of bends, one in every rank. `sep`
  ## is the room kept between the bends of twin edges, or 0 to leave those out as well.
  var want = newSeq[float](xs.len)
  # The points that each bend's edge runs between, across the ranks that hold only bends.
  var source = newSeq[float](xs.len)
  var to = newSeq[float](xs.len)
  for ei in 0 ..< firstDummy.len:
    let d0 = firstDummy[ei]
    if d0 < 0: continue
    let stop = d0 + span[ei] - 1
    # A bend's rank is its place in the run, counted from the rank after the edge's first node.
    let base = g.RANK[d0]
    var d = d0
    while d < stop:
      if empty[base + d - d0] == 0:
        inc d
        continue
      var last = d
      while last + 1 < stop and empty[base + last + 1 - d0] != 0: inc last
      let above = g.predE[g.predStart[d]]
      let below = g.succE[g.succStart[last]]
      let x0 = xs[g.EF[above]] + g.EFD[above]
      let x1 = xs[g.ET[below]] + g.ETD[below]
      let steps = last - d + 2
      for k in d .. last:
        want[k] = x0 + ((x1 - x0) * float(k - d + 1)) / float(steps)
        source[k] = x0
        to[k] = x1
      d = last + 1

  # Nothing in such a rank is in a bend's way, so each one goes onto its line and out of the
  # route. Only twins stay: bends of edges that run between the same two points, which would
  # otherwise be drawn as one. They take places a little apart, around the line.
  var twins: seq[int]
  for r in 1 ..< g.maxRank:
    if empty[r] == 0: continue
    let s = g.layerStart[r]
    let stop = g.layerStart[r + 1]
    var row = g.order[s ..< stop]
    row.sort(proc (a, b: int): int = orElse(source[a] - source[b], orElse(to[a] - to[b], a - b)))
    var i = 0
    while i < row.len:
      twins.setLen 0
      var j = i
      while j < row.len and abs(source[row[j]] - source[row[i]]) < TWIN and abs(to[row[j]] - to[row[i]]) < TWIN:
        twins.add row[j]
        inc j
      # The twins keep the order the rank gave them, so that two edges do not swap sides on the way.
      twins.sort(proc (a, b: int): int = g.pos[a] - g.pos[b])
      for k in 0 ..< twins.len:
        let d = twins[k]
        xs[d] = want[d] + (float(k) - float(twins.len - 1) / 2) * sep
        if twins.len == 1 or sep == 0: onLine[d] = 1
      i = j

proc pastLabels(g: Graph, xs: var seq[float], firstDummy, span: seq[int], clear: float,
                onLine: var seq[int]) =
  ## In a rank that holds labels and bends but no nodes, a bend is there to take its edge
  ## straight through between the labels. Where the edge would pass clear of every label anyway,
  ## the bend is left out, and the edge turns in the whole height between the ranks on either side.
  var labelled = newSeq[bool](g.maxRank + 1)
  var any = false
  for r in 1 ..< g.maxRank:
    var labels = false
    var others = false
    for i in g.layerStart[r] ..< g.layerStart[r + 1]:
      let kind = g.kinds[g.order[i]]
      if kind == ord(kLabel): labels = true
      elif kind != ord(kDummy): others = true
    if labels and not others:
      labelled[r] = true
      any = true
  if not any: return
  for ei in 0 ..< firstDummy.len:
    let d0 = firstDummy[ei]
    if d0 < 0: continue
    let stop = d0 + span[ei] - 1
    for d in d0 ..< stop:
      if g.kinds[d] != ord(kDummy) or not labelled[g.RANK[d]]: continue
      # The points on either side that the edge is held at, past any bends already left out.
      var first = d
      var last = d
      while first > d0 and onLine[first - 1] != 0: dec first
      while last + 1 < stop and onLine[last + 1] != 0: inc last
      let above = g.predE[g.predStart[first]]
      let below = g.succE[g.succStart[last]]
      let source = xs[g.EF[above]] + g.EFD[above]
      let to = xs[g.ET[below]] + g.ETD[below]
      let lo = min(source, to) - clear
      let hi = max(source, to) + clear
      var free = true
      let r = g.RANK[d]
      var i = g.layerStart[r]
      while free and i < g.layerStart[r + 1]:
        let label = g.order[i]
        if g.kinds[label] == ord(kLabel) and xs[label] + g.W[label] / 2 > lo and xs[label] - g.W[label] / 2 < hi:
          free = false
        inc i
      if not free: continue
      onLine[d] = 1
      # The bends left out between the two points lie on the line between them.
      let steps = last - first + 2
      for k in first .. last: xs[k] = source + ((to - source) * float(k - first + 1)) / float(steps)

proc reduceCrossings(g: Graph, nodes: seq[LNode]): (int, int) =
  ## Returns [final crossings, crossings before grouping or reordering].
  let n = g.n
  let real = g.real
  let maxRank = g.maxRank
  let offsets = g.offsets
  let hasGRP = g.GRP.len > 0
  var widest = 0
  for r in 0 .. maxRank: widest = max(widest, g.layerStart[r + 1] - g.layerStart[r])
  if widest < 2: return (0, 0)
  # With offsets, edges that reach one node at different offsets take separate places along it.
  let place = offsets
  var placeOf = if place: newSeq[int](g.EF.len) else: @[]
  # Local offset indices and counts do not depend on node order.
  var placeIn = newSeq[int](if place: g.EF.len else: 0)
  var places = newSeq[int](if place: n else: 0)
  var leaving = g.succE
  var mixed = newSeq[int](if place: n else: 0)
  if place:
    var arriving = g.predE
    proc byOffset(list: var seq[int], first, to: int, dx: seq[float]): bool =
      for k in first + 1 ..< to:
        if dx[list[k]] == dx[list[first]]: continue
        var part = list[first ..< to]
        part.sort(proc (a, b: int): int = orElse(dx[a] - dx[b], 0))
        for i, v in part: list[first + i] = v
        return true
      false
    for v in 0 ..< n:
      places[v] = 1
      if byOffset(arriving, g.predStart[v], g.predStart[v + 1], g.ETD):
        for k in g.predStart[v] + 1 ..< g.predStart[v + 1]:
          if g.ETD[arriving[k]] != g.ETD[arriving[k - 1]]: inc places[v]
          placeIn[arriving[k]] = places[v] - 1
      if byOffset(leaving, g.succStart[v], g.succStart[v + 1], g.EFD): mixed[v] = 1
  var size = 1
  while size < (if place: widest + g.EF.len else: widest): size = size shl 1
  var tree = newSeq[int](2 * size)
  var targets = newSeq[int](g.EF.len)

  proc count(): int =
    var total = 0
    for r in 0 ..< maxRank:
      var southLen = g.layerStart[r + 2] - g.layerStart[r + 1]
      if place:
        var next = 0
        for i in g.layerStart[r + 1] ..< g.layerStart[r + 2]:
          let v = g.order[i]
          for k in g.predStart[v] ..< g.predStart[v + 1]: placeOf[g.predE[k]] = next + placeIn[g.predE[k]]
          next += places[v]
        southLen = next
      if southLen < 2: continue
      var t = 0
      for i in g.layerStart[r] ..< g.layerStart[r + 1]:
        let v = g.order[i]
        let first = g.succStart[v]
        let to = g.succStart[v + 1]
        let t0 = t
        for k in first ..< to:
          targets[t] = if place: placeOf[leaving[k]] else: g.pos[g.ET[g.succE[k]]]
          inc t
        let d = t - t0
        if d < 2: continue
        if place and mixed[v] != 0:
          # Sort equal-offset edges by destination to avoid counting shared endpoints as crossings.
          for a in t0 + 1 ..< t:
            let item = targets[a]
            let dx = g.EFD[leaving[first + a - t0]]
            var b = a - 1
            while b >= t0 and g.EFD[leaving[first + b - t0]] == dx and targets[b] > item:
              targets[b + 1] = targets[b]
              dec b
            targets[b + 1] = item
        elif d <= 12:
          for a in t0 + 1 ..< t:
            let item = targets[a]
            var b = a - 1
            while b >= t0 and targets[b] > item:
              targets[b + 1] = targets[b]
              dec b
            targets[b + 1] = item
        else:
          var part = targets[t0 ..< t]
          part.sort()
          for i, v in part: targets[t0 + i] = v
      if t < 2: continue
      var leaves = 1
      while leaves < southLen: leaves = leaves shl 1
      for i in 0 ..< 2 * leaves: tree[i] = 0
      for k in 0 ..< t:
        var i = targets[k] + leaves
        inc tree[i]
        while i > 1:
          if (i and 1) == 0: total += tree[i + 1]
          i = i shr 1
          inc tree[i]
    total

  let declared = count()
  var bary = newSeq[float](n)
  var moving = newSeq[int](widest)
  var spare = newSeq[int](widest)

  # Keep groups contiguous, ordering each by its mean key.
  let groupParent = g.groupParent
  let groups = if g.hasGroupParent: groupParent.len else: 0
  var depth = newSeq[int](groups)
  for gr in 0 ..< groups:
    var p = gr
    while p >= 0:
      inc depth[gr]
      p = groupParent[p]
  var groupSum = newSeq[float](groups)
  var groupCount = newSeq[int](groups)
  var groupFirst = newSeq[int](groups)
  proc arrange(r: int, key: seq[float]) =
    let s = g.layerStart[r]
    let e = g.layerStart[r + 1]
    for i in s ..< e:
      var gr = g.GRP[g.order[i]]
      while gr >= 0:
        groupSum[gr] = 0
        groupCount[gr] = 0
        gr = groupParent[gr]
    for i in s ..< e:
      let v = g.order[i]
      var gr = g.GRP[v]
      while gr >= 0:
        if groupCount[gr] == 0: groupFirst[gr] = i
        groupSum[gr] += key[v]
        inc groupCount[gr]
        gr = groupParent[gr]
    # Compare siblings in their nearest common group; group items use n + group ID.
    proc value(item: int): float =
      if item >= n: groupSum[item - n] / float(groupCount[item - n]) else: key[item]
    proc first(item: int): int = (if item >= n: groupFirst[item - n] else: s + g.pos[item])
    proc compare(a, b: int): int =
      var ia = a
      var ib = b
      var ca = g.GRP[a]
      var cb = g.GRP[b]
      var da = if ca < 0: 0 else: depth[ca]
      var db = if cb < 0: 0 else: depth[cb]
      while da > db:
        ia = n + ca
        ca = groupParent[ca]
        dec da
      while db > da:
        ib = n + cb
        cb = groupParent[cb]
        dec db
      while ca != cb:
        ia = n + ca
        ca = groupParent[ca]
        ib = n + cb
        cb = groupParent[cb]
      orElse(value(ia) - value(ib), first(ia) - first(ib))
    g.sortLayer(s, e, compare)
    for i in s ..< e: g.pos[g.order[i]] = i - s
  if hasGRP:
    var at = newSeq[float](n)
    for r in 0 .. maxRank:
      for i in g.layerStart[r] ..< g.layerStart[r + 1]: at[g.order[i]] = float(i - g.layerStart[r])
      arrange(r, at)
  var best = if hasGRP: count() else: declared
  if best == 0: return (0, declared)
  var bestOrder = g.order
  # Require improvements over both the grouped and ungrouped starting orders.
  let startCount = min(best, declared)

  proc sweep(down: bool, biasRight: bool) =
    let startP = choose(down, g.predStart, g.succStart)
    let listP = choose(down, g.predE, g.succE)
    let otherP = choose(down, g.EF, g.ET)
    let otherDxP = choose(down, g.EFD, g.ETD)
    template start: untyped = startP[]
    template list: untyped = listP[]
    template other: untyped = otherP[]
    template otherDx: untyped = otherDxP[]
    for step in 1 .. maxRank:
      let r = if down: step else: maxRank - step
      if g.fixed[r] != 0: continue
      let s = g.layerStart[r]
      let e = g.layerStart[r + 1]
      var movable = 0
      for i in s ..< e:
        let v = g.order[i]
        let pin = if v < real: nodes[v].pin else: 0
        if pin != 0:
          bary[v] = pin * 1e9
          moving[movable] = v
          inc movable
          continue
        let first = start[v]
        let to = start[v + 1]
        if first == to:
          if hasGRP:
            # Preserve relative position when there are no neighbours in the adjacent rank.
            let across = if down: g.layerStart[r] - g.layerStart[r - 1] else: g.layerStart[r + 2] - g.layerStart[r + 1]
            bary[v] = (float(i - s) * float(across)) / float(e - s)
            continue
          bary[v] = -1
          continue
        var sum = 0.0
        for k in first ..< to:
          let u = other[list[k]]
          sum += float(g.pos[u])
          if offsets and g.W[u] > 0: sum += otherDx[list[k]] / g.W[u]
        bary[v] = sum / float(to - first)
        moving[movable] = v
        inc movable
      if hasGRP:
        arrange(r, bary)
        continue
      if movable < 2: continue
      sortByBary(moving, movable, bary, g.pos, biasRight, spare)
      var k = 0
      for i in s ..< e:
        if bary[g.order[i]] != -1:
          g.order[i] = moving[k]
          inc k
      for i in s ..< e: g.pos[g.order[i]] = i - s

  # How many pairs of nodes in one rank are not in the order they were given.
  proc outOfOrder(): int =
    var total = 0
    for r in 0 .. maxRank:
      for i in g.layerStart[r] ..< g.layerStart[r + 1]:
        if g.order[i] >= real: continue
        for j in i + 1 ..< g.layerStart[r + 1]:
          if g.order[j] < g.order[i]: inc total
    total
  proc settlePositions() =
    for r in 0 .. maxRank:
      for i in g.layerStart[r] ..< g.layerStart[r + 1]: g.pos[g.order[i]] = i - g.layerStart[r]

  # Adjacent swaps can remove crossings missed by barycenter sweeps.
  proc pinOf(v: int): float = (if v < real: nodes[v].pin else: 0)
  proc at(e: int, up: bool): float =
    let u = if up: g.EF[e] else: g.ET[e]
    if offsets and g.W[u] > 0: float(g.pos[u]) + (if up: g.EFD[e] else: g.ETD[e]) / g.W[u]
    else: float(g.pos[u])
  # Crossings between a and b, assuming a is left of b.
  proc between(a, b: int): int =
    var c = 0
    for k in g.predStart[a] ..< g.predStart[a + 1]:
      let x = at(g.predE[k], true)
      for j in g.predStart[b] ..< g.predStart[b + 1]:
        if x > at(g.predE[j], true): inc c
    for k in g.succStart[a] ..< g.succStart[a + 1]:
      let x = at(g.succE[k], false)
      for j in g.succStart[b] ..< g.succStart[b + 1]:
        if x > at(g.succE[j], false): inc c
    c
  proc transpose() =
    for pass in 0 ..< 8:
      var improved = false
      for r in 0 .. maxRank:
        if g.fixed[r] != 0: continue
        let s = g.layerStart[r]
        var i = s
        while i + 1 < g.layerStart[r + 1]:
          let a = g.order[i]
          let b = g.order[i + 1]
          if pinOf(a) != pinOf(b) or (hasGRP and g.GRP[a] != g.GRP[b]):
            inc i
            continue
          if between(b, a) >= between(a, b):
            inc i
            continue
          g.order[i] = b
          g.order[i + 1] = a
          g.pos[b] = i - s
          g.pos[a] = i + 1 - s
          improved = true
          inc i
      if not improved: break

  # The sweeps are run twice from the same start, going down first and going up first. They
  # often end with as few crossings either way but a different order, and then the one that
  # keeps more of the nodes in the order they were given is the less surprising.
  # Only for graphs small enough to be read node by node: a second run costs as much as the first.
  let initial = g.order
  let small = n <= 600
  var chosen = bestOrder
  var chosenOut = high(int)
  for attempt in 0 ..< (if small: 2 else: 1):
    if attempt > 0:
      g.order = initial
      settlePositions()
    var found = startCount
    var foundOrder = initial
    var i = 0
    var stale = 0
    while stale < 4 and i < MAX_SWEEPS:
      sweep((i + attempt) mod 2 == 0, i mod 4 >= 2)
      let c = count()
      if c < found:
        found = c
        foundOrder = g.order
        stale = 0
        if c == 0: break
      inc i
      inc stale
    g.order = foundOrder
    if small and found > 0:
      settlePositions()
      transpose()
      let c = count()
      if c < found:
        found = c
        foundOrder = g.order
    let output = if small: outOfOrder() else: 0
    if attempt == 0 or found < best or (found == best and output < chosenOut):
      best = found
      chosen = foundOrder
      chosenOut = output
  g.order = chosen
  settlePositions()
  bestOrder = chosen
  # The retained grouped order may exceed the ungrouped threshold; recount it.
  if hasGRP: best = count()

  # A drawing and its mirror image cross as often too. Of those two, likewise.
  if not small: return (best, declared)
  for i in 0 ..< real:
    if nodes[i].pin != 0: return (best, declared)
  if chosenOut == 0 or g.fixed[0] != 0 or g.fixed[maxRank] != 0: return (best, declared)
  for r in 0 .. maxRank:
    var a = g.layerStart[r]
    var b = g.layerStart[r + 1] - 1
    while a < b:
      swap(g.order[a], g.order[b])
      inc a
      dec b
  settlePositions()
  if count() > best or outOfOrder() >= chosenOut: g.order = bestOrder
  (best, declared)

proc position(g: Graph, opt: LayeredOptions): seq[float] =
  ## Brandes-Köpf horizontal coordinate assignment: four aligned layouts, balanced.
  let n = g.n
  let maxRank = g.maxRank
  let segments = g.EF.len
  var gap = newSeq[float](n)
  for i in 0 ..< n: gap[i] = halfRoom(g, opt, i)

  # Neighbours in left-to-right order, so the medians can be read off directly.
  var key = newSeq[float](segments)
  for e in 0 ..< segments: key[e] = float(g.pos[g.ET[e]])
  for v in 0 ..< n:
    if g.succStart[v + 1] - g.succStart[v] > 1: sortRange(g.succE, g.succStart[v], g.succStart[v + 1], key)
  for e in 0 ..< segments: key[e] = float(g.pos[g.EF[e]])
  for v in 0 ..< n:
    if g.predStart[v + 1] - g.predStart[v] > 1: sortRange(g.predE, g.predStart[v], g.predStart[v + 1], key)

  # An edge between two real nodes may not cross a dummy-to-dummy segment; mark those that would.
  var conflict = newSeq[int](segments)
  for r in 1 .. maxRank:
    let prevLen = g.layerStart[r] - g.layerStart[r - 1]
    let s = g.layerStart[r]
    let stop = g.layerStart[r + 1]
    var k0 = 0
    var scan = s
    for i in s ..< stop:
      let v = g.order[i]
      var inner = -1
      if isDummy(g.kinds[v]):
        let u = g.EF[g.predE[g.predStart[v]]]
        if isDummy(g.kinds[u]): inner = u
      let k1 = if inner >= 0: g.pos[inner] else: prevLen
      if inner >= 0 or i == stop - 1:
        for j in scan .. i:
          let w = g.order[j]
          let wDummy = isDummy(g.kinds[w])
          for k in g.predStart[w] ..< g.predStart[w + 1]:
            let e = g.predE[k]
            let up = g.pos[g.EF[e]]
            if (up < k0 or k1 < up) and not (wDummy and isDummy(g.kinds[g.EF[e]])): conflict[e] = 1
        scan = i + 1
        k0 = k1

  var results: seq[seq[float]]
  var root = newSeq[int](n)
  var align = newSeq[int](n)
  # Offset of each node from its block's root, so that aligned edges meet at their attachment points.
  var shift = newSeq[float](n)
  var eFrom = newSeq[int](n)
  var eTo = newSeq[int](n)
  var eW = newSeq[float](n)
  var indeg = newSeq[int](n)
  var outStart = newSeq[int](n + 1)
  var outE = newSeq[int](n)
  var fill = newSeq[int](n)
  var topo = newSeq[int](n)
  var x = newSeq[float](n)

  for variant in 0 ..< 4:
    let up = variant < 2
    let right = (variant and 1) == 1
    let startP = choose(up, g.predStart, g.succStart)
    let listP = choose(up, g.predE, g.succE)
    let otherP = choose(up, g.EF, g.ET)
    let ownDxP = choose(up, g.ETD, g.EFD)
    let otherDxP = choose(up, g.EFD, g.ETD)
    template start: untyped = startP[]
    template list: untyped = listP[]
    template other: untyped = otherP[]
    template ownDx: untyped = ownDxP[]
    template otherDx: untyped = otherDxP[]
    for i in 0 ..< n:
      root[i] = i
      align[i] = i
      shift[i] = 0
      indeg[i] = 0
      outStart[i + 1] = 0
      x[i] = 0

    for step in 0 .. maxRank:
      let r = if up: step else: maxRank - step
      let s = g.layerStart[r]
      let stop = g.layerStart[r + 1]
      let adjacent = if up: r - 1 else: r + 1
      let adjacentLast = if adjacent >= 0 and adjacent <= maxRank: g.layerStart[adjacent + 1] - g.layerStart[adjacent] - 1 else: 0
      var prevIdx = -1
      var i = if right: stop - 1 else: s
      while (if right: i >= s else: i < stop):
        let v = g.order[i]
        let first = start[v]
        let d = start[v + 1] - first
        if d != 0:
          let lo = first + ((d - 1) shr 1)
          let hi = first + (d shr 1)
          for pass in 0 ..< 2:
            if pass == 1 and lo == hi: break
            let e = list[if (pass == 0) != right: lo else: hi]
            let w = other[e]
            let idx = if right: adjacentLast - g.pos[w] else: g.pos[w]
            if align[v] == v and prevIdx < idx and conflict[e] == 0:
              align[w] = v
              root[v] = root[w]
              align[v] = root[v]
              shift[v] = shift[w] + otherDx[e] - ownDx[e]
              prevIdx = idx
        if right: dec i else: inc i

    var blockEdges = 0
    for r in 0 .. maxRank:
      let s = g.layerStart[r]
      let stop = g.layerStart[r + 1]
      for i in s + 1 ..< stop:
        let a = if right: g.order[i] else: g.order[i - 1]
        let b = if right: g.order[i - 1] else: g.order[i]
        let sep = gap[a] + gap[b]
        eFrom[blockEdges] = root[a]
        eTo[blockEdges] = root[b]
        eW[blockEdges] = if right: sep - shift[a] + shift[b] else: sep + shift[a] - shift[b]
        inc indeg[root[b]]
        inc outStart[root[a] + 1]
        inc blockEdges
    for i in 0 ..< n: outStart[i + 1] += outStart[i]
    for i in 0 ..< n: fill[i] = outStart[i]
    for e in 0 ..< blockEdges:
      outE[fill[eFrom[e]]] = e
      inc fill[eFrom[e]]

    var count = 0
    for i in 0 ..< n:
      if root[i] == i and indeg[i] == 0:
        topo[count] = i
        inc count
    var q = 0
    while q < count:
      let v = topo[q]
      for k in outStart[v] ..< outStart[v + 1]:
        let e = outE[k]
        let w = eTo[e]
        if x[v] + eW[e] > x[w]: x[w] = x[v] + eW[e]
        dec indeg[w]
        if indeg[w] == 0:
          topo[count] = w
          inc count
      inc q
    q = count - 1
    while q >= 0:
      let v = topo[q]
      var least = Inf
      for k in outStart[v] ..< outStart[v + 1]:
        let e = outE[k]
        let cand = x[eTo[e]] - eW[e]
        if cand < least: least = cand
      if least != Inf and least > x[v]: x[v] = least
      dec q
    var xs = newSeq[float](n)
    for i in 0 ..< n: xs[i] = (if right: -x[root[i]] else: x[root[i]]) + shift[i]
    results.add xs

  var narrowest = 0
  var bestWidth = Inf
  var mins, maxs: seq[float]
  for k in 0 ..< 4:
    var lo = Inf
    var hi = -Inf
    for i in 0 ..< n:
      let half = g.W[i] / 2
      if results[k][i] - half < lo: lo = results[k][i] - half
      if results[k][i] + half > hi: hi = results[k][i] + half
    mins.add lo
    maxs.add hi
    if hi - lo < bestWidth:
      bestWidth = hi - lo
      narrowest = k
  for k in 0 ..< 4:
    let delta = if (k and 1) == 0: mins[narrowest] - mins[k] else: maxs[narrowest] - maxs[k]
    if delta != 0:
      for i in 0 ..< n: results[k][i] += delta

  result = newSeq[float](n)
  for i in 0 ..< n:
    var a = results[0][i]
    var b = results[1][i]
    var c = results[2][i]
    var d = results[3][i]
    if a > b: swap(a, b)
    if c > d: swap(c, d)
    if a > c: swap(a, c)
    if b > d: swap(b, d)
    if b > c: swap(b, c)
    result[i] = (b + c) / 2

## Pele's tests/layout/compound.test.ts and tests/layout/layered.test.ts, ported (the port map
## counts only src/, so this file names its origin here instead).
##
## Pele's tests of the layered and compound layout, replayed on the port: the invariants every
## layout keeps, on random graphs, and the behaviours the layout promises on small ones. The one
## test of tests/layout/layered.test.ts comes first. `random` is Pele's seeded generator of
## tests/support/corpus.ts; `toBeCloseTo(x, 5)` is `closeTo`.
import std/[unittest, sets, math, algorithm, sequtils, strutils]
import nimaki/layout/[layered, compound]

proc random(seed: int): proc (): float =
  ## state = (Math.imul(state, 1664525) + 1013904223) >>> 0; state / 2^32
  var state = uint32(seed)
  result = proc (): float =
    state = state * 1664525'u32 + 1013904223'u32
    float(state) / 4294967296.0

func closeTo(a, b: float, digits = 5): bool = abs(a - b) < pow(10.0, -float(digits)) / 2

const OPTIONS = LayeredOptions(nodeSep: 40, edgeSep: 16, rankSep: 48, portSep: 20)
const DIRS = ["TB", "BT", "LR", "RL"]

proc withHeadRoom(o: LayeredOptions, h: float): LayeredOptions =
  result = o
  result.headRoom = h

proc withTracks(o: LayeredOptions): LayeredOptions =
  result = o
  result.tracks = true

proc edge(src, dst: int, labelW = 0.0, labelH = 0.0): CEdge =
  CEdge(src: src, dst: dst, minlen: 1, labelW: labelW, labelH: labelH, route: @[], labelX: 0, labelY: 0)

# Every other graph lets edges spread along the sides of its nodes.
proc randomGraph(seed: int): tuple[nodes: seq[CNode], edges: seq[CEdge], dir: Dir] =
  let rnd = random(seed)
  proc int(n: int): int = system.int(floor(rnd() * float(n)))
  var nodes: seq[CNode]
  var groups: seq[int]
  let groupCount = int(5)
  for g in 0 ..< groupCount:
    let node = cnode(0, 0, if groups.len > 0 and rnd() < 0.4: groups[int(groups.len)] else: -1)
    node.isGroup = true
    node.padX = 20
    node.padTop = 40
    node.padBottom = 20
    node.minW = 60
    node.dir = if rnd() < 0.3: DIRS[int(4)] else: ""
    node.seq = float(1000 + g)
    if seed mod 2 == 0: node.span = Inf
    groups.add nodes.len
    nodes.add node
  let leaves = 3 + int(30)
  for i in 0 ..< leaves:
    let parent = if groups.len > 0 and rnd() < 0.5: groups[int(groups.len)] else: -1
    let node = cnode(float(30 + int(120)), float(30 + int(50)), parent)
    node.seq = float(i)
    if seed mod 2 == 0: node.span = min(node.w, node.h) - 24
    nodes.add node
  var edges: seq[CEdge]
  let count = int(leaves * 2)
  for i in 0 ..< count:
    let labelled = rnd() < 0.3
    let src = int(nodes.len)
    let dst = int(nodes.len)
    edges.add edge(src, dst, if labelled: float(20 + int(60)) else: 0, if labelled: 24 else: 0)
  (nodes, edges, DIRS[int(4)])

proc isAncestor(nodes: seq[CNode], a, b: int): bool =
  var p = nodes[b].parent
  while p >= 0:
    if p == a: return true
    p = nodes[p].parent
  false

proc onBorder(node: CNode, x, y: float): bool =
  let dx = abs(x - node.x)
  let dy = abs(y - node.y)
  let inside = dx <= node.w / 2 + 0.5 and dy <= node.h / 2 + 0.5
  let edgeX = abs(dx - node.w / 2) <= 0.5
  let edgeY = abs(dy - node.h / 2) <= 0.5
  inside and (edgeX or edgeY)

proc seqd(nodes: seq[CNode], span = NaN) =
  for i, node in nodes:
    node.seq = float(i)
    if not span.isNaN: node.span = span

proc group(seq: int): CNode =
  result = cnode(0, 0)
  result.isGroup = true
  result.padX = 20
  result.padTop = 40
  result.padBottom = 20
  result.span = Inf
  result.seq = float(seq)

# Issue #3: two chains in separate groups feed a store in a third group.
proc fanIn(): tuple[nodes: seq[CNode], edges: seq[CEdge]] =
  var nodes = @[group(100), group(101), group(102), cnode(80, 60, 2)]
  var edges: seq[CEdge]
  for g in [0, 1]:
    for i in 0 ..< 5:
      let v = nodes.len
      nodes.add cnode(40, 40, g)
      nodes[v].seq = float(v)
      if i > 0: edges.add edge(v - 1, v)
      edges.add edge(v, 3)
  (nodes, edges)

# A node above a row of `children`, with an edge to each. With a `span`, the edges spread along the nodes' sides.
proc fan(children: int, span = 0.0): tuple[nodes: seq[CNode], edges: seq[CEdge], gap: float] =
  var nodes = @[cnode(100, 40)]
  var edges: seq[CEdge]
  for i in 1 .. children:
    nodes.add cnode(100, 40)
    edges.add edge(0, i)
  seqd(nodes, span)
  discard compoundLayout(nodes, edges, "TB", OPTIONS)
  (nodes, edges, nodes[1].y - nodes[0].y - 40)

suite "layered":
  test "orders a flat graph with groups side by side, and counts the crossings of that order":
    var nodes: seq[LNode]
    for i in 0 ..< 6: nodes.add lnode(40, 40)
    let ofs = @[0, 1, 0, -1, 0, -1]
    let edges = @[ledge(0, 4), ledge(1, 4), ledge(2, 5), ledge(3, 4), ledge(3, 5)]
    var opt = OPTIONS
    opt.hasGroups = true
    opt.groups = Groups(`of`: ofs, parent: @[-1, -1])
    opt.orderOnly = true
    let crossings = layered(nodes, edges, opt).crossings
    # Points are (rank, cross-flow position) pairs.
    var pieces: seq[array[3, float]]
    for e in edges:
      var k = 2
      while k < e.points.len:
        pieces.add [e.points[k - 2], e.points[k - 1], e.points[k + 1]]
        k += 2
    var crossed = 0
    for i in 0 ..< pieces.len:
      for j in i + 1 ..< pieces.len:
        let (r, a0, a1) = (pieces[i][0], pieces[i][1], pieces[i][2])
        let (s, b0, b1) = (pieces[j][0], pieces[j][1], pieces[j][2])
        if r == s and (a0 - b0) * (a1 - b1) < 0: inc crossed
    check crossings == crossed
    for i in 0 ..< nodes.len:
      for j in 0 ..< nodes.len:
        if ofs[i] < 0 or ofs[j] != ofs[i] or nodes[i].rank != nodes[j].rank or nodes[i].x >= nodes[j].x: continue
        for k in 0 ..< nodes.len:
          let between = nodes[k].rank == nodes[i].rank and nodes[k].x > nodes[i].x and nodes[k].x < nodes[j].x
          check not (between and ofs[k] != ofs[i])

suite "compound layout":
  test "keeps random graphs well formed":
    var failures: seq[string]
    for seed in 1 .. 300:
      let (nodes, edges, dir) = randomGraph(seed)
      let size = compoundLayout(nodes, edges, dir, OPTIONS)
      let where = "seed " & $seed
      template expect(cond: bool, what: string) =
        if not cond: failures.add where & " " & what
      expect(classify(size.width) notin {fcNan, fcInf, fcNegInf} and classify(size.height) notin {fcNan, fcInf, fcNegInf}, "size")
      for i, node in nodes:
        expect(classify(node.x) notin {fcNan, fcInf, fcNegInf} and classify(node.y) notin {fcNan, fcInf, fcNegInf}, "node " & $i)
        expect(node.x - node.w / 2 >= -0.5, "node " & $i & " left")
        expect(node.y - node.h / 2 >= -0.5, "node " & $i & " top")
        expect(node.x + node.w / 2 <= size.width + 0.5, "node " & $i & " right")
        expect(node.y + node.h / 2 <= size.height + 0.5, "node " & $i & " bottom")
        if node.parent >= 0:
          let parent = nodes[node.parent]
          expect(abs(node.x - parent.x) + node.w / 2 <= parent.w / 2 + 0.5, "node " & $i & " in parent")
          expect(abs(node.y - parent.y) + node.h / 2 <= parent.h / 2 + 0.5, "node " & $i & " in parent")
      for a in 0 ..< nodes.len:
        for b in a + 1 ..< nodes.len:
          if nodes[a].parent != nodes[b].parent: continue
          let overlapX = (nodes[a].w + nodes[b].w) / 2 - abs(nodes[a].x - nodes[b].x)
          let overlapY = (nodes[a].h + nodes[b].h) / 2 - abs(nodes[a].y - nodes[b].y)
          expect(not (overlapX > 0.5 and overlapY > 0.5), "nodes " & $a & " and " & $b & " overlap")
      for i, e in edges:
        if e.src == e.dst: continue
        expect(e.route.len mod 3 == 0, "edge " & $i)
        expect(e.route.len >= 6, "edge " & $i & " has a route")
        for value in e.route: expect(classify(value) notin {fcNan, fcInf, fcNegInf}, "edge " & $i)
        if e.route.len < 6 or isAncestor(nodes, e.src, e.dst) or isAncestor(nodes, e.dst, e.src): continue
        let last = e.route.len - 3
        expect(onBorder(nodes[e.src], e.route[0], e.route[1]), "edge " & $i & " starts on its source")
        expect(onBorder(nodes[e.dst], e.route[last], e.route[last + 1]), "edge " & $i & " ends on its target")
    if failures.len > 0: checkpoint failures[0 ..< min(5, failures.len)].join("; ")
    check failures.len == 0

  test "is deterministic":
    for seed in 1 .. 40:
      let first = randomGraph(seed)
      let second = randomGraph(seed)
      discard compoundLayout(first.nodes, first.edges, first.dir, OPTIONS)
      discard compoundLayout(second.nodes, second.edges, second.dir, OPTIONS)
      check second.nodes.mapIt([it.x, it.y, it.w, it.h]) == first.nodes.mapIt([it.x, it.y, it.w, it.h])
      check second.edges.mapIt(it.route) == first.edges.mapIt(it.route)

  test "runs ranks along the requested direction":
    for dir in DIRS:
      let nodes = @[cnode(60, 40), cnode(60, 40), cnode(60, 40)]
      seqd(nodes)
      discard compoundLayout(nodes, @[edge(0, 1), edge(1, 2)], dir, OPTIONS)
      let vertical = dir == "TB" or dir == "BT"
      let sign = if dir == "TB" or dir == "LR": 1.0 else: -1.0
      template at(n: CNode): float = (if vertical: n.y else: n.x)
      check sign * (at(nodes[1]) - at(nodes[0])) > 40
      check sign * (at(nodes[2]) - at(nodes[1])) > 40

  test "keeps a long edge straight through the ranks it skips":
    let nodes = @[cnode(60, 40), cnode(60, 40), cnode(60, 40)]
    seqd(nodes)
    let edges = @[edge(0, 1), edge(1, 2), edge(0, 2)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    let route = edges[2].route
    var xs = initHashSet[float]()
    var i = 3
    while i < route.len - 3:
      xs.incl round(route[i])
      i += 3
    check xs.len == 1

  test "runs an edge that skips ranks in line with one of its ends, so that it turns once, at the other":
    # A chain of eight, with edges that skip ranks down it and back up.
    var nodes: seq[CNode]
    for i in 0 ..< 8: nodes.add cnode(80, 40)
    seqd(nodes, 56)
    let edges = @[edge(0, 1), edge(1, 2), edge(2, 3), edge(3, 4), edge(4, 5), edge(5, 6), edge(6, 7), edge(0, 3),
                  edge(0, 7), edge(1, 5), edge(2, 6), edge(6, 1), edge(7, 0)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    # How many times the route changes its place across the flow.
    proc turns(route: seq[float]): int =
      var i = 3
      while i < route.len:
        if abs(route[i] - route[i - 3]) > 0.01: inc result
        i += 3
    for e in edges[7 .. ^1]: check turns(e.route) == 1
    # The edge from the second node down and the one back up to it both meet it in line.
    let down = edges[9].route
    let up = edges[11].route
    check closeTo(down[3], down[0])
    check closeTo(up[^6], up[^3])

  test "keeps the edges on one side of a node at its middle unless the node has a span":
    let nodes = @[cnode(120, 40), cnode(60, 40), cnode(60, 40), cnode(60, 40)]
    seqd(nodes)
    let edges = @[edge(0, 1), edge(0, 2), edge(0, 3)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    for e in edges: check closeTo(e.route[0], nodes[0].x)

  test "spreads the edges on one side of a node in the order of the nodes they lead to":
    for dir in DIRS:
      let nodes = @[cnode(120, 120), cnode(60, 60), cnode(60, 60), cnode(60, 60)]
      seqd(nodes)
      nodes[0].span = 96
      let edges = @[edge(0, 1), edge(0, 2), edge(0, 3)]
      discard compoundLayout(nodes, edges, dir, OPTIONS)
      let across = if dir == "TB" or dir == "BT": 0 else: 1
      let starts = edges.mapIt(it.route[across] - (if across == 0: nodes[0].x else: nodes[0].y))
      let targets = edges.mapIt(if across == 0: nodes[it.dst].x else: nodes[it.dst].y)
      let byStart = @[0, 1, 2].sorted(proc (a, b: int): int = cmp(starts[a], starts[b]))
      let byTarget = @[0, 1, 2].sorted(proc (a, b: int): int = cmp(targets[a], targets[b]))
      check byStart == byTarget
      # None of the three can run straight, so they stay around the middle, a pitch apart.
      check closeTo(starts[byStart[0]], -16)
      check closeTo(starts[byStart[1]], 0)
      check closeTo(starts[byStart[2]], 16)
      for e in edges: check onBorder(nodes[0], e.route[0], e.route[1])

  test "keeps an edge that arrives apart from one that leaves on the same side":
    let nodes = @[cnode(60, 40), cnode(60, 40)]
    seqd(nodes, 36)
    let edges = @[edge(0, 1), edge(1, 0)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    let down = edges[0].route
    let up = edges[1].route
    check closeTo(abs(down[^3] - up[0]), 16)
    check closeTo(abs(down[0] - up[^3]), 16)

  test "shares a place among edges that run the same way when there is no room for one each":
    var nodes: seq[CNode]
    for i in 0 .. 12: nodes.add cnode(60, 40)
    seqd(nodes, 36)
    var edges: seq[CEdge]
    for i in 0 ..< 12: edges.add edge(i, 12)
    # One edge the other way on the same side, which keeps a place of its own.
    edges.add edge(12, 0)
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    let into = edges[0 ..< 12].mapIt(it.route[^3])
    check into.mapIt(round(it * 100)).toHashSet.len <= 2
    let back = edges[12].route
    check closeTo(back[1], nodes[12].y - 20)
    for x in into: check abs(x - back[0]) >= 8

  test "stands a rank that only sends edges on one line, and hangs a rank that only receives them from one":
    proc lay(span: float): seq[CNode] =
      let nodes = @[cnode(60, 40), cnode(60, 120), cnode(60, 30), cnode(60, 90)]
      seqd(nodes, span)
      discard compoundLayout(nodes, @[edge(0, 2), edge(1, 2), edge(0, 3), edge(1, 3)], "TB", OPTIONS)
      nodes
    let spread = lay(36)
    check closeTo(spread[0].y + 20, spread[1].y + 60)
    check closeTo(spread[2].y - 15, spread[3].y - 45)
    # Without spreading, as in the diagram types that do not use it yet, each rank is centered.
    let plain = lay(0)
    check closeTo(plain[0].y, plain[1].y)
    check closeTo(plain[2].y, plain[3].y)

  test "gives the gap between two ranks more room when edges that meet at the middle of their nodes run far across it":
    check closeTo(fan(3).gap, OPTIONS.rankSep)
    # Seven children reach 420 across from the middle, and the gap is an eighth of that.
    check closeTo(fan(7).gap, 420 / 8)
    check closeTo(fan(40).gap, 3 * OPTIONS.rankSep)

  test "turns edges that run far across side by side at levels of their own, in a gap that grows to hold them":
    # With three children nothing runs far, and each edge is one curve across the usual gap.
    let few = fan(3, 76)
    check closeTo(few.gap, OPTIONS.rankSep)
    for e in few.edges: check e.route.len == 6
    # With seven, the three on each side run down, across and down again.
    let (nodes, edges, gap) = fan(7, 76)
    proc level(e: CEdge): float =
      check e.route.len == 12
      check closeTo(e.route[3], e.route[0])
      check closeTo(e.route[7], e.route[4])
      check closeTo(e.route[9], e.route[6])
      e.route[4]
    # The edge that runs furthest turns first, and each of the others 12 further down.
    check closeTo(level(edges[1]) - level(edges[0]), 12)
    check closeTo(level(edges[2]) - level(edges[1]), 12)
    for i in 0 ..< 3: check closeTo(level(edges[6 - i]), level(edges[i]))
    # The one in the middle runs straight down.
    check edges[3].route.len == 6
    check closeTo(edges[3].route[3], edges[3].route[0])
    # The levels keep 28 from the ranks above and below.
    check closeTo(level(edges[0]) - nodes[0].y - 20, 28)
    check closeTo(gap, 2 * 28 + 2 * 12)

  test "draws the edges of a gap as plain curves, in a taller gap, where they cross each other more than they run alongside":
    # Four nodes above four, each with an edge to every one below.
    var nodes: seq[CNode]
    for i in 0 ..< 8: nodes.add cnode(80, 40)
    seqd(nodes, 56)
    var edges: seq[CEdge]
    for i in 0 ..< 4:
      for j in 4 ..< 8: edges.add edge(i, j)
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    # No edge turns onto a level: each runs from one point to the other.
    for e in edges: check e.route.len == 6
    # The gap is half as tall as the widest edge runs across, and no more than three times the usual.
    let widest = max(edges.mapIt(abs(it.route[0] - it.route[3])))
    check widest > 6 * OPTIONS.rankSep
    check closeTo(nodes[4].y - nodes[0].y - 40, 3 * OPTIONS.rankSep)

  test "sets a rank of labels half an arrowhead nearer the tails of its edges, and holds a bend beside them for half their height":
    proc lay(headRoom: float): seq[CEdge] =
      let nodes = @[cnode(60, 40), cnode(60, 40)]
      seqd(nodes, 36)
      let edges = @[edge(0, 1, 40, 20), edge(0, 1, 50, 20), edge(0, 1)]
      discard compoundLayout(nodes, edges, "TB", OPTIONS.withHeadRoom(headRoom))
      edges
    # Without arrowheads the labels are midway between the two nodes.
    let plain = lay(0)
    check closeTo(plain[0].labelY, (40 + 108) / 2)
    # With them, the labels are midway between the node above and the backs of the arrowheads.
    let laid = lay(8)
    let (first, second, bare) = (laid[0], laid[1], laid[2])
    check closeTo(first.labelY, (40 + 108 - 8) / 2)
    check closeTo(second.labelY, first.labelY)
    # A labelled edge runs straight for the height of its label, and the bare one for half of that.
    check closeTo(first.route[7] - first.route[4], 20)
    check closeTo(bare.route[7] - bare.route[4], 10)
    check closeTo((bare.route[4] + bare.route[7]) / 2, first.labelY)

  test "turns an edge that runs far across at a level of its own where a shorter one would run close beside it":
    # A node above a row of three, and an edge back up to it from below the row.
    let nodes = @[cnode(80, 40), cnode(80, 40), cnode(80, 40), cnode(80, 40), cnode(80, 40)]
    seqd(nodes, 56)
    let edges = @[edge(0, 1), edge(0, 2), edge(0, 3), edge(1, 4), edge(2, 4), edge(3, 4), edge(4, 0)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    # The edge back up passes the row on one side, then runs across to the top node and up into it.
    let back = edges[6].route
    let n = back.len
    let level = back[n - 5]
    check closeTo(back[n - 8], level)
    check closeTo(back[n - 6], back[n - 3])
    check abs(back[n - 9] - back[n - 6]) > 2 * OPTIONS.rankSep
    # The edge down to the node on that side leaves next to where it arrives. It runs straight
    # down as far as that level and curves below it.
    let down = edges[2].route
    check abs(down[0] - back[n - 3]) < 20
    check down.len == 9
    check closeTo(down[3], down[0])
    check down[4] > level - 0.01

  test "moves an end along its side to let its edge run straight, and no closer to its neighbour than a pitch":
    # A wide node above four narrow ones.
    let nodes = @[cnode(400, 40), cnode(40, 40), cnode(40, 40), cnode(40, 40), cnode(40, 40)]
    for i, node in nodes:
      node.seq = float(i)
      node.span = node.w - 24
    let edges = @[edge(0, 1), edge(0, 2), edge(0, 3), edge(0, 4)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    # Each child is under the wide node, so each edge runs straight down to it.
    for e in edges: check closeTo(e.route[0], e.route[^3])
    let twoWay = @[cnode(200, 40), cnode(40, 40)]
    for i, node in twoWay:
      node.seq = float(i)
      node.span = node.w - 24
    let pair = @[edge(0, 1), edge(1, 0)]
    discard compoundLayout(twoWay, pair, "TB", OPTIONS)
    check closeTo(abs(pair[0].route[0] - pair[1].route[^3]), 16)

  test "moves the edges that leave side by side closer together before it lets them share a place":
    var nodes = @[cnode(60, 40)]
    var edges: seq[CEdge]
    for i in 1 .. 7:
      nodes.add cnode(60, 40)
      edges.add edge(0, i)
    seqd(nodes)
    nodes[0].span = 36
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    let starts = edges.mapIt(it.route[0]).sorted
    # Six gaps of half a pitch each across the 36 there is.
    for i in 1 ..< starts.len: check closeTo(starts[i] - starts[i - 1], 6)

  test "draws an edge as one curve across a rank that only a twin of another edge put there":
    proc lay(twin: bool): seq[CEdge] =
      let nodes = @[cnode(60, 40), cnode(60, 40), cnode(60, 40), cnode(60, 40)]
      seqd(nodes, 36)
      var edges = @[edge(0, 1), edge(0, 2), edge(0, 3)]
      if twin: edges.add edge(0, 3)
      discard compoundLayout(nodes, edges, "TB", OPTIONS)
      edges
    let plain = lay(false)
    let twinned = lay(true)
    # The twins make every edge take a rank in the middle, but none of them needs a bend there.
    for e in twinned[0 ..< 2]: check e.route.len == 6
    check closeTo(twinned[0].route[1], plain[0].route[1])
    # The gap is tall enough for the twins to turn at two levels, 12 apart and 28 from the ranks.
    check closeTo(twinned[0].route[4], plain[0].route[4] + 2 * 28 + 12 - OPTIONS.rankSep)
    # The twins leave and arrive at places of their own.
    let one = twinned[2].route
    let other = twinned[3].route
    check abs(one[0] - other[0]) >= 8
    check abs(one[^3] - other[^3]) >= 8
    # They would run close beside each other, so one turns straight away and the other further down.
    proc turnsAt(route: seq[float]): float = (if abs(route[3] - route[0]) < 0.01: route[4] else: route[1])
    check abs(turnsAt(one) - turnsAt(other)) >= 10

  test "keeps twin edges apart where their ends cannot be":
    let nodes = @[cnode(60, 40), cnode(60, 40)]
    seqd(nodes)
    let edges = @[edge(0, 1), edge(0, 1)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    let a = edges[0].route
    let b = edges[1].route
    check a.len == 9
    check b.len == 9
    check closeTo(a[0], b[0])
    check closeTo(abs(a[3] - b[3]), OPTIONS.edgeSep)

  test "routes edges at right angles on tracks, where no two can be taken for each other":
    var failures: seq[string]
    for seed in 1 .. 120:
      let rnd = random(seed * 7919)
      proc int(n: int): int = system.int(floor(rnd() * float(n)))
      var nodes: seq[CNode]
      let count = 3 + int(14)
      for i in 0 ..< count:
        let node = cnode(float(40 + int(120)), float(30 + int(60)))
        node.seq = float(i)
        node.span = node.w - 24
        nodes.add node
      var edges: seq[CEdge]
      let wanted = system.int(floor(rnd() * (float(count) * 2.5)))  # int(count * 2.5)
      for i in 0 ..< wanted:
        let src = int(count)
        let dst = int(count)
        if src != dst: edges.add edge(src, dst, if rnd() < 0.2: float(30 + int(40)) else: 0, 20)
      discard compoundLayout(nodes, edges, "TB", OPTIONS.withTracks)
      let where = "seed " & $seed
      template expect(cond: bool, what: string) =
        if not cond: failures.add where & " " & what
      # Every run across, with the x where the edge comes down to it and where it goes down from it.
      var runs: seq[tuple[y, lo, hi, `from`, to: float]]
      for ei, e in edges:
        let r = e.route
        expect(onBorder(nodes[e.src], r[0], r[1]), "edge " & $ei & " starts on its source")
        expect(onBorder(nodes[e.dst], r[^3], r[^2]), "edge " & $ei & " ends on its target")
        var k = 3
        while k < r.len:
          # Two ends less than half a unit out of line are joined directly.
          let across = abs(r[k + 1] - r[k - 2]) < 0.01
          let down = abs(r[k] - r[k - 3]) < 0.5
          expect(across or down, "edge " & $ei & " turns at right angles")
          if across and not down:
            # The route runs upwards when the edge does, so the higher end is the one it comes down to.
            let before = if k >= 6: r[k - 5] else: r[k - 2]
            let fromFirst = before < r[k - 2] - 0.01 or (k + 4 < r.len and r[k + 4] > r[k + 1] + 0.01)
            runs.add (r[k + 1], min(r[k], r[k - 3]), max(r[k], r[k - 3]),
                      (if fromFirst: r[k - 3] else: r[k]), (if fromFirst: r[k] else: r[k - 3]))
          k += 3
      for a in 0 ..< runs.len:
        for b in a + 1 ..< runs.len:
          if abs(runs[a].y - runs[b].y) > 0.01: continue
          let overlap = runs[a].lo < runs[b].hi - 0.5 and runs[b].lo < runs[a].hi - 0.5
          let mates = abs(runs[a].`from` - runs[b].`from`) < 0.5 or abs(runs[a].to - runs[b].to) < 0.5
          expect(not (overlap and not mates), "runs " & $a & " and " & $b & " lie on one track")
      # No run across passes through a node.
      for run in runs:
        for node in nodes:
          let inside = abs(run.y - node.y) < node.h / 2 - 0.5 and run.lo < node.x + node.w / 2 - 0.5 and
            run.hi > node.x - node.w / 2 + 0.5
          expect(not inside, "a run crosses a node")
    if failures.len > 0: checkpoint failures[0 ..< min(5, failures.len)].join("; ")
    check failures.len == 0

  test "nests the tracks of a fan so that its edges do not cross":
    let nodes = @[cnode(120, 40), cnode(60, 40), cnode(60, 40), cnode(60, 40), cnode(60, 40)]
    seqd(nodes)
    nodes[0].span = 96
    let edges = @[edge(0, 1), edge(0, 2), edge(0, 3), edge(0, 4)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS.withTracks)
    proc acrossY(e: CEdge): float = e.route[4]
    let left = edges.filterIt(nodes[it.dst].x < nodes[0].x).sorted(proc (a, b: CEdge): int = cmp(nodes[a.dst].x, nodes[b.dst].x))
    let right = edges.filterIt(nodes[it.dst].x > nodes[0].x).sorted(proc (a, b: CEdge): int = cmp(nodes[b.dst].x, nodes[a.dst].x))
    # The edge that reaches furthest turns first, so the nearer ones pass under it.
    for side in [left, right]:
      for i in 1 ..< side.len: check acrossY(side[i - 1]) < acrossY(side[i])

  test "counts where routes cross, but not where edges that meet at one node fan out from it":
    let nodes = @[cnode(40, 40), cnode(40, 40), cnode(40, 40), cnode(40, 40)]
    for i, node in nodes:
      node.x = float(100 * (i mod 2))
      node.y = float(200 * (i div 2))
    let crossed = @[edge(0, 3), edge(1, 2)]
    crossed[0].route = @[0.0, 20, 0, 100, 180, 0]
    crossed[1].route = @[100.0, 20, 0, 0, 180, 0]
    check routeCrossings(nodes, crossed) == 1
    let fanned = @[edge(0, 2), edge(0, 3)]
    fanned[0].route = @[10.0, 20, 0, 0, 180, 0]
    fanned[1].route = @[-10.0, 20, 0, 100, 180, 0]
    check routeCrossings(nodes, fanned) == 0

  test "does not count edges that join one straight run into the node they meet at as crossing":
    let nodes = @[cnode(40, 40), cnode(40, 40), cnode(40, 40)]
    nodes[1].x = 100
    nodes[2].x = 50
    nodes[2].y = 300
    let edges = @[edge(0, 2), edge(1, 2)]
    edges[0].route = @[0.0, 20, 0, 0, 200, 0, 50, 200, 0, 50, 280, 0]
    edges[1].route = @[100.0, 20, 0, 100, 150, 0, 50, 150, 0, 50, 280, 0]
    check routeCrossings(nodes, edges) == 0
    let (fanNodes, into) = fanIn()
    discard compoundLayout(fanNodes, into, "TB", OPTIONS.withTracks)
    check routeCrossings(fanNodes, into) == 0

  test "counts crossings where the drawing has them, round its corners or at its steps":
    let nodes = @[cnode(40, 40), cnode(40, 40), cnode(40, 40), cnode(40, 40)]
    nodes[0].y = -20
    nodes[1].x = 120
    nodes[1].y = 100
    nodes[2].x = 5
    nodes[2].y = 170
    nodes[3].x = 5
    nodes[3].y = 40
    # Rounding the corner clears the other edge.
    let corner = @[edge(0, 1), edge(2, 3)]
    corner[0].route = @[0.0, 0, 0, 0, 100, 0, 100, 100, 1]
    corner[1].route = @[5.0, 150, 0, 5, 60, 0]
    check routeCrossings(nodes, corner, Curved) == 0
    check routeCrossings(nodes, corner, Stepped) == 1
    check routeCrossings(nodes, corner, Linear) == 1
    let (fanNodes, into) = fanIn()
    discard compoundLayout(fanNodes, into, "TB", OPTIONS)
    check routeCrossings(fanNodes, into, Curved) <= 4

  test "orders the ports on the far side of a group by where their edges go, so that a fan into one node does not cross between groups":
    for dir in ["TB", "LR"]:
      var nodes = @[group(100), group(101), group(102), cnode(80, 40, 2)]
      var edges: seq[CEdge]
      for g in [0, 1]:
        for i in 0 ..< 5:
          let v = nodes.len
          nodes.add cnode(100, 40, g)
          if i > 0: edges.add edge(v - 1, v)
          edges.add edge(v, 3)
      for i, node in nodes:
        if node.isGroup: continue
        node.seq = float(i)
        node.span = 72
      discard compoundLayout(nodes, edges, dir, OPTIONS)
      let across = if dir == "TB": 0 else: 1
      proc at(e: CEdge, g: int): float =
        var k = 0
        while k < e.route.len:
          if onBorder(nodes[g], e.route[k], e.route[k + 1]): return e.route[k + across]
          k += 3
        NaN
      let fanned = edges.filterIt(it.dst == 3)
      let leave = fanned.mapIt(at(it, nodes[it.src].parent))
      let enter = fanned.mapIt(at(it, 2))
      for i in 0 ..< fanned.len:
        check not (leave[i].isNaN or enter[i].isNaN)
        for j in i + 1 ..< fanned.len: check sgn(leave[i] - leave[j]) == sgn(enter[i] - enter[j])

  test "runs an edge straight across the gap between a group border and the node it meets inside":
    for dir in ["TB", "LR"]:
      var nodes = @[group(100), group(101)]
      var froms, tos: seq[int]
      for i in 0 ..< 3:
        nodes.add cnode(60, 30, 0)
        froms.add nodes.len - 1
      for i in 0 ..< 5:
        nodes.add cnode(60, 30, 1)
        tos.add nodes.len - 1
      for i, node in nodes:
        if node.isGroup: continue
        node.seq = float(i)
        node.span = min(node.w, node.h) - 8
      var edges: seq[CEdge]
      for b in tos:
        for a in froms: edges.add edge(a, b, 40, 16)
      discard compoundLayout(nodes, edges, dir, OPTIONS)
      let across = if dir == "TB": 0 else: 1
      for i, e in edges:
        let last = e.route.len - 3
        var k = 0
        while k < last and not onBorder(nodes[1], e.route[k], e.route[k + 1]): k += 3
        check k < last
        check closeTo(e.route[k + across], e.route[last + across])
        k = last
        while k > 0 and not onBorder(nodes[0], e.route[k], e.route[k + 1]): k -= 3
        check k > 0
        check closeTo(e.route[k + across], e.route[across])

  test "keeps edges straight when their ends on a node are less than a twin apart":
    let nodes = @[group(100), cnode(48, 48, 0), cnode(70, 66, 0), cnode(48, 48)]
    for i, node in nodes:
      if i > 0: node.seq = float(i)
    nodes[1].span = 24
    nodes[2].span = 0.995
    nodes[3].span = 24
    let edges = @[edge(1, 2, 40, 16), edge(2, 3), edge(3, 2)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    for e in edges[1 .. ^1]:
      var xs: seq[float]
      for k, v in e.route:
        if k mod 3 == 0: xs.add v
      let lo = min(xs[0], xs[^1])
      let hi = max(xs[0], xs[^1])
      for x in xs:
        check x >= lo - 1
        check x <= hi + 1

  test "runs an edge into a group straight when only its bends need to move":
    var nodes = @[group(100), group(101)]
    proc leaf(parent: int): int =
      nodes.add cnode(54, 48, parent)
      let v = nodes.len - 1
      nodes[v].seq = float(v)
      nodes[v].span = 24
      v
    let a1 = leaf(0)
    let a2 = leaf(0)
    let a3 = leaf(0)
    let b1 = leaf(1)
    let b2 = leaf(1)
    let c = leaf(-1)
    let d = leaf(-1)
    let edges = @[edge(a1, a2), edge(a1, a3), edge(b1, b2), edge(a2, b1), edge(a3, b1), edge(b2, a1), edge(c, 0),
                  edge(c, 1), edge(0, d), edge(1, d)]
    discard compoundLayout(nodes, edges, "TB", OPTIONS)
    let route = edges[7].route
    let x = route[^3]
    var k = 0
    while k < route.len:
      if route[k + 1] > nodes[c].y + nodes[c].h / 2 + 24: check closeTo(route[k], x)
      k += 3

  test "orders the nodes of a row of groups as one drawing, so that the edges between them do not cross":
    var nodes = @[group(100), group(101), group(102)]
    proc stage(g: int): seq[int] =
      for i in 0 ..< 5:
        nodes.add cnode(80, 40, g)
        nodes[^1].seq = float(nodes.len)
        result.add nodes.len - 1
    let a = stage(0)
    let b = stage(1)
    let c = stage(2)
    var edges: seq[CEdge]
    for i, j in [4, 2, 0, 3, 1]: edges.add edge(a[i], b[j])
    for i, j in [1, 3, 0, 4, 2]: edges.add edge(b[i], c[j])
    discard compoundLayout(nodes, edges, "LR", OPTIONS)
    check routeCrossings(nodes, edges) == 0

  test "survives groups that contain each other":
    let a = cnode(0, 0, 1)
    let b = cnode(0, 0, 0)
    a.isGroup = true
    b.isGroup = true
    let leaf = cnode(40, 40, 0)
    let nodes = @[a, b, leaf, cnode(40, 40)]
    let edges = @[edge(2, 3)]
    let size = compoundLayout(nodes, edges, "TB", OPTIONS)
    check classify(size.width) notin {fcNan, fcInf, fcNegInf}
    check edges[0].route.len >= 6

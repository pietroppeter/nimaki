## port-of: src/layout/lanes.ts
## port-status: draft
##
## Layout for swimlanes. Every top-level group is a lane: a band that runs the length of the
## diagram along the flow. Ranks are shared by all lanes, so a step sits level with the steps
## that happen at the same time in other lanes, and each node stays inside its own lane.
##
## Port notes. Typed arrays are seqs; `place` is a closure over the ranked graph, as in the
## TypeScript, and returns an object. A label position `[c, a]` is an `array[2, float]`.
import std/[algorithm, intsets, math]
import ../js
import layered, compound

const
  LANE_HEAD = 34.0
  LANE_PAD* = 24.0
  SWEEPS = 8
  MAX_DUMMIES = 20000
  MAX_HOPS = 10000
  ROUTE_BUDGET = 2000000
  NEAR = 4.0
    ## Parallel lines closer than this are drawn as one.
  ROUNDS = 3
  RELAY = 8
  TURN = 20.0
  MARGIN = 20.0
    ## The room a lane keeps beside a handoff along its margin, and (LEG) how much of it is
    ## between the handoff and the lane's items.
  LEG = 14.0
  CLOSE = 3.0

type
  Placed = object
    width, height: float
    routed, margins: seq[uint8]
    work: int

  Around = object
    pts: seq[float]
    cost: float
    lane: int

func sign(x: float): float =
  ## Math.sign
  if x > 0: 1.0 elif x < 0: -1.0 else: x

proc border(fromN, to: CNode): array[2, float]

proc laneLayout*(nodes: seq[CNode], edges: seq[CEdge], dir: Dir, opt: LayeredOptions,
                 lanePad = LANE_PAD): CompoundResult =
  let n = nodes.len
  if n == 0: return CompoundResult(width: 0, height: 0)
  let sideways = dir == "LR" or dir == "RL"
  let flipped = dir == "BT" or dir == "RL"

  # Lanes in the order they were written. The graph lists groups last-declared first.
  var lanes: seq[int]
  for i in countdown(n - 1, 0):
    if nodes[i].parent < 0 and nodes[i].isGroup: lanes.add i
  let laneCount = max(1, lanes.len)
  var laneSlot = newSeq[int](n)
  laneSlot.fill(-1)
  for k, id in lanes: laneSlot[id] = k
  var hasChild = newSeq[uint8](n)
  for i in 0 ..< n:
    if nodes[i].parent >= 0: hasChild[nodes[i].parent] = 1
  # Room a lane keeps around its items, so that the groups drawn around them stay inside it.
  var lanePads = newSeq[float](laneCount)
  lanePads.fill(lanePad)
  var endPad = lanePad
  proc laneOf(i: int): int =
    var t = i
    var room = lanePad
    var hops = 0
    while nodes[t].parent >= 0 and hops < MAX_HOPS:
      t = nodes[t].parent
      if laneSlot[t] < 0: room += max(nodes[t].padX, max(nodes[t].padTop, nodes[t].padBottom))
      inc hops
    let lane = max(0, laneSlot[t])
    if room > lanePads[lane]: lanePads[lane] = room
    if room > endPad: endPad = room
    lane

  # What gets ranked and placed: nodes, and groups that are empty and so act as nodes.
  var itemOf = newSeq[int](n)
  itemOf.fill(-1)
  var real: seq[int]
  for i in 0 ..< n:
    if laneSlot[i] >= 0: continue
    if not nodes[i].isGroup or hasChild[i] == 0:
      itemOf[i] = real.len
      real.add i
  proc along(c: CNode): float = (if sideways: c.w else: c.h)
  proc cross(c: CNode): float = (if sideways: c.h else: c.w)

  var lnodes: seq[LNode]
  for i in real: lnodes.add lnode(cross(nodes[i]), along(nodes[i]))
  var ledges: seq[LEdge]
  var edgeOf: seq[int]
  var step = 1
  block:
    var seenKeys = initIntSet()
    for ei in 0 ..< edges.len:
      let e = edges[ei]
      let a = itemOf[e.src]
      let b = itemOf[e.dst]
      if a < 0 or b < 0 or a == b: continue
      let key = min(a, b) * real.len + max(a, b)
      if e.labelW > 0 or key in seenKeys: step = 2
      seenKeys.incl key
      ledges.add ledge(a, b, e.minlen, (if sideways: e.labelH else: e.labelW),
                       (if sideways: e.labelW else: e.labelH))
      edgeOf.add ei
  orient(lnodes, ledges)
  rank(lnodes, ledges, step)

  let m = ledges.len
  var itemLane = newSeq[int](real.len)
  for k, i in real: itemLane[k] = laneOf(i)

  # Lays the ranked items out and routes the relations. A plain relation is a handoff that takes
  # a simple route of its own, and so keeps no room through the ranks it passes.
  proc place(plain, margins: seq[uint8]): Placed =
    var pad = newSeq[float](laneCount)
    for lane in 0 ..< laneCount:
      pad[lane] = if margins[lane] != 0: max(lanePads[lane], MARGIN) else: lanePads[lane]
    var used = newSeq[uint8](laneCount)
    # Items: the real ones, then a dummy for every rank an edge passes through.
    var dummies = 0
    var span = newSeq[int](m)
    for k in 0 ..< m:
      span[k] = abs(lnodes[ledges[k].head].rank - lnodes[ledges[k].tail].rank)
      if plain[k] == 0: dummies += span[k] - 1
    let direct = dummies > MAX_DUMMIES
    let total = real.len + (if direct: 0 else: dummies)
    var RANK = newSeq[int](total)
    var LANE = newSeq[int](total)
    var SIZE = newSeq[float](total)
    var DEPTH = newSeq[float](total)
    var DUMMY = newSeq[uint8](total)
    var maxRank = 0
    for k in 0 ..< real.len:
      RANK[k] = lnodes[k].rank
      LANE[k] = itemLane[k]
      SIZE[k] = lnodes[k].w
      DEPTH[k] = lnodes[k].h
      if RANK[k] > maxRank: maxRank = RANK[k]
    var firstDummy = newSeq[int](m)
    firstDummy.fill(-1)
    var labelItem = newSeq[int](m)
    labelItem.fill(-1)
    var links: seq[int]
    block:
      var next = real.len
      for k in 0 ..< m:
        let e = ledges[k]
        let a = if e.reversed: e.head else: e.tail
        let b = if e.reversed: e.tail else: e.head
        if direct or span[k] < 2 or plain[k] != 0:
          links.add a; links.add b
          continue
        let ra = RANK[a]
        let rb = RANK[b]
        var labelRank = -1
        if e.labelW > 0:
          labelRank = ra + ashr(rb - ra, 1)
          if step == 2 and (labelRank and 1) == 0: dec labelRank
        firstDummy[k] = next
        var prev = a
        for r in ra + 1 ..< rb:
          let d = next
          inc next
          RANK[d] = r
          # The edge crosses from its first lane to its last one evenly along the way.
          LANE[d] = LANE[a] + int(jsRound(float((LANE[b] - LANE[a]) * (r - ra)) / float(rb - ra)))
          DUMMY[d] = 1
          if r == labelRank:
            SIZE[d] = e.labelW
            DEPTH[d] = e.labelH
            labelItem[k] = d
          links.add prev; links.add d
          prev = d
        links.add prev; links.add b

    var upStart = newSeq[int](total + 1)
    var downStart = newSeq[int](total + 1)
    for k in countup(0, links.len - 1, 2):
      inc downStart[links[k] + 1]
      inc upStart[links[k + 1] + 1]
    for i in 0 ..< total:
      upStart[i + 1] += upStart[i]
      downStart[i + 1] += downStart[i]
    var up = newSeq[int](links.len div 2)
    var down = newSeq[int](links.len div 2)
    block:
      var uf = upStart[0 ..< total]
      var df = downStart[0 ..< total]
      for k in countup(0, links.len - 1, 2):
        down[df[links[k]]] = links[k + 1]
        inc df[links[k]]
        up[uf[links[k + 1]]] = links[k]
        inc uf[links[k + 1]]

    # Order within each rank: by lane first, then by where the item's neighbours sit.
    var rows = newSeq[seq[int]](maxRank + 1)
    for i in 0 ..< total: rows[RANK[i]].add i
    var pos = newSeq[float](total)
    var key = newSeq[float](total)
    proc settle(row: var seq[int]) =
      row.sort(proc (a, b: int): int =
        orElse(float(LANE[a] - LANE[b]), orElse(key[a] - key[b], a - b)))
      for k in 0 ..< row.len: pos[row[k]] = float(k)
    for row in rows.mitems:
      for k in 0 ..< row.len: key[row[k]] = float(k)
      settle(row)
    for sweep in 0 ..< SWEEPS:
      if maxRank <= 0: break
      let downward = (sweep and 1) == 0
      for s in 1 .. maxRank:
        let r = if downward: s else: maxRank - s
        for i in rows[r]:
          var sum = 0.0
          let (lo, hi) = if downward: (upStart[i], upStart[i + 1]) else: (downStart[i], downStart[i + 1])
          let count = hi - lo
          for k in lo ..< hi: sum += pos[if downward: up[k] else: down[k]]
          key[i] = if count > 0: sum / float(count) else: pos[i]
        settle(rows[r])

    # The items of one rank that share a lane sit side by side as a run.
    proc gap(a, b: int): float = (if DUMMY[a] != 0 or DUMMY[b] != 0: opt.edgeSep else: opt.nodeSep)
    proc runs(row: seq[int]): seq[(int, int)] =
      ## eachRun: the runs of a row, as [from, to].
      var fromK = 0
      while fromK < row.len:
        var to = fromK
        while to + 1 < row.len and LANE[row[to + 1]] == LANE[row[fromK]]: inc to
        result.add (fromK, to)
        fromK = to + 1
    proc runSize(row: seq[int], fromK, to: int): float =
      var size = SIZE[row[fromK]]
      for k in fromK ..< to: size += gap(row[k], row[k + 1]) + SIZE[row[k + 1]]
      size

    # Lane breadth: enough for its fullest rank, and for its title.
    var breadth = newSeq[float](laneCount)
    var head = if lanes.len > 0: LANE_HEAD else: 0.0
    for k in 0 ..< lanes.len:
      let lane = nodes[lanes[k]]
      breadth[k] = max(0.0, lane.minW - 2 * pad[k])
      if lane.padTop > head: head = lane.padTop
    for row in rows:
      for (fromK, to) in runs(row):
        let size = runSize(row, fromK, to)
        if size > breadth[LANE[row[fromK]]]: breadth[LANE[row[fromK]]] = size
    var laneStart = newSeq[float](laneCount + 1)
    for k in 0 ..< laneCount: laneStart[k + 1] = laneStart[k] + breadth[k] + 2 * pad[k]

    # Across the flow: each lane's items start centered, then line up with their neighbours in
    # the same lane as far as the lane and the items beside them allow.
    var C = newSeq[float](total)
    var want = newSeq[float](total)
    proc center(row: seq[int], fromK, to: int) =
      let lane = LANE[row[fromK]]
      var at = (laneStart[lane] + pad[lane] + (laneStart[lane + 1] - pad[lane]) - runSize(row, fromK, to)) / 2
      for k in fromK .. to:
        C[row[k]] = at + SIZE[row[k]] / 2
        if k < to: at += SIZE[row[k]] + gap(row[k], row[k + 1])
    proc align(row: seq[int], fromK, to: int) =
      let lane = LANE[row[fromK]]
      var floor = laneStart[lane] + pad[lane]
      for k in fromK .. to:
        let i = row[k]
        C[i] = max(want[i], floor + SIZE[i] / 2)
        if k < to: floor = C[i] + SIZE[i] / 2 + gap(i, row[k + 1])
      var ceil = laneStart[lane + 1] - pad[lane]
      for k in countdown(to, fromK):
        let i = row[k]
        C[i] = min(C[i], ceil - SIZE[i] / 2)
        if k > fromK: ceil = C[i] - SIZE[i] / 2 - gap(row[k - 1], i)
    for row in rows:
      for (fromK, to) in runs(row): center(row, fromK, to)
    for pass in 0 ..< 4:
      if maxRank <= 0: break
      let downward = (pass and 1) == 0
      for s in 1 .. maxRank:
        let row = rows[if downward: s else: maxRank - s]
        for i in row:
          var sum = 0.0
          var count = 0
          let (lo, hi) = if downward: (upStart[i], upStart[i + 1]) else: (downStart[i], downStart[i + 1])
          for k in lo ..< hi:
            let other = if downward: up[k] else: down[k]
            if LANE[other] != LANE[i]: continue
            sum += C[other]
            inc count
          want[i] = if count > 0: sum / float(count) else: C[i]
        for (fromK, to) in runs(row): align(row, fromK, to)

    # Along the flow: one band per rank, after the lane titles.
    var bandStart = newSeq[float](maxRank + 1)
    var bandEnd = newSeq[float](maxRank + 1)
    # The room after a rank is for the relations that turn there or are only as long as they
    # were asked to be. Where just plain handoffs and straight lines pass, the ranks close up,
    # as far as the label of a handoff between them leaves it a line to sit on.
    var sep = newSeq[float](maxRank + 1)
    sep.fill(opt.rankSep / float(step))
    if 1'u8 in plain:
      let full = opt.rankSep / float(step)
      sep.fill(full / CLOSE)
      for k in 0 ..< m:
        let e = ledges[k]
        let a = if e.reversed: e.head else: e.tail
        let b = if e.reversed: e.tail else: e.head
        if plain[k] != 0:
          if e.labelH <= 0 or span[k] > step: continue
          let room = min(full, (e.labelH + 2 * TURN - min(DEPTH[a], DEPTH[b]) / 2) / float(span[k]))
          for r in RANK[a] ..< RANK[b]:
            if room > sep[r]: sep[r] = room
          continue
        let d0 = firstDummy[k]
        if d0 < 0 or span[k] <= step * e.minlen:
          for r in RANK[a] ..< RANK[b]: sep[r] = full
          continue
        for d in d0 - 1 ..< d0 + span[k] - 1:
          let u = if d < d0: a else: d
          let v = if d + 1 < d0 + span[k] - 1: d + 1 else: b
          if LANE[u] != LANE[v] or abs(C[u] - C[v]) >= 0.5: sep[RANK[u]] = full
    var at = head + endPad
    for r in 0 .. maxRank:
      var depth = 0.0
      for i in rows[r]:
        if DEPTH[i] > depth: depth = DEPTH[i]
      bandStart[r] = at
      bandEnd[r] = at + depth
      at += depth + (if r == maxRank: 0.0 else: sep[r])
    let length = at + endPad
    let breadthTotal = laneStart[laneCount]
    proc flip(a: float): float = (if flipped: head + length - a else: a)
    proc px(c, a: float): float = (if sideways: flip(a) else: c)
    proc py(c, a: float): float = (if sideways: c else: flip(a))
    let axis = if sideways: 1.0 else: 0.0

    for k in 0 ..< real.len:
      let node = nodes[real[k]]
      let a = (bandStart[RANK[k]] + bandEnd[RANK[k]]) / 2
      node.x = px(C[k], a)
      node.y = py(C[k], a)
    for k in 0 ..< lanes.len:
      let lane = nodes[lanes[k]]
      let c = (laneStart[k] + laneStart[k + 1]) / 2
      let size = laneStart[k + 1] - laneStart[k]
      lane.x = if sideways: length / 2 else: c
      lane.y = if sideways: c else: length / 2
      lane.w = if sideways: length else: size
      lane.h = if sideways: size else: length
      lane.padTop = head

    # Groups inside a lane are drawn around their members, deepest first.
    var depthOf = newSeq[int](n)
    var inner: seq[int]
    for i in 0 ..< n:
      if not nodes[i].isGroup or laneSlot[i] >= 0 or itemOf[i] >= 0: continue
      var d = 0
      var p = nodes[i].parent
      while p >= 0 and d < MAX_HOPS:
        inc d
        p = nodes[p].parent
      depthOf[i] = d
      inner.add i
    inner.sort(proc (a, b: int): int =
      let x = depthOf[b] - depthOf[a]
      if x != 0: x else: a - b)
    var box = newSeq[float](n * 4)
    for i in 0 ..< n:
      box[i * 4] = Inf
      box[i * 4 + 1] = Inf
      box[i * 4 + 2] = -Inf
      box[i * 4 + 3] = -Inf
    proc grow(g: int, c: CNode) =
      if c.x - c.w / 2 < box[g * 4]: box[g * 4] = c.x - c.w / 2
      if c.y - c.h / 2 < box[g * 4 + 1]: box[g * 4 + 1] = c.y - c.h / 2
      if c.x + c.w / 2 > box[g * 4 + 2]: box[g * 4 + 2] = c.x + c.w / 2
      if c.y + c.h / 2 > box[g * 4 + 3]: box[g * 4 + 3] = c.y + c.h / 2
    for i in real:
      if nodes[i].parent >= 0 and laneSlot[nodes[i].parent] < 0: grow(nodes[i].parent, nodes[i])
    for g in inner:
      let c = nodes[g]
      if box[g * 4] == Inf: continue
      let w = max(box[g * 4 + 2] - box[g * 4] + 2 * c.padX, c.minW)
      c.x = (box[g * 4] + box[g * 4 + 2]) / 2
      c.w = w
      c.y = (box[g * 4 + 1] - c.padTop + box[g * 4 + 3] + c.padBottom) / 2
      c.h = box[g * 4 + 3] - box[g * 4 + 1] + c.padTop + c.padBottom
      if c.parent >= 0 and laneSlot[c.parent] < 0: grow(c.parent, c)

    for e in edges: e.route = @[]
    for k in 0 ..< m:
      let e = ledges[k]
      let output = edges[edgeOf[k]]
      let a = if e.reversed: e.head else: e.tail
      let b = if e.reversed: e.tail else: e.head
      var pts = @[C[a], bandEnd[RANK[a]] - (bandEnd[RANK[a]] - bandStart[RANK[a]] - DEPTH[a]) / 2]
      let d0 = firstDummy[k]
      if d0 >= 0:
        for d in d0 ..< d0 + span[k] - 1:
          pts.add C[d]; pts.add bandStart[RANK[d]]
          if bandEnd[RANK[d]] > bandStart[RANK[d]]:
            pts.add C[d]; pts.add bandEnd[RANK[d]]
      pts.add C[b]; pts.add bandStart[RANK[b]] + (bandEnd[RANK[b]] - bandStart[RANK[b]] - DEPTH[b]) / 2
      var route: seq[float]
      for p in countup(0, pts.len - 1, 2):
        route.add px(pts[p], pts[p + 1]); route.add py(pts[p], pts[p + 1]); route.add axis
      if e.reversed:
        var i = 0
        var j = route.len - 3
        while i < j:
          for t in 0 ..< 2: swap(route[i + t], route[j + t])
          i += 3
          j -= 3
      output.route = route
      let label = labelItem[k]
      if label >= 0:
        let mid = (bandStart[RANK[label]] + bandEnd[RANK[label]]) / 2
        output.labelX = px(C[label], mid)
        output.labelY = py(C[label], mid)
      else:
        output.labelX = (route[0] + route[route.len - 3]) / 2
        output.labelY = (route[1] + route[route.len - 2]) / 2

    # An edge that starts or ends at a lane or a group runs straight to its border.
    for e in edges:
      if e.route.len > 0 or e.src == e.dst: continue
      let a = nodes[e.src]
      let b = nodes[e.dst]
      let pa = border(a, b)
      let pb = border(b, a)
      let flat = if abs(pb[0] - pa[0]) > abs(pb[1] - pa[1]): 1.0 else: 0.0
      e.route = @[pa[0], pa[1], flat, pb[0], pb[1], flat]
      e.labelX = (pa[0] + pb[0]) / 2
      e.labelY = (pa[1] + pb[1]) / 2

    # A handoff can leave towards the other lane, then arrive along the flow (or vice versa).
    # In particular, a decision's return branch must not leave through its incoming side and
    # retrace the path past the preceding step. Try the two single-corner routes, keeping the
    # ranked route when a node or another label blocks them.
    var routed = newSeq[uint8](m)
    var routePoints = 0
    for edge in edges: routePoints += edge.route.len div 3
    let work = m * (real.len + edges.len + routePoints)
    if work <= ROUTE_BUDGET:
      proc amid(i: int): float = (bandStart[RANK[i]] + bandEnd[RANK[i]]) / 2
      var labels = newSeq[array[2, float]](edges.len)
      for i, e in edges:
        labels[i] = [(if sideways: e.labelY else: e.labelX), flip(if sideways: e.labelX else: e.labelY)]
      proc overlaps(c0, a0, c1, a1, lc, la, cw, ah: float): bool =
        c1 > lc - cw / 2 and c0 < lc + cw / 2 and a1 > la - ah / 2 and a0 < la + ah / 2
      proc clear(c0, a0, c1, a1: float, src, dst, ei: int): bool =
        for i in 0 ..< real.len:
          if i != src and i != dst and overlaps(c0, a0, c1, a1, C[i], amid(i), SIZE[i] + 8, DEPTH[i] + 8):
            return false
        for i in 0 ..< edges.len:
          let e = edges[i]
          # A step's own loop keeps its label inside the step's box, and has no place here.
          if i != ei and e.labelW > 0 and e.src != e.dst and
              overlaps(c0, a0, c1, a1, labels[i][0], labels[i][1], (if sideways: e.labelH else: e.labelW),
                       (if sideways: e.labelW else: e.labelH)):
            return false
        true
      # How many other relations have a stretch inside a box. A stretch's whole box counts,
      # including its curve.
      proc crossings(x0, y0, x1, y1: float, ei: int): int =
        for i in 0 ..< edges.len:
          if i == ei: continue
          let route = edges[i].route
          var j = 3
          while j < route.len:
            if max(route[j - 3], route[j]) > x0 and min(route[j - 3], route[j]) < x1 and
                max(route[j - 2], route[j + 1]) > y0 and min(route[j - 2], route[j + 1]) < y1:
              inc result
              break
            j += 3
      proc meets(x, y: float, ei: int): int =
        for i in 0 ..< edges.len:
          let route = edges[i].route
          if i == ei or route.len == 0: continue
          let last = route.len - 3
          if (abs(route[0] - x) < 1 and abs(route[1] - y) < 1) or
              (abs(route[last] - x) < 1 and abs(route[last + 1] - y) < 1):
            inc result
      # Two relations drawn along one line read as a single path. Those that leave the same step
      # or arrive at the same step may share a trunk; any other pair must not.
      proc retraces(x0, y0, x1, y1: float, ei: int): bool =
        let upright = abs(x1 - x0) < 0.5
        let lo = if upright: min(y0, y1) else: min(x0, x1)
        let hi = if upright: max(y0, y1) else: max(x0, x1)
        let line = if upright: x0 else: y0
        let u = if upright: 0 else: 1
        let v = if upright: 1 else: 0
        for i in 0 ..< edges.len:
          let other = edges[i]
          if i == ei or other.src == edges[ei].src or other.dst == edges[ei].dst: continue
          let route = other.route
          var j = 3
          while j < route.len:
            let u0 = route[j - 3 + u]
            let u1 = route[j + u]
            if not (abs(u0 - line) >= NEAR or abs(u1 - line) >= NEAR):
              let v0 = route[j - 3 + v]
              let v1 = route[j + v]
              if min(hi, max(v0, v1)) - max(lo, min(v0, v1)) > 1: return true
            j += 3
        false
      for k in 0 ..< m:
        let e = ledges[k]
        let ei = edgeOf[k]
        let output = edges[ei]
        let a = e.tail
        let b = e.head
        if LANE[a] == LANE[b] or abs(C[b] - C[a]) < 1: continue
        let ac = C[a]
        let bc = C[b]
        let aa = amid(a)
        let ba = amid(b)
        let dc = sign(bc - ac)
        let da = sign(ba - aa)
        proc attempt(pts: seq[float], margin: float): bool =
          for p in countup(2, pts.len - 1, 2):
            if not clear(min(pts[p - 2], pts[p]) - margin, min(pts[p - 1], pts[p + 1]) - margin,
                         max(pts[p - 2], pts[p]) + margin, max(pts[p - 1], pts[p + 1]) + margin, a, b, ei):
              return false
            if retraces(px(pts[p - 2], pts[p - 1]), py(pts[p - 2], pts[p - 1]), px(pts[p], pts[p + 1]),
                        py(pts[p], pts[p + 1]), ei):
              return false
          var lc = 0.0
          var la = 0.0
          var longest = -1.0
          if output.labelW > 0:
            let cw = e.labelW
            let ah = e.labelH
            for p in countup(2, pts.len - 1, 2):
              let cc = (pts[p - 2] + pts[p]) / 2
              let ca = (pts[p - 1] + pts[p + 1]) / 2
              let across = abs(pts[p] - pts[p - 2])
              let along = abs(pts[p + 1] - pts[p - 1])
              let run = across + along
              if run <= longest or (if across > 0: across < cw + 8 else: along < ah + 8): continue
              if cc - cw / 2 < 0 or cc + cw / 2 > breadthTotal or ca - ah / 2 < 0 or ca + ah / 2 > length: continue
              # Include the ends here: the label must clear both shapes it connects.
              if not clear(cc - cw / 2, ca - ah / 2, cc + cw / 2, ca + ah / 2, -1, -1, ei): continue
              # A label moved onto a handoff must not cover a return path that keeps its
              # ranked route. A segment's whole box is kept clear, including its curve.
              let lx = px(cc, ca)
              let ly = py(cc, ca)
              if crossings(lx - output.labelW / 2, ly - output.labelH / 2, lx + output.labelW / 2,
                           ly + output.labelH / 2, ei) > 0: continue
              lc = cc
              la = ca
              longest = run
            if longest < 0: return false
          # A point short of each corner and one past it keep the turn close to the corner, so
          # that the line stays under its label and the handoff takes little room.
          var way = @[pts[0], pts[1]]
          for p in countup(2, pts.len - 1, 2):
            let dx = pts[p] - pts[p - 2]
            let dy = pts[p + 1] - pts[p - 1]
            let run = abs(dx) + abs(dy)
            let first = if p > 2: TURN else: 0.0
            let last = if p + 2 < pts.len: TURN else: 0.0
            if run > first + last + 1:
              if first != 0:
                way.add pts[p - 2] + (dx / run) * first; way.add pts[p - 1] + (dy / run) * first
              if last != 0:
                way.add pts[p] - (dx / run) * last; way.add pts[p + 1] - (dy / run) * last
            way.add pts[p]; way.add pts[p + 1]
          output.route = @[]
          for p in countup(0, way.len - 1, 2):
            let crosswise = if p == 0: way[0] != way[2] else: way[p] != way[p - 2]
            output.route.add px(way[p], way[p + 1])
            output.route.add py(way[p], way[p + 1])
            output.route.add(if crosswise: 1 - axis else: axis)
          if output.labelW > 0:
            output.labelX = px(lc, la)
            output.labelY = py(lc, la)
            labels[ei] = [lc, la]
          routed[k] = 1
          true
        if attempt(@[ac + dc * SIZE[a] / 2, aa, bc, aa, bc, ba - da * DEPTH[b] / 2], 2): continue
        if attempt(@[ac, aa + da * DEPTH[a] / 2, ac, ba, bc - dc * SIZE[b] / 2, ba], 2): continue
        # With both corners blocked, as for a return past the steps between, the handoff goes
        # around: out to the margin of a lane, along it, and back in level with its end. It
        # takes the margin that crosses the fewest other relations and shares the fewest ends
        # with them, then the shortest way.
        if work > ROUTE_BUDGET div RELAY: continue
        var around: seq[Around]
        let both = if LANE[a] < LANE[b]: [LANE[b], LANE[a]] else: [LANE[a], LANE[b]]
        for lane in both:
          # A lane that keeps no margin yet has less room there, and the handoff stays inside it.
          let inset = max(pad[lane] - LEG, min(pad[lane] / 2, MARGIN - LEG))
          for ch in [laneStart[lane] + inset, laneStart[lane + 1] - inset]:
            if abs(ch - ac) < SIZE[a] / 2 + 4 or abs(ch - bc) < SIZE[b] / 2 + 4: continue
            let pts = @[ac + sign(ch - ac) * SIZE[a] / 2, aa, ch, aa, ch, ba, bc + sign(ch - bc) * SIZE[b] / 2, ba]
            var cost = float(meets(px(pts[0], pts[1]), py(pts[0], pts[1]), ei) +
                             meets(px(pts[6], pts[7]), py(pts[6], pts[7]), ei)) * 1e6
            for p in countup(2, pts.len - 1, 2):
              let x0 = px(pts[p - 2], pts[p - 1])
              let y0 = py(pts[p - 2], pts[p - 1])
              let x1 = px(pts[p], pts[p + 1])
              let y1 = py(pts[p], pts[p + 1])
              cost += float(crossings(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), ei)) * 1e6 +
                      abs(x1 - x0) + abs(y1 - y0)
            around.add Around(pts: pts, cost: cost, lane: lane)
        around.sort(proc (p, q: Around): int = orElse(p.cost - q.cost, 0))
        for way in around:
          if not attempt(way.pts, 1): continue
          used[way.lane] = 1
          break

    Placed(width: (if sideways: length else: breadthTotal), height: (if sideways: breadthTotal else: length),
           routed: routed, margins: used, work: work)

  var plain = newSeq[uint8](m)
  var margins = newSeq[uint8](laneCount)
  var placed = place(plain, margins)
  # A handoff that was given a simple route needs no room kept for it through the ranks it
  # passes, so the lanes are laid out again without it. A handoff that then loses its route
  # goes back to the ranked one. Routing is most of the work, so a large graph is laid out once.
  var round = 0
  while round < ROUNDS and placed.work <= ROUTE_BUDGET div RELAY:
    var next = newSeq[uint8](m)
    for k in 0 ..< m: next[k] = if round == 0: placed.routed[k] else: plain[k] and placed.routed[k]
    if next == plain and placed.margins == margins: break
    plain = next
    margins = placed.margins
    placed = place(plain, margins)
    inc round
  var lost = false
  for k in 0 ..< m:
    if plain[k] != 0 and placed.routed[k] == 0: lost = true
  if lost: placed = place(newSeq[uint8](m), newSeq[uint8](laneCount))
  CompoundResult(width: placed.width, height: placed.height)

proc border(fromN, to: CNode): array[2, float] =
  ## The point where the line from one box's center to another's leaves the first box. When the
  ## other center is inside the box, the point is on the nearest side instead.
  let dx = to.x - fromN.x
  let dy = to.y - fromN.y
  let hw = max(fromN.w / 2, 0.5)
  let hh = max(fromN.h / 2, 0.5)
  if abs(dx) < hw and abs(dy) < hh:
    let toSide = hw - abs(dx)
    let toEnd = hh - abs(dy)
    return if toSide < toEnd: [fromN.x + (if dx < 0: -hw else: hw), to.y]
           else: [to.x, fromN.y + (if dy < 0: -hh else: hh)]
  let scale = min(if dx != 0: hw / abs(dx) else: Inf, if dy != 0: hh / abs(dy) else: Inf)
  [fromN.x + dx * scale, fromN.y + dy * scale]

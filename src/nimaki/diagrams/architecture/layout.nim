## port-of: src/diagrams/architecture/layout.ts
## port-status: conformant
##
## Grid placement. Mermaid hands the edge sides to a force-directed solver as relative placement
## constraints. Pele applies them directly: every service and junction takes a cell, an edge
## `a:R -- L:b` puts b in the cell to the right of a, and a group is a solid rectangle of cells, so a
## group never encloses a node that is not in it. Each container (the diagram, then every group) is
## laid out on its own, innermost first, and a finished group is placed in its parent as one block.
import std/[tables, algorithm, options]
from std/math import ceil
import ../../jsmath
import db

type Grid* = object
  col*, row*: seq[int]
    ## Cell of each node, in the order of the nodes passed in.
  groupCol*, groupRow*, groupCols*, groupRows*, groupParent*: seq[int]
    ## Cell rectangle and parent of each group. A group with nothing in it takes one cell.
  groupEmpty*: seq[bool]
  nodeParent*: seq[int]

const DX = [-1, 1, 0, 0]
const DY = [0, 0, -1, 1]

func sideIndex*(side: char): int =
  if side == 'L': 0 elif side == 'R': 1 elif side == 'T': 2 else: 3

const SMALL = 64
  ## Blocks up to this many cells are found through the cell map; larger ones are compared one by one.

func cellKey(cx, cy: int): (int, int) = (cx, cy)

proc placeOnGrid*(nodes: seq[ArchNode], groups: seq[ArchGroup], edges: seq[ArchEdge],
                  hints: seq[ArchLayoutHint]): Grid =
  let N = nodes.len
  let G = groups.len
  let root = G
  var nodeIndex = initTable[string, int]()
  var groupIndex = initTable[string, int]()
  # Items are nodes (0..N-1) then groups (N..N+G-1). Containers are groups (0..G-1) then the root.
  var parent = newSeq[int](N + G)
  for i in 0 ..< N + G: parent[i] = root
  var depth = newSeq[int](G + 1)
  var kids = newSeq[seq[int]](G + 1)
  for g, group in groups:
    groupIndex[group.id] = g
    let p = if group.parent.isNone: -1 else: groupIndex.getOrDefault(group.parent.get, -1)
    if p >= 0 and p != g:
      parent[N + g] = p
      depth[g] = depth[p] + 1
    else:
      depth[g] = 1
  for i, node in nodes:
    nodeIndex[node.id] = i
    let p = if node.parent.isNone: -1 else: groupIndex.getOrDefault(node.parent.get, -1)
    if p >= 0: parent[i] = p
    kids[parent[i]].add i
  for g in 0 ..< G: kids[parent[N + g]].add N + g

  # A link asks for one node to sit beside another. It belongs to the innermost container that
  # holds both ends, and there it relates the two children of that container the ends are in.
  var linkA, linkB, sideA, sideB, itemA, itemB: seq[int]
  var hintLinks = newSeq[seq[int]](N + G)
  var edgeLinks = newSeq[seq[int]](N + G)
  template addLink(a0, b0, sa, sb: int, lists: untyped) =
    let a = a0
    let b = b0
    if a != b:
      var ia = a
      var ib = b
      var ca = parent[a]
      var cb = parent[b]
      while ca != cb:
        if depth[ca] >= depth[cb]:
          ia = N + ca
          ca = parent[ia]
        else:
          ib = N + cb
          cb = parent[ib]
      let k = linkA.len
      linkA.add a
      linkB.add b
      sideA.add sa
      sideB.add sb
      itemA.add ia
      itemB.add ib
      lists[ia].add k
      lists[ib].add k
  for hint in hints:
    let row = hint.direction == "row"
    for i in 1 ..< hint.members.len:
      let a = nodeIndex.getOrDefault(hint.members[i - 1], -1)
      let b = nodeIndex.getOrDefault(hint.members[i], -1)
      if a >= 0 and b >= 0: addLink(a, b, (if row: 1 else: 3), (if row: 0 else: 2), hintLinks)
  # An edge between two like sides says least about where its ends go, so those come last.
  for likeSides in [false, true]:
    for edge in edges:
      if (edge.lhsDir == edge.rhsDir) != likeSides: continue
      let a = nodeIndex.getOrDefault(edge.lhsId, -1)
      let b = nodeIndex.getOrDefault(edge.rhsId, -1)
      if a >= 0 and b >= 0: addLink(a, b, sideIndex(edge.lhsDir), sideIndex(edge.rhsDir), edgeLinks)

  # Position of each item in its container, and its size in cells.
  var x = newSeq[int](N + G)
  var y = newSeq[int](N + G)
  var w = newSeq[int](N + G)
  var h = newSeq[int](N + G)
  for i in 0 ..< N + G:
    w[i] = 1
    h[i] = 1
  var placed = newSeq[bool](N + G)

  var order: seq[int]
  var cells = initTable[(int, int), int]()
  var large: seq[int]
  var reach = initTable[(int, int, int, int, int, int), int]()
  var first = 0
  var ax = 0
  var ay = 0

  proc anchor(node, item: int) =
    ax = 0
    ay = 0
    var cur = node
    while cur != item:
      ax += x[cur]
      ay += y[cur]
      cur = N + parent[cur]

  proc put(item, px, py: int) =
    x[item] = px
    y[item] = py
    placed[item] = true
    order.add item
    if w[item] * h[item] > SMALL:
      large.add item
      return
    for cy in py ..< py + h[item]:
      for cx in px ..< px + w[item]: cells[cellKey(cx, cy)] = item

  proc overlaps(item, rx, ry, rw, rh: int): bool =
    x[item] < rx + rw and rx < x[item] + w[item] and y[item] < ry + rh and ry < y[item] + h[item]

  proc collide(rx, ry, rw, rh: int): int =
    if rw * rh > SMALL:
      for i in first ..< order.len:
        if overlaps(order[i], rx, ry, rw, rh): return order[i]
      return -1
    for cy in ry ..< ry + rh:
      for cx in rx ..< rx + rw:
        let hit = cells.getOrDefault(cellKey(cx, cy), -1)
        if hit >= 0: return hit
    for item in large:
      if overlaps(item, rx, ry, rw, rh): return item
    -1

  # How far a block must slide along (sx, sy) to be clear. Each step jumps past what it hit, and
  # the result is kept, because a later block starting from the same place cannot stop sooner.
  proc slide(rx, ry, rw, rh, sx, sy: int): int =
    let key = (rx, ry, rw, rh, sx, sy)
    var k = reach.getOrDefault(key, 0)
    while true:
      let hit = collide(rx + k * sx, ry + k * sy, rw, rh)
      if hit < 0: break
      k = if sx > 0: x[hit] + w[hit] - rx elif sx < 0: rx + rw - x[hit]
          elif sy > 0: y[hit] + h[hit] - ry else: ry + rh - y[hit]
    reach[key] = k
    k

  proc follow(start, k: int) =
    let forward = itemA[k] == start
    let to = if forward: itemB[k] else: itemA[k]
    if placed[to]: return
    let sp = if forward: sideA[k] else: sideB[k]
    let sq = if forward: sideB[k] else: sideA[k]
    anchor((if forward: linkA[k] else: linkB[k]), start)
    let pax = ax
    let pay = ay
    anchor((if forward: linkB[k] else: linkA[k]), to)
    var dx = DX[sp]
    var dy = DY[sp]
    var shiftX = 0
    var shiftY = 0
    let facing = DX[sp] + DX[sq] == 0 and DY[sp] + DY[sq] == 0
    if sp == sq:
      # Like sides: the edge loops around, so the nodes stack across the direction it leaves in.
      dx = if DX[sp] == 0: 1 else: 0
      dy = 1 - dx
    elif not facing:
      # A bend: one step along the side the edge leaves, one step back from the side it enters.
      shiftX = -DX[sq]
      shiftY = -DY[sq]
    var bx, by: int
    if dx != 0:
      bx = if dx > 0: x[start] + w[start] else: x[start] - w[to]
      by = y[start] + pay + shiftY - ay
    else:
      by = if dy > 0: y[start] + h[start] else: y[start] - h[to]
      bx = x[start] + pax + shiftX - ax
    if facing:
      # When several placed nodes reach this one through the same pair of sides, line it up
      # with the middle one, not with whichever happened to be visited first.
      let list = edgeLinks[to]
      if list.len > 1:
        var wanted: seq[int]
        for j in list:
          let toIsB = itemB[j] == to
          let other = if toIsB: itemA[j] else: itemB[j]
          if not placed[other] or (if toIsB: sideA[j] else: sideB[j]) != sp or
             (if toIsB: sideB[j] else: sideA[j]) != sq: continue
          anchor((if toIsB: linkA[j] else: linkB[j]), other)
          let at = if dx != 0: y[other] + ay else: x[other] + ax
          anchor((if toIsB: linkB[j] else: linkA[j]), to)
          wanted.add at - (if dx != 0: ay else: ax)
        if wanted.len > 1:
          wanted.sort()
          if dx != 0: by = wanted[(wanted.len - 1) shr 1]
          else: bx = wanted[(wanted.len - 1) shr 1]
      # Taken: move sideways, to whichever side is nearer, so the edge can still leave straight.
      let px = if dx == 0: 1 else: 0
      let py = 1 - px
      let forth = slide(bx, by, w[to], h[to], px, py)
      let back = if forth == 0: 0 else: slide(bx, by, w[to], h[to], -px, -py)
      let near = if forth <= back: forth else: -back
      bx += px * near
      by += py * near
    else:
      let far = slide(bx, by, w[to], h[to], dx, dy)
      bx += dx * far
      by += dy * far
    put(to, bx, by)

  proc layout(c: int) =
    let items = kids[c]
    if items.len == 0: return
    order.setLen 0
    var starts: seq[int]
    for start in items:
      if placed[start]: continue
      first = order.len
      starts.add first
      cells.clear()
      large.setLen 0
      reach.clear()
      put(start, 0, 0)
      # Declared alignments are followed as soon as a node is placed, ahead of any edge.
      var hintAt = first
      var edgeAt = first
      var linkAt = 0
      while true:
        if hintAt < order.len:
          let start = order[hintAt]
          inc hintAt
          for k in hintLinks[start]: follow(start, k)
          continue
        if edgeAt >= order.len: break
        let list = edgeLinks[order[edgeAt]]
        if linkAt >= list.len:
          inc edgeAt
          linkAt = 0
          continue
        let k = list[linkAt]
        inc linkAt
        follow(order[edgeAt], k)
    starts.add order.len

    # Unconnected parts go side by side, wrapping into rows that keep the whole roughly square.
    let count = starts.len - 1
    var minX = newSeq[int](count)
    var minY = newSeq[int](count)
    var partW = newSeq[int](count)
    var partH = newSeq[int](count)
    var area = 0
    var widest = 0
    for p in 0 ..< count:
      var x0 = high(int)
      var y0 = high(int)
      var x1 = low(int)
      var y1 = low(int)
      for i in starts[p] ..< starts[p + 1]:
        let item = order[i]
        x0 = min(x0, x[item])
        y0 = min(y0, y[item])
        x1 = max(x1, x[item] + w[item])
        y1 = max(y1, y[item] + h[item])
      minX[p] = x0
      minY[p] = y0
      partW[p] = x1 - x0
      partH[p] = y1 - y0
      area += partW[p] * partH[p]
      widest = max(widest, partW[p])
    let limit = max(float(widest), ceil(sqrt(float(area) * 2)))
    var cx = 0
    var cy = 0
    var shelf = 0
    var width = 0
    for p in 0 ..< count:
      if cx > 0 and float(cx + partW[p]) > limit:
        cy += shelf
        cx = 0
        shelf = 0
      for i in starts[p] ..< starts[p + 1]:
        x[order[i]] += cx - minX[p]
        y[order[i]] += cy - minY[p]
      cx += partW[p]
      shelf = max(shelf, partH[p])
      width = max(width, cx)
    if c < G:
      w[N + c] = width
      h[N + c] = cy + shelf

  for c in countdown(G - 1, 0): layout(c)
  layout(root)

  result.groupCol = newSeq[int](G)
  result.groupRow = newSeq[int](G)
  result.groupParent = newSeq[int](G)
  result.groupEmpty = newSeq[bool](G)
  for g in 0 ..< G:
    let p = parent[N + g]
    result.groupParent[g] = if p == root: -1 else: p
    result.groupCol[g] = x[N + g] + (if p == root: 0 else: result.groupCol[p])
    result.groupRow[g] = y[N + g] + (if p == root: 0 else: result.groupRow[p])
    if kids[g].len == 0: result.groupEmpty[g] = true
  result.col = newSeq[int](N)
  result.row = newSeq[int](N)
  result.nodeParent = newSeq[int](N)
  for i in 0 ..< N:
    let p = parent[i]
    result.nodeParent[i] = if p == root: -1 else: p
    result.col[i] = x[i] + (if p == root: 0 else: result.groupCol[p])
    result.row[i] = y[i] + (if p == root: 0 else: result.groupRow[p])
  result.groupCols = w[N ..< N + G]
  result.groupRows = h[N ..< N + G]

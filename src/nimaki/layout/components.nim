## port-of: src/layout/components.ts
## port-status: draft
import std/[options, tables]
import compound

type Part = ref object
  nodes: seq[CNode]
  edges: seq[CEdge]
  left, top, right, bottom: float

proc wrapComponents*(nodes: seq[CNode], edges: seq[CEdge], width, gap: float): Option[CompoundResult] =
  ## Moves disconnected parts into rows without changing the layout inside a part.
  var parent = newSeq[int](nodes.len)
  for i in 0 ..< nodes.len: parent[i] = i
  proc root(start: int): int =
    var i = start
    while parent[i] != i:
      parent[i] = parent[parent[i]]
      i = parent[i]
    i
  proc join(a, b: int) = parent[root(a)] = root(b)
  for i in 0 ..< nodes.len:
    if nodes[i].parent >= 0: join(i, nodes[i].parent)
  for e in edges: join(e.src, e.dst)

  var parts = initOrderedTable[int, Part]()
  proc includeIn(p: Part, x, y: float, w = 0.0, h = 0.0) =
    p.left = min(p.left, x - w / 2)
    p.top = min(p.top, y - h / 2)
    p.right = max(p.right, x + w / 2)
    p.bottom = max(p.bottom, y + h / 2)
  for i in 0 ..< nodes.len:
    let id = root(i)
    var part = parts.getOrDefault(id, nil)
    if part == nil:
      part = Part(left: Inf, top: Inf, right: -Inf, bottom: -Inf)
      parts[id] = part
    let c = nodes[i]
    part.nodes.add c
    includeIn(part, c.x, c.y, c.w, c.h)
  if parts.len < 2: return none(CompoundResult)
  for e in edges:
    let part = parts[root(e.src)]
    part.edges.add e
    for i in countup(0, e.route.len - 1, 3): includeIn(part, e.route[i], e.route[i + 1])
    if e.labelW > 0: includeIn(part, e.labelX, e.labelY, e.labelW, e.labelH)

  var x, y, rowHeight, right = 0.0
  var fromX = Inf
  var to = -Inf
  var shifts: seq[float]
  for part in parts.values:
    let w = part.right - part.left
    let h = part.bottom - part.top
    if x > 0 and x + w > width:
      y += rowHeight + gap
      x = 0
      rowHeight = 0
    shifts.add x - part.left
    shifts.add y - part.top
    fromX = min(fromX, part.left)
    to = max(to, part.right)
    right = max(right, x + w)
    rowHeight = max(rowHeight, h)
    x += w + gap
  if right >= to - fromX: return none(CompoundResult)
  var k = 0
  for part in parts.values:
    shiftLayout(part.nodes, part.edges, shifts[k], shifts[k + 1])
    k += 2
  some(CompoundResult(width: right, height: y + rowHeight))

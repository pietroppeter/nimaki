## port-of: src/diagrams/sankey/layout.ts
## port-status: conformant
##
## Pele sorts short lists by insertion and long ones with the built-in sort. Every comparison
## here breaks ties by index, so the order is the same with any sort; nimaki uses one.
import std/algorithm
from std/math import classify, FloatClass
import ../../errors
import ../../jsmath
import ../../js
import db

type
  Alignment* = enum aJustify, aLeft, aRight, aCenter

  LayoutOptions* = object
    width*, height*, nodeWidth*, nodePadding*: float
    labelHeight*: float   ## Height of a label line; thin nodes are kept at least this far apart where there is room.
    alignment*: Alignment

  PlacedNode* = object
    layer*: int
    value*: float   ## Total flow through the node, in the diagram's units.
    x*, y*, height*: float

  PlacedLink* = object
    source*, target*: int
    value*, thickness*: float
    sourceY*, targetY*: float   ## Vertical centers of the band where it leaves its source and where it enters its target.

  SankeyLayout* = object
    nodes*: seq[PlacedNode]
    links*: seq[PlacedLink]

const PASSES = 6

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

func ranked(d: float, a, b: int): int =
  ## `d || a - b` as a comparator's sign.
  if d < 0: -1 elif d > 0: 1 else: a - b

proc layoutSankey*(model: SankeyModel, options: LayoutOptions): SankeyLayout =
  ## Places nodes in columns by their distance from a source, sizes them by their flow, and
  ## then lets each column settle next to its neighbours so that the bands cross less.
  let n = model.nodes.len
  var links: seq[PlacedLink]
  for link in model.links:
    links.add PlacedLink(source: link.source, target: link.target,
                         value: (if link.value.isFinite and link.value > 0: link.value else: 0.0))
  var outgoing = newSeq[seq[int]](n)
  var incoming = newSeq[seq[int]](n)
  for k, link in links:
    outgoing[link.source].add k
    incoming[link.target].add k

  # Longest distance from a source, in topological order; what is left over lies on a cycle.
  var depth = newSeq[int](n)
  var pending = newSeq[int](n)
  var order: seq[int]
  for i in 0 ..< n:
    pending[i] = incoming[i].len
    if pending[i] == 0: order.add i
  var q = 0
  while q < order.len:
    let i = order[q]
    for k in outgoing[i]:
      let t = links[k].target
      if depth[t] < depth[i] + 1: depth[t] = depth[i] + 1
      dec pending[t]
      if pending[t] == 0: order.add t
    inc q
  if order.len < n:
    # Every node left over has a predecessor that is left over too; walking back finds the loop.
    var stuck = 0
    while pending[stuck] == 0: inc stuck
    var seen = newSeq[bool](n)
    while not seen[stuck]:
      seen[stuck] = true
      for k in incoming[stuck]:
        if pending[links[k].source] > 0:
          stuck = links[k].source
          break
    raise newPeleError("Sankey diagrams cannot have circular links, and \"" & model.nodes[stuck].id &
                       "\" is part of one.", "semantic", "sankey")
  var layers = 1
  for i in 0 ..< n:
    if depth[i] + 1 > layers: layers = depth[i] + 1
  var reach = newSeq[int](n)
  for q in countdown(n - 1, 0):
    let i = order[q]
    for k in outgoing[i]:
      if reach[i] < reach[links[k].target] + 1: reach[i] = reach[links[k].target] + 1

  # Flows are scaled to the largest one, so that sums of huge values stay finite.
  var largest = 0.0
  for link in links:
    if link.value > largest: largest = link.value
  let unit = if largest > 0: 1 / largest else: 0.0

  var nodes: seq[PlacedNode]
  var flow = newSeq[float](n)
  var columns = newSeq[seq[int]](layers)
  let step = if layers > 1: (options.width - options.nodeWidth) / float(layers - 1) else: 0.0
  for i in 0 ..< n:
    var layer: int
    case options.alignment
    of aLeft: layer = depth[i]
    of aRight: layer = layers - 1 - reach[i]
    of aCenter:
      layer = depth[i]
      if incoming[i].len == 0 and outgoing[i].len > 0:
        layer = layers
        for k in outgoing[i]:
          if depth[links[k].target] - 1 < layer: layer = depth[links[k].target] - 1
    of aJustify:
      layer = if outgoing[i].len > 0: depth[i] else: layers - 1
    var into, outOf, value, valueOut = 0.0
    for k in incoming[i]:
      into += links[k].value * unit
      value += links[k].value
    for k in outgoing[i]:
      outOf += links[k].value * unit
      valueOut += links[k].value
    flow[i] = jsMax(into, outOf)
    nodes.add PlacedNode(layer: layer, value: jsMax(value, valueOut), x: float(layer) * step)
    columns[layer].add i

  var tallest = 1
  for column in columns:
    if column.len > tallest: tallest = column.len
  let gap = if tallest > 1: jsMin(options.nodePadding, options.height / float(tallest - 1)) else: options.nodePadding
  var scale = Inf
  for column in columns:
    var sum = 0.0
    for i in column: sum += flow[i]
    if sum > 0: scale = jsMin(scale, (options.height - float(column.len - 1) * gap) / sum)
  if not scale.isFinite or scale < 0: scale = 0

  # A thin node still needs room for its label. Where every column can afford it, each node
  # claims at least a label's height, and the flows are scaled down to make that fit.
  var claim = jsMax(0, options.labelHeight - gap)
  proc fits(s: float): bool =
    for column in columns:
      var extent = float(column.len - 1) * gap
      for i in column: extent += jsMax(flow[i] * s, claim)
      if extent > options.height + 1e-6: return false
    true
  if claim > 0 and not fits(scale):
    if fits(0):
      var low = 0.0
      for k in 0 ..< 40:
        let mid = (low + scale) / 2
        if fits(mid): low = mid
        else: scale = mid
      scale = low
    else:
      claim = 0

  # The room a node keeps clear above and below itself.
  var margin = newSeq[float](n)
  for link in links.mitems: link.thickness = link.value * unit * scale
  for column in columns:
    var y = 0.0
    for i in column:
      nodes[i].height = flow[i] * scale
      margin[i] = jsMax(0, claim - nodes[i].height) / 2
      nodes[i].y = y + margin[i]
      y += nodes[i].height + 2 * margin[i] + gap
    # Spare room is shared out between the nodes of a column.
    let spare = (options.height - y + gap) / float(column.len + 1)
    for k, i in column: nodes[i].y += spare * float(k + 1)

  template center(i: int): float = nodes[i].y + nodes[i].height / 2

  # Bands leave and enter a node in the order of where they go, so they do not cross at it.
  # These are the offsets of each band's middle from the top of the node at either end.
  var sourceOffset = newSeq[float](links.len)
  var targetOffset = newSeq[float](links.len)
  proc stackOut(i: int) =
    var y = 0.0
    outgoing[i].sort(proc (a, b: int): int = ranked(center(links[a].target) - center(links[b].target), a, b))
    for k in outgoing[i]:
      sourceOffset[k] = y + links[k].thickness / 2
      y += links[k].thickness
  proc stackIn(i: int) =
    var y = 0.0
    incoming[i].sort(proc (a, b: int): int = ranked(center(links[a].source) - center(links[b].source), a, b))
    for k in incoming[i]:
      targetOffset[k] = y + links[k].thickness / 2
      y += links[k].thickness
  proc stackAll() =
    for i in 0 ..< n:
      stackOut(i)
      stackIn(i)

  # Moves each node of a column towards where its bands would run level, then restores the
  # order and the gaps. `forward` looks at the bands coming in, otherwise at those going out.
  proc settle(l: int, pull: float, forward: bool) =
    for i in columns[l]:
      let count = if forward: incoming[i].len else: outgoing[i].len
      if count == 0: continue
      if forward: stackIn(i)
      else: stackOut(i)
      var weighted, weight, plain = 0.0
      for k in (if forward: incoming[i] else: outgoing[i]):
        let level = if forward: nodes[links[k].source].y + sourceOffset[k] - targetOffset[k]
                    else: nodes[links[k].target].y + targetOffset[k] - sourceOffset[k]
        weighted += level * links[k].thickness
        weight += links[k].thickness
        plain += center(if forward: links[k].source else: links[k].target) - nodes[i].height / 2
      let wanted = if weight > 0: weighted / weight else: plain / float(count)
      nodes[i].y += (wanted - nodes[i].y) * pull
    columns[l].sort(proc (a, b: int): int = ranked(center(a) - center(b), a, b))
    var y = 0.0
    for i in columns[l]:
      if nodes[i].y - margin[i] < y: nodes[i].y = y + margin[i]
      y = nodes[i].y + nodes[i].height + margin[i] + gap
    y = options.height
    for k in countdown(columns[l].len - 1, 0):
      let i = columns[l][k]
      if nodes[i].y + nodes[i].height + margin[i] > y: nodes[i].y = y - nodes[i].height - margin[i]
      y = nodes[i].y - margin[i] - gap

  stackAll()
  for pass in 0 ..< PASSES:
    let pull = pow(0.99, float(pass))
    for l in countdown(layers - 2, 0): settle(l, pull, false)
    stackAll()
    for l in 1 ..< layers: settle(l, pull, true)
    stackAll()
  for k in 0 ..< links.len:
    links[k].sourceY = nodes[links[k].source].y + sourceOffset[k]
    links[k].targetY = nodes[links[k].target].y + targetOffset[k]

  SankeyLayout(nodes: nodes, links: links)

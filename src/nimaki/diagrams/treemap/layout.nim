## port-of: src/diagrams/treemap/layout.ts
## port-status: conformant
import std/[algorithm, options]
from std/math import classify, FloatClass
import ../../js
import model

type
  Box* = ref object
    node*: TreemapNode
    parent*: Box   ## nil for none
    series*: int
      ## Position among the top-level nodes of the branch this box belongs to, which picks its color.
    value*: float
      ## A leaf's own value, or the sum of the leaves under a section.
    children*: seq[Box]
    headed*: bool
      ## Small sections give their header space to their children.
    header*: float
    x*, y*, w*, h*: float

  Insets* = object
    gap*: float
    header*: float
      ## Space a section keeps for its header, and around its children on the other three sides.
    short*: float
    side*: float

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

proc box(node: TreemapNode, parent: Box, series: int): Box =
  let value = if node.leaf and node.value.isSome and node.value.get.isFinite and node.value.get > 0: node.value.get else: 0.0
  Box(node: node, parent: parent, series: series, value: value)

func clamp(v, low, high: float): float = (if v >= low: jsMin(v, high) else: low)

proc squarify(boxes: seq[Box], total: float, x0, y0, w0, h0, gap: float) =
  ## Lays out the boxes in the rectangle as one squarified treemap: rows are added along the
  ## shorter side, and a row stops growing when another box would make its boxes less square.
  var (x, y, w, h) = (x0, y0, w0, h0)
  var rest = total
  var start = 0
  while start < boxes.len:
    let scale = (w * h) / rest
    let side = jsMin(w, h)
    var sum = boxes[start].value * scale
    let largest = sum
    var worst = jsMax((side * side * largest) / (sum * sum), (sum * sum) / (side * side * largest))
    var stop = start + 1
    while stop < boxes.len:
      let smallest = boxes[stop].value * scale
      let next = sum + smallest
      let ratio = jsMax((side * side * largest) / (next * next), (next * next) / (side * side * smallest))
      if ratio > worst: break
      worst = ratio
      sum = next
      inc stop

    let thickness = sum / side
    var offset = 0.0
    for i in start ..< stop:
      let b = boxes[i]
      let length = if i == stop - 1: side - offset else: (b.value * scale) / thickness
      let bx = if w >= h: x else: x + offset
      let by = if w >= h: y + offset else: y
      let bw = if w >= h: thickness else: length
      let bh = if w >= h: length else: thickness
      # Omit the gap if it would erase the box.
      let gx = if jsRound(bx + bw - gap / 2) > jsRound(bx + gap / 2): gap / 2 else: 0
      let gy = if jsRound(by + bh - gap / 2) > jsRound(by + gap / 2): gap / 2 else: 0
      b.x = jsRound(bx + gx)
      b.y = jsRound(by + gy)
      b.w = jsRound(bx + bw - gx) - b.x
      b.h = jsRound(by + bh - gy) - b.y
      offset += length
      rest -= b.value
    if w >= h:
      x += thickness
      w -= thickness
    else:
      y += thickness
      h -= thickness
    start = stop

proc layoutTreemap*(roots: seq[TreemapNode], width, height: float, insets: Insets): seq[Box] =
  ## Returns boxes with positive values, including zero-size boxes, parents before children.
  var top: seq[Box]
  for index, node in roots: top.add box(node, nil, index)
  var all = top
  var i = 0
  while i < all.len:
    let parent = all[i]
    for node in parent.node.children:
      let child = box(node, parent, parent.series)
      parent.children.add child
      all.add child
    inc i
  for i in countdown(all.high, 0):
    let b = all[i]
    if b.parent != nil: b.parent.value += b.value

  let gap = insets.gap
  let header = insets.header
  let short = insets.short
  let side = insets.side
  var placed: seq[Box]
  proc place(children: seq[Box], x, y, w0, h0: float) =
    var shown: seq[Box]
    for b in children:
      if b.value > 0: shown.add b
    # sort((a, b) => b.value - a.value): stable, larger first
    shown.sort(proc (a, b: Box): int = cmp(b.value, a.value))
    var total = 0.0
    for b in shown: total += b.value
    if shown.len == 0 or not total.isFinite: return
    let w = jsMax(0, w0)
    let h = jsMax(0, h0)
    if w > 0 and h > 0: squarify(shown, total, x - gap / 2, y - gap / 2, w + gap, h + gap, gap)
    for b in shown:
      let x0 = clamp(b.x, x, x + w)
      let y0 = clamp(b.y, y, y + h)
      b.w = clamp(b.x + b.w, x0, x + w) - x0
      b.h = clamp(b.y + b.h, y0, y + h) - y0
      b.x = x0
      b.y = y0
      placed.add b

  place(top, 0, 0, width, height)
  i = 0
  while i < placed.len:
    let b = placed[i]
    inc i
    if b.children.len == 0: continue
    let top = if b.h - header - side >= 12: header else: short
    b.headed = b.w > jsMax(24, 2 * side) and b.h - top - side >= 8
    b.header = if b.headed: top else: 0
    if b.headed: place(b.children, b.x + side, b.y + top, b.w - 2 * side, b.h - top - side)
    else: place(b.children, b.x, b.y, b.w, b.h)
  placed

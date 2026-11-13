## port-of: src/diagrams/block/layout.ts
## port-status: draft
##
## Pele's gap lists can have holes (`gaps[at] = ...` past the end), read as 0: here a hole is NaN.
import std/math
import ../../errors

type Cell* = ref object of RootObj
  children*: seq[Cell]
  columns*: float   ## Grid width: a positive count, or -1 to put every child on one row.
  span*: float
  space*: bool
  head*: float      ## Height reserved above a container's grid for its title.
  nw*, nh*: float   ## Size the content needs.
  col*, row*, cols*: int
  heights*: seq[float]
  rowGaps*, colGaps*: seq[float]   ## Extra space after each row or column.
  x*, y*, w*, h*: float

const MAX_SPAN = 1000.0

func gapAt*(gaps: seq[float], i: int): float =
  ## `gaps[i] ?? 0`
  if i < 0 or i >= gaps.len or gaps[i].isNaN: 0.0 else: gaps[i]

proc setGap*(gaps: var seq[float], i: int, value: float) =
  while gaps.len <= i: gaps.add NaN
  gaps[i] = value

func isInteger(x: float): bool = x == x and x - x == 0 and floor(x) == x

proc calculateBlockPosition*(columns, position: float): (float, float) =
  if columns == 0 or not isInteger(columns):
    raise newPeleError("Columns must be an integer !== 0.", "semantic", ErrorInfo(diagramType: "block"))
  if position < 0 or not isInteger(position):
    raise newPeleError("Position must be a non-negative integer." & $position, "semantic",
                       ErrorInfo(diagramType: "block"))
  if columns < 0: return (position, 0.0)
  (position mod columns, floor(position / columns))

func total(gaps: seq[float]): float =
  for gap in gaps:
    if not gap.isNaN: result += gap

proc measure(box: Cell, gap, inset: float) =
  ## Puts each child in its grid cell and sizes the container. Every column is as wide as the
  ## widest block needs. Every row that holds a plain block is as tall as the tallest block in the
  ## container; a row of nothing but containers is only as tall as they need.
  let columns = box.columns
  var heights: seq[float]
  var position = 0.0
  var cols = 0.0
  var cw = 0.0
  var tallest = 0.0
  for child in box.children:
    let (px, py) = calculateBlockPosition(columns, position)
    # Mermaid lets a block wider than the rest of its row stick out. Here it stops at the last column.
    var span = if child.span >= 1: min(child.span, MAX_SPAN) else: 1.0
    if columns > 0 and span > columns - px: span = columns - px
    child.span = span
    child.col = int(px)
    child.row = int(py)
    position += span
    if px + span > cols: cols = px + span
    if int(py) == heights.len: heights.add 0
    let r = int(py)
    if child.children.len == 0: heights[r] = -1
    elif heights[r] >= 0 and child.nh > heights[r]: heights[r] = child.nh
    if child.space: continue
    let width = (child.nw - gap * (span - 1)) / span
    if width > cw: cw = width
    if child.nh > tallest: tallest = child.nh
  var height = float(heights.len - 1) * gap + total(box.rowGaps)
  for row in 0 ..< heights.len:
    if heights[row] < 0: heights[row] = tallest
    height += heights[row]
  box.cols = int(cols)
  box.heights = heights
  box.nw = max(box.nw, cols * cw + (cols - 1) * gap + total(box.colGaps) + 2 * inset)
  box.nh = height + 2 * inset + box.head

proc arrange(box: Cell, gap, inset: float) =
  ## Gives each child its cell, sharing out any room the container has beyond what it needs.
  let cols = box.cols
  let heights = box.heights
  let rows = heights.len
  let cw = (box.w - 2 * inset - float(cols - 1) * gap - total(box.colGaps)) / float(cols)
  let room = box.h - 2 * inset - box.head - float(rows - 1) * gap - total(box.rowGaps)
  var offsets: seq[float]
  if box.colGaps.len > 0:
    var sum = 0.0
    for col in 0 ..< cols:
      offsets.add sum
      sum += gapAt(box.colGaps, col)
  var needed = 0.0
  for height in heights: needed += height
  let scale = if needed > 0: room / needed else: 0.0
  let share = if needed > 0: 0.0 else: room / float(rows)
  let left = box.x - box.w / 2 + inset
  var top = box.y - box.h / 2 + inset + box.head
  var row = 0
  for child in box.children:
    while row < child.row:
      top += heights[row] * scale + share + gap + gapAt(box.rowGaps, row)
      inc row
    let before = gapAt(offsets, child.col)
    let span = child.span
    child.w = cw * span + gap * (span - 1) + gapAt(offsets, child.col + int(span) - 1) - before
    child.h = heights[row] * scale + share
    child.x = left + float(child.col) * (cw + gap) + before + child.w / 2
    child.y = top + child.h / 2

proc layout*(root: Cell, gap: float): (float, float) =
  ## Lays out a tree of cells in place. The root has no border, so its grid starts at the origin.
  var order = @[root]
  var i = 0
  while i < order.len:
    for child in order[i].children: order.add child
    inc i
  for i in countdown(order.len - 1, 0):
    let box = order[i]
    if box.children.len > 0: measure(box, gap, if i == 0: 0.0 else: gap)
  root.w = root.nw
  root.h = root.nh
  root.x = root.w / 2
  root.y = root.h / 2
  for i in 0 ..< order.len:
    let box = order[i]
    if box.children.len > 0: arrange(box, gap, if i == 0: 0.0 else: gap)
  (root.w, root.h)

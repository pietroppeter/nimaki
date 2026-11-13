## port-of: src/diagrams/c4/layout.ts
## port-status: draft
##
## Pele's maps keyed by elements and groups are keyed here by their addresses.
import std/[tables, strutils, math]
import ../../svg/edges
import ../../js
import ../../text/[label, measurer]
import db, route

const
  SHAPE_W = 216.0
  SHAPE_MIN_H = 64.0
  PAD_X = 14.0
  PAD_Y = 12.0
  # Room between two columns for the label of a line across them, clear of an arrowhead on either
  # side, with an arrowhead's length to spare.
  GAP_X = NARROW + LABEL_PAD + 3 * ARROW
  GAP_Y = 88.0
  GROUP_PAD* = LANE + 8
  GROUP_GAP = 48.0
  HEAD_LEFT* = 16.0
  HEAD_TOP* = 10.0

let FORMS = {"person": "person", "box": "rect", "rounded": "rect", "component": "rect",
  "cylinder": "cyl", "database": "cyl", "db": "cyl", "queue": "h-cyl", "pipe": "h-cyl"}.toTable

type
  Node* = ref object of Box
    shape*: C4Element
    labels*: seq[Label]   ## Type, name, technology, description.
    textH*: float

  Group* = ref object of Box
    boundary*: C4Element
    kids*: seq[Group]
    nodes*: seq[Node]
    labels*: seq[Label]   ## Name, type, description.
    head*, headW*, headX*: float

  Layout* = object
    order*: seq[Group]    ## The boundaries drawn, parents first. The first is the unnamed top level.
    boxes*: Table[pointer, Box]

func key*(e: C4Element): pointer = cast[pointer](e)

proc formOf(shape: C4Element): string =
  let explicit = FORMS.getOrDefault(shape["shape"].toLowerAscii,
                                    FORMS.getOrDefault(shape["sprite"].toLowerAscii))
  if explicit != "": return explicit
  if shape["tags"] != "":
    for tag in shape["tags"].split(','):
      let form = FORMS.getOrDefault(jsTrim(tag).toLowerAscii)
      if form != "": return form
  let kind = shape.kind
  if kind.endsWith("person"): "person"
  elif kind.endsWith("_db"): "cyl"
  elif kind.endsWith("_queue"): "h-cyl"
  else: "rect"

proc measure(shape: C4Element, measurer: TextMeasurer, size, small: float, width = SHAPE_W): Node =
  let form = formOf(shape)
  let capW = if form == "h-cyl": 36.0 else: 0.0
  let capH = if form == "person": HEAD elif form == "cyl": 24.0 else: 0.0
  let inner = width - 2 * PAD_X - capW
  let techn = shape["techn"]
  let labels = @[
    layoutLabel("«" & shape.kind.replace('_', ' ') & "»", false, measurer, small - 1, inner),
    layoutLabel(shape.label, false, measurer, size, inner, Bold),
    layoutLabel(if techn != "": "[" & techn & "]" else: "", false, measurer, small, inner),
    layoutLabel(shape["descr"], false, measurer, small, inner)]
  var tw = 0.0
  var textH = if labels[3].height > 0: 4.0 else: 0.0
  for label in labels:
    tw = max(tw, label.width)
    textH += label.height
  Node(shape: shape, form: form, labels: labels, textH: textH, x: 0, y: 0,
       w: max(width, tw + 2 * PAD_X + capW), h: max(SHAPE_MIN_H, textH + 2 * PAD_Y + capH))

proc rows[B: Box](boxes: seq[B], perRow: int, gapX, gapY: float, stretch: bool): (float, float) =
  ## Places boxes left to right in rows of `perRow`, from (0, 0), and returns the width and height
  ## the rows take. Shapes are stretched to the height of their row; boundaries keep their own.
  var width = 0.0
  var y = 0.0
  var start = 0
  while start < boxes.len:
    let stop = min(boxes.len, start + perRow)
    var x = 0.0
    var rowH = 0.0
    for i in start ..< stop: rowH = max(rowH, boxes[i].h)
    for i in start ..< stop:
      let box = boxes[i]
      box.x = x
      box.y = y
      if stretch: box.h = rowH
      x += box.w + gapX
    width = max(width, x - gapX)
    y += rowH + gapY
    start += perRow
  (width, if boxes.len > 0: y - gapY else: 0.0)

func toCount(x: float): int =
  ## A row length: at least 1 here, and no more than any list holds.
  if x > 1e9: 1_000_000_000 else: int(x)

proc layoutC4*(db: C4Db, measurer: TextMeasurer, size, small, room, gap: float): Layout =
  ## Mermaid's grid: in each boundary, its shapes in rows of c4ShapeInRow, then the boundaries
  ## inside it in rows of c4BoundaryInRow. `room` NaN is undefined.
  let loose = room.isNaN
  let groupPad = if loose: GROUP_PAD else: 12.0
  var groups = initTable[pointer, Group]()
  var all: seq[Group]
  for boundary in db.boundaries:
    let labelRoom = if loose: 4000.0 else: max(80.0, room - 2 * HEAD_LEFT - 2 * GROUP_PAD * 2)
    let labels =
      if boundary.parent != nil:
        let typ = boundary["type"]
        @[layoutLabel(boundary.label, false, measurer, size, labelRoom, Bold),
          layoutLabel(if typ != "": "[" & typ & "]" else: "", false, measurer, small, labelRoom),
          layoutLabel(boundary["descr"], false, measurer, small, labelRoom)]
      else: @[]
    var head = 0.0
    var headW = 0.0
    for label in labels:
      head += label.height
      headW = max(headW, label.width)
    let group = Group(boundary: boundary, labels: labels,
      head: (if head > 0: head + HEAD_TOP + 6 + LANE else: groupPad),
      headW: headW, headX: HEAD_LEFT, form: "rect")
    if key(boundary) notin groups: all.add group
    groups[key(boundary)] = group
  let root = groups[key(db.boundaries[0])]
  for group in all:
    let parent = group.boundary.parent
    if parent != nil and key(parent) in groups: groups[key(parent)].kids.add group
  # A boundary that ends up inside itself is not reachable from the top, as in Mermaid.
  var order = @[root]
  var depths = {key(root.boundary): 0}.toTable
  var i = 0
  while i < order.len:
    for kid in order[i].kids:
      depths[key(kid.boundary)] = depths[key(order[i].boundary)] + 1
      order.add kid
    inc i
  for shape in db.shapes:
    if shape.parent != nil:
      let depth = float(depths.getOrDefault(key(shape.parent), 0))
      let nodeWidth = if loose: SHAPE_W else: max(100.0, min(SHAPE_W, room - 2 * depth * groupPad - 32))
      if key(shape.parent) in groups:
        groups[key(shape.parent)].nodes.add measure(shape, measurer, size, small, nodeWidth)

  let perRow = max(1.0, db.shapeInRow)
  let groupsPerRow = max(1.0, db.boundaryInRow)
  var kidsTop = initTable[pointer, float]()
  for i in countdown(order.len - 1, 0):
    let group = order[i]
    let gapX = if loose: GAP_X else: gap
    proc count[B: Box](boxes: seq[B], limit, gap: float): int =
      if loose: return toCount(limit)
      var widest = 1.0
      for box in boxes: widest = max(widest, box.w)
      toCount(max(1.0, min(limit, floor((room + gap - 2 * groupPad) / (widest + gap)))))
    let (gridW, gridH) = rows(group.nodes, count(group.nodes, perRow, gapX), gapX, GAP_Y, true)
    let (kidsW, kidsH) = rows(group.kids, count(group.kids, groupsPerRow, GROUP_GAP), GROUP_GAP,
                              GROUP_GAP, false)
    let between = if gridH > 0 and kidsH > 0: GROUP_GAP else: 0.0
    let frame = if group == root: 0.0 else: groupPad
    kidsTop[cast[pointer](group)] = gridH + between
    group.w = max(max(gridW, kidsW), group.headW + 2 * HEAD_LEFT - 2 * frame) + 2 * frame
    group.h = (if frame != 0: group.head else: frame) + gridH + between + kidsH + frame

  for group in order:
    let left = group.x + (if group == root: 0.0 else: groupPad)
    let top = group.y + (if group == root: 0.0 else: group.head)
    for node in group.nodes:
      node.x += left
      node.y += top
      result.boxes[key(node.shape)] = node
    for kid in group.kids:
      kid.x += left
      kid.y += top + kidsTop[cast[pointer](group)]
    if group != root: result.boxes[key(group.boundary)] = group
  result.order = order

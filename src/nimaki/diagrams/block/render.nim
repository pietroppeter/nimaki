## port-of: src/diagrams/block/render.ts
## port-status: draft
import std/[options, strutils, tables, sets]
from std/math import ceil, floor, isNaN, PI, `mod`
import ../../preprocess
import ../../svg/[builder, edges, ink, root, shapes, theme, title]
import ../../text/[label, measurer]
import ../../types
import ../../util/yaml
import ../../js
import ../../jsmath
import ../common/fit_width
import arrows, db, layout

const
  GAP = 12.0
  WRAP = 200.0
  CORNER = 8.0
  SHAPE_ATTRS = " fill=\"var(--_s)\" stroke=\"var(--_b)\""
  LINE_ATTRS = " stroke=\"var(--_b)\""
  OBSTACLE_BUDGET = 2_000_000   ## Checking every edge against every block is quadratic.
  LABEL_GAP = 4.0
  SQRT1_2 = 0.7071067811865476
  SPOTS = [0.5, 0.3, 0.7, 0.15, 0.85]

let SHAPES = {"square": "rect", "round": "rounded", "circle": "circle", "doublecircle": "dbl-circ",
  "diamond": "diam", "hexagon": "hex", "stadium": "stadium", "subroutine": "fr-rect",
  "cylinder": "cyl", "rect_left_inv_arrow": "odd", "lean_right": "lean-r", "lean_left": "lean-l",
  "trapezoid": "trap-b", "inv_trapezoid": "trap-t"}.toTable

const
  # Shapes that keep their own size in a larger cell, where the others stretch to fill it.
  FIXED = ["circle", "dbl-circ", "diam"]
  # Shapes that only widen, because their slants and curves are set by their height.
  WIDE = ["stadium", "hex", "odd", "lean-r", "lean-l", "trap-b", "trap-t"]

type
  Kind = enum kLeaf, kArrow, kComposite, kSpace

  View = ref object of Cell
    blk: Block
    kind: Kind
    index: int
    shape: string
    label: Label
    style: ResolvedStyle
    mask: int
    dx, dy: float
    bw, bh: float   ## Size as drawn, which for a fixed shape is smaller than its cell.

  Box = object
    x, y, bw, bh: float
    view: View      ## nil for a title

  Route = object
    edge: Block
    points: seq[float]   ## Two points for a straight line, three for a bend, none for a self-loop.
    loop: int
    label: Label
    lx, ly: float

func jsSign(x: float): float =
  if x > 0: 1.0 elif x < 0: -1.0 else: x

func orOne(x: float): float =
  if x == 0 or x.isNaN: 1.0 else: x

proc isRound(v: View): bool = v.kind == kLeaf and (v.shape == "circle" or v.shape == "dbl-circ")

proc edgeY(v: View, x, sign: float): float =
  ## Where a vertical line at x meets the outline, below the center (sign 1) or above it (sign -1).
  let hw = v.bw / 2
  let hh = v.bh / 2
  let dx = abs(x - v.x)
  var reach = hh
  if isRound(v): reach = jsmath.sqrt(max(hw * hw - dx * dx, 0))
  elif v.kind == kLeaf and v.shape == "diam": reach = hh * max(1 - dx / hw, 0)
  elif v.kind == kLeaf: reach = hh - shapeInset(v.shape, v.bw, v.bh, if sign > 0: 2 else: 0)
  elif v.kind == kArrow and arrowAxis(v.mask) == "x": reach = hh - OVERHANG
  v.y + sign * reach

proc edgeX(v: View, y, sign: float): float =
  ## Where a horizontal line at y meets the outline, right of the center (sign 1) or left of it.
  let hw = v.bw / 2
  let hh = v.bh / 2
  let dy = abs(y - v.y)
  var reach = hw
  if isRound(v): reach = jsmath.sqrt(max(hh * hh - dy * dy, 0))
  elif v.kind == kLeaf and v.shape == "diam": reach = hw * max(1 - dy / hh, 0)
  elif v.kind == kLeaf: reach = hw - shapeInset(v.shape, v.bw, v.bh, if sign > 0: 1 else: 3)
  elif v.kind == kArrow and arrowAxis(v.mask) == "y": reach = hw - OVERHANG
  v.x + sign * reach

proc border(v: View, tx, ty: float, output: var seq[float]) =
  ## Where the line from the center toward (tx, ty) leaves the outline.
  let dx = tx - v.x
  let dy = ty - v.y
  let hw = v.bw / 2
  let hh = v.bh / 2
  var k: float
  if isRound(v): k = hw / orOne(hypot(dx, dy))
  elif v.kind == kLeaf and v.shape == "diam": k = 1 / orOne(abs(dx) / hw + abs(dy) / hh)
  else: k = min((if dx == 0: Inf else: hw / abs(dx)), (if dy == 0: Inf else: hh / abs(dy)))
  if k == Inf: k = 0
  output.add [v.x + dx * k, v.y + dy * k]

proc crossesBox(x1, y1, x2, y2: float, v: View): bool =
  let l = v.x - v.bw / 2 + 1
  let r = v.x + v.bw / 2 - 1
  let t = v.y - v.bh / 2 + 1
  let b = v.y + v.bh / 2 - 1
  if (x1 < l and x2 < l) or (x1 > r and x2 > r) or (y1 < t and y2 < t) or (y1 > b and y2 > b): return false
  if x1 == x2 or y1 == y2: return true
  # The segment is diagonal and its bounding box overlaps: the box is hit unless all four corners
  # are on one side.
  let dx = x2 - x1
  let dy = y2 - y1
  proc side(x, y: float): float = jsSign(dx * (y - y1) - dy * (x - x1))
  let first = side(l, t)
  first == 0 or side(r, t) != first or side(r, b) != first or side(l, b) != first

proc hits(points: seq[float], s, t: View, obstacles: seq[View]): int =
  for v in obstacles:
    if v == s or v == t: continue
    var i = 0
    while i + 3 < points.len:
      if crossesBox(points[i], points[i + 1], points[i + 2], points[i + 3], v):
        inc result
        break
      i += 2

proc routeEdge(s, t: View, shift: float, obstacles: seq[View], check: bool): seq[float] =
  ## A straight line where the two blocks share a row or a column, otherwise one bend between
  ## facing sides.
  let sl = s.x - s.bw / 2
  let sr = s.x + s.bw / 2
  let st = s.y - s.bh / 2
  let sb = s.y + s.bh / 2
  let tl = t.x - t.bw / 2
  let tr = t.x + t.bw / 2
  let tt = t.y - t.bh / 2
  let tb = t.y + t.bh / 2
  let x1 = max(sl, tl)
  let x2 = min(sr, tr)
  let y1 = max(st, tt)
  let y2 = min(sb, tb)
  let overX = x2 - x1 > 6
  let overY = y2 - y1 > 6

  if overX and overY:
    # One block is inside the other: join the inner one to the nearest side of the outer one.
    let inner = if s.bw * s.bh <= t.bw * t.bh: s else: t
    let outer = if inner == s: t else: s
    let up = inner.y - inner.bh / 2 - (outer.y - outer.bh / 2)
    let down = outer.y + outer.bh / 2 - (inner.y + inner.bh / 2)
    let left = inner.x - inner.bw / 2 - (outer.x - outer.bw / 2)
    let right = outer.x + outer.bw / 2 - (inner.x + inner.bw / 2)
    let least = min(min(up, down), min(left, right))
    var points: seq[float]
    if least == down: points = @[inner.x, edgeY(inner, inner.x, 1), inner.x, outer.y + outer.bh / 2]
    elif least == up: points = @[inner.x, edgeY(inner, inner.x, -1), inner.x, outer.y - outer.bh / 2]
    elif least == right: points = @[edgeX(inner, inner.y, 1), inner.y, outer.x + outer.bw / 2, inner.y]
    else: points = @[edgeX(inner, inner.y, -1), inner.y, outer.x - outer.bw / 2, inner.y]
    return if inner == s: points else: @[points[2], points[3], points[0], points[1]]
  if overX:
    let margin = min(6.0, (x2 - x1) / 2)
    let x = min(max((x1 + x2) / 2 + shift, x1 + margin), x2 - margin)
    let down = if t.y > s.y: 1.0 else: -1.0
    return @[x, edgeY(s, x, down), x, edgeY(t, x, -down)]
  if overY:
    let margin = min(6.0, (y2 - y1) / 2)
    let y = min(max((y1 + y2) / 2 + shift, y1 + margin), y2 - margin)
    let right = if t.x > s.x: 1.0 else: -1.0
    return @[edgeX(s, y, right), y, edgeX(t, y, -right), y]

  let right = if t.x > s.x: 1.0 else: -1.0
  let down = if t.y > s.y: 1.0 else: -1.0
  let across = @[edgeX(s, s.y, right), s.y, t.x, s.y, t.x, edgeY(t, t.x, -down)]
  let along = @[s.x, edgeY(s, s.x, down), s.x, t.y, edgeX(t, t.y, -right), t.y]
  let wide = abs(t.x - s.x) >= abs(t.y - s.y)
  var best = if wide: across else: along
  if not check: return best
  var least = hits(best, s, t, obstacles)
  if least == 0: return best
  let other = if wide: along else: across
  let count = hits(other, s, t, obstacles)
  if count < least:
    best = other
    least = count
  if least == 0: return best
  var direct: seq[float]
  border(s, t.x, t.y, direct)
  border(t, s.x, s.y, direct)
  if hits(direct, s, t, obstacles) < least: direct else: best

proc trace(p: seq[float], startTrim0, endTrim0: float): EdgePath =
  ## Builds the path through two or three points, rounding the bend and leaving room for markers.
  var startTrim = startTrim0
  var endTrim = endTrim0
  let n = p.len
  let sx = p[0]
  let sy = p[1]
  let ex = p[n - 2]
  let ey = p[n - 1]
  var ax = p[2] - sx
  var ay = p[3] - sy
  let first = hypot(ax, ay)
  ax /= orOne(first)
  ay /= orOne(first)
  var bx = ex - p[n - 4]
  var by = ey - p[n - 3]
  let last = hypot(bx, by)
  bx /= orOne(last)
  by /= orOne(last)
  if n == 4 and startTrim + endTrim > first:
    let scale = first / (startTrim + endTrim)
    startTrim *= scale
    endTrim *= scale
  startTrim = min(startTrim, first)
  endTrim = min(endTrim, last)
  var d = "M" & num(sx + ax * startTrim) & "," & num(sy + ay * startTrim)
  if n == 6:
    let r = max(0.0, min(CORNER, min(first - startTrim, last - endTrim)))
    d.add "L" & num(p[2] - ax * r) & "," & num(p[3] - ay * r) & "Q" & num(p[2]) & "," & num(p[3]) &
      " " & num(p[2] + bx * r) & "," & num(p[3] + by * r)
  d.add "L" & num(ex - bx * endTrim) & "," & num(ey - by * endTrim)
  EdgePath(d: d, sx: sx, sy: sy, sdx: -ax, sdy: -ay, ex: ex, ey: ey, edx: bx, edy: by)

proc loopArc(v: View, k: int): (float, float, float, float, float) =
  ## A self-loop is an arc around the top right corner of the block, or around the matching point
  ## on a round or diamond outline: its center, radius, and the angles where it leaves and returns.
  let hw = v.bw / 2
  let hh = v.bh / 2
  let r = max(1.0, min(10 + 5 * float(k - 1), min(hw, hh)))
  if isRound(v):
    let px = v.x + hw * SQRT1_2
    let py = v.y - hw * SQRT1_2
    let half = 2 * asin(min(1.0, r / (2 * hw)))
    proc angle(at: float): float = atan2(v.y - hw * sin(at) - py, v.x + hw * cos(at) - px)
    return (px, py, r, angle(PI / 4 + half), angle(PI / 4 - half))
  if v.kind == kLeaf and v.shape == "diam":
    let slope = atan2(hh, hw)
    return (v.x + hw / 2, v.y - hh / 2, r, slope + PI, slope)
  (v.x + hw, v.y - hh, r, PI, PI / 2)

proc loopPath(v: View, k: int, startTrim, endTrim: float): EdgePath =
  let (px, py, r, a1, a2) = loopArc(v, k)
  let start = a1 + startTrim / r
  let stop = a2 - endTrim / r
  var sweep = (stop - start) mod (2 * PI)
  if sweep <= 0: sweep += 2 * PI
  let x1 = px + r * cos(start)
  let y1 = py + r * sin(start)
  let x2 = px + r * cos(stop)
  let y2 = py + r * sin(stop)
  let sx = px + r * cos(a1)
  let sy = py + r * sin(a1)
  let ex = px + r * cos(a2)
  let ey = py + r * sin(a2)
  # Each marker lies along the chord it covers, so it follows the curve instead of the tangent at its tip.
  let sl = hypot(sx - x1, sy - y1)
  let el = hypot(ex - x2, ey - y2)
  EdgePath(
    d: "M" & num(x1) & "," & num(y1) & "A" & num(r) & "," & num(r) & " 0 " &
      (if sweep > PI: "1" else: "0") & " 1 " & num(x2) & "," & num(y2),
    sx: sx, sy: sy,
    sdx: (if sl > 0: (sx - x1) / sl else: sin(a1)),
    sdy: (if sl > 0: (sy - y1) / sl else: -cos(a1)),
    ex: ex, ey: ey,
    edx: (if el > 0: (ex - x2) / el else: -sin(a2)),
    edy: (if el > 0: (ey - y2) / el else: cos(a2)))

proc covers(x, y, w, h: float, s, t: View, obstacles: seq[Box], check: bool): bool =
  if not check: return false
  for v in obstacles:
    if (v.view == nil or (v.view != s and v.view != t)) and abs(x - v.x) < (w + v.bw) / 2 and
        abs(y - v.y) < (h + v.bh) / 2:
      return true
  false

proc boxOf(v: View): Box = Box(x: v.x, y: v.y, bw: v.bw, bh: v.bh, view: v)

proc labelSpot(p: seq[float], at: int, w, h: float, s, t: View, obstacles: seq[View], check: bool): float =
  ## The point on a leg where a label of the given size covers no block other than the two it joins.
  if not check: return 0.5
  var boxes: seq[Box]
  for v in obstacles: boxes.add boxOf(v)
  for spot in SPOTS:
    let x = p[at] + (p[at + 2] - p[at]) * spot
    let y = p[at + 1] + (p[at + 3] - p[at + 1]) * spot
    if not covers(x, y, w, h, s, t, boxes, true): return spot
  0.5

proc stackLabels(stack: seq[int], routes: var seq[Route], legs: Table[int, seq[float]], s, t: View,
                 obstacles: seq[Box], check: bool): float =
  ## Stacks overlapping labels along their shared line, if they fit between its markers and cover
  ## no other block or title. Returns the extra length needed to fit the labels.
  let vertical = legs[stack[0]][0] == legs[stack[0]][2]
  var lo = -Inf
  var hi = Inf
  var need = -LABEL_GAP
  var crowded = false
  for a in 0 ..< stack.len:
    let leg = legs[stack[a]]
    if (if vertical: leg[0] != leg[2] else: leg[1] != leg[3]): return 0
    lo = max(lo, if vertical: min(leg[1], leg[3]) else: min(leg[0], leg[2]))
    hi = min(hi, if vertical: max(leg[1], leg[3]) else: max(leg[0], leg[2]))
    let p = routes[stack[a]]
    need += (if vertical: p.label.height else: p.label.width + 8) + LABEL_GAP
    for b in 0 ..< a:
      let q = routes[stack[b]]
      if abs(p.lx - q.lx) < (p.label.width + q.label.width) / 2 + 8 and
          abs(p.ly - q.ly) < (p.label.height + q.label.height) / 2:
        crowded = true
  if not crowded: return 0
  if need > hi - lo - 2 * ARROW: return need - (hi - lo - 2 * ARROW)
  var along: seq[float]
  var next = (lo + hi - need) / 2
  for i in stack:
    let label = routes[i].label
    let lx = routes[i].lx
    let ly = routes[i].ly
    let size = if vertical: label.height else: label.width + 8
    let at = next + size / 2
    if covers((if vertical: lx else: at), (if vertical: at else: ly), label.width + 8, label.height,
              s, t, obstacles, check): return 0
    along.add at
    next += size + LABEL_GAP
  for k, i in stack:
    if vertical: routes[i].ly = along[k]
    else: routes[i].lx = along[k]
  0

proc widen(parents: seq[View], s, t: View, vertical: bool, short: float,
           base: var Table[(int, bool), seq[float]]): bool =
  ## Widens the gap in the blocks' nearest shared container. `base` keeps the gaps as they were
  ## when the labels were measured.
  var chain = initHashSet[int]()
  var v = s
  while v != nil:
    chain.incl v.index
    v = parents[v.index]
  var tb: View = nil
  var box: View = t
  while box != nil and box.index notin chain:
    tb = box
    box = parents[box.index]
  if box == nil or tb == nil or box == s: return false
  var sb = s
  while parents[sb.index] != box: sb = parents[sb.index]
  var at: int
  if vertical:
    if sb.row == tb.row: return false
    at = max(sb.row, tb.row) - 1
  else:
    let (l, r) = if sb.col < tb.col: (sb, tb) else: (tb, sb)
    if float(r.col) < float(l.col) + l.span: return false
    at = r.col - 1
  let key = (box.index, vertical)
  if key notin base: base[key] = (if vertical: box.rowGaps else: box.colGaps)
  let was = gapAt(base[key], at)
  if vertical: box.rowGaps.setGap(at, max(gapAt(box.rowGaps, at), was + short))
  else: box.colGaps.setGap(at, max(gapAt(box.colGaps, at), was + short))
  true

proc draw(model: BlockDb, config: Config, options: RenderOptions, tight: bool): Rendered

proc renderBlock*(model: BlockDb, config: Config, options: RenderOptions): Rendered =
  tighten(options, proc (tight: bool): Rendered = draw(model, config, options, tight))

proc draw(model: BlockDb, config: Config, options: RenderOptions, tight: bool): Rendered =
  let size = options.fontSize.get(16)
  let edgeSize = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  let section = config["block"]
  let configured = if section != nil and isRecord(section): section["padding"] else: nil
  let gap = min((if configured != nil and configured.kind == yNumber and configured.n >= 0:
                   min(configured.n, 200.0) else: GAP),
                (if tight: 6.0 else: Inf))
  let wrap = if tight: 80.0 else: WRAP

  proc styleOf(b: Block): ResolvedStyle =
    var declarations: seq[string]
    # A style list is split on commas only, so one entry can still hold several declarations.
    proc add(styles: seq[string]) =
      for style in styles:
        for part in style.split(';'): declarations.add part
    for name in (if b.classes.len > 0: b.classes else: @["default"]):
      if name in model.classes: add(model.classes[name].styles)
    add(b.styles)
    resolveStyle(declarations)

  proc view(b: Block, index: int): View =
    let typ = b.typ
    let style = if typ == "space": resolveStyle(@[]) else: styleOf(b)
    let textStyle = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let fontSize = if style.fontSize > 0: style.fontSize else: size
    var kind = kLeaf
    var shape = ""
    var label: Label
    var nw, nh, head, dx, dy = 0.0
    var mask = 0
    if typ == "space":
      kind = kSpace
      label = layoutLabel("", false, measurer, fontSize, wrap)
    elif typ == "composite":
      kind = kComposite
      label = layoutLabel(b.label, false, measurer, fontSize,
                          (if tight: titleRoom(options) else: 4000.0), textStyle)
      head = if label.height > 0: label.height + 4 else: 0.0
      nw = label.width + 2 * gap
      nh = head + 2 * gap
    elif typ == "block_arrow":
      kind = kArrow
      label = layoutLabel(b.label, false, measurer, fontSize, wrap, textStyle)
      var blank = true
      for line in label.lines:
        for part in line:
          if part.hasIcon or jsTrim(part.text) != "": blank = false
      mask = arrowMask(b.directions)
      let s = if blank: arrowSize(mask, 0, 0) else: arrowSize(mask, label.width, label.height)
      nw = s.w
      nh = s.h
      dx = s.dx
      dy = s.dy
    else:
      shape = SHAPES.getOrDefault(typ, "rect")
      label = layoutLabel(b.label, false, measurer, fontSize, wrap, textStyle)
      let s = shapeSize(shape, label.width, label.height)
      nw = s.w
      # A cylinder's caps deepen as it widens, so it is sized for the deepest ones.
      nh = if shape == "cyl": max(s.h, label.height + 40) else: s.h
      dy = s.dy
    View(
      columns: (if kind == kComposite: b.columns else: -1.0),
      span: (if kind == kSpace: 1.0 elif b.widthInColumns.isNaN: 1.0 else: b.widthInColumns),
      space: kind == kSpace, head: head, nw: nw, nh: nh,
      blk: b, kind: kind, index: index, shape: shape, label: label, style: style,
      mask: mask, dx: dx, dy: dy)

  let root = view(model.root, 0)
  root.nw = 0
  root.nh = 0
  var order = @[root]
  var parents: seq[View] = @[nil]
  var byId = initTable[string, View]()
  var i = 0
  while i < order.len:
    let parent = order[i]
    inc i
    if parent.kind != kComposite: continue
    for child in parent.blk.children:
      let v = view(child, order.len)
      parent.children.add v
      parents.add parent
      order.add v
      if v.kind != kSpace: byId[child.id] = v

  var obstacles: seq[View]
  var titles: seq[Box]
  # Layout keeps the widest a container has been, so each run starts from the widths it needs.
  var widths: seq[float]
  for v in order: widths.add v.nw
  proc place(): (float, float) =
    for v in order: v.nw = widths[v.index]
    result = layout(root, gap)
    obstacles.setLen 0
    titles.setLen 0
    for v in order:
      if v.kind == kLeaf and v.shape in FIXED:
        v.bw = v.nw
        v.bh = v.nh
      elif v.kind == kArrow:
        v.bw = if v.span > 1: v.w else: v.nw
        v.bh = v.nh
      else:
        v.bw = v.w
        v.bh = if v.kind == kLeaf and v.shape in WIDE: v.nh else: v.h
      if v.kind == kLeaf and v.shape == "cyl": v.dy = min(12.0, max(6.0, v.bw / 14)) / 2
      if v.kind == kLeaf or v.kind == kArrow: obstacles.add v
      elif v.head > 0:
        titles.add Box(x: v.x, y: v.y - v.h / 2 + (v.head + gap) / 2 + 2, bw: v.label.width,
                       bh: v.label.height)
  var content = place()

  # Edges between the same two blocks are spread apart instead of drawn on top of each other.
  var pairs = initTable[int, int]()
  var labelled = initHashSet[int]()
  var ends: seq[(View, View)]
  var drawn: seq[Block]
  for edge in model.edges:
    let s = byId.getOrDefault(edge.start)
    let t = byId.getOrDefault(edge.stop)
    if s == nil or t == nil: continue
    let key = min(s.index, t.index) * order.len + max(s.index, t.index)
    pairs[key] = pairs.getOrDefault(key) + 1
    if edge.label != "": labelled.incl key
    ends.add (s, t)
    drawn.add edge
  let check = drawn.len * obstacles.len <= OBSTACLE_BUDGET
  var routes: seq[Route]
  var stacks = initOrderedTable[int, seq[int]]()
  var legs = initTable[int, seq[float]]()
  proc route() =
    var seen = initTable[int, int]()
    routes.setLen 0
    stacks.clear()
    for i in 0 ..< drawn.len:
      let (s, t) = ends[i]
      let key = min(s.index, t.index) * order.len + max(s.index, t.index)
      let total = pairs.getOrDefault(key, 1)
      let k = seen.getOrDefault(key)
      seen[key] = k + 1
      let label = layoutLabel(drawn[i].label, false, measurer, edgeSize, WRAP)
      var points: seq[float]
      var lx, ly: float
      if s == t:
        let (px, py, r, _, _) = loopArc(s, k + 1)
        lx = px + r + 6 + label.width / 2
        ly = py - r / 2
      else:
        let step = if key in labelled: jsRound(edgeSize * 1.5) + 2 else: 14.0
        points = routeEdge(s, t, (float(k) - float(total - 1) / 2) * step, obstacles, check)
        let n = points.len
        # The label goes on the longer leg.
        let firstLeg = abs(points[2] - points[0]) + abs(points[3] - points[1])
        let lastLeg = abs(points[n - 2] - points[n - 4]) + abs(points[n - 1] - points[n - 3])
        let at = if n == 6 and lastLeg > firstLeg: 2 else: 0
        let spot = if label.width > 0: labelSpot(points, at, label.width + 8, label.height, s, t,
                                                 obstacles, check)
                   else: 0.5
        lx = points[at] + (points[at + 2] - points[at]) * spot
        ly = points[at + 1] + (points[at + 3] - points[at + 1]) * spot
        if label.width > 0 and total > 1:
          legs[i] = points[at ..< at + 4]
          stacks.mgetOrPut(key, @[]).add i
      routes.add Route(edge: drawn[i], points: points, loop: (if s == t: k + 1 else: 0),
                       label: label, lx: lx, ly: ly)

  proc settle(grow: bool): bool =
    route()
    var blocked: seq[Box]
    if check:
      for v in obstacles: blocked.add boxOf(v)
      blocked.add titles
    var base = initTable[(int, bool), seq[float]]()
    for stack in stacks.values:
      if stack.len < 2: continue
      let (s, t) = ends[stack[0]]
      let short = stackLabels(stack, routes, legs, s, t, blocked, check)
      let vertical = legs[stack[0]][0] == legs[stack[0]][2]
      # Keep columns narrow to fit the host in tight layouts.
      if grow and short > 0 and (vertical or not tight) and
          widen(parents, s, t, vertical, ceil(short), base):
        result = true

  proc overlap(): float =
    for i in 0 ..< routes.len:
      let p = routes[i]
      for j in i + 1 ..< routes.len:
        let q = routes[j]
        let pw = (p.label.width + 8) / 2
        let qw = (q.label.width + 8) / 2
        let w = min(p.lx + pw, q.lx + qw) - max(p.lx - pw, q.lx - qw)
        let h = min(p.ly + p.label.height / 2, q.ly + q.label.height / 2) -
                max(p.ly - p.label.height / 2, q.ly - q.label.height / 2)
        if p.label.width > 0 and q.label.width > 0 and w > 0 and h > 0: result += w * h

  var minX, minY, maxX, maxY = 0.0
  proc grow(x, y, w, h: float) =
    if x - w / 2 < minX: minX = x - w / 2
    if x + w / 2 > maxX: maxX = x + w / 2
    if y - h / 2 < minY: minY = y - h / 2
    if y + h / 2 > maxY: maxY = y + h / 2
  proc bound(): float =
    ## Finds the drawing's extent and gives its width.
    minX = 0
    minY = 0
    maxX = content[0]
    maxY = content[1]
    for i in 0 ..< routes.len:
      let r = routes[i]
      if r.loop > 0:
        let (px, py, rr, _, _) = loopArc(ends[i][0], r.loop)
        grow(px, py, 2 * rr + 2, 2 * rr + 2)
      if r.label.width > 0: grow(r.lx, r.ly, r.label.width + 8, r.label.height)
    maxX - minX

  if settle(drawn.len * drawn.len <= OBSTACLE_BUDGET):
    let before = overlap()
    let narrow = bound()
    # A container stretched by its row gives some of a new gap back, so the gap may take a few rounds.
    var grown = true
    var round = 0
    while round < 3 and grown:
      content = place()
      grown = settle(round < 2)
      inc round
    # The drawing only grows if that leaves less of the labels covering each other, and within maxWidth.
    let wide = bound()
    let room = if options.maxWidth.isSome and options.maxWidth.get > 0: options.maxWidth.get else: Inf
    if overlap() > before - 1 or (wide > narrow and ceil(wide + 2 * pad) > room):
      for v in order:
        v.rowGaps = @[]
        v.colGaps = @[]
      content = place()
      discard settle(false)

  discard bound()

  let title = titleLabel(model.title, measurer, size, if tight: titleRoom(options) else: 4000.0)
  let titleHeight = if title.height > 0: title.height + 12 else: 0.0
  let inner = max(maxX - minX, title.width)
  let ox = pad - minX + (inner - (maxX - minX)) / 2
  let oy = pad + titleHeight - minY
  for v in order:
    v.x += ox
    v.y += oy
  let width = ceil(inner + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)

  var clusters = ""
  var nodes = ""
  var fills: seq[Fill]
  for i in 1 ..< order.len:
    let v = order[i]
    if v.kind == kSpace: continue
    let classes = classNames(v.blk.classes.join(" "))
    let id = escText(v.blk.id)
    if v.kind == kComposite:
      let top = v.y - v.h / 2
      if paints(v.style.shape):
        fills.add Fill(box: [v.x - v.w / 2, top, v.x + v.w / 2, top + v.h], shape: v.style.shape)
      clusters.add "<g class=\"pele-cluster" & classes & "\" data-id=\"" & id & "\">" &
        "<rect x=\"" & num(v.x - v.w / 2) & "\" y=\"" & num(top) & "\" width=\"" & num(v.w) &
        "\" height=\"" & num(v.h) & "\" fill=\"var(--_a)\"" &
        (if setsFill(v.style.shape): "" else: " fill-opacity=\"0.5\"") & " stroke=\"var(--_b)\"" &
        rounded(v.style.shape) & "/>" &
        labelSvg(v.label, v.x, top + (v.head + gap) / 2 + 2,
                 " class=\"pele-cluster-label\"" & inkFill(v.style.shape, v.style.text, "var(--_m)") &
                   v.style.text, icons) &
        "</g>"
      continue
    let arrow = v.kind == kArrow
    var label = v.label
    # Reuse a wider cell without changing the node size or the routes computed from it.
    if v.span > 1 and v.label.width > 0 and v.label.lines.len > 1 and v.bw > v.nw and
        (arrow or v.shape notin FIXED):
      let textStyle = (if v.style.bold: Bold else: 0) or (if v.style.italic: Italic else: 0)
      let room = v.label.width + (v.bw - v.nw)
      label = layoutLabel(v.blk.label, false, measurer, v.label.size, room, textStyle)
    nodes.add "<g class=\"pele-node pele-shape-" & (if arrow: "block-arrow" else: v.shape) & classes &
      "\" data-id=\"" & id & "\" transform=\"translate(" & num(v.x) & "," & num(v.y) & ")\">" &
      (if arrow: drawArrow(v.mask, v.bw, v.bh, SHAPE_ATTRS & v.style.shape)
       else: drawShape(v.shape, v.bw, v.bh, SHAPE_ATTRS & v.style.shape, LINE_ATTRS & v.style.line)) &
      labelSvg(label, v.dx, v.dy, " class=\"pele-label\"" &
        (if arrow or shapeFilled(v.shape): inkFill(v.style.shape, v.style.text) else: "") & v.style.text,
        icons) &
      "</g>"

  var casings = ""
  var edges = ""
  var labels = ""
  for i in 0 ..< routes.len:
    let edge = routes[i].edge
    let loop = routes[i].loop
    let label = routes[i].label
    let startType = edge.arrowTypeStart
    let endType = edge.arrowTypeEnd
    var path: EdgePath
    if loop > 0:
      path = loopPath(ends[i][0], loop, markerTrim(startType), markerTrim(endType))
    else:
      var k = 0
      while k < routes[i].points.len:
        routes[i].points[k] += ox
        routes[i].points[k + 1] += oy
        k += 2
      path = trace(routes[i].points, markerTrim(startType), markerTrim(endType))
    let over = overFills(path.d, [path.sx, path.sy, path.ex, path.ey], fills)
    let overInk = if over.none: "" else: over.ink
    if not over.none and over.ink == "":
      casings.add edgeCasing(path, startType, endType, "", edge.thickness == "thick")
    let id = escText(edge.id)
    let color = if overInk != "": overInk else: "var(--_l)"
    edges.add "<g class=\"pele-edge\" data-id=\"" & id & "\"" &
      (if overInk != "": " stroke=\"" & overInk & "\"" else: "") & ">" &
      "<path d=\"" & path.d & "\"" & (if edge.thickness == "thick": " stroke-width=\"2.5\"" else: "") &
      (if edge.pattern == "dotted": " stroke-dasharray=\"3 4\"" else: "") & "/>" &
      marker(startType, path.sx, path.sy, path.sdx, path.sdy, color) &
      marker(endType, path.ex, path.ey, path.edx, path.edy, color) &
      "</g>"
    if label.width > 0:
      labels.add edgeLabelSvg(edge.id, label, routes[i].lx + ox, routes[i].ly + oy, "", icons)

  let svg = svgDocument("block", width, height, size, options,
    Accessible(accTitle: model.accTitle, accDescr: model.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      casingsSvg(casings) &
      (if edges != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" &
         edges & "</g>" else: "") &
      "<g class=\"pele-nodes\">" & nodes & "</g>" &
      (if labels != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(edgeSize) & "\">" &
         labels & "</g>" else: ""))
  Rendered(svg: svg, width: width, height: height, links: @[])

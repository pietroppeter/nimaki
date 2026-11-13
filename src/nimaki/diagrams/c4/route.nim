## port-of: src/diagrams/c4/route.ts
## port-status: draft
##
## Boxes are compared by identity, as in Pele: `Lanes.taken` is keyed by the box's address.
import std/tables
from std/math import ceil, isNaN
import ../../svg/builder
import ../../jsmath

type
  Box* = ref object of RootObj
    ## A laid out shape or boundary: top-left corner, size, and the shared shape it is drawn as.
    x*, y*, w*, h*: float
    form*: string

  Route* = object
    d*: string
    ## Where the markers go: the tip, and the way it points.
    sx*, sy*, sdx*, sdy*, ex*, ey*, edx*, edy*: float
    ## The stretch the label may sit on.
    x0*, y0*, x1*, y1*: float
    ## The side of that stretch the label is pushed to, as a unit vector; zero centers it.
    nx*, ny*: float
    ## When set, the label stays over the line and moves that way by at most this much.
    lean*: float
    ## The widest the label should be.
    room*: float
    ## The corners of the line, as x, y pairs.
    points*: seq[float]

const
  LOOP = 28.0
  LANE* = 20.0
  LANE_STEP = 7.0
  CORNER = 8.0
  LEAN = 30.0
  NARROW* = 88.0
  WIDE = 160.0
  LABEL_PAD* = 8.0
  HEAD* = 26.0

func jsSign(x: float): float =
  ## Math.sign
  if x > 0: 1.0 elif x < 0: -1.0 else: x

func cylRy*(w: float): float = min(12.0, max(6.0, w / 14))
func queueRx*(h: float): float = min(12.0, h / 4)

func orOne(x: float): float =
  ## `x || 1`
  if x == 0 or x.isNaN: 1.0 else: x

func hitRect(x0, y0, x1, y1, px, py, dx, dy: float): float =
  ## How far along the segment from (px, py) by (dx, dy) it first meets the rectangle; Inf when it misses.
  var enter = 0.0
  var leave = 1.0
  if dx == 0:
    if px < x0 or px > x1: return Inf
  else:
    let a = (x0 - px) / dx
    let b = (x1 - px) / dx
    enter = max(enter, min(a, b))
    leave = min(leave, max(a, b))
  if dy == 0:
    if py < y0 or py > y1: return Inf
  else:
    let a = (y0 - py) / dy
    let b = (y1 - py) / dy
    enter = max(enter, min(a, b))
    leave = min(leave, max(a, b))
  if enter <= leave: enter else: Inf

func hitEllipse(cx, cy, rx, ry, px, py, dx, dy: float): float =
  let ux = dx / rx
  let uy = dy / ry
  let vx = (px - cx) / rx
  let vy = (py - cy) / ry
  let a = ux * ux + uy * uy
  let b = 2 * (ux * vx + uy * vy)
  let c = vx * vx + vy * vy - 1
  let disc = b * b - 4 * a * c
  if a == 0 or disc < 0: return Inf
  let t = (-b - jsmath.sqrt(disc)) / (2 * a)
  if t >= 0 and t <= 1: t elif c <= 0: 0.0 else: Inf

func hit(box: Box, px, py, qx, qy: float): float =
  ## Where a segment from outside first meets the outline of a shape, as a fraction of the segment.
  let x = box.x
  let y = box.y
  let w = box.w
  let h = box.h
  let dx = qx - px
  let dy = qy - py
  if box.form == "person":
    return min(hitRect(x, y + HEAD, x + w, y + h, px, py, dx, dy),
               hitEllipse(x + w / 2, y + 14, 13, 13, px, py, dx, dy))
  if box.form == "cyl":
    let ry = cylRy(w)
    return min(min(hitRect(x, y + ry, x + w, y + h - ry, px, py, dx, dy),
                   hitEllipse(x + w / 2, y + ry, w / 2, ry, px, py, dx, dy)),
               hitEllipse(x + w / 2, y + h - ry, w / 2, ry, px, py, dx, dy))
  if box.form == "h-cyl":
    let rx = queueRx(h)
    return min(min(hitRect(x + rx, y, x + w - rx, y + h, px, py, dx, dy),
                   hitEllipse(x + rx, y + h / 2, rx, h / 2, px, py, dx, dy)),
               hitEllipse(x + w - rx, y + h / 2, rx, h / 2, px, py, dx, dy))
  hitRect(x, y, x + w, y + h, px, py, dx, dy)

func crosses*(points: seq[float], x0, y0, x1, y1: float): bool =
  var i = 2
  while i < points.len:
    let px = points[i - 2]
    let py = points[i - 1]
    if hitRect(x0, y0, x1, y1, px, py, points[i] - px, points[i + 1] - py) <= 1: return true
    i += 2
  false

func contains(outer, inner: Box): bool =
  outer.x <= inner.x and outer.y <= inner.y and outer.x + outer.w >= inner.x + inner.w and
    outer.y + outer.h >= inner.y + inner.h

func connect(a, b: Box, shift: float): (float, float, float, float) =
  ## The straight line from a to b: x, y of its start, then of its end.
  let ax = a.x + a.w / 2
  let ay = a.y + a.h / 2
  let bx = b.x + b.w / 2
  let by = b.y + b.h / 2
  let down = contains(a, b)
  if down or contains(b, a):
    # One holds the other: a short line from the nearest side of the outer box.
    let outer = if down: a else: b
    let inner = if down: b else: a
    let ix = inner.x + inner.w / 2
    let iy = inner.y + inner.h / 2
    let left = inner.x - outer.x
    let right = outer.x + outer.w - inner.x - inner.w
    let top = inner.y - outer.y
    let bottom = outer.y + outer.h - inner.y - inner.h
    let least = min(min(left, right), min(top, bottom))
    let ox = if least == left: outer.x elif least == right: outer.x + outer.w else: ix
    let oy = if least == left or least == right: iy elif least == bottom: outer.y + outer.h else: outer.y
    let t = min(hit(inner, ox, oy, ix, iy), 1)
    let mx = ox + (ix - ox) * t
    let my = oy + (iy - oy) * t
    return if down: (ox, oy, mx, my) else: (mx, my, ox, oy)

  var px = ax
  var py = ay
  var qx = bx
  var qy = by
  # Shapes that share a column or a row are joined by an upright or level line through the shared span.
  let x0 = max(a.x, b.x)
  let x1 = min(a.x + a.w, b.x + b.w)
  let y0 = max(a.y, b.y)
  let y1 = min(a.y + a.h, b.y + b.h)
  if x0 < x1:
    px = (x0 + x1) / 2
    qx = px
  elif y0 < y1:
    py = (y0 + y1) / 2
    qy = py
  let len = orOne(hypot(qx - px, qy - py))
  let nx = (-(qy - py) / len) * shift
  let ny = ((qx - px) / len) * shift
  var ta = hit(a, qx + nx, qy + ny, px + nx, py + ny)
  var tb = hit(b, px + nx, py + ny, qx + nx, qy + ny)
  if ta <= 1 and tb <= 1:
    px += nx
    py += ny
    qx += nx
    qy += ny
  else:
    px = ax
    py = ay
    qx = bx
    qy = by
    ta = min(hit(a, qx, qy, px, py), 1)
    tb = min(hit(b, px, py, qx, qy), 1)
  (qx + (px - qx) * ta, qy + (py - qy) * ta, px + (qx - px) * tb, py + (qy - py) * tb)

const
  NEAR = 6.0
  FRAME_NEAR = 3.0
  PORT_STEP = 12.0

type Lanes* = ref object
  ## What the routes drawn so far take up: upright stretches as x, top, bottom; level ones as y,
  ## left, right; and where lines leave or reach each side of a shape.
  upright, level: seq[float]
  frames: array[2, seq[float]]
  taken: Table[pointer, seq[float]]
  squeezed*: int

func key(box: Box): pointer = cast[pointer](box)

proc free*(lanes: Lanes, upright: bool, at, a0, a1: float): bool =
  let lo = min(a0, a1)
  let hi = max(a0, a1)
  proc near(list: seq[float], gap: float): bool =
    var i = 0
    while i < list.len:
      if abs(list[i] - at) < gap and list[i + 1] < hi and list[i + 2] > lo: return true
      i += 3
    false
  not near(if upright: lanes.upright else: lanes.level, NEAR) and
    not near(lanes.frames[if upright: 0 else: 1], FRAME_NEAR)

proc crossings*(lanes: Lanes, points: seq[float]): int =
  var i = 2
  while i < points.len:
    let upright = points[i] == points[i - 2]
    let at = if upright: points[i] else: points[i + 1]
    let p = if upright: points[i - 1] else: points[i - 2]
    let q = if upright: points[i + 1] else: points[i]
    let lo = min(p, q)
    let hi = max(p, q)
    let list = if upright: lanes.level else: lanes.upright
    var j = 0
    while j < list.len:
      if list[j] > lo and list[j] < hi and list[j + 1] < at and list[j + 2] > at: inc result
      j += 3
    i += 2

proc frame*(lanes: Lanes, box: Box) =
  lanes.frames[0].add [box.x, box.y, box.y + box.h, box.x + box.w, box.y, box.y + box.h]
  lanes.frames[1].add [box.y, box.x, box.x + box.w, box.y + box.h, box.x, box.x + box.w]

proc take*(lanes: Lanes, points: seq[float]) =
  var i = 2
  while i < points.len:
    if points[i] == points[i - 2]:
      lanes.upright.add [points[i], min(points[i - 1], points[i + 1]), max(points[i - 1], points[i + 1])]
    elif points[i + 1] == points[i - 1]:
      lanes.level.add [points[i + 1], min(points[i - 2], points[i]), max(points[i - 2], points[i])]
    i += 2

proc ports*(lanes: Lanes, box: Box, side: int, want, lo, hi: float): seq[float] =
  ## Where on one side of a shape (0 left, 1 right, 2 top, 3 bottom) a line can leave or arrive,
  ## between lo and hi: the places clear of the lines already there, nearest `want` first.
  let used = lanes.taken.getOrDefault(key(box))
  var k = 0
  while k < 9 and result.len < 4:
    let at = want + (if (k and 1) != 0: 1.0 else: -1.0) * ceil(k / 2) * PORT_STEP
    if not (at < lo or at > hi):
      var clear = true
      var i = 0
      while i < used.len:
        if used[i] == float(side) and abs(used[i + 1] - at) < PORT_STEP: clear = false
        i += 2
      if clear: result.add at
    inc k
  if result.len == 0: result = @[want]

proc claim*(lanes: Lanes, box: Box, side: int, at: float) =
  lanes.taken.mgetOrPut(key(box), @[]).add [float(side), at]

func path(points: seq[float], startTrim, endTrim: float): string =
  let n = points.len
  let ux = jsSign(points[2] - points[0])
  let uy = jsSign(points[3] - points[1])
  var d = "M" & num(points[0] + ux * startTrim) & "," & num(points[1] + uy * startTrim)
  var i = 2
  while i < n - 2:
    let x = points[i]
    let y = points[i + 1]
    let ix = jsSign(x - points[i - 2])
    let iy = jsSign(y - points[i - 1])
    let ox = jsSign(points[i + 2] - x)
    let oy = jsSign(points[i + 3] - y)
    let r = min(CORNER, min(abs(x - points[i - 2] + y - points[i - 1]) / 2,
                            abs(points[i + 2] - x + points[i + 3] - y) / 2))
    d.add (if ix != 0 and not ix.isNaN: "H" & num(x - ix * r) else: "V" & num(y - iy * r))
    d.add "Q" & num(x) & "," & num(y) & " " & num(x + ox * r) & "," & num(y + oy * r)
    i += 2
  let lx = jsSign(points[n - 2] - points[n - 4])
  let ly = jsSign(points[n - 1] - points[n - 3])
  d & (if lx != 0 and not lx.isNaN: "H" & num(points[n - 2] - lx * endTrim)
       else: "V" & num(points[n - 1] - ly * endTrim))

func clearOf(points: seq[float], others: seq[Box], a, b: Box): bool =
  for other in others:
    if other != a and other != b and crosses(points, other.x, other.y, other.x + other.w, other.y + other.h):
      return false
  true

func bent(points: seq[float], along: int, startTrim, endTrim: float, nx = 0.0, lean = 0.0,
          room = WIDE): Route =
  ## The route for a line with corners through `points`. `along` is the stretch its label sits on.
  let n = points.len
  Route(
    d: path(points, startTrim, endTrim),
    sx: points[0], sy: points[1],
    sdx: -jsSign(points[2] - points[0]), sdy: -jsSign(points[3] - points[1]),
    ex: points[n - 2], ey: points[n - 1],
    edx: jsSign(points[n - 2] - points[n - 4]), edy: jsSign(points[n - 1] - points[n - 3]),
    x0: points[along], y0: points[along + 1], x1: points[along + 2], y1: points[along + 3],
    nx: nx, ny: 0, lean: lean, room: room, points: points)

func across(lo, hi: float): seq[float] =
  let mid = (lo + hi) / 2
  let step = max(LANE_STEP, (hi - lo) / 4)
  for k in 0 ..< 9:
    let at = mid + (if (k and 1) != 0: 1.0 else: -1.0) * ceil(k / 2) * step
    if at >= lo + NEAR and at <= hi - NEAR: result.add at

type Best = object
  found: bool
  points: seq[float]
  cost: float
  upright: bool
  sides: (int, int)

proc elbow(a, b: Box, others: seq[Box], lanes: Lanes, startTrim, endTrim: float): (bool, Route) =
  let ax = a.x + a.w / 2
  let ay = a.y + a.h / 2
  let bx = b.x + b.w / 2
  let by = b.y + b.h / 2
  var best = Best()
  proc consider(points: seq[float], upright: bool, sides: (int, int)): bool =
    ## True when `points` became the best.
    if not clearOf(points, others, a, b): return false
    var i = 2
    while i < points.len:
      let up = points[i] == points[i - 2]
      if not lanes.free(up, (if up: points[i] else: points[i + 1]),
                        (if up: points[i - 1] else: points[i - 2]),
                        (if up: points[i + 1] else: points[i])): return false
      i += 2
    var cost = float(lanes.crossings(points)) * 1e6
    i = 2
    while i < points.len:
      cost += abs(points[i] - points[i - 2]) + abs(points[i + 1] - points[i - 1])
      i += 2
    if not best.found or cost < best.cost:
      best = Best(found: true, points: points, cost: cost, upright: upright, sides: sides)
      return true
    false
  if a.x + a.w <= b.x or b.x + b.w <= a.x:
    let right = bx > ax
    let down = jsSign(by - ay)
    let sides = if right: (1, 0) else: (0, 1)
    let lanesAcross = across((if right: a.x + a.w else: b.x + b.w), (if right: b.x else: a.x))
    block search:
      for y0 in lanes.ports(a, sides[0], ay + (down * a.h) / 4, a.y + 8, a.y + a.h - 8):
        for y1 in lanes.ports(b, sides[1], by - (down * b.h) / 4, b.y + 8, b.y + b.h - 8):
          for lane in lanesAcross:
            let x0 = lane + (ax - lane) * min(hit(a, lane, y0, ax, y0), 1)
            let x1 = lane + (bx - lane) * min(hit(b, lane, y1, bx, y1), 1)
            if consider(@[x0, y0, lane, y0, lane, y1, x1, y1], true, sides): break search
  if a.y + a.h <= b.y or b.y + b.h <= a.y:
    let below = by > ay
    let sideways = jsSign(bx - ax)
    let sides = if below: (3, 2) else: (2, 3)
    let lanesAcross = across((if below: a.y + a.h else: b.y + b.h), (if below: b.y else: a.y))
    block search:
      for x0 in lanes.ports(a, sides[0], ax + (sideways * a.w) / 4, a.x + 8, a.x + a.w - 8):
        for x1 in lanes.ports(b, sides[1], bx - (sideways * b.w) / 4, b.x + 8, b.x + b.w - 8):
          for lane in lanesAcross:
            let y0 = lane + (ay - lane) * min(hit(a, x0, lane, x0, ay), 1)
            let y1 = lane + (by - lane) * min(hit(b, x1, lane, x1, by), 1)
            if consider(@[x0, y0, x0, lane, x1, lane, x1, y1], false, sides): break search
  if not best.found: return (false, Route())
  let points = best.points
  lanes.take(points)
  lanes.claim(a, best.sides[0], if best.upright: points[1] else: points[0])
  lanes.claim(b, best.sides[1], if best.upright: points[7] else: points[6])
  # The label sits on the middle stretch, across the gap.
  (true, bent(points, 2, startTrim, endTrim, room = (if best.upright: NARROW else: WIDE)))

type Way = object
  points: seq[float]
  side: int
  p0, p1: float
  step: int

proc route*(a, b: Box, shift: float, others: seq[Box], careful: bool, lanes: Lanes,
            startTrim, endTrim: float): Route =
  ## Routes a relation from a to b. `shift` moves the line sideways when another runs the opposite
  ## way. `others` are the shapes to steer clear of when `careful`. `lanes` holds what the routes
  ## before it take up.
  if a == b:
    let spread = min(a.h / 2 - 4, 10)
    let len = hypot(LOOP, spread)
    let x = a.x + a.w
    let cy = a.y + a.h / 2
    let ux = LOOP / len
    let uy = spread / len
    return Route(
      d: "M" & num(x + ux * startTrim) & "," & num(cy - spread - uy * startTrim) & "C" &
        num(x + LOOP) & "," & num(cy - spread * 2) & " " & num(x + LOOP) & "," &
        num(cy + spread * 2) & " " & num(x + ux * endTrim) & "," & num(cy + spread + uy * endTrim),
      sx: x, sy: cy - spread, sdx: -ux, sdy: uy,
      ex: x, ey: cy + spread, edx: -ux, edy: -uy,
      x0: x + LOOP + 4, y0: cy, x1: x + LOOP + 4, y1: cy,
      nx: 1, ny: 0, lean: 0, room: 64, points: @[])

  let (sx, sy, ex, ey) = connect(a, b, shift)
  let upright = sx == ex
  var blocked = false
  if careful and not contains(a, b) and not contains(b, a):
    for other in others:
      if other != a and other != b and
          hitRect(other.x, other.y, other.x + other.w, other.y + other.h, sx, sy, ex - sx, ey - sy) <= 1:
        blocked = true
  if careful and blocked and not upright and sy != ey:
    let (ok, around) = elbow(a, b, others, lanes, startTrim, endTrim)
    if ok: return around
    inc lanes.squeezed
  if careful and blocked and (upright or sy == ey):
    proc laneOn(forward: bool): float =
      var lane = if forward: -Inf else: Inf
      proc widen(box: Box) =
        let edge = if upright: box.x else: box.y
        lane = if forward: max(lane, edge + (if upright: box.w else: box.h)) else: min(lane, edge)
      widen(a)
      widen(b)
      for other in others:
        if other != a and other != b and
            hitRect(other.x, other.y, other.x + other.w, other.y + other.h, sx, sy, ex - sx, ey - sy) <= 1:
          widen(other)
      lane
    let lo = if upright: min(a.y, b.y) else: min(a.x, b.x)
    let hi = if upright: max(a.y + a.h, b.y + b.h) else: max(a.x + a.w, b.x + b.w)
    proc outside(forward: bool, lane: float): bool =
      for other in others:
        if other == a or other == b: continue
        let near = if upright: other.y < hi and other.y + other.h > lo
                   else: other.x < hi and other.x + other.w > lo
        let start = if upright: other.x else: other.y
        let stop = start + (if upright: other.w else: other.h)
        if near and (if forward: stop > lane else: start < lane): return false
      true
    let ax = a.x + a.w / 2
    let ay = a.y + a.h / 2
    let bx = b.x + b.w / 2
    let by = b.y + b.h / 2
    let towards = if upright: jsSign(by - ay) else: jsSign(bx - ax)
    proc along(forward: bool): Way =
      let lane = laneOn(forward)
      let sign = if forward: 1.0 else: -1.0
      let side = if upright: (if forward: 1 else: 0) elif forward: 3 else: 2
      let p0 = if upright: lanes.ports(a, side, ay + (towards * a.h) / 4, a.y + 8, a.y + a.h - 8)[0]
               else: lanes.ports(a, side, ax + (towards * a.w) / 4, a.x + 8, a.x + a.w - 8)[0]
      let p1 = if upright: lanes.ports(b, side, by - (towards * b.h) / 4, b.y + 8, b.y + b.h - 8)[0]
               else: lanes.ports(b, side, bx - (towards * b.w) / 4, b.x + 8, b.x + b.w - 8)[0]
      proc pointsAt(at: float): seq[float] =
        if upright:
          let x0 = at + (ax - at) * min(hit(a, at, p0, ax, p0), 1)
          let x1 = at + (bx - at) * min(hit(b, at, p1, bx, p1), 1)
          return @[x0, p0, at, p0, at, p1, x1, p1]
        let y0 = at + (ay - at) * min(hit(a, p0, at, p0, ay), 1)
        let y1 = at + (by - at) * min(hit(b, p1, at, p1, by), 1)
        @[p0, y0, p0, at, p1, at, p1, y1]
      var points = pointsAt(lane + sign * LANE)
      for k in 0 .. 4:
        let at = lane + sign * (LANE + float(k) * LANE_STEP)
        let tried = pointsAt(at)
        if not clearOf(tried, others, a, b): continue
        points = tried
        if lanes.free(upright, at, p0, p1): return Way(points: points, side: side, p0: p0, p1: p1, step: k)
      Way(points: points, side: side, p0: p0, p1: p1, step: 5)
    # A detour takes the outside of the drawing when only one side is outside. Otherwise it takes
    # the side where it crosses fewer lines, then the one where it runs nearer its shapes.
    let natural = if upright: ey > sy else: ex < sx
    let isOut = outside(natural, laneOn(natural))
    let back = outside(not natural, laneOn(not natural))
    let first = along(natural)
    let hasOther = isOut == back
    let other = if hasOther: along(not natural) else: Way()
    proc cost(way: Way): int = lanes.crossings(way.points) * 8 + way.step
    let forward = if back and not isOut: not natural
                  elif hasOther and cost(other) < cost(first): not natural
                  else: natural
    let way = if forward == natural: first elif hasOther: other else: along(not natural)
    let sign = if forward: 1.0 else: -1.0
    if way.step > 4: inc lanes.squeezed
    lanes.take(way.points)
    lanes.claim(a, way.side, way.p0)
    lanes.claim(b, way.side, way.p1)
    return if upright: bent(way.points, 2, startTrim, endTrim, nx = sign, lean = LEAN, room = NARROW)
           else: bent(way.points, 2, startTrim, endTrim, room = WIDE)

  let len = orOne(hypot(ex - sx, ey - sy))
  let dx = (ex - sx) / len
  let dy = (ey - sy) / len
  if upright or sy == ey: lanes.take(@[sx, sy, ex, ey])
  Route(
    d: "M" & num(sx + dx * startTrim) & "," & num(sy + dy * startTrim) & "L" &
      num(ex - dx * endTrim) & "," & num(ey - dy * endTrim),
    sx: sx, sy: sy, sdx: -dx, sdy: -dy, ex: ex, ey: ey, edx: dx, edy: dy,
    x0: sx, y0: sy, x1: ex, y1: ey,
    nx: (if shift != 0: -dy else: 0), ny: (if shift != 0: dx else: 0),
    lean: 0, room: (if abs(dx) > abs(dy): NARROW else: WIDE), points: @[sx, sy, ex, ey])

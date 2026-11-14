## port-of: src/svg/edges.ts
## port-status: conformant
##
## Port notes: `EdgePath.tokens` is empty for undefined (a path always has at least its move).
## `fillUnder` answers a `FillAt`: none (undefined), across (''), or the fill. The regular
## expressions on style strings are scanners, each with its pattern in a comment.
import std/[strutils, tables]
from std/math import PI, floor, sgn, isNaN
import ../jsmath
import ../js
import ../layout/layered
import ../text/[label, icons]
import builder, ink

const ARROW* = 8.0

type EdgePath* = object
  d*: string
  tokens*: seq[float]
  sx*, sy*, sdx*, sdy*: float
  ex*, ey*, edx*, edy*: float

# Marker types are Mermaid's: arrow_point, arrow_circle, arrow_cross; anything else draws nothing.

const
  CORNER = 12.0
    ## The most a corner is rounded by in a stepped route.
  HANDLE = 0.62
    ## How far the handles of a wide turn reach along its two legs. A little more than a
    ## circle's, which makes the turn fuller.
  LEAD* = 6.0
    ## How far an edge runs straight before a marker at its end, where it has the room.

proc markerTrim*(kind: string): float =
  if kind == "arrow_point": ARROW - 1 elif kind == "arrow_circle": ARROW elif kind == "arrow_cross": 4 else: 0

type SideReach* = ref object
  ## How far from each side of each node the edges that meet it start to turn: as far as the
  ## largest marker there needs, for every edge on the side, so that none turns sooner than its
  ## neighbour and crosses it. `add` takes a node, the side of it, and the marker of an end there.
  reach: Table[int, float]

proc sideReach*(): SideReach = SideReach(reach: initTable[int, float]())

proc add*(r: SideReach, node, side: int, kind: string) =
  let trim = markerTrim(kind)
  if side >= 0 and trim > 0 and trim + LEAD > r.reach.getOrDefault(node * 4 + side, 0):
    r.reach[node * 4 + side] = trim + LEAD

proc reachOf*(r: SideReach, node, side: int): float =
  if side >= 0: r.reach.getOrDefault(node * 4 + side, 0) else: 0

func signOr1(x: float): float =
  ## Math.sign(x) || 1
  if x > 0: 1 elif x < 0: -1 else: 1

func jsSign(x: float): float =
  if x > 0: 1 elif x < 0: -1 elif isNaN(x): NaN else: x

func written(v: float): float =
  ## Match the value parsed from num() output.
  let n = jsRound(v * 100)
  if n == 0: 0 else: n / 100

proc routePath*(route: seq[float], curve: string, startTrim, endTrim: float,
                startReachIn = NaN, endReachIn = NaN): EdgePath =
  ## Builds the path for a route of x, y, axis triples, trimming both ends to leave room for
  ## markers. Between two points that are not in line, a route is one S that leaves and arrives
  ## along the flow, or a step in a stepped route. Where the route itself turns a corner, a
  ## stepped route rounds it a little, and any other but a linear one turns as widely as it can:
  ## the turn takes the whole of a leg that ends at a node and half of a leg it shares with the
  ## next turn. `startReach` and `endReach` say how far from its nodes the edge starts to turn,
  ## where the other edges on the same side of a node need it to; by default (NaN), far enough
  ## to clear its own marker.
  let startReach = if isNaN(startReachIn): (if startTrim > 0: startTrim + LEAD else: 0) else: startReachIn
  let endReach = if isNaN(endReachIn): (if endTrim > 0: endTrim + LEAD else: 0) else: endReachIn
  let linear = curve == "linear"
  let stepped = curve == "step" or curve == "stepBefore" or curve == "stepAfter"
  var xs, ys, axes: seq[float]
  template near(ax, ay, bx, by: float): bool = abs(ax - bx) < 0.01 and abs(ay - by) < 0.01
  var i = 0
  while i < route.len:
    let x = route[i]
    let y = route[i + 1]
    let axis = route[i + 2]
    let last = xs.len - 1
    # A stepped route turns at right angles where a smooth one would curve.
    if stepped and last >= 0 and abs(x - xs[last]) >= 0.01 and abs(y - ys[last]) >= 0.01:
      let px = xs[last]
      let py = ys[last]
      let my = if curve == "stepBefore": py elif curve == "stepAfter": y else: (py + y) / 2
      let mx = if curve == "stepBefore": px elif curve == "stepAfter": x else: (px + x) / 2
      let turns = if axis == 0: [px, my, x, my] else: [mx, py, mx, y]
      var k = 0
      while k < 4:
        if not (near(turns[k], turns[k + 1], px, py) or near(turns[k], turns[k + 1], x, y)):
          xs.add turns[k]
          ys.add turns[k + 1]
          axes.add axis
        k += 2
    xs.add x
    ys.add y
    axes.add axis
    i += 3
  var last = xs.len - 1
  template aligned(i: int): bool = abs(xs[i] - xs[i - 1]) < 0.01 or abs(ys[i] - ys[i - 1]) < 0.01
  template straight(i: int): bool = linear or aligned(i)
  # The way the route heads from point i to point j: along the flow where an S joins them.
  proc unit(i, j: int, axis: float): (float, float) =
    if not straight(max(i, j)):
      return if axis == 0: (0.0, signOr1(ys[j] - ys[i])) else: (signOr1(xs[j] - xs[i]), 0.0)
    let dx = xs[j] - xs[i]
    let dy = ys[j] - ys[i]
    var len = hypot(dx, dy)
    if len == 0 or isNaN(len): len = 1
    (dx / len, dy / len)
  let (sdx, sdy) = unit(0, 1, axes[1])
  let (edx, edy) = unit(last - 1, last, axes[last])
  let sx = xs[0]
  let sy = ys[0]
  let ex = xs[last]
  let ey = ys[last]
  xs[0] += sdx * startTrim
  ys[0] += sdy * startTrim
  xs[last] -= edx * endTrim
  ys[last] -= edy * endTrim
  template length(i: int): float = abs(xs[i] - xs[i - 1]) + abs(ys[i] - ys[i - 1])
  # Whether the route turns a corner at point i, from running one way to running the other.
  proc turns(i: int): bool =
    not linear and i > 0 and i < last and aligned(i) and aligned(i + 1) and length(i) >= 0.01 and
      length(i + 1) >= 0.01 and (abs(xs[i] - xs[i - 1]) < 0.01) != (abs(xs[i + 1] - xs[i]) < 0.01)
  # An edge that curves into a marker runs straight for a little way first, where it has the
  # room, so that the marker does not sit on the bend.
  template along(i: int, ux, uy: float): float =
    abs(xs[i] - xs[i - 1]) * abs(ux) + abs(ys[i] - ys[i - 1]) * abs(uy)
  # Of the way from the end of a run to where it turns, the part that makes up for a larger
  # marker beside this one is kept where it can be, and the rest is at most a quarter of what
  # is left, so that ends on one side of a node turn equally far from it.
  proc lead(reach, trim, run: float): float =
    let room = min(max(0.0, reach - LEAD - trim), run / 4)
    room + min(reach - trim - room, (run - room) / 4)
  let arrives = if endReach > endTrim and (not straight(last) or turns(last - 1)):
                  lead(endReach, endTrim, along(last, edx, edy)) else: 0
  let leaves = if startReach > startTrim and (not straight(1) or turns(1)):
                 lead(startReach, startTrim, along(1, sdx, sdy)) else: 0
  if arrives >= 1:
    xs.insert(xs[last] - edx * arrives, last)
    ys.insert(ys[last] - edy * arrives, last)
    axes.insert(axes[last], last)
    inc last
  if leaves >= 1:
    xs.insert(xs[0] + sdx * leaves, 1)
    ys.insert(ys[0] + sdy * leaves, 1)
    axes.insert(axes[1], 1)
    inc last

  # Keep tokens to avoid parsing d when checking fills.
  var tokens: seq[float]
  proc tok(v: float): string =
    tokens.add written(v)
    num(v)
  tokens.add [77.0, 2]
  var d = "M" & tok(xs[0]) & "," & tok(ys[0])
  var atX = xs[0]
  var atY = ys[0]
  proc lineTo(x, y: float) =
    if near(x, y, atX, atY): return
    tokens.add [76.0, 2]
    d.add "L" & tok(x) & "," & tok(y)
    atX = x
    atY = y
  for i in 1 .. last:
    let x = xs[i]
    let y = ys[i]
    if not straight(i):
      let down = axes[i] == 0
      let along = if down: y - atY else: x - atX
      let k = abs(along) * ease(if down: x - atX else: y - atY, along)
      let ux = if down: 0.0 else: jsSign(along) * k
      let uy = if down: jsSign(along) * k else: 0.0
      tokens.add [67.0, 6]
      d.add "C" & tok(atX + ux) & "," & tok(atY + uy) & " " & tok(x - ux) & "," & tok(y - uy) & " " &
        tok(x) & "," & tok(y)
      atX = x
      atY = y
      continue
    if not turns(i):
      # A point part of the way along one straight run adds nothing to the path.
      if i < last and aligned(i) and aligned(i + 1) and
         (x - xs[i - 1]) * (xs[i + 1] - x) + (y - ys[i - 1]) * (ys[i + 1] - y) > 0:
        continue
      lineTo(x, y)
      continue
    # How much of the leg before the turn and of the leg after it the turn takes: all of one
    # that ends at a node, short of the straight run into a marker, and half of one it shares.
    var before = if turns(i - 1): length(i) / 2 else: length(i)
    var after = if turns(i + 1): length(i + 1) / 2 else: length(i + 1)
    if stepped:
      before = min(CORNER, min(before, after))
      after = before
    let (ux, uy) = unit(i - 1, i, axes[i])
    let (vx, vy) = unit(i, i + 1, axes[i + 1])
    lineTo(x - ux * before, y - uy * before)
    atX = x + vx * after
    atY = y + vy * after
    if stepped:
      tokens.add [81.0, 4]
      d.add "Q" & tok(x) & "," & tok(y) & " " & tok(atX) & "," & tok(atY)
    else:
      tokens.add [67.0, 6]
      d.add "C" & tok(x - ux * before * (1 - HANDLE)) & "," & tok(y - uy * before * (1 - HANDLE)) & " " &
        tok(x + vx * after * (1 - HANDLE)) & "," & tok(y + vy * after * (1 - HANDLE)) & " " & tok(atX) &
        "," & tok(atY)
  EdgePath(d: d, tokens: tokens, sx: sx, sy: sy, sdx: -sdx, sdy: -sdy, ex: ex, ey: ey, edx: edx, edy: edy)

proc marker*(kind: string, x, y, dx, dy: float, color: string, stroke = "none"): string =
  ## Draws a marker whose tip is at (x, y), pointing along (dx, dy).
  let nx = -dy
  let ny = dx
  if kind == "arrow_point":
    let bx = x - dx * ARROW
    let by = y - dy * ARROW
    let half = ARROW * 0.42
    return "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & num(bx + nx * half) & "," &
      num(by + ny * half) & "L" & num(bx - nx * half) & "," & num(by - ny * half) & "Z\" fill=\"" & color &
      "\" stroke=\"" & stroke & "\"/>"
  if kind == "arrow_circle":
    return "<circle class=\"pele-marker\" cx=\"" & num(x - dx * 4) & "\" cy=\"" & num(y - dy * 4) &
      "\" r=\"3.5\" fill=\"" & color & "\" stroke=\"" & stroke & "\"/>"
  if kind == "arrow_cross":
    let cx = x - dx * 4
    let cy = y - dy * 4
    let a = 3.5
    let ux = (dx + nx) * a
    let uy = (dy + ny) * a
    let vx = (dx - nx) * a
    let vy = (dy - ny) * a
    return "<path class=\"pele-marker\" d=\"M" & num(cx - ux) & "," & num(cy - uy) & "L" & num(cx + ux) & "," &
      num(cy + uy) & "M" & num(cx - vx) & "," & num(cy - vy) & "L" & num(cx + vx) & "," & num(cy + vy) & "\"/>"
  ""

const TENS = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14,
              1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22]
  ## Number(`1e${i}`)

func charAt(d: string, i: int): int = (if i < d.len: ord(d[i]) else: -1)

proc tokenize(d: string): seq[float] =
  ## Each command stores its character code, argument count, and arguments.
  var output: seq[float]
  var at = -1
  var i = 0
  while i < d.len:
    let c = ord(d[i])
    if c >= 65 and c <= 90 and c != 69:
      at = output.len + 1
      output.add [float(c), 0]
      inc i
    elif c == 45 or c == 46 or (c >= 48 and c <= 57):
      # Scale exact integers to match Number() rounding; otherwise use Number().
      var j = if c == 45: i + 1 else: i
      var m = 0.0
      var places = -1
      var k = charAt(d, j)
      while (k >= 48 and k <= 57) or (k == 46 and places < 0):
        if k == 46: places = 0
        else:
          m = m * 10 + float(k - 48)
          if places >= 0: inc places
        inc j
        k = charAt(d, j)
      var v: float
      if (charAt(d, j) or 32) == 101 or m > 9007199254740991.0 or places > 22:
        k = charAt(d, j)
        while k == 46 or k == 101 or k == 69 or (k >= 48 and k <= 57) or
              ((k == 45 or k == 43) and (charAt(d, j - 1) or 32) == 101):
          inc j
          k = charAt(d, j)
        v = try: parseFloat(d[i ..< j]) except ValueError: NaN
      else:
        v = if places > 0: m / TENS[places] else: m
        if c == 45: v = -v
      if at >= 0:
        output.add v
        output[at] += 1
      i = j
    else:
      inc i
  output

proc arc(output: var seq[float], x1, y1, rxIn, ryIn, large, sweep, x2, y2: float) =
  ## Samples an unrotated arc from (x1, y1), after SVG's conversion from end points to a center.
  var rx = rxIn
  var ry = ryIn
  let hx = (x1 - x2) / 2
  let hy = (y1 - y2) / 2
  if rx == 0 or ry == 0 or (hx == 0 and hy == 0):
    output.add [x2, y2]
    return
  let scale = max(1.0, sqrt((hx * hx) / (rx * rx) + (hy * hy) / (ry * ry)))
  rx *= scale
  ry *= scale
  let k = (if large == sweep: -1.0 else: 1.0) *
    sqrt(max(0.0, (rx * rx * ry * ry - rx * rx * hy * hy - ry * ry * hx * hx) / (rx * rx * hy * hy + ry * ry * hx * hx)))
  let cx = (k * rx * hy) / ry + (x1 + x2) / 2
  let cy = (-k * ry * hx) / rx + (y1 + y2) / 2
  let start = atan2((y1 - cy) / ry, (x1 - cx) / rx)
  var turn = atan2((y2 - cy) / ry, (x2 - cx) / rx) - start
  if sweep != 0 and turn < 0: turn += 2 * PI
  elif sweep == 0 and turn > 0: turn -= 2 * PI
  for i in 1 .. 8:
    output.add [cx + rx * cos(start + (turn * float(i)) / 8), cy + ry * sin(start + (turn * float(i)) / 8)]

proc sample(tokens: seq[float]): seq[float] =
  var output: seq[float]
  var x = 0.0
  var y = 0.0
  var i = 0
  while i < tokens.len:
    let cmd = int(tokens[i])
    let count = int(tokens[i + 1])
    let s = i + 2
    let e = s + count
    i = e
    if cmd == 72 or cmd == 86:
      for k in s ..< e:
        if cmd == 72: x = tokens[k] else: y = tokens[k]
        output.add [x, y]
    elif cmd == 67 or cmd == 81:
      let cubic = cmd == 67
      let step = if cubic: 6 else: 4
      var k = s
      while k + step <= e:
        let x1 = tokens[k]
        let y1 = tokens[k + 1]
        let x2 = tokens[k + 2]
        let y2 = tokens[k + 3]
        let x3 = if cubic: tokens[k + 4] else: x2
        let y3 = if cubic: tokens[k + 5] else: y2
        var t = 0.125
        while t <= 1:
          # Preserve the original De Casteljau operation order to keep rounding unchanged.
          var ax = x + (x1 - x) * t
          var ay = y + (y1 - y) * t
          var bx = x1 + (x2 - x1) * t
          var by = y1 + (y2 - y1) * t
          if cubic:
            let cx = x2 + (x3 - x2) * t
            let cy = y2 + (y3 - y2) * t
            ax += (bx - ax) * t
            ay += (by - ay) * t
            bx += (cx - bx) * t
            by += (cy - by) * t
          output.add [ax + (bx - ax) * t, ay + (by - ay) * t]
          t += 0.125
        x = x3
        y = y3
        k += step
    elif cmd == 65:
      var k = s
      while k + 7 <= e:
        arc(output, x, y, tokens[k], tokens[k + 1], tokens[k + 3], tokens[k + 4], tokens[k + 5], tokens[k + 6])
        x = tokens[k + 5]
        y = tokens[k + 6]
        k += 7
    else:
      var k = s
      while k + 2 <= e:
        if cmd == 77 and k == s and output.len > 0: output.add [NaN, NaN]
        x = tokens[k]
        y = tokens[k + 1]
        output.add [x, y]
        k += 2
  output

proc pathPoints(d: string): seq[float] =
  ## Samples curves and arcs; NaN separates subpaths.
  sample(tokenize(d))

proc clips(x, y, dx, dy, l, t, r, b: float): bool =
  ## Test segment overlap with the box using Liang-Barsky clipping.
  var lo = 0.0
  var hi = 1.0
  for side in 0 ..< 4:
    let p = if side == 0: -dx elif side == 1: dx elif side == 2: -dy else: dy
    let q = if side == 0: x - l elif side == 1: r - x elif side == 2: y - t else: b - y
    if p == 0:
      if q < 0: hi = -1
    elif p < 0: lo = jsMax(lo, q / p)
    else: hi = jsMin(hi, q / p)
  lo < hi

proc enters(points: seq[float], l, t, r, b: float): bool =
  var k = 0
  while k + 2 < points.len:
    let x = points[k]
    let y = points[k + 1]
    let x2 = points[k + 2]
    let y2 = points[k + 3]
    if not ((x < l and x2 < l) or (x > r and x2 > r) or (y < t and y2 < t) or (y > b and y2 > b)):
      if clips(x, y, x2 - x, y2 - y, l, t, r, b): return true
    k += 2
  false

type
  Fill* = object
    ## Fill bounds are [left, top, right, bottom].
    box*: array[4, float]
    shape*: string
  FillAt* = object
    ## undefined (`none`), '' (`across`), or a fill
    none*, across*: bool
    fill*: Fill

proc fillUnder*(d: string, tips: openArray[float], fills: seq[Fill], tokens: seq[float] = @[]): FillAt =
  ## The innermost fill holding the whole edge and its marker tips, '' when it crosses a border,
  ## or undefined off fills.
  if fills.len == 0: return FillAt(none: true)
  let points = if tokens.len > 0: sample(tokens) else: pathPoints(d)
  var minX = Inf
  var minY = Inf
  var maxX = -Inf
  var maxY = -Inf
  var k = 0
  while k < points.len + tips.len:
    let x = if k < points.len: points[k] else: tips[k - points.len]
    let y = if k < points.len: points[k + 1] else: tips[k + 1 - points.len]
    if x < minX: minX = x
    if x > maxX: maxX = x
    if y < minY: minY = y
    if y > maxY: maxY = y
    k += 2
  var found = false
  var holder: Fill
  var least = Inf
  for fill in fills:
    let (l, t, r, b) = (fill.box[0], fill.box[1], fill.box[2], fill.box[3])
    if maxX < l + 0.5 or minX > r - 0.5 or maxY < t + 0.5 or minY > b - 0.5: continue
    var touched = enters(points, l + 0.5, t + 0.5, r - 0.5, b - 0.5)
    var k = 0
    while k < tips.len and not touched:
      touched = tips[k] > l + 0.5 and tips[k] < r - 0.5 and tips[k + 1] > t + 0.5 and tips[k + 1] < b - 0.5
      k += 2
    if not touched: continue
    if minX < l or maxX > r or minY < t or maxY > b: return FillAt(across: true)
    let area = (r - l) * (b - t)
    if area < least:
      least = area
      holder = fill
      found = true
  if found: FillAt(fill: holder) else: FillAt(none: true)

func hasDecl(s, prop: string): bool =
  ## /[";]prop:/.test(s)
  var at = s.find(prop & ":")
  while at != -1:
    if at > 0 and s[at - 1] in {'"', ';'}: return true
    at = s.find(prop & ":", at + 1)
  false

proc edgeInk*(fill: Fill, line = ""): string =
  ## The fill's ink for an edge on it, or '' for a casing when unknown or when the line style sets a stroke.
  if hasDecl(line, "stroke"): return ""
  let (ok, color) = ink(fill.shape)
  if ok: color else: ""

proc hollowOn*(markers: string, fill: Fill): string =
  ## Markers with the page color inside them, with the fill's color there instead.
  # /[";]fill:([^;"]*)/.exec(fill.shape)?.[1].trim()
  var color = ""
  let s = fill.shape
  var at = s.find("fill:")
  while at != -1:
    if at > 0 and s[at - 1] in {'"', ';'}:
      var stop = at + 5
      while stop < s.len and s[stop] notin {';', '"'}: inc stop
      color = jsTrim(s[at + 5 ..< stop])
      break
    at = s.find("fill:", at + 1)
  if color != "": markers.replace(" fill=\"var(--_bg)\"", " fill=\"" & color & "\"") else: markers

type OverFill* = object
  ## undefined (`none`), or the ink: '' for a casing.
  none*: bool
  ink*: string

proc overFills*(d: string, tips: openArray[float], fills: seq[Fill], line = "",
                tokens: seq[float] = @[]): OverFill =
  ## The ink of the innermost fill that holds the whole edge, '' for a casing where it crosses a
  ## border, or undefined off fills.
  let fill = fillUnder(d, tips, fills, tokens)
  if fill.none: OverFill(none: true)
  elif fill.across: OverFill(ink: "")
  else: OverFill(ink: edgeInk(fill.fill, line))

const CASE = 4.0

proc declValue(line, prop: string): (bool, string) =
  ## line.includes(prop) ? new RegExp(`[";]${prop}:([^;"]+);`).exec(line)?.[1].trim() : undefined
  if prop notin line: return (false, "")
  var at = line.find(prop & ":")
  while at != -1:
    if at > 0 and line[at - 1] in {'"', ';'}:
      let start = at + prop.len + 1
      var stop = start
      while stop < line.len and line[stop] notin {';', '"'}: inc stop
      if stop > start and stop < line.len and line[stop] == ';':
        return (true, jsTrim(line[start ..< stop]))
    at = line.find(prop & ":", at + 1)
  (false, "")

func isPlainWidth(s: string): bool =
  ## /^[\d.]+(?:px)?$/
  var k = 0
  while k < s.len and s[k] in {'0'..'9', '.'}: inc k
  k > 0 and (k == s.len or s[k .. ^1] == "px")

func jsParseFloat(s: string): float =
  ## parseFloat of a string that `isPlainWidth` accepts.
  var stop = 0
  var dot = false
  while stop < s.len and s[stop] in {'0'..'9', '.'}:
    if s[stop] == '.':
      if dot: break
      dot = true
    inc stop
  var p = s[0 ..< stop]
  if p == "." or p == "": return NaN
  if p.startsWith("."): p = "0" & p
  if p.endsWith("."): p.add "0"
  parseFloat(p)

proc casing*(d, markers: string, line = "", thick = false): string =
  ## A wider page-colored stroke under an edge, as faint as it; markers drop their class so
  ## marker styles skip it.
  let (hasStroke, stroke) = declValue(line, "stroke")
  if hasStroke and (stroke == "none" or stroke == "transparent"): return ""
  var (hasWidth, width) = declValue(line, "stroke-width")
  if thick:
    hasWidth = true
    width = "2.5"
  var attrs = ""
  var style = ""
  if hasWidth and isPlainWidth(width):
    if jsParseFloat(width) != 1: attrs = " stroke-width=\"" & num(jsParseFloat(width) + CASE) & "\""
  elif hasWidth:
    style.add "stroke-width:calc(" & width & " + " & jsString(CASE) & "px);"
  for prop in ["opacity", "stroke-opacity"]:
    let (has, value) = declValue(line, prop)
    if has: style.add prop & ":" & value & ";"
  let body = "<path d=\"" & d & "\"/>" & markers.replace(" class=\"pele-marker\"", "")
  if attrs != "" or style != "":
    "<g" & attrs & (if style != "": " style=\"" & style & "\"" else: "") & ">" & body & "</g>"
  else: body

proc edgeCasing*(path: EdgePath, startType, endType: string, line = "", thick = false): string =
  casing(path.d,
    marker(startType, path.sx, path.sy, path.sdx, path.sdy, "var(--_bg)", "var(--_bg)") &
      marker(endType, path.ex, path.ey, path.edx, path.edy, "var(--_bg)", "var(--_bg)"),
    line, thick)

proc casingsSvg*(casings: string): string =
  if casings != "":
    "<g class=\"pele-casings\" fill=\"none\" stroke=\"var(--_bg)\" stroke-width=\"" & jsString(1 + CASE) &
      "\" stroke-linecap=\"round\" stroke-linejoin=\"round\" pointer-events=\"none\">" & casings & "</g>"
  else: ""

proc edgeLabelSvg*(id: string, label: Label, x, y: float, attrs: string, icons: IconResolver = nil): string =
  ## An edge label on a patch of the background, so the line does not run through the text.
  let w = label.width + 8
  let h = label.height
  "<g class=\"pele-edge-label\" data-id=\"" & escText(id) & "\">" &
    "<rect x=\"" & num(x - w / 2) & "\" y=\"" & num(y - h / 2) & "\" width=\"" & num(w) & "\" height=\"" &
    num(h) & "\" rx=\"3\" fill=\"var(--_bg)\"/>" &
    labelSvg(label, x, y, attrs, icons) &
    "</g>"

proc loopPath*[E](c: tuple[x, y: float], w, h: float, k: int, sideways: bool, base, trim: float,
                  e: E): EdgePath =
  ## A self-loop beside a node of drawn size w by h: out of the side that lies across the flow
  ## and back in. `k` counts the loops already on the node, so each one reaches a little
  ## further. Also places the edge's label beyond the loop. `e` is a ref with labelW, labelH,
  ## labelX and labelY.
  let half = (if sideways: w else: h) / 2
  let spread = min(half - 4, 8 + float(k) * 6)
  let reach = base + float(k) * 8
  var len = hypot(reach, spread)
  if len == 0 or isNaN(len): len = 1
  # Local frame: `out` points away from the node, `along` runs along its side.
  proc at(output, along: float): string =
    if sideways: num(c.x + along) & "," & num(c.y + h / 2 + output)
    else: num(c.x + w / 2 + output) & "," & num(c.y + along)
  let tx = (reach / len) * trim
  let ty = (spread / len) * trim
  if sideways:
    e.labelX = c.x
    e.labelY = c.y + h / 2 + reach + 4 + e.labelH / 2
  else:
    e.labelX = c.x + w / 2 + reach + 4 + e.labelW / 2
    e.labelY = c.y
  EdgePath(
    d: "M" & at(0, -spread) & "C" & at(reach, -spread * 2) & " " & at(reach, spread * 2) & " " & at(tx, spread + ty),
    sx: if sideways: c.x - spread else: c.x + w / 2,
    sy: if sideways: c.y + h / 2 else: c.y - spread,
    sdx: if sideways: 0 else: -1,
    sdy: if sideways: -1 else: 0,
    ex: if sideways: c.x + spread else: c.x + w / 2,
    ey: if sideways: c.y + h / 2 else: c.y + spread,
    edx: if sideways: -spread / len else: -reach / len,
    edy: if sideways: -reach / len else: -spread / len)

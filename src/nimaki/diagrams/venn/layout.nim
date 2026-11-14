## port-of: src/diagrams/venn/layout.ts
## port-status: draft
##
## A circle is a `ref object`, so that, as in Pele, the layout moves the very circles it returns
## and `regionPath` can tell two circles apart by identity (`==` on refs, which the JavaScript
## build also has).
import std/[algorithm, json, sets, tables]
from std/math import PI, floor, ceil, isNaN, classify, FloatClass
import ../../jsmath
import ../../js
import types

type
  Circle* = ref object
    id*: string
    x*, y*, r*: float

  Spot* = object
    ## Where the content of a region goes: the point inside all of `inside` and outside every
    ## other circle that is farthest from their outlines, and how far that is. A margin of 0 or
    ## less means the circles as placed leave the region empty.
    x*, y*, margin*: float

const TAU = PI * 2

func isFiniteNumber(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

func keyOfSorted(sets: seq[string]): string =
  var sorted = sets
  sorted.sort(jsCompare)
  $(%sorted)

proc ensurePairwiseSubsets*(subsets: seq[VennSubset]): seq[VennSubset] =
  ## For every overlap of three or more sets, adds the pairwise overlaps it implies and the
  ## diagram does not state, a quarter of the smaller set each, so that the circles are drawn
  ## overlapping. Returns the list it was given when there is nothing to add.
  var present = initHashSet[string]()
  var sizes = initTable[string, float]()
  for subset in subsets:
    present.incl keyOfSorted(subset.sets)
    if subset.sets.len == 1: sizes[subset.sets[0]] = subset.size
  var added: seq[VennSubset]
  for subset in subsets:
    if subset.sets.len < 3: continue
    var members = subset.sets
    members.sort(jsCompare)
    for i in 0 ..< members.len - 1:
      for j in i + 1 ..< members.len:
        let pair = @[members[i], members[j]]
        let key = $(%pair)
        if key in present: continue
        present.incl key
        let size = if pair[0] in sizes and pair[1] in sizes: jsMin(sizes[pair[0]], sizes[pair[1]]) / 4 else: 2.5
        added.add VennSubset(sets: pair, size: size, label: "", hasLabel: true)
  if added.len > 0: subsets & added else: subsets

proc lensArea*(r1, r2, d: float): float =
  ## The area two circles share when their centers are d apart.
  if d >= r1 + r2: return 0
  let small = jsMin(r1, r2)
  if d <= abs(r1 - r2): return PI * small * small
  let a1 = r1 * r1 * acos((d * d + r1 * r1 - r2 * r2) / (2 * d * r1))
  let a2 = r2 * r2 * acos((d * d + r2 * r2 - r1 * r1) / (2 * d * r2))
  let a3 = 0.5 * sqrt(jsMax((-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2), 0))
  a1 + a2 - a3

proc distanceForOverlap*(r1, r2, area: float): float =
  ## How far apart two circles sit for their overlap to have the given area. The area falls as
  ## the distance grows, so bisection finds it.
  var low = abs(r1 - r2)
  var high = r1 + r2
  if not (area > 0): return high
  let m = jsMin(r1, r2)
  if area >= PI * pow(m, 2): return low
  for i in 0 ..< 48:
    let middle = (low + high) / 2
    if lensArea(r1, r2, middle) > area: low = middle
    else: high = middle
  (low + high) / 2

proc margin(circles: seq[Circle], inside, outside: seq[int], x, y, floor: float): float =
  ## How far a point is from the nearest outline it must stay within or without. Gives up, with
  ## some value below `floor`, as soon as the point cannot reach `floor`.
  var best = Inf
  for i in inside:
    let c = circles[i]
    let dx = x - c.x
    let dy = y - c.y
    let room = c.r - sqrt(dx * dx + dy * dy)
    if room < best:
      if room < floor: return room
      best = room
  for i in outside:
    let c = circles[i]
    let dx = x - c.x
    let dy = y - c.y
    let room = sqrt(dx * dx + dy * dy) - c.r
    if room < best:
      if room < floor: return room
      best = room
  best

proc findSpot*(circles: seq[Circle], inside, outside: seq[int]): Spot =
  ## Finds the roomiest point of a region by sampling the smallest of its circles on a grid and
  ## then walking uphill from the best sample. Ties go to the point nearest the middle of the
  ## region, so a symmetric arrangement gets symmetric labels.
  var cx = 0.0
  var cy = 0.0
  var smallest = circles[inside[0]]
  for i in inside:
    let c = circles[i]
    cx += c.x / float(inside.len)
    cy += c.y / float(inside.len)
    if c.r < smallest.r: smallest = c
  let r = smallest.r
  var x = cx
  var y = cy
  var best = margin(circles, inside, outside, x, y, NegInf)
  var off = 0.0
  proc consider(px, py: float): bool =
    let m = margin(circles, inside, outside, px, py, best - r * 1e-9)
    if not (m > best - r * 1e-9): return false
    let distance = hypot(px - cx, py - cy)
    if m > best + r * 1e-9 or distance < off - r * 1e-9:
      best = m
      off = distance
      x = px
      y = py
      return true
    false
  const GRID = 10
  for gy in -GRID .. GRID:
    for gx in -GRID .. GRID:
      if gx * gx + gy * gy <= GRID * GRID:
        discard consider(smallest.x + (float(gx) * r) / GRID, smallest.y + (float(gy) * r) / GRID)
  var step = r / GRID
  var round = 0
  while round < 40 and step > r * 1e-6:
    var moved = false
    for k in 0 ..< 8:
      let angle = (float(k) * TAU) / 8
      if consider(x + cos(angle) * step, y + sin(angle) * step): moved = true
    if not moved: step /= 2
    inc round
  Spot(x: x, y: y, margin: best)

proc layoutCircles*(subsets: seq[VennSubset]): seq[Circle] =
  ## Places one circle per set, with areas in proportion to the sizes of the sets and each pair as
  ## far apart as its overlap asks: one, two and three sets exactly, more by relaxing a ring of
  ## circles toward those distances. Lengths are in units of the square root of a size.
  var sizes = initOrderedTable[string, float]()
  for subset in subsets:
    for id in subset.sets:
      if id notin sizes: sizes[id] = 10
  for subset in subsets:
    if subset.sets.len == 1: sizes[subset.sets[0]] = subset.size

  var index = initTable[string, int]()
  var circles: seq[Circle]
  var largest = 0.0
  for size in sizes.values:
    if isFiniteNumber(size) and size > largest: largest = size
  if largest == 0: largest = 10
  let widest = sqrt(largest / PI)
  for id, size in sizes:
    index[id] = circles.len
    # A set too small to hold its name, or with no size at all, still gets a circle that shows.
    let r = if isFiniteNumber(size) and size > 0: sqrt(size / PI) else: 0.0
    circles.add Circle(id: id, x: 0, y: 0, r: jsMax(r, widest * 0.3))
  let n = circles.len
  if n < 2: return circles

  # The overlap each pair was given, by the indexes of its circles.
  var overlaps = initOrderedTable[int, float]()
  for subset in ensurePairwiseSubsets(subsets):
    if subset.sets.len != 2: continue
    let a = index[subset.sets[0]]
    let b = index[subset.sets[1]]
    if a != b: overlaps[min(a, b) * n + max(a, b)] = subset.size
  # How far apart each overlapping pair should be. Pairs that do not overlap only have to keep a gap.
  var wanted = initTable[int, float]()
  for key, area in overlaps:
    wanted[key] = distanceForOverlap(circles[key div n].r, circles[key mod n].r, area)
  let gap = widest * 0.15
  proc distance(a, b: int): float =
    wanted.getOrDefault(a * n + b, circles[a].r + circles[b].r + gap)

  if n == 2:
    circles[1].x = distance(0, 1)
    return circles

  if n == 3:
    # Two sets side by side and the third below, the corners of a triangle whose sides are the
    # three distances. An overlap of all three has to exist, so the triangle shrinks until it does.
    var ab = distance(0, 1)
    var ac = distance(0, 2)
    var bc = distance(1, 2)
    var triple = false
    for subset in subsets:
      if toHashSet(subset.sets).len == 3: triple = true
    for attempt in 0 ..< 40:
      let x = if ab > 0: (ab * ab + ac * ac - bc * bc) / (2 * ab) else: 0.0
      circles[1].x = ab
      circles[2].x = jsMax(-ac, jsMin(ac, x))
      circles[2].y = sqrt(jsMax(ac * ac - x * x, 0))
      if not triple or findSpot(circles, @[0, 1, 2], @[]).margin > widest * 0.12: break
      ab *= 0.94
      ac *= 0.94
      bc *= 0.94
    return circles

  var total = 0.0
  for c in circles: total += 2 * c.r + gap
  let rounds = int(jsMin(300, floor(3e6 / float(n * n))))
  if n <= 64:
    let ring = total / TAU
    for i, c in circles:
      let angle = (float(i) * TAU) / float(n) - PI / 2
      c.x = cos(angle) * ring
      c.y = sin(angle) * ring
  else:
    let columns = int(ceil(sqrt(float(n))))
    let cell = 2 * widest + gap
    for i, c in circles:
      c.x = float(i mod columns) * cell
      c.y = floor(float(i) / float(columns)) * cell
  var dx = newSeq[float](n)
  var dy = newSeq[float](n)
  var pulls = newSeq[int](n)
  for round in 0 ..< rounds:
    for i in 0 ..< n:
      dx[i] = 0
      dy[i] = 0
      pulls[i] = 0
    for a in 0 ..< n:
      for b in a + 1 ..< n:
        let has = (a * n + b) in wanted
        let overlap = if has: wanted[a * n + b] else: 0.0
        let apart = circles[a].r + circles[b].r + gap
        var ux = circles[b].x - circles[a].x
        var uy = circles[b].y - circles[a].y
        var length = hypot(ux, uy)
        if not has and length >= apart: continue
        if length < 1e-9:
          ux = cos(float(a + b))
          uy = sin(float(a + b))
          length = 1
        let move = (length - (if has: overlap else: apart)) / 2 / length
        dx[a] += ux * move
        dy[a] += uy * move
        dx[b] -= ux * move
        dy[b] -= uy * move
        inc pulls[a]
        inc pulls[b]
    for i in 0 ..< n:
      if pulls[i] == 0: continue
      circles[i].x += dx[i] / float(pulls[i])
      circles[i].y += dy[i] / float(pulls[i])
  circles

proc regionPath*(circles: seq[Circle], format: proc (value: float): string): string =
  ## The outline of the region all the given circles share, as an SVG path, or "" if they share none.
  proc whole(c: Circle): string =
    "M" & format(c.x - c.r) & "," & format(c.y) & "A" & format(c.r) & "," & format(c.r) & " 0 1 1 " &
      format(c.x + c.r) & "," & format(c.y) & "A" & format(c.r) & "," & format(c.r) & " 0 1 1 " &
      format(c.x - c.r) & "," & format(c.y) & "Z"
  if circles.len == 1: return whole(circles[0])
  proc within(x, y: float, skip, other: Circle): bool =
    for c in circles:
      if c != skip and c != other and hypot(x - c.x, y - c.y) > c.r * (1 + 1e-9): return false
    true
  type Corner = object
    x, y: float
    a, b: Circle
  # The corners of the region: where two outlines cross inside all the other circles.
  var corners: seq[Corner]
  for i in 0 ..< circles.len:
    for j in i + 1 ..< circles.len:
      let a = circles[i]
      let b = circles[j]
      let d = hypot(b.x - a.x, b.y - a.y)
      if d >= a.r + b.r or d <= abs(a.r - b.r) or d == 0: continue
      let along = (a.r * a.r - b.r * b.r + d * d) / (2 * d)
      let up = sqrt(jsMax(a.r * a.r - along * along, 0))
      let mx = a.x + ((b.x - a.x) * along) / d
      let my = a.y + ((b.y - a.y) * along) / d
      for sign in [1.0, -1.0]:
        let x = mx + (sign * up * (b.y - a.y)) / d
        let y = my - (sign * up * (b.x - a.x)) / d
        if within(x, y, a, b): corners.add Corner(x: x, y: y, a: a, b: b)
  if corners.len < 2:
    # No corners: either one circle lies inside all the others, or there is nothing shared.
    var smallest = circles[0]
    for c in circles:
      if c.r < smallest.r: smallest = c
    for c in circles:
      if c != smallest and hypot(c.x - smallest.x, c.y - smallest.y) + smallest.r > c.r * (1 + 1e-9): return ""
    return whole(smallest)
  var cx = 0.0
  var cy = 0.0
  for p in corners:
    cx += p.x / float(corners.len)
    cy += p.y / float(corners.len)
  corners.sort(proc (p, q: Corner): int =
    let d = atan2(p.y - cy, p.x - cx) - atan2(q.y - cy, q.x - cx)
    if d < 0: -1 elif d > 0: 1 else: 0)
  var d = ""
  for i in 0 ..< corners.len:
    let source = corners[i]
    let to = corners[(i + 1) mod corners.len]
    if i == 0: d = "M" & format(source.x) & "," & format(source.y)
    # The side between two corners is an arc of a circle that passes through both; of those, the
    # one whose arc stays inside the others.
    var arc: Circle = nil
    var large = 0
    var narrowest = Inf
    for c in [source.a, source.b]:
      if c != to.a and c != to.b: continue
      let start = atan2(source.y - c.y, source.x - c.x)
      var sweep = atan2(to.y - c.y, to.x - c.x) - start
      if sweep <= 0: sweep += TAU
      let mx = c.x + c.r * cos(start + sweep / 2)
      let my = c.y + c.r * sin(start + sweep / 2)
      let width = hypot(mx - (source.x + to.x) / 2, my - (source.y + to.y) / 2)
      if width < narrowest:
        narrowest = width
        arc = c
        large = if sweep > PI: 1 else: 0
    if arc == nil: d.add "L" & format(to.x) & "," & format(to.y)
    else: d.add "A" & format(arc.r) & "," & format(arc.r) & " 0 " & $large & " 1 " & format(to.x) & "," & format(to.y)
  d & "Z"

## port-of: src/diagrams/architecture/render.ts
## port-status: draft
import std/[options, tables, algorithm]
from std/math import ceil, floor
import ../../preprocess
import ../../svg/[builder, edges, root, theme]
import ../../text/[label, measurer]
import ../../text/icons as textIcons
import ../../types
import ../../util/yaml
import ../../js
import ../../jsmath
import ../common/fit_width
import db, layout
import ./icons as archIcons

const
  STUB = 12.0
  CORNER = 6.0
  LABEL_GAP = 4.0
  DOT = 3.0
  DX = [-1.0, 1, 0, 0]
  DY = [0.0, 0, -1, 1]

proc setting(config: Config, key: string, fallback, lo, hi: float): float =
  let section = config["architecture"]
  let value = if isRecord(section): section[key] else: nil
  if value != nil and value.kind == yNumber and value.n - value.n == 0: min(hi, max(lo, value.n)) else: fallback

proc rank(values: var seq[float]): Table[float, int] =
  ## Maps the grid lines in use to consecutive indexes, so empty rows and columns take no room.
  values.sort(proc (a, b: float): int = cmp(a, b))
  for value in values:
    if value notin result: result[value] = result.len

proc iconSlot(name: string, x, y, side: float, icons: IconResolver): string =
  let found = if icons != nil: icons(name) else: ""
  "<svg class=\"pele-icon\" data-icon=\"" & escText(name) & "\" x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" &
    num(side) & "\" height=\"" & num(side) & "\"" &
    " viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
    (if found != "": found else: builtinIcon(name)) & "</svg>"

func unitsBefore(s: string, units: int): string =
  ## `s.slice(0, units)`, where a cut inside a surrogate pair keeps the whole character (the
  ## measurer gives a lone high surrogate the width of the character).
  s[0 ..< unitOffset(s, 0, units)]

func isHighSurrogateAt(s: string, unit: int): bool =
  ## Whether UTF-16 code unit `unit` of `s` is the first half of a surrogate pair.
  var k = 0
  var i = 0
  while i < s.len:
    let (cp, size) = codePointAt(s, i)
    if k == unit: return cp >= 0x10000
    k += (if cp >= 0x10000: 2 else: 1)
    if k > unit: return false
    i += size
  false

proc fit(label: Label, maxWidth: float, maxLines: int, measurer: TextMeasurer): Label =
  ## Cuts a label down to a box, ending what is left with an ellipsis.
  let cut = label.lines.len > maxLines
  if not cut and label.width <= maxWidth: return label
  let dots = measurer.width("…", label.size, 0)
  var lines: seq[seq[Span]]
  var widths: seq[float]
  var widest = 0.0
  for i in 0 ..< min(maxLines, label.lines.len):
    var line = label.lines[i]
    var width = label.widths[i]
    if width > maxWidth or (cut and i == maxLines - 1):
      while true:
        if line.len == 0:
          line.add Span(text: "…", style: 0, width: dots)
          width = dots
          break
        let rest = width - line[^1].width
        if not line[^1].hasIcon and rest + dots < maxWidth:
          let text = line[^1].text
          let style = line[^1].style
          var lo = 0
          var hi = utf16Len(text)
          while lo < hi:
            let mid = (lo + hi + 1) shr 1
            if rest + measurer.width(unitsBefore(text, mid), label.size, style) + dots <= maxWidth: lo = mid
            else: hi = mid - 1
          if lo > 0 and isHighSurrogateAt(text, lo - 1): dec lo
          line[^1].text = jsTrimEnd(unitsBefore(text, lo)) & "…"
          line[^1].width = measurer.width(line[^1].text, label.size, style)
          width = rest + line[^1].width
          break
        discard line.pop()
        width = rest
    lines.add line
    widths.add width
    widest = max(widest, width)
  result = label
  result.lines = lines
  result.widths = widths
  result.width = widest
  result.height = float(lines.len) * label.lineHeight

type Port = object
  x, y, dx, dy: float
  x0, y0, x1, y1: float
    ## The box the route has to stay out of when it cannot leave straight.
  gap: float
    ## How far short of the port an arrowhead stops: the radius of a junction's dot.
  wire: bool
    ## Set where a junction is reached through the border of its group: the line carries on to the junction.

proc route(s, e: Port): seq[float] =
  ## An orthogonal route from one port to another, each left along its side's normal.
  let (sx, sy, sdx, sdy) = (s.x, s.y, s.dx, s.dy)
  let (ex, ey, edx, edy) = (e.x, e.y, e.dx, e.dy)
  let s1x = sx + sdx * STUB
  let s1y = sy + sdy * STUB
  let e1x = ex + edx * STUB
  let e1y = ey + edy * STUB
  if sdx * edx + sdy * edy == 0:
    let cx = if sdx != 0: ex else: sx
    let cy = if sdx != 0: sy else: ey
    if (cx - sx) * sdx + (cy - sy) * sdy > 0 and (cx - ex) * edx + (cy - ey) * edy > 0: return @[sx, sy, cx, cy, ex, ey]
    return if sdx != 0: @[sx, sy, s1x, s1y, s1x, e1y, e1x, e1y, ex, ey]
           else: @[sx, sy, s1x, s1y, e1x, s1y, e1x, e1y, ex, ey]
  let sideways = sdx != 0
  let offset = if sideways: ey - sy else: ex - sx
  if sdx == -edx and sdy == -edy:
    let ahead = (ex - sx) * sdx + (ey - sy) * sdy
    if ahead > 0:
      if abs(offset) < 0.5: return @[sx, sy, ex, ey]
      # Turn midway between the two boxes, which is clear of both titles, when there is such a place.
      if sideways:
        let lo = if sdx > 0: s.x1 else: e.x1
        let hi = if sdx > 0: e.x0 else: s.x0
        let mx = if lo < hi: (lo + hi) / 2 else: (sx + ex) / 2
        return @[sx, sy, mx, sy, mx, ey, ex, ey]
      let lo = if sdy > 0: s.y1 else: e.y1
      let hi = if sdy > 0: e.y0 else: s.y0
      let my = if lo < hi: (lo + hi) / 2 else: (sy + ey) / 2
      return @[sx, sy, sx, my, ex, my, ex, ey]
  elif abs(offset) >= 1:
    if sideways:
      let x = if sdx > 0: max(sx, ex) + STUB else: min(sx, ex) - STUB
      return @[sx, sy, x, sy, x, ey, ex, ey]
    let y = if sdy > 0: max(sy, ey) + STUB else: min(sy, ey) - STUB
    return @[sx, sy, sx, y, ex, y, ex, ey]
  # The straight way is blocked by one of the two nodes: go between them, or around both.
  if sideways:
    let lane = if s.y1 + STUB <= e.y0: (s.y1 + e.y0) / 2 elif e.y1 + STUB <= s.y0: (e.y1 + s.y0) / 2
               else: max(s.y1, e.y1) + STUB
    return @[sx, sy, s1x, sy, s1x, lane, e1x, lane, e1x, ey, ex, ey]
  let lane = if s.x1 + STUB <= e.x0: (s.x1 + e.x0) / 2 elif e.x1 + STUB <= s.x0: (e.x1 + s.x0) / 2
             else: max(s.x1, e.x1) + STUB
  @[sx, sy, sx, s1y, lane, s1y, lane, e1y, ex, e1y, ex, ey]

func simplify(p: seq[float]): seq[float] =
  ## Drops repeated points and joins runs that continue in a straight line.
  result = @[p[0], p[1]]
  var i = 2
  while i < p.len:
    let x = p[i]
    let y = p[i + 1]
    i += 2
    let n = result.len
    let sameX = abs(x - result[n - 2]) < 0.01
    let sameY = abs(y - result[n - 1]) < 0.01
    if sameX and sameY: continue
    if n >= 4 and ((sameX and abs(result[n - 4] - result[n - 2]) < 0.01) or
                   (sameY and abs(result[n - 3] - result[n - 1]) < 0.01)):
      result[n - 2] = x
      result[n - 1] = y
    else:
      result.add x
      result.add y

proc pathData(p: seq[float], startTrim, endTrim: float): string =
  let n = p.len div 2
  var xs = newSeq[float](n)
  var ys = newSeq[float](n)
  for i in 0 ..< n:
    xs[i] = p[i * 2]
    ys[i] = p[i * 2 + 1]
  proc trim(at, toward: int, amount: float) =
    let len = hypot(xs[toward] - xs[at], ys[toward] - ys[at])
    let t = min(amount, max(0.0, len - 1))
    if len > 0 and t > 0:
      xs[at] += ((xs[toward] - xs[at]) / len) * t
      ys[at] += ((ys[toward] - ys[at]) / len) * t
  trim(0, 1, startTrim)
  trim(n - 1, n - 2, endTrim)
  result = "M" & num(xs[0]) & "," & num(ys[0])
  for i in 1 ..< n - 1:
    let before = hypot(xs[i] - xs[i - 1], ys[i] - ys[i - 1])
    let after = hypot(xs[i + 1] - xs[i], ys[i + 1] - ys[i])
    let r = min(CORNER, min(before / 2, after / 2))
    if r < 0.5:
      result.add "L" & num(xs[i]) & "," & num(ys[i])
      continue
    let inX = xs[i] - ((xs[i] - xs[i - 1]) / before) * r
    let inY = ys[i] - ((ys[i] - ys[i - 1]) / before) * r
    let outX = xs[i] + ((xs[i + 1] - xs[i]) / after) * r
    let outY = ys[i] + ((ys[i + 1] - ys[i]) / after) * r
    result.add "L" & num(inX) & "," & num(inY) & "Q" & num(xs[i]) & "," & num(ys[i]) & " " & num(outX) & "," & num(outY)
  result.add "L" & num(xs[n - 1]) & "," & num(ys[n - 1])

proc draw(model: ArchitectureDb, config: Config, options: RenderOptions, tight: bool): Rendered

proc renderArchitecture*(model: ArchitectureDb, config: Config, options: RenderOptions): Rendered =
  tighten(options, proc (tight: bool): Rendered = draw(model, config, options, tight))

proc draw(model: ArchitectureDb, config: Config, options: RenderOptions, tight: bool): Rendered =
  let iconSize = setting(config, "iconSize", 48, 8, 512)
  let size = setting(config, "fontSize", options.fontSize.get(16), 4, 128)
  let groupPad = min(setting(config, "padding", 20, 0, 256), (if tight: 12.0 else: Inf))
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  let half = iconSize / 2

  var nodes: seq[ArchNode]
  for n in model.nodes.values: nodes.add n
  var groups: seq[ArchGroup]
  for g in model.groups.values: groups.add g
  let N = nodes.len
  let G = groups.len
  let grid = placeOnGrid(nodes, groups, model.edges, model.layoutHints)
  var index = initTable[string, int]()
  for i, node in nodes: index[node.id] = i

  # A service is its icon square with the title beneath; a junction takes the same room.
  var labels = newSeq[Label](N)
  var boxW = newSeq[float](N)
  var boxH = newSeq[float](N)
  let wrap = if tight: max(iconSize, 64) else: max(iconSize * 2.25, 96)
  for i in 0 ..< N:
    let node = nodes[i]
    let label = layoutLabel((if not node.junction: node.title.get("") else: ""), true, measurer, size, wrap)
    labels[i] = label
    boxW[i] = max(iconSize, 2 * ceil(label.width / 2))
    boxH[i] = iconSize + (if label.height > 0: LABEL_GAP + label.height else: 0)

  var colValues, rowValues: seq[float]
  for i in 0 ..< N:
    colValues.add float(grid.col[i])
    rowValues.add float(grid.row[i])
  for g in 0 ..< G:
    if not grid.groupEmpty[g]: continue
    colValues.add float(grid.groupCol[g])
    rowValues.add float(grid.groupRow[g])
  let colOf = rank(colValues)
  let rowOf = rank(rowValues)
  let C = colOf.len
  let R = rowOf.len
  var colW = newSeq[float](C)
  var rowH = newSeq[float](R)
  let gap = if tight: max(24.0, 2 * STUB) else: max(40.0, jsRound(iconSize * 0.75))
  var gapX = newSeq[float](C)
  var gapY = newSeq[float](R)
  for c in 0 ..< C: gapX[c] = gap
  for r in 0 ..< R: gapY[r] = gap
  var nodeCol = newSeq[int](N)
  var nodeRow = newSeq[int](N)
  for i in 0 ..< N:
    let c = colOf[float(grid.col[i])]
    let r = rowOf[float(grid.row[i])]
    nodeCol[i] = c
    nodeRow[i] = r
    colW[c] = max(colW[c], boxW[i])
    rowH[r] = max(rowH[r], boxH[i])
  for g in 0 ..< G:
    if not grid.groupEmpty[g]: continue
    let c = colOf[float(grid.groupCol[g])]
    let r = rowOf[float(grid.groupRow[g])]
    colW[c] = max(colW[c], iconSize)
    rowH[r] = max(rowH[r], half)

  # An edge label needs the gap its edge crosses to be wide enough to hold it.
  let E = model.edges.len
  var edgeLabels = newSeq[Label](E)
  var ends = newSeq[int](E * 2)
  for k in 0 ..< E:
    let edge = model.edges[k]
    let a = index.getOrDefault(edge.lhsId, -1)
    let b = index.getOrDefault(edge.rhsId, -1)
    ends[k * 2] = a
    ends[k * 2 + 1] = b
    let label = layoutLabel(edge.title.get(""), true, measurer, small, 160)
    edgeLabels[k] = label
    if label.width == 0 or a < 0 or b < 0: continue
    if nodeCol[a] != nodeCol[b]:
      let c = min(nodeCol[a], nodeCol[b])
      gapX[c] = max(gapX[c], ceil(label.width) + 28)
    else:
      colW[nodeCol[a]] = max(colW[nodeCol[a]], 2 * ceil(label.width / 2) + 8)
      if nodeRow[a] != nodeRow[b]:
        let r = min(nodeRow[a], nodeRow[b])
        gapY[r] = max(gapY[r], ceil(label.height) + 24)

  # Room around each group, kept on the rows and columns at its edges. A group that shares an
  # edge with a group inside it stands that much further out. Children come after their parents,
  # so walking backwards settles every group before the one that holds it.
  var groupLabels = newSeq[Label](G)
  var c0 = newSeq[int](G)
  var c1 = newSeq[int](G)
  var r0 = newSeq[int](G)
  var r1 = newSeq[int](G)
  var insL = newSeq[float](G)
  var insR = newSeq[float](G)
  var insT = newSeq[float](G)
  var insB = newSeq[float](G)
  var headW = newSeq[float](G)
  var headH = newSeq[float](G)
  var colL = newSeq[float](C)
  var colR = newSeq[float](C)
  var rowT = newSeq[float](R)
  var rowB = newSeq[float](R)
  let badge = jsRound(size * 1.25)
  for g in 0 ..< G:
    c0[g] = colOf[float(grid.groupCol[g])]
    c1[g] = colOf[float(grid.groupCol[g] + grid.groupCols[g] - 1)]
    r0[g] = rowOf[float(grid.groupRow[g])]
    r1[g] = rowOf[float(grid.groupRow[g] + grid.groupRows[g] - 1)]
    let label = layoutLabel(groups[g].title.get(""), true, measurer, size,
                            (if tight: max(80.0, titleRoom(options) / 2) else: 320.0))
    groupLabels[g] = label
    let icon = if groups[g].icon.get("") != "": badge else: 0.0
    headW[g] = label.width + icon + (if label.width > 0 and icon > 0: 6 else: 0)
    headH[g] = max(label.height, icon)
  for g in countdown(G - 1, 0):
    let left = groupPad + insL[g]
    var right = groupPad + insR[g]
    let top = (if headH[g] > 0: max(groupPad, headH[g] + 12) else: groupPad) + insT[g]
    let bottom = groupPad + insB[g]
    if headW[g] > 0:
      var inner = left + right
      for c in c0[g] .. c1[g]:
        inner += colW[c] + (if c < c1[g]: colR[c] + gapX[c] + colL[c + 1] else: 0)
      if headW[g] + 20 > inner: right += ceil(headW[g] + 20 - inner)
    insL[g] = left
    insR[g] = right
    insT[g] = top
    insB[g] = bottom
    colL[c0[g]] = max(colL[c0[g]], left)
    colR[c1[g]] = max(colR[c1[g]], right)
    rowT[r0[g]] = max(rowT[r0[g]], top)
    rowB[r1[g]] = max(rowB[r1[g]], bottom)
    let p = grid.groupParent[g]
    if p < 0: continue
    if c0[p] == c0[g]: insL[p] = max(insL[p], left)
    if c1[p] == c1[g]: insR[p] = max(insR[p], right)
    if r0[p] == r0[g]: insT[p] = max(insT[p], top)
    if r1[p] == r1[g]: insB[p] = max(insB[p], bottom)

  var X = newSeq[float](C)
  var Y = newSeq[float](R)
  var innerW = 0.0
  for c in 0 ..< C:
    X[c] = innerW + colL[c]
    innerW = X[c] + colW[c] + colR[c] + (if c < C - 1: gapX[c] else: 0)
  var innerH = 0.0
  for r in 0 ..< R:
    Y[r] = innerH + rowT[r]
    innerH = Y[r] + rowH[r] + rowB[r] + (if r < R - 1: gapY[r] else: 0)
  # What is drawn, which an edge that has to go around a node can push past the grid.
  var minX = 0.0
  var minY = 0.0
  var maxX = innerW
  var maxY = innerH

  proc left(g: int): float = X[c0[g]] - insL[g]
  proc right(g: int): float = X[c1[g]] + colW[c1[g]] + insR[g]
  proc top(g: int): float = Y[r0[g]] - insT[g]
  proc bottom(g: int): float = Y[r1[g]] + rowH[r1[g]] + insB[g]
  proc centerX(i: int): float = X[nodeCol[i]] + colW[nodeCol[i]] / 2

  proc port(i, side: int, viaGroup: bool): Port =
    let dx = DX[side]
    let dy = DY[side]
    let cx = centerX(i)
    let y = Y[nodeRow[i]]
    var p = Port(x: cx, y: y + half, dx: dx, dy: dy, x0: cx - boxW[i] / 2, y0: y, x1: cx + boxW[i] / 2,
                 y1: y + boxH[i], gap: 0, wire: false)
    if nodes[i].junction:
      p.x0 = cx
      p.x1 = cx
      p.y0 = p.y
      p.y1 = p.y
      p.gap = DOT
    elif dx != 0:
      p.x = cx + dx * half
    else:
      p.y = if dy < 0: y else: y + boxH[i] + (if labels[i].height > 0: 2 else: 0)
    let g = if viaGroup: grid.nodeParent[i] else: -1
    if g >= 0:
      p.x0 = left(g)
      p.x1 = right(g)
      p.y0 = top(g)
      p.y1 = bottom(g)
      p.gap = 0
      p.wire = nodes[i].junction
      if dx != 0: p.x = (if dx < 0: p.x0 else: p.x1)
      else: p.y = (if dy < 0: p.y0 else: p.y1)
    p

  var edgesOut = ""
  var labelsOut = ""
  # Vertical runs of the edges, to keep group titles out from under them.
  var runs: seq[float]
  let trimLength = markerTrim("arrow_point")
  for k in 0 ..< E:
    let edge = model.edges[k]
    let a = ends[k * 2]
    let b = ends[k * 2 + 1]
    if a < 0 or b < 0: continue
    var s = port(a, sideIndex(edge.lhsDir), edge.lhsGroup)
    var e = port(b, sideIndex(edge.rhsDir), edge.rhsGroup)
    if s.x == e.x and s.y == e.y and s.dx == e.dx:
      # An edge from a side back to the same side: part the two ends so it shows as a loop.
      s.x -= 8 * abs(s.dy)
      s.y -= 8 * abs(s.dx)
      e.x += 8 * abs(s.dy)
      e.y += 8 * abs(s.dx)
    var routed = route(s, e)
    if s.wire: routed = @[centerX(a), Y[nodeRow[a]] + half] & routed
    if e.wire: routed.add @[centerX(b), Y[nodeRow[b]] + half]
    let points = simplify(routed)
    if points.len < 4: continue
    let id = escText(edge.lhsId & "-" & edge.rhsId)
    edgesOut.add "<g class=\"pele-edge\" data-id=\"" & id & "\">" &
      "<path d=\"" & pathData(points, (if edge.lhsInto and not s.wire: trimLength + s.gap else: 0),
                              (if edge.rhsInto and not e.wire: trimLength + e.gap else: 0)) & "\"/>" &
      (if edge.lhsInto: marker("arrow_point", s.x + s.dx * s.gap, s.y + s.dy * s.gap, -s.dx, -s.dy, "var(--_l)") else: "") &
      (if edge.rhsInto: marker("arrow_point", e.x + e.dx * e.gap, e.y + e.dy * e.gap, -e.dx, -e.dy, "var(--_l)") else: "") &
      "</g>"
    var best = -1
    var bestLength = -1.0
    var flat = -1
    var flatLength = -1.0
    let label = edgeLabels[k]
    var i = 0
    while i < points.len:
      minX = min(minX, points[i] - 4)
      maxX = max(maxX, points[i] + 4)
      minY = min(minY, points[i + 1] - 4)
      maxY = max(maxY, points[i + 1] + 4)
      i += 2
    i = 0
    while i + 3 < points.len:
      let horizontal = abs(points[i + 1] - points[i + 3]) < 0.01
      let length = abs(points[i] - points[i + 2]) + abs(points[i + 1] - points[i + 3])
      if not horizontal: runs.add @[points[i], min(points[i + 1], points[i + 3]), max(points[i + 1], points[i + 3])]
      if length > bestLength:
        best = i
        bestLength = length
      if horizontal and length > flatLength:
        flat = i
        flatLength = length
      i += 2
    if label.width > 0:
      let at = if flatLength >= label.width + 8: flat else: best
      var x = (points[at] + points[at + 2]) / 2
      var y = (points[at + 1] + points[at + 3]) / 2
      let w = label.width + 8
      let upright = abs(points[at] - points[at + 2]) < 0.01
      # On a short run next to a node the label would land on the node, so it moves off to the side.
      for p in [s, e]:
        if x + w / 2 <= p.x0 or x - w / 2 >= p.x1 or y + label.height / 2 <= p.y0 or y - label.height / 2 >= p.y1: continue
        if upright: x = (if x >= (p.x0 + p.x1) / 2: p.x1 + w / 2 + 4 else: p.x0 - w / 2 - 4)
        else: y = (if y >= (p.y0 + p.y1) / 2: p.y1 + label.height / 2 + 4 else: p.y0 - label.height / 2 - 4)
      minX = min(minX, x - w / 2)
      maxX = max(maxX, x + w / 2)
      minY = min(minY, y - label.height / 2)
      maxY = max(maxY, y + label.height / 2)
      labelsOut.add edgeLabelSvg(edge.lhsId & "-" & edge.rhsId, label, x, y, "", icons)

  var clusters = ""
  for g in 0 ..< G:
    let group = groups[g]
    let x = left(g)
    let y = top(g)
    let w = right(g) - x
    let label = groupLabels[g]
    var head = ""
    if headW[g] > 0:
      # The title starts at the left, or after the edges that come down through that corner.
      let band = y + headH[g] + 12
      var crossings: seq[float]
      var i = 0
      while i < runs.len:
        if runs[i + 1] < band and runs[i + 2] > y and runs[i] > x and runs[i] < x + w: crossings.add runs[i]
        i += 3
      crossings.sort(proc (a, b: float): int = cmp(a, b))
      crossings.add x + w - 4
      var start = x + 10
      for crossing in crossings:
        if crossing - 6 - start >= headW[g]: break
        start = max(start, crossing + 6)
      if start + headW[g] > x + w - 4: start = x + 10
      let cy = y + 6 + headH[g] / 2
      var textX = start
      if group.icon.get("") != "":
        head.add iconSlot(group.icon.get, start, cy - badge / 2, badge, icons)
        textX += badge + 6
      head.add labelSvg(label, textX + label.width / 2, cy, " class=\"pele-cluster-label\" fill=\"var(--_m)\"", icons)
    clusters.add "<g class=\"pele-cluster\" data-id=\"" & escText(group.id) & "\">" &
      "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(w) & "\" height=\"" & num(bottom(g) - y) &
      "\" fill=\"var(--_a)\" fill-opacity=\"0.5\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
      head & "</g>"

  var nodesOut = ""
  let glyph = iconSize * 0.5
  let textSize = max(6.0, jsRound(size * 0.75))
  for i in 0 ..< N:
    let node = nodes[i]
    let at = "data-id=\"" & escText(node.id) & "\" transform=\"translate(" & num(centerX(i)) & "," & num(Y[nodeRow[i]]) & ")\""
    if node.junction:
      nodesOut.add "<g class=\"pele-node pele-junction\" " & at & "><circle cy=\"" & num(half) & "\" r=\"" & jsString(DOT) &
        "\" fill=\"var(--_l)\"/></g>"
      continue
    var inner = ""
    if node.icon.get("") != "":
      inner = iconSlot(node.icon.get, -glyph / 2, (iconSize - glyph) / 2, glyph, icons)
    elif node.iconText.get("") != "":
      let text = layoutLabel(node.iconText.get, false, measurer, textSize, iconSize - 8)
      let lines = max(1, int(floor((iconSize - 4) / (if text.lineHeight != 0: text.lineHeight else: 1))))
      inner = labelSvg(fit(text, iconSize - 8, lines, measurer), 0, half,
                       " class=\"pele-icon-text\" font-size=\"" & jsString(textSize) & "\"", icons)
    nodesOut.add "<g class=\"pele-node pele-service\" " & at & ">" &
      "<rect x=\"" & num(-half) & "\" width=\"" & num(iconSize) & "\" height=\"" & num(iconSize) &
      "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
      inner &
      labelSvg(labels[i], 0, iconSize + LABEL_GAP + labels[i].height / 2, " class=\"pele-label\"", icons) &
      "</g>"

  let title = layoutLabel(model.title, false, measurer, size, (if tight: titleRoom(options) else: 4000.0), Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let width = ceil(max(maxX - minX, title.width) + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)
  let ox = jsRound((width - (maxX - minX)) / 2 - minX)
  let oy = jsRound(pad + titleHeight - minY)
  let body =
    (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
    (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
       edgesOut & "</g>" else: "") &
    (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\">" & labelsOut & "</g>" else: "") &
    (if nodesOut != "": "<g class=\"pele-nodes\">" & nodesOut & "</g>" else: "")
  let svg = svgDocument("architecture", width, height, size, options,
    Accessible(accTitle: model.accTitle, accDescr: model.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if body != "": "<g transform=\"translate(" & jsString(ox) & "," & jsString(oy) & ")\">" & body & "</g>" else: ""))
  Rendered(svg: svg, width: width, height: height, links: @[])

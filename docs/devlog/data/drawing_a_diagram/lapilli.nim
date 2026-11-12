## Lapilli: a toy diagram renderer, for the post *Drawing a diagram from scratch*.
##
## Lapilli are the little stones a volcano throws: this is a very small Pele. It reads a tiny
## subset of Mermaid's flowchart and draws it as SVG, with the same stages as Pele (lex, parse,
## measure, lay out, write) and none of the care. It is ours, not a port, and stays out of src/.
##
##   flowchart TD
##   idea[An idea] --> sketch --> diagram[A diagram]
##   idea --> diagram
##
## A line is a chain of nodes joined by `-->`. A node is a name, optionally followed by its text
## in square brackets; a name without text shows itself.
import std/[algorithm, math, sequtils, strutils, tables, unicode]

# ---------------------------------------------------------------------------------- 1. lexing

type
  TokenKind* = enum
    tkHeader = "header", tkName = "name", tkText = "text", tkArrow = "arrow",
    tkNewline = "newline", tkEnd = "end"
  Token* = object
    kind*: TokenKind
    text*: string
    line*, col*: int       ## where it starts, both from 1
  LapilliError* = object of ValueError

proc fail(line, col: int, msg: string) {.noreturn.} =
  raise newException(LapilliError, "line " & $line & ", column " & $col & ": " & msg)

proc lex*(src: string): seq[Token] =
  ## Cuts the text into tokens. One pass, left to right, looking at one character at a time,
  ## which is all a lexer is.
  var i = 0
  var line = 1
  var lineStart = 0
  template col: int = i - lineStart + 1
  template add(k: TokenKind, t: string, at: int) =
    result.add Token(kind: k, text: t, line: line, col: at - lineStart + 1)
  while i < src.len:
    let c = src[i]
    if c == '\n':
      add(tkNewline, "\n", i)
      inc i
      inc line
      lineStart = i
    elif c in {' ', '\t', '\r'}:
      inc i
    elif c == '%' and i + 1 < src.len and src[i + 1] == '%':
      while i < src.len and src[i] != '\n': inc i    # a comment, to the end of the line
    elif src.continuesWith("-->", i):
      add(tkArrow, "-->", i)
      i += 3
    elif c == '[':
      let start = i
      inc i
      while i < src.len and src[i] notin {']', '\n'}: inc i
      if i >= src.len or src[i] != ']': fail(line, start - lineStart + 1, "a `[` without its `]`")
      add(tkText, src[start + 1 ..< i].strip, start)
      inc i
    elif c in IdentChars:
      let start = i
      while i < src.len and src[i] in IdentChars: inc i
      let word = src[start ..< i]
      add(if result.len == 0 and word == "flowchart": tkHeader else: tkName, word, start)
    else:
      fail(line, col, "unexpected `" & $c & "`")
  result.add Token(kind: tkEnd, text: "", line: line, col: col)

# --------------------------------------------------------------------------------- 2. parsing

type
  Node* = object
    name*, label*: string
  Edge* = object
    tail*, head*: int      ## indexes into `nodes`, in the order written
  Model* = object
    direction*: string
    nodes*: seq[Node]
    edges*: seq[Edge]

proc parse*(tokens: seq[Token]): Model =
  ## Recursive descent: one procedure per rule of the grammar, each taking the tokens its rule
  ## needs and calling the procedures of the rules inside it.
  ##
  ##   diagram   = "flowchart" direction? newline* (statement newline*)* end
  ##   statement = node ("-->" node)*
  ##   node      = name text?
  var p = 0
  var model: Model
  var index = initTable[string, int]()
  template peek: Token = tokens[p]
  proc expect(kind: TokenKind, what: string): Token =
    if tokens[p].kind != kind:
      fail(tokens[p].line, tokens[p].col, "expected " & what & ", found " & $tokens[p].kind)
    result = tokens[p]
    inc p

  proc node(): int =
    let name = expect(tkName, "a node name").text
    var label = ""
    if peek.kind == tkText:
      label = peek.text
      inc p
    if name notin index:
      index[name] = model.nodes.len
      model.nodes.add Node(name: name, label: if label.len > 0: label else: name)
    elif label.len > 0:
      model.nodes[index[name]].label = label
    index[name]

  discard expect(tkHeader, "`flowchart`")
  model.direction = "TD"
  if peek.kind == tkName and peek.text in ["TD", "TB", "LR"]:
    model.direction = peek.text
    inc p
  while peek.kind != tkEnd:
    if peek.kind == tkNewline:
      inc p
      continue
    var tail = node()
    while peek.kind == tkArrow:
      inc p
      let head = node()
      model.edges.add Edge(tail: tail, head: head)
      tail = head
    if peek.kind notin {tkNewline, tkEnd}:
      fail(peek.line, peek.col, "expected `-->` or the end of the line, found " & $peek.kind)
  model

# -------------------------------------------------------------------------------- 3. measuring

const
  # Arial's advance widths for ' ' to '~', in thousandths of an em, two base-36 digits each:
  # the table of Pele's metrics measurer (src/text/metrics.ts, MIT, (c) kepano).
  Regular = "7q7q9vfgfgopij5b9999atg87q997q7qfgfgfgfgfgfgfgfgfgfg7q7qg8g8g8fgs7ijijk2k2ijgzlmk27qdwijfgn5k2lmijlmk2ijgzk2ijq8ijijgz7q7q7qd1fg99fgfgdwfgfg7qfgfg6666dw66n5fgfgfgfg99dw7qfgdwk2dwdwdw9a789ag8"
  FontSize* = 16.0
  PadX* = 16.0
  PadY* = 10.0

proc base36(c: char): int =
  if c in '0'..'9': ord(c) - ord('0') else: ord(c) - ord('a') + 10

let advance = toSeq(0 ..< 95).mapIt(base36(Regular[2*it]) * 36 + base36(Regular[2*it + 1]))

proc textWidth*(text: string, size = FontSize): float =
  ## How wide `text` is in Arial, without asking a browser. Characters outside ASCII get a
  ## guess, as in Pele (which also counts in UTF-16; Lapilli counts characters).
  var units = 0
  for r in text.runes:
    let c = int(r)
    units += (if c in 32..126: advance[c - 32] elif c >= 0x2e80: 1000 else: 580)
  units.float * size / 1000

proc boxSize*(label: string): (float, float) =
  (textWidth(label) + 2 * PadX, FontSize * 1.5 + 2 * PadY)

# ------------------------------------------------------------------------------ 4. laying out

const
  NodeSep* = 24.0   ## between two boxes of one rank
  RankSep* = 48.0   ## between two ranks
  DummyWidth = 8.0  ## a bend of a long edge takes some room in its rank

type
  Layout* = object
    ## Every box of the drawing, real or dummy. Dummies are the points where an edge that spans
    ## several ranks crosses the ranks between its ends; they come after the real nodes.
    w*, h*, x*, y*: seq[float]
    rank*: seq[int]
    real*: int
    ranks*: seq[seq[int]]          ## the boxes of each rank, left to right
    reversed*: seq[bool]           ## per edge: drawn against the flow, to break a cycle
    chains*: seq[seq[int]]         ## per edge: its boxes from tail to head, dummies between
    width*, height*: float

proc breakCycles*(m: Model): seq[bool] =
  ## A layered layout needs every edge to point down. Depth-first search from each node in the
  ## order written; an edge back to a node still on the stack closes a cycle, and is turned round.
  var reversed = newSeq[bool](m.edges.len)
  var state = newSeq[int](m.nodes.len)        # 0 not seen, 1 on the stack, 2 done
  proc visit(v: int) =
    state[v] = 1
    for e, edge in m.edges:
      if edge.tail != v: continue
      if state[edge.head] == 1: reversed[e] = true
      elif state[edge.head] == 0: visit(edge.head)
    state[v] = 2
  for v in 0 ..< m.nodes.len:
    if state[v] == 0: visit(v)
  reversed

proc assignRanks*(m: Model, reversed: seq[bool]): seq[int] =
  ## Longest path: a node goes one rank below the lowest of the nodes that point to it.
  ## Repeat until nothing moves (there are no cycles left, so this ends).
  result = newSeq[int](m.nodes.len)
  var changed = true
  while changed:
    changed = false
    for e, edge in m.edges:
      let (a, b) = if reversed[e]: (edge.head, edge.tail) else: (edge.tail, edge.head)
      if a == b: continue
      if result[b] < result[a] + 1:
        result[b] = result[a] + 1
        changed = true

proc crossings*(lay: Layout, edges: seq[(int, int)]): int =
  ## Two segments between the same two ranks cross when their ends are in opposite order.
  var pos = newSeq[int](lay.w.len)
  for row in lay.ranks:
    for i, v in row: pos[v] = i
  for i in 0 ..< edges.len:
    for j in i + 1 ..< edges.len:
      let (a, b) = edges[i]
      let (c, d) = edges[j]
      if lay.rank[a] != lay.rank[c]: continue
      if (pos[a] - pos[c]) * (pos[b] - pos[d]) < 0: inc result

proc segments*(lay: Layout): seq[(int, int)] =
  ## Every chain cut into rank-to-rank pieces, upper end first.
  for chain in lay.chains:
    for i in 0 ..< chain.len - 1:
      let (a, b) = (chain[i], chain[i + 1])
      result.add(if lay.rank[a] < lay.rank[b]: (a, b) else: (b, a))

proc orderRanks*(lay: var Layout, sweeps = 4): seq[int] =
  ## The barycenter heuristic: put each box at the average position of its neighbours in the rank
  ## above (sweeping down), then below (sweeping up). Keep the best order seen. Returns the
  ## number of crossings after each sweep, the first being the order as written.
  let segs = lay.segments
  var best = lay.ranks
  var bestCount = lay.crossings(segs)
  result.add bestCount
  for sweep in 0 ..< sweeps:
    let down = sweep mod 2 == 0
    var pos = newSeq[float](lay.w.len)
    for row in lay.ranks:
      for i, v in row: pos[v] = i.float
    let order = if down: toSeq(1 ..< lay.ranks.len) else: toSeq(countdown(lay.ranks.len - 2, 0))
    for r in order:
      var bary = initTable[int, float]()
      for v in lay.ranks[r]:
        var sum, n = 0.0
        for (a, b) in segs:
          let other = if down and b == v: a elif not down and a == v: b else: -1
          if other >= 0:
            sum += pos[other]
            n += 1
        bary[v] = if n > 0: sum / n else: pos[v]   # no neighbour: stay put
      lay.ranks[r].sort(proc (a, b: int): int = cmp(bary[a], bary[b]))   # stable
      for i, v in lay.ranks[r]: pos[v] = i.float
    let count = lay.crossings(segs)
    result.add count
    if count < bestCount:
      best = lay.ranks
      bestCount = count
  lay.ranks = best

proc placeX*(lay: var Layout, rounds = 8) =
  ## Pack each rank from the left, then let every box slide toward the average x of its
  ## neighbours, as far as the boxes beside it allow. A simple stand-in for Brandes-Köpf.
  let segs = lay.segments
  for row in lay.ranks:
    var x = 0.0
    for v in row:
      lay.x[v] = x + lay.w[v] / 2
      x += lay.w[v] + NodeSep
  for round in 0 ..< rounds:
    for row in lay.ranks:
      for i, v in row:
        var sum, n = 0.0
        for (a, b) in segs:
          if a == v: (sum += lay.x[b]; n += 1)
          if b == v: (sum += lay.x[a]; n += 1)
        if n == 0: continue
        var want = sum / n
        if i > 0:
          let left = row[i - 1]
          want = max(want, lay.x[left] + (lay.w[left] + lay.w[v]) / 2 + NodeSep)
        if i < row.len - 1:
          let right = row[i + 1]
          want = min(want, lay.x[right] - (lay.w[right] + lay.w[v]) / 2 - NodeSep)
        lay.x[v] = want
  var lo = Inf
  var hi = -Inf
  for v in 0 ..< lay.w.len:
    lo = min(lo, lay.x[v] - lay.w[v] / 2)
    hi = max(hi, lay.x[v] + lay.w[v] / 2)
  for v in 0 ..< lay.w.len: lay.x[v] -= lo
  lay.width = hi - lo

proc layout*(m: Model, sweeps = 4): Layout =
  ## The whole layered layout: cycles, ranks, dummies, order, x, then y. `sweeps = 0` keeps
  ## every rank in the order the nodes were written, to see what ordering does.
  result.real = m.nodes.len
  for node in m.nodes:
    let (w, h) = boxSize(node.label)
    result.w.add w
    result.h.add h
  result.reversed = breakCycles(m)
  result.rank = assignRanks(m, result.reversed)
  for e, edge in m.edges:
    # an edge over several ranks gets a dummy box in every rank it crosses
    var chain = @[edge.tail]
    let (r0, r1) = (result.rank[edge.tail], result.rank[edge.head])
    let step = if r1 > r0: 1 else: -1
    if abs(r1 - r0) > 1:
      var r = r0 + step
      while r != r1:
        result.w.add DummyWidth
        result.h.add 0
        result.rank.add r
        chain.add result.w.len - 1
        r += step
    chain.add edge.head
    result.chains.add chain
  let n = result.w.len
  result.x = newSeq[float](n)
  result.y = newSeq[float](n)
  result.ranks = newSeq[seq[int]](max(result.rank) + 1)
  for v in 0 ..< n: result.ranks[result.rank[v]].add v
  discard result.orderRanks(sweeps)
  result.placeX()
  var top = 0.0
  for row in result.ranks:
    let tall = row.mapIt(result.h[it]).max
    for v in row: result.y[v] = top + tall / 2
    top += tall + RankSep
  result.height = top - RankSep

# ------------------------------------------------------------------------------- 5. writing SVG

proc num*(x: float): string =
  ## A coordinate with at most two decimals and no trailing zeros, as Pele writes them.
  let n = floor(x * 100 + 0.5)
  if n == 0: return "0"
  result = formatFloat(n / 100, ffDecimal, 2)
  result.trimZeros()
  if result.endsWith('.'): result.setLen(result.len - 1)

proc esc*(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

proc svg*(m: Model, lay: Layout, pad = 8.0): string =
  ## Writes the drawing: boxes, then edges as polylines through their dummies, ending in an
  ## arrowhead. Colours come from the page (`currentColor`), so the drawing follows its theme.
  let w = ceil(lay.width + 2 * pad)
  let h = ceil(lay.height + 2 * pad)
  result = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " & num(w) & " " & num(h) &
    "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\" font-family=\"Arial, sans-serif\" font-size=\"" &
    num(FontSize) & "\" fill=\"none\" stroke=\"currentColor\">" &
    "<defs><marker id=\"lapilli-arrow\" viewBox=\"0 0 10 10\" refX=\"10\" refY=\"5\" markerWidth=\"8\" " &
    "markerHeight=\"8\" orient=\"auto-start-reverse\"><path d=\"M0,0L10,5L0,10Z\" fill=\"currentColor\" " &
    "stroke=\"none\"/></marker></defs>"
  for e, chain in lay.chains:
    var points: seq[string]
    for i, v in chain:
      var y = lay.y[v] + pad
      if i == 0: y += (if lay.rank[chain[1]] > lay.rank[v]: lay.h[v] / 2 else: -lay.h[v] / 2)
      if i == chain.len - 1: y += (if lay.rank[chain[^2]] < lay.rank[v]: -lay.h[v] / 2 else: lay.h[v] / 2)
      points.add num(lay.x[v] + pad) & "," & num(y)
    result.add "<polyline points=\"" & points.join(" ") & "\" marker-end=\"url(#lapilli-arrow)\"/>"
  for v, node in m.nodes:
    let (x, y) = (lay.x[v] + pad, lay.y[v] + pad)
    result.add "<rect x=\"" & num(x - lay.w[v] / 2) & "\" y=\"" & num(y - lay.h[v] / 2) & "\" width=\"" &
      num(lay.w[v]) & "\" height=\"" & num(lay.h[v]) & "\" rx=\"4\"/>"
    result.add "<text x=\"" & num(x) & "\" y=\"" & num(y + FontSize * 0.35) &
      "\" text-anchor=\"middle\" fill=\"currentColor\" stroke=\"none\">" & esc(node.label) & "</text>"
  result.add "</svg>"

proc render*(src: string, sweeps = 4): string =
  ## Text in, SVG out: the five stages in a row.
  let model = parse(lex(src))
  svg(model, layout(model, sweeps))

when isMainModule:
  echo render("flowchart TD\nidea[An idea] --> sketch --> diagram[A diagram]\nidea --> diagram\n")

## port-of: src/diagrams/sequence/render.ts
## port-status: draft
##
## Port notes: Pele's closures over the drawing's state (`layout`, `extend`, `need`, `backed`...)
## are nested procs over the same locals. `STYLES` is an array of `Option[LineStyle]`. A fill that
## is `undefined` is "" (Pele tests it for truthiness only).
import std/[options, tables, algorithm, sets, json]
from std/math import floor, ceil
import ../../preprocess
import ../../svg/[builder, edges, ink, root, theme, title]
import ../../text/[label, measurer]
import ../../types
import ../../util/yaml
import ../../js
import ../common/[literal_label, fit_width]
import actors, db, types as stypes

const
  Head_None = 0
  Head_Arrow = 1
  Head_Cross = 2
  Head_Open = 3
  Head_HalfSolid = 4
  Head_HalfStick = 5

type LineStyle = object
  dotted: bool
  head: int
  atStart: bool
    ## Where the heads are: at the receiver, at the sender only (the reverse arrows), or at both.
  atEnd: bool
  bottom: bool

const STYLES = block:
  var s: array[LINETYPE_STICK_ARROW_BOTTOM_REVERSE_DOTTED + 1, Option[LineStyle]]
  proc style(s: var array[LINETYPE_STICK_ARROW_BOTTOM_REVERSE_DOTTED + 1, Option[LineStyle]],
             kind: int, dotted: bool, head: int, ends = 1, bottom = false) =
    s[kind] = some(LineStyle(dotted: dotted, head: head, atStart: ends != 1, atEnd: ends != 0, bottom: bottom))
  style(s, LINETYPE_SOLID, false, Head_Arrow)
  style(s, LINETYPE_DOTTED, true, Head_Arrow)
  style(s, LINETYPE_SOLID_CROSS, false, Head_Cross)
  style(s, LINETYPE_DOTTED_CROSS, true, Head_Cross)
  style(s, LINETYPE_SOLID_OPEN, false, Head_None)
  style(s, LINETYPE_DOTTED_OPEN, true, Head_None)
  style(s, LINETYPE_SOLID_POINT, false, Head_Open)
  style(s, LINETYPE_DOTTED_POINT, true, Head_Open)
  style(s, LINETYPE_BIDIRECTIONAL_SOLID, false, Head_Arrow, 2)
  style(s, LINETYPE_BIDIRECTIONAL_DOTTED, true, Head_Arrow, 2)
  for dotted in [false, true]:
    let d = if dotted: 10 else: 0
    style(s, LINETYPE_SOLID_TOP + d, dotted, Head_HalfSolid)
    style(s, LINETYPE_SOLID_BOTTOM + d, dotted, Head_HalfSolid, 1, true)
    style(s, LINETYPE_STICK_TOP + d, dotted, Head_HalfStick)
    style(s, LINETYPE_STICK_BOTTOM + d, dotted, Head_HalfStick, 1, true)
    style(s, LINETYPE_SOLID_ARROW_TOP_REVERSE + d, dotted, Head_HalfSolid, 0)
    style(s, LINETYPE_SOLID_ARROW_BOTTOM_REVERSE + d, dotted, Head_HalfSolid, 0, true)
    style(s, LINETYPE_STICK_ARROW_TOP_REVERSE + d, dotted, Head_HalfStick, 0)
    style(s, LINETYPE_STICK_ARROW_BOTTOM_REVERSE + d, dotted, Head_HalfStick, 0, true)
  s

const FRAME_KIND = {
  LINETYPE_LOOP_START: "loop",
  LINETYPE_ALT_START: "alt",
  LINETYPE_OPT_START: "opt",
  LINETYPE_PAR_START: "par",
  LINETYPE_PAR_OVER_START: "par",
  LINETYPE_CRITICAL_START: "critical",
  LINETYPE_BREAK_START: "break",
  LINETYPE_RECT_START: "rect",
}.toTable

const
  MSG_PAD = 12.0
  SELF_W = 28.0
  SELF_H = 22.0
  ACT_W = 10.0
  ACT_STEP = 4.0
  ACT_MIN = 14.0
  NOTE_GAP = 10.0
  NOTE_OVER = 16.0
  FRAME_PAD = 20.0
  FRAME_NEST = 10.0
  TAB_H = 20.0
  FRAME_TEXT = 240.0
  BADGE_H = 16.0
  CENTRAL_R = 4.0
  DASH = " stroke-dasharray=\"4 4\""

type Numbering* = object
  index*: seq[float]
    ## The number each message line carries, whether or not it is shown. NaN for everything else.
  shown*: seq[bool]
  visible*: bool
    ## Whether numbers are on after the last statement.

func isLineMessage*(kind: int): bool =
  kind >= 0 and kind < STYLES.len and STYLES[kind].isSome

func numberMessages*(messages: seq[SeqMessage], always: bool): Numbering =
  ## Counts message lines the way Mermaid's renderer does while it draws.
  var index = newSeq[float](messages.len)
  var shown = newSeq[bool](messages.len)
  var current = 1.0
  var step = 1.0
  var visible = false
  for i in 0 ..< messages.len:
    let m = messages[i]
    index[i] = NaN
    shown[i] = false
    if m.kind == LINETYPE_AUTONUMBER:
      let spec = m.numbering
      # spec.start || current: undefined, NaN and 0 fall back
      if not (spec.start == 0 or spec.start != spec.start): current = spec.start
      if not (spec.step == 0 or spec.step != spec.step): step = spec.step
      visible = spec.visible
    elif isLineMessage(m.kind):
      index[i] = current
      shown[i] = visible or always
      current = jsRound((current + step) * 100) / 100
  Numbering(index: index, shown: shown, visible: visible)

type
  Column = ref object
    id: string
    actor: SeqActor
    kind: string
    label: Label
    size: ActorSize
    x: float
    createAt: int
    destroyAt: int
    top: float
    lifeStart: float
    lifeEnd: float
    activations: seq[float]

const
  V_Line = 0
  V_Self = 1
  V_Note = 2

type
  View = ref object
    kind: int
    a, b: int
    label: Label
    x, w: float

  Frame = ref object
    kind: string
    x0, x1: float
    top: float
    title: Label
    tabW: float
    fill: string
    dividers: seq[int]
    dividerY: seq[float]
    dividerLabels: seq[Label]

  BoxRun = ref object
    box: SeqBox
    first, last: int
    title: Label
    grow: float

let NO_LABEL = Label()

proc option(conf: YamlValue, key: string, fallback: float): float =
  let value = conf[key]
  if value != nil and value.kind == yNumber and value.n >= 0 and value.n <= 2000: value.n else: fallback

proc half(x, y, dir, up: float, stick: bool, color: string): string =
  let bx = num(x - dir * ARROW)
  if stick: return "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & bx & "," & num(y + up * 5) & "\"/>"
  "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & bx & "," & num(y + up * 4.5) & "V" & num(y) &
    "Z\" fill=\"" & color & "\" stroke=\"none\"/>"

proc head(kind: int, x, y, dir, up: float, color: string): string =
  ## Draws the head whose tip is at (x, y) and points along dir. `up` is the side a half head sits on.
  case kind
  of Head_Arrow: marker("arrow_point", x, y, dir, 0, color)
  of Head_Cross: marker("arrow_cross", x, y, dir, 0, color)
  of Head_Open:
    "<path class=\"pele-marker\" d=\"M" & num(x - dir * ARROW) & "," & num(y - 4.5) & "L" & num(x) & "," & num(y) &
      "L" & num(x - dir * ARROW) & "," & num(y + 4.5) & "\" stroke-linejoin=\"round\"/>"
  of Head_HalfSolid: half(x, y, dir, up, false, color)
  of Head_HalfStick: half(x, y, dir, up, true, color)
  else: ""

func trim(kind: int): float =
  if kind == Head_Arrow: ARROW - 1 elif kind == Head_Cross: 4 else: 0

func reversedJoin(parts: seq[string]): string =
  for k in countdown(parts.len - 1, 0): result.add parts[k]

proc draw(db: SeqDb, config: Config, options: RenderOptions, tight: bool, hold = 0.0, byNeed = true): Rendered

proc renderSequence*(db: SeqDb, config: Config, options: RenderOptions): Rendered =
  tighten(options, proc (tight: bool): Rendered = draw(db, config, options, tight))

proc draw(db: SeqDb, config: Config, options: RenderOptions, tight: bool, hold = 0.0, byNeed = true): Rendered =
  let conf = config["sequence"]
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.75)
  let measurer = measurerOf(options)
  let monospaced = "messages" in options.monospace
  let messageMeasurer = if monospaced:
      TextMeasurer(width: proc (t: string, s: float, style: int): float = measurer.width(t, s, style or Mono))
    else: measurer
  let icons = options.icons
  let pad = options.padding.get(8)
  let mirrorV = conf["mirrorActors"]
  let mirror = not (mirrorV != nil and mirrorV.kind == yBool and not mirrorV.b)
  let rightV = conf["rightAngles"]
  let rightAngles = rightV != nil and rightV.kind == yBool and rightV.b
  let actorMargin = min(option(conf, "actorMargin", 40), if tight: 8.0 else: Inf)
  let minW = min(option(conf, "width", 64), if tight: 48.0 else: Inf)
  let minH = option(conf, "height", jsRound(size * 1.5) + 20)
  let wrapW = min(option(conf, "width", 160),
                  if tight: max(32.0, (options.maxWidth.get(320) - 2 * pad) / max(1.0, float(db.actors.len)) -
                                actorMargin - 24)
                  else: Inf)
  # Mermaid's default of 35 corresponds to Pele's default gap. Other values move it by the difference.
  let msgGap = max(4.0, 14 + option(conf, "messageMargin", 35) - 35)
  let notePad = min(option(conf, "noteMargin", 10), if tight: 6.0 else: Inf)
  let boxPad = min(option(conf, "boxMargin", 10), if tight: 6.0 else: Inf)
  let alignV = conf["messageAlign"]
  let align = if alignV != nil and alignV.kind == yString and alignV.s == "left": -1.0
              elif alignV != nil and alignV.kind == yString and alignV.s == "right": 1.0
              else: 0.0

  let msgPad = if tight: 6.0 else: MSG_PAD
  let noteOver = if tight: 8.0 else: NOTE_OVER
  let framePad = if tight: 12.0 else: FRAME_PAD
  let frameNest = if tight: 6.0 else: FRAME_NEST
  let messages = db.messages
  let count = messages.len
  let showV = conf["showSequenceNumbers"]
  let numbering = numberMessages(messages, showV != nil and showV.kind == yBool and showV.b)
  proc text(raw: string, fontSize: float, wrap: bool, width = wrapW, by = measurer): Label =
    let label = layoutLabel(raw, false, by, fontSize, if tight or wrap: width else: Inf)
    if tight: breakLabel(label, by, max(120.0, width)) else: label
  proc messageText(raw: string, wrap: bool, width = wrapW): Label = text(raw, small, wrap, width, messageMeasurer)

  var hasUsed = false
  var used: HashSet[string]
  let hideV = conf["hideUnusedParticipants"]
  if hideV != nil and hideV.kind == yBool and hideV.b:
    hasUsed = true
    for m in messages:
      if m.start.isSome: used.incl m.start.get
      if m.to.isSome: used.incl m.to.get

  var nextLine = newSeq[int](count + 1)
  nextLine[count] = -1
  for i in countdown(count - 1, 0): nextLine[i] = if isLineMessage(messages[i].kind): i else: nextLine[i + 1]

  var cols: seq[Column]
  var colOf = initTable[string, int]()
  for id, actor in db.actors:
    if hasUsed and id notin used: continue
    let kind = actorKind(actor.kind)
    let label = text(actor.description, size, actor.wrap)
    var createAt = if id notin db.createdActors: -1 else: nextLine[min(db.createdActors[id], count)]
    if createAt >= 0 and messages[createAt].to != some(id): createAt = -1
    var destroyAt = if id notin db.destroyedActors: -1 else: nextLine[min(db.destroyedActors[id], count)]
    if destroyAt >= 0 and messages[destroyAt].to != some(id) and messages[destroyAt].start != some(id): destroyAt = -1
    colOf[id] = cols.len
    cols.add Column(
      id: id,
      actor: actor,
      kind: kind,
      label: label,
      size: (if tight: actorSize(kind, label, minW, minH, 8) else: actorSize(kind, label, minW, minH)),
      x: 0,
      createAt: createAt,
      destroyAt: destroyAt,
      top: 0,
      lifeStart: 0,
      lifeEnd: -1)
  let last = cols.len - 1

  # Widths between lifelines. Every message and note says how far apart the lifelines it touches must be.
  var needs = initOrderedTable[int, float]()
  proc need(lo, hi: int, width: float) =
    if lo < 0 or hi > last: return
    let key = lo * cols.len + hi
    if needs.getOrDefault(key, 0) < width: needs[key] = width
  proc badgeWidth(i: int): float =
    if numbering.shown[i]: max(BADGE_H, measurer.width(jsString(numbering.index[i]), tiny, 0) + 8) else: 0

  var views = newSeq[View](count)
  var sized = newSeq[Table[float, Label]](count)
  var hasSized = newSeq[bool](count)
  proc sizedText(i: int, room: float): Label =
    if not hasSized[i]:
      if room == wrapW: return views[i].label
      hasSized[i] = true
      sized[i] = {wrapW: views[i].label}.toTable
    if room notin sized[i]:
      sized[i][room] = messageText(messages[i].message, true, room)
    sized[i][room]
  for i in 0 ..< count:
    let m = messages[i]
    if m.start.isNone or m.to.isNone or m.start.get notin colOf or m.to.get notin colOf or m.isNumbering: continue
    let a = colOf[m.start.get]
    let b = colOf[m.to.get]
    if m.kind == LINETYPE_NOTE:
      let label = text(m.message, small, m.wrap)
      let w = label.width + 2 * notePad
      if m.placement == PLACEMENT_LEFTOF: need(a - 1, a, w + 2 * NOTE_GAP + ACT_W)
      elif m.placement == PLACEMENT_RIGHTOF: need(a, a + 1, w + 2 * NOTE_GAP + ACT_W)
      elif a == b:
        need(a - 1, a, w / 2 + NOTE_GAP)
        need(a, a + 1, w / 2 + NOTE_GAP)
      else: need(min(a, b), max(a, b), w - 2 * noteOver)
      views[i] = View(kind: V_Note, a: a, b: b, label: label, x: 0, w: w)
    elif isLineMessage(m.kind):
      let label = messageText(m.message, m.wrap)
      let badge = badgeWidth(i)
      if a == b:
        need(a, a + 1, SELF_W + 8 + label.width + 16 + ACT_W + badge)
        views[i] = View(kind: V_Self, a: a, b: b, label: label, x: 0, w: 0)
      else:
        let created = if cols[b].createAt == i: cols[b].size.w / 2 else: 0
        let central = if m.centralConnection != 0: 4 * CENTRAL_R else: 0
        need(min(a, b), max(a, b),
             (if tight: min(label.width, max(16.0, wrapW - 16)) else: label.width) + 2 * msgPad + ACT_W + badge +
               created + central)
        views[i] = View(kind: V_Line, a: a, b: b, label: label, x: 0, w: 0)

  var runs: seq[BoxRun]
  for i in 0 .. last:
    let box = cols[i].actor.box
    let run = if runs.len > 0: runs[^1] else: nil
    if box != nil and run != nil and run.box == box and run.last == i - 1: run.last = i
    elif box != nil:
      runs.add BoxRun(box: box, first: i, last: i, title: text(box.name.get(""), small, box.wrap), grow: 0)

  var gaps = newSeq[float](max(last, 0))
  for i in 0 ..< last:
    let left = cols[i]
    let right = cols[i + 1]
    let boxed = if left.actor.box != right.actor.box:
        (if left.actor.box != nil: boxPad else: 0) + (if right.actor.box != nil: boxPad else: 0)
      else: 0
    gaps[i] = max(left.size.w / 2 + right.size.w / 2 + actorMargin + boxed, needs.getOrDefault(i * cols.len + i + 1, 0))
  # A message across several lifelines widens each gap it crosses by an equal share of what is missing.
  var spans: seq[(int, int, float)]
  for key, width in needs:
    let lo = key div cols.len
    let hi = key mod cols.len
    if hi - lo > 1: spans.add (lo, hi, width)
  spans.sort(proc (p, q: (int, int, float)): int =
    let d = p[1] - p[0] - (q[1] - q[0])
    if d != 0: d else: p[0] - q[0])
  for (lo, hi, width) in spans:
    var total = 0.0
    for i in lo ..< hi: total += gaps[i]
    if total >= width: continue
    let share = (width - total) / float(hi - lo)
    for i in lo ..< hi: gaps[i] += share
  proc place() =
    for i in 1 .. last: cols[i].x = cols[i - 1].x + gaps[i - 1]
  place()
  for run in runs:
    let inner = cols[run.last].x + cols[run.last].size.w / 2 - (cols[run.first].x - cols[run.first].size.w / 2)
    run.grow = max(0.0, (run.title.width - inner) / 2)
    if run.grow == 0: continue
    if run.first > 0: gaps[run.first - 1] += run.grow
    if run.last < last: gaps[run.last] += run.grow

  var minX = Inf
  var maxX = -Inf
  proc extend(x0, x1: float) =
    if x0 < minX: minX = x0
    if x1 > maxX: maxX = x1
  proc boxEdges(run: BoxRun): (float, float) =
    (cols[run.first].x - cols[run.first].size.w / 2 - boxPad - run.grow,
     cols[run.last].x + cols[run.last].size.w / 2 + boxPad + run.grow)
  var frames = newSeq[Frame](count)
  proc layout() =
    place()
    minX = Inf
    maxX = -Inf
    for col in cols: extend(col.x - col.size.w / 2, col.x + col.size.w / 2)
    for run in runs:
      let (x0, x1) = boxEdges(run)
      extend(x0, x1)

    # Horizontal extents of every block, from what it holds.
    var open: seq[Frame]
    proc spanAll(): (float, float) =
      if last < 0: (0.0, 120.0) else: (cols[0].x - framePad, cols[last].x + framePad)
    for i in 0 ..< count:
      let m = messages[i]
      let kind = m.kind
      let view = views[i]
      if kind in FRAME_KIND:
        let frameKind = FRAME_KIND[kind]
        let frame = Frame(
          kind: frameKind,
          x0: Inf,
          x1: -Inf,
          top: 0,
          title: NO_LABEL,
          tabW: 0,
          fill: (if frameKind == "rect" and not m.isNumbering: m.message else: ""),
          dividers: @[i])
        frames[i] = frame
        open.add frame
      elif kind == LINETYPE_ALT_ELSE or kind == LINETYPE_PAR_AND or kind == LINETYPE_CRITICAL_OPTION:
        if open.len > 0: open[^1].dividers.add i
      elif kind == LINETYPE_LOOP_END or kind == LINETYPE_ALT_END or kind == LINETYPE_OPT_END or
           kind == LINETYPE_PAR_END or kind == LINETYPE_CRITICAL_END or kind == LINETYPE_BREAK_END or
           kind == LINETYPE_RECT_END:
        if open.len == 0: continue
        let frame = open.pop()
        frames[i] = frame
        if frame.x0 > frame.x1: (frame.x0, frame.x1) = spanAll()
        if frame.kind != "rect":
          frame.tabW = measurer.width(frame.kind, tiny, Bold) + 14
          # A block grows to the right to give its texts up to FRAME_TEXT of width before they wrap.
          for k in 0 ..< frame.dividers.len:
            let raw = messages[frame.dividers[k]].message
            let tab = if k == 0: frame.tabW + 8 else: 0
            let room = frame.x1 - frame.x0 - 16 - tab
            let label = if raw != "":
                text("[" & raw & "]", small, true,
                     max(room, if tight: min(FRAME_TEXT, wrapW) else: FRAME_TEXT))
              else: NO_LABEL
            if label.width > room: frame.x1 += label.width - room
            if k == 0: frame.title = label
            else: frame.dividerLabels.add label
        extend(frame.x0, frame.x1)
        if open.len > 0:
          let parent = open[^1]
          parent.x0 = min(parent.x0, frame.x0 - frameNest)
          parent.x1 = max(parent.x1, frame.x1 + frameNest)
      elif view != nil:
        let a = cols[view.a]
        let b = cols[view.b]
        var x0, x1: float
        if view.kind == V_Note:
          if m.placement == PLACEMENT_LEFTOF: view.x = a.x - NOTE_GAP - view.w
          elif m.placement == PLACEMENT_RIGHTOF: view.x = a.x + NOTE_GAP
          elif view.a == view.b: view.x = a.x - view.w / 2
          else:
            let lo = min(a.x, b.x) - noteOver
            let hi = max(a.x, b.x) + noteOver
            if tight or m.wrap: view.label = text(m.message, small, true, max(wrapW, hi - lo - 2 * notePad))
            view.w = max(hi - lo, view.label.width + 2 * notePad)
            view.x = (lo + hi - view.w) / 2
          x0 = view.x
          x1 = view.x + view.w
        elif view.kind == V_Self:
          x0 = a.x
          x1 = a.x + ACT_W + SELF_W + 8 + view.label.width + badgeWidth(i)
        else:
          x0 = min(a.x, b.x)
          x1 = max(a.x, b.x)
          if tight or m.wrap: view.label = sizedText(i, max(wrapW, x1 - x0 - 2 * msgPad - ACT_W))
          if b.createAt == i:
            if b.x > a.x: x1 += b.size.w / 2
            else: x0 -= b.size.w / 2
        extend(x0, x1)
        if open.len > 0:
          let frame = open[^1]
          frame.x0 = min(frame.x0, x0 - framePad)
          frame.x1 = max(frame.x1, x1 + framePad)
  layout()

  # Widen gaps only if it reduces message wrapping.
  var grown = false
  var uneven = false
  if tight and options.maxWidth.isSome:
    let spare = floor(options.maxWidth.get) - ceil(maxX - minX + 2 * pad) - hold
    var stretch = newSeq[int32](cols.len)
    var want = newSeq[float](gaps.len)
    var wrapped: seq[int]
    var lines = 0
    var i = 0
    while spare > 0 and i < views.len:
      let view = views[i]
      if view == nil or view.kind != V_Line:
        inc i
        continue
      let natural = messageText(messages[i].message, false, Inf)
      if view.label.lines.len <= natural.lines.len:
        inc i
        continue
      wrapped.add i
      lines += view.label.lines.len
      let lo = min(view.a, view.b)
      let hi = max(view.a, view.b)
      inc stretch[lo]
      dec stretch[hi]
      let short = (natural.width - (cols[hi].x - cols[lo].x - 2 * msgPad - ACT_W)) / float(hi - lo)
      for g in lo ..< hi: want[g] = max(want[g], short)
      inc i
    var active = 0'i32
    var crossed = 0
    for i in 0 ..< gaps.len:
      active += stretch[i]
      stretch[i] = if active > 0: 1 else: 0
      crossed += int(stretch[i])
    if crossed > 0:
      let before = gaps
      proc spread(share: proc (g: int): float): seq[int] =
        for g in 0 ..< gaps.len: gaps[g] = before[g] + share(g)
        layout()
        for i in wrapped: result.add views[i].label.lines.len
      proc sum(counts: seq[int]): int =
        for c in counts: result += c
      let even = proc (g: int): float = float(stretch[g]) * spare / float(crossed)
      var counts = spread(even)
      var missing = 0.0
      for w in want: missing += w
      # Allow for rounding error.
      let needsShare = proc (g: int): float = want[g] * (spare - 0.01) / missing
      # Reducing wrapping requires at least one gap wider than the even split.
      var wider = false
      for g in 0 ..< gaps.len:
        if needsShare(g) > even(g):
          wider = true
          break
      if byNeed and crossed > 1 and missing > 0 and wider:
        let first = counts
        counts = spread(needsShare)
        var every = true
        for k in 0 ..< counts.len:
          if counts[k] > first[k]: every = false
        uneven = sum(counts) < sum(first) and every
        if not uneven: counts = spread(even)
      grown = sum(counts) < lines
      if not grown:
        gaps = before
        layout()

  # Vertical placement, top to bottom, drawing as it goes.
  var boxTitleH = 0.0
  for run in runs: boxTitleH = max(boxTitleH, run.title.height)
  let boxTop = if runs.len > 0: boxPad + (if boxTitleH > 0: boxTitleH + 4 else: 0) else: 0
  var rowH = 0.0
  for col in cols:
    if col.createAt < 0: rowH = max(rowH, col.size.h)
  let headBottom = boxTop + rowH
  for col in cols:
    col.top = headBottom - col.size.h
    col.lifeStart = headBottom

  var xs: seq[float]
  for col in cols: xs.add col.x
  # Whether a lifeline runs between two x positions, where text would be struck through.
  proc crosses(x0, x1: float): bool =
    var lo = 0
    var hi = xs.len
    while lo < hi:
      let mid = (lo + hi) shr 1
      if xs[mid] <= x0: lo = mid + 1
      else: hi = mid
    lo < xs.len and xs[lo] < x1
  var stack: seq[Frame]
  var inks = initTable[string, string]()
  proc inkOf(fill: string): string =
    ## "" for undefined
    if fill == "": return ""
    if fill notin inks:
      let (ok, c) = ink(resolveStyle(@["fill:" & fill]).shape)
      inks[fill] = if ok: c else: ""
    inks[fill]
  proc inkOn(fill: string): string =
    let color = inkOf(fill)
    if color != "": " fill=\"" & color & "\"" else: ""
  # Prefer the innermost rect's fill, then a containing box's.
  proc fillUnder(l, r: float): string =
    for k in countdown(stack.len - 1, 0):
      if stack[k].kind == "rect": return stack[k].fill
    for run in runs:
      let (x0, x1) = boxEdges(run)
      if l >= x0 and r <= x1: return run.box.fill
    ""
  proc under(l, r: float): string = inkOn(fillUnder(l, r))
  proc backed(label: Label, cx, cy: float, frame = false): string =
    if label.width == 0: return ""
    let l = cx - label.width / 2
    let plate = crosses(l, l + label.width)
    let back = if plate:
        "<rect x=\"" & num(l - 3) & "\" y=\"" & num(cy - label.height / 2 + 2) & "\" width=\"" & num(label.width + 6) &
          "\" height=\"" & num(label.height - 4) & "\" rx=\"3\" fill=\"var(--_bg)\" stroke=\"none\"/>"
      else: ""
    let fill = if plate: "" else: under(l, l + label.width)
    back & labelSvg(label, cx, cy,
                    if frame: " class=\"pele-frame-label\"" & (if fill != "": fill else: " fill=\"var(--_m)\"") & " stroke=\"none\""
                    else: fill, icons)
  proc leftEdge(col: Column, extra = 0): float =
    if col.activations.len + extra > 0: col.x - ACT_W / 2 else: col.x
  proc rightEdge(col: Column, extra = 0): float =
    let depth = col.activations.len + extra
    if depth > 0: col.x + ACT_W / 2 + float(depth - 1) * ACT_STEP else: col.x

  # Shaded blocks and activations close from the inside out. They are written in reverse, so that
  # the inner ones end up on top.
  var rectsOut: seq[string]
  var activationsOut: seq[string]
  var framesOut = ""
  var edgesOut = ""
  var labelsOut = ""
  var notesOut = ""
  var actorsOut = ""
  var crossesOut = ""
  proc endActivation(col: Column, stop: float): float =
    let start = col.activations.pop()
    let bottom = max(stop, start + ACT_MIN)
    let x = col.x - ACT_W / 2 + float(col.activations.len) * ACT_STEP
    extend(x, x + ACT_W)
    activationsOut.add "<rect class=\"pele-activation\" data-id=\"" & escText(col.id) & "\" x=\"" & num(x) & "\" y=\"" &
      num(start) & "\" width=\"" & jsString(ACT_W) & "\" height=\"" & num(bottom - start) & "\" rx=\"2\"/>"
    bottom
  # The lifeline of a destroyed participant ends in a cross a little below the message that ends it.
  proc destroy(col: Column, lineY: float): float =
    let cx = col.x
    let cy = lineY + 16
    col.lifeEnd = cy
    crossesOut.add "<path class=\"pele-destroy\" data-id=\"" & escText(col.id) & "\" d=\"M" & num(cx - 6) & "," &
      num(cy - 6) & "L" & num(cx + 6) & "," & num(cy + 6) & "M" & num(cx + 6) & "," & num(cy - 6) & "L" &
      num(cx - 6) & "," & num(cy + 6) & "\"/>"
    cy + 6
  proc actorSvg(col: Column, top: float, footer: bool): string =
    let cls = col.actor.properties.getOrDefault("class", nil)
    "<g class=\"pele-node pele-actor pele-actor-" & col.kind & (if footer: " pele-actor-footer" else: "") &
      (if cls != nil and cls.kind == JString: classNames(cls.str) else: "") & "\" data-id=\"" & escText(col.id) & "\">" &
      drawActor(col.kind, col.x, top, col.size, col.label, icons,
                if isFigure(col.kind): inkOn(if col.actor.box != nil: col.actor.box.fill else: "") else: "") &
      "</g>"
  proc badge(i: int, cx, cy, w: float): string =
    "<g class=\"pele-sequence-number\"><rect x=\"" & num(cx - w / 2) & "\" y=\"" & num(cy - BADGE_H / 2) &
      "\" width=\"" & num(w) & "\" height=\"" & jsString(BADGE_H) & "\" rx=\"" & jsString(BADGE_H / 2) &
      "\" fill=\"var(--_l)\" stroke=\"none\"/><text x=\"" & num(cx) & "\" y=\"" & num(cy + tiny * 0.35) &
      "\" text-anchor=\"middle\" font-size=\"" & jsString(tiny) & "\" fill=\"var(--_bg)\" stroke=\"none\">" &
      esc(jsString(numbering.index[i])) & "</text></g>"

  var y = headBottom + 6
  for i in 0 ..< count:
    let m = messages[i]
    let kind = m.kind
    let view = views[i]
    let frame = frames[i]

    if kind == LINETYPE_ACTIVE_START:
      if m.start.isSome and m.start.get in colOf: cols[colOf[m.start.get]].activations.add y
    elif kind == LINETYPE_ACTIVE_END:
      if m.start.isSome and m.start.get in colOf:
        let col = cols[colOf[m.start.get]]
        if col.activations.len > 0: y = max(y, endActivation(col, y))
    elif frame != nil and frame.dividers[0] == i:
      stack.add frame
      if frame.kind == "rect":
        frame.top = y + 8
        y = frame.top
      else:
        frame.top = y + 12
        y = frame.top + max(TAB_H, frame.title.height + 2)
    elif frame != nil:
      discard stack.pop()
      let bottom = y + 12
      let x = num(frame.x0)
      let w = num(frame.x1 - frame.x0)
      if frame.kind == "rect":
        let fill = if frame.fill != "": resolveStyle(@["fill:" & frame.fill]).shape else: ""
        rectsOut.add "<rect class=\"pele-rect\" x=\"" & x & "\" y=\"" & num(frame.top) & "\" width=\"" & w &
          "\" height=\"" & num(bottom - frame.top) & "\"" &
          rounded((if fill != "": "" else: " fill-opacity=\"0.5\"") & fill) & "/>"
      else:
        var inner = "<rect x=\"" & x & "\" y=\"" & num(frame.top) & "\" width=\"" & w & "\" height=\"" &
          num(bottom - frame.top) & "\" fill=\"none\"" & ROUNDED & "/>"
        for k in 0 ..< frame.dividerY.len:
          let dy = frame.dividerY[k]
          let label = frame.dividerLabels[k]
          inner.add "<path d=\"M" & x & "," & num(dy) & "H" & num(frame.x1) & "\"" & DASH & "/>" &
            backed(label, frame.x0 + 8 + label.width / 2, dy + 2 + label.height / 2, true)
        inner.add "<rect x=\"" & x & "\" y=\"" & num(frame.top) & "\" width=\"" & num(frame.tabW) & "\" height=\"" &
          jsString(TAB_H) & "\" fill=\"var(--_s)\"" & ROUNDED & "/>" &
          "<text class=\"pele-frame-kind\" x=\"" & num(frame.x0 + frame.tabW / 2) & "\" y=\"" &
          num(frame.top + TAB_H / 2 + tiny * 0.35) & "\" text-anchor=\"middle\" font-size=\"" & jsString(tiny) &
          "\" font-weight=\"var(--_hw)\" fill=\"var(--_m)\" stroke=\"none\">" & frame.kind & "</text>" &
          backed(frame.title, frame.x0 + frame.tabW + 8 + frame.title.width / 2,
                 frame.top + max(TAB_H, frame.title.height) / 2, true)
        framesOut.add "<g class=\"pele-frame pele-frame-" & frame.kind & "\">" & inner & "</g>"
      y = bottom
    elif kind == LINETYPE_ALT_ELSE or kind == LINETYPE_PAR_AND or kind == LINETYPE_CRITICAL_OPTION:
      if stack.len > 0:
        let current = stack[^1]
        let label = current.dividerLabels[current.dividerY.len]
        current.dividerY.add y + 12
        y += 12 + (if label.height > 0: label.height else: 0)
    elif view != nil and view.kind == V_Note:
      let a = cols[view.a]
      let h = view.label.height + 2 * max(4.0, notePad - 4)
      let top = y + 10
      var x = view.x
      if m.placement == PLACEMENT_RIGHTOF: x += rightEdge(a) - a.x
      elif m.placement == PLACEMENT_LEFTOF: x += leftEdge(a) - a.x
      extend(x, x + view.w)
      notesOut.add "<g class=\"pele-note\" data-id=\"i" & escText(m.id) & "\">" &
        "<rect x=\"" & num(x) & "\" y=\"" & num(top) & "\" width=\"" & num(view.w) & "\" height=\"" & num(h) & "\"" &
        ROUNDED & "/>" &
        labelSvg(view.label, x + view.w / 2, top + h / 2, " class=\"pele-label\" stroke=\"none\" fill=\"var(--_fg)\"", icons) &
        "</g>"
      y = top + h
    elif view != nil:
      let st = STYLES[kind].get
      let a = cols[view.a]
      let b = cols[view.b]
      let label = view.label
      let bw = badgeWidth(i)
      # The activation a `+` starts belongs to this message, so the arrow stops at its edge.
      var starting = 0
      for k in i + 1 ..< count:
        let t = messages[k].kind
        if t == LINETYPE_ACTIVE_START:
          if messages[k].start == m.to: inc starting
        elif t != LINETYPE_ACTIVE_END and t != LINETYPE_CENTRAL_CONNECTION and t != LINETYPE_CENTRAL_CONNECTION_REVERSE:
          break
      let up = if st.bottom: 1.0 else: -1.0
      let attrs = if st.dotted: DASH else: ""
      let cc = m.centralConnection
      let circleTo = cc == LINETYPE_CENTRAL_CONNECTION or cc == LINETYPE_CENTRAL_CONNECTION_DUAL
      let circleFrom = cc == LINETYPE_CENTRAL_CONNECTION_REVERSE or cc == LINETYPE_CENTRAL_CONNECTION_DUAL
      var line = ""
      var color = "var(--_l)"
      template circle(cx, cy: float): string =
        "<circle class=\"pele-central\" cx=\"" & num(cx) & "\" cy=\"" & num(cy) & "\" r=\"" & jsString(CENTRAL_R) &
          "\" fill=\"" & color & "\" stroke=\"none\"/>"
      let tailAtEnd = st.atStart and not st.atEnd
      let headTrim = trim(st.head)
      var inner = ""
      var lineY: float

      if view.kind == V_Self:
        let top = y + msgGap + max(0.0, (label.height - SELF_H) / 2)
        let bottom = top + SELF_H
        var x0 = if circleFrom: a.x + CENTRAL_R else: rightEdge(a)
        var x1 = if circleTo: a.x + CENTRAL_R else: rightEdge(a, starting)
        let output = max(x0, x1) + SELF_W + bw / 2
        line = inkOf(fillUnder(a.x, output))
        color = if line != "": line else: color
        if circleFrom: inner.add circle(a.x, top)
        if circleTo: inner.add circle(a.x, bottom)
        if bw > 0:
          inner.add badge(i, if tailAtEnd: x1 else: x0, if tailAtEnd: bottom else: top, bw)
          if tailAtEnd: x1 += bw / 2
          else: x0 += bw / 2
        # The loop leaves to the right and comes back heading left, which turns a half head over.
        let heads = (if st.atStart: head(st.head, x0, top, -1, up, color) else: "") &
          (if st.atEnd: head(st.head, x1, bottom, -1, -up, color) else: "")
        let start = num(x0 + (if st.atStart: headTrim else: 0))
        let to = num(x1 + (if st.atEnd: headTrim else: 0))
        let d = if rightAngles:
            "M" & start & "," & num(top) & "H" & num(output) & "V" & num(bottom) & "H" & to
          else:
            "M" & start & "," & num(top) & "H" & num(output - 6) & "A6,6 0 0 1 " & num(output) & "," & num(top + 6) &
              "V" & num(bottom - 6) & "A6,6 0 0 1 " & num(output - 6) & "," & num(bottom) & "H" & to
        inner = "<path d=\"" & d & "\"" & attrs & "/>" & heads & inner
        extend(a.x, output + 8 + label.width)
        if label.width > 0:
          labelsOut.add "<g class=\"pele-edge-label\" data-id=\"i" & escText(m.id) & "\">" &
            labelSvg(label, output + 8 + label.width / 2, (top + bottom) / 2,
                     under(output + 8, output + 8 + label.width), icons) & "</g>"
        # A label taller than the loop reaches below it, so the next row starts under the label.
        lineY = max(bottom, (top + bottom) / 2 + label.height / 2)
      else:
        let dir = if b.x > a.x: 1.0 else: -1.0
        let creating = b.createAt == i
        line = inkOf(fillUnder(min(a.x, b.x), max(a.x, b.x)))
        color = if line != "": line else: color
        lineY = y + msgGap + max(if label.height > 0: label.height + 2 else: 6.0,
                                 if creating: b.size.h / 2 - msgGap + 6 else: 0.0)
        var x0 = if dir > 0: rightEdge(a) else: leftEdge(a)
        var x1 = if dir > 0: leftEdge(b, starting) else: rightEdge(b, starting)
        if creating:
          b.top = lineY - b.size.h / 2
          b.lifeStart = b.top + b.size.h
          x1 = b.x - dir * (if isFigure(b.kind): 18.0 else: b.size.w / 2 + 1)
        if circleFrom:
          inner.add circle(a.x, lineY)
          x0 = a.x + dir * CENTRAL_R
        if circleTo:
          inner.add circle(b.x, lineY)
          x1 = b.x - dir * CENTRAL_R
        if bw > 0:
          # The number sits on the lifeline at the tail of the arrow, past a connection circle if there is one.
          if tailAtEnd:
            let cx = if circleTo: x1 - dir * (bw / 2 + 2) else: x1
            inner.add badge(i, cx, lineY, bw)
            x1 = cx - (dir * bw) / 2
          else:
            let cx = if circleFrom: x0 + dir * (bw / 2 + 2) else: x0
            inner.add badge(i, cx, lineY, bw)
            x0 = cx + (dir * bw) / 2
        let heads = (if st.atStart: head(st.head, x0, lineY, -dir, up * dir, color) else: "") &
          (if st.atEnd: head(st.head, x1, lineY, dir, up * dir, color) else: "")
        let start = x0 + (if st.atStart: dir * headTrim else: 0)
        let to = x1 - (if st.atEnd: dir * headTrim else: 0)
        inner = "<path d=\"M" & num(start) & "," & num(lineY) & "H" & num(to) & "\"" & attrs & "/>" & heads & inner
        if label.width > 0:
          let l = min(x0, x1)
          let r = max(x0, x1)
          let cx = if align < 0: l + msgPad + label.width / 2
                   elif align > 0: r - msgPad - label.width / 2
                   else: (l + r) / 2
          extend(cx - label.width / 2, cx + label.width / 2)
          labelsOut.add "<g class=\"pele-edge-label\" data-id=\"i" & escText(m.id) & "\">" &
            backed(label, cx, lineY - 4 - label.height / 2) & "</g>"
        if creating: y = lineY + b.size.h / 2 - 6
      edgesOut.add "<g class=\"pele-edge pele-message\" data-id=\"i" & escText(m.id) & "\"" &
        (if line != "": " stroke=\"" & line & "\"" else: "") & ">" & inner & "</g>"
      y = max(y, lineY)
      if a.destroyAt == i: y = max(y, destroy(a, lineY))
      if b.destroyAt == i and b != a: y = max(y, destroy(b, lineY))

  y += 20
  for col in cols:
    while col.activations.len > 0: discard endActivation(col, y)
  var bottom = y
  if mirror:
    var footH = 0.0
    for col in cols:
      if col.lifeEnd >= 0: continue
      footH = max(footH, col.size.h)
      actorsOut.add actorSvg(col, y, true)
    bottom = y + footH
  var lifelines = ""
  for col in cols:
    actorsOut.add actorSvg(col, col.top, false)
    let stop = if col.lifeEnd >= 0: col.lifeEnd else: y
    if stop > col.lifeStart:
      lifelines.add "<path class=\"pele-lifeline\" data-id=\"" & escText(col.id) & "\" d=\"M" & num(col.x) & "," &
        num(col.lifeStart) & "V" & num(stop) & "\"/>"

  var boxesOut = ""
  for run in runs:
    let (x0, x1) = boxEdges(run)
    let fill = if run.box.fill == "transparent": "" else: resolveStyle(@["fill:" & run.box.fill]).shape
    let inkAttr = inkOn(run.box.fill)
    boxesOut.add "<g class=\"pele-cluster pele-box\"" &
      (if run.box.name.isSome and run.box.name.get != "": " data-id=\"" & escText(run.box.name.get) & "\"" else: "") & ">" &
      "<rect x=\"" & num(x0) & "\" y=\"0\" width=\"" & num(x1 - x0) & "\" height=\"" & num(bottom + boxPad) &
      "\" fill=\"var(--_a)\" stroke=\"var(--_b)\"" & rounded((if fill != "": "" else: " fill-opacity=\"0.5\"") & fill) & "/>" &
      labelSvg(run.title, (x0 + x1) / 2, boxPad / 2 + 2 + run.title.height / 2,
               " class=\"pele-cluster-label\"" & (if inkAttr != "": inkAttr else: " fill=\"var(--_m)\""), icons) &
      "</g>"
  if runs.len > 0: bottom += boxPad

  var minY = 0.0
  var titleOut = ""
  let room = titleRoom(options)
  let plainTitle = titleLabel(db.title, measurer, size, if tight: room else: Inf)
  let title = if tight: breakLabel(plainTitle, measurer, max(120.0, room)) else: plainTitle
  if minX > maxX: extend(0, max(title.width, 40))
  if title.width > 0:
    let cx = (minX + maxX) / 2
    extend(cx - title.width / 2, cx + title.width / 2)
    minY = -title.height - 12
    titleOut = labelSvg(title, cx, minY + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"", icons)

  let width = ceil(maxX - minX + 2 * pad)
  # Retry with equal shares or room for activation notes and rounding.
  if grown and width > options.maxWidth.get:
    return draw(db, config, options, tight,
                if uneven: hold elif hold > 0: Inf else: width - floor(options.maxWidth.get), false)
  let height = ceil(bottom - minY + 2 * pad)
  let svg = svgDocument(
    "sequence",
    width,
    height,
    size,
    options,
    Accessible(accTitle: db.accTitle, accDescr: db.accDescr),
    "<g transform=\"translate(" & num(pad - minX) & "," & num(pad - minY) & ")\">" &
      titleOut &
      (if boxesOut != "": "<g class=\"pele-boxes\" font-size=\"" & jsString(small) & "\">" & boxesOut & "</g>" else: "") &
      (if rectsOut.len > 0: "<g class=\"pele-rects\" fill=\"var(--_a)\">" & reversedJoin(rectsOut) & "</g>" else: "") &
      (if lifelines != "": "<g class=\"pele-lifelines\" fill=\"none\" stroke=\"var(--_b)\">" & lifelines & "</g>" else: "") &
      (if activationsOut.len > 0:
         "<g class=\"pele-activations\" fill=\"var(--_s)\" stroke=\"var(--_b)\">" & reversedJoin(activationsOut) & "</g>"
       else: "") &
      (if framesOut != "": "<g class=\"pele-frames\" font-size=\"" & jsString(small) & "\" stroke=\"var(--_b)\">" & framesOut & "</g>" else: "") &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" & edgesOut & "</g>" else: "") &
      (if crossesOut != "":
         "<g class=\"pele-destroys\" fill=\"none\" stroke=\"var(--_l)\" stroke-width=\"1.5\" stroke-linecap=\"round\">" & crossesOut & "</g>"
       else: "") &
      (if labelsOut != "":
         "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\"" &
           (if monospaced: " font-family=\"" & FONT_MONO & "\"" else: "") & ">" & labelsOut & "</g>"
       else: "") &
      (if notesOut != "": "<g class=\"pele-notes\" font-size=\"" & jsString(small) & "\" fill=\"var(--_a)\" stroke=\"var(--_b)\">" & notesOut & "</g>" else: "") &
      (if actorsOut != "": "<g class=\"pele-nodes\">" & actorsOut & "</g>" else: "") &
      "</g>")
  Rendered(svg: svg, width: width, height: height, links: @[])

## port-of: src/diagrams/eventmodeling/render.ts
## port-status: conformant
import std/[algorithm, options, sets, strutils, tables]
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, edges, root, theme]
import ../../text/[entities, label, measurer]
import ../../types
import ../../js
import ../common/[fit_width, literal_label]
import model

let SERIES = {
  # Series slot for each kind of entity. A UI has none and is drawn plain.
  "command": 0, "event": 1, "readmodel": 2, "processor": 6,
}.toTable

const
  BOX_PAD_X = 12.0
  BOX_PAD_Y = 10.0
  BOX_MIN_WIDTH = 96.0
  BOX_GAP = 16.0
  STAGGER = 80.0
  LANE_PAD = 12.0
  LANE_GAP = 8.0
  DATA_COLUMNS = 48
  NOTE_COLUMNS = 80
  CARD_GAP = 8.0

type
  Placed = ref object
    box: EmBox
    name: Label
    data: seq[string]
    x, y, w, h: float

  Band = ref object
    lane: EmLane
    label: Label
    right, y, h: float

proc hardWrap(text: string, columns: int): seq[string] =
  ## Splits text into lines of at most `columns` characters, keeping its own line breaks.
  for line in decodeEntities(text).split('\n'):
    if utf16Len(line) <= columns:
      result.add line
      continue
    var chars: seq[string]
    for c in codePoints(line): chars.add c
    if chars.len <= columns:
      result.add line
      continue
    var i = 0
    while i < chars.len:
      result.add chars[i ..< min(i + columns, chars.len)].join("")
      i += columns

proc lines(rows: seq[string], x, y, step: float, attrs: string): string =
  var body = ""
  for i in 0 ..< rows.len:
    if rows[i] != "":
      body.add "<tspan x=\"" & num(x) & "\" y=\"" & num(y + float(i) * step) & "\">" & esc(rows[i]) & "</tspan>"
  if body == "": "" else: "<text" & attrs & " xml:space=\"preserve\">" & body & "</text>"

proc draw(model: EventModelingModel, config: Config, options: RenderOptions, down: bool): Rendered

proc renderEventModel*(model: EventModelingModel, config: Config, options: RenderOptions): Rendered =
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

proc verticalEventModel(model: EventModelingModel, options: RenderOptions): Rendered

proc acc(model: EventModelingModel): Accessible = Accessible(accTitle: model.accTitle, accDescr: model.accDescr)

proc draw(model: EventModelingModel, config: Config, options: RenderOptions, down: bool): Rendered =
  if down: return verticalEventModel(model, options)
  let size = options.fontSize.get(16)
  let nameSize = jsRound(size * 0.875)
  let small = jsRound(size * 0.8125)
  let mono = jsRound(size * 0.75)
  let monoStep = jsRound(mono * 1.4)
  let smallStep = jsRound(small * 1.5)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  proc widest(rows: seq[string], fontSize: float, style: int): float =
    for row in rows: result = jsMax(result, measurer.width(row, fontSize, style))

  var bands: seq[Band]
  proc bandOf(lane: EmLane): Band =
    for b in bands:
      if b.lane == lane: return b
  var labelColumn = 0.0
  for lane in model.lanes:
    let label = layoutLabel(lane.label, false, measurer, small, 4000, Bold)
    labelColumn = jsMax(labelColumn, label.width)
    bands.add Band(lane: lane, label: label, right: -Inf, y: 0, h: 0)
  labelColumn += 2 * LANE_PAD

  # Time runs left to right. A frame in a new lane starts under the end of the one before it,
  # so the arrow between them can drop straight down; a frame in the same lane follows on.
  var placed: seq[Placed]
  var previous: Placed = nil
  for box in model.boxes:
    let band = bandOf(box.lane)
    let name = layoutLabel(box.name, false, measurer, nameSize, 4000, Bold)
    let data = if box.data != "": hardWrap(box.data, DATA_COLUMNS) else: @[]
    let w = jsMax(BOX_MIN_WIDTH, jsMax(name.width, widest(data, mono, Mono)) + 2 * BOX_PAD_X)
    let h = 2 * BOX_PAD_Y + name.height + (if data.len > 0: 6 + float(data.len) * monoStep else: 0)
    var x = 0.0
    if previous != nil:
      let stagger = previous.x + jsMax(previous.w / 2, previous.w - STAGGER)
      x = if previous.box.lane == box.lane: band.right + BOX_GAP else: jsMax(stagger, band.right + BOX_GAP)
    let item = Placed(box: box, name: name, data: data, x: x, y: 0, w: w, h: h)
    band.right = x + w
    band.h = jsMax(band.h, h)
    placed.add item
    previous = item

  var contentRight = 0.0
  for item in placed: contentRight = jsMax(contentRight, item.x + item.w)
  let laneWidth = labelColumn + contentRight + LANE_PAD

  let title = layoutLabel(model.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let left = pad
  let top = pad + titleHeight

  var y = top
  var lanes = ""
  for band in bands:
    band.y = y
    band.h += 2 * LANE_PAD
    lanes.add "<g class=\"pele-cluster pele-em-lane\" data-id=\"" & escText(band.lane.label) & "\">" &
      "<rect x=\"" & num(left) & "\" y=\"" & num(y) & "\" width=\"" & num(laneWidth) & "\" height=\"" & num(band.h) &
      "\" fill=\"var(--_s)\"" & ROUNDED & "/>" &
      labelSvg(band.label, left + LANE_PAD + band.label.width / 2, y + band.h / 2,
               " class=\"pele-cluster-label\" font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\" fill=\"var(--_m)\"") &
      "</g>"
    y += band.h + LANE_GAP
  var bottom = if bands.len > 0: y - LANE_GAP else: top

  var nodes = ""
  for item in placed:
    let band = bandOf(item.box.lane)
    item.x += left + labelColumn
    item.y = band.y + (band.h - item.h) / 2
    let frame = "x=\"" & num(item.x) & "\" y=\"" & num(item.y) & "\" width=\"" & num(item.w) & "\" height=\"" & num(item.h) & "\""
    let shape =
      if item.box.kind notin SERIES: "<rect " & frame & " fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & ROUNDED & "/>"
      else:
        let color = seriesColor(SERIES[item.box.kind])
        "<rect " & frame & " fill=\"var(--_bg)\"" & ROUNDED & "/><rect " & frame & " fill=\"" & color &
          "\" fill-opacity=\"0.22\" stroke=\"" & color & "\"" & ROUNDED & "/>"
    let nameY = item.y + BOX_PAD_Y + item.name.height / 2
    let text =
      labelSvg(item.name, item.x + item.w / 2, nameY,
               " class=\"pele-label\" font-size=\"" & jsString(nameSize) & "\" font-weight=\"var(--_hw)\"") &
      lines(item.data, item.x + BOX_PAD_X, item.y + BOX_PAD_Y + item.name.height + 6 + monoStep / 2 + mono * 0.35,
            monoStep, " class=\"pele-em-data\" font-family=\"" & FONT_MONO & "\" font-size=\"" & jsString(mono) & "\"")
    nodes.add "<g class=\"pele-node pele-em-" & item.box.kind & (if item.box.reset: " pele-em-reset" else: "") &
      "\" data-id=\"" & escText(item.box.id) & "\">" & shape & text & "</g>"

  var edgesOut = ""
  let trim = markerTrim("arrow_point")
  for relation in model.relations:
    let s = placed[relation.source.order]
    let t = placed[relation.target.order]
    if s == t: continue
    var d, head: string
    if s.box.lane == t.box.lane:
      # Along the lane, from the side of one box to the side of the other.
      let forward = t.x >= s.x
      let sx = if forward: s.x + s.w else: s.x
      let tx = if forward: t.x else: t.x + t.w
      let sy = s.y + s.h / 2
      let ty = t.y + t.h / 2
      let dir = if tx >= sx: 1.0 else: -1.0
      d = "M" & num(sx) & "," & num(sy) & "L" & num(tx - dir * trim) & "," & num(ty)
      head = marker("arrow_point", tx, ty, dir, 0, "var(--_l)")
    else:
      # Between lanes, straight down or up where the boxes overlap, else in an S.
      let down = t.y > s.y
      let start = jsMax(s.x, t.x)
      let stop = jsMin(s.x + s.w, t.x + t.w)
      proc inset(w: float): float = jsMin(24, w / 4)
      let sx = if stop - start >= 16: (start + stop) / 2
               elif t.x > s.x: s.x + s.w - inset(s.w) else: s.x + inset(s.w)
      let tx = if stop - start >= 16: sx
               elif t.x > s.x: t.x + inset(t.w) else: t.x + t.w - inset(t.w)
      let sy = if down: s.y + s.h else: s.y
      let ty = if down: t.y else: t.y + t.h
      let dir = if down: 1.0 else: -1.0
      let stopY = ty - dir * trim
      let mid = (sy + stopY) / 2
      d = if sx == tx: "M" & num(sx) & "," & num(sy) & "V" & num(stopY)
          else: "M" & num(sx) & "," & num(sy) & "C" & num(sx) & "," & num(mid) & " " & num(tx) & "," & num(mid) & " " &
                num(tx) & "," & num(stopY)
      head = marker("arrow_point", tx, ty, 0, dir, "var(--_l)")
    edgesOut.add "<g class=\"pele-edge\" data-id=\"" & escText(relation.source.id) & "-" & escText(relation.target.id) &
      "\"><path d=\"" & d & "\" fill=\"none\" stroke=\"var(--_l)\"/>" & head & "</g>"

  # Notes and given/when/then specifications, listed under the lanes with the frame they belong to.
  var names = initTable[string, string]()
  for box in model.boxes: names[box.id] = box.name
  var cards = ""
  var cardsRight = 0.0
  proc card(kind, heading, frame: string, rows: seq[string]) =
    let head = layoutLabel(heading & " · " & frame & (if frame in names: " " & names[frame] else: ""), false,
                           measurer, small, 4000, Bold)
    let w = jsMax(head.width, widest(rows, small, 0)) + 2 * BOX_PAD_X
    let h = 2 * BOX_PAD_Y + head.height + float(rows.len) * smallStep
    let cy = bottom + (if cards == "" and bands.len == 0: 0.0 else: CARD_GAP)
    cards.add "<g class=\"pele-em-" & kind & "\" data-id=\"" & escText(frame) & "\">" &
      "<rect x=\"" & num(left) & "\" y=\"" & num(cy) & "\" width=\"" & num(w) & "\" height=\"" & num(h) &
      "\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
      labelSvg(head, left + BOX_PAD_X + head.width / 2, cy + BOX_PAD_Y + head.height / 2,
               " font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\"") &
      lines(rows, left + BOX_PAD_X, cy + BOX_PAD_Y + head.height + smallStep / 2 + small * 0.35, smallStep,
            " font-size=\"" & jsString(small) & "\"") &
      "</g>"
    bottom = cy + h
    cardsRight = jsMax(cardsRight, w)
  for note in model.notes: card("note", "Note", note.frame, hardWrap(note.text, NOTE_COLUMNS))
  for spec in model.specifications:
    var rows = @["Given  " & spec.given.join(", ")]
    if spec.`when`.len > 0: rows.add "When  " & spec.`when`.join(", ")
    rows.add "Then  " & spec.then.join(", ")
    var wrapped: seq[string]
    for row in rows: wrapped.add hardWrap(row, NOTE_COLUMNS)
    card("specification", "Given / When / Then", spec.frame, wrapped)

  let width = jsMax(jsMax(if bands.len > 0: laneWidth else: 0, cardsRight), title.width)
  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(bottom + pad)
  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    lanes & edgesOut & nodes & cards

  Rendered(svg: svgDocument("eventmodeling", totalWidth, totalHeight, size, options, acc(model), content),
           width: totalWidth, height: totalHeight)

const
  RAIL_GAP = 8.0
  CARD_MIN = 120.0
  ARROW_ROOM = 20.0

type Slot = object
  y, h, w: float
  index: int
  lane: float

proc joined(label: Label): seq[string] =
  ## label.lines.map(line => line.map(span => span.text).join(''))
  for line in label.lines:
    var s = ""
    for span in line: s.add span.text
    result.add s

proc verticalEventModel(model: EventModelingModel, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let mono = jsRound(size * 0.75)
  let pad = options.padding.get(8)
  let measurer = measurerOf(options)
  let room = jsMax(160, options.maxWidth.get(320) - 2 * pad)
  # A relation that skips a card runs down a rail beside the cards. Relations into one card
  # share a rail; others whose runs overlap take the next rail out, so that no two follow the
  # same line.
  var runs = initOrderedTable[int, (int, int)]()
  # A relation between neighbouring cards passes the lower card's lane heading.
  var passed = initHashSet[int]()
  for relation in model.relations:
    let s = relation.source.order
    let t = relation.target.order
    if s == t: continue
    if abs(s - t) < 2:
      passed.incl max(s, t)
      continue
    if relation.target.order in runs:
      var run = runs[t]
      run[0] = min(run[0], s)
      run[1] = max(run[1], s)
      runs[t] = run
    else:
      runs[t] = (min(s, t), max(s, t))
  var railOf = initTable[int, int]()
  var railEnds: seq[int]
  var sortedRuns: seq[(int, (int, int))]
  for target, run in runs: sortedRuns.add (target, run)
  sortedRuns.sort(proc (a, b: (int, (int, int))): int = a[1][0] - b[1][0])
  for (target, run) in sortedRuns:
    let (start, stop) = run
    var rail = -1
    for k, e in railEnds:
      if e < start:
        rail = k
        break
    if rail < 0:
      rail = railEnds.len
      railEnds.add stop
    else:
      railEnds[rail] = stop
    railOf[target] = rail
  let gutter = 24 + RAIL_GAP * float(max(0, railEnds.len - 1))
  # Rails are never shared to save room: past what the width allows, the drawing is wider.
  let cardWidth = jsMax(CARD_MIN, room - gutter)
  let textRoom = cardWidth - 2 * BOX_PAD_X
  let title = layoutLabel(model.title, false, measurer, size, room, Bold)
  var y = pad + (if title.height != 0: title.height + 12 else: 0)
  var bottom = pad + title.height
  var width = jsMax(title.width, cardWidth + gutter)
  var nodes, edgesOut, cards: string
  var placed = newSeq[Slot](model.boxes.len)
  proc text(raw: string, fontSize: float, style = 0): Label =
    literalLabel(decodeEntities(raw), measurer, fontSize, textRoom, style)
  for index, box in model.boxes:
    let laneRoom = if index in passed: textRoom - ARROW_ROOM else: textRoom
    let lane = breakLabel(layoutLabel(box.lane.label, false, measurer, small, laneRoom, Bold), measurer, laneRoom)
    let name = layoutLabel(box.name, false, measurer, small, textRoom - 36, Bold)
    let hasData = box.data != ""
    let data = if hasData: text(box.data, mono, Mono) else: Label()
    let w = jsMax(jsMax(cardWidth, lane.width + 2 * BOX_PAD_X),
                  jsMax(name.width + 2 * BOX_PAD_X + 36, (if hasData: data.width else: 0) + 2 * BOX_PAD_X))
    let headH = lane.height + 12
    let h = 2 * BOX_PAD_Y + name.height + (if hasData: data.height + 6 else: 0)
    let cy = y + headH
    let frame = "x=\"" & num(pad) & "\" y=\"" & num(cy) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\""
    nodes.add "<g class=\"pele-cluster pele-em-lane\" data-id=\"" & escText(box.lane.label) & "\">" &
      leftLabelSvg(lane, pad + BOX_PAD_X, y,
                   " class=\"pele-cluster-label\" font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\" fill=\"var(--_m)\"") &
      "<g class=\"pele-node pele-em-" & box.kind & (if box.reset: " pele-em-reset" else: "") & "\" data-id=\"" &
      escText(box.id) & "\"><rect " & frame & " fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
      (if box.kind notin SERIES: ""
       else: "<rect " & frame & " fill=\"" & seriesColor(SERIES[box.kind]) & "\" fill-opacity=\"0.22\" stroke=\"" &
             seriesColor(SERIES[box.kind]) & "\"" & ROUNDED & "/>") &
      labelSvg(name, pad + BOX_PAD_X + name.width / 2, cy + BOX_PAD_Y + name.height / 2,
               " class=\"pele-label\" font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\"") &
      "<text class=\"pele-em-frame\" x=\"" & num(pad + w - BOX_PAD_X) & "\" y=\"" & num(cy + BOX_PAD_Y + small) &
      "\" text-anchor=\"end\" font-size=\"" & jsString(mono) & "\" fill=\"var(--_m)\">" & esc(box.id) & "</text>" &
      (if hasData: lines(joined(data), pad + BOX_PAD_X, cy + BOX_PAD_Y + name.height + 6 + data.lineHeight / 2 + mono * 0.35,
                         data.lineHeight, " class=\"pele-em-data\" font-family=\"" & FONT_MONO & "\" font-size=\"" & jsString(mono) & "\"")
       else: "") & "</g></g>"
    placed[index] = Slot(y: cy, h: h, w: w, index: index, lane: lane.width)
    width = jsMax(width, w + gutter)
    bottom = cy + h
    y = bottom + 28
  for relation in model.relations:
    let s = placed[relation.source.order]
    let t = placed[relation.target.order]
    if s.index == t.index: continue
    let down = t.y > s.y
    let dir = if down: 1.0 else: -1.0
    let sy = if down: s.y + s.h else: s.y
    let ty = if down: t.y else: t.y + t.h
    var d, head: string
    if abs(s.index - t.index) == 1:
      # The lower card's lane heading sits in the gap, and wraps to leave the arrow room beside it.
      let cx = pad + jsMax(jsMin(s.w, t.w) / 2, BOX_PAD_X + (if down: t else: s).lane + 16)
      d = "M" & num(cx) & "," & num(sy) & "V" & num(ty - dir * markerTrim("arrow_point"))
      head = marker("arrow_point", cx, ty, 0, dir, "var(--_l)")
    else:
      let rail = pad + width - gutter + 12 + RAIL_GAP * float(railOf.getOrDefault(relation.target.order, 0))
      # A card can send one relation and receive another: they leave above and arrive below its middle.
      let start = s.y + s.h / 2 - 5
      let stop = t.y + t.h / 2 + 5
      d = "M" & num(pad + s.w) & "," & num(start) & "H" & num(rail) & "V" & num(stop) & "H" &
        num(pad + t.w + markerTrim("arrow_point"))
      head = marker("arrow_point", pad + t.w, stop, -1, 0, "var(--_l)")
    edgesOut.add "<g class=\"pele-edge\" data-id=\"" & escText(relation.source.id) & "-" & escText(relation.target.id) &
      "\"><path d=\"" & d & "\" fill=\"none\" stroke=\"var(--_l)\"/>" & head & "</g>"
  var names = initTable[string, string]()
  for box in model.boxes: names[box.id] = box.name
  proc card(kind, heading, frame, raw: string) =
    let head = layoutLabel(heading & " · " & frame & (if frame in names: " " & names[frame] else: ""), false,
                           measurer, small, textRoom, Bold)
    let body = text(raw, small)
    let w = jsMax(jsMax(cardWidth, head.width + 2 * BOX_PAD_X), body.width + 2 * BOX_PAD_X)
    let h = 2 * BOX_PAD_Y + head.height + body.height
    cards.add "<g class=\"pele-em-" & kind & "\" data-id=\"" & escText(frame) & "\"><rect x=\"" & num(pad) & "\" y=\"" &
      num(y) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
      labelSvg(head, pad + BOX_PAD_X + head.width / 2, y + BOX_PAD_Y + head.height / 2,
               " font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\"") &
      lines(joined(body), pad + BOX_PAD_X, y + BOX_PAD_Y + head.height + body.lineHeight / 2 + small * 0.35,
            body.lineHeight, " font-size=\"" & jsString(small) & "\"") & "</g>"
    bottom = y + h
    y = bottom + CARD_GAP
    width = jsMax(width, w)
  for note in model.notes: card("note", "Note", note.frame, note.text)
  for spec in model.specifications:
    var rows = @["Given  " & spec.given.join(", ")]
    if spec.`when`.len > 0: rows.add "When  " & spec.`when`.join(", ")
    rows.add "Then  " & spec.then.join(", ")
    card("specification", "Given / When / Then", spec.frame, rows.join("\n"))
  let totalWidth = ceil(width + 2 * pad)
  let height = ceil(bottom + pad)
  let content = labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    edgesOut & nodes & cards
  Rendered(svg: svgDocument("eventmodeling", totalWidth, height, size, options, acc(model), content),
           width: totalWidth, height: height)

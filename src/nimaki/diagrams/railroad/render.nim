## port-of: src/diagrams/railroad/render.ts
## port-status: draft
##
## Port notes: Pele keys the width budgets by node object in a Map; here by the node's address.
import std/[options, strutils, tables]
from std/math import ceil
import ../../js
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[entities, label, measurer]
import ../../types
import ../../util/yaml
import ../common/fit_width
import common, types

type
  Kind = enum
    Terminal, NonTerminal, Special, Sequence, Choice, Bypass, Loop, Folded

  Box = ref object
    ## A laid-out element. The track enters at the left edge and leaves at the right edge on one
    ## baseline, with `up` above it and `down` below it.
    kind: Kind
    width, up, down: float
    kids: seq[Box]
    text: string     ## a leaf's text, or a loop's count
    id: string       ## the name a non-terminal refers to
    reach: float     ## how far a bypass rises above the baseline, or a loop drops below it

  Metrics = object
    measurer: TextMeasurer
    size, padding, height: float
    gap, sep: float  ## space between elements in a sequence, and between stacked branches
    arc: float

const
  LEAD = 12.0
  HEAD_GAP = 6.0
  RULE_GAP = 18.0
  COUNT_SIZE = 12.0
  ARROW = 7.0

proc option(config: Config, key: string, fallback, max: float): float =
  let value = config["railroad"][key]
  if value != nil and value.kind == yNumber and value.n >= 0: min(value.n, max) else: fallback

proc shown(text: string): string =
  ## Text is literal here: a terminal such as "<br>" or "*" is itself, not markup. Mermaid's `#35;`
  ## codes still stand for characters, and escapes that would be invisible are written out.
  let s = if "¶ß" in text: decodeEntities(text.replace("&", "&amp;")) else: text
  for c in s:
    case c
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add c

proc reverse[T](list: var seq[T], start: int) =
  var i = start
  var j = list.len - 1
  while i < j:
    swap(list[i], list[j])
    inc i
    dec j

func even(value: float): float = ceil(value / 2) * 2

proc leaf(kind: Kind, text, id: string, style: int, m: Metrics): Box =
  let half = m.height / 2
  let width = max(even(m.measurer.width(text, m.size, style) + 2 * m.padding), m.height)
  Box(kind: kind, width: width, up: half, down: half, text: text, id: id)

func countText(value: float): string =
  if value != Inf and value != -Inf and value == value: jsString(value) else: "∞"

func count(min, max: float): string =
  if max == Inf and min <= 1: return ""
  if min == max: return countText(min) & "×"
  if max == Inf: return "≥" & countText(min) & "×"
  if min == 0: "≤" & countText(max) & "×" else: countText(min) & "–" & countText(max) & "×"

func below(offset: float, above, branch: Box, m: Metrics): float =
  ## Where the next branch of a choice sits below the baseline, given the one above it.
  max(offset + above.down + m.sep + branch.up, 2 * m.arc)

func bypass(kid: Box, m: Metrics): Box =
  let reach = max(kid.up + m.sep, 2 * m.arc)
  Box(kind: Bypass, width: kid.width + 4 * m.arc, up: reach, down: kid.down, kids: @[kid], reach: reach)

func allSpaces(text: string): bool =
  ## /^ +$/
  if text == "": return false
  for c in text:
    if c != ' ': return false
  true

proc rowOf(row: seq[Box], width: float): Box =
  var up, down = 0.0
  for kid in row:
    up = max(up, kid.up)
    down = max(down, kid.down)
  Box(kind: Sequence, width: width, up: up, down: down, kids: row)

proc measure(root: RailroadNode, m: Metrics, room = Inf): Box =
  var budgets = initTable[int, float]()
  var pending: seq[(RailroadNode, float)] = @[(root, room)]
  var i = 0
  while room != Inf and i < pending.len:
    let (node, width) = pending[i]
    budgets[cast[int](node)] = width
    # A sequence that folds puts its rows inside rails, so its parts are sized for those rows.
    let around = case node.kind
      of nkChoice, nkOptional: 4 * m.arc
      of nkRepetition: (if node.min == 0: 6.0 else: 2.0) * m.arc
      of nkSequence: 6 * m.arc
      else: 0.0
    for child in partsOf(node): pending.add (child, max(40.0, width - around))
    inc i
  fold[RailroadNode, Box](root, partsOf, proc (node: RailroadNode, kids: seq[Box]): Box =
    let room = budgets.getOrDefault(cast[int](node), Inf)
    case node.kind
    of nkTerminal:
      let text = shown(node.text)
      leaf(Terminal, (if allSpaces(text): "␣".repeat(text.len) else: text), "", Mono, m)
    of nkNonterminal:
      leaf(NonTerminal, shown(node.text), node.text, 0, m)
    of nkSpecial:
      leaf(Special, "? " & shown(node.text) & " ?", "", Italic, m)
    of nkSequence:
      var width = float(max(0, kids.len - 1)) * m.gap
      var up, down = 0.0
      for kid in kids:
        width += kid.width
        up = max(up, kid.up)
        down = max(down, kid.down)
      let sequence = Box(kind: Sequence, width: width, up: up, down: down, kids: kids)
      if width <= room or kids.len < 2: return sequence
      var rows: seq[Box]
      var row: seq[Box]
      var rowW = 0.0
      for kid in kids:
        if row.len > 0 and rowW + m.gap + kid.width > max(40.0, room - 6 * m.arc):
          rows.add rowOf(row, rowW)
          row = @[]
          rowW = 0
        rowW += (if row.len > 0: m.gap else: 0.0) + kid.width
        row.add kid
      rows.add rowOf(row, rowW)
      if rows.len < 2: return sequence
      var foldedWidth, offset = 0.0
      for i in 0 ..< rows.len:
        foldedWidth = max(foldedWidth, rows[i].width)
        if i > 0: offset += rows[i - 1].down + max(m.sep, 2 * m.arc) + rows[i].up
      Box(kind: Folded, width: foldedWidth + 6 * m.arc, up: rows[0].up, down: offset + rows[^1].down, kids: rows)
    of nkChoice:
      var inner, offset = 0.0
      for i in 0 ..< kids.len:
        inner = max(inner, kids[i].width)
        if i > 0: offset = below(offset, kids[i - 1], kids[i], m)
      Box(kind: Choice, width: inner + 4 * m.arc,
          up: (if kids.len > 0: kids[0].up else: 0.0),
          down: (if kids.len > 0: offset + kids[^1].down else: 0.0), kids: kids)
    of nkOptional:
      bypass(kids[0], m)
    of nkRepetition:
      let (min, max) = (node.min, node.max)
      let kid = kids[0]
      if min == 1 and max == 1: return kid
      let text = count(min, max)
      let reach = max(kid.down + m.sep, 2 * m.arc)
      let label = if text == "": 0.0 else: even(m.measurer.width(text, COUNT_SIZE, 0))
      let loop = Box(kind: Loop, width: max(kid.width, label) + 2 * m.arc, up: kid.up,
                     down: reach + (if text == "": ARROW / 2 + 1 else: COUNT_SIZE + 6),
                     kids: @[kid], text: text, reach: reach)
      if min == 0: bypass(loop, m) else: loop)

proc draw(model: RailroadModel, config: Config, options: RenderOptions, tight: bool): Rendered

proc renderRailroad*(model: RailroadModel, config: Config, options: RenderOptions): Rendered =
  tighten(options, proc (tight: bool): Rendered = draw(model, config, options, tight))

proc draw(model: RailroadModel, config: Config, options: RenderOptions, tight: bool): Rendered =
  let base = options.fontSize.get(16)
  let fontSize = option(config, "fontSize", 0, 200)
  let size = if fontSize != 0: fontSize else: jsRound(base * 0.875)
  let headSize = if fontSize != 0: fontSize else: base
  let padding = option(config, "padding", -1, 200)
  let lineHeight = jsRound(size * 1.5)
  let m = Metrics(
    measurer: measurerOf(options),
    size: size,
    padding: (if padding < 0: 12.0 else: padding),
    height: even(lineHeight + (if padding < 0: 9.0 else: 2 * padding)),
    gap: min(option(config, "horizontalSeparation", 16, 500), if tight: 12.0 else: Inf),
    sep: option(config, "verticalSeparation", 10, 500),
    arc: min(option(config, "arcRadius", 10, 200), if tight: 6.0 else: Inf))
  let markers = config["railroad"]["showMarkers"]
  let radius = if markers != nil and markers.kind == yBool and not markers.b: 0.0
               else: option(config, "markerRadius", 4, 50)
  let strokeWidth = option(config, "strokeWidth", 0, 20)
  let stroke = if strokeWidth > 0: " stroke-width=\"" & num(strokeWidth) & "\"" else: ""
  let pad = options.padding.get(8)
  let arc = m.arc

  let A = num(arc)
  proc turn(sweep: int, dx, dy: string): string = "a" & A & "," & A & " 0 0 " & $sweep & " " & dx & A & "," & dy & A
  let eastToSouth = turn(1, "", "")
  let southToEast = turn(0, "", "")
  let eastToNorth = turn(0, "", "-")
  let northToEast = turn(1, "", "-")
  let loopDown = turn(0, "-", "")
  let loopUp = turn(0, "-", "-")

  let title = layoutLabel(model.title, false, m.measurer, base, (if tight: titleRoom(options) else: 4000.0), Bold)
  let titleHeight = if title.height > 0: title.height + 16 else: 0.0
  let headHeight = jsRound(headSize * 1.5)
  let textShift = size * 0.35
  let boxTop = m.height / 2

  var track = ""
  var arrows = ""
  var nodes = ""

  proc line(x1, y, x2: float) =
    if x2 > x1: track.add "M" & num(x1) & "," & num(y) & "H" & num(x2)

  proc place(root: Box, left, baseline: float) =
    var boxes = @[root]
    var at = @[left, baseline]
    while boxes.len > 0:
      let box = boxes.pop()
      let y = at.pop()
      let x = at.pop()
      let kids = box.kids
      let right = x + box.width
      case box.kind
      of Sequence:
        var kx = right
        for i in countdown(kids.len - 1, 0):
          kx -= kids[i].width
          boxes.add kids[i]
          at.add kx
          at.add y
          if i > 0: line(kx - m.gap, y, kx)
          kx -= m.gap
      of Folded:
        let start = x + 2 * arc
        let start0 = boxes.len
        var offset = 0.0
        line(x, y, start)
        for i in 0 ..< kids.len:
          let kid = kids[i]
          let ky = y + offset
          boxes.add kid
          at.add ky
          at.add start
          if i + 1 < kids.len:
            let next = kids[i + 1]
            let nextOffset = offset + kid.down + max(m.sep, 2 * arc) + next.up
            let mid = y + offset + kid.down + max(m.sep, 2 * arc) / 2
            track.add "M" & num(start + kid.width) & "," & num(ky) & "H" & num(right - 2 * arc) & "V" & num(mid) &
              "H" & num(x + arc) & "V" & num(y + nextOffset) & "H" & num(start)
            arrows.add "M" & num(start - ARROW) & "," & num(y + nextOffset - ARROW / 2) & "l7,3.5l-7,3.5z"
            offset = nextOffset
          else:
            track.add "M" & num(start + kid.width) & "," & num(ky) & "H" & num(right - arc) & "V" & num(y) & "H" & num(right)
        reverse(boxes, start0)
        reverse(at, 2 * start0)
      of Choice:
        let inner = box.width - 4 * arc
        let railIn = x + arc
        let railOut = right - arc
        let start0 = boxes.len
        var offset = 0.0
        for i in 0 ..< kids.len:
          let kid = kids[i]
          if i > 0: offset = below(offset, kids[i - 1], kid, m)
          let ky = y + offset
          let kx = x + 2 * arc + (inner - kid.width) / 2
          let last = i == kids.len - 1
          if i == 0:
            line(x, y, kx)
            line(kx + kid.width, y, right)
          else:
            track.add (if last: "M" & num(x) & "," & num(y) & eastToSouth & "V" & num(ky - arc)
                       else: "M" & num(railIn) & "," & num(ky - arc)) &
              southToEast &
              (if kx > railIn + arc: "H" & num(kx) else: "") &
              "M" & num(kx + kid.width) & "," & num(ky) &
              (if kx > railIn + arc: "H" & num(railOut - arc) else: "") &
              eastToNorth &
              (if last: "V" & num(y + arc) & northToEast else: "")
          boxes.add kid
          at.add ky
          at.add kx
        # Reversed, so that the branches come off the stack top to bottom.
        reverse(boxes, start0)
        reverse(at, 2 * start0)
      of Bypass:
        let kid = kids[0]
        let kx = x + 2 * arc
        line(x, y, kx)
        line(kx + kid.width, y, right)
        track.add "M" & num(x) & "," & num(y) & eastToNorth & "V" & num(y - box.reach + arc) & northToEast &
          "H" & num(right - 2 * arc) & eastToSouth & "V" & num(y - arc) & southToEast
        boxes.add kid
        at.add kx
        at.add y
      of Loop:
        let kid = kids[0]
        let kx = x + (box.width - kid.width) / 2
        let loopY = y + box.reach
        let middle = x + box.width / 2
        line(x, y, kx)
        line(kx + kid.width, y, right)
        track.add "M" & num(x + arc) & "," & num(y) & loopDown & "V" & num(loopY - arc) & southToEast &
          "H" & num(right - arc) & eastToNorth & "V" & num(y + arc) & loopUp
        arrows.add "M" & num(middle - ARROW / 2) & "," & num(loopY) & "l7,-3.5v7z"
        if box.text != "":
          nodes.add "<text class=\"pele-edge-label pele-count\" x=\"" & num(middle) & "\" y=\"" &
            num(loopY + COUNT_SIZE + 3) & "\" font-size=\"12\" fill=\"var(--_m)\">" & esc(box.text) & "</text>"
        boxes.add kid
        at.add kx
        at.add y
      else:
        let text = box.text
        let space = if text.startsWith(' ') or text.endsWith(' ') or "  " in text: " xml:space=\"preserve\"" else: ""
        let shape = "<rect x=\"" & num(x) & "\" y=\"" & num(y - boxTop) & "\" width=\"" & num(box.width) &
          "\" height=\"" & num(m.height) & "\""
        let label = "<text x=\"" & num(x + box.width / 2) & "\" y=\"" & num(y + textShift) & "\"" & space
        if box.kind == Terminal:
          nodes.add "<g class=\"pele-node pele-terminal\">" & shape & " rx=\"" & num(boxTop) &
            "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & stroke & "/>" & label & " font-family=\"" & FONT_MONO &
            "\">" & esc(text) & "</text></g>"
        elif box.kind == NonTerminal:
          nodes.add "<g class=\"pele-node pele-nonterminal\" data-id=\"" & escText(box.id) & "\">" & shape &
            " fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & stroke & ROUNDED & "/>" & label & ">" & esc(text) & "</text></g>"
        else:
          nodes.add "<g class=\"pele-node pele-special\">" & shape &
            " fill=\"var(--_bg)\" stroke=\"var(--_b)\" stroke-dasharray=\"4 3\"" & stroke & ROUNDED & "/>" &
            label & " font-style=\"italic\"><tspan fill=\"var(--_m)\">? </tspan>" & esc(text[2 ..< text.len - 2]) &
            "<tspan fill=\"var(--_m)\"> ?</tspan></text></g>"

  var rules = ""
  var width = title.width
  var top = pad + titleHeight
  var bottom = pad + title.height
  for rule in model.rules:
    let box = measure(rule.definition, m,
      if tight: max(80.0, options.maxWidth.get(320) - 2 * pad - 4 * radius - 2 * LEAD - 1) else: Inf)
    let name = shown(rule.name)
    let baseline = top + headHeight + HEAD_GAP + box.up
    let start = pad + 2 * radius
    let left = start + LEAD
    let stop = left + box.width + LEAD
    track = ""
    arrows = ""
    nodes = ""
    line(start, baseline, left)
    line(left + box.width, baseline, stop)
    place(box, left, baseline)
    let circles =
      if radius > 0:
        "<circle class=\"pele-marker pele-start\" cx=\"" & num(pad + radius) & "\" cy=\"" & num(baseline) &
          "\" r=\"" & num(radius) & "\" fill=\"var(--_l)\"/>" &
        "<circle class=\"pele-marker pele-end\" cx=\"" & num(stop + radius) & "\" cy=\"" & num(baseline) &
          "\" r=\"" & num(radius) & "\" fill=\"var(--_l)\"/>"
      else: ""
    rules.add "<g class=\"pele-rule\" data-id=\"" & escText(rule.name) & "\">" &
      "<text class=\"pele-rule-name\" x=\"" & num(pad) & "\" y=\"" & num(top + headHeight / 2 + headSize * 0.35) &
      "\" font-size=\"" & num(headSize) & "\" font-weight=\"var(--_hw)\" text-anchor=\"start\">" & esc(name) & "</text>" &
      "<path class=\"pele-edge pele-track\" d=\"" & track & "\" fill=\"none\" stroke=\"var(--_l)\"" & stroke & "/>" &
      (if arrows != "": "<path class=\"pele-marker\" d=\"" & arrows & "\" fill=\"var(--_l)\"/>" else: "") &
      circles & nodes & "</g>"
    width = max(width, max(stop + 2 * radius - pad, m.measurer.width(name, headSize, Bold)))
    bottom = baseline + box.down
    top = bottom + m.sep + RULE_GAP

  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(bottom + pad)
  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    (if rules != "": "<g class=\"pele-rules\" transform=\"translate(0.5,0.5)\" font-size=\"" & num(size) &
       "\" text-anchor=\"middle\">" & rules & "</g>" else: "")
  Rendered(svg: svgDocument("railroad", totalWidth, totalHeight, base, options,
                            Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
           width: totalWidth, height: totalHeight, links: @[])

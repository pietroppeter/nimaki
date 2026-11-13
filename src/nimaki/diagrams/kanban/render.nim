## port-of: src/diagrams/kanban/render.ts
## port-status: draft
import std/[options, tables, unicode]
from std/strutils import nil
from std/math import ceil, floor
import ../../preprocess
import ../../svg/[builder, root, theme, title]
import ../../text/[label, measurer, icons]
import ../../types
import ../../js
import ../../util/[yaml, url]
import ../common/[fit_width, icon]
import db

const
  COLUMN_GAP = 12.0
  COLUMN_PAD = 8.0
  CARD_PAD = 10.0
  CARD_GAP = 8.0
  META_GAP = 4.0
  ICON_GAP = 6.0

let PRIORITY = {
  # Mermaid names five priorities and gives Medium no color. Matching here ignores case. The high
  # ones are marked in the critical color and the low ones in the muted one, the nearer to Medium
  # the fainter. They are not series colors, as a theme may put those in any order.
  "very high": "stroke=\"" & CRITICAL & "\"",
  "high": "stroke=\"" & CRITICAL & "\" opacity=\"0.5\"",
  "low": "stroke=\"var(--_m)\" opacity=\"0.5\"",
  "very low": "stroke=\"var(--_m)\"",
}.toTable

proc fitLabel(raw: string, markdown: bool, measurer: TextMeasurer, size, max: float, base = 0): Label =
  ## Lays out text for a fixed width. A word too long for a line is broken between characters,
  ## because a card cannot grow sideways to hold it.
  let label = layoutLabel(raw, markdown, measurer, size, max, base)
  if label.width <= max: return label
  var lines: seq[seq[Span]]
  var widths: seq[float]
  var widest = 0.0
  var line: seq[Span]
  var width = 0.0
  template commit() =
    lines.add line
    widths.add width
    widest = jsMax(widest, width)
    line = @[]
    width = 0
  for i in 0 ..< label.lines.len:
    if label.widths[i] <= max:
      line = label.lines[i]
      width = label.widths[i]
      commit()
      continue
    for span in label.lines[i]:
      if span.hasIcon or span.math != nil:
        if width > 0 and width + span.width > max: commit()
        line.add span
        width += span.width
        continue
      var text = ""
      var start = width
      for ch in span.text.runes:
        let w = measurer.width($ch, size, span.style)
        if width > 0 and width + w > max:
          if text != "": line.add Span(text: text, style: span.style, width: width - start)
          commit()
          text = ""
          start = 0
        text.add $ch
        width += w
      if text != "": line.add Span(text: text, style: span.style, width: width - start)
    commit()
  var fitted = label
  fitted.lines = lines
  fitted.widths = widths
  fitted.width = widest
  fitted.height = float(lines.len) * label.lineHeight
  if label.heights.len > 0: withHeights(fitted) else: fitted

proc textBlock(label: Label, x, y: float, attrs: string, icons: IconResolver, atEnd = false): string =
  ## Writes a label with every line starting at x, or ending there, and the first line's box
  ## starting at y.
  for i in 0 ..< label.lines.len:
    let line = label.lines[i]
    let cy = y + lineMiddle(label, i)
    if line.len == 1 and not line[0].hasIcon and line[0].math == nil and (line[0].style and (Sub or Sup or Underline)) == 0:
      result.add "<text" & textStyle(attrs, line[0].style) & " x=\"" & num(x) & "\" y=\"" & num(cy + label.size * 0.35) &
        "\"" & (if atEnd: " text-anchor=\"end\"" else: "") & ">" & esc(line[0].text) & "</text>"
    else:
      let width = label.widths[i]
      result.add labelSvg(labelLine(label, i), x + (if atEnd: -width else: width) / 2, cy, attrs, icons)

type Card = object
  item: KanbanNode
  label, ticket, assigned: Label
  meta: float
    ## Height of the rows under the text that hold the ticket and the assignee.
  height: float

proc has(name: string): bool = name != "" and iconMarkup(name) != ""

proc renderKanban*(model: KanbanModel, config: Config, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let line = jsRound(size * 1.5)
  let smallLine = jsRound(small * 1.5)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  let conf = config["kanban"]
  let sectionWidth = conf["sectionWidth"]
  let glyph = small * 1.25
  # Math can't break across lines, so columns widen to hold the widest expression.
  var mathWidth = 0.0
  proc holds(raw: string, fontSize, reserved: float) =
    if raw == "" or not strutils.contains(raw, "$$"): return
    for spans in layoutLabel(raw, true, measurer, fontSize, Inf).lines:
      for span in spans:
        if span.math != nil: mathWidth = jsMax(mathWidth, span.math.width + reserved)
  for section in model.sections:
    let count = measurer.width($section.items.len, small, 0)
    holds(section.label, size, 2 * COLUMN_PAD + 8 + count + 12 + (if has(section.icon): glyph + ICON_GAP else: 0))
    for item in section.items:
      let reserved = 2 * (COLUMN_PAD + CARD_PAD)
      holds(item.label, small, reserved + (if has(item.icon): glyph + ICON_GAP else: 0))
      holds(item.ticket, small, reserved)
      holds(item.assigned, small, reserved)
  let ownWidth = jsMax(
    (if sectionWidth != nil and sectionWidth.kind == yNumber and sectionWidth.n > 0:
       jsMin(jsMax(sectionWidth.n, 80), 2000) else: 200),
    ceil(mathWidth))
  # A board wider than the width the host has is folded into rows of columns, which then
  # share the row between them.
  let room = if options.maxWidth.isSome and options.maxWidth.get > 0: options.maxWidth.get - 2 * pad else: Inf
  let count = model.sections.len
  let fits = float(count) * (ownWidth + COLUMN_GAP) - COLUMN_GAP <= room
  let perRow = if fits: max(count, 1)
               else: int(jsMax(1, floor((room + COLUMN_GAP) / (ownWidth + COLUMN_GAP))))
  let columnWidth = if fits: ownWidth
                    else: jsMax(jsMax(jsMin(ownWidth, room),
                                      jsMin(floor((room + COLUMN_GAP) / float(perRow)) - COLUMN_GAP, ownWidth * 2)),
                                ceil(mathWidth))
  let baseUrlValue = conf["ticketBaseUrl"]
  let baseUrl = if baseUrlValue != nil and baseUrlValue.kind == yString: baseUrlValue.s else: ""
  let cardWidth = columnWidth - 2 * COLUMN_PAD
  let textWidth = cardWidth - 2 * CARD_PAD
  var links: seq[LinkInfo]

  let sections = model.sections
  var titles: seq[Label]
  var countWidths: seq[float]
  var cards: seq[seq[Card]]
  var headHeight = line
  var bodyHeights: seq[float]
  for section in sections:
    let countWidth = measurer.width($section.items.len, small, 0)
    let reserved = countWidth + 12 + (if has(section.icon): glyph + ICON_GAP else: 0)
    let title = fitLabel(section.label, true, measurer, size, cardWidth - 8 - reserved, Bold)
    headHeight = jsMax(headHeight, title.height)
    countWidths.add countWidth
    titles.add title

    var list: seq[Card]
    var height = 0.0
    for item in section.items:
      let label = fitLabel(item.label, true, measurer, small, textWidth - (if has(item.icon): glyph + ICON_GAP else: 0))
      let ticket = fitLabel(item.ticket, false, measurer, small, textWidth)
      let assigned = fitLabel(item.assigned, false, measurer, small, textWidth)
      let meta = if ticket.width + assigned.width + 8 > textWidth: ticket.height + assigned.height
                 else: jsMax(ticket.height, assigned.height)
      let cardHeight = 2 * CARD_PAD + jsMax(label.height, smallLine) + (if meta != 0: META_GAP + meta else: 0)
      list.add Card(item: item, label: label, ticket: ticket, assigned: assigned, meta: meta, height: cardHeight)
      height += cardHeight + CARD_GAP
    cards.add list
    bodyHeights.add height
  headHeight += 2 * COLUMN_PAD
  var rowHeights: seq[float]
  var rowTops: seq[float]
  var first = 0
  var y = 0.0
  while first < sections.len:
    var tallest = CARD_GAP
    for index in first ..< min(first + perRow, sections.len): tallest = jsMax(tallest, bodyHeights[index])
    rowTops.add y
    rowHeights.add headHeight + tallest
    y += headHeight + tallest + COLUMN_GAP
    first += perRow
  let boardHeight = if rowHeights.len > 0: rowTops[^1] + rowHeights[^1] else: 0

  let title = titleLabel(model.title, measurer, size, titleRoom(options))
  let titleHeight = if title.height > 0: title.height + 16 else: 0
  let boardWidth = jsMax(float(min(sections.len, perRow)) * (columnWidth + COLUMN_GAP) - COLUMN_GAP, 0)
  let width = jsMax(boardWidth, title.width)
  let left = pad + (width - boardWidth) / 2
  let edge = columnWidth - COLUMN_PAD - 4

  var output = ""
  for index in 0 ..< sections.len:
    let section = sections[index]
    let row = index div perRow
    var body =
      "<rect width=\"" & jsString(columnWidth) & "\" height=\"" & num(rowHeights[row]) & "\" fill=\"var(--_s)\"" & ROUNDED & "/>" &
      textBlock(titles[index], COLUMN_PAD + 4, COLUMN_PAD, " class=\"pele-cluster-label\" font-weight=\"var(--_hw)\"", icons) &
      "<text class=\"pele-count\" x=\"" & jsString(edge) & "\" y=\"" & num(COLUMN_PAD + line / 2 + small * 0.35) &
      "\" text-anchor=\"end\" font-size=\"" & jsString(small) & "\" fill=\"var(--_m)\">" & $section.items.len & "</text>"
    if has(section.icon):
      body.add iconSvg(section.icon, edge - countWidths[index] - ICON_GAP - glyph, COLUMN_PAD + (line - glyph) / 2, glyph, icons)

    var y = headHeight
    for card in cards[index]:
      let item = card.item
      let priority = unicode.toLower(jsTrim(item.priority))
      let hasColor = priority in PRIORITY
      let color = PRIORITY.getOrDefault(priority, "")
      var inner = "<rect width=\"" & jsString(cardWidth) & "\" height=\"" & num(card.height) &
        "\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & ROUNDED & "/>"
      if hasColor:
        inner.add "<path class=\"pele-priority\" d=\"M2.5,5V" & num(card.height - 5) & "\" fill=\"none\" " & color &
          " stroke-width=\"3\" stroke-linecap=\"round\"/>"
      inner.add textBlock(card.label, CARD_PAD, CARD_PAD, " class=\"pele-label\"", icons)
      if has(item.icon):
        inner.add iconSvg(item.icon, cardWidth - CARD_PAD - glyph, CARD_PAD + (smallLine - glyph) / 2, glyph, icons)
      let bottom = card.height - CARD_PAD
      if item.ticket != "":
        let top = bottom - card.meta
        let href = if baseUrl != "": linkUrl(safeUrl(baseUrl.replaceFirst("#TICKET#", item.ticket)), options)
                   else: none(string)
        if href.isNone:
          inner.add textBlock(card.ticket, CARD_PAD, top, " class=\"pele-ticket\" fill=\"var(--_m)\"", icons)
        else:
          inner.add "<a href=\"" & esc(href.get) & "\" target=\"_blank\"" & relAttr(options) & ">" &
            textBlock(card.ticket, CARD_PAD, top, " class=\"pele-ticket\" fill=\"var(--_c)\"", icons) & "</a>"
          links.add LinkInfo(id: item.id, href: href.get, internal: false)
      if item.assigned != "":
        inner.add textBlock(card.assigned, cardWidth - CARD_PAD, bottom - card.assigned.height,
                            " class=\"pele-assigned\" fill=\"var(--_m)\"", icons, true)
      body.add "<g class=\"pele-node pele-card" &
        (if hasColor: " pele-priority-" & priority.replaceFirst(" ", "-") else: "") & classNames(item.cssClasses) &
        "\" data-id=\"" & escText(item.id) & "\" transform=\"translate(" & jsString(COLUMN_PAD) & "," & num(y) &
        ")\" font-size=\"" & jsString(small) & "\">" & inner & "</g>"
      y += card.height + CARD_GAP

    output.add "<g class=\"pele-cluster pele-column" & classNames(section.cssClasses) & "\" data-id=\"" &
      escText(section.id) & "\" transform=\"translate(" &
      num(left + float(index mod perRow) * (columnWidth + COLUMN_GAP)) & "," & num(pad + titleHeight + rowTops[row]) &
      ")\">" & body & "</g>"

  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(boardHeight + titleHeight + 2 * pad)
  let content = labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") & output

  Rendered(
    svg: svgDocument("kanban", totalWidth, totalHeight, size, options, Accessible(), content),
    width: totalWidth,
    height: totalHeight,
    links: links)

## port-of: src/diagrams/timeline/render.ts
## port-status: conformant
import std/options
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, edges, root, palette, theme]
import ../../text/[label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/[fit_width, fit]
import db

const
  PAD_X = 12.0
  PAD_Y = 8.0
  MIN_TEXT = 152.0
  MAX_TEXT = 216.0
  EVENT_TEXT_TD = 264.0
  GAP = 20.0
  AXIS = 20.0
  SPINE = 14.0
  EVENT_GAP = 8.0
  SECTION_GAP = 8.0
  TAIL = 12.0
  ON_COLOR = " fill=\"var(--_bg)\""
  LINE = " fill=\"none\" stroke=\"var(--_b)\""
  NO_SERIES = -1   ## Pele's undefined series

type Group = object
  section: int
  periods: seq[int]

proc box(x, y, w, h: float, attrs: string): string =
  "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\"" &
    rounded(attrs) & "/>"

proc draw(model: TimelineModel, config: Config, options: RenderOptions, vertical: bool): Rendered

proc renderTimeline*(model: TimelineModel, config: Config, options: RenderOptions): Rendered =
  if model.direction == "TD": return draw(model, config, options, true)
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

proc draw(model: TimelineModel, config: Config, options: RenderOptions, vertical: bool): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let flag = config["timeline"]["disableMulticolor"]
  let multicolor = not (flag != nil and flag.kind == yBool and flag.b)
  let periods = model.periods
  let hasSections = model.sections.len > 0

  # Mermaid draws nothing for periods that come before the first section; here they lead, in a
  # neutral color.
  var groups: seq[Group]
  for section in 0 ..< model.sections.len: groups.add Group(section: section)
  var leading = Group(section: -1)
  for i, period in periods:
    if period.sectionIndex >= 0 and period.sectionIndex < groups.len: groups[period.sectionIndex].periods.add i
    else: leading.periods.add i
  if leading.periods.len > 0: groups.insert(leading, 0)

  # Columns widen, up to a point, for a word that would not fit; past that the word is cut.
  # Running down, the two columns share the width the host has.
  let room = if vertical and options.maxWidth.isSome and options.maxWidth.get > 0: options.maxWidth.get - 2 * pad
             else: Inf
  let taken = AXIS + SPINE * 2 + 4 * PAD_X
  let periodText = jsMin(MIN_TEXT, jsMax(80, jsRound((room - taken) * 0.38)))
  let eventText = jsMin(EVENT_TEXT_TD, jsMax(110, room - taken - periodText))
  var textW = periodText
  template eventTextW(): float = (if vertical: eventText else: textW)
  var periodLabels: seq[Label]
  for p in periods: periodLabels.add plainLabel(p.text, measurer, size, textW)
  var eventLabels: seq[seq[Label]]
  for p in periods:
    var labels: seq[Label]
    for e in p.events: labels.add plainLabel(e, measurer, small, eventTextW())
    eventLabels.add labels
  var widest = 0.0
  for label in periodLabels: widest = jsMax(widest, label.width)
  if not vertical:
    for labels in eventLabels:
      for label in labels: widest = jsMax(widest, label.width)
  var overflow = widest > textW
  if vertical:
    for labels in eventLabels:
      for label in labels: overflow = overflow or label.width > eventText
  if overflow:
    textW = jsMin(jsMax(ceil(widest), periodText), if room == Inf: MAX_TEXT else: periodText)
    periodLabels.setLen 0
    for p in periods: periodLabels.add fitLabel(p.text, measurer, size, textW)
    eventLabels.setLen 0
    for p in periods:
      var labels: seq[Label]
      for e in p.events: labels.add fitLabel(e, measurer, small, eventTextW())
      eventLabels.add labels

  let lineHeight = jsRound(size * 1.5)
  let colW = textW + 2 * PAD_X
  let eventW = eventTextW() + 2 * PAD_X
  proc chipHeight(label: Label): float = jsMax(label.height, lineHeight) + 2 * PAD_Y
  proc eventHeight(label: Label): float = jsMax(label.height, jsRound(small * 1.5)) + 2 * PAD_Y
  proc seriesOf(group: Group, period: int): int =
    if group.section >= 0: group.section
    elif hasSections: NO_SERIES
    elif multicolor: period
    else: 0
  proc colorOf(group: Group, period: int): string =
    let series = seriesOf(group, period)
    if series == NO_SERIES: "var(--_m)" else: seriesColor(series)
  proc onColor(series: int): string =
    let fill = if series == NO_SERIES: "" else: seriesInkFill(series)
    if fill != "": fill else: ON_COLOR

  var hasEvents = false
  for labels in eventLabels:
    if labels.len > 0: hasEvents = true
  var slots = 0
  for group in groups: slots += max(group.periods.len, 1)

  let pitch = colW + GAP
  let drawn = periods.len > 0
  let bodyW =
    if vertical: colW + (if hasEvents: AXIS + SPINE * 2 + eventW elif drawn: AXIS + TAIL else: 0)
    elif slots > 0: float(slots) * pitch - GAP + (if drawn: TAIL + ARROW else: 0)
    else: 0.0
  let title = fitLabel(model.title, measurer, size, jsMax(bodyW, 320), Bold)
  let titleH = if title.height > 0: title.height + 16 else: 0
  let width = jsMax(bodyW, title.width)
  let left = pad + (width - bodyW) / 2
  let top = pad + titleH

  proc sectionLabel(group: Group, w: float): Label =
    fitLabel(model.sections[group.section], measurer, size, w - 2 * PAD_X, Bold)
  proc header(group: Group, label: Label, x, y, w, h: float): string =
    box(x, y, w, h, " fill=\"" & seriesColor(group.section) & "\"") &
      labelSvg(label, x + w / 2, y + h / 2, " font-weight=\"var(--_hw)\"" & onColor(group.section))
  proc period(i: int, group: Group, color: string, x, y, h: float): string =
    box(x, y, colW, h, " fill=\"" & color & "\"") &
      labelSvg(periodLabels[i], x + colW / 2, y + h / 2, onColor(seriesOf(group, i)))
  proc event(label: Label, color: string, x, y, h: float): string =
    "<g class=\"pele-node pele-event\">" &
      box(x, y, eventW, h, " fill=\"" & color & "\" fill-opacity=\"0.16\"") &
      labelSvg(label, x + eventW / 2, y + h / 2, " font-size=\"" & jsString(small) & "\"") &
      "</g>"
  proc dot(x, y: float, color: string): string =
    "<circle class=\"pele-dot\" cx=\"" & num(x) & "\" cy=\"" & num(y) & "\" r=\"4\" fill=\"" & color &
      "\" stroke=\"var(--_bg)\" stroke-width=\"2\"/>"
  proc opening(group: Group): string =
    if group.section >= 0:
      "<g class=\"pele-cluster pele-section\" data-id=\"" & escText(jsTrim(model.sections[group.section])) & "\">"
    else: ""
  proc openPeriod(i: int): string =
    "<g class=\"pele-node pele-period\" data-id=\"" & escText(jsTrim(periods[i].text)) & "\">"

  var body = ""
  var height: float

  if vertical:
    let axisX = left + colW + AXIS
    let spineX = axisX + SPINE
    let eventsX = spineX + SPINE
    var y = top
    for group in groups:
      body.add opening(group)
      if group.section >= 0:
        let label = sectionLabel(group, bodyW)
        let h = chipHeight(label)
        body.add header(group, label, left, y, bodyW, h)
        y += h + SECTION_GAP + 4
      for i in group.periods:
        let color = colorOf(group, i)
        let h = chipHeight(periodLabels[i])
        # A period and its first event share one center line, so the line between them runs straight.
        let first = if eventLabels[i].len > 0: eventHeight(eventLabels[i][0]) else: h
        let cy = y + jsMax(h, first) / 2
        var d = "M" & num(left + colW) & "," & num(cy) & "H" & num(axisX)
        var cards = ""
        var ey = cy - first / 2
        var last = cy
        for label in eventLabels[i]:
          let eh = eventHeight(label)
          last = ey + eh / 2
          d.add "M" & num(spineX) & "," & num(last) & "H" & num(eventsX)
          cards.add event(label, color, eventsX, ey, eh)
          ey += eh + EVENT_GAP
        if cards != "": d.add "M" & num(axisX) & "," & num(cy) & "H" & num(spineX) & "V" & num(last)
        body.add openPeriod(i) &
          period(i, group, color, left, cy - h / 2, h) &
          "<path class=\"pele-edge\" d=\"" & d & "\"" & LINE & "/>" &
          dot(axisX, cy, color) &
          cards &
          "</g>"
        y = jsMax(cy + h / 2, ey - EVENT_GAP) + GAP
      if group.periods.len == 0: y += GAP - SECTION_GAP - 4
      if group.section >= 0: body.add "</g>"
    if groups.len > 0: y -= GAP
    if drawn:
      let tip = y + TAIL + ARROW
      body = "<path class=\"pele-axis\" d=\"M" & num(axisX) & "," & num(top) & "V" & num(tip - ARROW + 1) &
        "\" fill=\"none\" stroke=\"var(--_l)\"/>" &
        marker("arrow_point", axisX, tip, 0, 1, "var(--_l)") &
        body
      y = tip
    height = y + pad
  else:
    var headerH = 0.0
    var sectionLabels: seq[Option[Label]]
    for group in groups:
      if group.section < 0:
        sectionLabels.add none(Label)
        continue
      let label = sectionLabel(group, float(max(group.periods.len, 1)) * pitch - GAP)
      headerH = jsMax(headerH, chipHeight(label))
      sectionLabels.add some(label)
    var chipH = 0.0
    for label in periodLabels: chipH = jsMax(chipH, chipHeight(label))
    let periodsY = top + (if hasSections: headerH + SECTION_GAP else: 0)
    let axisY = periodsY + chipH + (if chipH > 0: AXIS else: 0)
    let eventsY = axisY + AXIS
    var bottom = if drawn: axisY + TAIL else: top + headerH
    var slot = 0
    for g, group in groups:
      let span = max(group.periods.len, 1)
      let gx = left + float(slot) * pitch
      body.add opening(group)
      let label = sectionLabels[g]
      if label.isSome: body.add header(group, label.get, gx, top, float(span) * pitch - GAP, headerH)
      for k, i in group.periods:
        let color = colorOf(group, i)
        let x = gx + float(k) * pitch
        let cx = x + colW / 2
        var d = "M" & num(cx) & "," & num(periodsY + chipH) & "V" &
          num(if eventLabels[i].len > 0: eventsY else: axisY)
        var cards = ""
        var ey = eventsY
        for eventLabel in eventLabels[i]:
          let eh = eventHeight(eventLabel)
          if ey > eventsY: d.add "M" & num(cx) & "," & num(ey - EVENT_GAP) & "V" & num(ey)
          cards.add event(eventLabel, color, x, ey, eh)
          ey += eh + EVENT_GAP
        bottom = jsMax(bottom, ey - EVENT_GAP)
        body.add openPeriod(i) &
          period(i, group, color, x, periodsY, chipH) &
          "<path class=\"pele-edge\" d=\"" & d & "\"" & LINE & "/>" &
          dot(cx, axisY, color) &
          cards &
          "</g>"
      if group.section >= 0: body.add "</g>"
      slot += span
    if drawn:
      let tip = left + bodyW
      body = "<path class=\"pele-axis\" d=\"M" & num(left) & "," & num(axisY) & "H" & num(tip - ARROW + 1) &
        "\" fill=\"none\" stroke=\"var(--_l)\"/>" &
        marker("arrow_point", tip, axisY, 1, 0, "var(--_l)") &
        body
    height = bottom + pad

  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(jsMax(height, pad * 2))
  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") & body
  Rendered(
    svg: svgDocument("timeline", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight)

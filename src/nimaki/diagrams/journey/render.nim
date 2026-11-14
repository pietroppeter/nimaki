## port-of: src/diagrams/journey/render.ts
## port-status: conformant
import std/[options, tables]
from std/math import ceil, isNaN
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../js
import ../common/[fit_width, fit]
import db

const
  PAD_X = 10.0
  PAD_Y = 8.0
  MIN_TEXT = 124.0
  MAX_TEXT = 200.0
  GAP = 12.0
  BAND_PAD = 6.0
  GUTTER = 24.0
  LEVEL = 26.0
  FACE = 11.0
  DOT = 5.0
  DOT_STEP = 13.0
  LEGEND_GAP = 20.0

const EYES = "<circle cx=\"-3.6\" cy=\"-2.8\" r=\"1.3\"/><circle cx=\"3.6\" cy=\"-2.8\" r=\"1.3\"/>"
const MOUTHS = {"happy": "M-5,2A6,6 0 0 0 5,2", "neutral": "M-4.5,4.5H4.5", "sad": "M-5,6.5A6,6 0 0 1 5,6.5"}.toTable

proc face(x, y: float, mood: string): string =
  "<g class=\"pele-face pele-face-" & mood & "\" transform=\"translate(" & num(x) & "," & num(y) & ")\">" &
    "<circle r=\"" & jsString(FACE) & "\" fill=\"var(--_bg)\" stroke=\"var(--_l)\"/>" &
    "<g fill=\"var(--_l)\">" & EYES & "</g>" &
    "<path d=\"" & MOUTHS[mood] & "\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\"/>" &
    "</g>"

func mood(score: float): string =
  if score > 3: "happy" elif score < 3: "sad" else: "neutral"

proc draw(model: JourneyModel, config: Config, options: RenderOptions, down: bool): Rendered
proc verticalJourney(model: JourneyModel, options: RenderOptions): Rendered

proc renderJourney*(model: JourneyModel, config: Config, options: RenderOptions): Rendered =
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

type LegendItem = object
  name: string
  label: Label
  x, y, h: float

type Run = object
  start, count: int
  label: Option[Label]

proc draw(model: JourneyModel, config: Config, options: RenderOptions, down: bool): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.75)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  if down: return verticalJourney(model, options)
  let tasks = model.tasks
  let n = tasks.len

  # `Task: 5:` names an actor with no name; Mermaid gives it a dot and an empty legend row.
  var names: seq[string]
  for name in journeyActors(tasks):
    if name != "": names.add name
  var actor = initTable[string, int]()
  for i, name in names: actor[name] = i

  # Cards widen, up to a point, for a word that would not fit; past that the word is cut.
  var textW = MIN_TEXT
  var labels: seq[Label]
  for task in tasks: labels.add plainLabel(task.task, measurer, small, textW)
  var widest = 0.0
  for label in labels: widest = jsMax(widest, label.width)
  if widest > textW:
    textW = jsMin(ceil(widest), MAX_TEXT)
    labels.setLen 0
    for task in tasks: labels.add fitLabel(task.task, measurer, small, textW)

  let cardW = textW + 2 * PAD_X
  let pitch = cardW + GAP
  let plotW = if n > 0: float(n) * pitch - GAP else: 0.0

  let lineH = jsRound(small * 1.5)
  let limit = jsMax(plotW, 240)
  var legend: seq[LegendItem]
  var legendW = 0.0
  var legendH = 0.0
  var lx = 0.0
  for name in names:
    let label = fitLabel(name, measurer, small, limit - 2 * DOT - 6)
    let w = 2 * DOT + 6 + label.width
    if lx > 0 and lx + w > limit:
      lx = 0
      legendH += 4
    let y = if lx > 0: legend[^1].y else: legendH
    let h = jsMax(label.height, lineH)
    legend.add LegendItem(name: name, label: label, x: lx, y: y, h: h)
    lx += w
    legendW = jsMax(legendW, lx)
    legendH = jsMax(legendH, y + h)
    lx += LEGEND_GAP

  let bodyW = if n > 0: GUTTER + plotW else: 0.0
  let title = fitLabel(model.title, measurer, size, jsMax(bodyW, 320), Bold)
  let titleH = if title.height > 0: title.height + 16 else: 0
  let width = jsMax(jsMax(bodyW, title.width), if n > 0: GUTTER + legendW else: 0)
  let left = pad + (width - bodyW) / 2 + GUTTER
  let top = pad + titleH

  # A band covers a run of tasks that share a section, as in Mermaid; a section with no tasks
  # draws nothing.
  var runs: seq[Run]
  var bandH = 0.0
  var i = 0
  while i < n:
    var stop = i + 1
    while stop < n and tasks[stop].section == tasks[i].section: inc stop
    var label = none(Label)
    if tasks[i].section != "":
      let l = fitLabel(tasks[i].section, measurer, small, float(stop - i) * pitch - GAP - 2 * PAD_X, Bold)
      label = some(l)
      bandH = jsMax(bandH, jsMax(l.height, lineH) + 2 * BAND_PAD)
    runs.add Run(start: i, count: stop - i, label: label)
    i = stop

  var textH = lineH
  for label in labels: textH = jsMax(textH, label.height)
  let dotsH = if names.len > 0: 2 * DOT + 6 else: 0.0
  let cardH = textH + dotsH + 2 * PAD_Y
  let cardsY = top + (if bandH > 0: bandH + BAND_PAD else: 0)
  let chartTop = cardsY + cardH + FACE + 16
  let chartBottom = chartTop + 4 * LEVEL
  let right = left + plotW

  var body = ""
  var bottom = top
  if n > 0:
    var grid = ""
    var scale = ""
    for score in countdown(5, 1):
      let y = chartTop + float(5 - score) * LEVEL
      grid.add "M" & num(left - 6) & "," & num(y) & "H" & num(right)
      scale.add "<text x=\"" & num(left - 12) & "\" y=\"" & num(y + tiny * 0.35) & "\">" & $score & "</text>"
    body.add "<path class=\"pele-grid\" d=\"" & grid & "\" fill=\"none\" stroke=\"var(--_a)\"/>" &
      "<g class=\"pele-scale\" font-size=\"" & jsString(tiny) & "\" text-anchor=\"end\" fill=\"var(--_m)\">" & scale & "</g>"

    var line = ""
    var stems = ""
    var faces = ""
    var cards: seq[string]
    for i, task in tasks:
      let x = left + float(i) * pitch
      let cx = x + cardW / 2
      let score = task.score
      let level = if score.isNaN: 3.0 else: jsMin(5, jsMax(1, score))
      let y = chartTop + (5 - level) * LEVEL
      line.add (if i == 0: "M" else: "L") & num(cx) & "," & num(y)
      stems.add "M" & num(cx) & "," & num(cardsY + cardH) & "V" & num(y - FACE)
      faces.add face(cx, y, mood(score))

      var dots = ""
      var people: seq[string]
      for name in task.people:
        if name != "": people.add name
      let step = jsMin(DOT_STEP, (cardW - 2 * PAD_X - 2 * DOT) / float(max(people.len - 1, 1)))
      for k, name in people:
        dots.add "<circle class=\"pele-actor\" cx=\"" & num(cx + (float(k) - float(people.len - 1) / 2) * step) &
          "\" cy=\"" & num(cardsY + cardH - PAD_Y - DOT) & "\" r=\"" & jsString(DOT) & "\" fill=\"" &
          seriesColor(actor.getOrDefault(name, 0)) & "\" stroke=\"var(--_s)\">" &
          "<title>" & escText(name) & "</title></circle>"
      cards.add "<g class=\"pele-node pele-task\" data-id=\"" & escText(jsTrim(task.task)) & "\">" &
        "<rect x=\"" & num(x) & "\" y=\"" & num(cardsY) & "\" width=\"" & num(cardW) & "\" height=\"" &
        num(cardH) & "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
        labelSvg(labels[i], cx, cardsY + PAD_Y + textH / 2, " font-size=\"" & jsString(small) & "\"") &
        dots &
        "</g>"
    body.add "<path class=\"pele-stems\" d=\"" & stems & "\" fill=\"none\" stroke=\"var(--_b)\" stroke-dasharray=\"2 3\"/>" &
      (if n > 1: "<path class=\"pele-edge\" d=\"" & line & "\" fill=\"none\" stroke=\"var(--_l)\" stroke-linejoin=\"round\"/>" else: "") &
      faces

    for run in runs:
      var members = ""
      for k in run.start ..< run.start + run.count: members.add cards[k]
      if run.label.isNone:
        body.add members
        continue
      let x = left + float(run.start) * pitch
      let w = float(run.count) * pitch - GAP
      body.add "<g class=\"pele-cluster pele-section\" data-id=\"" & escText(jsTrim(tasks[run.start].section)) & "\">" &
        "<rect x=\"" & num(x) & "\" y=\"" & num(top) & "\" width=\"" & num(w) & "\" height=\"" & num(bandH) &
        "\" fill=\"var(--_a)\"" & ROUNDED & "/>" &
        labelSvg(run.label.get, x + w / 2, top + bandH / 2, " font-size=\"" & jsString(small) & "\" font-weight=\"var(--_hw)\"") &
        members &
        "</g>"
    bottom = chartBottom + FACE

    if legend.len > 0:
      let x0 = left + (plotW - legendW) / 2
      let y0 = bottom + 16
      var items = ""
      for item in legend:
        let cy = y0 + item.y + item.h / 2
        items.add "<g class=\"pele-legend-item\" data-id=\"" & escText(item.name) & "\">" &
          "<circle cx=\"" & num(x0 + item.x + DOT) & "\" cy=\"" & num(cy) & "\" r=\"" & jsString(DOT) &
          "\" fill=\"" & seriesColor(actor.getOrDefault(item.name, 0)) & "\"/>" &
          labelSvg(item.label, x0 + item.x + 2 * DOT + 6 + item.label.width / 2, cy, "") &
          "</g>"
      body.add "<g class=\"pele-legend\" font-size=\"" & jsString(small) & "\">" & items & "</g>"
      bottom = y0 + legendH

  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(jsMax(bottom, pad) + pad)
  let content =
    labelSvg(title, pad + width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") & body
  Rendered(
    svg: svgDocument("journey", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight)

proc verticalJourney(model: JourneyModel, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let room = jsMax(140, options.maxWidth.get(320) - 2 * pad)
  let title = fitLabel(model.title, measurer, size, room, Bold)
  var names: seq[string]
  for name in journeyActors(model.tasks):
    if name != "": names.add name
  var actors = initTable[string, int]()
  for i, name in names: actors[name] = i
  var y = pad + (if title.height != 0: title.height + 16 else: 0)
  var section = none(string)   # undefined until the first task
  var body = ""
  var width = title.width
  for index, task in model.tasks:
    if section != some(task.section):
      section = some(task.section)
      let head = fitLabel(task.section, measurer, size, room - 16, Bold)
      if head.height != 0:
        body.add labelSvg(head, pad + 8 + head.width / 2, y + head.height / 2, " class=\"pele-cluster-label\" font-weight=\"var(--_hw)\"")
        width = jsMax(width, head.width + 16)
        y += head.height + 8
    let label = fitLabel(task.task, measurer, small, room - 72)
    var people: seq[(string, Label)]
    for name in task.people:
      if name != "": people.add (name, fitLabel(name, measurer, small, room - 44))
    let textH = jsMax(label.height, 42)
    var h = 2 * PAD_Y + textH
    for person in people: h += jsMax(16, person[1].height) + 4
    let w = jsMax(room, label.width + 72)
    body.add "<g class=\"pele-node pele-journey-step\" data-id=\"" & $index & "\"><rect x=\"" & num(pad) &
      "\" y=\"" & num(y) & "\" width=\"" & num(w) & "\" height=\"" & num(h) & "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" &
      ROUNDED & "/>"
    body.add labelSvg(label, pad + PAD_X + label.width / 2, y + PAD_Y + label.height / 2, " class=\"pele-label\"")
    let cx = pad + w - 28
    body.add face(cx, y + PAD_Y + FACE, mood(task.score))
    if not task.score.isNaN:
      body.add "<text class=\"pele-journey-score\" x=\"" & num(cx) & "\" y=\"" & num(y + PAD_Y + 2 * FACE + small) &
        "\" font-size=\"" & jsString(small) & "\" text-anchor=\"middle\">" & num(jsMin(5, jsMax(1, task.score))) & "</text>"
    var py = y + PAD_Y + textH + 4
    for person in people:
      let ph = jsMax(16, person[1].height)
      body.add "<circle class=\"pele-actor\" cx=\"" & num(pad + 16) & "\" cy=\"" & num(py + ph / 2) & "\" r=\"" &
        jsString(DOT) & "\" fill=\"" & seriesColor(actors[person[0]]) & "\"/>" &
        labelSvg(person[1], pad + 28 + person[1].width / 2, py + ph / 2, " class=\"pele-journey-actor\" font-size=\"" & jsString(small) & "\"")
      py += ph + 4
    body.add "</g>"
    y += h
    if index + 1 < model.tasks.len:
      body.add "<path class=\"pele-edge\" d=\"M" & num(pad + w / 2) & "," & num(y) & "v16\" fill=\"none\" stroke=\"var(--_l)\"/>"
    y += 16
    width = jsMax(width, w)
  let totalWidth = ceil(width + 2 * pad)
  let height = ceil(jsMax(pad + title.height, y - (if model.tasks.len > 0: 16 else: 0)) + pad)
  let content = labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") & body
  Rendered(svg: svgDocument("journey", totalWidth, height, size, options,
                            Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
           width: totalWidth, height: height)

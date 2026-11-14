## port-of: src/diagrams/treemap/render.ts
## port-status: draft
import std/[options, strutils]
from std/math import ceil, floor, classify, FloatClass
import ../../jsmath
import ../../preprocess
import ../../svg/[builder, ink, root, palette, theme]
import ../../text/[entities, label, measurer]
import ../../types
import ../../js
import ../../jsregex
import ../../util/yaml
import ../common/[fit_width, fit_text]
import format, layout, model

const
  HEADER = 28.0
  SHORT_HEADER = 18.0
  SIDE = 6.0
  LINE = 1.25

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

proc titlePart(raw: string): string = jsTrim(esc(jsTrim(decodeEntities(raw))))

proc leafCount(roots: seq[TreemapNode]): int =
  var stack = roots
  while stack.len > 0:
    let node = stack.pop()
    if not node.leaf: stack.add node.children
    elif node.value.isSome and node.value.get.isFinite and node.value.get > 0: inc result

proc replaceFirst(s, sub, by: string): string =
  let at = s.find(sub)
  if at < 0: s else: s[0 ..< at] & by & s[at + sub.len .. ^1]

proc corners(attrs: string, b: Box): string =
  ## Caps corners at a quarter of a small box's shorter side; 4px is the default radius.
  let cap = jsMin(b.w, b.h) / 4
  if cap < 4: rounded(attrs).replaceFirst("rx:var(--_r)", "rx:min(var(--_r)," & num(cap) & "px)") else: rounded(attrs)

proc option(config: Config, key: string, fallback, min, max: float): float =
  let value = config["treemap"][key]
  if value != nil and value.kind == yNumber and value.n >= min: jsMin(value.n, max) else: fallback

proc renderTreemap*(model: TreemapModel, config: Config, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.75)
  let least = jsRound(size * 0.5625)
  let measurer = measurerOf(options)
  let treemap = config["treemap"]   # nil stands for Pele's `?? {}`
  let pad = if options.padding.isSome: options.padding.get else: option(config, "diagramPadding", 8, 0, 2000)

  # Mermaid sizes the diagram as ten times `nodeWidth` by ten times `nodeHeight`.
  let width = jsRound(capWidth(options, option(config, "nodeWidth", 64, 1, 400) * 10, 200, 2 * pad))
  let height = jsRound(option(config, "nodeHeight", 40, 1, 400) * 10)
  let showValuesValue = treemap["showValues"]
  let showValues = not (showValuesValue != nil and showValuesValue.kind == yBool and not showValuesValue.b)
  let valueFormat = treemap["valueFormat"]
  let format = formatter(if valueFormat != nil and valueFormat.kind == yString: valueFormat.s else: ",")
  # Reduce gaps and insets as average leaf area shrinks.
  let crowd = jsMin(1, jsMax(0, log10((width * height) / jsMax(1, float(leafCount(model.roots))) / 800)))
  let boxes = layoutTreemap(model.roots, width, height, Insets(
    gap: option(config, "padding", jsRound(2 + 2 * crowd), 0, 200),
    header: HEADER,
    short: SHORT_HEADER,
    side: jsRound(3 + 3 * crowd)))

  let title = layoutLabel(model.title, false, measurer, size, titleRoom(options), Bold)
  let titleHeight = if title.height > 0: title.height + 8 else: 0
  let left = pad + jsMax(0, (title.width - width) / 2)
  let top = pad + titleHeight

  var sections = ""
  var leaves = ""
  for b in boxes:
    let node = b.node
    let style = resolveStyle(node.cssCompiledStyles)
    let color = seriesColor(b.series)
    let x = left + b.x
    let y = top + b.y
    let name = jsTrim(decodeEntities(node.name))
    let value = if showValues: format(b.value) else: ""
    let group = "data-id=\"" & escText(node.name) & "\">"
    # Include headerless ancestors in tooltips because their children cover them.
    let own = titlePart(node.name)
    var path = if own == "": @[] else: @[own]
    var p = b.parent
    while p != nil and not p.headed:
      let section = titlePart(p.node.name)
      if section != "": path.insert(section, 0)
      p = p.parent
    let full = path.join(" › ")
    proc tooltip(hasDrawn: bool, drawn: string): string =
      if full == "" or (hasDrawn and drawn == name and full == own): "" else: "<title>" & full & "</title>"
    let rect = "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(b.w) & "\" height=\"" & num(b.h) &
      "\" fill=\"" & color & "\""
    # Inline font sizes override SVG attributes, so truncate instead of shrinking.
    let fixed = style.fontSize   # 0 for undefined
    let textStyle = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    let ink = if setsFill(style.shape): inkFill(style.shape, style.text) else: seriesInkFill(b.series)

    if not node.leaf:
      var text = ""
      var hasDrawn = false
      var drawn = ""
      if b.headed:
        let short = b.header < HEADER
        let labelSize = if fixed != 0: fixed elif short: tiny else: small
        let valueSize = if fixed != 0: fixed else: tiny
        let room = b.w - 2 * SIDE - 4
        let valueWidth = if value != "": measurer.width(value, valueSize, textStyle) else: 0.0
        let withValue = not short and valueWidth > 0 and room - valueWidth - 12 >= 3 * labelSize
        var label = (false, Fitted())
        if labelSize * LINE < b.header:
          label = fitText(name, (if withValue: room - valueWidth - 12 else: room), labelSize, labelSize, measurer,
                          textStyle or Bold)
        let baseline = y + b.header / 2 + 1
        hasDrawn = label[0]
        drawn = label[1].text
        if label[0]:
          text.add "<text x=\"" & num(x + SIDE + 2) & "\" y=\"" & num(baseline + labelSize * 0.35) &
            "\" font-weight=\"var(--_hw)\"" & (if short: " font-size=\"" & jsString(labelSize) & "\"" else: "") &
            ink & style.text & ">" & esc(label[1].text) & "</text>"
        if withValue and valueSize * LINE <= HEADER:
          text.add "<text class=\"pele-value\" x=\"" & num(x + b.w - SIDE - 2) & "\" y=\"" & num(baseline + valueSize * 0.35) &
            "\" font-size=\"" & jsString(tiny) & "\" text-anchor=\"end\"" & (if ink != "": ink else: " fill=\"var(--_m)\"") &
            style.text & ">" & esc(value) & "</text>"
      # A section is a tint of its color, unless a class gives it a fill of its own. Headerless
      # sections draw no box, so their children blend into the grid.
      let tint = if jsre"""/[";]fill:/""".test(style.shape): "" else: " fill-opacity=\"0.12\""
      let shape = if b.headed: rect & corners(tint & " stroke=\"" & color & "\"" & style.shape, b) & "/>"
                  else: "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(b.w) & "\" height=\"" & num(b.h) & "\" fill=\"none\"/>"
      sections.add "<g class=\"pele-node pele-section" & classNames(node.classSelector) & "\" " & group &
        tooltip(hasDrawn, drawn) & shape & text & "</g>"
      continue

    var text = ""
    let room = b.w - 8
    let smallest = if fixed != 0: fixed else: least
    let tallest =
      if fixed == 0: jsMin(size, floor((b.h - 4) / LINE))
      elif fixed * LINE <= b.h - 4: fixed
      else: 0.0
    var label = (false, Fitted())
    if tallest >= smallest: label = fitText(name, room, tallest, smallest, measurer, textStyle)
    if label[0]:
      let l = label[1]
      let cx = num(x + b.w / 2)
      let cy = y + b.h / 2
      let valueSize = if fixed != 0: fixed else: jsMax(least, jsRound(l.size * 0.8))
      let lines = (l.size + valueSize) * LINE
      if value != "" and lines <= b.h - 4 and measurer.width(value, valueSize, textStyle) <= room:
        let first = cy - lines / 2 + (l.size * LINE) / 2
        let second = cy + lines / 2 - (valueSize * LINE) / 2
        text = "<text x=\"" & cx & "\" y=\"" & num(first + l.size * 0.35) & "\" font-size=\"" & num(l.size) & "\"" &
          ink & style.text & ">" & esc(l.text) & "</text>" &
          "<text class=\"pele-value\" x=\"" & cx & "\" y=\"" & num(second + valueSize * 0.35) & "\" font-size=\"" &
          num(valueSize) & "\"" & ink & style.text & ">" & esc(value) & "</text>"
      else:
        text = "<text x=\"" & cx & "\" y=\"" & num(cy + l.size * 0.35) & "\" font-size=\"" & num(l.size) & "\"" &
          ink & style.text & ">" & esc(l.text) & "</text>"
    leaves.add "<g class=\"pele-node pele-leaf" & classNames(node.classSelector) & "\" " & group &
      tooltip(label[0], label[1].text) & rect & corners(style.shape, b) & "/>" & text & "</g>"

  let totalWidth = ceil(jsMax(width, title.width) + 2 * pad)
  let totalHeight = ceil(height + titleHeight + 2 * pad)
  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    (if sections != "": "<g class=\"pele-sections\" font-size=\"" & jsString(small) & "\">" & sections & "</g>" else: "") &
    (if leaves != "": "<g class=\"pele-leaves\" text-anchor=\"middle\" fill=\"var(--_bg)\">" & leaves & "</g>" else: "")

  Rendered(
    svg: svgDocument("treemap", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight)

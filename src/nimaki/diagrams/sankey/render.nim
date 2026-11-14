## port-of: src/diagrams/sankey/render.ts
## port-status: conformant
import std/[options, tables]
from std/math import ceil, floor, classify, FloatClass, isNaN
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[entities, label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/fit_width
import db, layout
import ../../jsregex

const
  LABEL_GAP = 6.0
  VALUE_GAP = 15.0
  LABEL_ROOM = 1.8
  CAREFUL = 300

func toBase36(x: uint32): string =
  ## `(x >>> 0).toString(36)`
  const DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
  var v = x
  if v == 0: return "0"
  while v > 0:
    result.insert($DIGITS[int(v mod 36)], 0)
    v = v div 36

func mul32(a, b: uint32): uint32 =
  ## Math.imul, in 16-bit halves so that no partial product passes 2^48 (a JavaScript number
  ## would lose the low bits of a full product; see the porting guide).
  let lo = (a and 0xffff'u32) * b
  let hi = ((a shr 16) * (b and 0xffff'u32)) and 0xffff'u32
  lo + (hi shl 16)

func contentId(text: string): string =
  ## Two 32-bit hashes, so different gradients practically never share an id.
  var a = 0x811c9dc5'u32
  var b = 5381'u32
  for c in codeUnits(text):
    a = mul32(a xor uint32(c), 0x01000193'u32)
    b = b * 33'u32 + uint32(c)
  toBase36(a) & toBase36(b)

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

proc numberOption(conf: Config, key: string, fallback, min, max: float): float =
  let value = conf[key]
  if value != nil and value.kind == yNumber and value.n >= min: jsMin(value.n, max) else: fallback

proc textOption(conf: Config, key: string): string =
  let value = conf[key]
  if value == nil: ""
  elif value.kind == yString: value.s
  elif value.kind == yNumber and value.n.isFinite: jsString(value.n)
  else: ""

proc isText(conf: Config, key, text: string): bool =
  let value = conf[key]
  value != nil and value.kind == yString and value.s == text

func rounded(value: float): float =
  ## Two decimals, as Mermaid shows values; numbers too large for that are left as they are.
  if abs(value) < 1e15: jsRound(value * 100) / 100 else: value

proc fillStyle(color: YamlValue): string =
  ## A colour from the configuration, as an inline style that overrides the series colour.
  if color != nil and color.kind == yString: resolveStyle(@["fill:" & color.s]).shape else: ""

proc draw(model: SankeyModel, conf: Config, options: RenderOptions, chartWidth, natural: float): Rendered

proc renderSankey*(model: SankeyModel, config: Config, options: RenderOptions): Rendered =
  let conf = if config["sankey"].isRecord: config["sankey"] else: ymap()
  let natural = numberOption(conf, "width", 600, 1, 10000)
  fitWidth(options, natural, 160, proc (chartWidth: float, narrow: bool): Rendered =
    draw(model, conf, options, chartWidth, natural))

type LabelBox = object
  value: string
  width: float
  after: bool
  left, y: float

proc draw(model: SankeyModel, conf: Config, options: RenderOptions, chartWidth, natural: float): Rendered =
  let size = options.fontSize.get(16)
  let least = jsRound(size * 0.625)
  # Labels shrink with a chart narrowed to fit, as they would if the whole picture were scaled down.
  var small = jsMax(least, jsRound(size * 0.875 * jsMin(1, chartWidth / natural)))
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let chartHeight = numberOption(conf, "height", 400, 1, 10000)
  let nodeWidth = jsMin(numberOption(conf, "nodeWidth", 10, 1, 200), chartWidth)
  let showValuesOpt = conf["showValues"]
  let showValues = not (showValuesOpt != nil and showValuesOpt.kind == yBool and not showValuesOpt.b)
  let prefix = decodeEntities(textOption(conf, "prefix"))
  let suffix = decodeEntities(textOption(conf, "suffix"))
  let outlined = isText(conf, "labelStyle", "outlined")
  let alignment = if isText(conf, "nodeAlignment", "left"): aLeft
                  elif isText(conf, "nodeAlignment", "right"): aRight
                  elif isText(conf, "nodeAlignment", "center"): aCenter
                  else: aJustify
  let linkColorOpt = conf["linkColor"]
  let linkColor = if linkColorOpt != nil and linkColorOpt.kind == yString: linkColorOpt.s else: "gradient"
  let nodePadding = numberOption(conf, "nodePadding", 12, 0, 200) + (if showValues: VALUE_GAP else: 0)

  proc lay(labelSize: float): SankeyLayout =
    layoutSankey(model, LayoutOptions(width: chartWidth, height: chartHeight, nodeWidth: nodeWidth,
                                      nodePadding: nodePadding, labelHeight: labelSize * 1.15,
                                      alignment: alignment))
  var layout = lay(small)
  # Labels also shrink with the most crowded column, so each keeps about LABEL_ROOM lines.
  var rows = initTable[int, int]()
  var fullest = 1
  for node in layout.nodes:
    let count = rows.getOrDefault(node.layer, 0) + 1
    rows[node.layer] = count
    if count > fullest: fullest = count
  let crowded = jsMax(least, jsRound(chartHeight / float(fullest) / LABEL_ROOM))
  if crowded < small:
    small = crowded
    layout = lay(small)
  let nodes = layout.nodes
  let links = layout.links
  let lineHeight = small * 1.5

  var custom = initTable[string, string]()
  let colors = conf["nodeColors"]
  if colors.isRecord:
    for id, color in colors.fields:
      let style = fillStyle(color)
      if style != "": custom[id] = style
  proc nodeStyle(i: int): string = custom.getOrDefault(model.nodes[i].id, "")
  # Match the whole fill to preserve semicolons in escaped entities.
  proc nodeColor(i: int): string =
    let m = jsre"""/^ style="fill:(.*);"$/""".exec(nodeStyle(i))
    if m.found: m[1] else: seriesColor(i)

  # Labels sit beside the bars, on the side that faces the middle of the chart unless that
  # side is crowded.
  var central = 0
  var most = 0.0
  for node in nodes:
    if node.value > most:
      most = node.value
      central = node.layer
  var minX = 0.0
  var maxX = chartWidth
  var minY = 0.0
  var maxY = chartHeight
  var labels: seq[LabelBox]
  for i, node in nodes:
    let name = decodeEntities(model.nodes[i].id)
    let value = if showValues: prefix & jsString(rounded(node.value)) & suffix else: ""
    let width = measurer.width(if value != "": name & " " & value else: name, small, 0)
    let after = if outlined: node.layer >= central else: node.x < chartWidth / 2
    let x = if after: node.x + nodeWidth + LABEL_GAP else: node.x - LABEL_GAP
    let y = node.y + node.height / 2
    minX = jsMin(minX, if after: x else: x - width)
    maxX = jsMax(maxX, if after: x + width else: x)
    minY = jsMin(minY, y - small * 0.75)
    maxY = jsMax(maxY, y + small * 0.75)
    labels.add LabelBox(value: value, width: width, after: after, left: (if after: x else: x - width), y: y)
  # A label moves at most one line; retain two bands on each side.
  # Pele's Map is keyed by numbers, which can be infinite (a tiny font size); NaN is one key.
  func bandKey(x: float): (bool, float) = (if x.isNaN: (true, 0.0) else: (false, x))
  var bands = initTable[(bool, float), seq[int]]()
  if nodes.len <= CAREFUL:
    for k, label in labels:
      let band = floor(label.y / lineHeight)
      for key in [band - 2, band - 1, band, band + 1, band + 2]:
        bands.mgetOrPut(bandKey(key), @[]).add k
  var labelsOut = ""
  var nodesOut = ""
  for i, node in nodes:
    let id = model.nodes[i].id
    let name = decodeEntities(id)
    let height = jsMax(node.height, 1)
    nodesOut.add "<rect class=\"pele-sankey-node\" data-id=\"" & escText(id) & "\" x=\"" & num(node.x) &
      "\" y=\"" & num(node.y) & "\" width=\"" & num(nodeWidth) & "\" height=\"" & num(height) &
      "\" rx=\"" & num(jsMin(2, height / 2)) & "\" fill=\"" & seriesColor(i) & "\"" & nodeStyle(i) & "/>"

    proc overlapsLabel(left, y: float): bool =
      for j in bands.getOrDefault(bandKey(floor(y / lineHeight)), @[]):
        let other = labels[j]
        if j != i and abs(other.y - y) < lineHeight and left < other.left + other.width + LABEL_GAP and
           left + labels[i].width > other.left - LABEL_GAP: return true
      false
    # Try the other side, then an adjacent line when both sides are crowded.
    if nodes.len <= CAREFUL and overlapsLabel(labels[i].left, labels[i].y):
      block place:
        for dy in [0.0, -lineHeight, lineHeight]:
          for after in [labels[i].after, not labels[i].after]:
            let width = labels[i].width
            let left = if after: node.x + nodeWidth + LABEL_GAP else: node.x - LABEL_GAP - width
            let y = labels[i].y + dy
            if overlapsLabel(left, y) or left < minX or left + width > maxX or y - small * 0.75 < minY or
               y + small * 0.75 > maxY: continue
            var blocked = false
            for j, bar in nodes:
              if j != i and left < bar.x + nodeWidth + LABEL_GAP and left + width > bar.x - LABEL_GAP and
                 y - small * 0.75 < bar.y + bar.height and y + small * 0.75 > bar.y:
                blocked = true
                break
            if blocked: continue
            # A label stays nearer its own bar than any other in the column, so it can't name that one.
            let own = jsMax(0, jsMax(node.y - y, y - node.y - node.height))
            for j, bar in nodes:
              if j != i and bar.x == node.x and jsMax(0, jsMax(bar.y - y, y - bar.y - bar.height)) <= own:
                blocked = true
                break
            if blocked: continue
            labels[i].left = left
            labels[i].y = y
            labels[i].after = after
            break place
    let value = labels[i].value
    let after = labels[i].after
    let y = labels[i].y
    let x = if after: node.x + nodeWidth + LABEL_GAP else: node.x - LABEL_GAP
    let position = " x=\"" & num(x) & "\" y=\"" & num(y + small * 0.35) & "\" text-anchor=\"" &
      (if after: "start" else: "end") & "\""
    let text = esc(name) & (if value != "": " <tspan class=\"pele-sankey-value\" fill=\"var(--_m)\">" & esc(value) & "</tspan>" else: "")
    labelsOut.add "<g class=\"pele-label\" data-id=\"" & escText(id) & "\">" &
      (if outlined: "<text" & position & " fill=\"none\" stroke=\"var(--_bg)\" stroke-width=\"3\" stroke-linejoin=\"round\">" &
                    esc(name) & (if value != "": " " & esc(value) else: "") & "</text>"
       else: "") &
      "<text" & position & ">" & text & "</text></g>"

  let fixed = if linkColor == "gradient" or linkColor == "source" or linkColor == "target": ""
              else: fillStyle(linkColorOpt)
  # Without an idPrefix diagrams share gradient ids, and Chrome then uses a hidden or differently
  # themed copy's gradient. Other characters would end the url() and void the whole fill.
  let idPrefix = options.idPrefix.get("")
  let gradient = linkColor == "gradient" and jsre"/^[\w-]+$/".test(idPrefix)
  var gradients = initOrderedTable[string, string]()
  var linksOut = ""
  for link in links:
    let stop = if linkColor == "target": link.target else: link.source
    let half = jsMax(link.thickness, 1) / 2
    let x0 = nodes[link.source].x + nodeWidth
    let x1 = nodes[link.target].x
    var paint = "fill=\"" & seriesColor(stop) & "\"" & (if fixed != "": fixed else: nodeStyle(stop))
    if gradient:
      # Ids come from the gradient itself, so diagrams sharing a prefix agree on them. The colour
      # after the url() is the fallback.
      let stops = "x1=\"" & num(x0) & "\" x2=\"" & num(x1) & "\"><stop offset=\"0\" stop-color=\"" &
        nodeColor(link.source) & "\"/>" & "<stop offset=\"1\" stop-color=\"" & nodeColor(link.target) & "\"/>"
      let id = idPrefix & "-sankey-" & contentId(stops)
      gradients[id] = "<linearGradient id=\"" & id & "\" gradientUnits=\"userSpaceOnUse\" " & stops & "</linearGradient>"
      paint = "fill=\"url(#" & id & ") " & nodeColor(link.source) & "\""
    let mid = num((x0 + x1) / 2)
    let source = escText(model.nodes[link.source].id)
    let target = escText(model.nodes[link.target].id)
    linksOut.add "<path class=\"pele-sankey-link\" data-id=\"" & source & "-&gt;" & target & "\" d=\"M" &
      num(x0) & "," & num(link.sourceY - half) & "C" & mid & "," & num(link.sourceY - half) & " " & mid & "," &
      num(link.targetY - half) & " " & num(x1) & "," & num(link.targetY - half) & "L" & num(x1) & "," &
      num(link.targetY + half) & "C" & mid & "," & num(link.targetY + half) & " " & mid & "," &
      num(link.sourceY + half) & " " & num(x0) & "," & num(link.sourceY + half) & "Z\" " & paint & ">" &
      "<title>" & source & " → " & target & ": " & esc(prefix) & jsString(rounded(link.value)) & esc(suffix) &
      "</title></path>"

  let title = layoutLabel(model.title, false, measurer, size, titleRoom(options), Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let inner = jsMax(maxX - minX, title.width)
  let ox = pad - minX + (inner - (maxX - minX)) / 2
  let oy = pad + titleHeight - minY
  let width = ceil(inner + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)

  var defs = ""
  for g in gradients.values: defs.add g
  let content =
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g transform=\"translate(" & num(ox) & "," & num(oy) & ")\">" &
    (if gradients.len > 0: "<defs>" & defs & "</defs>" else: "") &
    "<g class=\"pele-sankey-links\" fill-opacity=\"0.4\">" & linksOut & "</g>" &
    "<g class=\"pele-sankey-nodes\">" & nodesOut & "</g>" &
    "<g class=\"pele-labels\" font-size=\"" & jsString(small) & "\">" & labelsOut & "</g>" &
    "</g>"

  Rendered(
    svg: svgDocument("sankey", width, height, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: width,
    height: height)

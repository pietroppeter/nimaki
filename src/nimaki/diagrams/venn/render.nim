## port-of: src/diagrams/venn/render.ts
## port-status: draft
import std/[json, options, sets, strutils, tables]
from std/math import ceil
import ../../jsmath
import ../../js
import ../../preprocess
import ../../svg/[builder, ink, root, theme]
import ../../text/[label, measurer]
import ../../types
import db, layout, types as vennTypes

const
  RADIUS = 100.0
  MAX_GROWTH = 1.6

type
  Line = object
    id: string               ## that of a text
    hasId: bool
    raw: string
    size: float
    base: int
    label: Label

  Region = ref object
    sets: seq[string]
    inside: seq[int]
    spot: Spot
    lines: seq[Line]         ## what is written in the region: its label first, then its texts
    style: ResolvedStyle
    across: bool             ## whether its text is written across other circles

func keyOf(ids: seq[string]): string =
  ## One key for a list of set ids. Ids may hold any character, so they are not simply joined.
  if ids.len == 1: ids[0] else: $(%ids)

proc renderVenn*(model: VennDb, config: Config, options: RenderOptions): Rendered =
  let noStyle = resolveStyle(@[])
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let tiny = jsRound(size * 0.8125)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let circles = layoutCircles(model.subsets)
  var index = initTable[string, int]()
  for i, c in circles: index[c.id] = i

  # Styles for the same targets add up, later declarations winning.
  var styles = initTable[string, OrderedTable[string, string]]()
  for declared in model.styles:
    let key = keyOf(declared.targets)
    if key notin styles: styles[key] = initOrderedTable[string, string]()
    for property, value in declared.styles: styles[key][property] = value
  proc styleOf(key: string): ResolvedStyle =
    if key notin styles: return noStyle
    var list: seq[string]
    for property, value in styles[key]: list.add property & ":" & value
    resolveStyle(list)

  # Circles that touch each circle; only those can cut into a region of it.
  var neighbors = newSeq[seq[int]](circles.len)
  for a in 0 ..< circles.len:
    for b in a + 1 ..< circles.len:
      if hypot(circles[a].x - circles[b].x, circles[a].y - circles[b].y) < circles[a].r + circles[b].r:
        neighbors[a].add b
        neighbors[b].add a

  # One region for each set and each stated overlap; a later statement about the same sets
  # replaces an earlier one.
  var stated = initOrderedTable[string, VennSubset]()
  for subset in model.subsets: stated[keyOf(subset.sets)] = subset
  var regions = initOrderedTable[string, Region]()
  for key, subset in stated:
    var sets: seq[string]
    for id in subset.sets:
      if id notin sets: sets.add id
    var inside: seq[int]
    for id in sets: inside.add index[id]
    let within = toHashSet(inside)
    var smallest = inside[0]
    for i in inside:
      if circles[i].r < circles[smallest].r: smallest = i
    let style = styleOf(key)
    let text = if subset.hasLabel: subset.label elif subset.sets.len == 1: subset.sets[0] else: ""
    let base = (if style.bold: Bold else: 0) or (if style.italic: Italic else: 0)
    var others: seq[int]
    for i in neighbors[smallest]:
      if i notin within: others.add i
    var spot = findSpot(circles, inside, others)
    # A region that other circles cover, or all but cover, is written across them instead.
    let across = others.len > 0 and spot.margin < circles[smallest].r * 0.2
    if across: spot = findSpot(circles, inside, @[])
    let region = Region(sets: sets, inside: inside, spot: spot, style: style, across: across)
    if text != "":
      let fontSize = if sets.len == 1: size else: small
      region.lines.add Line(raw: text, size: fontSize, base: base,
                            label: layoutLabel(text, false, measurer, fontSize, 4000, base))
    regions[key] = region
  for node in model.textNodes:
    let raw = if node.hasLabel: node.label else: node.id
    let key = keyOf(node.sets)
    if key in regions:
      regions[key].lines.add Line(id: node.id, hasId: true, raw: raw, size: tiny, base: 0,
                                  label: layoutLabel(raw, false, measurer, tiny, 4000))

  # Lengths so far are in units of the layout. The scale gives the largest circle a set radius,
  # and grows, within limits, until every region holds what is written in it.
  var largest = 0.0
  for c in circles:
    if c.r > largest: largest = c.r
  var scale = if largest > 0: RADIUS / largest else: 1.0
  var growth = 1.0
  for region in regions.values:
    if region.spot.margin <= 0: continue
    var width = 0.0
    var height = 0.0
    for line in region.lines:
      width = jsMax(width, line.label.width)
      height += line.label.height
    let need = hypot(width, height) / 2 + 4
    growth = jsMax(growth, jsMin(need / (region.spot.margin * scale), MAX_GROWTH))
  scale *= growth

  # What is still too wide for its region is wrapped to it.
  for region in regions.values:
    let room = jsMax(region.spot.margin * scale * 1.8, 72)
    for line in region.lines.mitems:
      if line.label.width > room: line.label = layoutLabel(line.raw, false, measurer, line.size, room, line.base)

  var minX = Inf
  var minY = Inf
  var maxX = NegInf
  var maxY = NegInf
  for c in circles:
    minX = jsMin(minX, (c.x - c.r) * scale)
    minY = jsMin(minY, (c.y - c.r) * scale)
    maxX = jsMax(maxX, (c.x + c.r) * scale)
    maxY = jsMax(maxY, (c.y + c.r) * scale)
  for region in regions.values:
    var wide = 0.0
    var tall = 0.0
    for line in region.lines:
      wide = jsMax(wide, line.label.width)
      tall += line.label.height
    minX = jsMin(minX, region.spot.x * scale - wide / 2)
    maxX = jsMax(maxX, region.spot.x * scale + wide / 2)
    minY = jsMin(minY, region.spot.y * scale - tall / 2)
    maxY = jsMax(maxY, region.spot.y * scale + tall / 2)
  if circles.len == 0:
    minX = 0
    minY = 0
    maxX = 0
    maxY = 0

  let title = layoutLabel(if model.title != "": normalizeText(model.title) else: "", false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0.0
  let inner = jsMax(maxX - minX, title.width)
  let ox = pad + (inner - (maxX - minX)) / 2 - minX
  let oy = pad + titleHeight - minY
  let width = ceil(inner + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)
  var placed: seq[Circle]
  for c in circles: placed.add Circle(id: c.id, x: c.x * scale + ox, y: c.y * scale + oy, r: c.r * scale)

  var sets = ""
  for i, c in placed:
    let color = seriesColor(i)
    let style = if c.id in regions: regions[c.id].style else: noStyle
    sets.add "<circle class=\"pele-venn-set\" data-id=\"" & escText(c.id) & "\" cx=\"" & num(c.x) & "\" cy=\"" &
      num(c.y) & "\" r=\"" & num(c.r) & "\" fill=\"" & color & "\" fill-opacity=\"0.2\" stroke=\"" & color & "\"" &
      style.shape & "/>"

  var painted: seq[Region]
  for r in regions.values:
    if r.sets.len > 1 and r.style.shape != "": painted.add r
  # The fill under a region's text is the last overlap drawn over all of it, or its own circle
  # when the style sets an opacity.
  proc under(region: Region): string =
    if region.across: return ""
    var fill = if region.sets.len == 1 and ("\"fill-opacity:" in region.style.shape or
                                            ";fill-opacity:" in region.style.shape): region.style.shape
               else: ""
    for other in painted:
      var all = true
      for id in other.sets:
        if id notin region.sets: all = false
      if all: fill = other.style.shape
    fill

  var overlaps = ""
  var labels = ""
  for region in regions.values:
    let id = escText(region.sets.join("|"))
    # An overlap is only drawn when a style gives it a look of its own; otherwise the circles show it.
    if region.sets.len > 1 and region.style.shape != "":
      var mine: seq[Circle]
      for i in region.inside: mine.add placed[i]
      let d = regionPath(mine, proc (v: float): string = num(v))
      if d != "":
        overlaps.add "<path class=\"pele-venn-overlap\" data-id=\"" & id & "\" d=\"" & d & "\" fill=\"none\"" &
          region.style.shape & "/>"
    var total = 0.0
    for line in region.lines: total += line.label.height
    if total == 0: continue
    let x = region.spot.x * scale + ox
    var y = region.spot.y * scale + oy - total / 2
    let fill = under(region)
    var content = ""
    for line in region.lines:
      let own = if not line.hasId: region.style.text else: styleOf(line.id).text
      let (hasColor, color) = ink(fill, own)
      let attrs =
        if not line.hasId:
          " class=\"pele-label\"" & (if line.size == size: "" else: " font-size=\"" & jsString(line.size) & "\"") &
            (if hasColor and color != "": " fill=\"" & color & "\"" else: "") & own
        else:
          " class=\"pele-venn-text\" data-id=\"" & escText(line.id) & "\" font-size=\"" & jsString(tiny) &
            "\" fill=\"" & (if hasColor: color else: "var(--_m)") & "\"" & own
      content.add labelSvg(line.label, x, y + line.label.height / 2, attrs)
      y += line.label.height
    labels.add "<g class=\"pele-venn-region\" data-id=\"" & id & "\">" & content & "</g>"

  let svg = svgDocument("venn", width, height, size, options, Accessible(),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      "<g class=\"pele-venn-sets\">" & sets & "</g>" &
      (if overlaps != "": "<g class=\"pele-venn-overlaps\">" & overlaps & "</g>" else: "") &
      (if labels != "": "<g class=\"pele-venn-labels\">" & labels & "</g>" else: ""))
  Rendered(svg: svg, width: width, height: height)

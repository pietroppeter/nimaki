## port-of: src/diagrams/cynefin/render.ts
## port-status: conformant
import std/[options, tables]
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, edges, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../util/yaml
import ../../js
import ../../jsmath
import boundaries, model

const QUADRANTS = [
  # [domain, column, row, series color]
  ("complex", 0, 0, 0),
  ("complicated", 1, 0, 1),
  ("chaotic", 0, 1, 3),
  ("clear", 1, 1, 2),
]
const CONFUSION_COLOR = 4

const META = {
  # [name, decision model, kind of practice]
  "complex": ("Complex", "Probe → Sense → Respond", "Emergent Practices"),
  "complicated": ("Complicated", "Sense → Analyse → Respond", "Good Practices"),
  "clear": ("Clear", "Sense → Categorise → Respond", "Best Practices"),
  "chaotic": ("Chaotic", "Act → Sense → Respond", "Novel Practices"),
  "confusion": ("Confusion", "", "Disorder"),
}.toTable

const
  MAX_CONFUSION_ITEMS = 3
  ITEM_MAX_WIDTH = 200.0
  ITEM_PAD_X = 10.0
  ITEM_PAD_Y = 4.0
  ITEM_GAP = 6.0
  HEAD_GAP = 10.0
  MARGIN = 20.0
  CLEARANCE = 10.0

type
  Badge = object
    text: string
    label: Label
    w, h: float
    overflow: bool

  Block = ref object
    name: string
    title: Label
    subtitles: seq[Label]
    badges: seq[Badge]
    w, h: float
    cx, cy: float

proc setting(config: Config, key: string, fallback, min, max: float): float =
  let value = config["cynefin"][key]
  if value != nil and value.kind == yNumber and value.n >= min and value.n <= max: value.n else: fallback

func sq(x: float): float = x * x

proc renderCynefin*(model: CynefinModel, config: Config, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.8125)
  let itemSize = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  let showV = config["cynefin"]["showDomainDescriptions"]
  let showDescriptions = not (showV != nil and showV.kind == yBool and not showV.b)
  let amplitude = setting(config, "boundaryAmplitude", 8, 0, 50)
  let seed = resolveSeed(setting(config, "seed", 0, -1e15, 1e15), options.idPrefix.get("pele"))
  let itemLine = jsRound(itemSize * 1.5)

  proc badge(text: string, overflow: bool): Badge =
    let label = layoutLabel(text, false, measurer, itemSize, ITEM_MAX_WIDTH)
    Badge(text: text, label: label, w: label.width + 2 * ITEM_PAD_X, h: max(label.height, itemLine) + 2 * ITEM_PAD_Y,
          overflow: overflow)

  proc makeBlock(name: string): Block =
    let meta = META[name]
    let title = layoutLabel(meta[0], false, measurer, size, 4000, Bold)
    var subtitles: seq[Label]
    if showDescriptions:
      for text in [meta[1], meta[2]]:
        if text != "": subtitles.add layoutLabel(text, false, measurer, small, 4000, Italic)
    let items = if name in model.domains: model.domains[name].items else: @[]
    let shown = if name == "confusion" and items.len > MAX_CONFUSION_ITEMS: MAX_CONFUSION_ITEMS else: items.len
    var badges: seq[Badge]
    for i in 0 ..< shown: badges.add badge(items[i], false)
    if shown < items.len: badges.add badge("+" & $(items.len - shown) & " more", true)
    var w = title.width
    var h = title.height
    for s in subtitles:
      w = max(w, s.width)
      h += s.height
    if badges.len > 0: h += HEAD_GAP - ITEM_GAP
    for b in badges:
      w = max(w, b.w)
      h += ITEM_GAP + b.h
    Block(name: name, title: title, subtitles: subtitles, badges: badges, w: w, h: h)

  var quadrants: seq[Block]
  for q in QUADRANTS: quadrants.add makeBlock(q[0])
  let confusion = makeBlock("confusion")
  let rx = max(88.0, confusion.w * 0.71 + 8)
  let ry = max(64.0, confusion.h * 0.71 + 6)

  var quadW = setting(config, "width", 640, 100, 10000) / 2
  var quadH = setting(config, "height", 440, 100, 10000) / 2
  for b in quadrants:
    quadW = max(quadW, b.w + 2 * MARGIN)
    quadH = max(quadH, b.h + 2 * MARGIN)
  # A block sits in the middle of its quadrant, so its inner corner must stay clear of the ellipse.
  for b in quadrants:
    let dx = (quadW - b.w) / 2
    let dy = (quadH - b.h) / 2
    if sq(dx / (rx + CLEARANCE)) + sq(dy / (ry + CLEARANCE)) >= 1: continue
    let wider = b.w + 2 * (rx + CLEARANCE)
    let taller = b.h + 2 * (ry + CLEARANCE)
    if wider * quadH <= quadW * taller: quadW = max(quadW, wider)
    else: quadH = max(quadH, taller)

  let title = layoutLabel(model.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0
  let width = 2 * quadW
  let height = 2 * quadH
  let x0 = pad
  let y0 = pad + titleHeight
  let cx = x0 + quadW
  let cy = y0 + quadH
  let right = x0 + width
  let bottom = y0 + height

  var foldO = FOLD
  foldO.segments = 4
  foldO.pinEnd = true
  var westO = HORIZON
  westO.segments = 4
  westO.pinEnd = true
  var eastO = HORIZON
  eastO.segments = 4
  eastO.pinStart = true
  let fold = wave(y0, cy, cx, seed, amplitude, foldO)
  let west = wave(x0, cx, cy, seed + 100, amplitude, westO)
  let east = wave(cx, right, cy, seed + 200, amplitude, eastO)
  let drop = cliff(cx, cy, bottom, width * 0.03)
  proc at(curve: seq[float], stop: bool): string =
    if stop: num(curve[^2]) & "," & num(curve[^1]) else: num(curve[0]) & "," & num(curve[1])

  let regions = {
    "complex": "M" & num(x0) & "," & num(y0) & "L" & at(fold, false) & forward(fold) & backward(west) & "Z",
    "complicated": "M" & at(fold, false) & "L" & num(right) & "," & num(y0) & "L" & at(east, true) & backward(east) &
      backward(fold) & "Z",
    "chaotic": "M" & at(west, false) & forward(west) & forward(drop) & "L" & num(x0) & "," & num(bottom) & "Z",
    "clear": "M" & at(east, false) & forward(east) & "L" & num(right) & "," & num(bottom) & "L" & at(drop, true) &
      backward(drop) & "Z",
  }.toTable

  var fills = ""
  for q in QUADRANTS:
    fills.add "<path class=\"pele-cynefin-region\" data-id=\"" & q[0] & "\" d=\"" & regions[q[0]] & "\" fill=\"" &
      seriesColor(q[3]) & "\" fill-opacity=\"0.14\"/>"
  let boundariesOut =
    "<g class=\"pele-cynefin-boundaries\" fill=\"none\" stroke=\"var(--_b)\" stroke-dasharray=\"6 3\">" &
    "<path d=\"" & curvePath(fold) & "\"/><path d=\"" & curvePath(west) & "\"/><path d=\"" & curvePath(east) & "\"/>" &
    "<path class=\"pele-cynefin-cliff\" d=\"" & curvePath(drop) &
    "\" stroke=\"var(--_l)\" stroke-width=\"2\" stroke-dasharray=\"none\" stroke-linecap=\"round\"/></g>"
  let oval = ellipsePath(cx, cy, rx, ry)
  let ellipse =
    "<path d=\"" & oval & "\" fill=\"var(--_bg)\"/>" &
    "<path class=\"pele-cynefin-region\" data-id=\"confusion\" d=\"" & oval & "\" fill=\"" & seriesColor(CONFUSION_COLOR) &
    "\" fill-opacity=\"0.18\" stroke=\"var(--_b)\" stroke-dasharray=\"4 2\"/>"

  proc drawBlock(b: Block): string =
    var y = b.cy - b.h / 2
    var output = labelSvg(b.title, b.cx, y + b.title.height / 2, " class=\"pele-label\" font-weight=\"var(--_hw)\"")
    y += b.title.height
    for s in b.subtitles:
      output.add labelSvg(s, b.cx, y + s.height / 2, " class=\"pele-cynefin-subtitle\" font-size=\"" & jsString(small) &
        "\" font-style=\"italic\" fill=\"var(--_m)\"")
      y += s.height
    y += HEAD_GAP - ITEM_GAP
    for item in b.badges:
      y += ITEM_GAP
      output.add "<g class=\"pele-node" & (if item.overflow: " pele-cynefin-overflow" else: "") & "\"" &
        (if item.overflow: "" else: " data-id=\"" & escText(item.text) & "\"") & ">" &
        "<rect x=\"" & num(b.cx - item.w / 2) & "\" y=\"" & num(y) & "\" width=\"" & num(item.w) & "\" height=\"" &
        num(item.h) & "\" fill=\"var(--_bg)\" stroke=\"var(--_b)\"" & (if item.overflow: " stroke-dasharray=\"3 2\"" else: "") &
        ROUNDED & "/>" &
        labelSvg(item.label, b.cx, y + item.h / 2, " class=\"pele-label\" font-size=\"" & jsString(itemSize) & "\"" &
          (if item.overflow: " fill=\"var(--_m)\"" else: ""), icons) &
        "</g>"
      y += item.h
    "<g class=\"pele-cynefin-domain\" data-id=\"" & b.name & "\">" & output & "</g>"

  var blocks = initTable[string, Block]()
  var domains = ""
  for index, q in QUADRANTS:
    let b = quadrants[index]
    b.cx = x0 + quadW * (float(q[1]) + 0.5)
    b.cy = y0 + quadH * (float(q[2]) + 0.5)
    blocks[q[0]] = b
    domains.add drawBlock(b)
  confusion.cx = cx
  confusion.cy = cy
  blocks["confusion"] = confusion
  domains.add drawBlock(confusion)

  proc inside(b: Block, x, y: float): bool =
    if b == confusion: sq((x - cx) / (rx + 4)) + sq((y - cy) / (ry + 4)) <= 1
    else: abs(x - b.cx) <= b.w / 2 + 8 and abs(y - b.cy) <= b.h / 2 + 8

  var edgesOut = ""
  var seen = initTable[string, int]()
  for transition in model.transitions:
    if transition.start notin blocks or transition.to notin blocks: continue
    let start = blocks[transition.start]
    let to = blocks[transition.to]
    if start == to: continue
    let key = if transition.start < transition.to: transition.start & " " & transition.to
              else: transition.to & " " & transition.start
    let repeat = seen.getOrDefault(key, 0)
    seen[key] = repeat + 1

    let dx = to.cx - start.cx
    let dy = to.cy - start.cy
    var len = hypot(dx, dy)
    if len == 0: len = 1
    let mx = (start.cx + to.cx) / 2
    let my = (start.cy + to.cy) / 2
    # Curves bow away from the middle of the diagram, which keeps them off the ellipse.
    let outward = if -dy * (mx - cx) + dx * (my - cy) >= 0: 1.0 else: -1.0
    let nx = (-dy / len) * outward
    let ny = (dx / len) * outward
    # A diagonal runs through the middle, so it bows far enough to pass the ellipse.
    let diagonal = start != confusion and to != confusion and abs(dx) > 1 and abs(dy) > 1
    let bow = (if diagonal: 2 * (hypot(rx * nx, ry * ny) + 16) else: len * 0.15) + float(repeat) * 56
    let px = mx + nx * bow
    let py = my + ny * bow
    proc point(t: float): (float, float) =
      let u = 1 - t
      (u * u * start.cx + 2 * u * t * px + t * t * to.cx, u * u * start.cy + 2 * u * t * py + t * t * to.cy)
    proc insideAt(b: Block, t: float): bool =
      let (x, y) = point(t)
      inside(b, x, y)
    proc crossing(b: Block, lo0, hi0: float, leaving: bool): float =
      var lo = lo0
      var hi = hi0
      for i in 0 ..< 16:
        let mid = (lo + hi) / 2
        if insideAt(b, mid) == leaving: lo = mid
        else: hi = mid
      (lo + hi) / 2
    const STEPS = 48
    var i = 1
    while i <= STEPS and insideAt(start, float(i) / STEPS): inc i
    if i > STEPS: continue
    let t0 = crossing(start, float(i - 1) / STEPS, float(i) / STEPS, true)
    while i <= STEPS and not insideAt(to, float(i) / STEPS): inc i
    let t1 = if i > STEPS: 1.0 else: crossing(to, float(i - 1) / STEPS, float(i) / STEPS, false)

    let (sx, sy) = point(t0)
    var (ex, ey) = point(t1)
    template blossom(a, b, c: float): float =
      (1 - t0) * (1 - t1) * a + ((1 - t0) * t1 + t0 * (1 - t1)) * b + t0 * t1 * c
    let qx = blossom(start.cx, px, to.cx)
    let qy = blossom(start.cy, py, to.cy)
    var el = hypot(ex - qx, ey - qy)
    if el == 0: el = 1
    let ux = (ex - qx) / el
    let uy = (ey - qy) / el
    let head = marker("arrow_point", ex, ey, ux, uy, "var(--_l)")
    ex -= ux * markerTrim("arrow_point")
    ey -= uy * markerTrim("arrow_point")

    var text = ""
    if transition.label != "":
      let label = layoutLabel(transition.label, false, measurer, small, ITEM_MAX_WIDTH)
      let (lx, ly) = point((t0 + t1) / 2)
      let away = (abs(nx) * label.width) / 2 + (abs(ny) * label.height) / 2 + 6
      let half = label.width / 2 + 4
      let tx = min(max(lx + nx * away, x0 + half), max(right - half, x0 + half))
      text = labelSvg(label, tx, ly + ny * away, " class=\"pele-edge-label\" font-size=\"" & jsString(small) & "\"", icons)
    edgesOut.add "<g class=\"pele-edge\" data-id=\"" & transition.start & "-" & transition.to & "\">" &
      "<path d=\"M" & num(sx) & "," & num(sy) & "Q" & num(qx) & "," & num(qy) & " " & num(ex) & "," & num(ey) &
      "\" fill=\"none\" stroke=\"var(--_l)\"/>" & head & text & "</g>"

  let totalWidth = ceil(max(width, title.width) + 2 * pad)
  let totalHeight = ceil(height + titleHeight + 2 * pad)
  let content =
    labelSvg(title, x0 + width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g class=\"pele-cynefin-regions\">" & fills & "</g>" &
    boundariesOut & ellipse & domains &
    (if edgesOut != "": "<g class=\"pele-edges\">" & edgesOut & "</g>" else: "")
  Rendered(svg: svgDocument("cynefin", totalWidth, totalHeight, size, options,
                            Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
           width: totalWidth, height: totalHeight, links: @[])

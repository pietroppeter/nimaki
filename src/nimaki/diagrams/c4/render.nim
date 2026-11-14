## port-of: src/diagrams/c4/render.ts
## port-status: conformant
import std/[options, tables, strutils, sets]
from std/math import ceil, isNaN
import ../../preprocess
import ../../errors
import ../../svg/[builder, edges, ink, root, shapes, theme]
import ../../text/[label, measurer]
import ../../types
import ../../util/url
import ../../js
import ../common/[fit_width, literal_label]
import db, layout, route
import ../../jsregex

const
  PAIR_SHIFT = 7.0
  NARROW_GAP = 36.0
  WIDEN = 24.0
  MAX_OFFSET = 2000.0
  EDGE = 8.0                ## A label may cover this much of a shape's edge, where there is no text.
  SLIDE = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]
  CARE_BUDGET = 2000000     ## Above this many box comparisons, labels stay put and lines go straight.

proc userStyle(fill, stroke, color: string): ResolvedStyle =
  var declarations: seq[string]
  if fill != "": declarations.add "fill:" & fill
  if stroke != "": declarations.add "stroke:" & stroke
  if color != "": declarations.add "color:" & color
  resolveStyle(declarations)

proc link(body, url, id: string, links: var seq[LinkInfo], options: RenderOptions): string =
  if url == "": return body
  # Entity encoding has hidden any `#name;` in the address. Put it back, so that the check sees
  # what a browser would.
  var address = url
  if "¶ß" in url:
    address = url.replace(jsre"/\ufb02\u00b0\u00b0?/g", "#").replace(jsre"/\u00b6\u00df/g", ";")
  linked(body, sanitizeUrl(address), id, links, options)

proc draw(db: C4Db, options: RenderOptions, tight: bool, gap = NARROW_GAP): (Rendered, int)

proc renderC4*(db: C4Db, config: Config, options: RenderOptions): Rendered =
  tighten(options, proc (tight: bool): Rendered =
    if not tight: return draw(db, options, false)[0]
    var (best, squeezed) = draw(db, options, true, NARROW_GAP)
    var gap = NARROW_GAP + WIDEN
    while squeezed > 0 and gap <= NARROW_GAP + 3 * WIDEN:
      let (wider, left) = draw(db, options, true, gap)
      if left < squeezed:
        best = wider
        squeezed = left
      gap += WIDEN
    best)

proc draw(db: C4Db, options: RenderOptions, tight: bool, gap = NARROW_GAP): (Rendered, int) =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.8125)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  var links: seq[LinkInfo]
  let lay = layoutC4(db, measurer, size, small,
                     (if tight: max(80.0, options.maxWidth.get(320) - 2 * pad) else: NaN), gap)
  let order = lay.order
  let boxes = lay.boxes
  let root = order[0]

  var minX = 0.0
  var minY = 0.0
  var maxX = root.w
  var maxY = root.h
  proc grow(x0, y0, x1, y1: float) =
    minX = min(minX, x0)
    minY = min(minY, y0)
    maxX = max(maxX, x1)
    maxY = max(maxY, y1)

  var ends: seq[Box]
  var pairs = initTable[int, HashSet[int]]()
  for rel in db.rels:
    let start = if rel.fromAttr.isSome: nil else: db.getC4Shape(rel.start)
    let to = if rel.toAttr.isSome: nil else: db.getC4Shape(rel.to)
    let a = if start != nil: boxes.getOrDefault(key(start)) else: nil
    let b = if to != nil: boxes.getOrDefault(key(to)) else: nil
    if a == nil or b == nil:
      raise newPeleError("C4 rel \"" & rel.start & "\" -> \"" & rel.to &
        "\" references an unknown shape or boundary", "semantic", ErrorInfo(diagramType: "c4"))
    ends.add a
    ends.add b
    pairs.mgetOrPut(a.uid, initHashSet[int]()).incl b.uid

  # What a relation's label should not cover: shapes, arrowheads, boundary headings, and the
  # labels placed before it.
  var nodes: seq[Box]
  var taken: seq[float]
  for group in order:
    for node in group.nodes:
      nodes.add node
      taken.add [node.x + EDGE, node.y + EDGE, node.x + node.w - EDGE, node.y + node.h - EDGE]
  let careful = db.rels.len * (nodes.len + order.len + 3 * db.rels.len) <= CARE_BUDGET
  proc covered(x0, y0, x1, y1: float): float =
    var i = 0
    while i < taken.len:
      let w = min(x1, taken[i + 2]) - max(x0, taken[i])
      if w > 0:
        let h = min(y1, taken[i + 3]) - max(y0, taken[i + 1])
        if h > 0: result += w * h
      i += 4
  proc offset(value: float): float =
    if value != 0 and not value.isNaN: max(-MAX_OFFSET, min(MAX_OFFSET, value)) else: 0.0

  # Every line is drawn before any label is placed, so that labels can keep off the arrowheads.
  var casings = ""
  var edgesOut = ""
  let trim = markerTrim("arrow_point")
  var fills: seq[Fill]
  for group in order:
    if group == root: continue
    let shape = userStyle(group.boundary["bgColor"], "", "").shape
    if paints(shape):
      fills.add Fill(box: [group.x, group.y, group.x + group.w, group.y + group.h], shape: shape)
  let lanes = Lanes()
  for group in order:
    if group != root: lanes.frame(group)
  var routes: seq[Route]
  for index, rel in db.rels:
    let a = ends[index * 2]
    let b = ends[index * 2 + 1]
    let style = userStyle("", rel["lineColor"], "")
    let startArrow = rel.typ == "birel" or rel.typ == "rel_b"
    let endArrow = rel.typ != "rel_b"
    let back = pairs.getOrDefault(b.uid)
    let reverse = a != b and a.uid in back
    let r = route(a, b, (if reverse: PAIR_SHIFT else: 0.0), nodes, careful, lanes,
                  (if startArrow: trim else: 0.0), (if endArrow: trim else: 0.0))
    grow(min(r.x0, r.x1), min(r.y0, r.y1), max(r.x0, r.x1), max(r.y0, r.y1))
    if startArrow and careful: taken.add [r.sx - ARROW, r.sy - ARROW, r.sx + ARROW, r.sy + ARROW]
    if endArrow and careful: taken.add [r.ex - ARROW, r.ey - ARROW, r.ex + ARROW, r.ey + ARROW]
    let over = overFills(r.d, [r.sx, r.sy, r.ex, r.ey], fills, style.line)
    let overInk = if over.none: "" else: over.ink
    let color = if overInk != "": overInk
                elif style.stroke != "": esc(style.stroke)
                else: "var(--_l)"
    if not over.none and over.ink == "":
      casings.add edgeCasing(EdgePath(d: r.d, sx: r.sx, sy: r.sy, sdx: r.sdx, sdy: r.sdy,
                                      ex: r.ex, ey: r.ey, edx: r.edx, edy: r.edy),
                             (if startArrow: "arrow_point" else: "none"),
                             (if endArrow: "arrow_point" else: "none"), style.line)
    edgesOut.add "<g class=\"pele-edge\" data-id=\"" & escText(rel.start & "-" & rel.to) & "\"" &
      (if overInk != "": " stroke=\"" & overInk & "\"" else: "") & style.line &
      "><path d=\"" & r.d & "\"/>" &
      (if startArrow: marker("arrow_point", r.sx, r.sy, r.sdx, r.sdy, color) else: "") &
      (if endArrow: marker("arrow_point", r.ex, r.ey, r.edx, r.edy, color) else: "") &
      "</g>"
    routes.add r

  # A boundary's heading goes at the left, the middle or the right of its top edge: the first of
  # them no line crosses.
  for group in order:
    if not careful or group.headW == 0: continue
    let top = group.y + HEAD_TOP
    let bottom = group.y + group.head - LANE
    var fewest = Inf
    for x in [HEAD_LEFT, (group.w - group.headW) / 2, group.w - HEAD_LEFT - group.headW]:
      var count = 0
      for r in routes:
        if crosses(r.points, group.x + x - 4, top, group.x + x + group.headW + 4, bottom): inc count
      if float(count) < fewest:
        fewest = float(count)
        group.headX = x
      if count == 0: break
    taken.add [group.x + group.headX - 4, top, group.x + group.headX + group.headW + 4, bottom]

  var labelsOut = ""
  for index, rel in db.rels:
    let r = routes[index]
    let id = rel.start & "-" & rel.to
    let style = userStyle("", "", rel["textColor"])
    let text = (if db.c4Type == "C4Dynamic": $(index + 1) & ": " else: "") & rel.label
    let label = layoutLabel(text, false, measurer, small, r.room)
    let technText = rel["techn"]
    let techn = layoutLabel(if technText != "": "[" & technText & "]" else: "", false, measurer,
                            small, r.room, Italic)
    let lw = max(label.width, techn.width) + LABEL_PAD
    let lh = label.height + techn.height
    if lh == 0: continue

    # The label sits on the line, or just beside it when another relation runs the opposite way.
    let beside = abs(r.nx) * (lw / 2) + abs(r.ny) * (lh / 2) + 2
    let aside = if r.lean != 0: max(0.0, min(r.lean, beside - 14)) else: beside
    var dx = r.nx * aside + (if tight: 0.0 else: offset(rel.offsetX))
    var dy = r.ny * aside + (if tight: 0.0 else: offset(rel.offsetY))
    var at = 0.5
    if careful:
      # Slide along the line to the spot that covers least.
      var least = Inf
      let moved = dx != r.nx * aside or dy != r.ny * aside
      var pass = 0
      while pass < (if moved: 2 else: 1) and least > 0:
        let px = if pass != 0: r.nx * aside else: dx
        let py = if pass != 0: r.ny * aside else: dy
        for t in SLIDE:
          let cx = r.x0 + (r.x1 - r.x0) * t + px
          let cy = r.y0 + (r.y1 - r.y0) * t + py
          let area = covered(cx - lw / 2, cy - lh / 2, cx + lw / 2, cy + lh / 2)
          if area < least:
            least = area
            at = t
            dx = px
            dy = py
          if area == 0: break
        inc pass
    let cx = r.x0 + (r.x1 - r.x0) * at + dx
    let top = r.y0 + (r.y1 - r.y0) * at + dy - lh / 2
    if careful: taken.add [cx - lw / 2, top, cx + lw / 2, top + lh]
    grow(cx - lw / 2, top, cx + lw / 2, top + lh)
    let descr = rel["descr"]
    labelsOut.add "<g class=\"pele-edge-label\" data-id=\"" & escText(id) & "\">" &
      (if descr != "": "<title>" & escText(descr) & "</title>" else: "") &
      "<rect x=\"" & num(cx - lw / 2) & "\" y=\"" & num(top) & "\" width=\"" & num(lw) &
      "\" height=\"" & num(lh) & "\" rx=\"3\" fill=\"var(--_bg)\"/>" &
      link(labelSvg(label, cx, top + label.height / 2, style.text) &
             labelSvg(techn, cx, top + label.height + techn.height / 2,
                      " class=\"pele-c4-techn\" fill=\"var(--_m)\"" & style.text),
           rel["link"], id, links, options) &
      "</g>"

  var clusters = ""
  var nodesOut = ""
  for group in order:
    if group != root:
      let boundary = group.boundary
      let style = userStyle(boundary["bgColor"], boundary["borderColor"], boundary["fontColor"])
      let x = group.x + group.headX
      var y = group.y + HEAD_TOP
      let color = inkFill(style.shape, style.text) & style.text
      let muted = inkFill(style.shape, style.text, "var(--_m)") & style.text
      var text = leftLabelSvg(group.labels[0], x, y,
        " class=\"pele-cluster-label\" font-weight=\"var(--_hw)\"" & color)
      y += group.labels[0].height
      text.add leftLabelSvg(group.labels[1], x, y,
        " class=\"pele-c4-type\" font-size=\"" & jsString(small) & "\"" & muted)
      y += group.labels[1].height
      text.add leftLabelSvg(group.labels[2], x, y,
        " class=\"pele-c4-descr\" font-size=\"" & jsString(small) & "\"" & muted)
      let isNode = boundary.nodeType != ""
      clusters.add "<g class=\"pele-cluster pele-c4-" & (if isNode: "node" else: "boundary") &
        "\" data-id=\"" & escText(boundary.alias) & "\">" &
        "<rect x=\"" & num(group.x) & "\" y=\"" & num(group.y) & "\" width=\"" & num(group.w) &
        "\" height=\"" & num(group.h) & "\" fill=\"none\" stroke=\"var(--_b)\"" &
        (if isNode: "" else: " stroke-dasharray=\"6 4\"") & rounded(style.shape) & "/>" &
        link(text, boundary["link"], boundary.alias, links, options) &
        "</g>"
    for node in group.nodes:
      let shape = node.shape
      let external = shape.kind.startsWith("external")
      let style = userStyle(shape["bgColor"], shape["borderColor"], shape["fontColor"])
      let stroke = " stroke=\"var(--_b)\"" & (if external: " stroke-dasharray=\"4 3\"" else: "")
      let w = node.w
      let h = node.h
      let form = node.form
      let labels = node.labels
      let dx = if form == "h-cyl": -queueRx(h) / 2 else: 0.0
      let dy = if form == "person": HEAD / 2 elif form == "cyl": cylRy(w) / 2 else: 0.0
      let color = inkFill(style.shape, style.text) & style.text
      let muted = inkFill(style.shape, style.text, "var(--_m)") & style.text
      var y = dy - node.textH / 2
      var text = labelSvg(labels[0], dx, y + labels[0].height / 2,
        " class=\"pele-c4-type\" font-size=\"" & jsString(small - 1) & "\"" & muted)
      y += labels[0].height
      text.add labelSvg(labels[1], dx, y + labels[1].height / 2,
        " class=\"pele-label\" font-weight=\"var(--_hw)\"" & color)
      y += labels[1].height
      text.add labelSvg(labels[2], dx, y + labels[2].height / 2,
        " class=\"pele-c4-techn\" font-size=\"" & jsString(small) & "\"" & muted)
      y += labels[2].height + 4
      text.add labelSvg(labels[3], dx, y + labels[3].height / 2,
        " class=\"pele-c4-descr\" font-size=\"" & jsString(small) & "\"" & color)
      nodesOut.add "<g class=\"pele-node pele-shape-" & form & " pele-c4-" & shape.kind &
        (if external: " pele-c4-external" else: "") & "\" data-id=\"" & escText(shape.alias) &
        "\" transform=\"translate(" & num(node.x + w / 2) & "," & num(node.y + h / 2) & ")\">" &
        link(drawShape(form, w, h, " fill=\"var(" & (if external: "--_bg" else: "--_s") & ")\"" &
                         stroke & style.shape, stroke & style.line) & text,
             shape["link"], shape.alias, links, options) &
        "</g>"

  let title = layoutLabel(db.title, false, measurer, size,
                          (if tight: titleRoom(options) else: 4000.0), Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0.0
  let inner = max(maxX - minX, title.width)
  let width = ceil(inner + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)
  let ox = pad - minX + (inner - (maxX - minX)) / 2
  let oy = pad + titleHeight - minY

  let svg = svgDocument("c4", width, height, size, options,
    Accessible(accTitle: db.accTitle, accDescr: db.accDescr),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      "<g transform=\"translate(" & num(ox) & "," & num(oy) & ")\">" &
      (if clusters != "": "<g class=\"pele-clusters\">" & clusters & "</g>" else: "") &
      casingsSvg(casings) &
      (if edgesOut != "": "<g class=\"pele-edges\" fill=\"none\" stroke=\"var(--_l)\" stroke-linecap=\"round\">" &
         edgesOut & "</g>" else: "") &
      (if nodesOut != "": "<g class=\"pele-nodes\">" & nodesOut & "</g>" else: "") &
      (if labelsOut != "": "<g class=\"pele-edge-labels\" font-size=\"" & jsString(small) & "\">" &
         labelsOut & "</g>" else: "") &
      "</g>")
  (Rendered(svg: svg, width: width, height: height, links: links), lanes.squeezed)

## port-of: src/diagrams/mindmap/render.ts
## port-status: conformant
import std/options
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, root, shapes, theme, title]
import ../../text/[label, icons]
import ../../types
import ../../js
import ../../util/yaml
import ../common/[fit_width, icon]
import db

const
  SHAPES = ["", "rounded", "rect", "circle", "cloud", "bang", "hex"]
    ## Indexed by Mermaid's node type. A node without delimiters is text on a line, except the root.
  ROOT_SHAPE = "stadium"

  GAP_X = 36.0
  GAP_Y = 8.0
  GROUP_GAP = 18.0
    ## Between two subtrees, of which at least one has children of its own.
  BRANCH_GAP_X = 52.0
  BRANCH_GAP_Y = 28.0
  TEXT_PAD = 6.0
  PILL_PAD = 12.0
  TINT = 0.22
  ICON_GAP = 6.0
  INDENT = 28.0
    ## Running down, each level is set in by this much, and links leave a node this far from its
    ## left edge.
  STEM = 12.0
  BEND = 8.0
  ROW_GAP = 10.0

proc leftLabel(label: Label, left, cy: float, icons: IconResolver): string =
  ## A label with each line starting at `left`, for an outline, where centered lines would look
  ## ragged.
  if label.lines.len < 2: return labelSvg(label, left + label.width / 2, cy, " class=\"pele-label\"", icons)
  let top = cy - label.height / 2
  for k in 0 ..< label.lines.len:
    result.add labelSvg(labelLine(label, k), left + label.widths[k] / 2, top + lineMiddle(label, k),
                        " class=\"pele-label\"", icons)

proc draw(model: MindmapModel, config: Config, options: RenderOptions, down: bool): Rendered

proc renderMindmap*(model: MindmapModel, config: Config, options: RenderOptions): Rendered =
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

proc draw(model: MindmapModel, config: Config, options: RenderOptions, down: bool): Rendered =
  ## `down` draws the map as an outline: the root at the top, and each level set in under its
  ## parent. It is far narrower than branches spreading to both sides, and as tall as it needs to be.
  let size = options.fontSize.get(16)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = options.icons
  let maxNodeWidth = config["mindmap"]["maxNodeWidth"]
  let wrap = if maxNodeWidth != nil and maxNodeWidth.kind == yNumber and maxNodeWidth.n > 0: jsMin(maxNodeWidth.n, 2000)
             else: 200
  let glyph = size * 1.25

  let nodes = model.nodes
  let n = nodes.len
  var parent = newSeq[int](n)
  var depth = newSeq[int](n)
  for i in 0 ..< n:
    for child in nodes[i].children:
      parent[child.id] = i
      depth[child.id] = depth[i] + 1
  # An outline has the width the host gives it, less what its level is set in.
  let room = if down and options.maxWidth.isSome and options.maxWidth.get > 0: options.maxWidth.get - 2 * pad
             else: Inf
  var labels = newSeq[Label](n)
  var shapes = newSeq[string](n)
  var w = newSeq[float](n)
  var h = newSeq[float](n)
  var dy = newSeq[float](n)
  var anchor = newSeq[float](n)
    ## Where links meet the node, measured down from its top: its middle.
  var drawn = newSeq[bool](n)
    ## Whether the host has the node's icon. One it does not have takes no room.

  for i in 0 ..< n:
    let node = nodes[i]
    drawn[i] = node.icon != "" and iconMarkup(node.icon) != ""
    let fit = jsMin(wrap, jsMax(72, room - float(depth[i]) * INDENT - 2 * TEXT_PAD - (if drawn[i]: glyph + ICON_GAP else: 0)))
    labels[i] = layoutLabel(node.descr, true, measurer, size, fit)
    let label = labels[i]
    let tw = label.width + (if drawn[i]: glyph + (if label.width > 0: ICON_GAP else: 0) else: 0)
    let th = jsMax(label.height, jsRound(size * 1.5))
    var shape = SHAPES[node.kind]
    if shape == "": shape = (if i == 0: ROOT_SHAPE else: "")
    # In an outline the root heads a column, and the trunk drops from under its left end. A circle
    # or a cloud would stand wide of that, so the root is a pill there unless it is a box already.
    if down and i == 0 and shape != "rect" and shape != "rounded": shape = ROOT_SHAPE
    shapes[i] = shape
    if shape == "":
      # A node with no shape of its own is plain text when it ends a branch, and text in a
      # tinted pill when the branch goes on from it, which sets the levels apart.
      let pill = node.children.len > 0
      w[i] = tw + 2 * (if pill: PILL_PAD else: TEXT_PAD)
      h[i] = th + (if pill: 6 else: 0)
      anchor[i] = h[i] / 2
    else:
      let s = shapeSize(shape, tw, th)
      w[i] = s.w
      h[i] = s.h
      dy[i] = s.dy
      anchor[i] = s.h / 2

  # Each subtree takes a band of height `extent`. `rel` is a subtree's offset among its siblings,
  # `own` the node's offset inside its band, and `kids` the offset of its children's bands.
  var extent = newSeq[float](n)
  var rel = newSeq[float](n)
  var own = newSeq[float](n)
  var kids = newSeq[float](n)
  var stacked = 0.0

  # Stacks subtrees top to bottom and returns the height at which their parent's anchor belongs.
  proc stack(list: seq[MindmapNode], start, stop: int, gap: float): float =
    var y = 0.0
    var last = 0.0
    for k in start ..< stop:
      let c = list[k].id
      rel[c] = y
      let grouped = list[k].children.len > 0 or (k + 1 < stop and list[k + 1].children.len > 0)
      last = if grouped: jsMax(gap, GROUP_GAP) else: gap
      y += extent[c] + last
    stacked = y - last
    let a = list[start].id
    let b = list[stop - 1].id
    (rel[a] + own[a] + anchor[a] + rel[b] + own[b] + anchor[b]) / 2

  # Nodes are in depth-first order, so going backwards visits children before their parent.
  for i in countdown(n - 1, 1):
    let children = nodes[i].children
    if children.len == 0:
      extent[i] = h[i]
      continue
    let top = stack(children, 0, children.len, GAP_Y) - anchor[i]
    let low = jsMin(0, top)
    extent[i] = jsMax(stacked, top + h[i]) - low
    own[i] = top - low
    kids[i] = -low

  var x = newSeq[float](n)
  var y = newSeq[float](n)
  var band = newSeq[float](n)
  var side = newSeq[int](n)
  var trunk = newSeq[float](n)
    ## Running down: how far the trunk under each node has been drawn.

  if down:
    # Nodes are in depth-first order, which is the order of an outline's rows.
    var row = 0.0
    for i in 0 ..< n:
      if i > 0 and parent[i] == 0: row += ROW_GAP
      x[i] = float(depth[i]) * INDENT + w[i] / 2
      y[i] = row
      row += h[i] + ROW_GAP
  elif n > 0:
    # The first branches go right and the rest left, split where the two sides are closest in height.
    let branches = nodes[0].children
    let count = branches.len
    var total = 0.0
    for branch in branches: total += extent[branch.id]
    var split = count
    var best = Inf
    var right = 0.0
    for k in 1 ..< count:
      right += extent[branches[k - 1].id]
      let diff = abs(2 * right - total + float(2 * k - count) * BRANCH_GAP_Y)
      if diff < best:
        best = diff
        split = k
    var start = 0
    var stop = split
    var dir = 1
    while start < count:
      let middle = stack(branches, start, stop, BRANCH_GAP_Y)
      for k in start ..< stop:
        let c = branches[k].id
        band[c] = rel[c] - middle
        side[c] = dir
      start = stop
      stop = count
      dir = -1
    y[0] = -h[0] / 2
    for i in 0 ..< n:
      if i > 0: y[i] = band[i] + own[i]
      for child in nodes[i].children:
        let c = child.id
        if i > 0:
          side[c] = side[i]
          band[c] = band[i] + kids[i] + rel[c]
        x[c] = x[i] + float(side[c]) * (w[i] / 2 + (if i > 0: GAP_X else: BRANCH_GAP_X) + w[c] / 2)

  var minX = 0.0
  var maxX = 0.0
  var minY = 0.0
  var maxY = 0.0
  var output = ""
  var edges = ""
  var body = ""
  var color = ""
  proc flush(section: int) =
    if body == "": return
    output.add "<g class=\"pele-branch pele-section-" & $section & "\">" &
      "<g class=\"pele-edges\" fill=\"none\" stroke=\"" & color & "\" stroke-width=\"1.5\">" & edges & "</g>" & body & "</g>"
    edges = ""
    body = ""

  # The root is drawn last, on top of the links that leave it.
  for k in 1 .. n:
    let i = k mod n
    let node = nodes[i]
    let shape = shapes[i]
    let label = labels[i]
    let cx = x[i]
    let top = y[i]
    minX = jsMin(minX, cx - w[i] / 2)
    maxX = jsMax(maxX, cx + w[i] / 2)
    minY = jsMin(minY, top)
    maxY = jsMax(maxY, top + h[i])

    if i == 0 or parent[i] == 0: flush(nodes[k - 1].section)
    if i > 0 and down:
      if parent[i] == 0: color = seriesColor(node.section)
      let p = parent[i]
      # The link drops from under its parent and turns in to the node's left. It starts where
      # the link to the sibling above turned in, so each stretch of a shared trunk has one color.
      # Under the root's rounded end, the trunk starts where that end has come down to the bottom.
      let stem = if p == 0: jsMin(jsMax(STEM, h[0] / 2), INDENT - BEND) else: STEM
      let x1 = x[p] - w[p] / 2 + jsMin(stem, w[p] / 2)
      let y1 = if trunk[p] != 0 and trunk[p] == trunk[p]: trunk[p] else: y[p] + h[p]   # trunk[p] || ...
      let left = cx - w[i] / 2
      let x2 = left + (if shape != "": shapeInset(shape, w[i], h[i], 3) else: 0)
      let y2 = top + anchor[i]
      let bend = jsMax(0, jsMin(BEND, jsMin(x2 - x1, y2 - y1)))
      # The next link carries on from where this one leaves the trunk, so the trunk has no gap.
      trunk[p] = y2 - bend
      edges.add "<path class=\"pele-edge\" d=\"M" & num(x1) & "," & num(y1) & "V" & num(y2 - bend) & "Q" &
        num(x1) & "," & num(y2) & " " & num(x1 + bend) & "," & num(y2) & "H" & num(x2) & "\"/>"
    elif i > 0:
      if parent[i] == 0: color = seriesColor(node.section)
      let p = parent[i]
      let dir = float(side[i])
      let start = if dir > 0: 1 else: 3
      let x1 = x[p] + dir * (w[p] / 2 - (if shapes[p] != "": shapeInset(shapes[p], w[p], h[p], start) else: 0))
      let y1 = y[p] + anchor[p]
      let near = cx - (dir * w[i]) / 2
      let x2 = near + (if shape != "": dir * shapeInset(shape, w[i], h[i], 4 - start) else: 0)
      let y2 = top + anchor[i]
      let mid = num((x1 + x2) / 2)
      edges.add "<path class=\"pele-edge\" d=\"M" & num(x1) & "," & num(y1) & "C" & mid & "," & num(y1) & " " &
        mid & "," & num(y2) & " " & num(x2) & "," & num(y2) & "\"/>"

    let pill = shape == "" and node.children.len > 0
    # Every node off the root is filled with a tint of its branch's color and outlined in it,
    # whether its shape was given in the source or is the pill of a node that branches.
    # The root is neutral.
    let tint = " fill=\"" & color & "\" fill-opacity=\"" & jsString(TINT) & "\" stroke=\"" & color & "\""
    var inner = ""
    if shape != "":
      inner = if i > 0: drawShape(shape, w[i], h[i], tint, " stroke=\"" & color & "\"")
              else: drawShape(shape, w[i], h[i], " fill=\"var(--_s)\" stroke=\"var(--_b)\"", " stroke=\"var(--_b)\"")
    elif pill:
      inner = "<rect x=\"" & num(-w[i] / 2) & "\" y=\"" & num(-h[i] / 2) & "\" width=\"" & num(w[i]) &
        "\" height=\"" & num(h[i]) & "\" rx=\"" & num(h[i] / 2) & "\"" & tint & "/>"
    var shift = 0.0
    if node.icon != "" and drawn[i]:
      shift = (glyph + (if label.width > 0: ICON_GAP else: 0)) / 2
      inner.add iconSvg(node.icon, -shift - label.width / 2, dy[i] - glyph / 2, glyph, icons)
    let group =
      "<g class=\"pele-node pele-shape-" & (if shape != "": shape elif pill: "branch" else: "text") &
      (if i > 0: "" else: " pele-root") & classNames(node.class) & "\" data-id=\"" & escText(node.nodeId) &
      "\" transform=\"translate(" & num(cx) & "," & num(top + h[i] / 2) & ")\">" &
      inner &
      (if down and shape == "": leftLabel(label, shift - label.width / 2, dy[i], icons)
       else: labelSvg(label, shift, dy[i], " class=\"pele-label\"", icons)) &
      "</g>"
    if i > 0: body.add group
    else: output.add group

  let title = titleLabel(model.title, measurer, size, titleRoom(options))
  let titleHeight = if title.height > 0: title.height + 16 else: 0
  let width = jsMax(maxX - minX, title.width)
  let totalWidth = ceil(width + 2 * pad)
  let totalHeight = ceil(maxY - minY + titleHeight + 2 * pad)
  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g transform=\"translate(" & num(pad - minX + (width - maxX + minX) / 2) & "," &
    num(pad + titleHeight - minY) & ")\">" & output & "</g>"

  Rendered(
    svg: svgDocument("mindmap", totalWidth, totalHeight, size, options, Accessible(), content),
    width: totalWidth,
    height: totalHeight)

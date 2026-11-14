## port-of: src/diagrams/ishikawa/render.ts
## port-status: conformant
import std/options
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, edges, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../js
import ../../jsmath
import ../common/[literal_label, fit_width]
import types

const
  SLANT = 0.5
    ## How far a bone moves toward the tail for each unit it rises from the spine.
  FIRST_ROW = 14.0
  ROW_GAP = 6.0
  BONE_END = 8.0
  TWIG_STEP = 22.0
  STUB = 18.0
  TEXT_GAP = 5.0
  PAIR_GAP = 26.0
  HEAD_GAP = 34.0
  TAIL = 28.0
  BOX_PAD_X = 10.0
  BOX_PAD_Y = 5.0

let LENGTH = hypot(SLANT, 1)

type
  Bone = ref object
    ## A cause below a category. Bones at even depths run level, from the slanted bone above them
    ## toward the tail; bones at odd depths slant away from the spine, from the level bone above them.
    label: Label
    depth: int
    parent: int
    slot: int
      ## Its place among its siblings, counted from the spine outward.
    kids: int
    rise: float
      ## How far its row is from the spine.
    at: float
      ## Where it meets its parent, measured level from the category's bone: 0 on it, negative toward the tail.
    textEnd: float
      ## Where its text ends.

  Category = ref object
    node: IshikawaNode
    label: Label
    boxW, boxH: float
    bones: seq[Bone]
    rise: float
      ## The length of its bone, as distance from the spine.
    reach: float
      ## How far its causes reach toward the tail, measured level from its bone.

  Frame = ref object
    node: IshikawaNode
    depth: int
    parent: int
    slot: int
    bone: int
      ## Set when the bone was made and only its row is still to come.

proc arrange(node: IshikawaNode, up: bool, measurer: TextMeasurer, size, small: float): Category =
  ## Gives every cause of a category a row of its own, so that no two texts can meet, and measures
  ## how far the whole of it reaches. A level bone takes the row nearest the spine and its twigs the
  ## rows beyond; a slanted twig takes the row beyond everything that hangs off it. The outline may
  ## be nested as deep as its indentation goes, so the walk keeps a stack of its own.
  let label = layoutLabel(node.text, false, measurer, size, 180)
  let lineHeight = jsRound(small * 1.5)
  var bones: seq[Bone]
  var rows: seq[int]
  var stack: seq[Frame]
  # Above the spine the first cause goes farthest out, so that the causes read from the top down.
  template push(children: seq[IshikawaNode], depth0, parent0: int) =
    let kids = children
    let n = kids.len
    for slot in countdown(n - 1, 0):
      stack.add Frame(node: kids[if up: n - 1 - slot else: slot], depth: depth0, parent: parent0, slot: slot, bone: -1)
  push(node.children, 2, -1)
  while stack.len > 0:
    let frame = stack.pop()
    if frame.bone != -1:
      rows.add frame.bone
      continue
    let index = bones.len
    bones.add Bone(
      label: layoutLabel(frame.node.text, false, measurer, small, 200),
      depth: frame.depth,
      parent: frame.parent,
      slot: frame.slot,
      kids: frame.node.children.len)
    if frame.depth mod 2 == 0: rows.add index
    else:
      frame.bone = index
      stack.add frame
    push(frame.node.children, frame.depth + 1, index)

  var rise = FIRST_ROW
  for index in rows:
    let height = max(bones[index].label.height, lineHeight) + ROW_GAP
    bones[index].rise = rise + height / 2
    rise += height
  let boxW = label.width + 2 * BOX_PAD_X
  var reach = boxW / 2
  for bone in bones:
    if bone.depth mod 2 == 0:
      bone.at = if bone.parent != -1: bones[bone.parent].at else: 0
      bone.textEnd = bone.at - (if bone.kids > 0: float(bone.kids + 1) * TWIG_STEP else: STUB) - TEXT_GAP
    else:
      # Twigs stand along their level bone, the one nearest the spine nearest the tail.
      let parent = bones[bone.parent]
      bone.at = parent.at - float(parent.kids - bone.slot) * TWIG_STEP
      bone.textEnd = bone.at - TEXT_GAP
    reach = max(reach, bone.label.width - bone.textEnd)
  Category(node: node, label: label, boxW: boxW, boxH: label.height + 2 * BOX_PAD_Y, bones: bones,
           rise: rise + BONE_END, reach: reach)

proc draw(model: IshikawaModel, config: Config, options: RenderOptions, down: bool): Rendered
proc verticalCauses(model: IshikawaModel, options: RenderOptions): Rendered

proc renderIshikawa*(model: IshikawaModel, config: Config, options: RenderOptions): Rendered =
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, down))

proc draw(model: IshikawaModel, config: Config, options: RenderOptions, down: bool): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  if down: return verticalCauses(model, options)
  let root = model.root
  let title = layoutLabel(model.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0

  var body = ""
  var minX = 0.0
  var maxX = 0.0
  var minY = 0.0
  var maxY = 0.0
  if root != nil:
    let head = layoutLabel(root.text, false, measurer, size, 200, Bold)
    let headH = max(head.height + 24, 48.0)
    let headW = head.width + 24 + headH / 2
    var categories: seq[Category]
    for i, node in root.children: categories.add arrange(node, i mod 2 == 0, measurer, size, small)
    # Even a category without causes has a bone long enough to carry its name clear of the head.
    for category in categories: category.rise = max(category.rise, headH / 2 + 14)

    # Categories meet the spine in pairs, one above and one below, each pair as far toward the
    # tail from the one before as the wider of the two needs.
    var xs: seq[float]
    var x = -HEAD_GAP
    var i = 0
    while i < categories.len:
      if i > 0:
        var room = 0.0
        for side in 0 ..< 2:
          let b = i - 2 + side
          let nx = i + side
          if b < categories.len:
            room = max(room, categories[b].reach + (if nx < categories.len: categories[nx].boxW / 2 else: 0))
        x -= room + PAIR_GAP
      xs.add x
      xs.add x
      i += 2
    let tail = if categories.len > 0: x - TAIL else: -HEAD_GAP

    maxX = headW
    minX = tail
    minY = -headH / 2
    maxY = headH / 2
    var groups = ""
    for i, category in categories:
      let sign = if i mod 2 == 0: -1.0 else: 1.0
      let ax = xs[i]
      template px(at, rise: float): float = ax + at - rise * SLANT
      let endX = px(0, category.rise)
      let endY = sign * category.rise
      # The bone stops short of the spine to leave its arrowhead a clean point.
      let trim = ARROW - 1
      var d = "M" & num(ax - (SLANT / LENGTH) * trim) & "," & num((sign * trim) / LENGTH) & "L" & num(endX) & "," & num(endY)
      var texts = ""
      for bone in category.bones:
        let y = sign * bone.rise
        if bone.depth mod 2 == 0:
          d.add "M" & num(px(bone.at, bone.rise)) & "," & num(y) & "H" & num(px(bone.textEnd + TEXT_GAP, bone.rise))
        else:
          let start = category.bones[bone.parent].rise
          d.add "M" & num(px(bone.at, start)) & "," & num(sign * start) & "L" & num(px(bone.at, bone.rise)) & "," & num(y)
        let right = px(bone.textEnd, bone.rise)
        texts.add labelSvg(bone.label, right - bone.label.width / 2, y, if bone.depth > 2: " fill=\"var(--_m)\"" else: "")
        minX = min(minX, right - bone.label.width)
      let boxY = endY + sign * (category.boxH / 2)
      minX = min(minX, endX - category.boxW / 2)
      maxX = max(maxX, endX + category.boxW / 2)
      minY = min(minY, boxY - category.boxH / 2)
      maxY = max(maxY, boxY + category.boxH / 2)
      groups.add "<g class=\"pele-ishikawa-category\" data-id=\"" & escText(category.node.text) & "\">" &
        "<path class=\"pele-ishikawa-bones\" d=\"" & d & "\" fill=\"none\" stroke=\"var(--_l)\"/>" &
        marker("arrow_point", ax, 0, SLANT / LENGTH, -sign / LENGTH, "var(--_l)") &
        "<rect x=\"" & num(endX - category.boxW / 2) & "\" y=\"" & num(boxY - category.boxH / 2) & "\" width=\"" &
        num(category.boxW) & "\" height=\"" & num(category.boxH) & "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"" & ROUNDED & "/>" &
        labelSvg(category.label, endX, boxY, " class=\"pele-label\"") &
        (if texts != "": "<g class=\"pele-ishikawa-causes\" font-size=\"" & jsString(small) & "\">" & texts & "</g>" else: "") &
        "</g>"

    let r = headH / 2
    body = "<path class=\"pele-ishikawa-spine\" d=\"M" & num(tail) & ",0H" & num(-(ARROW - 1)) & "\" fill=\"none\" stroke=\"var(--_l)\"/>" &
      marker("arrow_point", 0, 0, 1, 0, "var(--_l)") &
      groups &
      "<g class=\"pele-ishikawa-head\" data-id=\"" & escText(root.text) & "\">" &
      "<path d=\"M0," & num(-r) & "H" & num(headW - r) & "A" & num(r) & "," & num(r) & " 0 0 1 " & num(headW - r) & "," &
      num(r) & "H0Z\" fill=\"var(--_s)\" stroke=\"var(--_b)\" stroke-linejoin=\"round\"/>" &
      labelSvg(head, 12 + head.width / 2, 0, " class=\"pele-label\" font-weight=\"var(--_hw)\"") &
      "</g>"

  let inner = max(maxX - minX, title.width)
  let width = ceil(inner + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)
  let ox = pad + (inner - (maxX - minX)) / 2 - minX
  let oy = pad + titleHeight - minY
  let svg = svgDocument("ishikawa", width, height, size, options, Accessible(),
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
      (if body != "": "<g transform=\"translate(" & num(ox) & "," & num(oy) & ")\">" & body & "</g>" else: ""))
  Rendered(svg: svg, width: width, height: height, links: @[])

type Entry = ref object
  node: IshikawaNode
  depth: int
  parent: int
  x, y, w, h: float
  label: Label

proc verticalCauses(model: IshikawaModel, options: RenderOptions): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.875)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let room = max(140.0, options.maxWidth.get(320) - 2 * pad)
  let title = layoutLabel(model.title, false, measurer, size, titleRoom(options), Bold)
  var order: seq[Entry]
  var pending: seq[(IshikawaNode, int, int)]
  if model.root != nil: pending.add (model.root, 0, -1)
  var depth = 0
  while pending.len > 0:
    let (node, d, parent) = pending.pop()
    let index = order.len
    order.add Entry(node: node, depth: d, parent: parent)
    depth = max(depth, d)
    for i in countdown(node.children.len - 1, 0): pending.add (node.children[i], d + 1, index)
  let indent = min(20.0, max(2.0, (room - 120) / max(1.0, float(depth))))
  var y = pad + (if title.height != 0: title.height + 12 else: 0)
  var width = title.width
  var nodes = ""
  var edges = ""
  for entry in order:
    entry.x = pad + float(entry.depth) * indent
    let labelRoom = max(60.0, room - float(entry.depth) * indent - 20)
    entry.label = breakLabel(layoutLabel(entry.node.text, false, measurer, if entry.depth < 2: size else: small,
                                         labelRoom, if entry.depth < 2: Bold else: 0), measurer, labelRoom)
    entry.w = entry.label.width + 20
    entry.h = entry.label.height + 12
    entry.y = y
    y += entry.h + 12
    width = max(width, entry.x - pad + entry.w)
    let framed = entry.depth < 2
    nodes.add "<g class=\"pele-node " &
      (if entry.depth == 0: "pele-ishikawa-head" elif entry.depth == 1: "pele-ishikawa-category" else: "pele-ishikawa-cause") &
      "\" data-id=\"" & escText(entry.node.text) & "\">" &
      (if framed: "<rect x=\"" & num(entry.x) & "\" y=\"" & num(entry.y) & "\" width=\"" & num(entry.w) & "\" height=\"" &
                  num(entry.h) & "\" rx=\"" & (if entry.depth == 0: "12" else: "4") & "\" fill=\"var(--_s)\" stroke=\"var(--_b)\"/>"
       else: "") &
      labelSvg(entry.label, entry.x + entry.w / 2, entry.y + entry.h / 2,
               " class=\"pele-label\"" & (if entry.depth < 2: " font-weight=\"var(--_hw)\"" else: "") &
                 (if entry.depth > 1: " font-size=\"" & jsString(small) & "\"" else: "")) & "</g>"
    if entry.parent >= 0:
      let parent = order[entry.parent]
      let gx = parent.x + indent / 2
      edges.add "<path class=\"pele-edge\" d=\"M" & num(gx) & "," & num(parent.y + parent.h) & "V" &
        num(entry.y + entry.h / 2) & "H" & num(entry.x) & "\" fill=\"none\" stroke=\"var(--_b)\"/>"
  let totalWidth = ceil(width + 2 * pad)
  let height = ceil(max(pad + title.height, y - 12) + pad)
  let content = labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    edges & nodes
  Rendered(svg: svgDocument("ishikawa", totalWidth, height, size, options, Accessible(), content),
           width: totalWidth, height: height, links: @[])

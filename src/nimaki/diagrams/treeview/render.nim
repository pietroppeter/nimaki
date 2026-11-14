## port-of: src/diagrams/treeview/render.ts
## port-status: draft
import std/[options, strutils, tables]
from std/math import ceil
import ../../preprocess
import ../../svg/[builder, root, theme]
import ../../text/[entities, label, measurer]
import ../../types
import ../../js
import ../../util/yaml
import ../common/[fit_width, literal_label]
import icons, model
import ../../jsregex

const
  ICON_GAP = 6.0
  DESC_GAP = 16.0
  GUIDE_INSET = 7.0
  ELBOW = 4.0
  HIGHLIGHT_OVERHANG = 4.0

proc setting(config: Config, key: string, fallback, min, max: float): float =
  let value = config["treeView"][key]
  if value != nil and value.kind == yNumber and value.n >= min and value.n <= max: value.n
  else: fallback

type TreeSettings* = object
  paddingX*, paddingY*, rowIndent*, lineThickness*: float

proc treeSettings*(config: Config): TreeSettings =
  ## Mermaid's layout options, with Pele's defaults.
  TreeSettings(
    paddingX: setting(config, "paddingX", 5, 0, 100),
    paddingY: setting(config, "paddingY", 2, 0, 100),
    rowIndent: setting(config, "rowIndent", 15, 0, 400),
    lineThickness: setting(config, "lineThickness", 1, 0.25, 12))

type Row = ref object
  node: TreeNode
  x, cy: float
  icon: string              ## "" for undefined
  text: string
  labelX: float
  highlighted: bool
  hasLabel, hasDescription: bool
  label, description: Label
  top, height: float

proc draw(model: TreeViewModel, config: Config, options: RenderOptions, tight: bool): Rendered

proc renderTreeView*(model: TreeViewModel, config: Config, options: RenderOptions): Rendered =
  tighten(options, proc (tight: bool): Rendered = draw(model, config, options, tight))

proc draw(model: TreeViewModel, config: Config, options: RenderOptions, tight: bool): Rendered =
  let size = options.fontSize.get(16)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)
  let icons = iconConfig(config)
  let mono = "files" in options.monospace
  let family = if mono: " font-family=\"" & FONT_MONO & "\"" else: ""

  let s = treeSettings(config)
  let (paddingX, paddingY, rowIndent, lineThickness) = (s.paddingX, s.paddingY, s.rowIndent, s.lineThickness)
  var maxDepth = 0
  var depths: seq[(TreeNode, int)]
  for node in model.root.children: depths.add (node, 0)
  var k = 0
  while tight and k < depths.len:
    let (node, depth) = depths[k]
    maxDepth = max(maxDepth, depth)
    for child in node.children: depths.add (child, depth + 1)
    inc k
  let step = if tight: jsMin(rowIndent + paddingX, jsMax(2, (options.maxWidth.get(320) - 120) / float(max(1, maxDepth))))
             else: rowIndent + paddingX
  let rowHeight = jsRound(size * 1.5) + 2 * paddingY
  let iconSize = size

  let title = layoutLabel(model.title, false, measurer, size, (if tight: titleRoom(options) else: 4000), Bold)
  let titleHeight = if title.height > 0: title.height + 12 else: 0

  proc nodeIcon(node: TreeNode): string =
    getNodeIcon(node.icon, node.name, node.nodeType == "directory", icons)

  # Siblings line up: when one entry of a folder has an icon, the others leave room for one.
  proc hasIcon(list: seq[TreeNode]): bool =
    for child in list:
      if nodeIcon(child) != "": return true
    false
  var rows: seq[Row]
  var rowOf = initTable[int, Row]()
  var pending: seq[(TreeNode, int, bool)]
  proc push(list: seq[TreeNode], depth: int) =
    let slot = hasIcon(list)
    for i in countdown(list.high, 0): pending.add (list[i], depth, slot)
  push(model.root.children, 0)
  var labelRight = 0.0
  var anyHighlight = false
  var rowsHeight = 0.0
  while pending.len > 0:
    let (node, depth, slot) = pending.pop()
    let x = float(depth) * step
    let text = decodeEntities(node.name)
    let labelX = x + (if slot: iconSize + ICON_GAP else: 0)
    let room = jsMax(40, options.maxWidth.get(320) - 2 * pad - 2 * HIGHLIGHT_OVERHANG - labelX)
    let style = (if node.nodeType == "directory": Bold else: 0) or (if mono: Mono else: 0)
    let row = Row(node: node, x: x, icon: nodeIcon(node), text: text, labelX: labelX)
    if tight:
      row.hasLabel = true
      row.label = literalLabel(text, measurer, size, room, style)
      if node.description != "":
        row.hasDescription = true
        row.description = literalLabel(decodeEntities(node.description), measurer, size, room, Italic)
    let width = if row.hasLabel: row.label.width else: measurer.width(text, size, style)
    if labelX + width > labelRight: labelRight = labelX + width
    row.highlighted = node.cssClass != "" and "highlight" in node.cssClass.split(jsre"/\s+/")
    if row.highlighted: anyHighlight = true
    let labelHeight = if row.hasLabel: row.label.height else: 0
    let descriptionHeight = if row.hasDescription: row.description.height else: 0
    let height = if tight: jsMax(rowHeight, labelHeight + descriptionHeight + 2 * paddingY) else: rowHeight
    row.cy = rowsHeight + (if tight: paddingY + jsMax(iconSize, labelHeight) / 2 else: height / 2)
    row.top = rowsHeight
    row.height = height
    rowsHeight += height
    rows.add row
    rowOf[node.id] = row
    push(node.children, depth + 1)

  let descX = labelRight + DESC_GAP
  var width = labelRight
  for row in rows:
    let description = row.node.description
    if description == "": continue
    let w = if row.hasDescription: row.description.width
            else: measurer.width(decodeEntities(description), size, Italic)
    width = jsMax(width, (if tight: row.labelX else: descX) + w)
  width = jsMax(width, title.width)
  let inset = pad + (if anyHighlight: HIGHLIGHT_OVERHANG else: 0)
  let top = pad + titleHeight
  let totalWidth = ceil(width + 2 * inset)
  let totalHeight = ceil(top + rowsHeight + pad)

  var guides = ""
  for row in rows:
    let children = row.node.children
    if children.len == 0: continue
    let gx = inset + row.x + GUIDE_INSET
    let tick = jsMax(gx, inset + row.x + step - paddingX)
    let last = top + rowOf[children[^1].id].cy
    let r = jsMin(ELBOW, tick - gx)
    var d = "M" & num(gx) & "," & num(top + row.top + row.height - 2) & "V" & num(last - r)
    if r > 0: d.add "Q" & num(gx) & "," & num(last) & " " & num(gx + r) & "," & num(last) & "H" & num(tick)
    var i = 0
    while i < children.len - 1 and tick > gx:
      d.add "M" & num(gx) & "," & num(top + rowOf[children[i].id].cy) & "H" & num(tick)
      inc i
    guides.add "<path d=\"" & d & "\"/>"

  let baseline = size * 0.35
  var body = ""
  for row in rows:
    let node = row.node
    let cy = top + row.cy
    let directory = node.nodeType == "directory"
    var inner = ""
    if row.highlighted:
      let x = inset + row.x - HIGHLIGHT_OVERHANG
      inner.add "<rect class=\"pele-tree-highlight\" x=\"" & num(x) & "\" y=\"" & num(top + row.top + 1) &
        "\" width=\"" & num(totalWidth - inset + HIGHLIGHT_OVERHANG - x) & "\" height=\"" &
        num(row.height - 2) & "\" fill=\"var(--_c)\" fill-opacity=\"0.14\"" & ROUNDED & "/>"
    if row.icon != "":
      let prefix = BUILTIN_PACK & ":"
      let name = if row.icon.startsWith(prefix): row.icon[prefix.len .. ^1] else: ""
      let glyph = GLYPHS.getOrDefault(name, GLYPHS[if directory: "folder" else: "file"])
      let hosted = if options.icons != nil: options.icons(row.icon) else: ""
      let drawn = if hosted != "": hosted
                  else: "<path d=\"" & glyph & "\" stroke=\"var(--_m)\" stroke-width=\"1.5\"/>"
      inner.add "<svg class=\"pele-icon\" data-icon=\"" & escText(row.icon) & "\" x=\"" & num(inset + row.x) &
        "\" y=\"" & num(cy - iconSize / 2) & "\" width=\"" & num(iconSize) & "\" height=\"" & num(iconSize) &
        "\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" &
        drawn & "</svg>"
    if row.hasLabel:
      inner.add leftLabelSvg(row.label, inset + row.labelX, top + row.top + paddingY,
        " class=\"pele-label\"" & (if directory: " font-weight=\"var(--_hw)\"" else: "") & family)
    elif row.text != "":
      inner.add "<text class=\"pele-label\" x=\"" & num(inset + row.labelX) & "\" y=\"" & num(cy + baseline) & "\"" &
        (if directory: " font-weight=\"var(--_hw)\"" else: "") & family & " xml:space=\"preserve\">" &
        esc(row.text) & "</text>"
    if row.hasDescription:
      inner.add leftLabelSvg(row.description, inset + row.labelX,
        top + row.top + paddingY + (if row.hasLabel: row.label.height else: 0),
        " class=\"pele-tree-description\" font-style=\"italic\" fill=\"var(--_m)\"")
    elif node.description != "":
      inner.add "<text class=\"pele-tree-description\" x=\"" & num(inset + descX) & "\" y=\"" & num(cy + baseline) &
        "\" font-style=\"italic\" fill=\"var(--_m)\" xml:space=\"preserve\">" &
        esc(decodeEntities(node.description)) & "</text>"
    body.add "<g class=\"pele-node pele-tree-" & (if directory: "dir" else: "file") & classNames(node.cssClass) &
      "\" data-id=\"" & escText(node.name) & "\">" & inner & "</g>"

  let content =
    labelSvg(title, totalWidth / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    (if guides != "": "<g class=\"pele-tree-guides\" fill=\"none\" stroke=\"var(--_b)\" stroke-width=\"" &
       num(lineThickness) & "\">" & guides & "</g>" else: "") &
    body

  Rendered(
    svg: svgDocument("treeView", totalWidth, totalHeight, size, options,
                     Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
    width: totalWidth,
    height: totalHeight)

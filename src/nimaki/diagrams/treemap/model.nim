## port-of: src/diagrams/treemap/model.ts
## port-status: conformant
import std/[strutils, tables, options]
import ../../js
import parser

type
  TreemapNode* = ref object
    name*: string
    leaf*: bool
      ## Sections have a list of children, which may be empty. Leaves have none.
    children*: seq[TreemapNode]
    value*: Option[float]
    classSelector*: string        ## "" for undefined
    cssCompiledStyles*: seq[string]

  TreemapItem* = object
    level*: int
    name*: string
    leaf*: bool                   ## Pele's type: 'Leaf' or 'Section'
    value*: Option[float]
    classSelector*: string
    cssCompiledStyles*: seq[string]   ## empty for undefined

  TreemapModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    roots*: seq[TreemapNode]
    classes*: OrderedTable[string, seq[string]]

proc buildHierarchy*(items: seq[TreemapItem]): seq[TreemapNode] =
  ## A row belongs to the nearest section above it that is indented less.
  var stack: seq[(TreemapNode, int)]
  for item in items:
    let node = TreemapNode(name: item.name, leaf: item.leaf)
    node.classSelector = item.classSelector
    if item.cssCompiledStyles.len > 0: node.cssCompiledStyles = item.cssCompiledStyles
    if item.leaf and item.value.isSome: node.value = item.value

    while stack.len > 0 and stack[^1][1] >= item.level: discard stack.pop()
    if stack.len == 0: result.add node
    else: stack[^1][0].children.add node
    if not item.leaf: stack.add (node, item.level)

func collapseIndents(s: string): string =
  ## s.replace(/\n\s+/g, '\n')
  var i = 0
  while i < s.len:
    if s[i] == '\n' and spaceLenAt(s, i + 1) > 0:
      result.add '\n'
      i += 1
      while true:
        let n = spaceLenAt(s, i)
        if n == 0: break
        i += n
      continue
    result.add s[i]
    inc i

proc buildTreemap*(ast: TreemapAst, title: string): TreemapModel =
  var classes = initOrderedTable[string, seq[string]]()
  for row in ast.rows:
    if not row.classDef: continue
    if row.className notin classes: classes[row.className] = @[]
    # An escaped comma stays in the value; the others separate declarations.
    let text = row.styleText.replace("\\,", "§§§").replace(",", ";").replace("§§§", ",")
    for style in text.split(';'): classes[row.className].add style

  var items: seq[TreemapItem]
  for row in ast.rows:
    if row.classDef: continue
    let item = row.item
    let styles = if item.classSelector != "": classes.getOrDefault(item.classSelector) else: @[]
    items.add TreemapItem(
      level: row.indent,
      name: item.name,
      leaf: item.leaf,
      value: if item.leaf: some(item.value) else: none(float),
      classSelector: item.classSelector,
      cssCompiledStyles: styles)

  TreemapModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": jsTrimStart(ast.accTitle) else: "",   # replace(/^\s+/g, '')
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "",
    roots: buildHierarchy(items),
    classes: classes)

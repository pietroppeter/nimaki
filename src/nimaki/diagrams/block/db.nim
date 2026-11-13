## port-of: src/diagrams/block/db.ts
## port-status: draft
##
## Also holds the types of src/diagrams/block/types.ts. A Block's optional strings are "" for
## undefined, which every reader treats as Pele does; `widthInColumns` is NaN for undefined, and
## `hasId` is false for a composite whose header was a link statement. Pele's `children` holds
## statements until `setHierarchy` turns them into blocks: here those are `statements` and
## `children`.
import std/[tables, sets, strutils]
from std/math import isNaN
import ../../errors
import ../../js

type
  Block* = ref object
    id*: string
    hasId*: bool
    typ*, label*: string
    statements*: seq[Statement]
    children*: seq[Block]
    columns*: float           ## -1 for undefined
    widthInColumns*: float    ## NaN for undefined
    width*: float             ## cells a `space` statement asked for
    directions*: seq[string]
    classes*, styles*: seq[string]
    colorIndex*: int
    start*, stop*, arrowTypeStart*, arrowTypeEnd*, thickness*, pattern*: string
    css*, styleClass*, stylesStr*: string

  Statement* = object
    ## A block, or a list (block, edge, block...) when the statement had links.
    isList*: bool
    blocks*: seq[Block]

  BlockClassDef* = object
    id*: string
    styles*, textStyles*: seq[string]

  BlockDb* = ref object of RootObj
    title*, accTitle*, accDescr*: string
    root*: Block
    blocks*, edges*: seq[Block]
    classes*: OrderedTable[string, BlockClassDef]
    byId*: Table[string, Block]
    pending: HashSet[string]
    edgeCount: Table[string, int]
    ids, colors: int
    spaces: float

const MAX_SPACES = 100000.0

func one*(b: Block): Statement = Statement(blocks: @[b])

proc newBlock*(id = "", typ = ""): Block =
  Block(id: id, hasId: true, typ: typ, columns: -1, widthInColumns: NaN, width: NaN)

proc copy(b: Block): Block =
  new result
  result[] = b[]

proc newBlockDb*(): BlockDb =
  let root = newBlock("root", "composite")
  BlockDb(root: root)

func typeStr2Type*(typeStr: string): string =
  case typeStr
  of "[]": "square"
  of "()": "round"
  of "(())": "circle"
  of ">]": "rect_left_inv_arrow"
  of "{}": "diamond"
  of "{{}}": "hexagon"
  of "([])": "stadium"
  of "[[]]": "subroutine"
  of "[()]": "cylinder"
  of "((()))": "doublecircle"
  of "[//]": "lean_right"
  of "[\\\\]": "lean_left"
  of "[/\\]": "trapezoid"
  of "[\\/]": "inv_trapezoid"
  of "<[]>": "block_arrow"
  else: "na"

func edgeStrToEdgeData*(typeStr: string): string =
  let s = jsTrim(typeStr)
  if s.len == 0: return ""
  case s[^1]
  of 'x': "arrow_cross"
  of 'o': "arrow_circle"
  of '>': "arrow_point"
  else: ""

func edgeStrToEdgeStartData*(typeStr: string): string =
  let s = jsTrim(typeStr)
  if s.len == 0: return "arrow_open"
  case s[0]
  of 'x': "arrow_cross"
  of 'o': "arrow_circle"
  of '<': "arrow_point"
  else: "arrow_open"

func edgeStrToThickness*(typeStr: string): string =
  if "==" in typeStr: "thick" else: "normal"

func edgeStrToPattern*(typeStr: string): string =
  if ".-" in typeStr: "dotted" else: "solid"

type Frame = object
  list: seq[Block]
  at: int
  parent: Block
  children: seq[Block]
  columns: float

proc frame(statements: seq[Statement], parent: Block): Frame =
  var list: seq[Block]
  for s in statements: list.add s.blocks
  var columns = -1.0
  for b in list:
    if b.typ == "column-setting":
      columns = b.columns
      break
  Frame(list: list, at: 0, parent: parent, columns: columns)

proc generateId*(db: BlockDb): string =
  ## Mermaid's ids are random. These are counted, so the same text always gives the same output.
  inc db.ids
  "id-" & $db.ids

func replaceFirst(s, sub, by: string): string =
  let at = s.find(sub)
  if at == -1: s else: s[0 ..< at] & by & s[at + sub.len .. ^1]

proc addStyleClass(db: BlockDb, id: string, styleAttributes: string) =
  let found = addr db.classes.mgetOrPut(id, BlockClassDef(id: id))
  for attribute in styleAttributes.split(','):
    let semi = attribute.find(';')
    let fixed = jsTrim(if semi == -1: attribute else: attribute[0 ..< semi] & attribute[semi + 1 .. ^1])
    if "color" in attribute:
      found.textStyles.add fixed.replaceFirst("fill", "bgFill").replaceFirst("color", "fill")
    found.styles.add fixed

proc named(db: BlockDb, id: string): Block =
  result = db.byId.getOrDefault(id)
  if result == nil:
    result = newBlock(id, "na")
    db.byId[id] = result
    db.pending.incl id

proc addStyle2Node(db: BlockDb, id, styles: string) =
  db.named(id).styles = styles.split(',')

proc setCssClass(db: BlockDb, itemIds, cssClassName: string) =
  for id in itemIds.split(','): db.named(jsTrim(id)).classes.add cssClassName

proc setHierarchy*(db: BlockDb, statements: seq[Statement]) =
  var stack = @[frame(statements, db.root)]
  while stack.len > 0:
    let top = stack.high
    if stack[top].at == stack[top].list.len:
      stack[top].parent.children = stack[top].children
      discard stack.pop()
      continue
    let b = stack[top].list[stack[top].at]
    inc stack[top].at
    case b.typ
    of "classDef":
      db.addStyleClass(b.id, b.css)
      continue
    of "applyClass":
      db.setCssClass(b.id, b.styleClass)
      continue
    of "applyStyles":
      if b.stylesStr != "": db.addStyle2Node(b.id, b.stylesStr)
      continue
    of "column-setting":
      stack[top].parent.columns = b.columns
      continue
    of "edge":
      let count = db.edgeCount.getOrDefault(b.id) + 1
      db.edgeCount[b.id] = count
      b.id = $count & "-" & b.id
      db.edges.add b
      continue
    else: discard

    # A composite whose header was a link statement has no id of its own.
    if not b.hasId:
      b.id = db.generateId()
      b.hasId = true
    if b.label == "": b.label = (if b.typ == "composite": "" else: b.id)
    let known = db.byId.getOrDefault(b.id)
    var fresh = known == nil
    if not fresh and b.id in db.pending:
      db.pending.excl b.id
      fresh = true
    if not fresh:
      if b.typ != "na": known.typ = b.typ
      if b.label != b.id: known.label = b.label
    else:
      if known != nil:
        b.classes = known.classes
        b.styles = known.styles
      if b.typ == "composite":
        b.colorIndex = db.colors
        inc db.colors
      db.byId[b.id] = b

    let inner = b.statements
    b.statements = @[]
    b.children = @[]
    if b.typ == "space":
      let width = if b.width.isNaN: 1.0 else: b.width
      if not (width <= MAX_SPACES - db.spaces):
        raise newPeleError("A block diagram can hold at most " & jsString(MAX_SPACES) & " space blocks.",
                           "limit", ErrorInfo(diagramType: "block"))
      db.spaces += max(width, 0.0)
      var j = 0
      while float(j) < width:
        let c = copy(b)
        c.id = b.id & "-" & $j
        c.children = @[]
        db.byId[c.id] = c
        stack[top].children.add c
        inc j
    elif fresh:
      stack[top].children.add b
    if inner.len > 0: stack.add frame(inner, b)
  db.blocks = db.root.children

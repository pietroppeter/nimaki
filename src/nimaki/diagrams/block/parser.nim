## port-of: src/diagrams/block/parser.ts
## port-status: conformant
import std/options
import ../../errors
import ../../js
import db, lexer, tokens

type
  NodeInfo = object
    id, label, typeStr: string
    directions: seq[string]
  Frame = object
    list: seq[Statement]
    hasHeader: bool
    header: Statement

const STATEMENT_START =
  "'NODE_ID', 'COLUMNS', 'SPACE_BLOCK', 'BLOCK_DIAGRAM_KEY', 'id-block', 'classDef', 'class', 'style'"

func digitsValue(s: string): float =
  ## parseInt of a run of digits, or of "-1".
  if s == "-1": return -1
  for c in s: result = result * 10 + float(ord(c) - ord('0'))

proc closeDocument(list: seq[Statement]): seq[Statement] =
  ## The grammar inlines a document's last statement when it is a list.
  if list.len == 0 or not list[^1].isList: return list
  result = list[0 ..< ^1]
  for b in list[^1].blocks: result.add one(b)

proc parseBlock*(src: string, db: BlockDb) =
  let toks = tokenize(src)
  let types = toks.types
  let texts = toks.texts
  var i = 0

  proc fail(expected: string) {.noreturn.} =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("block", src, toks.starts[i], "", true)
    raise syntaxError("block", src, toks.starts[i],
      "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")
  proc expect(typ: int): string =
    if types[i] != typ: fail("'" & TOKEN_NAMES[typ] & "'")
    result = texts[i]
    inc i

  proc node(): NodeInfo =
    let id = expect(T_NODE_ID)
    if types[i] == T_NODE_DSTART:
      let open = texts[i]
      inc i
      let label = expect(T_STR)
      return NodeInfo(id: id, label: label, typeStr: open & expect(T_NODE_DEND))
    if types[i] == T_BLOCK_ARROW_START:
      let open = texts[i]
      inc i
      let label = expect(T_STR)
      var directions = @[expect(T_DIR)]
      while types[i] == T_DIR:
        directions.add texts[i]
        inc i
      return NodeInfo(id: id, label: label, typeStr: open & expect(T_BLOCK_ARROW_END),
                      directions: directions)
    NodeInfo(id: id)

  proc nodeStatement(): Statement =
    let first = node()
    var size = 1.0
    if types[i] == T_SIZE:
      size = digitsValue(texts[i])
      inc i
    var start = newBlock(first.id, typeStr2Type(first.typeStr))
    start.label = first.label
    start.directions = first.directions
    start.widthInColumns = size
    var chain: seq[Block]
    var isChain = false
    while types[i] == T_LINK or types[i] == T_START_LINK:
      var label = ""
      let t = types[i]
      inc i
      if t == T_START_LINK:
        discard expect(T_LINK_LABEL)
        label = expect(T_STR)
        discard expect(T_LINK)
      let link = texts[i - 1]
      let to = node()
      # Mermaid keeps only the last link of `A --> B --> C` and loses its start. Here every link counts.
      if not isChain:
        isChain = true
        let head = newBlock(start.id, start.typ)
        head.label = start.label
        head.directions = start.directions
        chain.add head
      start = newBlock(to.id, typeStr2Type(to.typeStr))
      start.label = to.label
      start.directions = to.directions
      let prev = chain[^1].id
      let edge = newBlock(prev & "-" & to.id, "edge")
      edge.start = prev
      edge.stop = to.id
      edge.label = label
      edge.thickness = edgeStrToThickness(link)
      edge.pattern = edgeStrToPattern(link)
      edge.directions = to.directions
      edge.arrowTypeEnd = edgeStrToEdgeData(link)
      edge.arrowTypeStart = edgeStrToEdgeStartData(link)
      chain.add edge
      chain.add start
    if isChain: Statement(isList: true, blocks: chain) else: one(start)

  discard expect(T_KEY)
  # Composites nest without recursion: each open one keeps the statement list of its parent.
  var open: seq[Frame]
  var list: seq[Statement]
  while true:
    case types[i]
    of T_NODE_ID:
      list.add nodeStatement()
    of T_COLUMNS:
      let b = newBlock("", "column-setting")
      b.columns = some(digitsValue(texts[i]))
      inc i
      list.add one(b)
    of T_SPACE_BLOCK:
      let width = digitsValue(texts[i])
      inc i
      let b = newBlock(db.generateId(), "space")
      b.width = width
      list.add one(b)
    of T_KEY:
      inc i
      open.add Frame(list: list)
      list = @[]
    of T_ID_BLOCK:
      inc i
      if types[i] != T_NODE_ID: fail("'NODE_ID'")
      open.add Frame(list: list, hasHeader: true, header: nodeStatement())
      list = @[]
    of T_end:
      if open.len == 0 or list.len == 0: fail(STATEMENT_START)
      let frame = open.pop()
      inc i
      let id = db.generateId()
      let children = closeDocument(list)
      list = frame.list
      var b: Block
      if not frame.hasHeader:
        b = newBlock(id, "composite")
      elif frame.header.isList:
        b = newBlock("", "composite")
      else:
        b = Block()
        b[] = frame.header.blocks[0][]
        b.typ = "composite"
      b.statements = children
      list.add one(b)
    of T_CLASSDEF:
      inc i
      let b = newBlock(jsTrim(expect(T_CLASSDEF_ID)), "classDef")
      b.css = jsTrim(expect(T_CLASSDEF_STYLEOPTS))
      list.add one(b)
    of T_CLASS:
      inc i
      let b = newBlock(jsTrim(expect(T_CLASSENTITY_IDS)), "applyClass")
      b.styleClass = jsTrim(expect(T_STYLECLASS))
      list.add one(b)
    of T_STYLE:
      inc i
      let b = newBlock(jsTrim(expect(T_STYLE_ENTITY_IDS)), "applyStyles")
      b.stylesStr = jsTrim(expect(T_STYLE_DEFINITION_DATA))
      list.add one(b)
    of T_EOF:
      if open.len > 0: fail(STATEMENT_START & ", 'end'")
      if list.len == 0: fail(STATEMENT_START)
      db.setHierarchy(closeDocument(list))
      return
    else:
      fail(if list.len == 0: STATEMENT_START
           else: STATEMENT_START & (if open.len > 0: ", 'end'" else: ", 'EOF'"))

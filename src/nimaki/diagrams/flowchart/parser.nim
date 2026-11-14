## port-of: src/diagrams/flowchart/parser.ts
## port-status: conformant
##
## Pele's `T.END` (the end of the tokens) is `T_STOP`; `T_end` is the stop keyword. The
## `Uint8Array` tables of token types are sets.
import std/[options, tables]
import ../../errors
import ../../js
import db, lexer, tokens, types

const ID: set[uint8] = {
  T_NUM.uint8,
  T_NODE_STRING.uint8,
  T_DOWN.uint8,
  T_MINUS.uint8,
  T_DEFAULT.uint8,
  T_COMMA.uint8,
  T_COLON.uint8,
  T_AMP.uint8,
  T_BRKT.uint8,
  T_MULT.uint8,
  T_UNICODE_TEXT.uint8,
}

const ALPHANUM: set[uint8] = {
  T_NUM.uint8,
  T_UNICODE_TEXT.uint8,
  T_NODE_STRING.uint8,
  T_DIR.uint8,
  T_DOWN.uint8,
  T_MINUS.uint8,
  T_COMMA.uint8,
  T_COLON.uint8,
  T_AMP.uint8,
  T_BRKT.uint8,
  T_MULT.uint8,
}

const NO_TAGS: set[uint8] = {
  T_NUM.uint8,
  T_NODE_STRING.uint8,
  T_SPACE.uint8,
  T_MINUS.uint8,
  T_AMP.uint8,
  T_UNICODE_TEXT.uint8,
  T_COLON.uint8,
  T_MULT.uint8,
  T_BRKT.uint8,
  T_STYLE.uint8,
  T_LINKSTYLE.uint8,
  T_CLASSDEF.uint8,
  T_CLASS.uint8,
  T_CLICK.uint8,
  T_GRAPH.uint8,
  T_DIR.uint8,
  T_subgraph.uint8,
  T_end.uint8,
  T_DOWN.uint8,
  T_UP.uint8,
  T_START_LINK.uint8,
}

const STYLE_PART: set[uint8] = {T_NUM.uint8, T_NODE_STRING.uint8, T_COLON.uint8, T_SPACE.uint8,
                                T_BRKT.uint8, T_STYLE.uint8}

func isIn(t: int, s: set[uint8]): bool = t >= 0 and t < 256 and t.uint8 in s

type Frame = object
  id: Option[FlowText]
  title: Option[FlowText]
  same: bool          ## Pele's `id === title`: the header has no title of its own
  list: seq[DocItem]
  collect: bool

const TEXT_TOKENS = "'UNICODE_TEXT', 'TEXT', 'TAGSTART'"
const DIRECTIONS = ["TB", "BT", "RL", "LR", "TD"]
const STATEMENT_START =
  "'SEMI', 'NEWLINE', 'SPACE', 'EOF', 'subgraph', 'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'STYLE', 'LINKSTYLE', 'CLASSDEF', 'CLASS', 'CLICK', 'NODE_STRING'"

func noItems(): DocItem = DocItem(kind: dkList)

# Mermaid trims whitespace between a closing brace and the end of its line before parsing.
proc braceTrail(source: string): seq[Edit] =
  ## The matches of /}\s*\n/g: a brace, then the whitespace after it up to its last line feed.
  var p = 0
  while p < source.len:
    if source[p] == '}':
      var q = p + 1
      var last = -1
      while q < source.len and isJsSpaceAt(source, q):
        if source[q] == '\n': last = q
        q += spaceLenAt(source, q)
      if last >= 0:
        result.add (p, last + 1, 2)
        p = last + 1
        continue
    inc p

proc replaceBraceTrail(source: string, edits: seq[Edit]): string =
  var at = 0
  for (first, last, length) in edits:
    result.add source[at ..< first]
    result.add "}\n"
    at = last
  result.add source[at .. ^1]

proc parseFlowchart*(source: string, db: FlowDb) =
  let edits = if '}' in source: braceTrail(source) else: @[]
  let src = if '}' in source: replaceBraceTrail(source, edits) else: source
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  var i = 0
  var pendingData = none(string)

  proc fail(expected: string) =
    let t = types[i]
    let at = if src == source: starts[i] else: inputOffset(@[edits], starts[i])
    if t == T_ERROR: raise syntaxError("flowchart", source, at, "", true)
    raise syntaxError("flowchart", source, at, "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")

  proc expect(t: int, also = ""): string =
    if types[i] != t: fail("'" & TOKEN_NAMES[t] & "'" & (if also != "": ", " & also else: ""))
    result = texts[i]
    inc i

  proc separator() =
    let t = types[i]
    if t != T_NEWLINE and t != T_SEMI and t != T_EOF: fail("'SEMI', 'NEWLINE', 'EOF'")
    inc i

  proc idString(): string =
    if not types[i].isIn(ID): fail("'NODE_STRING'")
    var s = texts[i]
    inc i
    while types[i].isIn(ID):
      s.add texts[i]
      inc i
    s

  proc alphaNum(): string =
    if not types[i].isIn(ALPHANUM): fail("'NODE_STRING'")
    var s = texts[i]
    inc i
    while types[i].isIn(ALPHANUM):
      s.add texts[i]
      inc i
    s

  proc text(): FlowText =
    let t = types[i]
    var typ: LabelType
    if t == T_STR: typ = "string"
    elif t == T_MD_STR: typ = "markdown"
    elif t == T_TEXT or t == T_TAGSTART or t == T_TAGEND or t == T_UNICODE_TEXT: typ = "text"
    else: fail(TEXT_TOKENS & ", 'TAGEND', 'STR', 'MD_STR'")
    var s = texts[i]
    inc i
    while true:
      let n = types[i]
      if n != T_TEXT and n != T_TAGSTART and n != T_TAGEND and n != T_UNICODE_TEXT: break
      s.add texts[i]
      inc i
    FlowText(text: s, kind: typ)

  proc closed(t: int) =
    discard expect(t, TEXT_TOKENS)

  proc edgeText(): FlowText =
    let t = types[i]
    var typ: LabelType
    if t == T_STR: typ = "string"
    elif t == T_MD_STR: typ = "markdown"
    elif t == T_EDGE_TEXT or t == T_UNICODE_TEXT: typ = "text"
    else: fail("'EDGE_TEXT', 'STR', 'MD_STR'")
    var s = texts[i]
    inc i
    while types[i] == T_EDGE_TEXT or types[i] == T_UNICODE_TEXT:
      s.add texts[i]
      inc i
    FlowText(text: s, kind: typ)

  proc textNoTags(): FlowText =
    let t = types[i]
    var typ: LabelType
    if t == T_STR: typ = "text"
    elif t == T_MD_STR: typ = "markdown"
    elif t.isIn(NO_TAGS): typ = "text"
    else: fail("'NODE_STRING', 'STR', 'MD_STR'")
    var s = texts[i]
    inc i
    while types[i].isIn(NO_TAGS):
      s.add texts[i]
      inc i
    FlowText(text: s, kind: typ)

  proc shapeData(): string =
    var s = texts[i]
    inc i
    while types[i] == T_SHAPE_DATA:
      s.add texts[i]
      inc i
    s

  proc vertex(): string =
    let id = idString()
    var label: FlowText
    case types[i]
    of T_SQS:
      inc i
      label = text()
      closed(T_SQE)
      db.addVertex(id, some(label), "square")
    of T_DOUBLECIRCLESTART:
      inc i
      label = text()
      closed(T_DOUBLECIRCLEEND)
      db.addVertex(id, some(label), "doublecircle")
    of T_PS:
      inc i
      if types[i] == T_PS:
        inc i
        label = text()
        closed(T_PE)
        discard expect(T_PE)
        db.addVertex(id, some(label), "circle")
      else:
        label = text()
        closed(T_PE)
        db.addVertex(id, some(label), "round")
    of T_ELLIPSE_START:
      inc i
      label = text()
      closed(T_ELLIPSE_END)
      db.addVertex(id, some(label), "ellipse")
    of T_STADIUMSTART:
      inc i
      label = text()
      closed(T_STADIUMEND)
      db.addVertex(id, some(label), "stadium")
    of T_SUBROUTINESTART:
      inc i
      label = text()
      closed(T_SUBROUTINEEND)
      db.addVertex(id, some(label), "subroutine")
    of T_VERTEX_WITH_PROPS_START:
      inc i
      let field = expect(T_NODE_STRING)
      discard expect(T_COLON)
      let value = expect(T_NODE_STRING)
      discard expect(T_PIPE)
      label = text()
      closed(T_SQE)
      db.addVertex(id, some(label), "rect", props = some({field: value}.toTable))
    of T_CYLINDERSTART:
      inc i
      label = text()
      closed(T_CYLINDEREND)
      db.addVertex(id, some(label), "cylinder")
    of T_DIAMOND_START:
      inc i
      if types[i] == T_DIAMOND_START:
        inc i
        label = text()
        closed(T_DIAMOND_STOP)
        discard expect(T_DIAMOND_STOP)
        db.addVertex(id, some(label), "hexagon")
      else:
        label = text()
        closed(T_DIAMOND_STOP)
        db.addVertex(id, some(label), "diamond")
    of T_TAGEND:
      inc i
      label = text()
      closed(T_SQE)
      db.addVertex(id, some(label), "odd")
    of T_TRAPSTART:
      inc i
      label = text()
      if types[i] == T_INVTRAPEND:
        inc i
        db.addVertex(id, some(label), "lean_right")
      else:
        closed(T_TRAPEND)
        db.addVertex(id, some(label), "trapezoid")
    of T_INVTRAPSTART:
      inc i
      label = text()
      if types[i] == T_TRAPEND:
        inc i
        db.addVertex(id, some(label), "lean_left")
      else:
        closed(T_INVTRAPEND)
        db.addVertex(id, some(label), "inv_trapezoid")
    else:
      db.addVertex(id)
    id

  proc styledVertex(): string =
    let id = vertex()
    if types[i] == T_STYLE_SEPARATOR:
      inc i
      db.setClass(id, idString())
    id

  proc node(): seq[string] =
    var ids = @[styledVertex()]
    pendingData = none(string)
    while true:
      let data = if types[i] == T_SHAPE_DATA: some(shapeData()) else: none(string)
      if types[i] != T_SPACE:
        pendingData = data
        return ids
      inc i
      while types[i] == T_SPACE: inc i
      if types[i] != T_AMP:
        if data.isSome: fail("'AMP'")
        return ids
      inc i
      if types[i] != T_SPACE: fail("'SPACE'")
      inc i
      while types[i] == T_SPACE: inc i
      let next = styledVertex()
      if data.isSome:
        db.addVertex(ids[^1], metadata = data)
      ids.add next

  proc link(): FlowLinkInfo =
    var id = ""
    if types[i] == T_LINK_ID:
      id = texts[i]
      inc i
    if types[i] == T_LINK:
      var info = db.destructLink(texts[i])
      inc i
      if id != "": info.id = id
      if types[i] == T_PIPE:
        inc i
        info.text = some(text())
        closed(T_PIPE)
        if types[i] == T_SPACE: inc i
      return info
    if types[i] == T_START_LINK:
      let start = texts[i]
      inc i
      let label = edgeText()
      let e = expect(T_LINK, "'EDGE_TEXT'")
      var info = db.destructLink(e, start)
      info.text = some(label)
      if id != "": info.id = id
      return info
    fail("'LINK', 'START_LINK'")

  proc vertexStatement(collect: bool): seq[string] =
    var stmt = node()
    if pendingData.isSome:
      db.addVertex(stmt[^1], metadata = pendingData)
    var nodes = stmt
    while true:
      let t = types[i]
      if t != T_LINK and t != T_START_LINK and t != T_LINK_ID: return nodes
      let info = link()
      let next = node()
      if pendingData.isSome:
        db.addVertex(next[^1], metadata = pendingData)
      db.addLink(stmt, next, some(info))
      if collect: nodes = next & nodes
      stmt = next

  proc style(): string =
    if not types[i].isIn(STYLE_PART): fail("'NODE_STRING', 'NUM', 'COLON', 'BRKT'")
    var s = texts[i]
    inc i
    while types[i].isIn(STYLE_PART):
      s.add texts[i]
      inc i
    s

  proc stylesOpt(): seq[string] =
    var output = @[style()]
    while types[i] == T_COMMA:
      inc i
      output.add style()
    output

  proc linkStyleStatement() =
    inc i
    discard expect(T_SPACE)
    var positions: seq[string]
    if types[i] == T_DEFAULT:
      positions = @[texts[i]]
      inc i
    else:
      positions = @[expect(T_NUM, "'DEFAULT'")]
      while types[i] == T_COMMA:
        inc i
        positions.add expect(T_NUM)
    discard expect(T_SPACE)
    if types[i] != T_INTERPOLATE:
      db.updateLink(positions, stylesOpt())
      return
    inc i
    discard expect(T_SPACE)
    let interpolate = alphaNum()
    if types[i] == T_SPACE:
      inc i
      let styles = stylesOpt()
      db.updateLinkInterpolate(positions, interpolate)
      db.updateLink(positions, styles)
    else:
      db.updateLinkInterpolate(positions, interpolate)

  proc linkTail(id, url: string) =
    if types[i] != T_SPACE:
      db.setLink(id, url)
      return
    inc i
    if types[i] == T_LINK_TARGET:
      let target = texts[i]
      inc i
      db.setLink(id, url, target)
      return
    let tooltip = expect(T_STR, "'LINK_TARGET'")
    if types[i] == T_SPACE:
      inc i
      db.setLink(id, url, expect(T_LINK_TARGET))
    else:
      db.setLink(id, url)
    db.setTooltip(id, some(tooltip))

  proc clickStatement() =
    let id = texts[i]
    inc i
    case types[i]
    of T_CALLBACKNAME:
      let name = texts[i]
      inc i
      let hasArgs = types[i] == T_CALLBACKARGS
      var args = ""
      if hasArgs:
        args = texts[i]
        inc i
      var tooltip = none(string)
      if types[i] == T_SPACE:
        inc i
        tooltip = some(expect(T_STR))
      if hasArgs: db.setClickEvent(id, name, args)
      else: db.setClickEvent(id, name)
      if tooltip.isSome: db.setTooltip(id, tooltip)
    of T_HREF:
      inc i
      let url = expect(T_STR)
      linkTail(id, url)
    of T_STR:
      let url = texts[i]
      inc i
      linkTail(id, url)
    else:
      let name = alphaNum()
      if types[i] == T_SPACE:
        inc i
        let tooltip = expect(T_STR)
        db.setClickEvent(id, name)
        db.setTooltip(id, some(tooltip))
      else:
        db.setClickEvent(id, name)

  proc subgraphHeader(): Frame =
    inc i
    var t = types[i]
    if t == T_NEWLINE or t == T_SEMI or t == T_EOF:
      inc i
      return Frame(id: none(FlowText), title: none(FlowText))
    discard expect(T_SPACE, "'SEMI', 'NEWLINE', 'EOF'")
    let id = textNoTags()
    var title = id
    var same = true
    if types[i] == T_SQS:
      inc i
      title = text()
      same = false
      closed(T_SQE)
    t = types[i]
    if t != T_NEWLINE and t != T_SEMI and t != T_EOF: fail("'SEMI', 'NEWLINE', 'EOF', 'SQS'")
    inc i
    Frame(id: some(id), title: some(title), same: same)

  proc statement(collect: bool): DocItem =
    let t = types[i]
    case t
    of T_STYLE:
      inc i
      discard expect(T_SPACE)
      let id = idString()
      discard expect(T_SPACE)
      db.addVertex(id, style = some(stylesOpt()))
      separator()
      noItems()
    of T_LINKSTYLE:
      linkStyleStatement()
      separator()
      noItems()
    of T_CLASSDEF:
      inc i
      discard expect(T_SPACE)
      let id = idString()
      discard expect(T_SPACE)
      db.addClass(id, stylesOpt())
      separator()
      noItems()
    of T_CLASS:
      inc i
      discard expect(T_SPACE)
      let ids = idString()
      discard expect(T_SPACE)
      db.setClass(ids, idString())
      separator()
      noItems()
    of T_CLICK:
      clickStatement()
      separator()
      noItems()
    of T_direction_tb, T_direction_bt, T_direction_rl, T_direction_lr, T_direction_td:
      inc i
      DocItem(kind: dkDir, value: DIRECTIONS[t - T_direction_tb])
    of T_acc_title:
      inc i
      let value = expect(T_acc_title_value).jsTrim
      db.setAccTitle(value)
      DocItem(kind: dkString, s: value)
    of T_acc_descr:
      inc i
      let value = expect(T_acc_descr_value).jsTrim
      db.setAccDescription(value)
      DocItem(kind: dkString, s: value)
    of T_acc_descr_multiline_value:
      let value = texts[i].jsTrim
      inc i
      db.setAccDescription(value)
      DocItem(kind: dkString, s: value)
    else:
      if not t.isIn(ID): fail(STATEMENT_START)
      let nodes = vertexStatement(collect)
      separator()
      DocItem(kind: dkList, items: nodes)

  # Subgraphs nest without recursion: each open one keeps the list and collect flag of its parent.
  proc document() =
    var open: seq[Frame]
    var list: seq[DocItem]
    var collect = false
    while true:
      let t = types[i]
      if t == T_STOP: break
      if t == T_end:
        if open.len == 0: break
        let frame = open.pop()
        inc i
        let id = db.addSubGraph(frame.id, list, frame.title, frame.same)
        list = frame.list
        collect = frame.collect
        if collect: list.add DocItem(kind: dkString, s: id)
      elif t == T_SEMI or t == T_NEWLINE or t == T_SPACE or t == T_EOF:
        if collect: list.add DocItem(kind: dkString, s: texts[i])
        inc i
      elif t == T_subgraph:
        var frame = subgraphHeader()
        frame.list = list
        frame.collect = collect
        open.add frame
        list = @[]
        collect = true
      else:
        let item = statement(collect)
        if collect and (item.kind != dkList or item.items.len > 0): list.add item
    if open.len > 0: fail("'end'")

  while types[i] == T_SPACE or types[i] == T_NEWLINE: inc i
  discard expect(T_GRAPH, "'SPACE', 'NEWLINE'")
  if types[i] == T_NODIR:
    inc i
    db.setDirection("TB")
  else:
    let dir = expect(T_DIR, "'NODIR'")
    var t = types[i]
    if t == T_SPACE:
      inc i
      while types[i] == T_SPACE: inc i
      t = types[i]
      if t != T_NEWLINE: fail("'NEWLINE', 'SPACE'")
    elif t != T_SEMI and t != T_NEWLINE:
      fail("'SEMI', 'NEWLINE', 'SPACE'")
    inc i
    db.setDirection(dir)
  document()
  if types[i] != T_STOP: fail(STATEMENT_START)

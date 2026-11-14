## port-of: src/diagrams/agentflow/parser.ts
## port-status: conformant
##
## Pele's `T.END` (the end of the tokens) is `T_STOP`; `T_end` is the keyword that closes a block.
## The `Uint8Array` tables of token types are sets. Pele also records where each statement sits
## (`add...Mapping`), for editors; nothing drawn reads it, so the port leaves it out.
import std/[options, tables]
import ../../errors
import ../../js
import db, lexer, tokens, types
import ../../jsregex

const ID: set[uint8] = {
  T_NUM.uint8, T_NODE_STRING.uint8, T_DOWN.uint8, T_MINUS.uint8, T_DEFAULT.uint8, T_COMMA.uint8,
  T_COLON.uint8, T_AMP.uint8, T_BRKT.uint8, T_MULT.uint8, T_UNICODE_TEXT.uint8,
}

const ALPHANUM: set[uint8] = {
  T_NUM.uint8, T_UNICODE_TEXT.uint8, T_NODE_STRING.uint8, T_DIR.uint8, T_DOWN.uint8,
  T_MINUS.uint8, T_COMMA.uint8, T_COLON.uint8, T_AMP.uint8, T_BRKT.uint8, T_MULT.uint8,
}

const NO_TAGS: set[uint8] = {
  T_NUM.uint8, T_NODE_STRING.uint8, T_SPACE.uint8, T_MINUS.uint8, T_AMP.uint8,
  T_UNICODE_TEXT.uint8, T_COLON.uint8, T_MULT.uint8, T_BRKT.uint8, T_STYLE.uint8,
  T_LINKSTYLE.uint8, T_CLASSDEF.uint8, T_CLASS.uint8, T_CLICK.uint8, T_GRAPH.uint8, T_DIR.uint8,
  T_flow.uint8, T_connector.uint8, T_global.uint8, T_end.uint8, T_DOWN.uint8, T_UP.uint8,
  T_START_LINK.uint8,
}

const STYLE_PART: set[uint8] = {T_NUM.uint8, T_NODE_STRING.uint8, T_COLON.uint8, T_SPACE.uint8,
                                T_BRKT.uint8, T_STYLE.uint8}

const SEPARATOR: set[uint8] = {T_NEWLINE.uint8, T_SEMI.uint8, T_EOF.uint8, T_COMMENT.uint8}

const TRAILING: set[uint8] = {T_COMMENT.uint8, T_NEWLINE.uint8, T_SPACE.uint8, T_EOF.uint8}

func isIn(t: int, s: set[uint8]): bool = t >= 0 and t < 256 and t.uint8 in s

type Frame = object
  global: bool
  at: int                ## token index of the `flow` keyword
  id: Option[FlowText]
  title: Option[FlowText]
  data: Option[string]
  dataFrom, dataTo: int
  list: seq[DocItem]
  collect: bool

const TEXT_TOKENS = "'UNICODE_TEXT', 'TEXT', 'TAGSTART'"
const SEPARATORS = "'COMMENT', 'SEMI', 'NEWLINE', 'EOF'"
const DIRECTIONS = ["TB", "BT", "RL", "LR", "TD"]
const STATEMENT_START =
  "'COMMENT', 'SEMI', 'NEWLINE', 'SPACE', 'EOF', 'flow', 'global', 'connector', 'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'STYLE', 'LINKSTYLE', 'CLASSDEF', 'CLASS', 'CLICK', 'NODE_STRING'"

func noItems(): DocItem = DocItem(kind: dkList)

# Mermaid trims spaces and tabs between a closing brace and the end of its line before parsing.
const RE_BRACE_TRAIL = jsre"/}[^\S\n]*\n/g"

proc parseAgentflow*(source: string, db: AgentflowDb, raw = false) =
  ## `raw` parses the text as it is, the way Mermaid's generated parser does without its wrapper.
  let src = if not raw and '}' in source: source.replace(RE_BRACE_TRAIL, "}\n") else: source
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  let locs = tokens.locs
  var i = 0
  var pendingData = none(string)
  var dataFrom = 0
  var dataTo = 0

  proc fail(expected: string) =
    let t = types[i]
    var start = starts[i]
    if t == T_EOF or t == T_STOP:
      # Comments are tokens here, so skip trailing ones.
      var k = i
      while k > 0 and types[k - 1].isIn(TRAILING): dec k
      start = jsTrimEnd(src[0 ..< starts[k]]).len
    let at = if src == source: start else: inputOffset(@[replacements(source, RE_BRACE_TRAIL, 2)], start)
    if t == T_ERROR: raise syntaxError("agentflow", source, at, "", true)
    raise syntaxError("agentflow", source, at, "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")

  # The span from the start of token `a` to the end of token `b`.
  proc span(a, b: int): Loc =
    Loc(firstLine: locs[4 * a], firstColumn: locs[4 * a + 1], lastLine: locs[4 * b + 2],
        lastColumn: locs[4 * b + 3])

  proc expect(t: int, also = ""): string =
    if types[i] != t: fail("'" & TOKEN_NAMES[t] & "'" & (if also != "": ", " & also else: ""))
    result = texts[i]
    inc i

  proc separator() =
    if not types[i].isIn(SEPARATOR): fail(SEPARATORS)
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
    dataFrom = i
    var s = texts[i]
    inc i
    while types[i] == T_SHAPE_DATA:
      s.add texts[i]
      inc i
    dataTo = i - 1
    s

  proc attach(id, data: string, a, b: int) =
    db.addVertex(id, metadata = some(data), metadataLoc = some(span(a, b)))

  proc attachData(id: string, frame: Frame) =
    if frame.data.isNone: return
    db.addVertex(id, metadata = frame.data, metadataLoc = some(span(frame.dataFrom, frame.dataTo)))

  proc vertex(): string =
    let id = idString()
    var label: FlowText
    var typ = ""
    var props = none(Table[string, string])
    case types[i]
    of T_SQS:
      inc i
      label = text()
      closed(T_SQE)
      typ = "square"
    of T_DOUBLECIRCLESTART:
      inc i
      label = text()
      closed(T_DOUBLECIRCLEEND)
      typ = "doublecircle"
    of T_PS:
      inc i
      if types[i] == T_PS:
        inc i
        label = text()
        closed(T_PE)
        discard expect(T_PE)
        typ = "circle"
      else:
        label = text()
        closed(T_PE)
        typ = "round"
    of T_ELLIPSE_START:
      inc i
      label = text()
      closed(T_ELLIPSE_END)
      typ = "ellipse"
    of T_STADIUMSTART:
      inc i
      label = text()
      closed(T_STADIUMEND)
      typ = "stadium"
    of T_SUBROUTINESTART:
      inc i
      label = text()
      closed(T_SUBROUTINEEND)
      typ = "subroutine"
    of T_VERTEX_WITH_PROPS_START:
      inc i
      let field = expect(T_NODE_STRING)
      discard expect(T_COLON)
      let value = expect(T_NODE_STRING)
      discard expect(T_PIPE)
      label = text()
      closed(T_SQE)
      typ = "rect"
      props = some({field: value}.toTable)
    of T_CYLINDERSTART:
      inc i
      label = text()
      closed(T_CYLINDEREND)
      typ = "cylinder"
    of T_DIAMOND_START:
      inc i
      if types[i] == T_DIAMOND_START:
        inc i
        label = text()
        closed(T_DIAMOND_STOP)
        discard expect(T_DIAMOND_STOP)
        typ = "hexagon"
      else:
        label = text()
        closed(T_DIAMOND_STOP)
        typ = "diamond"
    of T_TAGEND:
      inc i
      label = text()
      closed(T_SQE)
      typ = "odd"
    of T_TRAPSTART:
      inc i
      label = text()
      if types[i] == T_INVTRAPEND:
        inc i
        typ = "lean_right"
      else:
        closed(T_TRAPEND)
        typ = "trapezoid"
    of T_INVTRAPSTART:
      inc i
      label = text()
      if types[i] == T_TRAPEND:
        inc i
        typ = "lean_left"
      else:
        closed(T_INVTRAPEND)
        typ = "inv_trapezoid"
    else: discard
    if props.isSome: db.addVertex(id, some(label), typ, props = props)
    elif typ != "": db.addVertex(id, some(label), typ)
    else: db.addVertex(id)
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
      let a = dataFrom
      let b = dataTo
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
      if data.isSome: attach(ids[^1], data.get, a, b)
      ids.add next

  proc link(): LinkInfo =
    var id = ""
    var hasId = false
    if types[i] == T_LINK_ID:
      id = texts[i]
      hasId = true
      inc i
    if types[i] == T_LINK:
      var info = db.destructLink(texts[i])
      inc i
      if hasId: info.id = id
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
      if hasId: info.id = id
      return info
    fail("'LINK', 'START_LINK'")

  proc vertexStatement(): seq[string] =
    var stmt = node()
    if pendingData.isSome: attach(stmt[^1], pendingData.get, dataFrom, dataTo)
    var nodes = stmt
    while true:
      let t = types[i]
      if t != T_LINK and t != T_START_LINK and t != T_LINK_ID: return nodes
      let info = link()
      let next = node()
      if pendingData.isSome: attach(next[^1], pendingData.get, dataFrom, dataTo)
      db.addLink(stmt, next, some(info))
      nodes = next & nodes
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

  # Reads `flow` or `connector` up to the separator: an id, an optional bracketed title, optional metadata.
  proc header(at: int): Frame =
    discard expect(T_SPACE, SEPARATORS)
    let id = textNoTags()
    var title = FlowText(text: "", kind: "text")
    if types[i] == T_SQS:
      inc i
      title = text()
      closed(T_SQE)
    let data = if types[i] == T_SHAPE_DATA: some(shapeData()) else: none(string)
    if not types[i].isIn(SEPARATOR): fail(SEPARATORS & ", 'SHAPE_DATA'")
    Frame(global: false, at: at, id: some(id), title: some(title), data: data,
          dataFrom: dataFrom, dataTo: dataTo)

  proc statement(): DocItem =
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
    of T_connector:
      let at = i
      inc i
      let frame = header(at)
      inc i
      let id = db.addConnector(frame.id.get, frame.title.get)
      attachData(id, frame)
      DocItem(kind: dkString, s: id)
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
      let nodes = vertexStatement()
      separator()
      DocItem(kind: dkList, items: nodes)

  # Blocks nest without recursion: each open one keeps the list and collect flag of its parent.
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
        if frame.global:
          db.addGlobal(list)
          list = frame.list
          collect = frame.collect
          continue
        let id = db.addSubGraph(frame.id, list, frame.title)
        attachData(id, frame)
        list = frame.list
        collect = frame.collect
        if collect: list.add DocItem(kind: dkString, s: id)
      elif t == T_SEMI or t == T_NEWLINE or t == T_SPACE or t == T_EOF:
        if collect: list.add DocItem(kind: dkString, s: texts[i])
        inc i
      elif t == T_COMMENT:
        inc i
      elif t == T_flow or t == T_global:
        let at = i
        inc i
        var frame: Frame
        if t == T_global or types[i].isIn(SEPARATOR):
          frame = Frame(global: t == T_global, at: at, list: list, collect: collect)
          separator()
        else:
          frame = header(at)
          frame.list = list
          frame.collect = collect
          inc i
        open.add frame
        list = @[]
        collect = true
      else:
        let item = statement()
        if collect and (item.kind != dkList or item.items.len > 0): list.add item
    if open.len > 0: fail("'end'")

  while types[i] == T_SPACE or types[i] == T_NEWLINE or types[i] == T_COMMENT: inc i
  discard expect(T_GRAPH, "'SPACE', 'NEWLINE', 'COMMENT'")
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
    elif t != T_SEMI and t != T_NEWLINE and t != T_COMMENT:
      fail("'COMMENT', 'SEMI', 'NEWLINE', 'SPACE'")
    inc i
    db.setDirection(dir)
  document()
  if types[i] != T_STOP: fail(STATEMENT_START)

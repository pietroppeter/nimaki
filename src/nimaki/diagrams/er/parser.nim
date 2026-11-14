## port-of: src/diagrams/er/parser.ts
## port-status: conformant
import std/strutils
import ../../errors
import ../../js
import db, lexer, tokens, types

func cardinality(t: int): Cardinality =
  ## CARDINALITY.get(t); "" for undefined
  case t
  of T_ZERO_OR_ONE: "ZERO_OR_ONE"
  of T_ZERO_OR_MORE: "ZERO_OR_MORE"
  of T_ONE_OR_MORE: "ONE_OR_MORE"
  of T_ONLY_ONE: "ONLY_ONE"
  of T_MD_PARENT: "MD_PARENT"
  else: ""

const DIRECTIONS = ["TB", "BT", "RL", "LR"]

const
  NAME = "'UNICODE_TEXT', 'NUM', 'ENTITY_NAME', 'DECIMAL_NUM', 'ENTITY_ONE'"
  CARDS = "'ZERO_OR_ONE', 'ZERO_OR_MORE', 'ONE_OR_MORE', 'ONLY_ONE', 'MD_PARENT'"
  LINE =
    "'EOF', 'NEWLINE', 'title', 'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'SUBGRAPH', 'direction_tb', " &
    "'direction_bt', 'direction_rl', 'direction_lr', 'CLASSDEF', 'CLASS', 'STYLE', " &
    NAME

type Frame = ref object
  id: string
  title: string
  # What Mermaid's grammar hands to addSubGraph: the value of every statement inside. Besides entity
  # names that includes accessibility text and the keywords `style`, `class` and `classDef`.
  list: seq[DocItem]

func unquote(text: string): string =
  ## text.slice(1, -1)
  if text.len <= 2: "" else: text[1 ..< text.len - 1]

proc parseEr*(src: string, db: ErDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  var i = 0

  proc typeAt(k: int): int = (if k < types.len: types[k] else: -1)

  proc fail(expected: string) =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("er", src, starts[i], "", true)
    raise syntaxError("er", src, starts[i], "Expecting " & expected & ", got '" &
                      (if t == T_CHAR: texts[i] else: TOKEN_NAMES[t]) & "'")

  proc expect(t: int): string =
    if typeAt(i) != t: fail("'" & TOKEN_NAMES[t] & "'")
    result = texts[i]
    inc i

  proc separator() =
    let t = typeAt(i)
    if t != T_NEWLINE and t != T_SEMI and t != T_EOF: fail("'EOF', 'NEWLINE', 'SEMI'")
    inc i

  proc isName(t: int): bool =
    t == T_UNICODE_TEXT or t == T_ENTITY_NAME or t == T_NUM or t == T_DECIMAL_NUM or t == T_ENTITY_ONE

  proc entityName(): string =
    let t = typeAt(i)
    if not isName(t): fail(NAME)
    let text = texts[i]
    inc i
    if t == T_ENTITY_NAME: unquote(text) else: text

  proc idList(): seq[string] =
    while true:
      let t = typeAt(i)
      if t != T_UNICODE_TEXT and t != T_STYLE_TEXT: fail("'UNICODE_TEXT', 'STYLE_TEXT'")
      result.add texts[i]
      inc i
      if typeAt(i) != T_COMMA: return
      inc i

  proc isStyleComponent(t: int): bool = t == T_STYLE_TEXT or t == T_NUM or t == T_COLON or t == T_BRKT

  proc stylesOpt(): seq[string] =
    while true:
      if not isStyleComponent(typeAt(i)): fail("'STYLE_TEXT', 'COLON', 'NUM', 'BRKT'")
      var style = texts[i]
      inc i
      while isStyleComponent(typeAt(i)):
        style.add texts[i]
        inc i
      result.add style
      if typeAt(i) != T_COMMA: return
      inc i

  proc relSpec(): RelSpec =
    let cardB = cardinality(types[i])
    inc i
    let r = typeAt(i)
    if r != T_IDENTIFYING and r != T_NON_IDENTIFYING: fail("'NON_IDENTIFYING', 'IDENTIFYING'")
    let relType = if r == T_IDENTIFYING: "IDENTIFYING" else: "NON_IDENTIFYING"
    inc i
    let cardA = cardinality(typeAt(i))
    if cardA == "": fail(CARDS)
    inc i
    RelSpec(cardA: cardA, relType: relType, cardB: cardB)

  proc role(): string =
    let t = typeAt(i)
    if t != T_WORD and t != T_ENTITY_NAME and t != T_UNICODE_TEXT: fail("'UNICODE_TEXT', 'ENTITY_NAME', 'WORD'")
    let text = texts[i]
    inc i
    if t == T_UNICODE_TEXT: text else: unquote(text)

  proc isChar(ch: string): bool = typeAt(i) == T_CHAR and texts[i] == ch

  # Returns the attributes last to first, as Mermaid's right-recursive rule builds them.
  proc attributes(): seq[ParsedAttribute] =
    var list: seq[ParsedAttribute]
    while true:
      var kind = expect(T_ATTRIBUTE_WORD)
      if isChar("?"):
        kind.add texts[i]
        inc i
      if typeAt(i) != T_ATTRIBUTE_WORD:
        fail(if kind.endsWith("?"): "'ATTRIBUTE_WORD'" else: "'ATTRIBUTE_WORD', '?'")
      var attribute = ParsedAttribute(kind: kind, name: texts[i])
      inc i
      if typeAt(i) == T_ATTRIBUTE_KEY:
        var keys = @[texts[i]]
        inc i
        while isChar(","):
          inc i
          keys.add expect(T_ATTRIBUTE_KEY)
        attribute.hasKeys = true
        attribute.keys = keys
      if typeAt(i) == T_COMMENT:
        attribute.hasComment = true
        attribute.comment = unquote(texts[i])
        inc i
      list.add attribute
      if typeAt(i) == T_BLOCK_STOP: break
    for k in countdown(list.high, 0): result.add list[k]

  # Parses an optional `{ ... }` block; empty when there is none or it is empty.
  proc attributeBlock(): seq[ParsedAttribute] =
    if typeAt(i) != T_BLOCK_START: return @[]
    inc i
    if typeAt(i) == T_BLOCK_STOP:
      inc i
      return @[]
    result = attributes()
    inc i

  proc entityStatement(): seq[string] =
    let a = entityName()
    var t = typeAt(i)
    if t == T_SQS:
      inc i
      let alias = entityName()
      discard expect(T_SQE)
      var classes: seq[string]
      var hasClasses = false
      if typeAt(i) == T_STYLE_SEPARATOR:
        inc i
        classes = idList()
        hasClasses = true
      let attrs = attributeBlock()
      discard db.addEntity(a, alias)
      if attrs.len > 0: db.addAttributes(a, attrs)
      if hasClasses: db.setClass(@[a], classes)
      return @[a]
    var classes: seq[string]
    var hasClasses = false
    if t == T_STYLE_SEPARATOR:
      inc i
      classes = idList()
      hasClasses = true
      t = typeAt(i)
    if cardinality(t) != "":
      let spec = relSpec()
      let b = entityName()
      var classesB: seq[string]
      var hasClassesB = false
      if typeAt(i) == T_STYLE_SEPARATOR:
        inc i
        classesB = idList()
        hasClassesB = true
      discard expect(T_COLON)
      let label = role()
      discard db.addEntity(a)
      discard db.addEntity(b)
      db.addRelationship(a, label, b, spec)
      if hasClasses: db.setClass(@[a], classes)
      if hasClassesB: db.setClass(@[b], classesB)
      return @[a, b]
    let attrs = attributeBlock()
    discard db.addEntity(a)
    if attrs.len > 0: db.addAttributes(a, attrs)
    if hasClasses: db.setClass(@[a], classes)
    @[a]

  discard expect(T_ER_DIAGRAM)
  # Subgraphs nest on this stack rather than on the call stack; the first frame is the diagram itself.
  var frames = @[Frame()]
  var frame = frames[0]
  var nested = false

  while true:
    let t = typeAt(i)
    case t
    of T_NEWLINE:
      inc i
    of T_EOF:
      inc i
      if nested: fail("'END', " & LINE)
      return
    of T_END_KW:
      if not nested: fail(LINE)
      inc i
      let id = db.addSubGraph(frame.id, frame.list, frame.title)
      discard frames.pop()
      frame = frames[^1]
      nested = frames.len > 1
      if nested: frame.list.add docText(id)
    of T_SUBGRAPH:
      inc i
      let id = entityName()
      var title = id
      if typeAt(i) == T_SQS:
        inc i
        title = entityName()
        while isName(typeAt(i)): title.add " " & entityName()
        discard expect(T_SQE)
      separator()
      frame = Frame(id: id, title: title)
      frames.add frame
      nested = true
    of T_acc_title:
      inc i
      let value = expect(T_acc_title_value).jsTrim
      db.setAccTitle(value)
      if nested: frame.list.add docText(value)
    of T_acc_descr:
      inc i
      let value = expect(T_acc_descr_value).jsTrim
      db.setAccDescription(value)
      if nested: frame.list.add docText(value)
    of T_acc_descr_multiline_value:
      let value = texts[i].jsTrim
      inc i
      db.setAccDescription(value)
      if nested: frame.list.add docText(value)
    of T_direction_tb, T_direction_bt, T_direction_rl, T_direction_lr:
      inc i
      let value = DIRECTIONS[t - T_direction_tb]
      if nested: frame.list.add docDir(value)
      else: db.setDirection(value)
    of T_CLASSDEF:
      let keyword = texts[i]
      inc i
      let ids = idList()
      let styles = stylesOpt()
      separator()
      db.addClass(ids, styles)
      if nested: frame.list.add docText(keyword)
    of T_CLASS:
      let keyword = texts[i]
      inc i
      let ids = idList()
      db.setClass(ids, idList())
      if nested: frame.list.add docText(keyword)
    of T_STYLE:
      let keyword = texts[i]
      inc i
      let ids = idList()
      let styles = stylesOpt()
      separator()
      db.addCssStyles(ids, styles)
      if nested: frame.list.add docText(keyword)
    else:
      if not isName(t): fail(if nested: "'END', " & LINE else: LINE)
      let names = entityStatement()
      if nested:
        for name in names: frame.list.add docText(name)

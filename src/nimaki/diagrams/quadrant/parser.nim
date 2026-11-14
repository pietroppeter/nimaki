## port-of: src/diagrams/quadrant/parser.ts
## port-status: conformant
import ../../errors
import ../../js
import db, lexer, tokens

func flags(tokens: varargs[int]): set[0 .. 63] =
  for t in tokens: result.incl t

const
  WORD = flags(T_PUNCTUATION, T_AMP, T_NUM, T_ALPHA, T_COMMA, T_PLUS, T_EQUALS, T_MULT, T_DOT,
               T_BRKT, T_UNDERSCORE, T_UNICODE_TEXT)
  ID = flags(T_ALPHA, T_NUM, T_MINUS, T_COMMA, T_COLON, T_AMP, T_BRKT, T_MULT, T_UNICODE_TEXT)
  STYLE = flags(T_ALPHA, T_NUM, T_COLON, T_SPACE, T_BRKT, T_MINUS)
  EOL = flags(T_NEWLINE, T_SEMI, T_EOF)
  TEXT_TOKENS = "'STR', 'MD_STR', 'ALPHA', 'NUM', 'UNICODE_TEXT', 'PUNCTUATION'"

proc parseQuadrant*(src: string, db: QuadrantDb) =
  let toks = tokenize(src)
  let types = toks.types
  let texts = toks.texts
  let starts = toks.starts
  var i = 0

  proc fail(expected: string) =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("quadrantChart", src, starts[i], "", true)
    raise syntaxError("quadrantChart", src, starts[i], "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")

  proc expect(kind: int): string =
    if types[i] != kind: fail("'" & TOKEN_NAMES[kind] & "'")
    result = texts[i]
    inc i

  proc isText(t: int): bool = t == T_STR or t == T_MD_STR or t in WORD

  proc text(): QuadrantText =
    let first = types[i]
    if not isText(first): fail(TEXT_TOKENS)
    var s = texts[i]
    inc i
    while types[i] in WORD or types[i] == T_SPACE or types[i] == T_MINUS:
      s.add texts[i]
      inc i
    QuadrantText(defined: true, text: s, markdown: first == T_MD_STR)

  proc styles(): seq[string] =
    while true:
      if types[i] notin STYLE: fail("'ALPHA', 'NUM', 'COLON', 'SPACE', 'BRKT', 'MINUS'")
      var s = texts[i]
      inc i
      while types[i] in STYLE:
        s.add texts[i]
        inc i
      result.add jsTrim(s)
      if types[i] != T_COMMA: return
      inc i

  while types[i] in EOL or types[i] == T_SPACE: inc i
  discard expect(T_QUADRANT)

  while types[i] != T_END:
    while types[i] == T_SPACE: inc i
    let t = types[i]
    case t
    of T_CLASSDEF:
      inc i
      discard expect(T_SPACE)
      if types[i] notin ID: fail("'ALPHA', 'NUM', 'UNICODE_TEXT'")
      var id = texts[i]
      inc i
      while types[i] in ID:
        id.add texts[i]
        inc i
      discard expect(T_SPACE)
      db.addClass(id, styles())
    of T_X_AXIS, T_Y_AXIS:
      inc i
      var source = text()
      var target: QuadrantText
      if types[i] == T_DELIMITER:
        inc i
        if isText(types[i]): target = text()
        else: source.text.add " ⟶ "
      if t == T_X_AXIS:
        db.setXAxisLeftText(source)
        if target.defined: db.setXAxisRightText(target)
      else:
        db.setYAxisBottomText(source)
        if target.defined: db.setYAxisTopText(target)
    of T_QUADRANT_1, T_QUADRANT_2, T_QUADRANT_3, T_QUADRANT_4:
      inc i
      db.setQuadrantText(t - T_QUADRANT_1, text())
    of T_title:
      inc i
      db.setDiagramTitle(jsTrim(expect(T_title_value)))
    of T_acc_title:
      inc i
      db.setAccTitle(jsTrim(expect(T_acc_title_value)))
    of T_acc_descr:
      inc i
      db.setAccDescription(jsTrim(expect(T_acc_descr_value)))
    of T_acc_descr_multiline_value:
      db.setAccDescription(jsTrim(texts[i]))
      inc i
    else:
      if isText(t):
        let label = text()
        var className = ""
        if types[i] == T_class_name:
          className = texts[i]
          inc i
        discard expect(T_point_start)
        let x = expect(T_point_x)
        let y = expect(T_point_y)
        db.addPoint(label, className, x, y, (if types[i] in STYLE: styles() else: @[]))
    if types[i] notin EOL: fail("'NEWLINE', 'SEMI', 'EOF'")
    inc i

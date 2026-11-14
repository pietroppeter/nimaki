## port-of: src/diagrams/venn/parser.ts
## port-status: conformant
import std/strutils
import ../../errors
import ../../js
import db, lexer

const
  STATEMENT = "'EOF', 'NEWLINE', 'TITLE', 'SET', 'UNION', 'TEXT', 'INDENT_TEXT', 'STYLE'"
  VALUE = "'NUMERIC', 'IDENTIFIER', 'STRING', 'HEXCOLOR', 'RGBCOLOR', 'RGBACOLOR'"

proc parseVenn*(src: string, db: VennDb) =
  ## Ports Mermaid's venn grammar. A token is read only when the grammar has to look at one to
  ## decide, because the lexer asks the model whether an indented `text` continues a set, and the
  ## statements are what tell the model so.
  let lexer = newVennLexer(src, IndentHost(
    getIndentMode: proc (): bool = db.getIndentMode(),
    setIndentMode: proc (enabled: bool) = db.setIndentMode(enabled)))
  var kind = -1

  proc peek(): int =
    if kind == -1: kind = lexer.next()
    kind

  proc fail(expected: string) =
    if peek() == T_ERROR: raise syntaxError("venn", src, lexer.start, "", true)
    raise syntaxError("venn", src, lexer.start, "Expecting " & expected & ", got '" & TOKEN_NAMES[kind] & "'")

  proc take(): string =
    kind = -1
    lexer.text

  proc expect(wanted: int): string =
    if peek() != wanted: fail("'" & TOKEN_NAMES[wanted] & "'")
    take()

  proc identifier(): string =
    if peek() != T_IDENTIFIER and kind != T_STRING: fail("'IDENTIFIER', 'STRING'")
    take()

  proc identifiers(): seq[string] =
    result = @[identifier()]
    while peek() == T_COMMA:
      discard take()
      result.add identifier()

  proc subset(ids: seq[string], union: bool) =
    var label = ""
    var hasLabel = false
    if peek() == T_BRACKET_LABEL:
      label = take()
      hasLabel = true
    var size = 0.0
    var hasSize = false
    if peek() == T_COLON:
      discard take()
      size = jsParseFloat(expect(T_NUMERIC))
      hasSize = true
    if union:
      if ids.len < 2: raise newPeleError("union requires multiple identifiers", "semantic", "venn")
      db.validateUnionIdentifiers(ids)
    db.addSubsetData(ids, label, hasLabel, size, hasSize)
    db.setIndentMode(true)

  # The id of a text, and the label in brackets that an id which is not a number may carry.
  proc text(sets: proc (): seq[string]) =
    let k = peek()
    if k != T_IDENTIFIER and k != T_STRING and k != T_NUMERIC: fail("'NUMERIC', 'IDENTIFIER', 'STRING'")
    let id = take()
    var label = ""
    var hasLabel = false
    if k != T_NUMERIC and peek() == T_BRACKET_LABEL:
      label = take()
      hasLabel = true
    db.addTextData(sets(), id, label, hasLabel)

  proc style() =
    let ids = identifiers()
    var styles: seq[(string, string)]
    while true:
      let key = expect(T_IDENTIFIER)
      discard expect(T_COLON)
      var value: string
      if peek() == T_STRING: value = take()
      else:
        var parts: seq[string]
        while peek() == T_IDENTIFIER or (kind >= T_NUMERIC and kind <= T_RGBACOLOR): parts.add take()
        if parts.len == 0: fail(VALUE)
        value = parts.join(" ")
      styles.add (key, value)
      if peek() != T_COMMA: break
      discard take()
    db.addStyleData(ids, styles)

  while peek() == T_NEWLINE: discard take()
  discard expect(T_VENN)
  while true:
    let statement = peek()
    if statement == T_EOF: return
    if statement < T_NEWLINE or statement > T_STYLE or statement == T_VENN: fail(STATEMENT)
    discard take()
    if statement == T_TITLE:
      # lexer.text.slice(6): the word, and the one character after it
      let t = lexer.text
      db.setDiagramTitle(t[min(5 + charLen(t, 5), t.len) .. ^1])
    elif statement == T_SET: subset(@[identifier()], false)
    elif statement == T_UNION: subset(identifiers(), true)
    elif statement == T_TEXT:
      let ids = identifiers()
      text(proc (): seq[string] = ids)
    elif statement == T_INDENT_TEXT:
      text(proc (): seq[string] =
        let (has, current) = db.getCurrentSets()
        if not has: raise newPeleError("text requires set", "semantic", "venn")
        current)
    elif statement == T_STYLE: style()

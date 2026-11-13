## port-of: src/diagrams/ishikawa/parser.ts
## port-status: draft
import ../../errors
import ../../js
import db, lexer

const STOP = "'SPACELINE', 'NL', 'EOF'"

proc parseIshikawa*(src: string, db: IshikawaDb) =
  ## Follows the parser Jison builds from Mermaid's grammar: blank lines and comments may come first,
  ## then the keyword and at most one line break, then statements. A statement is a line of text,
  ## with or without indentation, or a blank line; each is ended by a blank line, a line break or
  ## the end of the text, and any number of line breaks after that.
  let tokens = tokenize(src)
  let types = tokens.types
  let starts = tokens.starts
  let ends = tokens.ends
  var i = 0

  proc fail(expected: string) {.noreturn.} =
    raise syntaxError("ishikawa", src, starts[i], "Expecting " & expected & ", got '" & TOKEN_NAMES[types[i]] & "'")

  if types[i] == T_SPACELINE:
    inc i
    while types[i] == T_SPACELINE or types[i] == T_NL: inc i
    if types[i] != T_ISHIKAWA: fail("'SPACELINE', 'NL', 'ISHIKAWA'")
  elif types[i] != T_ISHIKAWA: fail("'SPACELINE', 'ISHIKAWA'")
  inc i
  if types[i] == T_NL: inc i

  while true:
    let kind = types[i]
    if kind == T_TEXT or (kind == T_SPACELIST and types[i + 1] == T_TEXT):
      let text = if kind == T_TEXT: i else: i + 1
      i = text + 1
      if types[i] != T_SPACELINE and types[i] != T_NL and types[i] != T_EOF: fail(STOP)
      db.addNode(if kind == T_TEXT: 0 else: utf16Len(src, starts[text - 1], ends[text - 1]),
                 jsTrim(src[starts[text] ..< ends[text]]))
    elif kind == T_SPACELINE or kind == T_SPACELIST:
      inc i
      if types[i] != T_SPACELINE and types[i] != T_NL and types[i] != T_EOF:
        fail(if kind == T_SPACELIST: STOP & ", 'TEXT'" else: STOP)
    else: fail("'SPACELINE', 'SPACELIST', 'TEXT'")
    inc i
    while types[i] == T_NL or types[i] == T_EOF: inc i
    if types[i] == T_STOP: return

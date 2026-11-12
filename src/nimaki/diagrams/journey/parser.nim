## port-of: src/diagrams/journey/parser.ts
## port-status: draft
import ../../errors
import ../../js
import db, lexer

const STATEMENT =
  "'EOF', 'SPACE', 'NEWLINE', 'title', 'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'section', 'taskName'"

proc parseJourney*(src: string, db: JourneyDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts

  proc fail(i: int, expected: string) =
    let got = if types[i] == T_END: "1" else: TOKEN_NAMES[types[i]]
    raise syntaxError("journey", src, starts[i], "Expecting " & expected & ", got '" & got & "'")

  if types[0] != T_journey: fail(0, "'journey'")

  var i = 1
  while true:
    let text = texts[i]
    case types[i]
    of T_NEWLINE: discard
    of T_title: db.setDiagramTitle(substringFrom(text, 6))
    of T_acc_title:
      inc i
      db.setAccTitle(jsTrim(texts[i]))
    of T_acc_descr:
      inc i
      db.setAccDescription(jsTrim(texts[i]))
    of T_acc_descr_multiline_value: db.setAccDescription(jsTrim(text))
    of T_section: db.addSection(substringFrom(text, 8))
    of T_taskName:
      inc i
      if types[i] != T_taskData: fail(i, "'taskData'")
      db.addTask(text, texts[i])
    of T_EOF: return
    else: fail(i, STATEMENT)
    inc i

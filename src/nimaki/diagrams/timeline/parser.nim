## port-of: src/diagrams/timeline/parser.ts
## port-status: conformant
import ../../errors
import ../../js
import ../common/scan
import db, lexer

const STATEMENT =
  "'EOF', 'SPACE', 'NEWLINE', 'title', 'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'section', 'period', 'event'"

proc parseTimeline*(src: string, db: TimelineDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts

  proc fail(i: int, expected: string) =
    let got = if types[i] == T_END: "1" else: TOKEN_NAMES[types[i]]
    raise syntaxError("timeline", src, starts[i], "Expecting " & expected & ", got '" & got & "'")

  let head = types[0]
  if head != T_timeline and head != T_timeline_lr and head != T_timeline_td:
    fail(0, "'timeline', 'timeline_lr', 'timeline_td'")
  if head != T_timeline: db.setDirection(if head == T_timeline_lr: "LR" else: "TD")

  var i = 1
  while true:
    let text = texts[i]
    case types[i]
    of T_NEWLINE: discard
    of T_title: db.getCommonDb().setDiagramTitle(substringFrom(text, 6))
    of T_acc_title:
      inc i
      db.getCommonDb().setAccTitle(jsTrim(texts[i]))
    of T_acc_descr:
      inc i
      db.getCommonDb().setAccDescription(jsTrim(texts[i]))
    of T_acc_descr_multiline_value: db.getCommonDb().setAccDescription(jsTrim(text))
    of T_section: db.addSection(substringFrom(text, 8))
    of T_period: db.addTask(text, 0, "")
    of T_event: db.addEvent(substringFrom(text, 2))
    of T_EOF: return
    else: fail(i, STATEMENT)
    inc i

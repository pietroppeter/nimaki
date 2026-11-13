## port-of: src/diagrams/gantt/parser.ts
## port-status: draft
##
## Port notes: Pele's parser calls a `GanttBuilder`; here it calls the database directly.
import ../../errors
import ../../js
import db, lexer, tokens

const WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

const LINE =
  "'EOF', 'SPACE', 'NL', 'weekday_monday', 'weekday_tuesday', 'weekday_wednesday', 'weekday_thursday', " &
  "'weekday_friday', 'weekday_saturday', 'weekday_sunday', 'weekend_friday', 'weekend_saturday', 'dateFormat', " &
  "'inclusiveEndDates', 'topAxis', 'axisFormat', 'tickInterval', 'excludes', 'includes', 'todayMarker', 'title', " &
  "'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'section', 'taskTxt', 'click'"

func startsLine(t: int): bool =
  ## Tokens that can start a line, which are also the only ones that can follow a complete statement.
  (t >= T_weekday_monday and t <= T_weekend_saturday) or
    t in [T_EOF, T_NL, T_dateFormat, T_inclusiveEndDates, T_topAxis, T_axisFormat, T_tickInterval,
          T_excludes, T_includes, T_todayMarker, T_title, T_acc_title, T_acc_descr,
          T_acc_descr_multiline_value, T_section, T_taskTxt, T_click]

proc parseGantt*(src: string, db: GanttDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  var i = 0

  proc fail(expected: string) {.noreturn.} =
    let t = types[i]
    raise syntaxError("gantt", src, starts[i],
      "Expecting " & expected & ", got '" & (if t == T_END: "1" else: TOKEN_NAMES[t]) & "'")

  proc stop(also = "") =
    ## Mermaid's parser runs a statement's action only after seeing that the next token can follow it.
    if not startsLine(types[i]): fail(LINE & also)

  if types[i] != T_gantt: fail("'gantt'")
  inc i

  while true:
    let t = types[i]
    let text = texts[i]
    if not startsLine(t): fail(LINE)
    inc i
    case t
    of T_EOF:
      if types[i] == T_END: return
      stop()
    of T_NL: discard
    of T_dateFormat:
      stop()
      db.setDateFormat(substringFrom(text, 11))
    of T_inclusiveEndDates:
      stop()
      db.enableInclusiveEndDates()
    of T_topAxis:
      stop()
      db.enableTopAxis()
    of T_axisFormat:
      stop()
      db.setAxisFormat(substringFrom(text, 11))
    of T_tickInterval:
      stop()
      db.setTickInterval(substringFrom(text, 13))
    of T_excludes:
      stop()
      db.setExcludes(substringFrom(text, 9))
    of T_includes:
      stop()
      db.setIncludes(substringFrom(text, 9))
    of T_todayMarker:
      stop()
      db.setTodayMarker(substringFrom(text, 12))
    of T_weekend_friday:
      stop()
      db.setWeekend("friday")
    of T_weekend_saturday:
      stop()
      db.setWeekend("saturday")
    of T_title:
      stop()
      db.setDiagramTitle(substringFrom(text, 6))
    of T_acc_title:
      if types[i] != T_acc_title_value: fail("'acc_title_value'")
      let value = texts[i]
      inc i
      stop()
      db.setAccTitle(jsTrim(value))
    of T_acc_descr:
      if types[i] != T_acc_descr_value: fail("'acc_descr_value'")
      let value = texts[i]
      inc i
      stop()
      db.setAccDescription(jsTrim(value))
    of T_acc_descr_multiline_value:
      stop()
      db.setAccDescription(jsTrim(text))
    of T_section:
      stop()
      db.addSection(substringFrom(text, 8))
    of T_taskTxt:
      if types[i] != T_taskData: fail("'taskData'")
      let data = texts[i]
      inc i
      stop()
      db.addTask(text, data)
    of T_click:
      var hasName, hasHref = false
      var href = ""
      if types[i] == T_callbackname:
        hasName = true
        inc i
        var hasArgs = false
        if types[i] == T_callbackargs:
          hasArgs = true
          inc i
        if types[i] == T_href:
          href = texts[i]
          hasHref = true
          inc i
          stop()
        else:
          stop(if not hasArgs: ", 'callbackargs', 'href'" else: ", 'href'")
      elif types[i] == T_href:
        href = texts[i]
        hasHref = true
        inc i
        if types[i] == T_callbackname:
          hasName = true
          inc i
          if types[i] == T_callbackargs:
            inc i
            stop()
          else:
            stop(", 'callbackargs'")
        else:
          stop(", 'callbackname'")
      else:
        fail("'callbackname', 'href'")
      if hasName: db.setClickEvent(text)
      if hasHref: db.setLink(text, href)
    else:
      stop()
      db.setWeekday(WEEKDAYS[t - T_weekday_monday])

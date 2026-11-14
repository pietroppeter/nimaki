## port-of: src/diagrams/gantt/lexer.ts
## port-status: draft
##
import std/strutils
import ../../js
import tokens
import ../../jsregex

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

const
  S_INITIAL = 0
  S_acc_title = 1
  S_acc_descr = 2
  S_acc_descr_multiline = 3
  S_href = 4
  S_callbackname = 5
  S_callbackargs = 6
  S_click = 7

func spaces(s: string, i: int): int =
  ## \s* from i
  result = i
  while result < s.len:
    let n = spaceLenAt(s, result)
    if n == 0: break
    result += n

const RE_ACC_TITLE = jsre"/accTitle\s*:\s*/iy"
const RE_ACC_DESCR = jsre"/accDescr\s*:\s*/iy"
const RE_ACC_DESCR_ML = jsre"/accDescr\s*\{\s*/iy"
const RE_HREF = jsre"""/href\s+"/iy"""
const RE_CALL = jsre"/call\s+/iy"
const RE_CLICK = jsre"/click\s+/iy"
const RE_EMPTY_CALL = jsre"/\(\s*\)/y"
const RE_WEEKDAY = jsre"/weekday\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/iy"
const DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
const RE_WEEKEND = jsre"/weekend\s+(?:(friday)|saturday)\b/iy"
const RE_DATE = jsre"/\d\d\d\d-\d\d-\d\d\b/y"
const RE_BARE_TITLE = jsre"/title[^\S\r\n]*(?=[\r\n]|$)/iy"

# Statements that start with a keyword, grouped by the keyword's first letter and kept in the grammar's rule order.
const
  KEYWORDS_A = [(jsre"/axisFormat\s[^#\n;]+/iy", T_axisFormat), (jsre"/accDescription\s[^#\n;]+/iy", T_accDescription)]
  KEYWORDS_G = [(jsre"/gantt\b/iy", T_gantt)]
  KEYWORDS_D = [(jsre"/dateFormat\s[^#\n;]+/iy", T_dateFormat)]
  KEYWORDS_I = [(jsre"/inclusiveEndDates\b/iy", T_inclusiveEndDates), (jsre"/includes\s[^#\n;]+/iy", T_includes)]
  KEYWORDS_T = [
    (jsre"/topAxis\b/iy", T_topAxis),
    (jsre"/tickInterval\s[^#\n;]+/iy", T_tickInterval),
    (jsre"/todayMarker\s[^\n;]+/iy", T_todayMarker),
    (jsre"/title[^\S\r\n][^\n]+/iy", T_title),
  ]
  KEYWORDS_E = [(jsre"/excludes\s[^#\n;]+/iy", T_excludes)]
  KEYWORDS_S = [(jsre"/section\s[^\n]+/iy", T_section)]

func keywords(c: char): seq[(JsRegExp, int)] =
  case c
  of 'a': @KEYWORDS_A
  of 'g': @KEYWORDS_G
  of 'd': @KEYWORDS_D
  of 'i': @KEYWORDS_I
  of 't': @KEYWORDS_T
  of 'e': @KEYWORDS_E
  of 's': @KEYWORDS_S
  else: @[]

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var state = S_INITIAL
  var p = 0

  proc emit(kind, s, e: int) =
    types.add kind
    texts.add src[s ..< e]
    starts.add s
    p = e

  proc until(ch: char, start: int): int =
    let e = src.find(ch, start)
    if e == -1: n else: e

  proc at(re: JsRegExp): int = re.matchEnd(src, p)

  proc keyword(c: char): bool =
    var e: int
    case toLowerAscii(c)
    of 'a':
      if (e = at(RE_ACC_TITLE); e >= 0):
        state = S_acc_title
        emit(T_acc_title, p, e)
        return true
      if (e = at(RE_ACC_DESCR); e >= 0):
        state = S_acc_descr
        emit(T_acc_descr, p, e)
        return true
      if (e = at(RE_ACC_DESCR_ML); e >= 0):
        state = S_acc_descr_multiline
        p = e
        return true
    of 'h':
      if (e = at(RE_HREF); e >= 0):
        state = S_href
        p = e
        return true
    of 'c':
      if (e = at(RE_CALL); e >= 0):
        state = S_callbackname
        p = e
        return true
      if (e = at(RE_CLICK); e >= 0):
        state = S_click
        p = e
        return true
    of 't':
      if (e = at(RE_BARE_TITLE); e >= 0):
        p = e
        return true
    of 'w':
      var m = RE_WEEKDAY.exec(src, p)
      if m.found:
        emit(T_weekday_monday + DAYS.find(m[1].toLowerAscii), p, m.stop)
        return true
      m = RE_WEEKEND.exec(src, p)
      if m.found:
        emit(if m.has(1): T_weekend_friday else: T_weekend_saturday, p, m.stop)
        return true
    else: discard
    for (re, kind) in keywords(toLowerAscii(c)):
      if (e = at(re); e >= 0):
        emit(kind, p, e)
        return true
    false

  while true:
    if p >= n:
      let kind = case state
        of S_acc_title: T_acc_title_value
        of S_acc_descr: T_acc_descr_value
        of S_acc_descr_multiline: T_acc_descr_multiline_value
        of S_href: T_href
        of S_callbackname: T_callbackname
        of S_callbackargs: T_callbackargs
        of S_click: T_click
        else: T_EOF
      emit(kind, n, n)
      break
    let c = src[p]
    case state
    of S_INITIAL:
      let d = if p + 1 < n: src[p + 1] else: '\0'
      if c == '%':
        if d != '%':
          var e = until('\n', p + 1)
          while e < n and src[e] == '\n': inc e
          p = e
        elif p + 2 < n and src[p + 2] == '{':
          # The grammar enters a lexer state it never defines, so nothing can follow.
          emit(T_open_directive, p, p + 3)
          emit(T_ERROR, p, p)
          return Tokens(types: types, texts: texts, starts: starts)
        else:
          p = until('\n', p + 2)
      elif c == '\n':
        var e = p + 1
        while e < n and src[e] == '\n': inc e
        emit(T_NL, p, e)
      elif spaceLenAt(src, p) > 0:
        p = spaces(src, p)
      elif keyword(c):
        discard
      elif c in {'0'..'9'} and at(RE_DATE) >= 0:
        emit(T_date, p, p + 10)
      elif c != ':':
        var e = p + 1
        while e < n and src[e] != ':' and src[e] != '\n': inc e
        emit(T_taskTxt, p, e)
      else:
        var e = p + 1
        while e < n and src[e] notin {'#', '\n', ';'}: inc e
        emit(if e > p + 1: T_taskData else: T_COLON, p, e)
    of S_acc_title, S_acc_descr:
      let kind = if state == S_acc_title: T_acc_title_value else: T_acc_descr_value
      state = S_INITIAL
      emit(kind, p, until('\n', p))
    of S_acc_descr_multiline:
      if c == '}':
        state = S_INITIAL
        inc p
      else:
        emit(T_acc_descr_multiline_value, p, until('}', p))
    of S_href:
      if c == '"':
        state = S_INITIAL
        inc p
      else:
        emit(T_href, p, until('"', p))
    of S_callbackname:
      if c == '(':
        let e = at(RE_EMPTY_CALL)
        if e >= 0:
          state = S_INITIAL
          p = e
        else:
          state = S_callbackargs
          inc p
      else:
        emit(T_callbackname, p, until('(', p))
    of S_callbackargs:
      if c == ')':
        state = S_INITIAL
        inc p
      else:
        emit(T_callbackargs, p, until(')', p))
    else:
      let w = spaceLenAt(src, p)
      if w > 0:
        state = S_INITIAL
        p += w
      else:
        var e = p + codePointAt(src, p).size
        while e < n and spaceLenAt(src, e) == 0: e += codePointAt(src, e).size
        emit(T_click, p, e)
  types.add T_END
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)

## port-of: src/diagrams/gantt/lexer.ts
## port-status: draft
##
## Port notes: each sticky regular expression is a matcher with its pattern in a comment. They
## match without regard to ASCII case, as the `i` flag does without `u`.
import std/strutils
import ../../js
import tokens

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

func word(s: string, i: int, w: string): bool =
  ## w at i, ASCII case ignored
  if i + w.len > s.len: return false
  for k in 0 ..< w.len:
    if toLowerAscii(s[i + k]) != toLowerAscii(w[k]): return false
  true

func spaces(s: string, i: int): int =
  ## \s* from i
  result = i
  while result < s.len:
    let n = spaceLenAt(s, result)
    if n == 0: break
    result += n

func isWordAt(s: string, i: int): bool = i < s.len and isWordChar(s[i])

func boundary(s: string, i: int): bool =
  ## \b at i
  isWordAt(s, i - 1) != isWordAt(s, i)

func spacedTo(s: string, p: int, w: string, c: char): int =
  ## /w\s*c\s*/iy
  if not word(s, p, w): return -1
  let i = spaces(s, p + w.len)
  if i < s.len and s[i] == c: spaces(s, i + 1) else: -1

func spacedPlus(s: string, p: int, w: string): int =
  ## /w\s+/iy: where the blanks end, or -1
  if not word(s, p, w): return -1
  let i = spaces(s, p + w.len)
  if i > p + w.len: i else: -1

func restOf(s: string, i: int, stops: set[char]): int =
  ## [^stops]+ from i: where it ends, or -1
  var j = i
  while j < s.len and s[j] notin stops: inc j
  if j > i: j else: -1

func keywordLine(s: string, p: int, w: string, stops: set[char]): int =
  ## /w\s[^stops]+/iy
  if not word(s, p, w): return -1
  let n = spaceLenAt(s, p + w.len)
  if n == 0: return -1
  restOf(s, p + w.len + n, stops)

func keywordWord(s: string, p: int, w: string): int =
  ## /w\b/iy
  if word(s, p, w) and boundary(s, p + w.len): p + w.len else: -1

func isDigit(s: string, i: int): bool = i < s.len and s[i] in {'0'..'9'}

func matchDate(s: string, p: int): int =
  ## /\d\d\d\d-\d\d-\d\d\b/y
  for k in [0, 1, 2, 3, 5, 6, 8, 9]:
    if not isDigit(s, p + k): return -1
  if s[p + 4] != '-' or s[p + 7] != '-': return -1
  if boundary(s, p + 10): p + 10 else: -1

func isBlankNotBreak(s: string, i: int): int =
  ## [^\S\r\n] at i: its length, or 0
  if i < s.len and s[i] in {'\r', '\n'}: 0 else: spaceLenAt(s, i)

func bareTitle(s: string, p: int): int =
  ## /title[^\S\r\n]*(?=[\r\n]|$)/iy
  if not word(s, p, "title"): return -1
  var i = p + 5
  while true:
    let n = isBlankNotBreak(s, i)
    if n == 0: break
    i += n
  if i >= s.len or s[i] in {'\r', '\n'}: i else: -1

func titleLine(s: string, p: int): int =
  ## /title[^\S\r\n][^\n]+/iy
  if not word(s, p, "title"): return -1
  let n = isBlankNotBreak(s, p + 5)
  if n == 0: return -1
  restOf(s, p + 5 + n, {'\n'})

const DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

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

  proc keyword(c: char): bool =
    var e: int
    case toLowerAscii(c)
    of 'a':
      e = spacedTo(src, p, "accTitle", ':')
      if e >= 0:
        state = S_acc_title
        emit(T_acc_title, p, e)
        return true
      e = spacedTo(src, p, "accDescr", ':')
      if e >= 0:
        state = S_acc_descr
        emit(T_acc_descr, p, e)
        return true
      e = spacedTo(src, p, "accDescr", '{')
      if e >= 0:
        state = S_acc_descr_multiline
        p = e
        return true
    of 'h':
      # /href\s+"/iy
      e = spacedPlus(src, p, "href")
      if e >= 0 and e < n and src[e] == '"':
        state = S_href
        p = e + 1
        return true
    of 'c':
      e = spacedPlus(src, p, "call")
      if e >= 0:
        state = S_callbackname
        p = e
        return true
      e = spacedPlus(src, p, "click")
      if e >= 0:
        state = S_click
        p = e
        return true
    of 't':
      e = bareTitle(src, p)
      if e >= 0:
        p = e
        return true
    of 'w':
      # /weekday\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/iy
      e = spacedPlus(src, p, "weekday")
      if e >= 0:
        for k, day in DAYS:
          if word(src, e, day) and boundary(src, e + day.len):
            emit(T_weekday_monday + k, p, e + day.len)
            return true
      # /weekend\s+(?:(friday)|saturday)\b/iy
      e = spacedPlus(src, p, "weekend")
      if e >= 0:
        if word(src, e, "friday") and boundary(src, e + 6):
          emit(T_weekend_friday, p, e + 6)
          return true
        if word(src, e, "saturday") and boundary(src, e + 8):
          emit(T_weekend_saturday, p, e + 8)
          return true
    else: discard
    # Statements that start with a keyword, grouped by the keyword's first letter and kept in the grammar's rule order.
    template rule(found: int, kind: int) =
      e = found
      if e >= 0:
        emit(kind, p, e)
        return true
    case toLowerAscii(c)
    of 'a':
      rule(keywordLine(src, p, "axisFormat", {'#', '\n', ';'}), T_axisFormat)
      rule(keywordLine(src, p, "accDescription", {'#', '\n', ';'}), T_accDescription)
    of 'g':
      rule(keywordWord(src, p, "gantt"), T_gantt)
    of 'd':
      rule(keywordLine(src, p, "dateFormat", {'#', '\n', ';'}), T_dateFormat)
    of 'i':
      rule(keywordWord(src, p, "inclusiveEndDates"), T_inclusiveEndDates)
      rule(keywordLine(src, p, "includes", {'#', '\n', ';'}), T_includes)
    of 't':
      rule(keywordWord(src, p, "topAxis"), T_topAxis)
      rule(keywordLine(src, p, "tickInterval", {'#', '\n', ';'}), T_tickInterval)
      rule(keywordLine(src, p, "todayMarker", {'\n', ';'}), T_todayMarker)
      rule(titleLine(src, p), T_title)
    of 'e':
      rule(keywordLine(src, p, "excludes", {'#', '\n', ';'}), T_excludes)
    of 's':
      rule(keywordLine(src, p, "section", {'\n'}), T_section)
    else: discard
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
      elif c in {'0'..'9'} and matchDate(src, p) >= 0:
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
        # /\(\s*\)/y
        let e = spaces(src, p + 1)
        if e < n and src[e] == ')':
          state = S_INITIAL
          p = e + 1
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

## port-of: src/diagrams/xychart/lexer.ts
## port-status: conformant
##
## Positions are byte offsets. `charCodeAt` becomes `cu`, which reads the character at a byte
## offset (-1 past the end, as NaN is nothing; the high surrogate for a character past U+FFFF);
## a step over a whitespace character takes its bytes.
import std/strutils
import ../../js
import ../../util/chars
import ../common/caseless
import tokens

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

const
  # const enum S
  S_INITIAL = 0
  S_axis_data = 1
  S_axis_band_data = 2
  S_data = 3
  S_data_inner = 4
  S_string = 5
  S_acc_title = 6
  S_acc_descr = 7
  S_acc_descr_multiline = 8

  # The token each state gives for the empty rest of the input.
  AT_END = [T_EOF, T_EOF, T_EOF, T_EOF, T_EOF, T_STR, T_acc_title_value, T_acc_descr_value,
            T_acc_descr_multiline_value]

# Mermaid's grammar means to open a markdown string at `"` followed by a backtick, but its quoting
# turns the rule into one that matches this text and leaves the current state. Markdown strings
# are never read.
const BROKEN_RULE = "`)" & repeat(' ', 36) & "{ this.pushstate(md_string); }\n<md_string>(?:(?!`\").)+" &
                    repeat(' ', 18) & "{ return md_str; }\n<md_string>(?:`"

func single(c: int): int =
  case c
  of ord(':'): T_COLON
  of ord('+'): T_PLUS
  of ord(','): T_COMMA
  of ord('='): T_EQUALS
  of ord('*'): T_MULT
  of ord('#'): T_BRKT
  of ord('_'): T_UNDERSCORE
  of ord('.'): T_DOT
  of ord('&'): T_AMP
  of ord('-'): T_MINUS
  of ord(';'): T_SEMI
  else: 0

func cu(src: string, i: int): int =
  if i < 0 or i >= src.len: return -1
  let b = ord(src[i])
  if b < 0x80: return b
  let (cp, _) = codePointAt(src, i)
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func charLen(src: string, i: int): int =
  if i >= src.len: 1 elif ord(src[i]) < 0x80: 1 else: codePointAt(src, i)[1]

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0

  template emit(kind, s, e: int) =
    let s0 = s
    let e0 = e
    types.add kind
    texts.add src[s0 ..< e0]
    starts.add s0
    p = e0
  template push(s: int) =
    stack.add state
    state = s
  template pop() =
    if stack.len > 0: state = stack.pop()
  proc lineEnd(q: int): int =
    let e = src.find('\n', q)
    if e == -1: n else: e
  proc run(q: int): int =
    var q = q
    while q < n and isSpace(cu(src, q)): q += charLen(src, q)
    q
  proc digits(q: int): int =
    var q = q
    while isDigit(cu(src, q)): inc q
    q
  proc keyword(at: int, word: string): bool =
    wordAt(src, at, word) and not isWord(cu(src, at + word.len))

  while p < n:
    let c = cu(src, p)

    if state == S_string:
      if c == 34:
        inc p
        pop()
      else:
        let e = src.find('"', p)
        emit(T_STR, p, (if e == -1: n else: e))
      continue
    if state == S_acc_title or state == S_acc_descr:
      emit(AT_END[state], p, lineEnd(p))
      pop()
      continue
    if state == S_acc_descr_multiline:
      if c == 125:
        inc p
        pop()
      else:
        let e = src.find('}', p)
        emit(T_acc_descr_multiline_value, p, (if e == -1: n else: e))
      continue

    let next = cu(src, p + 1)
    if c == 37 and next == 37:
      p = lineEnd(p + 2)
      continue
    if c == 10 or c == 13:
      # Only a line break that directly follows an axis or a series ends it; one after spaces is
      # skipped with them, and the state carries on to the next line.
      if (state == S_axis_data or state == S_data) and (c == 10 or next == 10):
        emit(T_NEWLINE, p, (if c == 10: p + 1 else: p + 2))
        pop()
        continue
      var e = p + 1
      while cu(src, e) == 10 or cu(src, e) == 13: inc e
      emit(T_NEWLINE, p, e)
      continue

    var matched = false
    case c or 32
    of 116:
      if keyword(p, "title"):
        emit(T_title, p, p + 5)
        matched = true
    of 97:
      if wordAt(src, p, "acc"):
        let descr = wordAt(src, p + 3, "descr")
        if descr or wordAt(src, p + 3, "title"):
          let k = run(p + 8)
          let d = cu(src, k)
          if d == 58:
            emit((if descr: T_acc_descr else: T_acc_title), p, run(k + 1))
            push(if descr: S_acc_descr else: S_acc_title)
            matched = true
          elif d == 123 and descr:
            p = run(k + 1)
            push(S_acc_descr_multiline)
            matched = true
    of 120:
      if keyword(p, "xychart-beta"):
        emit(T_XYCHART, p, p + 12)
        matched = true
      elif keyword(p, "xychart"):
        emit(T_XYCHART, p, p + 7)
        matched = true
      elif keyword(p, "x-axis"):
        emit(T_X_AXIS, p, p + 6)
        push(S_axis_data)
        matched = true
    of 121:
      if keyword(p, "y-axis"):
        emit(T_Y_AXIS, p, p + 6)
        push(S_axis_data)
        matched = true
    of 118:
      if wordAt(src, p, "vertical"):
        emit(T_CHART_ORIENTATION, p, p + 8)
        matched = true
    of 104:
      if wordAt(src, p, "horizontal"):
        emit(T_CHART_ORIENTATION, p, p + 10)
        matched = true
    of 108:
      if keyword(p, "line"):
        emit(T_LINE, p, p + 4)
        push(S_data)
        matched = true
    of 98:
      if keyword(p, "bar"):
        emit(T_BAR, p, p + 3)
        push(S_data)
        matched = true
    else: discard
    if matched: continue

    if c == 91:
      if state == S_axis_data: push(S_axis_band_data)
      elif state == S_data: push(S_data_inner)
      emit(T_SQUARE_BRACES_START, p, p + 1)
      continue
    if c == 93:
      if state == S_data_inner or state == S_axis_band_data: pop()
      emit(T_SQUARE_BRACES_END, p, p + 1)
      continue
    if state == S_axis_data and c == 45 and next == 45 and cu(src, p + 2) == 62:
      emit(T_ARROW_DELIMITER, p, p + 3)
      continue
    if state == S_axis_data or state == S_data_inner:
      let q = if c == 43 or c == 45: p + 1 else: p
      let d = cu(src, q)
      var e = -1
      if isDigit(d):
        e = digits(q + 1)
        if cu(src, e) == 46 and isDigit(cu(src, e + 1)): e = digits(e + 2)
      elif d == 46 and isDigit(cu(src, q + 1)):
        e = digits(q + 2)
      if e != -1:
        emit(T_NUMBER_WITH_DECIMAL, p, e)
        continue
    if c == 96 and wordAt(src, p, BROKEN_RULE):
      p += BROKEN_RULE.len
      pop()
      continue
    if c == 34:
      inc p
      push(S_string)
      continue
    if isLetter(c):
      var e = p + 1
      while isLetter(cu(src, e)): inc e
      emit(T_ALPHA, p, e)
      continue
    if isDigit(c):
      emit(T_NUM, p, digits(p + 1))
      continue
    if isSpace(c):
      p = run(p + charLen(src, p))
      continue
    if c < 128 and single(c) != 0:
      emit(single(c), p, p + 1)
      continue
    break

  if p < n:
    types.add T_ERROR
    texts.add ""
    starts.add p
    return Tokens(types: types, texts: texts, starts: starts)
  # Jison tries the rules of the current state once more against the empty rest of the input.
  types.add AT_END[state]
  texts.add ""
  starts.add n
  types.add T_END
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)

## port-of: src/diagrams/quadrant/lexer.ts
## port-status: conformant
##
## Offsets are bytes. Pele keeps the end of the last run of spaces, dashes and whitespace it
## scanned, so that a long run is not scanned again from each of its characters; the end of a
## run is the same from any of its characters, and nimaki scans it again.
import std/strutils
import ../../util/chars
import ../common/scan
import tokens

export scan.Tokens

const
  S_INITIAL = 0
  S_TITLE = 1
  S_ACC_TITLE = 2
  S_ACC_DESCR = 3
  S_ACC_DESCR_MULTILINE = 4
  S_STRING = 5
  S_MD_STRING = 6
  S_CLASS_NAME = 7
  S_POINT_START = 8
  S_POINT_X = 9
  S_POINT_Y = 10

  AT_END = [T_EOF, T_title_value, T_acc_title_value, T_acc_descr_value, T_acc_descr_multiline_value, T_STR]
    ## The token each state gives for the empty rest of the input, where it gives one.

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
  of ord(' '), ord('\t'), 11, 12: T_SPACE
  of ord(';'): T_SEMI
  of ord('!'), ord('$'), ord('%'), ord('\''), ord('`'), ord('?'), ord('\\'), ord('/'): T_PUNCTUATION
  else: 0

func byteAt(s: string, i: int): int =
  if i >= 0 and i < s.len: ord(s[i]) else: -1

func wordAt*(src: string, at: int, word: string): bool =
  ## Whether `word`, written in lower case, is at `at`. Only ASCII letters match in either case,
  ## as with the `i` flag on a regular expression without the `u` flag.
  for k in 0 ..< word.len:
    let c = byteAt(src, at + k)
    let w = ord(word[k])
    if c != w and not (w >= 97 and w <= 122 and c == w - 32): return false
  true

proc tokenize*(src: string): Tokens =
  let n = src.len
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0

  template emit(kind, s, e: int) =
    result.types.add kind
    result.texts.add src[s ..< e]
    result.starts.add s
    p = e
  template push(s: int) =
    stack.add state
    state = s
  template pop() =
    if stack.len > 0: state = stack.pop()

  proc spaces(q: int): int =
    result = q
    while byteAt(src, result) == 32: inc result
  proc run(q: int): int =
    result = q
    while result < n and isSpace(codeAt(src, result)): result += sizeAt(src, result)
  # Mermaid's `(1)|(0(.\d+)?)`, where the dot is any character within a line.
  proc coordinate(q: int): int =
    let c = byteAt(src, q)
    if c == 49: return q + 1
    if c != 48: return -1
    var e = q + 1
    if e < n:
      let d = codeAt(src, e)
      # a character past U+FFFF is two code units, and the second is no digit
      if not isLineEnd(d) and d <= 0xFFFF and isDigit(byteAt(src, e + sizeAt(src, e))):
        e += sizeAt(src, e) + 1
        while isDigit(byteAt(src, e)): inc e
    e

  block lexing:
    while p < n:
      let c = ord(src[p])
      let next = byteAt(src, p + 1)

      case state
      of S_TITLE, S_ACC_TITLE, S_ACC_DESCR:
        emit(AT_END[state], p, lineEnd(src, p))
        pop()
        continue
      of S_ACC_DESCR_MULTILINE:
        if c == 125:
          inc p
          pop()
        else:
          let e = src.find('}', p)
          emit(T_acc_descr_multiline_value, p, (if e == -1: n else: e))
        continue
      of S_STRING:
        if c == 34:
          inc p
          pop()
        else:
          let e = src.find('"', p)
          emit(T_STR, p, (if e == -1: n else: e))
        continue
      of S_MD_STRING:
        if c == 96 and next == 34:
          p += 2
          pop()
          continue
        if c != 96 and c != 34:
          var e = p + 1
          while e < n and src[e] != '`' and src[e] != '"': inc e
          emit(T_MD_STR, p, e)
          continue
        break lexing
      of S_CLASS_NAME:
        if isWord(c):
          var e = p + 1
          while isWord(byteAt(src, e)): inc e
          emit(T_class_name, p, e)
          pop()
          continue
        break lexing
      of S_POINT_START:
        let e = coordinate(p)
        if e != -1:
          emit(T_point_x, p, e)
          push(S_POINT_X)
          continue
        let k = run(p)
        if byteAt(src, k) == 93:
          p = spaces(k + 1)
          pop()
          continue
        break lexing
      of S_POINT_X:
        let k = run(p)
        if byteAt(src, k) == 44:
          p = run(k + 1)
          state = S_POINT_Y
          continue
        break lexing
      of S_POINT_Y:
        let e = coordinate(p)
        if e != -1:
          emit(T_point_y, p, e)
          pop()
          continue
        break lexing
      else: discard

      if c == 37 and next == 37:
        p = lineEnd(src, p + 2)
        continue
      if c == 10 or c == 13:
        var e = p + 1
        while byteAt(src, e) == 10 or byteAt(src, e) == 13: inc e
        emit(T_NEWLINE, p, e)
        continue

      let lower = c or 32
      if lower == 116 and wordAt(src, p, "title") and not isWord(byteAt(src, p + 5)):
        emit(T_title, p, p + 5)
        push(S_TITLE)
        continue
      if lower == 97 and wordAt(src, p, "acc"):
        let descr = wordAt(src, p + 3, "descr")
        if descr or wordAt(src, p + 3, "title"):
          let k = run(p + 8)
          let d = byteAt(src, k)
          if d == 58:
            emit((if descr: T_acc_descr else: T_acc_title), p, run(k + 1))
            push(if descr: S_ACC_DESCR else: S_ACC_TITLE)
            continue
          if d == 123 and descr:
            p = run(k + 1)
            push(S_ACC_DESCR_MULTILINE)
            continue

      # Axis, quadrant and chart keywords and the axis arrow take the spaces around them.
      let j = if c == 32: spaces(p) else: p
      let d = byteAt(src, j)
      let dl = d or 32
      var kind = 0
      var stop = 0
      if dl == 120 and wordAt(src, j, "x-axis"):
        kind = T_X_AXIS
        stop = j + 6
      elif dl == 121 and wordAt(src, j, "y-axis"):
        kind = T_Y_AXIS
        stop = j + 6
      elif d == 45:
        var dashTo = j
        while byteAt(src, dashTo) == 45: inc dashTo
        if dashTo - j >= 2 and byteAt(src, dashTo) == 62:
          kind = T_DELIMITER
          stop = dashTo + 1
      elif dl == 113 and wordAt(src, j, "quadrant"):
        let q = byteAt(src, j + 9)
        if byteAt(src, j + 8) == 45 and q >= 49 and q <= 52:
          kind = T_QUADRANT_1 + q - 49
          stop = j + 10
        elif wordAt(src, j + 8, "chart"):
          kind = T_QUADRANT
          stop = j + 13
      if kind != 0:
        emit(kind, p, spaces(stop))
        continue

      if lower == 99 and wordAt(src, p, "classdef") and not isWord(byteAt(src, p + 8)):
        emit(T_CLASSDEF, p, p + 8)
        continue
      if c == 34:
        if next == 96:
          p += 2
          push(S_MD_STRING)
        else:
          inc p
          push(S_STRING)
        continue
      if c == 58 and next == 58 and byteAt(src, p + 2) == 58:
        p += 3
        push(S_CLASS_NAME)
        continue
      # A point's `: [`, with any whitespace before, between and after, line breaks included.
      let cp = codeAt(src, p)
      if c == 58 or isSpace(cp):
        let k = if c != 58: run(p) else: p
        if byteAt(src, k) == 58:
          let gapTo = run(k + 1)
          if byteAt(src, gapTo) == 91:
            emit(T_point_start, p, run(gapTo + 1))
            push(S_POINT_START)
            continue

      if isLetter(c):
        var e = p + 1
        while isLetter(byteAt(src, e)): inc e
        emit(T_ALPHA, p, e)
        continue
      if c >= 128:
        var e = p + 1
        while byteAt(src, e) >= 128: inc e
        emit(T_UNICODE_TEXT, p, e)
        continue
      if isDigit(c):
        var e = p + 1
        while isDigit(byteAt(src, e)): inc e
        emit(T_NUM, p, e)
        continue
      if c < 128 and single(c) != 0:
        emit(single(c), p, p + 1)
        continue
      break lexing

  if p < n:
    result.types.add T_ERROR
    result.texts.add ""
    result.starts.add p
    return
  # Jison tries the rules of the current state once more against the empty rest of the input.
  if state < AT_END.len:
    result.types.add AT_END[state]
    result.texts.add ""
    result.starts.add n
  result.types.add T_END
  result.texts.add ""
  result.starts.add n

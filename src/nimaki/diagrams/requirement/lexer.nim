## port-of: src/diagrams/requirement/lexer.ts
## port-status: conformant
##
## Positions are byte offsets into the UTF-8 source (decision 0011). `cc(q)` reads the character
## at `q` as `charCodeAt` would where it matters (a whole code point; -1 past the end), and a
## `q++` over a character that may not be ASCII steps over the whole character (`step`).
import std/[strutils, tables]
import ../../js
import ../../util/chars
import ../common/scan
import tokens
import ../../jsregex

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

const
  S_INITIAL = 0
  S_string = 1
  S_style = 2
  S_acc_title = 3
  S_acc_descr = 4
  S_acc_descr_multiline = 5
  LONGEST_KEYWORD = 22
  RE_ACC_TITLE = jsre"/accTitle\s*:\s*/iy"
  RE_ACC_DESCR = jsre"/accDescr\s*:\s*/iy"
  RE_ACC_DESCR_ML = jsre"/accDescr\s*\{\s*/iy"
  RE_DIRECTION = jsre"/direction\s+(?:(TB)|(BT)|(RL)|LR)/gi"
  RE_LINE_END = jsre"/[\n\r\u2028\u2029]/g"

func isStop(c: char): bool =
  ## Characters that end an unquoted string: `:,{<>-=` and line breaks.
  c in {':', ',', '\r', '\n', '{', '<', '>', '-', '='}

func wordCI(src, w: string, q: int): bool =
  ## Case-insensitive match of a lowercase ASCII word, as the /i flag gives.
  for i in 0 ..< w.len:
    let a = ord(w[i])
    let c = if q + i < src.len: ord(src[q + i]) else: -1
    if c != a and not (a >= 97 and a <= 122 and c == a - 32): return false
  true

# Produces the token stream of Mermaid's requirement lexer. Its rules are tried in order and
# the first match wins, so a line that holds a direction statement anywhere is one token.
proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0

  template cc(q: int): int = codeAt(src, q)
  template step(q: int): int = q + sizeAt(src, q)
  template byteAt(q: int): int = (if q < n: ord(src[q]) else: -1)

  # Where each kind of direction statement starts and where its keyword ends, found in one pass.
  var dirStarts: array[4, seq[int]]
  var dirEnds: array[4, seq[int]]
  var dirSeen = [0, 0, 0, 0]
  var anyDir = false
  var lineEnd = -1
  for m in RE_DIRECTION.matches(src):
    let kind = if m.has(1): 0 elif m.has(2): 1 elif m.has(3): 2 else: 3
    dirStarts[kind].add m.index
    dirEnds[kind].add m.stop
    anyDir = true

  proc emit(t, s, e: int) =
    types.add t
    texts.add src[s ..< e]
    starts.add s
    p = e
  proc push(s: int) =
    stack.add state
    state = s
  proc pop() =
    if stack.len > 0: state = stack.pop()
  proc at(re: JsRegExp, q: int): int = re.matchEnd(src, q)
  proc lineBreak(q: int): int =
    let e = src.find('\n', q)
    if e == -1: n else: e

  # `.*direction\s+XX[^\n]*`: the last such statement that starts on this line decides the token.
  proc direction(): bool =
    if lineEnd < p:
      let m = RE_LINE_END.exec(src, p)
      lineEnd = if m.found: m.index else: n
      for k in 0 ..< 4:
        var j = dirSeen[k]
        while j < dirStarts[k].len and dirStarts[k][j] <= lineEnd: inc j
        dirSeen[k] = j
    for k in 0 ..< 4:
      let j = dirSeen[k] - 1
      if j >= 0 and dirStarts[k][j] >= p:
        emit(T_direction_tb + k, p, lineBreak(dirEnds[k][j]))
        return true
    false

  proc initial(c: int): bool =
    let lower = c or 32
    if lower == 116 and wordCI(src, "itle", p + 1) and isSpace(cc(p + 5)):
      let from0 = step(p + 5)
      var q = from0
      while q < n:
        let d = ord(src[q])
        if d == 35 or d == 10 or d == 59: break
        inc q
      if q > from0:
        emit(T_title, p, q)
        return true
    if lower == 97 and (byteAt(p + 1) or 32) == 99 and (byteAt(p + 2) or 32) == 99:
      var e = at(RE_ACC_TITLE, p)
      if e >= 0:
        push(S_acc_title)
        emit(T_acc_title, p, e)
        return true
      e = at(RE_ACC_DESCR, p)
      if e >= 0:
        push(S_acc_descr)
        emit(T_acc_descr, p, e)
        return true
      e = at(RE_ACC_DESCR_ML, p)
      if e >= 0:
        push(S_acc_descr_multiline)
        p = e
        return true
    if anyDir and not isLineEnd(c) and direction(): return true

    if c == 10 or (c == 13 and byteAt(p + 1) == 10):
      var q = p
      while q < n:
        let d = ord(src[q])
        if d == 10: inc q
        elif d == 13 and byteAt(q + 1) == 10: q += 2
        else: break
      emit(T_NEWLINE, p, q)
      return true
    if isSpace(c):
      p = step(p)
      while p < n and isSpace(cc(p)): p = step(p)
      return true
    if c == 35 or c == 37:
      p = lineBreak(p)
      return true

    if isWord(c):
      var q = p + 1
      while q < n and isWord(ord(src[q])): inc q
      if q - p <= LONGEST_KEYWORD:
        let keyword = KEYWORDS.getOrDefault(src[p ..< q].toLowerAscii, -1)
        if keyword != -1:
          if keyword == T_STYLE or keyword == T_CLASSDEF or keyword == T_CLASS: push(S_style)
          emit(keyword, p, q)
          return true
      while q < n:
        if isStop(src[q]): break
        inc q
      types.add T_unqString
      texts.add src[p ..< q].jsTrim
      starts.add p
      p = q
      return true

    case c
    of 123:
      emit(T_STRUCT_START, p, p + 1)
      true
    of 125:
      emit(T_STRUCT_STOP, p, p + 1)
      true
    of 58:
      if byteAt(p + 1) == 58 and byteAt(p + 2) == 58: emit(T_STYLE_SEPARATOR, p, p + 3)
      else: emit(T_COLONSEP, p, p + 1)
      true
    of 60:
      if byteAt(p + 1) != 45: return false
      emit(T_END_ARROW_L, p, p + 2)
      true
    of 45:
      if byteAt(p + 1) == 62: emit(T_END_ARROW_R, p, p + 2)
      else: emit(T_LINE, p, p + 1)
      true
    of 34:
      push(S_string)
      inc p
      true
    of 44:
      emit(T_COMMA, p, p + 1)
      true
    else:
      false

  proc style(c: int): bool =
    if isWord(c):
      var q = p + 1
      while q < n and isWord(ord(src[q])): inc q
      emit(T_ALPHA, p, q)
      return true
    case c
    of 58:
      emit(T_COLON, p, p + 1)
    of 59:
      emit(T_SEMICOLON, p, p + 1)
    of 37:
      emit(T_PERCENT, p, p + 1)
    of 45:
      emit(T_MINUS, p, p + 1)
    of 35:
      emit(T_BRKT, p, p + 1)
    of 32:
      inc p
    of 34:
      push(S_string)
      inc p
    of 10:
      pop()
      inc p
    of 44:
      emit(T_COMMA, p, p + 1)
    else:
      return false
    true

  while p < n:
    let c = cc(p)
    var ok = true
    case state
    of S_INITIAL:
      ok = initial(c)
    of S_style:
      ok = style(c)
    of S_string:
      if c == 34:
        pop()
        inc p
      else:
        let e = src.find('"', p)
        emit(T_qString, p, if e == -1: n else: e)
    of S_acc_title:
      pop()
      emit(T_acc_title_value, p, lineBreak(p))
    of S_acc_descr:
      pop()
      emit(T_acc_descr_value, p, lineBreak(p))
    else:  # S_acc_descr_multiline
      if c == 125:
        pop()
        inc p
      else:
        let e = src.find('}', p)
        emit(T_acc_descr_multiline_value, p, if e == -1: n else: e)
    if not ok:
      types.add T_ERROR
      texts.add ""
      starts.add p
      return Tokens(types: types, texts: texts, starts: starts)

  # At the end of input Jison still tries the rules that can match nothing, once.
  let last =
    if state == S_INITIAL: T_EOF
    elif state == S_string: T_qString
    elif state == S_acc_title: T_acc_title_value
    elif state == S_acc_descr: T_acc_descr_value
    elif state == S_acc_descr_multiline: T_acc_descr_multiline_value
    else: -1
  if last != -1: emit(last, n, n)
  emit(T_END, n, n)
  Tokens(types: types, texts: texts, starts: starts)

## port-of: src/diagrams/er/lexer.ts
## port-status: draft
##
## Positions are byte offsets into the UTF-8 source (decision 0011). `cc(q)` reads the character
## at `q` as `charCodeAt` would where it matters (a whole code point; -1 past the end), and a
## `q++` over a character that may not be ASCII steps over the whole character (`step`). Runs
## that test `c >= 128` read bytes, which is the same test: every byte of a character that is not
## ASCII is 128 or more.
import std/strutils
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
  S_block = 1
  S_block_bq = 2
  S_acc_title = 3
  S_acc_descr = 4
  S_acc_descr_multiline = 5
  S_style = 6

  TEXT = 1
  STYLE_TEXT = 2
  ATTR_START = 4
  ATTR_REST = 8

proc classTable(): array[128, int] =
  for c in 0 ..< 128:
    let word = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
    let letter = word and (c < 48 or c > 57)
    if word: result[c] = result[c] or TEXT or STYLE_TEXT or ATTR_REST
    if letter: result[c] = result[c] or ATTR_START
  for ch in "-*": result[ord(ch)] = result[ord(ch)] or TEXT or STYLE_TEXT or ATTR_REST
  result[46] = result[46] or TEXT or ATTR_REST
  result[42] = result[42] or ATTR_START
  for ch in "[](),": result[ord(ch)] = result[ord(ch)] or ATTR_REST

const CLASS = classTable()

func classOf(c, kind: int): bool =
  ## `(CLASS[c] & kind) !== 0` for a byte, with `c >= 128` counted in: true for every byte of a
  ## character that is not ASCII.
  c >= 128 or (c >= 0 and (CLASS[c] and kind) != 0)

func isAttr(c, kind: int): bool =
  ## Mermaid's attribute pattern is case-insensitive, which lets the micro sign into its
  ## À-￿ range. `c` is a code point.
  if c < 0: false
  elif c < 128: (CLASS[c] and kind) != 0
  else: c >= 0xc0 or c == 0xb5

const RE_ACC_TITLE = jsre"/accTitle\s*:\s*/iy"
const RE_ACC_DESCR = jsre"/accDescr\s*:\s*/iy"
const RE_ACC_DESCR_ML = jsre"/accDescr\s*\{\s*/iy"
const RE_DIRECTION = [
  jsre"/.*direction\s+TB[^\n]*/iy",
  jsre"/.*direction\s+BT[^\n]*/iy",
  jsre"/.*direction\s+RL[^\n]*/iy",
  jsre"/.*direction\s+LR[^\n]*/iy",
]
const RE_DIR_WORD = jsre"/direction/gi"
const RE_LINE_END = jsre"/[\n\r\u2028\u2029]/g"

func nextLineEnd(src: string, q: int): int =
  let m = RE_LINE_END.exec(src, q)
  if m.found: m.index else: src.len

func wordCI(src, w: string, q: int): bool =
  ## Case-insensitive match of a lowercase ASCII word, as the /i flag gives.
  for i in 0 ..< w.len:
    let a = ord(w[i])
    let c = if q + i < src.len: ord(src[q + i]) else: -1
    if c != a and not (a >= 97 and a <= 122 and c == a - 32): return false
  true

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var state = S_INITIAL
  var p = 0
  var dirNext = -2
  var dirFailed = 0
  var lineEnd = -1
  var tildeNext = -2
  var tildeLine = -1
  var tildeLast = -1
  var wsNext = -1

  template cc(q: int): int = codeAt(src, q)
  template step(q: int): int = q + sizeAt(src, q)
  template byteAt(q: int): int = (if q < n: ord(src[q]) else: -1)

  proc emit(t, s, e: int) =
    types.add t
    texts.add src[s ..< e]
    starts.add s
    p = e
  # Matches a lower-case keyword at p, ignoring case.
  proc kw(word: string): bool = wordCI(src, word, p)
  proc kwb(word: string): bool = kw(word) and not isWord(cc(p + word.len))
  proc lower(q: int): int =
    let c = byteAt(q)
    if c >= 65 and c <= 90: c + 32 else: c
  proc digits(q: int): int =
    var q = q
    while isDigit(byteAt(q)): inc q
    q

  # A direction statement swallows its whole line, from wherever the lexer stands on it.
  proc direction(): bool =
    if dirNext == -1: return false
    if dirNext < p:
      dirNext = RE_DIR_WORD.exec(src, p).index
      if dirNext == -1: return false
    if p < dirFailed: return false
    if lineEnd < p: lineEnd = nextLineEnd(src, p)
    if dirNext >= lineEnd: return false
    for i in 0 ..< 4:
      let e = RE_DIRECTION[i].matchEnd(src, p)
      if e >= 0:
        emit(T_direction_tb + i, p, e)
        return true
    dirFailed = lineEnd
    false

  proc quoted() =
    let e = src.find('"', p + 1)
    if e == -1:
      emit(T_CHAR, p, p + 1)
      return
    var name = e > p + 1
    var q = p + 1
    while name and q < e:
      let c = ord(src[q])
      if c == 37 or c == 92 or c == 13 or c == 10 or c == 11 or c == 8: name = false
      inc q
    emit(if name: T_ENTITY_NAME else: T_WORD, p, e + 1)

  proc number(c: int) =
    let d = cc(p + 1)
    if d == 43 and (c == 49 or c == 48):
      emit(if c == 49: T_ONE_OR_MORE else: T_ZERO_OR_MORE, p, p + 2)
      return
    let q = digits(p + 1)
    if byteAt(q) == 46 and isDigit(byteAt(q + 1)):
      emit(T_DECIMAL_NUM, p, digits(q + 2))
      return
    if c == 49:
      if isSpace(d):
        var r = step(p + 1)
        while isSpace(cc(r)): r = step(r)
        let f = cc(r)
        if isWord(f) or f == 34 or f == 39:
          emit(T_ONLY_ONE, p, p + 1)
          return
      elif d == 45 or d == 46:
        let f = byteAt(p + 2)
        if f == 45 or f == 46:
          emit(T_ONLY_ONE, p, p + 1)
          return
      if not isWord(d):
        emit(T_ENTITY_ONE, p, p + 1)
        return
    emit(T_NUM, p, q)

  proc keyword(lc: int): bool =
    let d = byteAt(p + 1)
    case lc
    of 101:
      if kwb("erdiagram"): emit(T_ER_DIAGRAM, p, p + 9)
      elif kwb("end"):
        var e = p + 3
        while isSpace(cc(e)): e = step(e)
        emit(T_END_KW, p, e)
      else: return false
      true
    of 115:
      if kwb("style"):
        state = S_style
        emit(T_STYLE, p, p + 5)
      elif kwb("subgraph"): emit(T_SUBGRAPH, p, p + 8)
      else: return false
      true
    of 99:
      if kwb("classdef"):
        state = S_style
        emit(T_CLASSDEF, p, p + 8)
      elif kwb("class"): emit(T_CLASS, p, p + 5)
      else: return false
      true
    of 111:
      if kwb("one or zero"): emit(T_ZERO_OR_ONE, p, p + 11)
      elif kwb("one or more") or kwb("one or many"): emit(T_ONE_OR_MORE, p, p + 11)
      elif kwb("one"): emit(T_ONLY_ONE, p, p + 3)
      elif kwb("only one"): emit(T_ONLY_ONE, p, p + 8)
      elif d == 124: emit(T_ZERO_OR_ONE, p, p + 2)
      elif d == 123: emit(T_ZERO_OR_MORE, p, p + 2)
      elif kwb("optionally to"): emit(T_NON_IDENTIFYING, p, p + 13)
      else: return false
      true
    of 122:
      if kwb("zero or one"): emit(T_ZERO_OR_ONE, p, p + 11)
      elif kwb("zero or more") or kwb("zero or many"): emit(T_ZERO_OR_MORE, p, p + 12)
      else: return false
      true
    of 109:
      if kw("many(0)"): emit(T_ZERO_OR_MORE, p, p + 7)
      elif kw("many(1)"): emit(T_ONE_OR_MORE, p, p + 7)
      elif kwb("many"): emit(T_ZERO_OR_MORE, p, p + 4)
      else: return false
      true
    of 116:
      if not kwb("to"): return false
      emit(T_IDENTIFYING, p, p + 2)
      true
    of 117:
      if d != 46 and d != 45 and d != 124: return false
      emit(T_MD_PARENT, p, p + 1)
      true
    of 124:
      if lower(p + 1) == 111 and not isWord(cc(p + 2)): emit(T_ZERO_OR_ONE, p, p + 2)
      elif d == 124: emit(T_ONLY_ONE, p, p + 2)
      elif d == 123: emit(T_ONE_OR_MORE, p, p + 2)
      else: return false
      true
    of 125:
      if lower(p + 1) == 111 and not isWord(cc(p + 2)): emit(T_ZERO_OR_MORE, p, p + 2)
      elif d == 124: emit(T_ONE_OR_MORE, p, p + 2)
      else: return false
      true
    of 46:
      if d != 46 and d != 45: return false
      emit(T_NON_IDENTIFYING, p, p + 2)
      true
    of 45:
      if d == 45: emit(T_IDENTIFYING, p, p + 2)
      elif d == 46: emit(T_NON_IDENTIFYING, p, p + 2)
      else: return false
      true
    else:
      false

  proc initial(c: int) =
    if (c == 97 or c == 65) and kw("acc"):
      var e = RE_ACC_TITLE.matchEnd(src, p)
      if e >= 0:
        state = S_acc_title
        emit(T_acc_title, p, e)
        return
      e = RE_ACC_DESCR.matchEnd(src, p)
      if e >= 0:
        state = S_acc_descr
        emit(T_acc_descr, p, e)
        return
      e = RE_ACC_DESCR_ML.matchEnd(src, p)
      if e >= 0:
        state = S_acc_descr_multiline
        p = e
        return
    if direction(): return

    case c
    of 32, 9, 13:
      var e = p + 1
      while byteAt(e) == 32 or byteAt(e) == 9 or byteAt(e) == 13: inc e
      p = e
      return
    of 10:
      var e = p + 1
      while byteAt(e) == 10: inc e
      emit(T_NEWLINE, p, e)
      return
    of 34:
      quoted()
      return
    of 123:
      state = S_block
      emit(T_BLOCK_START, p, p + 1)
      return
    of 35:
      emit(T_BRKT, p, p + 1)
      return
    of 44:
      emit(T_COMMA, p, p + 1)
      return
    of 58:
      if byteAt(p + 1) == 58 and byteAt(p + 2) == 58: emit(T_STYLE_SEPARATOR, p, p + 3)
      else: emit(T_COLON, p, p + 1)
      return
    of 91:
      emit(T_SQS, p, p + 1)
      return
    of 93:
      emit(T_SQE, p, p + 1)
      return
    else: discard
    if isDigit(c):
      number(c)
      return
    if keyword(if c >= 65 and c <= 90: c + 32 else: c): return
    if classOf(byteAt(p), TEXT):
      var e = p + 1
      while classOf(byteAt(e), TEXT): inc e
      emit(T_UNICODE_TEXT, p, e)
      return
    emit(T_CHAR, p, p + 1)

  # Mermaid's generic type rule: a run of non-space characters holding a `~`, through the last `~` on the line.
  proc generic(): bool =
    if tildeNext == -1: return false
    if tildeNext < p:
      tildeNext = src.find('~', p)
      if tildeNext == -1: return false
    if wsNext < p:
      var q = p
      while q < n and not isSpace(cc(q)): q = step(q)
      wsNext = q
    if tildeNext >= wsNext: return false
    if tildeLine < p:
      tildeLine = nextLineEnd(src, p)
      tildeLast = src.rfind('~', 0, max(tildeLine - 1, 0))
    if tildeLast <= tildeNext: return false
    var e = tildeLast + 1
    while e < n and not isSpace(cc(e)): e = step(e)
    emit(T_ATTRIBUTE_WORD, p, e)
    true

  proc blockRule(c: int) =
    if isSpace(c):
      p = step(p)
      while isSpace(cc(p)): p = step(p)
      return
    let lc = c or 32
    if (lc == 112 or lc == 102 or lc == 117) and (byteAt(p + 1) or 32) == 107 and not isWord(cc(p + 2)):
      emit(T_ATTRIBUTE_KEY, p, p + 2)
      return
    if generic(): return
    if isAttr(c, ATTR_START):
      var e = step(p)
      while e < n and isAttr(cc(e), ATTR_REST): e = step(e)
      emit(T_ATTRIBUTE_WORD, p, e)
      return
    if c == 96:
      state = S_block_bq
      inc p
      return
    if c == 34:
      let e = src.find('"', p + 1)
      if e != -1:
        emit(T_COMMENT, p, e + 1)
        return
    elif c == 125:
      state = S_INITIAL
      emit(T_BLOCK_STOP, p, p + 1)
      return
    emit(T_CHAR, p, step(p))

  while p < n:
    let c = cc(p)
    case state
    of S_INITIAL:
      initial(c)
    of S_block:
      blockRule(c)
    of S_block_bq:
      if c == 96:
        state = S_block
        inc p
      else:
        let e = src.find('`', p)
        emit(T_ATTRIBUTE_WORD, p, if e == -1: n else: e)
    of S_acc_title, S_acc_descr:
      let e = src.find('\n', p)
      emit(if state == S_acc_title: T_acc_title_value else: T_acc_descr_value, p, if e == -1: n else: e)
      state = S_INITIAL
    of S_acc_descr_multiline:
      if c == 125:
        state = S_INITIAL
        inc p
      else:
        let e = src.find('}', p)
        emit(T_acc_descr_multiline_value, p, if e == -1: n else: e)
    else:  # S_style
      if c == 10:
        var e = p + 1
        while byteAt(e) == 10: inc e
        state = S_INITIAL
        emit(T_NEWLINE, p, e)
      elif isSpace(c):
        p = step(p)
        while isSpace(cc(p)): p = step(p)
      elif c == 58: emit(T_COLON, p, p + 1)
      elif c == 44: emit(T_COMMA, p, p + 1)
      elif c == 35: emit(T_BRKT, p, p + 1)
      elif c == 59: emit(T_SEMI, p, p + 1)
      elif classOf(byteAt(p), STYLE_TEXT):
        var e = p + 1
        while classOf(byteAt(e), STYLE_TEXT): inc e
        emit(T_STYLE_TEXT, p, e)
      else:
        types.add T_ERROR
        texts.add ""
        starts.add p
        return Tokens(types: types, texts: texts, starts: starts)

  # At the end of input Jison's INITIAL state yields EOF, the title and description states yield
  # an empty value, and the block and style states yield nothing.
  let last =
    if state == S_INITIAL: T_EOF
    elif state == S_acc_title: T_acc_title_value
    elif state == S_acc_descr: T_acc_descr_value
    elif state == S_acc_descr_multiline: T_acc_descr_multiline_value
    else: -1
  if last != -1:
    types.add last
    texts.add ""
    starts.add n
  types.add T_END
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)

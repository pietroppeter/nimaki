## port-of: src/diagrams/agentflow/lexer.ts
## port-status: conformant
##
## Port notes, as in the flowchart lexer: positions are byte offsets into the UTF-8 source.
## `cu(i)` reads the character at byte `i` as `charCodeAt` does where it matters (an ASCII byte is
## itself, any other character its code point, one outside the Basic Multilingual Plane its high
## surrogate); -1 past the end. Where the TypeScript steps one code unit past a character that may
## not be ASCII, the port steps past the whole character. Jison's columns count UTF-16 code units,
## and so do the columns here.
import std/strutils
import ../../js
import ../../util/[chars, unicode]
import tokens
import ../../jsregex

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]
  locs*: seq[int]
    ## Four numbers per token, counted the way Jison counts them: first line, first column,
    ## last line, last column. Lines start at 1, columns at 0.

const
  S_INITIAL = 0
  S_string = 1
  S_md_string = 2
  S_acc_title = 3
  S_acc_descr = 4
  S_acc_descr_multiline = 5
  S_dir = 6
  S_text = 7
  S_ellipseText = 8
  S_trapText = 9
  S_edgeText = 10
  S_click = 11
  S_callbackname = 12
  S_callbackargs = 13
  S_shapeData = 14
  S_shapeDataStr = 15

const NODE_CHAR = block:
  var t: array[128, bool]
  for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!\"#$%&'*+.`?\\_/":
    t[ord(ch)] = true
  t

func cu(src: string, i: int): int =
  if i < 0 or i >= src.len: return -1
  let b = ord(src[i])
  if b < 0x80: return b
  let (cp, _) = codePointAt(src, i)
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func charLen(src: string, i: int): int =
  if i >= src.len: 1 elif ord(src[i]) < 0x80: 1 else: codePointAt(src, i)[1]

func spaces(src: string, i: int): int =
  ## The end of a run of `\s` starting at i.
  var j = i
  while j < src.len and isSpace(cu(src, j)): j += charLen(src, j)
  j

const RE_ACC_TITLE = jsre"/accTitle\s*:\s*/y"
const RE_ACC_DESCR = jsre"/accDescr\s*:\s*/y"
const RE_ACC_DESCR_ML = jsre"/accDescr\s*\{\s*/y"
const RE_CALL = jsre"/call\s+/y"
const RE_CLICK = jsre"/click\s+/y"
const RE_NODIR = jsre"/(?:\r?\n)*\s*\n/y"
const RE_DIR = jsre"/\s*(?:LR|RL|TB|BT|TD|BR)\b/y"
const RE_DIR_SYM = jsre"/\s*[<>^]/y"
const RE_DIR_V = jsre"/\s*v\b/y"
const RE_DIRECTION = [
  jsre"/.*direction\s+TB[^\n]*/y",
  jsre"/.*direction\s+BT[^\n]*/y",
  jsre"/.*direction\s+RL[^\n]*/y",
  jsre"/.*direction\s+LR[^\n]*/y",
  jsre"/.*direction\s+TD[^\n]*/y",
]
const RE_LINE_END = jsre"/[\n\r\u2028\u2029]/g"
const RE_EMPTY_CALL = jsre"/\(\s*\)/y"
const RE_BR = jsre"/\n\s*/g"

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var locs: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0
  var line = 1
  var col = 0
  var firstGraph = true
  var dirNext = src.find("direction")
  var atNext = src.find('@')
  var lineEnd = -1
  var dirFailed = 0
  var runEnd = 0
  var runAt = -1
  var wsFrom = -1
  var wsTo = -1
  var blankFrom = -1
  var blankTo = -1
  var noLink = -1
  var noArrow = -1

  template cc(q: int): int = cu(src, q)

  # Moves over one match. Jison counts \r\n, \r and \n as one line break each, and after a
  # break its column stops at the first U+2028 or U+2029.
  proc advance(e: int) =
    var brk = -1
    var k = p
    while k < e:
      let ch = ord(src[k])
      if ch == 10:
        inc line
        brk = k
      elif ch == 13:
        if k + 1 < e and ord(src[k + 1]) == 10: inc k
        inc line
        brk = k
      inc k
    if brk < 0:
      col += utf16Len(src, p, e)
    else:
      var k = brk + 1
      while k < e:
        let ch = cc(k)
        if ch == 0x2028 or ch == 0x2029: break
        k += charLen(src, k)
      col = utf16Len(src, brk + 1, k)
    p = e

  proc emit(kind, e: int) =
    types.add kind
    texts.add src[p ..< e]
    starts.add p
    locs.add line
    locs.add col
    advance(e)
    locs.add line
    locs.add col

  # For a token that cannot hold a line break.
  proc emitFlat(kind, e: int) =
    types.add kind
    texts.add src[p ..< e]
    starts.add p
    locs.add line
    locs.add col
    col += utf16Len(src, p, e)
    p = e
    locs.add line
    locs.add col

  # For a run that Jison matches one character at a time, where \r\n counts as two line breaks.
  proc emitChars(kind, e: int) =
    types.add kind
    texts.add src[p ..< e]
    starts.add p
    locs.add line
    locs.add col
    var k = p
    while k < e:
      let ch = ord(src[k])
      if ch == 10 or ch == 13:
        inc line
        col = 0
        inc k
      else:
        let (cp, size) = codePointAt(src, k)
        col += (if cp >= 0x10000: 2 else: 1)
        k += size
    p = e
    locs.add line
    locs.add col

  proc emitText(kind: int, text: string, e: int) =
    types.add kind
    texts.add text
    starts.add p
    locs.add line
    locs.add col
    advance(e)
    locs.add line
    locs.add col

  proc push(s: int) =
    stack.add state
    state = s

  proc pop() =
    if stack.len > 0: state = stack.pop()

  proc kw(word: string): bool =
    src.continuesWith(word, p) and not isWord(cc(p + word.len))

  # End of the run of whitespace starting at q. The last run is kept, so asking again from inside it costs nothing.
  proc wsEnd(q: int): int =
    if q >= wsFrom and q <= wsTo: return wsTo
    let j = spaces(src, q)
    wsFrom = q
    wsTo = j
    j

  proc blankEnd(q: int): int =
    if q >= blankFrom and q <= blankTo: return blankTo
    var j = q
    while j < n:
      let ch = ord(src[j])
      if ch != 32 and ch != 9: break
      inc j
    blankFrom = q
    blankTo = j
    j

  # End of `\s*--+[x>]\s*` starting at q, or -1.
  proc arrowEnd(q: int): int =
    let j = wsEnd(q)
    if j == noArrow or cc(j) != 45 or cc(j + 1) != 45: return -1
    var k = j + 2
    while cc(k) == 45: inc k
    let t = cc(k)
    if t == 120 or t == 62: return wsEnd(k + 1)
    noArrow = j
    -1

  proc link(): bool =
    let j = wsEnd(p)
    if j == noLink or cc(j) != 45: return false
    let d = cc(j + 1)
    var k = j + 2
    if d == 45:
      while cc(k) == 45: inc k
      let t = cc(k)
      if t == 120 or t == 62:
        emit(T_LINK, wsEnd(k + 1))
      else:
        push(S_edgeText)
        emit(T_START_LINK, wsEnd(j + 2))
      return true
    if d == 46:
      while cc(k) == 46: inc k
      if cc(k) == 45:
        emit(T_LINK, wsEnd(k + 1))
        return true
    noLink = j
    false

  # `%%` not followed by `{`, through the end of the line.
  proc commentEnd(q: int): int =
    if cc(q) != 37 or cc(q + 1) != 37 or cc(q + 2) == 123: return -1
    let e = src.find('\n', q + 2)
    if e == -1: n else: e

  proc quote() =
    if cc(p + 1) == 96:
      push(S_md_string)
      advance(p + 2)
    else:
      push(S_string)
      advance(p + 1)

  proc opener(c: int): bool =
    let d = cc(p + 1)
    if c == 40:
      if d == 45:
        push(S_ellipseText)
        emitFlat(T_ELLIPSE_START, p + 2)
      elif d == 91:
        push(S_text)
        emitFlat(T_STADIUMSTART, p + 2)
      elif d == 40 and cc(p + 2) == 40:
        push(S_text)
        emitFlat(T_DOUBLECIRCLESTART, p + 3)
      else:
        push(S_text)
        emitFlat(T_PS, p + 1)
      return true
    if c == 91:
      if d == 91:
        push(S_text)
        emitFlat(T_SUBROUTINESTART, p + 2)
      elif d == 40:
        push(S_text)
        emitFlat(T_CYLINDERSTART, p + 2)
      elif d == 47:
        push(S_trapText)
        emitFlat(T_TRAPSTART, p + 2)
      elif d == 92:
        push(S_trapText)
        emitFlat(T_INVTRAPSTART, p + 2)
      else:
        push(S_text)
        emitFlat(T_SQS, p + 1)
      return true
    if c == 124:
      push(S_text)
      emitFlat(T_PIPE, p + 1)
      return true
    if c == 123:
      push(S_text)
      emitFlat(T_DIAMOND_START, p + 1)
      return true
    false

  proc nodeString(): bool =
    var q = p
    while q < n:
      let ch = ord(src[q])
      if ch < 128 and NODE_CHAR[ch]:
        inc q
      elif ch == 45 and q + 1 < n:
        let d = ord(src[q + 1])
        if d == 62 or d == 45 or d == 46: break
        inc q
      else:
        break
    if q == p: return false
    emitFlat(T_NODE_STRING, q)
    true

  proc blanks(origin: int): int =
    var e = origin
    while e < n:
      let ch = ord(src[e])
      if ch != 32 and ch != 9: break
      inc e
    e

  proc initial(c: int): bool =
    var e: int
    case c
    of 97:
      if src.continuesWith("acc", p):
        e = RE_ACC_TITLE.matchEnd(src, p)
        if e >= 0:
          push(S_acc_title)
          emit(T_acc_title, e)
          return true
        e = RE_ACC_DESCR.matchEnd(src, p)
        if e >= 0:
          push(S_acc_descr)
          emit(T_acc_descr, e)
          return true
        e = RE_ACC_DESCR_ML.matchEnd(src, p)
        if e >= 0:
          push(S_acc_descr_multiline)
          advance(e)
          return true
      if kw("agentflow-beta"):
        if firstGraph:
          firstGraph = false
          push(S_dir)
        emitFlat(T_GRAPH, p + 14)
        return true
    of 64:
      if cc(p + 1) == 123:
        push(S_shapeData)
        emitText(T_SHAPE_DATA, "", p + 2)
        return true
    of 99:
      e = RE_CALL.matchEnd(src, p)
      if e >= 0:
        push(S_callbackname)
        advance(e)
        return true
      if kw("classDef"):
        emitFlat(T_CLASSDEF, p + 8)
        return true
      if kw("class"):
        emitFlat(T_CLASS, p + 5)
        return true
      e = RE_CLICK.matchEnd(src, p)
      if e >= 0:
        push(S_click)
        advance(e)
        return true
      if kw("connector"):
        emitFlat(T_connector, p + 9)
        return true
    of 34:
      quote()
      return true
    of 115:
      if kw("style"):
        emitFlat(T_STYLE, p + 5)
        return true
    of 100:
      if kw("default"):
        emitFlat(T_DEFAULT, p + 7)
        return true
    of 108:
      if kw("linkStyle"):
        emitFlat(T_LINKSTYLE, p + 9)
        return true
    of 105:
      if kw("interpolate"):
        emitFlat(T_INTERPOLATE, p + 11)
        return true
    of 104:
      if src.continuesWith("href", p) and isSpace(cc(p + 4)):
        emit(T_HREF, p + 4 + charLen(src, p + 4))
        return true
    of 102:
      if kw("flow"):
        emitFlat(T_flow, p + 4)
        return true
    of 103:
      if kw("global"):
        emitFlat(T_global, blanks(p + 6))
        return true
    of 101:
      if kw("end"):
        emitFlat(T_end, blanks(p + 3))
        return true
    of 95:
      for (word, size) in [("_self", 5), ("_blank", 6), ("_parent", 7), ("_top", 4)]:
        if kw(word):
          emitFlat(T_LINK_TARGET, p + size)
          return true
    else: discard

    if dirNext != -1 and p >= dirFailed:
      if dirNext < p: dirNext = src.find("direction", p)
      if dirNext != -1:
        if lineEnd < p:
          let m = RE_LINE_END.exec(src, p)
          lineEnd = if m.found: m.index else: n
        if dirNext < lineEnd:
          for i in 0 ..< 5:
            e = RE_DIRECTION[i].matchEnd(src, p)
            if e >= 0:
              emit(T_direction_tb + i, e)
              return true
          # No direction statement starts anywhere in the rest of this line either.
          dirFailed = lineEnd

    # A link id is a run of non-space characters up to its last `@` that is not followed by `{` or `"`.
    if atNext != -1 and c != 34 and not isSpace(c):
      if p >= runEnd:
        if atNext < p: atNext = src.find('@', p)
        var q = p
        while q < n:
          let ch = cc(q)
          if ch == 34 or isSpace(ch): break
          q += charLen(src, q)
        runEnd = q
        runAt = -1
        if atNext != -1 and atNext < q:
          var k = min(q, n - 1) - 1
          while k >= atNext:
            if ord(src[k]) == 64:
              let after = cc(k + 1)
              if after != 123 and after != 34:
                runAt = k
                break
            dec k
      if runAt > p:
        emitFlat(T_LINK_ID, runAt + 1)
        return true

    if c >= 48 and c <= 57:
      var q = p + 1
      while q < n:
        let ch = ord(src[q])
        if ch < 48 or ch > 57: break
        inc q
      emitFlat(T_NUM, q)
      return true

    case c
    of 35:
      emitFlat(T_BRKT, p + 1)
      return true
    of 58:
      if cc(p + 1) == 58 and cc(p + 2) == 58: emitFlat(T_STYLE_SEPARATOR, p + 3)
      else: emitFlat(T_COLON, p + 1)
      return true
    of 38:
      emitFlat(T_AMP, p + 1)
      return true
    of 59:
      emitFlat(T_SEMI, p + 1)
      return true
    of 44:
      emitFlat(T_COMMA, p + 1)
      return true
    of 42:
      emitFlat(T_MULT, p + 1)
      return true
    of 60:
      emitFlat(T_TAGSTART, p + 1)
      return true
    of 45:
      if link() or nodeString(): return true
      emitFlat(T_MINUS, p + 1)
      return true
    of 40:
      return opener(c)
    of 91:
      if cc(p + 1) == 124:
        emitFlat(T_VERTEX_WITH_PROPS_START, p + 2)
        return true
      return opener(c)
    of 124, 123:
      return opener(c)
    of 62:
      push(S_text)
      emitFlat(T_TAGEND, p + 1)
      return true
    of 94:
      emitFlat(T_UP, p + 1)
      return true
    of 92:
      if cc(p + 1) == 124:
        emitFlat(T_SEP, p + 2)
        return true
      return nodeString()
    of 118:
      if not isWord(cc(p + 1)):
        emitFlat(T_DOWN, p + 1)
        return true
      return nodeString()
    of 37:
      e = commentEnd(p)
      if e >= 0:
        emit(T_COMMENT, e)
        return true
      return nodeString()
    else: discard

    if isSpace(c):
      if link(): return true
      if c == 32 or c == 9:
        e = commentEnd(blankEnd(p))
        if e >= 0:
          emit(T_COMMENT, e)
          return true
      e = p
      while true:
        let ch = cc(e)
        if ch == 10: inc e
        elif ch == 13 and cc(e + 1) == 10: e += 2
        else: break
      if e > p: emit(T_NEWLINE, e)
      else: emit(T_SPACE, p + charLen(src, p))
      return true

    if c < 128: return nodeString()
    if isUnicodeLetter(c):
      emitFlat(T_UNICODE_TEXT, p + charLen(src, p))
      return true
    false

  while true:
    if p >= n:
      var kind = -1
      case state
      of S_INITIAL: kind = T_EOF
      of S_acc_title: kind = T_acc_title_value
      of S_acc_descr: kind = T_acc_descr_value
      of S_acc_descr_multiline: kind = T_acc_descr_multiline_value
      of S_click: kind = T_CLICK
      of S_callbackname: kind = T_CALLBACKNAME
      of S_callbackargs: kind = T_CALLBACKARGS
      else: discard
      if kind != -1: emitFlat(kind, n)
      break

    let c = cc(p)
    var ok = true

    case state
    of S_INITIAL:
      ok = initial(c)

    of S_string:
      if c == 34:
        if cc(p + 1) == 96:
          push(S_md_string)
          advance(p + 2)
        else:
          pop()
          advance(p + 1)
      else:
        let e = src.find('"', p)
        emit(T_STR, if e == -1: n else: e)

    of S_md_string:
      if c == 96:
        if cc(p + 1) == 34:
          pop()
          advance(p + 2)
        else:
          ok = false
      elif c == 34:
        quote()
      else:
        var q = p + 1
        while q < n:
          let ch = ord(src[q])
          if ch == 96 or ch == 34: break
          inc q
        emit(T_MD_STR, q)

    of S_acc_title, S_acc_descr:
      var e = src.find('\n', p)
      if e == -1: e = n
      let kind = if state == S_acc_title: T_acc_title_value else: T_acc_descr_value
      pop()
      emit(kind, e)

    of S_acc_descr_multiline:
      if c == 125:
        pop()
        advance(p + 1)
      else:
        var e = src.find('}', p)
        if e == -1: e = n
        emit(T_acc_descr_multiline_value, e)

    of S_dir:
      if c == 34:
        quote()
      else:
        var e = RE_NODIR.matchEnd(src, p)
        if e >= 0:
          pop()
          emit(T_NODIR, e)
        else:
          e = RE_DIR.matchEnd(src, p)
          if e < 0: e = RE_DIR_SYM.matchEnd(src, p)
          if e < 0: e = RE_DIR_V.matchEnd(src, p)
          if e >= 0:
            pop()
            emit(T_DIR, e)
          else:
            ok = opener(c)

    of S_text:
      let d = cc(p + 1)
      case c
      of 34: quote()
      of 40, 91, 123: discard opener(c)
      of 93:
        pop()
        if d == 41: emitFlat(T_STADIUMEND, p + 2)
        elif d == 93: emitFlat(T_SUBROUTINEEND, p + 2)
        else: emitFlat(T_SQE, p + 1)
      of 41:
        pop()
        if d == 93: emitFlat(T_CYLINDEREND, p + 2)
        elif d == 41 and cc(p + 2) == 41: emitFlat(T_DOUBLECIRCLEEND, p + 3)
        else: emitFlat(T_PE, p + 1)
      of 124:
        pop()
        emitFlat(T_PIPE, p + 1)
      of 125:
        pop()
        emitFlat(T_DIAMOND_STOP, p + 1)
      of 37:
        # Jison drops the lone `%` from Mermaid's text pattern, so only a comment may start with one.
        let e = commentEnd(p)
        if e >= 0: advance(e)
        else: ok = false
      else:
        var q = p + charLen(src, p)
        while q < n:
          let ch = ord(src[q])
          if ch in [91, 93, 40, 41, 123, 125, 124, 34, 37]: break
          inc q
        emit(T_TEXT, q)

    of S_ellipseText:
      let d = cc(p + 1)
      var e: int
      if c == 34:
        quote()
      elif c == 37 and (e = commentEnd(p); e >= 0):
        advance(e)
      elif (c == 45 or c == 47 or c == 41) and d == 41:
        pop()
        emitFlat(T_ELLIPSE_END, p + 2)
      elif c == 40 or c == 91 or c == 123:
        discard opener(c)
      elif c == 41 or c == 93 or c == 125:
        ok = false
      else:
        var q = p + charLen(src, p)
        while q < n:
          let ch = ord(src[q])
          if ch in [34, 40, 41, 91, 93, 123, 125]: break
          if (ch == 45 or ch == 47) and cc(q + 1) == 41: break
          if ch == 37 and cc(q + 1) == 37 and cc(q + 2) != 123: break
          inc q
        emitChars(T_TEXT, q)

    of S_trapText:
      let d = cc(p + 1)
      if c == 34:
        quote()
      else:
        case c
        of 40:
          if d == 45 or d == 91 or (d == 40 and cc(p + 2) == 40): discard opener(c)
          elif d == 93:
            pop()
            emitFlat(T_TRAPEND, p + 2)
          else: discard opener(c)
        of 91, 123: discard opener(c)
        of 92:
          if d == 93:
            pop()
            emitFlat(T_TRAPEND, p + 2)
          else: emitFlat(T_TEXT, p + 1)
        of 47:
          if d == 93:
            pop()
            emitFlat(T_INVTRAPEND, p + 2)
          else: emitFlat(T_TEXT, p + 1)
        of 93, 41:
          if d == 93:
            pop()
            emitFlat(T_TRAPEND, p + 2)
          else: ok = false
        of 125: ok = false
        of 37:
          let e = commentEnd(p)
          if e >= 0: advance(e)
          else: ok = false
        else:
          if (c == 63 or c == 61) and d == 93:
            pop()
            emitFlat(T_TRAPEND, p + 2)
          else:
            var q = p + charLen(src, p)
            while q < n:
              let ch = ord(src[q])
              if ch in [92, 91, 93, 40, 41, 123, 125, 47, 37]: break
              inc q
            emit(T_TEXT, q)

    of S_edgeText:
      if c == 34:
        quote()
      else:
        let e = arrowEnd(p)
        if e >= 0:
          pop()
          emit(T_LINK, e)
        elif c == 45 and cc(p + 1) == 45:
          ok = false
        else:
          var q = p + charLen(src, p)
          while q < n:
            let ch = cc(q)
            if ch == 34: break
            if ch == 45:
              if cc(q + 1) == 45: break
            elif isSpace(ch) and arrowEnd(q) >= 0:
              break
            q += charLen(src, q)
          emitChars(T_EDGE_TEXT, q)

    of S_click:
      if c == 34:
        quote()
      elif isSpace(c):
        pop()
        advance(p + charLen(src, p))
      else:
        var q = p + charLen(src, p)
        while q < n and not isSpace(cc(q)): q += charLen(src, q)
        emitFlat(T_CLICK, q)

    of S_callbackname:
      if c == 40:
        let e = RE_EMPTY_CALL.matchEnd(src, p)
        pop()
        if e >= 0:
          advance(e)
        else:
          push(S_callbackargs)
          advance(p + 1)
      else:
        var e = src.find('(', p)
        if e == -1: e = n
        emit(T_CALLBACKNAME, e)

    of S_callbackargs:
      if c == 41:
        pop()
        advance(p + 1)
      else:
        var e = src.find(')', p)
        if e == -1: e = n
        emit(T_CALLBACKARGS, e)

    of S_shapeData:
      if c == 34:
        push(S_shapeDataStr)
        emitFlat(T_SHAPE_DATA, p + 1)
      elif c == 125:
        pop()
        advance(p + 1)
      elif c == 94:
        ok = false
      else:
        var q = p + charLen(src, p)
        while q < n:
          let ch = ord(src[q])
          if ch == 125 or ch == 94 or ch == 34: break
          inc q
        emit(T_SHAPE_DATA, q)

    of S_shapeDataStr:
      if c == 34:
        pop()
        emitFlat(T_SHAPE_DATA, p + 1)
      else:
        var e = src.find('"', p)
        if e == -1: e = n
        emitText(T_SHAPE_DATA, src[p ..< e].replace(RE_BR, "<br/>"), e)

    else: discard

    if not ok:
      types.add T_ERROR
      texts.add ""
      starts.add p
      locs.add [line, col, line, col]
      return Tokens(types: types, texts: texts, starts: starts, locs: locs)

  types.add T_STOP
  texts.add ""
  starts.add n
  locs.add [line, col, line, col]
  Tokens(types: types, texts: texts, starts: starts, locs: locs)

## port-of: src/diagrams/flowchart/lexer.ts
## port-status: conformant
##
## Port notes: positions are byte offsets into the UTF-8 source. `cu(i)` reads the character at
## byte `i` as `charCodeAt` does where it matters: an ASCII byte is itself, any other character
## is its code point, and one outside the Basic Multilingual Plane reads as its high surrogate
## (which is neither a letter nor a space). Past the end it is -1 (JavaScript's NaN). Where the
## TypeScript steps one code unit past a character that may not be ASCII, the port steps past
## the whole character.
import std/strutils
import ../../js
import ../../util/[chars, unicode]
import tokens
import ../../jsregex

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

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
  S_thickEdgeText = 11
  S_dottedEdgeText = 12
  S_click = 13
  S_callbackname = 14
  S_callbackargs = 15
  S_shapeData = 16
  S_shapeDataStr = 17

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
  ## The bytes of the character at i (as one step of the TypeScript's `++`).
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
const RE_LINK = jsre"/\s*[xo<]?--+[-xo>]\s*/y"
const RE_START_LINK = jsre"/\s*[xo<]?--\s*/y"
const RE_THICK_LINK = jsre"/\s*[xo<]?==+[=xo>]\s*/y"
const RE_THICK_START = jsre"/\s*[xo<]?==\s*/y"
const RE_DOTTED_LINK = jsre"/\s*[xo<]?-?\.+-[xo>]?\s*/y"
const RE_DOTTED_START = jsre"/\s*[xo<]?-\.\s*/y"
const RE_INVIS_LINK = jsre"/\s*~~~+\s*/y"
const RE_NEWLINE = jsre"/(?:\r?\n)+/y"
const RE_SPACE = jsre"/[^\S\n\r]+/y"
const RE_EMPTY_CALL = jsre"/\(\s*\)/y"
const RE_BR = jsre"/\n\s*/g"

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0
  var firstGraph = true
  var dirNext = src.find("direction")
  var atNext = src.find('@')
  var lineEnd = -1
  var dirFailed = 0
  var runEnd = 0
  var runAt = -1
  var wsFrom = -1
  var wsTo = -1

  template c0(i: int): int = cu(src, i)
  proc emit(kind: int, s, e: int) =
    types.add kind
    texts.add src[s ..< e]
    starts.add s
    p = e
  proc push(s: int) =
    stack.add state
    state = s
  proc pop() =
    if stack.len > 0: state = stack.pop()
  proc kw(w: string): bool = src.continuesWith(w, p) and not isWord(c0(p + w.len))

  # First character after any run of whitespace starting at q, skipping one optional x, o or <.
  proc linkChar(q: int): int =
    var j = q
    if q >= wsFrom and q <= wsTo:
      j = wsTo
    elif isSpace(c0(q)):
      j = spaces(src, j)
      wsFrom = q
      wsTo = j
    let d = c0(j)
    if d == 120 or d == 111 or d == 60: c0(j + 1) else: d
  proc invisAhead(q: int): bool =
    var j = q
    if q >= wsFrom and q <= wsTo:
      j = wsTo
    elif isSpace(c0(q)):
      j = spaces(src, j)
      wsFrom = q
      wsTo = j
    c0(j) == 126

  proc quote() =
    if c0(p + 1) == 96:
      push(S_md_string)
      p += 2
    else:
      push(S_string)
      inc p

  proc invisLink(): bool =
    if not invisAhead(p): return false
    let e = RE_INVIS_LINK.matchEnd(src, p)
    if e < 0: return false
    emit(T_LINK, p, e)
    true

  proc opener(c: int): bool =
    let d = c0(p + 1)
    if c == 40:
      if d == 45:
        push(S_ellipseText)
        emit(T_ELLIPSE_START, p, p + 2)
      elif d == 91:
        push(S_text)
        emit(T_STADIUMSTART, p, p + 2)
      elif d == 40 and c0(p + 2) == 40:
        push(S_text)
        emit(T_DOUBLECIRCLESTART, p, p + 3)
      else:
        push(S_text)
        emit(T_PS, p, p + 1)
      return true
    if c == 91:
      if d == 91:
        push(S_text)
        emit(T_SUBROUTINESTART, p, p + 2)
      elif d == 40:
        push(S_text)
        emit(T_CYLINDERSTART, p, p + 2)
      elif d == 47:
        push(S_trapText)
        emit(T_TRAPSTART, p, p + 2)
      elif d == 92:
        push(S_trapText)
        emit(T_INVTRAPSTART, p, p + 2)
      else:
        push(S_text)
        emit(T_SQS, p, p + 1)
      return true
    if c == 124:
      push(S_text)
      emit(T_PIPE, p, p + 1)
      return true
    if c == 123:
      push(S_text)
      emit(T_DIAMOND_START, p, p + 1)
      return true
    false

  proc graph(len: int) =
    if firstGraph:
      firstGraph = false
      push(S_dir)
    emit(T_GRAPH, p, p + len)

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
    emit(T_NODE_STRING, p, q)
    true

  proc link(c: int): bool =
    let d = linkChar(p)
    var e: int
    if d == 45:
      e = RE_LINK.matchEnd(src, p)
      if e >= 0:
        emit(T_LINK, p, e)
        return true
      e = RE_START_LINK.matchEnd(src, p)
      if e >= 0:
        push(S_edgeText)
        emit(T_START_LINK, p, e)
        return true
      e = RE_DOTTED_LINK.matchEnd(src, p)
      if e >= 0:
        emit(T_LINK, p, e)
        return true
      e = RE_DOTTED_START.matchEnd(src, p)
      if e >= 0:
        push(S_dottedEdgeText)
        emit(T_START_LINK, p, e)
        return true
    elif d == 61:
      e = RE_THICK_LINK.matchEnd(src, p)
      if e >= 0:
        emit(T_LINK, p, e)
        return true
      e = RE_THICK_START.matchEnd(src, p)
      if e >= 0:
        push(S_thickEdgeText)
        emit(T_START_LINK, p, e)
        return true
    elif d == 46:
      e = RE_DOTTED_LINK.matchEnd(src, p)
      if e >= 0:
        emit(T_LINK, p, e)
        return true
    c != 45 and c != 61 and c != 46 and invisLink()

  proc initial(c: int): bool =
    var e: int
    case c
    of 97:
      if src.continuesWith("acc", p):
        e = RE_ACC_TITLE.matchEnd(src, p)
        if e >= 0:
          push(S_acc_title)
          emit(T_acc_title, p, e)
          return true
        e = RE_ACC_DESCR.matchEnd(src, p)
        if e >= 0:
          push(S_acc_descr)
          emit(T_acc_descr, p, e)
          return true
        e = RE_ACC_DESCR_ML.matchEnd(src, p)
        if e >= 0:
          push(S_acc_descr_multiline)
          p = e
          return true
    of 64:
      if c0(p + 1) == 123:
        push(S_shapeData)
        types.add T_SHAPE_DATA
        texts.add ""
        starts.add p
        p += 2
        return true
    of 99:
      e = RE_CALL.matchEnd(src, p)
      if e >= 0:
        push(S_callbackname)
        p = e
        return true
      if kw("classDef"):
        emit(T_CLASSDEF, p, p + 8)
        return true
      if kw("class"):
        emit(T_CLASS, p, p + 5)
        return true
      e = RE_CLICK.matchEnd(src, p)
      if e >= 0:
        push(S_click)
        p = e
        return true
    of 34:
      quote()
      return true
    of 115:
      if kw("style"):
        emit(T_STYLE, p, p + 5)
        return true
      if kw("swimlane-beta"):
        graph(13)
        return true
      if kw("subgraph"):
        emit(T_subgraph, p, p + 8)
        return true
    of 100:
      if kw("default"):
        emit(T_DEFAULT, p, p + 7)
        return true
    of 108:
      if kw("linkStyle"):
        emit(T_LINKSTYLE, p, p + 9)
        return true
    of 105:
      if kw("interpolate"):
        emit(T_INTERPOLATE, p, p + 11)
        return true
    of 104:
      if src.continuesWith("href", p) and isSpace(c0(p + 4)):
        emit(T_HREF, p, p + 5)
        return true
    of 102:
      if kw("flowchart-elk"):
        graph(13)
        return true
      if kw("flowchart"):
        graph(9)
        return true
    of 103:
      if kw("graph"):
        graph(5)
        return true
    of 101:
      if kw("end"):
        e = spaces(src, p + 3)
        emit(T_end, p, e)
        return true
    of 95:
      if kw("_self"):
        emit(T_LINK_TARGET, p, p + 5)
        return true
      if kw("_blank"):
        emit(T_LINK_TARGET, p, p + 6)
        return true
      if kw("_parent"):
        emit(T_LINK_TARGET, p, p + 7)
        return true
      if kw("_top"):
        emit(T_LINK_TARGET, p, p + 4)
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
              emit(T_direction_tb + i, p, e)
              return true
          # No direction statement starts anywhere in the rest of this line either.
          dirFailed = lineEnd

    # A link id is a run of non-space characters up to its last `@` that is not followed by `{` or `"`.
    if atNext != -1 and c != 34 and not isSpace(c):
      if p >= runEnd:
        if atNext < p: atNext = src.find('@', p)
        var q = p
        while q < n:
          let ch = c0(q)
          if ch == 34 or isSpace(ch): break
          q += charLen(src, q)
        runEnd = q
        runAt = -1
        if atNext != -1 and atNext < q:
          var k = min(q, n - 1) - 1
          while k >= atNext:
            if ord(src[k]) == 64:
              let after = c0(k + 1)
              if after != 123 and after != 34:
                runAt = k
                break
            dec k
      if runAt > p:
        emit(T_LINK_ID, p, runAt + 1)
        return true

    if c >= 48 and c <= 57:
      var q = p + 1
      while q < n:
        let ch = ord(src[q])
        if ch < 48 or ch > 57: break
        inc q
      emit(T_NUM, p, q)
      return true

    case c
    of 35:
      emit(T_BRKT, p, p + 1)
      return true
    of 58:
      if c0(p + 1) == 58 and c0(p + 2) == 58: emit(T_STYLE_SEPARATOR, p, p + 3)
      else: emit(T_COLON, p, p + 1)
      return true
    of 38:
      emit(T_AMP, p, p + 1)
      return true
    of 59:
      emit(T_SEMI, p, p + 1)
      return true
    of 44:
      emit(T_COMMA, p, p + 1)
      return true
    of 42:
      emit(T_MULT, p, p + 1)
      return true
    of 120, 111:
      return link(c) or nodeString()
    of 60:
      if link(c): return true
      emit(T_TAGSTART, p, p + 1)
      return true
    of 45:
      if link(c) or nodeString(): return true
      emit(T_MINUS, p, p + 1)
      return true
    of 61:
      return link(c)
    of 46:
      return link(c) or nodeString()
    of 126:
      return invisLink()
    of 40:
      return opener(c)
    of 91:
      if c0(p + 1) == 124:
        emit(T_VERTEX_WITH_PROPS_START, p, p + 2)
        return true
      return opener(c)
    of 124, 123:
      return opener(c)
    of 62:
      push(S_text)
      emit(T_TAGEND, p, p + 1)
      return true
    of 94:
      emit(T_UP, p, p + 1)
      return true
    of 92:
      if c0(p + 1) == 124:
        emit(T_SEP, p, p + 2)
        return true
      return nodeString()
    of 118:
      if not isWord(c0(p + 1)):
        emit(T_DOWN, p, p + 1)
        return true
      return nodeString()
    else: discard

    if isSpace(c):
      if link(c): return true
      e = RE_NEWLINE.matchEnd(src, p)
      if e >= 0:
        emit(T_NEWLINE, p, e)
        return true
      e = RE_SPACE.matchEnd(src, p)
      if e >= 0:
        emit(T_SPACE, p, e)
        return true
      return false

    if c < 128: return nodeString()
    if isUnicodeLetter(c):
      emit(T_UNICODE_TEXT, p, p + charLen(src, p))
      return true
    false

  proc linkAt(kind: int, q: int): int =
    case kind
    of 0: RE_LINK.matchEnd(src, q)
    of 1: RE_THICK_LINK.matchEnd(src, q)
    else: RE_DOTTED_LINK.matchEnd(src, q)

  proc edgeText(c: int, linkRe: int, a, b: int): bool =
    if c == 34:
      quote()
      return true
    let d = linkChar(p)
    if d == a or d == b:
      let e = linkAt(linkRe, p)
      if e >= 0:
        pop()
        emit(T_LINK, p, e)
        return true
    if c == a and (a != 45 or c0(p + 1) == 45): return false
    var q = p + 1
    while q < n:
      let ch = c0(q)
      if ch == 34: break
      if ch == a:
        if a != 45 or c0(q + 1) == 45: break
      elif ch == 120 or ch == 111 or ch == 60 or ch == b or isSpace(ch):
        let dd = linkChar(q)
        if (dd == a or dd == b) and linkAt(linkRe, q) >= 0: break
      inc q
    emit(T_EDGE_TEXT, p, q)
    true

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
      if kind != -1: emit(kind, n, n)
      break

    let c = c0(p)
    var ok = true

    case state
    of S_INITIAL:
      ok = initial(c)

    of S_string:
      if c == 34:
        if c0(p + 1) == 96:
          push(S_md_string)
          p += 2
        else:
          pop()
          inc p
      else:
        let e = src.find('"', p)
        emit(T_STR, p, if e == -1: n else: e)

    of S_md_string:
      if c == 96:
        if c0(p + 1) == 34:
          pop()
          p += 2
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
        emit(T_MD_STR, p, q)

    of S_acc_title, S_acc_descr:
      var e = src.find('\n', p)
      if e == -1: e = n
      let kind = if state == S_acc_title: T_acc_title_value else: T_acc_descr_value
      pop()
      emit(kind, p, e)

    of S_acc_descr_multiline:
      if c == 125:
        pop()
        inc p
      else:
        var e = src.find('}', p)
        if e == -1: e = n
        emit(T_acc_descr_multiline_value, p, e)

    of S_dir:
      var e: int
      if c == 34:
        quote()
      elif (e = RE_NODIR.matchEnd(src, p); e >= 0):
        pop()
        emit(T_NODIR, p, e)
      elif (e = RE_DIR.matchEnd(src, p); e >= 0) or (e = RE_DIR_SYM.matchEnd(src, p); e >= 0) or (e = RE_DIR_V.matchEnd(src, p); e >= 0):
        pop()
        emit(T_DIR, p, e)
      else:
        ok = invisLink() or opener(c)

    of S_text:
      let d = c0(p + 1)
      case c
      of 34:
        quote()
      of 40, 91, 123:
        discard opener(c)
      of 93:
        pop()
        if d == 41: emit(T_STADIUMEND, p, p + 2)
        elif d == 93: emit(T_SUBROUTINEEND, p, p + 2)
        else: emit(T_SQE, p, p + 1)
      of 41:
        pop()
        if d == 93: emit(T_CYLINDEREND, p, p + 2)
        elif d == 41 and c0(p + 2) == 41: emit(T_DOUBLECIRCLEEND, p, p + 3)
        else: emit(T_PE, p, p + 1)
      of 124:
        pop()
        emit(T_PIPE, p, p + 1)
      of 125:
        pop()
        emit(T_DIAMOND_STOP, p, p + 1)
      else:
        if (c == 126 or isSpace(c)) and invisLink(): discard
        else:
          var q = p + 1
          while q < n:
            let ch = ord(src[q])
            if ch == 91 or ch == 93 or ch == 40 or ch == 41 or ch == 123 or ch == 125 or ch == 124 or ch == 34:
              break
            inc q
          emit(T_TEXT, p, q)

    of S_ellipseText:
      let d = c0(p + 1)
      if c == 34:
        quote()
      elif (c == 126 or isSpace(c)) and invisLink():
        discard
      elif (c == 45 or c == 47 or c == 41) and d == 41:
        pop()
        emit(T_ELLIPSE_END, p, p + 2)
      elif c == 40 or c == 91 or c == 123:
        discard opener(c)
      elif c == 41 or c == 93 or c == 125:
        ok = false
      else:
        var q = p + 1
        while q < n:
          let ch = c0(q)
          if ch == 34 or ch == 40 or ch == 41 or ch == 91 or ch == 93 or ch == 123 or ch == 125: break
          if (ch == 45 or ch == 47) and c0(q + 1) == 41: break
          if (ch == 126 or isSpace(ch)) and invisAhead(q) and RE_INVIS_LINK.matchEnd(src, q) >= 0: break
          inc q
        emit(T_TEXT, p, q)

    of S_trapText:
      block trap:
        let d = c0(p + 1)
        if c == 34:
          quote()
          break trap
        if (c == 126 or isSpace(c)) and invisLink(): break trap
        case c
        of 40:
          if d == 45 or d == 91 or (d == 40 and c0(p + 2) == 40):
            discard opener(c)
          elif d == 93:
            pop()
            emit(T_TRAPEND, p, p + 2)
          else:
            discard opener(c)
        of 91, 123:
          discard opener(c)
        of 92:
          if d == 93:
            pop()
            emit(T_TRAPEND, p, p + 2)
          else:
            emit(T_TEXT, p, p + 1)
        of 47:
          if d == 93:
            pop()
            emit(T_INVTRAPEND, p, p + 2)
          else:
            emit(T_TEXT, p, p + 1)
        of 93, 41:
          if d == 93:
            pop()
            emit(T_TRAPEND, p, p + 2)
          else:
            ok = false
        of 125:
          ok = false
        else:
          if (c == 63 or c == 61) and d == 93:
            pop()
            emit(T_TRAPEND, p, p + 2)
            break trap
          var q = p + 1
          while q < n:
            let ch = ord(src[q])
            if ch == 92 or ch == 91 or ch == 93 or ch == 40 or ch == 41 or ch == 123 or ch == 125 or ch == 47:
              break
            inc q
          emit(T_TEXT, p, q)

    of S_edgeText:
      ok = edgeText(c, 0, 45, -1)
    of S_thickEdgeText:
      ok = edgeText(c, 1, 61, -1)
    of S_dottedEdgeText:
      ok = edgeText(c, 2, 46, 45)

    of S_click:
      if c == 34:
        quote()
      elif isSpace(c):
        pop()
        p += charLen(src, p)
      else:
        var q = p + 1
        while q < n and not isSpace(c0(q)): q += charLen(src, q)
        emit(T_CLICK, p, q)

    of S_callbackname:
      if c == 40:
        let e = RE_EMPTY_CALL.matchEnd(src, p)
        pop()
        if e >= 0:
          p = e
        else:
          push(S_callbackargs)
          inc p
      else:
        var e = src.find('(', p)
        if e == -1: e = n
        emit(T_CALLBACKNAME, p, e)

    of S_callbackargs:
      if c == 41:
        pop()
        inc p
      else:
        var e = src.find(')', p)
        if e == -1: e = n
        emit(T_CALLBACKARGS, p, e)

    of S_shapeData:
      if c == 34:
        push(S_shapeDataStr)
        emit(T_SHAPE_DATA, p, p + 1)
      elif c == 125:
        pop()
        inc p
      elif c == 94:
        ok = false
      else:
        var q = p + 1
        while q < n:
          let ch = ord(src[q])
          if ch == 125 or ch == 94 or ch == 34: break
          inc q
        emit(T_SHAPE_DATA, p, q)

    of S_shapeDataStr:
      if c == 34:
        pop()
        emit(T_SHAPE_DATA, p, p + 1)
      else:
        var e = src.find('"', p)
        if e == -1: e = n
        types.add T_SHAPE_DATA
        texts.add src[p ..< e].replace(RE_BR, "<br/>")
        starts.add p
        p = e
    else: discard

    if not ok:
      types.add T_ERROR
      texts.add ""
      starts.add p
      return Tokens(types: types, texts: texts, starts: starts)

  types.add T_STOP
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)

## port-of: src/diagrams/block/lexer.ts
## port-status: conformant
##
## Positions are byte offsets. `charCodeAt` becomes `cu`, which reads the character at a byte
## offset (-1 past the end, as NaN is nothing); a step past a whitespace character takes its bytes.
import std/strutils
import ../../js
import ../../util/chars
import tokens

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

const
  # const enum S
  S_INITIAL = 0
  S_string = 1
  S_md_string = 2
  S_NODE = 3
  S_BLOCK_ARROW = 4
  S_ARROW_DIR = 5
  S_LLABEL = 6
  S_CLASSDEF = 7
  S_CLASSDEFID = 8
  S_CLASS = 9
  S_CLASS_STYLE = 10
  S_STYLE_STMNT = 11
  S_STYLE_DEFINITION = 12
  S_acc_title = 13
  S_acc_descr = 14
  S_acc_descr_multiline = 15

  DIRECTIONS = ["right", "left", "x", "y", "up", "down"]
  # Characters that end a node id: ( ) [ { } < > - : = and whitespace.
  ID_STOP = {'\t', '\n', '\v', '\f', '\r', ' ', '(', ')', '-', ':', '<', '=', '>', '[', '{', '}'}

func cu(src: string, i: int): int =
  ## charCodeAt: the character at byte i (a character past U+FFFF reads as its high surrogate).
  if i < 0 or i >= src.len: return -1
  let cp = codePointAt(src, i).rune
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func sizeAt(src: string, i: int): int =
  if i >= src.len: 1 else: codePointAt(src, i).size

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0

  proc put(typ: int, text: string, stop: int): bool =
    types.add typ
    texts.add text
    starts.add p
    p = stop
    true
  proc emit(typ: int, stop: int): bool = put(typ, src[p ..< stop], stop)
  proc push(s: int) =
    stack.add state
    state = s
  proc pop() =
    if stack.len > 0: state = stack.pop()
  proc ws(q0: int): int =
    var q = q0
    while q < n and isSpace(cu(src, q)): q += sizeAt(src, q)
    q
  proc digits(q0: int): int =
    var q = q0
    while q < n and src[q] in {'0'..'9'}: inc q
    q
  proc word(q0: int): int =
    var q = q0
    while q < n and isWord(cu(src, q)): inc q
    q
  proc keyword(text: string): bool =
    src.continuesWith(text, p) and not isWord(cu(src, p + text.len))

  proc quote(): bool =
    if cu(src, p + 1) == 96:
      push(S_md_string)
      p += 2
    else:
      push(S_string)
      inc p
    true

  proc dotted(q0: int): int =
    ## End of `.+-[xo>]?` at q, or -1.
    var q = q0
    if cu(src, q) != 46: return -1
    inc q
    while cu(src, q) == 46: inc q
    if cu(src, q) != 45: return -1
    let c = cu(src, q + 1)
    if c == 120 or c == 111 or c == 62: q + 2 else: q + 1

  proc linkEnd(q0: int): int =
    ## End of a complete link at q, before its trailing whitespace, or -1.
    var q = q0
    let c = cu(src, q)
    if c == 120 or c == 111 or c == 60: inc q
    let line = cu(src, q)
    if line == 46: return dotted(q)
    if line != 45 and line != 61: return -1
    var k = q + 1
    while cu(src, k) == line: inc k
    if k - q == 1: return (if line == 45: dotted(k) else: -1)
    let head = cu(src, k)
    if head == 120 or head == 111 or head == 62: return k + 1
    if k - q >= 3: k else: -1

  proc link(): bool =
    let e = linkEnd(p)
    if e >= 0: return emit(T_LINK, ws(e))
    let q = if cu(src, p) == 60: p + 1 else: p
    let a = cu(src, q)
    let b = cu(src, q + 1)
    if (a == 45 and (b == 45 or b == 46)) or (a == 61 and b == 61):
      push(S_LLABEL)
      return emit(T_START_LINK, ws(q + 2))
    false

  proc lineState(typ: int): bool =
    var e = src.find('\n', p)
    if e == -1: e = n
    pop()
    emit(typ, e)

  proc idList(typ: int, next: int): bool =
    ## `\w+(,\s*\w+)*`
    var k = word(p)
    if k == p: return false
    while cu(src, k) == 44:
      let start = ws(k + 1)
      let stop = word(start)
      if stop == start: break
      k = stop
    state = next
    emit(typ, k)

  proc initial(c: int): bool =
    if isSpace(c):
      p = ws(p + sizeAt(src, p))
      return true
    var q: int
    case c
    of 98:
      if src.continuesWith("block", p):
        if keyword("block-beta"): return emit(T_KEY, p + 10)
        if cu(src, p + 5) == 58: return emit(T_ID_BLOCK, p + 6)
        if not isWord(cu(src, p + 5)): return emit(T_KEY, p + 5)
    of 99:
      if src.continuesWith("columns", p):
        q = ws(p + 7)
        if q > p + 7:
          if src.continuesWith("auto", q) and not isWord(cu(src, q + 4)): return put(T_COLUMNS, "-1", q + 4)
          let e = digits(q)
          if e > q: return put(T_COLUMNS, src[q ..< e], e)
      elif src.continuesWith("class", p):
        let def = src.continuesWith("Def", p + 5)
        let start = if def: p + 8 else: p + 5
        q = ws(start)
        if q > start:
          push(if def: S_CLASSDEF else: S_CLASS)
          return emit((if def: T_CLASSDEF else: T_CLASS), q)
    of 34:
      return quote()
    of 115:
      if src.continuesWith("space", p):
        if cu(src, p + 5) == 58:
          let e = digits(p + 6)
          if e > p + 6: return put(T_SPACE_BLOCK, src[p + 6 ..< e], e)
        if not isWord(cu(src, p + 5)): return put(T_SPACE_BLOCK, "1", p + 5)
      elif src.continuesWith("style", p):
        q = ws(p + 5)
        if q > p + 5:
          push(S_STYLE_STMNT)
          return emit(T_STYLE, q)
    of 100:
      if keyword("default"): return emit(T_DEFAULT, p + 7)
    of 108:
      if keyword("linkStyle"): return emit(T_LINKSTYLE, p + 9)
    of 105:
      if keyword("interpolate"): return emit(T_INTERPOLATE, p + 11)
    of 97:
      if src.continuesWith("accTitle", p):
        q = ws(p + 8)
        if cu(src, q) == 58:
          push(S_acc_title)
          return emit(T_acc_title, ws(q + 1))
      elif src.continuesWith("accDescr", p):
        q = ws(p + 8)
        let d = cu(src, q)
        if d == 58:
          push(S_acc_descr)
          return emit(T_acc_descr, ws(q + 1))
        if d == 123:
          push(S_acc_descr_multiline)
          p = ws(q + 1)
          return true
    of 101:
      if keyword("end"): return emit(T_end, ws(p + 3))
    of 45:
      if cu(src, p + 1) == 41:
        push(S_NODE)
        return emit(T_NODE_DSTART, p + 2)
      return link()
    of 61:
      return link()
    of 60:
      if cu(src, p + 1) == 91:
        push(S_BLOCK_ARROW)
        return emit(T_BLOCK_ARROW_START, p + 2)
      return link()
    of 40:
      let d = cu(src, p + 1)
      let len = if d == 45 or d == 91: 2 elif d == 40: (if cu(src, p + 2) == 40: 3 else: 2) else: 1
      push(S_NODE)
      return emit(T_NODE_DSTART, p + len)
    of 41, 123:
      push(S_NODE)
      return emit(T_NODE_DSTART, if cu(src, p + 1) == c: p + 2 else: p + 1)
    of 62:
      push(S_NODE)
      return emit(T_NODE_DSTART, p + 1)
    of 91:
      let d = cu(src, p + 1)
      push(S_NODE)
      return emit(T_NODE_DSTART,
        if d == 91 or d == 124 or d == 40 or d == 92 or d == 47: p + 2 else: p + 1)
    of 58:
      let e = digits(p + 1)
      if e > p + 1: return put(T_SIZE, src[p + 1 ..< e], e)
      return false
    else: discard

    q = p
    while q < n:
      if src[q] < '\x80':
        if src[q] in ID_STOP: break
        inc q
      else:
        if isSpace(cu(src, q)): break
        q += sizeAt(src, q)
    q > p and emit(T_NODE_ID, q)

  proc nodeEnd(c: int): bool =
    let d = cu(src, p + 1)
    var len = 0
    case c
    of 34: return quote()
    of 40: len = if d == 45: 2 elif d == 40: (if cu(src, p + 2) == 40: 3 else: 2) else: 1
    of 41: len = if d == 41: (if cu(src, p + 2) == 41: 3 else: 2) elif d == 93: 2 else: 1
    of 125: len = if d == 125: 2 else: 1
    of 45: len = if d == 41: 2 else: 0
    of 93: len = if d == 93 or d == 41 or d == 62: 2 else: 1
    of 92, 47: len = if d == 93: 2 else: 0
    else: discard
    if len == 0: return false
    pop()
    emit(T_NODE_DEND, p + len)

  proc arrowDir(c: int): bool =
    if c == 41:
      pop()
      pop()
      return put(T_BLOCK_ARROW_END, "]>", ws(p + 1))
    let start = ws(if c == 44: p + 1 else: p)
    for dir in DIRECTIONS:
      if src.continuesWith(dir, start):
        let e = ws(start + dir.len)
        return put(T_DIR, src[(if c == 44: start else: p) ..< e], e)
    false

  while true:
    if p >= n:
      let typ = case state
        of S_INITIAL: T_EOF
        of S_string: T_STR
        of S_CLASSDEFID: T_CLASSDEF_STYLEOPTS
        of S_CLASS_STYLE: T_STYLECLASS
        of S_STYLE_DEFINITION: T_STYLE_DEFINITION_DATA
        of S_acc_title: T_acc_title_value
        of S_acc_descr: T_acc_descr_value
        of S_acc_descr_multiline: T_acc_descr_multiline_value
        else: -1
      p = n
      if typ != -1: discard put(typ, "", n)
      break

    let c = cu(src, p)
    var ok = true

    case state
    of S_INITIAL:
      ok = initial(c)
    of S_string:
      if c == 34:
        pop()
        inc p
      else:
        let e = src.find('"', p)
        discard emit(T_STR, if e == -1: n else: e)
    of S_md_string:
      if c == 96:
        ok = cu(src, p + 1) == 34
        if ok:
          pop()
          p += 2
      elif c == 34:
        ok = false
      else:
        var q = p + 1
        while q < n and src[q] notin {'`', '"'}: inc q
        discard emit(T_MD_STR, q)
    of S_NODE:
      ok = nodeEnd(c)
    of S_BLOCK_ARROW:
      if c == 34:
        discard quote()
      elif c == 93 and cu(src, p + 1) == 62:
        let q = ws(p + 2)
        ok = cu(src, q) == 40
        if ok:
          push(S_ARROW_DIR)
          p = q + 1
      else:
        ok = false
    of S_ARROW_DIR:
      ok = arrowDir(c)
    of S_LLABEL:
      if c == 34:
        if cu(src, p + 1) == 96:
          discard quote()
        else:
          discard emit(T_LINK_LABEL, p + 1)
          push(S_string)
      else:
        let e = linkEnd(ws(p))
        ok = e >= 0
        if ok:
          pop()
          discard emit(T_LINK, ws(e))
    of S_CLASSDEF:
      var typ = T_DEFAULT_CLASSDEF_ID
      var k = if src.continuesWith("DEFAULT", p): p + 7 else: p
      var q = ws(k)
      if k == p or q == k:
        typ = T_CLASSDEF_ID
        k = word(p)
        q = ws(k)
      ok = k > p and q > k
      if ok:
        state = S_CLASSDEFID
        discard emit(typ, q)
    of S_CLASSDEFID:
      discard lineState(T_CLASSDEF_STYLEOPTS)
    of S_CLASS:
      ok = idList(T_CLASSENTITY_IDS, S_CLASS_STYLE)
    of S_CLASS_STYLE:
      discard lineState(T_STYLECLASS)
    of S_STYLE_STMNT:
      ok = idList(T_STYLE_ENTITY_IDS, S_STYLE_DEFINITION)
    of S_STYLE_DEFINITION:
      discard lineState(T_STYLE_DEFINITION_DATA)
    of S_acc_title:
      discard lineState(T_acc_title_value)
    of S_acc_descr:
      discard lineState(T_acc_descr_value)
    else:
      if c == 125:
        pop()
        inc p
      else:
        let e = src.find('}', p)
        discard emit(T_acc_descr_multiline_value, if e == -1: n else: e)

    if not ok:
      types.add T_ERROR
      texts.add ""
      starts.add p
      return Tokens(types: types, texts: texts, starts: starts)

  types.add T_STOP
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)

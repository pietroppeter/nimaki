## port-of: src/diagrams/common/outline.ts
## port-status: draft
##
## The indented outline grammar that Mermaid's mindmap and kanban diagrams share.
## Kanban adds `@{ ... }` metadata after a node and keeps `@` out of node ids.
import std/strutils
import ../../errors
import ../../js
import ../../util/chars
import scan

export Tokens

const
  # const enum T
  T_STOP* = 0          ## T.END (`T_end` would be the same name as `T_END` in Nim)
  T_ERROR* = 1
  T_SPACELINE* = 2
  T_NL* = 3
  T_EOF* = 4
  T_KEYWORD* = 5
  T_SPACELIST* = 6
  T_ICON* = 7
  T_CLASS* = 8
  T_NODE_DSTART* = 9
  T_NODE_ID* = 10
  T_NODE_DESCR* = 11
  T_NODE_DEND* = 12
  T_SHAPE_DATA* = 13

const NAMES = [
  # As the generated parser prints them. It has no name for the end of input and prints its number.
  "1", "INVALID", "SPACELINE", "NL", "EOF", "", "SPACELIST", "ICON", "CLASS", "NODE_DSTART",
  "NODE_ID", "NODE_DESCR", "NODE_DEND", "SHAPE_DATA"]

func tokenName*(kind: int, kanban: bool): string =
  if kind == T_KEYWORD: (if kanban: "KANBAN" else: "MINDMAP") else: NAMES[kind]

const
  # NODE_TYPE
  NODE_TYPE_DEFAULT* = 0
  NODE_TYPE_NO_BORDER* = 0
  NODE_TYPE_ROUNDED_RECT* = 1
  NODE_TYPE_RECT* = 2
  NODE_TYPE_CIRCLE* = 3
  NODE_TYPE_CLOUD* = 4
  NODE_TYPE_BANG* = 5
  NODE_TYPE_HEXAGON* = 6

func getType*(start, stop: string): int =
  ## Any opening delimiter pairs with any closing one, as in Mermaid.
  case start
  of "[": NODE_TYPE_RECT
  of "(": (if stop == ")": NODE_TYPE_ROUNDED_RECT else: NODE_TYPE_CLOUD)
  of "((": NODE_TYPE_CIRCLE
  of ")": NODE_TYPE_CLOUD
  of "))": NODE_TYPE_BANG
  of "{{": NODE_TYPE_HEXAGON
  else: NODE_TYPE_DEFAULT

const
  # const enum S
  S_INITIAL = 0
  S_CLASS = 1
  S_ICON = 2
  S_NODE = 3
  S_NSTR = 4
  S_NSTR2 = 5
  S_DATA = 6
  S_DATA_STR {.used.} = 7

func code(src: string, i: int): int = (if i >= 0 and i < src.len: ord(src[i]) else: -1)

func spaceEnd(src: string, p: int): int =
  ## RE_SPACE: /\s+/y, where it ends, or -1.
  var i = p
  while true:
    let n = spaceLenAt(src, i)
    if n == 0: break
    i += n
  if i > p: i else: -1

func lineEndAt(src: string, p: int): int =
  ## RE_LINE: /.+/y, where it ends, or -1. `.` is any character but \n, \r, U+2028 and U+2029.
  var i = p
  while i < src.len:
    let c = src[i]
    if c == '\n' or c == '\r': break
    if c == '\xE2' and i + 2 < src.len and src[i + 1] == '\x80' and src[i + 2] in {'\xA8', '\xA9'}: break
    inc i
  if i > p: i else: -1

func runNotOf(src: string, p: int, stops: set[char]): int =
  ## /[^stops]+/y, for stops in ASCII, where it ends, or -1.
  var i = p
  while i < src.len and src[i] notin stops: inc i
  if i > p: i else: -1

func letters(src: string, p: int, word: string): bool =
  ## Jison's case-insensitive flag folds ASCII letters only.
  for k in 0 ..< word.len:
    if (code(src, p + k) or 32) != ord(word[k]): return false
  true

func replaceBreaks(s: string): string =
  ## s.replace(/\n\s*/g, '<br/>')
  var i = 0
  while i < s.len:
    if s[i] == '\n':
      result.add "<br/>"
      inc i
      while true:
        let n = spaceLenAt(s, i)
        if n == 0: break
        i += n
    else:
      result.add s[i]
      inc i

proc tokenize*(src: string, kanban: bool): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  let keyword = if kanban: "kanban" else: "mindmap"
  let idStops = if kanban: {'(', '[', '\n', ')', '{', '}', '@'} else: {'(', '[', '\n', ')', '{', '}'}
  var state = S_INITIAL
  var p = 0
  var nextBreak = -1

  template put(kind: int, text: string, stop: int) =
    types.add kind
    texts.add text
    starts.add p
    p = stop
  template emit(kind: int, stop: int, next: int) =
    let e = stop
    put(kind, src[p ..< e], e)
    state = next
  template upTo(ch: char): int =
    (let e = src.find(ch, p); if e == -1: n else: e)

  while p < n:
    let c = code(src, p)
    let d = code(src, p + 1)
    var e: int
    if state == S_INITIAL:
      let w = max(spaceEnd(src, p), p)
      if kanban and c == 64 and d == 123:
        put(T_SHAPE_DATA, "", p + 2)
        state = S_DATA
      elif code(src, w) == 37 and code(src, w + 1) == 37:
        emit(T_SPACELINE, lineEndAt(src, w), S_INITIAL)
      elif w > p:
        if nextBreak < p: nextBreak = upTo('\n')
        if nextBreak >= w: emit(T_SPACELIST, w, S_INITIAL)
        else:
          e = src.rfind('\n', last = w - 1)
          if e > p: emit(T_SPACELINE, e + 1, S_INITIAL)
          else: emit(T_NL, p + 1, S_INITIAL)
      elif letters(src, p, keyword) and not isWord(code(src, p + keyword.len)):
        emit(T_KEYWORD, p + keyword.len, S_INITIAL)
      elif c == 58 and d == 58 and code(src, p + 2) == 58:
        p += 3
        state = S_CLASS
      elif c == 58 and d == 58 and letters(src, p + 2, "icon") and code(src, p + 6) == 40:
        p += 7
        state = S_ICON
      elif (c == 45 and d == 41) or (c == 40 and (d == 45 or d == 40)) or ((c == 41 or c == 123) and d == c):
        emit(T_NODE_DSTART, p + 2, S_NODE)
      elif c == 41 or c == 40 or c == 91:
        emit(T_NODE_DSTART, p + 1, S_NODE)
      else:
        e = runNotOf(src, p, idStops)
        if e != -1: emit(T_NODE_ID, e, S_INITIAL)
        else: break
    elif state == S_NODE:
      if c == 34:
        state = if d == 96: S_NSTR2 else: S_NSTR
        p += (if d == 96: 2 else: 1)
      elif c == 41 or c == 40:
        emit(T_NODE_DEND, (if d == c or (c == 40 and d == 45): p + 2 else: p + 1), S_INITIAL)
      elif c == 93:
        emit(T_NODE_DEND, p + 1, S_INITIAL)
      elif (c == 125 and d == 125) or (c == 45 and d == 41):
        emit(T_NODE_DEND, p + 2, S_INITIAL)
      else:
        # A lone closing brace takes the rest of its line as text.
        emit(T_NODE_DESCR, (if c == 125: lineEndAt(src, p) else: runNotOf(src, p, {')', ']', '(', '}'})), S_NODE)
    elif state == S_NSTR:
      if c == 34:
        inc p
        state = S_NODE
      else:
        emit(T_NODE_DESCR, upTo('"'), S_NSTR)
    elif state == S_NSTR2:
      if c == 96 and d == 34:
        p += 2
        state = S_NODE
      else:
        e = runNotOf(src, p, {'`', '"'})
        if e != -1: emit(T_NODE_DESCR, e, S_NSTR2)
        else: break
    elif state == S_CLASS:
      e = lineEndAt(src, p)
      if e != -1: emit(T_CLASS, e, S_INITIAL)
      elif c == 10:
        inc p
        state = S_INITIAL
      else: break
    elif state == S_ICON:
      if c == 41:
        inc p
        state = S_INITIAL
      else:
        emit(T_ICON, upTo(')'), S_ICON)
    elif state == S_DATA:
      if c == 34:
        emit(T_SHAPE_DATA, p + 1, S_DATA_STR)
      elif c == 125:
        inc p
        state = S_INITIAL
      else:
        e = runNotOf(src, p, {'}', '^', '"'})
        if e != -1: emit(T_SHAPE_DATA, e, S_DATA)
        else: break
    elif c == 34:
      emit(T_SHAPE_DATA, p + 1, S_DATA)
    else:
      e = upTo('"')
      put(T_SHAPE_DATA, replaceBreaks(src[p ..< e]), e)

  if p < n:
    put(T_ERROR, "", p)
  else:
    if state == S_INITIAL: put(T_EOF, "", n)
    put(T_STOP, "", n)
  Tokens(types: types, texts: texts, starts: starts)

const STOP = "'SPACELINE', 'NL', 'EOF'"

func isStart(kind: int): bool =
  kind in [T_SPACELINE, T_SPACELIST, T_ICON, T_CLASS, T_NODE_DSTART, T_NODE_ID]

func isStop(kind: int): bool = kind == T_SPACELINE or kind == T_NL or kind == T_EOF

type
  OutlineNode* = object
    ## What `addNode` receives.
    level*: int
    id*, descr*: string
    kind*: int
    hasShapeData*: bool
    shapeData*: string

  Decoration* = object
    icon*, class*: string   ## "" for undefined

proc parseOutline*(src: string, kanban: bool, addNode: proc (node: OutlineNode),
                   decorateNode: proc (decoration: Decoration)) =
  ## Makes the calls on the db that the grammar's actions make, in the same order, and reports
  ## errors in the state where the generated parser would.
  let diagram = if kanban: "kanban" else: "mindmap"
  let tokens = tokenize(src, kanban)
  let (types, texts, starts) = (tokens.types, tokens.texts, tokens.starts)
  let data = if kanban: ", 'SHAPE_DATA'" else: ""
  var i = 0

  proc fail(expected: string) {.noreturn.} =
    let t = types[i]
    if t == T_ERROR: raise syntaxError(diagram, src, starts[i], "", true)
    raise syntaxError(diagram, src, starts[i], "Expecting " & expected & ", got '" & tokenName(t, kanban) & "'")

  let keyword = "'" & tokenName(T_KEYWORD, kanban) & "'"
  if types[i] == T_SPACELINE:
    inc i
    while types[i] == T_SPACELINE or types[i] == T_NL: inc i
    if types[i] != T_KEYWORD: fail("'SPACELINE', 'NL', " & keyword)
  elif types[i] != T_KEYWORD:
    fail("'SPACELINE', " & keyword)
  inc i
  var first = "'SPACELINE', 'NL', 'SPACELIST', 'ICON', 'CLASS', 'NODE_DSTART', 'NODE_ID'"
  if types[i] == T_NL:
    inc i
    first = "'SPACELINE', 'SPACELIST', 'ICON', 'CLASS', 'NODE_DSTART', 'NODE_ID'"

  while true:
    var t = types[i]
    var level = 0
    let indented = t == T_SPACELIST
    if indented:
      level = utf16Len(texts[i])
      inc i
      t = types[i]
    if t == T_NODE_ID or t == T_NODE_DSTART:
      var id = ""
      var hasId = false
      var descr: string
      var kind = 0
      if t == T_NODE_ID:
        id = texts[i]
        hasId = true
        inc i
      if types[i] == T_NODE_DSTART:
        let start = texts[i]
        inc i
        if types[i] != T_NODE_DESCR: fail("'NODE_DESCR'")
        descr = texts[i]
        inc i
        if types[i] != T_NODE_DEND: fail("'NODE_DEND'")
        let stop = texts[i]
        inc i
        if not isStop(types[i]) and types[i] != T_SHAPE_DATA: fail(STOP & data)
        kind = getType(start, stop)
      else:
        if not isStop(types[i]) and types[i] != T_SHAPE_DATA: fail(STOP & ", 'NODE_DSTART'" & data)
        descr = id
      var node = OutlineNode(level: level, id: (if hasId: id else: descr), descr: descr, kind: kind)
      if types[i] == T_SHAPE_DATA:
        var shapeData = texts[i]
        inc i
        while types[i] == T_SHAPE_DATA:
          shapeData.add texts[i]
          inc i
        if not isStop(types[i]): fail(STOP & data)
        node.hasShapeData = true
        node.shapeData = shapeData
      addNode(node)
    elif t == T_ICON or t == T_CLASS:
      let text = texts[i]
      inc i
      if not isStop(types[i]): fail(STOP)
      decorateNode(if t == T_ICON: Decoration(icon: text) else: Decoration(class: text))
    elif indented:
      if not isStop(t): fail(STOP & ", 'ICON', 'CLASS', 'NODE_DSTART', 'NODE_ID'")
    elif t == T_SPACELINE:
      inc i
      if not isStop(types[i]): fail(STOP)
    else:
      fail(first)

    inc i
    while types[i] == T_NL or types[i] == T_EOF: inc i
    if types[i] == T_STOP: return
    if not isStart(types[i]): fail(STOP & ", 'SPACELIST', 'ICON', 'CLASS', 'NODE_DSTART', 'NODE_ID'")

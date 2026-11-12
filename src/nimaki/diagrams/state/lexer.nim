## port-of: src/diagrams/state/lexer.ts
## port-status: draft
##
## Positions are byte offsets into the UTF-8 source (decision 0011). `cc(q)` reads the character
## at `q` as `charCodeAt` would where it matters (a whole code point; -1 past the end), and a
## `j++` over a character that may not be ASCII steps over the whole character (`step`). Each
## global regular expression is a search proc with its pattern in a comment.
import std/strutils
import ../../js
import ../../util/chars
import ../common/scan
import tokens

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]
  error*: string
    ## Set when lexing stopped on the grammar's own error rather than on unrecognized text
    ## ("" for undefined).

const
  S_INITIAL = 0
  S_struct = 1
  S_STATE = 2
  S_STATE_STRING = 3
  S_STATE_ID = 4
  S_SCALE = 5
  S_acc_title = 6
  S_acc_descr = 7
  S_acc_descr_multiline = 8
  S_CLASSDEF = 9
  S_CLASSDEFID = 10
  S_CLASS = 11
  S_CLASS_STYLE = 12
  S_STYLE = 13
  S_STYLEDEF_STYLES = 14
  S_NOTE = 15
  S_NOTE_ID = 16
  S_NOTE_TEXT = 17
  S_FLOATING_NOTE = 18
  S_FLOATING_NOTE_ID = 19

func lowerAt(src: string, q: int): int =
  if q < src.len: ord(src[q]) or 32 else: -1

func wordCI(src, w: string, q: int): bool =
  ## Case-insensitive match of a lowercase ASCII word, as the grammar's /i flag gives.
  for i in 0 ..< w.len:
    let a = ord(w[i])
    let c = if q + i < src.len: ord(src[q + i]) else: -1
    if c != a and not (a >= 97 and a <= 122 and c == a - 32): return false
  true

proc searchDirection(src: string, q: int): int =
  ## /direction/gi
  var i = max(q, 0)
  while i + 9 <= src.len:
    if lowerAt(src, i) == ord('d') and wordCI(src, "direction", i): return i
    inc i
  -1

proc searchStereotype(src: string, q: int): int =
  ## /<<(?:fork|join|choice)>>|\[\[(?:fork|join|choice)\]\]/gi
  var i = max(q, 0)
  while i < src.len:
    let c = src[i]
    if (c == '<' or c == '[') and i + 1 < src.len and src[i + 1] == c:
      let close = if c == '<': ">>" else: "]]"
      for w in ["fork", "join", "choice"]:
        if wordCI(src, w, i + 2) and src.continuesWith(close, i + 2 + w.len): return i
    inc i
  -1

proc searchLineEnd(src: string, q: int): int =
  ## /[\n\r  ]/g
  var i = max(q, 0)
  while i < src.len:
    let c = src[i]
    if c == '\n' or c == '\r': return i
    if c == '\xE2' and i + 2 < src.len and src[i + 1] == '\x80' and (src[i + 2] == '\xA8' or src[i + 2] == '\xA9'):
      return i
    inc i
  -1

proc searchPercent(src: string, q: int): int =
  ## /%%/g
  let at = src.find("%%", max(q, 0))
  at

proc searchBrace(src: string, q: int): int =
  ## /\{/g
  src.find('{', max(q, 0))

# Finds the next match of a pattern at or after a position, remembering the answer so that
# asking at each token costs one scan of the text in total.
proc finder(search: proc (src: string, q: int): int, src: string): proc (q: int): int =
  var start = 0
  var next = -2
  result = proc (q: int): int =
    if next == -2 or q < start or (next != -1 and q > next):
      next = search(src, q)
      start = q
    next

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0
  var error = ""

  let nextDirection = finder(searchDirection, src)
  let nextStereotype = finder(searchStereotype, src)
  let nextLineEnd = finder(searchLineEnd, src)
  let nextPercent = finder(searchPercent, src)
  let nextBrace = finder(searchBrace, src)

  # The last `direction <dir>` of each kind on the line being lexed, and where its keyword ends.
  var dirFrom = -1
  var dirTo = -1
  var dirAt = [-1, -1, -1, -1]
  var dirEnd = [0, 0, 0, 0]
  # The same for <<fork>>, <<join>>, <<choice>> and their [[ ]] spellings.
  var stereoFrom = -1
  var stereoTo = -1
  var stereoAt = [-1, -1, -1, -1, -1, -1]

  template cc(q: int): int = codeAt(src, q)
  template step(q: int): int = q + sizeAt(src, q)

  proc emit(t: int, s, e: int) =
    types.add t
    texts.add src[s ..< e]
    starts.add s
    p = e
  proc emitText(t: int, text: string, s, e: int) =
    types.add t
    texts.add text
    starts.add s
    p = e
  proc push(s: int) =
    stack.add state
    state = s
  proc pop() =
    if stack.len > 0: state = stack.pop()
  proc word(w: string, q: int): bool = wordCI(src, w, q)
  proc wsEnd(q: int): int =
    var j = q
    while j < n and isSpace(cc(j)): j = step(j)
    j
  proc wordEnd(q: int): int =
    var j = q
    while j < n and isWord(cc(j)): inc j
    j
  proc eol(q: int): int =
    let k = src.find('\n', q)
    if k == -1: n else: k
  proc lineEnd(q: int): int =
    let k = nextLineEnd(q)
    if k == -1: n else: k

  # Rules `.*direction\s+TB[^\n]*` and its three siblings: the first kind, in grammar order,
  # found between q and the end of its line.
  proc direction(q: int): int =
    if q < dirFrom or q > dirTo:
      let first = nextDirection(q)
      let e = if first == -1: n else: lineEnd(q)
      dirFrom = q
      dirTo = e
      dirAt = [-1, -1, -1, -1]
      var d = first
      while d != -1 and d < e:
        let w = wsEnd(d + 9)
        if w != d + 9:
          let kind = if word("tb", w): 0 elif word("bt", w): 1 elif word("rl", w): 2 elif word("lr", w): 3 else: -1
          if kind != -1:
            dirAt[kind] = d
            dirEnd[kind] = w + 2
        d = nextDirection(d + 1)
    for kind in 0 ..< 4:
      if dirAt[kind] >= q: return kind
    -1

  proc stereotype(q: int): int =
    if q < stereoFrom or q > stereoTo:
      let first = nextStereotype(q)
      let e = if first == -1: n else: lineEnd(q)
      stereoFrom = q
      stereoTo = e
      stereoAt = [-1, -1, -1, -1, -1, -1]
      var d = first
      while d != -1 and d < e:
        let letter = ord(src[d + 2]) or 32
        stereoAt[(if src[d] == '<': 0 else: 3) + (if letter == 102: 0 elif letter == 106: 1 else: 2)] = d
        d = nextStereotype(d + 1)
    for kind in 0 ..< 6:
      if stereoAt[kind] >= q: return kind
    -1

  # The grammar's processId(): an id ends at an inline `%%`, and a text that starts with one is dropped.
  proc emitId(s, e: int): bool =
    let at = nextPercent(s)
    if at == -1 or at + 2 > e:
      emit(T_ID, s, e)
      return true
    if at == s:
      p = e
      return false
    emit(T_ID, s, at)
    true

  proc finish(t: int): Tokens =
    types.add t
    texts.add ""
    starts.add p
    Tokens(types: types, texts: texts, starts: starts, error: error)

  while true:
    if p >= n:
      # Jison tries the current state's rules once more on the empty remainder.
      case state
      of S_INITIAL: emit(T_NL, n, n)
      of S_acc_title: emit(T_acc_title_value, n, n)
      of S_acc_descr: emit(T_acc_descr_value, n, n)
      of S_acc_descr_multiline: emit(T_acc_descr_multiline_value, n, n)
      of S_CLASSDEFID: emit(T_CLASSDEF_STYLEOPTS, n, n)
      of S_CLASS_STYLE: emit(T_STYLECLASS, n, n)
      of S_STYLEDEF_STYLES: emit(T_STYLEDEF_STYLEOPTS, n, n)
      of S_STATE_STRING: emit(T_STATE_DESCR, n, n)
      of S_FLOATING_NOTE: emit(T_NOTE_TEXT, n, n)
      of S_STATE_ID, S_FLOATING_NOTE_ID: emit(T_ID, n, n)
      else: discard
      return finish(T_END)

    let c = cc(p)
    case state
    of S_INITIAL, S_struct:
      let root = state == S_INITIAL
      let lc = c or 32
      block rules:
        if root:
          if lc == 99 and word("click", p) and not isWord(cc(p + 5)):
            emit(T_CLICK, p, p + 5)
            break rules
          if lc == 104 and word("href", p) and not isWord(cc(p + 4)):
            emit(T_HREF, p, p + 4)
            break rules
          if c == 34:
            let close = src.find('"', p + 1)
            if close != -1:
              emit(T_STRING, p, close + 1)
              break rules
          if lc == 100 and word("default", p) and not isWord(cc(p + 7)):
            emit(T_DEFAULT, p, p + 7)
            break rules
          let kind = direction(p)
          if kind != -1:
            emit(T_direction_tb + kind, p, eol(dirEnd[kind]))
            break rules
          if c == 10:
            var j = p + 1
            while cc(j) == 10: inc j
            emit(T_NL, p, j)
            break rules
          if isSpace(c):
            p = wsEnd(p)
            break rules
        elif c != 10 and isSpace(c):
          var j = step(p)
          while j < n and cc(j) != 10 and isSpace(cc(j)): j = step(j)
          p = j
          break rules
        if c == 35 or (c == 37 and cc(p + 1) == 37 and cc(p + 2) != 123):
          p = eol(p)
          break rules
        if lc == 115:
          if root and word("scale", p):
            let e = wsEnd(p + 5)
            if e > p + 5:
              emit(T_scale, p, e)
              push(S_SCALE)
              break rules
          if word("style", p):
            let e = wsEnd(p + 5)
            if e > p + 5:
              emit(T_style, p, e)
              push(S_STYLE)
              break rules
          if word("state", p):
            var e = wsEnd(p + 5)
            if e > p + 5:
              p = e
              push(S_STATE)
              break rules
            if root and word("diagram", p + 5):
              let start = if word("-v2", p + 12): p + 15 else: p + 12
              e = wsEnd(start)
              if e > start:
                emit(T_SD, p, e)
                break rules
        elif lc == 99:
          if word("class", p):
            let def = word("def", p + 5)
            let start = if def: p + 8 else: p + 5
            let e = wsEnd(start)
            if e > start:
              emit(if def: T_classDef else: T_class, p, e)
              push(if def: S_CLASSDEF else: S_CLASS)
              break rules
        elif lc == 97 and root:
          if word("acctitle", p) or word("accdescr", p):
            let title = (cc(p + 3) or 32) == 116
            let q = wsEnd(p + 8)
            let d = cc(q)
            if d == 58:
              emit(if title: T_acc_title else: T_acc_descr, p, wsEnd(q + 1))
              push(if title: S_acc_title else: S_acc_descr)
              break rules
            if d == 123 and not title:
              p = wsEnd(q + 1)
              push(S_acc_descr_multiline)
              break rules
        if root:
          if c == 123:
            emit(T_STRUCT_START, p, p + 1)
            push(S_struct)
            break rules
        else:
          let kind = direction(p)
          if kind != -1:
            emit(T_direction_tb + kind, p, eol(dirEnd[kind]))
            break rules
          if c == 125:
            emit(T_STRUCT_STOP, p, p + 1)
            pop()
            break rules
          if c == 10:
            inc p
            break rules
        if lc == 110 and word("note", p):
          let e = wsEnd(p + 4)
          if e > p + 4:
            emit(T_note, p, e)
            push(S_NOTE)
            break rules
        if root and lc == 104 and word("hide empty description", p) and not isWord(cc(p + 22)):
          emit(T_HIDE_EMPTY, p, p + 22)
          break rules
        if c == 91 and cc(p + 1) == 42 and cc(p + 2) == 93:
          emit(T_EDGE_STATE, p, p + 3)
          break rules
        var j = p
        while j < n:
          let d = cc(j)
          if d == 58 or d == 45 or d == 123 or isSpace(d): break
          j = step(j)
        if j > p:
          discard emitId(p, j)
          break rules
        if c == 58:
          j = p + 1
          while j < n:
            let d = cc(j)
            if d == 10 or d == 59: break
            if d == 58:
              let after = cc(j + 1)
              if j + 1 >= n or after == 58 or after == 10 or after == 59: break
              inc j
            j = step(j)
          if j > p + 1:
            emitText(T_DESCR, src[p ..< j].jsTrim, p, j)
            break rules
          if cc(p + 1) == 58 and cc(p + 2) == 58:
            emit(T_STYLE_SEPARATOR, p, p + 3)
            break rules
        elif c == 45 and cc(p + 1) == 45:
          if cc(p + 2) == 62:
            emit(T_ARROW, p, p + 3)
            break rules
          if not root:
            emit(T_CONCURRENT, p, p + 2)
            break rules
        if not root: return finish(T_ERROR)
        emit(T_INVALID, p, step(p))

    of S_STATE:
      block rules:
        if c != 10 and isSpace(c):
          var j = step(p)
          while j < n and cc(j) != 10 and isSpace(cc(j)): j = step(j)
          p = j
          break rules
        if c == 35 or (c == 37 and cc(p + 1) == 37 and cc(p + 2) != 123):
          p = eol(p)
          break rules
        let kind = stereotype(p)
        if kind != -1:
          let at = stereoAt[kind]
          let choice = kind == 2 or kind == 5
          emitText(if choice: T_CHOICE elif kind mod 3 == 0: T_FORK else: T_JOIN, src[p ..< at].jsTrim, p,
                   at + (if choice: 10 else: 8))
          pop()
          break rules
        if c == 34:
          inc p
          push(S_STATE_STRING)
          break rules
        let q = if c == 10: wsEnd(p) else: p
        if word("as", q):
          let e = wsEnd(q + 2)
          if e > q + 2:
            emit(T_AS, p, e)
            push(S_STATE_ID)
            break rules
        if c == 10:
          inc p
          pop()
          break rules
        if c == 123:
          emit(T_STRUCT_START, p, p + 1)
          pop()
          push(S_struct)
          break rules
        if isWord(c):
          let first = wordEnd(p)
          let second = wsEnd(first)
          if second > first and isWord(cc(second)):
            let brace = nextBrace(second + 1)
            if brace != -1 and brace < lineEnd(second):
              error = "Error: State name must be a single word. Found: \"" & src[p .. brace].jsTrim & "\""
              return finish(T_ERROR)
        var j = step(p)
        while j < n:
          let d = cc(j)
          if d == 123 or isSpace(d): break
          j = step(j)
        emit(T_COMPOSIT_STATE, p, j)

    of S_STATE_STRING:
      if c == 34:
        inc p
        pop()
      else:
        let close = src.find('"', p)
        emit(T_STATE_DESCR, p, if close == -1: n else: close)

    of S_STATE_ID:
      var j = p
      while j < n:
        let d = cc(j)
        if d == 10 or d == 123: break
        j = step(j)
      if emitId(p, j): pop()

    of S_SCALE:
      if c >= 48 and c <= 57:
        var j = p + 1
        while j < n and cc(j) >= 48 and cc(j) <= 57: inc j
        emit(T_WIDTH, p, j)
      else:
        let q = wsEnd(p)
        if q > p and word("width", q) and not isWord(cc(q + 5)):
          p = q + 5
          pop()
        else:
          return finish(T_ERROR)

    of S_acc_title:
      emit(T_acc_title_value, p, eol(p))
      pop()

    of S_acc_descr:
      emit(T_acc_descr_value, p, eol(p))
      pop()

    of S_acc_descr_multiline:
      if c == 125:
        inc p
        pop()
      else:
        let close = src.find('}', p)
        emit(T_acc_descr_multiline_value, p, if close == -1: n else: close)

    of S_CLASSDEF:
      let isDefault = word("default", p) and wsEnd(p + 7) > p + 7
      let j = if isDefault: p + 7 else: wordEnd(p)
      let e = wsEnd(j)
      if j == p or e == j: return finish(T_ERROR)
      emit(if isDefault: T_DEFAULT_CLASSDEF_ID else: T_CLASSDEF_ID, p, e)
      pop()
      push(S_CLASSDEFID)

    of S_CLASSDEFID:
      emit(T_CLASSDEF_STYLEOPTS, p, eol(p))
      pop()

    of S_CLASS:
      var j = wordEnd(p)
      if j == p: return finish(T_ERROR)
      while cc(j) == 44:
        let k = wsEnd(j + 1)
        let e = wordEnd(k)
        if e == k: break
        j = e
      emit(T_CLASSENTITY_IDS, p, j)
      pop()
      push(S_CLASS_STYLE)

    of S_CLASS_STYLE:
      emit(T_STYLECLASS, p, eol(p))
      pop()

    of S_STYLE:
      var j = p
      while j < n and (isWord(cc(j)) or cc(j) == 44): inc j
      let e = wsEnd(j)
      if j == p or e == j: return finish(T_ERROR)
      emit(T_STYLE_IDS, p, e)
      pop()
      push(S_STYLEDEF_STYLES)

    of S_STYLEDEF_STYLES:
      emit(T_STYLEDEF_STYLEOPTS, p, eol(p))
      pop()

    of S_NOTE:
      if word("left of", p) and not isWord(cc(p + 7)):
        emit(T_left_of, p, p + 7)
        pop()
        push(S_NOTE_ID)
      elif word("right of", p) and not isWord(cc(p + 8)):
        emit(T_right_of, p, p + 8)
        pop()
        push(S_NOTE_ID)
      elif c == 34:
        inc p
        pop()
        push(S_FLOATING_NOTE)
      else:
        return finish(T_ERROR)

    of S_NOTE_ID:
      let q = wsEnd(p)
      var j = q
      while j < n:
        let d = cc(j)
        if d == 58 or d == 45 or isSpace(d): break
        j = step(j)
      if j == q: return finish(T_ERROR)
      if emitId(p, j):
        pop()
        push(S_NOTE_TEXT)

    of S_NOTE_TEXT:
      block rules:
        let q = wsEnd(p)
        if cc(q) == 58:
          var j = q + 1
          while j < n:
            let d = cc(j)
            if d == 58 or d == 10 or d == 59: break
            j = step(j)
          if j > q + 1:
            # Mermaid drops two characters here, expecting " :"; with no space before the colon
            # the first character of the note goes too.
            let from2 = min(step(step(p)), j)
            emitText(T_NOTE_TEXT, src[from2 ..< j].jsTrim, p, j)
            pop()
            break rules
        var k = src.find('\n', p)
        var e = -1
        while k != -1:
          e = wsEnd(k)
          if word("end note", e) and not isWord(cc(e + 8)): break
          k = src.find('\n', e)
        if k == -1: return finish(T_ERROR)
        emitText(T_NOTE_TEXT, src[p ..< e].jsTrim, p, e + 8)
        pop()

    of S_FLOATING_NOTE:
      let q = wsEnd(p)
      if word("as", q):
        emit(T_AS, p, wsEnd(q + 2))
        pop()
        push(S_FLOATING_NOTE_ID)
      elif c == 34:
        inc p
      else:
        let close = src.find('"', p)
        emit(T_NOTE_TEXT, p, if close == -1: n else: close)

    of S_FLOATING_NOTE_ID:
      if emitId(p, eol(p)): pop()

    else: discard

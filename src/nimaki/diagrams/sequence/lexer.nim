## port-of: src/diagrams/sequence/lexer.ts
## port-status: draft
##
## Port notes: positions are byte offsets into the UTF-8 source (decision 0011). `cu(q)` reads
## the character at byte `q` as `charCodeAt` does where it matters: an ASCII byte is itself, any
## other character is its code point, and one outside the Basic Multilingual Plane reads as its
## high surrogate (neither a space nor ASCII). Past the end it is -1 (JavaScript's NaN). Where the
## TypeScript steps one code unit past a character that may not be ASCII (`q++` after a test that
## a non-ASCII character can pass), the port steps past the whole character (`step`). A loop that
## looks only for ASCII steps byte by byte: no byte of a longer character is ASCII.
import std/strutils
import ../../js
import ../../util/chars
import tokens

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

const
  S_INITIAL = 0
  S_ID = 1
  S_ALIAS = 2
  S_LINE = 3
  S_CONFIG = 4
  S_acc_title = 5
  S_acc_descr = 6
  S_acc_descr_multiline = 7

const
  C_ActorStart = 1
  C_ActorRest = 2
  C_Id = 4
  C_IdWide = 8
  C_Line = 16
  C_Menu = 32

const CLASS = block:
  ## Character classes of Mermaid's lexer rules, for ASCII. Other characters are tested by isSpace.
  var t: array[128, int]
  for c in 0 ..< 128:
    let ch = chr(c)
    let ws = c == 32 or (c >= 9 and c <= 13)
    var bits = 0
    if ch notin "/\\+()<->:\n,;": bits = bits or C_ActorStart
    if ch notin "+<->:\n,;": bits = bits or C_ActorRest
    if ch notin "<>:\n,;@": bits = bits or C_IdWide or (if ws: 0 else: C_Id)
    if ch notin "#\n;": bits = bits or C_Line
    if ch notin "/\\+()<>:\n,;-" and not ws: bits = bits or C_Menu
    t[c] = bits
  t

func cu(src: string, i: int): int =
  if i < 0 or i >= src.len: return -1
  let b = ord(src[i])
  if b < 0x80: return b
  let (cp, _) = codePointAt(src, i)
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func step(src: string, i: int): int =
  ## The byte after the character at i (one `++` of the TypeScript over it).
  if i >= src.len or ord(src[i]) < 0x80: i + 1 else: i + codePointAt(src, i)[1]

proc tokenize*(src: string): Tokens =
  let n = src.len
  var types: seq[int]
  var texts: seq[string]
  var starts: seq[int]
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0
  var nextNl = -1

  template emit(kind: int, s, e: int) =
    let s0 = s
    let e0 = e
    types.add kind
    texts.add src[s0 ..< e0]
    starts.add s0
    p = e0
  template emitText(kind: int, s, e: int, text: string) =
    let s0 = s
    let e0 = e
    types.add kind
    texts.add text
    starts.add s0
    p = e0
  template push(s: int) =
    stack.add state
    state = s
  template pop() =
    if stack.len > 0: state = stack.pop()
  proc eol(q: int): int =
    if nextNl < q:
      nextNl = src.find('\n', q)
      if nextNl == -1: nextNl = n
    nextNl
  proc has(q: int, bit: int): bool =
    let c = cu(src, q)
    if c < 0: return true # NaN: not below 128, and not a space
    if c < 128: return (CLASS[c] and bit) != 0
    if bit == C_Id or bit == C_Menu: not isSpace(c) else: true
  # Matches a lowercase literal without regard to the case of the source.
  proc ci(q: int, word: string): bool =
    for k in 0 ..< word.len:
      let w = ord(word[k])
      let c = if q + k < n: ord(src[q + k]) else: -1
      if (if w >= 97 and w <= 122: (c or 32) != w else: c != w): return false
    true
  proc word(lit: string): bool = ci(p, lit) and not isWord(cu(src, p + lit.len))
  proc skipWs(q0: int): int =
    var q = q0
    while q < n and isSpace(cu(src, q)): q = step(src, q)
    q
  proc skipSameLine(): bool =
    var q = p
    while q < n:
      let c = cu(src, q)
      if c == 10 or not isSpace(c): break
      q = step(src, q)
    if q == p: return false
    p = q
    true
  proc lineRun(q0: int): int =
    var q = q0
    while q < n and has(q, C_Line): q = step(src, q)
    q
  proc begin(kind: int, len: int, next: int) =
    emit(kind, p, p + len)
    push(next)
  proc keyword(lit: string, kind: int, next = -1): bool =
    if not word(lit): return false
    emit(kind, p, p + lit.len)
    if next >= 0: push(next)
    true
  # The actor menu keywords count only when spaces and the start of a name follow.
  proc menu(lit: string, kind: int): bool =
    if not ci(p, lit): return false
    var q = p + lit.len
    var c = cu(src, q)
    if c != 32 and c != 9: return false
    while c == 32 or c == 9:
      inc q
      c = cu(src, q)
    if q >= n or not has(q, C_Menu): return false
    emit(kind, p, p + lit.len)
    true

  proc arrowAhead(q: int): bool =
    let c = cu(src, q)
    let d = cu(src, q + 1)
    if c == 45:
      if d == 120 or d == 88 or d == 41 or d == 92 or d == 47 or d == 45: return true
      let e = cu(src, q + 2)
      return d == 124 and (e == 92 or e == 47)
    if c == 47 or c == 92: return (d == 124 or d == c) and cu(src, q + 2) == 45
    c == 40 and d == 41

  proc actor() =
    var q = step(src, p)
    while q < n and has(q, C_ActorStart): q = step(src, q)
    while q < n and not arrowAhead(q):
      var r = q
      while cu(src, r) == 45: inc r
      if r >= n or not has(r, C_ActorRest): break
      r = step(src, r)
      while r < n and has(r, C_ActorRest): r = step(src, r)
      q = r
    emitText(T_ACTOR, p, q, jsTrim(src[p ..< q]))

  proc number(): bool =
    var q = p
    while isDigit(cu(src, q)): inc q
    let whole = q > p
    if cu(src, q) == 46 and isDigit(cu(src, q + 1)):
      let r = if isDigit(cu(src, q + 2)): q + 3 else: q + 2
      let after = cu(src, r)
      if after == 32 or after == 10:
        emit(T_NUM, p, r)
        return true
    let after = cu(src, q)
    if whole and (after == 32 or after == 10):
      emit(T_NUM, p, q)
      return true
    false

  proc dash() =
    let d = cu(src, p + 1)
    let e = cu(src, p + 2)
    if d == 62: emit(if e == 62: T_SOLID_ARROW else: T_SOLID_OPEN_ARROW, p, p + (if e == 62: 3 else: 2))
    elif d == 120 or d == 88: emit(T_SOLID_CROSS, p, p + 2)
    elif d == 41: emit(T_SOLID_POINT, p, p + 2)
    elif d == 124 and e == 92: emit(T_SOLID_ARROW_TOP, p, p + 3)
    elif d == 124 and e == 47: emit(T_SOLID_ARROW_BOTTOM, p, p + 3)
    elif d == 92 and e == 92: emit(T_STICK_ARROW_TOP, p, p + 3)
    elif d == 47 and e == 47: emit(T_STICK_ARROW_BOTTOM, p, p + 3)
    elif d == 45:
      let f = cu(src, p + 3)
      if e == 62: emit(if f == 62: T_DOTTED_ARROW else: T_DOTTED_OPEN_ARROW, p, p + (if f == 62: 4 else: 3))
      elif e == 120 or e == 88: emit(T_DOTTED_CROSS, p, p + 3)
      elif e == 41: emit(T_DOTTED_POINT, p, p + 3)
      elif e == 124 and f == 92: emit(T_SOLID_ARROW_TOP_DOTTED, p, p + 4)
      elif e == 124 and f == 47: emit(T_SOLID_ARROW_BOTTOM_DOTTED, p, p + 4)
      elif e == 92 and f == 92: emit(T_STICK_ARROW_TOP_DOTTED, p, p + 4)
      elif e == 47 and f == 47: emit(T_STICK_ARROW_BOTTOM_DOTTED, p, p + 4)
      else: emit(T_MINUS, p, p + 1)
    else: emit(T_MINUS, p, p + 1)

  proc reverse(c: int): bool =
    let d = cu(src, p + 1)
    if (d != 124 and d != c) or cu(src, p + 2) != 45: return false
    let dotted = cu(src, p + 3) == 45
    let top = c == 47
    var kind: int
    if d == 124:
      if dotted: kind = (if top: T_SOLID_ARROW_TOP_REVERSE_DOTTED else: T_SOLID_ARROW_BOTTOM_REVERSE_DOTTED)
      else: kind = (if top: T_SOLID_ARROW_TOP_REVERSE else: T_SOLID_ARROW_BOTTOM_REVERSE)
    elif dotted: kind = (if top: T_STICK_ARROW_TOP_REVERSE_DOTTED else: T_STICK_ARROW_BOTTOM_REVERSE_DOTTED)
    else: kind = (if top: T_STICK_ARROW_TOP_REVERSE else: T_STICK_ARROW_BOTTOM_REVERSE)
    emit(kind, p, p + (if dotted: 4 else: 3))
    true

  proc title(): bool =
    if not ci(p, "title"): return false
    var q = p + 5
    let legacy = cu(src, q) == 58
    if legacy: inc q
    var e = q
    while e < n and cu(src, e) != 10 and isSpace(cu(src, e)): e = step(src, e)
    if e == n or cu(src, e) == 10:
      p = e
      return true
    let sep = cu(src, q)
    if not isSpace(sep) or sep == 13 or not has(step(src, q), C_Line): return false
    emit(if legacy: T_legacy_title else: T_title, p, lineRun(step(src, q)))
    true

  proc acc(): bool =
    let descr = ci(p, "accdescr")
    if not descr and not ci(p, "acctitle"): return false
    let q = skipWs(p + 8)
    let c = cu(src, q)
    if c == 58:
      emit(if descr: T_acc_descr else: T_acc_title, p, skipWs(q + 1))
      push(if descr: S_acc_descr else: S_acc_title)
      return true
    if descr and c == 123:
      p = skipWs(q + 1)
      push(S_acc_descr_multiline)
      return true
    false

  proc keywords(c: int): bool =
    case c or 32
    of 97:
      keyword("actor", T_participant_actor, S_ID) or
        keyword("alt", T_alt, S_LINE) or
        keyword("and", T_and, S_LINE) or
        keyword("activate", T_activate, S_ID) or
        acc() or
        keyword("autonumber", T_autonumber)
    of 98:
      keyword("box", T_box, S_LINE) or keyword("break", T_break, S_LINE)
    of 99:
      keyword("create", T_create) or keyword("critical", T_critical, S_LINE)
    of 100:
      keyword("destroy", T_destroy, S_ID) or menu("details", T_details) or keyword("deactivate", T_deactivate, S_ID)
    of 101:
      keyword("else", T_else, S_LINE) or keyword("end", T_end)
    of 108:
      keyword("loop", T_loop, S_LINE) or keyword("left of", T_left_of) or menu("links", T_links) or
        menu("link", T_link)
    of 110:
      keyword("note", T_note)
    of 111:
      keyword("opt", T_opt, S_LINE) or keyword("option", T_option, S_LINE) or keyword("over", T_over) or
        keyword("off", T_off)
    of 112:
      keyword("participant", T_participant, S_ID) or
        keyword("par", T_par, S_LINE) or
        keyword("par_over", T_par_over, S_LINE) or
        menu("properties", T_properties)
    of 114:
      keyword("rect", T_rect, S_LINE) or keyword("right of", T_right_of)
    of 115:
      keyword("sequencediagram", T_SD)
    of 116:
      title()
    else:
      false

  proc initial() =
    let c = cu(src, p)
    if c == 10:
      var q = p + 1
      while cu(src, q) == 10: inc q
      emit(T_NEWLINE, p, q)
      return
    if isSpace(c):
      p = skipWs(step(src, p))
      return
    if c == 35 or (c == 37 and cu(src, p + 1) != 123):
      p = eol(p)
      return
    if (isDigit(c) or c == 46) and number(): return
    if c < 128 and (c or 32) >= 97 and (c or 32) <= 122 and keywords(c): return
    if c == 44: emit(T_COMMA, p, p + 1)
    elif c == 59: emit(T_NEWLINE, p, p + 1)
    elif has(p, C_ActorStart): actor()
    elif c == 45: dash()
    elif c == 60 and src.continuesWith("<<->>", p): emit(T_BIDIRECTIONAL_SOLID_ARROW, p, p + 5)
    elif c == 60 and src.continuesWith("<<-->>", p): emit(T_BIDIRECTIONAL_DOTTED_ARROW, p, p + 6)
    elif (c == 47 or c == 92) and reverse(c): return
    elif c == 58: emit(T_TXT, p, lineRun(p + 1))
    elif c == 43: emit(T_PLUS, p, p + 1)
    elif c == 40 and cu(src, p + 1) == 41: emit(T_CENTRAL, p, p + 2)
    else: emit(T_INVALID, p, p + 1)

  # A participant name, up to an alias, a config object, or the end of the statement.
  proc id(): bool =
    if skipSameLine(): return true
    let c = cu(src, p)
    if c == 35:
      p = eol(p)
      return true
    if c == 64 and cu(src, p + 1) == 123:
      begin(T_CONFIG_START, 2, S_CONFIG)
      return true
    var a = p
    while a < n and has(a, C_Id): a = step(src, a)
    if a > p:
      let w = skipWs(a)
      if cu(src, w) == 64 and cu(src, w + 1) == 123:
        emit(T_ACTOR, p, a)
        return true
      if w > a and ci(w, "as") and isSpace(cu(src, w + 2)):
        emit(T_ACTOR, p, a)
        push(S_ALIAS)
        return true
    var b = a
    while b < n and has(b, C_IdWide): b = step(src, b)
    if b > p:
      let stop = cu(src, b)
      # Before any other delimiter the name must be followed by a comment, so it ends at the last one.
      var cut = b
      if b < n and stop != 10 and stop != 59:
        dec cut
        while cut > p and src[cut] != '#': dec cut
      if cut > p:
        emitText(T_ACTOR, p, cut, jsTrim(src[p ..< cut]))
        pop()
        return true
    if cu(src, b) == 60:
      emit(T_INVALID, p, eol(p))
      pop()
      return true
    if c != 10:
      let e = eol(p)
      emitText(T_INVALID, p, e, jsTrim(src[p ..< e]))
      pop()
      return true
    false

  proc stepState(): bool =
    case state
    of S_INITIAL:
      initial()
      return true
    of S_ID:
      return id()
    of S_ALIAS:
      if skipSameLine(): return true
      if cu(src, p) == 35:
        p = eol(p)
        return true
      pop()
      pop()
      if word("as"): begin(T_AS, 2, S_LINE)
      else: emit(T_NEWLINE, p, p)
      return true
    of S_LINE:
      if skipSameLine(): return true
      if cu(src, p) == 35:
        p = eol(p)
        return true
      emit(T_restOfLine, p, lineRun(p))
      pop()
      return true
    of S_CONFIG:
      if cu(src, p) != 125:
        var q = src.find('}', p)
        if q == -1: q = n
        emit(T_CONFIG_CONTENT, p, q)
        return true
      else:
        let w = skipWs(p + 1)
        let alias = w > p + 1 and ci(w, "as") and isSpace(cu(src, w + 2))
        emit(T_CONFIG_END, p, p + 1)
        pop()
        if alias: push(S_ALIAS)
        else: pop()
        return true
    of S_acc_title, S_acc_descr:
      emit(if state == S_acc_title: T_acc_title_value else: T_acc_descr_value, p, eol(p))
      pop()
      return true
    else:
      if cu(src, p) == 125:
        inc p
        pop()
      else:
        var q = src.find('}', p)
        if q == -1: q = n
        emit(T_acc_descr_multiline_value, p, q)
      return true

  while p < n:
    if not stepState():
      types.add T_ERROR
      texts.add ""
      starts.add p
      return Tokens(types: types, texts: texts, starts: starts)

  # Mermaid's lexer tries its rules once more on the empty remainder before reporting the end.
  if state == S_INITIAL or state == S_ALIAS: emit(T_NEWLINE, n, n)
  elif state == S_LINE: emit(T_restOfLine, n, n)
  elif state == S_acc_title: emit(T_acc_title_value, n, n)
  elif state == S_acc_descr: emit(T_acc_descr_value, n, n)
  elif state == S_acc_descr_multiline: emit(T_acc_descr_multiline_value, n, n)
  types.add T_STOP
  texts.add ""
  starts.add n
  Tokens(types: types, texts: texts, starts: starts)
